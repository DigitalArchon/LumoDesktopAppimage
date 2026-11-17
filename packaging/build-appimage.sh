#!/bin/bash
# Build the Lumo AppImage reproducibly with rootless Podman (see README.md).
#   packaging/build-appimage.sh build   AppImage of HEAD -> dist/
#   packaging/build-appimage.sh check   build HEAD twice from scratch and compare the hashes
# DIST=dir puts the results somewhere other than dist/.
# What is built: the upstream commit packaging/upstream.env pins, fetched from Proton's repository,
# with this repository's packaging/ as committed at HEAD. SOURCE_DATE_EPOCH is HEAD's commit
# time. With anything in packaging/ changed since HEAD, nothing is built, and the changed files
# are named.
# This machine needs rootless Podman, git, GNU tar and python3, and https access to GitHub.
set -euo pipefail

missing_host_tools() {  # -> a line for each this machine lacks
    command -v git >/dev/null || echo "git"
    command -v podman >/dev/null || echo "Podman, rootless: sudo apt install podman (or dnf/pacman)"
    command -v python3 >/dev/null || echo "python3 (reads the version from tauri.conf.json)"
    case "$(tar --version 2>/dev/null || true)" in
        *"GNU tar"*) ;;
        *) echo "GNU tar (bsdtar and BusyBox's tar have no --sort=name)" ;;
    esac
}
missing="$(missing_host_tools)"
if [ -n "$missing" ]; then
    echo "Nothing built. $0 needs these, which this machine lacks:" >&2
    while IFS= read -r line; do echo "  $line" >&2; done <<< "$missing"
    exit 1
fi

mode="${1:-build}"
case "$mode" in
    build|check) ;;
    *) echo "usage: $0 build|check" >&2; exit 2 ;;
esac
top="$(git rev-parse --show-toplevel)"
cd "$top"

# The build's definition, everything in packaging/ (this script, the pins, the upstream commit),
# must be HEAD's, byte for byte: this script reads the Containerfile and pins from the working
# tree to make the builder image, so a changed one would otherwise go into a build said to be HEAD's.
changed_definition() {  # -> the files in packaging/ that are not as HEAD has them
    local entry oid path
    git ls-tree -r -z HEAD -- packaging | while IFS= read -r -d '' entry; do
        oid="${entry%%$'\t'*}"
        oid="${oid##* }"
        path="${entry#*$'\t'}"
        if [ ! -f "$path" ] || [ "$(git hash-object --no-filters -- "$path")" != "$oid" ]; then
            printf '%s\n' "$path"
        fi
    done
    git ls-files --others --exclude-standard -- packaging
}
changed="$(changed_definition)"
if [ -n "$changed" ]; then
    echo "Nothing built. The build is defined by the commit it builds, HEAD ($(git rev-parse --short HEAD))," \
         "and these are not as committed there:" >&2
    while IFS= read -r line; do echo "  $line" >&2; done <<< "$changed"
    echo "Commit the changes, or put them aside (git stash), and build again." >&2
    exit 1
fi
. packaging/appimage/pins.sh
. packaging/upstream.env

case "$UPSTREAM_REPO" in
    https://*) ;;
    *) echo "UPSTREAM_REPO must be an https:// URL, not $UPSTREAM_REPO" >&2; exit 1 ;;
esac
[[ "$UPSTREAM_COMMIT" =~ ^[0-9a-f]{40}$ ]] || { echo "UPSTREAM_COMMIT must be a full commit id" >&2; exit 1; }
[[ "$RELEASE" =~ ^[1-9][0-9]*$ ]] || { echo "RELEASE must be a number from 1" >&2; exit 1; }

# The host's CA bundle, for apt in the builder to reach the package snapshot over https. Only
# the builder image is made with it; apt checks what it fetches by signature.
CA_BUNDLES=(/etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt
            /etc/ssl/ca-bundle.pem /etc/pki/tls/cert.pem /etc/ssl/cert.pem)
