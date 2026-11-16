#!/usr/bin/env bash
# Cierra un run de matriz: publica boots/dtbo de cada variante en el release y
# verifica que los kernels (zips y boots) sean aceptables para APatch.
#
# Uso:
#   STOCK_BOOT=… AOSP_BOOT=… ./finish-run.sh <run-id> <release-tag>
#
# Variables: STOCK_BOOT (obligatoria), AOSP_BOOT, MB (magiskboot),
#            MKDTBOIMG (mkdtboimg.py), KPTOOLS (kptools-android)
set -euo pipefail
RUN=${1:?run id}
REL=${2:?release tag}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(dirname "$HERE")
MB=${MB:-magiskboot}
MKDTBOIMG=${MKDTBOIMG:-mkdtboimg.py}
KPTOOLS=${KPTOOLS:-kptools-android}

echo "########## 1/3 publicar ##########"
RELEASE_TAG="$REL" "$HERE/publish.sh" "$RUN" "${REPO:-criollojoel10/ruby-6.6-flashable}" "$MB" "$MKDTBOIMG"

echo
echo "########## 2/3 verificar cabecera MZ + kptools en los zips ##########"
shopt -s nullglob
zips=("$OUT"/AnyKernel3-*"${REL#ruby66-}"*.zip)
[ ${#zips[@]} -gt 0 ] || zips=("$OUT"/AnyKernel3-*.zip)
rc=0
for z in "${zips[@]}"; do
  echo
  echo "### $(basename "$z")"
  "$HERE/verify-apatch.sh" "$z" "$KPTOOLS" || rc=1
done

echo
echo "########## 3/3 assets del release ##########"
gh release view "$REL" -R "${REPO:-criollojoel10/ruby-6.6-flashable}" \
  --json assets --jq '.assets[]|"\(.size)\t\(.name)"' | sort -k2

exit $rc
