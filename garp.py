import socket, psutil, struct, binascii

def send_unsolicited_arp_broadcast(interface, source_mac, source_ip, broadcast):
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    s.bind((interface, 0))

    # Ethernet header
    dest_mac = binascii.unhexlify("ff:ff:ff:ff:ff:ff".replace(":", ""))
    src_mac = binascii.unhexlify(source_mac.replace(":", ""))
    eth_type = b'\x08\x06'  # ARP
    eth_header = dest_mac + src_mac + eth_type

    # ARP header
    htype = b'\x00\x01'  # Ethernet
    ptype = b'\x08\x00'  # IPv4
    hlen = b'\x06'
    plen = b'\x04'
    operation = b'\x00\x02'  # ARP reply
    sender_mac = src_mac
    sender_ip = socket.inet_aton(source_ip)
    target_mac = dest_mac
    target_ip = socket.inet_aton(broadcast)
    arp_header = htype + ptype + hlen + plen + operation + sender_mac + sender_ip + target_mac + target_ip

    # Combine headers and send packet
    packet = eth_header + arp_header
    s.send(packet)
    s.close()

def send_garp(interface, src_mac, src_ip):
    s = socket.socket(socket.AF_PACKET, socket.SOCK_RAW)
    s.bind((interface, 0))

    # Ethernet frame
    dst_mac = 'ff:ff:ff:ff:ff:ff'  # Broadcast MAC address
    ethertype = 0x0806  # ARP protocol
    eth_header = struct.pack('!6s6sH', bytes.fromhex(dst_mac.replace(':', '')), bytes.fromhex(src_mac.replace(':', '')), ethertype)

    # ARP packet
    htype = 1  # Ethernet
    ptype = 0x0800  # IPv4
    hlen = 6  # MAC address length
    plen = 4  # IP address length
    operation = 1  # ARP request
    arp_header = struct.pack('!HHBBH6s4s6s4s', htype, ptype, hlen, plen, operation, bytes.fromhex(src_mac.replace(':', '')), socket.inet_aton(src_ip), bytes.fromhex(dst_mac.replace(':', '')), socket.inet_aton(src_ip))

    # Combine and send Ethernet frame and ARP packet
    packet = eth_header + arp_header
    s.send(packet)
    s.close()

if __name__ == "__main__":
    mac = "ff:ff:ff:ff:ff:ff"
    ip = "127.0.0.1"
    broadcast = "255.255.255.255"

    interfaces = psutil.net_if_addrs()
    
    for if_name, if_addr in interfaces.items():
        # Check if the interface is physical
        if not if_name.startswith(('lo', 'docker', 'veth', 'br-', 'virbr', 'vmnet', 'xfrm', 'vme', 'vsync')):
            for address in if_addr:
                if address.family == 2:
                    print(f"Interface: {if_name}, Family: {address.family}, IPv4 Address: {address.address}, Broadcast: {address.broadcast}")
                    ip = address.address
                    broadcast = address.broadcast
                if address.family == psutil.AF_LINK:
                    print(f"Interface: {if_name}, MAC Address: {address.address}")
                    mac = address.address

                    # Check if interface UP
                    net_if_stats = psutil.net_if_stats()
                    if if_name in net_if_stats:
                        if net_if_stats[if_name].isup:
                            send_garp(if_name, mac, ip)
                            send_unsolicited_arp_broadcast(if_name, mac, ip, broadcast)