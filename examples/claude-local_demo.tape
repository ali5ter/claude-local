# A real session: Ollama must be reachable and both configured models installed.
# Run through run_vhs.sh, which strips nested-session markers that would otherwise leak in.
Output claude-local_demo.gif

Source config.tape

Type "claude-local --switchable --audit"
Sleep 600ms
Enter

# The banner, then Claude Code starts with the local model in its header
Sleep 7s

# The picker lists the two local models under their real names. Switch to the second
# one with s (session only); Enter would save the row's alias as Claude Code's default.
Type "/model"
Sleep 1200ms
Enter
Sleep 2s
Down
Sleep 1500ms
Type "s"
Sleep 1500ms

# A prompt answered by the local model, now the slower second one. Wait for the reply
# itself (a thinking model takes a variable while), then pause so it can be read.
Type "Reply with exactly: ok"
Sleep 600ms
Enter
Wait+Screen@90s /⏺ ok/
Sleep 2s

# Leave; the audit summary prints on exit
Type "/exit"
Sleep 800ms
Enter
Sleep 5s
