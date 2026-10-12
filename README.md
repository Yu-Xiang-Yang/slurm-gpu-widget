# Cluster Queue Widget for macOS

**English** | [简体中文](README.zh-CN.md)

A macOS desktop widget and menu-bar plugin that reports the per-partition (queue) occupancy of a Slurm cluster. The collector verifies the Tunnelblick VPN connection, re-establishes it when required, queries the cluster over SSH, and renders GPU/CPU utilisation, job counts and, optionally, per-node status.

<p align="center"><img src="preview.png" width="380" alt="Desktop widget preview (mock data)"></p>

## Features

- **VPN detection**: the state of a named Tunnelblick configuration is read via AppleScript; when it is not `CONNECTED`, a connection is initiated and polled for up to `CONNECT_TIMEOUT` seconds.
- **Single SSH round trip**: `scontrol show node -o` and `squeue` are executed in one non-interactive session (`BatchMode=yes`), with a typical refresh time of approximately 1 s.
- **Per-partition aggregation**: allocated/total GPUs (from `Gres` and `AllocTRES`), allocated/total CPUs, idle and unavailable nodes, running and pending jobs, and the jobs of the current user.
- **MIG awareness**: partitions backed by MIG-partitioned GPUs (e.g. `gpu:2g.20gb:12`) are labelled, and their capacity is reported in MIG instances rather than physical cards.
- **Configurable cluster name** (`CLUSTER_NAME`), displayed in the widget title and the menu bar.
- **Optional node list** (`SHOW_NODES=1`): node names with state and per-node GPU/CPU usage under each partition (a submenu in SwiftBar).
- **Bilingual interface** (`UI_LANG`): Chinese or English labels in both front ends, selected explicitly or from the macOS language.
- **Draggable desktop card**: the Übersicht card can be repositioned by dragging its title; the position persists across refreshes, and a double-click restores the default location.
- Nodes in `DOWN`, `DRAIN`, `FAIL`, `MAINT` or `NOT_RESPONDING` states are excluded from available capacity; nodes belonging to several partitions are counted once in the global GPU total.

## Front ends

| Front end | Location | Installation |
|---|---|---|
| **Übersicht** | Translucent card on the desktop, one block per partition | `brew install --cask ubersicht` |
| **SwiftBar** | Menu-bar item (e.g. `GPU free 14/32`) with a per-partition dropdown | `brew install --cask swiftbar` |

Both front ends invoke the same collector, `cluster-status.sh`; either or both may be installed.

## Installation

1. Install at least one front end (see the table above) and **launch it once**, so that its plugin directory is created.
2. Run the installer and edit the generated configuration:

   ```bash
   git clone https://github.com/Yu-Xiang-Yang/slurm-gpu-widget.git
   cd slurm-gpu-widget
   bash install.sh
   open -e ~/.config/cluster-widget/config
   ```

3. Verify the collector; a JSON document indicates a working setup:

   ```bash
   ~/.config/cluster-widget/cluster-status.sh
   ~/.config/cluster-widget/cluster-status.sh --swiftbar
   ```

Re-running `install.sh` updates the scripts and widgets but never overwrites an existing configuration file.

### Prerequisites

1. **Password-less SSH.** The widget runs in the background and cannot answer prompts. Key-based authentication is required; for keys protected by a passphrase, `UseKeychain yes` and `AddKeysToAgent yes` should be added to `~/.ssh/config`. A bastion host can be declared with `ProxyJump`.
2. **Non-interactive VPN.** The Tunnelblick credentials must be stored in the macOS Keychain. VPNs requiring one-time passcodes cannot be connected automatically; in that case `AUTO_CONNECT=0` is recommended.
3. **Automation permission.** On the first run macOS asks whether Übersicht/SwiftBar may control Tunnelblick; the permission must be granted for automatic reconnection.

## Configuration

File: `~/.config/cluster-widget/config` (template: [`config.example`](config.example)). Environment variables given on the command line take precedence over the file.

