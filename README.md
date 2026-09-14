# Mend Docker Sandbox kits

Two [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) **`kind: mixin`** kits for Mend:

| Kit | What it adds |
|---|---|
| [`mend-ai-security/`](./mend-ai-security/) | Mend CLI + `mend ai scan` (AI-BOM / Shadow AI). Works on any agent. |
| [`mend-guardrails/`](./mend-guardrails/) | Loopback `mend-guardrails-server` on Codex / OpenAI-compatible agents (`OPENAI_BASE_URL`). Inspects prompt bodies (secrets, PII, prompt injection) and exposes `/v1/guard/*` for cooperative MCP/tool-text checks. |

Compose them on Codex:

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<mend-guardrails-license>" \
  .
```

Git URL form (pin `ref` to a 40-hex SHA):

```bash
sbx run codex \
  --kit "git+https://github.com/ajeetraina/sbx-kits-mend.git#ref=<40-hex-sha>&dir=mend-ai-security" \
  --kit "git+https://github.com/ajeetraina/sbx-kits-mend.git#ref=<40-hex-sha>&dir=mend-guardrails" \
  -e MEND_KEY="<mend-guardrails-license>" \
  .
```

Published OCI artifacts (pin by digest, not `:latest`):

```bash
sbx run codex \
  --kit docker.io/ajeetraina777/mend-ai-security-kit:latest \
  --kit docker.io/ajeetraina777/mend-guardrails-kit:latest \
  -e MEND_KEY="<mend-guardrails-license>" \
  .
```

`MEND_KEY` is required for the Guardrails mixin (activation key from the Mend
platform; parsed **inside** the VM). It is **not** proxy-managed. Do **not**
declare `credentials.apiKey.inject` on `*.mend.io` — that TLS-intercepts Mend
and breaks CLI login. See
[`mend-ai-security/docs/CREDENTIALS.md`](./mend-ai-security/docs/CREDENTIALS.md)
and [`mend-guardrails/docs/CREDENTIALS.md`](./mend-guardrails/docs/CREDENTIALS.md).

The Guardrails mixin sets `requires.agent: codex` and rewrites `OPENAI_BASE_URL`
to the loopback inspector. Drop `requires.agent` in a fork to reuse that rewrite
on another OpenAI-compatible agent.

Instruction-file integrity (Go `MAI-AC-*` / `.sbxenv.yaml` / shared skills) is **not** in these kits yet.

## License

Apache-2.0. "Mend", the Mend CLI, and Mend Guardrails are products of Mend.io; these kits only install and configure them inside a sandbox.
