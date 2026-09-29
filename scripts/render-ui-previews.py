#!/usr/bin/env python3
"""Render isolated SkillHanger UI cases offscreen, including lower page sections."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import json
import struct
import subprocess

root = Path(__file__).resolve().parent.parent
binary = root / "dist/SkillHanger.app/Contents/MacOS/SkillHanger"
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, default=root / "tasks/evidence/skillhanger-crimson")
output = parser.parse_args().output.resolve()
output.mkdir(parents=True, exist_ok=True)
cases = []
for page in ("overview", "usage", "awake", "activity", "settings"):
    for appearance in ("light", "dark"):
        cases.append((f"{page}-{appearance}", ["--page", page, "--appearance", appearance]))
    cases.append((f"{page}-compact", ["--page", page, "--appearance", "light", "--compact-preview"]))
for name, flags in [
    ("activity-working", ["--page", "activity", "--activity-filter", "Working", "--appearance", "light"]),
    ("activity-waiting", ["--page", "activity", "--activity-filter", "Waiting", "--appearance", "dark"]),
    ("activity-finished", ["--page", "activity", "--activity-filter", "Finished", "--appearance", "light", "--compact-preview"]),
    ("reduce-motion", ["--page", "overview", "--appearance", "dark", "--reduce-motion-preview"]),
    ("widget-moved", ["--page", "settings", "--settings-tab", "widget", "--appearance", "light", "--preview-widget-moved"]),
    ("activity-empty", ["--page", "activity", "--empty-preview"]),
    ("overview-empty", ["--page", "overview", "--empty-preview"]),
    ("activity-paused", ["--page", "activity", "--preview-scenario", "paused"]),
    ("usage-loading", ["--page", "usage", "--preview-scenario", "loading"]),
    ("usage-error", ["--page", "usage", "--preview-scenario", "error", "--compact-preview"]),
    ("usage-stale", ["--page", "usage", "--appearance", "dark", "--preview-scenario", "stale"]),
    ("usage-disabled", ["--page", "usage", "--appearance", "dark", "--preview-scenario", "disabled"]),
    ("widget-light", ["--page", "settings", "--settings-tab", "widget", "--appearance", "light"]),
    ("widget-dark", ["--page", "settings", "--settings-tab", "widget", "--appearance", "dark"]),
    ("power-settings", ["--page", "settings", "--settings-tab", "awake"]),
    ("settings-bottom", ["--page", "settings", "--compact-preview", "--preview-bottom"]),
    ("widget-bottom", ["--page", "settings", "--settings-tab", "widget", "--appearance", "dark", "--compact-preview", "--preview-bottom"]),
    ("awake-bottom", ["--page", "awake", "--compact-preview", "--preview-bottom"]),
    ("connect-agent", ["--page", "activity", "--compact-preview", "--preview-connect-agent"]),
]:
    cases.append((name, flags))

def render(case):
    name, flags = case
    destination = output / f"{name}.png"
    destination.unlink(missing_ok=True)
    result = subprocess.run([str(binary), "--render-preview", str(destination), *flags],
                            capture_output=True, text=True, timeout=30)
    if result.returncode or not destination.is_file():
        raise RuntimeError(f"{name}: render failed: {result.stderr}")
    header = destination.read_bytes()[:24]
    if header[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"{name}: invalid PNG")
    width, height = struct.unpack(">II", header[16:24])
    expected = (940, 660) if "--compact-preview" in flags else (1180, 820)
    if abs(width / height - expected[0] / expected[1]) > 0.005:
        raise RuntimeError(f"{name}: unexpected size {width}x{height}")
    return {"case": name, "flags": flags, "file": destination.name,
            "pixels": [width, height], "window": list(expected)}

with ThreadPoolExecutor(max_workers=2) as executor:
    results = list(executor.map(render, cases))
(output / "manifest.json").write_text(json.dumps(results, indent=2) + "\n")
print(f"Rendered {len(results)} isolated UI cases; manifest: {output / 'manifest.json'}")
