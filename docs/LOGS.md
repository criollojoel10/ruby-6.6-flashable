# Capturar logs en ruby (MIUI/HyperOS)

Referencias: `criollojoel10/ruby-nura` (`docs/KERNEL.md`, `tools/flash-boot-a.sh`)
y `criollojoel10/ruby-mainline` (`docs/PLAN.md`, `docs/TEST-PLAN.md`).

## pstore/ramoops: el log que sobrevive a un panic

El bootloader de ruby (LK) le pasa al kernel, en **cada** arranque:

```
ramoops.mem_address=0x48090000
ramoops.mem_size=0xe0000
ramoops.pmsg_size=0x10000
ramoops.console_size=0x40000
```

Esa región queda fuera del `System RAM` que LK declara (`40000000-4807ffff`
en el mapa actual), así que el kernel 6.6 la usa igual que el 4.19 de MIUI sin
pisar RAM del sistema. `ruby_defconfig` ya trae:

```
CONFIG_PSTORE=y
CONFIG_PSTORE_CONSOLE=y
CONFIG_PSTORE_RAM=y
CONFIG_PSTORE_PMSG=y
```

…por lo que **el kernel 6.6 escribe pstore sin parches ni nodos de DT extra**.

### Regla de oro

`ramoops` **no sobreescribe** el registro anterior (escribe al lado y rota
lento). Si no limpiás antes de flashear, después leés el panic viejo y parece
que el kernel nuevo no arrancó.

```sh
# ANTES de flashear (Android con root / APatch / KernelSU)
su -c 'rm -f /sys/fs/pstore/*; ls -l /sys/fs/pstore/'

# DESPUÉS de un intento fallido, de vuelta en Android
su -c 'ls -l /sys/fs/pstore/'
su -c 'cat /sys/fs/pstore/console-ramoops-0' > /sdcard/console-ramoops-0.txt
```

El archivo se puede leer también desde OrangeFox (Mount → data, luego
`/data/system/dropbox` no; usá la terminal de OFOX):

```sh
mkdir -p /mnt/pstore && mount -t pstore pstore /mnt/pstore 2>/dev/null
ls -l /mnt/pstore && cat /mnt/pstore/console-ramoops-0
```

Si pstore está vacío tras un bootloop, el fallo es anterior al `pstore`
(`memblock`, descompresión del kernel, DTB) o el kernel ni siquiera arrancó.

## dmesg del arranque que sí bootea

```sh
su -c 'dmesg' > /sdcard/dmesg-6.6.txt
su -c 'dmesg | grep -iE "wlan|wifi|conninfra|consys|btmtk|nvram"' | head -80
su -c 'dmesg | grep -iE "mt6360|charger|gauge|battery"' | head -60
su -c 'dmesg | grep -iE "panel|lcm|dsi|drm"' | head -60
```

Filtros rápidos para ver si el kernel es el nuestro:

```sh
uname -r                            # 6.6.143-...-g<hash>
cat /proc/version
su -c 'cat /proc/cmdline'           # misma cmdline de LK
```

## Recolector (root) para adjuntar a un issue

```sh
su -c '
  out=/sdcard/ruby66-logs-$(date +%Y%m%d-%H%M%S)
  mkdir -p $out
  dmesg                    > $out/dmesg.txt
  cat /proc/version        > $out/version.txt
  cat /proc/cmdline        > $out/cmdline.txt
  uname -a                 > $out/uname.txt
  cat /proc/last_kmsg      > $out/last_kmsg.txt 2>/dev/null
  cp -a /sys/fs/pstore/.  $out/pstore/ 2>/dev/null
  getprop                  > $out/getprop.txt
  ls -l /vendor/lib/modules > $out/vendor-modules.txt
  logcat -b all -d         > $out/logcat.txt 2>/dev/null
  tar -C /sdcard -czf $out.tar.gz $(basename $out)
  echo $out.tar.gz
'
```

## Vuelta atrás (OrangeFox, sin PC)

1. OFOX → *Install* → *Install Image* → elegí `boot_a-stock.img` →
   destino **Boot**.
2. Si hace falta, lo mismo con `dtbo_a-stock.img` → **Dtbo** y
   `vbmeta_a-stock.img` → **Vbmeta** (con *disable verity/verification*).
3. Reiniciá. Si el slot activo es `_b`, usá los `*_b` correspondientes.

Con APatch: tras restaurar el boot original, reabrí APatch y volvé a parchear
(su parche va dentro del kernel del boot, así que cualquier flash de kernel lo
borra).
