---
name: maclick-automation
description: Use when an agent needs to inspect, click, or drag controls in macOS apps from this repository by using the maclick CLI. Covers opening apps, listing hint labels, activating targets, dragging between targets, and pairing commands with screenshots for visual verification.
---

# maclick automation

Use `maclick` for deterministic macOS UI control from this repo.

## Commands

Build first if needed:

```bash
swift build
```

Open an app:

```bash
./.build/debug/maclick open Chess.app
```

List actionable hints for a running app:

```bash
./.build/debug/maclick Chess --help
```

Recenter an off-screen window:

```bash
./.build/debug/maclick Chess --recenter
```

Click a hint:

```bash
./.build/debug/maclick Calculator I
```

Drag from one hint to another:

```bash
./.build/debug/maclick Chess AN to SE
```

## Workflow

1. Open the app with `maclick open ...` if it is not already running.
2. Inspect with `maclick <app> --help` and read the semantic labels.
3. Recenter with `maclick <app> --recenter` if the window is off-screen or awkwardly placed.
4. Click with `maclick <app> <hint>`.
5. Drag with `maclick <app> <from> to <to>`.
6. When state matters, take a screenshot after actions:

```bash
screencapture -C /tmp/maclick-check.png
```

## Tips

- The `<app>` argument is usually the app name, for example `Chess`, `Calculator`, or `Terminal`.
- Match hints exactly, but case does not matter.
- Re-run `--help` after each meaningful UI change because hints may be reassigned.
- For apps that expose real AX actions, `maclick` prefers semantic activation over raw mouse input. Chess works best through this path.
- For generic canvases and custom controls, `maclick` falls back to real HID mouse movement and dragging.
- If a control is visually present but hard to activate through Accessibility alone, `maclick` already falls back to a real HID mouse click for button-like targets.
