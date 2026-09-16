/* gearhub dashboard: vanilla JS, no dependencies. */
"use strict";

const POLL_MS = 10000;
const DEBOUNCE_MS = 300;

const INPUT_SOURCES = [
  { value: "0x0f", label: "DisplayPort" },
  { value: "0x11", label: "HDMI 1" },
  { value: "0x12", label: "HDMI 2" },
];

const $ = (sel) => document.querySelector(sel);

function setStatus(name, text, cls) {
  const el = document.querySelector(`[data-status="${name}"]`);
  if (!el) return;
  el.textContent = text;
  el.className = "status" + (cls ? " " + cls : "");
}

function notDetected(body, message) {
  body.innerHTML = "";
  const p = document.createElement("p");
  p.className = "muted";
  p.textContent = message || "nao detectado";
  body.appendChild(p);
}

function debounce(fn, ms) {
  let timer = null;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

async function getJSON(url) {
  const resp = await fetch(url);
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.json();
}

async function postJSON(url, payload) {
  const resp = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
  return resp.json();
}

/* ---------------- Monitores ---------------- */

// While the user drags a slider we must not clobber it with poll data.
const dirtyControls = new Set();

function sliderControl(display, code, label, reading) {
  const row = document.createElement("div");
  row.className = "control";
  const id = `vcp-${display}-${code}`;

  const lab = document.createElement("label");
  lab.htmlFor = id;
  lab.textContent = label;

  const slider = document.createElement("input");
  slider.type = "range";
  slider.id = id;
  slider.min = 0;
  slider.max = reading.max || 100;
  slider.value = reading.current;

  const out = document.createElement("output");
  out.textContent = reading.current;

  const push = debounce(async (value) => {
    try {
      await postJSON(`/api/monitors/${display}/vcp`, { code, value: Number(value) });
    } catch (err) {
      console.error("setvcp", err);
    } finally {
      dirtyControls.delete(id);
    }
  }, DEBOUNCE_MS);

  slider.addEventListener("input", () => {
    dirtyControls.add(id);
    out.textContent = slider.value;
    push(slider.value);
  });

  row.append(lab, slider, out);
  return row;
}

function inputSelect(display, currentValue) {
  const row = document.createElement("div");
  row.className = "control";

  const lab = document.createElement("label");
  lab.textContent = "Entrada";

  const select = document.createElement("select");
  let matched = false;
  for (const src of INPUT_SOURCES) {
    const opt = document.createElement("option");
    opt.value = src.value;
    opt.textContent = src.label;
    if (src.value === currentValue) { opt.selected = true; matched = true; }
    select.appendChild(opt);
  }
  if (currentValue && !matched) {
    const opt = document.createElement("option");
    opt.value = currentValue;
    opt.textContent = currentValue;
    opt.selected = true;
    select.appendChild(opt);
  }

  select.addEventListener("change", async () => {
    try {
      await postJSON(`/api/monitors/${display}/vcp`, {
        code: "60",
        value: parseInt(select.value, 16),
      });
    } catch (err) {
      console.error("input source", err);
    }
  });

  const spacer = document.createElement("span");
  row.append(lab, select, spacer);
  return row;
}

function renderMonitors(data) {
  const body = $("#monitors-body");
  if (!data.available || !data.monitors || data.monitors.length === 0) {
    setStatus("monitors", "nao detectado", "off");
    notDetected(body, "Nenhum display DDC/CI detectado.");
    return;
  }
  setStatus("monitors", `${data.monitors.length} display(s)`, "ok");

  // Rebuild only when the set of displays changed; otherwise update in place
  // so sliders being dragged are not destroyed.
  const key = data.monitors.map((m) => m.display).join(",");
  if (body.dataset.key !== key) {
    body.dataset.key = key;
    body.innerHTML = "";
    for (const mon of data.monitors) {
      const sub = document.createElement("div");
      sub.className = "subcard";
      sub.dataset.display = mon.display;

      const title = document.createElement("div");
      title.className = "subcard-title";
      const name = document.createElement("span");
      name.textContent = mon.model || `Display ${mon.display}`;
      const tag = document.createElement("span");
      tag.className = "tag";
      tag.textContent = `display ${mon.display}`;
      title.append(name, tag);
      sub.appendChild(title);

      if (mon.brightness) sub.appendChild(sliderControl(mon.display, "10", "Brilho", mon.brightness));
      if (mon.contrast) sub.appendChild(sliderControl(mon.display, "12", "Contraste", mon.contrast));
      sub.appendChild(inputSelect(mon.display, mon.input));
      body.appendChild(sub);
    }
    return;
  }

  for (const mon of data.monitors) {
    for (const [code, reading] of [["10", mon.brightness], ["12", mon.contrast]]) {
      if (!reading) continue;
      const id = `vcp-${mon.display}-${code}`;
      if (dirtyControls.has(id)) continue;
      const slider = document.getElementById(id);
      if (slider) {
        slider.value = reading.current;
        const out = slider.parentElement.querySelector("output");
        if (out) out.textContent = reading.current;
      }
    }
  }
}

async function pollMonitors() {
  try {
    renderMonitors(await getJSON("/api/monitors"));
  } catch (err) {
    setStatus("monitors", "erro", "off");
    notDetected($("#monitors-body"), "Falha ao consultar ddcutil.");
  }
}

/* ---------------- Mouse ---------------- */

function mouseConfigForm(deviceName) {
  const wrap = document.createElement("div");
  wrap.className = "inline-form";

  const settingSel = document.createElement("select");
  for (const [value, label] of [["dpi", "DPI"], ["report_rate", "Taxa (polling)"]]) {
    const opt = document.createElement("option");
    opt.value = value;
    opt.textContent = label;
    settingSel.appendChild(opt);
  }

  const valueInput = document.createElement("input");
  valueInput.type = "text";
  valueInput.placeholder = "ex: 1600 ou 1ms";
  valueInput.size = 10;

  const btn = document.createElement("button");
  btn.className = "button";
  btn.type = "button";
  btn.textContent = "Aplicar";

  const notice = document.createElement("p");
  notice.className = "notice";

  btn.addEventListener("click", async () => {
    const value = valueInput.value.trim();
    if (!value) {
      notice.textContent = "Informe um valor.";
      return;
    }
    notice.textContent = "Aplicando...";
    try {
      const res = await postJSON("/api/mouse/config", {
        device: deviceName,
        setting: settingSel.value,
        value,
      });
      notice.textContent = res.ok ? "Aplicado." : `Falhou: ${res.error || "erro"}`;
      loadMouse();
    } catch (err) {
      notice.textContent = `Falhou: ${err.message}`;
    }
  });

  const form = document.createElement("div");
  form.className = "inline-form";
  form.append(settingSel, valueInput, btn);

  wrap.style.flexDirection = "column";
  wrap.style.alignItems = "stretch";
  wrap.append(form, notice);
  return wrap;
}

function renderMouse(data) {
  const body = $("#mouse-body");
  if (!data.available || !data.devices || data.devices.length === 0) {
    setStatus("mouse", "nao detectado", "off");
    notDetected(body, "Nenhum dispositivo Logitech detectado via solaar.");
    return;
  }
  setStatus("mouse", "conectado", "ok");
  body.innerHTML = "";

  for (const dev of data.devices) {
    const sub = document.createElement("div");
    sub.className = "subcard";

    const name = document.createElement("p");
    name.className = "device-name";
    name.textContent = dev.name;
    sub.appendChild(name);

    const kv = document.createElement("dl");
    kv.className = "kv";
    const pairs = [];
    if (dev.battery) pairs.push(["Bateria", dev.battery]);
    if (dev.dpi) pairs.push(["DPI", dev.dpi]);
    if (dev.reportRate) pairs.push(["Taxa", dev.reportRate]);
    for (const [k, v] of pairs) {
      const dt = document.createElement("dt");
      dt.textContent = k;
      const dd = document.createElement("dd");
      dd.textContent = v;
      kv.append(dt, dd);
    }
    if (pairs.length) sub.appendChild(kv);

    sub.appendChild(mouseConfigForm(dev.name));
    body.appendChild(sub);
  }
}

async function loadMouse() {
  try {
    renderMouse(await getJSON("/api/mouse"));
  } catch (err) {
    setStatus("mouse", "erro", "off");
    notDetected($("#mouse-body"), "Falha ao consultar solaar.");
  }
}

/* ---------------- Water cooler ---------------- */

// OpenLinkHub payloads vary by version; walk the JSON and pull out
// anything that looks like a temperature, pump, or fan reading.
function extractCoolerMetrics(node, path, out) {
  if (out.length >= 8 || node == null) return;
  if (typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      extractCoolerMetrics(value, path.concat(key), out);
      if (out.length >= 8) return;
    }
    return;
  }
  if (typeof node !== "number" && typeof node !== "string") return;
  const key = path.join(".").toLowerCase();
  const leaf = String(path[path.length - 1] || "").toLowerCase();
  let label = null;
  let suffix = "";
  if (/temp/.test(leaf) || /liquid/.test(key)) {
    label = /liquid/.test(key) ? "Liquido" : "Temp";
    if (typeof node === "number") suffix = " °C";
  } else if (/pump/.test(key) && /(rpm|speed|value)/.test(leaf)) {
    label = "Bomba";
    if (typeof node === "number") suffix = " rpm";
  } else if (/fan/.test(key) && /(rpm|speed|value)/.test(leaf)) {
    label = "Fan";
    if (typeof node === "number") suffix = " rpm";
  } else if (/rpm/.test(leaf)) {
    label = path.length > 1 ? String(path[path.length - 2]) : "RPM";
    suffix = " rpm";
  }
  if (label !== null && node !== 0 && node !== "") {
    out.push({ label, value: `${node}${suffix}` });
  }
}

