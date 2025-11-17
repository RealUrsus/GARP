#!/bin/bash
# Dead Module Detection
CONF=/etc/keepalived/keepalived.conf

IF=$1
PROCESS=$2

if [ -r $CONF ]; then
    VIRTUAL_IPS=$(sed -n '/virtual_ipaddress\s*{/,/}/{ /virtual_ipaddress\s*{/! { /}/! p }}' $CONF | sed -n -r '/\b((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b/p' | tr -d '\n' | tr -d '\t')
    for ip in $VIRTUAL_IPS
        do
            if  ! $(ip -4 a show dev $IF | grep -qw "$ip"); then
                # This is BACKUP node
                exit 0
            fi
    done
else
    echo >&2 "no keepalived.conf"
    exit 1
fi

# Use "#if /usr/bin/pgrep $PROCESS > /dev/null 2>&1 ; then" if process is sencitive for killall
if /usr/bin/killall -0 $PROCESS > /dev/null 2>&1 ; then
    exit 0
else
    /usr/bin/logger -t keepalived -p daemon.error "Dead MASTER detected"
    exit 1
fi
