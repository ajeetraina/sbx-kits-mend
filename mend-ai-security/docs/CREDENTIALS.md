# How Mend credentials work in this kit

The sandbox has a feature that can hide credentials from the code running inside
it (the "secret manager" / proxy). We tried to use it for Mend, but it can't
work for one fundamental reason:

**It can't reach Mend's key.** The feature only substitutes credentials that ride
on the *outside* of a network request (the header). Mend sends its key on the
*inside* (the request body), where the feature never touches it. So the real key
never reaches Mend and login fails.

We proved this live (see [the test matrix](#we-verified-this-live) below). The
sandbox proxy **does** intercept Mend's traffic and even holds the correct key,
but because it only swaps **headers**, what Mend reads from the **body** is still
the placeholder, so auth is rejected. Hand the *same* key to the *same* intercepted
sandbox via `-e` (which lands it in the body) and login succeeds. So the
interception itself is fine: **header-only substitution is the sole blocker.**

So we pass the key directly with `-e`, which works today. The only trade-off is
that the key is readable inside the sandbox which is fine, since the sandbox is
already isolated.

We'll revisit the secret manager if a future `sbx` learns to swap credentials
in the request body.

## The whole story in one picture

![Mend credential flow: why we use -e instead of the secret manager](../assets/credential-flow.svg)

Top to bottom: the secret manager works for a normal service (it swaps the key
into the request **header**); the same approach fails for Mend because Mend reads
its key from the request **body**, which the header swap never touches; so we pass
the key with `-e` and let Mend log itself in. (The proxy's TLS interception is
*not* the problem; auth succeeds through the same MITM when the key rides in the
body. Verified live.) Source:
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
  browser runs on the host, so the redirect never arrives. Use "Enter credentials
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
| Token response shape | custom; only `token_type` is standard OAuth (no `access_token` / `refresh_token` / `expires_in`) |
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
That's the "outside of the envelope," and Mend never reads it, because its key
is in the body. The placeholder reaches Mend unswapped, and login fails.
Confirmed empirically: all four env vars set correctly still failed when the
`apiKey` block was declared.

`sbx secret set-custom` has the same limit: its help says it replaces the
placeholder *"in the request headers"*, so it can't swap a body value either.

Declaring `apiKey.inject` on `*.mend.io` (or targeting those hosts with
`set-custom`) does make the proxy **TLS-intercept** them: it presents its own
`Docker Sandboxes Proxy CA` certificate instead of Mend's. **But that interception
does not break anything.** The `mend` CLI (like `curl`) trusts the proxy CA, the
TLS handshake completes, and auth proceeds normally. The *only* failure is that
the header swap misses the body. We confirmed this directly: with the proxy
holding the correct key and intercepting `*.mend.io`, auth **fails** when the key
is delivered via the header swap (placeholder in env) and **succeeds** when the
same key is delivered via `-e` (real key in env, lands in body), same sandbox,
same MITM. So we removed the `credentials:` block: it adds interception that can
never deliver the credential, with no upside.

### What works and what doesn't

| Mechanism | Works for Mend? | Trade-off |
|---|---|---|
| **Direct env** (`-e MEND_USER_KEY=<key>`) | ✅ yes | Real key is readable inside the sandbox |
| **OAuth device login** (`mend auth login`) | ✅ yes (SSO orgs) | Interactive browser approval; not automatable |
| `apiKey` header inject | ❌ no | header ≠ body |
| `set-custom` placeholder | ❌ no | header-only |

---

## We verified this live

Tested on macOS host + `sbx` v0.48.0, kit built from `./mend-ai-security`, Mend CLI
v26.9.2-hf1 in-sandbox, using a dedicated Mend **Service User** (bypasses SSO).
The probe is `mend auth info` (authenticates without needing scan permissions).

| # | Sandbox config | How the key is delivered | Result |
|---|---|---|---|
| 1 | Clean (proxy passthrough, real Mend cert) | `-e` → env → request **body** | ✅ `Logged in as sbx-cred-test` |
| 2b | **MITM active** (`set-custom` on `*.mend.io`, proxy CA cert) | `-e` → env → request **body** | ✅ `Logged in as sbx-cred-test` |
| 2a | **MITM active**, proxy holds the *correct* key | **secret-injection** → placeholder in env, proxy swaps it into the **header** | ❌ `the specified Mend credentials are invalid` |

The decisive comparison is **2b vs 2a**: identical sandbox, identical active MITM,
the proxy holding the identical real key. The *only* difference is where the
credential lands: body (`-e`) succeeds, header (secret-injection) fails. That
isolates the cause to header-vs-body and rules out the TLS interception as the
culprit.

Supporting observations:

- **Passthrough vs MITM, by certificate.** As shipped (no secret targeting
  `*.mend.io`), `curl -v https://api-saas.mend.io` shows Mend's real cert
  (`issuer: Amazon RSA 2048 M01`). Add a `set-custom` secret for `*.mend.io` and
  the same request shows `issuer: O=Docker Sandboxes; CN=Docker Sandboxes Proxy CA`,
  proof the proxy flips from CONNECT passthrough to TLS interception when a
  secret targets the host.
- **Interception doesn't break the handshake.** Under that MITM, both `curl` and
  `mend connectivity` report every `*.mend.io` host reachable, and `SSL certificate
  verified via OpenSSL`, so the proxy CA is trusted inside the sandbox.
- **`set-custom` help (v0.48.0)** states it replaces the placeholder *"in the
  request headers"*, matching the observed header-only behavior.
- **Side note (not a credential issue):** the Service User authenticated fine but
  `mend ai scan` returned `403 Access is denied` on project creation, a Mend RBAC
  matter (associate the Service User with a group/role), unrelated to delivery.

---

## If `sbx` ever supports body-level secrets

Two drafts kept on hand for that day.

### Draft A: `oauth:` block (SSO device-login flow)

Fill every `‹CONFIRM›` from a completed login before wiring this in.

```yaml
credentials:
  - service: mend
    description: "Mend login (OpenID/device, SSO)"
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
        structure:                       # ‹CONFIRM whole shape›: match your real settings.json
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

### Draft B: `set-custom` recipe (header-swap; only if Mend ever uses a header)

Kept for completeness. This is a **runtime command**, not a spec change, and only
works if `MEND_DEBUG_AUTH` shows the key going out in a **header** (per the binary
it goes in the body, so expect this NOT to work; confirm first):

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
body, the response field names, and the `settings.json` shape, i.e. every
`‹CONFIRM›` above.

---

## Appendix: proposed upstream improvement for `sbx`

The limitation above isn't Mend-specific: **any** CLI that authenticates by sending
its credential in the request **body** (a form/JSON login `POST`) hits the same
wall, because `sbx` secret substitution is header-only. For those tools the only
working path today is `-e`, which places the raw key inside the sandbox, defeating
the "credentials never enter the sandbox" guarantee. The following is a feature
request we intend to raise with the Docker Sandboxes team.

**Title:** Secret substitution is header-only: body-authenticating CLIs (e.g. Mend)
can't keep credentials out of the sandbox.

**Summary.** `sbx` substitutes the placeholder for the real secret **in request
headers** at the proxy. That works for header/API-key auth, but a credential sent
in the request **body** is never swapped, so `-e` (raw key in the sandbox) is the
only option. We'd like body-auth tools to keep credentials out of the sandbox too.

**Evidence (same tests as above).** Using a Mend Service User and `mend auth info`:

| # | Sandbox config | Credential delivery | Result |
|---|---|---|---|
| 1 | Clean (passthrough) | `-e` → env → **body** | ✅ `Logged in` |
| 2b | `set-custom` on `*.mend.io` → **MITM active**, proxy holds the real key | `-e` → env → **body** | ✅ `Logged in` |
| 2a | same MITM, proxy holds the real key | secret-injection → placeholder in env, proxy swaps into **header** | ❌ `credentials invalid` |

2b vs 2a: identical sandbox, identical interception, identical real key in the
proxy. This isolates the cause to header-vs-body. Certificate checks confirm the
MITM itself works (`curl` and `mend` both trust the `Docker Sandboxes Proxy CA` and
authenticate through it); header-only substitution is the sole blocker.

**Requested change (any one):**

1. **Body-aware substitution:** let a custom secret declare the placeholder be
   swapped in the request **body** (JSON path / form field / regex), opt-in per
   secret, same as today's host-targeted interception.
2. **A supported pattern** for body-auth CLIs that still keeps the secret out of the
   sandbox (e.g. a proxy-injected auth-broker sidecar, or a proxy-materialized
   credential file).
3. At minimum, **document the header-only limitation** on `secret set-custom` and in
   the credentials guide so kit authors don't design around a guarantee that doesn't
   apply to body-auth tools.

**Before filing:** confirm the right repo/channel for `sbx` feature requests, and
re-run the repro on the latest `sbx` (v0.49.0-rc was available) in case body
substitution has already landed.
