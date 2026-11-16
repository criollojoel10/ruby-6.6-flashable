#!/usr/bin/env python3
"""Marca la cabecera arm64 del kernel como "EFI" para que APatch/kptools pueda
parchearlo.

Contexto (KernelPatch tools/image.c, get_kernel_info):

    kinfo->uefi = !strncmp(khdr->hdr.efi.mz, "MZ", 2);
    if (uefi) b_insn = hdr.efi.b_insn;   // offset 4
    else      b_insn = hdr.nefi.b_insn;  // offset 0
    if ((b_insn & 0xFC000000) != 0x14000000)
        tools_loge_exit("kernel primary entry: %x\\n", b_insn);

Un kernel arm64 compilado con CONFIG_EFI=n empieza con NOP (`1f 20 03 d5`) y
el branch real está en el offset 4. kptools lee el offset 0, ve el NOP y aborta
con `kernel primary entry: d503201f`.

Los kernels con CONFIG_EFI=y empiezan con la instrucción `ccmp x18, #0, #0xd,
pl` = `4d 5a 40 fa`, cuyos dos primeros bytes son "MZ". kptools entonces toma
la rama EFI y lee el branch del offset 4, que es el correcto.

Este script cambia sólo esos 4 bytes (NOP -> ccmp "MZ"). El flujo de arranque
no cambia: el bootloader empieza en el offset 0, ejecuta el ccmp (inofensivo,
sólo toca flags) y sigue con el branch del offset 4 igual que antes.

Uso:
    fix-apatch-header.py <Image | Image.gz> [-o salida]

Si la entrada es .gz escribe .gz; si es raw escribe raw.
"""
import gzip
import shutil
import sys

NOP = bytes.fromhex("1f2003d5")
MZ = bytes.fromhex("4d5a40fa")  # ccmp x18, #0, #0xd, pl  ("MZ" en bytes 0-1)


def patch(img: bytes) -> bytes:
    if len(img) < 8:
        raise SystemExit("imagen demasiado corta")
    code0 = img[0:4]
    code1 = int.from_bytes(img[4:8], "little")
    if code0 == MZ:
        print("  ya tiene la cabecera EFI (MZ); sin cambios")
        return img
    if code0 != NOP:
        raise SystemExit("cabecera inesperada: %s (no es NOP)" % code0.hex())
    if (code1 & 0xFC000000) != 0x14000000:
        raise SystemExit("el offset 4 no es un branch: 0x%08x" % code1)
    out = MZ + img[4:]
    print("  code0: %s (nop) -> %s (ccmp MZ); branch en offset 4: 0x%08x" % (code0.hex(), MZ.hex(), code1))
    return out


def main(argv):
    if len(argv) < 2:
        raise SystemExit(__doc__)
    src = argv[1]
    dst = argv[3] if len(argv) > 3 and argv[2] in ("-o", "--output") else src
    gz = src.endswith(".gz")
    if gz:
        with gzip.open(src, "rb") as f:
            img = f.read()
        img = patch(img)
        with open(dst, "wb") as f:
            with gzip.GzipFile(fileobj=f, mode="wb", compresslevel=9, mtime=0) as g:
                g.write(img)
    else:
        with open(src, "rb") as f:
            img = f.read()
        img = patch(img)
        with open(dst, "wb") as f:
            f.write(img)
    print("  escrito: %s" % dst)


if __name__ == "__main__":
    main(sys.argv)
