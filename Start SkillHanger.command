#!/bin/zsh
set -e

project_dir="${0:A:h}"
cd "$project_dir"
if [[ ! -x "$project_dir/dist/SkillHanger.app/Contents/MacOS/SkillHanger" ]]; then
    make app
fi
open "$project_dir/dist/SkillHanger.app"
