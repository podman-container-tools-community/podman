#!/usr/bin/env bats
# Signing and signature verification for a built podman; hack/functional-test.sh runs it
# after functional.bats, as root and as a rootless user. IMAGE is the image pushed and
# signed, REGISTRY a plain-HTTP registry (host:port). Releases are built with
# containers_image_openpgp: GPG signatures verify, but signing with GPG (--sign-by) is
# not supported. Sigstore signing is pure Go and works. sigstore/ holds a key pair made
# with `skopeo generate-sigstore-key` for these tests only (podman cannot make one).
# The cases run in order and later ones use what earlier ones pushed. Pushes drop the
# signatures that pulling a signed copy stores with IMAGE.

bats_require_minimum_version 1.5.0
load helpers

setup_file() {
  : "${REGISTRY:?}"
  export IMAGE="${IMAGE:-quay.io/libpod/alpine:latest}"
  export KEYS="${BATS_TEST_DIRNAME}/sigstore"
  WORK="$(mktemp -d)"
  export WORK
  # Root and rootless push the same image, so each gets repositories of its own.
  local prefix
  prefix="${REGISTRY}/signed-$(id -u)"
  export SIGSTORE_REPO="${prefix}/sigstore" GPG_REPO="${prefix}/gpg"
  podman pull -q "${IMAGE}" >/dev/null

  # podman has no option for registries.d; the user's directory replaces the system one.
  REGISTRIES_D="${HOME}/.config/containers/registries.d"
  if [[ -e "${REGISTRIES_D}" ]]; then
    echo "${REGISTRIES_D} exists, not replacing it" >&2
    return 1
  fi
  export REGISTRIES_D
  mkdir -p "${REGISTRIES_D}" "${WORK}/lookaside"
  cat >"${REGISTRIES_D}/test.yaml" <<EOF
docker:
  ${SIGSTORE_REPO}:
    use-sigstore-attachments: true
  ${GPG_REPO}:
    lookaside: file://${WORK}/lookaside
EOF

  # A GPG key for simple signing, and a second one nothing is signed with.
  local name
  for name in signer other; do
    GNUPGHOME="${WORK}/gnupg-${name}" gpg_quiet --quick-gen-key "${name} <${name}@example.com>" rsa2048 sign never
    GNUPGHOME="${WORK}/gnupg-${name}" gpg_quiet --export >"${WORK}/${name}.gpg"
  done
}

teardown_file() {
  local name
  for name in signer other; do
    gpgconf --homedir "${WORK}/gnupg-${name}" --kill gpg-agent 2>/dev/null || true
  done
  if [[ -n "${REGISTRIES_D:-}" ]]; then
    rm -rf "${REGISTRIES_D}"
  fi
  rm -rf "${WORK}"
}

# gpg without prompts, in the home directory GNUPGHOME names.
gpg_quiet() {
  [[ -d "${GNUPGHOME}" ]] || mkdir -m 0700 "${GNUPGHOME}"
  gpg --batch --quiet --pinentry-mode loopback --passphrase '' "$@"
}

# write_policy <file> <repository> <requirement JSON>: rejects everything but <repository>.
write_policy() {
  jq -n --arg repo "$2" --argjson req "$3" \
    '{default: [{type: "reject"}], transports: {docker: {($repo): [$req]}}}' >"$1"
}

@test "sigstore: sign with a private key on push" {
  podman push -q --tls-verify=false --remove-signatures --digestfile "${WORK}/sigstore.digest" \
    --sign-by-sigstore-private-key "${KEYS}/signer.private" --sign-passphrase-file "${KEYS}/passphrase" \
    "${IMAGE}" "${SIGSTORE_REPO}:latest"
  # The signature is an attachment tagged after the image's digest.
  local digest
  digest="$(cat "${WORK}/sigstore.digest")"
  run -0 curl -fsS "http://${SIGSTORE_REPO%%/*}/v2/${SIGSTORE_REPO#*/}/tags/list"
  jq -e --arg tag "${digest/:/-}.sig" '.tags | index($tag)' <<<"${output}"
}

@test "sigstore: policy accepts the signed image" {
  podman rmi -f "${SIGSTORE_REPO}:latest" >/dev/null 2>&1 || true
  write_policy "${WORK}/sigstore-policy.json" "${SIGSTORE_REPO}" \
    "{\"type\": \"sigstoreSigned\", \"keyPath\": \"${KEYS}/signer.pub\", \"signedIdentity\": {\"type\": \"matchRepository\"}}"
  podman pull -q --tls-verify=false --signature-policy "${WORK}/sigstore-policy.json" "${SIGSTORE_REPO}:latest"
  podman rmi "${SIGSTORE_REPO}:latest"
}

@test "sigstore: policy rejects the image for another key" {
  write_policy "${WORK}/sigstore-other.json" "${SIGSTORE_REPO}" \
    "{\"type\": \"sigstoreSigned\", \"keyPath\": \"${KEYS}/other.pub\", \"signedIdentity\": {\"type\": \"matchRepository\"}}"
  run -125 podman pull -q --tls-verify=false --signature-policy "${WORK}/sigstore-other.json" "${SIGSTORE_REPO}:latest"
  [[ "${output}" == *"Source image rejected"* ]]
}

@test "gpg: signing with --sign-by fails with a clear error" {
  GNUPGHOME="${WORK}/gnupg-signer" run -125 podman push --tls-verify=false --sign-by signer@example.com \
    "${IMAGE}" "${GPG_REPO}:sign-by"
  [[ "${output}" == *"signing is not supported"*"containers_image_openpgp"* ]]
}

# The signature is made with gpg, as by a signer outside this build, and stored where the
# lookaside configuration in registries.d points.
@test "gpg: policy accepts an image signed by gpg in a lookaside" {
  podman push -q --tls-verify=false --remove-signatures --digestfile "${WORK}/gpg.digest" "${IMAGE}" "${GPG_REPO}:latest"
  local digest
  digest="$(cat "${WORK}/gpg.digest")"
  local sigdir="${WORK}/lookaside/${GPG_REPO#*/}@${digest/:/=}"
  mkdir -p "${sigdir}"
  jq -nc --arg ref "${GPG_REPO}:latest" --arg digest "${digest}" \
    '{critical: {identity: {"docker-reference": $ref}, image: {"docker-manifest-digest": $digest},
      type: "atomic container signature"}, optional: {}}' |
    GNUPGHOME="${WORK}/gnupg-signer" gpg_quiet --sign --output "${sigdir}/signature-1"

  write_policy "${WORK}/gpg-policy.json" "${GPG_REPO}" \
    "{\"type\": \"signedBy\", \"keyType\": \"GPGKeys\", \"keyPath\": \"${WORK}/signer.gpg\"}"
  podman pull -q --tls-verify=false --signature-policy "${WORK}/gpg-policy.json" "${GPG_REPO}:latest"
  podman rmi "${GPG_REPO}:latest"
}

@test "gpg: policy rejects the image for another key" {
  write_policy "${WORK}/gpg-other.json" "${GPG_REPO}" \
    "{\"type\": \"signedBy\", \"keyType\": \"GPGKeys\", \"keyPath\": \"${WORK}/other.gpg\"}"
  run -125 podman pull -q --tls-verify=false --signature-policy "${WORK}/gpg-other.json" "${GPG_REPO}:latest"
  [[ "${output}" == *"Source image rejected"* ]]
}
