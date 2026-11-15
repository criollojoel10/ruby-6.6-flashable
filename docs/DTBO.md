# DTB / DTBO en ruby (MIUI vs kernel 6.6)

Datos medidos sobre los binarios reales (dump `boot_a`, `dtbo_a` y release
`rubyx-20261015`), no sobre documentación.

## Qué lleva cada partición

| Imagen | Contenido | Tamaño |
|---|---|---|
| `boot.img` (v2, page 2048) | `kernel` = `Image` gzip · `ramdisk` · **`dtb` (1 FDT, 170 KiB en MIUI / 179 KiB en 6.6)** | 128 MiB |
| `dtbo.img` | tabla `d7b7ab1e`, **1 entrada**, page 2048 → overlay de 76 KiB | 32 MiB |

El `dtb` del `boot` y el overlay del `dtbo` son cosas distintas:

- el **`dtb` del boot** es el árbol base;
- el **`dtbo`** es un overlay que el bootloader aplica *encima* del base, con
  `fragment@N { target = <&label>; __overlay__ { ... }; }`.

## Solapamiento de labels (la buena noticia)

```
labels en el dtb base 6.6 (release) ...... 445
labels en el dtb base MIUI 4.19 .......... 426
targets del dtbo stock de MIUI ........... 63
targets del dtbo stock que faltan en 6.6 .. 0
```

Es decir: **el `dtbo` stock de MIUI aplica sin errores sobre el `dtb` base del
kernel 6.6**. Por eso el zip principal (`miui-base-dtb`) deja el `dtbo` como
está y sólo reemplaza kernel + `dtb` dentro del `boot`.

## Qué agrega cada overlay

El `dtbo` de MIUI (92 fragmentos) tiene dos cosas que el `ruby.dtbo` del 6.6
(93 fragmentos) no tiene:

```
fragment -> &chosen      : atag,videolfb-{fb_base_l,fb_base_h,islcmfound,
                           islcm_inited,fps,vramSize,lcmname}
fragment -> &mt6360_pmu  : mt6360,intr_gpio_num / intr_gpio
```

Y el `ruby.dtbo` 6.6 agrega nodos que MIUI no tiene:

```
target-path /wifi@18000000      (nodo WiFi del combo MTK)
target-path /seninf_top@1a004000 (SENINF de cámara)
target      &consys             (connectivity subsystem)
```

Sin esos tres, el kernel 6.6 puede arrancar pero WiFi/consys no enganchan.

## dtbo híbrido

`dtbo-hybrid-<TAG>.img` = `ruby.dtbo` (6.6) **+** los dos fragmentos de MIUI,
fusionados a nivel de fuente y recompilados:

```sh
dtc -I dtb -O dts -o ruby.dtbo.dts ruby.dtbo
python3 tools/merge-dtbo.py ruby.dtbo.dts dtb/miui-extras.dts -o hybrid.dts
dtc -@ -I dts -O dtb -o hybrid.dtb hybrid.dts
python3 mkdtboimg.py create --page_size=2048 dtbo-hybrid.img hybrid.dtb
```

`merge-dtbo.py` sólo concatena los `fragment@N`, renumera y descarta
`__symbols__` / `__fixups__` / `__local_fixups__` (dtc los regenera con `-@`).

Validación hecha en local: aplicar el híbrido al `dtb` 6.6 con `fdtoverlay`
deja `chosen` con los `atag,videolfb-*`, `mt6360,intr_gpio_num = <4>`,
`/wifi@18000000`, `/seninf_top@1a004000` y `consys@18000000`.

## Por qué el boot no lleva los overlays ya aplicados

Podría hornearse todo en un solo FDT (`fdtoverlay`), pero entonces el `dtbo`
stock de MIUI se volvería a aplicar encima en cada arranque. Sumar dos veces un
overlay es idempotente en general, pero si un `target-path` define nodos
duplicados el bootloader aborta. Mantener el `dtbo` aparte es lo que hacen
MoonWake y Lineage, y es reversible sin tocar el `boot`.

## Memoria y pstore

El `dtb` **no** trae nodo `/memory`: lo inyecta el bootloader en cada arranque.
Tampoco hay nodo `ramoops`; la región la pasa LK por cmdline
(`ramoops.mem_address=0x48090000`, `size=0xe0000`, fuera del `System RAM`
declarado), así que el 6.6 la usa igual que el 4.19. Ver `docs/LOGS.md`.
