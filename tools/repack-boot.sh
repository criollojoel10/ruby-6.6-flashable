#!/usr/bin/env bash
# Repackea un boot.img v2 (MTK) conservando su ramdisk y reemplazando
# kernel + dtb por los del kernel 6.6.
#
# Uso:
#   ./repack-boot.sh <stock-boot.img> <Image.gz> <dtb> <out-boot.img> [magiskboot]
#
# magiskboot: binario aarch64/x86_64 (https://github.com/svoboda18/magiskboot)
set -euo pipefail

STOCK=$(realpath "${1:?stock-boot.img}")
IMG_GZ=$(realpath "${2:?Image.gz}")
DTB=$(realpath "${3:?dtb}")
OUT=$(realpath -m "${4:?out-boot.img}")
MB=${5:-magiskboot}

command -v "$MB" >/dev/null 2>&1 || { echo "no encuentro magiskboot ($MB)" >&2; exit 1; }
[ -f "$STOCK" ] && [ -f "$IMG_GZ" ] && [ -f "$DTB" ] || { echo "falta un archivo de entrada" >&2; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

"$MB" unpack "$STOCK" >/dev/null
gzip -dc "$IMG_GZ" > kernel
cp -f "$DTB" dtb
"$MB" repack "$STOCK" "$OUT"

ls -lh "$OUT"
