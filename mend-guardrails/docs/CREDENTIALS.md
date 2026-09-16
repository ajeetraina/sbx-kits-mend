# Mend Guardrails credentials in Docker Sandboxes

This kit opens egress to Mend and related package hosts. It does **not**
proxy-manage Mend credentials. The model-provider `Authorization` sentinel is
forwarded unchanged so the host sbx proxy can inject the real key.

## MEND_KEY (Guardrails activation key)

The Python SDK / `mend-guardrails-server` read `MEND_KEY` **inside the VM**.
Get it from the Mend platform:
[Integrations → Mend AI Guardrails → Get Activation Key](https://docs.mend.io/platform/latest/mend-ai-runtime-protection#MendAIRuntimeProtection-InstallMendAIGuardrails).
It is **not** the CLI Service User key (`MEND_USER_KEY`). Pass the real
activation key with `sbx run -e` — do not use Docker's `proxy-managed`
sentinel for this variable.

The activation key is required at **install** time as well as for SDK
entitlement. Kit install exits early when `MEND_KEY` is unset.

Default is online: `policySource=api` and `offline=false` (platform policy).
Pass the activation key at launch:

```bash
sbx run codex --kit ./mend-guardrails -e MEND_KEY="<license>" .
```

Opt in to the kit `sandbox.json` (local policy with offline mode):

```bash
sbx run codex --kit ./mend-guardrails \
  --kit-arg mend-guardrails.policySource=local \
  --kit-arg mend-guardrails.offline=true \
  -e MEND_KEY="<license>" .
```

If `MEND_KEY` is unset, `mend-guardrails-sandbox-start` copies
`MEND_GUARDRAILS_KEY` onto `MEND_KEY` for the **server process only** (hosts
that already export a different Mend key). The SDK still reads `MEND_KEY`.

Do **not** put `MEND_KEY` in `args:` / `--kit-arg` (kit args are not a secret
store).

`offline=true` (`MEND_GUARDRAILS_OFFLINE=true`) runs without platform
registration and telemetry. **`MEND_KEY` is still required**. Use
`offline=true` with `policySource=local`. Use `policySource=api` with
`offline=false` (the kit default).

`policySource=api` loads the org policy from the Mend Platform and feeds AI
Runtime dashboard events. Enable the detectors you need in the platform
policy for online mode.

## Model provider keys (OpenAI / Codex)

The kit sets `OPENAI_BASE_URL=http://127.0.0.1:8787/v1` for the **agent**.
`mend-guardrails-sandbox-start` **unsets** `OPENAI_BASE_URL` in the **server**
process so the OpenAI SDK upstream is `https://api.openai.com/v1`.

Keep a non-empty `OPENAI_API_KEY` in the server process (the OpenAI client
validates credentials at construction). Startup keeps whatever the sandbox
provided and otherwise exports the placeholder
`mend-guardrails-forwarded-per-request`.

With `MEND_GUARDRAILS_FORWARD_HEADERS=Authorization`, the agent sends Docker's
**sentinel**; the server forwards that header; the **host sbx proxy** swaps in
the real key. Mend never sees, stores, or needs the customer's model API key.

Do not set a real `OPENAI_API_KEY` on the guardrails server.

Leave `HTTP_PROXY` / `HTTPS_PROXY` to the sandbox so network policy and
credential inject keep working. This kit does not set those variables.

## Composing with `mend-ai-security`

Do not declare `credentials.apiKey.inject` on `*.mend.io`. TLS intercept on
those hosts interferes with the Mend CLI login handshake used by the
`mend-ai-security` mixin. This kit allow-lists Mend hosts only (no inject) so
both mixins can stack.

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
