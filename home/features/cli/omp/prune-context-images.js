// Auto-prune old images from the LLM context so a long session never crosses
// Anthropic's stricter per-image size cap (2000px), which only applies once a
// request carries more than 20 images. We keep only the most-recent N image
// blocks per request and replace older ones with a short text placeholder.
// Transient: this only changes what is sent to the model, not the saved
// transcript on disk.
export default function pruneContextImages(pi) {
  const KEEP = (() => {
    const raw =
      (typeof process !== "undefined" &&
        process.env &&
        process.env.OMP_MAX_CONTEXT_IMAGES) ||
      "";
    const n = parseInt(raw, 10);
    return Number.isFinite(n) && n >= 0 ? n : 10;
  })();
  const PLACEHOLDER =
    "[imagem antiga removida automaticamente do contexto (limite de imagens da API)]";

  pi.on("context", async (event) => {
    const messages = event && event.messages;
    if (!Array.isArray(messages)) return;

    // Collect every image content block position, in conversation order.
    const locs = [];
    for (let mi = 0; mi < messages.length; mi++) {
      const content = messages[mi] && messages[mi].content;
      if (!Array.isArray(content)) continue;
      for (let bi = 0; bi < content.length; bi++) {
        const blk = content[bi];
        if (blk && typeof blk === "object" && blk.type === "image") {
          locs.push(mi + ":" + bi);
        }
      }
    }
    if (locs.length <= KEEP) return; // within budget, nothing to prune

    // Replace all but the last KEEP images with a text placeholder.
    const drop = new Set(locs.slice(0, locs.length - KEEP));
    const out = messages.map((msg, mi) => {
      const content = msg && msg.content;
      if (!Array.isArray(content)) return msg;
      let changed = false;
      const newContent = content.map((blk, bi) => {
        if (drop.has(mi + ":" + bi)) {
          changed = true;
          return { type: "text", text: PLACEHOLDER };
        }
        return blk;
      });
      return changed ? { ...msg, content: newContent } : msg;
    });
    return { messages: out };
  });
}
