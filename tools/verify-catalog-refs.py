#!/usr/bin/env python3
"""Verify the `file:line` citations in CATALOG.md's Azure trap answer keys.

Self-contained: reads CATALOG.md, splits the "Trap answer keys (Azure)" section
into per-journey blocks by their `### Azure trap audit — <journey-dir>` headings,
resolves every backticked citation against `user-journey-tests/azure/<journey-dir>/`, and
applies two checks:

  RANGE   - the cited file exists and the cited line(s) are within it
  CONTENT - where the prose writes  `token` at `:NN`  or  `path:NN` (`token` ...),
            the token must actually appear inside the cited line range.
            Content anchoring is what catches a citation that drifted by a line
            while a sibling lane edited the cited file; a pure range check passes
            on drifted refs.

Exits 1 on RANGE / MISSING / NOPATH. CONTENT flags are advisory: they also fire on
Terraform addresses (`type.name` split across a declaration line), values reached
through a variable or module parameter, and a symbol's own declaration line, so
each one needs a human look rather than an automatic failure.

Usage:  python3 verify-catalog-refs.py [path/to/CATALOG.md]
"""
import gzip
import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CATALOG = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "CATALOG.md"
JOURNEYS = CATALOG.parent / "user-journey-tests" / "azure"

SECTION = re.compile(r"^### Azure trap audit — (\S+)\s*$")
HEADING = re.compile(r"^#{1,6} ")

# a citation is a backticked  path:N  /  path:N-M  /  :N  /  :N-M
PATHPART = r"[A-Za-z0-9_./-]+\.(?:tf|json|bicep|py|js|mjs|go|yaml|yml|md|csv|sh|gz)"
CITE = re.compile(r"`(" + PATHPART + r")?:(\d+)(?:-(\d+))?`")
# `token` at `:NN`   (token immediately before the "at")
TOK_BEFORE = re.compile(r"`([^`]{2,120})`\s+at\s+`(?:" + PATHPART + r")?:\d+(?:-\d+)?`")
# `path:NN` (`token`
TOK_AFTER = re.compile(r"`(?:" + PATHPART + r")?:\d+(?:-\d+)?`\s*\(`([^`]{2,120})`")

_cache = {}


def lines_of(p: pathlib.Path):
    if p in _cache:
        return _cache[p]
    try:
        if p.suffix == ".gz":
            data = gzip.open(p, "rt", errors="replace").read()
        else:
            data = p.read_text(errors="replace")
        out = data.splitlines()
    except Exception:
        out = None
    _cache[p] = out
    return out


def norm(s: str) -> str:
    s = s.replace("’", "'").replace("“", '"').replace("”", '"')
    s = s.replace("'", "").replace('"', "").replace("\\|", "|")
    return re.sub(r"\s+", "", s).lower()


def token_present(tok: str, seg) -> bool:
    """Is `tok` visible inside the cited lines? Tolerant of quoting/spacing."""
    if "…" in tok or "..." in tok:
        return True  # elided quote, cannot check
    hay = norm("\n".join(seg))
    if norm(tok) in hay:
        return True
    # key = value / key: value -> require both halves somewhere in the range
    m = re.match(r"^\s*([\w.\[\]$-]+)\s*[:=]\s*(.+)$", tok)
    if m:
        k, v = norm(m.group(1)), norm(m.group(2))
        if k and v and k in hay and v in hay:
            return True
    # bare identifier: allow it to be found anywhere in range
    if re.fullmatch(r"[\w.$-]+", tok.strip()) and norm(tok) in hay:
        return True
    return False


def blocks(catalog_text: str):
    """Yield (journey-dir, [lines]) for each `### Azure trap audit — ...` section."""
    current, buf = None, []
    for line in catalog_text.splitlines():
        m = SECTION.match(line)
        if m:
            if current:
                yield current, buf
            current, buf = m.group(1), []
            continue
        if current and HEADING.match(line):
            yield current, buf
            current, buf = None, []
            continue
        if current:
            buf.append(line)
    if current:
        yield current, buf


def check(block_lines, base: pathlib.Path):
    results = []
    for raw_line in block_lines:
        # citations resolve left-to-right; a bare :NN inherits the last named path
        last_path = None
        # collect token hints keyed by the citation text they annotate
        hints = {}
        for m in TOK_BEFORE.finditer(raw_line):
            hints.setdefault(m.end(), []).append(m.group(1))
        for m in TOK_AFTER.finditer(raw_line):
            hints.setdefault(m.start(), []).append(m.group(1))
        for m in CITE.finditer(raw_line):
            path, a, b = m.group(1), int(m.group(2)), m.group(3)
            b = int(b) if b else a
            if path:
                last_path = path
            elif last_path is None:
                results.append(("NOPATH", f":{a}", "bare :N with no preceding path"))
                continue
            p = base / (path or last_path)
            L = lines_of(p)
            if L is None:
                results.append(("MISSING", f"{path or last_path}:{a}", "file not found/readable"))
                continue
            if a < 1 or b > len(L):
                results.append(("RANGE", f"{path or last_path}:{a}-{b}", f"file has {len(L)} lines"))
                continue
            tok = None
            for end, toks in hints.items():
                if abs(end - m.end()) <= 1 or abs(end - m.start()) <= 1:
                    tok = toks[0]
                    break
            if tok:
                seg = L[a - 1:b]
                if token_present(tok, seg):
                    results.append(("OKC", f"{path or last_path}:{a}-{b}", tok))
                else:
                    results.append(("CONTENT", f"{path or last_path}:{a}-{b}", f"token not in range: {tok!r}"))
            else:
                results.append(("OK", f"{path or last_path}:{a}-{b}", ""))
    return results


def main():
    if not CATALOG.exists():
        print(f"catalog not found: {CATALOG}")
        return 2
    grand = {"OK": 0, "OKC": 0, "CONTENT": 0, "RANGE": 0, "MISSING": 0, "NOPATH": 0}
    seen = 0
    for slug, block_lines in blocks(CATALOG.read_text()):
        base = JOURNEYS / slug
        if not base.is_dir():
            print(f"[MISSING] journey directory {base}")
            grand["MISSING"] += 1
            continue
        seen += 1
        res = check(block_lines, base)
        counts = {}
        for kind, _ref, _note in res:
            counts[kind] = counts.get(kind, 0) + 1
            grand[kind] = grand.get(kind, 0) + 1
        bad = [r for r in res if r[0] in ("CONTENT", "RANGE", "MISSING", "NOPATH")]
        print(f"{slug}: {len(res):3d} refs  range-ok={len(res) - len(bad) + counts.get('CONTENT', 0):3d}  "
              f"content-checked={counts.get('OKC', 0):3d}  problems={len(bad)}")
        for kind, ref, note in bad:
            print(f"    [{kind}] {ref}  {note}")
    print()
    total = sum(grand.values())
    print(f"{seen} journey blocks | TOTAL {total} refs | content-verified {grand['OKC']} | "
          f"range-only {grand['OK']} | CONTENT-FAIL {grand['CONTENT']} | "
          f"RANGE-FAIL {grand['RANGE']} | MISSING {grand['MISSING']} | NOPATH {grand['NOPATH']}")
    return 1 if (grand["RANGE"] or grand["MISSING"] or grand["NOPATH"]) else 0


sys.exit(main())
