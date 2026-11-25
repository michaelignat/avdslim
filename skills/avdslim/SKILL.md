---
name: avdslim
description: Get an isolated Android emulator per task by cloning the golden AVD copy-on-write, boot it, test on it, and delete it. Use whenever a task needs an Android emulator, runs emulators in parallel, or must reinstall a build on Android. Never boot, modify or install onto the golden AVD or someone else's emulator.
---

# avdslim

`avdslim` clones the golden AVD (`Ailo_Golden_API34`: Android 34, the DEV consumer app `app.ailo`, no sign-ins) in about 0.3s for about 10 MB, boots it in seconds and prints its serial.

## Workflow

1. Reuse this task's clone if `avdslim list` shows one named after the task. Otherwise clone:
   `avdslim clone Ailo_Golden_API34 "<TASK-ID>-<role>"`, for example `SUBS-421-renter`. Spaces become `-`; use the printed name.
2. Boot it: `SERIAL=$(avdslim boot <name>)`. Stdout is only the serial (`emulator-5554`). Booting an already running clone prints its serial again.
3. Pin every command to that serial:
   - `adb -s "$SERIAL" ...`
   - `agent-device open <package> --serial "$SERIAL" --session <name>`
4. Install the task's build: `adb -s "$SERIAL" install -r <apk>` (split APKs: `install-multiple -r`). Do not edit the golden to do this.
5. When the task is done, delete your clones: `avdslim delete <name> --stop`.

## Rules

- Never pass `--golden`. It exists for the user to refresh the golden.
- Only touch clones you created. Never stop, restart, install onto or delete another task's emulator, including ones `avdslim list` shows as `avd`.
- Clone once per phone that must run at the same time (renter and investor side by side), not once per check.
- Do not clone a clone; clone the golden. A running AVD cannot be cloned.
- `avdslim boot` starts from the golden's saved snapshot. If the app state looks stale or wrong, use `--cold`. If the boot times out, read `~/.local/state/avdslim/logs/<name>.log`.
- Animations stay on by default. Add `--no-animations` to `boot` only when motion is not under test.
- Use `avdslim list --json` or `avdslim status <name> --json` when you need to parse state. Exit code 3 means a safety rule refused the action; do not work around it.
