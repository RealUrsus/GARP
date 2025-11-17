#!/bin/bash
# Dead Module Detection for Keepalived
# Checks if virtual IPs are assigned and if critical process is running

set -euo pipefail

# Constants
readonly CONF=/etc/keepalived/keepalived.conf
readonly SCRIPT_NAME=$(basename "$0")

# Debug mode (set to 1 to enable)
DEBUG=${DEBUG:-0}

# Function to log debug messages
debug_log() {
    if [ "$DEBUG" -eq 1 ]; then
        echo "[DEBUG] $*" >&2
    fi
}

# Function to display usage
usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <interface> <process>

Arguments:
  interface    Network interface to check for virtual IPs
  process      Process name to verify is running on MASTER node

Environment:
  DEBUG=1      Enable debug logging

Exit codes:
  0 - Success (BACKUP node or healthy MASTER)
  1 - Error (missing config, dead MASTER, or invalid arguments)

Example:
  $SCRIPT_NAME eth0 frr
EOF
    exit 1
}

# Validate arguments
if [ $# -ne 2 ]; then
    echo "Error: Missing required arguments" >&2
    usage
fi

INTERFACE="$1"
PROCESS_NAME="$2"

debug_log "Interface: $INTERFACE"
debug_log "Process: $PROCESS_NAME"

# Validate interface name
if [ -z "$INTERFACE" ]; then
    echo "Error: Interface name cannot be empty" >&2
    exit 1
fi

# Validate process name
if [ -z "$PROCESS_NAME" ]; then
    echo "Error: Process name cannot be empty" >&2
    exit 1
fi

# Check if keepalived config exists and is readable
if [ ! -r "$CONF" ]; then
    echo "Error: Keepalived configuration file '$CONF' not found or not readable" >&2
    exit 1
fi

debug_log "Config file found: $CONF"

# Check if interface exists
if ! ip link show "$INTERFACE" > /dev/null 2>&1; then
    echo "Error: Network interface '$INTERFACE' does not exist" >&2
    exit 1
fi

debug_log "Interface exists: $INTERFACE"

# Extract virtual IPs from keepalived.conf
# Handle both plain IPs and CIDR notation (e.g., 192.168.1.1/24)
VIRTUAL_IPS=$(sed -n '/virtual_ipaddress\s*{/,/}/{ /virtual_ipaddress\s*{/! { /}/! p }}' "$CONF" \
    | sed -n -E 's|.*/([0-9]+).*|\1|; /\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))\b/p' \
    | sed 's|/[0-9]*||g' \
    | tr -d '\n' \
    | tr -d '\t')

debug_log "Extracted virtual IPs: $VIRTUAL_IPS"

# Check if we found any virtual IPs
if [ -z "$VIRTUAL_IPS" ]; then
    echo "Warning: No virtual IPs found in configuration" >&2
    debug_log "Assuming BACKUP node (no VIPs configured)"
    exit 0
fi

# Check if virtual IPs are assigned to this interface
# If first IP is not found, this is a BACKUP node - no need to check further
for ip in $VIRTUAL_IPS; do
    debug_log "Checking if IP $ip exists on interface $INTERFACE"

    # Strip any CIDR notation if present
    ip_clean=$(echo "$ip" | sed 's|/[0-9]*||')

    if ! ip -4 addr show dev "$INTERFACE" | grep -qw "$ip_clean"; then
        # Virtual IP not found - this is BACKUP node
        debug_log "IP $ip_clean not found on $INTERFACE - BACKUP node"
        logger -t keepalived -p daemon.info "BACKUP node detected (VIP $ip_clean not on $INTERFACE)"
        exit 0
    fi

    debug_log "IP $ip_clean found on $INTERFACE"
    # Only check first IP - if it's assigned, we're MASTER
    break
done

debug_log "This is MASTER node - checking process status"

# We are MASTER - check if critical process is running
# Use pgrep for more precise matching (recommended for Ubuntu 24.04)
if command -v pgrep > /dev/null 2>&1; then
    debug_log "Using pgrep to check for process: $PROCESS_NAME"
    if pgrep -x "$PROCESS_NAME" > /dev/null 2>&1; then
        debug_log "Process $PROCESS_NAME is running - MASTER healthy"
        exit 0
    else
        logger -t keepalived -p daemon.error "Dead MASTER detected - process '$PROCESS_NAME' not running"
        debug_log "Process $PROCESS_NAME NOT running - MASTER dead"
        exit 1
    fi
else
    # Fallback to killall if pgrep not available
    debug_log "pgrep not found, falling back to killall"
    if killall -0 "$PROCESS_NAME" > /dev/null 2>&1; then
        debug_log "Process $PROCESS_NAME is running - MASTER healthy"
        exit 0
    else
        logger -t keepalived -p daemon.error "Dead MASTER detected - process '$PROCESS_NAME' not running"
        debug_log "Process $PROCESS_NAME NOT running - MASTER dead"
        exit 1
    fi
fi
