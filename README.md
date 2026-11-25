# avdslim

Clone a stopped Android emulator for each task. On APFS, clones share disk blocks with the original until they write to them. On other filesystems, `clone` falls back to a full copy.

## Run a task

Install the Android SDK on macOS and run `make install` to symlink the script into `~/.local/bin`. Use `avdslim list` to find the golden and any clones you own. Name each clone `<TASK-ID>-<role>`:

```sh
name=SUBS-421-renter
avdslim clone Ailo_Golden_API34 "$name" || exit 1
SERIAL=$(avdslim boot "$name") || exit 1
adb -s "$SERIAL" shell getprop ro.build.version.sdk
avdslim install "$name" new-build.apk
avdslim delete "$name" --stop
```

Reuse your own clone across checks. `boot` prints only the ready serial on success; `serial` retrieves a running emulator's serial without waiting for Android. Use `--window` for a visible emulator. After `shutdown`, a used clone cold boots to preserve its data. Clones never save snapshots.

A new clone tries to restore the golden's snapshot. If the emulator rejects it, `boot` reports the cold fallback on stderr. If any recorded app is missing, boot fails. Delete your clone and retry with a fresh one; if it happens again, ask the owner to re-seal the golden.

## Maintain a golden

Start with an AVD created in Android Studio or `avdmanager`. Install the apps you want and seal it **while running**:

```sh
avdslim boot MyGolden
avdslim install MyGolden app.apk
avdslim golden MyGolden
```

Sealing flushes the guest disk, records third-party packages, saves the boot snapshot and stops the emulator. On a stopped AVD, `golden` only marks it. To refresh, `boot MyGolden --golden --cold`, install with `--golden`, then `shutdown MyGolden`. Use this after an emulator upgrade or to replace an old snapshot that only loads headless. Existing clones keep their original data.

## Reference

- `avdslim --help` lists commands. `--json` works with `list`, `status`, `clone`, `boot`, `shutdown` and `delete`. Batch delete returns an array; single delete returns an object.
- Exit codes: `0` success, `1` failure, `2` usage, `3` safety refusal.
- Set `ANDROID_SDK_ROOT` or `ANDROID_HOME` for a non-default SDK, `ANDROID_AVD_HOME` for a non-default AVD directory, and `AVDSLIM_STATE` for logs and locks. Use the same state directory across concurrent agents.
- Run `make check` for shellcheck and the offline fake-emulator tests.
