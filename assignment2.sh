#!/bin/bash
# assignment2.sh — COMP2137 Assignment 2: System Modification Script
# Runs on server1 or server2

set -euo pipefail

startTime=$(date +%s)

logMsg() {
    local msg="$1"
    local elapsed=$(( $(date +%s) - startTime ))
    printf "\n==> %s [Elapsed: %ss]\n" "$msg" "$elapsed"
}

# --- Ensure root ---
if [[ $EUID -ne 0 ]]; then
    echo "Re-executing as root via sudo..."
    exec sudo -E bash "$0" "$@"
fi

logMsg "Starting system configuration"

hostname=$(hostname)
netplanDir="/etc/netplan"
netplanFile="${netplanDir}/01-netcfg.yaml"

# Remove all existing Netplan configs
rm -f "${netplanDir}"/*.yaml "${netplanDir}"/*.yml || true

# Assign IPs based on hostname
if [[ "$hostname" == "server1" ]]; then
    eth0Ip="192.168.16.21/24"
    eth1Ip="172.16.1.241/24"
elif [[ "$hostname" == "server2" ]]; then
    eth0Ip="192.168.16.21/24"
    eth1Ip="172.16.1.242/24"
else
    echo "Unknown server hostname: $hostname"
    exit 1
fi

# Write Netplan config
cat > "$netplanFile" <<EOF
network:
    version: 2
    ethernets:
        eth0:
            addresses: [$eth0Ip]
            routes:
              - to: default
                via: 192.168.16.2
            nameservers:
                addresses: [192.168.16.2]
                search: [home.arpa, localdomain]
        eth1:
            addresses: [$eth1Ip]
EOF

chmod 0644 "$netplanFile"
logMsg "Netplan configuration written"

netplan apply
logMsg "Netplan applied"

# Update /etc/hosts
eth0IpNoMask="${eth0Ip%/*}"
sed -i -E "/\s+$hostname$/d" /etc/hosts
echo "$eth0IpNoMask $hostname" >> /etc/hosts
logMsg "/etc/hosts updated ($eth0IpNoMask $hostname)"

# Install software
logMsg "Installing Apache2 and Squid"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq apache2 squid
systemctl enable --now apache2 squid
logMsg "Apache2 and Squid installed and running"

# --- Create users and SSH keys ---
logMsg "Starting user creation and SSH key setup"

users=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)
dennisExtraKey="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI riken@generic-vm"

templateDir="/root/ssh-templates"
mkdir -p "$templateDir"
[[ ! -f "$templateDir/id_rsa" ]] && ssh-keygen -t rsa -b 4096 -N '' -f "$templateDir/id_rsa" -q </dev/null
[[ ! -f "$templateDir/id_ed25519" ]] && ssh-keygen -t ed25519 -N '' -f "$templateDir/id_ed25519" -q </dev/null

for user in "${users[@]}"; do
    {
        # Create user if missing
        if ! id "$user" &>/dev/null; then
            if [[ "$user" == "dennis" ]]; then
                useradd -m -s /bin/bash -G sudo "$user" || true
            else
                useradd -m -s /bin/bash "$user" || true
            fi
            logMsg "User '$user' created"
        fi

        homeDir="$(getent passwd "$user" | cut -d: -f6)"
        sshDir="$homeDir/.ssh"
        mkdir -p "$sshDir"
        chmod 700 "$sshDir"
        chown "$user:$user" "$sshDir"

        # Copy keys safely
        for key in id_rsa id_ed25519; do
            cp -n "$templateDir/$key" "$sshDir/$key" 2>/dev/null || true
            cp -n "$templateDir/$key.pub" "$sshDir/$key.pub" 2>/dev/null || true
        done

        # authorized_keys
        {
            cat "$sshDir/id_rsa.pub"
            cat "$sshDir/id_ed25519.pub"
            [[ "$user" == "dennis" ]] && echo "$dennisExtraKey"
        } | sort -u > "$sshDir/authorized_keys"

        chmod 600 "$sshDir/authorized_keys"
        chown "$user:$user" "$sshDir/authorized_keys"

        logMsg "SSH keys configured for '$user'"
    } || logMsg "Warning: failed configuring user '$user', continuing..."
done

logMsg "All users and SSH keys have been successfully created."

logMsg "System configuration completed successfully"
