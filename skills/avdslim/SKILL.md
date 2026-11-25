---
name: avdslim
description: Clone and boot an isolated Android emulator for a task, pin commands to its serial, and clean it up after testing.
---

# Run a task on Android

1. Choose `<TASK-ID>-<role>`, e.g. `name=SUBS-421-renter`. Check `avdslim list --json`. Reuse only a clone you know belongs to your task. Otherwise run `avdslim clone Ailo_Golden_API34 "$name"`.
2. Capture the serial: `SERIAL=$(avdslim boot "$name") || exit 1`. Add `--window` for a visible emulator. If another command holds the lock, wait and retry.
3. Pin every command: `adb -s "$SERIAL" …` or `agent-device open <package> --serial "$SERIAL" --session "$name"`. Install the task's build with `avdslim install "$name" <apk>`.
4. Use `avdslim shutdown "$name"` to keep the clone between sessions. Its next boot is cold to preserve installed apps and sign-ins. When finished, run `avdslim delete "$name" --stop`.

If a snapshot fails to load, check the reported reason and verify the expected state before testing. If boot reports missing apps, delete your clone and clone again. If it repeats, ask the golden's owner to re-seal it. On timeout, inspect the reported log and retry boot.

Never use `--force`, `--golden`, `adb kill-server` or process-wide kills. Other tasks share the host and adb server. Exit 3 is a safety refusal; do not work around it.
