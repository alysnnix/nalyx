#!/usr/bin/env bun
// omp-web: a local web UI to browse and continue omp sessions.
//
// Loopback-only by design: it binds 127.0.0.1. Tailnet access + TLS is handled
// by the reverse proxy in front (see the omp-web NixOS module). Access is gated
// by optional Google OIDC + an email allowlist when OMP_WEB_AUTH=google.
//
// Endpoints:
//   GET  /                      -> SPA
//   GET  /app.js /style.css     -> static assets
//   GET  /api/sessions          -> [{ id, title, preview, cwd, mtime, dir }]
//   GET  /api/session?id=<id>   -> { id, title, cwd, messages: [...] }
//   WS   /api/stream?id=<id>    -> continue a session over RPC (streams events)
//
// Runs the agent by spawning `omp --mode rpc --resume <file>` in the session's
// own cwd, so tools operate on that project. Requires the omp binary and Bun.

import { readdir, stat } from "node:fs/promises";
import { join, basename } from "node:path";
import { homedir } from "node:os";

const PORT = parseInt(process.env.OMP_WEB_PORT || "8790", 10);
const HOST = process.env.OMP_WEB_HOST || "127.0.0.1";
const OMP_BIN = process.env.OMP_BIN || "omp";
const SESSIONS_DIR =
  process.env.OMP_SESSIONS_DIR || join(homedir(), ".omp", "agent", "sessions");
const PUBLIC_DIR = new URL("./public/", import.meta.url).pathname;
const HEAD_BYTES = 64 * 1024;

const log = (...a) => console.log(new Date().toISOString(), ...a);

// -------------------------------------------------------------------- auth
//
// Optional Google OIDC (authorization-code flow) with an email allowlist.
// Credentials come from the environment only (never the public repo). With
// OMP_WEB_AUTH=off (default) the service is open — safe only on loopback / a
// single-user tailnet. The id_token is trusted because it is fetched
// server-to-server from Google's token endpoint over TLS (no JWKS needed).

const AUTH = (process.env.OMP_WEB_AUTH || "off").toLowerCase();
const GOOGLE_CLIENT_ID = process.env.OMP_WEB_GOOGLE_CLIENT_ID || "";
const GOOGLE_CLIENT_SECRET = process.env.OMP_WEB_GOOGLE_CLIENT_SECRET || "";
const ALLOWED_EMAILS = (process.env.OMP_WEB_ALLOWED_EMAILS || "")
  .split(",")
  .map((s) => s.trim().toLowerCase())
  .filter(Boolean);
const BASE_URL_OVERRIDE = process.env.OMP_WEB_BASE_URL || "";
const COOKIE = "omp_session";
const SESSION_TTL_MS = 30 * 24 * 3600 * 1000;

const authEnabled = AUTH === "google";
const authConfigured =
  authEnabled && !!GOOGLE_CLIENT_ID && !!GOOGLE_CLIENT_SECRET && ALLOWED_EMAILS.length > 0;

const sessions = new Map(); // token -> { email, exp }
const oauthStates = new Map(); // state -> exp (ms)
const now = () => Date.now();
const rand = () =>
  crypto.randomUUID().replaceAll("-", "") + crypto.randomUUID().replaceAll("-", "");
const sweep = (map) => {
  const t = now();
  for (const [k, v] of map) if ((typeof v === "number" ? v : v.exp) < t) map.delete(k);
};

function getCookie(req, name) {
  for (const part of (req.headers.get("cookie") || "").split(";")) {
    const [k, ...v] = part.trim().split("=");
    if (k === name) return decodeURIComponent(v.join("="));
  }
  return null;
}

function currentEmail(req) {
  if (!authEnabled) return "anon";
  const tok = getCookie(req, COOKIE);
  const s = tok && sessions.get(tok);
  if (!s || s.exp < now()) {
    if (s) sessions.delete(tok);
    return null;
  }
  return s.email;
}

function baseUrl(req) {
  if (BASE_URL_OVERRIDE) return BASE_URL_OVERRIDE.replace(/\/$/, "");
  const url = new URL(req.url);
  const host =
    req.headers.get("x-forwarded-host") || req.headers.get("host") || url.host;
  // tailscale serve always terminates TLS, so *.ts.net is https regardless of
  // whatever proto header the local nginx hop set.
  const proto = host.includes(".ts.net")
    ? "https"
    : req.headers.get("x-forwarded-proto") || url.protocol.replace(":", "");
  return `${proto}://${host}`;
}

