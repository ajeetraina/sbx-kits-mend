# How Mend credentials work in this kit

The kit ships **no proxy-managed credential**. It just opens
network access to `*.mend.io` and lets the Mend CLI log itself in. You pass your
credentials at run time with `-e`.

## The short version

The sandbox has a feature that can hide credentials from the code running inside
it (the "secret manager" / proxy). We tried to use it for Mend, but it doesn't
work — for two reasons:

1. **It can't reach Mend's key.** The feature only hides keys that ride on the
   *outside* of a network request (the header). Mend sends its key on the
   *inside* (the request body), where the feature can't touch it. So Mend never
   sees the real key and login fails.

2. **Turning it on actually breaks login.** To do its job, the feature has to
   intercept Mend's traffic — and that interference alone makes Mend reject us,
   even with correct credentials. The same key works fine outside the sandbox.

So we pass the key directly with `-e`, which works today. The only trade-off is
that the key is readable inside the sandbox — which is fine, since the sandbox is
already isolated.

We'll revisit the secret manager if a future `sbx` learns to swap credentials
in the request body.

## The whole story in one picture

![Mend credential flow: why we use -e instead of the secret manager](../assets/credential-flow.svg)

Top to bottom: the secret manager works for a normal service (it swaps the key
into the request **header**); the same approach fails for Mend two ways (Mend's
key is in the **body**, and the proxy's interception breaks the login handshake);
so we pass the key with `-e` and let Mend log itself in. Source:
[`credential-flow.mmd`](../assets/credential-flow.mmd).

## How to run it (works today)

```bash
sbx run claude --kit docker.io/ajeetraina777/mend-ai-security-kit:latest \
  -e MEND_URL="https://saas.mend.io" \
  -e MEND_EMAIL="you@example.com" \
  -e MEND_USER_KEY="<user-key>" \
  -e MEND_ORGANIZATION="<org-uuid>" \
  ~/path/to/project
# inside the sandbox:
mend ai scan --directory .
```

A few things to know:

- Use a **Service User** email + key, not a personal user key. Personal keys are
  rejected under SSO (and Docker's org is SSO-enforced).
- You can also run `mend auth login` → **"Enter credentials manually"** and paste
  the same Service User email + key. The token gets cached in
  `~/.mend/config/settings.json`.
- **Browser login does not work** inside the sandbox. It redirects to
  `http://127.0.0.1:<port>`, but that port lives inside the sandbox while your
  browser runs on the host — the redirect never arrives. Use "Enter credentials
  manually" instead.

---

## Why the secret manager can't help (the details)

Everything below is the investigation trail, kept for reference.

### What the Mend CLI actually does

From `strings` on the installed `mend` binary (v26.8.2-hf1):

| Signal | Value |
|---|---|
| User-key login endpoint | `/login/accessToken`, `/apis/v2/login` |
| SSO / device login | `/login/openId`, `OAuthDeviceCode` |
| Token / config store | `~/.mend/config/settings.json` |
| Token response shape | custom — only `token_type` is standard OAuth (no `access_token` / `refresh_token` / `expires_in`) |
| Auth env vars | `MEND_URL`, `MEND_EMAIL`, `MEND_USER_KEY`, `MEND_ORGANIZATION` (+ `MEND_SAST_*` for `mend code`) |
| Debug switch | `MEND_DEBUG_AUTH=true` (prints the auth request/response) |

Two takeaways:

1. Mend logs in with a **handshake**: it POSTs email + user key to
   `/login/accessToken` and gets back a token it stores in `settings.json`. The
   key travels in the **request body**, not in an `Authorization` header.
2. SSO orgs (e.g. `@docker.com`) use the **OpenID device-code flow**
   (`mend auth login` → browser approval), not a static user key.

### Why the proxy / secret manager fails

The sandbox's secret feature works by intercepting outbound traffic and swapping
the real value into the **request header** (e.g. `Authorization: Bearer <key>`).
That's the "outside of the envelope" — and Mend never reads it, because its key
is in the body. The placeholder reaches Mend unswapped, and login fails.
Confirmed empirically: all four env vars set correctly still failed when the
`apiKey` block was declared.

`sbx secret set-custom` has the same limit — its help says it replaces the
placeholder *"in the request headers"*, so it can't swap a body value either.

On top of that, declaring `apiKey.inject` on `*.mend.io` makes the proxy
**TLS-intercept** those hosts. That interception mangles Mend's login handshake
and returns `Unauthorized` *inside* the sandbox, while the same credentials
succeed on the host (no proxy in the path). So we removed the `credentials:`
block entirely.

### What works and what doesn't

| Mechanism | Works for Mend? | Trade-off |
|---|---|---|
| **Direct env** (`-e MEND_USER_KEY=<key>`) | ✅ yes | Real key is readable inside the sandbox |
| **OAuth device login** (`mend auth login`) | ✅ yes (SSO orgs) | Interactive browser approval; not automatable |
| `apiKey` header inject | ❌ no | header ≠ body |
| `set-custom` placeholder | ❌ no | header-only |

---

## If `sbx` ever supports body-level secrets

Two drafts kept on hand for that day.

### Draft A — `oauth:` block (SSO device-login flow)

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

Caveat: the first device approval is interactive, so even with this block the
initial `mend auth login` needs a human. The block only lets the proxy manage the
stored tokens/refresh afterward.

### Draft B — `set-custom` recipe (header-swap; only if Mend ever uses a header)

Kept for completeness. This is a **runtime command**, not a spec change, and only
works if `MEND_DEBUG_AUTH` shows the key going out in a **header** (per the binary
it goes in the body, so expect this NOT to work — confirm first):

```bash
sbx secret set-custom -g \
  --host '*.mend.io' \
  --env MEND_USER_KEY \
  --placeholder "mend-{rand}" \
  --value "$MEND_USER_KEY"
```

### To finalize either draft, capture from one completed login

```bash
mend auth login                                    # complete the browser/device approval
cat ~/.mend/config/settings.json                   # -> credentialFile.structure (REDACT the token value)
MEND_DEBUG_AUTH=true mend ai scan --directory . 2>&1 | grep -iE 'POST|host|header|body|token|status' | head
```

Those outputs pin down the token endpoint, whether the key goes in a header or
body, the response field names, and the `settings.json` shape — i.e. every
`‹CONFIRM›` above.
