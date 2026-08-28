#!/usr/bin/env bash
# Engine test suite for wordsmith. Everything runs against a sandbox in a
# temp dir with fake backends on PATH: no model is called, nothing touches
# the real ~/.config or XDG_RUNTIME_DIR, and the whole thing finishes in a
# few seconds. Exit status is non-zero if any test fails.
#
#   tests/run-tests.sh
#
# The fakes are controlled by env vars (CODEX_MODE, CLAUDE_MODE, OC_MODE,
# OLLAMA_MODE) so failure paths are tested without a real failure.

set -u

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WS="$PLUGIN_DIR/bin/wordsmith"

SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
export XDG_RUNTIME_DIR="$SB/run"
export XDG_CONFIG_HOME="$SB/config"
export WL_DIR="$SB/wl" AUDIT="$SB/audit"
mkdir -p "$SB/run" "$SB/config" "$SB/bin" "$WL_DIR" "$AUDIT"

# ------------------------------------------------------------- the fakes -----

cat > "$SB/bin/codex" <<'EOF'
#!/usr/bin/env bash
out=""
for ((i=1;i<=$#;i++)); do [[ "${!i}" == "-o" ]] && { j=$((i+1)); out="${!j}"; }; done
cat > "$AUDIT/codex-stdin.txt"
case "${CODEX_MODE:-ok}" in
  ok)    printf 'REWRITTEN(TEXT %s CHARS)' "$(wc -c < "$AUDIT/codex-stdin.txt" | tr -d ' ')" > "$out" ;;
  fence) printf '```\nREWRITTEN-FENCED\n```' > "$out" ;;
  empty) : > "$out" ;;
  fail)  echo "codex: mock failure" >&2; exit 1 ;;
  slow)  sleep 30 ;;
esac
EOF

cat > "$SB/bin/claude" <<'EOF'
#!/usr/bin/env bash
case "${CLAUDE_MODE:-ok}" in
  ok)   printf 'CLAUDE-REWRITE' ;;
  fail) echo "claude: mock failure" >&2; exit 1 ;;
esac
EOF

cat > "$SB/bin/opencode" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "session" && "$2" == "delete" ]]; then
  echo "deleted $3" >> "$AUDIT/session-deletes.log"; exit 0
fi
echo "created id=ses_TEST123" >&2
case "${OC_MODE:-ok}" in
  ok)   printf 'OC-REWRITE' ;;
  fail) echo "level=ERROR mock opencode failure" >&2; exit 1 ;;
esac
EOF

cat > "$SB/bin/curl" <<'EOF'
#!/usr/bin/env bash
# Stands in for the Ollama daemon at localhost:11434.
case "${OLLAMA_MODE:-ok}" in
  down)     exit 7 ;;
  modelerr) printf '{"error":"model not found, try pulling it first"}'; exit 0 ;;
  empty)    printf '{"message":{"content":""}}'; exit 0 ;;
  *)        printf '{"message":{"content":"LOCAL-REWRITE"}}' ;;
esac
EOF

cat > "$SB/bin/wtype" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-" ]]; then cat > "$AUDIT/wtype.txt"
else printf '%s' "$*" > "$AUDIT/wtype.txt"; fi
EOF

cat > "$SB/bin/wl-paste" <<'EOF'
#!/usr/bin/env bash
f="$WL_DIR/clipboard.txt"
for a in "$@"; do [[ "$a" == "--primary" ]] && f="$WL_DIR/primary.txt"; done
[[ -s "$f" ]] && cat "$f" || exit 1
EOF

cat > "$SB/bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
cat > "$WL_DIR/clipboard.txt"
EOF

