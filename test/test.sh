#!/bin/bash
# shellcheck disable=SC2015,SC2016  # `A && ok || bad` and eval'd single-quoted checks are intended
# Offline checks for avdslim. Everything runs against a throwaway AVD home with a fake
# `emulator` and `adb`, so no real emulator or AVD is ever touched.
# Run: test/test.sh   (needs only bash, python3 and macOS tools)
set -u

HERE="$(cd "$(dirname "$0")/.." && pwd -P)"
AVDSLIM="$HERE/avdslim"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/avdslim-test.XXXXXX")" || exit 1
TMP="$(cd "$TMP" && pwd -P)"
export ANDROID_AVD_HOME="$TMP/avd" AVDSLIM_STATE="$TMP/state" ANDROID_SDK_ROOT="$TMP/sdk" FAKE="$TMP/fake"
mkdir -p "$ANDROID_AVD_HOME" "$TMP/sdk/emulator" "$TMP/sdk/platform-tools" "$FAKE"
mkdir "$TMP/bin"
cat > "$TMP/bin/ps" <<'EOF'
#!/bin/bash
/bin/ps "$@" | awk -v exe="$ANDROID_SDK_ROOT/emulator/emulator" 'index($0," " exe " -avd ") { $2="emulator"; print }'
EOF
printf '#!/bin/sh\nexit 1\n' > "$TMP/bin/lsof"
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
cleanup() {
  local f
  for f in "$FAKE"/pid-*; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done
  rm -rf "$TMP"
}
trap cleanup EXIT

# Fake emulator: records its arguments, pretends to load the snapshot, stays alive.
cat > "$TMP/sdk/emulator/emulator" <<'EOF'
#!/bin/bash
name=""; port=""; load=1; args="$*"
while [ $# -gt 0 ]; do
  case "$1" in -avd) name="$2" ;; -port) port="$2" ;; -no-snapshot-load) load=0 ;; esac
  shift
done
echo "$args" > "$FAKE/args-$name"
echo "$name" > "$FAKE/name-$port"
: > "$ANDROID_AVD_HOME/$name.avd/hardware-qemu.ini"
if [ "$load" = 1 ]; then
  if [ -f "$FAKE/snapshot-broken" ]; then
    echo "USER_INFO    | The emulator is starting from scratch. Reason: different renderer configured"
  else
    echo "INFO         | Successfully loaded snapshot 'default_boot' using 1 ms"
  fi
fi
echo $$ > "$FAKE/pid-$port"
sleep 300 &
trap 'kill $!; exit 0' TERM
wait
EOF
# Fake adb: answers only for serials whose fake emulator is alive.
cat > "$TMP/sdk/platform-tools/adb" <<'EOF'
#!/bin/bash
[ "${1:-}" = -s ] || exit 0 # start-server, devices
port="${2#emulator-}"; shift 2
if [ "$1" = wait-for-device ]; then
  until [ -s "$FAKE/pid-$port" ]; do sleep 0.02; done
  [ ! -e "$FAKE/not-ready" ] || exec sleep 10
fi
kill -0 "$(cat "$FAKE/pid-$port" 2>/dev/null)" 2>/dev/null || { echo "adb: device not found" >&2; exit 1; }
name="$(cat "$FAKE/name-$port")"
echo "$name: $*" >> "$FAKE/adb.log"
case "$*" in
  "emu avd name") echo "${FAKE_REPORTED_NAME:-$name}" ;;
  "shell getprop sys.boot_completed") echo 1 ;;
  *"pm list packages -3") cat "$FAKE/packages" 2>/dev/null ;;
  "emu avd snapshot save default_boot")
    mkdir -p "$ANDROID_AVD_HOME/$name.avd/snapshots/default_boot"
    echo saved > "$ANDROID_AVD_HOME/$name.avd/snapshots/default_boot/snapshot.pb"
    printf 'hw.gpu.mode = host\navd.name = %s\n' "$name" > "$ANDROID_AVD_HOME/$name.avd/snapshots/default_boot/hardware.ini"
    echo OK ;;
  "emu kill") kill "$(cat "$FAKE/pid-$port")"; rm -f "$FAKE/pid-$port" ;;
  install*) echo Success ;;
esac
EOF
chmod +x "$TMP/sdk/emulator/emulator" "$TMP/sdk/platform-tools/adb"

