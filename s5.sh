sudo su - << 'EOF'
# 1. 禁用 man-db 索引更新（防止安装时卡在 100% 或 Processing triggers）
echo "正在优化系统：禁用手册页索引更新以提速..."
cat <<INNER_EOF > /etc/dpkg/dpkg.cfg.d/01_nodoc
path-exclude /usr/share/man/*
path-exclude /usr/share/doc/*
path-exclude /usr/share/info/*
INNER_EOF

# 2. 暴力清理可能存在的 apt/dpkg 锁文件
echo "正在清理系统锁文件..."
killall apt apt-get dpkg 2>/dev/null
rm -f /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock
dpkg --configure -a

# 3. 安装 dante-server
echo "正在快速安装 dante-server..."
apt-get update -y
apt-get install -y dante-server

# 4. 自动配置变量
PORT=36470
USER="proxyuser"
PASS="Aaaaqqqq@1"
NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
IP=$(curl -s ifconfig.me || curl -s api.ipify.org)

# 5. 写入 SOCKS5 配置文件
echo "正在写入配置文件..."
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

# 6. 设置代理用户
echo "正在设置代理用户..."
id "$USER" &>/dev/null || useradd -r -s /bin/false "$USER"
echo "$USER:$PASS" | chpasswd

# 7. 开放系统内部防火墙 (UFW)
if command -v ufw > /dev/null; then
    echo "正在开放 UFW 端口..."
    ufw allow $PORT/tcp
    ufw allow $PORT/udp
fi

# 8. 重启并激活服务
echo "正在启动服务..."
systemctl stop danted
systemctl start danted
systemctl enable danted

# 9. 最终安装报告
clear
echo "================================================================"
echo "          SOCKS5 代理安装成功 (Ubuntu 优化版)           "
echo "================================================================"
echo "  [服务器状态]: $(systemctl is-active danted)"
echo "  [公网 IP]: $IP"
echo "  [监听端口]: $PORT"
echo "  [用户名]: $USER"
echo "  [密  码]: $PASS"
echo "----------------------------------------------------------------"
echo "  [TCP 状态]: 已开启"
echo "  [UDP 状态]: 已开启"
echo "----------------------------------------------------------------"
echo "  [标准连接]: socks5://$USER:$PASS@$IP:$PORT"
echo "----------------------------------------------------------------"
echo "  [Windows 命令行测试方法]:"
echo "  curl -v --proxy-user \"$USER:$PASS\" --socks5-hostname $IP:$PORT https://www.google.com"
echo "================================================================"
echo "  ⚠️  阿里云特别提醒：                                         "
echo "  请务必登录阿里云控制台，在【安全组规则】中手动添加以下规则：   "
echo "  1. 协议：TCP | 端口范围：$PORT | 源地址：0.0.0.0/0"
echo "  2. 协议：UDP | 端口范围：$PORT | 源地址：0.0.0.0/0"
echo "================================================================"
EOF
