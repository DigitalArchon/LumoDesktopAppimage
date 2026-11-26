#!/bin/bash
# Runs inside the build container (see Containerfile); started by packaging/build-appimage.sh.
#   /src.tar holds upstream/ (Proton's commit, as committed) and packaging/ (this repository's)
#   -> /out/Lumo-<version>-<release>-x86_64.AppImage, its .sha256 and its .zsync
# Inputs are pinned (pins.sh, upstream.env, upstream's package-lock.json and Cargo.lock) and every
# timestamp is SOURCE_DATE_EPOCH, so the same commit of this repository gives the same AppImage,
# byte for byte, on any machine.
set -euo pipefail
umask 022
export LC_ALL=C.UTF-8 TZ=UTC
: "${SOURCE_DATE_EPOCH:?}" "${VERSION:?}"

W=/work
rm -rf "$W" && mkdir -p "$W/in" "$W/AppDir/usr/bin" /cache
tar -xf /src.tar -C "$W/in"
mv "$W/in/upstream" "$W/src"
P="$W/in/packaging/appimage"
# shellcheck source=pins.sh
. "$P/pins.sh"

fetch() {  # url sha256 dest: download once into the cache, always verify
    local url=$1 sum=$2 dest=$3
    if [ ! -f "$dest" ] || ! echo "$sum  $dest" | sha256sum -c --quiet - 2>/dev/null; then
        # https only, redirects included: a hash proves what arrived, not who saw it asked for
        curl --proto '=https' --tlsv1.2 -fsSL --retry 3 -o "$dest.part" "$url"
        echo "$sum  $dest.part" | sha256sum -c --quiet -
        mv "$dest.part" "$dest"
    fi
}
fetch "$RUST_URL" "$RUST_SHA256" /cache/rust.tar.xz
fetch "$NODE_URL" "$NODE_SHA256" /cache/node.tar.xz
fetch "$RUNTIME_URL" "$RUNTIME_SHA256" /cache/runtime-x86_64

# toolchains, unpacked fresh every build (never from the cache's previous state)
mkdir -p "$W/rust-dist" /opt/node
tar -xJf /cache/rust.tar.xz -C "$W/rust-dist" --strip-components=1 --no-same-owner
"$W/rust-dist/install.sh" --prefix=/opt/rust --disable-ldconfig \
    --components=rustc,cargo,rust-std-x86_64-unknown-linux-gnu >/dev/null
tar -xJf /cache/node.tar.xz -C /opt/node --strip-components=1 --no-same-owner
export PATH="/opt/rust/bin:/opt/node/bin:$PATH"
rustc --version && cargo --version && echo "node $(node --version), npm $(npm --version)"

# Downloads, kept between builds: crates are checked against Cargo.lock's checksums and npm
# packages against package-lock.json's integrity hashes whether they come from the cache or not.
export CARGO_HOME=/cache/cargo npm_config_cache=/cache/npm
export npm_config_update_notifier=false npm_config_fund=false npm_config_audit=false
cd "$W/src"
# no install scripts: nothing in the lock needs one (esbuild and the Tauri CLI find their
# native binaries through optionalDependencies)
npm ci --ignore-scripts --no-progress

# The build paths are mapped out of everything compiled: Rust's panic locations name source
# files, and aws-lc's C code is built with __FILE__ in its assertions.
export RUSTFLAGS="--remap-path-prefix=$W/src=/build --remap-path-prefix=$CARGO_HOME=/cargo --remap-path-prefix=/opt/rust=/rust"
export CFLAGS="-ffile-prefix-map=$W/src=/build -ffile-prefix-map=$CARGO_HOME=/cargo"
export CXXFLAGS="$CFLAGS"
export CARGO_INCREMENTAL=0 CARGO_TERM_PROGRESS_WHEN=never
# Compiled in (option_env!): the production web app instead of Proton's development one. No
# Sentry DSN is set, so crash reporting stays off. The updater is given no endpoint
# (tauri.appimage.json): Proton's manifest offers .deb and .rpm only, and an AppImage must not
# take one of those for an update of itself.
export LUMO_URL
# Upstream's Cargo.lock can lag the app's own version (0.5.9 shipped with "lumo" at 0.5.8 in
# it). That entry, and only that one, is set to Cargo.toml's version; --locked still refuses
# any other difference between the lock and the manifests.
crate_version="$(sed -n 's/^version = "\(.*\)"$/\1/p' src-tauri/Cargo.toml | head -1)"
sed -i "/^name = \"lumo\"\$/{n;s/^version = \".*\"\$/version = \"$crate_version\"/}" src-tauri/Cargo.lock
grep -A1 -x 'name = "lumo"' src-tauri/Cargo.lock | grep -qx "version = \"$crate_version\""

