# ruby-6.6-flashable

Kernel **6.6.143** para el **Redmi Note 12 Pro / Pro+ 5G / Discovery (`ruby`, MT6877V)**
construido desde [`RubyxLabs/android_kernel_xiaomi_mt6877`](https://github.com/RubyxLabs/android_kernel_xiaomi_mt6877)
(`lineage-24.0`) y empaquetado al estilo [`DXRN-MoonWake/KernelAction`](https://github.com/DXRN-MoonWake/KernelAction)
para poder flashearlo sobre **MIUI / HyperOS** (Android 14, vendor 4.19) sin reemplazar el ramdisk.

El pipeline de build reutiliza los arreglos ya validados en
[`ruby-droid-kernel-build`](https://github.com/criollojoel10/ruby-droid-kernel-build)
(header de IOMMU vendorizado, audio DSP fuera, `-Werror` desactivado, auto-cura de includes).

## Qué produce cada build

| Archivo | Para qué |
|---|---|
| `AnyKernel3-…-miui-base-dtb.zip` | **Principal.** Kernel + `mt6877.dtb` base. Conserva el ramdisk de MIUI y usa el `dtbo` que ya tengas. |
| `AnyKernel3-…-miui-combined-dtb.zip` | Fallback: DTB combinado (ruby ya fusionado, sin overlay). |
| `dtbo-….img` | Overlay Ruby 6.6 (`fastboot flash dtbo`). Es el que hace juego con el kernel. |
| `Image.gz`, `mt6877.dtb`, `ruby.dtbo` | Imágenes crudas para repack manual. |
| `config-…` / `SHA256SUMS` | Config exacta y hashes. |

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
- El vermagic no importa en MIUI: no hay módulos 6.6 que cargar.

## Backups (Termux con root)

```sh
su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a-stock.img'
su -c 'dd if=/dev/block/by-name/dtbo_a of=/sdcard/dtbo_a-stock.img'
su -c 'dd if=/dev/block/by-name/vbmeta_a of=/sdcard/vbmeta_a-stock.img'
# slot b: repetir con boot_b, dtbo_b, vbmeta_b
```

## Camino A — fastboot (recomendado)

Repackeá el `boot.img` stock con su ramdisk (Magisk incluido si ya lo tenías):

```sh
./tools/repack-boot.sh boot_a-stock.img Image.gz mt6877.dtb boot-6.6-miui.img
```

Flasheo:

```sh
fastboot flash boot boot-6.6-miui.img
fastboot flash dtbo dtbo-<TAG>.img
fastboot --disable-verity --disable-verification flash vbmeta vbmeta_a-stock.img
fastboot reboot
```

Orden alternativo si AVB se queja: primero `vbmeta`, después `boot` y `dtbo`.

Verificación tras bootear:

```sh
uname -r   # 6.6.143-ruby66-miui-g<hash>
```

## Camino B — OrangeFox + AnyKernel3

1. Flasheá OrangeFox y luego "Flash current OrangeFox" (según la guía de MoonWake).
2. Sideload del zip: `adb sideload AnyKernel3-…-miui-base-dtb.zip`.
3. Flasheá el `dtbo-….img` (fastboot u OrangeFox → flash image → dtbo).
4. Reiniciá.

Si el equipo queda en bootloop/pantalla negra con el zip base, probá
`AnyKernel3-…-miui-combined-dtb.zip`.

## Rescate

```sh
fastboot flash boot boot_a-stock.img
fastboot flash dtbo dtbo_a-stock.img
fastboot --disable-verity --disable-verification flash vbmeta vbmeta_a-stock.img
fastboot reboot
```

## Compilar

GitHub → Actions → **Build ruby 6.6 flashable (MIUI/HyperOS)** → *Run workflow*.

- `kernel_ref`: `lineage-24.0` (o un commit fijo).
- `ksu`: `false` si usás Magisk (recomendado en MIUI). `true` integra KernelSU-Next.
- `localversion`: sufijo de `uname -r`.

Cada build publica un **release prerelease** con todos los archivos, además del
artifact de Actions.

## Créditos

- Kernel: [RubyxLabs](https://github.com/RubyxLabs) (GPL-2.0).
- Idea de empaquetado/CI y AnyKernel3 para ruby: [DXRN-MoonWake](https://github.com/DXRN-MoonWake).
- Arreglos de compilación del snapshot: `ruby-droid-kernel-build`.
