# RPI Ansible

[Ansible](https://www.ansible.com/) repository of personal Kubernetes
single-node cluster powered by [k3s](https://k3s.io/) on the latest Debian
stable running on a
[Raspberry Pi 4 Model B](https://www.raspberrypi.com/products/raspberry-pi-4-model-b/)
(RPI4).

> :warning: Everything here is done just for fun; things will likely break,
> readers beware!

## Acknoledgements

I thank @iamleot for his work
[iamleot/rpi-ansible](https://github.com/iamleot/rpi-ansible) from which I
created this fork.
This repository includes code that he further added in original codebase to
keep this project up-to-date and well-maintained.

## Initial setup

The following steps explain how to install a Debian distro on the RPI4 and
configure it.

### Prepare the microSD card

Debian GNU/Linux images for Raspberry Pis are available at
<https://raspi.debian.net/daily-images/>.

For RPI4, you can download it with:

```sh
curl -OL 'https://raspi.debian.net/daily/raspi_4_bookworm.img.xz'
curl -OL 'https://raspi.debian.net/daily/raspi_4_bookworm.img.xz.sha256'
```

Then, write the image to a microSD card.

> :information_source: The example below is based on an `xzcat` run on NetBSD,
> where `sd0` corresponds to the microSD card.
> You can use equivalent commands on other OSes.

```sh
xzcat raspi_4_bookworm.img.xz | dd of=/dev/rsd0 bs=1m
```

### Your first run

During the first boot, you need to use an HDMI monitor and an attached keyboard.
Alternatively, you can use a
[serial console connection](#serial-console-connection).

You can login as `root`, it does not have any password.

Once you've logged in, at first, upgrade all the packages:

```sh
apt update
apt upgrade
```

Then, install Python that is required to use Ansible:

```sh
apt install python3
```

## Manual configurations

### WiFi network

WiFi is configured by the `wireless` Ansible role
(`roles/wireless/tasks/main.yml`), which installs `wpasupplicant` and
templates `/etc/network/interfaces.d/wlan0` for you. It is disabled by
default (`wireless_enabled: false`) so a fresh clone never needs any WiFi
setup at all.

To avoid ever committing the SSID/password in plaintext, both are stored as
individually [vault-encrypted](https://docs.ansible.com/ansible/latest/vault_guide/vault_encrypting_content.html)
variables in a committed `group_vars/rpi/wireless.yml` file. Encrypting the
SSID too (not just the password) matters because this repo is public: a
real home network name in git history can be cross-referenced against
wardriving databases (e.g. WiGLE) back to a real location.

To set it up, pick a vault password (store it in a password manager — you
will need it for every future `make run`), then generate the two encrypted
blocks. Reading from stdin, rather than passing the values as command-line
arguments, keeps them out of your shell history:

```sh
ansible-vault encrypt_string --ask-vault-pass --stdin-name 'wireless_ssid'
# type your network's SSID, then press Ctrl-D
ansible-vault encrypt_string --ask-vault-pass --stdin-name 'wireless_psk'
# type your network's password, then press Ctrl-D
```

Create `group_vars/rpi/wireless.yml` with `wireless_enabled: true` plus the
two blocks output above, e.g.:

```yaml
---
wireless_enabled: true
wireless_ssid: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          66386439653236336462626566653063336164663966303231363934653561363...
wireless_psk: !vault |
          $ANSIBLE_VAULT;1.1;AES256
          32643361393835653136306164393433656333383761346130336436393730323...
```

Then commit that file and apply it, supplying the vault password:

```sh
make run ANSIBLE_PLAYBOOK="ansible-playbook --ask-vault-pass"
```

For this deployment, the vault password is kept in
[gopass](https://www.gopass.pw/) (secret name `Devices/rpi-ansible-vault`)
rather than typed from memory. Feed it to `ansible-playbook` directly
instead of the interactive prompt:

```sh
ansible-playbook \
  --vault-password-file <(gopass show -o Devices/rpi-ansible-vault) \
  --verbose playbook.yml
```

The interface comes up on next boot; to bring it up immediately without
rebooting, run `ifup wlan0` on the Pi (the role does not do this
automatically, since restarting the interface could drop the very SSH
session applying the change if the Pi is currently reached over WiFi).

## Serial console connection

To establish a serial console connection, connect the USB-to-TTL cable leads to
the GPIO header located on the edge of the RPI4 board.

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

The diagram below represents the top-left corner of the Raspberry Pi 4 GPIO
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
