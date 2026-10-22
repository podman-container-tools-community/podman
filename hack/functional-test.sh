#!/usr/bin/env bash
# Exercises a built podman with matching runtime helpers:
#   hack/functional-test.sh <dist dir>
# Starts a privileged container of upstream's quay.io/podman/stable image for the
# same version, minor or major (needs docker and network access to quay.io), which
# brings conmon, crun, netavark, aardvark-dns and passt in versions that release was
# built for. Without such a tag it falls back to Fedora 43 for Podman 5 and Fedora
# rawhide for newer releases, since Podman 6 needs netavark 2. Puts the amd64 binaries
# from <dist dir> in place and runs test/functional.bats as root and rootless, with the
# bats from mise.toml on PATH (mise install), mounted into the container. test/signing.bats
# runs after it and pushes to a registry:3 container on a Docker network shared only with
# the test container.
set -euo pipefail

IMAGE=quay.io/libpod/alpine:latest

if [[ "$1" != --inside ]]; then
  dist="$(realpath "$1")"
  version="$("${dist}/podman_linux_amd64_v1/podman" --version | awk '{print $3}')"
  major="${version%%.*}"
  base=registry.fedoraproject.org/fedora:rawhide
  if [[ "${major}" == 5 ]]; then
    base=registry.fedoraproject.org/fedora:43
  fi
  for tag in "v${version}" "v${version%.*}" "v${major}"; do
    if docker pull -q "quay.io/podman/stable:${tag}" >/dev/null; then
      base="quay.io/podman/stable:${tag}"
      break
    fi
  done
  repo="$(cd "$(dirname "$0")/.." && pwd)"
  # bats-core's root: bin/bats and the libexec/ and lib/ it loads. bats is plain bash, so
  # the host's copy runs in the container too.
  bats="$(dirname "$(dirname "$(realpath "$(command -v bats)")")")"
  if [[ ! -d "${bats}/libexec/bats-core" ]]; then
    echo "no bats-core installation at ${bats} (mise shims? use mise exec or activate)" >&2
    exit 1
  fi
  echo "+ testing podman ${version} in ${base}" >&2
  # Named after this process, so only what this run created is removed.
  name="podman-functional-$$"
  trap 'docker rm -f -v "${name}-registry" >/dev/null 2>&1 || true
    docker network rm "${name}" >/dev/null 2>&1 || true' EXIT
  docker network create "${name}" >/dev/null
  docker run -d --rm --name "${name}-registry" --network "${name}" --network-alias registry \
    docker.io/library/registry:3 >/dev/null
  # Anonymous volumes keep container storage, and the overlays podman build (buildah)
  # mounts over the build context in /var/tmp, off the overlay root filesystem.
  docker run --rm --privileged --cgroupns=private --network "${name}" \
    -v "${dist}:/dist:ro" \
    -v "$(realpath "$0"):/functional-test.sh:ro" \
    -v "${repo}/test:/tests:ro" -v "${bats}:/bats:ro" \
    -v /var/lib/containers -v /home -v /var/tmp \
    "${base}" /functional-test.sh --inside
  exit
fi

REGISTRY=registry:5000

echo "+ installing runtime helpers (no-op where the image has them)" >&2
dnf install -y -q --setopt=install_weak_deps=False \
  catatonit conmon crun netavark aardvark-dns passt containers-common shadow-utils util-linux \
  gnupg2 jq >/dev/null
# Fedora's base image carries newuidmap and newgidmap without their file capabilities,
# which rootless podman needs; quay.io/podman/stable has them already.
rpm --setcaps shadow-utils
# As in the image (see Dockerfile): pasta from /usr/libexec/podman, where Ubuntu's
# AppArmor profiles for the host's pasta and passt do not attach.
for bin in pasta pasta.avx2; do
  if [[ -e "/usr/bin/${bin}" ]]; then
    ln -f "$(realpath "/usr/bin/${bin}")" "/usr/libexec/podman/${bin}"
  fi
done
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

podman version
status=0

echo "=== root" >&2
IMAGE="${IMAGE}" REGISTRY="${REGISTRY}" /bats/bin/bats --formatter tap /tests/functional.bats /tests/signing.bats || status=1

echo "=== rootless" >&2
useradd -m tester
su - tester -c "export IMAGE=${IMAGE} REGISTRY=${REGISTRY} XDG_RUNTIME_DIR=/tmp/run-tester &&
  mkdir -p -m 700 \$XDG_RUNTIME_DIR && /bats/bin/bats --formatter tap /tests/functional.bats /tests/signing.bats" || status=1

exit "${status}"
