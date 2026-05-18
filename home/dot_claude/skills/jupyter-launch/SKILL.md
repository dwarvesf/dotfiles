---
name: jupyter-launch
description: Use when starting a JupyterLab server, opening a `.ipynb` file in Jupyter on this machine, configuring the Notebook Intelligence (NBI) extension, or switching the AI provider for a notebook session. Trigger phrases include "start jupyter", "launch jupyter", "open <X>.ipynb", "run a notebook", "spin up jupyter lab", "swap to local model for this notebook", "use claude for this notebook", "jlab", "nbi", "notebook intelligence", "swap NBI preset", "AI in jupyter", or any case where the next action is `jupyter lab ...`. Tells Claude to prefer the `jlab` fish wrapper (which injects ANTHROPIC_API_KEY + OLLAMA_HOST) over bare `jupyter lab`, and how to pick the right NBI preset (cloud Claude vs local Ollama on the Mini) for the workload. NOT for editing notebook content (just edit the .py twin per SPEC-011). NOT for non-Jupyter Python REPL work.
---

# Launching JupyterLab on this machine

Single hard rule: **start the server with `jlab`, not `jupyter lab`.**

```fish
jlab path/to/notebook.ipynb        # or just `jlab` to land in the file browser
```

The wrapper at `~/.config/fish/functions/jlab.fish`:

1. Builds a temp env-file with `ANTHROPIC_API_KEY=op://Toolkit/anthropic-api-key/credential` plus `OLLAMA_HOST=http://mac-mini:11434`.
2. Resolves via `op run --env-file=...` (biometric prompt may appear once per session).
3. Exec's `/Users/tieubao/.local/bin/jupyter-lab` with the user's args.
4. Prints the active NBI preset before the server starts.

Without those env vars, Notebook Intelligence's Anthropic provider and Ollama provider both fail silently (no error toast; just no completion). Bare `jupyter lab` will appear to launch fine but the AI panel will be useless.

## Picking the NBI preset

NBI configs live in `~/.jupyter/nbi/`. The active config is `config.json`; presets are `config.claude.tpl.json` and `config.ollama.tpl.json` (op-inject templates containing `op://` placeholders for the opencode API key). Three fish helpers swap them:

| Helper | Preset | Use for |
|---|---|---|
| `nbi-claude` | chat=`claude-opus-4-7` (Anthropic), inline=`deepseek-v4-flash` (opencode `/zen/go/v1`) | Learning notebooks, public content, the cost-optimized default (Opus for thinking; cheap opencode for high-frequency keystrokes). |
| `nbi-local` | chat=`qwen3.6:35b-a3b` on Mini (Ollama), inline=`deepseek-v4-flash` (opencode) | Notebooks where notebook *context* should stay local (trading, family-office cell sees the whole notebook) but short inline snippets going to opencode cloud are acceptable. For strict no-cloud, see "Strict-local override" below. |
| `nbi-status` | (read-only) | Print which preset is active. |

Each helper runs `op inject -i <preset>.tpl.json -o config.json -f`, resolving the opencode key from `op://Toolkit/opencode-api-key-coding/credential` at swap time. The resolved key sits plaintext in `~/.jupyter/nbi/config.json`; the directory is gitignored.

After running `nbi-claude` or `nbi-local`, the change applies on the **next** `jlab` invocation. The currently-running server keeps the preset it started with.

Decision rule:

- Current working directory is `learning/`, `experiments/`, `tools/`, `research/`, or a public repo → `nbi-claude`.
- Current working directory is `tieubao/trading`, `tieubao/family-office`, `dfoundation`, or any path with client / NDA data → `nbi-local`.
- User explicitly names the provider → honor that.
- Unsure → ask once.

## Strict-local override (when inline cloud is unacceptable)

`nbi-local` routes inline completions to opencode cloud by default (cheap, fast, but it's still cloud). For notebooks where even short snippets must not leave the machine (raw secrets, PII, embargoed financial data), swap inline to a local Ollama coder model:

1. `ssh mac-mini-danang 'ollama pull qwen2.5-coder'` (~5GB; one-time).
2. Edit `~/.jupyter/nbi/config.ollama.tpl.json` and change the `inline_completion_model` block to `{"provider": "ollama", "model": "qwen2.5-coder"}` (drop the openai-compatible properties).
3. Re-run `nbi-local`.

NBI's Ollama inline-completion is hardcoded to a fixed model list: `qwen2.5-coder`, `deepseek-coder-v2`, `codestral`, `starcoder2`, `codellama:7b-code`. Pick one of these; the user's general Mini models (qwen3.6, deepseek-r1, qwen3-vl, deepseek-ocr, llama3.2) don't qualify.

## Gotchas

**1. Ollama on Mini is bound to the personal Tailscale identity.** The Mini has two tailnet names: `mac-mini-danang` (100.98.16.107, tagged Dwarves device) and `mac-mini` (100.118.23.42, personal `nntruonghan@` device). Ollama listens on `mac-mini` only. The `jlab` wrapper hard-codes `http://mac-mini:11434`; don't second-guess and don't rewrite to the tagged name.

**2. opencode.ai/zen/go/v1 has a TLS-fingerprint gate.** Cloudflare WAF rejects `curl` / stdlib-urllib clients even with a correct Bearer token. The only known-good clients are `httpx` and the `openai` Python SDK. NBI's openai-compatible provider uses the `openai` SDK, so it works. If you're tempted to test the endpoint with `curl`, use `-H` plus an SDK-side check; the curl path will 401 on `/chat/completions` even with a valid key.

**3. Key rotation requires re-running the swap.** Active `config.json` contains the resolved opencode key. If the `op://Toolkit/opencode-api-key-coding/credential` item rotates, run `nbi-claude` or `nbi-local` again to re-render. Until then, NBI keeps the stale key and silently 401s on inline requests.

**4. Edit `.py`, not `.ipynb`.** Per SPEC-011 in `learning/quantum-computing/CLAUDE.md`, notebooks are jupytext-paired. The `.py:percent` is the committed source; the `.ipynb` is a gitignored build artifact. JupyterLab's autosave keeps both in sync once you open the `.ipynb`, but for Claude Code edits, modify the `.py` and run `jupytext --sync <file>.py`.

## Reference

- Wrapper: `~/.config/fish/functions/jlab.fish`
- Helpers: `~/.config/fish/functions/nbi-{claude,local,status}.fish`
- Preset templates: `~/.jupyter/nbi/config.{claude,ollama}.tpl.json` (committed-safe; `op://` refs)
- Active: `~/.jupyter/nbi/config.json` (rendered; gitignored; contains resolved opencode key)
- opencode endpoint: `https://opencode.ai/zen/go/v1`, model `deepseek-v4-flash`, auth `op://Toolkit/opencode-api-key-coding/credential`
- Tool survey + verdict (May 2026): `ops-toolkit/research/2026-05-18-jupyter-ai-assist-landscape.md`
- Track convention: `ops-toolkit/learning/quantum-computing/CLAUDE.md` (Tech stack)
- Notebook generation shape: `ops-toolkit/learning/quantum-computing/workbooks/_template/`
