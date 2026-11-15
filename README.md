# ruby-6.6-flashable

Kernel **6.6.143** para el **Redmi Note 12 Pro / Pro+ 5G / Discovery (`ruby`, MT6877V)**
construido desde [`RubyxLabs/android_kernel_xiaomi_mt6877`](https://github.com/RubyxLabs/android_kernel_xiaomi_mt6877)
(`lineage-24.0`) y empaquetado al estilo [`DXRN-MoonWake/KernelAction`](https://github.com/DXRN-MoonWake/KernelAction).

Es **universal**: el zip conserva el ramdisk que ya tenga el teléfono, así que
sirve tanto para **MIUI/HyperOS** (Android 14, vendor 4.19) como para
**AOSP/Lineage** (A16/A17). Ver [`docs/UNIVERSAL.md`](docs/UNIVERSAL.md) para la
evidencia (ramdisk gzip de MIUI vs lz4 de Lineage, drivers MTK built-in,
solape de labels del dtbo, configs de Android moderno).

Dos sabores por build: **vanilla** y **KSU** (`CONFIG_KSU=y`, KernelSU-Next).

El pipeline de build reutiliza los arreglos ya validados en
[`ruby-droid-kernel-build`](https://github.com/criollojoel10/ruby-droid-kernel-build)
(header de IOMMU vendorizado, audio DSP fuera, `-Werror` desactivado, auto-cura de includes).

## Qué produce cada build

| Archivo | Para qué |
|---|---|
| `AnyKernel3-…-base-dtb.zip` | **Principal y universal.** Kernel + `mt6877.dtb` base; conserva ramdisk y `dtbo` del equipo. |
| `AnyKernel3-…-combined-dtb.zip` | Fallback: DTB combinado (ruby ya fusionado, sin overlay). |
| `dtbo-….img` | Overlay Ruby 6.6, para `fastboot flash dtbo`. |
| `dtbo-hybrid-….img` | Overlay 6.6 + extras del dtbo de MIUI (videolfb y mt6360). |
| `boot-6.6-miui-….img` / `boot-6.6-aosp-….img` | Boot ya armado con el ramdisk MIUI / Lineage, para flashear como imagen. |
| `Image.gz`, `mt6877.dtb`, `ruby.dtbo` | Imágenes crudas para repack manual. |
| `config-…` / `SHA256SUMS` | Config exacta y hashes. |

Los `boot-*.img` los arma `tools/assemble.sh` a partir del dump del equipo; el
release los incluye ya verificados.

## Requisitos y advertencias

- Bootloader desbloqueado y **MIUI/HyperOS ya configurado**: si flasheás el kernel
  antes de terminar el setup inicial, no vas a poder completarlo.
- **Respaldá `boot`, `dtbo` y `vbmeta` antes de tocar nada.** Sin eso no hay rescate.
- Los `.ko` de MIUI son de 4.19 y **no cargan** en 6.6. No hacen falta: en este árbol
  los drivers MTK (panel, táctil, PMIC/carga, WiFi/BT/GPS, etc.) van *built-in*
  (`CONFIG_WLAN_DRV_BUILD_IN=y`, `CONFIG_MTK_COMBO_*=y`). Los `modprobe` fallidos
  de `/vendor/lib/modules` son inofensivos.
- `CONFIG_MTK_AUDIODSP_SUPPORT` queda desactivado porque el snapshot público no
  trae los headers del audio DSP. El audio ASoC normal compila; pueden faltar
  funciones avanzadas de offload/DSP.
- El vermagic no importa en ningún caso: el vendor de RubyxLabs no trae `.ko`
  y los drivers necesarios van built-in, así que no hay módulos externos que enganchar.

## Backups (Termux con root)

```sh
su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a-stock.img'
su -c 'dd if=/dev/block/by-name/dtbo_a of=/sdcard/dtbo_a-stock.img'
su -c 'dd if=/dev/block/by-name/vbmeta_a of=/sdcard/vbmeta_a-stock.img'
# slot b: repetir con boot_b, dtbo_b, vbmeta_b
```

## Orden de pruebas (OrangeFox)

Tenés OFOX y un `boot.img` de restauración, así que se puede iterar sin PC.
Empezá por lo más conservador y avanzá sólo si falla:

| # | Qué flashear | Qué conserva | Cuándo pasar al siguiente |
|---|---|---|---|
| 0 | `boot-6.6-miui.img` (imagen ya armada) | ramdisk MIUI exacto | no bootea / pantalla negra |
| 1 | `AnyKernel3-…-miui-base-dtb.zip` | ramdisk **y** `dtbo` de MIUI | no bootea / pantalla negra |
| 2 | zip 1 + `dtbo-hybrid-….img` (dtbo) | ramdisk MIUI; dtbo = 6.6 + extras MIUI | sigue sin bootear |
| 3 | `AnyKernel3-…-miui-combined-dtb.zip` | ramdisk MIUI | — |

La opción 0 es la más segura: el `boot.img` se arma en local con el dump
`boot_a` del equipo (`tools/repack-boot.sh`) y se flashea como imagen desde
OFOX (*Install Image* → Boot) o por `dd` desde Android con root. No depende de
que el recovery pueda leer/parchear el boot.

El zip 1 replica a MoonWake: kernel + `dtb` base dentro de `boot`, sin tocar
`dtbo`. Es seguro **porque OFOX se arranca temporalmente** y entonces lee el
`boot_a` real de MIUI (ver `docs/DEVICE-STATE.md`).

El `dtbo-hybrid` es para cuando el equipo arranca pero **WiFi/consys** o el
panel no funcionan: agrega los nodos 6.6 (`wifi@18000000`, `seninf_top`,
`consys`) y a la vez conserva del `dtbo` de MIUI los `atag,videolfb-*` del
`chosen` y el GPIO de IRQ del `mt6360`.

## Camino A — OrangeFox (on-device, recomendado)

1. OFOX → *Install* → elegí el zip de AnyKernel3 → *Swipe to flash*.
2. Si vas a probar el híbrido: *Install* → *Install Image* → `dtbo-hybrid-….img`
   → destino **Dtbo**.
3. Reiniciá a sistema y verificá `uname -r`.

AnyKernel3 conserva el ramdisk tal cual y reemplaza sólo kernel y `dtb`.

### Root: APatch (recomendado)

APatch parchea **el kernel** del `boot`, así que cualquier kernel nuevo arranca
sin root. El flujo es de dos pasos y usa la variante **vanilla**:

**Ya con APatch funcionando (tu caso), es un solo paso sin perder root:**

1. Copiás `boot-6.6-miui-…img` a `/sdcard/Download`.
2. APatch → *Install* → elegís ese `boot.img` → *Patch* (usa tu superkey) →
   genera `apatch_patched_11282_….img` con **el kernel 6.6 dentro**.
3. Flasheás ese `apatch_patched_….img` en `boot` (OFOX → *Install Image*, o
   `tools/flash-boot.sh`).

Así el teléfono arranca ya con 6.6 **y** root APatch, sin pasar por un arranque
sin root. Si preferís primero validar el kernel sin root, flasheás el
`boot-6.6-miui-…img` tal cual y después repetís el paso 2 con la misma imagen.

Requisitos de APatch que este kernel cumple: `CONFIG_KALLSYMS=y`,
`CONFIG_KALLSYMS_ALL=y`, `CONFIG_KPROBES=y`, kernel 6.6 (APatch soporta 3.18–6.12)
y kCFI (`CONFIG_CFI_CLANG=y`, KernelPatch lo maneja desde 2025).

**No uses Magisk.** Y no mezcles: la variante `ksu` ya trae KernelSU-Next y es
alternativa a APatch, no complemento.

Antes de reiniciar, limpiá pstore para que el log del intento sea el nuevo:

```sh
su -c 'rm -f /sys/fs/pstore/*'
```

## Camino B — fastboot, con `boot.img` ya armado

Repack del `boot` stock conservando su ramdisk exacto (necesita `magiskboot`):

```sh
./tools/repack-boot.sh boot_a-stock.img Image.gz mt6877.dtb boot-6.6-miui.img
```

```sh
fastboot flash boot boot-6.6-miui.img
fastboot reboot
```

Sólo si vas a probar el dtbo híbrido:

```sh
fastboot flash dtbo dtbo-hybrid-<TAG>.img
```

Verificación:

```sh
uname -r   # 6.6.143-android15-8-4k-Singularity-ruby66-g<hash>
```

## Logs cuando algo falla

Ver [`docs/LOGS.md`](docs/LOGS.md). Resumen: LK ya le pasa a **todo** kernel

```
ramoops.mem_address=0x48090000 ramoops.mem_size=0xe0000 ...
```

y `ruby_defconfig` trae `CONFIG_PSTORE*`, así que el 6.6 escribe el panic en
`/sys/fs/pstore/console-ramoops-0` sin parches. Limpiá pstore **antes** de
flashear (no se sobreescribe solo) y leelo desde Android u OFOX.

## Rescate — OrangeFox (sin PC)

Estado del equipo verificado en [`docs/DEVICE-STATE.md`](docs/DEVICE-STATE.md):
Android está en el slot **`_a`**, el `super` **no tiene sistema en `_b`** y
OFOX se arranca temporalmente (no vive en ninguna partición de boot). O sea:
**el slot `_b` no es una vía de recuperación**.

1. OFOX → *Install* → *Install Image* → `boot_a-stock.img` → **Boot**.
2. Si tocaste el dtbo: `dtbo_a-stock.img` → **Dtbo**
   (`vbmeta_a-stock.img` → **Vbmeta** sólo si AVB se queja).
3. Reiniciá y volvé a parchear con APatch.

Por fastboot:

```sh
fastboot flash boot boot_a-stock.img
fastboot flash dtbo dtbo_a-stock.img
fastboot reboot
```

> Si el kernel nuevo no arranca, el teléfono queda sin sistema: necesitás una
> forma externa de arrancar OFOX (`fastboot boot ofox.img`, u OTG desde otro
> Android). El backup en `/sdcard` no se puede aplicar solo.

## Compilar

GitHub → Actions → **Build ruby 6.6 flashable (MIUI/HyperOS)** → *Run workflow*.

- `kernel_ref`: `lineage-24.0` (o un commit fijo).
- `variants`: `both` (default, compila vanilla + KSU en un solo run con matriz),
  `vanilla` o `ksu`.
- `ksu_ref`: commit/tag de KernelSU-Next (vacío = último tag).
- `make_release`: publica un release único con todo lo compilado.

Un run con `both` lanza dos jobs en paralelo (cada variante es un kernel
distinto porque `CONFIG_KSU` cambia el binario) y el job `release` junta los
artefactos de las dos en un solo release.

Cada build publica un **release prerelease** con todos los archivos, además del
artifact de Actions.

## Créditos

- Kernel: [RubyxLabs](https://github.com/RubyxLabs) (GPL-2.0).
- Idea de empaquetado/CI y AnyKernel3 para ruby: [DXRN-MoonWake](https://github.com/DXRN-MoonWake).
- Arreglos de compilación del snapshot: `ruby-droid-kernel-build`.
