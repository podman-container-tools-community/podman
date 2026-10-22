# syntax=docker/dockerfile:1

# The static release binaries with their runtime helpers from Alpine, configured like
# upstream's quay.io/podman/stable image. Built by hack/build-image.sh from a context of
# linux/<arch>/<binaries> and packaging/image/.
# Pinned by version and index digest so image builds stay reproducible; Renovate bumps it
# (both FROM lines name the same image).
FROM alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6 AS base

# Everything that has to run happens here, on the build host's platform, so no emulation
# is needed: apk installs the target architecture's packages into a copy of the target's
# file system, without their scripts (a modprobe for fuse-overlayfs and triggers that the
# base image has already run). Only what changed ends up in /delta, so the final image
# adds one layer on top of Alpine's.
FROM --platform=$BUILDPLATFORM alpine:3.24.3@sha256:b3413572228e34bd1c9245f5565e6cd127005655e8a7899aef33d8e83255c9e6 AS delta
ARG TARGETARCH
# Podman 6 needs netavark 2 and the configuration files of containers-common 0.68
# (container-libs in Alpine), and 3.24 ships netavark 1.17 and containers-common
# 0.64: true takes netavark, aardvark-dns and container-libs from the edge community
# repository instead.
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
netavark="netavark aardvark-dns containers-common"
if [ "${NETAVARK_FROM_EDGE}" = true ]; then
  echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /rootfs/etc/apk/repositories
  netavark="netavark@edge aardvark-dns@edge container-libs@edge"
fi
# shadow-subids: newuidmap and newgidmap (file capabilities) for rootless.
# fuse-overlayfs: rootless overlay where the kernel's is not allowed.
# shellcheck disable=SC2086 # netavark holds three package names
# bash and git as in upstream's image: bash is the default command and the podman
# user's shell, git serves podman build from Git URLs.
apk --root /rootfs --arch "${arch}" --no-cache --no-scripts add \
  conmon crun ${netavark} passt catatonit fuse-overlayfs shadow-subids \
  iptables nftables tzdata bash git
# bash's own script would add it to /etc/shells.
echo /bin/bash >> /rootfs/etc/shells

# Ubuntu's AppArmor profiles for passt and pasta attach by path to
# /usr/bin/{passt,pasta}{,.avx2} and are written for the host's binaries: 24.04's passt
# profile, which Alpine's pasta symlinks resolve to, lacks what pasta needs, and 26.04's
# pasta profile does not let podman signal pasta. podman looks for pasta in
# /usr/libexec/podman before $PATH, and hard links there run unconfined.
ln -f /rootfs/usr/bin/passt /rootfs/usr/libexec/podman/pasta
if [ -f /rootfs/usr/bin/passt.avx2 ]; then
  ln -f /rootfs/usr/bin/passt.avx2 /rootfs/usr/libexec/podman/pasta.avx2
fi

# Unprivileged user for rootless podman, with subordinate ID ranges around its own ID
# as in upstream's image, and its own storage volume.
echo 'podman:x:1000:1000:podman:/home/podman:/bin/bash' >> /rootfs/etc/passwd
echo 'podman:x:1000:' >> /rootfs/etc/group
echo 'podman:!::0:::::' >> /rootfs/etc/shadow
printf 'podman:1:999\npodman:1001:64535\n' > /rootfs/etc/subuid
cp /rootfs/etc/subuid /rootfs/etc/subgid
mkdir -p /rootfs/home/podman/.config/containers/containers.conf.d \
  /rootfs/home/podman/.local/share/containers
chown -R 1000:1000 /rootfs/home/podman

# Empty additional image store, as in upstream's image, for a read-only store mounted
# at /var/lib/shared (storage.conf).
for store in overlay vfs; do
  mkdir -p "/rootfs/var/lib/shared/${store}-images" "/rootfs/var/lib/shared/${store}-layers"
  touch "/rootfs/var/lib/shared/${store}-images/images.lock" "/rootfs/var/lib/shared/${store}-layers/layers.lock"
done

# ctime cannot be preserved, so -cnewer finds exactly what the steps above wrote.
mkdir /delta
find /rootfs -mindepth 1 -cnewer /marker -printf '%P\0' |
  tar -C /rootfs --null --no-recursion --xattrs --xattrs-include='security.*' -T - -cf - |
  tar -C /delta --xattrs --xattrs-include='security.*' -xpf -
EOF

FROM base
ARG TARGETPLATFORM
COPY --from=delta /delta/ /
# Drop-ins, not the main files: since Podman 6 a user's ~/.config/containers/containers.conf
# replaces /etc/containers/containers.conf instead of adding to it, but drop-ins are
# read from every directory. A drop-in shadows one of the same name in an earlier
# directory, so the user's has its own name.
COPY packaging/image/containers.conf /etc/containers/containers.conf.d/50-podman-in-container.conf
COPY --chown=1000:1000 packaging/image/podman-containers.conf /home/podman/.config/containers/containers.conf.d/60-rootless-in-container.conf
COPY packaging/image/storage.conf /etc/containers/storage.conf
COPY --chown=1000:1000 packaging/image/storage-rootless.conf /home/podman/.config/containers/storage.conf
COPY $TARGETPLATFORM/podman $TARGETPLATFORM/podman-remote /usr/bin/
COPY $TARGETPLATFORM/quadlet $TARGETPLATFORM/rootlessport /usr/libexec/podman/
# Container storage and the overlays podman build mounts over the build context (in
# /var/tmp) need a file system that is not the image's overlay.
VOLUME ["/var/lib/containers", "/var/tmp", "/home/podman/.local/share/containers"]
# As in upstream's image: container=oci tells podman it runs in a container (no warning
# about / not being a shared mount), and builds use chroot isolation.
ENV container=oci BUILDAH_ISOLATION=chroot
CMD ["/bin/bash"]
