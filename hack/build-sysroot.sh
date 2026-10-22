#!/usr/bin/env bash
# Builds the C sysroot for the static build with zig cc:
#   hack/build-sysroot.sh <sysroot>
# A static musl libseccomp for both architectures, installed to <sysroot>/<arch>/{include,lib}
# (libseccomp-golang finds it through PKG_CONFIG_LIBDIR, set in .goreleaser.yaml), and
# systemd's public headers in <sysroot>/include/systemd for the systemd build tag:
# go-systemd's journal reader includes them and loads libsystemd with dlopen at run time,
# nothing is linked. systemd publishes no release tarballs, so the four files come from
# its repository at the release's commit, which pins their content.
# Needs zig, gperf and curl. Renovate bumps the libseccomp version with the tarball's
# sha256 and the systemd tag with its commit; the versions keep the tag's v.
set -euo pipefail

# renovate: datasource=github-release-attachments depName=seccomp/libseccomp
LIBSECCOMP_VERSION=v2.6.1
LIBSECCOMP_SHA256=501f66c667225d53791b97e1d7cf85ab764c297d04881f60f38f451c4b0ee1be
# renovate: datasource=github-tags depName=systemd/systemd
SYSTEMD_VERSION=v262.1
SYSTEMD_COMMIT=73612ea502d53baf9b0df4336cfc296a7ee0d524

sysroot="$(realpath -m "$1")"
work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT
mkdir -p "${sysroot}"

command -v gperf >/dev/null || sudo apt-get install -y --no-install-recommends gperf
tarball="${work}/libseccomp-${LIBSECCOMP_VERSION#v}.tar.gz"
curl -fsSLo "${tarball}" \
  "https://github.com/seccomp/libseccomp/releases/download/${LIBSECCOMP_VERSION}/libseccomp-${LIBSECCOMP_VERSION#v}.tar.gz"
sha256sum --check --strict <<<"${LIBSECCOMP_SHA256}  ${tarball}"
mkdir "${work}/src"
tar -xzf "${tarball}" -C "${work}/src" --strip-components=1
for arch in x86_64 aarch64; do
  mkdir "${work}/${arch}"
  (
    cd "${work}/${arch}"
    "${work}/src/configure" --quiet --host="${arch}-linux-musl" --prefix="${sysroot}/${arch}" \
      --enable-static --disable-shared \
      CC="zig cc -target ${arch}-linux-musl" AR="zig ar" RANLIB="zig ranlib"
    make --silent -j"$(nproc)" >/dev/null
    make --silent install >/dev/null
  )
done

echo "systemd ${SYSTEMD_VERSION} (${SYSTEMD_COMMIT})"
mkdir -p "${sysroot}/include/systemd"
for header in _sd-common.h sd-daemon.h sd-id128.h sd-journal.h; do
  curl -fsSLo "${sysroot}/include/systemd/${header}" \
    "https://raw.githubusercontent.com/systemd/systemd/${SYSTEMD_COMMIT}/src/systemd/${header}"
done
