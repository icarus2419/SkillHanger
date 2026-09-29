# SkillHanger

**UsageBar + Agent Awake, together in one native macOS app.** See your AI plan allowance, follow local Claude Code and Codex tasks, and control how your Mac stays awake while they work.

The full app window has six main pages, plus a dedicated sidebar page for each installed skill or plugin:

- **Skill Library:** browse GitHub skills and plugins, explore community coding styles, and install for Codex or Claude Code.
- **Overview:** plan allowance, task state, sleep protection, and quick switches.
- **Usage:** remaining limits, reset times, source/freshness, provider switches, refresh, and alerts.
- **Agent Awake:** monitoring, per-provider task selection, idle sleep protection, dim task display, closed-lid helper status, and copyable command/hook setup.
- **Activity:** recent tasks with state filters, search, elapsed time, observed tool actions, and real token counts when supplied.
- **Settings:** appearance, launch at login, menu bar, provider checks, refresh/alerts, floating widget layout/size/opacity/placement/names/colors/locking/snapping, and Agent Awake preferences.

Settings save as you change them. Overview setting tiles toggle their real preferences; Activity count tiles filter sessions and toggle back to All on a second click. The header includes a light/dark appearance shortcut. The widget preview supports dragging and centering a local trial placement; move the real floating widget to save its actual position. The original draggable UsageBar batteries, colors, provider marks, and compact usage popup remain available. The full Usage and Overview pages use the same original continuous bars and green/yellow/red palette. Clicking the floating battery or menu bar batteries opens usage details. The popup's Settings action explicitly opens SkillHanger settings. Closing the window leaves monitoring and the menu bar running. Choose Quit from the app menu to stop it.

The interface keeps its burgundy sidebar and crimson logo, with warm charcoal or soft white workspace surfaces and restrained crimson/rose controls. A compact protection summary and one shared quick-control row leave more space for usage and sessions. Both appearances share the same layout and controls, including the original slim UsageBar capacity bars.

SkillHanger's logo is a deep-crimson hooked “h” with soft rounded geometry, reflecting the app's name. It appears in the sidebar, About, empty Activity state, usage popup, and Dock icon, with matching burgundy navigation accents. Its transparent [source asset](Sources/AgentAwakeApp/Assets/SkillHangerLogo.png) is included.

UsageBar's existing reader/parser/watcher code lives in this repository's `UsageCore` target. Its original neighboring repository is unchanged. Agent Awake's core, task directory, bundle identifier, CLI names, and helper identifiers remain compatible. Existing UsageBar display preferences and metadata cache are imported once without replacing values already saved by this app; credentials are never imported or cached.

Usage checks use the providers' existing CLI logins and allowlisted read-only HTTPS endpoints. Local Codex session files can supply usage snapshots. Only usage/task metadata is retained: no saved prompts, transcripts, or response text.

## Build and launch

Requires macOS 13+ and Swift 6 toolchain. No third-party runtime dependencies.

```sh
swift test
make app
open dist/SkillHanger.app
```

After packaging, double-click `Start SkillHanger.command` to open the app. If the package is missing, it builds it first. The generated `dist/AgentAwake.app` path remains a compatibility alias.

To show Activity while keeping your current app focused: `open -g dist/SkillHanger.app --args --background --page activity`.

For a reproducible UI preview without network checks, power assertions, or live task records:

```sh
dist/SkillHanger.app/Contents/MacOS/SkillHanger --preview --page activity
```

Render a page with isolated sample data:

```sh
dist/SkillHanger.app/Contents/MacOS/SkillHanger --render-preview /tmp/skillhanger.png --page settings --appearance light
```

Pages: `overview`, `usage`, `awake`, `activity`, `settings`. Additional preview flags: `--compact-preview`, `--empty-preview`, `--settings-tab widget`, `--settings-tab awake`, `--preview-bottom`, `--preview-connect-agent`, `--activity-filter Working|Waiting|Finished`, `--preview-widget-moved`, `--reduce-motion-preview`, and `--preview-scenario loading|error|stale|disabled|paused`. Render previews stay offscreen and do not insert a menu bar item or switch app focus. Screenshots are visibly labeled. The normal application never seeds sample readings or scenario states.

UsageBar's usage endpoints are undocumented and may change. Login/rate-limit/network errors and stale readings are shown explicitly; retry backoff is preserved. Usage checks do not run model inference or spend tokens.

The packaged CLI is at `dist/SkillHanger.app/Contents/MacOS/agent-awake`. For a quick supervised task:

```sh
dist/SkillHanger.app/Contents/MacOS/agent-awake run codex -- codex exec "your task"
```

Or use `run claude -- claude -p "your task"`. The wrapper accepts finite `codex exec` and `claude -p` tasks only; interactive sessions need hooks because an open interactive process can be idle between tasks. It passes the child's input and output through to the terminal, records a heartbeat while the process exists, and records completion, failure, or cancellation when it exits. When provider hooks are also enabled, their events update the wrapper's single task card; a permission wait releases the sleep assertion until activity resumes. Run it from the directory where the agent should work. A wrapper process that is force-killed becomes `status unknown` within eight seconds.

