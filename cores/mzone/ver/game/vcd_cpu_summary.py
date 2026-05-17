#!/usr/bin/env python3
import re
import sys


def main():
    vcd = sys.argv[1] if len(sys.argv) > 1 else "test.vcd"
    want = {
        "main_cpu_cen",
        "main_stub_addr",
        "reg_pc",
        "main_vram0_we",
        "main_vram1_we",
        "main_cram0_we",
        "main_cram1_we",
        "rom_cs",
    }

    ids = {}
    with open(vcd, "r", errors="ignore") as f:
        for line in f:
            if line.startswith("$enddefinitions"):
                break
            m = re.match(r"\$var\s+\S+\s+\d+\s+(\S+)\s+([^\s\[]+)", line)
            if m and m.group(2) in want:
                ids.setdefault(m.group(2), m.group(1))

    counts = {k: 0 for k in ids}
    highs = {k: 0 for k in ids}
    last = {k: "" for k in ids}
    rev = {v: k for k, v in ids.items()}

    with open(vcd, "r", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line[0] == "$" or line[0] == "#":
                continue
            if line[0] == "b":
                fields = line.split(None, 1)
                if len(fields) != 2:
                    continue
                val, sid = fields
                if sid in rev:
                    key = rev[sid]
                    counts[key] += 1
                    last[key] = val
            else:
                sid = line[1:]
                if sid in rev:
                    key = rev[sid]
                    counts[key] += 1
                    if line[0] == "1":
                        highs[key] += 1
                    last[key] = line[0]

    for key in sorted(want):
        val = last.get(key, "")
        if val.startswith("b") and set(val[1:]) <= {"0", "1"}:
            val += f" 0x{int(val[1:], 2):x}"
        print(
            f"{key}: id={ids.get(key, '?')} count={counts.get(key, 0)} "
            f"high={highs.get(key, 0)} last={val}"
        )


if __name__ == "__main__":
    main()
