"""Build tests/corpus/tounicode_control.pdf.

A minimal PDF whose /ToUnicode maps code 0x01 to U+0001 instead of U+0020 — the
exact defect seen in the wild (design tools emitting a control codepoint for the
space glyph). The page shows "AB", that glyph, then "CD".

Expected extraction: "AB CD". Before the cmap repair it was "AB\\u0001CD", and a
naive fix that merely drops the glyph yields "ABCD" — words glued together — so
the fixture pins the space, not just the absence of the control character.

Regenerate: python tools/make_tounicode_fixture.py
"""

from pathlib import Path

ESC_01 = "\\001"  # PDF string escape for byte 0x01

objs: dict[int, bytes] = {}
objs[1] = b"<< /Type /Catalog /Pages 2 0 R >>"
objs[2] = b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"
objs[3] = (
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] "
    b"/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>"
)

stream = f"BT /F1 12 Tf 20 50 Td (AB{ESC_01}CD) Tj ET".encode("latin-1")
objs[4] = b"<< /Length %d >>\nstream\n%s\nendstream" % (len(stream), stream)

# Widths: code 1 carries a space's advance (278/1000 em); A-D are 556.
widths = b"278" + b" 0" * 63 + b" 556 556 556 556"
objs[5] = (
    b"<< /Type /Font /Subtype /TrueType /BaseFont /Test "
    b"/FirstChar 1 /LastChar 68 /Widths [" + widths + b"] "
    b"/FontDescriptor 6 0 R /ToUnicode 7 0 R >>"
)
objs[6] = (
    b"<< /Type /FontDescriptor /FontName /Test /Flags 32 /ItalicAngle 0 "
    b"/Ascent 700 /Descent -200 /CapHeight 700 /StemV 80 "
    b"/FontBBox [0 -200 1000 900] >>"
)

cmap = (
    b"/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n"
    b"5 beginbfchar\n"
    b"<01> <0001>\n"  # the defect
    b"<41> <0041>\n<42> <0042>\n<43> <0043>\n<44> <0044>\n"
    b"endbfchar\nendcmap\nend\nend"
)
objs[7] = b"<< /Length %d >>\nstream\n%s\nendstream" % (len(cmap), cmap)

out = bytearray(b"%PDF-1.4\n")
offsets: dict[int, int] = {}
for n in sorted(objs):
    offsets[n] = len(out)
    out += b"%d 0 obj\n" % n + objs[n] + b"\nendobj\n"

xref = len(out)
out += b"xref\n0 %d\n" % (len(objs) + 1)
out += b"0000000000 65535 f \n"
for n in sorted(objs):
    out += b"%010d 00000 n \n" % offsets[n]
out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (
    len(objs) + 1,
    xref,
)

dest = Path(__file__).resolve().parent.parent / "tests" / "corpus" / "tounicode_control.pdf"
dest.write_bytes(bytes(out))
print(f"wrote {dest} ({len(out)} bytes)")
