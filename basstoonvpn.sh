#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

# Stop the script if any error occurs
set -eo pipefail

# Make sure that we are running with administrative privileges (we'll need to install things on the system, after all)
if [ "$UID" != "0" ]
then
	echo "Error: Please run this script as root (type: \"sudo $0\")"
	exit 1
fi

# Print warning that we'll be messing with system packages and firewall settings
echo "==================================================="
echo "BassToonVPN Setup"
echo "WARNING: This script is designed to be run on a bare, dedicated device or VM."
echo "It will install and uninstall packages from the system, and it will reset and reconfigure its firewall rules."
echo "==================================================="

DO_PROCEED=""
until [ "$DO_PROCEED" = "y" -o "$DO_PROCEED" = "n" ]
do
	read -p "Proceed with BassToonVPN setup? (y/n): " DO_PROCEED
done
if [ "$DO_PROCEED" != "y" ]
then
	echo "Cancelled."
	exit 1
fi

# ID of the client to be created, a number between 2 and 255.
CLIENT_ID="2"
DELETE_VPN_CONF="no"

# If a /etc/wireguard/basstoonvpn.conf already exists...
if [ -f /etc/wireguard/basstoonvpn.conf ]
then
	echo ""
	echo "==================================================="
	echo "Existing VPN configuration found."
	echo "==================================================="
	echo ""
	echo "There is already a VPN configuration installed."
	echo "Would you like to:"
	echo "1) Delete the old VPN and create a new one"
	echo "2) Add a new device to the existing VPN"
	echo "c) Cancel the installation"
	CHOSEN_OPTION=""
	until [ "$CHOSEN_OPTION" = "1" -o "$CHOSEN_OPTION" = "2" -o "$CHOSEN_OPTION" = "c" ] # 
	do
		read -p "Specify an option and press Enter (1, 2, c): " CHOSEN_OPTION
	done

	if [ "$CHOSEN_OPTION" == "c" ]
	then
		echo "Cancelled."
		exit 1
	elif [ "$CHOSEN_OPTION" == "1" ]
	then
		# We want to generate the whole config from scratch, so remove the old one
		DELETE_VPN_CONF="yes"
	else
		# Keep the old config, but extract the server private key and the next available client ID
		while 
			cat /etc/wireguard/basstoonvpn.conf | grep "192.168.103.$CLIENT_ID"
		do
			CLIENT_ID=$(($CLIENT_ID + 1))
		done
		if [ $CLIENT_ID -gt 255 ]
		then
			echo "Error: There are too many clients already registered (you can have at most 253)."
			exit 1
		fi
		# I love sed. Don't you? Of course you do.
		SERVER_PRIV_KEY=$(cat /etc/wireguard/basstoonvpn.conf | grep PrivateKey | sed -e "s/^PrivateKey\s*=\s*\([a-zA-Z0-9+\/\-_=]*\)\s*\$/\1/")
	fi
else
	echo "==================================================="
	echo "Setting up prerequisites. Just a moment..."
	echo "==================================================="
	# No VPN configuration found, this is probably a first install. Install prerequisites and remove firewalls that might mess with our setup
	apt-get update -y
	apt-get remove -y iptables firewalld 2> /dev/null || true
	apt-get install -y wireguard-tools nftables curl qrencode
fi


# Server private key is generated fresh, unless it was already taken from an existing config
if [ -z "$SERVER_PRIV_KEY" ]
then
	SERVER_PRIV_KEY="$(wg genkey)"
fi
SERVER_PUB_KEY="$(echo $SERVER_PRIV_KEY | wg pubkey)"

echo ""
echo "==================================================="
echo "Creating new client..."
echo "==================================================="
echo ""
echo "Would you like to:"
echo "1) Generate a client private key on the server and print out a full client config (simpler, but less secure)"
echo "2) Generate a client private key on the server and print out a QR code (useful for setting up smartphone clients)"
echo "3) Enter only the client public key (more secure but you must generate the private key yourself and add it to your client config manually)"
echo "c) Cancel the installation"
CHOSEN_OPTION=""
until [ "$CHOSEN_OPTION" = "1" -o "$CHOSEN_OPTION" = "2" -o "$CHOSEN_OPTION" = "3" -o "$CHOSEN_OPTION" = "c" ]
do
	read -p "Specify an option and press Enter (1, 2, 3, c): " CHOSEN_OPTION
done

PRINT_MODE="text"
if [ "$CHOSEN_OPTION" == "c" ]
then
	echo "Cancelled."
	exit 1
elif [ "$CHOSEN_OPTION" == "1" ]
then
	CLIENT_PRIV_KEY="$(wg genkey)"
	CLIENT_PUB_KEY="$(echo $CLIENT_PRIV_KEY | wg pubkey)"
elif [ "$CHOSEN_OPTION" == "2" ]
then
	CLIENT_PRIV_KEY="$(wg genkey)"
	CLIENT_PUB_KEY="$(echo $CLIENT_PRIV_KEY | wg pubkey)"
	PRINT_MODE="qr"
	echo "Warning: The QR code is fairly large. To ensure that it is printed correctly, you must zoom out your terminal."
	echo "Scan the QR code BEFORE zooming back in to continue the installation. If it goes off the border of your terminal, it will get garbled."
	read -p "Zoom out and press Enter."
else
	CLIENT_PRIV_KEY="PASTE-YOUR-PRIVATE-KEY-HERE"
	while [ -z $CLIENT_PUB_KEY ]
	do
		read -p "Paste your client public key: " CLIENT_PUB_KEY
	done
fi

# The preshared key is always server-generated, since the server needs knowledge of it anyway
PRESHARED_KEY="$(wg genpsk)"

