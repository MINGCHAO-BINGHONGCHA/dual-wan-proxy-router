#!/bin/bash
# ============================================================
# setup-dns-split.sh — DNS 层面国内外分流
# 国内域名 → 114 DNS 真实 IP → enp1s0 校园网
# 国外域名 → mihomo:1053 fake-IP → proxy → usb0
# 用法: sudo ./setup-dns-split.sh
# ============================================================

set -e

echo "=== Step 1: 下载国内域名列表 ==="
CHINA_LIST="/etc/dnsmasq.d/accelerated-domains.china.conf"
CHINA_LIST_TMP=$(mktemp)

# 从 dnsmasq-china-list 项目下载
URL="https://raw.githubusercontent.com/felixonmars/dnsmasq-china-list/master/accelerated-domains.china.conf"
if curl -fsSL --max-time 30 "$URL" -o "$CHINA_LIST_TMP" 2>/dev/null; then
    DOMAINS=$(grep -c '^server=' "$CHINA_LIST_TMP" 2>/dev/null || echo 0)
    echo "  下载成功: $DOMAINS 个国内域名规则"
    mv "$CHINA_LIST_TMP" "$CHINA_LIST"
else
    echo "  GitHub 下载失败, 使用内置基础列表"
    # 内置常用国内域名
    cat > "$CHINA_LIST" << 'CHINA'
server=/cn/114.114.114.114
server=/baidu.com/114.114.114.114
server=/baidustatic.com/114.114.114.114
server=/bdstatic.com/114.114.114.114
server=/bilibili.com/114.114.114.114
server=/bilivideo.com/114.114.114.114
server=/qq.com/114.114.114.114
server=/qpic.cn/114.114.114.114
server=/qcloud.com/114.114.114.114
server=/gtimg.com/114.114.114.114
server=/weixin.com/114.114.114.114
server=/wechat.com/114.114.114.114
server=/taobao.com/114.114.114.114
server=/tmall.com/114.114.114.114
server=/alicdn.com/114.114.114.114
server=/alipay.com/114.114.114.114
server=/alibaba.com/114.114.114.114
server=/aliyun.com/114.114.114.114
server=/1688.com/114.114.114.114
server=/jd.com/114.114.114.114
server=/360buyimg.com/114.114.114.114
server=/sina.com.cn/114.114.114.114
server=/weibo.com/114.114.114.114
server=/weibocdn.com/114.114.114.114
server=/163.com/114.114.114.114
server=/126.com/114.114.114.114
server=/netease.com/114.114.114.114
server=/sohu.com/114.114.114.114
server=/sogou.com/114.114.114.114
server=/douyin.com/114.114.114.114
server=/douyinvod.com/114.114.114.114
server=/bytedance.com/114.114.114.114
server=/toutiao.com/114.114.114.114
server=/pinduoduo.com/114.114.114.114
server=/meituan.com/114.114.114.114
server=/meituan.net/114.114.114.114
server=/xiaomi.com/114.114.114.114
server=/mi.com/114.114.114.114
server=/miui.com/114.114.114.114
server=/huawei.com/114.114.114.114
server=/honor.com/114.114.114.114
server=/zhihu.com/114.114.114.114
server=/csdn.net/114.114.114.114
server=/jianshu.com/114.114.114.114
server=/juejin.cn/114.114.114.114
server=/ipip.net/114.114.114.114
server=/ip.sb/114.114.114.114
server=/iqiyi.com/114.114.114.114
server=/youku.com/114.114.114.114
server=/tencent.com/114.114.114.114
server=/tencent-cloud.com/114.114.114.114
server=/myqcloud.com/114.114.114.114
server=/cloud.tencent.com/114.114.114.114
server=/dns.alidns.com/114.114.114.114
server=/cn.bing.com/114.114.114.114
CHINA
fi

echo ""

echo "=== Step 2: 写入 dnsmasq 主配置 ==="
rm -f /etc/dnsmasq.d/router.conf.mihomo /etc/dnsmasq.d/router.conf.school

cat > /etc/dnsmasq.d/router.conf << 'CONF'
# dnsmasq 路由器配置 — DNS 层面国内外分流
# 国内域名 → accelerated-domains.china.conf → 114.114.114.114 (真实 IP)
# 国外域名 → mihomo:1053 (fake-IP) → TUN → proxy → usb0

