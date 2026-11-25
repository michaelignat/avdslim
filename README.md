# avdslim

Give each task its own Android emulator. Keep one "golden" AVD with your apps
installed, clone it copy-on-write per task, boot the clone from the golden's
snapshot in seconds, run several side by side, delete them when done. The Android
counterpart of [simslim](https://github.com/mobai-app/simslim).

One bash script (3.2 compatible), no dependencies beyond the Android SDK tools and
macOS builtins. Apple Silicon, APFS.

## Install

```sh
make install                 # symlinks ./avdslim into ~/.local/bin (PREFIX=... to change)
```

It finds the SDK through `ANDROID_SDK_ROOT` / `ANDROID_HOME` (default
`~/Library/Android/sdk`) and AVDs through `ANDROID_AVD_HOME` (default `~/.android/avd`).

## Per task

```sh
avdslim clone Ailo_Golden_API34 SUBS-421-renter    # 0.1-0.4s, a few MB
SERIAL=$(avdslim boot SUBS-421-renter)             # 2-7s, prints emulator-5554
adb -s "$SERIAL" install -r new-build.apk          # or: avdslim install SUBS-421-renter new-build.apk
avdslim delete SUBS-421-renter --stop
```

Name clones `<TASK-ID>-<role>`. `avdslim --help` is the full reference.

| Command | What it does |
| --- | --- |
| `clone <golden> <name>` | copy-on-write clone of a stopped AVD; prints the final name |
| `boot <name> [--window] [--cold] [--timeout S] [--no-animations]` | boot detached, wait for Android, print the serial, verify the result |
| `serial <name>` | serial of a running AVD (exit 1 if stopped) |
| `install <name> <apk>...` | `adb install -r`; several apks are one split-APK app |
| `shutdown <name>` | flush the guest's disk, then stop the emulator |
| `delete <name>... [--stop] [--force]` | delete clones |
| `list [--booted]`, `status <name>` | name, state, serial, kind (`golden`/`clone`/`avd`), details |
| `golden <name> [--off]` | seal a running AVD as golden, or remove the mark |

`--json` works on list, status, clone, boot, shutdown and delete. Results go to
stdout, progress and warnings to stderr. Exit codes: 0 ok, 1 failure, 2 usage,
3 refused by a safety rule.

## What boot guarantees

- **First boot of a clone** restores the golden's snapshot: Android is up in
  seconds, exactly as the golden was sealed.
- **Later boots of the same clone are cold boots** (20-45s). Restoring a snapshot
  also rolls the disk back to the snapshot, so a second warm boot would silently
  discard everything the clone installed. `shutdown` flushes the guest's disk
  first, so the cold boot sees all of it.
- **`--window` and headless share one snapshot.** The emulator refuses a snapshot
  saved with a different renderer, and its default renderer is software when
  headless and the host GPU with a window. `boot` always passes `-gpu host`.
- **The outcome is checked.** `boot` reports `snapshot loaded`, `cold` or
  `failed` (a snapshot existed, the emulator rejected it and cold booted; the
  emulator's reason is printed as a warning). It then compares the installed
  third-party apps with the list recorded when the golden was sealed and exits 1
  if any are missing.

## Creating and refreshing a golden

```sh
# create (once)
avdmanager create avd -n Ailo_Golden_API34 -k 'system-images;android-34;google_apis;arm64-v8a' -d pixel_8
avdslim boot Ailo_Golden_API34                 # first boot is cold, about a minute
avdslim install Ailo_Golden_API34 app.apk
avdslim golden Ailo_Golden_API34               # seal: flush disk, save snapshot, record apps, stop

# refresh (new build of the app, new sign-in state, ...)
avdslim boot Ailo_Golden_API34 --golden        # add --cold after an emulator upgrade or a snapshot warning
avdslim install Ailo_Golden_API34 new.apk --golden
avdslim shutdown Ailo_Golden_API34             # shutting a golden down always seals it
```

Sealing matters. The emulator is stopped with `adb emu kill`, which does not shut
Android down, so whatever Android still holds in its page cache never reaches the
disk image. A snapshot hides that, because the cache is part of the saved RAM, until
the first cold boot: an app installed just before the kill is then simply gone.
Sealing runs `sync` in the guest, saves the snapshot explicitly and records
`pm list packages -3` in the golden so every clone's boot can be checked against it.

Clones made before a refresh keep the state they were cloned with.

## How cloning works

`clone` runs `cp -c -R` (APFS `clonefile`) into a temporary directory, then:

- deletes per-instance state: `*.lock`, `hardware-qemu.ini`, `emulator-user.ini`
  (window position, UUID, Bluetooth address), `bootcompleted.ini`, launch-param files;
- rewrites the identity in `config.ini` and writes `<name>.ini`;
- re-points `snapshots/*/hardware.ini` at the clone, because the emulator only
  restores a snapshot whose recorded AVD name and image paths match;
- rebases any qcow2 overlay whose backing file is an absolute path into the source
  (current emulators use relative names, so this is normally a no-op);
- writes `avdslim.managed` (source, creation time, the golden's app list) and moves
  the clone into place.

Clones boot with `-no-snapshot-save`, so they never write the 2.5 GB RAM image a
snapshot needs. Console ports are the first free even port in 5554-5682; `boot`
holds a lock on the port and on the AVD name until Android is up, so parallel boots
never collide and one AVD is never started twice.

## Limits

- Only stopped AVDs can be cloned, and a clone cannot be cloned (its disk no longer
  matches the snapshot it carries). Clone the golden.
- Copy-on-write needs APFS. Elsewhere `clone` warns and falls back to a full copy.
- A clone's disk grows by what it writes. `status` reports allocated size including
  blocks still shared with the golden, so it overstates the real cost.
- Snapshots are tied to the emulator version. After upgrading the emulator, refresh
  the golden with `boot --golden --cold`.
- A golden whose snapshot was saved without `-gpu host` (avdslim 0.1) still boots
  headless from its snapshot, but `--window` cannot restore it; `boot` warns.
  Refresh it with `boot --golden --cold`.
- An AVD avdslim did not create (`avd` in `list`) is booted the way the stock
  emulator would: it loads and saves its own snapshot.

## Safety rules

- A running AVD is never cloned or deleted, except `delete --stop` on a clone.
- A golden AVD needs `--golden` to be booted, installed onto or deleted.
- `delete` only removes clones unless `--force` is given, never a running AVD that
  avdslim did not create, and only a real directory named `<name>.avd` directly
  inside the AVD home.
- AVD names are limited to `[A-Za-z0-9._-]`; spaces become `-`, other characters `_`.

## Measured

M4 Max, APFS, emulator 37.2.12, API 34 google_apis arm64, 2 GB RAM, 3.5 GB golden
with one 260 MB debug app.

| Operation | Result |
| --- | --- |
| Clone | 0.1-0.4 s, about 5 MB each (`df` before/after three clones) |
| First boot of a clone (snapshot) | 2.0-6.7 s alone, 8-9 s for three booted at once; same with `--window` |
| Cold boot of a clone | 20-45 s |
| First boot of a new AVD | 58 s |
| Shutdown | 0.7-2.4 s for a clone, 4.6-13 s for a golden (it saves its snapshot) |

## Development

```sh
make check    # shellcheck + test/test.sh (offline: fake AVD home, fake emulator and adb)
```