For Codex batch tasks, `run codex -- codex exec --json "your task"` also records the actual `input_tokens` and `output_tokens` from a `turn.completed` event. The JSON stream still prints to your terminal. Other launch modes show “Tokens unavailable” until a provider supplies observed usage.

For Claude batch tasks, `run claude -- claude -p --output-format json "your task"` records usage from the final `result` object. The displayed input count includes uncached, cache creation, and cache read tokens. Claude's JSON output still prints to your terminal. `--output-format stream-json` works too.

## Monitor ordinary interactive sessions

Provider hooks are opt-in. **Do not replace existing provider configuration.** Merge the following event handlers into your user-level Claude Code `~/.claude/settings.json` and Codex `~/.codex/hooks.json`, using an **absolute path to your installed app's** `Contents/MacOS/agent-awake` binary. The examples below use `/ABSOLUTE/PATH/TO/agent-awake`; substitute the actual path before saving. Codex may ask you to review or trust the new hooks with `/hooks`.

Claude Code example event entry (merge each event into the existing `hooks` object):

```json
{
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}],
    "PostToolUse": [{"hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}],
    "PermissionRequest": [{"hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}],
    "Notification": [{"matcher": "permission_prompt|idle_prompt", "hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}],
    "StopFailure": [{"hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}],
    "SessionEnd": [{"hooks": [{"type": "command", "command": "/ABSOLUTE/PATH/TO/agent-awake hook claude"}]}]
  }
}
```

Codex `hooks.json` uses the same event object shape. Use `hook codex` for `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PermissionRequest`, `Stop`, `Interrupt`, and `SessionEnd`. Prefer `~/.codex/hooks.json` for user-level coverage. Codex's project-local notification and hook configuration has separate precedence/trust behavior; inspect `/hooks` to verify which files loaded.

The app stores task metadata in `~/Library/Application Support/AgentAwake/tasks` with directory mode 0700 and task files mode 0600. A hook-only task becomes `status unknown` after 120 seconds without another event, and the idle sleep assertion is released. This conservative timeout means a very long silent model call may lose sleep prevention. Use the supervised wrapper when continuous process lifetime matters.

The animation reflects observed lifecycle state and tool-action events. The tool-action count is not a completion percentage.

## Lid-close status

Apple documents that an idle sleep assertion does **not** prevent lid-close sleep. A user-authorized test on this Mac (`Mac16,1`, macOS 15.5) confirmed that the privileged, system-wide `pmset disablesleep` setting allowed the probe to continue executing on battery with the lid closed for 171 seconds. It recorded 146 closed-lid samples, with a maximum gap of two seconds. Normal sleep was restored and the temporary recovery service was removed. This establishes feasibility on this Mac; it does not yet verify the task-controlled helper or an actual provider task during lid closure. **The optional helper is implemented and packaged, but not installed or enabled.** See the [setup instructions](Resources/ClosedLidSetup.md).

The probe's read-only check is `dist/SkillHanger.app/Contents/MacOS/agent-awake-lid-probe status`. Its root-only `start` command requires battery power of at least 30%, starts a temporary root-owned recovery service before changing `SleepDisabled`, and restores normal sleep at the latest after three minutes, or earlier for low battery, thermal pressure, a power-source change, normal completion, or reboot. It writes a timestamp report under `/var/tmp`. The authorized physical test exercised privileged start, closed-lid sampling, and restoration after the time limit; low-battery, thermal, crash, and reboot recovery still need physical verification. `recover` is the manual restoration command if the test is interrupted.

## Sources

