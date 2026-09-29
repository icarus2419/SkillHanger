# Optional closed-lid helper

The helper is implemented but its installation and real-task behavior are awaiting verification. The bounded probe proved closed-lid execution on this Mac, not universal compatibility.

The menu app works without this helper and prevents idle system sleep while a monitored task runs. The helper adds privileged closed-lid control. It stays off until you enable **Keep working with the lid closed** in the menu.

## What you authorize by installing

- A root-owned launchd service that starts with macOS and accepts short activity leases from your user account.
- Processes running as your user can request this limited sleep setting through the lease file. The helper accepts no shell commands, file paths, prompts, or transcripts from the app.
- The global `pmset disablesleep` setting is enabled only with an opted-in, fresh lease reporting a running task. Waiting, completion, cancellation, app exit, or a lease older than eight seconds restores the helper's owned setting. Polling and system-command latency can add a few seconds.
- Battery must be at least 30% to activate; at 20% or serious thermal pressure, normal sleep is restored. A root-owned recovery marker allows startup restoration after interruption.
- Other closed-lid utilities can conflict with the same global setting. Disable them first. Use a hard, ventilated surface and keep the Mac out of a bag while it works.

## Install after approval

In Terminal, enter `sudo ` followed by dragging `agent-awake-closed-lid` from the app's `Contents/MacOS` folder into Terminal, then add ` install`. For an app installed in Applications, the command is:

```sh
sudo /Applications/SkillHanger.app/Contents/MacOS/agent-awake-closed-lid install
```

Enter your administrator password in Terminal only. Installation does not enable the setting. Open SkillHanger's menu, enable the switch, and check that the helper reports active while a monitored task runs. A production physical test is still required before relying on unattended work.

## Recovery and removal

Turn the menu switch off to restore normal sleep. If the app or helper is unresponsive, this command stops the helper and restores its owned setting:

```sh
sudo /Library/PrivilegedHelperTools/com.agentawake.closedlid recover
```

Recovery leaves the helper installed for the next boot. To remove it and its service files:

```sh
sudo /Library/PrivilegedHelperTools/com.agentawake.closedlid uninstall
```

Check afterward with `pmset -g` and confirm `SleepDisabled` is zero or absent. The helper does not restore a setting owned by another utility.
