#!/bin/bash
# shellcheck disable=SC2015  # `A && ok || bad` is the intended idiom here
# Offline checks for avdslim: no emulator, no adb. Uses a throwaway AVD home.
# Run: test/test.sh   (needs only bash and macOS tools)
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd -P)"
AVDSLIM="$HERE/avdslim"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/avdslim-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT
export ANDROID_AVD_HOME="$TMP/avd" AVDSLIM_STATE="$TMP/state" ANDROID_SDK_ROOT="$TMP/sdk"
mkdir -p "$ANDROID_AVD_HOME" "$TMP/sdk"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }
check() { # description, expected-exit, command...
  local desc="$1" want="$2" out rc
  shift 2
  out="$("$@" 2>&1)"; rc=$?
  LAST="$out"
  if [ "$rc" = "$want" ]; then ok "$desc"; else bad "$desc (exit $rc, wanted $want): $out"; fi
}
contains() { case "$LAST" in *"$1"*) ok "output has '$1'" ;; *) bad "output lacks '$1': $LAST" ;; esac; }

# A fake AVD: config, a qcow2-looking overlay, a snapshot, and per-instance junk.
make_avd() { # name
  local d="$ANDROID_AVD_HOME/$1.avd"
  mkdir -p "$d/snapshots/default_boot"
  printf 'avd.id=<build>\navd.name=<build>\nhw.device.name=pixel_8\nhw.ramSize=2G\n' > "$d/config.ini"
  printf 'avd.ini.encoding=UTF-8\npath=%s\npath.rel=avd/%s.avd\ntarget=android-34\n' "$d" "$1" > "$ANDROID_AVD_HOME/$1.ini"
  printf 'avd.name = %s\ndisk.dataPartition.path = %s/userdata.img\n' "$1" "$d" > "$d/snapshots/default_boot/hardware.ini"
  echo data > "$d/userdata.img"
  : > "$d/multiinstance.lock"; : > "$d/hardware-qemu.ini"; echo uuid=1 > "$d/emulator-user.ini"
}

make_avd Base
make_avd Hand_Made

check "list shows AVDs" 0 "$AVDSLIM" list; contains "Base"
check "list --json is a JSON array" 0 "$AVDSLIM" list --json
case "$LAST" in '['*']') ok "json brackets" ;; *) bad "json brackets: $LAST" ;; esac

# --- clone
check "clone sanitizes spaces" 0 "$AVDSLIM" clone Base "SUBS 421 renter"; contains "SUBS-421-renter"
[ -d "$ANDROID_AVD_HOME/SUBS-421-renter.avd" ] && ok "clone dir exists" || bad "clone dir exists"
[ ! -e "$ANDROID_AVD_HOME/SUBS-421-renter.avd/multiinstance.lock" ] && ok "lock dropped" || bad "lock dropped"
[ ! -e "$ANDROID_AVD_HOME/SUBS-421-renter.avd/hardware-qemu.ini" ] && ok "hardware-qemu.ini dropped" || bad "hardware-qemu.ini dropped"
[ ! -e "$ANDROID_AVD_HOME/SUBS-421-renter.avd/emulator-user.ini" ] && ok "emulator-user.ini dropped" || bad "emulator-user.ini dropped"
[ -f "$ANDROID_AVD_HOME/SUBS-421-renter.avd/avdslim.managed" ] && ok "managed marker" || bad "managed marker"
grep -q '^avd.name=SUBS-421-renter$' "$ANDROID_AVD_HOME/SUBS-421-renter.avd/config.ini" && ok "identity rewritten" || bad "identity rewritten"
grep -q "SUBS-421-renter.avd/userdata.img" "$ANDROID_AVD_HOME/SUBS-421-renter.avd/snapshots/default_boot/hardware.ini" && ok "snapshot repointed" || bad "snapshot repointed"
grep -q "^path=$ANDROID_AVD_HOME/SUBS-421-renter.avd\$" "$ANDROID_AVD_HOME/SUBS-421-renter.ini" && ok "ini path" || bad "ini path"
check "clone onto existing name fails" 1 "$AVDSLIM" clone Base SUBS-421-renter
check "clone of missing source fails" 1 "$AVDSLIM" clone Nope x
check "clone rejects unusable name" 2 "$AVDSLIM" clone Base "--"
check "clone dry-run changes nothing" 0 "$AVDSLIM" clone Base dry --dry-run
[ ! -e "$ANDROID_AVD_HOME/dry.avd" ] && ok "dry-run created nothing" || bad "dry-run created nothing"

