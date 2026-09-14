# Mend Guardrails

A [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **`kind: mixin`**
kit that runs `mend-guardrails-server` ([product](https://www.mend.io/runtime-guardrails/), [docs](https://docs.mend.io/platform/latest/mend-ai-runtime-protection))
on **loopback** and points Codex at it with `OPENAI_BASE_URL`. Prompt bodies are
inspected (secrets, PII, prompt injection) before they reach the model. The
customer's model API key stays a Docker **sentinel**; the host proxy swaps it
after Mend forwards `Authorization`.

`requires.agent: codex`. Drop that field to reuse the same rewrite on another
OpenAI-compatible agent. There is **no** Anthropic `/v1/messages` shim in this
kit.

## Usage

```bash
sbx run codex --kit ./mend-guardrails -e MEND_KEY="<license>" .
```

Optional kit args (not secrets). Always pass `MEND_KEY` (the [platform
activation key](https://docs.mend.io/platform/latest/mend-ai-runtime-protection#MendAIRuntimeProtection-InstallMendAIGuardrails),
not a CLI Service User key). Default is **online**: `policySource=api` and
`offline=false` load the org policy from the Mend Platform (AI Runtime
dashboard events). Platform default guardrails are off until an admin enables
them. Opt in to the kit's `sandbox.json` with `policySource=local` (startup
forces `offline=true`; the SDK does not load local files in online mode). Do
not combine `offline=true` with `policySource=api`.

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
bundled in the wheel. First `sbx run --kit` can take several minutes; the TUI
stays on the pip step while wheels/models download.

## Check that malicious instructions are blocked

Default kit mode is **online** (`policySource=api`). The fixture assumes the
Mend Platform org policy is already set to **Block** the input detectors you
care about (Prompt Injection / Jailbreak, Secret Keys). It does not use
`sandbox.json`.

After the sandbox is up, the app posts a benign prompt (must be allowed) and
synthetic jailbreak / fake-key text (must be blocked: HTTP 200,
`"allowed": false`) to `/v1/guard/input`. That is the same org policy Codex
uses, without calling the upstream model. Chat Completions is not a reliable
block probe here: the server runs input checks **in parallel with** the LLM
call, so a jailbreak can 500 at the provider instead of returning HTTP 400.

The app does **not** require a shell pipe to `mend-guard-text`.

```bash
sbx run codex --kit ./mend-guardrails -e MEND_KEY="<license>" .
```

In the Codex TUI, run it as a **shell** command (prefix `!`). Do **not** paste
the jailbreak text into the prompt box.

```text
! python3 mend-guardrails/tests/malicious_app.py
```

Each case prints the text sent in (`IN →`) and the guardrails response
(`OUT ←`). Long values are trimmed; set `MEND_TEST_FULL=1` for the full body.

The app refuses to run if the sandbox was started with `policySource=local` or
`offline=true`. Blocked cases never need a live model reply.

If the TUI errors with `gpt-5.6-sol` / ChatGPT account, switch model (`/model`)
to one your ChatGPT plan allows (often `gpt-5.6-luna` or `gpt-5.6-terra`) or
use an API key. That failure is from the **model** call, not from Guardrails.

## Check the transparent path (no Mend call in the app)

`tests/malicious_openai_app.py` is an ordinary OpenAI client: it builds
`OpenAI(base_url=OPENAI_BASE_URL)` and calls `chat.completions.create` with
the same payloads. It never calls `/v1/guard/*`, `mend-guard-text`, or adds a
`guardrails` block — inspection happens only because the kit pointed
`OPENAI_BASE_URL` at the loopback server.

```text
! python3 mend-guardrails/tests/malicious_openai_app.py
```

A block is HTTP **400** with `detail.error=guardrail_enforcement_triggered`.
Each case prints `IN →` (the prompt) and `OUT ←` (the model reply on 200, or
the error body), so you can see exactly what reached the model and what came
back. Override the model with `OPENAI_MODEL` if the upstream rejects the
default. On this endpoint input guardrails run **in parallel** with the model
call, so upstream failures (401/429/5xx) also land here.

The app uses the `openai` SDK only when `OPENAI_API_KEY` is set. Without it,
it falls back to plain HTTP and sends **no** `Authorization` header, so the
sbx host proxy can still inject the real credential. Sending an invented
bearer token breaks that swap.

A benign prompt can also come back `401`/`429` when the sandbox has no usable
provider credential. Policy allowed it, the provider refused, so the fixture
reports that as allowed rather than failing.

HTTP **500** is an unmapped server-side exception, not a verdict. Point either
fixture at another server to read its log — `OPENAI_BASE_URL` for
`malicious_openai_app.py`, `MEND_GUARDRAILS_URL` for `malicious_app.py`:

```bash
mend-guardrails-server --host 127.0.0.1 --port 8788 \
  --policy-source api --log-level debug
```

## License

Apache-2.0 for this kit. Mend Guardrails is a Mend.io product.
