---
name: excalidraw
description: "Create Excalidraw diagrams (workflows, flowcharts, architecture, mind maps) inside the Obsidian vault. Use when the user asks to draw, sketch, diagram, visualize a flow, or create an Excalidraw drawing. Writes uncompressed JSON to a `.excalidraw.md` file that the Obsidian Excalidraw plugin renders. Triggers: 'desenha um diagrama', 'faz um workflow', 'draw a flow', 'cria um excalidraw'."
---

# Excalidraw — Draw Diagrams in Obsidian

Generate `.excalidraw.md` files with **uncompressed JSON** that the Obsidian Excalidraw plugin renders directly. No compression step required — just write valid JSON.

## Vault paths

The Obsidian vault lives in **two mirrored locations** on this machine. Save to the Windows path; that's the one Obsidian opens.

| Path | Role |
|------|------|
| `/mnt/c/Users/aly/Documents/GitHub/notes/excalidraw/` | **Canonical** — Obsidian opens this vault. Always save here. |
| `~/nalyx/.private/notes/Excalidraw/` | WSL mirror — only mirror to it if the user explicitly asks. |

Verify the canonical path before writing:

```bash
ls /mnt/c/Users/aly/Documents/GitHub/notes/excalidraw/ 2>/dev/null
```

If missing, tell the user "Excalidraw vault not found at the Windows path — is the disk mounted?" and stop.

## File format

Every Excalidraw drawing is a markdown file with this **exact** skeleton:

````markdown
---
excalidraw-plugin: parsed
tags: [excalidraw]
---
==⚠  Switch to EXCALIDRAW VIEW in the MORE OPTIONS menu of this document. ⚠==

# Excalidraw Data

## Text Elements
Label one ^id1
Label two ^id2

%%
## Drawing
```json
{ ...full Excalidraw scene JSON... }
```
%%
````

Critical:
- The `## Drawing` block lives **inside** the `%%...%%` Obsidian comment fence
- The code fence is **`json`** (NOT `compressed-json`)
- `Text Elements` lists text labels followed by `^anchor-id` for cross-references — keep it in sync with the `text` elements you put in the JSON

## Scene JSON schema

Top-level shape:

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/tag/2.0.0",
  "elements": [ /* ...all shapes... */ ],
  "appState": { "gridSize": null, "viewBackgroundColor": "#ffffff" },
  "files": {}
}
```

### Rectangle (a box)

```json
{
  "id": "box1",
  "type": "rectangle",
  "x": 100, "y": 100, "width": 140, "height": 70,
  "angle": 0,
  "strokeColor": "#1e1e1e",
  "backgroundColor": "#a5d8ff",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 1,
  "opacity": 100,
  "groupIds": [],
  "frameId": null,
  "roundness": {"type": 3},
  "seed": 100001,
  "version": 1,
  "versionNonce": 100001,
  "isDeleted": false,
  "boundElements": [
    {"type": "text", "id": "text1"},
    {"type": "arrow", "id": "arrow1"}
  ],
  "updated": 1735689600000,
  "link": null,
  "locked": false
}
```

### Text (label inside a box)

`containerId` must match the rectangle's `id`. The rectangle's `boundElements` must reference this text's `id`.

```json
{
  "id": "text1",
  "type": "text",
  "x": 135, "y": 120, "width": 70, "height": 30,
  "angle": 0,
  "strokeColor": "#1e1e1e",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 1,
  "opacity": 100,
  "groupIds": [],
  "frameId": null,
  "roundness": null,
  "seed": 200001,
  "version": 1,
  "versionNonce": 200001,
  "isDeleted": false,
  "boundElements": null,
  "updated": 1735689600000,
  "link": null,
  "locked": false,
  "text": "Usuário",
  "fontSize": 20,
  "fontFamily": 1,
  "textAlign": "center",
  "verticalAlign": "middle",
  "containerId": "box1",
  "originalText": "Usuário",
  "lineHeight": 1.25,
  "baseline": 18
}
```

### Arrow (connection between boxes)

`points` is relative to the arrow's own `(x, y)`. Bind both ends so arrows stick to boxes when moved.

```json
{
  "id": "arrow1",
  "type": "arrow",
  "x": 240, "y": 135, "width": 110, "height": 0,
  "angle": 0,
  "strokeColor": "#1e1e1e",
  "backgroundColor": "transparent",
  "fillStyle": "solid",
  "strokeWidth": 2,
  "strokeStyle": "solid",
  "roughness": 1,
  "opacity": 100,
  "groupIds": [],
  "frameId": null,
  "roundness": {"type": 2},
  "seed": 300001,
  "version": 1,
  "versionNonce": 300001,
  "isDeleted": false,
  "boundElements": null,
  "updated": 1735689600000,
  "link": null,
  "locked": false,
  "points": [[0, 0], [110, 0]],
  "lastCommittedPoint": null,
  "startBinding": {"elementId": "box1", "focus": 0, "gap": 1},
  "endBinding": {"elementId": "box2", "focus": 0, "gap": 1},
  "startArrowhead": null,
  "endArrowhead": "arrow"
}
```

### Other shapes (when needed)

- **Ellipse**: `"type": "ellipse"` — same fields as rectangle
- **Diamond**: `"type": "diamond"` — same fields as rectangle (great for decision nodes)
- **Line**: `"type": "line"` — like arrow but no arrowhead
- **Free text** (no container): omit `containerId`, set `x`/`y` directly

## Layout guidelines

Coordinates are pixels; origin is top-left.

- **Box size:** 140×70 for short labels (≤ 8 chars), scale up ~10px width per extra char
- **Horizontal flow:** boxes 250 px apart on x-axis (140 box + ~110 arrow)
- **Vertical flow:** rows 150 px apart on y-axis
- **Arrow placement:** `arrow.x = box.x + box.width`, `arrow.y = box.y + box.height/2`. Width = `next_box.x - arrow.x`
- **Text inside box:** roughly center it — `text.x = box.x + (box.width - text.width)/2`, `text.y = box.y + (box.height - text.height)/2`. Approximate text width as `len(text) × 11` at fontSize 20.
- **IDs:** use sequential `box1`, `box2`, `text1`, `arrow1`. They just need to be unique within the file.
- **`seed` / `versionNonce`:** any positive integer, but use **distinct values per element** (e.g., 100001, 100002, ...) — repeating seeds causes rendering quirks.

## Color palette

Stick to Excalidraw's default palette so it looks native:

| Color | Hex | Use |
|-------|-----|-----|
| Black | `#1e1e1e` | strokes, default text |
| Blue | `#a5d8ff` | inputs, users |
| Green | `#b2f2bb` | success, services |
| Red/Pink | `#ffc9c9` | errors, datastores |
| Yellow | `#ffec99` | warnings, queues |
| Purple | `#d0bfff` | external services |
| Gray | `#e9ecef` | neutral / infra |
| Transparent | `"transparent"` | text backgrounds, arrows |

