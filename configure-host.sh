#!/bin/bash
# configure-host.sh - COMP2137 Assignment 3
# Idempotent host configuration script:
# sets hostname
# sets LAN IP via netplan
# ensures /etc/hosts entries
# Produces no output unless -verbose or errors occur.

set -u

# Ignore these signals as required
trap '' TERM HUP INT

VERBOSE=0
EXIT_STATUS=0
LOGTAG="configure-host"

vprint() {
    if [ "$VERBOSE" -eq 1 ]; then
        echo "$@"
    fi
}

log_change() {
    # Log to syslog using logger
    logger -t "$LOGTAG" "$@"
}

die_usage() {
    echo "Usage: $0 [-verbose] [-name hostname] [-ip address] [-hostentry name address]" >&2
    exit 1
}

ensure_hostentry() {
    local name="$1"
    local ip="$2"

    if grep -qE "^${ip}[[:space:]].*\b${name}\b" /etc/hosts; then
        vprint "/etc/hosts already has '${ip} ${name}'"
        return 0
    fi

    if grep -qE "^${ip}[[:space:]]" /etc/hosts; then
        # Replace existing line for that IP
        # We ensure the IP is at the beginning of the line
        if sed -i -E "s/^${ip}[[:space:]].*/${ip} ${name}/" /etc/hosts; then
            vprint "Updated /etc/hosts entry for ${ip} -> ${name}"
            log_change "Updated /etc/hosts entry: ${ip} ${name}"
        else
            echo "ERROR: failed to update /etc/hosts for ${ip}" >&2
            EXIT_STATUS=1
            return 1
        fi
    else
        # Append new line
        if printf '%s %s\n' "$ip" "$name" >> /etc/hosts; then
            vprint "Added /etc/hosts entry ${ip} ${name}"
            log_change "Added /etc/hosts entry: ${ip} ${name}"
        else
            echo "ERROR: failed to append to /etc/hosts" >&2
            EXIT_STATUS=1
            return 1
        fi
    fi
}

ensure_hostname() {
    local newname="$1"
    local cur
    cur="$(hostname)"

    if [ "$cur" = "$newname" ]; then
        vprint "Hostname already '${newname}'"
        return 0
    fi

    # Update /etc/hostname
    if ! printf '%s\n' "$newname" > /etc/hostname; then
        echo "ERROR: failed to write /etc/hostname" >&2
        EXIT_STATUS=1
        return 1
    fi

    # Apply to running system
    if ! hostname "$newname" >/dev/null 2>&1; then
        echo "ERROR: failed to change running hostname" >&2
        EXIT_STATUS=1
        return 1
    fi

    # Ensure 127.0.1.1 mapping exists
    if grep -qE "^127\.0\.1\.1[[:space:]]" /etc/hosts; then
        if ! sed -i -E "s/^127\.0\.1\.1[[:space:]].*/127.0.1.1 ${newname}/" /etc/hosts; then
            echo "ERROR: failed to update 127.0.1.1 mapping in /etc/hosts" >&2
            EXIT_STATUS=1
            return 1
        fi
    else
        if ! printf '%s %s\n' "127.0.1.1" "$newname" >> /etc/hosts; then
            echo "ERROR: failed to add 127.0.1.1 mapping to /etc/hosts" >&2
            EXIT_STATUS=1
            return 1
        fi
    fi

    vprint "Hostname changed from '${cur}' to '${newname}'"
    log_change "Hostname changed from '${cur}' to '${newname}'"
}

ensure_ip() {
    local newip="$1"
    local netplan
    netplan="$(ls /etc/netplan/*.yaml 2>/dev/null | head -n 1)"

    if [ -z "$netplan" ]; then
        echo "ERROR: no netplan configuration found in /etc/netplan" >&2
        EXIT_STATUS=1
        return 1
    fi

    # Find current LAN CIDR in netplan (assuming 192.168.16.0/24 LAN)
    local current_cidr
    current_cidr="$(grep -oE '192\.168\.16\.[0-9]+/[0-9]+' "$netplan" | head -n 1 || true)"

    if [ -z "$current_cidr" ]; then
        echo "ERROR: could not find current 192.168.16.x address in $netplan" >&2
        EXIT_STATUS=1
        return 1
    fi

    local cur_ip cur_prefix new_cidr
    cur_ip="${current_cidr%/*}"
    cur_prefix="${current_cidr#*/}"
    new_cidr="${newip}/${cur_prefix}"

    if [ "$cur_ip" = "$newip" ]; then
        vprint "LAN IP already ${newip}"
        return 0
    fi
    # FIX: The 'fi' for the initial IP check was missing, leading to unconditional updates.

    if sed -i "s|${current_cidr}|${new_cidr}|" "$netplan"; then
        vprint "Updated netplan IP from ${current_cidr} to ${new_cidr}"
        log_change "LAN IP changed from ${current_cidr} to ${new_cidr}"
    else
        echo "ERROR: failed to update netplan file ${netplan}" >&2
        EXIT_STATUS=1
        return 1
    fi

    if ! netplan apply >/dev/null 2>&1; then
        echo "ERROR: netplan apply failed" >&2
        EXIT_STATUS=1
        return 1
    fi

    vprint "Applied new IP ${new_cidr} via netplan"


    # Ensure /etc/hosts entry for our own hostname with this IP
    local h
    h="$(hostname)"
    ensure_hostentry "$h" "$newip"
}


DO_NAME=0
DO_IP=0
DO_HOSTENTRY=0
DESIRED_NAME=""
DESIRED_IP=""
HE_NAME=""
HE_IP=""

while [ $# -gt 0 ]; do
    case "$1" in
        -verbose)
            VERBOSE=1
            ;;
        -name)
            [ $# -lt 2 ] && die_usage
            DO_NAME=1
            DESIRED_NAME="$2"
            shift
            ;;
        -ip)
            [ $# -lt 2 ] && die_usage
            DO_IP=1
            DESIRED_IP="$2"
            shift
            ;;
        -hostentry)
            [ $# -lt 3 ] && die_usage
            DO_HOSTENTRY=1
            HE_NAME="$2"
            HE_IP="$3"
            shift 2 # Consumes $2 and $3
            ;;
        *)
            die_usage
            ;;
    esac
    shift # Consumes $1 (the option)
done

# If nothing requested, silently exit
if [ "$DO_NAME" -eq 0 ] && [ "$DO_IP" -eq 0 ] && [ "$DO_HOSTENTRY" -eq 0 ]; then
    exit 0
fi

# Perform requested actions
if [ "$DO_NAME" -eq 1 ]; then
    ensure_hostname "$DESIRED_NAME"
fi

if [ "$DO_IP" -eq 1 ]; then
    ensure_ip "$DESIRED_IP"
fi

if [ "$DO_HOSTENTRY" -eq 1 ]; then
    ensure_hostentry "$HE_NAME" "$HE_IP"
fi

exit "$EXIT_STATUS"
