# Tarjeta de flasheo (ruby, MIUI/HyperOS, APatch + OrangeFox)

Tag del build: `ruby66-<fecha>-<run>-<sha>-<vanilla|ksu>`

## 0. Antes de tocar nada

```sh
# backup del boot actual (con APatch) y del stock limpio
su -c 'dd if=/dev/block/by-name/boot_a of=/sdcard/boot_a-actual.img bs=1M'
su -c 'dd if=/data/adb/ap/ori.img  of=/sdcard/boot_a-pristino.img bs=1M'
su -c 'rm -f /sys/fs/pstore/*'      # para que el log del intento sea el nuevo
```

## 1. Vanilla + APatch (recomendado)

1. Copiá `boot-6.6-miui-<tag>.img` a `/sdcard/Download`.
2. APatch → *Install* → ese `boot.img` → *Patch* (usa tu superkey ya puesta).
3. Flasheá el `apatch_patched_11282_*.img` resultante en **boot**:
   - OFOX → *Install* → *Install Image* → destino **Boot**, o
   - desde Android con root: `tools/flash-boot.sh apatch_patched_11282_*.img`
4. Reiniciá y comprobá:

```sh
uname -r    # 6.6.143-android15-8-4k-Singularity-ruby66-g<sha>
```

## 2. KSU (alternativa, sin APatch)

1. OFOX → *Install* → `AnyKernel3-<tag>-base-dtb.zip` (variante `ksu`).
2. Reiniciá e instalá el manager de KernelSU-Next.
3. `uname -r` debe terminar en `-ruby66-ksu-g<sha>`.

No mezclar: si venías de APatch y flasheás la variante `ksu`, el root APatch
desaparece (el kernel es otro).

## 3. Universal (MIUI y AOSP A17)

- El **mismo zip** sirve para MIUI y para LineageOS/AOSP: conserva el ramdisk
  del equipo y sólo cambia kernel + `dtb`.
- En AOSP el `dtbo` es el del ROM; en MIUI el stock. El zip **no** toca `dtbo`.
- Si en MIUI falla WiFi/consys (o el panel), flasheá además
  `dtbo-hybrid-<tag>.img` en **Dtbo**.
- Boot prearmado por familia: `boot-6.6-miui-<tag>.img` (MIUI) y
  `boot-6.6-aosp-<tag>.img` (Lineage 24 / A17).

## 4. Si no arranca

1. OFOX temporal (`fastboot boot ofox.img` u OTG).
2. *Install Image* → `/sdcard/boot_a-actual.img` → **Boot** (vuelve con APatch).
3. Leé el log del intento fallido:

```sh
su -c 'cat /sys/fs/pstore/console-ramoops-0' | tail -60
```

Más detalle en `docs/LOGS.md` y `docs/DEVICE-STATE.md`.
