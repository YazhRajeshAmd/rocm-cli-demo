#!/usr/bin/env bash
# =============================================================================
# rocm-cli "zero to serving" demo -- scripted live terminal run
#
# Capability being proven : rocm-cli takes a bare AMD GPU box to a working,
#                           OpenAI-compatible local model endpoint in minutes,
#                           with one binary and no manual ROCm/Python setup.
# Illustration (light)    : an internal support-ticket copilot.
#
# Four acts (mirrors the AMD capability-demo shape, adapted to a terminal):
#   1. Configure & launch   -> rocm examine / diagnose --model / serve
#   2. Example workload     -> support-copilot prompts (illustration only)
#   3. Capability, measured -> TTFT, tok/s, p50/p99 from a real client
#   4. Business impact      -> elapsed "zero-to-serving" time + what it means
#
# Run:   bash demo.sh                      (live, press Enter between acts)
#        DEMO_MODE=rehearsal bash demo.sh  (no GPU; prints plan, runs `rocm dash --demo`)
#        PACE=auto bash demo.sh            (hands-free, for recording)
# See README.md for all env vars and honesty notes.
# =============================================================================
set -u

DEMO_MODE="${DEMO_MODE:-live}"        # live | rehearsal
PACE="${PACE:-manual}"                # manual | auto
AUTO_DELAY="${AUTO_DELAY:-3}"         # seconds between acts when PACE=auto
MODEL="${MODEL:-qwen}"                # `qwen` is a built-in alias per the rocm-cli README
ENGINE="${ENGINE:-}"                  # empty = let rocm pick (vllm on Instinct, lemonade on Radeon/Ryzen AI)
DEMO_COLD="${DEMO_COLD:-0}"           # 1 = actually run `rocm install sdk` on camera
ENDPOINT="${ENDPOINT:-}"              # set to skip endpoint auto-detection
REQUESTS="${REQUESTS:-6}"
RUSH_REQUESTS="${RUSH_REQUESTS:-64}"  # Act 3 burst size (>=50 so p99 means something)
RUSH_CONCURRENCY="${RUSH_CONCURRENCY:-16}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLIENT="$HERE/copilot_client.py"
PY="${PYTHON:-python3}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[36m'; YEL=$'\033[33m'; RED=$'\033[31m'; GRN=$'\033[32m'; RST=$'\033[0m'

