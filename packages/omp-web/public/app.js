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
  activeToggle: $("#activeToggle"),
  transcript: $("#transcript"),
  title: $("#title"),
  cwd: $("#cwd"),
  input: $("#input"),
  send: $("#send"),
  stop: $("#stop"),
  composer: $("#composer"),
  back: $("#back"),
  attach: $("#attach"),
  file: $("#file"),
  mic: $("#mic"),
  thumbs: $("#thumbs"),
};

let all = [];
let currentId = null;
let ws = null;
let streaming = false;
let liveBubble = null; // in-progress assistant bubble element
let thinkNode = null; // in-progress thinking block within the live bubble
let loadingNode = null; // "pensando…" placeholder shown until content arrives
let collapsed = new Set(); // directory groups the user has collapsed
let onlyActive = false; // sidebar filter: only sessions open right now
let pending = []; // images staged in the composer: { data, mimeType, url }

// --------------------------------------------------------------- markdown
// Tiny self-contained renderer. Text is HTML-escaped first, then only a known
// set of tags is emitted, so model output can never inject live markup.

const esc = (s) =>
  s.replace(
    /[&<>"]/g,
    (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c],
  );

function mdInline(s) {
  let out = "";
  for (const part of s.split(/(`[^`]+`)/g)) {
    if (part.length > 1 && part.startsWith("`") && part.endsWith("`")) {
      out += "<code>" + part.slice(1, -1) + "</code>";
      continue;
    }
    out += part
      .replace(
        /\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g,
        (_, t, u) =>
          `<a href="${u}" target="_blank" rel="noopener noreferrer">${t}</a>`,
      )
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/(^|[^*])\*([^*\n]+)\*/g, "$1<em>$2</em>")
      .replace(/(^|[^\w`])_([^_\n]+)_/g, "$1<em>$2</em>");
  }
  return out;
}

function markdown(src) {
  const lines = esc(src).replace(/\r\n?/g, "\n").split("\n");
  let html = "";
  let para = [];
  let list = null;
  const flushPara = () => {
    if (para.length) {
      html += "<p>" + mdInline(para.join(" ")) + "</p>";
      para = [];
    }
  };
  const flushList = () => {
    if (list) {
      html +=
        `<${list.type}>` +
        list.items.map((it) => "<li>" + mdInline(it) + "</li>").join("") +
        `</${list.type}>`;
      list = null;
    }
  };
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (/^```/.test(line)) {
      flushPara();
      flushList();
      const code = [];
      i++;
      while (i < lines.length && !/^```/.test(lines[i])) code.push(lines[i++]);
      html += "<pre><code>" + code.join("\n") + "</code></pre>";
      continue;
    }
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      flushPara();
      flushList();
      const lvl = h[1].length;
      html += `<h${lvl}>` + mdInline(h[2]) + `</h${lvl}>`;
      continue;
    }
    if (/^&gt;\s?/.test(line)) {
      flushPara();
      flushList();
      html +=
        "<blockquote>" + mdInline(line.replace(/^&gt;\s?/, "")) + "</blockquote>";
      continue;
    }
    const ul = /^[-*+]\s+(.*)$/.exec(line);
    const ol = /^(\d+)\.\s+(.*)$/.exec(line);
    if (ul || ol) {
      flushPara();
      const type = ul ? "ul" : "ol";
      if (!list || list.type !== type) {
        flushList();
        list = { type, items: [] };
      }
      list.items.push(ul ? ul[1] : ol[2]);
      continue;
    }
    if (/^(-{3,}|\*{3,}|_{3,})$/.test(line.trim())) {
      flushPara();
      flushList();
      html += "<hr>";
      continue;
    }
    if (!line.trim()) {
      flushPara();
      flushList();
      continue;
    }
    para.push(line);
  }
  flushPara();
  flushList();
  return html;
}

// -------------------------------------------------------------- rendering

