#!/usr/bin/env python3
"""Extracts where our trainers stand, and which faction they serve, from the QuestieDB addon's data.

Usage: python3 tools/extract_questie.py <QuestieDB-*-Forever.zip>   (needs tools/cmangos/trainer_spells.csv)
QuestieDB bakes its NPC rows into the addon TOC as base64 CBOR (key X-Npc-<id>-<field>). Writes
tools/questie/trainers.csv: npc, faction (A, H, AH or empty), area (zone area id of the first spawn), x, y
(x, y are percent of the zone map). Only the numbers are committed, not QuestieDB's files.
"""
import base64
import csv
import re
import struct
import sys
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "questie" / "trainers.csv"
SPAWNS, ZONE, FRIENDLY = 7, 9, 13  # NPC field indexes (npcMeta.lua)


def cbor(data, i=0):
    """Decodes one CBOR item at data[i]; returns (value, next index). Bytes become str."""
    head = data[i]
    major, info = head >> 5, head & 31
    i += 1
    if info < 24:
        arg = info
    elif info < 28:
        size = 1 << (info - 24)
        arg = int.from_bytes(data[i:i + size], "big")
        i += size
    else:
        raise ValueError("unsupported CBOR additional info %d" % info)
    if major == 0:
        return arg, i
    if major == 1:
        return -1 - arg, i
    if major in (2, 3):
        return data[i:i + arg].decode("utf-8", "replace"), i + arg
    if major == 4:
        out = []
        for _ in range(arg):
            v, i = cbor(data, i)
            out.append(v)
        return out, i
    if major == 5:
        out = {}
        for _ in range(arg):
            k, i = cbor(data, i)
            v, i = cbor(data, i)
            out[k] = v
        return out, i
    if major == 6:
        return cbor(data, i)
    if info == 27:  # double
        return struct.unpack(">d", data[i - 8:i])[0], i
    if info == 26:  # float
        return struct.unpack(">f", data[i - 4:i])[0], i
    return {20: False, 21: True, 22: None}.get(info), i


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(HERE / "cmangos" / "trainer_spells.csv", encoding="utf-8", newline="") as f:
        wanted = {r["npc"] for r in csv.DictReader(f)}
    with zipfile.ZipFile(sys.argv[1]) as z:
        toc = next(n for n in z.namelist() if n.endswith("QuestieDB_Forever.toc"))
        text = z.read(toc).decode("utf-8")
    store = {}
    for m in re.finditer(r"^## X-Npc-(\d+)-(\w+): (\S+)$", text, re.M):
        if m.group(1) in wanted:
            store[(m.group(1), m.group(2))] = m.group(3)

    rows, missing = [], []
    for npc in sorted(wanted, key=int):
        scalar = store.get((npc, "S"))
        if not scalar:
            missing.append(npc)
            continue
        row, _ = cbor(base64.b64decode(scalar))
        spawns = store.get((npc, str(SPAWNS)))
        area, x, y = "", "", ""
        if spawns:
            table, _ = cbor(base64.b64decode(spawns))
            if isinstance(table, dict) and table:
                area = row.get(ZONE) if row.get(ZONE) in table else sorted(table)[0]
                spot = next((p for p in table[area] if len(p) > 1 and isinstance(p[0], (int, float)) and isinstance(p[1], (int, float))), None)
                if spot:
                    x, y = spot[0], spot[1]
                else:
                    area = ""  # no usable coordinates
        rows.append((npc, row.get(FRIENDLY, ""), area, x, y))
    OUT.parent.mkdir(exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["npc", "faction", "area", "x", "y"])
        w.writerows(rows)
    print(f"{OUT}: {len(rows)} trainers, {sum(1 for r in rows if r[2] != '')} with a location; no data for {missing}")


if __name__ == "__main__":
    main()
