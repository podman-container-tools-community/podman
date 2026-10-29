#!/usr/bin/env bats
# Tests for the podman image, run on the Docker host by hack/image-test.sh. IMAGE is the
# image under test, BASE the image the tests run in it, IMAGE_USER root or podman.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export BASE="${BASE:-quay.io/libpod/alpine:latest}"
  export IMAGE_USER="${IMAGE_USER:-root}"
  export CONTAINER="podman-image-test-${IMAGE_USER}"
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
  docker run -d --rm --privileged --name "${CONTAINER}" --user "${IMAGE_USER}" \
    -p 127.0.0.1:18080:8080 "${IMAGE}" sleep infinity >/dev/null

  # Bridge network with DNS (netavark, aardvark-dns) and a port published through both
  # podman and Docker, served by busybox nc.
  in_image network create testnet >/dev/null
  in_image run -d --name web --network testnet -p 8080:8080 "${BASE}" \
    sh -c 'while true; do printf "HTTP/1.0 200 OK\r\n\r\nok\n" | nc -l -p 8080; done' >/dev/null
}

teardown_file() {
  docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
}

in_image() {
  docker exec "${CONTAINER}" podman "$@"
}

@test "podman --version without entrypoint" {
  run -0 --separate-stderr docker run --rm "${IMAGE}" podman --version
  [[ "${output}" == "podman version "* ]]
}

# hack/generate-sbom.sh; releases built before it have none.
@test "SBOM of the static C libraries" {
  docker exec "${CONTAINER}" test -f /usr/share/sbom/podman/static-libraries.spdx.json ||
    skip "release without static-libraries.spdx.json"
  run -0 --separate-stderr docker exec "${CONTAINER}" cat /usr/share/sbom/podman/static-libraries.spdx.json
  for name in musl libseccomp sqlite; do
    [[ "${output}" == *"\"name\": \"${name}\""* ]]
  done
}

@test "rootless mode matches the user" {
  run -0 --separate-stderr in_image info --format '{{.Host.Security.Rootless}}'
  expect_output "$([[ "${IMAGE_USER}" == podman ]] && echo true || echo false)"
}

@test "run echo" {
  run -0 --separate-stderr in_image run --rm "${BASE}" echo ok
  expect_output ok
}

@test "bridge network with DNS" {
  run -0 --separate-stderr in_image run --rm --network testnet "${BASE}" \
    wget -q -T 5 -O - http://web:8080/
  expect_output ok
}

@test "published port through podman and Docker" {
  run -0 curl -s --retry 5 --retry-connrefused --retry-delay 1 http://127.0.0.1:18080/
  expect_output ok
}

# podman build (buildah) mounts an overlay over the build context, with its upper
# directory in /var/tmp.
@test "build" {
  docker exec "${CONTAINER}" sh -c \
    'mkdir -p /tmp/ctx && printf "FROM %s\nRUN echo built > /built\n" "$1" >/tmp/ctx/Containerfile' sh "${BASE}"
  run -0 --separate-stderr in_image build -q -t localhost/built /tmp/ctx
  run -0 --separate-stderr in_image run --rm localhost/built cat /built
  expect_output built
}

# Upstream's documented form; podman's --security-opt label=disable and unmask=ALL
# correspond to Docker's seccomp and AppArmor settings here.
@test "rootless without --privileged: run and build" {
  [[ "${IMAGE_USER}" == podman ]] || skip "rootless only"
  # shellcheck disable=SC2016 # expanded by the shell in the image
  run -0 --separate-stderr docker run --rm --user podman --device /dev/fuse \
    --security-opt seccomp=unconfined --security-opt apparmor=unconfined "${IMAGE}" \
    sh -c 'set -e
      podman run --rm "$1" echo ok
      mkdir /tmp/ctx
      printf "FROM %s\nRUN echo built > /built\n" "$1" >/tmp/ctx/Containerfile
      podman build -q -t localhost/built /tmp/ctx >/dev/null
      podman run --rm localhost/built cat /built' sh "${BASE}"
  expect_output "ok
built"
}
