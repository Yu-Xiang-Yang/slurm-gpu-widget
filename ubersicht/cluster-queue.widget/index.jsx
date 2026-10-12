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
  width: 340px;
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

// 界面文字：语言由脚本输出的 lang 字段决定（配置项 UI_LANG）
const STR = {
  zh: {
    free: "空闲", run: "运行", pend: "排队", me: "我", maxfree: "单节点最多空闲", cards: "卡", mig: "个 MIG 实例",
    nodes: "节点", idle: "空闲", down: "不可用", nodata: "脚本没有返回数据", drag: "拖动移动位置，双击恢复默认",
    model: "型号", mem: "内存", myjobs: "我的作业", vram: "显存", title: "GPU 队列", clickConnect: "点击连接 VPN", connected: "已连接", updated: "更新于",
  },
  en: {
    free: "free", run: "running", pend: "pending", me: "mine", maxfree: "Max free on one node:", cards: "GPUs", mig: "MIG instances",
    nodes: "nodes", idle: "idle", down: "down", nodata: "The script returned no data", drag: "Drag to move, double-click to reset",
    model: "Model", mem: "RAM", myjobs: "My jobs", vram: "VRAM", title: "GPU Queues", clickConnect: "Click to connect VPN", connected: "connected", updated: "Updated",
  },
};
let T = STR[(typeof navigator !== "undefined" && /^zh/.test(navigator.language)) ? "zh" : "en"];

const pct = (u, t) => (t > 0 ? Math.round((u * 100) / t) : 0);
const color = (p) => (p >= 90 ? "#ff453a" : p >= 60 ? "#ffd60a" : "#30d158");

const gb = (mb) => Math.round(mb / 1024);

const Bar = ({ label, used, total, unit }) => {
  const p = pct(used, total);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 6, margin: "3px 0" }}>
      <span style={{ width: 28, opacity: 0.7 }}>{label}</span>
      <div style={{ flex: 1, height: 6, borderRadius: 3, background: "rgba(255,255,255,0.15)" }}>
        <div style={{ width: `${p}%`, height: "100%", borderRadius: 3, background: color(p) }} />
      </div>
      <span style={{ width: 92, textAlign: "right", fontVariantNumeric: "tabular-nums" }}>
        {unit === "G" ? `${gb(used)}/${gb(total)}G` : `${T.free} ${total - used}/${total}`}
      </span>
    </div>
  );
};

// 节点明细（配置 SHOW_NODES=1 时脚本才会输出 node_list）
const stateColor = (st) =>
  /down|drain|fail|maint|not_responding/.test(st) ? "#ff453a" : st === "idle" ? "#30d158" : "#ffd60a";

// 单张卡（配置 GPU_DETAIL=1 且节点允许 ssh 执行 nvidia-smi 时才有）
const GpuRow = ({ g }) => (
  <div style={{ display: "flex", gap: 6, fontSize: 10, opacity: 0.7, paddingLeft: 14, fontVariantNumeric: "tabular-nums" }}>
    <span style={{ width: 30 }}>GPU{g.index}</span>
    <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{g.name}</span>
    <span>{(g.mem_used / 1024).toFixed(1)}/{Math.round(g.mem_total / 1024)}G</span>
    <span style={{ width: 32, textAlign: "right", color: color(g.util) }}>{g.util}%</span>
  </div>
);

const NodeRow = ({ n }) => (
  <div>
    <div style={{ display: "flex", gap: 6, fontSize: 11, fontVariantNumeric: "tabular-nums", opacity: 0.85 }}>
      <span style={{ color: stateColor(n.state) }}>●</span>
      <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{n.name}</span>
      {n.gpu_total > 0 && <span>GPU {n.gpu_used}/{n.gpu_total}</span>}
      <span style={{ width: 64, textAlign: "right", opacity: 0.7, whiteSpace: "nowrap" }}>CPU {n.cpu_used}/{n.cpu_total}</span>
      {n.mem_total > 0 && (
        <span style={{ width: 88, textAlign: "right", opacity: 0.7, whiteSpace: "nowrap" }}>{T.mem} {gb(n.mem_used)}/{gb(n.mem_total)}G</span>
      )}
    </div>
    {(n.gpus || []).map((g) => <GpuRow key={g.index} g={g} />)}
  </div>
);