# tao, the windowing library of Proton's Tauri, put its own title bar on a window under Wayland
# up to 0.35, and that bar's minimize, maximize and close buttons never got the click
# (tauri-apps/tauri#13749); the borderless quick-ask window got one too, which squeezed it to a
# strip. tao 0.36 fixed it (tauri-apps/tao#1218). 0.5.9-2 patched Proton's tao 0.35.3 with that
# commit; from 0.5.10 Proton's lock has a tao with the fix, built as it is. The build stops if
# the lock ever names an older one.
tao_version="$(grep -A1 -x 'name = "tao"' src-tauri/Cargo.lock | sed -n 's/^version = "\(.*\)"$/\1/p')"
if [[ ! "$tao_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
   || [ "$(printf '%s\n' 0.36.0 "$tao_version" | sort -V | head -1)" != 0.36.0 ]; then
    echo "Proton's Cargo.lock has tao '${tao_version}', not one tao of 0.36.0 or newer: windows" \
         "would lose their working title bar on Wayland (tauri-apps/tao#1218)." >&2
    exit 1
fi

# The webview bundles, built here rather than by Tauri (tauri.appimage.json empties its
# beforeBuildCommand, whose other step, scripts/build-tools-helper.mjs, builds a macOS helper
# and does nothing on Linux). tauri-codegen walks this folder in the order the file system lists it,
# unsorted, and compiles each script's CSP hash into the binary in that order. ext4 lists a
# folder in a hash order seeded per file system, so one commit gave one binary on MintDev and
# another on p330-2 (Nov 2026: the same 13 hashes, reordered). So the folder is copied into a
# tmpfs (/distfs, a mount of build-appimage.sh's), which lists a folder in the order its
# entries were made: oldest first or newest first, depending on the kernel (newest first on
# 7.0). A probe finds which, each folder's entries are made in the order that lists them
# sorted, and every folder is checked to list sorted before Tauri reads it, so Tauri walks
# the same order on any kernel; one that does neither fails the build instead.
npm run build:webview
mkdir /distfs/probe && touch /distfs/probe/a /distfs/probe/b
case "$(ls -f /distfs/probe | grep -v '^\.\.\?$' | tr -d '\n')" in
    ab) order="" ;;          # oldest first: make entries in sorted order
    ba) order="-r" ;;        # newest first: make them in reverse sorted order
    *) echo "tmpfs lists a folder in neither creation order; the build can't be made reproducible here" >&2; exit 1 ;;
esac
rm -rf /distfs/probe
fill_sorted() {  # src dst: dst (empty) gets src's entries, made in the order tmpfs lists sorted;
                 # then each subfolder is filled in turn, which leaves its parent's order alone
    local src=$1 dst=$2 name
    while IFS= read -r name; do
        if [ -d "$src/$name" ]; then mkdir "$dst/$name"; else cp "$src/$name" "$dst/$name"; fi
    done < <(ls -A "$src" | LC_ALL=C sort $order)
    while IFS= read -r name; do
        fill_sorted "$src/$name" "$dst/$name"
    done < <(find "$src" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | LC_ALL=C sort)
}
mkdir /distfs/dist
fill_sorted src-tauri/dist /distfs/dist
while IFS= read -r dir; do
    if [ "$(ls -f "$dir" | grep -v '^\.\.\?$')" != "$(ls -A "$dir" | LC_ALL=C sort)" ]; then
        echo "$dir doesn't list sorted; the build can't be made reproducible here" >&2
        exit 1
    fi
done < <(find /distfs/dist -type d)
rm -rf src-tauri/dist
ln -s /distfs/dist src-tauri/dist
npx --no-install tauri build --no-bundle --ci --config "$P/tauri.appimage.json" -- --locked
BIN="$W/src/src-tauri/target/release/lumo-desktop"

# AppDir layout (AppImage spec): entry point, desktop entry, icon
install -m 755 "$BIN" "$W/AppDir/usr/bin/lumo-desktop"
install -m 755 "$P/AppRun" "$W/AppDir/AppRun"
install -m 644 "$P/lumo.desktop" "$W/AppDir/lumo.desktop"
install -m 644 src-tauri/icons/128x128@2x.png "$W/AppDir/lumo.png"
ln -s lumo.png "$W/AppDir/.DirIcon"
install -D -m 644 src-tauri/icons/128x128@2x.png "$W/AppDir/usr/share/icons/hicolor/256x256/apps/lumo.png"
install -D -m 644 src-tauri/icons/128x128.png "$W/AppDir/usr/share/icons/hicolor/128x128/apps/lumo.png"
install -D -m 644 src-tauri/icons/32x32.png "$W/AppDir/usr/share/icons/hicolor/32x32/apps/lumo.png"
sed -i "s/@VERSION@/$VERSION/" "$W/AppDir/lumo.desktop"
grep -qx "X-AppImage-Version=$VERSION" "$W/AppDir/lumo.desktop"
install -d "$W/AppDir/usr/share/applications"
ln -s ../../../lumo.desktop "$W/AppDir/usr/share/applications/lumo.desktop"
desktop-file-validate "$W/AppDir/lumo.desktop"

