# Mend Docker Sandbox kits

Two [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **`kind: mixin`** kits for Mend:

| Kit | What it adds |
|---|---|
| [`mend-ai-security/`](./mend-ai-security/) | Mend CLI + `mend ai scan` (AI-BOM / Shadow AI). Works on any agent. |
| [`mend-guardrails/`](./mend-guardrails/) | Loopback `mend-guardrails-server` on Codex / OpenAI-compatible agents (`OPENAI_BASE_URL`). Inspects prompt bodies (secrets, PII, prompt injection) and exposes `/v1/guard/*` plus `mend-guard-text` for MCP/tool-text checks. |

The kits use **different secrets**. They are not interchangeable.

| Variable | Kit | What it is |
|---|---|---|
| `MEND_KEY` | Guardrails | [Activation key](https://docs.mend.io/platform/latest/mend-ai-runtime-protection#MendAIRuntimeProtection-InstallMendAIGuardrails) from the Mend platform (Integrations → Mend AI Guardrails). Parsed **inside** the VM. |
| `MEND_USER_KEY` | AI Security (CLI) | Service User key, with `MEND_EMAIL` (+ `MEND_URL` / `MEND_ORGANIZATION`). Or skip env vars and run `mend auth login` inside the sandbox. |

Do **not** put either secret in kit `args:` / `--kit-arg`. When composing both kits, do not declare `credentials.apiKey.inject` on `*.mend.io` (see the credentials docs). See [`mend-ai-security/docs/CREDENTIALS.md`](./mend-ai-security/docs/CREDENTIALS.md) and [`mend-guardrails/docs/CREDENTIALS.md`](./mend-guardrails/docs/CREDENTIALS.md).

Compose them on Codex. `MEND_KEY` is passed **once** at runtime (Guardrails). The CLI can still `mend auth login` inside the VM:

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<guardrails-activation-key>" \
  .
```

Both products authenticated at launch (CLI env-var path):

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

Git URL form (pin `ref` to a 40-hex SHA):

```bash
sbx run codex \
  --kit "git+https://github.com/ajeetraina/sbx-kits-mend.git#ref=<40-hex-sha>&dir=mend-ai-security" \
  --kit "git+https://github.com/ajeetraina/sbx-kits-mend.git#ref=<40-hex-sha>&dir=mend-guardrails" \
  -e MEND_KEY="<guardrails-activation-key>" \
  .
```

Published OCI artifacts (pin by digest, not `:latest`):

```bash
sbx run codex \
  --kit docker.io/ajeetraina777/mend-ai-security-kit:latest \
  --kit docker.io/ajeetraina777/mend-guardrails-kit:latest \
  -e MEND_KEY="<guardrails-activation-key>" \
  .
```

The Guardrails mixin sets `requires.agent: codex` and rewrites `OPENAI_BASE_URL`
to the loopback inspector. Drop `requires.agent` in a fork to reuse that rewrite
on another OpenAI-compatible agent.

## License

Apache-2.0. "Mend", the Mend CLI, and Mend Guardrails are products of Mend.io; these kits only install and configure them inside a sandbox.
