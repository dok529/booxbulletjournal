# Minimaler Protobuf-Wire-Format-Codec (ohne Schema): Felder als Liste (Nummer, Typ, Wert).


def varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7f) << s
        s += 7
        if c < 0x80:
            return r, i


def parse(b):
    i, out = 0, []
    while i < len(b):
        k, i = varint(b, i)
        f, w = k >> 3, k & 7
        if w == 0:
            v, i = varint(b, i)
        elif w == 1:
            v, i = b[i:i + 8], i + 8
        elif w == 5:
            v, i = b[i:i + 4], i + 4
        elif w == 2:
            n, i = varint(b, i)
            v, i = b[i:i + n], i + n
        else:
            raise ValueError("Wire-Typ %d an Position %d" % (w, i))
        out.append((f, w, v))
    return out


def enc_varint(n):
    out = bytearray()
    while True:
        b, n = n & 0x7f, n >> 7
        if n:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def encode(fields):
    out = bytearray()
    for f, w, v in fields:
        out += enc_varint(f << 3 | w)
        if w == 0:
            out += enc_varint(v)
        elif w == 2:
            out += enc_varint(len(v)) + v
        else:
            out += v
    return bytes(out)


def getf(fields, f):
    for g, _, v in fields:
        if g == f:
            return v


def setf(fields, f, v, w=2):
    """Ersetzt das erste Feld f (Typ bleibt) oder hängt es an."""
    for i, (g, ww, _) in enumerate(fields):
        if g == f:
            fields[i] = (f, ww, v)
            return fields
    fields.append((f, w, v))
    return fields