// 自己正在运行的作业（配置 SHOW_MY_JOBS=1）
const Job = ({ j }) => (
  <div style={{ marginTop: 6 }}>
    <div style={{ display: "flex", gap: 6, fontSize: 11, fontVariantNumeric: "tabular-nums" }}>
      <span style={{ fontWeight: 600 }}>{j.id}</span>
      <span style={{ flex: 1, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", opacity: 0.85 }}>{j.name}</span>
      <span style={{ opacity: 0.85 }}>{j.elapsed}<span style={{ opacity: 0.5 }}> / {j.limit}</span></span>
    </div>
    <div style={{ fontSize: 10, opacity: 0.5 }}>{j.partition} · {j.nodes}</div>
    {j.gpus.map((g) => (
      <div key={g.index} style={{ display: "flex", alignItems: "center", gap: 6, fontSize: 10, fontVariantNumeric: "tabular-nums" }}>
        <span style={{ width: 34, opacity: 0.7 }}>GPU{g.index}</span>
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: "rgba(255,255,255,0.15)" }}>
          <div style={{ width: `${pct(g.mem_used, g.mem_total)}%`, height: "100%", borderRadius: 2, background: color(pct(g.mem_used, g.mem_total)) }} />
        </div>
        <span style={{ width: 96, textAlign: "right" }}>{T.vram} {(g.mem_used / 1024).toFixed(1)}/{Math.round(g.mem_total / 1024)}G</span>
        <span style={{ width: 32, textAlign: "right", color: color(g.util) }}>{g.util}%</span>
      </div>
    ))}
  </div>
);

const Partition = ({ p, gpuOnly }) => (
  <div style={{ marginTop: 10 }}>
    <div style={{ display: "flex", justifyContent: "space-between", fontWeight: 600 }}>
      <span>{p.name}{p.mig ? " (MIG)" : ""}</span>
      <span style={{ fontWeight: 400, opacity: 0.8 }}>
        {T.run} {p.running} · {T.pend} {p.pending}
        {p.mine > 0 ? ` · ${T.me} ${p.mine}` : ""}
      </span>
    </div>
    {p.model && <div style={{ fontSize: 11, opacity: 0.7, marginTop: 1 }}>{T.model}: {p.model}</div>}
    {p.gpu_total > 0 && <Bar label="GPU" used={p.gpu_used} total={p.gpu_total} />}
    {!gpuOnly && <Bar label="CPU" used={p.cpu_used} total={p.cpu_total} />}
    {p.mem_total > 0 && <Bar label={T.mem} used={p.mem_used} total={p.mem_total} unit="G" />}
    <div style={{ opacity: 0.5, fontSize: 11 }}>
      {p.gpu_total > 0 ? `${T.maxfree} ${p.gpu_max_free_node} ${p.mig ? T.mig : T.cards} · ` : ""}
      {T.nodes} {p.nodes} · {T.idle} {p.idle_nodes}
      {p.down_nodes > 0 ? ` · ${T.down} ${p.down_nodes}` : ""}
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

  if (d && STR[d.lang]) T = STR[d.lang];
  if (!d) {
    return <div data-drag-root onMouseDown={startDrag} onDoubleClick={resetPos} style={{ cursor: "move" }}>⚠︎ {T.nodata}<br /><small>{String(error || output || "").slice(0, 200)}</small></div>;
  }

  const ok = d.vpn === "CONNECTED";
  return (
    <div data-drag-root>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <span
          onMouseDown={startDrag}
          onDoubleClick={resetPos}
          title={T.drag}
          style={{ fontSize: 14, fontWeight: 700, cursor: "move", flex: 1, userSelect: "none" }}
        >
          {d.cluster || T.title}
          {d.gpu_total > 0 && (
            <span style={{ marginLeft: 8, fontWeight: 400, opacity: 0.8 }}>{T.free} {d.gpu_total - d.gpu_used}/{d.gpu_total}</span>
          )}
        </span>
        <span
          onClick={() => !ok && run(`${SCRIPT} --connect`)}
          style={{ cursor: ok ? "default" : "pointer", color: ok ? "#30d158" : "#ff453a" }}
          title={ok ? "" : T.clickConnect}
        >
          ● VPN {ok ? T.connected : d.vpn}
        </span>
      </div>
      {d.error && <div style={{ marginTop: 8, color: "#ff9f0a" }}>{d.error}</div>}
      {d.partitions.map((p) => <Partition key={p.name} p={p} gpuOnly={d.gpu_only} />)}
      {d.my_jobs && d.my_jobs.length > 0 && (
        <div style={{ marginTop: 12, paddingTop: 8, borderTop: "1px solid rgba(255,255,255,0.12)" }}>
          <div style={{ fontWeight: 600 }}>{T.myjobs} ({d.my_jobs.length})</div>
          {d.my_jobs.map((j) => <Job key={j.id} j={j} />)}
        </div>
      )}
      <div style={{ marginTop: 10, opacity: 0.4, fontSize: 10, textAlign: "right" }}>{T.updated} {d.time}</div>
    </div>
  );
};
