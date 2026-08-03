// omp-web SPA. All URLs are relative to document.baseURI so the app works
// whether served at "/" (direct) or under a subpath (behind the tailnet proxy).

const $ = (sel) => document.querySelector(sel);
const api = (p) => new URL(p, document.baseURI);
const wsUrl = (p) => {
  const u = api(p);
  u.protocol = u.protocol === "https:" ? "wss:" : "ws:";
  return u;
};

const els = {
  app: $("#app"),
  sessions: $("#sessions"),
  filter: $("#filter"),
  refresh: $("#refresh"),
  transcript: $("#transcript"),
  title: $("#title"),
  cwd: $("#cwd"),
  input: $("#input"),
  send: $("#send"),
  stop: $("#stop"),
  composer: $("#composer"),
  back: $("#back"),
};

let all = [];
let currentId = null;
let ws = null;
let streaming = false;
let liveBubble = null; // in-progress assistant bubble element

// ------------------------------------------------------------- rendering

const fmtTime = (ms) => {
  const d = new Date(ms);
  const diff = (Date.now() - ms) / 1000;
  if (diff < 3600) return Math.max(1, Math.round(diff / 60)) + "m";
  if (diff < 86400) return Math.round(diff / 3600) + "h";
  return d.toLocaleDateString();
};

function renderSessions() {
  const q = els.filter.value.trim().toLowerCase();
  const list = q
    ? all.filter(
        (s) =>
          s.title.toLowerCase().includes(q) ||
          (s.cwd || "").toLowerCase().includes(q) ||
          (s.preview || "").toLowerCase().includes(q),
      )
    : all;
  els.sessions.innerHTML = "";
  for (const s of list) {
    const li = document.createElement("li");
    li.dataset.id = s.id;
    if (s.id === currentId) li.classList.add("active");
    const cwd = (s.cwd || "").replace(/^\/home\/[^/]+/, "~");
    li.innerHTML = `<div class="s-title"></div><div class="s-meta"><span>${fmtTime(
      s.mtime,
    )}</span><span class="s-cwd"></span></div>`;
    li.querySelector(".s-title").textContent = s.title;
    li.querySelector(".s-cwd").textContent = cwd;
    li.addEventListener("click", () => openSession(s.id));
    els.sessions.appendChild(li);
  }
}

async function loadSessions() {
  const r = await fetch(api("api/sessions"));
  all = await r.json();
  renderSessions();
}

function bubble(role, node) {
  const wrap = document.createElement("div");
  wrap.className = "msg " + role;
  const who = document.createElement("div");
  who.className = "who";
  who.textContent = role === "user" ? "você" : "omp";
  const b = document.createElement("div");
  b.className = "bubble";
  if (node != null) b.append(node);
  wrap.append(who, b);
  els.transcript.appendChild(wrap);
  scroll();
  return b;
}

function renderBlocks(container, blocks) {
  for (const blk of blocks) {
    if (blk.t === "text") {
      const p = document.createElement("div");
      p.textContent = blk.text;
      container.appendChild(p);
    } else if (blk.t === "think") {
      const d = document.createElement("div");
      d.className = "think";
      d.textContent = blk.text;
      container.appendChild(d);
    } else if (blk.t === "tool") {
      const d = document.createElement("div");
      d.className = "tool";
      d.innerHTML = "🔧 <b></b>";
      d.querySelector("b").textContent = blk.name;
      if (blk.input && Object.keys(blk.input).length) {
        const s = JSON.stringify(blk.input);
        d.append(" " + (s.length > 120 ? s.slice(0, 120) + "…" : s));
      }
      container.appendChild(d);
    } else if (blk.t === "toolResult") {
      const d = document.createElement("div");
      d.className = "toolResult" + (blk.isError ? " err" : "");
      d.textContent = blk.output ? blk.output.slice(0, 4000) : "(sem saída)";
      container.appendChild(d);
    } else if (blk.t === "image") {
      const d = document.createElement("div");
      d.className = "imgph";
      d.textContent = "🖼️ imagem";
      container.appendChild(d);
    }
  }
}