- [Apple idle system sleep assertion](https://developer.apple.com/documentation/iokit/kiopmassertiontypepreventuseridlesystemsleep)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks)
- [Codex hooks guide](https://learn.chatgpt.com/docs/hooks)
# Skill Library

SkillHanger includes a native skill and plugin browser with 459 sourced entries in its initial catalog. Skill Library opens on Browse, with Caveman, Ponytail, and Karpathy Guidelines leading the Popular list. Choose Codex or Claude Code, search by capability or publisher, filter by category and Community/Skills/Plugins/Installed, and open an entry for its description and GitHub source. Click Install once to add it at user scope, then start a new agent session. Connected plugin services may still need account setup in the agent.

The catalog comes from [OpenAI plugins](https://github.com/openai/plugins), [Anthropic's plugin directory](https://github.com/anthropics/claude-plugins-official), [Anthropic skills](https://github.com/anthropics/skills), [Superpowers](https://github.com/obra/superpowers), and [Vercel agent skills](https://github.com/vercel-labs/agent-skills). It also includes researched community packages from [Caveman](https://github.com/JuliusBrussee/caveman), [Ponytail](https://github.com/DietrichGebert/ponytail), [Karpathy Guidelines](https://github.com/multica-ai/andrej-karpathy-skills), [Matt Pocock](https://github.com/mattpocock/skills), [Taste Skill](https://github.com/Leonxlnx/taste-skill), [Planning With Files](https://github.com/OthmanAdi/planning-with-files), [Addy Osmani](https://github.com/addyosmani/agent-skills), and [Impeccable](https://github.com/pbakaus/impeccable). Community entries explain purpose, when to use them, invocation, and setup requirements. Repository stars are dated discovery evidence, not a quality guarantee. The shared `marketplace-sources.json` controls canonical paths and explanations for both bundled discovery and live refresh, avoiding mirrored copies. Refresh catalog fetches current metadata and retains saved entries when a source is unavailable. These directory listings do not imply every third-party package is audited.

Skills install as complete folders at the catalog commit into `~/.agents/skills` for Codex or `~/.claude/skills` for Claude Code. Existing legacy `~/.codex/skills` folders are recognized. SkillHanger preserves name conflicts and locally edited files. Plugins use the native CLI; Codex's GitHub packages use a separate `skillhanger-github-openai` catalog because `openai-curated` is reserved. Existing official-directory installs are also recognized. No hooks or account connections are approved automatically.

After installation, a dedicated package page opens and stays available in the sidebar. It displays the package’s available original logo, description, supported modes, saved per-agent invocation, source, installed instructions, and ownership-aware removal. Caveman includes lite/full/ultra, Wenyan variants, and off. Invocation preferences build a command to copy into the agent; they do not silently change an active session. Managed standalone skills can be disabled and restored without deleting their files. Claude plugins expose their native user-scope enable switch when inventory confirms its state. Codex’s current plugin CLI does not expose that switch.

Installed sidebar entries are grouped by Codex and Claude Code, with a separate search that matches package, publisher, type, and agent. Each entry shows Skill or Plugin and confirmed disabled status. The main navigation stays visible while installed entries scroll. Use ⌘F to search the library and ⇧⌘F to search installed entries. Clearing catalog filters keeps your current section, agent, and sort order.

Installed rows are full-width buttons with subtle borders, hover/pressed feedback, and a small chevron. Right-click a row and choose Uninstall, or swipe/drag left to reveal its red bin button. Click the bin to confirm uninstall for that row’s agent. Swipe right, click the row, or press Escape to close it; swiping never uninstalls automatically. Standalone skills installed outside SkillHanger move to Trash after their metadata and folder path are checked. Managed skills retain file-change protection, and plugins use their agent’s native uninstall command.

New researched favorites include [Humanizer](https://github.com/blader/humanizer), [UI/UX Pro Max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill), [Agent Browser](https://github.com/vercel-labs/agent-browser), [Obsidian Skills](https://github.com/kepano/obsidian-skills), and [Context Engineering](https://github.com/muratcankoylan/Agent-Skills-for-Context-Engineering). Each entry explains required companion tools and invocation. Root-directory skills such as Humanizer are supported.

Catalog maintenance: `python3 scripts/refresh-marketplace-catalog.py`, followed by `python3 scripts/refresh-package-logos.py` to bundle declared PNG plugin logos. Isolated end-to-end verification: `dist/SkillHanger.app/Contents/MacOS/SkillHanger --preview --marketplace-verify /tmp/skillhanger-verification.json`. This downloads real GitHub packages, installs/removes them in a temporary home, writes a report, and leaves user agent settings unchanged.

Package workspace verification: `dist/SkillHanger.app/Contents/MacOS/SkillHanger --preview --package-workspaces-verify /tmp/skillhanger-workspaces.json`. This checks actual pinned GitHub downloads, complete files, automatic workspace selection, saved settings, disable/re-enable, and removal in a temporary home. Package page preview: `--render-preview /tmp/caveman.png --page package --package-workspace-preview --appearance light`; plugin preview: `--page package --plugin-workspace-preview`, optionally with `--marketplace-claude-preview`.

Package-specific invocation settings now cover UI/UX Pro Max (stack, intent, design-system dials), Agent Browser (workflow guide, window visibility, isolated session), and Obsidian CLI (target vault). These settings prepare a prompt to copy into the selected agent. Reset restores only that package’s invocation preferences for that agent. Preview any adapter with `--page package --package-workspace-preview --package-preview-name ui-ux-pro-max`; add `--package-design-system-preview` for dials and `--preview-scroll-offset 500` to inspect lower controls offscreen.

## Repository layout

- `Sources/`: macOS app, shared libraries, command-line tools, and bundled assets.
- `Tests/`: existing app and core regression tests and fixtures.
- `Resources/`: app metadata and closed-lid helper setup.
- `scripts/`: packaging, catalog maintenance, and preview generation.
- `tasks/evidence/`: catalog and logo source provenance used by maintenance scripts.

Build cache (`.build/`), packaged apps (`dist/`), local editor settings, development notes, and generated preview evidence are excluded from Git. Catalog and logo source provenance are retained.
