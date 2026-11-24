# Mali-G52 / Anland PanVK ICD (branch `mali-g52`)

This branch is NEURAX-FX `main` (which has merged `debug/wayland-shm-readback`)
plus two local patches for Samsung Galaxy A13 / Mali-G52 (Bifrost JM, arch v7).

## What is local to this branch

- `anland/0001-panvk-jm-sync-file-export.patch` — JM sync_file export workaround.
  This kernel (4.19) has no `/dev/sw_sync`, vgem has no `DRIVER_SYNCOBJ`, and
  there is no JM kbase sync_file export. The patch keeps a dup of the first
  imported Android `SYNC_FD` and re-exports it as the completion fence, falling
  back to a signalled eventfd. Cross-process GPU sync is effectively disabled;
  the Anland socketpair carries render-done. The Anland consumer tolerates this
  because niri is built to submit GPU-staging frames with `fd = -1`.
- `anland/0002-panvk-jm-vgem-sync-file.patch` — env-gated vgem `sync_file`
  bridge for JM. Requires `anZxKr/SM-A135F_Kernel@77be591ee`. With
  `PANVK_KBASE_JM_VGEM_FENCE=1`, export returns a pending vgem fd immediately
  and signals it after kbase/JM completion. Default/off keeps the 0001 path.
  The bridge uses one device-owned worker and a bounded job ring instead of a
  thread and allocation per submit, validates the configured node as a vgem
  render node, and reports wait/signal failures.
- `anland/linux-aarch64-cross.ini` — AArch64 glibc cross file (system cross
  toolchain; no NEURAX sysroot needed).
- `anland/build-g52.sh` — reproducible build driver.
- `anland/build-g52-vgem-fence.sh` — reproducible build for the vgem test ICD.

`muic/0003` is deliberately NOT applied: it is CSF/G720-only (KCPU queues,
`CQS_SET_OPERATION`, `FENCE_WAIT`) and does not apply to JM.

NEURAX debug patches applied: `0002`, `0003`, `0004`, `0006`, `0008`, `0009`
(Kopper/WSI paths, sync-file waiter lifetime, vgem render-node alias).
Skipped: `0001`/`0007` (env-gated diagnostics) and `0005` (CSF-only).

## Build

Host packages: `meson`, `ninja`, `aarch64-linux-gnu-{gcc,g++,ar,strip}`,
`wayland-scanner`, `pkg-config`, aarch64 glibc headers/libs.

Host tools (`mesa_clc`, `panfrost_compile`, `vtn_bindgen2`) are needed for
`-Dmesa-clc=system -Dprecomp-compiler=system`. Build them with
`scripts/bootstrap-host-tools.sh` or reuse a previously built `build/host-tools`.

```sh
chmod +x anland/build-g52.sh
PANVK_JOBS=2 ./anland/build-g52.sh

chmod +x anland/build-g52-vgem-fence.sh
PANVK_JOBS=2 ./anland/build-g52-vgem-fence.sh
```

Outputs:

```text
artifacts/panvk-g52-anland/libvulkan_panfrost.so
artifacts/panvk-g52-vgem-fence/libvulkan_panfrost.so
```

## Device install (container, Fedora 45 aarch64)

For the current ICD:

```sh
install -Dm755 libvulkan_panfrost.so /opt/panvk-anland/libvulkan_panfrost.so
install -Dm644 panvk-g52.json /opt/panvk-anland/panvk-g52.json
```

For the vgem ICD:

```sh
install -Dm755 libvulkan_panfrost.so /opt/panvk-anland-vgem/libvulkan_panfrost.so
install -Dm644 panvk-g52.json /opt/panvk-anland-vgem/panvk-g52.json
```

niri env for the vgem ICD:

```
ANLAND_PANVK_ICD=/opt/panvk-anland-vgem/libvulkan_panfrost.so
VK_DRIVER_FILES=/opt/panvk-anland-vgem/panvk-g52.json
PANVK_KBASE_DRM_NODE=/dev/dri/renderD128
PANVK_KBASE_ANLAND_STAGING=1
PANVK_KBASE_JM_VGEM_FENCE=1
```

The rebuilt `vgem.ko` must be loaded manually after boot.
