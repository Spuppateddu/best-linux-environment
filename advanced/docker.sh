#!/usr/bin/env bash
# Docker Engine — daemon, CLI, containerd, buildx/compose, and this user in the
# docker group. CE from Docker's repo, but a docker.io host is kept as it is.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib/common.sh"

# docker-ce is the daemon; the rest are the CLI, the runtime and the two plugins
# that make `docker buildx` / `docker compose` exist as subcommands.
DOCKER_PKGS=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)

# The same two subcommands, as Ubuntu names them: `docker.io` is the daemon and
# the CLI only, and without these `docker compose` / `docker buildx` don't exist.
DOCKER_IO_PLUGINS=(docker-compose-v2 docker-buildx)

# Either stack counts as installed — see the header. --check (the menu's tick)
# goes through this too, so a docker.io host isn't offered a redundant install.
is_installed() { apt_installed docker-ce || apt_installed docker.io; }
[[ "${1:-}" == "--check" ]] && { is_installed && exit 0 || exit 1; }

title "Docker Engine"

user="$(id -un)"

# ── the packages ─────────────────────────────────────────────────────────────
# No early exit when installed: the service and group checks below are what break.
if apt_installed docker-ce; then
    skip "Docker CE already installed ($(docker --version 2>/dev/null || echo 'version unknown'))."
elif apt_installed docker.io; then
    skip "Ubuntu's docker.io already installed ($(docker --version 2>/dev/null || echo 'version unknown')) — kept."
    # The same upstream plugins, packaged separately. On a release too old to
    # carry them apt_ensure warns and moves on; the fix is a newer Ubuntu.
    apt_ensure "${DOCKER_IO_PLUGINS[@]}"
else
    # podman-docker and docker-compose v1 own /usr/bin/docker, so docker-ce would
    # clash. Removing them can kill a live daemon, so this stops and tells you.
    conflicting=()
    for pkg in docker-compose docker-doc podman-docker; do
        apt_installed "$pkg" && conflicting+=("$pkg")
    done
    if [[ ${#conflicting[@]} -gt 0 ]]; then
        fail "Ubuntu's own Docker packages are installed: ${conflicting[*]}"
        fail "Docker CE conflicts with them. Remove them, then re-run this module:"
        fail "  sudo apt-get remove ${conflicting[*]}"
        exit 1
    fi

    apt_ensure ca-certificates curl gnupg

    # Docker publishes one suite per Ubuntu codename (…/dists/<codename>/).
    codename="$(. /etc/os-release 2>/dev/null && printf '%s' "${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}")"
    if [[ -z "$codename" ]]; then
        fail "Could not determine the Ubuntu codename — install Docker manually:"
        fail "  https://docs.docker.com/engine/install/ubuntu/"
        exit 1
    fi

    # Not apt_repo_add's guard alone: Docker's own docs put the key in
    # /etc/apt/keyrings, and a hand-set-up host must not have its list rewritten.
    if grep -rlF download.docker.com /etc/apt/sources.list /etc/apt/sources.list.d >/dev/null 2>&1; then
        skip "Docker apt repo already configured."
    else
        dockerarch="$(arch_pick amd64 arm64)" || {
            fail "Unsupported arch $(uname -m) — Docker CE publishes amd64 and arm64 only."
            exit 1
        }
        apt_repo_add docker \
            "https://download.docker.com/linux/ubuntu/gpg" \
            "deb [arch=${dockerarch} signed-by=/usr/share/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable"
    fi

    apt_ensure "${DOCKER_PKGS[@]}"

    # apt_ensure warns and returns 0, so check what landed. The usual cause is
    # Docker not having published this codename yet.
    if [[ "$DRY_RUN" != true ]] && ! is_installed; then
        if can_sudo; then
            fail "docker-ce is still not installed — no candidate for '${codename}'?"
            fail "Docker publishes per codename: https://download.docker.com/linux/ubuntu/dists/"
            fail "Stopgap until it lands: sudo apt-get install docker.io docker-compose-v2"
            exit 1
        fi
        warn "sudo unavailable — Docker not installed. Re-run from a terminal:"
        warn "  ./setup.sh only docker"
        exit 0
    fi
fi

# ── the daemon at boot ───────────────────────────────────────────────────────
# Asserted anyway: a host where someone disabled it looks installed, with no daemon.
if has_cmd systemctl && [[ -d /run/systemd/system ]]; then
    if systemctl is-enabled docker.service >/dev/null 2>&1; then
        skip "docker.service already enabled at boot."
    elif can_sudo || [[ "$DRY_RUN" == true ]]; then
        step "Enabling docker.service"
        run sudo systemctl enable --now docker.service
    else
        warn "sudo unavailable — could not enable docker.service."
    fi
else
    skip "No systemd here — start the daemon however this host does."
fi

# ── docker without sudo ──────────────────────────────────────────────────────
# That group is root-equivalent by design. grep -x, so "dockerroot" can't pass.
if id -nG "$user" | tr ' ' '\n' | grep -x docker >/dev/null 2>&1; then
    skip "$user is already in the docker group."
elif can_sudo || [[ "$DRY_RUN" == true ]]; then
    step "Adding $user to the docker group"
    run sudo usermod -aG docker "$user"
    warn "Group membership starts at your next login — until then use sudo, or run: newgrp docker"
else
    warn "sudo unavailable — $user not added to the docker group (docker will need sudo)."
fi

ok "Docker Engine ready."

# ── its TUI ──────────────────────────────────────────────────────────────────
# One way only, and a separate process, so GitHub can't fail the Docker install.
if [[ "$DRY_RUN" == true ]] || is_installed; then
    bash "$BLE_ROOT/advanced/lazydocker.sh" || warn "lazydocker failed — Docker itself is fine. Retry: ./setup.sh only lazydocker"
fi
