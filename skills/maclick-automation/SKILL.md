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
3. Click with `maclick <app> <hint>`.
4. Drag with `maclick <app> <from> to <to>`.
5. When state matters, take a screenshot after actions:

```bash
screencapture /tmp/maclick-check.png
```

## Tips

- The `<app>` argument is usually the app name, for example `Chess`, `Calculator`, or `Terminal`.
- Match hints exactly, but case does not matter.
- Re-run `--help` after each meaningful UI change because hints may be reassigned.
- For board games and canvases, prefer drag commands over repeated clicks.
- If a control is visually present but hard to activate through Accessibility alone, `maclick` already falls back to a real HID mouse click for button-like targets.
