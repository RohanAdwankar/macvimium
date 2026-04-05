---
name: maclick-automation
description: Use when an agent needs to inspect, click, or drag controls in macOS apps from this repository by using the maclick CLI. Covers opening apps, listing hint labels, activating targets, dragging between targets, and pairing commands with screenshots for visual verification.
---

# maclick automation

Use `maclick` for deterministic macOS UI control from this repo.

## Commands

Install path wrapper once:

```bash
maclick --help
```

Open an app:

```bash
maclick open Chess.app
```

List actionable hints for a running app:

```bash
maclick Chess --help
```

Capture the selected window with hint overlays:

```bash
maclick Chess screenshot /tmp/chess-hints.png
```

Recenter an off-screen window:

```bash
maclick Chess --recenter
```

Click a hint:

```bash
maclick Calculator I
```

Drag from one hint to another:

```bash
maclick Chess AN to SE
```

## Workflow

1. Open the app with `maclick open ...` if it is not already running.
2. Inspect with `maclick <window> --help` and read the semantic labels.
3. Recenter with `maclick <window> --recenter` if the window is off-screen or awkwardly placed.
4. Capture `maclick <window> screenshot ...` when you need pixel-grounded confirmation.
5. Click with `maclick <window> <hint>`.
6. Drag with `maclick <window> <from> to <to>`.

## Tips

- The first argument is a window query. It can be an app name like `Chess` or `Calculator`, or part of the visible window title.
- Match hints exactly, but case does not matter.
- Re-run `--help` after each meaningful UI change because hints may be reassigned.
- Hints are generated from the selected window subtree, not the whole app process. That avoids mixing controls from unrelated windows or sheets.
- `screenshot` writes a PNG of the selected window with the current hint labels rendered on top.
- Use drag for true pointer drags. For square-grid apps and similar controls, two explicit clicks can be more reliable than a drag.
