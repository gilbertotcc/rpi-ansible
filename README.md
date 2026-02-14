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

To avoid hardcoding sensitive information such as the WiFi password, configure
the WiFi network manually. Edit `/etc/network/interfaces.d/wlan0` with the
following content.

```none
# To enable wireless networking, uncomment the following lines and -naturally-
# replace with your network's details.
#
# allow-hotplug wlan0
# iface wlan0 inet dhcp
# iface wlan0 inet6 dhcp
#     wpa-ssid my-network-ssid
#     wpa-psk s3kr3t_P4ss
allow-hotplug wlan0
iface wlan0 inet dhcp
    wpa-ssid <NETWORK>
    wpa-psk <PASSWORD>
```

Where `<PASSWORD>` must be replaced with the wifi password for network
`<NETWORK>`.

Further improvements on this will be addressed in issue
<https://github.com/gilbertotcc/rpi-ansible/issues/2>.

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
