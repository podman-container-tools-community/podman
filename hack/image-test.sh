#!/usr/bin/env bash
# Builds the image from a goreleaser dist directory, laid out like goreleaser's dockers_v2
# context, and runs test/image.bats against it as root and rootless:
#   hack/image-test.sh <dist dir>
# Builds every architecture found in <dist dir> (no emulation needed) and tests the
# host's. Needs Docker with buildx, curl, and network access to quay.io, github.com
# (bats, hack/install-bats.sh) and dl-cdn.alpinelinux.org.
set -euo pipefail

dist="$(realpath "$1")"
repo="$(cd "$(dirname "$0")/.." && pwd)"
image=localhost/podman:test
host="$(docker version --format '{{.Server.Arch}}')"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/ctx/.build/packaging"
cp -r "${repo}/packaging/image" "${work}/ctx/.build/packaging/"
platforms=()
for arch in amd64 arm64; do
  for id in podman podman-remote quadlet rootlessport; do
    binary=("${dist}/${id}_linux_${arch}_"*/"${id}")
    [[ -f "${binary[0]}" ]] || continue 2
    mkdir -p "${work}/ctx/linux/${arch}"
    cp "${binary[0]}" "${work}/ctx/linux/${arch}/"
  done
  platforms+=("linux/${arch}")
done

# As goreleaser does (build_args in .goreleaser.yaml): netavark 2 from edge for Podman 6.
version="$(jq -r .version "${dist}/metadata.json")"
edge=""
if ((${version%%.*} >= 6)); then
  edge=true
fi
build() {
  docker buildx build --quiet --build-arg NETAVARK_FROM_EDGE="${edge}" \
    -f "${repo}/Dockerfile" "$@" "${work}/ctx" >/dev/null
}
for platform in "${platforms[@]}"; do
  if [[ "${platform}" != "linux/${host}" ]]; then
    echo "+ building ${platform}" >&2
    build --platform "${platform}"
  fi
done
echo "+ building linux/${host}" >&2
build --load --platform "linux/${host}" -t "${image}"

"${repo}/hack/install-bats.sh" "${work}/bats"
status=0
for user in root podman; do
  echo "=== image as ${user}" >&2
  IMAGE="${image}" IMAGE_USER="${user}" \
    "${work}/bats/bin/bats" --formatter tap "${repo}/test/image.bats" || status=1
done

docker image rm "${image}" >/dev/null
exit "${status}"
