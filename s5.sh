sudo su - << 'EOF'
# 1. 彻底禁用 man-db 索引更新（让 apt 安装变快）
echo "正在禁用手册页索引更新以提速..."
cat <<INNER_EOF > /etc/dpkg/dpkg.cfg.d/01_nodoc
path-exclude /usr/share/man/*
path-exclude /usr/share/doc/*
path-exclude /usr/share/info/*
INNER_EOF

# 2. 杀掉残留进程并清理锁
killall apt apt-get dpkg 2>/dev/null
rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
dpkg --configure -a

# 3. 再次确保安装了 dante-server (现在会飞快)
apt-get update
apt-get install -y dante-server

# 4. 写入 SOCKS5 配置
PORT=36470
USER="proxyuser"
PASS="Aaaaqqqq@1"
NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')

cat > /etc/danted.conf <<INNER_EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

internal: 0.0.0.0 port = $PORT
external: $NIC

socksmethod: username
clientmethod: none

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
INNER_EOF

# 5. 用户设置
id "proxyuser" &>/dev/null || useradd -r -s /bin/false proxyuser
echo "proxyuser:Aaaaqqqq@1" | chpasswd

# 6. 开放防火墙
if command -v ufw > /dev/null; then
    ufw allow 36470/tcp
    ufw allow 36470/udp
fi

# 7. 重启服务
systemctl stop danted
systemctl start danted
systemctl enable danted

# 8. 完成
echo "------------------------------------------------"
echo "安装及配置已完成！"
systemctl status danted --no-pager
echo "------------------------------------------------"
EOF
