#!/usr/bin/env bash
# Exercises a built podman with the runtime helpers of a current distribution:
#   hack/functional-test.sh <dist dir>
# Starts a privileged Fedora container (needs docker and network access to quay.io),
# installs conmon, crun, netavark, aardvark-dns and passt there, puts the amd64
# binaries from <dist dir> in place and runs the tests as root and rootless.
set -euo pipefail

FEDORA_IMAGE="${FEDORA_IMAGE:-registry.fedoraproject.org/fedora:43}"
IMAGE=quay.io/libpod/alpine:latest

if [[ "$1" != --inside ]]; then
  # Anonymous volumes keep container storage off the overlay root filesystem.
  exec docker run --rm --privileged --cgroupns=private \
    -v "$(realpath "$1"):/dist:ro" \
    -v "$(realpath "$0"):/functional-test.sh:ro" \
    -v /var/lib/containers -v /home \
    "${FEDORA_IMAGE}" /functional-test.sh --inside
fi

echo "+ installing runtime helpers" >&2
dnf install -y -q --setopt=install_weak_deps=False \
  catatonit conmon crun netavark aardvark-dns passt containers-common shadow-utils jq >/dev/null
install -m 755 /dist/podman_linux_amd64_v1/podman /usr/bin/podman
install -m 755 /dist/podman-remote_linux_amd64_v1/podman-remote /usr/bin/podman-remote
install -D -m 755 /dist/rootlessport_linux_amd64_v1/rootlessport /usr/libexec/podman/rootlessport
install -D -m 755 /dist/quadlet_linux_amd64_v1/quadlet /usr/libexec/podman/quadlet

# No systemd in this container: cgroupfs and file-based events and logs.
mkdir -p /etc/containers/containers.conf.d
cat >/etc/containers/containers.conf.d/50-test.conf <<'EOF'
[containers]
log_driver = "k8s-file"
[engine]
cgroup_manager = "cgroupfs"
events_logger = "file"
EOF

tests() {
  set -euo pipefail
  run() {
    echo "+ podman $*" >&2
    podman "$@"
  }
  run version
  run info --format json | jq -e '.host.security.seccompEnabled' >/dev/null
  run pull -q "${IMAGE}" >/dev/null
  test "$(run run --rm "${IMAGE}" echo hello)" = hello

  # The default seccomp profile is applied (mode 2: filter).
  run run --rm "${IMAGE}" grep -E '^Seccomp:\s+2' /proc/self/status

  # Bridge network with DNS (netavark, aardvark-dns) and a published port.
  run network create testnet >/dev/null
  run run -d --name web --network testnet -p 8080:8080 "${IMAGE}" httpd -f -p 8080 >/dev/null
  { run run --rm --network testnet "${IMAGE}" wget -q -O /dev/null -T 5 http://web:8080/ 2>&1 || true; } | grep -q 404
  curl -s -o /dev/null -w '%{http_code}' --retry 5 --retry-connrefused http://127.0.0.1:8080/ | grep -qx 404
  run rm -f -t 0 web >/dev/null
  run network rm testnet >/dev/null

  # Pods and builds.
  run pod create --name testpod >/dev/null
  test "$(run run --rm --pod testpod "${IMAGE}" echo in-pod)" = in-pod
  run pod rm -f -t 0 testpod >/dev/null
  ctx="$(mktemp -d)"
  printf 'FROM %s\nRUN echo built > /built\n' "${IMAGE}" >"${ctx}/Containerfile"
  run build -q -t localhost/built "${ctx}" >/dev/null
  test "$(run run --rm localhost/built cat /built)" = built
  run rmi localhost/built >/dev/null

  # Quadlet generates a unit from a .container file.
  mkdir -p "${ctx}/quadlet" "${ctx}/units"
  printf '[Container]\nImage=%s\n' "${IMAGE}" >"${ctx}/quadlet/test.container"
  user=()
  if [[ "$(id -u)" != 0 ]]; then user=(--user); fi
  QUADLET_UNIT_DIRS="${ctx}/quadlet" /usr/libexec/podman/quadlet "${user[@]}" "${ctx}/units"
  grep -q '^ExecStart=/usr/bin/podman run' "${ctx}/units/test.service"
  rm -rf "${ctx}"

  # podman-remote against the API service.
  sock="unix://${XDG_RUNTIME_DIR:-/run}/podman-test.sock"
  podman system service -t 0 "${sock}" &
  service=$!
  for _ in $(seq 50); do
    if podman-remote --url "${sock}" info >/dev/null 2>&1; then break; fi
    sleep 0.2
  done
  test "$(podman-remote --url "${sock}" run --rm "${IMAGE}" echo remote)" = remote
  kill "${service}"
  wait "${service}" || true
}

echo "=== root" >&2
tests

echo "=== rootless" >&2
useradd -m tester
su - tester -c "export IMAGE=${IMAGE} XDG_RUNTIME_DIR=/tmp/run-tester && mkdir -p -m 700 \$XDG_RUNTIME_DIR && $(declare -f tests); tests"

echo "functional tests passed" >&2