chmod +x "$SB/bin"/*
export PATH="$SB/bin:$PATH"
: > "$AUDIT/session-deletes.log"

# ------------------------------------------------------------ the harness ----

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1: $2"; }
assert() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "got [$2] want [$3]"; fi }
assert_grep() { if printf '%s' "$2" | grep -q "$3"; then ok "$1"; else bad "$1" "[$2] misses /$3/"; fi }

wait_done() { # wait_status [wanted] — until status equals it, or leaves working
  local want="${1:-}"
  for _ in $(seq 1 60); do
    ST=$($WS state | jq -r .status)
    if [[ -n "$want" ]]; then [[ "$ST" == "$want" ]] && return 0
    else [[ "$ST" != "working" ]] && return 0; fi
    sleep 0.2
  done
  ST=$($WS state | jq -r .status)
  return 1
}

run_stdin() { printf '%s' "$1" | $WS run --stdin --mode "${2:-shorten}" >/dev/null 2>&1; }

echo "== happy path =="
run_stdin 'Hello there,

This is a draft.'
wait_done done
assert "status done" "$ST" "done"
assert "result" "$($WS state | jq -r .result)" "REWRITTEN(TEXT 30 CHARS)"
assert "model received the text on stdin" "$(wc -c < "$AUDIT/codex-stdin.txt" | tr -d ' ')" "30"
assert "autocopy puts result on clipboard" "$(cat "$WL_DIR/clipboard.txt")" "REWRITTEN(TEXT 30 CHARS)"
assert "source label" "$($WS state | jq -r .source)" "stdin"

echo "== copy, history, indexes =="
run_stdin 'Second draft.'
wait_done done
$WS copy >/dev/null 2>&1
assert "copy" "$(cat "$WL_DIR/clipboard.txt")" "REWRITTEN(TEXT 13 CHARS)"
assert "history depth" "$($WS state | jq '.history | length')" "2"
$WS copy --index 1 >/dev/null 2>&1
assert "copy --index 1 walks history" "$(cat "$WL_DIR/clipboard.txt")" "REWRITTEN(TEXT 30 CHARS)"
$WS copy --index 9 2>&1 | grep -q "no result" && ok "out-of-range copy dies cleanly" || bad "out-of-range copy" "no error"

echo "== quoted-thread split =="
run_stdin 'Hi Alex,

Please fix this.

On Tue, Aug 25, 2026 at 3:14 PM, Alex wrote:

> quoted line one
> quoted line two'
wait_done done
assert "model saw only the draft" "$(cat "$AUDIT/codex-stdin.txt")" "Hi Alex,

Please fix this."
assert "tail reattached byte for byte" "$($WS state | jq -r .result)" "REWRITTEN(TEXT 26 CHARS)

On Tue, Aug 25, 2026 at 3:14 PM, Alex wrote:

> quoted line one
> quoted line two"
assert "quotedLines counted" "$($WS state | jq -r .quotedLines)" "4"

echo "== failure paths =="
printf 'x' | env CODEX_MODE=slow $WS run --stdin --mode shorten --timeout 2 >/dev/null 2>&1
wait_done error
assert "timeout status" "$ST" "error"
assert_grep "timeout message" "$($WS state | jq -r .error)" "timed out after 2s"

printf 'y' | env CODEX_MODE=fail $WS run --stdin >/dev/null 2>&1
wait_done error
assert "backend failure status" "$ST" "error"
assert_grep "backend failure surfaced" "$($WS state | jq -r .error)" "mock failure"

printf 'z' | env CODEX_MODE=empty $WS run --stdin >/dev/null 2>&1
wait_done error
assert "empty output is a failure" "$ST" "error"

printf 'f' | env CODEX_MODE=fence $WS run --stdin >/dev/null 2>&1
wait_done done
assert "stray fence stripped" "$($WS state | jq -r .result)" "REWRITTEN-FENCED"

printf '' | $WS run --stdin >/dev/null 2>&1
assert "empty stdin" "$($WS state | jq -r .error)" "No text on stdin."
printf '   \n\n  ' | $WS run --stdin >/dev/null 2>&1
assert "whitespace-only stdin" "$($WS state | jq -r .error)" "No text on stdin."

python3 -c "print('a'*1500)" 2>/dev/null | $WS run --stdin --max-chars 1000 >/dev/null 2>&1 \
  || { printf 'a%.0s' {1..1500}; echo; } | $WS run --stdin --max-chars 1000 >/dev/null 2>&1
assert_grep "maxChars enforced" "$($WS state | jq -r .error)" "the limit is 1000"

printf 'c' | $WS run --stdin --mode custom >/dev/null 2>&1
assert "custom needs an instruction" "$($WS state | jq -r .status)" "error"

echo "== dangling value flags terminate =="
for cmd in "state --backend" "state --model" "state --effort" "state --timeout" \
           "state --max-chars" "state --source" "state --instruction" "state --index" \
           "state --default-backend" "state --default-model-codex" \
           "run --mode" "copy --index"; do
  out=$(timeout 2 $WS $cmd 2>&1); rc=$?
  if [[ $rc -eq 124 ]]; then bad "[$cmd] hangs" "infinite loop"
  elif printf '%s' "$out" | grep -q "missing value for"; then ok "[$cmd] dies cleanly"
  else bad "[$cmd]" "rc=$rc out=$out"; fi
done

echo "== backends, models, persistence =="
$WS backend claude >/dev/null
assert "backend persisted" "$(jq -r .backend "$XDG_CONFIG_HOME/omarchy/wordsmith.json")" "claude"
run_stdin 'cl'
wait_done done
assert "claude path" "$($WS state | jq -r .result)" "CLAUDE-REWRITE"
assert "selectedBackend follows the toggle" "$($WS state | jq -r .selectedBackend)" "claude"
$WS model claude-sonnet-5 >/dev/null
assert "model persisted" "$(jq -r .claudeModel "$XDG_CONFIG_HOME/omarchy/wordsmith.json")" "claude-sonnet-5"
$WS model not-a-model 2>&1 | grep -q "not offered" && ok "unlisted model rejected" || bad "unlisted model" "accepted"
assert "models reports current" "$($WS models | jq -r .current)" "claude-sonnet-5"

echo "== one job at a time, cancel =="
printf 'guard' > "$WL_DIR/clipboard.txt"; : > "$WL_DIR/primary.txt"
env CODEX_MODE=slow $WS run --mode shorten >/dev/null 2>&1
sleep 0.5
assert "second run returns working state" "$(env CODEX_MODE=slow $WS run --mode shorten 2>/dev/null | jq -r .status)" "working"
$WS cancel >/dev/null 2>&1
sleep 0.3
assert "cancel returns to idle" "$($WS state | jq -r .status)" "idle"
$WS cancel >/dev/null 2>&1 && ok "cancel with no job is safe" || bad "cancel with no job" "rc=$?"

echo "== selection grab =="
printf 'is is a test\n\nfull text' > "$WL_DIR/primary.txt"
printf 'This is a test\n\nfull text' > "$WL_DIR/clipboard.txt"
$WS run --mode shorten >/dev/null 2>&1
assert "clipboard superset wins" "$($WS state | jq -r .source)" "clipboard"
printf 'full primary text' > "$WL_DIR/primary.txt"
printf 'unrelated clipboard' > "$WL_DIR/clipboard.txt"
$WS run --mode shorten >/dev/null 2>&1
assert "unrelated clipboard loses to the drag" "$($WS state | jq -r .source)" "selection"
: > "$WL_DIR/primary.txt"; : > "$WL_DIR/clipboard.txt"
$WS run --mode shorten >/dev/null 2>&1
assert_grep "nothing selected" "$($WS state | jq -r .error)" "Nothing selected"

echo "== opencode session purge =="
$WS backend opencode-go >/dev/null
run_stdin 'oc'
wait_done done
assert "opencode path" "$($WS state | jq -r .result)" "OC-REWRITE"
sleep 0.5
grep -q "deleted ses_TEST123" "$AUDIT/session-deletes.log" && ok "session purged" \
  || bad "session purged" "$(cat "$AUDIT/session-deletes.log")"

echo "== unicode, clear, JSON shapes =="
printf 'สวัสดี Héllo — café' | $WS run --stdin >/dev/null 2>&1
wait_done done
assert "chars are codepoints, not bytes" "$($WS state | jq -r .chars)" "19"
assert "unicode survives the state file" "$($WS state | jq -r .original)" "สวัสดี Héllo — café"
$WS clear >/dev/null
assert "clear resets" "$($WS state | jq -r .status)" "idle"
assert "clear wipes history" "$($WS state | jq '.history | length')" "0"
$WS backends | jq -e 'length == 4 and all(.[]; .model != "")' >/dev/null && ok "backends JSON" || bad "backends JSON" "malformed"
$WS modes | jq -e 'length == 5' >/dev/null && ok "modes JSON" || bad "modes JSON" "malformed"
rm -f "$XDG_RUNTIME_DIR/wordsmith/state.json"
$WS state | jq -e '.status == "idle" and (.history | length) == 0' >/dev/null && ok "fresh-boot state" || bad "fresh-boot state" "malformed"

echo
echo "pass=$PASS fail=$FAIL"
[[ $FAIL -eq 0 ]]
