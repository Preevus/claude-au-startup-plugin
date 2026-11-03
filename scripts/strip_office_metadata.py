#!/usr/bin/env python3
"""Strip metadata from Office files (.docx, .xlsx, .pptx and their macro and
template variants) in place, so templates carry no trace of who made them,
when, or on what machine.

Usage:
  python3 scripts/strip_office_metadata.py PATH [PATH ...]

Each PATH is a file or a folder (searched recursively). Files that are already
clean are left untouched, so running it twice changes nothing.

It removes:
  - document properties: title, author, last modified by, created and modified
    dates, revision, application, company and statistics (docProps/core.xml and
    docProps/app.xml are kept as empty elements)
  - custom properties (docProps/custom.xml) and thumbnails (docProps/thumbnail.*)
  - Word revision session IDs (w:rsid* attributes and the w:rsids list),
    paragraph IDs (w14:paraId, w14:textId) and document IDs (w14:docId, w15:docId)
  - the "save preview picture" setting, document variables, and an attached
    template or mail merge data source (both are links that can name a local
    folder)
  - zip details: every timestamp is reset to the earliest time a zip file can
    record, and extra fields (which can hold the real time and a user ID) and
    comments are dropped

It keeps the visible content unchanged, including comments and tracked
changes. scripts/check_repo.sh reports their authors, so remove those in Word.
"""
import io
import os
import re
import stat
import sys
import zipfile

OFFICE_EXT = (".docx", ".docm", ".dotx", ".dotm", ".xlsx", ".xlsm", ".xltx",
              ".pptx", ".pptm", ".potx")
EPOCH = (1980, 1, 1, 0, 0, 0)
MAX_MEMBER = 50 * 1024 * 1024
MAX_TOTAL = 200 * 1024 * 1024

CORE = (b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        b'<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
        b'xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" '
        b'xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>')
APP = (b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
       b'<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" '
       b'xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"/>')

DROP_PART = re.compile(r"^docProps/(custom\.xml|thumbnail\.[A-Za-z0-9]+)$")
DROP_OVERRIDE = re.compile(rb'<Override\b[^>]*PartName="/docProps/(?:custom\.xml|thumbnail\.[A-Za-z0-9]+)"[^>]*/>')
DROP_REL = re.compile(rb'<Relationship\b[^>]*Target="/?docProps/(?:custom\.xml|thumbnail\.[A-Za-z0-9]+)"[^>]*/>')
ID_ATTR = re.compile(rb'\s(?:w:rsid[A-Za-z]*|w14:paraId|w14:textId)="[^"]*"')
SETTINGS_BLOCK = re.compile(rb'<(w:rsids|w:docVars)\b[^>]*?(?:/>|>.*?</\1>)', re.S)
SETTINGS_EMPTY = re.compile(rb'<(?:w:rsidRoot|w14:docId|w15:docId|w:savePreviewPicture)\b[^>]*/>')
WITH_RELS = re.compile(rb'<w:attachedTemplate\b[^>]*/>|<w:mailMerge\b[^>]*?(?:/>|>.*?</w:mailMerge>)', re.S)
REL_ID = re.compile(rb'\br:id="([^"]*)"')


def clean_member(name, data, removed_rel_ids):
    """Return the cleaned bytes for one zip member."""
    if name == "docProps/core.xml":
        return CORE
    if name == "docProps/app.xml":
        return APP
    if name == "[Content_Types].xml":
        return DROP_OVERRIDE.sub(b"", data)
    if name == "_rels/.rels":
        return DROP_REL.sub(b"", data)
    if not name.endswith(".xml"):
        return data
    if name == "word/settings.xml":
        for m in WITH_RELS.finditer(data):
            removed_rel_ids.extend(REL_ID.findall(m.group(0)))
        data = WITH_RELS.sub(b"", data)
        data = SETTINGS_BLOCK.sub(b"", data)
        data = SETTINGS_EMPTY.sub(b"", data)
    return ID_ATTR.sub(b"", data)


def strip(path):
    """Clean one file in place. Return a short status line."""
    with zipfile.ZipFile(path) as zin:
        infos = zin.infolist()
        total = 0
        for info in infos:
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError("contains a symbolic link: " + info.filename)
            total += info.file_size
            if info.file_size > MAX_MEMBER or total > MAX_TOTAL:
                raise ValueError("too large to process safely")
        members = [(info.filename, zin.read(info.filename)) for info in infos
                   if not DROP_PART.match(info.filename)]
    rel_ids = []
    cleaned = [(name, clean_member(name, data, rel_ids)) for name, data in members]
    if rel_ids:  # links for an attached template or mail merge live in settings.xml.rels
        pattern = re.compile(rb'<Relationship\b[^>]*Id="(?:' + b"|".join(re.escape(i) for i in rel_ids) + rb')"[^>]*/>')
        cleaned = [(n, pattern.sub(b"", d) if n == "word/_rels/settings.xml.rels" else d) for n, d in cleaned]

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zout:
        for name, data in cleaned:
            info = zipfile.ZipInfo(name, date_time=EPOCH)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = 0o600 << 16
            zout.writestr(info, data)
    new = buf.getvalue()
    with open(path, "rb") as fh:
        if fh.read() == new:
            return "already clean"
    tmp = path + ".strip-tmp"
    with open(tmp, "wb") as fh:
        fh.write(new)
    os.replace(tmp, path)
    return "metadata stripped"


def office_files(paths):
    for p in paths:
        if os.path.isdir(p):
            for root, dirs, files in os.walk(p):
                dirs[:] = sorted(d for d in dirs if d != ".git")
                for f in sorted(files):
                    if f.lower().endswith(OFFICE_EXT) and not f.startswith("~$"):
                        yield os.path.join(root, f)
        else:
            yield p


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__.strip())
        return 0 if argv else 1
    failed = 0
    count = 0
    for path in office_files(argv):
        count += 1
        try:
            print("%s: %s" % (path, strip(path)))
        except (OSError, ValueError, zipfile.BadZipFile) as ex:
            failed += 1
            print("%s: ERROR %s" % (path, ex), file=sys.stderr)
    if count == 0:
        print("no Office files found")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
