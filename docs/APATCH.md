# APatch en kernel 6.6 (ruby): causa y solución

## El error

Al intentar parchear el boot con APatch:

```
[-] KernelPatch/tools/image.c:81/get_kernel_info();
    kernel primary entry: d503201f
```

`0xd503201f` es un **NOP** arm64. No es un fallo de nuestro kernel ni de la ROM:
es cómo kptools decide dónde está el branch de entrada.

## Por qué pasa (código de KernelPatch)

`tools/image.c`, `get_kernel_info()`:

```c
#define EFI_MAGIC_SIG "MZ"

union _entry {
    struct _efi  { uint8_t mz[4]; uint32_t b_insn; } efi;   // branch en offset 4
    struct _nefi { uint32_t b_insn; uint32_t reserved0; } nefi; // branch en offset 0
} hdr;

kinfo->uefi = !strncmp((const char *)khdr->hdr.efi.mz, "MZ", 2);
b_insn = uefi ? hdr.efi.b_insn : hdr.nefi.b_insn;

if ((b_insn & 0xFC000000) != 0x14000000)
    tools_loge_exit("kernel primary entry: %x\n", b_insn);
```

Cabecera arm64 de cada kernel:

| kernel | bytes 0-7 | resultado |
|---|---|---|
| MIUI 4.19 | `00 80 81 14` … → `b` en offset 0, sin "MZ" | kptools lee el `b` → OK |
| nuestro 6.6 (`CONFIG_EFI=n`) | `1f 20 03 d5` `19 24 a4 14` → NOP en 0, `b` en 4 | kptools lee el NOP → **falla** |
| 6.6 con `CONFIG_EFI=y` | `4d 5a 40 fa` … → "MZ" + `b` en 4 | kptools toma la rama EFI → OK |

El kernel 6.6 del proyecto (y también el release de RubyxLabs) se compila con
`CONFIG_EFI=n`, así que lleva NOP + branch. kptools sólo entiende
"branch en 0" o "MZ + branch en 4".

## Solución aplicada

Dos capas, ambas ya en el repo:

1. **Cabecera tipo EFI** (`tools/fix-apatch-header.py`): cambia los 4 bytes
   `1f 20 03 d5` (NOP) por `4d 5a 40 fa` (`ccmp x18, #0, #0xd, pl`, cuyos dos
   primeros bytes son "MZ"). El arranque no cambia: el bootloader ejecuta el
   `ccmp` (sólo toca flags) y sigue con el `b` del offset 4.
   - `assemble.sh` lo aplica a todos los `boot.img` que arma.
   - El workflow lo aplica a `Image.gz` antes de empaquetar los zips.

2. **Parcheo con kptools sin superkey** (root_key mode):

   ```sh
   kptools-android -p -i boot-6.6-miui-…-vanilla-apatch.img \
                   -k kpimg-android -o apatch_patched_noskey.img
   ```

   Sin `-s`/`-S`, kptools imprime
   `root_key mode with empty superkey: root_superkey zeroed` y deja el boot
   parcheado con la superkey **en cero**: al abrir APatch por primera vez te
   pide crear la tuya. No viaja ninguna clave en el archivo.

   Verificación con `kptools -l -i kernel`:

   ```
   patched=true
   [kpimg] version=0xd09  config=android,release  arch=arm64
   banner=Linux version 6.6.143-android15-8-4k-Singularity-ruby66-g3264c10f3205 …
   ```

## Artefactos

| archivo | qué es |
|---|---|
| `boot-6.6-miui-…-vanilla-apatch.img` | boot vanilla con cabecera MZ, **sin** parchear (entrada para APatch, por si preferís parchear desde la app) |
| `apatch_patched_noskey_ruby66-6.6.143-vanilla.img` | ya parcheado con kptools 0.13.9 (`kpimg d09`), superkey en cero |

## Flasheo

1. OFOX → *Install Image* → `apatch_patched_noskey_….img` → **Boot**
   (o `tools/flash-boot.sh` desde Android con root).
2. Reiniciar, abrir APatch → crear la superkey cuando la pida.
3. `uname -r` → `6.6.143-android15-8-4k-Singularity-ruby66-g3264c10f3205`.

Si algo falla: OFOX → `boot_a-stock.img` (vuelve con APatch 4.19) y el log del
intento en `/sys/fs/pstore/console-ramoops-0`.