# The tray icon's library, for hosts without one. Tauri's tray (libappindicator-sys) dlopens
# libayatana-appindicator3.so.1 or libappindicator3.so.1 when it starts and the app aborts if
# neither loads; KDE and GNOME installs often have neither. AppRun puts this directory on the
# library path only when the host lacks both. GTK, GLib and D-Bus always come from the host.
FB="$W/AppDir/usr/lib/fallback"
mkdir -p "$FB"
for lib in libayatana-appindicator3.so.1 libayatana-indicator3.so.7 libayatana-ido3-0.4.so.0 \
           libdbusmenu-glib.so.4 libdbusmenu-gtk3.so.4; do
    install -m 644 "$(readlink -f "/usr/lib/x86_64-linux-gnu/$lib")" "$FB/$lib"
done
# their licences (LGPL/GPL), as the packages ship them
for pkg in libayatana-appindicator3-1 libayatana-indicator3-7 libayatana-ido3-0.4-0 \
           libdbusmenu-glib4 libdbusmenu-gtk3-4; do
    install -D -m 644 "/usr/share/doc/$pkg/copyright" "$W/AppDir/usr/share/doc/$pkg/copyright"
done
install -D -m 644 LICENSE "$W/AppDir/usr/share/doc/lumo-desktop/LICENSE"

# What the binary links: everything must be a system library the AppImage expects of the host.
echo "lumo-desktop needs:"; readelf -d "$BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/  \1/p'
unexpected="$(readelf -d "$BIN" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p' | grep -v -E \
    '^lib(c|m|gcc_s|dl|pthread|rt|webkit2gtk-4\.1|javascriptcoregtk-4\.1|soup-3\.0|gtk-3|gdk-3|gdk_pixbuf-2\.0|cairo|cairo-gobject|pango-1\.0|pangocairo-1\.0|atk-1\.0|harfbuzz|gio-2\.0|gobject-2\.0|glib-2\.0|dbus-1)\.so\.[0-9]+$' || true)"
if [ -n "$unexpected" ]; then
    echo "lumo-desktop links libraries the AppImage doesn't account for:" >&2
    echo "$unexpected" >&2
    exit 1
fi

# Nothing in the image may name the folders it was built in.
if named="$(grep -rlaF -e "$W/" -e "$CARGO_HOME" -e /opt/rust -e /opt/node -e /distfs "$W/AppDir")"; then
    echo "These name a build folder:" >&2
    echo "$named" >&2
    exit 1
fi

chmod -R u+rwX,go+rX,go-w "$W/AppDir"
find "$W/AppDir" -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
# (mksquashfs takes every timestamp from SOURCE_DATE_EPOCH by itself)
mksquashfs "$W/AppDir" "$W/app.squashfs" -quiet -noappend -root-owned -no-xattrs \
    -comp zstd -Xcompression-level 19 -b 1M

NAME="Lumo-$VERSION-x86_64.AppImage"
# Update information, in the runtime's .upd_info section, where AppImageUpdate, Gear Lever and
# AppImageLauncher read it: the latest GitHub release's .zsync, made below, from which an updater
# fetches only the blocks that changed and checks the result against the SHA-1 the .zsync
# carries. (DA Privacy Kit's build.sh, ported to shell: this image has no Python.)
cp /cache/runtime-x86_64 "$W/runtime"
info="gh-releases-zsync|$GITHUB_OWNER|$GITHUB_REPO|latest|Lumo-*-x86_64.AppImage.zsync"
read -r off size < <(readelf -SW "$W/runtime" \
    | sed -n 's/.*\.upd_info *PROGBITS *[0-9a-f]* *\([0-9a-f]*\) *\([0-9a-f]*\).*/\1 \2/p')
[ -n "${off:-}" ] || { echo "the runtime has no .upd_info section" >&2; exit 1; }
off=$((16#$off)) size=$((16#$size))
[ "${#info}" -lt "$size" ] || { echo "update information too long for .upd_info" >&2; exit 1; }
[ "$(dd if="$W/runtime" bs=1 skip="$off" count="$size" status=none | tr -d '\0' | wc -c)" = 0 ] \
    || { echo "the runtime's .upd_info isn't empty" >&2; exit 1; }
printf '%s' "$info" | dd of="$W/runtime" bs=1 seek="$off" conv=notrunc status=none
cat "$W/runtime" "$W/app.squashfs" > "/out/$NAME"
chmod 755 "/out/$NAME"
# zsyncmake writes the file's modification time into the .zsync (MTime): the commit's, like
# everything else. The URL is the file's name, relative to the .zsync's (the release page).
touch -d "@$SOURCE_DATE_EPOCH" "/out/$NAME"
(cd /out && rm -f "$NAME.zsync" && zsyncmake -u "$NAME" -o "$NAME.zsync" "$NAME" >/dev/null)
(cd /out && sha256sum "$NAME" > "$NAME.sha256" && cat "$NAME.sha256")
