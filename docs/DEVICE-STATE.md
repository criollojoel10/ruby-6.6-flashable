# Estado verificado del dispositivo (2026-11-15)

Todo medido con `su` sobre el equipo, no deducido de documentación vieja.

## Slots

```
ro.boot.slot_suffix = _a        (Android/MIUI corriendo en _a)
ro.boot.verifiedbootstate = green
ro.boot.veritymode = enforcing
```

`lpdump` del `super` (virtual A/B):

| partición lógica | extents |
|---|---|
| `product_a`, `system_a`, `system_ext_a`, `vendor_a` | presentes |
| `*_b` | **sin extents** (vacías) |

Conclusión: **el slot `_b` no puede arrancar Android**. No es una vía de
recuperación ni de prueba. Lo que haya en `boot_b` no sirve para volver a un
sistema funcional.

## Qué hay realmente en cada boot

Medido con `magiskboot unpack` y hashes completos de 128 MiB:

| partición | kernel | ramdisk | dtb | md5 del boot |
|---|---|---|---|---|
| `boot_a` **vivo** | 4.19.191-ge6429b82e599, `KERNEL_SZ` 16 798 312 | 18 292 495 B | 170 180 B | `5a36c0c5…` |
| `boot_a` **prístino** (`/data/adb/ap/ori.img`) | `KERNEL_SZ` 16 715 274 | idéntico | idéntico | `797f292e…` |
| `boot_b` | idéntico al prístino | idéntico | idéntico | `797f292e…` |

El `boot_a` vivo está **parcheado por APatch**: su kernel pesa 83 038 B más
(el payload de KernelPatch) y su ramdisk/dtb son idénticos al original.
`/data/adb/ap/ori.img` es la copia prístina que guardó APatch, y **`boot_b` es
byte a byte la misma imagen** (`797f292e…`), o sea que hay una copia del boot
stock intacta en el propio teléfono.

`boot_b` **no** tiene el kernel de Kupfer: es el boot de MIUI stock. Igual no
sirve para arrancar Android (no hay sistema en `_b`).

Backup: `boot_a-stock.img` (dump de la partición viva) es el boot **con
APatch**; `boot_a-pristine.img` / `boot_b-stock.img` son el boot **stock sin
root**. Para restaurar sin perder root, usá el primero; para volver a stock
limpio, el segundo.

## Otras particiones

| partición | estado |
|---|---|
| `vendor_boot_a/b` | 64 MiB **a ceros** |
| `dtbo_a` / `dtbo_b` | cabecera idéntica; 1 entrada de 76 863 B |
| `vbmeta_a` | AVB0 v0.1, flags 1 (disable-verity), rollback 1635148404 |
| `misc` | `bootloader_control` válido (`_a` + `BCAB`, versión 1.2), **sin comando BCB pendiente** |
| `super` cola libre (offset 7 944 339 456) | a ceros: no hay imagen ext4 de Kupfer ahí |

## OrangeFox

`/sdcard/Fox/.foxs` + `/sdcard/Fox/logs/lastrecoverylog.log`:

```
OrangeFox Recovery R12.0 ... for ruby  (slot _a)
FOX_KERNEL=4.19.191-g343cba0f96f4
INCREMENTAL_VERSION=OS2.0.16.0.UMOMIXM
```

OFOX corre con **su** kernel 4.19, distinto del de `boot_a`, y `boot_a` sigue
siendo MIUI: OFOX **no está instalado** en ninguna partición de boot (no hay
`recovery`, `vendor_boot` está en ceros). Se arranca de forma temporal
(`fastboot boot` / OTG), que es justo el caso bueno para AnyKernel3: el zip
lee el `boot_a` real de MIUI y le escribe kernel + dtb.

> Si algún día OFOX se instala *dentro* de `boot_a`, **no** hay que flashear
> el zip de AnyKernel3 desde ahí: parchearía el ramdisk de OFOX. En ese caso
> se usa `boot-6.6-miui.img` ya armado (Install Image → Boot).

## Root: APatch (verificado en el equipo)

```
$ su -c 'su --version'
11282:APatch

$ pm list packages | grep -i apatch
package:me.bmax.apatch

$ su -c 'ls /data/adb'
ap  apd  boot-completed.d  lspd  modules  post-fs-data.d  post-mount.d
rezygisk  service.d  teesim  tricky_store  ...

$ su -c 'ls /data/adb/modules'
hma_oss_zygisk  playintegrityfix  rezygisk  teesim  zygisk_lsposed

$ ls /data/adb/magisk
(no existe)
```

O sea: **APatch 11282 (0.13.9) instalado y funcionando**, sin Magisk. El
`context=u:r:magisk:s0` del `su` es sólo el dominio SELinux que usa APatch por
compatibilidad, no indicio de Magisk.

- APatch guarda el boot original en `/data/adb/ap/ori.img` (prístino, ver
  arriba) y el parche de KernelPatch va **dentro del kernel** del `boot`.
- Cualquier kernel nuevo (6.6 incluido) arranca **sin root**; se re-parchea
  eligiendo el `boot.img` nuevo en APatch, que reutiliza la superkey ya
  configurada (no hay que volver a escribirla).
- Requisitos que el 6.6 cumple: `CONFIG_KALLSYMS=y`, `CONFIG_KALLSYMS_ALL=y`,
  `CONFIG_KPROBES=y`, `CONFIG_MODULES=y`, kernel dentro del rango 3.18–6.12 y
  kCFI (`CONFIG_CFI_CLANG=y`, soportado por KernelPatch).

## Recuperación realista

1. OFOX temporal (`fastboot boot ofox.img`, o desde otro Android por OTG).
2. OFOX → *Install Image* → `boot_a-stock.img` (stock **con APatch**) o
   `boot_a-pristine.img` (stock limpio) → **Boot**.
3. Reiniciar.

Sin OFOX arrancable, la única vuelta es fastboot/OTG: el backup en `/sdcard`
no se puede aplicar desde un teléfono que no arranca. Como `boot_b` es byte a
byte el boot stock, también se puede recuperar copiando esa partición a
`boot_a` desde OFOX.
