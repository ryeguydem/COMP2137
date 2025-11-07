#!/usr/bin/env bash
# assignment2.sh — COMP2137 Assignment 2: System Modification Script
# Runs on server1

set -euo pipefail

# --- Ensure root ---
if [[ $EUID -ne 0 ]]; then
  echo "Re-execing as root via sudo..."
  exec sudo -E bash "$0" "$@"
fi

log(){ printf "\n==> %s\n" "$*"; }

# --- 1) Find the 192.168.16.x interface and set it to 192.168.16.21/24 via netplan ---
log "Detecting interface on 192.168.16.0/24..."
iface="$(ip -o -4 addr show | awk '$4 ~ /^192\.168\.16\./ {print $2; exit}')"
[[ -n "${iface}" ]] || { echo "No 192.168.16.* interface found"; exit 1; }
log "Interface is ${iface}"

# Pick the netplan file that defines this iface (fallback to first yaml)
netplan_file="$(grep -rlE "^[[:space:]]*${iface}:" /etc/netplan || true)"
[[ -n "${netplan_file}" ]] || netplan_file="$(ls -1 /etc/netplan/*.y*ml 2>/dev/null | head -n1)"
[[ -n "${netplan_file}" ]] || { echo "No netplan file found"; exit 1; }
log "Netplan file: ${netplan_file}"

# Backup once
[[ -f "${netplan_file}.bak.a2" ]] || cp -a "${netplan_file}" "${netplan_file}.bak.a2"

# Replace any existing 192.168.16.* /24 under that iface with .21, or inject it if missing
tmp="$(mktemp)"
awk -v iface="$iface" '
  BEGIN{ in_iface=0 }
  {
    if ($0 ~ "^[[:space:]]*"iface":") { in_iface=1; print; next }
    if (in_iface && $0 ~ "^[[:space:]]*[a-z]") { in_iface=0 }
    if (in_iface && $0 ~ /192\.168\.16\.[0-9]+\/24/) { gsub(/192\.168\.16\.[0-9]+\/24/, "192.168.16.21/24"); print; next }
    print
  }' "${netplan_file}" > "${tmp}"

if ! awk -v iface="$iface" '
  BEGIN{in_iface=0; found=0}
  {
    if ($0 ~ "^[[:space:]]*"iface":") in_iface=1
    else if (in_iface && $0 ~ "^[[:space:]]*[a-z]") in_iface=0
    if (in_iface && $0 ~ /192\.168\.16\.21\/24/) found=1
  }
  END{ exit found?0:1 }' "${tmp}"; then
  awk -v iface="$iface" '
    function indent(n){ s=""; for(i=0;i<n;i++) s=s" "; return s }
    BEGIN{in_iface=0; lvl=0; done=0}
    {
      print
      if ($0 ~ "^[[:space:]]*"iface":") { in_iface=1; lvl = match($0,/[^ ]/)-1 }
      else if (in_iface && $0 ~ "^[[:space:]]*[a-z]") { if(!done){ print indent(lvl+2)"addresses: [192.168.16.21/24]"; done=1 } in_iface=0 }
      else if (in_iface && $0 ~ /^[[:space:]]*addresses:/) {
        if ($0 ~ /\[/) { if ($0 !~ /192\.168\.16\.21\/24/) sub(/\]$/, ", 192.168.16.21/24]") }
        else { print gensub(/^[[:space:]]*/,"&- 192.168.16.21/24",1) }
        done=1
      }
    }
    END{ if (in_iface && !done) print indent(lvl+2)"addresses: [192.168.16.21/24]" }' "${tmp}" > "${tmp}.2"
  mv "${tmp}.2" "${tmp}"
fi

install -m 0644 "${tmp}" "${netplan_file}"; rm -f "${tmp}"
log "Applying netplan..."
netplan apply

# --- 2) /etc/hosts: server1 -> 192.168.16.21 (remove old server1 lines on 192.168.16.*) ---
log "Updating /etc/hosts for server1..."
cp -a /etc/hosts /etc/hosts.bak.a2 || true
grep -vE '^192\.168\.16\.[0-9]+\s+server1(\s|$)' /etc/hosts > /etc/hosts.new
grep -qE '^192\.168\.16\.21\s+server1(\s|$)' /etc/hosts.new || echo "192.168.16.21 server1" >> /etc/hosts.new
install -m 0644 /etc/hosts.new /etc/hosts && rm -f /etc/hosts.new

# --- 3) Software: apache2 + squid, enabled and running ---
log "Installing apache2 and squid..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 squid
systemctl enable --now apache2
systemctl enable --now squid

# --- 4) Users + SSH keys ---
log "Creating users and SSH keys..."
users=(dennis aubrey captain snibbles brownie scooter sandy perrier cindy tiger yoda)

ensure_user() {
  local u="$1"
  id "$u" &>/dev/null || useradd -m -s /bin/bash "$u"
}
ensure_keys() {
  local u="$1"
  local home; home="$(getent passwd "$u" | cut -d: -f6)"
  local sshd="${home}/.ssh"
  install -d -m 700 -o "$u" -g "$u" "$sshd"
  [[ -f "${sshd}/id_rsa"      ]] || sudo -u "$u" ssh-keygen -t rsa -b 4096 -N "" -f "${sshd}/id_rsa" >/dev/null
  [[ -f "${sshd}/id_ed25519" ]] || sudo -u "$u" ssh-keygen -t ed25519 -N "" -f "${sshd}/id_ed25519" >/dev/null
  {
    cat "${sshd}/id_rsa.pub"
    cat "${sshd}/id_ed25519.pub"
    if [[ "$u" == "dennis" ]]; then
      echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIG4rT3vTt99Ox5kndS4HmgTrKBT8SKzhK4rhGkEVGlCI student@generic-vm'
    fi
  } | sort -u > "${sshd}/authorized_keys"
  chown "$u:$u" "${sshd}/authorized_keys"; chmod 600 "${sshd}/authorized_keys"
  [[ "$u" == "dennis" ]] && usermod -aG sudo dennis || true
}
for u in "${users[@]}"; do
  ensure_user "$u"
  ensure_keys "$u"
done

log "Done."
echo "Interface ${iface} -> 192.168.16.21/24; hosts updated; apache2 & squid running; users + keys created; dennis has sudo."
