[![CI](https://github.com/podman-container-tools-community/podman/actions/workflows/ci.yaml/badge.svg)](https://github.com/podman-container-tools-community/podman/actions/workflows/ci.yaml)
[![Release](https://github.com/podman-container-tools-community/podman/actions/workflows/release.yaml/badge.svg)](https://github.com/podman-container-tools-community/podman/actions/workflows/release.yaml)
[![GitHub license](https://img.shields.io/github/license/podman-container-tools-community/podman)](https://github.com/podman-container-tools-community/podman/blob/main/LICENSE)
[![Current Release](https://img.shields.io/github/release/podman-container-tools-community/podman.svg?logo=github)](https://github.com/podman-container-tools-community/podman/releases/latest)
[![GitHub Repo stars](https://img.shields.io/github/stars/podman-container-tools-community/podman?style=flat&logo=github)](https://github.com/podman-container-tools-community/podman/stargazers)
[![GitHub all releases](https://img.shields.io/github/downloads/podman-container-tools-community/podman/total?logo=github)](https://github.com/podman-container-tools-community/podman/releases/latest)
[![ghcr.io Pulls](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fipitio.github.io%2Fbackage%2Fpodman-container-tools-community%2Fpodman%2Fpodman.json&query=%24.downloads&logo=github&label=ghcr.io%20pulls)](https://github.com/podman-container-tools-community/podman/pkgs/container/podman)

# podman (community build)

⭐ Don't forget to star this repository! ⭐

Community-maintained, static binaries and packages of
[podman](https://github.com/podman-container-tools/podman), part of
[podman-container-tools](https://github.com/podman-container-tools).
**These are not official releases.** They are built from unmodified upstream source
and are not supported by the upstream maintainers.

## Why this exists

Upstream publishes a static `podman-remote` client, but no distribution-independent
`podman`. Distribution packages are often several releases behind, and some
environments (CI runners, minimal or immutable hosts) have no current package at all.
This project fills that gap with:

- static `podman` and `podman-remote` binaries for `linux/amd64` and `linux/arm64`,
- `.deb` and `.rpm` packages of the same binaries, with `quadlet`, `rootlessport`,
  systemd units and shell completions, that replace the distribution's `podman`
  package,
- a multi-arch `podman` image on Alpine with the same binaries and the runtime helpers,
- every upstream minor version from 5.3 on, not only the newest one.

podman is not self-contained: it starts containers through **conmon** and an OCI
runtime (**crun** or runc), and sets up networks with **netavark** (plus
**aardvark-dns** for container name resolution) and **passt** (rootless networking).
These come from your distribution; the packages depend on them. The configuration in
`/etc/containers` (`registries.conf`, `policy.json`, the seccomp profile) comes from the
distribution's `containers-common` (`golang-github-containers-common` on Debian and
Ubuntu).

## Install

### apt (Debian, Ubuntu)

The apt repository follows the newest upstream release. It needs apt 2.3.10 or newer
(Debian 12, Ubuntu 22.04 and later) for the inline key in the sources file:

```sh
curl -fsSL https://raw.githubusercontent.com/podman-container-tools-community/podman/main/packaging/apt/podman.sources |
  sudo tee /etc/apt/sources.list.d/podman.sources
sudo apt update
sudo apt install podman
```

The repository only serves the newest release: after a new upstream release, the `.deb`
URLs in an older cached index are gone (404), so run `sudo apt update` before
`apt install` or `apt upgrade`. To stay on one release, replace
`releases/latest/download` in the URI with `releases/download/vX.Y.Z`.

The runtime helpers come from the distribution, so older distribution releases may
ship versions that are too old for current podman; check upstream's release notes for
the minimum netavark, conmon and crun versions. In particular, **Podman 6 needs
netavark and aardvark-dns 2.0 and the configuration files of containers-common 0.68**
(upstream's 6.0.0 release notes). The Podman 6 packages depend on those versions, so
they refuse to install on a distribution that still ships netavark 1.x (Debian 13 does);
such a distribution can run the Podman 5 packages.

The packages use epoch 6, so they stay installed when the distribution ships its own
podman update. To go back to the distribution's package, remove the source and run
`sudo apt install --allow-downgrades podman=<version>`.

### rpm (Fedora, RHEL, openSUSE)

There is no dnf repository. Download the package from the release, check its signature
(`dnf install` does not check local files) and install it:

```sh
sudo rpm --import https://raw.githubusercontent.com/podman-container-tools-community/podman/main/packaging/gpg.asc
rpm -K podman-6.1.4-1.x86_64.rpm
sudo dnf install ./podman-6.1.4-1.x86_64.rpm
```

`rpm -K` has to report `signatures OK`. The packages use epoch 6 (Fedora's podman has
epoch 5), so `dnf upgrade` does not switch back to the distribution's podman. They
also replace Fedora's `podman-remote` and `podmansh` packages.

The deb and rpm packages and the apt repository are signed with the GPG key in
[`packaging/gpg.asc`](packaging/gpg.asc)
(`59E1 335F 8162 F5DF FE1D  4DA9 7243 E2C2 DA62 80BC`).

### Binaries

`podman-linux-<arch>` and `podman-remote-linux-<arch>` in each release are the bare
binaries. The `podman_<version>_linux_<arch>.tar.gz` archive also contains `quadlet`
and `rootlessport` (install them to `/usr/libexec/podman/`), the systemd units and the
shell completions.

### Image

`ghcr.io/podman-container-tools-community/podman` carries the same static release
binaries (`podman`, `podman-remote`, `quadlet` and `rootlessport`) on Alpine 3.24, set up
like upstream's `quay.io/podman/stable` and used the same way: no entrypoint, BusyBox `sh`
(no `bash`) as the default command, `root` or the rootless `podman` user (UID 1000).

```sh
docker run --rm --privileged ghcr.io/podman-container-tools-community/podman:latest \
  podman run --rm quay.io/libpod/alpine:latest echo hello
docker run --rm --privileged --user podman ghcr.io/podman-container-tools-community/podman:latest \
  podman run --rm quay.io/libpod/alpine:latest echo hello
# Rootless without --privileged (with podman as the outer engine:
# --security-opt label=disable --security-opt unmask=ALL --device /dev/fuse)
docker run --rm --user podman --device /dev/fuse \
  --security-opt seccomp=unconfined --security-opt apparmor=unconfined \
  ghcr.io/podman-container-tools-community/podman:latest \
  podman run --rm quay.io/libpod/alpine:latest echo hello
```

conmon, crun, netavark, aardvark-dns, passt, catatonit, fuse-overlayfs, `git`
and the configuration in `/etc/containers` come from Alpine; for Podman 6, which needs
netavark 2 and the configuration files of containers-common 0.68, netavark,
aardvark-dns and container-libs come from Alpine's edge repository. As upstream:

- containers share the outer container's namespaces
  ([`packaging/image/containers.conf`](packaging/image/containers.conf)), and rootless
  containers bind-mount `/proc` without sysctls
  ([`packaging/image/podman-containers.conf`](packaging/image/podman-containers.conf)),
- `container=oci` and `BUILDAH_ISOLATION=chroot` are set,
- `/var/lib/shared` is an empty additional image store, for a read-only store mounted
  there,
- the short-name aliases (`podman pull fedora` and so on) are the same.

Differences from upstream:

- **No `cpp` and `ssh`.** `podman build` with a `Containerfile.in` and Git URLs over SSH do
  not work.
- **Registries.** Unqualified names are searched on `docker.io` only, without
  `short-name-mode = "enforcing"`; upstream also searches `registry.fedoraproject.org`
  and `registry.access.redhat.com` and refuses ambiguous short names.
- **Native overlay** for rootless storage on the volume in
  `/home/podman/.local/share/containers`, instead of fuse-overlayfs (Alpine's 1.16
  fails on kernel 7.0); upstream's `fsync=0` is left out, it breaks native overlay.
- **Drop-ins.** The image's settings are drop-ins in
  `/etc/containers/containers.conf.d/` and
  `/home/podman/.config/containers/containers.conf.d/`. Since Podman 6, a mounted
  `~/.config/containers/containers.conf` replaces `/etc/containers/containers.conf`
  instead of adding to it; add your settings as a drop-in with another filename, since
  a drop-in shadows one of the same name.

On Ubuntu 24.04 and newer hosts, rootless podman in the image needs `sudo sysctl -w
kernel.apparmor_restrict_unprivileged_userns=0`, as in the tests. The image runs `pasta`
from `/usr/libexec/podman`, where Ubuntu's AppArmor profiles for the host's `passt`
and `pasta` (by path, `/usr/bin/passt` and `/usr/bin/pasta`) do not attach: they break
rootless networking in containers.

`podman-remote` talks to a podman API socket:

```sh
docker run --rm -v "$XDG_RUNTIME_DIR/podman/podman.sock:/run/podman/podman.sock" \
  ghcr.io/podman-container-tools-community/podman:latest \
  podman-remote --url unix:///run/podman/podman.sock ps
```

## Trust model

This repository contains **only build configuration**. Nothing here can change what is
compiled from podman's source:

- Source comes from the Go module proxy (`proxy.golang.org`) at the upstream tag and is
  verified against the Go checksum database (`sum.golang.org`), using
  [goreleaser verifiable builds](https://goreleaser.com/customization/builds/verifiable_builds/).
  Dependencies and their hashes are upstream's own `go.sum`.
- `podman` links one C library that is not part of the Go module: **libseccomp**, built
  from its release tarball, checked against a pinned SHA-256
  ([`hack/build-sysroot.sh`](hack/build-sysroot.sh)). systemd's public headers, needed
  by the `systemd` build tag, come from systemd's repository at the release's pinned
  commit (systemd publishes no tarballs); nothing of systemd is linked. The C compiler
  and musl libc are [zig](https://ziglang.org/), pinned to a version in
  [`mise.toml`](mise.toml).
- Builds run only in GitHub Actions. Binaries and checksums are signed keyless with
  [cosign](https://github.com/sigstore/cosign) via GitHub OIDC, images are signed the
  same way, and every file in `checksums.txt` gets a GitHub build provenance
  attestation.
- Every archive has an SPDX SBOM next to it (`<archive>.sbom.json`, listed in
  `checksums.txt`), and every image carries one per platform as a BuildKit attestation,
  covered by the image signature. syft finds the Go modules in the binaries; the C code
  it cannot see there (musl, libseccomp, and the SQLite that `github.com/mattn/go-sqlite3`
  bundles) is listed in `static-libraries.spdx.json`, which is in the archive and in the
  image under `/usr/share/sbom/podman/`, and merged into both SBOMs. The image's SBOM:
  `docker buildx imagetools inspect ghcr.io/podman-container-tools-community/podman:v6.1.4 --format '{{ json .SBOM }}'`.
- The apt repository metadata (`InRelease`) and the rpm packages are additionally signed
  with a GPG key, because apt and rpm cannot verify sigstore signatures; apt verifies
  the deb packages through the checksums in the signed `InRelease`. The key is kept in
  this repository's secrets and used only by the release workflow.
- Every release is built with the newest stable Go, not the minimum in upstream's
  `go.mod` (exceptions are listed in [`.github/actions/setup`](.github/actions/setup/action.yaml)).
  The Go version used is recorded in each binary (`go version -m`).
- Builds are reproducible: with the same Go, zig and libseccomp versions, anyone gets
  bit-for-bit identical binaries and packages.

## Which versions are released

Every upstream [GitHub release](https://github.com/podman-container-tools/podman/releases)
since `v5.3.0`, drafts and prereleases excluded
([`hack/upstream-releases.sh`](hack/upstream-releases.sh)). 5.0 to 5.2 have a `replace`
directive in `go.mod` (runc), which a build from the Go module proxy cannot honour, so
they cannot be built verifiably.

## Release flow

New upstream releases are picked up automatically, usually within six hours. Each
release is built and tested ([`test/`](test)) before anything is published, then
released here with binaries, packages, the apt repository and images on `ghcr.io`, all
signed.

Image tags: `vX.Y.Z` and `vX.Y.Z-immutable` always, `vX.Y` for the newest release of a
minor, `vX` and `latest` for the newest upstream release by version (not upstream's
GitHub "latest" flag, which a backport release of an older minor can take).
`vX.Y.Z-immutable` is pushed once by the release and never moves.

Releases are built by the pipeline on `main`; the release notes name the pipeline
commit. The release's Git tag in this repository only anchors the GitHub release (it
points at the repository's first commit) and never moves.

Images are rebuilt without a new release when the Alpine base image or its packages
change: weekly for the newest release of every minor, and after changes to the image
definition. A rebuild takes the released archives, checks them against the
cosign-signed `checksums.txt` and builds the image with the current `Dockerfile`, so the
images always contain exactly the released binaries. It updates every tag of that
release except `vX.Y.Z-immutable`, which keeps the digest of the original release.

## Verify a binary

Download the binary (or archive, or package), `checksums.txt` and
`checksums.txt.sigstore.json` from the release. The examples use podman `v6.1.4`.

1. **Signature of the checksums**, proving the file came from this repository's release
   workflow on `main`:

   ```sh
   cosign verify-blob \
     --certificate-identity https://github.com/podman-container-tools-community/podman/.github/workflows/release.yaml@refs/heads/main \
     --certificate-oidc-issuer https://token.actions.githubusercontent.com \
     --bundle checksums.txt.sigstore.json \
     checksums.txt
   ```

2. **Checksum of the binary**:

   ```sh
   sha256sum --check --ignore-missing checksums.txt
   ```

3. **Build provenance** (optional, needs the GitHub CLI):

   ```sh
   gh attestation verify podman-linux-amd64 --repo podman-container-tools-community/podman
   ```

4. **Source**: the module hash embedded in the binary must match the Go checksum database,
   which proves the Go code was built from the upstream tag:

   ```sh
   go version -m podman-linux-amd64 | grep -P '^\tmod'
   # mod  go.podman.io/podman/v6  v6.1.4  h1:2aUnBUpWTFcrQ+zHBWYeiO4GPFe8x1eGc2skZKysPvk=
   curl -s https://sum.golang.org/lookup/go.podman.io/podman/v6@v6.1.4
   ```

   Before 6.0 the module path is `github.com/containers/podman/v5`.

### Verify an image

Every image, released or rebuilt, is signed by the `images.yaml` workflow on `main`:

```sh
cosign verify ghcr.io/podman-container-tools-community/podman:v6.1.4 \
  --certificate-identity https://github.com/podman-container-tools-community/podman/.github/workflows/images.yaml@refs/heads/main \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Reproduce a build

See [Reproduce locally](#reproduce-locally). Use the Go version shown by `go version -m`
on the released binary.

## Limitations

Compared to a distribution package, the static `podman` has:

- **No reading from journald.** `podman` is built with the `systemd` tag (so it uses
  the systemd cgroup manager and systemd timers for health checks on a systemd host,
  as the distribution's podman does), but podman reads the journal through
  libsystemd loaded with `dlopen`, which a static binary cannot do. With the
  `journald` log driver or events backend, `podman logs` and `podman events` fail. The
  packages therefore install `/etc/containers/containers.conf.d/50-podman-community.conf`
  with `k8s-file` logs and `file` events; keep those settings when you use the bare
  binaries on a systemd host:

  ```toml
  [containers]
  log_driver = "k8s-file"
  [engine]
  events_logger = "file"
  ```
- **No GPG signing.** `podman push --sign-by` and `podman image sign` fail.
  Verifying GPG signatures through `policy.json` (`signedBy` with `keyPath`) works.
  Sigstore signing and verification work fully. No Sequoia-PGP backend.
- **No btrfs storage driver.** overlay and vfs work.
- **No libsubid.** Rootless user namespaces still work: `/etc/subuid` and `/etc/subgid`
  are read directly and `newuidmap`/`newgidmap` are used. Subordinate ID ranges served
  by NSS providers (sssd, FreeIPA) are not supported; libsubid loads those with
  `dlopen`, which is impossible in a static binary.
- **No NSS.** musl resolves users from `/etc/passwd` and names through `/etc/hosts` and
  DNS only: no LDAP or sssd users for `--user name`, no mDNS (`.local`) and no
  systemd-resolved specific behaviour.
- **No man pages.** Upstream generates them with tools outside the Go module; see
  [the online documentation](https://docs.podman.io/).
- **Runtime helpers from the distribution.** conmon, crun, netavark, aardvark-dns, passt
  and catatonit (for pods' infra containers) are separate programs, partly in C and
  Rust, and are not part of this build. Older distributions may ship versions that are
  too old for current podman.
- **The apt repository serves only the newest release.** Its sources point at
  `releases/latest/download`, so once a new upstream release is published, the `.deb`
  URLs in a cached index return 404 until `sudo apt update` runs (see
  [apt](#apt-debian-ubuntu)). This is by design; there is no package pool with older
  releases.
- **Linux only**, `amd64` and `arm64`. No `podman machine` (macOS, Windows).

## Reproduce locally

Needs Go, gperf and [mise](https://mise.jdx.dev), which installs zig, goreleaser and syft from
`.build/mise.lock`:

```sh
git clone --branch v6.1.4 https://github.com/podman-container-tools/podman
cd podman
git clone https://github.com/podman-container-tools-community/podman .build
printf '/.build/\n/dist/\n/.zig-cache/\n' >> .git/info/exclude
(cd .build && mise install)
eval "$(mise env -C .build)"
.build/hack/build-sysroot.sh /tmp/sysroot
SYSROOT=/tmp/sysroot GOTOOLCHAIN=local MODULE="$(go mod edit -json | jq -r .Module.Path)" \
GITHUB_REPOSITORY_OWNER=podman-container-tools-community GITHUB_REPOSITORY=podman-container-tools-community/podman \
  goreleaser release --config .build/.goreleaser.yaml --clean --skip=publish,sign,sbom
```

The libseccomp version and checksum are those in [`hack/build-sysroot.sh`](hack/build-sysroot.sh).
With the same Go version (see `go version -m`), the binaries are bit-for-bit identical.
How to run the tests is described in [`AGENTS.md`](AGENTS.md).

## Contributing

Bug reports and pull requests are welcome. [`CONTRIBUTING.md`](CONTRIBUTING.md) explains
how to report a problem, what changes we accept and how to propose one. How the build
works, how to run the tests and the release workflows are described in
[`AGENTS.md`](AGENTS.md).
