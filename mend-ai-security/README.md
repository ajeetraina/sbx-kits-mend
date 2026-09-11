# Mend AI Security

A Docker Sandboxes **mixin** that installs the [Mend CLI](https://docs.mend.io/platform/latest/download-the-mend-cli)
and enables **AI-security scanning** inside the sandbox — discover AI models,
frameworks, and system prompts in your workspace ("Shadow AI") and generate an
**AI-BOM** (AI Bill of Materials) with `mend ai scan`.

Compose it onto any agent (Claude Code, Codex, …) to give that agent the
ability to run Mend AI security scans against the code it is working on.

## What it adds

- The `mend` CLI on `PATH` (`/usr/local/bin/mend`).
- `mend ai scan` — AI usage discovery + AI-BOM generation.
- Egress allow-list for `*.mend.io` so scans and CLI auto-update work under a
  `deny-all` network policy.
- A proxy-managed `MEND_USER_KEY` credential — the container never sees the raw
  key.
- A `MEND_URL` default (`https://saas.mend.io`) plus agent instructions on how
  to run scans and authenticate.

The same CLI also provides `mend dep` (SCA), `mend code` (SAST), and
`mend image` (container) scanning.

## Usage

This is a mixin, so run it with `--kit` on top of a base agent. Pick one
reference form:

**Published OCI artifact (recommended):**

```bash
sbx run claude --kit docker.io/ajeetraina777/mend-ai-security-kit:latest .
```

**Git URL:**

```bash
sbx run claude \
  --kit "git+https://github.com/ajeetraina/sbx-kits-mend.git#ref=<40-hex-sha>&dir=mend-ai-security" .
```

**Local path:**

```bash
sbx run claude --kit ./mend-ai-security/ .
```

## Authentication

The Mend CLI authenticates with a service user. Provide these when you launch
the sandbox:

| Variable | Secret? | Notes |
|---|---|---|
| `MEND_URL` | no | Tenant URL. Preset to `https://saas.mend.io`; override for EU/IL/legacy (e.g. `https://saas-eu.mend.io`). |
| `MEND_EMAIL` | no | Service-user (or personal) email. |
| `MEND_USER_KEY` | **yes** | Service-user key. Proxy-managed — bind it in `~/.config/sbx/credentials.yaml`. |
| `MEND_ORGANIZATION` | no | Organization UUID (needed for some scopes). |

`MEND_USER_KEY` is delivered through the sbx credential proxy: in the container
it is the literal `proxy-managed`, and the proxy swaps in the real key on
outbound requests to Mend. Bind it under `service: mend` in your
`~/.config/sbx/credentials.yaml`.

Pass the non-secret coordinates at run time, for example:

```bash
sbx run claude \
  --kit docker.io/sbx/mend-ai-security-kit:latest \
  -e MEND_EMAIL="svc@example.com" \
  -e MEND_ORGANIZATION="<org-uuid>" .
```

> The published OCI artifact is built and pushed to
> `docker.io/ajeetraina777/mend-ai-security-kit` by
> [`.github/workflows/publish.yml`](../.github/workflows/publish.yml) on every
> push to `main`. Consumers should pin by digest (`@sha256:...`) rather than
> `:latest` — see the workflow summary for the digest of each build.

Then, inside the sandbox:

```bash
mend connectivity --mend-url="$MEND_URL"   # verify auth/network
mend ai scan --directory .                 # AI security scan + AI-BOM
```

## Limitations

- **linux_amd64 only — will not run on Apple Silicon.** Mend does not publish a
  native Linux arm64 CLI build, so this kit installs the `linux_amd64` binary.
  On an arm64 host (e.g. an Apple Silicon Mac) the sandbox is an aarch64 microVM
  and the binary fails with `Exec format error`. Emulation is not a workaround
  here either — the microVM has no `qemu-user-static` and `binfmt_misc` is not
  mounted. Run this kit on an **amd64 host** (Intel/AMD, or amd64 CI/cloud),
  where it installs and runs cleanly.

## License

Apache-2.0. "Mend" and the Mend CLI are products of Mend.io; this kit only
installs and configures the vendor CLI.
