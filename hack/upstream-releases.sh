#!/usr/bin/env bash
# Prints the tags of upstream podman's GitHub releases since MIN_VERSION, oldest first.
# Drafts and pre-releases are skipped.
set -euo pipefail

UPSTREAM="${UPSTREAM:-podman-container-tools/podman}"
MIN_VERSION="${MIN_VERSION:-v5.3.0}"

# The releases API sometimes answers 200 with an empty page, so a list counts only when
# it contains upstream's latest release (first page) and a release older than
# MIN_VERSION (last pages); otherwise it is read again.
latest="$(gh api "repos/${UPSTREAM}/releases/latest" --jq .tag_name)"
for attempt in 1 2 3 4 5; do
  tags="$(gh api --paginate "repos/${UPSTREAM}/releases" --jq '.[] | select(.draft or .prerelease | not) | .tag_name')"
  oldest="$(sort -V <<<"${tags}" | head -1)"
  if grep -qxF "${latest}" <<<"${tags}" && [[ -n "${oldest}" && "${oldest}" != "${MIN_VERSION}" &&
    "$(printf '%s\n' "${MIN_VERSION}" "${oldest}" | sort -V | head -1)" == "${oldest}" ]]; then
    break
  fi
  if ((attempt == 5)); then
    echo "upstream-releases.sh: releases of ${UPSTREAM} incomplete after ${attempt} attempts" \
      "(latest ${latest} or releases before ${MIN_VERSION} missing)" >&2
    exit 1
  fi
  sleep $((attempt * 2))
done

sort -V <<<"${tags}" |
  while read -r tag; do
    if [[ "$(printf '%s\n' "${MIN_VERSION}" "${tag}" | sort -V | head -1)" == "${MIN_VERSION}" ]]; then
      echo "${tag}"
    fi
  done