| Key | Default | Description |
|---|---|---|
| `CLUSTER_NAME` | *(empty)* | Cluster name shown in the widget title and menu bar; empty yields the default title. |
| `TB_CONFIG` | *(empty)* | Tunnelblick configuration name; empty disables VPN detection and connects via SSH directly. |
| `SSH_HOST` | *(empty)* | SSH target, preferably a `Host` alias from `~/.ssh/config`. |
| `AUTO_CONNECT` | `1` | Initiate a Tunnelblick connection when the VPN is down. |
| `CONNECT_TIMEOUT` | `30` | Maximum waiting time (s) for the VPN connection. |
| `SSH_TIMEOUT` | `8` | SSH connection timeout (s). |
| `PARTITIONS` | *(empty)* | Comma-separated whitelist of partitions; empty displays all. |
| `GPU_ONLY` | `1` | `1` displays GPU partitions only; `0` adds CPU partitions and CPU bars. |
| `SHOW_NODES` | `0` | `1` lists node names with state and per-node usage under each partition. |
| `UI_LANG` | `auto` | Interface language: `zh`, `en`, or `auto` (Chinese when the primary macOS language is Chinese, otherwise English). |

Example: a temporary view of all partitions with node details, independent of the configuration file:

```bash
GPU_ONLY=0 SHOW_NODES=1 PARTITIONS=gpu,compute ~/.config/cluster-widget/cluster-status.sh --swiftbar
```

For large partitions (≈ 100 nodes) `SHOW_NODES=1` should be combined with `PARTITIONS` to bound the height of the card.

## Output format

`cluster-status.sh` (default mode) emits one JSON object:

```json
{
  "lang": "en", "cluster": "Demo", "show_nodes": true, "time": "13:58:32",
  "vpn": "CONNECTED", "error": "", "gpu_only": true,
  "gpu_used": 10, "gpu_total": 20,
  "partitions": [{
    "name": "gpu", "nodes": 3, "idle_nodes": 1, "down_nodes": 1,
    "cpu_used": 48, "cpu_total": 128, "gpu_used": 6, "gpu_total": 16,
    "gpu_max_free_node": 8, "running": 2, "pending": 1, "mine": 0, "mig": false,
    "node_list": [{"name": "gpu01", "state": "mixed", "cpu_used": 48, "cpu_total": 64, "gpu_used": 6, "gpu_total": 8}]
  }]
}
```

`node_list` is present only when `SHOW_NODES=1`. `gpu_max_free_node` denotes the largest number of free GPUs (or MIG instances) on a single node, which bounds the largest single-node job that can start immediately.

`--swiftbar` emits the SwiftBar plugin format, and `--connect` only triggers the Tunnelblick connection.

## Testing without a cluster

The repository contains synthetic `scontrol`/`squeue` output in [`mock/`](mock):

```bash
MOCK_DIR=mock bash cluster-status.sh
MOCK_DIR=mock SHOW_NODES=1 CLUSTER_NAME=Demo bash cluster-status.sh --swiftbar
```

## Method

1. VPN state: `osascript -e 'tell application "Tunnelblick" to get state of first configuration where name = "…"'`.
2. Data acquisition: `ssh -o BatchMode=yes $SSH_HOST "scontrol show node -o; squeue -h -o '%P|%T|%u'"`.
3. Aggregation (local `awk`): `CPUAlloc/CPUTot` for CPUs; the GPU total is derived from `Gres` (e.g. `gpu:a100:8(S:0-1)`, `gpu:4`, `gpu:2g.20gb:12,gpu:1g.20gb:4`), and the allocated count from `gres/gpu=N` in `AllocTRES` (absent when zero). The `Partitions` field is split on commas, so a node contributes to each partition it belongs to.

## Troubleshooting

| Symptom | Cause and remedy |
|---|---|
| `install.sh` reports neither front end | The application has never been launched; launch it once and re-run `install.sh`. |
| Übersicht shows nothing on the desktop | The Übersicht rendering server (port 41416) did not start; quitting and reopening Übersicht restores it. `curl http://127.0.0.1:41416/` verifies the server. |
| `ssh failed` / `ssh 失败` | Key-based login is not configured, or the host alias is wrong; `ssh -o BatchMode=yes $SSH_HOST true` reproduces the error. |
| VPN remains disconnected | Credentials are not in the Keychain, or the automation permission was denied (System Settings → Privacy & Security → Automation). |

## Other schedulers

Only the remote command and the `awk` parser in `cluster-status.sh` are scheduler-specific (PBS: `pbsnodes -a` / `qstat`; LSF: `bhosts` / `bqueues`). The JSON schema and both front ends remain unchanged.

## License

[MIT](LICENSE)
