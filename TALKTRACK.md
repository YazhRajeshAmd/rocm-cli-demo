# Talk track: rocm-cli zero-to-serving

Audience: mixed technical and business. Keep Act 2 short; spend the time on Acts 1 and 3.

## 30-second cut
"This is one binary on an AMD GPU box. `rocm serve qwen` and in a couple of minutes I have a private, OpenAI-compatible endpoint. Same API your apps already use, running on our hardware, with our data staying put." Run only `rocm serve` and one client call.

## 3-minute cut
1. `rocm examine`: "It looks at the GPU, driver and ROCm state for me." (20s)
2. `rocm diagnose --model qwen`: "It tells me whether this model will run here before I download gigabytes." (20s)
3. `rocm serve qwen`: let the progress indicator and the summary table with the smoke-test TTFT and tok/s do the talking. (60s)
4. One copilot call (Act 2), then the elapsed time from Act 4. (60s)

## 10-minute full run (all four acts)

**Act 1: configure & launch**
- Point at what the machine reports. Say which engine rocm-cli picked and why (vLLM on Instinct, Lemonade on Radeon/Ryzen AI). Only say this if the output actually shows it.
- Mention the `--managed` background behavior and `rocm services list` for lifecycle.

**Act 2: example workload**
- Say it out loud: "This copilot is just an example so the numbers mean something. The subject is how fast and how simply the endpoint came up."

**Act 3: measured**
- Walk the three numbers: TTFT (how fast it starts answering), tok/s (how fast it writes), p50 vs p99 (does the slowest request stay close to the typical one under a burst).
- Say plainly: client-side smoke test, not an official benchmark. Offer `rocm bench load --auto-ramp` for a sweep.
- Optional: `rocm dash` in a second pane (Observe tab) to show GPU utilization while the burst runs. Use `rocm dash --demo` only if you say it is synthetic.

**Act 4: impact**
- Read the elapsed figure and its label (WARM or COLD) exactly as printed.
- Takeaways: a private endpoint in the time the stopwatch showed; no per-token API bill and no data leaving the box; same OpenAI API so existing apps just repoint; `rocm remote serve` (preview) to share the endpoint across machines over Tailscale.
- Do not cite cost savings or ROI figures unless you have your own measured numbers.

## Likely questions
- **Is this production?** It is a Tech Preview; positioned for experimentation and early feedback.
- **What models?** Curated recipes via `rocm model`; any compatible Hugging Face model otherwise. GGUF for Lemonade, safetensors for vLLM.
- **Multi-GPU?** The README says serving one model across multiple GPUs is not supported; `--gpu` pins a device.
- **Windows/Mac?** Windows: CLI and Lemonade only. macOS: unsupported.