const fmtTime = (ms) => {
  const d = new Date(ms);
  const diff = (Date.now() - ms) / 1000;
  if (diff < 3600) return Math.max(1, Math.round(diff / 60)) + "m";
  if (diff < 86400) return Math.round(diff / 3600) + "h";
  return d.toLocaleDateString();
};

const prettyDir = (cwd) =>
  (cwd || "").replace(/^\/home\/[^/]+/, "~") || "(sem diretório)";

function renderSessions() {
  const q = els.filter.value.trim().toLowerCase();
  let list = all;
  if (onlyActive) list = list.filter((s) => s.active);
  if (q)
    list = list.filter(
      (s) =>
        s.title.toLowerCase().includes(q) ||
        (s.cwd || "").toLowerCase().includes(q) ||
        (s.preview || "").toLowerCase().includes(q),
    );

  // Group sessions by their project directory (cwd). Groups are ordered by
  // their most-recent chat, sessions within a group by mtime desc. A search
  // query force-expands every group so matches are never hidden.
  const groups = new Map();
  for (const s of list) {
    const key = s.cwd || "";
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(s);
  }
  for (const arr of groups.values()) arr.sort((a, b) => b.mtime - a.mtime);
  const order = [...groups.keys()].sort(
    (a, b) => groups.get(b)[0].mtime - groups.get(a)[0].mtime,
  );

  els.sessions.innerHTML = "";
  if (!order.length) {
    const empty = document.createElement("li");
    empty.className = "s-empty";
    empty.textContent = onlyActive ? "nenhum chat aberto agora" : "nenhum chat";
    els.sessions.appendChild(empty);
    return;
  }
  for (const key of order) {
    const items = groups.get(key);
    const isCollapsed = !q && collapsed.has(key);

    const head = document.createElement("li");
    head.className = "s-group" + (isCollapsed ? " collapsed" : "");
    head.innerHTML =
      `<span class="s-caret">▾</span><span class="s-dir"></span>` +
      `<span class="s-count">${items.length}</span>`;
    head.querySelector(".s-dir").textContent = prettyDir(key);
    head.addEventListener("click", () => {
      if (collapsed.has(key)) collapsed.delete(key);
      else collapsed.add(key);
      renderSessions();
    });
    els.sessions.appendChild(head);

    if (isCollapsed) continue;
    for (const s of items) {
      const li = document.createElement("li");
      li.className = "s-item" + (s.active ? " live" : "");
      li.dataset.id = s.id;
      if (s.id === currentId) li.classList.add("active");
      li.innerHTML =
        `<div class="s-title"><span class="s-dot"></span><span></span></div>` +
        `<div class="s-meta">${fmtTime(s.mtime)}</div>`;
      li.querySelector(".s-title span:last-child").textContent = s.title;
      li.addEventListener("click", () => openSession(s.id));
      els.sessions.appendChild(li);
    }
  }
}

