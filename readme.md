# 智能分流软路由

Debian 13 软路由，DNS 层面国内外分流：国内走校园网，国外走手机代理。

## 网络拓扑

```
┌──────────────────────────────────────────────────┐
│                  Debian 软路由                      │
│                                                    │
│  enp1s0 (校园 WAN)    enp2s0 (LAN)    usb0 (手机)   │
│  10.202.34.189/20    192.168.100.1    192.168.161.x │
│       ▲                   ▲                ▲        │
│       │                   │                │        │
│  国内直连              LAN 设备        代理出口      │
│  183.95.x.x           192.168.100.x    50.7.x.x    │
│  湖北联通                             香港节点      │
└──────────────────────────────────────────────────┘
```

## 核心思路

**DNS 层面分流，不再依赖 iptables 判断国内外。**

```
国内域名 (112,849个):
  dnsmasq → 114.114.114.114 → 真实 IP → 主路由表 → enp1s0 校园网

国外域名:
  dnsmasq → mihomo:1053 → fake-IP (198.18.x.x) → TUN → proxy → usb0 手机
```

### 为什么用 DNS 分流而非 iptables IP 分流

iptables 用 `ipset china_ipv4` 匹配目的 IP 来判断国内外，但 ipset 和 mihomo 的 GeoIP 数据库不完全一致，导致约 45% 的国内连接被误判为国外。DNS 层面用域名列表分流更精确。

## 项目文件

```
network/
├── readme.md                          # 本文档
├── STATUS.md                          # 运行状态
├── CLAUDE.md                          # AI 辅助说明
│
├── setup-dns-split.sh                 # 一键部署脚本 ★
├── fix-utun-route.sh                  # 修复 mihomo 重启后路由丢失
├── verify-routing.sh                  # 路由验证脚本
│
├── config/
│   ├── mihomo-config.yaml             # mihomo 代理配置
│   ├── iptables.rules.v4              # iptables 规则 (mangle/nat/filter)
│   ├── resolv.conf.head               # 路由器 DNS (校园 DNS 优先)
│   ├── dhcpcd.exit-hook               # usb0 DHCP 后自动配置 table 200
│   └── 99-disable-ipv6-lan.conf       # 禁 LAN IPv6
│
├── scripts/
│   ├── setup-policy-routing           # 策略路由初始化 (ip rule + table)
│   └── update-china-routes            # 更新 china_ipv4 ipset
│
├── services/
│   ├── mihomo.service                 # mihomo systemd 服务
│   ├── setup-policy-routing.service   # 开机自动配置路由
│   ├── update-china-routes.service    # 国内 IP 更新服务
│   └── update-china-routes.timer      # 每周更新一次
│
├── mihomo-modules.conf                # TUN 内核模块
└── 99-android-tether.rules            # USB 网卡命名 udev 规则
```

## 策略路由

```
ip rule:
  100:  fwmark 0x1    → table 100 (utun TUN)
  200:  fwmark 0x100  → table 200 (usb0 手机)

table 100:   default dev utun
table 200:   default via 192.168.161.115 dev usb0
main table:  default via enp1s0 (metric 1002)   ← 国内优先
             default via usb0   (metric 1005)   ← 备用
```

## iptables 标记规则

```
mangle/PREROUTING (LAN 流量):
  198.18.0.0/16 → RETURN          # fake-IP 不打标，走主表到 utun
  非 china_ipv4 → MARK 0x1        # 非国内 IP → table 100 → TUN

mangle/OUTPUT (路由器自身):
  uid=mihomo    → MARK 0x100      # mihomo 出站全部走 usb0
  非 china_ipv4 → MARK 0x1        # 路由器自身代理流量 → TUN
```

## 流量路径

### LAN 客户端访问国内 (baidu.com)

```
1. DNS: 客户端 → dnsmasq → 114.114.114.114 → 真实 IP (111.63.x.x)
2. TCP: 192.168.100.x → 111.63.x.x:443
3. PREROUTING: dst 在 china_ipv4 → 不打标
4. 路由: 主表 → enp1s0 → 校园网 NAT → 183.95.x.x
```

### LAN 客户端访问国外 (google.com)

