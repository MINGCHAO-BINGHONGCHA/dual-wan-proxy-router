#!/bin/bash
# ============================================================
# verify-routing.sh — 验证国内/国外流量走向
# 用法: ./verify-routing.sh
# ============================================================

CAMPUS_IP="183.95.255.73"
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✅ $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  1. 路由器默认出口${NC}"
echo -e "${CYAN}========================================${NC}"
DEFAULT_IP=$(curl -4 -s --max-time 5 http://myip.ipip.net 2>/dev/null)
echo "  $DEFAULT_IP"
if echo "$DEFAULT_IP" | grep -q "$CAMPUS_IP"; then
    pass "默认路由走校园网 enp1s0"
else
    fail "默认路由不是校园网！"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  2. DNS 验证（LAN 侧 dnsmasq → mihomo）${NC}"
echo -e "${CYAN}========================================${NC}"
GOOGLE_DNS=$(dig +short google.com @192.168.100.1 2>/dev/null | head -1)
BAIDU_DNS=$(dig +short baidu.com @192.168.100.1 2>/dev/null | head -1)
echo "  google.com → $GOOGLE_DNS"
echo "  baidu.com  → $BAIDU_DNS"
if echo "$GOOGLE_DNS" | grep -q '198.18'; then
    pass "google fake-IP 正常"
else
    fail "google DNS 未走 mihomo fake-IP"
fi
if echo "$BAIDU_DNS" | grep -q '198.18'; then
    pass "baidu fake-IP 正常"
else
    fail "baidu DNS 未走 mihomo fake-IP"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  3. 路由器国外访问（应走代理）${NC}"
echo -e "${CYAN}========================================${NC}"
FOREIGN_IP=$(curl -4 -s --max-time 5 https://ip.sb 2>/dev/null)
echo "  ip.sb → $FOREIGN_IP"
if [ -n "$FOREIGN_IP" ] && ! echo "$FOREIGN_IP" | grep -q "$CAMPUS_IP"; then
    pass "国外访问走代理（非校园网）"
else
    fail "国外访问可能没走代理"
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  4. iptables 打标计数（需 sudo）${NC}"
echo -e "${CYAN}========================================${NC}"
echo "  （请手动执行: sudo ./verify-routing.sh iptables）"
if [ "$1" = "iptables" ]; then
    sudo iptables-legacy -t mangle -L OUTPUT -nv | grep -E 'mihomo|china_ipv4'
fi

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  5. LAN 设备手动测试${NC}"
echo -e "${CYAN}========================================${NC}"
echo "  LAN 设备上执行:"
echo "    curl -4 http://myip.ipip.net   # 应显示校园网 IP (183.95.x.x)"
echo "    curl -4 https://www.google.com -o /dev/null -w '%{http_code}'  # 应 200"
echo ""
echo "  或用浏览器访问:"
echo "    http://myip.ipip.net  → 期望: 183.95.255.73 (校园网)"
echo "    https://ip.sb         → 期望: 非校园网 (代理 IP)"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  判断标准${NC}"
echo -e "${CYAN}========================================${NC}"
echo "  ✅ 国内: 默认路由 + myip.ipip.net = 校园网 IP"
echo "  ✅ 国外: curl google.com 通 + ip.sb ≠ 校园网 IP"
echo "  ✅ DNS:  LAN → dnsmasq → fake-IP (198.18.x.x)"
echo "  ✅ 计数: iptables china_ipv4 RETURN pkts > 0"
echo "            iptables MARK 0x100 pkts > RETURN pkts"
