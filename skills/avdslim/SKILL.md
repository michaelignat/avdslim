---
name: avdslim
description: Get an isolated Android emulator per task by cloning the golden AVD copy-on-write, boot it, test on it, and delete it. Use whenever a task needs an Android emulator, runs emulators in parallel, or must reinstall a build on Android. Never boot, modify or install onto the golden AVD or someone else's emulator.
---

# avdslim

`avdslim` clones the golden AVD (`Ailo_Golden_API34`: Android 34, the DEV consumer app `app.ailo`, no sign-ins) in under a second for a few MB, boots it in seconds and prints its serial.

## Workflow

1. Reuse this task's clone if `avdslim list` shows one named after the task. Otherwise clone:
   `avdslim clone Ailo_Golden_API34 <TASK-ID>-<role>`, for example `SUBS-421-renter`.
2. Boot it: `SERIAL=$(avdslim boot <name>)`. Stdout is only the serial (`emulator-5554`). Add `--window` to see it. Booting a running clone prints its serial again.
3. Pin every command to that serial:
   - `adb -s "$SERIAL" ...`
   - `agent-device open <package> --serial "$SERIAL" --session <name>`
4. Install the task's build: `avdslim install <name> <apk>` (or `adb -s "$SERIAL" install -r <apk>`).
5. When the task is done, delete your clones: `avdslim delete <name> --stop`.

## What to expect from boot

- A clone's first boot restores the golden's snapshot (2-7s). After `avdslim shutdown`, later boots of that clone are cold boots (20-45s) and keep everything you installed and signed in to.
- `boot` checks its own result. Read stderr:
  - `snapshot failed` warning: the emulator rejected the snapshot and cold booted. The clone is usable but slower to start; report the printed reason.
  - exit 1 with "missing apps its golden had": the clone is broken. Delete it and clone again. If it repeats, stop and report that the golden needs re-sealing.
  - timeout: read `~/.local/state/avdslim/logs/<name>.log`.

## Rules

- Never pass `--golden` or `--force`. They exist for the user to refresh the golden and remove foreign AVDs.
- Only touch clones you created. Never stop, restart, install onto or delete another task's emulator, including ones `avdslim list` shows as `avd`.
- Never run `adb` without `-s "$SERIAL"`, and never `adb kill-server` or kill emulator processes; other tasks share the adb server.
- Clone once per phone that must run at the same time (renter and investor side by side), not once per check.
- Clone the golden, not a clone (refused).
- Animations stay on. Add `--no-animations` to `boot` only when motion is not under test.
- Parse state with `avdslim list --json` or `avdslim status <name> --json`. Exit code 3 means a safety rule refused the action; do not work around it.