START_TS=$(date +%s)
act()   { printf '\n%s== ACT %s ==%s\n' "$BOLD$CYAN" "$1" "$RST"; }
say()   { printf '%s%s%s\n' "$DIM" "$1" "$RST"; }
warn()  { printf '%s%s%s\n' "$YEL" "$1" "$RST"; }
die()   { printf '%s%s%s\n' "$RED" "$1" "$RST"; exit 1; }
pause() {
  if [ "$PACE" = "auto" ]; then sleep "$AUTO_DELAY"; else
    printf '%s[Enter to continue]%s' "$DIM" "$RST"; read -r _ ; fi
}
# type the command like a human, then run it (live) or just show it (rehearsal)
run() {
  printf '%s$ %s' "$GRN" "$RST"
  local c="$*" i
  for ((i=0;i<${#c};i++)); do printf '%s' "${c:$i:1}"; sleep 0.012; done; printf '\n'
  if [ "$DEMO_MODE" = "rehearsal" ]; then warn "  [rehearsal] not executed"; return 0; fi
  eval "$c"
}

banner() {
  printf '%s' "$BOLD"
  echo "rocm-cli  |  zero-to-serving demo  |  mode: $DEMO_MODE  |  model: $MODEL"
  printf '%s' "$RST"
  warn "Illustrative demo script. Tech-preview software; numbers below are client-side smoke-test figures, not an AMD benchmark."
  if [ "$DEMO_MODE" = "rehearsal" ]; then
    warn "REHEARSAL MODE: nothing below is measured. No GPU commands are executed."
  fi
}

preflight() {
  if [ "$DEMO_MODE" = "live" ]; then
    command -v rocm >/dev/null 2>&1 || die "rocm not found on PATH. Install: curl -fsSL https://raw.githubusercontent.com/ROCm/rocm-cli/main/install.sh | sh  (then open a new shell)"
    command -v "$PY" >/dev/null 2>&1 || die "$PY not found (needed only for copilot_client.py)"
    [ -f "$CLIENT" ] || die "missing $CLIENT"
  fi
}

detect_endpoint() {
  [ -n "$ENDPOINT" ] && return 0
  # BEST-EFFORT: schema/format of `rocm services list` output is not verified
  # here. We grab the first http:// URL it prints. If that fails, ask.
  ENDPOINT="$(rocm services list 2>/dev/null | grep -Eo 'https?://[^[:space:]",|]+' | head -n1)"
  if [ -z "$ENDPOINT" ]; then
    warn "Could not auto-detect the endpoint from 'rocm services list'."
    printf 'Paste the endpoint from the serve table: '; read -r ENDPOINT
  fi
}

banner
preflight
pause

# ---------------------------------------------------------------- ACT 1
act "1 - Configure & launch (the developer's view)"
say "One binary. First, what does this machine have?"
run "rocm examine"
pause

say "Before downloading anything: will this model run on this GPU?"
run "rocm diagnose --model $MODEL"
pause

if [ "$DEMO_COLD" = "1" ]; then
  say "Cold start: install a managed ROCm runtime (TheRock wheels + matching PyTorch)."
  run "rocm install sdk"
  STOPWATCH_LABEL="COLD (included rocm install sdk + model download as needed)"
else
  say "Runtime is pre-staged for the demo (set DEMO_COLD=1 to show install live)."
  STOPWATCH_LABEL="WARM (runtime pre-staged; model may or may not be cached)"
fi

SERVE_START=$(date +%s)
say "Serve the model. rocm picks the engine for this GPU and runs a smoke test."
SERVE_CMD="rocm serve $MODEL"
[ -n "$ENGINE" ] && SERVE_CMD="$SERVE_CMD --engine $ENGINE"
run "$SERVE_CMD" || die "rocm serve failed. Debug with: rocm serve $MODEL --verbose   |   rocm diagnose   |   rocm services logs <id>"
SERVE_END=$(date +%s)
pause

# ---------------------------------------------------------------- ACT 2
act "2 - Example workload (illustration only)"
say "Used here only so the numbers have a concrete workload behind them:"
say "an internal support-ticket copilot answering agents' requests."
if [ "$DEMO_MODE" = "live" ]; then detect_endpoint; say "endpoint: $ENDPOINT"; fi
run "$PY \"$CLIENT\" --endpoint \"\$ENDPOINT\" --requests 1 --show-first"
pause

# ---------------------------------------------------------------- ACT 3
act "3 - The capability, measured"
say "Standard OpenAI-compatible endpoint -> any existing client works. Now a burst: end-of-month ticket rush."
run "$PY \"$CLIENT\" --endpoint \"\$ENDPOINT\" --requests $RUSH_REQUESTS --concurrency $RUSH_CONCURRENCY --json-out \"$HERE/last_run.json\""
say "For a full concurrency sweep use the built-in tool (smoke test, not an official benchmark):"
say "  rocm bench load --endpoint \"\$ENDPOINT\" --auto-ramp"
say "Live view of the same GPU: rocm dash   (rehearsal/no GPU: rocm dash --demo)"
pause

# ---------------------------------------------------------------- ACT 4
act "4 - Business impact"
END_TS=$(date +%s)
if [ "$DEMO_MODE" = "live" ]; then
  printf '%sElapsed, start of demo -> serving + answering: %ss  [%s]%s\n' "$BOLD" "$((END_TS-START_TS))" "$STOPWATCH_LABEL" "$RST"
  printf 'Of which `rocm serve` (start -> ready + smoke test): %ss\n' "$((SERVE_END-SERVE_START))"
  say "Elapsed includes presenter pauses when PACE=manual; use PACE=auto or the serve-only figure for a fair number."
else
  say "Rehearsal: no timings recorded. Launching the tool's own synthetic dashboard (q to quit)."
  if command -v rocm >/dev/null 2>&1; then
    printf '%s$ %srocm dash --demo\n' "$GRN" "$RST"; rocm dash --demo
  else
    warn "  rocm not installed here; skipping 'rocm dash --demo'."
  fi
fi
cat <<'EOF'

What this means (talk track, no invented figures):
  - Time to a working private endpoint is the elapsed figure above, not an engineering ticket.
  - Data stays on your own AMD GPU: no per-token API bill, no data leaving the box.
  - Same OpenAI-compatible API: the apps your team already wrote just point at it.
  - Scale-out: `rocm remote serve <machine> <model>` (preview) shares an endpoint over Tailscale.
EOF
printf '\n%sDone.%s\n' "$BOLD" "$RST"
