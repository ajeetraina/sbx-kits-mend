# Mend Guardrails

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **`kind: mixin`**
kit that runs [`mend-guardrails-server`](https://www.mend.io/runtime-guardrails/)
([docs](https://docs.mend.io/platform/latest/mend-ai-runtime-protection)) on
**loopback** and points Codex at it with `OPENAI_BASE_URL`. Prompt bodies are
inspected (secrets, PII, prompt injection) before they reach the model. The
customer's model API key stays a Docker **sentinel**; the host proxy swaps it
after Mend forwards `Authorization`.

`requires.agent: codex`. Drop that field to reuse the same `OPENAI_BASE_URL`
rewrite on another OpenAI-compatible agent.

## Usage

```bash
sbx run codex --kit ./mend-guardrails -e MEND_KEY="<license>" .
```

Optional kit args (not secrets). Always pass `MEND_KEY` (the [platform
activation key](https://docs.mend.io/platform/latest/mend-ai-runtime-protection#MendAIRuntimeProtection-InstallMendAIGuardrails),
not a CLI Service User key).

**Default (online):** `policySource=api` and `offline=false` load the org
policy from the Mend Platform and report AI Runtime dashboard events. Enable
the detectors you need (for example Prompt Injection / Jailbreak and Secret
Keys) in the platform policy before testing blocks.

**Local policy:** opt in to the kit's `sandbox.json` with `policySource=local`.
Startup sets `offline=true` so the SDK can load local policy files. Use
`offline=true` only with `policySource=local`, not with `policySource=api`.

```bash
sbx run codex --kit ./mend-guardrails \
  --kit-arg mend-guardrails.policySource=local \
  --kit-arg mend-guardrails.offline=true \
  -e MEND_KEY="<license>" .
```

Stack with the CLI AI-BOM mixin. `MEND_KEY` is Guardrails only; the CLI uses
`mend auth login` inside the VM, or pass `MEND_USER_KEY` separately (it is not
the same secret):

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<guardrails-activation-key>" \
  .
```

Both products authenticated at launch:

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<guardrails-activation-key>" \
  -e MEND_URL="https://saas.mend.io" \
  -e MEND_EMAIL="<service-user-email>" \
  -e MEND_USER_KEY="<service-user-key>" \
  -e MEND_ORGANIZATION="<org-uuid>" \
  .
```

Git: `#dir=mend-guardrails`. OCI: `docker.io/ajeetraina777/mend-guardrails-kit`
(pin by digest).

Python **3.11+** is required (upstream package). Install also needs PyPI,
GitHub (spaCy model wheel), Mend downloads, and Hugging Face if models are not
bundled in the wheel. `MEND_KEY` must be set at install time (`sbx run -e`).
First `sbx run --kit` can take several minutes while wheels and models
download.

## Verify prompts are inspected

`tests/malicious_openai_app.py` is an ordinary OpenAI client: it builds
`OpenAI(base_url=OPENAI_BASE_URL)` and calls `chat.completions.create`. It does
not call `/v1/guard/*` or `mend-guard-text` — inspection happens because the
kit pointed `OPENAI_BASE_URL` at the loopback server.

Default kit mode is **online** (`policySource=api`). Configure the Mend
Platform org policy to **Block** the detectors under test before you run the
fixture.

```bash
sbx run codex --kit ./mend-guardrails -e MEND_KEY="<license>" .
```

In the Codex TUI, run it as a **shell** command (prefix `!`):

```text
! python3 mend-guardrails/tests/malicious_openai_app.py
```

A policy block is HTTP **400** with `detail.error=guardrail_enforcement_triggered`.
Each case prints `IN →` (the prompt) and `OUT ←` (the model reply on success,
or the error body). Override the model with `OPENAI_MODEL` if needed.

The app uses the `openai` SDK when `OPENAI_API_KEY` is set. Without it, it
falls back to plain HTTP and sends **no** `Authorization` header so the sbx
host proxy can inject the real credential. Leave `OPENAI_API_KEY` unset (or
use the sandbox sentinel) rather than inventing a bearer token.

If the TUI errors with a model or ChatGPT account message, switch model
(`/model`) to one your plan allows or use an API key. That response is from
the **model** provider.

To run the loopback server yourself for debugging:

```bash
mend-guardrails-server --host 127.0.0.1 --port 8788 \
  --policy-source api --log-level debug
```

Point the fixture with `OPENAI_BASE_URL`.

## Scan MCP and tool results

Use the Guard API helpers when you want to check untrusted tool or MCP text
against the same policy:

```bash
mend-guard-text input <<'EOF'
<tool or MCP result text>
EOF
```

Exit 0 means allowed (JSON on stdout; use `sanitized_text` if present). Exit 2
means blocked. `mend-guard-text output` applies the output-stage policy to
candidate replies.

## License

Apache-2.0 for this kit. Mend Guardrails is a Mend.io product.
