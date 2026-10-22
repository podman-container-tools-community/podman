# syntax=docker/dockerfile:1

# The static release binaries with the runtime helpers from Alpine, configured like
# upstream's quay.io/podman/stable image.
# Pinned by index digest so image builds stay reproducible; Renovate bumps it (both FROM
# lines name the same image).
FROM alpine:3.24@sha256:71e9b7bae160ba167fa17414401b94cbcdaf3c32feeab9298bd794a2a0614c35 AS base

# Everything that has to run happens here, on the build host's platform, so no emulation
# is needed: apk installs the target architecture's packages into a copy of the target's
# file system, without their scripts (a modprobe for fuse-overlayfs and triggers that the
# base image has already run). Only what changed ends up in /delta, so the final image
# adds one layer on top of Alpine's.
FROM --platform=$BUILDPLATFORM alpine:3.24@sha256:71e9b7bae160ba167fa17414401b94cbcdaf3c32feeab9298bd794a2a0614c35 AS delta
ARG TARGETARCH
# Podman 6 needs netavark 2, and 3.24 ships 1.17: true takes netavark and aardvark-dns
# from the edge community repository instead.
ARG NETAVARK_FROM_EDGE=""
SHELL ["/bin/ash", "-euo", "pipefail", "-c"]
# Versions come from the Alpine release the base image pins; apk cannot pin older ones,
# because the repositories only keep the newest.
# hadolint ignore=DL3018
RUN apk add --no-cache findutils tar
COPY --from=base / /rootfs/
# hadolint ignore=DL3018
RUN <<EOF
case "${TARGETARCH}" in
  amd64) arch=x86_64 ;;
  arm64) arch=aarch64 ;;
  *) echo "unsupported architecture ${TARGETARCH}" >&2; exit 1 ;;
esac
touch /marker
netavark="netavark aardvark-dns"
if [ "${NETAVARK_FROM_EDGE}" = true ]; then
  echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /rootfs/etc/apk/repositories
  netavark="netavark@edge aardvark-dns@edge"
fi
# shadow-subids: newuidmap and newgidmap (file capabilities) for rootless.
# fuse-overlayfs: rootless overlay where the kernel's is not allowed.
# shellcheck disable=SC2086 # netavark holds two package names
apk --root /rootfs --arch "${arch}" --no-cache --no-scripts add \
  conmon crun ${netavark} passt catatonit fuse-overlayfs shadow-subids \
  containers-common iptables nftables tzdata

# Ubuntu's AppArmor profile for passt attaches by path to /usr/bin/passt{,.avx2} and does
# not allow what pasta needs. exec resolves Alpine's pasta symlinks to those paths, so on
# Ubuntu hosts with passt installed rootless networking would fail; hard links keep the
# pasta name, as in Fedora's package.
for link in /rootfs/usr/bin/pasta /rootfs/usr/bin/pasta.avx2; do
  if [ -L "${link}" ]; then
    ln -f "/rootfs/usr/bin/$(readlink "${link}")" "${link}"
  fi
done

# Unprivileged user for rootless podman, with subordinate ID ranges around its own ID
# as in upstream's image, and its own storage volume.
echo 'podman:x:1000:1000:podman:/home/podman:/bin/sh' >> /rootfs/etc/passwd
echo 'podman:x:1000:' >> /rootfs/etc/group
echo 'podman:!::0:::::' >> /rootfs/etc/shadow
printf 'podman:1:999\npodman:1001:64535\n' > /rootfs/etc/subuid
cp /rootfs/etc/subuid /rootfs/etc/subgid
mkdir -p /rootfs/home/podman/.config/containers /rootfs/home/podman/.local/share/containers
chown -R 1000:1000 /rootfs/home/podman

# ctime cannot be preserved, so -cnewer finds exactly what the steps above wrote.
mkdir /delta
find /rootfs -mindepth 1 -cnewer /marker -printf '%P\0' |
  tar -C /rootfs --null --no-recursion --xattrs --xattrs-include='security.*' -T - -cf - |
  tar -C /delta --xattrs --xattrs-include='security.*' -xpf -
EOF

FROM base
ARG TARGETPLATFORM
COPY --from=delta /delta/ /
COPY .build/packaging/image/containers.conf /etc/containers/containers.conf
COPY --chown=1000:1000 .build/packaging/image/storage.conf /home/podman/.config/containers/storage.conf
COPY $TARGETPLATFORM/podman $TARGETPLATFORM/podman-remote /usr/bin/
COPY $TARGETPLATFORM/quadlet $TARGETPLATFORM/rootlessport /usr/libexec/podman/
# Container storage and the overlays podman build mounts over the build context (in
# /var/tmp) need a file system that is not the image's overlay.
VOLUME ["/var/lib/containers", "/var/tmp", "/home/podman/.local/share/containers"]
ENTRYPOINT ["/usr/bin/podman"]
