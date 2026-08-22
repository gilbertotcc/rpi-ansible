# RPi Ansible

[Ansible](https://www.ansible.com/) repository of personal Kubernetes
single-node cluster powered by [k3s](https://k3s.io/) on the latest Debian
stable running on a
[Raspberry Pi 4 Model B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)
(RPi4), plus a
[Raspberry Pi 3 Model B](https://www.raspberrypi.com/products/raspberry-pi-3-model-b/)
(RPi3) as a second, lighter-weight board.

> :warning: Everything here is done just for fun; things will likely break,
> readers beware!

## Acknoledgements

I thank @iamleot for his work
[iamleot/rpi-ansible](https://github.com/iamleot/rpi-ansible) from which I
created this fork.
This repository includes code that he further added in original codebase to
keep this project up-to-date and well-maintained.

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
> for this section. WiFi is not configured until the `wireless` role
> runs (see [WiFi network](#wifi-network)), so a wired connection is
> what gets you online for the package/SSH setup below.

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

## Manual configurations

### WiFi network

WiFi is configured by the `wireless` Ansible role
(`roles/wireless/tasks/main.yml`), which installs `ifupdown`,
`wpasupplicant`, `firmware-brcm80211`, and `wireless-regdb`, then
templates `/etc/network/interfaces.d/wlan0` for you. Both boards use WiFi
as their primary (often only) network connection, so in practice you'll
want it enabled for each. The role itself defaults to
`wireless_enabled: false` as a safe fallback, so a fresh clone doesn't
need any WiFi setup just to pass `make check`/lint.

To avoid ever committing the SSID/password in plaintext, both are stored
as individually
[vault-encrypted](https://docs.ansible.com/ansible/latest/vault_guide/vault_encrypting_content.html#encrypting-individual-variables-with-ansible-vault)
variables. Both boards are on the same real WiFi network, so the SSID
and PSK live once in a committed `group_vars/all/wireless.yml`, which
Ansible applies to every host in the inventory; per-host files
(`group_vars/rpi4/wireless.yml`, `group_vars/rpi3/wireless.yml`) hold
only `wireless_enabled` plus that host's plaintext `wireless_address`
(static IP, CIDR notation) and `wireless_gateway` — these aren't secret,
so they don't need vault-encrypting. Should a board ever join a
different network, override the SSID/PSK in that host's own
`group_vars/<group>/wireless.yml`, since Ansible resolves group_vars
files for more specific groups before `group_vars/all`. Encrypting the
SSID too (not just the password) matters if your repository is public:
a real network name in git history can be cross-referenced against
wardriving databases (e.g. WiGLE) back to a real location.

To set it up, pick a vault password, then generate the two encrypted
blocks. Reading from stdin, rather than passing the values as command-line
arguments, keeps them out of your shell history:

```sh
ansible-vault encrypt_string --ask-vault-pass --stdin-name 'wireless_ssid'
# type your network's SSID, then press Ctrl-d
ansible-vault encrypt_string --ask-vault-pass --stdin-name 'wireless_psk'
# type your network's password, then press Ctrl-d
```

Create (or edit) `group_vars/all/wireless.yml` with the two encrypted
blocks output above:

```yaml
---
wireless_ssid: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          66386439653236336462626566653063336164663966303231363934653561363...
wireless_psk: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          32643361393835653136306164393433656333383761346130336436393730323...
```

Then create (or edit) each host's `group_vars/<group>/wireless.yml` with
`wireless_enabled: true` and its `wireless_address`/`wireless_gateway`,
e.g.:

```yaml
---
wireless_enabled: true
wireless_address: 192.168.1.25/27
wireless_gateway: 192.168.1.1
```

Commit both files, then apply them as described in "Ansible Vault
password" below. The interface comes up on next boot; to bring it up
immediately without rebooting, run `ifup wlan0` on the Pi (the role does
not do this automatically, since restarting the interface could drop
the very SSH session applying the change if the Pi is currently reached
over WiFi).

### Ansible Vault password

`group_vars/all/wireless.yml` above — and any future vault-encrypted
variable — is decrypted with the vault password you chose when running
`encrypt_string`. You'll need it for every `make run` that touches
vault-encrypted content, so store it somewhere retrievable (a password
manager or secrets vault) rather than relying on memory.

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

### WireGuard VPN

The `wireguard` Ansible role (`roles/wireguard/tasks/main.yml`)
installs WireGuard and idempotently generates the node's private/public
keypair (`/etc/wireguard/wg0` / `/etc/wireguard/wg0.pub`, guarded by
`creates:` so re-runs don't regenerate them). It does not yet configure
the remote peer or bring the `wg0` interface up — see
[issue #21](https://github.com/gilbertotcc/rpi-ansible/issues/21) for
the plan to automate the rest. Until then, complete the tunnel setup
by hand, as `root` on the Pi:

1. Read this node's public key:

   ```sh
   cat /etc/wireguard/wg0.pub
   ```

   Register this key as a peer on the remote WireGuard server. The
   server must also allow this client's assigned tunnel address, e.g.
   `10.254.10.10/32`.

2. Create `/etc/wireguard/wg0.conf`:

   ```sh
   vim /etc/wireguard/wg0.conf
   ```

   ```ini
   [Interface]
   PrivateKey = <contents of /etc/wireguard/wg0>
   ListenPort = 51820

   [Peer]
   # Public key of the remote WireGuard peer/server, not this node's own key.
   PublicKey = <REMOTE_PEER_PUBLIC_KEY>
   AllowedIPs = 10.254.10.0/24
   Endpoint = <REMOTE_PUBLIC_IP_OR_DNS>:51820
   PersistentKeepalive = 25
   ```

   Replace the placeholders with the values supplied by the remote VPN
   administrator. `PrivateKey` is the actual Base64 key content from
   `/etc/wireguard/wg0`, not a path to that file; `PublicKey` under
   `[Peer]` is the *remote* peer's key, not this node's own
   `wg0.pub`.

   Restrict the file's permissions, since it embeds the private key:

   ```sh
   chmod 600 /etc/wireguard/wg0.conf
   ```

3. Create `/etc/network/interfaces.d/wg0`:

   ```sh
   vim /etc/network/interfaces.d/wg0
   ```

   ```none
   auto wg0
   iface wg0 inet static
           address 10.254.10.10/24
           pre-up wg-quick up $IFACE
           pre-down wg-quick down $IFACE
   ```

   Replace `10.254.10.10/24` with this node's assigned VPN address.

4. Activate the configuration:

   ```sh
   service networking restart
   ```

   Alternatively, reboot the node.

5. Verify the tunnel:

   ```sh
   wg show
   ping -I wg0 -c 3 <REMOTE_TUNNEL_IP>
   ```

   A working connection shows a `peer:` section, a recent
   `latest handshake`, and non-zero sent and received transfer
   counters.

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

## Serial console connection

To establish a serial console connection, connect the USB-to-TTL cable
leads to the GPIO header located on the edge of the board — RPi3 and
RPi4 share the same 40-pin header and pin layout.

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

On macOS, ou can use `screen` to connect to the board with this command:

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

Or you can tpye `C-a C-d`.

## See also

- [Serial communication over UART Raspberry Pi 4](https://forums.raspberrypi.com/viewtopic.php?t=307094)
- [WireGuard — Debian Wiki](https://wiki.debian.org/WireGuard)
- [rpi-flux](https://github.com/gilbertotcc/rpi-flux)