async function loadSessions() {
  try {
    const r = await fetch(api("api/sessions"));
    if (!r.ok) return;
    all = await r.json();
    renderSessions();
  } catch {
    /* transient (offline / service restart): keep the last render */
  }
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

function imageEl(src) {
  const img = document.createElement("img");
  img.className = "att";
  img.loading = "lazy";
  img.src = src;
  img.alt = "imagem";
  return img;
}

function renderBlocks(container, blocks) {
  for (const blk of blocks) {
    if (blk.t === "text") {
      const p = document.createElement("div");
      p.className = "md";
      p.innerHTML = markdown(blk.text);
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
      if (blk.ref) {
        container.appendChild(
          imageEl(
            api(
              "api/blob?ref=" +
                encodeURIComponent(blk.ref) +
                (blk.mime ? "&mime=" + encodeURIComponent(blk.mime) : ""),
            ),
          ),
        );
      } else {
        const d = document.createElement("div");
        d.className = "imgph";
        d.textContent = "🖼️ imagem";
        container.appendChild(d);
      }
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
  thinkNode = null;
  loadingNode = null;
  els.app.classList.add("viewing");
  renderSessions();
  els.transcript.innerHTML = '<div class="status">carregando…</div>';
  let data;
  try {
    const r = await fetch(api("api/session?id=" + encodeURIComponent(id)));
    if (!r.ok) throw new Error("http " + r.status);
    data = await r.json();
  } catch {
    els.transcript.innerHTML = '<div class="status">erro ao carregar</div>';
    return;
  }
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
  ws.addEventListener("close", () => setStreaming(false));
}

function ensureLive() {
  if (!liveBubble) liveBubble = bubble("assistant", null);
  return liveBubble;
}

function showLoading() {
  const b = ensureLive();
  if (loadingNode) return;
  loadingNode = document.createElement("div");
  loadingNode.className = "loading";
  loadingNode.innerHTML =
    "pensando<span class='dots'><i>.</i><i>.</i><i>.</i></span>";
  b.appendChild(loadingNode);
  scroll();
}

function hideLoading() {
  if (loadingNode) {
    loadingNode.remove();
    loadingNode = null;
  }
}

// The current live text node accumulates raw markdown in `_raw` and re-renders
// on each delta; a tool call or thinking block ends it so the next text starts
// a fresh node.
function streamNode(b) {
  let last = b.lastChild;
  if (!last || last.dataset?.stream !== "1") {
    last = document.createElement("div");
    last.className = "md";
    last.dataset.stream = "1";
    last._raw = "";
    b.appendChild(last);
  }
  return last;
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
      thinkNode = null;
      showLoading();
      break;
    case "message_update": {
      const ev = f.assistantMessageEvent;
      if (!ev) break;
      if (ev.type === "text_delta" && ev.delta) {
        hideLoading();
        thinkNode = null;
        const node = streamNode(ensureLive());
        node._raw += ev.delta;
        node.innerHTML = markdown(node._raw);
        scroll();
      } else if (ev.type === "thinking_delta" && ev.delta) {
        hideLoading();
        const b = ensureLive();
        if (!thinkNode) {
          thinkNode = document.createElement("div");
          thinkNode.className = "think";
          b.appendChild(thinkNode);
        }
        thinkNode.textContent += ev.delta;
        scroll();
      }
      break;
    }
    case "tool_execution_start": {
      hideLoading();
      thinkNode = null;
      const b = ensureLive();
      const d = document.createElement("div");
      d.className = "tool";
      d.innerHTML = "🔧 <b></b>";
      d.querySelector("b").textContent = f.toolName || f.name || "tool";
      b.appendChild(d);
      scroll();
      break;
    }
    case "agent_end":
      hideLoading();
      setStreaming(false);
      liveBubble = null;
      thinkNode = null;
      break;
    case "omp_exit":
      hideLoading();
      setStreaming(false);
      status(`sessão encerrada (código ${f.code})`);
      break;
    case "omp_stderr":
      console.warn("omp stderr:", f.text);
      break;
    case "error":
      hideLoading();
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

function autosize() {
  els.input.style.height = "auto";
  els.input.style.height = Math.min(els.input.scrollHeight, 200) + "px";
}

function send() {
  const text = els.input.value.trim();
  if ((!text && !pending.length) || !ws || streaming) return;
  if (ws.readyState !== WebSocket.OPEN) {
    status("conectando… tente de novo em 1s");
    return;
  }
  const u = bubble("user", null);
  if (pending.length) {
    const row = document.createElement("div");
    row.className = "att-row";
    for (const p of pending) row.appendChild(imageEl(p.url));
    u.appendChild(row);
  }
  if (text) {
    const p = document.createElement("div");
    p.className = "md";
    p.innerHTML = markdown(text);
    u.appendChild(p);
  }
  const images = pending.map((p) => ({ data: p.data, mimeType: p.mimeType }));
  clearPending();
  els.input.value = "";
  autosize();
  setStreaming(true);
  showLoading();
  ws.send(
    JSON.stringify({
      type: "prompt",
      message: text,
      ...(images.length ? { images } : {}),
    }),
  );
}

// ------------------------------------------------------------- attachments

function renderThumbs() {
  els.thumbs.innerHTML = "";
  els.thumbs.hidden = pending.length === 0;
  pending.forEach((p, i) => {
    const w = document.createElement("div");
    w.className = "thumb";
    const x = document.createElement("button");
    x.type = "button";
    x.className = "thumb-x";
    x.textContent = "×";
    x.addEventListener("click", () => {
      pending.splice(i, 1);
      renderThumbs();
    });
    w.append(imageEl(p.url), x);
    els.thumbs.appendChild(w);
  });
}

function clearPending() {
  pending = [];
  renderThumbs();
}

function addFiles(files) {
  for (const file of files) {
    if (!file.type.startsWith("image/")) continue;
    const reader = new FileReader();
    reader.onload = () => {
      const url = String(reader.result); // data:<mime>;base64,<data>
      pending.push({
        url,
        mimeType: file.type,
        data: url.slice(url.indexOf(",") + 1),
      });
      renderThumbs();
    };
    reader.readAsDataURL(file);
  }
}

// --------------------------------------------------------------- dictation
// Browser speech-to-text fills the composer (voice -> text). This does NOT
// send an audio file to the model; omp's RPC prompt only accepts images.

function setupMic() {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) {
    els.mic.hidden = true;
    return;
  }
  const rec = new SR();
  rec.lang = "pt-BR";
  rec.interimResults = false;
  rec.continuous = true;
  let on = false;
  rec.addEventListener("result", (e) => {
    let t = "";
    for (let i = e.resultIndex; i < e.results.length; i++)
      if (e.results[i].isFinal) t += e.results[i][0].transcript;
    if (t) {
      els.input.value = (els.input.value + " " + t.trim()).trim();
      autosize();
    }
  });
  rec.addEventListener("end", () => {
    on = false;
    els.mic.classList.remove("on");
  });
  els.mic.addEventListener("click", () => {
    if (on) {
      rec.stop();
      return;
    }
    try {
      rec.start();
      on = true;
      els.mic.classList.add("on");
    } catch {
      /* start() throws if already running: ignore */
    }
  });
}

// ------------------------------------------------------------------ events

els.composer.addEventListener("submit", (e) => {
  e.preventDefault();
  send();
});
els.stop.addEventListener("click", () => {
  if (ws && ws.readyState === WebSocket.OPEN)
    ws.send(JSON.stringify({ type: "abort" }));
});
els.input.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    send();
  }
});
els.input.addEventListener("input", autosize);
els.filter.addEventListener("input", renderSessions);
els.refresh.addEventListener("click", loadSessions);
els.activeToggle.addEventListener("click", () => {
  onlyActive = !onlyActive;
  els.activeToggle.classList.toggle("on", onlyActive);
  renderSessions();
});
els.attach.addEventListener("click", () => els.file.click());
els.file.addEventListener("change", () => {
  addFiles(els.file.files);
  els.file.value = "";
});
els.input.addEventListener("paste", (e) => {
  const imgs = [...(e.clipboardData?.items || [])]
    .filter((it) => it.type.startsWith("image/"))
    .map((it) => it.getAsFile())
    .filter(Boolean);
  if (imgs.length) {
    e.preventDefault();
    addFiles(imgs);
  }
});
for (const t of ["dragover", "drop"])
  els.composer.addEventListener(t, (e) => {
    e.preventDefault();
    if (t === "drop" && e.dataTransfer?.files?.length)
      addFiles(e.dataTransfer.files);
  });
els.back.addEventListener("click", () => {
  els.app.classList.remove("viewing");
  if (ws) {
    ws.close();
    ws = null;
  }
  currentId = null;
  renderSessions();
});

// Refresh the sidebar (and the "open now" dots) periodically while visible.
setInterval(() => {
  if (document.visibilityState === "visible") loadSessions();
}, 5000);

setupMic();
loadSessions();
