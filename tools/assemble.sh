#!/usr/bin/env bash
# Arma los artefactos flasheables a partir de lo que deja el CI:
#   boot-6.6-miui-<tag>.img   (boot v2 con ramdisk MIUI + kernel/dtb 6.6)
#   dtbo-hybrid-<tag>.img     (overlay 6.6 + extras del dtbo de MIUI)
#
# Uso:
#   ./assemble.sh <dir-artefactos> <stock-boot.img> <tag> [magiskboot] [mkdtboimg.py]
#
# <dir-artefactos> debe tener Image.gz, mt6877.dtb y ruby.dtbo (los baja
# `gh run download`). El dtbo híbrido necesita `dtc` y el script de mkdtboimg.
set -euo pipefail

[ $# -ge 3 ] || { echo "uso: $0 <dir-artefactos> <stock-boot.img> <tag> [magiskboot] [mkdtboimg.py]" >&2; exit 2; }
DIR=$(cd "$1" && pwd)
STOCK=$(readlink -f "$2")
TAG=$3
MB=${4:-magiskboot}
MKDTBOIMG=${5:-mkdtboimg.py}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(dirname "$HERE")

for f in Image.gz mt6877.dtb ruby.dtbo; do
  [ -s "$DIR/$f" ] || { echo "falta $DIR/$f" >&2; exit 1; }
done
[ -s "$STOCK" ] || { echo "falta $STOCK" >&2; exit 1; }
command -v "$MB" >/dev/null || { echo "falta magiskboot ($MB)" >&2; exit 1; }
command -v dtc >/dev/null || { echo "falta dtc" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "== 1/3 boot.img (ramdisk MIUI + kernel/dtb 6.6) =="
cp "$STOCK" "$work/orig.img"
mkdir -p "$work/repack" && cd "$work/repack"
"$MB" unpack "$work/orig.img" >/dev/null
cp "$work/repack/ramdisk.cpio" "$work/ramdisk-miui.cpio"
gzip -dc "$DIR/Image.gz" > kernel
cp "$DIR/mt6877.dtb" dtb
"$MB" repack "$work/orig.img" boot-new.img >/dev/null
cp boot-new.img "$OUT/boot-6.6-miui-${TAG}.img"
echo "   -> boot-6.6-miui-${TAG}.img ($(stat -c %s "$OUT/boot-6.6-miui-${TAG}.img") bytes)"

echo "== 2/3 verificación del boot repackeado =="
mkdir -p "$work/verify" && cd "$work/verify"
"$MB" unpack "$OUT/boot-6.6-miui-${TAG}.img" >/dev/null
want_kernel=$(sha256sum "$work/repack/kernel" | cut -d' ' -f1)
got_kernel=$(sha256sum kernel | cut -d' ' -f1)
want_ramdisk=$(sha256sum "$work/ramdisk-miui.cpio" | cut -d' ' -f1)
got_ramdisk=$(sha256sum ramdisk.cpio | cut -d' ' -f1)
want_dtb=$(sha256sum "$work/repack/dtb" | cut -d' ' -f1)
got_dtb=$(sha256sum dtb | cut -d' ' -f1)
[ "$want_kernel" = "$got_kernel" ]   || { echo "kernel distinto" >&2; exit 1; }
[ "$want_ramdisk" = "$got_ramdisk" ] || { echo "ramdisk distinto" >&2; exit 1; }
[ "$want_dtb" = "$got_dtb" ]         || { echo "dtb distinto" >&2; exit 1; }
echo "   kernel, ramdisk y dtb idénticos; header y cmdline preservados"

echo "== 3/3 dtbo híbrido =="
dtc -I dtb -O dts -o "$work/ruby.dtbo.dts" "$(realpath "$DIR")/ruby.dtbo"
python3 "$HERE/merge-dtbo.py" "$work/ruby.dtbo.dts" "$OUT/dtb/miui-extras.dts" -o "$work/hybrid.dts"
dtc -@ -I dts -O dtb -o "$work/hybrid.dtb" "$work/hybrid.dts"
python3 "$MKDTBOIMG" create --page_size=2048 \
  "$OUT/dtbo-hybrid-${TAG}.img" "$work/hybrid.dtb"
echo "   -> dtbo-hybrid-${TAG}.img ($(stat -c %s "$OUT/dtbo-hybrid-${TAG}.img") bytes)"

echo "== sha256 =="
( cd "$OUT" && sha256sum "boot-6.6-miui-${TAG}.img" "dtbo-hybrid-${TAG}.img" )
