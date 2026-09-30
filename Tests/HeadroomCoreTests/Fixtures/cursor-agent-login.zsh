#!/bin/zsh
# Cursor Agent 2026.09.28's signed-out TUI while `status` still reports signed in: no OSC 11
# query, and any byte starts the browser login.
if [[ "$1" == status ]]; then
  print -n '{"isAuthenticated":true}'
  exit 0
fi
stty raw -echo
print -n $'\e[2J\e[H\r\n\r\nCursor Agent\r\nv2026.09.28-64d2043\r\nPress any key to log in...\r\n'
if read -k 1 -t 3 character; then
  print -r -- "$character" > "$PWD/unexpected-input"
fi