## Naming files

- Workflow / flow: `flow-<topic>.excalidraw.md`
- Architecture: `arch-<system>.excalidraw.md`
- Mind map: `mindmap-<topic>.excalidraw.md`
- Sequence / decision tree: `seq-<topic>.excalidraw.md` / `tree-<topic>.excalidraw.md`
- Use `kebab-case`, English

## Procedure

1. **Confirm intent** — if the request is vague ("draw something about X"), ask: how many nodes, what's the flow direction (horizontal/vertical), any decision points?
2. **Sketch coordinates** — assign `(x, y)` per box following layout guidelines
3. **Build elements list** — rectangles first, then their texts, then arrows. Generate unique IDs and seeds.
4. **Wire bindings** — for each box: `boundElements` must list every text and arrow attached to it. For each text: `containerId` must point at its box. For each arrow: `startBinding.elementId` + `endBinding.elementId` must point at the source/target box ids.
5. **Sync `## Text Elements`** — list each text with a `^anchor-id` (any unique slug)
6. **Save** to `/mnt/c/Users/aly/Documents/GitHub/notes/excalidraw/<name>.excalidraw.md`
7. **Report** the path. The user opens it in Obsidian.

## Common mistakes to avoid

- Forgetting `%%...%%` around the `## Drawing` block → plugin ignores it
- Using `compressed-json` fence (we are writing raw JSON) → plugin tries to decompress and fails
- `boundElements` on a box not including its child text/arrow → text floats out, arrow detaches when box moves
- Arrow `points` second pair not matching `width` / `height` → arrow renders short or off-target
- Reusing the same `seed` across many elements → glitchy strokes
- Text `width` too small for the actual string → text overflows. Use `len × 11` rule of thumb at fontSize 20.

## Minimal working example

A 2-box flow "A → B" — paste this scene JSON into the skeleton above to verify:

```json
{
  "type": "excalidraw",
  "version": 2,
  "source": "https://github.com/zsviczian/obsidian-excalidraw-plugin/releases/tag/2.0.0",
  "elements": [
    {"id":"box1","type":"rectangle","x":100,"y":100,"width":140,"height":70,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"#a5d8ff","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"roundness":{"type":3},"seed":1,"version":1,"versionNonce":1,"isDeleted":false,"boundElements":[{"type":"text","id":"t1"},{"type":"arrow","id":"a1"}],"updated":1735689600000,"link":null,"locked":false},
    {"id":"t1","type":"text","x":150,"y":120,"width":40,"height":30,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"roundness":null,"seed":2,"version":1,"versionNonce":2,"isDeleted":false,"boundElements":null,"updated":1735689600000,"link":null,"locked":false,"text":"A","fontSize":20,"fontFamily":1,"textAlign":"center","verticalAlign":"middle","containerId":"box1","originalText":"A","lineHeight":1.25,"baseline":18},
    {"id":"box2","type":"rectangle","x":350,"y":100,"width":140,"height":70,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"#b2f2bb","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"roundness":{"type":3},"seed":3,"version":1,"versionNonce":3,"isDeleted":false,"boundElements":[{"type":"text","id":"t2"},{"type":"arrow","id":"a1"}],"updated":1735689600000,"link":null,"locked":false},
    {"id":"t2","type":"text","x":400,"y":120,"width":40,"height":30,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"roundness":null,"seed":4,"version":1,"versionNonce":4,"isDeleted":false,"boundElements":null,"updated":1735689600000,"link":null,"locked":false,"text":"B","fontSize":20,"fontFamily":1,"textAlign":"center","verticalAlign":"middle","containerId":"box2","originalText":"B","lineHeight":1.25,"baseline":18},
    {"id":"a1","type":"arrow","x":240,"y":135,"width":110,"height":0,"angle":0,"strokeColor":"#1e1e1e","backgroundColor":"transparent","fillStyle":"solid","strokeWidth":2,"strokeStyle":"solid","roughness":1,"opacity":100,"groupIds":[],"frameId":null,"roundness":{"type":2},"seed":5,"version":1,"versionNonce":5,"isDeleted":false,"boundElements":null,"updated":1735689600000,"link":null,"locked":false,"points":[[0,0],[110,0]],"lastCommittedPoint":null,"startBinding":{"elementId":"box1","focus":0,"gap":1},"endBinding":{"elementId":"box2","focus":0,"gap":1},"startArrowhead":null,"endArrowhead":"arrow"}
  ],
  "appState": {"gridSize": null, "viewBackgroundColor": "#ffffff"},
  "files": {}
}
```
