# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this is

Ansible repository that configures a personal single-node Kubernetes cluster
(powered by [k3s](https://k3s.io/)) on a Raspberry Pi 4 running Debian stable.
Forked from [iamleot/rpi-ansible](https://github.com/iamleot/rpi-ansible).
There is exactly one target host, defined in `hosts.ini`, connected to as
`root` (see `ansible.cfg`).

## Commands

All common tasks are wired through [Task](https://taskfile.dev/) (`Taskfile.yml`):

```sh
task check          # runs yamllint + syntax-check + ansible-lint (the full CI gate)
task yamllint       # yamllint . 
task syntax-check   # ansible-playbook --syntax-check against playbook.yml
task ansible-lint   # ansible-lint
task run            # ansible-playbook --verbose playbook.yml (applies config to the real RPI)
```

Run `task check` before considering any change to `playbook.yml`, `tasks/*.yml`,
or lint configs complete — this is exactly what the `ansible.yaml` CI workflow runs.

There is no test suite; correctness is validated via syntax-check + ansible-lint
(structural/style) and via `conftest` in CI (policy checks against
`.github` using an external policy bundle, see `.github/workflows/conftest.yaml`).

## Architecture

- `playbook.yml` is the single entrypoint. It targets `hosts: all` and imports
  task files from `tasks/` **in a fixed order**, each responsible for one
  concern:
  1. `tasks/update_packages.yml` — apt upgrade everything
  2. `tasks/packages.yml` — install the fixed package list
  3. `tasks/network.yml` — set hostname from `files/hostname`
  4. `tasks/wireguard.yml` — install WireGuard, generate keys idempotently (uses
     `creates:` guards)
  5. `tasks/dns_resolver.yml` — install/enable `unbound`, point
     `/etc/resolv.conf` at it
  6. `tasks/k3s.yml` — install/upgrade k3s to the version pinned by
     `k3s_version` in `playbook.yml`, using `files/k3s-config.yaml`
- Order matters: later task files assume earlier ones already ran (packages
  installed, hostname set, etc.). When adding a new concern, add a new
  `tasks/<name>.yml` file and import it from `playbook.yml` in the appropriate
  position rather than growing an existing task file with unrelated work.
- `files/` holds static files pushed verbatim to the Pi via `ansible.builtin.copy`
  (hostname, k3s config, resolv.conf). WiFi credentials are deliberately
  **not** managed here — see the "Manual configurations" section of
  `README.md` — to avoid committing secrets.
- `k3s_version` (in `playbook.yml`) is validated by an `assert` in
  `tasks/k3s.yml` against `v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+`; the task
  compares the installed version to it and only reinstalls on mismatch. Bump
  this var to upgrade k3s; valid channel/version values are listed at
  <https://update.k3s.io/v1-release/channels>.
- Nearly every task uses `become: true` and guards apt cache updates with
  `cache_valid_time: 3600`, following the existing pattern for any new apt-based
  task.

## CI (GitHub Actions, all under `.github/workflows/`)

- `ansible.yaml` — runs `task check` on push to `main` and on PRs.
- `conftest.yaml` — runs `conftest` against `.github` using an external,
  personal policy bundle (`iamleot/conftest-policies`), on push to `main` and PRs.
- `check-markdown-files.yml` — `markdownlint-cli2` + `lychee` link checking,
  scoped to `**.md` changes.
- Dependency updates are handled by both Dependabot (`.github/dependabot.yml`,
  GitHub Actions only) and Renovate (`renovate.json`, which also has custom
  regex managers to track `CONFTEST_VERSION` / `TASK_VERSION` pins inside the
  workflow YAML files).

## Conventions worth preserving

- Every task in `tasks/*.yml` has a trailing-period, capitalized `name:`
  (e.g. `Install unbound if needed.`) — match this style for new tasks.
  Every task file starts with a `---` and a short `#`-comment block describing
  its purpose.
  Idempotency-sensitive shell steps use `creates:` / `changed_when:` rather than
  free-running shell commands.
- Markdown must pass `markdownlint-cli2` (`.markdownlint-cli2.yaml`: ATX
  headers, 80-char line length except in tables/code blocks) and `lychee`
  link checking (add unreachable/intentional URLs to `.lycheeignore` rather
  than disabling the check).
