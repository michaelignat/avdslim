# avdslim

Clone, boot and delete Android emulators (AVDs) copy-on-write. The Android counterpart
of [simslim](https://github.com/mobai-app/simslim): keep one "golden" AVD with your
apps installed, clone it per task for almost no disk, run several clones in parallel,
delete them when done.

One bash script (3.2 compatible), no dependencies beyond the Android SDK tools and
macOS builtins. Apple Silicon, APFS.

## Install

```sh
make install                 # symlinks ./avdslim into ~/.local/bin (PREFIX=... to change)
# or: ln -s "$PWD/avdslim" ~/.local/bin/avdslim
```

It finds the SDK through `ANDROID_SDK_ROOT` / `ANDROID_HOME` (default
`~/Library/Android/sdk`) and AVDs through `ANDROID_AVD_HOME` (default `~/.android/avd`).

## Quick start

```sh
# once: create the golden AVD, install your apps, mark it golden
avdmanager create avd -n Ailo_Golden_API34 -k 'system-images;android-34;google_apis;arm64-v8a' -d pixel_8
avdslim golden Ailo_Golden_API34
avdslim slim Ailo_Golden_API34 --golden
avdslim boot Ailo_Golden_API34 --golden            # first boot is a cold boot (~90s)
avdslim install Ailo_Golden_API34 --golden app.apk # several apks = one split-APK app
avdslim shutdown Ailo_Golden_API34                 # saves the quickboot snapshot

# per task
avdslim clone Ailo_Golden_API34 SUBS-421-renter    # ~0.3s, ~10 MB
SERIAL=$(avdslim boot SUBS-421-renter)             # ~5-12s, prints emulator-5554
adb -s "$SERIAL" install -r new-build.apk
avdslim delete SUBS-421-renter --stop
```

## Commands

Run `avdslim --help` for the full reference. Summary:

| Command | What it does |
| --- | --- |
| `list [--booted] [--json]` | name, state, serial, kind (`golden`/`clone`/`avd`), target, device |
| `status <name> [--json]` | state, serial, pid, source, size, config |
| `clone <src> <name>` | copy-on-write clone of a stopped AVD; prints the sanitized name |
| `boot <name> [--window] [--cold] [--port N] [--timeout S] [--no-animations]` | boot detached, wait for `sys.boot_completed`, print the serial |
| `serial <name>` | serial of a running AVD (exit 1 if stopped) |
| `shutdown <name>` | `adb emu kill` and wait for exit |
| `delete <name>... [--stop] [--force]` | delete clones |
| `rename <old> <new>` | rename a stopped AVD |
| `install <name> <apk>...` | `adb install -r` onto the AVD's serial |
| `golden <name> [--off]` | mark or unmark a golden AVD |
| `slim <name> [--ram MB] [--cores N]` | audio off, no device frame, optional RAM/cores |

Global: `--json`, `-n/--dry-run`, `-h/--help`. Results go to stdout (`boot` prints
only the serial), progress and warnings to stderr. Exit codes: 0 ok, 1 failure,
2 usage, 3 refused by a safety rule.

## How cloning works

`clone` runs `cp -c -R` (APFS `clonefile`) on the AVD directory into a temporary
directory, then:

- deletes per-instance state: `*.lock`, `hardware-qemu.ini`, `emulator-user.ini`
  (window position, UUID, Bluetooth address), `bootcompleted.ini`, launch-param files;
- rewrites the identity in `config.ini` (`avd.id`, `avd.name`, `AvdId`,
  `avd.ini.displayname` where present) and writes `<name>.ini`;
- re-points `snapshots/*/hardware.ini` at the clone. The emulator only restores a
  quickboot snapshot when the recorded AVD name and image paths match, and
  otherwise falls back to a cold boot ("different AVD configuration");
- rebases any qcow2 overlay whose backing file is an absolute path into the source
  (current emulators use relative names, so this is normally a no-op);
- marks the clone `avdslim.managed`, then moves it into place.

Booting passes `-no-window -no-audio -no-boot-anim -no-metrics`, plus
`-no-snapshot-save` for everything except a golden AVD. A clone therefore restores the
golden's quickboot snapshot (apps installed, home screen) in seconds and never writes
a snapshot back. `--cold` forces a full boot. Console ports are the first free even
port in 5554-5584, claimed under a lock so parallel `boot` calls never collide.

### Limits

- Only stopped AVDs can be cloned; a live copy would be inconsistent.
- Copy-on-write needs APFS. Elsewhere `clone` warns and falls back to a full copy.
- A clone's blocks diverge from the golden as it runs (userdata is a qcow2 overlay,
  so the cost is just what the clone writes). `status` reports allocated size
  including blocks shared with the source, so it overstates the real cost.
- Quickboot snapshots restore the guest as it was when the golden was shut down.
  Refresh the golden (boot with `--golden`, change, `shutdown`) to update both
  disk and snapshot together. Use `--cold` if a task needs a fresh boot.
- Snapshots are tied to the emulator version and the config; after upgrading the
  emulator or running `slim --ram/--cores`, refresh the golden.
- `slim` is deliberately modest: it leaves camera, sensors, GPS and network alone,
  and does not turn animations off unless you pass `--no-animations` to `boot`.

## Safety rules

- A running AVD is never cloned, renamed, slimmed or deleted. `--force` does not change that.
- A golden AVD needs `--golden` to be booted, deleted, renamed, slimmed or installed onto.
- `delete` only removes AVDs created by `avdslim clone` unless `--force` is given,
  and only a real directory named `<name>.avd` directly inside the AVD home.
- AVD names are limited to `[A-Za-z0-9._-]`; spaces become `-`, other characters `_`.

## Measured (M-series Mac, APFS, API 34 google_apis arm64, 2 GB RAM, 3.5 GB golden)

| Operation | Result |
| --- | --- |
| Clone time | 0.2-0.3 s |
| Clone disk cost | about 9-12 MB (`df` before/after; the disk is noisy, so this is an upper estimate) |
| Boot from the golden snapshot | 11.8 s for the first, 4.4 s and 4.6 s for two booted in parallel |
| Cold boot of a clone | about 50 s (snapshot unavailable); first boot of the fresh golden was 92 s |
| Shutdown | 1.6 s for a clone, 4.9 s for the golden (it saves its snapshot) |

## Development

```sh
make check    # shellcheck + test/test.sh (offline: fake AVD home, no emulator needed)
```
