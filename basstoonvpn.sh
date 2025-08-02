#!/usr/bin/env bash

set -eo pipefail

# Helper function that prints a separator to make things look nicer
print_separator() {
	echo ""
	echo "========================================"
	echo ""
}

# Process command-line args and inputs
REMOTE_SSH_ADDR=$1
ADDITION_MODE=$2
if [[ -z "$REMOTE_SSH_ADDR" ]]
then
	read -p "Remote user and address? (e.g. root@123.45.67.89): " REMOTE_SSH_ADDR
else
	echo "Connecting to $REMOTE_SSH_ADDR."
fi
while [[ "$ADDITION_MODE" != "add" && "$ADDITION_MODE" != "reset" ]]
do
	read -p "Mode? (add/reset): " ADDITION_MODE
done

# Reset mode: uninstalls the VPN and removes firewall rules
if [[ "$ADDITION_MODE" == "reset" ]]
then
	print_separator
	echo "Uninstalling the VPN. If you connected through the VPN, your connection might drop here."
	print_separator
	# Wrap this in a single bask call to force the remote to fetch the entire command before executing.
	# This should prevent the command executing only halfway due to the connection dropping
	ssh -2 "$REMOTE_SSH_ADDR" "bash -c \"nft flush ruleset; rm /etc/wireguard/basstoonvpn.conf; systemctl disable --now wg-quick@basstoonvpn.service; ip link del basstoonvpn\"" || true
	print_separator
	exit 0
fi

# Otherwise, we're in add mode and we will install or extend the VPN on the remote

# This function will be sent to the remote and executed. It manages the WireGuard config file.
add_wireguard_client() {
	local CLIENT_PUB_KEY=$1
	if [[ -z $CLIENT_PUB_KEY ]]
	then
		echo "Usage: $0 <client public key>" 1>&2
		return 1
	fi

	# ID of the client to be created, a number between 2 and 255.
	local CLIENT_ID="2"

	# If a /etc/wireguard/basstoonvpn.conf already exists...
	if [[ -f /etc/wireguard/basstoonvpn.conf ]]
	then
		# Keep the old config, but extract the server private key and the next available client ID
		while 
			cat /etc/wireguard/basstoonvpn.conf | grep "192.168.103.$CLIENT_ID" >/dev/null
		do
			local CLIENT_ID=$(($CLIENT_ID + 1))
		done
		if [[ $CLIENT_ID -gt 255 ]]
		then
			echo "Error: There are too many clients already registered (you can have at most 254)." 1>&2
			return 1
		fi
		# I love sed. Don't you? Of course you do.
		local SERVER_PRIV_KEY=$(cat /etc/wireguard/basstoonvpn.conf | grep PrivateKey | sed -e "s/^PrivateKey\s*=\s*\([a-zA-Z0-9+\/\-_=]*\)\s*\$/\1/")
	else
		# No VPN configuration found, this is probably a first install. Install prerequisites and remove firewalls that might mess with our setup
		apt-get update -y >/dev/null
		apt-get remove -y iptables firewalld 2> /dev/null >/dev/null || true
		apt-get install -y wireguard-tools nftables curl >/dev/null
	fi
	# Generate a fresh server private key if we didn't already extract one from an existing config. Then compute the public key from that.
	if [[ -z "$SERVER_PRIV_KEY" ]]
	then
		local SERVER_PRIV_KEY="$(wg genkey)"
	fi
	local SERVER_PUB_KEY="$(echo $SERVER_PRIV_KEY | wg pubkey)"

	# The preshared key is always server-generated, since the server needs knowledge of it anyway
	local PRESHARED_KEY="$(wg genpsk)"

	# For the client config, we need the server's public IP address somehow, and the ipify service is the simplest way to do that
	local ENDPOINT=$(curl -s --fail https://api.ipify.org)

	# Generate the client's config. The client will have to substiture their own private key in this.
	local CLIENT_CONFIG=$(cat <<- EOF
		[Interface]
		PrivateKey = TODO-INSERT-YOUR-PRIVATE-KEY-HERE
		Address = 192.168.103.$CLIENT_ID/24,fc00:8f78:4cb5:b7c4::$CLIENT_ID/64
		DNS = 8.8.8.8,4.4.4.4

		[Peer]
		Endpoint = $ENDPOINT:51820
		PublicKey = $SERVER_PUB_KEY
		PresharedKey = $PRESHARED_KEY
		AllowedIPs = 0.0.0.0/0,::/0
		PersistentKeepalive = 25
		EOF
	)

	# Echo the config back
	echo "$CLIENT_CONFIG"

	# If there was no config file or we asked to reset, overwrite the config file
	if [[ ! (-f /etc/wireguard/basstoonvpn.conf) ]]
	then
	touch /etc/wireguard/basstoonvpn.conf
	chown root:root /etc/wireguard/basstoonvpn.conf
	chmod 0600 /etc/wireguard/basstoonvpn.conf
	cat > /etc/wireguard/basstoonvpn.conf <<- EOF
		[Interface]
		PrivateKey = $SERVER_PRIV_KEY
		Address = 192.168.103.1/24,fc00:8f78:4cb5:b7c4::1/64
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

	# Append the client's entry to the server config
	cat >> /etc/wireguard/basstoonvpn.conf <<- EOF

		[Peer]
		PublicKey = $CLIENT_PUB_KEY
		PresharedKey = $PRESHARED_KEY
		AllowedIPs = 192.168.103.$CLIENT_ID/32, fc00:8f78:4cb5:b7c4::$CLIENT_ID/128
		PersistentKeepalive = 25
		EOF
	
	# Now start the service, trying not to disrupt existing VPN connections.
	if
		systemctl is-enabled --quiet wg-quick@basstoonvpn.service
	then
		if
			systemctl is-active --quiet wg-quick@basstoonvpn.service
		then
			# Service enabled and running -> just reload to avoid disrupting existing connections
			systemctl reload --quiet wg-quick@basstoonvpn.service
		else
			# Service is enabled, but not running -> start it
			systemctl start --quiet wg-quick@basstoonvpn.service
		fi
	else
		# Service is not enabled -> enable and start it
		systemctl enable --now wg-quick@basstoonvpn.service
	fi

	# Done!
	return 0
}
# Generate a key pair for the new client locally
PRIV_KEY=$(openssl genpkey -algorithm X25519 -outform der | base64)
PUB_KEY=$(echo $PRIV_KEY | base64 --decode | openssl pkey -pubout -outform der | base64)
# Taking only the last 32 bytes of the DER representation gives us the raw keys, like WireGuard would use them
PRIV_KEY=$(echo $PRIV_KEY | base64 --decode | tail -c 32 | base64)
PUB_KEY=$(echo $PUB_KEY | base64 --decode | tail -c 32 | base64)
# Now execute the operation on the remote and extract the output
CLIENT_CONFIG=$(ssh -2 "$REMOTE_SSH_ADDR" "set -eo pipefail; $(declare -f add_wireguard_client); add_wireguard_client $PUB_KEY")
# Substitute our private key in the result from the remote. We need to escape slashes in the private key otherwise they mess up the sed command.
CLIENT_CONFIG=$(echo "$CLIENT_CONFIG" | sed -e "s/TODO-INSERT-YOUR-PRIVATE-KEY-HERE/$(echo $PRIV_KEY | sed -e 's/\//\\\//g')/")

print_separator

read -p "Config ready. I'm about to print a large QR code, so please zoom out your terminal and press Enter."

print_separator

echo "$CLIENT_CONFIG"

print_separator

echo "$CLIENT_CONFIG" | qrencode -t ansi

print_separator