function renderCooler(data) {
  const body = $("#cooler-body");
  if (!data.available) {
    setStatus("cooler", "nao detectado", "off");
    notDetected(body, "Daemon OpenLinkHub fora do ar.");
    return;
  }
  setStatus("cooler", "online", "ok");
  body.innerHTML = "";

  const metrics = [];
  extractCoolerMetrics(data.data, [], metrics);

  if (metrics.length === 0) {
    const p = document.createElement("p");
    p.className = "muted";
    p.textContent = "Daemon ativo. Abra o OpenLinkHub para detalhes e RGB.";
    body.appendChild(p);
    return;
  }

  const row = document.createElement("div");
  row.className = "metric-row";
  for (const m of metrics) {
    const box = document.createElement("div");
    box.className = "metric";
    const value = document.createElement("div");
    value.className = "value";
    value.textContent = m.value;
    const label = document.createElement("div");
    label.className = "label";
    label.textContent = m.label;
    box.append(value, label);
    row.appendChild(box);
  }
  body.appendChild(row);
}

async function pollCooler() {
  try {
    renderCooler(await getJSON("/api/cooler"));
  } catch (err) {
    setStatus("cooler", "erro", "off");
    notDetected($("#cooler-body"), "Falha ao consultar o daemon.");
  }
}

/* ---------------- boot ---------------- */

pollMonitors();
loadMouse();
pollCooler();
setInterval(pollMonitors, POLL_MS);
setInterval(pollCooler, POLL_MS);
