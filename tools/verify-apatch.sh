#!/usr/bin/env bash
# Comprueba que un kernel (Image.gz o zip AnyKernel3) es aceptable para
# APatch/kptools: cabecera arm64 con "MZ" y branch en offset 4.
#
# Uso:
#   ./verify-apatch.sh <Image.gz | AnyKernel3.zip> [kptools]
#
# Sale 0 si kptools -l acepta el kernel; 1 si tira
# "kernel primary entry: ..." (kernel compilado con CONFIG_EFI=n).
set -euo pipefail

IN=${1:?Image.gz o AnyKernel3.zip}
KP=${2:-${KPTOOLS:-kptools-android}}
HERE=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

case "$IN" in
  *.zip)
    ( cd "$work" && unzip -qo "$(readlink -f "$IN")" 'Image*' >/dev/null 2>&1 || true )
    img=$(find "$work" -maxdepth 1 -name 'Image*' | head -n1)
    [ -n "$img" ] || { echo "el zip no trae Image*" >&2; exit 1; }
    ;;
  *) img=$IN ;;
esac

case "$img" in
  *.gz) gzip -dc "$img" > "$work/kernel" ;;
  *)    cp -f "$img" "$work/kernel" ;;
esac

echo "== cabecera =="
od -A d -t x1 -N 8 "$work/kernel"
if python3 - "$work/kernel" <<'PY'
import sys, struct
d = open(sys.argv[1], 'rb').read(8)
uefi = d[0:2] == b'MZ'
b_insn = struct.unpack('<I', d[4:8] if uefi else d[0:4])[0]
ok = (b_insn & 0xFC000000) == 0x14000000
print("  uefi(MZ)=%s  b_insn=0x%08x  %s" % (uefi, b_insn, "OK" if ok else "RECHAZADO por kptools"))
sys.exit(0 if ok else 1)
PY
then rc_hdr=0; else rc_hdr=1; fi

echo "== kptools =="
if [ -x "$KP" ] || command -v "$KP" >/dev/null 2>&1; then
  set +e
  out=$("$KP" -l -i "$work/kernel" 2>&1)
  rc=$?
  set -e
  echo "$out" | grep -E "patched=|banner=|version=|kernel primary entry|magic error" | sed 's/^/  /' || true
  if echo "$out" | grep -q "kernel primary entry"; then
    echo "  -> kptools RECHAZA el kernel (APatch no puede parchearlo)" >&2
    exit 1
  fi
  [ "$rc" -eq 0 ] || { echo "  -> kptools falló (rc=$rc)" >&2; exit 1; }
  echo "  -> kptools acepta el kernel"
else
  echo "  (sin kptools en PATH; sólo se validó la cabecera)"
fi

exit $rc_hdr
