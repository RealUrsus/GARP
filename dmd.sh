#!/bin/bash
# Dead Module Detection
set -euo pipefail

CONF=/etc/keepalived/keepalived.conf
IF="${1:-}"
PROCESS="${2:-}"

# Input validation
if [[ -z "$IF" ]] || [[ -z "$PROCESS" ]]; then
    /usr/bin/logger -t keepalived -p daemon.error "dmd.sh: missing arguments (interface, process)"
    exit 1
fi

# Check config readable
if [[ ! -r "$CONF" ]]; then
    /usr/bin/logger -t keepalived -p daemon.error "dmd.sh: cannot read $CONF"
    exit 1
fi

# Extract virtual IPs (handles CIDR notation)
VIRTUAL_IPS=$(sed -n '/virtual_ipaddress[[:space:]]*{/,/}/{
    /virtual_ipaddress[[:space:]]*{/d
    /}/d
    s/^[[:space:]]*//
    s/[[:space:]].*//
    s/\/.*//
    /^[0-9]/p
}' "$CONF")

# Check if this node is MASTER
is_master=false
while IFS= read -r ip; do
    [[ -z "$ip" ]] && continue
    if timeout 5 ip -4 addr show dev "$IF" 2>/dev/null | grep -qw "$ip"; then
        is_master=true
        break
    fi
done <<< "$VIRTUAL_IPS"

# BACKUP node is always healthy
if [[ "$is_master" == "false" ]]; then
    exit 0
fi

# MASTER node - check process
if /usr/bin/pgrep -x "$PROCESS" >/dev/null 2>&1; then
    exit 0
else
    /usr/bin/logger -t keepalived -p daemon.error "dmd.sh: Dead MASTER detected - process '$PROCESS' not running"
    exit 1
fi
