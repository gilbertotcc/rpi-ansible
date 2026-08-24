# RPi Ansible

This is an [Ansible](https://www.ansible.com/) repository for two personal
Raspberry Pi boards, both running the latest Debian stable. A
[Raspberry Pi 4 Model B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)
(RPi4) runs a single-node Kubernetes cluster powered by
[k3s](https://k3s.io/) (a lightweight Kubernetes distribution). A
[Raspberry Pi 3 Model B](https://www.raspberrypi.com/products/raspberry-pi-3-model-b/)
(RPi3) is a second, lighter-weight board: it runs Prometheus Node Exporter,
exposing host metrics for the RPi4-managed Prometheus to scrape, and
[Vector](https://vector.dev/), forwarding its logs to Google Cloud Logging.

> :warning: Everything here is done just for fun; things will likely break,
> readers beware!

## Table of contents

- [Requirements](#requirements)
- [Board setup](#board-setup)
  - [Prepare the microSD card](#prepare-the-microsd-card)
  - [Your first run](#your-first-run)
- [Serial console connection](#serial-console-connection)
- [Configuration and manual setup](#configuration-and-manual-setup)
  - [Configuration variables](#configuration-variables)
  - [Ansible Vault password](#ansible-vault-password)
  - [Ethernet network](#ethernet-network)
  - [WireGuard VPN](#wireguard-vpn)
  - [Vector log export](#vector-log-export)
- [Maintenance](#maintenance)
  - [Upgrading Debian](#upgrading-debian)
- [Monitoring](#monitoring)
- [Acknowledgements](#acknowledgements)
- [See also](#see-also)

## Requirements

Hardware:

- A
  [Raspberry Pi 4 Model B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)
  or
  [Raspberry Pi 3 Model B](https://www.raspberrypi.com/products/raspberry-pi-3-model-b/)
  with its power supply.
- A microSD card, and a way to write an image to it (e.g. a card reader
  on the machine you run Ansible from).
- Either an HDMI monitor and keyboard for the first boot, or a
  USB-to-TTL serial cable (see
  [Serial console connection](#serial-console-connection)). This
  applies to RPi4; on RPi3 the serial console is not enabled by
  default, so a monitor and keyboard are mandatory for the first boot
  (see [Your first run](#your-first-run)).

Software, on the machine you run Ansible from (not the Pi itself):

- [Ansible](https://www.ansible.com/).
- An SSH client, with a key trusted by the Pi's `root` account (see
  [Your first run](#your-first-run) for how to install and trust it).

On the Pi itself, only Python 3 and an SSH server are required beyond
the base Debian install, for Ansible to reach it and run its modules.

## Board setup

The following steps explain how to install Debian on either board and
get it ready for Ansible. Where a step differs between RPi3 and RPi4,
it's called out explicitly.

### Prepare the microSD card

Debian images for Raspberry Pis are available at
<https://raspi.debian.net/daily/>. Each board uses its own image:
`raspi_3_bookworm.img.xz` for RPi3, `raspi_4_bookworm.img.xz` for RPi4.
The `raspi-arm64` image from
<https://cloud.debian.org/images/cloud/trixie/daily/latest/> was tried
first, but its hybrid GPT/MBR layout could leave RPi3 unbootable when
its root partition was expanded (see
[issue #54](https://github.com/gilbertotcc/rpi-ansible/issues/54)). The
`raspi.debian.net` images use a plain MBR layout and resize the root
filesystem to fill the microSD card automatically on first boot.

Download the image for your board along with its checksum:

```sh
curl -OL 'https://raspi.debian.net/daily/raspi_3_bookworm.img.xz'        # RPi3
curl -OL 'https://raspi.debian.net/daily/raspi_3_bookworm.img.xz.sha256'
```

Verify it, then write it straight to a microSD card — it decompresses
on the fly, no separate extraction step is needed; adapt the device
path for yours. On macOS:

```sh
shasum -a 256 -c raspi_3_bookworm.img.xz.sha256
diskutil list                      # find the card's device, e.g. disk2
diskutil unmountDisk /dev/disk2
xzcat raspi_3_bookworm.img.xz | sudo dd of=/dev/disk2 bs=1m status=progress
```

### Your first run

During the first boot, log in using an HDMI monitor and an attached
keyboard.

- On RPi4, you can instead use a
  [serial console connection](#serial-console-connection) from the
  very first boot.
- On RPi3, the serial console is not enabled by default, so a monitor
  and keyboard are required for this first login; it can only be used
  after completing the steps below at least once (see
  [Serial console connection](#serial-console-connection)).

> :information_source: Connect the board to your router over Ethernet
> for this section — it's this board's permanent network connection
> (see [Ethernet network](#ethernet-network)), and it's also what gets
> you online for the package/SSH setup below.

The image ships with no root password: at the login prompt, enter
`root` as the username and press `Enter` for the password.

Once logged in, check the board's IP address — you'll need it for the
SSH steps below and for `hosts.ini`:

```sh
ip addr show
```

Then, upgrade all the packages:

```sh
apt update
apt upgrade
```

Python is the only package still missing; install it (an SSH server is
already included in the image):

```sh
apt install python3
```

Since root has no password yet, permit root login over SSH and
temporarily allow empty-password logins by setting the following in
`/etc/ssh/sshd_config`:

```none
PermitRootLogin yes
PermitEmptyPasswords yes
```

then restart the service:

```sh
systemctl restart ssh
```

Finally, from the machine you run Ansible from, trust your SSH key on
the board (press `Enter` when prompted for the empty password):

```sh
ssh-copy-id -i ~/.ssh/keys/key.pub root@<IP_ADDRESS>
```

and verify the login works:

```sh
ssh -i ~/.ssh/keys/key root@<IP_ADDRESS>
```

Once key-based login is confirmed, close the empty-password window: remove
`PermitEmptyPasswords yes` from `/etc/ssh/sshd_config` and restart `ssh`
again.

## Serial console connection

A serial console gives you a login prompt over a USB-to-TTL cable instead
of an HDMI monitor and keyboard — useful for headless boards or once a
monitor isn't convenient anymore. To establish one, connect the
USB-to-TTL cable leads to the GPIO header located on the edge of the
board — RPi3 and RPi4 share the same 40-pin header and pin layout.

> :information_source: On RPi3, this connection only becomes usable
> after the first boot has been completed via monitor and keyboard —
> see [Your first run](#your-first-run).

<!-- -->

> :warning: DO NOT connect the Red (5V) wire.
> Connecting it will damage the board.

The connection requires a *crossover* configuration: The cable's Receiver (RX)
connects to the Pi's Transmitter (TX), and vice versa.

| Wire Color | Cable Function | Connect to Pi Pin | Pi Pin Function | Description                                           |
| :--------- | :------------- | :---------------- | :-------------- | :---------------------------------------------------- |
| **Red**    | 5V VCC         | **NC**            | 5V Power        | **Leave Disconnected**                                |
| **Black**  | GND            | **Pin 6**         | Ground          | Common Ground reference                               |
| **White**  | RX (Receive)   | **Pin 8**         | GPIO 14 (TXD)   | Pi transmits data → Cable receives                    |
| **Green**  | TX (Transmit)  | **Pin 10**        | GPIO 15 (RXD)   | Cable transmits data → Pi receives                    |

The diagram below represents the top-left corner of the Pi's GPIO
header (the end closest to the SD card slot).
Connections are made to the outer row of pins.

```text
      [Edge of Board]
      
      (3V3)  [01]  [02]  (5V)
      (SDA)  [03]  [04]  (5V)
      (SCL)  [05]  [06]  GND  <─── Connect BLACK Wire
      (GP4)  [07]  [08]  TXD  <─── Connect WHITE Wire
      (GND)  [09]  [10]  RXD  <─── Connect GREEN Wire
             [11]  [12]  (GP18)
             ...   ...
```

On macOS, you can use `screen` to connect to the board with this command:

```sh
screen /dev/cu.usbserial-1140 115200
```

where `cu.usbserial-1140` is the device representing the serial connection.

To close the serial communication session use the following commands to get the
session ID and close it.

```sh
screen -ls
screen -r <SESSION_ID>
```

Or you can type `C-a C-d`.

## Configuration and manual setup

The sections below cover everything Ansible can't fully automate for you
before `make run` does anything useful for a given host: variables you must
set, and one-time manual steps (generating a vault password, registering a
device with a remote server) that only you can perform. Several roles
(`wireguard`, `vector`) share the same safety pattern: each defaults to
its `*_enabled` variable set to `false`, so a fresh clone of this
repository needs no extra setup just to pass `make check`/lint — you
opt a host in explicitly, as covered in each section below.

### Configuration variables

Before `make run` does anything useful, define these variables in the
listed files. Each is covered in full, with the exact commands to set
it, in its own subsection below.

**[Network](#ethernet-network):**

- `network_hostname` — required — the hostname to set on the board —
  `group_vars/<group>/network.yml` (`group_vars/rpi4/network.yml`,
  `group_vars/rpi3/network.yml`).
- `network_address` — required — that host's static IP for `eth0`, in
  CIDR notation — `group_vars/<group>/network.yml`.
- `network_gateway` — required — that host's network gateway IP —
  `group_vars/<group>/network.yml`.

**[WireGuard VPN](#wireguard-vpn):**

- `wireguard_enabled` — optional, defaults to `false` — enables the
  `wireguard` role for that host — `group_vars/<group>/wireguard.yml`.
- `wireguard_peer_public_key` — required when `wireguard_enabled: true`
  (vault-encrypted) — the remote VPN peer's public key —
  `group_vars/all/wireguard.yml`.
- `wireguard_peer_allowed_ips` — required when `wireguard_enabled: true`
  — the tunnel subnet allowed through the peer, e.g. `10.254.10.0/24`
  — `group_vars/all/wireguard.yml`.
- `wireguard_peer_endpoint` — required when `wireguard_enabled: true`
  (vault-encrypted) — the remote peer's `host:port` —
  `group_vars/all/wireguard.yml`.
- `wireguard_address` — required when `wireguard_enabled: true` — that
  host's tunnel IP for `wg0`, in CIDR notation —
  `group_vars/<group>/wireguard.yml`.

**[Vector log export](#vector-log-export)** (RPi3 only):

- `vector_enabled` — optional, defaults to `false` — enables the
  `vector` role — `group_vars/rpi3/vector.yml`.
- `vector_gcp_project_id` — required when `vector_enabled: true`
  (vault-encrypted) — the GCP project ID logs are written to —
  `group_vars/rpi3/vector.yml`.
- `vector_gcp_credentials_json` — required when `vector_enabled: true`
  (vault-encrypted) — the downloaded service account key JSON —
  `group_vars/rpi3/vector.yml`.

### Ansible Vault password

Several variables above (WireGuard's peer details, Vector's GCP
credentials) are stored
[vault-encrypted](https://docs.ansible.com/ansible/latest/vault_guide/vault_encrypting_content.html#encrypting-individual-variables-with-ansible-vault)
rather than in plaintext, since this repository is public. Each is
decrypted with the vault password you choose the first time you run
`ansible-vault encrypt_string` (see the sections below for the exact
commands). You'll need that same password for every `make run` that
touches vault-encrypted content, so store it somewhere retrievable (a
password manager or secrets vault) rather than relying on memory.

By default you'll be asked for it interactively:

```sh
make run ANSIBLE_PLAYBOOK="ansible-playbook --ask-vault-pass"
```

If you'd rather not retype it on every run, point Ansible at a script
that prints it instead, via the
[`ANSIBLE_VAULT_PASSWORD_FILE`](https://docs.ansible.com/ansible/latest/reference_appendices/config.html#envvar-ANSIBLE_VAULT_PASSWORD_FILE)
environment variable. Any password manager with a CLI that can print a
secret to stdout works; the steps below use
[gopass](https://www.gopass.pw/) as a concrete example — substitute your
own tool (1Password CLI, `pass`, etc.) if you use something else.

1. Store the vault password in gopass:

   ```sh
   gopass insert Devices/rpi-ansible-vault
   ```

2. Install [direnv](https://direnv.net/) and hook it into your shell (see
   its install docs).
3. Allow this repository's `.envrc` once — it and
   `scripts/ansible-vault-password.sh` are already committed here:

   ```sh
   direnv allow
   ```

From then on, entering this directory exports
`ANSIBLE_VAULT_PASSWORD_FILE`, and plain `make run` decrypts without
prompting — no `ANSIBLE_PLAYBOOK` override needed — subject to however
your password manager caches its own unlock.

### Ethernet network

Both boards connect over Ethernet (`eth0`) as their primary network
connection. The `network` Ansible role (`roles/network/tasks/main.yml`)
sets the board's hostname and templates a static-IP config for `eth0`
via [ifupdown](https://wiki.debian.org/NetworkConfiguration#ifupdown)
(Debian's traditional network interface manager), at
`/etc/network/interfaces.d/eth0` — the same pattern used for `wg0` (see
[WireGuard VPN](#wireguard-vpn) below).

Set `network_address` (that host's static IP for `eth0`, CIDR notation)
and `network_gateway` in each host's `group_vars/<group>/network.yml`,
alongside the existing `network_hostname`, e.g.:

```yaml
---
network_hostname: rpi-202508
network_address: 192.168.1.25/24
network_gateway: 192.168.1.1
```

These aren't secret, so no vault-encryption is needed. Commit the file,
then apply it as described in
[Ansible Vault password](#ansible-vault-password) above (only needed if
other vault-encrypted variables are also pending for that host). The
static IP takes effect on next boot; to apply it immediately without
rebooting, run `ifup eth0` on the Pi (the role does not do this
automatically, since bringing the interface back up could drop the very
SSH session applying the change).

### WireGuard VPN

The `wireguard` Ansible role (`roles/wireguard/tasks/main.yml`) installs
[WireGuard](https://www.wireguard.com/) (a VPN protocol), idempotently
generates the node's private/public keypair (`/etc/wireguard/wg0` /
`/etc/wireguard/wg0.pub`, guarded by `creates:` so re-runs don't
regenerate them), templates `/etc/wireguard/wg0.conf` and an ifupdown
`interfaces.d/wg0` stanza, and brings the tunnel up — all in one
playbook run. `wg0` is brought up with plain `ip`/`wg` commands in
ifupdown's `pre-up`/`post-down` hooks, not `wg-quick`; activating a
config change restarts the `networking` service.

The one thing this repo can't automate is registering this node with
the remote WireGuard server, since that's a separate system outside
this repo's scope. Everything else is driven by variables:

1. Generate this node's keypair and read its public key. If the node
   already has one, skip straight to reading `/etc/wireguard/wg0.pub`;
   otherwise generate one by hand as `root` first, since the role only
   (re)generates keys once `wireguard_enabled` is already `true`:

   ```sh
   # only if /etc/wireguard/wg0 doesn't already exist
   (umask 0077; wg genkey > /etc/wireguard/wg0)
   wg pubkey < /etc/wireguard/wg0 > /etc/wireguard/wg0.pub
   cat /etc/wireguard/wg0.pub
   ```

   Register this key as a peer on the remote WireGuard server. The
   server must also allow this client's assigned tunnel address, e.g.
   `10.254.10.10/32`.

2. The peer's public key and endpoint are stored as individually
   vault-encrypted variables (see
   [Ansible Vault password](#ansible-vault-password) above), since even
   values that aren't secrets on their own (a public key, a hostname)
   can identify or locate the remote server if leaked through a public
   repo's git history. `wireguard_peer_allowed_ips` (the tunnel subnet,
   e.g. `10.254.10.0/24`) isn't identifying on its own, so it stays
   plaintext, same reasoning as `network_gateway`. Both boards share the
   same remote VPN server, so all three live once in a committed
   `group_vars/all/wireguard.yml`. Generate the encrypted blocks — the
   commands below assume `ANSIBLE_VAULT_PASSWORD_FILE` is already set
   (see [Ansible Vault password](#ansible-vault-password) above); pass
   `--ask-vault-pass` instead if you haven't set that up yet:

   ```sh
   ansible-vault encrypt_string --stdin-name 'wireguard_peer_public_key'
   # type the remote peer's public key, then press Ctrl-d
   ansible-vault encrypt_string --stdin-name 'wireguard_peer_endpoint'
   # e.g. vpn.example.com:51820, then press Ctrl-d
   ```

   Create (or edit) `group_vars/all/wireguard.yml` with the two
   encrypted blocks output above, plus the plaintext
   `wireguard_peer_allowed_ips`:

   ```yaml
   ---
   wireguard_peer_public_key: !vault |
             $ANSIBLE_VAULT;1.1;AES256
             66386439653236336462626566653063336164663966303231363934653561363...
   wireguard_peer_allowed_ips: 10.254.10.0/24
   wireguard_peer_endpoint: !vault |
             $ANSIBLE_VAULT;1.1;AES256
             39346137353339663836316133333061633837666561633363393062373238633...
   ```

3. This node's tunnel address isn't secret, so create (or edit) each
   host's `group_vars/<group>/wireguard.yml` with
   `wireguard_enabled: true` and its plaintext `wireguard_address`, e.g.:

   ```yaml
   ---
   wireguard_enabled: true
   wireguard_address: 10.254.10.10/24
   ```

4. Commit the files, then apply them as described in
   [Ansible Vault password](#ansible-vault-password) above. The role
   templates `wg0.conf`/`interfaces.d/wg0` and restarts the `networking`
   service to bring the tunnel up — no manual activation needed.

5. Verify the tunnel:

   ```sh
   wg show
   ping -I wg0 -c 3 <REMOTE_TUNNEL_IP>
   ```

   A working connection shows a `peer:` section, a recent
   `latest handshake`, and non-zero sent and received transfer
   counters.

### Vector log export

RPi3 runs [Vector](https://vector.dev/) via the `vector` Ansible role
(`roles/vector/tasks/main.yml`), forwarding its
[journald](https://www.freedesktop.org/software/systemd/man/latest/systemd-journald.service.html)
(systemd's logging service) logs to Google Cloud Logging through
Vector's `gcp_stackdriver_logs` sink. The role installs Vector from its
official APT repository (guarded so the setup script only runs once, not
on every play), templates `/etc/vector/vector.yaml`, and writes the GCP
service account key to `/etc/rpi-observability/`.

The GCP project ID and the service account key are both stored as
individually vault-encrypted variables (see
[Ansible Vault password](#ansible-vault-password) above) in
`group_vars/rpi3/vector.yml`, since this repository is public and
neither should be committed in plaintext.

To set it up, first create a dedicated Google Cloud service account
scoped to only
[`roles/logging.logWriter`](https://cloud.google.com/logging/docs/access-control#logging_permission_types)
(Logs Writer) at the project level, so Vector can write log entries and
nothing else. Using the
[Cloud Console](https://console.cloud.google.com/iam-admin/serviceaccounts):

1. Enable the Cloud Logging API for your project, if it isn't already.
2. Under **IAM & Admin > Service Accounts**, create a new service
   account — give it a descriptive ID (e.g. `vector-cloud-logging`) and
   name.
3. Grant it only the **Logs Writer** (`roles/logging.logWriter`) role
   at the project level; skip any broader role.
4. Open the new service account's **Keys** tab, then
   **Add Key > Create new key > JSON**, and download it. Note where it lands
   locally — you'll reference that path below.

Never commit, print, or upload the downloaded key JSON anywhere — only
its service-account email and local file path are safe to share; see
[Best practices for managing service account keys](https://cloud.google.com/iam/docs/best-practices-for-managing-service-account-keys).
Getting the key onto the Pi itself is handled below and by the `vector`
role (`roles/vector/tasks/main.yml`), which writes it to
`/etc/rpi-observability/` with non-world-readable permissions — no
manual `scp`/`chmod` needed.

With the downloaded key file in hand, generate the two encrypted
blocks. The commands below assume `ANSIBLE_VAULT_PASSWORD_FILE` is
already set (see [Ansible Vault password](#ansible-vault-password)
above); pass `--ask-vault-pass` instead if you haven't set that up yet.
Reading from stdin, rather than passing the values as command-line
arguments, keeps them out of your shell history:

```sh
ansible-vault encrypt_string --stdin-name 'vector_gcp_project_id'
# type your GCP project ID, then press Ctrl-d
ansible-vault encrypt_string --stdin-name 'vector_gcp_credentials_json' < path/to/key.json
```

Edit `group_vars/rpi3/vector.yml` with `vector_enabled: true` and the
two encrypted blocks output above:

```yaml
---
vector_enabled: true
vector_gcp_project_id: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          66386439653236336462626566653063336164663966303231363934653561363...
vector_gcp_credentials_json: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          32643361393835653136306164393433656333383761346130336436393730323...
```

Commit the file, then apply it as described in
[Ansible Vault password](#ansible-vault-password) above. To validate
it's working:

```sh
vector validate /etc/vector/vector.yaml
systemctl status vector.service
logger -t rpi3-vector-poc "Cloud Logging test $(date --iso-8601=seconds)"
```

Then check the Google Cloud Logs Explorer for the tagged test event.

## Maintenance

Unlike the sections above, this covers ongoing upkeep for a board that's
already set up and running — not part of the first-time setup.

### Upgrading Debian

Debian's current stable release is tracked at
<https://www.debian.org/releases/> — check there before upgrading.
The steps below are a manual, in-place major-version upgrade, worked
through here as `bookworm` to `trixie` on RPi3; the same steps apply
to any future release jump, substituting the relevant codenames. This
isn't yet automated by Ansible — perform it by hand, as `root` on the
Pi.

> :warning: This is a major-version jump: expect interactive prompts
> for service restarts and configuration-file conflicts, and keep a
> way to reach the board (console/SSH) in case networking breaks
> mid-upgrade.

1. Fully upgrade the current release first:

   ```sh
   apt full-upgrade
   ```

2. Edit `/etc/apt/sources.list`: comment out the current release's
   entries and add the new release's, e.g.:

   ```none
   #deb http://deb.debian.org/debian bookworm main non-free-firmware non-free
   #deb http://deb.debian.org/debian bookworm-updates main non-free-firmware non-free
   #deb http://security.debian.org/debian-security bookworm-security main non-free-firmware non-free

   deb http://deb.debian.org/debian trixie main non-free-firmware non-free
   deb http://deb.debian.org/debian trixie-updates main non-free-firmware non-free
   deb http://security.debian.org/debian-security trixie-security main non-free-firmware non-free
   ```

3. Pull in the new release's packages:

   ```sh
   apt update
   apt upgrade
   ```

   You'll be prompted to restart services; do so. You may also be
   prompted to keep or replace configuration files (e.g.
   `journald.conf`) — when unsure, keep the local version: roles like
   `roles/journald` re-template their managed files on the next
   Ansible run anyway.

4. Run `apt full-upgrade` again to pull in whatever the first pass
   left pending (renamed/transitional packages, a new kernel image,
   and similar dependency churn) — expect a large changeset here.

5. Reboot to load the new kernel and cleanly restart every service:

   ```sh
   systemctl reboot
   ```

6. SSH back in and confirm the board's services still work (e.g.
   `curl -fsS http://<rpi3-address>:9100/metrics | head` — see
   [Monitoring](#monitoring)), then re-run Ansible against just that
   host to confirm it's still idempotent post-upgrade:

   ```sh
   ansible-playbook playbook.yml --limit=rpi3
   ```

7. Purge residual packages from the previous release. After confirming the
   upgraded system boots and runs correctly, inspect for packages in the `rc`
   state (removed packages with residual configuration files):

   ```sh
   dpkg -l | grep '^rc'
   ```

   Purge any obsolete residual packages you no longer need, such as old kernel
   packages from the previous Debian release:

   ```sh
   apt purge <package-name>...
   ```

   Optionally preview and remove automatically installed dependencies that are
   no longer required:

   ```sh
   apt autoremove --purge --simulate
   apt autoremove --purge
   ```

## Monitoring

RPi3 runs
[Prometheus Node Exporter](https://github.com/prometheus/node_exporter) via the
`node_exporter` Ansible role, exposing host metrics (CPU, load, memory,
filesystem, disk I/O, network, and a handful of systemd unit statuses)
at `http://<rpi3-address>:9100/metrics`. The role only installs and runs
the exporter; it does not itself deploy Prometheus or Grafana. Scraping
is owned by the Prometheus instance already running on RPi4 (managed
separately through Flux) — registering RPi3 as a scrape target and any
Grafana dashboard work happen there, not in this repository. Port 9100
should stay private to the home LAN.

To validate the exporter is up after a run targeting RPi3:

```sh
curl -fsS http://<rpi3-address>:9100/metrics | head
```

RPi3's logs (as opposed to metrics) are handled separately, via the
`vector` role forwarding journald to Google Cloud Logging — see
[Vector log export](#vector-log-export) above.

## Acknowledgements

I thank @iamleot for his work
[iamleot/rpi-ansible](https://github.com/iamleot/rpi-ansible) from which I
created this fork.
This repository includes code that he further added in original codebase to
keep this project up-to-date and well-maintained.

## See also

- [Ansible Vault documentation](https://docs.ansible.com/ansible/latest/vault_guide/index.html)
- [k3s documentation](https://docs.k3s.io/)
- [Prometheus Node Exporter](https://github.com/prometheus/node_exporter)
- [Vector documentation](https://vector.dev/docs/)
- [Serial communication over UART Raspberry Pi 4](https://forums.raspberrypi.com/viewtopic.php?t=307094)
- [WireGuard — Debian Wiki](https://wiki.debian.org/WireGuard)
- [rpi-flux](https://github.com/gilbertotcc/rpi-flux)
