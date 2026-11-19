# Lumo Desktop AppImage (unofficial)

An AppImage of [Lumo Desktop](https://github.com/ProtonLumo/lumo-desktop), Proton's desktop app
for its Lumo AI assistant, for the Linux distributions Proton doesn't package it for: Arch,
CachyOS, Manjaro, openSUSE, and anything else that isn't served by Proton's `.deb` and `.rpm`.

It's built from Proton's published source **with no changes to Proton's code**, by a build
anyone can repeat and get the same file, byte for byte. It's also built to work properly outside
Proton's packages. If you only put Lumo's files into an AppImage, sign-in, the window buttons
and more break on many systems. This one fixes each of those problems (below).

> **Unofficial.** This project isn't affiliated with, sponsored or endorsed by Proton AG.
> "Proton" and "Lumo" are trademarks of Proton AG. Report problems with Lumo itself to
> [Proton](https://github.com/ProtonLumo/lumo-desktop), and problems with the AppImage here.

## What it fixes

If another Lumo AppImage won't finish signing in, its window buttons do nothing, or it opens a
blank window, these are the usual causes. This AppImage fixes all of them:

**Since 0.5.9-2**

- **The title-bar buttons work on Wayland.** The windowing library in Proton's version of Tauri
  (tao 0.35) draws its own title bar on Wayland. On KDE Plasma that title bar's minimize,
  maximize and close buttons never get the click, so the window can only be resized from its
  edges. Proton's own `.deb` and `.rpm` use the same tao. This build applies tao's own fix,
  from tao 0.36, so your desktop draws its usual title bar.
- **Ctrl+L quick-ask opens whole.** The same bug squeezes the quick-ask box into a thin strip
  with its top and bottom cut off, on screens larger than 1280×800. The same fix stops it.

**Since 0.5.9-1**

- **Browser sign-in finishes.** Sign-in happens in your browser, which hands the session back
  through a `proton-lumo://` link. Proton's packages register that link type when they're
  installed. An AppImage isn't installed, so without help the browser has nowhere to send the
  link and the app never signs in. This AppImage registers itself each time it starts, wherever
  you've put it, so moving the file doesn't break sign-in.
- **No blank window on Arch-based systems.** It uses your system's WebKitGTK instead of a
  bundled copy. WebKitGTK has to match your graphics drivers, which a bundled copy often doesn't.
  Using the system copy also gets you your distribution's security fixes for the engine that
  renders a web app.
- **It starts on desktops without a tray library.** Lumo won't start without
  a tray-icon library (`libayatana-appindicator`), and not every system has one installed. A
  spare copy is inside, used only when your system has none.
- **It loads the real Lumo.** Built from Proton's source with nothing set, the app loads
  `lumo.proton.dev`, a Proton development environment. This build sets
  `https://lumo.proton.me`, as Proton's packages do.
- **Updates that work.** Proton's update server only offers `.deb` and `.rpm`, so the in-app
  updater is off. Gear Lever and AppImageUpdate update the AppImage from this repository's
  releases instead (below).

None of these fixes changes Proton's code. They're build settings, a startup step in the
AppImage, and a patch from tao's own developers, all listed in
[How it differs](#how-it-differs-from-protons-linux-packages). [`RELEASE-NOTES.md`](RELEASE-NOTES.md)
has the details for each release.

## Using it

1. Download `Lumo-<version>-x86_64.AppImage` from [Releases](../../releases).
2. Make it executable and run it:
   ```sh
   chmod +x Lumo-*-x86_64.AppImage
   ./Lumo-*-x86_64.AppImage
   ```
3. Click **Sign in with your browser**. Proton's sign-in page opens in your browser, and the
   browser hands the session back to the app.

The AppImage uses your system's **WebKitGTK 4.1** to draw its window. Most desktops have it.
If yours doesn't, install it:

| Distribution | Command |
|---|---|
| Arch, CachyOS, Manjaro | `sudo pacman -S webkit2gtk-4.1` |
| Fedora | `sudo dnf install webkit2gtk4.1` |
| openSUSE | `sudo zypper install libwebkit2gtk-4_1-0` |
| Ubuntu 24.04+, Debian 13+ | `sudo apt install libwebkit2gtk-4.1-0` |

You also need glibc 2.39 or newer (any distribution from 2024 on), and a keyring service for
saved credentials: KWallet on KDE, GNOME Keyring on GNOME. Both are usually already running.

**Updates.** Lumo's built-in updater is switched off in this build, because Proton's update
server only offers `.deb` and `.rpm` packages. To update, download the new release, or use
[Gear Lever](https://github.com/mijorus/gearlever) or AppImageUpdate. The AppImage tells them
where its releases are. AppImageUpdate downloads only the parts that changed.

### What it does to your system

To finish browser sign-in, the app has to receive `proton-lumo://` links. Proton's `.deb` and
`.rpm` register that when they're installed; an AppImage isn't installed, so it registers itself
each time it starts. It writes `~/.local/share/applications/lumo-appimage-url-handler.desktop`,
pointing at wherever the AppImage is now, and makes that the handler for `proton-lumo://`. Set
`LUMO_APPIMAGE_NO_URL_HANDLER=1` to stop it, and delete the file to remove it.

Lumo keeps its data where Proton's build does: settings in `~/.config/me.proton.lumo-app/`,
web data and logs in `~/.local/share/me.proton.lumo-app/`, and secrets in your keyring.

## How it differs from Proton's Linux packages

Proton's code isn't changed. Four things are set differently when it's built, all through the
build's own settings rather than by editing Proton's files, and one library Proton's code uses,
tao, gets a bug fix from tao's own developers (the last row). (The build does correct Proton's
`Cargo.lock`, the lockfile, to match; see [the reproducible build](#the-reproducible-build).)

| | Proton's `.deb`/`.rpm` | This AppImage |
|---|---|---|
| Web app the window loads | `https://lumo.proton.me` | The same. It has to be set at build time: without it, the source defaults to `lumo.proton.dev`, a Proton development environment |
| In-app updater | Proton's update server | Off (no update address) |
| `proton-lumo://` links | Registered by the package | Registered by the AppImage when it starts (above) |
| Crash and error reports | Sent to Proton when its build includes Proton's reporting key (there's no setting for it) | Off: the key isn't in the source, and this build doesn't add one |
| Windows on Wayland | tao 0.35, the windowing library that comes with Proton's version of Tauri, draws its own title bar there, always with minimize, maximize and close. On KDE Plasma those buttons never get the click, and the Ctrl+L quick-ask box can open as a thin strip with its top and bottom cut off | tao's own fix, released in tao 0.36, is applied to the tao 0.35.3 Proton's build uses (below). The buttons and quick-ask work, and the title bar is your desktop's usual one: on GNOME that means a close button only, as in other GNOME apps |

The AppImage contains the Lumo program and a spare copy of the tray-icon library
(`libayatana-appindicator`), used only when your system has none. Without one, Lumo can't start.
Everything else comes from your system. WebKitGTK is deliberately **not** bundled. It renders a
web app from the internet, so it should get your distribution's security updates. A bundled copy
would also have to match your graphics drivers, which is why bundled-WebKit AppImages often show
a blank window on Arch-based systems.

## Why a separate repository, not a fork

A fork would carry Proton's whole source tree and history, and every Lumo release would mean
merging it into the packaging, or rebasing the packaging onto it, in public. This repository
holds only the packaging:

- [`packaging/upstream.env`](packaging/upstream.env) names Proton's repository, the exact commit
  to build, and its version. The build fetches that commit by its id and checks the version.
- [`packaging/`](packaging/) holds the build: the build environment, the pinned toolchains, and
  the four settings above. That's everything that differs from Proton's build, in one place you
  can read.
- A new Lumo release is a one-line change to `upstream.env`, so the history shows exactly which
  Proton commit each release was built from.

It also keeps the line clear for anyone landing here: this isn't Proton's repository, and
nothing of Proton's code is changed in it.

## How releases are made

1. **Every day**, a workflow ([`upstream-watch.yml`](.github/workflows/upstream-watch.yml))
   checks Proton's repository. When there's a new version, it updates `upstream.env`, tags the
   commit `v<version>-1`, and starts the release workflow.
2. **The release workflow** ([`release.yml`](.github/workflows/release.yml)) builds the AppImage
   with the same script you can run yourself. It records a signed GitHub
   [attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations)
   that this workflow built these bytes from this commit, and opens a **draft** release.
3. **The maintainer** builds the same tag on their own machine, checks the checksums match, and
   only then publishes the draft. A release isn't published on GitHub's word alone.

A fix to the packaging itself gets the next number: `v0.5.9-2`, `v0.5.9-3`, and so on. Lumo's
own version stays Proton's. [`RELEASE-NOTES.md`](RELEASE-NOTES.md) says what each release changes
and how every release differs from Proton's packages. The release workflow puts both into the
release's notes, after Proton's own changelog for that version.

## Checking a download

Every release lists the AppImage's SHA-256. There are three ways to check a download, from
quickest to most thorough:

```sh
# the file isn't damaged
sha256sum -c Lumo-<version>-x86_64.AppImage.sha256

# GitHub's workflow built it from this repository (needs GitHub CLI 2.49 or newer)
gh attestation verify Lumo-<version>-x86_64.AppImage --repo DigitalArchon/LumoDesktopAppimage

# it is what the source builds to: rebuild it yourself and compare
git clone https://github.com/DigitalArchon/LumoDesktopAppimage
cd LumoDesktopAppimage
git checkout v<version>
packaging/build-appimage.sh build
cat dist/Lumo-<version>-x86_64.AppImage.sha256
```

## The reproducible build

The same commit of this repository gives the same AppImage on any machine, byte for byte. That
lets anyone check a release against the source without trusting GitHub, Proton's servers or the
maintainer. What makes it so:

- **Everything downloaded is pinned** in [`packaging/appimage/pins.sh`](packaging/appimage/pins.sh):
  - the Ubuntu 24.04 build environment, by digest;
  - its packages, from a dated [snapshot](https://snapshot.ubuntu.com) of Ubuntu's archive;
  - Rust (1.99.0), Node.js (22.23.4) and the AppImage runtime, by SHA-256.

  Proton's commit is pinned by its id. Its npm packages and Rust crates are checked against the
  hashes in the lockfiles Proton commits. Each download is checked against a pinned hash, or for
  Ubuntu's packages the archive's signatures, so a download that changed would stop the build
  rather than change the AppImage.
- **It builds in a container** (rootless Podman), from the committed files only. The build
  refuses to run while anything in `packaging/` differs from the commit.
- **Time and place are taken out.** Every timestamp the build writes is the commit's time
  (`SOURCE_DATE_EPOCH`): the files in the AppImage, its file system, and the `.zsync`. The folders the build ran in are mapped out of the
  compiled program (Rust's `--remap-path-prefix`, the C compiler's `-ffile-prefix-map`), and the
  build fails if a build folder still shows up anywhere in the AppImage.
- **File order is fixed.** The AppImage's file system is packed in sorted order with fixed
  owners. One less obvious case: Tauri compiles a list of the app's script hashes into the
  program, in whatever order the disk lists the files. ext4 orders each folder differently on
  each machine, so the same commit used to give a different program on different computers. The
  build now puts those files in a tmpfs, which lists files in the order they were created (oldest
  or newest first, depending on the kernel). It works out which, creates the files so every folder
  lists in sorted order, checks that they do, and fails on a kernel where they don't.
- **Three upstream quirks are handled:**
  - Proton's `Cargo.lock` for 0.5.9 still records the app itself as 0.5.8. The build changes
    that one line to 0.5.9, which is what Cargo does on its own in a normal build. Proton's
    build tool runs Cargo without `--locked`, so Proton's own 0.5.9 build should have made the
    same change. This build runs Cargo with `--locked`, which forbids any other change to the
    lockfile, so every other mismatch still stops the build. Nothing is compiled from that line:
    the version built in comes from `Cargo.toml`.
  - The app's own default web address is Proton's development environment, so the production
    one is set (above).
  - On Wayland, tao 0.35.3 (the windowing library of Proton's Tauri 2.11) gives windows a title
    bar of its own, whose buttons never get a click on KDE Plasma ([tauri-apps/tauri#13749](https://github.com/tauri-apps/tauri/issues/13749)),
    and gives the undecorated quick-ask window one too, which can squeeze it to a thin strip.
    tao fixed that in 0.36 ([tauri-apps/tao#1218](https://github.com/tauri-apps/tao/pull/1218)),
    which Tauri 2.11 can't use. The build applies that commit, exactly as tao published it
    ([`packaging/appimage/patches/`](packaging/appimage/patches/)), to tao 0.35.3, after
    checking the download against the checksum in Proton's `Cargo.lock`. Cargo builds the patched
    copy in its place, through a `[patch]` given on Cargo's command line, not written into
    Proton's files. In the lockfile, tao's entry loses its `source` and `checksum` lines, as
    Cargo records any patched crate. With the version line above, those are the only changes
    this build makes to Proton's files. If Proton's lockfile moves to another tao, the build
    stops, so the patch is dropped once Proton's Tauri brings tao 0.36.

To check reproducibility yourself, `packaging/build-appimage.sh check` builds twice from scratch
and compares. A difference that depends on the machine only shows up when you compare builds from
**two different** machines, which is why releases are compared that way before they're published.

## Building it yourself

You need Linux with rootless Podman, git, GNU tar, Python 3 and internet access. The first build
downloads about 1 GB (build environment, toolchains, crates) and needs about 3 GB of disk.
Later builds reuse the downloads in `~/.cache/lumo-appimage` and take a few minutes.

```sh
packaging/build-appimage.sh build    # -> dist/Lumo-<version>-x86_64.AppImage, .sha256, .zsync
packaging/build-appimage.sh check    # build twice, compare
```

## Licence

Lumo Desktop is licensed by Proton AG under the [GNU GPL v3.0](https://github.com/ProtonLumo/lumo-desktop/blob/master/LICENSE),
and so is this packaging ([LICENSE](LICENSE)). The source of each release is the Proton commit
its `upstream.env` names, plus this repository at the release's tag. The bundled tray libraries
are LGPL/GPL; their copyright files are inside the AppImage under `usr/share/doc/`.
