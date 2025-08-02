# BassToonVPN
BassToonVPN is an interactive tool for setting up hub-and-spoke WireGuard VPNs:
- Configures NAT masquerading (clients will access the Internet through the server's IP address);
- Supports the initial installation and the addition of new clients (up to 254 in total);
- Requires only a few common Linux utilites;
- It can also print QR codes to your terminal for setting up mobile devices.

BassToonVPN is meant for technical enthusiasts who are comfortable with the command line and are looking for a simple setup with minimal configuration necessary - all you need is a Linux virtual or physical machine with a public IP address and SSH (or console) access.
For a more comprehensive solution with a friendly Web-based UI, you probably want [wg-easy](https://github.com/wg-easy/wg-easy).

## Usage
1. Set up an SSH key on your system: `ssh-keygen`
2. Configure your SSH key for access to a root user on the remote machine
3. Download, install, and run the script and follow the interactive prompts:
    ```bash
    curl -s https://raw.githubusercontent.com/valentindimov/BassToonVPN/refs/heads/main/basstoonvpn.sh > /usr/local/bin/basstoonvpn
    sudo chown root:root /usr/local/bin/basstoonvpn
    sudo chmod 0555 /usr/local/bin/basstoonvpn
    basstoonvpn
    ```

To add more clients to an already-installed VPN server, simply run `basstoonvpn` and follow the interactive prompts again.

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
