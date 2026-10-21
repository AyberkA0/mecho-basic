# Mecho Basic

A tiny macOS menu bar app. Hold **F6** and speak; when you let go, it plays back what you said with an echo.

## Install

```bash
./build.sh install
```

The app is installed to `~/Applications/Mecho Basic.app`, launched, and registered as a login item (you can turn that off from the menu).

On first launch it needs two permissions:
- **Microphone** — to record.
- **Accessibility** — to capture F6 and hide it from the system (System Settings → Privacy & Security → Accessibility).

F6 works both as a standard function key and as the Do Not Disturb (moon) key on Apple keyboards; either way the system action is suppressed.

> The app is ad-hoc signed, so after each rebuild macOS may revoke the Accessibility permission. Remove the app from the Accessibility list and add it again.
