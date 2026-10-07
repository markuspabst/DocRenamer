#!/bin/zsh
# Finder Quick Action wrapper: runs docrenamer and reports the result as a notification.
output=$("$HOME/.local/bin/docrenamer" "$@" 2>&1 | grep -v "^CoreGraphics PDF has logged an error"; exit ${pipestatus[1]})
exit_code=$?

title="DocRenamer"
[[ $exit_code -ne 0 ]] && title="DocRenamer: error"

osascript \
  -e 'on run argv' \
  -e 'display notification (item 1 of argv) with title (item 2 of argv)' \
  -e 'end run' \
  "$output" "$title"
exit $exit_code
