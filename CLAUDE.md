# CLAUDE.md

## Project Overview

Debian 13 (trixie) soft router with DNS-level split routing: domestic traffic → campus network (enp1s0), foreign traffic → mihomo proxy → USB-tethered phone (usb0).

- **enp1s0** (WAN): Campus network via Ruijie client auth, DHCP (10.202.34.189/20). Default route.
- **enp2s0** (LAN): Internal network, static IP 192.168.100.1/24.
- **usb0** (phone): USB-tethered Android, used exclusively for mihomo proxy traffic.

**Goal**: DNS-level split — domestic domains resolve to real IPs via 114.114.114.114 (bypassing mihomo entirely), foreign domains resolve to fake-IPs via mihomo:1053 and route through usb0.

## Architecture

```
Domestic:  DNS → dnsmasq → 114.114.114.114 → real IP → main table → enp1s0 (campus)
Foreign:   DNS → dnsmasq → mihomo:1053 → fake-IP → utun TUN → mihomo proxy → usb0 (phone)
```

### Policy Routing
- `ip rule 100`: fwmark 0x1 → table 100 (utun TUN)
- `ip rule 200`: fwmark 0x100 → table 200 (usb0 phone)
- Main table: enp1s0 (metric 1002) preferred over usb0 (metric 1005)

### iptables Marks
- `0x1`: LAN/router traffic to non-China IPs → TUN (mihomo processing)
- `0x100`: Mihomo own outbound traffic → usb0 (phone)

## Key Files

| Path | Purpose |
|------|---------|
| `setup-dns-split.sh` | One-shot deployment script |
| `fix-utun-route.sh` | Restore utun routes after mihomo restart |
| `verify-routing.sh` | Routing verification |
| `config/mihomo-config.yaml` | Mihomo proxy config (TUN + fake-IP + rules) |
| `config/iptables.rules.v4` | iptables rules (mangle/nat/filter) |
| `config/resolv.conf.head` | Router DNS (campus DNS first) |
| `config/dhcpcd.exit-hook` | Auto-configure table 200 on usb0 DHCP |
| `scripts/setup-policy-routing` | Initialize ip rules and routing tables |
| `scripts/update-china-routes` | Download China IP ranges for ipset |

## System Files (deployed to /etc)

| Path | Purpose |
|------|---------|
| `/etc/mihomo/config.yaml` | mihomo config |
| `/etc/iptables/rules.v4` | iptables rules (iptables-legacy) |
| `/etc/dnsmasq.d/router.conf` | dnsmasq: domain split + mihomo upstream |
| `/etc/dnsmasq.d/accelerated-domains.china.conf` | 112k+ Chinese domain rules |
| `/etc/resolv.conf.head` | Router DNS priority |
| `/etc/systemd/system/mihomo.service` | mihomo service |

## Commands

```bash
# Deploy
sudo ./setup-dns-split.sh

# Fix routes after mihomo restart
sudo ./fix-utun-route.sh

# Verify
./verify-routing.sh

# Check DNS split
dig +short baidu.com @192.168.100.1    # real IP
dig +short google.com @192.168.100.1   # 198.18.x.x

# Check routing
curl -4 http://myip.ipip.net           # campus IP
curl -4 --socks5 127.0.0.1:7891 https://ip.sb  # proxy IP

# Check rules
sudo iptables-legacy -t mangle -L OUTPUT -nv | grep "owner UID"
curl -s http://127.0.0.1:9090/rules

# Update China domain list
sudo curl -o /etc/dnsmasq.d/accelerated-domains.china.conf \
  https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
sudo systemctl restart dnsmasq
```

## Constraints

- The campus network uses Ruijie client auth on enp1s0 — do not break it.
- The USB phone connection is metered; only proxy traffic should use it.
- Mihomo restart removes utun routes — always run `fix-utun-route.sh` after.
- `/etc/resolv.conf` is managed by dhcpcd; use `/etc/resolv.conf.head` for persistence.
- Use `iptables-legacy`, not `iptables` (nf_tables backend incompatible with ipset).
