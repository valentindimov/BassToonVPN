# BassToonVPN
BassToonVPN is an interactive tool for setting up hub-and-spoke WireGuard VPNs:
- Configures NAT masquerading (clients will access the Internet through the server's IP address);
- Supports the initial installation and the addition of new clients (up to 254 in total);
- Requires only a few common Linux utilites;
- It can also print QR codes to your terminal for setting up mobile devices.

BassToonVPN is meant for technical enthusiasts who are comfortable with the command line and are looking for a simple setup with minimal configuration necessary - all you need is a Linux virtual or physical machine with a public IP address and SSH (or console) access.
For a more comprehensive solution with a friendly Web-based UI, you probably want [wg-easy](https://github.com/wg-easy/wg-easy).

## Usage
The script [basstoonvpn.sh](./basstoonvpn.sh) offers a command-line interface.
- To set up the VPN on the remote server or add a client to the VPN if it's already installed:
    ```bash
    ./basstoonvpn.sh user@remote.server.ip.address add <mode: qr/text>
    ```
    Depending on the `mode` argument, the WireGuard config file for the new client is printed as text or as a scannable QR code to the terminal.
- To uninstall the VPN from a remote server, evicting all clients and shutting down the VPN:
    ```bash
    ./basstoonvpn.sh user@remote.server.ip.address reset
    ```
    If you connected to the server via VPN to do this, your connection will probably drop, but the uninstall should have worked regardless.

Note that before doing this, you need to have created an SSH key on your PC (`ssh-keygen`) and set up the remote VM to allow SSH access using this key.

## Installation
The script doesn't require installation, but if you want, you can download and install it by running the following command in your terminal:
```bash
curl -s https://raw.githubusercontent.com/valentindimov/BassToonVPN/refs/heads/main/basstoonvpn.sh > /usr/local/bin/basstoonvpn
sudo chown root:root /usr/local/bin/basstoonvpn
sudo chmod 0555 /usr/local/bin/basstoonvpn
```
From that point on you can call the script simply by using `basstoonvpn`.
To update the script, just rerun the above commands again.

### WARNING: BassToonVPN is designed for dedicated servers!
BassToonVPN assumes the remote server is a dedicated physical device or VM.
It can install required dependencies, uninstall packages that can conflict with it, and it will completely overwrite the server's firewall configuration.

### SSH after setup
BassToonVPN configures the host's firewall such that only the WireGuard service (UDP port 51820) is publicly accessible.
It also allows SSH connections to the host, but only from inside the VPN.
If you want to SSH to the host after initially installing the VPN, you need to activate your VPN connection and connect to `192.168.103.1`.

## Requirements
Currently BassToonVPN supports Debian or Ubuntu systems and requires `curl`, `wireguard-tools` (more specifically the `wg-quick` utility), and `nftables` to be installed on the remote server. `qrencode` needs to be installed locally to display QR codes..

When the VPN is first set up on the remote server, dependencies will be installed, and the `iptables` and `firewalld` packages will be removed if they are installed since they can interfere with its firewall configuration.

The script can be ported to other Linux distros rather easily, you just need to replace the `apt-get` commands with the corresponding alternative on your system.

## Future functionality
The following will be worked on in the future:
- Output the client configuration into a .conf file
- List clients in the VPN
- Delete clients from the VPN
- Extend the number of possible clients
