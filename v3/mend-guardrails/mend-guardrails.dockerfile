# syntax=docker/dockerfile:1
# check=skip=SecretsUsedInArgOrEnv
# (OPENAI_API_KEY below is the Docker sentinel "proxy-managed", not a real
#  secret — the host proxy swaps the real key on api.openai.com. False positive.)
#
# Mend Guardrails is an env-carrying overlay that also ships the kit's helper
# scripts, the shell agent-env, the /etc/profile.d drop and the local policy.
# It installs no Python package into the image: mend-guardrails[server] lands in
# the COMPOSED base's system Python at create time, via the lifecycle install
# hook in mend-guardrails.yaml (a mixin overlay lands on an unknown base, so
# baking site-packages here would not resolve).
#
# What the recipe DOES carry:
#   - the static runtime environment (ENV), merged onto the composed image;
#   - the helper CLIs under /home/agent/.local/bin/ (curl proxy wrapper,
#     mend-guard-text, mend-guardrails-configure-codex, -sandbox-start,
#     -selftest), shipped executable;
#   - the shell env + /etc/profile.d drop that keep loopback and api.openai.com
#     out of the proxy path;
#   - the local sandbox policy (used only with policySource=local/offline).
#
# MIGRATION NOTE: v2 shipped this tree via the sbx-kits-contrib files/home/
# convention (everything under files/home/ mirrored into /home/agent/) and an
# install hook chmod'd the binaries. v3 has no such convention — content rides
# in this overlay, executable, so that chmod step is gone. The files/ here are a
# copy of ../../mend-guardrails/files/ (a kit's build context is rooted at its
# own directory and cannot reach a sibling's tree), so the two copies must be
# kept in sync.

# Stage the content with the right ownership. The chown starts exactly at
# /home/agent so /home itself stays root-owned — the overlay home-ownership
# invariant is /home = root, /home/agent = uid 1000. /etc content stays root.
FROM busybox:1 AS build
COPY files/home/ /out/home/agent/
COPY files/etc/ /out/etc/
RUN chown -R 1000:1000 /out/home/agent \
    && chmod 0755 /out/home/agent/.local/bin/*

# The overlay: FROM scratch keeps the layer purely the content above plus this
# ENV, which rides in the image config. The frontend stages the descriptor as a
# content layer alongside it.
FROM scratch
COPY --from=build /out /

# MIGRATION NOTE: v2 set these as environment.variables; static ones move to ENV
# here (on the final stage so they merge at assembly). The arg-driven ones
# (MEND_GUARDRAILS_OFFLINE / _POLICY_SOURCE / _INTERCEPT_TUI) are NOT set here —
# they resolve at create via the args' env: in mend-guardrails.yaml. Do not set
# NO_PROXY / HTTP(S)_PROXY here: HTTP(S)_PROXY is sandbox-managed, and the agent
# NO_PROXY for api.openai.com/loopback is appended by agent-env.sh (shells) and
# the PATH curl wrapper; the server startup script strips it for its own egress.
# OPENAI_API_KEY is the Docker sentinel, swapped for the real key by the host
# proxy on api.openai.com — not a real secret (hence no credential@1).
ENV OPENAI_BASE_URL="http://127.0.0.1:8787/v1" \
    OPENAI_API_KEY="proxy-managed" \
    MEND_GUARDRAILS_FORWARD_HEADERS="Authorization" \
    MEND_GUARDRAILS_POLICY_DIR="/home/agent/.mend-guardrails/policies" \
    MEND_GUARDRAILS_DEFAULT_CONFIG_ID="sandbox" \
    MEND_GUARDRAILS_INSTANCE_NAME="docker-sandbox"