# For the client config, we need the server's public IP address somehow, and the ipify service is the simplest way to do that
ENDPOINT=$(curl -s --fail https://api.ipify.org)

CLIENT_CONFIG=$(cat <<- EOF
[Interface]
PrivateKey = $CLIENT_PRIV_KEY
Address = 192.168.103.$CLIENT_ID/24, fc00:8f78:4cb5:b7c4::$CLIENT_ID/64
DNS = 8.8.8.8,4.4.4.4

[Peer]
Endpoint = $ENDPOINT:51820
PublicKey = $SERVER_PUB_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = 0.0.0.0/5, 8.0.0.0/7, 11.0.0.0/8, 12.0.0.0/6, 16.0.0.0/4, 32.0.0.0/3, 64.0.0.0/2, 128.0.0.0/3, 160.0.0.0/5, 168.0.0.0/6, 172.0.0.0/12, 172.32.0.0/11, 172.64.0.0/10, 172.128.0.0/9, 173.0.0.0/8, 174.0.0.0/7, 176.0.0.0/4, 192.0.0.0/9, 192.128.0.0/11, 192.160.0.0/13, 192.169.0.0/16, 192.170.0.0/15, 192.172.0.0/14, 192.176.0.0/12, 192.192.0.0/10, 193.0.0.0/8, 194.0.0.0/7, 196.0.0.0/6, 200.0.0.0/5, 208.0.0.0/4, 224.0.0.0/3, ::/1, 8000::/2, c000::/3, e000::/4, f000::/5, f800::/6, fe00::/9, fec0::/10, ff00::/8, 192.168.103.0/24, fc00:8f78:4cb5:b7c4::0/64
PersistentKeepalive = 25
EOF
)

echo "==================================================="
echo "Your client config will look like this:"
echo "==================================================="
echo ""
if [ "$PRINT_MODE" = "qr" ]
then
	echo "$CLIENT_CONFIG" | qrencode -t ansi
else
	echo "$CLIENT_CONFIG"
fi
echo ""
echo "==================================================="
echo "You must paste it into your WireGuard client."
echo "If you chose to generate a private key yourself, paste it where it says PASTE-YOUR-PRIVATE-KEY-HERE"
echo "Note: Only one device can use this config. To add more devices, rerun $0."
echo "==================================================="

DO_INSTALL=""
until [ "$DO_INSTALL" = "y" -o "$DO_INSTALL" = "n" ]
do
	read -p "Install this client? (y/n): " DO_INSTALL
done
if [ "$DO_INSTALL" != "y" ]
then
	echo "Cancelled."
	exit 1
fi

echo "==================================================="
echo "Reconfiguring the VPN."
echo "If you're using SSH, your connection might drop now. You need to activate your VPN client and reconnect to 192.168.103.1."
echo "==================================================="

if [ "$DELETE_VPN_CONF" = "yes" ]
then
	rm /etc/wireguard/basstoonvpn.conf
fi

# Generate WireGuard config files. The PreUp commands in the server config will take care of firewall and forwarding rules.

# Server base config (only printed if the file is missing)
if [ ! -f /etc/wireguard/basstoonvpn.conf ]
then

touch /etc/wireguard/basstoonvpn.conf
chown root:root /etc/wireguard/basstoonvpn.conf
chmod 0600 /etc/wireguard/basstoonvpn.conf

cat > /etc/wireguard/basstoonvpn.conf <<- EOF
[Interface]
PrivateKey = $SERVER_PRIV_KEY
Address = 192.168.103.1/24, fc00:8f78:4cb5:b7c4::1/64
ListenPort = 51820
PreUp = sysctl net.ipv4.ip_forward=1
PreUp = sysctl net.ipv6.conf.all.forwarding=1
PreUp = nft flush ruleset
PreUp = nft create table inet vpn_rules
PreUp = nft add chain inet vpn_rules prerouting "{ type nat hook postrouting priority 100; policy accept; }"
PreUp = nft add chain inet vpn_rules postrouting "{ type nat hook postrouting priority 100; policy accept; }"
PreUp = nft add rule inet vpn_rules postrouting iifname "%i" oifname != "%i" masquerade
PreUp = nft add chain inet vpn_rules input "{ type filter hook input priority 0; policy drop; }"
PreUp = nft add chain inet vpn_rules forward "{ type filter hook forward priority 0; policy drop; }"
PreUp = nft add chain inet vpn_rules output "{ type filter hook output priority 0; policy accept; }"
PreUp = nft add rule inet vpn_rules input ct state established,related accept
PreUp = nft add rule inet vpn_rules input udp dport 51820 accept
PreUp = nft add rule inet vpn_rules input iifname "%i" tcp dport 22 accept
PreUp = nft add rule inet vpn_rules input iifname "lo" accept
PreUp = nft add rule inet vpn_rules forward iifname "%i" accept
PreUp = nft add rule inet vpn_rules forward oifname "%i" accept
EOF

fi

# Append client entry to server config
cat >> /etc/wireguard/basstoonvpn.conf <<- EOF

[Peer]
PublicKey = $CLIENT_PUB_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = 192.168.103.$CLIENT_ID/32, fc00:8f78:4cb5:b7c4::$CLIENT_ID/128
PersistentKeepalive = 25
EOF

# Make sure that any preexisting installation is stopped
wg-quick down basstoonvpn 2> /dev/null || true
systemctl disable --now wg-quick@basstoonvpn.service 2> /dev/null || true

# Restart the VPN
systemctl enable --now wg-quick@basstoonvpn.service

echo "==================================================="
echo "Done!"
echo "==================================================="
