#!/bin/sh
# Build the AArch64 glibc PanVK ICD for Mali-G52 / JM + Anland GPU staging.
#
# Source stack (all reproducible from this repo):
#   1. Mesa 5a07217f               (sources.lock)
#   2. NEURAX base stack -> p0175  (scripts/prepare-rc5-tree.sh)
#   3. patches/debug/0002,0003,0004,0006,0008,0009
#                                  (Kopper/WSI, sync-file lifetime, vgem alias)
#   4. muic/0001                   (Anland staging imports; skip CSF-only 0003)
#   5. anland/0001-...patch        (our JM sync_file export workaround)
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MESA="$ROOT/work/mesa"
BDIR="$ROOT/build/linux-glibc-g52"
OUT="$ROOT/artifacts/panvk-g52-anland"
JOBS="${PANVK_JOBS:-2}"
PIN="$(python3 -c "import json;print(json.load(open('$ROOT/sources.lock'))['mesaCommit'])")"

cd "$ROOT"

echo "[1/5] fetch pinned Mesa $PIN"
[ -d "$MESA/.git" ] || ./scripts/fetch-mesa.sh "$ROOT/work"
git -C "$MESA" checkout -q --detach "$PIN"
git -C "$MESA" reset --hard -q
git -C "$MESA" clean -fdq

echo "[2/5] documented NEURAX patch stack through p0175"
./scripts/prepare-rc5-tree.sh --mesa "$MESA"

echo "[3/5] selected NEURAX patches for G52 Anland"
# Included: Zink Kopper / Vulkan WSI (0002,0003,0006,0008), kbase sync-file
# lifetime (0004), vgem render alias (0009). muic/0001 = Anland staging import.
# Skipped: 0001/0007 diagnostics (env-gated), 0005 CSF-only, muic/0003 CSF-only.
for n in 0002 0003 0004 0006 0008 0009; do
   p=$(find patches/debug -maxdepth 1 -name "$n-*.patch" | head -n1)
   [ -n "$p" ] || { echo "MISSING patch $n" >&2; exit 1; }
   echo "  APPLY $p"
   git -C "$MESA" apply "$ROOT/$p"
   git -C "$MESA" add -A
   git -C "$MESA" commit -q --no-verify -m "series: debug/$(basename "$p")"
done
git -C "$MESA" am "$ROOT/muic/0001-panvk-kbase-anland-staging.patch"

echo "[4/5] JM sync_file export workaround for G52 Anland"
git -C "$MESA" apply "$ROOT/anland/0001-panvk-jm-sync-file-export.patch"
git -C "$MESA" add -A
git -C "$MESA" commit -q --no-verify -m "anland: JM sync_file export workaround"

echo "[5/5] configure + build aarch64 glibc ICD"
mkdir -p "$OUT"
if [ ! -f "$BDIR/build.ninja" ]; then
   PATH="$ROOT/build/host-tools/bin:$PATH" meson setup "$BDIR" "$MESA" \
      --cross-file "$ROOT/anland/linux-aarch64-cross.ini" \
      -Dbuildtype=release -Dplatforms=x11,wayland \
      -Dgallium-drivers= -Dvulkan-drivers=panfrost -Dpanfrost-kmds=kbase \
      -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dopengl=false \
      -Dglx=disabled -Dgbm=disabled -Dzstd=disabled -Dlibunwind=disabled \
      -Dmesa-clc=system -Dprecomp-compiler=system
fi
ninja -j"$JOBS" -C "$BDIR"

SO="$(find "$BDIR" -name libvulkan_panfrost.so | head -n1)"
[ -n "$SO" ] || { echo "BUILD-FAIL: ICD missing" >&2; exit 1; }
cp "$SO" "$OUT/libvulkan_panfrost.so"
cat > "$OUT/panvk-g52.json" <<'JSON'
{
    "file_format_version": "1.0.0",
    "ICD": {
        "library_path": "./libvulkan_panfrost.so",
        "api_version": "1.4.0"
    }
}
JSON
sha256sum "$OUT/libvulkan_panfrost.so" | tee "$OUT/SHA256SUMS"
echo "OK out=$OUT"