# --- golden
check "mark golden" 0 "$AVDSLIM" golden Base
check "golden cannot be deleted" 3 "$AVDSLIM" delete Base
check "golden cannot be booted" 3 "$AVDSLIM" boot Base
check "golden cannot be slimmed" 3 "$AVDSLIM" slim Base
check "golden cannot be renamed" 3 "$AVDSLIM" rename Base Other
check "clone of golden is not golden" 0 "$AVDSLIM" status SUBS-421-renter; contains "kind:     clone"
check "golden listed as golden" 0 "$AVDSLIM" list; contains "golden"
check "slim golden with --golden" 0 "$AVDSLIM" slim Base --golden --ram 3072 --cores 2
grep -q '^hw.ramSize=3072M$' "$ANDROID_AVD_HOME/Base.avd/config.ini" && ok "ram set" || bad "ram set"
grep -q '^showDeviceFrame=no$' "$ANDROID_AVD_HOME/Base.avd/config.ini" && ok "frame off" || bad "frame off"

# --- delete safety
check "unmanaged AVD needs --force" 3 "$AVDSLIM" delete Hand_Made
[ -d "$ANDROID_AVD_HOME/Hand_Made.avd" ] && ok "hand-made AVD untouched" || bad "hand-made AVD untouched"
check "delete rejects path-like name" 2 "$AVDSLIM" delete ../avd/Base
check "delete clone" 0 "$AVDSLIM" delete SUBS-421-renter
[ ! -e "$ANDROID_AVD_HOME/SUBS-421-renter.avd" ] && [ ! -e "$ANDROID_AVD_HOME/SUBS-421-renter.ini" ] && ok "clone gone" || bad "clone gone"

# An ini that points outside the AVD home must not be deleted.
mkdir -p "$TMP/elsewhere.avd"; echo x > "$TMP/elsewhere.avd/config.ini"
printf 'path=%s/elsewhere.avd\ntarget=android-34\n' "$TMP" > "$ANDROID_AVD_HOME/Outside.ini"
check "ini pointing outside home is refused" 3 "$AVDSLIM" delete Outside --force
[ -d "$TMP/elsewhere.avd" ] && ok "outside dir untouched" || bad "outside dir untouched"

# --- a running AVD that avdslim did not create is untouchable, even with --force
make_avd Running_One
printf '#!/bin/bash\nsleep 120\n' > "$TMP/qemu-system-fake"; chmod +x "$TMP/qemu-system-fake"
"$TMP/qemu-system-fake" -avd Running_One -port 5700 >/dev/null 2>&1 &
FAKE_PID=$!
sleep 0.5
check "list sees the running AVD" 0 "$AVDSLIM" list; contains "emulator-5700"
check "serial of running AVD" 0 "$AVDSLIM" serial Running_One; contains "emulator-5700"
check "clone of running AVD is refused" 3 "$AVDSLIM" clone Running_One copy
check "delete running unmanaged refused" 3 "$AVDSLIM" delete Running_One
check "delete --force running unmanaged refused" 3 "$AVDSLIM" delete Running_One --force
check "delete --force --stop running unmanaged refused" 3 "$AVDSLIM" delete Running_One --force --stop
check "rename running refused" 3 "$AVDSLIM" rename Running_One Other
check "slim running refused" 3 "$AVDSLIM" slim Running_One
[ -d "$ANDROID_AVD_HOME/Running_One.avd" ] && ok "running AVD still on disk" || bad "running AVD still on disk"
pkill -P "$FAKE_PID" 2>/dev/null; kill "$FAKE_PID" 2>/dev/null

# --- misc
check "golden --off" 0 "$AVDSLIM" golden Base --off
check "delete golden-less managed requires managed" 3 "$AVDSLIM" delete Base
check "unknown command" 2 "$AVDSLIM" frobnicate
check "help is complete" 0 "$AVDSLIM" --help; contains "SAFETY RULES"
check "version" 0 "$AVDSLIM" version

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
