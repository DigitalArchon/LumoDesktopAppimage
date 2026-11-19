# Release notes

What each release of this AppImage changes, and how every release differs from Proton's official
Linux packages. Releases are numbered `<Lumo version>-<packaging release>`: `0.5.9-2` is Proton's
Lumo 0.5.9, packaged a second time. The release workflow copies this release's section and the
section on Proton's packages into the GitHub release, so links here are full URLs.

## How it differs from Proton's packages

Proton's code isn't changed. Compared with Proton's own `.deb` and `.rpm` of the same version:

- **Window fixes on Wayland.** tao, the windowing library that comes with Proton's version of
  Tauri (tao 0.35.3), is built with a fix from tao's own developers
  ([tauri-apps/tao#1218](https://github.com/tauri-apps/tao/pull/1218), released in tao 0.36).
  Windows get your desktop's usual title bar instead of tao's own, so the minimize, maximize and
  close buttons work on KDE Plasma and the Ctrl+L quick-ask box no longer opens cut off. On GNOME
  the title bar has a close button only, as GNOME apps do. Proton's packages use the same tao
  0.35.3 without the fix.
- **No in-app updater.** Proton's update server only offers `.deb` and `.rpm`. Update by
  downloading the new release, or with Gear Lever or AppImageUpdate.
- **`proton-lumo://` links** (needed to finish browser sign-in) are registered by the AppImage
  each time it starts, in `~/.local/share/applications/lumo-appimage-url-handler.desktop`, instead
  of by a package install. `LUMO_APPIMAGE_NO_URL_HANDLER=1` turns that off.
- **No crash or error reports** are sent: Proton's reporting key isn't in the source, and this
  build doesn't add one.
- **The same web app**, `https://lumo.proton.me`. It is set at build time, because without it the
  source defaults to a Proton development environment.
- **A spare tray-icon library** (`libayatana-appindicator`) is inside, used only when your system
  has none. Everything else, WebKitGTK included, comes from your system.
- **Proton's `Cargo.lock`** gets two corrections: the app's own version line, where Proton's lock
  lags the app (it says 0.5.8 in 0.5.9; Cargo makes the same change on its own), and tao's entry
  losing its `source` and `checksum` lines, as Cargo records any patched library.

Details: [How it differs from Proton's Linux packages](https://github.com/DigitalArchon/LumoDesktopAppimage#how-it-differs-from-protons-linux-packages)
in the README.

## 0.5.9-2

Lumo itself is unchanged: still Proton's 0.5.9, from the same commit as 0.5.9-1. This release
fixes two bugs seen on KDE Plasma under Wayland:

- **The title-bar buttons work.** Minimize, maximize and close did nothing; you could only resize
  the window by dragging its edges. Close hides Lumo to the tray, as in Proton's build.
- **Ctrl+L quick-ask opens whole.** On screens larger than 1280×800 it could open as a thin
  strip, with its top and bottom cut off.

Both came from tao 0.35.3, the windowing library in Proton's version of Tauri: on Wayland it gives
every window a title bar of its own, which on KDE Plasma takes the clicks meant for the buttons and
squeezes the borderless quick-ask window ([tauri-apps/tauri#13749](https://github.com/tauri-apps/tauri/issues/13749)).
tao's developers fixed it in tao 0.36, which Proton's Tauri version can't use yet, so this build
applies their fix to tao 0.35.3. Proton's own `.deb` and `.rpm` of 0.5.9 use the same tao without
the fix.

On GNOME (Wayland) the window now has GNOME's usual title bar, with a close button only, as other
GNOME apps have, where 0.5.9-1 showed tao's minimize, maximize and close.

Tested with KDE Plasma (CachyOS) and GNOME (Fedora 44), both on Wayland. Ctrl+L doesn't open
quick-ask on GNOME under Wayland, in this release or in 0.5.9-1: Lumo registers it as a
system-wide shortcut, which GNOME's Wayland session doesn't pass to apps.

## 0.5.9-1

First release: Proton's Lumo 0.5.9 as an AppImage.
