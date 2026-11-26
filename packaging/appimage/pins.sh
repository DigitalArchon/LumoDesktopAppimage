# Everything the AppImage build downloads, pinned. Change these deliberately: a new value means
# a different AppImage. (Sourced by build-appimage.sh on the host and build.sh in the container.)
# Versions are picked at least two weeks old, as the repo's own .npmrc (min-release-age) does.

# Ubuntu 24.04 base image, by digest. Its glibc (2.39) is the oldest the AppImage runs on, and
# the WebKitGTK 4.1 headers it builds against are the oldest WebKitGTK it accepts at run time.
BASE_IMAGE="docker.io/library/ubuntu:24.04@sha256:008173c23f95b170204355c12626cb5a965d779a7e1283b09e9cffbb1bf33ca3"
# build tools and -dev packages come from the Ubuntu archive as it was at this moment
APT_SNAPSHOT="20261022T000000Z"

# Rust, the standalone installer (rustc, cargo, std); hash from channel-rust-1.99.0.toml
RUST_URL="https://static.rust-lang.org/dist/2026-10-01/rust-1.99.0-x86_64-unknown-linux-gnu.tar.xz"
RUST_SHA256="891c6366d7100feda0bca4c03ce63f3c9ac827cbebbc283e7433061d42c6a376"

# Node.js 22 (the README's version), for npm ci and the webview bundles; hash from SHASUMS256.txt
NODE_URL="https://nodejs.org/dist/v22.23.4/node-v22.23.4-linux-x64.tar.xz"
NODE_SHA256="1805bcd35e6815559bd2eb97db438d3fdb0eb3a5e6a977b7c1badca76337e9ce"

# AppImage type 2 runtime, static (no libfuse2 needed on the host)
RUNTIME_URL="https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64"
RUNTIME_SHA256="2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"

# Where releases are published: the AppImage's update information names this repository's
# latest GitHub release, for AppImageUpdate, Gear Lever and AppImageLauncher.
GITHUB_OWNER="DigitalArchon"
GITHUB_REPO="LumoDesktopAppimage"

# The web app the window loads. Upstream's default, with nothing set, is Proton's internal
# development environment (src-tauri/src/lib.rs).
LUMO_URL="https://lumo.proton.me"
