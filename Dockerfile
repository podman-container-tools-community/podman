# syntax=docker/dockerfile:1

# The static release binaries with the runtime helpers from Alpine, configured like
# upstream's quay.io/podman/stable image.
# Pinned by index digest so image builds stay reproducible; Renovate bumps it.
FROM alpine:3.24@sha256:71e9b7bae160ba167fa17414401b94cbcdaf3c32feeab9298bd794a2a0614c35
ARG TARGETPLATFORM
# Podman 6 needs netavark 2, and 3.24 ships 1.17: true takes netavark and aardvark-dns
# from the edge community repository instead.
ARG NETAVARK_FROM_EDGE=""
# Versions come from the pinned Alpine release.
# hadolint ignore=DL3018,SC2086
RUN set -eu; \
    netavark="netavark aardvark-dns"; \
    if [ "${NETAVARK_FROM_EDGE}" = true ]; then \
      echo "@edge https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories; \
      netavark="netavark@edge aardvark-dns@edge"; \
    fi; \
    apk add --no-cache conmon crun ${netavark} passt catatonit fuse-overlayfs \
      cmd:newuidmap cmd:newgidmap containers-common iptables nftables ca-certificates tzdata; \
    adduser -D -u 1000 podman; \
    printf 'podman:1:999\npodman:1001:64535\n' > /etc/subuid; \
    cp /etc/subuid /etc/subgid; \
    mkdir -p /home/podman/.config/containers /home/podman/.local/share/containers; \
    chown -R podman:podman /home/podman
COPY .build/packaging/image/containers.conf /etc/containers/containers.conf
COPY --chown=1000:1000 .build/packaging/image/storage.conf /home/podman/.config/containers/storage.conf
COPY $TARGETPLATFORM/podman $TARGETPLATFORM/podman-remote /usr/bin/
COPY $TARGETPLATFORM/quadlet $TARGETPLATFORM/rootlessport /usr/libexec/podman/
# Container storage needs a file system that is not the image's overlay.
VOLUME ["/var/lib/containers", "/home/podman/.local/share/containers"]
ENTRYPOINT ["/usr/bin/podman"]
