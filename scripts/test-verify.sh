#!/bin/sh
# Count accepted attempts against the installed fprintd.
# Usage: sh test-verify.sh [normal] [misplaced] [other-finger]
N=${1:-3}
M=${2:-6}
I=${3:-4}

run () { # $1 = what to press, $2 = attempts; prints number of verify-match
  m=0
  for i in $(seq 1 "$2"); do
    printf '\n>>> %s/%s: lift your finger, press Enter, wait 1 s (calibration), then press %s ' "$i" "$2" "$1" >&2
    read _
    r=$(fprintd-verify 2>&1 | grep -o 'verify-[a-z-]*' | tail -1)
    echo "    $r" >&2
    [ "$r" = verify-match ] && m=$((m + 1))
  done
  echo "$m"
}

n=$(run "the ENROLLED finger normally" "$N")
m=$(run "the ENROLLED finger deliberately off-centre (alternate up/down/left/right)" "$M")
i=$(run "a DIFFERENT finger" "$I")
echo
echo "enrolled, normal:     $n/$N"
echo "enrolled, misplaced:  $m/$M"
echo "different finger:     $i/$I (should be 0)"
