# syntax=docker/dockerfile:1
#
# Mend AI Security is a pure content overlay: it ships the Mend CLI as a single
# native binary at /usr/local/bin/mend and carries no ENV.
#
# MIGRATION NOTE: v2 downloaded the CLI in a create-time install hook, arch-
# matched by `uname -m`. v3 bakes it into the overlay instead — it is a static,
# base-independent binary with no create-time input, so moving it into a layer
# removes both the per-create download latency and the install-phase network
# grant. A multi-platform build stage selects the matching binary via TARGETARCH
# (so each published platform carries its own native executable), downloading on
# the build host's arch rather than under emulation. Mend publishes both
# linux_amd64 and linux_arm64 (the arm64 build is undocumented on the download
# page but is a real native aarch64 executable).

FROM --platform=$BUILDPLATFORM curlimages/curl:8.11.1 AS build
ARG TARGETARCH
RUN case "$TARGETARCH" in \
      arm64) plat=linux_arm64 ;; \
      *)     plat=linux_amd64 ;; \
    esac; \
    curl -fsSL "https://downloads.mend.io/cli/$plat/mend" -o /tmp/mend \
    && chmod 0755 /tmp/mend

# The overlay: a single root-owned binary on PATH. No ENV — the v2 kit set none,
# and the CLI authenticates itself with no environment contract (see the kit's
# agent context for the MEND_* auth variables the USER may pass at `sbx run`).
FROM scratch
COPY --from=build /tmp/mend /usr/local/bin/mend
