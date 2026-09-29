#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
helper_path="${project_dir}/dist/SkillHanger.app/Contents/MacOS/agent-awake-closed-lid"
if [[ ! -x "$helper_path" ]]; then
    print -u2 "Build the packaged app with make app first."
    exit 1
fi
print "This installs the optional root service. Closed-lid mode stays off until enabled in SkillHanger."
exec sudo "$helper_path" install
