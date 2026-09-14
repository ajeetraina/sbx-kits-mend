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

The kit policy (`sandbox.json`) enforces **PromptInjection** and **Secret Keys**
on the input stage. That file is used only when you **opt in** to local mode.
After the sandbox is up, a fixture script posts a benign prompt (must be
allowed) and synthetic jailbreak / fake-key text (must be blocked,
`mend-guard-text` exit 2):

```bash
sbx run codex --kit ./mend-guardrails \
  --kit-arg mend-guardrails.policySource=local \
  --kit-arg mend-guardrails.offline=true \
  -e MEND_KEY="<license>" .
```

In the Codex TUI, run it as a **shell** command (prefix `!`). Do **not** paste
it into the prompt box — that sends a model request first.

```text
! bash mend-guardrails/tests/malicious-instructions.sh
```

If the TUI errors with `gpt-5.6-sol` / ChatGPT account, switch model (`/model`)
to one your ChatGPT plan allows (often `gpt-5.6-luna` or `gpt-5.6-terra`) or
use an API key. That failure is from the **model** call, not from Guardrails.

To see Guardrails stop a jailbreak in the agent path, switch model first, then
type the injection as a prompt. The script itself uses `/v1/guard/input` and
does not need a live model reply.

## License

Apache-2.0 for this kit. Mend Guardrails is a Mend.io product.
