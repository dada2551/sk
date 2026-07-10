#!/bin/bash

# 配置信息
PORT=36470
USER="user"
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

echo "正在安装 SOCKS5 (Dante)..."

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

# 监听端口
internal: 0.0.0.0 port = $PORT
# 出口网卡
external: $NIC

# 认证方法
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
EOF

# 创建代理用户
userdel $USER 2>/dev/null
useradd -r -s /bin/false $USER
echo "$USER:$PASS" | chpasswd

# 启动服务
systemctl stop danted 2>/dev/null
systemctl enable danted
systemctl start danted

# 配置防火墙
if command -v ufw > /dev/null; then
    ufw allow $PORT/tcp
elif command -v firewall-cmd > /dev/null; then
    firewall-cmd --permanent --add-port=$PORT/tcp
    firewall-cmd --reload
fi

# 获取公网IP
IP=$(curl -s ifconfig.me)

echo "------------------------------------------------"
echo "SOCKS5 安装完成！"
echo "服务器地址: $IP"
echo "端口: $PORT"
echo "用户名: $USER"
echo "密码: $PASS"
echo "连接配置: socks5://$USER:$PASS@$IP:$PORT"
echo "------------------------------------------------"
