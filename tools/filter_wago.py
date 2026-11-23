#!/usr/bin/env python3
"""Trims the WoW Forever client tables CrafterArbitrage needs, downloaded by hand from wago.tools.

Usage: python3 tools/filter_wago.py <folder with the full CSVs> <build>

Download each of these into the folder as <Table>.csv from
https://wago.tools/db2/<Table>/csv?build=<build>   (Forever builds are 1.60.1.x; see https://wago.tools/builds):
  SkillLineAbility, SpellEffect, SpellReagents, SpellName, ItemSparse, Item, ItemEffect, ItemXItemEffect
Writes tools/wago/<Table>.csv (only the crafting professions' rows and the columns the generator reads) and
tools/wago/BUILD. Commit the result: gen_recipes.py reads those files and needs no network.
"""
import csv
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "wago"
SRC = None  # folder with the downloaded CSVs, set by main()

# Professions whose recipes make an item. Enchanting (333) makes enchants, not items. Mining (186) is kept
# only for smelting: a bar can be made from ore instead of bought.
SKILL_LINES = {"171", "164", "202", "165", "197", "185", "129", "186"}
CREATE_ITEM = "24"  # spell effect "create item"
LEARN_SPELL = "36"  # spell effect "learn spell" (recipe items use it)

SLA_COLS = ["SkillLine", "Spell", "MinSkillLineRank", "SupercedesSpell", "AcquireMethod",
            "TrivialSkillLineRankHigh", "TrivialSkillLineRankLow", "ClassMask", "RaceMasks_0", "RaceMasks_1"]
EFFECT_COLS = ["SpellID", "EffectIndex", "Effect", "EffectItemType", "EffectBasePointsF", "EffectDieSides"]
REAGENT_COLS = ["SpellID"] + [f"Reagent_{i}" for i in range(8)] + [f"ReagentCount_{i}" for i in range(8)]
ITEM_COLS = ["ID", "Display_lang", "SellPrice", "BuyPrice", "VendorStackCount", "OverallQualityID", "Bonding",
             "RequiredSkill", "RequiredSkillRank", "RequiredLevel", "MinFactionID", "MinReputation"]


def download(table, _build=None):
    with open(SRC / f"{table}.csv", encoding="utf-8", newline="") as f:
        reader = csv.DictReader(f)
        return list(reader), reader.fieldnames


def write(name, cols, rows):
    with open(OUT / f"{name}.csv", "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    print(f"  {name}: {len(rows)} rows")


def keep_cols(rows, fields, cols):
    missing = [c for c in cols if c not in fields]
    return [{c: r.get(c, "") for c in cols} for r in rows], missing


def main():
    global SRC
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    SRC, build = Path(sys.argv[1]), sys.argv[2]
    OUT.mkdir(exist_ok=True)

    sla, f = download("SkillLineAbility", build)
    sla = [r for r in sla if r["SkillLine"] in SKILL_LINES]
    spells = {r["Spell"] for r in sla}
    sla_out, _ = keep_cols(sla, f, SLA_COLS)
    write("SkillLineAbility", SLA_COLS, sla_out)

    eff, f = download("SpellEffect", build)
    all_effects = eff
    eff = [r for r in eff if r["SpellID"] in spells and r["Effect"] == CREATE_ITEM]
    eff_out, missing = keep_cols(eff, f, EFFECT_COLS)
    write("SpellEffect", EFFECT_COLS, eff_out)

    rea, f = download("SpellReagents", build)
    rea = [r for r in rea if r["SpellID"] in spells]
    rea_out, _ = keep_cols(rea, f, REAGENT_COLS)
    write("SpellReagents", REAGENT_COLS, rea_out)

    # Recipe items: the item whose use teaches a recipe, directly or through a "learn spell" (effect 36).
    learn_effects = {}
    for r in all_effects:
        if r["Effect"] == LEARN_SPELL:
            learn_effects.setdefault(r["SpellID"], set()).add(r["EffectTriggerSpell"])
    item_effects, _ = download("ItemEffect")
    effect_spell = {r["ID"]: r["SpellID"] for r in item_effects}
    taught = set()
    crafts = {x["SpellID"] for x in eff}
    for r in download("ItemXItemEffect")[0]:
        spell = effect_spell.get(r["ItemEffectID"])
        if spell is None:
            continue
        for target in {spell} | learn_effects.get(spell, set()):
            if target in crafts:
                taught.add((r["ItemID"], target))
    recipe_items = [{"item": i, "spell": sp} for i, sp in sorted(taught, key=lambda t: (int(t[0]), int(t[1])))]
    write("RecipeItems", ["item", "spell"], recipe_items)

    items = {r["EffectItemType"] for r in eff} | {i for i, _ in taught}
    for r in rea:
        items.update(r[f"Reagent_{i}"] for i in range(8) if r[f"Reagent_{i}"] not in ("", "0"))

    names, f = download("SpellName", build)
    write("SpellName", ["ID", "Name_lang"], [r for r in names if r["ID"] in spells])

    sparse, f = download("ItemSparse", build)
    sparse = [r for r in sparse if r["ID"] in items]
    sparse_out, _ = keep_cols(sparse, f, ITEM_COLS)
    write("ItemSparse", ITEM_COLS, sparse_out)

    item, f = download("Item", build)
    item = [r for r in item if r["ID"] in items]
    item_out, _ = keep_cols(item, f, ["ID"])
    write("Item", ["ID"], item_out)

    (OUT / "BUILD").write_text(build + "\n")
    print("done, build", build)


if __name__ == "__main__":
    main()
