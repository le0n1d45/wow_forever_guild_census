#!/usr/bin/env python3
"""Extracts where our trainers stand, and which faction they serve, from the QuestieDB addon's data.

Usage: python3 tools/extract_questie.py <QuestieDB-*-Forever.zip>
Needs tools/cmangos/trainer_spells.csv (trainers) and tools/wago/RecipeItems.csv (recipe item sources).
QuestieDB bakes its NPC rows into the addon TOC as base64 CBOR (key X-Npc-<id>-<field>). Writes
tools/questie/trainers.csv: npc, faction (A, H, AH or empty), area (zone area id of the first spawn), x, y
(x, y are percent of the zone map). Also writes, for each recipe item that teaches one of our recipes:
tools/questie/recipe_sources.csv: item, kind (vendor, drop, object, quest), id (npc, npc, object or quest id),
tools/questie/npcs.csv: the vendors and (up to MAX_DROPPERS) droppers among them: npc, name, subtitle, faction,
area, x, y, and tools/questie/quests.csv: id, name. Only the numbers are committed, not QuestieDB's files.
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
ITEM_DROPS, ITEM_OBJECT_DROPS, ITEM_QUESTS, ITEM_VENDORS = 2, 3, 6, 14  # item field indexes (itemMeta.lua)
MAX_DROPPERS = 5  # per item: drop lists run to dozens of mobs at tiny rates, so keep the first few


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


def stored(store, kind, id_, field):
    """One stored value; a long one is a "~N~" header with its parts under <field>-1 .. <field>-N."""
    raw = store.get((kind, id_, field))
    m = re.fullmatch(r"~(\d+)~", raw or "")
    if m:
        return "".join(store[(kind, id_, f"{field}-{i}")] for i in range(1, int(m.group(1)) + 1))
    return raw


def scalar_row(store, kind, id_):
    raw = stored(store, kind, id_, "S")
    if not raw:
        return None
    row, _ = cbor(base64.b64decode(raw))
    return {i + 1: v for i, v in enumerate(row)} if isinstance(row, list) else row


def table_field(store, kind, id_, field):
    raw = stored(store, kind, id_, str(field))
    return cbor(base64.b64decode(raw))[0] if raw else None


def npc_place(store, npc):
    """(faction, area, x, y) of an NPC; area, x, y empty when it has no usable spawn."""
    row = scalar_row(store, "Npc", npc) or {}
    faction, area, x, y = row.get(FRIENDLY, ""), "", "", ""
    table = table_field(store, "Npc", npc, SPAWNS)
    if isinstance(table, dict) and table:
        zone = row.get(ZONE) if row.get(ZONE) in table else sorted(table)[0]
        spot = next((p for p in table[zone] if len(p) > 1 and isinstance(p[0], (int, float)) and isinstance(p[1], (int, float))), None)
        if spot:
            area, x, y = zone, spot[0], spot[1]
    return faction, area, x, y


def write_csv(path, header, rows):
    path.parent.mkdir(exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(HERE / "cmangos" / "trainer_spells.csv", encoding="utf-8", newline="") as f:
        trainers = {r["npc"] for r in csv.DictReader(f)}
    with open(HERE / "wago" / "RecipeItems.csv", encoding="utf-8", newline="") as f:
        recipe_items = sorted({r["item"] for r in csv.DictReader(f)}, key=int)
    with zipfile.ZipFile(sys.argv[1]) as z:
        toc = next(n for n in z.namelist() if n.endswith("QuestieDB_Forever.toc"))
        text = z.read(toc).decode("utf-8")
    store = {}
    for m in re.finditer(r"^## X-(Npc|Item|Quest)-(\d+)-([\w-]+): (\S+)$", text, re.M):
        store[(m.group(1), m.group(2), m.group(3))] = m.group(4)

    rows = []
    for npc in sorted(trainers, key=int):
        row = scalar_row(store, "Npc", npc)
        if row is None:
            print("no QuestieDB data for trainer", npc)
            continue
        rows.append((npc, *npc_place(store, npc)))
    write_csv(OUT, ["npc", "faction", "area", "x", "y"], rows)
    print(f"{OUT}: {len(rows)} trainers, {sum(1 for r in rows if r[2] != '')} with a location")

    sources, npcs, quests = [], set(), set()
    for item in recipe_items:
        for kind, field in (("vendor", ITEM_VENDORS), ("drop", ITEM_DROPS), ("object", ITEM_OBJECT_DROPS), ("quest", ITEM_QUESTS)):
            ids = table_field(store, "Item", item, field)
            if not isinstance(ids, list):
                continue
            ids = sorted(i for i in ids if isinstance(i, int))
            if kind == "drop":
                ids = ids[:MAX_DROPPERS]
            for i in ids:
                sources.append((item, kind, i))
                if kind in ("vendor", "drop"):
                    npcs.add(i)
                elif kind == "quest":
                    quests.add(i)
    write_csv(HERE / "questie" / "recipe_sources.csv", ["item", "kind", "id"], sources)
    npc_rows = []
    for npc in sorted(npcs):
        row = scalar_row(store, "Npc", str(npc)) or {}
        npc_rows.append((npc, row.get(1, ""), row.get(14, ""), *npc_place(store, str(npc))))
    write_csv(HERE / "questie" / "npcs.csv", ["npc", "name", "subname", "faction", "area", "x", "y"], npc_rows)
    quest_rows = [(q, (scalar_row(store, "Quest", str(q)) or {}).get(1, "")) for q in sorted(quests)]
    write_csv(HERE / "questie" / "quests.csv", ["id", "name"], quest_rows)
    with_source = {s[0] for s in sources}
    print(f"{len(sources)} sources for {len(with_source)} of {len(recipe_items)} recipe items; {len(npc_rows)} npcs, {len(quest_rows)} quests")


if __name__ == "__main__":
    main()
