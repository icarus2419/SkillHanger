#!/usr/bin/env python3
"""Package one combined app and preserve existing Agent Awake launch paths."""
from pathlib import Path
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
dist = root / "dist"
app = dist / ".SkillHanger.staging.app"
if app.exists():
    shutil.rmtree(app)
binary_dir = root / ".build/release"
macos = app / "Contents/MacOS"
resources = app / "Contents/Resources"
macos.mkdir(parents=True, exist_ok=True)
resources.mkdir(parents=True, exist_ok=True)
for name in ("SkillHanger", "agent-awake", "agent-awake-lid-probe", "agent-awake-closed-lid"):
    shutil.copy2(binary_dir / name, macos / name)
compat_binary = macos / "AgentAwakeApp"
if compat_binary.exists() or compat_binary.is_symlink():
    compat_binary.unlink()
compat_binary.symlink_to("SkillHanger")
shutil.copy2(root / "Resources/Info.plist", app / "Contents/Info.plist")
shutil.copy2(root / "Resources/ClosedLidSetup.md", resources)
(resources / "Readme.md").write_text((root / "README.md").read_text().replace("Resources/ClosedLidSetup.md", "ClosedLidSetup.md"))
shutil.copytree(root / "docs/images", resources / "docs/images")
shutil.copytree(binary_dir / "SkillHanger_AgentAwakeApp.bundle", resources / "SkillHanger_AgentAwakeApp.bundle")
iconset = dist / "AppIcon.iconset"
subprocess.run(["swift", str(root / "scripts/make-icon.swift"), str(iconset),
                str(root / "Sources/AgentAwakeApp/Assets/SkillHangerLogo.png")], check=True)
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns")], check=True)
shutil.rmtree(iconset)
subprocess.run(["codesign", "--force", "--deep", "--sign", "-", str(app)], check=True)
final_app = dist / "SkillHanger.app"
previous_app = dist / ".SkillHanger.previous.app"
if previous_app.exists():
    shutil.rmtree(previous_app)
if final_app.exists():
    final_app.rename(previous_app)
app.rename(final_app)
if previous_app.exists():
    shutil.rmtree(previous_app)
compat_app = dist / "AgentAwake.app"
if compat_app.is_symlink():
    compat_app.unlink()
elif compat_app.exists():
    # This path is the prior generated package, never a source directory.
    shutil.rmtree(compat_app)
compat_app.symlink_to("SkillHanger.app")
print(f"Packaged {final_app}")