function loginPage(msg) {
  return new Response(
    `<!doctype html><meta charset=utf-8>` +
      `<meta name=viewport content="width=device-width,initial-scale=1">` +
      `<title>omp chats — entrar</title><style>` +
      `body{background:#0f1115;color:#e6e8ee;font:16px system-ui;display:grid;place-items:center;height:100dvh;margin:0}` +
      `.card{background:#161923;border:1px solid #2a2f3d;border-radius:14px;padding:28px 32px;text-align:center;max-width:340px}` +
      `a.btn{display:inline-block;margin-top:14px;background:#6ea8fe;color:#08111f;font-weight:600;text-decoration:none;padding:10px 18px;border-radius:10px}` +
      `.err{color:#ff6b6b}</style>` +
      `<div class=card><h1>omp chats</h1>${msg ? `<p class=err>${msg}</p>` : ""}` +
      `<a class=btn href="auth/login">Entrar com Google</a></div>`,
    {
      status: msg ? 403 : 200,
      headers: { "content-type": "text/html; charset=utf-8" },
    },
  );
}

function redirectTo(loc, cookie) {
  const r = new Response("", { status: 302, headers: { location: loc } });
  if (cookie) r.headers.set("set-cookie", cookie);
  return r;
}

// Handle /auth/* routes. Returns a Response, or null if not an auth route.
async function handleAuth(req, url, path) {
  if (!authEnabled) return null;
  const redirectUri = `${baseUrl(req)}/auth/callback`;

  if (path.endsWith("/auth/login")) {
    if (!authConfigured) return new Response("auth not configured", { status: 500 });
    const state = rand();
    oauthStates.set(state, now() + 10 * 60 * 1000);
    sweep(oauthStates);
    const p = new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID,
      redirect_uri: redirectUri,
      response_type: "code",
      scope: "openid email",
      state,
      prompt: "select_account",
    });
    return redirectTo(`https://accounts.google.com/o/oauth2/v2/auth?${p}`);
  }

  if (path.endsWith("/auth/logout")) {
    const tok = getCookie(req, COOKIE);
    if (tok) sessions.delete(tok);
    return redirectTo(`${baseUrl(req)}/`, `${COOKIE}=; HttpOnly; Path=/; Max-Age=0`);
  }

  if (path.endsWith("/auth/callback")) {
    const code = url.searchParams.get("code");
    const state = url.searchParams.get("state");
    if (!code || !state || !oauthStates.has(state))
      return loginPage("Sessão de login inválida, tente de novo.");
    oauthStates.delete(state);
    let email = null;
    let verified = false;
    try {
      const tr = await fetch("https://oauth2.googleapis.com/token", {
        method: "POST",
        headers: { "content-type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({
          code,
          client_id: GOOGLE_CLIENT_ID,
          client_secret: GOOGLE_CLIENT_SECRET,
          redirect_uri: redirectUri,
          grant_type: "authorization_code",
        }),
      });
      const tok = await tr.json();
      if (tok.id_token) {
        const payload = JSON.parse(
          Buffer.from(tok.id_token.split(".")[1], "base64url").toString("utf8"),
        );
        email = (payload.email || "").toLowerCase();
        verified = payload.email_verified === true || payload.email_verified === "true";
      }
    } catch (e) {
      log("oauth token exchange failed", e);
    }
    if (!email || !verified || !ALLOWED_EMAILS.includes(email))
      return loginPage("Esse email não tem acesso.");
    const token = rand();
    sessions.set(token, { email, exp: now() + SESSION_TTL_MS });
    sweep(sessions);
    const secure = baseUrl(req).startsWith("https") ? "; Secure" : "";
    return redirectTo(
      `${baseUrl(req)}/`,
      `${COOKIE}=${token}; HttpOnly; SameSite=Lax; Path=/; Max-Age=${SESSION_TTL_MS / 1000}${secure}`,
    );
  }
  return null;
}

// ---------------------------------------------------------------- parsing

const safeParse = (line) => {
  try {
    return JSON.parse(line);
  } catch {
    return null;
  }
};

const textOfContent = (content) => {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  for (const b of content) {
    if (b && typeof b === "object" && b.type === "text" && b.text) {
      return String(b.text);
    }
  }
  return "";
};

