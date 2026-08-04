#!/usr/bin/env bun
// omp-collab-relay: a self-hosted, content-blind WebSocket relay for omp's
// `/collab` live-session sharing, so session data never leaves the tailnet.
//
// Dependency-free reimplementation of oh-my-pi's
// packages/collab-web/scripts/local-relay.ts (MIT, Can Boluk). It speaks the
// exact contract the real omp host and collab-web guest expect:
//   GET /r/<roomId>?role=host|guest       -> WebSocket upgrade
//   host binary frame [4B BE peerId][payload]: peerId 0 broadcasts to all
//     guests, peerId N targets that guest; forwarded unchanged
//   guest binary frame: the first 4 bytes are rewritten to the sender's peerId,
//     then forwarded to the host
//   TEXT control to host: {"t":"peer-joined","peer":N} / {"t":"peer-left","peer":N}
//   host disconnect: TEXT {"t":"room-closed"} to guests, then close 4001
// Payloads are AES-256-GCM sealed by the clients; the relay never sees plaintext.

const PORT = parseInt(process.env.OMP_COLLAB_PORT || "8792", 10);
const HOST = process.env.OMP_COLLAB_HOST || "127.0.0.1";
const HEADER = 4; // envelope header length: a uint32 BE peerId
const ROOM_PATH_RE = /^\/r\/([A-Za-z0-9_-]{10,64})$/;

const rooms = new Map(); // roomId -> { host, guests: Map<peerId, ws>, nextPeerId }

Bun.serve({
  port: PORT,
  hostname: HOST,
  idleTimeout: 255,
  fetch(req, srv) {
    const url = new URL(req.url);
    if (url.pathname === "/healthz") return new Response("ok");
    const m = ROOM_PATH_RE.exec(url.pathname);
    const role = url.searchParams.get("role");
    if (!m || (role !== "host" && role !== "guest"))
      return new Response("not found", { status: 404 });
    if (srv.upgrade(req, { data: { roomId: m[1], role, peerId: 0 } }))
      return undefined;
    return new Response("websocket upgrade required", { status: 426 });
  },
  websocket: {
    idleTimeout: 255,
    open(ws) {
      const { roomId, role } = ws.data;
      if (role === "host") {
        if (rooms.has(roomId)) {
          ws.close(4009, "a host is already connected for this room");
          return;
        }
        rooms.set(roomId, { host: ws, guests: new Map(), nextPeerId: 1 });
        return;
      }
      const room = rooms.get(roomId);
      if (!room) {
        ws.close(4004, "no such room");
        return;
      }
      const peerId = room.nextPeerId++;
      ws.data.peerId = peerId;
      room.guests.set(peerId, ws);
      room.host.send(JSON.stringify({ t: "peer-joined", peer: peerId }));
    },
    message(ws, message) {
      if (typeof message === "string") return; // clients never send TEXT
      if (message.byteLength < HEADER) return;
      const room = rooms.get(ws.data.roomId);
      if (!room) return;
      const view = new DataView(message.buffer, message.byteOffset, HEADER);
      if (ws.data.role === "host") {
        // peerId 0 broadcasts to every guest; N targets that one guest.
        const peer = view.getUint32(0, false);
        if (peer === 0) for (const g of room.guests.values()) g.send(message);
        else room.guests.get(peer)?.send(message);
        return;
      }
      // Guest -> host: stamp the sender's peerId into the envelope, forward.
      view.setUint32(0, ws.data.peerId, false);
      room.host.send(message);
    },
    close(ws) {
      const { roomId, role, peerId } = ws.data;
      const room = rooms.get(roomId);
      if (!room) return;
      if (role === "host") {
        if (room.host !== ws) return; // a rejected second host
        rooms.delete(roomId);
        const closure = JSON.stringify({ t: "room-closed" });
        for (const g of room.guests.values()) {
          g.send(closure);
          g.close(4001, "room closed");
        }
        room.guests.clear();
        return;
      }
      if (room.guests.delete(peerId))
        room.host.send(JSON.stringify({ t: "peer-left", peer: peerId }));
    },
  },
});

console.log(`omp-collab-relay listening on ${HOST}:${PORT}`);
