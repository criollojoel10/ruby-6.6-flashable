# Por qué un solo kernel sirve para MIUI y AOSP (A16/A17)

Resumen de la evidencia medida, no de suposiciones.

## 1. El zip no trae ramdisk

AnyKernel3 hace `dump_boot` → `write_boot`: descomprime el ramdisk **del boot
que ya está en el teléfono**, mete el kernel/dtb nuevos y lo vuelve a
comprimir con el mismo formato. Nunca escribe un ramdisk propio.

Comprobado en local con los dos `boot.img` reales:

| base | ramdisk | resultado |
|---|---|---|
| `boot_a` MIUI (HyperOS 2.0.16) | `gzip`, 18.29 MB | `boot-6.6-miui-*.img`, ramdisk idéntico por SHA-256 |
| `boot` LineageOS 24 (rubyx-20261015) | `lz4_legacy` | `boot-6.6-aosp-*.img`, ramdisk idéntico por SHA-256 |

Es decir: **el mismo `Image.gz` + `mt6877.dtb` produce un boot válido para las
dos familias**; sólo cambia el ramdisk que ya estaba ahí. Por eso el zip es
universal y no hay "zip para MIUI" y "zip para AOSP".

## 2. Los drivers MTK van dentro del kernel, no en módulos

`ruby_defconfig` (6.6.143) tiene:

```
CONFIG_WLAN_DRV_BUILD_IN=y      WiFi/BT/GPS dentro del kernel
CONFIG_MTK_COMBO_CHIP_CONSYS_6877=y
CONFIG_MTK_COMBO_BT=y / _GPS=y / _WIFI=y
CONFIG_MTK_CONNFEM=y
CONFIG_MTK_FMRADIO=y
CONFIG_MTK_FPSGO_V3=y
CONFIG_MACH_MT6877=y
```

Y el árbol vendor de RubyxLabs **no trae ningún `.ko`**. Consecuencias:

- En AOSP/A17 no hay módulos que cargar: el kernel no depende del `vendor_dlkm`.
- En MIUI los `/vendor/lib/modules/*.ko` son de **4.19** y no cargan en 6.6;
  no hacen falta porque su equivalente está compilado dentro. Los `modprobe`
  fallidos son ruido inofensivo.
- El vermagic deja de ser un requisito: no hay módulos externos que enganchar.

## 3. El dtb base 6.6 acepta el dtbo stock de MIUI

Medido sobre los binarios:

```
labels en el dtb base 6.6 ........ 445
targets del dtbo stock de MIUI .... 63
targets que faltan en el 6.6 ........ 0
```

El overlay de MIUI aplica limpio sobre el `dtb` 6.6. En AOSP el `dtbo` es el
del propio ROM (misma base). En ambos casos el zip **no toca el `dtbo`**.

Si en MIUI fallara WiFi/consys, está `dtbo-hybrid-*.img` (overlay 6.6 +
`atag,videolfb-*` y GPIO del `mt6360` del dtbo de MIUI). Ver `docs/DTBO.md`.

## 4. Todo lo que pide Android moderno está en la config

Verificado en `ruby_defconfig`:

```
CONFIG_BPF_SYSCALL=y  CONFIG_BPF_JIT=y  CONFIG_CGROUP_BPF=y
CONFIG_PSI=y          CONFIG_SECURITY_SELINUX=y
CONFIG_ANDROID_BINDER_IPC=y  CONFIG_ANDROID_BINDERFS=y
CONFIG_DMABUF_HEAPS=y CONFIG_FS_ENCRYPTION=y  CONFIG_CGROUP_FREEZER=y
CONFIG_IKCONFIG=y     CONFIG_IKCONFIG_PROC=y
CONFIG_UCLAMP_TASK=y  CONFIG_DEBUG_FS=y
```

y el workflow añade `SYSVIPC`, `POSIX_MQUEUE`, namespaces (`PID/UTS/IPC/NET/
USER`), cgroups (`DEVICE/PIDS/SCHED/CFS_BANDWIDTH/MEMCG`), `OVERLAY_FS`,
`VETH/MACVLAN/BRIDGE/TUN`, `SECCOMP_FILTER`.

## 5. Matriz de artefactos

| artefacto | MIUI/HyperOS | AOSP/Lineage (A16/A17) |
|---|---|---|
| `AnyKernel3-…-base-dtb.zip` | ✅ (dtbo stock) | ✅ (dtbo del ROM) |
| `AnyKernel3-…-combined-dtb.zip` | fallback | fallback |
| `dtbo-hybrid-….img` | ✅ si falla WiFi/consys | opcional |
| `boot-6.6-miui-….img` | ✅ flash directo | — |
| `boot-6.6-aosp-….img` | — | ✅ flash directo |
| variante `-ksu` | ✅ con manager KSU-Next | ✅ con manager KSU-Next |

## 6. Qué NO es universal

- **Root**: APatch/Magisk y KernelSU-Next no conviven. La variante `ksu` trae
  `CONFIG_KSU=y` y requiere el manager de KernelSU-Next; la vanilla arranca sin
  root (APatch/Magisk se aplican después).
- **Particiones**: el zip escribe sólo `boot` del slot activo. No toca `dtbo`,
  `vbmeta`, `vendor_boot` ni `super`.
- **64K pages**: este kernel es 4K. Un ROM que exija 16K/64K no va a arrancar;
  ruby es 4K en stock y en Lineage.
