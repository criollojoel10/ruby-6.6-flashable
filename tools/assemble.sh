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

[ $# -ge 3 ] || { echo "uso: $0 <dir-artefactos> <stock-boot.img> <tag> [magiskboot] [mkdtboimg.py] [aosp-base-boot.img]" >&2; exit 2; }
DIR=$(cd "$1" && pwd)
STOCK=$(readlink -f "$2")
TAG=$3
MB=${4:-magiskboot}
MKDTBOIMG=${5:-mkdtboimg.py}
AOSP=${6:-}
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

# build_boot <boot-base.img> <prefijo-salida>
# Repackea el boot base conservando SU ramdisk y reemplazando kernel + dtb.
# Verifica por hash que kernel, ramdisk y dtb quedaron exactos.
build_boot() {
  local base=$1 name=$2 d="$work/$2"
  mkdir -p "$d/repack" "$d/verify"
  cp "$base" "$d/orig.img"
  ( cd "$d/repack"
    "$MB" unpack "$d/orig.img" >/dev/null
    gzip -dc "$DIR/Image.gz" > kernel
    # Cabecera "EFI" (MZ) para que APatch/kptools pueda parchear kernels 6.6
    # compilados con CONFIG_EFI=n (ver tools/fix-apatch-header.py).
    python3 "$HERE/fix-apatch-header.py" kernel
    cp "$DIR/mt6877.dtb" dtb
    "$MB" repack "$d/orig.img" boot-new.img >/dev/null
    cp boot-new.img "$OUT/$name"
  )
  ( cd "$d/verify"
    "$MB" unpack "$OUT/$name" >/dev/null
    for f in kernel ramdisk.cpio dtb; do
      a=$(sha256sum "$d/repack/$f" | cut -d' ' -f1)
      b=$(sha256sum "$f" | cut -d' ' -f1)
      [ "$a" = "$b" ] || { echo "  $f distinto en $name" >&2; return 1; }
    done
    gzip -dc kernel 2>/dev/null | strings | grep -m1 -E '^6\.6\.[0-9]+' | sed 's/^/  version: /' || true
  )
  echo "   -> $name ($(stat -c %s "$OUT/$name") bytes) verificado"
}

echo "== 1/3 boot.img con ramdisk MIUI =="
build_boot "$STOCK" "boot-6.6-miui-${TAG}.img"

if [ -n "$AOSP" ]; then
  AOSP=$(readlink -f "$AOSP")
  [ -s "$AOSP" ] || { echo "falta el boot base AOSP ($AOSP)" >&2; exit 1; }
  echo "== 1b/3 boot.img con ramdisk AOSP/Lineage =="
  build_boot "$AOSP" "boot-6.6-aosp-${TAG}.img"
fi

echo "== 2/3 dtbo híbrido =="
dtc -@ -I dtb -O dts -o "$work/ruby.dtbo.dts" "$DIR/ruby.dtbo"
python3 "$HERE/merge-dtbo.py" "$work/ruby.dtbo.dts" "$OUT/dtb/miui-extras.dts" -o "$work/hybrid.dts"
dtc -@ -I dts -O dtb -o "$work/hybrid.dtb" "$work/hybrid.dts"
# Validación: el híbrido tiene que aplicar al dtb base y aportar videolfb/wifi.
fdtoverlay -i "$DIR/mt6877.dtb" -o "$work/flat.dtb" "$work/hybrid.dtb" >/dev/null
[ "$(fdtget "$work/flat.dtb" /chosen atag,videolfb-lcmname)" = "td4330_fhdp_dsi_cmd_auo_rt4831_drv" ] \
  || { echo "el híbrido no aporta atag,videolfb-lcmname" >&2; exit 1; }
fdtget "$work/flat.dtb" /seninf_top@1a004000 compatible >/dev/null
fdtget -l "$work/flat.dtb" /wifi@18000000 >/dev/null
echo "   híbrido verificado contra el dtb base (videolfb, seninf, wifi)"
python3 "$MKDTBOIMG" create --page_size=2048 \
  "$OUT/dtbo-hybrid-${TAG}.img" "$work/hybrid.dtb"
echo "   -> dtbo-hybrid-${TAG}.img ($(stat -c %s "$OUT/dtbo-hybrid-${TAG}.img") bytes)"

echo "== 3/3 sha256 =="
( cd "$OUT" && sha256sum boot-6.6-*-"${TAG}.img" "dtbo-hybrid-${TAG}.img" )
