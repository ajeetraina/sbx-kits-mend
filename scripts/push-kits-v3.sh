#!/usr/bin/env bash
# Build and push the Kit v3 mixins (v3/mend-guardrails, v3/mend-ai-security) to
# Docker Hub. A v3 kit is an ordinary OCI image: BuildKit reads each descriptor's
# `# syntax=docker/sandbox-kit:3` line, pulls the kit frontend, validates the
# descriptor, builds the overlay and attaches the descriptor to the manifest.
#
#   ./scripts/push-kits-v3.sh                          # push both kits
#   DOCKERHUB_NAMESPACE=me ./scripts/push-kits-v3.sh   # push to another namespace
#   PUSH=0 ./scripts/push-kits-v3.sh                   # build only, into OCI layouts
#   KITS="mend-guardrails" ./scripts/push-kits-v3.sh   # push a subset
#
# The v3 kit directories live under v3/ (v3/mend-guardrails, v3/mend-ai-security).
#
# This is the v3 counterpart to the v2 .github/workflows/publish.yml (which runs
# `sbx kit push` on the spec.yaml kits). Both the v2 and v3 kits stay published:
# a v3 mixin only composes onto v3 workloads, a v2 mixin only onto v2 agents.
#
# NOTE ON TAGS: the v3 kits reuse the existing Docker Hub image names the v2
# publish workflow used (mend-guardrails-kit, mend-ai-security-kit) and push both
# :latest and a :<version> pin read from each descriptor's version: field (a bare
# :latest says nothing about the build). Do not run the v2 publish against the
# same :latest afterward — it would overwrite these with v2 images.
set -euo pipefail

# Default namespace is the Docker Hub user (ajeetraina777), not the GitHub name.
namespace="${DOCKERHUB_NAMESPACE:-${DOCKER_NAMESPACE:-ajeetraina777}}"
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
push="${PUSH:-1}"
platforms="${PLATFORMS:-linux/amd64,linux/arm64}"

command -v docker >/dev/null 2>&1 || { echo "push-kits-v3: docker not found." >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "push-kits-v3: docker buildx not available." >&2; exit 1; }

# Read the descriptor's own `version:` so the pinned tag says what the image is.
kit_version() {
  sed -n 's/^version:[[:space:]]*"\{0,1\}\([0-9][^"]*\)"\{0,1\}[[:space:]]*$/\1/p' "$1"
}

# publish KIT_DIR DESCRIPTOR IMAGE_NAME "TAG[ TAG...]"
publish() {
  local kit_dir="$1" descriptor="$2" image_name="$3"; shift 3
  local tags=("$@")
  local image="docker.io/$namespace/$image_name"
  local version; version="$(kit_version "$kit_dir/$descriptor")"
  [ -n "$version" ] || { echo "push-kits-v3: $descriptor has no version: field" >&2; exit 1; }

  local args=()
  for t in "${tags[@]}"; do
    args+=(-t "$image:$t" -t "$image:$t-$version")
  done

  if [ "$push" = "1" ]; then
    docker buildx build "$kit_dir" -f "$kit_dir/$descriptor" \
      --platform "$platforms" --push --provenance=true "${args[@]}"
    echo "Pushed $image_name ${tags[*]} (and -$version pins) from $kit_dir"
  else
    local layout="/tmp/sbx-kit-${image_name}-layout"
    rm -rf "$layout"
    docker buildx build "$kit_dir" -f "$kit_dir/$descriptor" \
      -t "$image_name:${tags[0]}-$version" \
      --output "type=oci,dest=$layout,tar=false"
    echo "Built $image_name ${tags[0]} $version into $layout"
    echo "  kit-tck validate --layout $layout ${tags[0]}-$version"
  fi
}

# Which kits to publish (space-separated kit directory names under v3/).
KITS="${KITS:-mend-guardrails mend-ai-security}"
for kit in $KITS; do
  case "$kit" in
    mend-guardrails)  publish "$repo_root/v3/mend-guardrails"  mend-guardrails.yaml  mend-guardrails-kit  latest ;;
    mend-ai-security) publish "$repo_root/v3/mend-ai-security" mend-ai-security.yaml mend-ai-security-kit latest ;;
    *) echo "push-kits-v3: unknown kit '$kit'" >&2; exit 1 ;;
  esac
done

if [ "$push" = "1" ]; then
  echo
  echo "Compose one onto a v3 workload, e.g.:"
  echo "  sbx run docker/sbx-kit-shell:1.0.0 --kit docker.io/$namespace/mend-ai-security-kit:latest ."
fi
