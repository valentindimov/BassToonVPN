# BassToonVPN
BassToonVPN is a relatively simple interactive tool for setting up WireGuard VPN servers:
- Configures NAT masquerading (clients will access the Internet through the server's IP address)
- Supports the initial installation and the addition of new clients (up to 253 in total)
- Requires only standard Linux utilites and the `wireguard-tools` package.
- It can also print QR codes to your terminal for setting up mobile devices.

BassToonVPN is meant for technical enthusiasts who are comfortable with the command line and are looking for a simple setup with minimal configuration necessary - all you need is a Linux virtual or physical machine with a public IP address and SSH (or console) access.
For a more comprehensive solution with a friendly Web-based UI, you probably want [wg-easy](https://github.com/wg-easy/wg-easy).

## Usage
On the system which will be your VPN server, download and run the script with root privileges and follow the interactive prompts:
```bash
curl -s https://raw.githubusercontent.com/valentindimov/BassToonVPN/refs/heads/main/basstoonvpn.sh > basstoonvpn.sh
chmod +x basstoonvpn.sh
sudo ./basstoonvpn.sh
```
The script can perform the initial configuration on the VPN server, or add new clients to an already-installed configuration.

### WARNING: BassToonVPN is designed for dedicated servers!
BassToonVPN is designed to run on a dedicated device or VM.
It may install required dependencies, uninstall packages that can conflict with it, and it will completely overwrite the host's firewall configuration.

### SSH after setup
BassToonVPN configures the host's firewall such that only the WireGuard service (UDP port 51820) is publicly accessible.
It also allows SSH connections to the host, but only from inside the VPN.
If you want to SSH to the host after initially installing the VPN, you need activate your VPN connection and connect to `192.168.103.1`.

## Requirements
Currently BassToonVPN supports Debian or Ubuntu systems and requires `curl`, `wireguard-tools` (more specifically the `wg-quick` utility), and `nftables` to be installed on the system. `qrencode` is also used for printing QR codes (useful e.g. for setting mobile clients).
When the VPN is first set up, it will try to install these dependencies itself, and it will also remove the `iptables` and `firewalld` packages if they are installed.

The script can be ported to other Linux distros rather easily, you just need to replace the `apt-get` commands with the corresponding alternative on your system.
