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

NBI configs live in `~/.jupyter/nbi/`. The active one is `config.json`; presets are `config.claude.json` and `config.ollama.json`. Three fish helpers swap them:

| Helper | Preset | Use for |
|---|---|---|
| `nbi-claude` | chat=`claude-opus-4-7`, inline=`claude-haiku-4-5-20251001` | Learning notebooks, public content, anything fine to send to Anthropic. Default. |
| `nbi-local` | chat=`qwen3.6:35b-a3b` on Mini, inline=`qwen2.5-coder` | Trading, family-office, anything that must not leave the machine. |
| `nbi-status` | (read-only) | Print which preset is active. |

After running `nbi-claude` or `nbi-local`, the change applies on the **next** `jlab` invocation. The currently-running server keeps the preset it started with.

Decision rule:

- Current working directory is `learning/`, `experiments/`, `tools/`, `research/`, or a public repo → `nbi-claude`.
- Current working directory is `tieubao/trading`, `tieubao/family-office`, `dfoundation`, or any path with client / NDA data → `nbi-local`.
- User explicitly names the provider → honor that.
- Unsure → ask once.

## Gotchas

**1. Ollama on Mini is bound to the personal Tailscale identity.** The Mini has two tailnet names: `mac-mini-danang` (100.98.16.107, tagged Dwarves device) and `mac-mini` (100.118.23.42, personal `nntruonghan@` device). Ollama listens on `mac-mini` only. The `jlab` wrapper hard-codes `http://mac-mini:11434`; don't second-guess and don't rewrite to the tagged name.

**2. NBI inline-completion-via-Ollama is hardcoded to coder models.** The list: `qwen2.5-coder`, `deepseek-coder-v2`, `codestral`, `starcoder2`, `codellama:7b-code`. None of the user's general Mini models (qwen3.6, deepseek-r1, qwen3-vl, deepseek-ocr, llama3.2) qualify. Until `qwen2.5-coder` is pulled, `nbi-local` gives chat + cell-level but no inline tab-complete. Pull when local inline matters:

```fish
ssh mac-mini-danang 'ollama pull qwen2.5-coder'   # ~5GB
```

**3. Edit `.py`, not `.ipynb`.** Per SPEC-011 in `learning/quantum-computing/CLAUDE.md`, notebooks are jupytext-paired. The `.py:percent` is the committed source; the `.ipynb` is a gitignored build artifact. JupyterLab's autosave keeps both in sync once you open the `.ipynb`, but for Claude Code edits, modify the `.py` and run `jupytext --sync <file>.py`.

## Reference

- Wrapper: `~/.config/fish/functions/jlab.fish`
- Helpers: `~/.config/fish/functions/nbi-{claude,local,status}.fish`
- Presets: `~/.jupyter/nbi/config.{claude,ollama}.json`
- Active: `~/.jupyter/nbi/config.json`
- Tool survey + verdict (May 2026): `ops-toolkit/research/2026-05-18-jupyter-ai-assist-landscape.md`
- Track convention: `ops-toolkit/learning/quantum-computing/CLAUDE.md` (Tech stack)
- Notebook generation shape: `ops-toolkit/learning/quantum-computing/workbooks/_template/`
