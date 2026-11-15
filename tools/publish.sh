#!/usr/bin/env bash
# Baja los artifacts de un run, arma los flasheables que el CI no puede armar
# (boot MIUI/AOSP + dtbo híbrido) y los sube al release del run.
#
# Funciona con runs de matriz (vanilla + ksu en un solo run, release único) y
# con runs de una sola variante (release por variante).
#
# Uso:
#   STOCK_BOOT=... AOSP_BOOT=... ./publish.sh <run-id> [repo] [magiskboot] [mkdtboimg.py]
#
# Variables:
#   STOCK_BOOT  boot stock del equipo (obligatoria)
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

: "${STOCK_BOOT:?falta STOCK_BOOT (dump del boot stock)}"
[ -s "$STOCK_BOOT" ] || { echo "no existe STOCK_BOOT=$STOCK_BOOT" >&2; exit 1; }

echo "== descargando artifacts del run $RUN =="
rm -rf "$DL"; mkdir -p "$DL"
gh run download "$RUN" -R "$REPO" -D "$DL"

mapfile -t ARTS < <(find "$DL" -maxdepth 2 -name Image.gz -printf '%h\n' | sort)
[ "${#ARTS[@]}" -gt 0 ] || { echo "no encontré Image.gz en $DL" >&2; exit 1; }

assets=()
reltags=()
for art in "${ARTS[@]}"; do
  base=$(basename "$art")
  TAG=${base#ruby66-flashable-}; TAG=${TAG#ruby66-vanilla-}; TAG=${TAG#ruby66-ksu-}
  echo
  echo "== variante: $TAG =="
  if [ -n "${AOSP_BOOT:-}" ] && [ -s "$AOSP_BOOT" ]; then
    "$HERE/assemble.sh" "$art" "$STOCK_BOOT" "$TAG" "$MB" "$MKDTBOIMG" "$AOSP_BOOT"
  else
    "$HERE/assemble.sh" "$art" "$STOCK_BOOT" "$TAG" "$MB" "$MKDTBOIMG"
  fi

  # zips a la nomenclatura universal (base-dtb / combined-dtb)
  shopt -s nullglob
  for kind in base-dtb combined-dtb; do
    src=("$art"/AnyKernel3-*-miui-${kind}.zip)
    if [ "${#src[@]}" -eq 1 ]; then
      dst="$OUT/AnyKernel3-${TAG}-${kind}.zip"
      [ "${src[0]}" = "$dst" ] || { mv -f "${src[0]}" "$dst"; echo "   -> $(basename "$dst")"; }
    fi
  done
  for f in "$art"/AnyKernel3-*.zip; do cp -f "$f" "$OUT/"; done

  for f in "$OUT/boot-6.6-miui-${TAG}.img" "$OUT/dtbo-hybrid-${TAG}.img"; do
    [ -f "$f" ] && assets+=("$f")
  done
  [ -f "$OUT/boot-6.6-aosp-${TAG}.img" ] && assets+=("$OUT/boot-6.6-aosp-${TAG}.img")
  for f in "$OUT"/AnyKernel3-"${TAG}"-*.zip; do [ -f "$f" ] && assets+=("$f"); done
  for f in "$art"/Image.gz "$art"/mt6877.dtb "$art"/ruby.dtbo "$art"/config-* "$art"/dtbo-*.img; do
    [ -f "$f" ] && assets+=("$f")
  done

  reltags+=("$(echo "$TAG" | sed -E 's/-(vanilla|ksu)$//')")
done

REL=$(printf '%s\n' "${reltags[@]}" | sort -u | head -n1)
[ -n "$REL" ] || { echo "no pude determinar el tag del release" >&2; exit 1; }
echo
echo "== release: $REL =="

( cd "$OUT" && sha256sum boot-6.6-*-"${REL}"*.img AnyKernel3-"${REL}"*.zip "dtbo-hybrid-${REL}"*.img \
    > "SHA256SUMS-flashable-${REL}" 2>/dev/null ) || true
[ -f "$OUT/SHA256SUMS-flashable-${REL}" ] && assets+=("$OUT/SHA256SUMS-flashable-${REL}")

printf '   %s\n' "${assets[@]##*/}"
if gh release view "$REL" -R "$REPO" >/dev/null 2>&1; then
  gh release upload "$REL" "${assets[@]}" -R "$REPO" --clobber
else
  gh release create "$REL" "${assets[@]}" -R "$REPO" --prerelease \
    --title "ruby 6.6 flasheable · $REL" \
    --notes "Kernel 6.6 (RubyxLabs lineage-24.0), universal MIUI/AOSP.

- boot-6.6-miui-*.img: ramdisk MIUI (entrada para APatch o flash directo).
- boot-6.6-aosp-*.img: ramdisk Lineage/AOSP 17.
- AnyKernel3-*-base-dtb.zip: universal (conserva ramdisk y dtbo del equipo).
- AnyKernel3-*-combined-dtb.zip: fallback con DTB fusionado.
- dtbo-hybrid-*.img: overlay 6.6 + extras del dtbo de MIUI.

Ver docs/FLASH-CARD.md, docs/UNIVERSAL.md y docs/DEVICE-STATE.md."
fi

echo "== assets en el release =="
gh release view "$REL" -R "$REPO" --json assets --jq '.assets[].name'
