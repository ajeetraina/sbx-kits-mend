# Mend Docker Sandbox kits

Two [Docker Sandboxes](https://docs.docker.com/ai/sandboxes/) mixin kits for Mend:

| Kit | What it adds |
|---|---|
| [`mend-ai-security/`](./mend-ai-security/) | Mend CLI + `mend ai scan` (AI-BOM / Shadow AI). Works on any agent. |
| [`mend-guardrails/`](./mend-guardrails/README.md) | Mend AI Runtime Protection for Codex / OpenAI-compatible agents. Inspects prompts (secrets, PII, prompt injection); optional TUI intercept; `mend-guard-text` for MCP/tool text. |

The kits use **different secrets**. They are not interchangeable.

| Variable | Kit | What it is |
|---|---|---|
| `MEND_KEY` | Guardrails | [Activation key](https://docs.mend.io/platform/latest/mend-ai-runtime-protection#MendAIRuntimeProtection-InstallMendAIGuardrails) from the Mend platform (Integrations → Mend AI Guardrails). |
| `MEND_USER_KEY` | AI Security (CLI) | Service User key, with `MEND_EMAIL` (+ `MEND_URL` / `MEND_ORGANIZATION`). Or skip env vars and run `mend auth login` inside the sandbox. |

Do **not** put either secret in `--kit-arg`. Pass them with `sbx run -e`.
`--kit-arg` values are kit *configuration*: they get baked into the kit layer and
surface in image layers, build cache, logs, and `sbx inspect` — so a secret there
is persisted and visible. `-e` injects values only into the running sandbox at
runtime, never into a stored artifact. Keep `--kit-arg` for non-secret toggles.

Compose them on Codex (`MEND_KEY` once for Guardrails; CLI can still log in inside the VM):

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

Full Guardrails usage (policy modes, TUI intercept, verification): see the
[mend-guardrails README](./mend-guardrails/README.md).

## Kits v3 (schemaVersion 3)

The kits above are the original **v2** `spec.yaml` mixins. A **v3** rewrite of
both lives under [`v3/`](./v3/), expressed as the typed-capability
[Kit v3 descriptor](https://github.com/docker/sandbox-kit-spec):

| v2 (spec.yaml) | v3 descriptor |
|---|---|
| [`mend-ai-security/`](./mend-ai-security/) | [`v3/mend-ai-security/`](./v3/mend-ai-security/) |
| [`mend-guardrails/`](./mend-guardrails/) | [`v3/mend-guardrails/`](./v3/mend-guardrails/) |

Both schemas stay published — **a v3 mixin only composes onto v3 workloads and a
v2 mixin only onto v2 agents**, so nothing existing breaks. A v3 kit is an
ordinary OCI image: `docker buildx` reads the descriptor's
`# syntax=docker/sandbox-kit:3` line, validates it, builds the overlay and
attaches the descriptor to the manifest.

Build/validate locally (no push), or compose onto a v3 shell workload:

```bash
PUSH=0 ./scripts/push-kits-v3.sh                              # build both into OCI layouts
sbx run docker/sbx-kit-shell:1.0.0 --kit ./v3/mend-ai-security .
```

Publishing (both `:latest` and a `:<version>` pin) is `scripts/push-kits-v3.sh`,
run by the [Publish Kits (v3)](./.github/workflows/push-kits-v3.yaml) workflow on
manual dispatch.

## License

Apache-2.0. "Mend", the Mend CLI, and Mend Guardrails are products of Mend.io; these kits only install and configure them inside a sandbox.
