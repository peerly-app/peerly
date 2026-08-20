#!/usr/bin/env python3
"""Removes from AppDir/usr/lib everything that only exists because
linuxdeploy, scanning the "peero" executable, followed its dependency on
libmedia_kit_video_plugin.so all the way down into libmpv.so.2's own huge
transitive closure (the full ffmpeg codec stack, ~150-300MB, ~150+ files --
see the "solution complète" discussion this script came out of).

libmedia_kit_video_plugin.so itself is untouched (it lives in usr/bin/lib/,
outside the directory this script prunes) and keeps resolving libmpv.so.2
from the host system at the normal dynamic-linker search path -- that's the
point: video playback depends on the host having libmpv2 installed (already
declared as a runtime dependency in control.template for the .deb), instead
of freezing ~150 unrelated shared libraries into the AppImage where they'd
never receive the host's security updates again.

Usage: prune-video-codec-libs.py <AppDir/usr/lib> <path-to-bundle>/peero
The second argument is the *bundle* (pre-linuxdeploy) executable directory,
used to compute which libraries are legitimately needed by every plugin
*except* libmedia_kit_video_plugin.so.
"""
import os
import subprocess
import sys

lib_dir, bundle_lib_dir = sys.argv[1], sys.argv[2]

# NB: deliberately excludes both "peero" itself and
# libmedia_kit_video_plugin.so -- either one would pull in libmpv.so.2 and
# its entire dependency tree, contaminating the "wanted" set.
sources = [
    os.path.join(bundle_lib_dir, "libflutter_linux_gtk.so"),
    os.path.join(bundle_lib_dir, "libaudioplayers_linux_plugin.so"),
    os.path.join(bundle_lib_dir, "libfile_selector_linux_plugin.so"),
    os.path.join(bundle_lib_dir, "librecord_linux_plugin.so"),
    os.path.join(bundle_lib_dir, "libmedia_kit_libs_linux_plugin.so"),
]

keep_names = set()
for src in sources:
    out = subprocess.run(["ldd", src], capture_output=True, text=True, check=True).stdout
    for line in out.splitlines():
        keep_names.add(line.split()[0])

entries = [
    name for name in os.listdir(lib_dir)
    if not os.path.isdir(os.path.join(lib_dir, name))
]
keep = set()

# Pass 1: files/symlinks whose own name is wanted -> keep them + their target.
for name in entries:
    path = os.path.join(lib_dir, name)
    if name in keep_names:
        keep.add(name)
        if os.path.islink(path):
            keep.add(os.path.basename(os.readlink(path)))

# Pass 2: any symlink pointing at a kept file -> keep the symlink too
# (covers e.g. libfoo.so -> libfoo.so.0 -> libfoo.so.0.1.2 chains).
changed = True
while changed:
    changed = False
    for name in entries:
        if name in keep:
            continue
        path = os.path.join(lib_dir, name)
        if os.path.islink(path):
            target = os.path.basename(os.readlink(path))
            if target in keep:
                keep.add(name)
                changed = True

removed, removed_bytes = 0, 0
for name in entries:
    if name in keep:
        continue
    path = os.path.join(lib_dir, name)
    if not os.path.islink(path):
        removed_bytes += os.path.getsize(path)
    os.remove(path)
    removed += 1

print(f"kept {len(entries) - removed} files, removed {removed} files "
      f"({removed_bytes / 1_000_000:.1f} MB of video codec libs not needed "
      f"outside media_kit_video/libmpv)")
