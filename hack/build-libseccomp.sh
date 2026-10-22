#!/usr/bin/env bash
# Builds a static libseccomp against musl for every target architecture with zig:
#   hack/build-libseccomp.sh <release tarball> <sysroot>
# Installs to <sysroot>/<arch>/{include,lib}, where <arch> is x86_64 or aarch64.
# podman's seccomp support (libseccomp-golang) links against it. Needs zig and gperf.
set -euo pipefail

tarball="$(realpath "$1")"
sysroot="$(realpath -m "$2")"
src="$(mktemp -d)"
trap 'rm -rf "${src}"' EXIT

tar -xzf "${tarball}" -C "${src}" --strip-components=1

for arch in x86_64 aarch64; do
  mkdir "${src}/build-${arch}"
  (
    cd "${src}/build-${arch}"
    "${src}/configure" --quiet \
      --host="${arch}-linux-musl" \
      --prefix="${sysroot}/${arch}" \
      --enable-static --disable-shared \
      CC="zig cc -target ${arch}-linux-musl" AR="zig ar" RANLIB="zig ranlib"
    make --silent -j"$(nproc)" >/dev/null
    make --silent install >/dev/null
  )
done