async function openSession(id) {
  if (ws) {
    ws.close();
    ws = null;
  }
  currentId = id;
  streaming = false;
  liveBubble = null;
  els.app.classList.add("viewing");
  renderSessions();
  els.transcript.innerHTML = '<div class="status">carregando…</div>';
  const r = await fetch(api("api/session?id=" + encodeURIComponent(id)));
  if (!r.ok) {
    els.transcript.innerHTML = '<div class="status">erro ao carregar</div>';
    return;
  }
  const data = await r.json();
  els.title.textContent = data.title || "chat";
  els.cwd.textContent = (data.cwd || "").replace(/^\/home\/[^/]+/, "~");
  els.transcript.innerHTML = "";
  for (const m of data.messages) {
    const b = bubble(m.role, null);
    renderBlocks(b, m.blocks);
  }
  els.input.disabled = false;
  els.send.disabled = false;
  els.input.focus();
  scroll();
  connect(id);
}

function scroll() {
  els.transcript.scrollTop = els.transcript.scrollHeight;
}

// ---------------------------------------------------------- live streaming

function connect(id) {
  ws = new WebSocket(wsUrl("api/stream?id=" + encodeURIComponent(id)));
  ws.addEventListener("message", (ev) => onFrame(ev.data));
  ws.addEventListener("close", () => {
    setStreaming(false);
  });
}

function ensureLive() {
  if (!liveBubble) liveBubble = bubble("assistant", null);
  return liveBubble;
}

function onFrame(raw) {
  let f;
  try {
    f = JSON.parse(raw);
  } catch {
    return;
  }
  switch (f.type) {
    case "agent_start":
      liveBubble = null;
      ensureLive();
      break;
    case "message_update": {
      const ev = f.assistantMessageEvent;
      if (ev && ev.type === "text_delta" && ev.delta) {
        const b = ensureLive();
        let last = b.lastChild;
        if (!last || last.dataset?.stream !== "1") {
          last = document.createElement("div");
          last.dataset.stream = "1";
          b.appendChild(last);
        }
        last.textContent += ev.delta;
        scroll();
      }
      break;
    }
    case "tool_execution_start": {
      const b = ensureLive();
      const d = document.createElement("div");
      d.className = "tool";
      d.innerHTML = "🔧 <b></b>";
      d.querySelector("b").textContent = f.toolName || f.name || "tool";
      b.appendChild(d);
      // next text goes in a fresh stream node
      const fresh = document.createElement("div");
      fresh.dataset.stream = "1";
      b.appendChild(fresh);
      scroll();
      break;
    }
    case "agent_end":
      setStreaming(false);
      liveBubble = null;
      break;
    case "omp_exit":
      setStreaming(false);
      status(`sessão encerrada (código ${f.code})`);
      break;
    case "omp_stderr":
      console.warn("omp stderr:", f.text);
      break;
    case "error":
      setStreaming(false);
      status("erro: " + f.error);
      break;
    default:
      break;
  }
}

function status(text) {
  const d = document.createElement("div");
  d.className = "status";
  d.textContent = text;
  els.transcript.appendChild(d);
  scroll();
}

function setStreaming(on) {
  streaming = on;
  els.send.disabled = on || !currentId;
  els.input.disabled = on || !currentId;
  els.stop.hidden = !on;
}

function send() {
  const text = els.input.value.trim();
  if (!text || !ws || streaming) return;
  if (ws.readyState !== WebSocket.OPEN) {
    status("conectando… tente de novo em 1s");
    return;
  }
  bubble("user", document.createTextNode(text));
  els.input.value = "";
  autosize();
  setStreaming(true);
  ws.send(JSON.stringify({ type: "prompt", message: text }));
}

// ------------------------------------------------------------------ events

els.composer.addEventListener("submit", (e) => {
  e.preventDefault();
  send();
});
els.stop.addEventListener("click", () => {
  if (ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify({ type: "abort" }));
});
els.input.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    send();
  }
});
const autosize = () => {
  els.input.style.height = "auto";
  els.input.style.height = Math.min(els.input.scrollHeight, 200) + "px";
};
els.input.addEventListener("input", autosize);
els.filter.addEventListener("input", renderSessions);
els.refresh.addEventListener("click", loadSessions);
els.back.addEventListener("click", () => {
  els.app.classList.remove("viewing");
  if (ws) {
    ws.close();
    ws = null;
  }
  currentId = null;
  renderSessions();
});

loadSessions();