// Lightweight metadata from the head of a session file (no full read).
async function summarize(file, dir) {
  let st;
  try {
    st = await stat(file);
  } catch {
    return null;
  }
  let head = "";
  try {
    head = await Bun.file(file).slice(0, HEAD_BYTES).text();
  } catch {
    return null;
  }
  const lines = head.split("\n");
  let id = basename(file).replace(/\.jsonl$/, "");
  let cwd = "";
  let title = "";
  let preview = "";
  for (const line of lines) {
    if (!line) continue;
    const o = safeParse(line);
    if (!o || typeof o !== "object") continue;
    if (o.type === "session") {
      if (o.id) id = o.id;
      if (o.cwd) cwd = o.cwd;
      if (o.title && !title) title = o.title;
    } else if (o.type === "title" && o.title) {
      title = o.title; // later title records win
    } else if (o.type === "message" && o.message && !preview) {
      if (o.message.role === "user") {
        preview = textOfContent(o.message.content).slice(0, 200);
      }
    }
  }
  if (!title) title = preview || "Untitled";
  return { id, title, preview, cwd, dir, mtime: st.mtimeMs, file };
}

async function listSessionFiles() {
  const out = [];
  let dirs;
  try {
    dirs = await readdir(SESSIONS_DIR, { withFileTypes: true });
  } catch {
    return out;
  }
  for (const d of dirs) {
    if (!d.isDirectory()) continue;
    const sub = join(SESSIONS_DIR, d.name);
    let files;
    try {
      files = await readdir(sub);
    } catch {
      continue;
    }
    for (const f of files) {
      if (f.endsWith(".jsonl")) out.push({ file: join(sub, f), dir: d.name });
    }
  }
  return out;
}

// id -> { file, cwd } index, rebuilt on demand. Keeps the client from ever
// handing us raw filesystem paths (no traversal surface).
let indexById = new Map();

async function buildIndex() {
  const files = await listSessionFiles();
  const infos = (
    await Promise.all(files.map(({ file, dir }) => summarize(file, dir)))
  ).filter(Boolean);
  const map = new Map();
  for (const i of infos) map.set(i.id, i);
  indexById = map;
  infos.sort((a, b) => b.mtime - a.mtime);
  return infos;
}

async function resolveId(id) {
  if (indexById.has(id)) return indexById.get(id);
  await buildIndex();
  return indexById.get(id) || null;
}

// Full transcript, normalized to display blocks.
async function readTranscript(file) {
  const text = await Bun.file(file).text();
  const messages = [];
  let title = "";
  let cwd = "";
  let id = "";
  for (const line of text.split("\n")) {
    if (!line) continue;
    const o = safeParse(line);
    if (!o) continue;
    if (o.type === "session") {
      id = o.id || id;
      cwd = o.cwd || cwd;
      if (o.title && !title) title = o.title;
    } else if (o.type === "title" && o.title) {
      title = o.title;
    } else if (o.type === "message" && o.message) {
      const role = o.message.role;
      if (role !== "user" && role !== "assistant") continue;
      const blocks = [];
      const content = o.message.content;
      if (typeof content === "string") {
        if (content.trim()) blocks.push({ t: "text", text: content });
      } else if (Array.isArray(content)) {
        for (const b of content) {
          if (!b || typeof b !== "object") continue;
          switch (b.type) {
            case "text":
              if (b.text) blocks.push({ t: "text", text: b.text });
              break;
            case "thinking":
              if (b.thinking) blocks.push({ t: "think", text: b.thinking });
              break;
            case "toolCall":
              blocks.push({
                t: "tool",
                name: b.name || b.toolName || "tool",
                input: b.input ?? b.arguments ?? null,
              });
              break;
            case "toolResult":
              blocks.push({
                t: "toolResult",
                output: textOfContent(b.content ?? b.output ?? b.result ?? ""),
                isError: !!b.isError,
              });
              break;
            case "image":
              blocks.push({ t: "image" });
              break;
            default:
              break;
          }
        }
      }
      if (blocks.length) messages.push({ role, blocks });
    }
  }
  return { id, title, cwd, messages };
}

// ------------------------------------------------------------------ omp RPC

