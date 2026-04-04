# macvimium

https://github.com/user-attachments/assets/23980e1f-2a32-4e9f-add1-776e7e3c1914

Vimium-style navigation for macOS.

## Quick Start

```bash
git clone https://github.com/RohanAdwankar/macvimium
cd macvimium
swift build
swift run
```

## What it does

- Runs as a menu bar app.
- Press `Option` + `Command` + `F` to enter hint mode.
- Scans the frontmost app's accessibility tree for pressable elements.
- Draws short keyboard hints near those elements.
- Type the full hint label shown on screen to activate the element.
- Press `Escape` to cancel.

## Requirements

- macOS 14+
- Accessibility permission for the app or built binary

The first time hint mode is triggered, macOS should prompt for Accessibility access. If it does not, add the built binary manually in:

`System Settings -> Privacy & Security -> Accessibility`
