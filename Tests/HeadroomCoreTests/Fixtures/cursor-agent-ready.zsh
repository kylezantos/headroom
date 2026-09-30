#!/bin/zsh
if [[ "$1" == status ]]; then
  print -n '{"isAuthenticated":true}'
  exit 0
fi
print -r -- "$*" > "$PWD/argv"
stty raw -echo
# Older builds block their first paint until the terminal answers the OSC 11 query.
print -n $'\e]11;?\a'
reply=''
while read -k 1 character; do
  reply+="$character"
  [[ "$character" == $'\a' ]] && break
done
[[ "$reply" == $'\e]11;rgb:'* ]] || exit 1
print -n $'Cursor Agent\r\nv2026.09.15-d2fe57e\r\nPlan, search, build anything\r\nAuto Balance\r\n'
buffer=''
while read -k 1 character; do
  buffer+="$character"
  [[ "$buffer" == */usage ]] && break
done
print -n $'\r\n→  /usage    Show plan and on-demand usage\r\n'
buffer=''
while read -k 1 character; do
  buffer+="$character"
  [[ "$buffer" == *$'\e[13u' ]] && break
done
print -n $'\r\nMonthly plan and on-demand usage\r\nUsage • Pro+ Resets Sep 1\r\nIncluded 1% used\r\n  Auto 1% used\r\n  API 3% used\r\nOn-Demand Disabled\r\n'
sleep 1
