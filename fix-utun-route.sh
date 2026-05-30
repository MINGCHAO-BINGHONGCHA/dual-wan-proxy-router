#!/bin/bash
# ============================================================
# fix-utun-route.sh — 修复 mihomo 重启后路由丢失
# 用法: sudo ./fix-utun-route.sh
# ============================================================

echo "[1/4] 添加 table 100 默认路由 → utun..."
ip route add default dev utun table 100 2>/dev/null && echo "  ✅ 已添加" || echo "  ⚠️ 已存在"

echo "[2/4] 添加 main table 198.18.0.0/16 → utun（fake-IP 路由）..."
ip route add 198.18.0.0/16 dev utun 2>/dev/null && echo "  ✅ 已添加" || echo "  ⚠️ 已存在"

echo "[3/4] 写入 systemd drop-in（mihomo 重启后自动添加）..."
mkdir -p /etc/systemd/system/mihomo.service.d
cat > /etc/systemd/system/mihomo.service.d/route-fix.conf << 'CONF'
[Service]
ExecStartPost=/bin/sh -c 'sleep 1 && ip route add default dev utun table 100 2>/dev/null || true; ip route add 198.18.0.0/16 dev utun 2>/dev/null || true'
CONF
echo "  ✅ 已写入"

echo "[4/4] 重载 systemd..."
systemctl daemon-reload
echo "  ✅ 完成"

echo ""
echo "=== 验证 ==="
echo "table 100:"
ip route show table 100
echo ""
echo "main table 198.18:"
ip route show table main | grep 198.18
echo ""
echo "systemd drop-in:"
cat /etc/systemd/system/mihomo.service.d/route-fix.conf
