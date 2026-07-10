#!/bin/bash

# 配置信息
PORT=36470
USER="proxyuser"
PASS="Aaaaqqqq@1"

# 检查权限
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以 root 权限运行"
   exit 1
fi

# 识别系统
if [ -f /etc/debian_version ]; then
    OS="debian"
    PM="apt-get"
elif [ -f /etc/redhat-release ]; then
    OS="centos"
    PM="yum"
else
    echo "不支持的系统"
    exit 1
fi

echo "正在安装 SOCKS5 (Dante) - 支持 TCP/UDP..."

# 安装依赖
$PM update -y
if [ "$OS" == "debian" ]; then
    $PM install -y dante-server
else
    $PM install -y epel-release
    $PM install -y dante-server
fi

# 获取网卡名称
NIC=$(ip add | grep "^2: " | awk -F'[ :]+' '{print $2}')
if [ -z "$NIC" ]; then
    NIC=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
fi

# 创建配置文件
cat > /etc/danted.conf <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody

# 监听端口 (TCP 和 UDP 协商)
internal: 0.0.0.0 port = $PORT
# 出口网卡
external: $NIC

# 认证方法
socksmethod: username
clientmethod: none

# 客户端白名单（允许所有IP连接）
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

# 规则放行：允许 TCP 连接和 UDP 关联
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    # connect 为 TCP, udpassociate 为 UDP
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF

# 创建代理用户
userdel $USER 2>/dev/null
useradd -r -s /bin/false $USER
echo "$USER:$PASS" | chpasswd

# 启动服务
systemctl stop danted 2>/dev/null
systemctl enable danted
systemctl start danted

# 配置防火墙：同时开放 TCP 和 UDP
if command -v ufw > /dev/null; then
    ufw allow $PORT/tcp
    ufw allow $PORT/udp
elif command -v firewall-cmd > /dev/null; then
    firewall-cmd --permanent --add-port=$PORT/tcp
    firewall-cmd --permanent --add-port=$PORT/udp
    firewall-cmd --reload
fi

# 获取公网IP
IP=$(curl -s ifconfig.me)

echo "------------------------------------------------"
echo "SOCKS5 安装完成 (TCP+UDP 已启用)！"
echo "服务器地址: $IP"
echo "端口: $PORT"
echo "用户名: $USER"
echo "密码: $PASS"
echo "UDP 状态: 已开启"
echo "连接配置: socks5://$USER:$PASS@$IP:$PORT"
echo "------------------------------------------------"
