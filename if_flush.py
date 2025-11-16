from pyroute2 import IPRoute, NetlinkError

if __name__ == "__main__":
    ip = IPRoute()
    try:
        interfaces = ip.get_links()

        for interface in interfaces:
            print(f"Index: {interface['index']}, Name: {interface.get_attr('IFLA_IFNAME')}, State: {interface.get_attr('IFLA_OPERSTATE')}")
            if_name = interface.get_attr('IFLA_IFNAME')
            if not if_name.startswith(('lo', 'docker', 'veth', 'br-', 'virbr', 'vmnet', 'vme', 'enp10s0', 'enp11s0')):
                try:
                    # flush all addresses with IFA_LABEL='if_name':
                    ip.flush_addr(label=if_name)
                    print(f"Flushed addresses on {if_name}")
                except NetlinkError as e:
                    print(f"Failed to flush {if_name}: {e}")
    finally:
        ip.close()
