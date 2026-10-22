#!/usr/bin/env bash
# Recomputes the SHA-256 pinned next to each version Renovate bumps, and adds the SHA-256
# of downloads that mise.lock has no checksum for:
#   hack/update-checksums.sh
# Runs on Renovate pull requests via .github/workflows/renovate.yaml, and locally.
# Needs mise, curl and shasum or sha256sum.
set -euo pipefail

cd "$(dirname "$0")/.."

sha256() {
  if command -v shasum >/dev/null; then
    shasum -a 256 | cut -d ' ' -f 1
  else
    sha256sum | cut -d ' ' -f 1
  fi
}

# pin FILE NAME URL: downloads URL, with {version} replaced by NAME_VERSION from FILE,
# and writes its SHA-256 to NAME_SHA256 in FILE.
pin() {
  local file="$1" name="$2" url="$3" version hash
  # NAME_VERSION=value in shell, NAME_VERSION: value in YAML.
  local sep='(=|:[[:space:]]*)'
  version="$(sed -nE "s/^[[:space:]]*${name}_VERSION${sep}([^[:space:]]+).*$/\2/p" "${file}")"
  if [[ -z "${version}" ]]; then
    echo "${file}: ${name}_VERSION not found" >&2
    exit 1
  fi
  hash="$(curl -fsSL "${url//\{version\}/${version}}" | sha256)"
  sed -E "s/^([[:space:]]*${name}_SHA256${sep})[0-9a-f]{64}/\1${hash}/" \
    "${file}" >"${file}.tmp"
  # cat instead of mv keeps the file's mode, such as the executable bit.
  cat "${file}.tmp" >"${file}"
  rm "${file}.tmp"
  if ! grep -q "${name}_SHA256.*${hash}" "${file}"; then
    echo "${file}: ${name}_SHA256 not found" >&2
    exit 1
  fi
  echo "${name} ${version}: ${hash}"
}

# lock_checksums: refreshes mise.lock for mise.toml and adds a SHA-256 to every download
# that has none. mise lock records checksums only where a release publishes them, and
# GitHub's source archives, which bats-core is installed from, come without.
lock_checksums() {
  local line url checksum="" hashed="" hash="" out
  mise lock
  out="$(mktemp)"
  while IFS= read -r line; do
    case "${line}" in
    '['*) checksum="" ;;
    'checksum = '*) checksum=yes ;;
    'url = '*)
      if [[ -z "${checksum}" ]]; then
        url="${line#url = \"}"
        url="${url%\"}"
        # Platforms that share one download follow each other.
        if [[ "${url}" != "${hashed}" ]]; then
          hash="$(curl -fsSL "${url}" | sha256)"
          hashed="${url}"
          echo "${url}: ${hash}" >&2
        fi
        echo "checksum = \"sha256:${hash}\""
      fi
      ;;
    esac
    printf '%s\n' "${line}"
  done <mise.lock >"${out}"
  # cat instead of mv keeps the file's mode.
  cat "${out}" >mise.lock
  rm "${out}"
}

# pin_systemd_headers: the SYSTEMD_HEADERS_SHA256 block in the setup action, one
# sha256sum line per header, downloaded one by one from systemd's repository at
# SYSTEMD_VERSION.
pin_systemd_headers() {
  local file=.github/actions/setup/action.yaml version header hash
  version="$(sed -nE 's/^[[:space:]]*SYSTEMD_VERSION:[[:space:]]*([^[:space:]]+).*$/\1/p' "${file}")"
  if [[ -z "${version}" ]]; then
    echo "${file}: SYSTEMD_VERSION not found" >&2
    exit 1
  fi
  for header in _sd-common.h sd-daemon.h sd-id128.h sd-journal.h; do
    hash="$(curl -fsSL "https://raw.githubusercontent.com/systemd/systemd/v${version}/src/systemd/${header}" | sha256)"
    sed -E "s/^([[:space:]]*)[0-9a-f]{64}(  ${header})$/\1${hash}\2/" "${file}" >"${file}.tmp"
    cat "${file}.tmp" >"${file}"
    rm "${file}.tmp"
    if ! grep -q "${hash}  ${header}" "${file}"; then
      echo "${file}: SYSTEMD_HEADERS_SHA256 line for ${header} not found" >&2
      exit 1
    fi
    echo "systemd ${version} ${header}: ${hash}"
  done
}

pin .github/actions/setup/action.yaml LIBSECCOMP \
  "https://github.com/seccomp/libseccomp/releases/download/v{version}/libseccomp-{version}.tar.gz"
pin_systemd_headers
lock_checksums
