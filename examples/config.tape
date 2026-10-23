# Shared settings for every tape in this directory, pulled in with `Source config.tape`.
# Runs the repo's own claude-local.sh from the repo root, named as the installed command.
# Echo is off while it runs: Claude Code turns on focus reporting before raw mode, and
# VHS's terminal answers with a focus-in report (ESC [ I) that would otherwise be echoed
# as a stray ^[[I next to the Claude Code logo.
Set FontSize 13
Set Width 1280
Set Height 680
Set Padding 10
Set Shell bash

Hide
Type `PS1="\[\e[38;5;63m\]❯\[\e[0m\] "` Enter
Type "cd .." Enter
Type `claude-local() { stty -echo; ./claude-local.sh "$@"; stty echo; }` Enter
Type "clear" Enter
Sleep 100ms
Show
