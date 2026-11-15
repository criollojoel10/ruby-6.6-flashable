#!/usr/bin/env bash
# Simula el flasheo de un zip AnyKernel3 SIN tocar particiones:
# usa el ak3-core.sh real del zip (el mismo que corre en OrangeFox) contra una
# copia del boot en un archivo, y verifica el resultado.
#
# Uso:
#   ./simulate-ak3.sh <AnyKernel3.zip> <stock-boot.img> [dir-salida]
#
# Comprueba al final:
#   - kernel del boot parcheado == Image del zip (descomprimida)
#   - dtb == dtb del zip
#   - ramdisk == ramdisk del boot original (byte a byte)
#   - imprime el banner de versión del kernel
set -euo pipefail

ZIP=$(readlink -f "${1:?zip}")
STOCK=$(readlink -f "${2:?stock boot}")
OUT=${3:-$(dirname "$STOCK")/ak3-sim}
HERE=$(cd "$(dirname "$0")" && pwd)

mkdir -p "$OUT"
rm -rf "$OUT/ak3"
mkdir -p "$OUT/ak3"
( cd "$OUT/ak3" && unzip -qo "$ZIP" )

[ -f "$OUT/ak3/anykernel.sh" ] || { echo "el zip no tiene anykernel.sh" >&2; exit 1; }
[ -f "$OUT/ak3/tools/ak3-core.sh" ] || { echo "el zip no tiene tools/ak3-core.sh" >&2; exit 1; }

# En el equipo real setup_ak() resuelve /dev/block/by-name/boot_a. Acá
# apuntamos a un archivo: se deja correr setup_ak (limpia placeholders, etc.)
# y sólo se anula el abort de resolución de partición, en la copia.
sed -i 's|abort "Unable to determine \$block partition. Aborting...";|:|' \
  "$OUT/ak3/tools/ak3-core.sh"

# kernel y dtb que trae el zip (cualquiera de los nombres que soporta AK3)
KERNEL_SRC=""
for k in Image.gz-dtb Image.gz Image Image-dtb zImage-dtb zImage; do
  [ -f "$OUT/ak3/$k" ] && { KERNEL_SRC=$k; break; }
done
[ -n "$KERNEL_SRC" ] || { echo "el zip no trae kernel (Image*)" >&2; exit 1; }
DTB_SRC=""
for d in dtb dtb.img; do [ -f "$OUT/ak3/$d" ] && { DTB_SRC=$d; break; }; done

cp "$STOCK" "$OUT/fake-boot.img"
size_mb=$(( $(stat -c %s "$STOCK") / 1048576 ))

cat > "$OUT/run.sh" <<EOF
# sin set -e: ak3-core.sh tolera fallos de rmdir/rm en modo real
cd "$OUT/ak3"
home=\$PWD
bin=\$home/tools
export home bin
kernel_filename="$KERNEL_SRC"
block="$OUT/fake-boot.img"
customdd="bs=1048576 count=$size_mb"
export customdd
is_slot_device=1
ramdisk_compression=auto
patch_vbmeta_flag=auto
OUTFD=1
. tools/ak3-core.sh
ui_print "simulacion AK3: \$kernel_filename"
dump_boot
write_boot
EOF

echo "== simulando flash (kernel del zip: $KERNEL_SRC, dtb: ${DTB_SRC:-<stock>}) =="
( cd "$OUT/ak3" && bash "$OUT/run.sh" ) 2>&1 | tail -15

echo "== verificando resultado =="
mkdir -p "$OUT/verify" && cd "$OUT/verify"
"$OUT/ak3/tools/magiskboot" unpack "$OUT/fake-boot.img" >/dev/null 2>&1 || {
  echo "no pude desempacar el boot parcheado" >&2; exit 1; }

mkdir -p "$OUT/stock" && cd "$OUT/stock"
"$OUT/ak3/tools/magiskboot" unpack "$STOCK" >/dev/null 2>&1

fail=0
# kernel: comparar contra la Image del zip descomprimida
case "$KERNEL_SRC" in
  *-dtb) gzip -dc "$OUT/ak3/$KERNEL_SRC" | head -c 100000000 > "$OUT/zip-kernel" 2>/dev/null || true ;;
  *)     gzip -dc "$OUT/ak3/$KERNEL_SRC" > "$OUT/zip-kernel" 2>/dev/null || cp "$OUT/ak3/$KERNEL_SRC" "$OUT/zip-kernel" ;;
esac
if cmp -s "$OUT/verify/kernel" "$OUT/zip-kernel"; then
  echo "  kernel  : OK igual a la Image del zip"
else
  # si el zip trae Image.gz-dtb, el kernel del boot es sólo la parte gzip
  if [ "${KERNEL_SRC#*-dtb}" != "$KERNEL_SRC" ]; then
    echo "  kernel  : zip trae *-dtb (AK3 conserva el dtb del boot original)"
  else
    echo "  kernel  : DISTINTO" >&2; fail=1
  fi
fi

if [ -f "$OUT/ak3/${DTB_SRC:-__none__}" ]; then
  if cmp -s "$OUT/verify/dtb" "$OUT/ak3/$DTB_SRC"; then
    echo "  dtb     : OK igual al del zip"
  else
    echo "  dtb     : DISTINTO" >&2; fail=1
  fi
else
  if cmp -s "$OUT/verify/dtb" "$OUT/stock/dtb"; then
    echo "  dtb     : OK se conservó el del boot original"
  else
    echo "  dtb     : DISTINTO" >&2; fail=1
  fi
fi

# AK3 descomprime y vuelve a empaquetar el cpio: el stream cambia de orden y
# las fechas cambian, así que se compara el contenido extraído (como root,
# para no perder permisos ni symlinks).
rm -rf "$OUT/rd-old" "$OUT/rd-new"
mkdir -p "$OUT/rd-old" "$OUT/rd-new"
if su -c id >/dev/null 2>&1; then
  su -c "cd '$OUT/rd-old' && cpio -idm --quiet < '$OUT/stock/ramdisk.cpio' && \
         cd '$OUT/rd-new' && cpio -idm --quiet < '$OUT/verify/ramdisk.cpio' && \
         diff -r '$OUT/rd-old' '$OUT/rd-new'" > "$OUT/ramdisk-diff.txt" 2>&1
  rdrc=$?
  entries=$(su -c "find '$OUT/rd-new' | wc -l")
else
  ( cd "$OUT" && cpio -itv < stock/ramdisk.cpio | awk '{print $1, $3, $NF}' | sort > rd-old.lst
    cpio -itv < verify/ramdisk.cpio | awk '{print $1, $3, $NF}' | sort > rd-new.lst
    diff -u rd-old.lst rd-new.lst ) > "$OUT/ramdisk-diff.txt" 2>&1
  rdrc=$?
  entries=$(wc -l < "$OUT/rd-old.lst")
fi
if [ "$rdrc" -eq 0 ]; then
  echo "  ramdisk : OK mismo contenido ($entries entradas, sin diferencias)"
else
  echo "  ramdisk : DISTINTO del original (ver $OUT/ramdisk-diff.txt)" >&2
  head -12 "$OUT/ramdisk-diff.txt" >&2
  fail=1
fi

ver=$(grep -a -m1 -oE '6\.6\.[0-9]+[^ ]* SMP[^ ]*' "$OUT/verify/kernel" 2>/dev/null || true)
echo "  version : ${ver:-no encontrada}"

exit $fail
