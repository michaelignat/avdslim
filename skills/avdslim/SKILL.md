---
name: avdslim
description: Clone and boot an isolated Android emulator for a task, pin commands to its serial, and clean it up after testing.
---

# Android emulator for a task

**Golden:** `Ailo_Golden_API34`. Clone it. Never boot, change or delete it.

## Steps

1. **Clone.** Reuse your task's clone if it exists (`avdslim list`). Otherwise:
   `avdslim clone Ailo_Golden_API34 <TASK-ID>-<role>`, e.g. `SUBS-421-renter`
2. **Boot.** `SERIAL=$(avdslim boot <name>) || exit 1`. Add `--window` to see it.
3. **Use.** Pin everything to the serial: `adb -s "$SERIAL" …`, `agent-device … --serial "$SERIAL"`
4. **New build?** `avdslim install <name> <apk>`
5. **Done.** `avdslim delete <name> --stop`. To keep it for later: `avdslim shutdown <name>`

## If something goes wrong

- **Apps missing on boot:** delete your clone and clone again.
- **`INSTALL_FAILED_UPDATE_INCOMPATIBLE`:** your build is signed with a different key from the installed one, for example a local debug build. Run `adb -s "$SERIAL" uninstall <package>`, then install. This only wipes that app's data on your clone.
- **Busy lock:** wait and retry.

## Never

- `--force` or `--golden`
- `adb kill-server`, `pkill` or `killall` on emulators
- Any command on another task's emulator

Exit code `3` is a safety refusal. Don't work around it.