# 上游: 默认走 mihomo fake-IP
server=127.0.0.1#1053

# 国内域名直连 (在 accelerated-domains.china.conf 中定义)
conf-file=/etc/dnsmasq.d/accelerated-domains.china.conf

interface=enp2s0
listen-address=127.0.0.1
cache-size=2000
min-cache-ttl=600
domain-needed
bogus-priv
log-queries
CONF

echo ""

echo "=== Step 3: 更新 iptables — mihomo 全部标 0x100 → usb0 ==="
# mihomo 现在只处理国外流量, 全部走 usb0
cat > /etc/iptables/rules.v4 << 'IPT'
# ============================================================
# iptables 规则 — DNS 层面国内外分流
# ============================================================

# --- mangle 表 ---
*mangle
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

# 保留本地/私有地址
-A PREROUTING -d 192.168.0.0/16 -j RETURN
-A PREROUTING -d 10.0.0.0/8 -j RETURN
-A PREROUTING -d 172.16.0.0/12 -j RETURN
-A PREROUTING -d 198.18.0.0/16 -j RETURN
-A OUTPUT -d 192.168.0.0/16 -j RETURN
-A OUTPUT -d 10.0.0.0/8 -j RETURN
-A OUTPUT -d 172.16.0.0/12 -j RETURN
-A OUTPUT -d 198.18.0.0/16 -j RETURN

# LAN 客户端 → 非中国 IP → mark 0x1 → table 100 (utun/TUN)
-A PREROUTING -i enp2s0 -m set ! --match-set china_ipv4 dst -j MARK --set-mark 0x1

# Mihomo 出站全部标记 0x100 → table 200 → usb0
-A OUTPUT -m owner --uid-owner mihomo -j MARK --set-mark 0x100
-A OUTPUT -m owner --uid-owner mihomo -j RETURN

# 路由器自身 → 非中国 IP → mark 0x1 → table 100 (utun/TUN)
-A OUTPUT -m set ! --match-set china_ipv4 dst -j MARK --set-mark 0x1

COMMIT

# --- nat 表 ---
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]

-A POSTROUTING -s 192.168.100.0/24 -o enp1s0 -j MASQUERADE
-A POSTROUTING -s 192.168.100.0/24 -o usb0 -j MASQUERADE
-A POSTROUTING -o usb0 -j MASQUERADE

COMMIT

# --- filter 表 ---
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]

-A FORWARD -i enp2s0 -o enp1s0 -j ACCEPT
-A FORWARD -i enp1s0 -o enp2s0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A FORWARD -i enp2s0 -o usb0 -j ACCEPT
-A FORWARD -i usb0 -o enp2s0 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

COMMIT
IPT

iptables-legacy-restore < /etc/iptables/rules.v4
echo "  iptables 已加载"

echo ""

echo "=== Step 4: 重启 dnsmasq ==="
if dnsmasq --test -C /etc/dnsmasq.conf 2>&1; then
    systemctl restart dnsmasq
    echo "  dnsmasq 已重启"
else
    echo "  !! dnsmasq 配置有误, 请检查"
    exit 1
fi

echo ""

echo "=== 验证 ==="
echo "国内 DNS:"
echo -n "  baidu.com → "; dig +short baidu.com @127.0.0.1 | head -1
echo -n "  qq.com    → "; dig +short qq.com @127.0.0.1 | head -1
echo "国外 DNS:"
echo -n "  google.com → "; dig +short google.com @127.0.0.1 | head -1
echo -n "  youtube.com → "; dig +short youtube.com @127.0.0.1 | head -1
echo ""
echo "国内(真实 IP) ≠ 198.18.x.x, 国外(fake-IP) = 198.18.x.x"
echo "国内域名: $DOMAINS 个规则"
echo ""
echo "路由器测试:"
echo -n "  直连: "; curl -4 -s --max-time 3 http://myip.ipip.net
echo ""
echo -n "  SOCKS5: "; curl -4 -s --max-time 5 --socks5 127.0.0.1:7891 http://myip.ipip.net
echo ""
