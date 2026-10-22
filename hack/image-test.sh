#!/usr/bin/env bash
# Builds the image from a goreleaser dist directory or a directory with the release
# archives (hack/build-image.sh --load) and runs
# test/image.bats against it, as root and as the podman user:
#   hack/image-test.sh <dist dir|release dir>
# Needs Docker with buildx, curl, jq, bats from mise.toml on PATH (mise install) and
# network access to quay.io, Docker Hub and dl-cdn.alpinelinux.org.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
export IMAGE=localhost/podman:test
"${repo}/hack/build-image.sh" --load "$1" "${IMAGE}"

status=0
for user in root podman; do
  echo "=== image as ${user}" >&2
  IMAGE_USER="${user}" bats --formatter tap "${repo}/test/image.bats" || status=1
done
docker image rm "${IMAGE}" >/dev/null
exit "${status}"
