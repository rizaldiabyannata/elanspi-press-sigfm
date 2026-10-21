#!/bin/sh
# Count genuine and impostor results against the installed fprintd. Usage: sh test-verify.sh [genuine] [impostor]
G=${1:-6}
I=${2:-4}

run () { # $1 = label, $2 = attempts; prints number of verify-match
  m=0
  for i in $(seq 1 "$2"); do
    printf '\n>>> %s %s/%s: lift your finger, press Enter, wait 1 s (calibration), then press the finger ' "$1" "$i" "$2" >&2
    read _
    r=$(fprintd-verify 2>&1 | grep -o 'verify-[a-z-]*' | tail -1)
    echo "    $r" >&2
    [ "$r" = verify-match ] && m=$((m + 1))
  done
  echo "$m"
}

g=$(run "ENROLLED finger" "$G")
i=$(run "DIFFERENT finger" "$I")
echo
echo "enrolled finger accepted:  $g/$G"
echo "different finger accepted: $i/$I (should be 0)"
