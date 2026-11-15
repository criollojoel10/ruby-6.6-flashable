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

| partición | kernel | ramdisk | dtb |
|---|---|---|---|
| `boot_a` | 4.19.191-ge6429b82e599 (MIUI) | Android (18.29 MB) | 170 180 B |
| `boot_b` | 4.19.191-ge6429b82e599 (MIUI, otra compilación) | Android (18.29 MB) | 170 180 B |

`boot_b` **no** tiene el kernel de Kupfer: es un boot de MIUI viejo. Igual no
sirve para arrancar Android (no hay sistema en `_b`).

Backup `boot_a` verificado: los primeros 2048 B del dump coinciden bit a bit
con la partición viva (`57ad5c69…`), así que `boot_a-stock.img` es una
restauración válida.

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

## Root

- APatch 0.13.9 (`apatch_patched_11282_0.13.9_ntti.img` en `Download`).
- El parche de APatch vive **dentro del kernel del boot**, así que cualquier
  kernel nuevo (6.6 incluido) arranca sin root: hay que volver a parchear con
  APatch eligiendo el `boot.img` nuevo.

## Recuperación realista

1. OFOX temporal (`fastboot boot ofox.img`, o desde otro Android por OTG).
2. OFOX → *Install Image* → `boot_a-stock.img` → **Boot**.
3. Reiniciar; re-parchear APatch.

Sin OFOX arrancable, la única vuelta es fastboot/OTG: el backup en `/sdcard`
no se puede aplicar desde un teléfono que no arranca.
