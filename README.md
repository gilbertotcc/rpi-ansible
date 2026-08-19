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

Debian GNU/Linux images for Raspberry Pis are available at
<https://cloud.debian.org/images/cloud/trixie/daily/latest/>. The same
`raspi-arm64` image works for both RPi4 and RPi3.

You can download it with:

```sh
curl -OL 'https://cloud.debian.org/images/cloud/trixie/daily/latest/debian-13-raspi-arm64-daily.tar.xz'
curl -OL 'https://cloud.debian.org/images/cloud/trixie/daily/latest/SHA512SUMS'
```

The download is a `.tar.xz` archive wrapping a single raw disk image
(`disk.raw`); extract it before writing to a microSD card:

```sh
tar xf debian-13-raspi-arm64-daily.tar.xz
```

Then, write the image to a microSD card; adapt the device path for
yours. On macOS:

```sh
diskutil list                      # find the card's device, e.g. disk2
diskutil unmountDisk /dev/disk2
sudo dd if=disk.raw of=/dev/disk2 bs=1m status=progress
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

The first-boot setup process prompts you to configure a timezone (safe
to skip) and to set a root password — do set one here.

> :warning: Do not leave the root password blank. This image's
> installer does not create any regular user account, and Debian's
> usual convention is that leaving root's password blank at install
> time is precisely what triggers automatically installing and
> granting `sudo` to a created user account. Since no such user exists
> here, leaving root's password unset means
> **no account will ever be able to log in again**. See
> <https://lists.debian.org/debian-user/2025/04/msg00244.html> for the
> underlying explanation.

Once set, login as `root` with the password you just chose.

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

Then, install Python and an SSH server, both required for Ansible to
manage the board:

```sh
apt install python3 openssh-server
```

Permit root login over SSH by setting the following in
`/etc/ssh/sshd_config`:

```none
PermitRootLogin yes
```

then restart the service:

```sh
systemctl restart ssh
```

Finally, from the machine you run Ansible from, trust your SSH key on
the board:

```sh
ssh-copy-id -i ~/.ssh/keys/key.pub root@<IP_ADDRESS>
```

and verify the login works:

```sh
ssh -i ~/.ssh/keys/key root@<IP_ADDRESS>
```

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

The connection requires a _crossover_ configuration: The cable's Receiver (RX)
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
- [rpi-flux](https://github.com/gilbertotcc/rpi-flux)