pass=0; fail=0
ok() { pass=$((pass + 1)); echo "ok   $1"; }
bad() { fail=$((fail + 1)); echo "FAIL $1"; }
check() { # description, expected-exit, command...   (LAST = stdout+stderr, OUT = stdout only)
  local desc="$1" want="$2" rc
  shift 2
  OUT="$("$@" 2>"$TMP/stderr")"; rc=$?
  LAST="$OUT$(cat "$TMP/stderr")"
  if [ "$rc" = "$want" ]; then ok "$desc"; else bad "$desc (exit $rc, wanted $want): $LAST"; fi
}
contains() { case "$LAST" in *"$1"*) ok "output has '$1'" ;; *) bad "output lacks '$1': $LAST" ;; esac; }
is_json() { printf '%s' "$OUT" | python3 -I -m json.tool >/dev/null 2>&1 && ok "$1 is valid JSON" || bad "$1 is valid JSON: $OUT"; }
t() { local d="$1"; shift; if "$@"; then ok "$d"; else bad "$d"; fi; }
args_of() { cat "$FAKE/args-$1"; }
has_arg() { case " $(args_of "$1") " in *" $2 "*) return 0 ;; esac; return 1; }

# A fake AVD the way avdmanager leaves it, plus per-instance junk from an earlier run.
make_avd() { # name
  local d="$ANDROID_AVD_HOME/$1.avd"
  mkdir -p "$d"
  printf 'avd.id=<build>\navd.name=<build>\nhw.device.name=pixel_8\nhw.ramSize=2G\n' > "$d/config.ini"
  printf 'avd.ini.encoding=UTF-8\npath=%s\npath.rel=avd/%s.avd\ntarget=android-34\n' "$d" "$1" > "$ANDROID_AVD_HOME/$1.ini"
  echo data > "$d/userdata.img"
  : > "$d/multiinstance.lock"; : > "$d/hardware-qemu.ini"; echo uuid=1 > "$d/emulator-user.ini"
}
add_snapshot() { # name gpu-mode
  local d="$ANDROID_AVD_HOME/$1.avd"
  mkdir -p "$d/snapshots/default_boot"
  echo old > "$d/snapshots/default_boot/snapshot.pb"
  printf 'hw.gpu.mode = %s\navd.name = %s\ndisk.dataPartition.path = %s/userdata.img\n' "$2" "$1" "$d" > "$d/snapshots/default_boot/hardware.ini"
}
C="$ANDROID_AVD_HOME/SUBS-421-renter.avd"

make_avd Base
make_avd Hand_Made
check "list shows AVDs" 0 "$AVDSLIM" list; contains "Base"
check "list --json" 0 "$AVDSLIM" list --json; is_json "list"
check "status --json" 0 "$AVDSLIM" status Base --json; is_json "status"
printf '%s\n' $'target=bad|\t"quoted"\\' > "$ANDROID_AVD_HOME/Odd.ini"
mkdir "$ANDROID_AVD_HOME/Odd.avd"; touch "$ANDROID_AVD_HOME/Odd.avd/config.ini"
check "list preserves unusual field values" 0 "$AVDSLIM" list --json; is_json "list controls"; contains 'bad|\t\"quoted\"'
check "shutdown already stopped" 0 "$AVDSLIM" shutdown Base --json; is_json "stopped shutdown"

# --- creating a golden: boot the fresh AVD, install, seal it while running
check "boot a fresh AVD" 0 "$AVDSLIM" boot Base --json; is_json "boot"; contains '"snapshot":"cold"'
t "fresh AVD boots with the host GPU" has_arg Base "-gpu host"
t "an unmanaged AVD keeps save-on-exit" eval '! has_arg Base -no-snapshot-save'
check "boot again is idempotent" 0 "$AVDSLIM" boot Base; [ "$OUT" = emulator-5554 ] && ok "prints only the serial" || bad "prints only the serial: $OUT"
check "install" 0 "$AVDSLIM" install Base "$0"; contains Success
check "serial now belongs to a different AVD" 1 env FAKE_REPORTED_NAME=Elsewhere "$AVDSLIM" shutdown Base
check "seal cannot silently record an empty manifest after adb fails" 1 "$AVDSLIM" golden Base
echo "package:app.ailo" > "$FAKE/packages"
check "seal a running AVD as golden" 0 "$AVDSLIM" golden Base; contains "sealed Base as golden with apps: app.ailo"
t "seal flushed the disk before saving the snapshot" eval 'grep -A1 "^Base: shell .*sync && pm" "$FAKE/adb.log" | grep -q "snapshot save"'
t "seal saved a snapshot" grep -q saved "$ANDROID_AVD_HOME/Base.avd/snapshots/default_boot/snapshot.pb"
t "seal recorded the apps" grep -q '^packages=app.ailo$' "$ANDROID_AVD_HOME/Base.avd/avdslim.golden"
check "golden is stopped after sealing" 1 "$AVDSLIM" serial Base

