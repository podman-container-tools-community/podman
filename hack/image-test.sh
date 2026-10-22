#!/usr/bin/env bash
# Builds the image from a goreleaser dist directory, laid out like goreleaser's dockers_v2
# context, and uses it as root and rootless:
#   hack/image-test.sh <dist dir>
# Builds every architecture found in <dist dir> (no emulation needed) and runs the host's.
# Needs Docker with buildx, curl, and network access to quay.io and dl-cdn.alpinelinux.org.
set -euo pipefail

dist="$(realpath "$1")"
repo="$(cd "$(dirname "$0")/.." && pwd)"
base="${BASE_IMAGE:-quay.io/libpod/alpine:latest}"
image=localhost/podman:test
name=podman-image-test
host="$(docker version --format '{{.Server.Arch}}')"
work="$(mktemp -d)"
trap 'docker rm -f "${name}" >/dev/null 2>&1 || true; rm -rf "${work}"' EXIT

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

in_image() {
  echo "+ [image as ${user}] podman $*" >&2
  docker exec "${name}" podman "$@"
}

for user in root podman; do
  docker run -d --rm --privileged --name "${name}" --user "${user}" -p 127.0.0.1:18080:8080 \
    --entrypoint sleep "${image}" infinity >/dev/null
  test "$(in_image info --format '{{.Host.Security.Rootless}}')" = "$([[ "${user}" == podman ]] && echo true || echo false)"
  test "$(in_image run --rm "${base}" echo ok)" = ok

  # Bridge network with DNS (netavark, aardvark-dns) and a port published through both
  # podman and Docker, served by busybox nc.
  in_image network create testnet >/dev/null
  in_image run -d --name web --network testnet -p 8080:8080 "${base}" \
    sh -c 'while true; do printf "HTTP/1.0 200 OK\r\n\r\nok\n" | nc -l -p 8080; done' >/dev/null
  test "$(in_image run --rm --network testnet "${base}" wget -q -T 5 -O - http://web:8080/)" = ok
  test "$(curl -s --retry 5 --retry-connrefused --retry-delay 1 http://127.0.0.1:18080/)" = ok
  docker rm -f "${name}" >/dev/null
done

docker image rm "${image}" >/dev/null
echo "image tests passed" >&2
