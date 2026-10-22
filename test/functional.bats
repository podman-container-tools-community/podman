#!/usr/bin/env bats
# Functional tests for a built podman with the runtime helpers of a distribution.
# hack/functional-test.sh runs them inside a privileged container, as root and as a
# rootless user. IMAGE is the image the tests run.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  export IMAGE="${IMAGE:-quay.io/libpod/alpine:latest}"
  export SOCK="unix://${XDG_RUNTIME_DIR:-/run}/podman-test.sock"
  podman pull -q "${IMAGE}" >/dev/null

  # Bridge network with DNS (netavark, aardvark-dns) and a port published by podman,
  # served by busybox nc.
  podman network create testnet >/dev/null
  podman run -d --name web --network testnet -p 8080:8080 "${IMAGE}" \
    sh -c 'while true; do printf "HTTP/1.0 200 OK\r\n\r\nok\n" | nc -l -p 8080; done' >/dev/null

  # API service for podman-remote; fd 3 closed so bats does not wait for it.
  podman system service -t 0 "${SOCK}" 3>&- &
  echo "$!" >"${BATS_FILE_TMPDIR}/service.pid"
}

teardown_file() {
  kill "$(cat "${BATS_FILE_TMPDIR}/service.pid")" 2>/dev/null || true
  podman pod rm -f -t 0 testpod >/dev/null 2>&1 || true
  podman rm -f -t 0 web >/dev/null 2>&1 || true
  podman network rm -f testnet >/dev/null 2>&1 || true
}

@test "info reports seccomp" {
  run -0 --separate-stderr podman info --format '{{.Host.Security.SECCOMPEnabled}}'
  expect_output true
}

@test "run echo" {
  run -0 --separate-stderr podman run --rm "${IMAGE}" echo hello
  expect_output hello
}

@test "seccomp filter mode 2" {
  run -0 --separate-stderr podman run --rm "${IMAGE}" grep -E '^Seccomp:\s+2' /proc/self/status
}

@test "bridge network with DNS" {
  run -0 --separate-stderr podman run --rm --network testnet "${IMAGE}" \
    wget -q -T 5 -O - http://web:8080/
  expect_output ok
}

@test "published port" {
  run -0 curl -s --retry 5 --retry-connrefused --retry-delay 1 http://127.0.0.1:8080/
  expect_output ok
}

@test "pod" {
  run -0 --separate-stderr podman pod create --name testpod
  run -0 --separate-stderr podman run --rm --pod testpod "${IMAGE}" echo in-pod
  expect_output in-pod
  run -0 --separate-stderr podman pod rm -f -t 0 testpod
}

@test "build" {
  printf 'FROM %s\nRUN echo built > /built\n' "${IMAGE}" >"${BATS_TEST_TMPDIR}/Containerfile"
  run -0 --separate-stderr podman build -q -t localhost/built "${BATS_TEST_TMPDIR}"
  run -0 --separate-stderr podman run --rm localhost/built cat /built
  expect_output built
  run -0 --separate-stderr podman rmi localhost/built
}

@test "quadlet generates unit" {
  mkdir "${BATS_TEST_TMPDIR}/quadlet" "${BATS_TEST_TMPDIR}/units"
  printf '[Container]\nImage=%s\n' "${IMAGE}" >"${BATS_TEST_TMPDIR}/quadlet/test.container"
  user=()
  if [[ "$(id -u)" != 0 ]]; then user=(--user); fi
  QUADLET_UNIT_DIRS="${BATS_TEST_TMPDIR}/quadlet" run -0 /usr/libexec/podman/quadlet "${user[@]}" "${BATS_TEST_TMPDIR}/units"
  grep -q '^ExecStart=/usr/bin/podman run' "${BATS_TEST_TMPDIR}/units/test.service"
}

@test "podman-remote via API service" {
  for _ in $(seq 50); do
    if podman-remote --url "${SOCK}" info >/dev/null 2>&1; then break; fi
    sleep 0.2
  done
  run -0 --separate-stderr podman-remote --url "${SOCK}" run --rm "${IMAGE}" echo remote
  expect_output remote
}