# --- golden protection
check "golden cannot be booted" 3 "$AVDSLIM" boot Base
check "golden cannot be installed onto" 3 "$AVDSLIM" install Base "$0"
check "golden cannot be deleted" 3 "$AVDSLIM" delete Base
check "golden cannot be deleted with --force" 3 "$AVDSLIM" delete Base --force
check "golden listed as golden" 0 "$AVDSLIM" list; contains "golden"

# --- clone
check "clone sanitizes spaces" 0 "$AVDSLIM" clone Base "SUBS 421 renter" --json; is_json "clone"; contains "SUBS-421-renter"
t "clone dir exists" test -d "$C"
t "lock dropped" test ! -e "$C/multiinstance.lock"
t "hardware-qemu.ini dropped" test ! -e "$C/hardware-qemu.ini"
t "emulator-user.ini dropped" test ! -e "$C/emulator-user.ini"
t "clone is not golden" test ! -e "$C/avdslim.golden"
t "clone inherits the golden's app list" grep -q '^packages=app.ailo$' "$C/avdslim.managed"
t "identity rewritten" grep -q '^avd.name=SUBS-421-renter$' "$C/config.ini"
t "snapshot repointed" grep -q '^avd.name = SUBS-421-renter$' "$C/snapshots/default_boot/hardware.ini"
t "ini path" grep -q "^path=$C\$" "$ANDROID_AVD_HOME/SUBS-421-renter.ini"
t "ini path.rel" grep -q '^path.rel=avd/SUBS-421-renter.avd$' "$ANDROID_AVD_HOME/SUBS-421-renter.ini"
t "no temporary files left" eval '[ -z "$(ls -A "$ANDROID_AVD_HOME" | grep avdslim-tmp)" ]'
check "status of a clone" 0 "$AVDSLIM" status SUBS-421-renter; contains "kind:     clone"
check "clone onto existing name fails" 1 "$AVDSLIM" clone Base SUBS-421-renter
check "clone of missing source fails" 1 "$AVDSLIM" clone Nope x
check "clone rejects unusable name" 2 "$AVDSLIM" clone Base "--"
check "clone of a clone is refused" 3 "$AVDSLIM" clone SUBS-421-renter again
make_avd Spaced
sed -i '' 's/^path=/path = /' "$ANDROID_AVD_HOME/Spaced.ini"
check "clone source with spaced ini assignment" 0 "$AVDSLIM" clone Spaced spaced-clone
check "spaced assignment is replaced, not shadowing the clone path" 0 "$AVDSLIM" delete spaced-clone
t "spaced source remains intact" test -f "$ANDROID_AVD_HOME/Spaced.avd/config.ini"
check "stopped clone cannot be marked golden" 3 "$AVDSLIM" golden SUBS-421-renter

# --- boot: snapshot on first boot, cold afterwards, same flags with and without a window
check "first boot of a clone" 0 "$AVDSLIM" boot SUBS-421-renter --json; contains '"snapshot":"loaded"'
t "clone never saves a snapshot" has_arg SUBS-421-renter -no-snapshot-save
t "clone boots headless with the host GPU" eval 'has_arg SUBS-421-renter "-gpu host" && has_arg SUBS-421-renter -no-window'
t "first boot loads the snapshot" eval '! has_arg SUBS-421-renter -no-snapshot-load'
check "serial" 0 "$AVDSLIM" serial SUBS-421-renter; [ "$OUT" = emulator-5554 ] && ok "serial value" || bad "serial value: $OUT"
check "running clone cannot be deleted without --stop" 3 "$AVDSLIM" delete SUBS-421-renter
check "shutdown" 0 "$AVDSLIM" shutdown SUBS-421-renter --json; is_json "shutdown"
t "shutdown flushed the guest disk" grep -q "^SUBS-421-renter: shell sync" "$FAKE/adb.log"
t "shutdown of a clone saved no snapshot" eval '! grep -q "^SUBS-421-renter: emu avd snapshot" "$FAKE/adb.log"'
check "second boot of a clone" 0 "$AVDSLIM" boot SUBS-421-renter --window --json; contains '"snapshot":"cold"'
t "second boot keeps the clone's data (no snapshot load)" has_arg SUBS-421-renter -no-snapshot-load
t "window boot uses the same GPU and no -no-window" eval 'has_arg SUBS-421-renter "-gpu host" && ! has_arg SUBS-421-renter -no-window'
check "delete --stop" 0 "$AVDSLIM" delete SUBS-421-renter --stop --json; is_json "delete"
t "clone gone" eval '[ ! -e "$C" ] && [ ! -e "$ANDROID_AVD_HOME/SUBS-421-renter.ini" ]'

