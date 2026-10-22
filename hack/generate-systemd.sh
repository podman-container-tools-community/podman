#!/usr/bin/env bash
# Copies upstream's systemd units for the packages, as upstream's install.systemd does:
#   hack/generate-systemd.sh <output dir>
# Runs in the upstream checkout. *.service.in get @@PODMAN@@ replaced with
# /usr/bin/podman. Writes <output dir>/system and <output dir>/user.
set -euo pipefail

out="$1"
rm -rf "${out}"
for kind in system user; do
  mkdir -p "${out}/${kind}"
  for unit in contrib/systemd/"${kind}"/*; do
    name="$(basename "${unit}")"
    case "${name}" in
    # tmpfiles.d snippet of upstream's podman-docker package
    podman-docker.conf) ;;
    *.in) sed -e 's;@@PODMAN@@;/usr/bin/podman;g' "${unit}" >"${out}/${kind}/${name%.in}" ;;
    *) cp "${unit}" "${out}/${kind}/${name}" ;;
    esac
  done
done
