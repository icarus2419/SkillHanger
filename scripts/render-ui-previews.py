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
for page in ("overview", "marketplace", "installed", "usage", "awake", "activity", "settings"):
    extras = ["--installed-library-preview"] if page == "installed" else []
    for appearance in ("light", "dark"):
        cases.append((f"{page}-{appearance}", ["--page", page, "--appearance", appearance, *extras]))
    cases.append((f"{page}-compact", ["--page", page, "--appearance", "light", "--compact-preview", *extras]))
for name, flags in [
    ("community-light", ["--page", "marketplace", "--marketplace-community-preview", "--appearance", "light"]),
    ("community-dark", ["--page", "marketplace", "--marketplace-community-preview", "--appearance", "dark"]),
    ("community-compact", ["--page", "marketplace", "--marketplace-community-preview", "--compact-preview", "--appearance", "dark"]),
    ("library-claude", ["--page", "marketplace", "--marketplace-claude-preview", "--appearance", "light"]),
    ("library-empty", ["--page", "marketplace", "--marketplace-empty-preview", "--compact-preview"]),
    ("library-offline", ["--page", "marketplace", "--marketplace-error-preview", "--compact-preview", "--appearance", "dark"]),
    ("library-installed", ["--page", "marketplace", "--library-installed-preview", "--installed-library-preview"]),
    ("library-detail-light", ["--page", "marketplace", "--marketplace-detail-preview", "--appearance", "light"]),
    ("library-detail-dark", ["--page", "marketplace", "--marketplace-detail-preview", "--appearance", "dark"]),
    ("package-compact", ["--page", "package", "--package-workspace-preview", "--compact-preview"]),
    ("package-design-controls", ["--page", "package", "--package-workspace-preview", "--package-preview-name", "ui-ux-pro-max", "--package-design-system-preview", "--appearance", "dark"]),
    ("plugin-workspace", ["--page", "package", "--plugin-workspace-preview", "--marketplace-claude-preview", "--appearance", "light"]),
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
    ("usage-popup-light", ["--page", "usage", "--usage-popup-preview", "--appearance", "light"]),
    ("usage-popup-dark", ["--page", "usage", "--usage-popup-preview", "--appearance", "dark"]),
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
    expected = (610, 590) if "--marketplace-detail-preview" in flags else (940, 660) if "--compact-preview" in flags else (1180, 820)
    if "--usage-popup-preview" in flags:
        if width not in (350, 700) or not 250 <= height * 350 / width <= 950:
            raise RuntimeError(f"{name}: unexpected popup size {width}x{height}")
        expected = (350, round(height * 350 / width))
    if abs(width / height - expected[0] / expected[1]) > 0.005:
        raise RuntimeError(f"{name}: unexpected size {width}x{height}")
    return {"case": name, "flags": flags, "file": destination.name,
            "pixels": [width, height], "window": list(expected)}

with ThreadPoolExecutor(max_workers=2) as executor:
    results = list(executor.map(render, cases))
(output / "manifest.json").write_text(json.dumps(results, indent=2) + "\n")
print(f"Rendered {len(results)} isolated UI cases; manifest: {output / 'manifest.json'}")
