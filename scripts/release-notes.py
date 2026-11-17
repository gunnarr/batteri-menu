#!/usr/bin/env python3
"""Prints the CHANGELOG.md section for a version as HTML, for the update window."""
import html
import pathlib
import sys

version = sys.argv[1]
lines = (pathlib.Path(__file__).parent.parent / "CHANGELOG.md").read_text().splitlines()
items, current, inside = [], None, False
for line in lines:
    if line.startswith("## "):
        if inside:
            break
        inside = line[3:].split()[0] == version
        continue
    if not inside:
        continue
    if line.startswith("- "):
        current = [line[2:].strip()]
        items.append(current)
    elif line.strip() and current is not None:
        current.append(line.strip())
if not items:
    sys.exit(f"No entries for {version} in CHANGELOG.md")
print("<ul>")
for item in items:
    print(f"<li>{html.escape(' '.join(item))}</li>")
print("</ul>")
