#!/usr/bin/env bash
# Flashea boot (y opcionalmente dtbo) desde Android con root, sin recovery.
#
# Uso:
#   ./flash-boot.sh boot-6.6-miui.img [dtbo-hybrid.img]
#
# - Detecta el slot activo (_a/_b) y escribe sólo ese.
# - Guarda un backup del boot/dtbo actual en /sdcard antes de tocar nada.
# - Limpia pstore para que el próximo panic sea el del kernel nuevo.
# - Verifica tamaño contra la partición y el magic "ANDROID!".
set -euo pipefail

IMAGE=${1:?falta la imagen de boot}
DTBO_IMAGE=${2:-}
SLOT=$(getprop ro.boot.slot_suffix)
[ -n "$SLOT" ] || { echo "no pude leer ro.boot.slot_suffix" >&2; exit 1; }
LETTER=${SLOT#_}
STAMP=$(date +%Y%m%d-%H%M%S)

[ -f "$IMAGE" ] || { echo "no existe $IMAGE" >&2; exit 1; }
head -c 8 "$IMAGE" | grep -q 'ANDROID!' || { echo "$IMAGE no parece un boot.img Android" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "falta $1" >&2; exit 1; }; }
need su
need dd
need sha256sum

boot_part="/dev/block/by-name/boot_${LETTER}"
dtbo_part="/dev/block/by-name/dtbo_${LETTER}"

isize=$(stat -c %s "$IMAGE")
psize=$(su -c "blockdev --getsize64 $boot_part" 2>/dev/null || echo 0)
[ "$psize" -gt 0 ] || { echo "no pude leer el tamaño de $boot_part" >&2; exit 1; }
[ "$isize" -le "$psize" ] || { echo "la imagen ($isize) no entra en $boot_part ($psize)" >&2; exit 1; }

echo "slot activo : $SLOT"
echo "boot        : $boot_part ($psize bytes) <- $IMAGE ($isize bytes)"
[ -n "$DTBO_IMAGE" ] && echo "dtbo        : $dtbo_part <- $DTBO_IMAGE"

echo "== backup del boot actual =="
su -c "dd if=$boot_part of=/sdcard/boot${SLOT}-preflash-${STAMP}.img bs=1M" 2>&1 | tail -1
if [ -n "$DTBO_IMAGE" ]; then
  su -c "dd if=$dtbo_part of=/sdcard/dtbo${SLOT}-preflash-${STAMP}.img bs=1M" 2>&1 | tail -1
fi

echo "== limpiando pstore =="
su -c 'rm -f /sys/fs/pstore/*' 2>/dev/null || true

echo "== escribiendo boot =="
su -c "dd if=$IMAGE of=$boot_part bs=1M conv=fsync" 2>&1 | tail -1

if [ -n "$DTBO_IMAGE" ]; then
  [ -f "$DTBO_IMAGE" ] || { echo "no existe $DTBO_IMAGE" >&2; exit 1; }
  echo "== escribiendo dtbo =="
  su -c "dd if=$DTBO_IMAGE of=$dtbo_part bs=1M conv=fsync" 2>&1 | tail -1
fi

echo "== verificación (sha del inicio de la partición) =="
su -c "dd if=$boot_part bs=1M count=$(( (isize / 1048576) + 1 )) 2>/dev/null" | head -c "$isize" | sha256sum
sha256sum "$IMAGE"

cat <<EOF

Listo. Reiniciá y comprobá:
    uname -r
Si no arranca, desde OFOX: Install Image -> /sdcard/boot${SLOT}-preflash-${STAMP}.img -> Boot
EOF
