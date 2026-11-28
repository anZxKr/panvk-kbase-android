#!/bin/sh
# Build the AArch64 glibc PanVK ICD for Mali-G52 / JM with native and vgem sync_file paths.
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_ROOT="${PANVK_BUILD_ROOT:-/home/ubuntu/panvk-driver-builds/jmnative}"
MESA="$BUILD_ROOT/mesa"
BDIR="$BUILD_ROOT/build"
OUT="$BUILD_ROOT/out"
HOST_TOOLS="$BUILD_ROOT/host-tools"
JOBS="${PANVK_JOBS:-2}"
PIN="$(python3 -c "import json;print(json.load(open('$ROOT/sources.lock'))['mesaCommit'])")"

cd "$ROOT"
export PATH="$HOST_TOOLS/bin:$PATH"

echo "[1/7] fetch pinned Mesa $PIN"
mkdir -p "$BUILD_ROOT"
[ -d "$MESA/.git" ] || ./scripts/fetch-mesa.sh "$BUILD_ROOT"
git -C "$MESA" checkout -q --detach "$PIN"
git -C "$MESA" reset --hard -q
git -C "$MESA" clean -fdq

echo "[2/7] documented NEURAX patch stack through p0175"
./scripts/prepare-rc5-tree.sh --mesa "$MESA"

echo "[3/7] selected NEURAX patches for G52 Anland"
for n in 0002 0003 0004 0006 0008 0009; do
   p=$(find patches/debug -maxdepth 1 -name "$n-*.patch" | head -n1)
   [ -n "$p" ] || { echo "MISSING patch $n" >&2; exit 1; }
   echo "  APPLY $p"
   git -C "$MESA" apply "$ROOT/$p"
   git -C "$MESA" add -A
   git -C "$MESA" commit -q --no-verify -m "series: debug/$(basename "$p")"
done
git -C "$MESA" am "$ROOT/muic/0001-panvk-kbase-anland-staging.patch"

echo "[4/7] JM sync_file export workaround for G52 Anland"
git -C "$MESA" apply "$ROOT/anland/0001-panvk-jm-sync-file-export.patch"
git -C "$MESA" add -A
git -C "$MESA" commit -q --no-verify -m "anland: JM sync_file export workaround"

echo "[5/7] vgem sync_file bridge"
git -C "$MESA" apply "$ROOT/anland/0002-panvk-jm-vgem-sync-file.patch"
git -C "$MESA" add -A
git -C "$MESA" commit -q --no-verify -m "anland: JM vgem sync_file bridge" -m "Generated-by: LLM"

echo "[6/7] native JM sync_file fence export"
git -C "$MESA" apply "$ROOT/anland/0003-panvk-jm-native-sync-file.patch"
git -C "$MESA" add -A
git -C "$MESA" commit -q --no-verify -m "anland: native JM sync_file fences" -m "Generated-by: LLM"

echo "[7/7] configure + build aarch64 glibc ICD"
mkdir -p "$OUT"
if [ ! -f "$BDIR/build.ninja" ]; then
   meson setup "$BDIR" "$MESA" \
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
