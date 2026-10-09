#!/usr/bin/env python3
"""
Streaming client for the rocm-cli demo ("internal support copilot" workload).

Sends support-style prompts to the OpenAI-compatible endpoint that `rocm serve`
exposes, and measures time-to-first-token (TTFT), end-to-end latency, and an
APPROXIMATE decode rate. Python stdlib only (no pip install needed).

Honesty notes (also in README):
  * Token counts are APPROXIMATE: we count streamed content chunks, which is
    usually ~1 token per chunk but is not guaranteed. We deliberately do NOT
    send `stream_options.include_usage` because not every engine behind
    `rocm serve` (Lemonade/llama.cpp vs vLLM) is confirmed to accept it.
  * This is a small client-side smoke test, NOT an official AMD benchmark.
    For a sweep use `rocm bench load --auto-ramp` (see README).
  * Concurrency is capped (MAX_WORKERS) -- it is a bounded pool of real
    requests, not one thread per simulated user.
"""
import argparse
import json
import sys
import threading
import time
import urllib.request
import urllib.error
from concurrent.futures import ThreadPoolExecutor

MAX_WORKERS = 16

PROMPTS = [
    "A customer says their VPN disconnects every 10 minutes on Wi-Fi. Give me a 3-step troubleshooting reply.",
    "Summarize this ticket in two sentences: 'Invoice #4471 was charged twice after I upgraded my plan on the 3rd. Please refund the duplicate.'",
    "Draft a polite reply asking a customer for their order number and the last four digits of their payment method.",
    "Classify this message as billing, technical, or account access: 'I can't reset my password, the email never arrives.'",
    "Explain in plain language why a 502 Bad Gateway might appear after a deployment, for a non-technical account manager.",
    "Write a one-paragraph apology for a 40-minute service outage, with next steps and no jargon.",
]


def normalize_base(endpoint: str) -> str:
    """Accept host, host/v1, or a full /v1/chat/completions URL; return .../v1."""
    e = endpoint.strip().rstrip("/")
    for tail in ("/chat/completions", "/completions"):
        if e.endswith(tail):
            e = e[: -len(tail)]
    if not e.endswith("/v1"):
        e += "/v1"
    return e


def discover_model(base: str) -> str:
    with urllib.request.urlopen(base + "/models", timeout=10) as r:
        data = json.load(r)
    ids = [m.get("id") for m in data.get("data", []) if m.get("id")]
    if not ids:
        raise RuntimeError("GET /v1/models returned no models")
    return ids[0]


def one_request(base: str, model: str, prompt: str, max_tokens: int):
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "max_tokens": max_tokens,
        "stream": True,
    }).encode()
    req = urllib.request.Request(
        base + "/chat/completions", data=body,
        headers={"Content-Type": "application/json"},
    )
    t0 = time.perf_counter()
    ttft = None
    chunks = 0
    text = []
    with urllib.request.urlopen(req, timeout=300) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                break
            try:
                delta = json.loads(payload)["choices"][0].get("delta", {})
            except (ValueError, KeyError, IndexError):
                continue
            # Some reasoning models stream `reasoning_content` before `content`.
            piece = delta.get("content") or delta.get("reasoning_content")
            if piece:
                if ttft is None:
                    ttft = time.perf_counter() - t0
                chunks += 1
                text.append(piece)
    total = time.perf_counter() - t0
    if ttft is None:
        raise RuntimeError("stream ended without any content")
    decode_s = max(total - ttft, 1e-9)
    return {
        "ttft": ttft, "total": total, "chunks": chunks,
        "tps": (chunks - 1) / decode_s if chunks > 1 else 0.0,
        "text": "".join(text),
    }


def pct(vals, p):
    """Nearest-rank percentile."""
    s = sorted(vals)
    k = max(0, min(len(s) - 1, int(round(p / 100.0 * len(s) + 0.5)) - 1))
    return s[k]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--endpoint", required=True,
                    help="URL from `rocm serve` / `rocm services list` (host, /v1, or full path)")
    ap.add_argument("--model", default="", help="API-qualified model name (default: discover via /v1/models)")
    ap.add_argument("--requests", type=int, default=6)
    ap.add_argument("--concurrency", type=int, default=1, help=f"capped at {MAX_WORKERS}")
    ap.add_argument("--max-tokens", type=int, default=128)
    ap.add_argument("--show-first", action="store_true", help="print the first reply (nice for a live demo)")
    ap.add_argument("--json-out", default="", help="write raw per-request results to this file")
    a = ap.parse_args()

    base = normalize_base(a.endpoint)
    try:
        model = a.model or discover_model(base)
    except Exception as e:  # noqa: BLE001
        sys.exit(f"Could not reach {base}: {e}\n"
                 f"Is the server up? Try: rocm services list")
    conc = max(1, min(a.concurrency, MAX_WORKERS))
    if a.concurrency > MAX_WORKERS:
        print(f"(concurrency capped at {MAX_WORKERS})")

    print(f"endpoint : {base}")
    print(f"model    : {model}")
    print(f"requests : {a.requests}   concurrency: {conc}   max_tokens: {a.max_tokens}\n")

    results, errors = [], []
    lock = threading.Lock()

    def work(i):
        prompt = PROMPTS[i % len(PROMPTS)]
        try:
            r = one_request(base, model, prompt, a.max_tokens)
            with lock:
                results.append(r)
                print(f"  req {i+1:>3}: TTFT {r['ttft']*1000:7.0f} ms | total {r['total']:6.2f} s | "
                      f"~{r['tps']:6.1f} tok/s")
        except (urllib.error.URLError, RuntimeError, OSError) as e:
            with lock:
                errors.append(str(e))
                print(f"  req {i+1:>3}: ERROR {e}")

    wall0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=conc) as pool:
        list(pool.map(work, range(a.requests)))
    wall = time.perf_counter() - wall0

    if not results:
        sys.exit("\nNo successful requests.")

    if a.show_first:
        print("\n--- first reply ---\n" + results[0]["text"].strip() + "\n-------------------")

    ttfts = [r["ttft"] * 1000 for r in results]
    tpss = [r["tps"] for r in results if r["tps"] > 0]
    agg_chunks = sum(r["chunks"] for r in results)
    print("\nSummary (client-side, approximate)")
    print(f"  ok / errors        : {len(results)} / {len(errors)}")
    print(f"  TTFT p50 / p99     : {pct(ttfts, 50):.0f} ms / {pct(ttfts, 99):.0f} ms"
          + ("   (n<50: p99 is effectively the max)" if len(ttfts) < 50 else ""))
    if tpss:
        print(f"  per-stream tok/s   : median ~{pct(tpss, 50):.1f}")
    print(f"  aggregate tok/s    : ~{agg_chunks / wall:.1f}  (all streams, wall {wall:.2f} s)")

    if a.json_out:
        with open(a.json_out, "w") as f:
            json.dump({"endpoint": base, "model": model, "concurrency": conc,
                       "results": [{k: v for k, v in r.items() if k != "text"} for r in results],
                       "errors": errors}, f, indent=2)
        print(f"  raw results        : {a.json_out}")
    sys.exit(1 if errors and not results else 0)


if __name__ == "__main__":
    main()
