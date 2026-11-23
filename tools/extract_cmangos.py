#!/usr/bin/env python3
"""Extracts which trainers teach our recipes, and for how much, from the CMaNGOS classic-db dump.

Usage: python3 tools/extract_cmangos.py <ClassicDB_*.sql.gz>
Source: https://github.com/cmangos/classic-db  Full_DB/ClassicDB_*.sql.gz  (GPL-2.0 data; only the extracted
numbers are committed). Needs tools/wago/SkillLineAbility.csv (see filter_wago.py) to know which spells are ours.

Classic trainers teach "learn spell" effects (effect 36) that no longer exist in the Forever client; each one is
mapped to the recipe it teaches through the dump's own spell_template. Writes tools/cmangos/trainer_spells.csv:
  npc, name, subname, spell, cost (copper), skill (skill line), reqskill, reqlevel, rank_step
rank_step is 1 apprentice .. 4 artisan for the profession rank spells, empty for a recipe.
"""
import csv
import gzip
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE / "cmangos" / "trainer_spells.csv"
SKILL_LINES = {171, 164, 202, 165, 197, 185, 129, 186}
LEARN_SPELL, SKILL_STEP, SKILL = 36, 118, 44  # spell effects
TABLES = ("spell_template", "npc_trainer", "npc_trainer_template", "creature_template")


def tuples(values):
    """Rows of an INSERT ... VALUES (...),(...) statement, honouring quotes and escapes."""
    row, field, i, n = [], [], 0, len(values)
    depth, quoted = 0, False
    while i < n:
        c = values[i]
        if quoted:
            if c == "\\":
                field.append(values[i + 1])
                i += 2
                continue
            if c == "'":
                quoted = False
            else:
                field.append(c)
        elif c == "'":
            quoted = True
        elif c == "(" and depth == 0:
            depth, row, field = 1, [], []
        elif c == "," and depth == 1:
            row.append("".join(field))
            field = []
        elif c == ")" and depth == 1:
            row.append("".join(field))
            yield row
            depth = 0
        elif depth == 1:
            field.append(c)
        i += 1


def read_dump(path):
    columns, data = {}, {t: [] for t in TABLES}
    current = None
    with gzip.open(path, "rt", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.match(r"CREATE TABLE `(\w+)`", line)
            if m:
                current = m.group(1) if m.group(1) in data else None
                if current:
                    columns[current] = []
                continue
            if current and line.startswith("  `"):
                columns[current].append(re.match(r"\s*`(\w+)`", line).group(1))
                continue
            m = re.match(r"INSERT INTO `(\w+)` VALUES ", line)
            if m and m.group(1) in data:
                data[m.group(1)].extend(tuples(line[m.end():]))
    return columns, data


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    with open(HERE / "wago" / "SkillLineAbility.csv", encoding="utf-8", newline="") as f:
        ours = {int(r["Spell"]) for r in csv.DictReader(f)}
    columns, data = read_dump(sys.argv[1])

    def col(table, name):
        return columns[table].index(name)

    # What each Classic spell teaches (effect 36) and which profession rank it grants (effect 118 / 44).
    st = "spell_template"
    idx = {k: col(st, k) for k in ["Id"] + [f"{p}{n}" for p in ("Effect", "EffectTriggerSpell", "EffectMiscValue", "EffectBasePoints")
                                            for n in (1, 2, 3)]}
    teaches, steps = {}, {}
    for r in data[st]:
        sid = int(r[idx["Id"]])
        for n in (1, 2, 3):
            effect = int(r[idx[f"Effect{n}"]])
            if effect == LEARN_SPELL:
                teaches[sid] = int(r[idx[f"EffectTriggerSpell{n}"]])
            elif effect in (SKILL_STEP, SKILL):
                line = int(r[idx[f"EffectMiscValue{n}"]])
                if line in SKILL_LINES:
                    steps[sid] = (line, int(r[idx[f"EffectBasePoints{n}"]]) + 1)

    # Trainer templates are shared by several NPCs.
    ct = "creature_template"
    users, names = {}, {}
    for r in data[ct]:
        entry = int(r[col(ct, "Entry")])
        names[entry] = (r[col(ct, "Name")], r[col(ct, "SubName")] if r[col(ct, "SubName")] != "NULL" else "")
        tpl = int(r[col(ct, "TrainerTemplateId")])
        if tpl:
            users.setdefault(tpl, []).append(entry)

    out = set()
    for table in ("npc_trainer", "npc_trainer_template"):
        for r in data[table]:
            entry, spell, cost, reqskill, reqvalue, reqlevel = (int(x) for x in r[:6])
            target = teaches.get(spell, spell)
            step = steps.get(target)
            if not step and target not in ours:
                continue
            skill = step[0] if step else reqskill
            for npc in (users.get(entry, []) if table == "npc_trainer_template" else [entry]):
                name, subname = names.get(npc, ("", ""))
                out.add((npc, name, subname, target, cost, skill, reqvalue, reqlevel, step[1] if step else ""))
    out = sorted(out)
    OUT.parent.mkdir(exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["npc", "name", "subname", "spell", "cost", "skill", "reqskill", "reqlevel", "rank_step"])
        w.writerows(out)
    print(f"{OUT}: {len(out)} rows ({len({o[0] for o in out})} trainers, {sum(1 for o in out if o[8])} rank rows)")


if __name__ == "__main__":
    main()
