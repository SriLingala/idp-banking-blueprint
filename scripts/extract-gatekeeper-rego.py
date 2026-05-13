#!/usr/bin/env python3
"""Extract embedded Gatekeeper Rego from ConstraintTemplates for local tests."""

from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
TEMPLATE_DIR = ROOT / "policies" / "opa" / "templates"
OUT_DIR = ROOT / "build" / "opa"


def extract_rego(text: str) -> str:
    match = re.search(r"(?ms)^ {6}rego: \|\n(?P<body>(?: {8}.*\n?)*)", text)
    if not match:
        raise ValueError("missing `rego: |` block")

    lines = []
    for line in match.group("body").splitlines():
        if line.startswith("        "):
            lines.append(line[8:])
        else:
            lines.append(line)
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for existing in OUT_DIR.glob("*.rego"):
        existing.unlink()

    for template in sorted(TEMPLATE_DIR.glob("*.yaml")):
        try:
            rego = extract_rego(template.read_text())
        except ValueError as exc:
            print(f"{template}: {exc}", file=sys.stderr)
            return 1

        package = re.search(r"(?m)^package\s+([a-zA-Z0-9_]+)", rego)
        if not package:
            print(f"{template}: extracted Rego has no package", file=sys.stderr)
            return 1

        out = OUT_DIR / f"{package.group(1)}.rego"
        out.write_text(rego)
        print(f"wrote {out.relative_to(ROOT)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

