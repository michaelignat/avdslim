# avdslim

Fast, disposable Android emulators for parallel testing.

Keep one **golden** emulator with your apps installed. Clone it for each task, then delete the clone when you're done.

- Clones take **under a second** and **a few MB** (APFS copy-on-write).
- A fresh clone boots in **about 5–10 s**.
- Several clones can run at once, each on its own serial.

The Android counterpart of [simslim](https://github.com/mobai-app/simslim).

## Install with an agent

Copy this into your coding agent:

```text
Install avdslim (https://github.com/michaelignat/avdslim) for me:

1. Download the latest release to ~/.local/bin/avdslim and make it executable:
   mkdir -p ~/.local/bin && curl -fsSL https://github.com/michaelignat/avdslim/releases/latest/download/avdslim -o ~/.local/bin/avdslim && chmod +x ~/.local/bin/avdslim
   Make sure ~/.local/bin is on my PATH, then run `avdslim version`.
2. Save https://raw.githubusercontent.com/michaelignat/avdslim/main/skills/avdslim/SKILL.md as an "avdslim" skill in your skills directory.
3. Ask me which emulator should be the golden one, or help me make one (see the README's "Make a golden").
4. Add this to my global AGENTS.md:
   "Android emulators: use avdslim. Clone the golden per task, pin commands to the serial it prints, and delete your clone when done. Never touch the golden or another task's emulator. Update avdslim by re-running the install curl command."
```

## Install

Needs macOS and the Android SDK.

```sh
mkdir -p ~/.local/bin && curl -fsSL https://github.com/michaelignat/avdslim/releases/latest/download/avdslim \
  -o ~/.local/bin/avdslim && chmod +x ~/.local/bin/avdslim
```

Run the same command again to update. From a clone of this repo: `make install`.

## Use a clone

```sh
avdslim clone MyGolden SUBS-421-renter    # name: <TASK-ID>-<role>
SERIAL=$(avdslim boot SUBS-421-renter)    # add --window to see it
adb -s "$SERIAL" ...                      # pin every command to the serial
avdslim install SUBS-421-renter app.apk   # optional: a newer build
avdslim delete SUBS-421-renter --stop     # when the task is done
```

**Good to know**

- `shutdown` keeps a clone. Its next boot is cold, so its data survives.
- If `boot` says apps are missing, delete the clone and clone again.
- **Signature mismatch?** `INSTALL_FAILED_UPDATE_INCOMPATIBLE` means your build is signed with a different key from the installed one, for example a local debug build over an official one. Uninstall the app on your clone first: `adb -s "$SERIAL" uninstall <package>`. This wipes that app's data on the clone only.

## Make a golden

Create a phone emulator in Android Studio or with `avdmanager`, then:

```sh
avdslim boot MyGolden
avdslim install MyGolden app.apk
avdslim golden MyGolden      # seal it: saves the apps and stops it
```

**Refresh it later**

```sh
avdslim boot MyGolden --golden --cold
avdslim install MyGolden new.apk --golden
avdslim shutdown MyGolden    # re-seals
```

Existing clones keep what they had.

## Slim a golden

Smaller golden, lighter clones: 2 GB guest RAM and fewer background apps.

```sh
avdslim slim MyGolden --ram 2048 --golden   # stopped golden; below 2560 MB it boots with -lowram
avdslim boot MyGolden --golden --cold
avdslim slim MyGolden --golden              # disable unused packages (running golden)
avdslim shutdown MyGolden                   # seal; clones inherit it
```

- Categories: `apps assistant telephony wallpaper telemetry radios` (default), `gms` (opt-in; may break apps that need Play services).
- `--except cat,...` skips some. `--with gms` adds gms. `--off` re-enables.
- `avdslim status` shows `slim:` and the RAM.
- Measured on API 34 (two samples each): about 0.8 GB less memory per emulator, snapshot 0.5 GB smaller.

## Safety

- Running emulators can't be cloned or deleted.
- The golden can't be booted, changed, slimmed or deleted without `--golden`.
- `delete` only removes clones that avdslim made.

## Reference

| | |
| --- | --- |
| Help | `avdslim --help` |
| JSON output | `--json` on `list`, `status`, `clone`, `boot`, `shutdown`, `delete` |
| Exit codes | `0` ok · `1` failed · `2` usage · `3` refused for safety |
| Environment | `ANDROID_SDK_ROOT`, `ANDROID_AVD_HOME`, `AVDSLIM_STATE` (logs and locks) |
| Tests | `make check` |
