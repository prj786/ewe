#!/usr/bin/env bash
# shellcheck disable=SC2034  # $out is read inside check's eval strings
# system/tuning/apply.sh in a sandbox root — never the real /etc, nothing
# live (EWE_TUNING_NO_LIVE). Checks: zram gate, idempotency (second run
# silent), an edited file survives --remove, --remove cleans up its own,
# exit 0 everywhere, and the drop-ins parse as what they claim to be.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
SB="$(mktemp -d)"; trap 'rm -rf "$SB"' EXIT
export EWE_TUNING_ROOT="$SB/root" EWE_TUNING_NO_LIVE=1
A=system/tuning/apply.sh
pass=0; failn=0
check() { if eval "$2"; then pass=$((pass+1)); else failn=$((failn+1)); echo "FAIL: $1"; fi; }
R="$SB/root"

check "sh -n apply.sh" "sh -n $A"

# no zram → only the journal + plocate drop-ins
out="$(sh $A)"; rc=$?
check "exit 0 (no zram)" "[ $rc = 0 ]"
check "no zram: no sysctl file" "[ ! -e $R/etc/sysctl.d/70-ewe-memory.conf ]"
check "no zram: no tmpfiles file" "[ ! -e $R/etc/tmpfiles.d/70-ewe-memory.conf ]"
check "journald cap installed" "cmp -s system/tuning/70-ewe-journald.conf $R/etc/systemd/journald.conf.d/70-ewe.conf"
check "plocate drop-in installed" "cmp -s system/tuning/plocate-updatedb.timer.conf $R/etc/systemd/system/plocate-updatedb.timer.d/70-ewe.conf"
check "says what it changed" "printf '%s' \"\$out\" | grep -q 'journal is capped'"

# zram configured → the memory pair too; second run is silent
mkdir -p "$R/etc/systemd"; printf '[zram0]\n' > "$R/etc/systemd/zram-generator.conf"
out="$(sh $A)"
check "zram: sysctl installed" "cmp -s system/tuning/70-ewe-memory.sysctl.conf $R/etc/sysctl.d/70-ewe-memory.conf"
check "zram: tmpfiles installed" "cmp -s system/tuning/70-ewe-memory.tmpfiles.conf $R/etc/tmpfiles.d/70-ewe-memory.conf"
check "zram: only the new files reported" "[ \$(printf '%s\n' \"\$out\" | grep -c ':: ewe:') = 2 ]"
out="$(sh $A)"
check "second run changes nothing" "[ -z \"\$out\" ]"

# content sanity: what the kernel/systemd will read
check "swappiness 180" "grep -qx 'vm.swappiness = 180' system/tuning/70-ewe-memory.sysctl.conf"
check "page-cluster 0" "grep -qx 'vm.page-cluster = 0' system/tuning/70-ewe-memory.sysctl.conf"
check "zswap off line" "grep -qx 'w /sys/module/zswap/parameters/enabled - - - - N' system/tuning/70-ewe-memory.tmpfiles.conf"
check "thp madvise line" "grep -qx 'w /sys/kernel/mm/transparent_hugepage/enabled - - - - madvise' system/tuning/70-ewe-memory.tmpfiles.conf"
check "journald section" "grep -qx '\\[Journal\\]' system/tuning/70-ewe-journald.conf && grep -qx 'SystemMaxUse=1G' system/tuning/70-ewe-journald.conf"
check "timer section" "grep -qx '\\[Timer\\]' system/tuning/plocate-updatedb.timer.conf && grep -qx 'OnBootSec=10min' system/tuning/plocate-updatedb.timer.conf"
if command -v systemd-analyze >/dev/null 2>&1; then
    check "sysctl file parses" "systemd-analyze cat-config sysctl.d >/dev/null 2>&1"
fi

# an admin edit is never overwritten silently — it is put back to ours on
# apply (ours wins, same as the NM drop-ins) but survives --remove
echo 'vm.swappiness = 10' > "$R/etc/sysctl.d/70-ewe-memory.conf"
sh $A --remove >/dev/null
check "--remove keeps an edited file" "[ -e $R/etc/sysctl.d/70-ewe-memory.conf ]"
check "--remove deletes our tmpfiles file" "[ ! -e $R/etc/tmpfiles.d/70-ewe-memory.conf ]"
check "--remove deletes the journald cap" "[ ! -e $R/etc/systemd/journald.conf.d/70-ewe.conf ]"
check "--remove deletes the plocate drop-in and its dir" "[ ! -e $R/etc/systemd/system/plocate-updatedb.timer.d ]"
sh $A --remove >/dev/null; rc=$?
check "--remove twice: exit 0" "[ $rc = 0 ]"

# the wiring: every caller runs this one script
check "phase 60 runs apply.sh" "grep -q 'system/tuning/apply.sh' phases/60-userconfig.sh"
check "package post_install/upgrade run it" "[ \$(grep -c '^    _ewe_tuning$' packaging/ewe.install) = 2 ]"
check "package pre_remove removes" "grep -q 'apply.sh --remove' packaging/ewe.install"
check "uninstall --purge removes" "grep -q 'apply.sh\" --remove' uninstall.sh"

echo "ewe-tuning: $pass passed, $failn failed"
[ "$failn" = 0 ]
