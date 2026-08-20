#!/bin/bash
# Bundles into an AppImage's AppDir the `parecord`/`pactl` binaries the
# `record` package shells out to (by bare name, via $PATH) to capture the
# microphone on Linux -- see record_linux's RecordLinux.start(). Used from
# release.yml, not run by app users.
#
# ffmpeg (also shelled out to by record_linux, for AAC encoding) is
# deliberately NOT bundled here -- same reasoning as libmpv/video: its
# codec dependency closure is huge (~150 libs), so it's declared as a
# runtime dependency instead (control.template for the .deb; AppImage users
# need it on the host, like libmpv2 -- see AppRun and
# prune-video-codec-libs.py).
#
# Kept in its own subdirectory (not the top-level usr/lib that
# prune-video-codec-libs.py prunes) so its libraries are never touched by
# that pass.
#
# Usage: bundle-pulseaudio-tools.sh <path-to-AppDir>
set -euo pipefail

# Resolved to an absolute path: the rest of this script cd's into a scratch
# download dir, which would otherwise silently break the caller's relative
# "AppDir" (see the same fix in bundle-gstreamer-audio.sh).
APPDIR="$(cd "$1" && pwd)"
TOOLS_DIR="$APPDIR/usr/lib/peero-audio-tools"
BIN_DEST="$TOOLS_DIR/bin"
LIB_DEST="$TOOLS_DIR/lib"
mkdir -p "$BIN_DEST" "$LIB_DEST"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# Not installed system-wide (only pulled in as a build-time transitive dep
# of other things, if at all) -- `apt-get download` fetches the .deb
# without root or installing.
apt-get download pulseaudio-utils
deb="$(ls pulseaudio-utils_*.deb)"
dpkg-deb -x "$deb" extracted

cp extracted/usr/bin/pacat "$BIN_DEST/"
ln -s pacat "$BIN_DEST/parecord"

# Bundle pacat's own shared library dependencies (skipping the handful
# that are always present as part of the base OS ABI).
skip_regex='^(linux-vdso|libc\.so|libm\.so|ld-linux)'
for lib in $(ldd extracted/usr/bin/pacat | awk '{print $3}' | grep -v '^$'); do
  name="$(basename "$lib")"
  [[ "$name" =~ $skip_regex ]] && continue
  cp -n "$lib" "$LIB_DEST/" 2>/dev/null || true
done

# pacat dlopen's its private pulseaudio/ subdirectory modules (e.g.
# libpulsecommon) relative to its own install prefix, not via a normal
# NEEDED entry resolvable by ldd -- copy the whole thing across.
if [ -d extracted/usr/lib/x86_64-linux-gnu/pulseaudio ]; then
  cp -r extracted/usr/lib/x86_64-linux-gnu/pulseaudio "$LIB_DEST/"
fi

patchelf --set-rpath '$ORIGIN/../lib:$ORIGIN/../lib/pulseaudio' "$BIN_DEST/pacat"

echo "Bundled pulseaudio-utils (parecord):"
ls -la "$BIN_DEST" "$LIB_DEST"
