# macvimium

Minimal system-wide Vimium-style navigation for macOS.

## What it does

- Runs as a menu bar app.
- Press `Control` + `Option` + `;` to enter hint mode.
- Scans the frontmost app's accessibility tree for pressable elements.
- Draws short keyboard hints near those elements.
- Type the hint to activate the element.
- Press `Escape` to cancel.

## Requirements

- macOS 14+
- Accessibility permission for the app or built binary

The first time hint mode is triggered, macOS should prompt for Accessibility access. If it does not, add the built binary manually in:

`System Settings -> Privacy & Security -> Accessibility`

## Development

```bash
swift build
swift run
```

This project uses Swift Package Manager and currently builds with the macOS Command Line Tools, so full Xcode is not required.
