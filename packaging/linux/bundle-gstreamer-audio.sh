#!/bin/bash
# Bundles into an AppImage's AppDir the exact, small set of GStreamer plugins
# needed to play back this app's voice messages (AAC-LC audio in an .m4a/
# MP4 container -- see AudioRecorderService). Used from release.yml, not run
# by app users.
#
# Deliberately narrow: this is not "GStreamer support" in general, just
# enough for audioplayers' playbin pipeline to decode what this app itself
# produces. Video (media_kit/libmpv) is out of scope -- see AppRun.
#
# Usage: bundle-gstreamer-audio.sh <path-to-AppDir>
set -euo pipefail

# Resolved to an absolute path: the rest of this script cd's into a
# scratch download dir, which would otherwise silently break the
# caller's relative "AppDir".
APPDIR="$(cd "$1" && pwd)"
GST_DEST="$APPDIR/usr/lib/gstreamer-1.0"
SCANNER_DEST="$APPDIR/usr/lib/gstreamer1.0/gstreamer-1.0"
mkdir -p "$GST_DEST" "$SCANNER_DEST"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$WORKDIR"

# Not installed system-wide (only their -dev counterparts are, as build
# deps) -- `apt-get download` fetches the .deb without root or installing.
apt-get download \
  libgstreamer1.0-0 \
  gstreamer1.0-plugins-base \
  gstreamer1.0-plugins-good \
  gstreamer1.0-libav

extract() {
  local pkg_glob="$1" internal_path="$2" dest_dir="$3"
  local deb
  deb="$(ls ${pkg_glob}_*.deb)"
  dpkg-deb --fsys-tarfile "$deb" | tar -x -C "$dest_dir" --strip-components="$4" "./$internal_path"
}

# Core: element registration (queue, filesrc, etc.) + the out-of-process
# plugin scanner GStreamer needs to probe plugins on first run.
extract libgstreamer1.0-0 "usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstcoreelements.so" "$GST_DEST" 5
extract libgstreamer1.0-0 "usr/lib/x86_64-linux-gnu/gstreamer1.0/gstreamer-1.0/gst-plugin-scanner" "$SCANNER_DEST" 6
chmod +x "$SCANNER_DEST/gst-plugin-scanner"

# Base: playbin/decodebin plumbing + format glue.
for so in playback typefindfunctions audioconvert audioresample app volume; do
  extract gstreamer1.0-plugins-base "usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgst${so}.so" "$GST_DEST" 5
done

# Good: MP4/M4A demuxing (isomp4), AAC parsing, sink autodetection + pulseaudio backend.
for so in isomp4 autodetect audioparsers pulseaudio; do
  extract gstreamer1.0-plugins-good "usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgst${so}.so" "$GST_DEST" 5
done

# libav: the actual AAC decoder (avdec_aac).
extract gstreamer1.0-libav "usr/lib/x86_64-linux-gnu/gstreamer-1.0/libgstlibav.so" "$GST_DEST" 5

echo "Bundled GStreamer audio plugins:"
ls -la "$GST_DEST"
