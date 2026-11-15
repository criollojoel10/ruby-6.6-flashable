#!/usr/bin/env bash
# Baja el artifact de un run, arma los flasheables (boot MIUI/AOSP + dtbo
# híbrido), renombra los zips a la nomenclatura universal y los publica en el
# release del run.
#
# Uso:
#   STOCK_BOOT=... AOSP_BOOT=... ./publish.sh <run-id> <repo> [magiskboot] [mkdtboimg.py]
#
# Variables:
#   STOCK_BOOT  boot_a stock del equipo (obligatoria)
#   AOSP_BOOT   boot de Lineage/AOSP para el boot prearmado (opcional)
#   DOWNLOAD    dir de descarga (default: ./dl/<run>)
set -euo pipefail

RUN=${1:?run id}
REPO=${2:-criollojoel10/ruby-6.6-flashable}
MB=${3:-magiskboot}
MKDTBOIMG=${4:-mkdtboimg.py}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(dirname "$HERE")
DL=${DOWNLOAD:-$OUT/dl/$RUN}

: "${STOCK_BOOT:?falta STOCK_BOOT (dump de boot_a)}"
[ -s "$STOCK_BOOT" ] || { echo "no existe STOCK_BOOT=$STOCK_BOOT" >&2; exit 1; }

echo "== descargando artifact del run $RUN =="
rm -rf "$DL"; mkdir -p "$DL"
gh run download "$RUN" -R "$REPO" -D "$DL"

art=$(find "$DL" -maxdepth 2 -name Image.gz -printf '%h\n' | head -n1)
[ -n "$art" ] || { echo "no encontré Image.gz en $DL" >&2; exit 1; }
TAG=$(basename "$art"); TAG=${TAG#ruby66-flashable-}
echo "artifact: $art"
echo "tag     : $TAG"

echo "== armando boot MIUI/AOSP + dtbo híbrido =="
if [ -n "${AOSP_BOOT:-}" ] && [ -s "$AOSP_BOOT" ]; then
  "$HERE/assemble.sh" "$art" "$STOCK_BOOT" "$TAG" "$MB" "$MKDTBOIMG" "$AOSP_BOOT"
else
  "$HERE/assemble.sh" "$art" "$STOCK_BOOT" "$TAG" "$MB" "$MKDTBOIMG"
fi

echo "== normalizando nombres de zips =="
shopt -s nullglob
mv_to() { # <origen-glob> <destino>
  local src=($1)
  [ ${#src[@]} -eq 1 ] || return 0
  [ "${src[0]}" = "$2" ] && return 0
  mv -f "${src[0]}" "$2"
  echo "   ${src[0]} -> $(basename "$2")"
}
for kind in base-dtb combined-dtb; do
  mv_to "$art/AnyKernel3-*-miui-${kind}.zip" "$art/AnyKernel3-${TAG}-${kind}.zip"
done
# el artifact sandbox no siempre es escribible; copiamos si hace falta
for f in "$art"/AnyKernel3-*.zip; do
  cp -f "$f" "$OUT/$(basename "$f")" 2>/dev/null || true
done

echo "== assets a publicar =="
assets=("$OUT/boot-6.6-miui-${TAG}.img" "$OUT/dtbo-hybrid-${TAG}.img")
[ -f "$OUT/boot-6.6-aosp-${TAG}.img" ] && assets+=("$OUT/boot-6.6-aosp-${TAG}.img")
for f in "$OUT"/AnyKernel3-"${TAG}"-*.zip; do [ -f "$f" ] && assets+=("$f"); done
for f in Image.gz mt6877.dtb ruby.dtbo; do [ -f "$art/$f" ] && assets+=("$art/$f"); done
for f in "$art"/dtbo-*.img "$art"/config-*; do [ -f "$f" ] && assets+=("$f"); done
printf '   %s\n' "${assets[@]##*/}"

if gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
  ( cd "$OUT" && sha256sum boot-6.6-*-"${TAG}.img" AnyKernel3-"${TAG}"-*.zip \
      "dtbo-hybrid-${TAG}.img" > "SHA256SUMS-flashable-${TAG}" )
  assets+=("$OUT/SHA256SUMS-flashable-${TAG}")
  gh release upload "$TAG" "${assets[@]}" -R "$REPO" --clobber
else
  gh release create "$TAG" "${assets[@]}" -R "$REPO" --prerelease \
    --title "ruby 6.6 flasheable · $TAG" \
    --notes "Kernel 6.6 (RubyxLabs lineage-24.0) universal MIUI/AOSP.

- AnyKernel3-…-base-dtb.zip: universal (conserva ramdisk y dtbo del equipo).
- AnyKernel3-…-combined-dtb.zip: fallback con DTB fusionado.
- boot-6.6-miui-…img / boot-6.6-aosp-…img: boot prearmado para cada familia.
- dtbo-hybrid-…img: overlay 6.6 + extras del dtbo de MIUI.

Ver README y docs/UNIVERSAL.md, docs/DEVICE-STATE.md, docs/LOGS.md."
fi

echo "== listo =="
gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name'
