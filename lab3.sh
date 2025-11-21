#!/bin/bash
# lab3.sh - COMP2137 Assignment 3
# Deploys configure-host.sh to server1-mgmt and server2-mgmt,
# then updates the local /etc/hosts file.

set -u

# verbose option
VERBOSE=0
VERBFLAG=""
if [ $# -gt 0 ] && [ "$1" = "-verbose" ]; then
    VERBOSE=1
    VERBFLAG="-verbose"
fi

vprint() { [ "$VERBOSE" -eq 1 ] && echo "$@"; }

# determine real user's home directory
if [ -n "${SUDO_USER-}" ]; then
    REALUSER="$SUDO_USER"
    REALHOME="$(eval echo ~"$SUDO_USER")"
else
    REALUSER="$USER"
    REALHOME="$HOME"
fi

# locate SSH key
SSH_KEY=""
for key in "$REALHOME/.ssh/id_ed25519" "$REALHOME/.ssh/id_rsa"; do
    if [ -f "$key" ]; then
        SSH_KEY="$key"
        break
    fi
done

if [ -z "$SSH_KEY" ]; then
    echo "ERROR: No SSH key found in $REALHOME/.ssh" >&2
    exit 1
fi

SSH_KEY_OPT="-i $SSH_KEY"

run_or_fail() {
    local desc="$1"; shift
    if ! "$@"; then
        echo "ERROR: $desc" >&2
        exit 1
    fi
}

# verify configure-host.sh exists
if [ ! -x ./configure-host.sh ]; then
    echo "ERROR: ./configure-host.sh missing or not executable" >&2
    exit 1
fi

# server1-mgmt (loghost)
vprint "Copying configure-host.sh to server1-mgmt..."
run_or_fail "scp to server1-mgmt failed" \
    scp $SSH_KEY_OPT ./configure-host.sh remoteadmin@server1-mgmt:/root

vprint "Running configure-host.sh on server1-mgmt..."
run_or_fail "configure-host on server1 failed" \
    ssh $SSH_KEY_OPT remoteadmin@server1-mgmt -- \
    "/root/configure-host.sh $VERBFLAG -name loghost -ip 192.168.16.3 -hostentry webhost 192.168.16.4"

# server2-mgmt (webhost)
vprint "Copying configure-host.sh to server2-mgmt..."
run_or_fail "scp to server2-mgmt failed" \
    scp $SSH_KEY_OPT ./configure-host.sh remoteadmin@server2-mgmt:/root

vprint "Running configure-host.sh on server2-mgmt..."
run_or_fail "configure-host on server2 failed" \
    ssh $SSH_KEY_OPT remoteadmin@server2-mgmt -- \
    "/root/configure-host.sh $VERBFLAG -name webhost -ip 192.168.16.4 -hostentry loghost 192.168.16.3"

# update local /etc/hosts
vprint "Updating local /etc/hosts for loghost..."
run_or_fail "local hostentry loghost failed" \
    ./configure-host.sh $VERBFLAG -hostentry loghost 192.168.16.3

vprint "Updating local /etc/hosts for webhost..."
run_or_fail "local hostentry webhost failed" \
    ./configure-host.sh $VERBFLAG -hostentry webhost 192.168.16.4

[ "$VERBOSE" -eq 1 ] && echo "lab3.sh completed successfully."
exit 0
