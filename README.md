# rocm-cli demo: zero to serving

**Capability being proven:** [`rocm-cli`](https://github.com/ROCm/rocm-cli) takes an AMD GPU machine to a working, OpenAI-compatible local model endpoint in minutes, with one binary and no manual ROCm/Python setup.
**Illustration (kept light):** an internal support-ticket copilot. It exists only so the numbers have a workload behind them.

## What's in the folder

| File | Purpose |
|---|---|
| `demo.sh` | Paced, scripted live terminal run (4 acts). Types each command like a human, then runs it. |
| `copilot_client.py` | Stdlib-only streaming client. Measures TTFT, approximate tok/s, p50/p99 against the endpoint. |
| `TALKTRACK.md` | What to say in each act, with 30s / 3min / 10min cut points. |
| `last_run.json` | Written by Act 3 on a live run (raw per-request results). |

## The four acts

1. **Configure & launch** (developer view): `rocm examine`, `rocm diagnose --model qwen` (will it run here, before downloading), optional `rocm install sdk`, then `rocm serve qwen`. This is the real configuration, and the audience sees it run.
2. **Example workload**: one support-copilot prompt. Captioned as illustration, not the product.
3. **Capability, measured**: a burst of 64 requests at concurrency 16 against the endpoint. Reports TTFT p50/p99, per-stream tok/s and aggregate tok/s. Pointer to `rocm bench load --auto-ramp` for a sweep.
4. **Business impact**: measured wall-clock to serving (labeled WARM or COLD) plus the plain-language takeaways. No invented ROI numbers.

## Quick start: rehearsal (no GPU)

```bash
DEMO_MODE=rehearsal bash demo.sh
```

Prints the plan and shows each command without executing it, then runs `rocm dash --demo` (a synthetic dashboard from the real tool, works anywhere). **Nothing in this mode is measured**, and the script says so on screen.

## Quick start: live (real AMD GPU)

Requirements: Linux (Ubuntu 24.04+) or WSL2, x86_64, an AMD GPU, `python3` for the client only.

```bash
# 1. Install rocm-cli (Linux/WSL), then open a new shell so ~/.local/bin is on PATH
curl -fsSL https://raw.githubusercontent.com/ROCm/rocm-cli/main/install.sh | sh

# 2. Pre-stage (recommended, so the live run isn't dominated by multi-GB downloads)
rocm install sdk
rocm serve qwen          # first run downloads weights; then: rocm services list  -> rocm services stop <id>

# 3. Run the demo
bash demo.sh
```

Use `bash demo.sh`, not `./demo.sh`: zip/extract often drops the executable bit.

### Showing the real cold start

`DEMO_COLD=1 bash demo.sh` runs `rocm install sdk` on camera. That is the honest "zero setup" story but takes much longer (it downloads a managed ROCm runtime and PyTorch stack). The Act 4 stopwatch labels the run **COLD** or **WARM** so you never present a warm number as a cold one.

## Environment variables

| Var | Default | Meaning |
|---|---|---|
| `DEMO_MODE` | `live` | `live` or `rehearsal` |
| `PACE` | `manual` | `manual` (Enter between acts) or `auto` (for recording) |
| `AUTO_DELAY` | `3` | seconds between acts when `PACE=auto` |
| `MODEL` | `qwen` | built-in alias. On Instinct (vLLM) you can use a safetensors repo, e.g. `Qwen/Qwen2.5-1.5B-Instruct`. On Radeon/Ryzen AI (Lemonade) use a GGUF with a quant, e.g. `unsloth/Qwen3-0.6B-GGUF:Q4_0` |
| `ENGINE` | _(auto)_ | `vllm` or `lemonade`; empty lets rocm-cli choose for your GPU |
| `DEMO_COLD` | `0` | `1` = run `rocm install sdk` live |
| `ENDPOINT` | _(auto-detect)_ | set explicitly to skip detection, e.g. `http://127.0.0.1:8000` |
| `REQUESTS` / `RUSH_REQUESTS` / `RUSH_CONCURRENCY` | `6` / `64` / `16` | Act 3 burst shape (client caps concurrency at 16) |
| `PYTHON` | `python3` | interpreter for the client |

### Standalone client (no demo script)

```bash
python3 copilot_client.py --endpoint http://127.0.0.1:8000 --requests 64 --concurrency 16
```

## Honesty notes (read before presenting)

**Verified:** the command names, flags, and behaviors below come from the rocm-cli README on `main` (fetched 2026-10-09): `rocm examine`, `rocm diagnose --model`, `rocm install sdk`, `rocm serve <model> [--engine]`, `rocm services list`, `rocm bench load --auto-ramp`, `rocm dash [--demo]`, `rocm remote serve`. rocm-cli is a **Tech Preview**; commands can change.

**Not verified (no AMD GPU was available where this was built):**

- **Nothing here was run against real hardware.** The client was tested only against a local mock OpenAI-style streaming server, and the shell script only in rehearsal mode and with `bash -n`. Run `DEMO_MODE=live` once end-to-end on your GPU box before any audience sees it.
- **Endpoint auto-detection is best-effort.** `demo.sh` greps the first `http(s)://` URL out of `rocm services list`. The README does not document that output format, so if it fails the script asks you to paste the endpoint from the `rocm serve` summary table (or set `ENDPOINT`).
- **Model name for the API:** the README says serve prints an "API-qualified model name". The client discovers the name from `GET /v1/models` instead, which is standard for OpenAI-compatible servers but not confirmed for each engine.
- **Token counts are approximate.** The client counts streamed content chunks (about 1 token each, not guaranteed). It does not request `include_usage` because support for it isn't confirmed for both engines.
- **p99 needs volume.** With under 50 requests the client says p99 is effectively the max. The default Act 3 burst is 64 requests for that reason.
- **Not an official benchmark.** The README itself says `rocm bench load` and client-side throughput are local smoke tests. Don't quote these numbers as AMD benchmark results.
- **Engine and model form depend on the GPU.** Instinct selects vLLM (safetensors); Radeon/Ryzen AI selects Lemonade (GGUF with a quant). A safetensors-only model on Lemonade fails rather than substituting. Gated models (e.g., Llama) need `HF_TOKEN` or `huggingface-cli login`.
- **Platform limits:** Windows has CLI + Lemonade only (no live dashboard, no vLLM). macOS is unsupported.

## If something fails

Debug from real output, one hypothesis at a time:

```bash
rocm examine                 # what does the machine report?
rocm diagnose                # known ROCm/PyTorch/llama.cpp failure modes
rocm serve qwen --verbose    # stream engine logs (Ctrl-D detaches, Ctrl-C stops)
rocm services list           # is something already running? (reuse needs matching flags)
rocm services logs <id>
dmesg | tail -50             # if several rocm/GPU commands all hang, suspect the driver
```

Common friction: port already in use, an existing server with different sampling flags (stop it with `rocm services stop <id>`), gated model without a token, and a GPU/driver fault that no CLI-level fix will repair.
