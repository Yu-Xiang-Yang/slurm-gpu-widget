// Übersicht 桌面组件：显示 Tunnelblick VPN 状态和 Slurm 各分区 CPU/GPU 占用
import { run } from "uebersicht";

const SCRIPT = "$HOME/.config/cluster-widget/cluster-status.sh";

export const command = SCRIPT;
export const refreshFrequency = 60 * 1000; // 每分钟刷新

// 位置：按住标题栏拖动即可移动，位置保存在 localStorage；双击标题栏恢复默认（右上角）
const POS_KEY = "cluster-queue-pos";
const loadPos = () => {
  try {
    return JSON.parse(localStorage.getItem(POS_KEY));
  } catch (e) {
    return null;
  }
};
const saved = loadPos();
const posCss = saved ? `left: ${saved.x}px; top: ${saved.y}px;` : "top: 40px; right: 24px;";

export const className = `
  ${posCss}
  width: 300px;
  padding: 14px 16px;
  border-radius: 14px;
  background: rgba(28, 28, 30, 0.72);
  -webkit-backdrop-filter: blur(20px);
  color: #f2f2f7;
  font: 12px -apple-system, "PingFang SC", sans-serif;
`;

// 拖动：直接改组件外层容器的 left/top，松开鼠标时保存
const startDrag = (e) => {
  if (e.button !== 0) return;
  const box = e.currentTarget.closest("[data-drag-root]").parentElement;
  const r = box.getBoundingClientRect();
  const dx = e.clientX - r.left, dy = e.clientY - r.top;
  const move = (ev) => {
    box.style.right = "auto";
    box.style.bottom = "auto";
    box.style.left = `${Math.max(0, ev.clientX - dx)}px`;
    box.style.top = `${Math.max(0, ev.clientY - dy)}px`;
  };
  const up = () => {
    document.removeEventListener("mousemove", move);
    document.removeEventListener("mouseup", up);
    const b = box.getBoundingClientRect();
    try {
      localStorage.setItem(POS_KEY, JSON.stringify({ x: Math.round(b.left), y: Math.round(b.top) }));
    } catch (err) {}
  };
  document.addEventListener("mousemove", move);
  document.addEventListener("mouseup", up);
  e.preventDefault();
};

const resetPos = (e) => {
  const box = e.currentTarget.closest("[data-drag-root]").parentElement;
  try {
    localStorage.removeItem(POS_KEY);
  } catch (err) {}
  box.style.left = "auto";
  box.style.bottom = "auto";
  box.style.top = "40px";
  box.style.right = "24px";
};

const pct = (u, t) => (t > 0 ? Math.round((u * 100) / t) : 0);
const color = (p) => (p >= 90 ? "#ff453a" : p >= 60 ? "#ffd60a" : "#30d158");

const Bar = ({ label, used, total }) => {
  const p = pct(used, total);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6, margin: "3px 0" }}>
      <span style={{ width: 28, opacity: 0.7 }}>{label}</span>
      <div style={{ flex: 1, height: 6, borderRadius: 3, background: "rgba(255,255,255,0.15)" }}>
        <div style={{ width: `${p}%`, height: "100%", borderRadius: 3, background: color(p) }} />
      </div>
      <span style={{ width: 92, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>
        空闲 {total - used}/{total}
      </span>
    </div>
  );
};

// 节点明细（配置 SHOW_NODES=1 时脚本才会输出 node_list）
const stateColor = (st) =>
  /down|drain|fail|maint|not_responding/.test(st) ? "#ff453a" : st === "idle" ? "#30d158" : "#ffd60a";

const NodeRow = ({ n }) => (
  <div style={{ display: "flex", gap: 6, fontSize: 11, fontVariantNumeric: "tabular-nums", opacity: 0.85 }}>
    <span style={{ color: stateColor(n.state) }}>●</span>
    <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{n.name}</span>
    {n.gpu_total > 0 && <span>GPU {n.gpu_used}/{n.gpu_total}</span>}
    <span style={{ width: 78, textAlign: "right", opacity: 0.7 }}>CPU {n.cpu_used}/{n.cpu_total}</span>
  </div>
);

const Partition = ({ p, gpuOnly }) => (
  <div style={{ marginTop: 10 }}>
    <div style={{ display: "flex", justifyContent: "space-between", fontWeight: 600 }}>
      <span>{p.name}{p.mig ? " (MIG)" : ""}</span>
      <span style={{ fontWeight: 400, opacity: 0.8 }}>
        运行 {p.running} · 排队 {p.pending}
        {p.mine > 0 ? ` · 我 ${p.mine}` : ""}
      </span>
    </div>
    {p.gpu_total > 0 && <Bar label="GPU" used={p.gpu_used} total={p.gpu_total} />}
    {!gpuOnly && <Bar label="CPU" used={p.cpu_used} total={p.cpu_total} />}
    <div style={{ opacity: 0.5, fontSize: 11 }}>
      {p.gpu_total > 0 ? `单节点最多空闲 ${p.gpu_max_free_node} ${p.mig ? "个 MIG 实例" : "卡"} · ` : ""}
      节点 {p.nodes} · 空闲 {p.idle_nodes}
      {p.down_nodes > 0 ? ` · 不可用 ${p.down_nodes}` : ""}
    </div>
    {p.node_list && (
      <div style={{ marginTop: 4, paddingLeft: 4 }}>
        {p.node_list.map((n) => <NodeRow key={n.name} n={n} />)}
      </div>
    )}
  </div>
);

export const render = ({ output, error }) => {
  let d = null;
  try {
    d = JSON.parse(output);
  } catch (e) {}

  if (!d) {
    return <div data-drag-root onMouseDown={startDrag} onDoubleClick={resetPos} style={{ cursor: "move" }}>⚠︎ 脚本没有返回数据<br /><small>{String(error || output || "").slice(0, 200)}</small></div>;
  }

  const ok = d.vpn === "CONNECTED";
  return (
    <div data-drag-root>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <span
          onMouseDown={startDrag}
          onDoubleClick={resetPos}
          title="拖动移动位置，双击恢复默认"
          style={{ fontSize: 14, fontWeight: 700, cursor: "move", flex: 1, userSelect: "none" }}
        >
          {d.cluster || "GPU 队列"}
          {d.gpu_total > 0 && (
            <span style={{ marginLeft: 8, fontWeight: 400, opacity: 0.8 }}>空闲 {d.gpu_total - d.gpu_used}/{d.gpu_total}</span>
          )}
        </span>
        <span
          onClick={() => !ok && run(`${SCRIPT} --connect`)}
          style={{ cursor: ok ? "default" : "pointer", color: ok ? "#30d158" : "#ff453a" }}
          title={ok ? "" : "点击连接 VPN"}
        >
          ● VPN {ok ? "已连接" : d.vpn}
        </span>
      </div>
      {d.error && <div style={{ marginTop: 8, color: "#ff9f0a" }}>{d.error}</div>}
      {d.partitions.map((p) => <Partition key={p.name} p={p} gpuOnly={d.gpu_only} />)}
      <div style={{ marginTop: 10, opacity: 0.4, fontSize: 10, textAlign: "right" }}>更新于 {d.time}</div>
    </div>
  );
};