# --- boot verification
"$AVDSLIM" clone Base v1 >/dev/null; : > "$FAKE/snapshot-broken"
check "rejected snapshot is reported" 0 "$AVDSLIM" boot v1 --json; contains '"snapshot":"failed"'; contains "different renderer configured"
rm "$FAKE/snapshot-broken"; "$AVDSLIM" delete v1 --stop >/dev/null 2>&1
"$AVDSLIM" clone Base v2 >/dev/null; : > "$FAKE/packages"
check "missing golden apps fail the boot" 1 "$AVDSLIM" boot v2; contains "missing apps its golden had: app.ailo"
t "failed verification withholds serial" test -z "$OUT"
check "retry still rejects missing apps" 1 "$AVDSLIM" boot v2
touch "$FAKE/not-ready"
check "timeout on already running but not ready" 1 "$AVDSLIM" boot v2 --timeout 1
rm "$FAKE/not-ready"
echo "package:app.ailo" > "$FAKE/packages"; "$AVDSLIM" delete v2 --stop >/dev/null 2>&1
check "cold boot on request" 0 "$AVDSLIM" clone Base v3; "$AVDSLIM" boot v3 --cold >/dev/null 2>&1
t "--cold skips the snapshot" has_arg v3 -no-snapshot-load
"$AVDSLIM" delete v3 --stop >/dev/null 2>&1

# --- a snapshot saved without the host GPU only loads with the emulator's default renderer
make_avd Legacy; add_snapshot Legacy lavapipe; "$AVDSLIM" golden Legacy >/dev/null
"$AVDSLIM" clone Legacy l1 >/dev/null
check "legacy snapshot boots headless" 0 "$AVDSLIM" boot l1
t "legacy snapshot gets no -gpu flag" eval '! has_arg l1 -gpu'
"$AVDSLIM" delete l1 --stop >/dev/null 2>&1; "$AVDSLIM" clone Legacy l2 >/dev/null
check "legacy snapshot with --window warns" 0 "$AVDSLIM" boot l2 --window; contains "re-seal the golden"
"$AVDSLIM" delete l2 --stop >/dev/null 2>&1
check "cold golden boot switches to the host GPU" 0 "$AVDSLIM" boot Legacy --golden --cold
t "cold golden boot uses -gpu host" eval 'has_arg Legacy "-gpu host" && has_arg Legacy -no-snapshot-save'
check "shutdown seals a golden" 0 "$AVDSLIM" shutdown Legacy; contains "sealed Legacy"
t "re-sealed snapshot records the host GPU" grep -q 'hw.gpu.mode = host' "$ANDROID_AVD_HOME/Legacy.avd/snapshots/default_boot/hardware.ini"

# --- parallel boots get distinct ports; one AVD cannot be booted twice at once
"$AVDSLIM" clone Base p1 >/dev/null; "$AVDSLIM" clone Base p2 >/dev/null; "$AVDSLIM" clone Base p3 >/dev/null
"$AVDSLIM" boot p1 > "$TMP/p1" 2>/dev/null & "$AVDSLIM" boot p2 > "$TMP/p2" 2>/dev/null & "$AVDSLIM" boot p3 > "$TMP/p3" 2>/dev/null &
wait
ports="$(cat "$TMP/p1" "$TMP/p2" "$TMP/p3" | sort -u | tr '\n' ' ')"
[ "$ports" = "emulator-5554 emulator-5556 emulator-5558 " ] && ok "three parallel boots, three ports" || bad "three parallel boots, three ports: $ports"
check "batch delete" 0 "$AVDSLIM" delete p1 p2 p3 --stop --json; is_json "batch delete"
"$AVDSLIM" clone Base p4 >/dev/null
check "released port can be reused" 0 "$AVDSLIM" boot p4; [ "$OUT" = emulator-5554 ] && ok "first free port reused" || bad "first free port reused: $OUT"
"$AVDSLIM" shutdown p4 >/dev/null 2>&1
mkfifo "$TMP/ready"
perl -MFcntl=:flock -e 'open my $f, ">>", $ARGV[0] or die; flock($f,LOCK_EX) or die; print "ready\n"; close STDOUT; sleep 60' \
  "$AVDSLIM_STATE/locks/avd-p4" > "$TMP/ready" & locker=$!
