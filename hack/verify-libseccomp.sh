#!/usr/bin/env bash
# Verifies a libseccomp release tarball against its detached signature:
#   hack/verify-libseccomp.sh <tarball> <tarball.asc>
# Accepts only signatures by the release signing keys that libseccomp's README lists,
# pinned by fingerprint below; hack/libseccomp-keys.asc holds the public keys and must
# hold exactly these. Needs gpg.
set -euo pipefail

# https://github.com/seccomp/libseccomp/blob/main/README.md
fingerprints=(
  47A68FCE37C7D7024FD65E11356CE62C2B524099 # Tom Hromatka
  7100AADFAE6E6E940D2E0AD655E45A5AE8CA7C8A # Paul Moore
)

tarball="$1"
signature="$2"
keys="$(dirname "$0")/libseccomp-keys.asc"

GNUPGHOME="$(mktemp -d)"
export GNUPGHOME
trap 'rm -rf "${GNUPGHOME}"' EXIT

gpg --batch --quiet --import "${keys}"
# Primary key fingerprints only: each fpr record that follows a pub record.
imported="$(gpg --batch --with-colons --list-keys |
  awk -F: '$1 == "fpr" && prev == "pub" { print $10 } { prev = $1 }' | sort)"
if [[ "${imported}" != "$(printf '%s\n' "${fingerprints[@]}" | sort)" ]]; then
  echo "${keys}: expected exactly the keys ${fingerprints[*]}, got:" >&2
  echo "${imported}" >&2
  exit 1
fi

# VALIDSIG names the primary key last, also for signatures made with a subkey.
status="$(gpg --batch --status-fd 1 --verify "${signature}" "${tarball}" 2>/dev/null)" || {
  echo "${tarball}: bad signature" >&2
  exit 1
}
signer="$(awk '$2 == "VALIDSIG" { print $NF }' <<<"${status}")"
for fingerprint in "${fingerprints[@]}"; do
  if [[ "${signer}" == "${fingerprint}" ]]; then
    echo "${tarball}: good signature by ${signer}"
    exit 0
  fi
done
echo "${tarball}: no valid signature by a pinned key" >&2
exit 1
