# 软路由状态文档

> 最后更新: 2026-05-30
> 机器: Debian 13 (trixie), enp1s0 + enp2s0 + usb0

## 架构概览

```
LAN (192.168.100.0/24)
  │
  ├─ 国内: DNS → 114.114.114.114 (真实 IP) → enp1s0 → 校园网 183.95.x.x
  └─ 国外: DNS → mihomo:1053 (fake-IP) → TUN → proxy → usb0 → 手机 50.7.x.x
```

## 接口

| 接口 | IP | 用途 |
|------|-----|------|
| enp1s0 | 10.202.34.189/20 (DHCP) | 校园 WAN, 国内出口 |
| enp2s0 | 192.168.100.1/24 (静态) | LAN |
| usb0 | 192.168.161.x/24 (DHCP) | USB 手机, 代理出口 |
| utun | 198.18.0.1/30 | mihomo TUN fake-IP |

## 策略路由

```
ip rule:
  100:  fwmark 0x1    → table 100 (utun)
  200:  fwmark 0x100  → table 200 (usb0)

table 100:  default dev utun
table 200:  default via 192.168.161.115 dev usb0
main:       default via 10.202.47.254 dev enp1s0 (metric 1002)
            default via 192.168.161.115 dev usb0 (metric 1005)
```

## DNS 分流 (dnsmasq)

```
dnsmasq → /etc/dnsmasq.d/accelerated-domains.china.conf (112,849 条)
  国内域名 → 114.114.114.114
  其余     → 127.0.0.1#1053 (mihomo fake-IP)
```

## 流量标记 (iptables mangle)

```
OUTPUT:
  uid=mihomo         → MARK 0x100 (全部走 usb0)
  非 china_ipv4      → MARK 0x1   (走 TUN)

PREROUTING:
  enp2s0 + 非 china  → MARK 0x1   (LAN 代理流量走 TUN)
  198.18.0.0/16      → RETURN     (fake-IP 直通 utun)
```

## 核心组件

| 组件 | 状态 |
|------|------|
| mihomo | ✅ running |
| dnsmasq | ✅ running (112,849 国内域名) |
| iptables-legacy | ✅ 已加载 |
| ipset china_ipv4 | ✅ 已加载 |
| dhcpcd | ✅ enp1s0 + usb0 |

## 验证结果

| 测试 | 结果 |
|------|------|
| 路由器直连 | 183.95.255.73 (校园) |
| 路由器 SOCKS5 国内 | 183.95.251.79 (手机) |
| 路由器代理国外 | 50.7.x.x (香港) |
| DNS baidu.com | 真实 IP |
| DNS google.com | 198.18.x.x fake-IP |
