# Mend Guardrails credentials in Docker Sandboxes

Status: **do not proxy-manage Mend credentials**. The kit opens egress and
forwards the **model-provider** `Authorization` sentinel unchanged.

## MEND_KEY (Guardrails license)

The Python SDK / `mend-guardrails-server` **parse `MEND_KEY` inside the VM**
(JWT / Caesar-wrapped license). Get it from the Mend platform:
[Integrations → Mend AI Guardrails → Get Activation Key](https://docs.mend.io/platform/latest/mend-ai-runtime-protection#MendAIRuntimeProtection-InstallMendAIGuardrails).
It is **not** the CLI Service User key (`MEND_USER_KEY`). Entitlement does not
work with Docker's `proxy-managed` sentinel in that environment variable.

Default uses the kit's local `sandbox.json` (`policySource=local`). Pass the
activation key at launch:

```bash
sbx run codex --kit ./mend-guardrails -e MEND_KEY="<license>" .
```

If `MEND_KEY` is unset, `mend-guardrails-sandbox-start` copies
`MEND_GUARDRAILS_KEY` onto `MEND_KEY` for the **server process only** (hosts
that already export a different Mend key). The SDK still reads `MEND_KEY`.

Trade-off: the key is readable inside the sandbox. Scope it to Guardrails.

Do **not** put `MEND_KEY` in `args:` / `--kit-arg` (kit args are not a secret
store).

`offline=true` (`MEND_GUARDRAILS_OFFLINE=true`) skips platform registration and
telemetry. It does **not** switch policy source. **`MEND_KEY` is still
required**. Do not combine `offline=true` with `policySource=api`.

`policySource=api` (and `offline=false`) loads the org policy from the Mend
Platform and is what feeds AI Runtime dashboard/events. On the platform,
default guardrails are off until an admin enables them — that applies to `api`
mode, not to the committed `sandbox.json`.

## Model provider keys (OpenAI / Codex)

The kit sets `OPENAI_BASE_URL=http://127.0.0.1:8787/v1` for the **agent**.
`mend-guardrails-sandbox-start` **unsets** `OPENAI_BASE_URL` (and
`OPENAI_API_KEY`) in the **server** process so the OpenAI SDK upstream is
`https://api.openai.com/v1`, not loopback.

`MEND_GUARDRAILS_FORWARD_HEADERS=Authorization`: the agent sends Docker's
**sentinel**; the server forwards that header; the **host sbx proxy** swaps in
the real key. Mend never sees, stores, or needs the customer's model API key.

Do not set a real `OPENAI_API_KEY` on the guardrails server.

Leave `HTTP_PROXY` / `HTTPS_PROXY` to the sandbox so network policy and
credential inject keep working. This kit does not set those variables.

## Never inject on `*.mend.io`

Declaring `credentials.apiKey.inject` on `*.mend.io` makes the sbx proxy
TLS-intercept those hosts. That breaks the Mend CLI login handshake used by
the `mend-ai-security` mixin (same credentials work on the host). This kit
must remain composable with that mixin: allow-list only, no inject.

Stack both kits with one `MEND_KEY` (Guardrails) at runtime. CLI login is
separate (`mend auth login` or `MEND_EMAIL` + `MEND_USER_KEY`):

```bash
sbx run codex \
  --kit ./mend-ai-security \
  --kit ./mend-guardrails \
  -e MEND_KEY="<guardrails-activation-key>" \
  .
```

See [`../../mend-ai-security/docs/CREDENTIALS.md`](../../mend-ai-security/docs/CREDENTIALS.md).
