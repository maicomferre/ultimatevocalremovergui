# Linux CPU packaging

This directory contains the community-maintained Debian packaging for Ultimate
Vocal Remover GUI. It creates an `amd64`, CPU-only package and does not install
CUDA, ROCm, NVIDIA libraries, or `onnxruntime-gpu`.

This is an unofficial distribution. The original authors, project links,
license, and credits are preserved in the main README and installed package
documentation.

## Runtime layout

- Application and private Python runtime:
  `/usr/lib/ultimate-vocal-remover`
- Launcher: `/usr/bin/ultimate-vocal-remover`
- Short launcher alias: `/usr/bin/uvr`
- Desktop entry:
  `/usr/share/applications/ultimate-vocal-remover.desktop`
- Application data and models:
  `${XDG_DATA_HOME:-~/.local/share}/ultimate-vocal-remover`
- Settings:
  `${XDG_CONFIG_HOME:-~/.config}/ultimate-vocal-remover`
- Caches:
  `${XDG_CACHE_HOME:-~/.cache}/ultimate-vocal-remover`

The source checkout keeps its legacy local-directory behavior when `UVR.py` is
run directly. The installed launcher enables the XDG layout.

## Build

The build requires Bash, `rsync`, `dpkg-deb`, `desktop-file-validate`, and a
current `uv` executable. Python is fixed to 3.14.6 and Python packages are
synchronized from `requirements/linux-cpu.txt`.

From the repository root, run:

```bash
./scripts/build-deb.sh
```

The package and its SHA-256 checksum are written to `dist/`. Both `build/` and
`dist/` are intentionally ignored by Git. Allow several gigabytes of free disk
space for downloads, caches, staging, and compression.

An already prepared standalone Python runtime can be reused:

```bash
UVR_PYTHON_RUNTIME=/path/to/cpython-3.14.6-linux-x86_64-gnu \
  ./scripts/build-deb.sh
```

The build checks the exact Python version, synchronizes the locked dependencies,
asserts that PyTorch is CPU-only, validates key imports and the desktop file,
then removes development-only files from the disposable staging tree.

## Install and remove

APT resolves the required system tools and libraries:

```bash
sudo apt install ./dist/ultimate-vocal-remover_5.6.0-5_amd64.deb
```

Start the application from the desktop menu or run:

```bash
ultimate-vocal-remover
```

Remove the package with:

```bash
sudo apt remove ultimate-vocal-remover
```

Removal does not delete models, settings, or caches from the user's XDG
directories.

## Compatibility notes

- The package requires glibc 2.34 or newer. This covers the intended Ubuntu
  22.04+, Debian 12+, and corresponding Linux Mint bases.
- The embedded drag-and-drop extension is built for Tk 8.6. Under the packaged
  Tk 9 runtime, the GUI falls back to file and directory selection buttons;
  audio processing is unaffected.
- The package includes FFmpeg and Rubber Band as system dependencies. FFplay is
  also used for completion and error sounds.
- The package is currently `amd64` only. Other architectures require their own
  runtime and validation.

The generated package should be tested in a clean VM before publishing a
release. At minimum, verify installation, desktop menu entry and icon, settings
persistence, model download, a real CPU separation, upgrade, and removal.

## Version updates

The packaged Linux edition does not follow the upstream `current_version_linux`
string from the application catalog. It reports the real Debian revision and
checks for updates against a small manifest published with the APT repository:

- Manifest: `https://apt.maicom.dev/uvr-manifest.json`
- Field used by the CPU package: `linux_cpu`

Comparisons use Debian version ordering, so a textual difference is never
treated as a newer version. When an update is available, the application shows
APT instructions instead of an in-app download prompt.
