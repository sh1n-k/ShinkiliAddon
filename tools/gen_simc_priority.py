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


def extract_entries(block: str, name: str) -> list[tuple[int, list[dict], bool]]:
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
    entries: list[tuple[int, list[dict], bool]] = []
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
            if tm:
                gate: dict = {"t": tm.group(1)}
                im = re.search(r"id=(\d+)", gobj)
                if im:
                    gate["id"] = int(im.group(1))
                if "neg=true" in gobj:
                    gate["neg"] = True
                # `deficit` (max minus current) and `ispct` (percent of max)
                # change what `n` is measured against. Dropping them would leave
                # a plain current-amount comparison behind -- a silent inversion
                # of the SimC line -- so they are carried through and the runtime
                # declines to evaluate the gate.
                if "deficit=true" in gobj:
                    gate["deficit"] = True
                if "ispct=true" in gobj:
                    gate["ispct"] = True
                # Resource gates carry a comparison the runtime evaluates against
                # the readable secondary-resource count.
                rm = re.search(r'res="(\w+)"', gobj)
                if rm:
                    gate["res"] = rm.group(1)
                om = re.search(r'op="([<>=!]+)"', gobj)
                if om:
                    gate["op"] = om.group(1)
                nm = re.search(r"n=(-?[\d.]+)", gobj)
                if nm:
                    raw = nm.group(1)
                    gate["n"] = float(raw) if "." in raw else int(raw)
                else:
                    # Health-threshold gates spell the same number `pct`. The
                    # runtime's execute branch already compares a percentage
                    # against `n`, so carrying it across as `n` is what makes an
                    # otherwise complete gate evaluable instead of unknown.
                    pm = re.search(r"pct=(-?[\d.]+)", gobj)
                    if pm:
                        raw = pm.group(1)
                        gate["n"] = float(raw) if "." in raw else int(raw)
                gates.append(gate)
            p = q

        # `delegated` marks a SimC step whose real condition also needs a value
        # the client cannot read. Keeping the flag is what lets the runtime say
        # "this ordering is not verifiable -- defer to Assisted Combat".
        #
        # Bounded to the entry's own text: the source emits one entry per line,
        # so scan to the entry-closing brace (or end of line, whichever comes
        # first). A fixed character window would eventually swallow the NEXT
        # entry's flag and silently mark this one unverifiable forever.
        rest = inner[k:]
        line_end = rest.find("\n")
        brace_end = rest.find("},")
        bounds = [b for b in (line_end, brace_end + 2 if brace_end >= 0 else -1) if b >= 0]
        entry_tail = rest[: min(bounds)] if bounds else rest
        delegated = "delegated=true" in entry_tail
        entries.append((sid, gates, delegated))
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
        "--",
        "-- entry = {id, gates = {...}, delegated = bool}",
        "--   gates: {t=\"cd\"} | {t=\"buff\",id,neg} | {t=\"dot\",id} | {t=\"execute\"}",
        "--          | {t=\"resource\",res,op,n} | {t=\"power\",res,op,n}",
        "--          | {t=\"stack\",id,op,n} | {t=\"targets\",op,n}",
        "--   The source drops the reference id from `cd`, the polarity from",
        "--   `dot`, and the operator from `execute`, so those read as unknown at",
        "--   runtime. `targets` is never emitted today. `stack` is carried but",
        "--   not evaluated: aura stack counts are secret in 12.0. A `resource` or",
        "--   `power` gate flagged deficit/ispct measures `n` against the maximum",
        "--   and is likewise not evaluable. See AGENTS.md.",
        "--   delegated: the SimC condition also needs a value the client cannot",
        "--   read, so this ordering is NOT verifiable and must never outrank",
        "--   Blizzard's live Assisted Combat pick.",
        "",
        "ShinkiliSimcData = ShinkiliSimcData or {}",
        "ShinkiliSimcData.version = 2",
        "ShinkiliSimcData.specs = {",
    ]

    def gate_literal(g: dict) -> str:
        bits = ['t="%s"' % g["t"]]
        if "id" in g:
            bits.append("id=%d" % g["id"])
        if "res" in g:
            bits.append('res="%s"' % g["res"])
        if "op" in g:
            bits.append('op="%s"' % g["op"])
        if "n" in g:
            value = g["n"]
            bits.append("n=%s" % (repr(value) if isinstance(value, float) else str(value)))
        if g.get("neg"):
            bits.append("neg=true")
        if g.get("deficit"):
            bits.append("deficit=true")
        if g.get("ispct"):
            bits.append("ispct=true")
        return "{" + ",".join(bits) + "}"

    total_delegated = 0
    for key in sorted(out.keys()):
        sp = out[key]
        lines.append('  ["%s"] = {' % key)
        for name in ("st", "aoe"):
            entries = sp.get(name) or []
            if not entries:
                continue
            lines.append("    %s = {" % name)
            for sid, gates, delegated in entries:
                if delegated:
                    total_delegated += 1
                parts = ["id=%d" % sid]
                if gates:
                    parts.append("gates={%s}" % ",".join(gate_literal(g) for g in gates))
                if delegated:
                    parts.append("delegated=true")
                lines.append("      {%s}," % ",".join(parts))
            lines.append("    },")
        lines.append("  },")
    lines.append("}")
    lines.append("")
    lines.append("return ShinkiliSimcData")
    OUT.write_text("\n".join(lines) + "\n")
    total = sum(len(v["st"]) + len(v["aoe"]) for v in out.values())
    print(
        "wrote", OUT,
        "specs", len(out),
        "entries", total,
        "delegated", total_delegated,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
