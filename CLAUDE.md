# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Build, package, and flash RK3588 firmware images. The workflow extracts a rootfs from a running RK3588 device, creates a minimal ext4 image, and repackages it as a Rockchip `update.img` for USB flashing.

## Key Commands

- **Full build + flash**: `sudo ./build_and_flash.sh -a` (auto mode, no confirmations)
- **Start from a specific step**: `sudo ./build_and_flash.sh -s N` (e.g., `-s 1` to skip remote rootfs creation)
- **List available steps**: `./build_and_flash.sh -l`
- **Unpack a firmware image**: `sudo ./unpack.sh` (requires `update.img` in cwd)
- **Pack a new firmware image**: `sudo ./pack.sh` (requires `output/Image/` populated)
- **Flash rootfs only** (no erase): `sudo upgrade_tool di -p rootfs output/Image/rootfs.img`
- **Flash full firmware** (with erase): `sudo upgrade_tool ef <update_img> && sudo upgrade_tool uf <update_img>`

## Architecture

### Build pipeline (`build_and_flash.sh`)

13-step pipeline, each step is a function (`step0_create_remote_rootfs` through `step12_cleanup`). Steps 4-10 run without confirmation prompts; others require interactive approval unless `-a` (auto mode) is set.

The pipeline connects to the robot at `192.168.54.110` as user `lumosbot` via SSH/rsync.

**Step ordering matters**: step 9 runs `unpack.sh` to extract the base `update.img` into `output/`, then copies the newly built `rootfs.img` into `output/Image/`. Step 10 runs `pack.sh` to create `new_update.img` from those files.

The version string (`v0.1.3`) in `build_and_flash.sh` controls output filename dating.

### Firmware packaging (`pack.sh`)

1. Copies `MiniLoaderAll.bin` and `parameter.txt` into `output/Image/`
2. Symlinks partition images listed in `package-file` into `output/Image/`
3. If rootfs is not the last partition with `grow` flag, resizes the rootfs partition entry in `parameter.txt` based on actual filesystem size (via `dumpe2fs`)
4. Runs `bin/afptool -pack` → `bin/rkImageMaker` to produce final `update.img`

### Firmware unpacking (`unpack.sh`)

Reverses packaging: `bin/rkImageMaker -unpack` → `bin/afptool -unpack`. Outputs to `output/`.

### Binary tools (`bin/`)

- `afptool`: Rockchip firmware package tool (pack/unpack partition images)
- `rkImageMaker`: Rockchip image creator (`-RK3588`, `-unpack`) — SoC type is auto-detected from `parameter.txt` `MACHINE_MODEL` field

### Flash methods (step 11)

Two approaches for different use cases:
- **rootfs-only** (`upgrade_tool di -p rootfs`): flashes just the rootfs partition, no erase. Safer, used by Windows testers.
- **Full firmware** (`upgrade_tool ef` + `upgrade_tool uf`): erases all flash then writes complete firmware image.

### Key files/dirs

- `output/Image/` — staging area for partition images before packing
- `ubuntu-mount/` — mount point for the ext4 image during build
- `rootfs/` — extracted rootfs contents
- `package-file` (inside `output/`) — manifest listing partition image files; must exist for pack.sh
- `parameter.txt` (inside `output/Image/`) — partition layout; rootfs partition auto-resized if not last

### Requires sudo

Almost all operations require sudo: image mounting, file copying with ownership preservation, `e2fsck`/`resize2fs`, and `upgrade_tool` for USB flashing.