```
1. DNS: 客户端 → dnsmasq → mihomo:1053 → fake-IP (198.18.0.x)
2. TCP: 192.168.100.x → 198.18.0.x:443
3. PREROUTING: dst=198.18.x → RETURN (不打标)
4. 路由: 主表 198.18.0.0/16 → utun → mihomo TUN
5. mihomo: 匹配规则 → Auto(proxy) → 代理节点
6. mihomo 出站: uid=mihomo → MARK 0x100 → table 200 → usb0 手机
```

## 安装部署

```bash
# 1. 一键部署
sudo ./setup-dns-split.sh

# 2. 修复路由（每次 mihomo 重启后需要）
sudo ./fix-utun-route.sh

# 3. 部署 mihomo 配置
sudo cp config/mihomo-config.yaml /etc/mihomo/config.yaml
sudo systemctl restart mihomo

# 4. 部署 iptables
sudo cp config/iptables.rules.v4 /etc/iptables/rules.v4
sudo bash -c 'iptables-legacy-restore < /etc/iptables/rules.v4'

# 5. 复制系统文件
sudo cp config/resolv.conf.head /etc/
sudo cp services/mihomo.service /etc/systemd/system/
sudo cp services/setup-policy-routing.service /etc/systemd/system/
sudo cp services/update-china-routes.service /etc/systemd/system/
sudo cp services/update-china-routes.timer /etc/systemd/system/
sudo cp scripts/setup-policy-routing /usr/local/sbin/
sudo cp scripts/update-china-routes /usr/local/sbin/
sudo cp mihomo-modules.conf /etc/modules-load.d/mihomo.conf
sudo cp 99-android-tether.rules /etc/udev/rules.d/
sudo cp config/99-disable-ipv6-lan.conf /etc/sysctl.d/

# 6. 启用服务
sudo systemctl daemon-reload
sudo systemctl enable mihomo setup-policy-routing update-china-routes.timer
sudo systemctl start mihomo setup-policy-routing update-china-routes.timer
```

## 验证

```bash
# 完整检查
./verify-routing.sh

# DNS 分流
dig +short baidu.com @192.168.100.1   # 应返回真实 IP，非 198.18.x
dig +short google.com @192.168.100.1  # 应返回 fake-IP 198.18.x

# 出口 IP
curl -4 http://myip.ipip.net          # 应显示 183.95.x.x (校园网)
curl -4 --socks5 127.0.0.1:7891 https://ip.sb  # 应显示代理 IP

# iptables 计数
sudo iptables-legacy -t mangle -L OUTPUT -nv | grep "owner UID"
```

## 常用命令

```bash
# 更新国内域名列表
sudo curl -o /etc/dnsmasq.d/accelerated-domains.china.conf \
  https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf
sudo systemctl restart dnsmasq

# 切换 DNS 模式 (校园直连 → 编辑 router.conf 改为 resolv-file)
sudo vim /etc/dnsmasq.d/router.conf

# 重启 mihomo (记得修复路由)
sudo systemctl restart mihomo && sudo ./fix-utun-route.sh

# 查看 mihomo 规则命中
curl -s http://127.0.0.1:9090/rules | python3 -m json.tool

# 手动更新 china_ipv4 ipset
sudo /usr/local/sbin/update-china-routes
```

## 故障排查

| 现象 | 检查 |
|------|------|
| LAN 不能上网 | `ip route show table 100` 是否有 `default dev utun` |
| 国内走代理 | `dig baidu.com @127.0.0.1` 是否返回真实 IP |
| 代理不通 | `curl -4 --socks5 127.0.0.1:7891 https://ip.sb` |
| 全部走手机 | `ip route show \| grep default` 确认 enp1s0 metric 更低 |
| 全部走校园 | `ip route show table 200` 是否为空 |

## 依赖

| 组件 | 用途 |
|------|------|
| mihomo (Clash Meta) | 代理核心，TUN + fake-IP |
| dnsmasq | DNS 服务器，国内域名分流 |
| iptables-legacy | 流量标记 (mangle) + NAT |
| ipset | china_ipv4 集合 |
| dhcpcd | enp1s0/usb0 DHCP 客户端 |
| curl + dig | 测试验证 |
