#!/bin/bash
# gate-lock.test.sh <candidate gate-lock.ps1> - must pass BEFORE a candidate replaces the live gate.
# Why: four gate defects shipped in one afternoon (2026-10-01), each found only after agents used it:
#   v1 console death -> exit 0; v2 waited on leaked grandchildren (3 h hang);
#   v3 lost the exit code (null -> 0); v4 first cut did not parse (stray CR); v5 called-script throw or parse error -> 0;
#   v6 a hung child held the gate for hours (no limit).
# The candidate is copied into its own folder so it gets its own lock file and never queues behind
# live jobs. Exit 0 only if every case passes; the last line is "GATE-TEST pass=<n> fail=<n>".
set -u
cand="$1"; dir=$(mktemp -d -p "$(dirname "$0")" gtest.XXXXXX); cp "$cand" "$dir/gate-lock.ps1"
pass=0; fail=0
check() { if [ "$1" = "$2" ]; then pass=$((pass+1)); echo "[PASS] $3"; else fail=$((fail+1)); echo "[FAIL] $3 (got '$1', want '$2')"; fi; }
w=$(cygpath -w "$dir/gate-lock.ps1")
n=$(powershell -NoProfile -Command "\$e=\$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$w',[ref]\$null,[ref]\$e); \$e.Count" | tr -d '\r')
check "$n" "0" "parses with zero errors"
bare=$(python -c "import sys;b=open(sys.argv[1],'rb').read();print(b.replace(b'\r\n',b'').count(b'\r'))" "$w")
check "$bare" "0" "no bare CR"
nonascii=$(LC_ALL=C grep -c '[^ -~	]' <(tr -d '\r' < "$dir/gate-lock.ps1")); check "$nonascii" "0" "ASCII only"
run() { local t0=$(date +%s); out=$(powershell -NoProfile -File "$dir/gate-lock.ps1" -Label "gtest-$1" -Command "$2" "${@:3}"); rc=$?; secs=$(( $(date +%s) - t0 )); rel=$(echo "$out" | grep -o 'released exit=[0-9]*' | tail -1); }
run exit5 "Write-Output hi; exit 5";           check "$rc" "5" "exit code passes through";  check "$rel" "released exit=5" "released line carries the code"
run zero  "Write-Output hi";                   check "$rc" "0" "a clean command is 0";      check "$rel" "released exit=0" "released line on success"
run crash "throw 'boom'";                      check "$rc" "97" "a thrown error is 97, never 0"
run parse "& 'C:\Users\yedid\AppData\Local\Temp\claude\C--Users-yedid-bin-wezfleet\38d41f80-e534-4f43-9b23-82b80979b435\scratchpad\gl-repro\parse.ps1'";   check "$rc" "97" "a parse error in a called script is 97, never 0"
run nested "& 'C:\Users\yedid\AppData\Local\Temp\claude\C--Users-yedid-bin-wezfleet\38d41f80-e534-4f43-9b23-82b80979b435\scratchpad\gl-repro\throw.ps1'";   check "$rc" "97" "an uncaught throw in a called script is 97, never 0"
run nonterm "Write-Error soft; Write-Output after"; check "$rc" "0" "a non-terminating error still runs on and exits 0"
run hang "Start-Sleep -Seconds 60; exit 0" -MaxMinutes 0.1
check "$rc" "98" "a child past -MaxMinutes is killed and the gate exits 98, never 0"
check "$([ $secs -lt 40 ] && echo fast || echo slow:$secs)" "fast" "the timeout releases the gate promptly"
check "$(echo "$out" | grep -c "TIMEOUT after")" "1" "the gate says it timed out"
run host  "Write-Host hostline; exit 3";       check "$rc" "3" "Write-Host does not break the code"
run linger "Start-Process -FilePath ping.exe -ArgumentList '-n','40','127.0.0.1' -WindowStyle Hidden; exit 5"
check "$rc" "5" "a lingering grandchild keeps the code"; check "$([ $secs -lt 20 ] && echo fast || echo slow:$secs)" "fast" "a lingering grandchild does not hold the gate"
# v5: the child runs opted out of execution-speed power throttling (EcoQoS), read back from inside it.
rd=$(cygpath -w "$(dirname "$0")/throttle-read.ps1")
run throttle "& '$rd' -Child"
check "$rc" "0" "the throttling readback runs"
check "$(echo "$out" | grep -c 'throttling opt-out: set')" "1" "the gate says the opt-out took"
check "$(echo "$out" | grep -o 'SELF ControlMask=[0-9]* StateMask=[0-9]*' | head -1)" "SELF ControlMask=1 StateMask=0" "the child reads itself as opted out"
echo "MEASURE grandchild of the opted-out child: $(echo "$out" | grep -o 'GRANDCHILD .*' | tr -d '\r')"
echo "$out" | grep -q 'hi' ; :
rm -rf "$dir"
echo "GATE-TEST pass=$pass fail=$fail"; [ $fail -eq 0 ]
