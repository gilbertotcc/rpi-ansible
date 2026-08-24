# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## What this is

Ansible repository that configures personal Raspberry Pi boards on
Debian stable: a Raspberry Pi 4 (RPi4), plus a Raspberry Pi 3 (RPi3) as
a second, lighter-weight board. RPi4 also runs a single-node Kubernetes
cluster powered by [k3s](https://k3s.io/); RPi3 instead runs Prometheus
Node Exporter, exposing host metrics for the RPi4/Flux-managed
Prometheus to scrape, and Vector, forwarding its journald logs to
Google Cloud Logging. Forked from
[iamleot/rpi-ansible](https://github.com/iamleot/rpi-ansible).
`hosts.ini` defines two groups — `rpi4` and `rpi3` — both connected to
as `root` (see `ansible.cfg`). `playbook.yml` targets `hosts: all`; all
roles apply to both hosts except `roles/k3s`, which is gated to the
`rpi4` group only, via `when: inventory_hostname in groups['rpi4']` on
that role entry in `playbook.yml`'s `roles:` list — RPi3's more limited
hardware runs no k3s node — and `roles/node_exporter`/`roles/vector`,
gated the same way to the `rpi3` group only. Both boards connect over
Ethernet (`eth0`); per-host values (hostname, static `eth0` IP) live
in `group_vars/rpi4/` and `group_vars/rpi3/`.
_Last updated: 2026-08-24._

## Commands

All common tasks are wired through `make` (`Makefile`):

```sh
make check          # runs yamllint + syntax-check + ansible-lint (the full CI gate)
make yamllint       # yamllint . 
make syntax-check   # ansible-playbook --syntax-check against playbook.yml
make ansible-lint   # ansible-lint
make run            # ansible-playbook --verbose playbook.yml (applies config to the real RPis)
```

Run `make check` before considering any change to `playbook.yml`, `roles/*/tasks/*.yml`,
or lint configs complete — this is exactly what the `ansible.yaml` CI workflow runs.

`group_vars/all/wireguard.yml` holds the vault-encrypted WireGuard peer
values (see `roles/wireguard` below), once populated. `make run` needs
a vault password to decrypt these. With
`.envrc`/`scripts/ansible-vault-password.sh` set up (direnv + gopass —
see the "Ansible Vault password" section of `README.md`), plain
`make run` works out of the box.

There is no test suite; correctness is validated via syntax-check + ansible-lint
(structural/style) and via `conftest` in CI (policy checks against
`.github` using an external policy bundle, see `.github/workflows/conftest.yaml`).

## Architecture

- `playbook.yml` is the single entrypoint. It targets `hosts: all` and applies
  roles from `roles/` **in a fixed order** via a `roles:` list, each
  responsible for one concern:
  1. `roles/packages` — apt upgrade everything (gated by `packages_update`)
     and install the package list (`packages_needed_packages`)
  2. `roles/journald` — cap journald's on-disk footprint via
     `roles/journald/templates/journald.conf.j2`, so logs don't grow
     unbounded on the microSD
  3. `roles/zram` — configure zram-backed swap via
     systemd-zram-generator, giving this low-RAM board memory headroom
     without writing swap to the microSD
  4. `roles/network` — set hostname from the `network_hostname` var and
     bring up `eth0` with a static address (`network_address`/
     `network_gateway`) via a templated ifupdown `interfaces.d/eth0`
     stanza (`group_vars/rpi4/network.yml`, `group_vars/rpi3/network.yml`),
     the same pattern used for `wg0`.
  5. `roles/dns_resolver` — install/enable the DNS resolver
     (`dns_resolver_package`/`dns_resolver_service`, default `unbound`),
     point `/etc/resolv.conf` at it
  6. `roles/wireguard` — install WireGuard, generate keys idempotently (uses
     `creates:` guards), and — once `wireguard_enabled` (defaults to
     `false` as a safe fallback) plus the peer values are supplied —
     template `/etc/wireguard/wg0.conf` and an ifupdown
     `interfaces.d/wg0` stanza and bring the tunnel up. `wg0` is
     deliberately brought up via plain `ip`/`wg` commands in ifupdown
     hooks; activation restarts the `networking` service (see
     README.md's "WireGuard VPN" section). `ifupdown` is installed by
     this role itself, since nothing else in the playbook needs it
     anymore
  7. `roles/node_exporter` — install/configure `prometheus-node-exporter`,
     exposing host metrics on `node_exporter_listen_address` (default
     `0.0.0.0:9100`) for the separately managed RPi4/Flux Prometheus to
     scrape (RPi3 only — gated via `when:` in `playbook.yml`; see
     README.md's "Monitoring" section)
  8. `roles/vector` — install Vector and forward RPi3's journald logs to
     Google Cloud Logging via the `gcp_stackdriver_logs` sink
     (`vector_enabled`, defaults to `false` as a safe fallback, same
     pattern as `roles/wireguard`; RPi3 only — gated via `when:` in
     `playbook.yml`; see README.md's "Vector log export" section)
  9. `roles/k3s` — install/upgrade k3s to the version pinned by
     `k3s_version` in `playbook.yml`, using
     `roles/k3s/templates/k3s-config.yaml.j2` (RPi4 only — gated via
     `when:` in `playbook.yml`)
- Order matters: later roles assume earlier ones already ran (packages
  installed, hostname set, etc.). When adding a new concern, add a new
  `roles/<name>/` directory (with `tasks/main.yml` and, as needed,
  `defaults/main.yml`, `files/`, `meta/main.yml`) and reference it from
  `playbook.yml`'s `roles:` list in the appropriate position, rather than
  growing an existing role's tasks with unrelated work.
- A role that needs to behave differently per host (not just per group)
  gates itself with `when: inventory_hostname in groups['<group>']` on
  its `roles:` list entry (see `k3s` above) rather than an in-role
  conditional, keeping the host/group logic visible in one place.
- A role that requires a value to be explicitly set per host (rather than
  falling back to a shared default) defines it as an empty string in
  `defaults/main.yml` and asserts it's non-empty as its first task
  (`delegate_to: localhost`, see `roles/network`) —
  this fails fast with a clear message instead of silently applying an
  empty/wrong value.
- Each role's `files/` holds static files pushed verbatim to the Pi via
  `ansible.builtin.copy` (currently just `resolv.conf`); `templates/`
  holds Jinja2 files rendered via `ansible.builtin.template` for values
  that vary (journald limits, zram config, eth0's static IP, k3s config).
- `vector_gcp_project_id`/`vector_gcp_credentials_json` (used by
  `roles/vector`) follow the same per-variable vault-encryption pattern,
  in `group_vars/rpi3/vector.yml` — the GCP project ID and service
  account key must never be committed to this public repository either.
  See the "Vector log export" section of `README.md` for the exact
  commands.
- `wireguard_peer_public_key`/`wireguard_peer_allowed_ips`/
  `wireguard_peer_endpoint` (used by `roles/wireguard`) follow the same
  per-variable vault-encryption pattern, shared by both boards (same
  remote VPN server) in `group_vars/all/wireguard.yml`; each host's
  plaintext `wireguard_enabled`/`wireguard_address` live in
  `group_vars/rpi4/wireguard.yml`/`group_vars/rpi3/wireguard.yml`. See
  the "WireGuard VPN" section of `README.md` for the exact commands.
- `.envrc` and `scripts/ansible-vault-password.sh` give non-interactive vault
  password delivery (`ANSIBLE_VAULT_PASSWORD_FILE`) via direnv + gopass.
- Values a role's tasks may need to vary (package lists, the DNS resolver
  package/service name, etc.) live in that role's `defaults/main.yml`
  rather than being hardcoded in `tasks/main.yml`.
- `k3s_version` (in `playbook.yml`) is validated by an `assert` in
  `roles/k3s/tasks/main.yml` against `v[0-9]+\.[0-9]+\.[0-9]+\+k3s[0-9]+`;
  the task compares the installed version to it and only reinstalls on
  mismatch. Bump this var to upgrade k3s; valid channel/version values are
  listed at <https://update.k3s.io/v1-release/channels>.
- Nearly every task uses `become: true` and guards apt cache updates with
  `cache_valid_time: 3600`, following the existing pattern for any new apt-based
  task.
- Every role has a `meta/main.yml` with `dependencies: []` — roles are
  self-contained and don't depend on each other via Ansible role
  dependencies; ordering between them is expressed solely by their position
  in `playbook.yml`'s `roles:` list.

## CI (GitHub Actions, all under `.github/workflows/`)

- `ansible.yaml` — runs `make check` on push to `main` and on PRs.
- `conftest.yaml` — runs `conftest` against `.github` using an external,
  personal policy bundle (`iamleot/conftest-policies`), on push to `main` and PRs.
- `check-markdown-files.yml` — `markdownlint-cli2` + `lychee` link checking,
  scoped to `**.md` changes.
- Dependency updates are handled by both Dependabot (`.github/dependabot.yml`,
  GitHub Actions only) and Renovate (`renovate.json`, which also has a custom
  regex manager to track the `CONFTEST_VERSION` pin inside the workflow YAML
  files).

## Conventions worth preserving

- Every task in `roles/*/tasks/main.yml` has a trailing-period, capitalized
  `name:` (e.g. `Install unbound if needed.`) — match this style for new
  tasks. Every `tasks/main.yml` starts with a `---` and a short
  `#`-comment block describing the role's purpose.
  Idempotency-sensitive shell steps use `creates:` / `changed_when:` rather than
  free-running shell commands.
- Markdown must pass `markdownlint-cli2` (`.markdownlint-cli2.yaml`: ATX
  headers, 80-char line length except in tables/code blocks) and `lychee`
  link checking (add unreachable/intentional URLs to `.lycheeignore` rather
  than disabling the check).

## README.md editing principles

`README.md` is written for three personas — Junior DevOps Engineer, Senior
Software Engineer, and Sysadmin — each of whom may skim for a different
section; no single persona's needs should dictate the whole structure. Any
edit to `README.md` (including a full rewrite) must follow these five rules:

1. **Organization.** Order sections in a logical, task-oriented reading
   order — what a reader needs first, comes first. Any README section list
   over roughly 100 lines needs a table of contents. Keep initial-setup
   content and ongoing-maintenance content in visibly separate sections,
   not interleaved.
2. **Clarity.** Write short, well-structured sentences. State a pattern or
   explanation once and reference it afterward from other sections — don't
   restate it near-verbatim in multiple places. Gloss jargon/tooling names
   (`k3s`, `zram`, `journald`, WireGuard, `ifupdown`, and similar) with a
   short explanation or a link on first mention, since not every reader
   already knows them.
3. **Skimmability.** Default to concise; prefer headings and lists over
   dense paragraphs. Only go verbose where a step is genuinely crucial or
   non-obvious (e.g. a manual step Ansible can't automate).
4. **Comprehension.** Never drop a manual/non-automatable step when
   editing — these document things Ansible cannot do for the reader, and
   cutting them silently breaks the setup, not just the prose.
5. **References.** Link to official docs inline on first mention of a
   tool/technology, and keep a "See also" section at the end that collects
   further reading, rather than leaving references scattered through the
   body only.
