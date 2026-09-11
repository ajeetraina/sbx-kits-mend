# Mend CLI credential design — findings & drafts

Status: **investigation**. This documents how the Mend CLI authenticates, why
the kit's shipped `apiKey` credential is likely ineffective, and two candidate
redesigns. Nothing here is wired into `spec.yaml` yet — the `‹CONFIRM›` values
must be captured from a completed `mend auth login` first.

## What the CLI actually does (evidence from the binary, v26.8.2-hf1)

`strings` on the installed `mend` binary shows:

| Signal | Value |
|---|---|
| User-key login endpoint | `/login/accessToken`, `/apis/v2/login` |
| SSO / device login | `/login/openId`, `OAuthDeviceCode` |
| Token / config store | `~/.mend/config/settings.json` (config pkg: `config.Auth` / `AuthGeneral` / `AuthSAST`, base dir `MEND_BASE_DIR`) |
| Token response shape | custom — only `token_type` is a standard OAuth field (no `access_token` / `refresh_token` / `expires_in`) |
| Auth env vars | `MEND_URL`, `MEND_EMAIL`, `MEND_USER_KEY`, `MEND_ORGANIZATION` (+ `MEND_SAST_*` for `mend code`) |
| Debug switch | `MEND_DEBUG_AUTH=true` (prints the auth request/response) |

Two conclusions:

1. Mend authenticates with a **login handshake** — it POSTs email + user key to
   `/login/accessToken` and gets back a token it stores in `settings.json`. The
   key travels in the **request body**, not an `Authorization` header.
2. SSO orgs (e.g. `@docker.com`) use the **OpenID device-code flow**
   (`mend auth login` → browser approval), not a static user key.

## Why the shipped credential block is likely ineffective

`spec.yaml` currently declares:

```yaml
credentials:
  - service: mend
    apiKey:
      name: MEND_USER_KEY
      inject:
        - { domain: saas.mend.io, scheme: bearer }
        - { domain: api-saas.mend.io, scheme: bearer }
```

`apiKey` injection adds an `Authorization: Bearer <key>` **header** on egress.
But Mend doesn't read a bearer header — it sends the user key in the login POST
**body**. So the proxy-managed header is ignored and the container's
`MEND_USER_KEY=proxy-managed` sentinel reaches Mend unswapped → "authenticate
first". Confirmed empirically: all four env vars set correctly still fail.

`sbx secret set-custom` has the same limitation — its help states it replaces
the placeholder **"in the request headers"**, so it cannot swap a value carried
in the body either.

## Delivery mechanisms and whether they work for Mend

| Mechanism | Works for Mend CLI? | Trade-off |
|---|---|---|
| **Direct env** (`-e MEND_USER_KEY=<key>`) | ✅ yes (user-key login) | Real key is readable inside the sandbox |
| **OAuth device login** (`mend auth login`) | ✅ yes (SSO orgs) | Interactive browser approval; not automatable |
| `apiKey` header inject (shipped) | ❌ no | header ≠ body |
| `set-custom` placeholder | ❌ no (header-only) | header ≠ body |

**Recommendation:** default the kit to the **direct-env** path (documented,
with the in-container-key caveat), and support **OAuth device login** for SSO
orgs. Only revisit a proxy-managed static credential if Mend adds header-based
auth or a body-swap lands in `sbx`.

---

## Draft A — `oauth:` block (SSO device-login flow)

Fill every `‹CONFIRM›` from a completed login before wiring this in.

```yaml
credentials:
  - service: mend
    description: "Mend login — OpenID/device (SSO)"
    required: false
    oauth:
      tokenEndpoint:
        host: api-saas.mend.io          # ‹CONFIRM host›  (MEND_DEBUG_AUTH prints the real one)
        path: /login/accessToken        # ‹CONFIRM path›  binary: /login/accessToken, /login/openId (SSO)
      sentinels:
        accessToken: mend-oat-proxy-managed
        refreshToken: mend-ort-proxy-managed   # ‹CONFIRM› drop if Mend issues no refresh token
      responseFields:                    # Mend returns a custom JSON shape (only token_type is standard)
        accessToken: "‹CONFIRM›"         # e.g. "accessToken" / "jwtToken"  (from MEND_DEBUG_AUTH response body)
        refreshToken: "‹CONFIRM›"        # or remove with the sentinel above
        expiresIn: "‹CONFIRM›"           # e.g. "expiresIn" / "exp"
      credentialFile:
        path: "~/.mend/config/settings.json"   # confirmed from binary
        structure:                       # ‹CONFIRM whole shape› — match your real settings.json
          auth:
            accessToken: "{{.AccessToken}}"
            # refreshToken: "{{.RefreshToken}}"
            # expiresAt:   "{{.ExpiresAt}}"

permissions:
  network:
    allow: ["*.mend.io", mend.io, saas.mend.io, api-saas.mend.io]
```

Caveat: the initial device approval is interactive, so even with this block the
first `mend auth login` needs a human. The block only lets the proxy manage the
stored tokens/refresh after that.

## Draft B — `set-custom` recipe (header-swap; **only if** Mend uses a header)

Included for completeness. This is a **runtime command**, not a spec change, and
only works if `MEND_DEBUG_AUTH` shows the key going out in a **header** (per the
binary it goes in the body, so expect this NOT to work — confirm first):

```bash
sbx secret set-custom -g \
  --host '*.mend.io' \
  --env MEND_USER_KEY \
  --placeholder "mend-{rand}" \
  --value "$MEND_USER_KEY"
```

## Draft C — direct env (works today; recommended default)

No spec change; the real key is passed at run time and read by the CLI's own
login. The trade-off is that the key is present inside the sandbox.

```bash
sbx run claude --kit docker.io/ajeetraina777/mend-ai-security-kit:latest \
  -e MEND_URL="https://saas.mend.io" \
  -e MEND_EMAIL="you@example.com" \
  -e MEND_USER_KEY="<user-key>" \
  -e MEND_ORGANIZATION="<org-uuid>" \
  ~/path/to/project
# inside: mend ai scan --directory .
```

---

## To finalize the design, capture from one completed login

```bash
mend auth login                                    # complete the browser/device approval
cat ~/.mend/config/settings.json                   # -> credentialFile.structure (REDACT the token value)
MEND_DEBUG_AUTH=true mend ai scan --directory . 2>&1 | grep -iE 'POST|host|header|body|token|status' | head
```

Those two outputs pin down: the token endpoint host/path, whether the key is in
a header or body, the response field names, and the `settings.json` shape — i.e.
every `‹CONFIRM›` above. Once we have them, we pick Draft A (oauth) or Draft C
(direct-env default) and wire it into `spec.yaml`.