// Per-socket state: the spawned omp process + a line reader over its stdout.
async function startOmp(ws, info) {
  const proc = Bun.spawn({
    cmd: [OMP_BIN, "--mode", "rpc", "--resume", info.file],
    cwd: info.cwd && info.cwd.length ? info.cwd : undefined,
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env },
  });
  ws.data.proc = proc;
  ws.data.stdin = proc.stdin;

  // Stream stdout as newline-delimited JSON to the client.
  (async () => {
    const decoder = new TextDecoder();
    let buf = "";
    for await (const chunk of proc.stdout) {
      buf += decoder.decode(chunk, { stream: true });
      let nl;
      while ((nl = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, nl);
        buf = buf.slice(nl + 1);
        if (!line.trim()) continue;
        // Auto-decline extension UI dialogs so a turn never stalls waiting
        // for a UI surface we don't have. Fire-and-forget UI (notify/status)
        // needs no reply and is simply not forwarded.
        const frame = safeParse(line);
        if (frame && frame.type === "extension_ui_request") {
          if (["select", "confirm", "input", "editor"].includes(frame.method)) {
            sendToOmp(ws, { type: "extension_ui_response", id: frame.id, cancelled: true });
          }
          continue;
        }
        try {
          ws.send(line); // forward raw RPC frame; client parses
        } catch {
          /* socket closed */
        }
      }
    }
  })().catch((e) => log("omp stdout error", e));

  // Surface fatal stderr so the client isn't left hanging.
  (async () => {
    const decoder = new TextDecoder();
    let errbuf = "";
    for await (const chunk of proc.stderr) errbuf += decoder.decode(chunk);
    if (errbuf.trim())
      try {
        ws.send(JSON.stringify({ type: "omp_stderr", text: errbuf.slice(-2000) }));
      } catch {}
  })().catch(() => {});

  proc.exited.then((code) => {
    try {
      ws.send(JSON.stringify({ type: "omp_exit", code }));
    } catch {}
  });
}

function sendToOmp(ws, obj) {
  const sink = ws.data.proc?.stdin;
  if (sink) {
    sink.write(JSON.stringify(obj) + "\n");
    sink.flush?.();
  }
}

// ------------------------------------------------------------------- server

const staticFile = (name) => Bun.file(join(PUBLIC_DIR, name));

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), {
    status,
    headers: { "content-type": "application/json" },
  });

const server = Bun.serve({
  port: PORT,
  hostname: HOST,
  idleTimeout: 255,
  async fetch(req, server) {
    const url = new URL(req.url);
    const path = url.pathname;

    const authResp = await handleAuth(req, url, path);
    if (authResp) return authResp;
    if (authEnabled) {
      if (!authConfigured)
        return new Response(
          "omp-web: OMP_WEB_AUTH=google but Google credentials / allowed emails are not configured",
          { status: 500 },
        );
      if (!currentEmail(req)) {
        if (path.includes("/api/")) return json({ error: "unauthorized" }, 401);
        return loginPage();
      }
    }
    // Tolerate being mounted under a base path by the proxy: strip a trailing
    // known route regardless of prefix.
    if (path.endsWith("/api/stream")) {
      const id = url.searchParams.get("id") || "";
      const info = await resolveId(id);
      if (!info) return json({ error: "session not found" }, 404);
      if (server.upgrade(req, { data: { info, id } })) return;
      return new Response("expected websocket", { status: 426 });
    }
    if (path.endsWith("/api/sessions")) {
      return json(
        (await buildIndex()).map(({ id, title, preview, cwd, mtime, dir }) => ({
          id,
          title,
          preview,
          cwd,
          mtime,
          dir,
        })),
      );
    }
    if (path.endsWith("/api/session")) {
      const info = await resolveId(url.searchParams.get("id") || "");
      if (!info) return json({ error: "session not found" }, 404);
      return json(await readTranscript(info.file));
    }
    // static
    let name = path.replace(/^.*\/(?=[^/]*$)/, ""); // basename
    if (!name || name === "" || path.endsWith("/")) name = "index.html";
    const f = staticFile(name);
    if (await f.exists()) return new Response(f);
    // SPA fallback
    return new Response(staticFile("index.html"));
  },
  websocket: {
    idleTimeout: 255,
    async open(ws) {
      ws.data.started = false;
      ws.send(JSON.stringify({ type: "hello", id: ws.data.id }));
    },
    async message(ws, raw) {
      const msg = safeParse(typeof raw === "string" ? raw : raw.toString());
      if (!msg) return;
      if (msg.type === "prompt") {
        if (!ws.data.started) {
          ws.data.started = true;
          try {
            await startOmp(ws, ws.data.info);
          } catch (e) {
            ws.send(JSON.stringify({ type: "error", error: String(e) }));
            return;
          }
        }
        sendToOmp(ws, {
          type: "prompt",
          message: msg.message,
          ...(ws.data.streaming ? { streamingBehavior: "followUp" } : {}),
        });
      } else if (msg.type === "abort") {
        sendToOmp(ws, { type: "abort" });
      }
    },
    close(ws) {
      try {
        ws.data.proc?.kill();
      } catch {}
    },
  },
});

log(
  `omp-web listening on http://${HOST}:${PORT}  (sessions: ${SESSIONS_DIR}, ` +
    `auth: ${authEnabled ? (authConfigured ? "google" : "google[UNCONFIGURED]") : "off"})`,
);
