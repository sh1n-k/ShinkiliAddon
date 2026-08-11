#!/usr/bin/env python3
"""Generate Shinkili/ShinkiliSimcData.lua from JustAC Data/SimcRotations.lua (SimC-derived).

Usage:
  python3 tools/gen_simc_priority.py [path/to/SimcRotations.lua]
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SRC = Path("/Users/shin/PersonalProjects/JustAC/Data/SimcRotations.lua")
OUT = ROOT / "Shinkili" / "ShinkiliSimcData.lua"


def extract_entries(block: str, name: str) -> list[tuple[int, list[dict]]]:
    mm = re.search(rf"(?<![A-Za-z0-9_]){name}\s*=\s*\{{", block)
    if not mm:
        return []
    i = mm.end() - 1
    depth = 0
    j = i
    while j < len(block):
        if block[j] == "{":
            depth += 1
        elif block[j] == "}":
            depth -= 1
            if depth == 0:
                j += 1
                break
        j += 1
    inner = block[i + 1 : j - 1]
    entries: list[tuple[int, list[dict]]] = []
    pos = 0
    while True:
        m = re.search(r"\{id=(\d+),gates=", inner[pos:])
        if not m:
            break
        sid = int(m.group(1))
        gstart = pos + m.end()
        if gstart >= len(inner) or inner[gstart] != "{":
            pos = pos + m.end()
            continue
        depth = 0
        k = gstart
        while k < len(inner):
            if inner[k] == "{":
                depth += 1
            elif inner[k] == "}":
                depth -= 1
                if depth == 0:
                    k += 1
                    break
            k += 1
        gates_inner = inner[gstart + 1 : k - 1]
        gates: list[dict] = []
        p = 0
        while p < len(gates_inner):
            if gates_inner[p] != "{":
                p += 1
                continue
            d = 0
            q = p
            while q < len(gates_inner):
                if gates_inner[q] == "{":
                    d += 1
                elif gates_inner[q] == "}":
                    d -= 1
                    if d == 0:
                        q += 1
                        break
                q += 1
            gobj = gates_inner[p + 1 : q - 1]
            tm = re.search(r't="(\w+)"', gobj)
            if tm and tm.group(1) != "resource":
                gate: dict = {"t": tm.group(1)}
                im = re.search(r"id=(\d+)", gobj)
                if im:
                    gate["id"] = int(im.group(1))
                if "neg=true" in gobj:
                    gate["neg"] = True
                gates.append(gate)
            p = q
        entries.append((sid, gates))
        pos = k
    return entries


def get_spec_block(body: str, key: str) -> str | None:
    m = re.search(r'\["%s"\]\s*=\s*\{' % key, body)
    if not m:
        return None
    i = body.find("{", m.start())
    depth = 0
    j = i
    while j < len(body):
        if body[j] == "{":
            depth += 1
        elif body[j] == "}":
            depth -= 1
            if depth == 0:
                return body[i : j + 1]
        j += 1
    return None


def main() -> int:
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_SRC
    if not src_path.exists():
        print("source missing:", src_path, file=sys.stderr)
        return 1
    src = src_path.read_text()
    m = re.search(r"RegisterGated\(\{(.*)\}\)", src, re.S)
    if not m:
        print("parse failed", file=sys.stderr)
        return 1
    body = m.group(1)
    keys = []
    seen = set()
    for key in re.findall(r'\["([A-Z]+_\d+)"\]', body):
        if key not in seen:
            seen.add(key)
            keys.append(key)

    out: dict = {}
    for key in keys:
        block = get_spec_block(body, key)
        if not block:
            continue
        st = extract_entries(block, "st")
        aoe = extract_entries(block, "aoe")
        if st or aoe:
            out[key] = {"st": st, "aoe": aoe}

    lines = [
        "-- Shinkili SimC-derived priority data (flattened).",
        "-- Generated from SimulationCraft APLs (GPL-3.0) via tools/gen_simc_priority.py.",
        "-- Used to refine AC recommendations; not a full SimC engine.",
        "",
        "ShinkiliSimcData = ShinkiliSimcData or {}",
        "ShinkiliSimcData.version = 1",
        "ShinkiliSimcData.specs = {",
    ]
    for key in sorted(out.keys()):
        sp = out[key]
        lines.append('  ["%s"] = {' % key)
        for name in ("st", "aoe"):
            entries = sp.get(name) or []
            if not entries:
                continue
            lines.append("    %s = {" % name)
            for sid, gates in entries:
                if not gates:
                    lines.append("      {id=%d}," % sid)
                else:
                    gparts = []
                    for g in gates:
                        bits = ['t="%s"' % g["t"]]
                        if "id" in g:
                            bits.append("id=%d" % g["id"])
                        if g.get("neg"):
                            bits.append("neg=true")
                        gparts.append("{" + ",".join(bits) + "}")
                    lines.append("      {id=%d,gates={%s}}," % (sid, ",".join(gparts)))
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    lines.append("")
    lines.append("return ShinkiliSimcData")
    OUT.write_text("\n".join(lines) + "\n")
    print("wrote", OUT, "specs", len(out), "entries", sum(len(v["st"]) + len(v["aoe"]) for v in out.values()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