host_ca_bundle() {
    local ca
    for ca in "$@"; do
        if [ -f "$ca" ]; then
            printf '%s\n' "$ca"
            return 0
        fi
    done
    echo "No CA bundle on this machine: looked for $*. Install the distribution's ca-certificates package." >&2
    return 1
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/lumo-appimage"
mkdir -p "$CACHE"

TAG="lumo-appimage-builder:$(cat packaging/appimage/Containerfile packaging/appimage/pins.sh | sha256sum | cut -c1-12)"
if ! podman image exists "$TAG"; then
    ca="$(host_ca_bundle "${CA_BUNDLES[@]}")"
    mkdir "$WORK/context"
    install -m 0644 "$ca" "$WORK/context/hostca.crt"
    podman build -t "$TAG" \
        --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg APT_SNAPSHOT="$APT_SNAPSHOT" \
        -f packaging/appimage/Containerfile "$WORK/context"
fi

# Proton's commit, fetched by its id into a cache of its own (once; a commit id names its
# whole tree, so what is in the cache is what the pin says).
UP="$CACHE/upstream.git"
[ -d "$UP" ] || git init -q --bare "$UP"
if ! git --git-dir="$UP" cat-file -e "$UPSTREAM_COMMIT^{commit}" 2>/dev/null; then
    echo "Fetching $UPSTREAM_REPO $UPSTREAM_COMMIT" >&2
    git --git-dir="$UP" -c protocol.allow=never -c protocol.https.allow=always \
        fetch -q --depth 1 "$UPSTREAM_REPO" "$UPSTREAM_COMMIT"
fi
built_version="$(git --git-dir="$UP" show "$UPSTREAM_COMMIT:src-tauri/tauri.conf.json" \
    | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["version"])')"
if [ "$built_version" != "$UPSTREAM_VERSION" ]; then
    echo "upstream.env says $UPSTREAM_VERSION, but $UPSTREAM_COMMIT is version $built_version" >&2
    exit 1
fi
VERSION="$UPSTREAM_VERSION-$RELEASE"
EPOCH="$(git log -1 --format=%ct HEAD)"

# A tree's files exactly as committed, from git's object store (git archive would pass them
# through this machine's autocrlf, filters and tar.umask settings). Plain files only.
export_tree() {  # git-dir commit path-in-commit dest
    local gitdir=$1 commit=$2 sub=$3 dest=$4 entry fmode ftype oid path
    git --git-dir="$gitdir" ls-tree -r -z "$commit" -- $sub | while IFS= read -r -d '' entry; do
        read -r fmode ftype oid <<< "${entry%%$'\t'*}"
        path="${entry#*$'\t'}"
        case "$fmode" in
            100644|100755) ;;
            *) echo "$path is a $ftype of mode $fmode, which the build does not take" >&2; exit 1 ;;
        esac
        mkdir -p "$dest/$(dirname "$path")"
        git --git-dir="$gitdir" cat-file blob "$oid" > "$dest/$path"
        chmod "${fmode#100}" "$dest/$path"
    done
}
make_src_tar() {  # -> $WORK/src.tar: upstream/ (Proton's commit) and packaging/ (HEAD's)
    mkdir -p "$WORK/tree/upstream"
    export_tree "$UP" "$UPSTREAM_COMMIT" "" "$WORK/tree/upstream"
    export_tree "$(git rev-parse --absolute-git-dir)" HEAD packaging "$WORK/tree"
    (cd "$WORK/tree" && tar -cf "$WORK/src.tar" --sort=name --owner=0 --group=0 --numeric-owner \
        --mode=u+rwX,go+rX,go-w --mtime="@$EPOCH" upstream packaging)
}
DIST="$(mkdir -p "${DIST:-dist}" && cd "${DIST:-dist}" && pwd)"

run() {  # out-dir
    mkdir -p "$1"
    # --pull=never: the builder is the image made above, on this machine. /distfs: a tmpfs for
    # the webview bundles, whose listing order build.sh controls (see there).
    podman run --rm --pull=never --tmpfs /distfs:rw,size=256m,mode=0755 \
        -v "$WORK/src.tar:/src.tar:ro,Z" -v "$CACHE:/cache:Z" -v "$1:/out:Z" \
        -e SOURCE_DATE_EPOCH="$EPOCH" -e VERSION="$VERSION" "$TAG" \
        bash -c 'tar -xOf /src.tar packaging/appimage/build.sh > /tmp/build.sh && bash /tmp/build.sh'
}

echo "Building Lumo $VERSION: upstream ${UPSTREAM_COMMIT:0:12}, packaging $(git rev-parse --short HEAD)" >&2
make_src_tar
case "$mode" in
    build)
        run "$DIST" ;;
    check)
        run "$WORK/a"
        run "$WORK/b"
        a=$(cut -d' ' -f1 "$WORK"/a/*.sha256); b=$(cut -d' ' -f1 "$WORK"/b/*.sha256)
        if [ "$a" = "$b" ] && cmp -s "$WORK"/a/*.zsync "$WORK"/b/*.zsync; then
            cp "$WORK"/a/* "$DIST"/
            echo "Reproducible: both builds are $a"
        else
            echo "NOT reproducible: $a vs $b (compare with diffoscope; copies in $DIST/check-a, $DIST/check-b)" >&2
            rm -rf "$DIST/check-a" "$DIST/check-b" && cp -r "$WORK/a" "$DIST/check-a" && cp -r "$WORK/b" "$DIST/check-b"
            exit 1
        fi ;;
esac