read -r _ < "$TMP/ready" || exit 1
check "boot under lock refused" 1 "$AVDSLIM" boot p4; contains "busy"
check "delete under lock refused" 1 "$AVDSLIM" delete p4
kill -9 "$locker"; wait "$locker" 2>/dev/null
check "owner crash releases lock" 0 "$AVDSLIM" delete p4

# --- delete safety
check "unmanaged AVD needs --force" 3 "$AVDSLIM" delete Hand_Made
t "hand-made AVD untouched" test -d "$ANDROID_AVD_HOME/Hand_Made.avd"
check "delete rejects path-like name" 2 "$AVDSLIM" delete ../avd/Base
# An ini that points outside the AVD home must not be deleted.
mkdir -p "$TMP/elsewhere.avd"; echo x > "$TMP/elsewhere.avd/config.ini"
printf 'path=%s/elsewhere.avd\ntarget=android-34\n' "$TMP" > "$ANDROID_AVD_HOME/Outside.ini"
check "ini pointing outside home is refused" 3 "$AVDSLIM" delete Outside --force
t "outside dir untouched" test -d "$TMP/elsewhere.avd"
# A symlinked AVD directory must not be followed.
mkdir -p "$TMP/target.avd"; echo x > "$TMP/target.avd/config.ini"; ln -s "$TMP/target.avd" "$ANDROID_AVD_HOME/Linked.avd"
printf 'path=%s/Linked.avd\n' "$ANDROID_AVD_HOME" > "$ANDROID_AVD_HOME/Linked.ini"
check "symlinked AVD dir is refused" 3 "$AVDSLIM" delete Linked --force
t "symlink target untouched" test -f "$TMP/target.avd/config.ini"
make_avd Indirect
printf 'path=%s/Base.avd/../Indirect.avd\n' "$ANDROID_AVD_HOME" > "$ANDROID_AVD_HOME/Indirect.ini"
check "delete rejects indirect path even when it resolves inside home" 3 "$AVDSLIM" delete Indirect --force
t "indirect dir untouched" test -f "$ANDROID_AVD_HOME/Indirect.avd/config.ini"

# --- a running AVD that avdslim did not create is untouchable, even with --force
check "boot the hand-made AVD" 0 "$AVDSLIM" boot Hand_Made
check "list --booted sees it" 0 "$AVDSLIM" list --booted; contains "Hand_Made  running  emulator-5554  avd"
check "clone of running AVD is refused" 3 "$AVDSLIM" clone Hand_Made copy
check "delete running unmanaged refused" 3 "$AVDSLIM" delete Hand_Made
check "delete --force running unmanaged refused" 3 "$AVDSLIM" delete Hand_Made --force
check "delete --force --stop running unmanaged refused" 3 "$AVDSLIM" delete Hand_Made --force --stop
check "an inherited process cache cannot bypass running protection" 3 env PS_SNAP='' "$AVDSLIM" delete Hand_Made --force
t "running AVD still on disk and alive" eval '[ -d "$ANDROID_AVD_HOME/Hand_Made.avd" ] && "$AVDSLIM" serial Hand_Made >/dev/null'
check "shutdown the hand-made AVD" 0 "$AVDSLIM" shutdown Hand_Made
check "delete --force of a stopped unmanaged AVD" 0 "$AVDSLIM" delete Hand_Made --force

# --- misc
check "golden --off" 0 "$AVDSLIM" golden Base --off
check "un-goldened AVD is unmanaged again" 3 "$AVDSLIM" delete Base
check "unknown command" 2 "$AVDSLIM" frobnicate
check "unknown option" 2 "$AVDSLIM" list --frobnicate
check "bad --timeout" 2 "$AVDSLIM" boot Base --timeout soon
check "octal timeout rejected" 2 "$AVDSLIM" boot Base --timeout 08
check "unknown command without AVD home" 2 env ANDROID_AVD_HOME="$TMP/absent" "$AVDSLIM" frobnicate
check "missing AVD home" 1 env ANDROID_AVD_HOME="$TMP/absent" "$AVDSLIM" list
check "missing adb" 1 env PATH=/bin:/usr/bin ANDROID_SDK_ROOT="$TMP/absent" "$AVDSLIM" boot Base; contains "adb not found"
check "multiline clone name normalized" 0 "$AVDSLIM" clone Base $'multi\nline'; contains "multi-line"
check "help" 0 "$AVDSLIM" --help; contains 'SERIAL=$(avdslim boot'
check "version" 0 "$AVDSLIM" version

echo
echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
