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

Optional kit args (not secrets). Always pass `MEND_KEY` (platform activation
key). Default `policySource=local` uses this kit's `sandbox.json`; it does not
load the org Default Guardrails Policy. Use `policySource=api` with
`offline=false` for platform policy and AI Runtime dashboard events. Do not
combine `offline=true` with `policySource=api`. `offline=true` only skips
platform registration/telemetry.

```bash
sbx run codex --kit ./mend-guardrails \
  --kit-arg mend-guardrails.offline=true \
  --kit-arg mend-guardrails.policySource=local \
  -e MEND_KEY="<license>" .
```

Stack with the CLI AI-BOM mixin:

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<license>" \
  .
```

Git: `#dir=mend-guardrails`. OCI: `docker.io/ajeetraina777/mend-guardrails-kit`
(pin by digest).

Python **3.11+** is required (upstream package). Install also needs PyPI,
GitHub (spaCy model wheel), Mend downloads, and Hugging Face if models are not
bundled in the wheel.

## License

Apache-2.0 for this kit. Mend Guardrails is a Mend.io product.
