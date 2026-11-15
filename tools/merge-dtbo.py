#!/usr/bin/env python3
"""Fusiona overlays DTB (dtbo) a nivel de fuente.

Uso:
    merge-dtbo.py <base-overlay.dts> <extra-overlay.dts> [...] -o <salida.dts>

Motivo: en MIUI el `dtbo` stock de ruby trae dos fragmentos que el `ruby.dtbo`
del kernel 6.6 no tiene (`&chosen` con los atag,videolfb y `&mt6360_pmu` con
los GPIO de IRQ). El de 6.6 en cambio agrega nodos que MIUI necesita para
WiFi/consys/seninf. Este script concatena los fragmentos de todos los `.dts`
de overlay en uno solo, en orden, sin tocar el resto.

Los `.dts` de entrada deben ser volcados con `dtc -I dtb -O dts` (sin -@).
Las secciones __symbols__ / __fixups__ / __local_fixups__ se descartan:
dtc las regenera al compilar con `-@`.
"""
import re
import sys


def find_top_blocks(text):
    """Devuelve (cabeza, fragmentos, cola) separando los bloques de nivel 1."""
    start = text.index("{", text.index("/ {"))
    depth = 0
    i = start
    while i < len(text):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                end = i + 1
                break
        i += 1
    head = text[: start + 1]
    body = text[start + 1 : end]
    tail = text[end:]

    blocks = []
    idx = 0
    key = re.compile(r"^\t([A-Za-z0-9_@,.\-]+)\s*\{", re.M)
    while True:
        m = key.search(body, idx)
        if not m:
            break
        bstart = m.start()
        d = 0
        j = m.end() - 1
        while j < len(body):
            if body[j] == "{":
                d += 1
            elif body[j] == "}":
                d -= 1
                if d == 0:
                    break
            j += 1
        bend = j + 1
        # consumir el ';' opcional
        while bend < len(body) and body[bend] in " \t;":
            bend += 1
        while bend < len(body) and body[bend] == "\n":
            bend += 1
        blocks.append((m.group(1), body[bstart:bend].rstrip() + "\n"))
        idx = bend
    return head, blocks, tail


def main(argv):
    out = None
    files = []
    i = 1
    while i < len(argv):
        if argv[i] in ("-o", "--output"):
            out = argv[i + 1]
            i += 2
        else:
            files.append(argv[i])
            i += 1
    if not out or not files:
        print(__doc__, file=sys.stderr)
        return 2

    skip = {"__symbols__", "__fixups__", "__local_fixups__"}
    frags = []
    head = None
    for path in files:
        text = open(path, encoding="utf-8", errors="surrogateescape").read()
        h, blocks, _ = find_top_blocks(text)
        if head is None:
            # Algunos dtc (p.ej. 1.7.0 de Ubuntu) NO emiten /plugin/; al
            # descompilar un dtbo. Sin esa directiva los &label externos se
            # tratan como error en vez de generar __fixups__.
            if "/plugin/" not in h:
                h = h.replace("/dts-v1/;", "/dts-v1/;\n/plugin/;", 1)
            head = h
        frags.extend(b for b in blocks if b[0] not in skip)

    out_lines = [head]
    # reenumerar fragment@N de forma contigua
    n = 0
    for name, block in frags:
        if name.startswith("fragment@"):
            block = re.sub(r"^\tfragment@\d+", "\tfragment@%d" % n, block, count=1)
            n += 1
        out_lines.append(block)
    out_lines.append("};\n")

    with open(out, "w", encoding="utf-8", errors="surrogateescape") as f:
        f.write("\n".join(out_lines))
    print("fragmentos: %d -> %s" % (n, out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
