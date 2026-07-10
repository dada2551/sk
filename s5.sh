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

# 识别系统并设置对应的变量
if [ -f /etc/debian_version ]; then
    OS="debian"
    PM="apt-get"
    CONF="/etc/danted.conf"
    SERVICE="danted"
elif [ -f /etc/redhat-release ]; then
    OS="centos"
    PM="yum"
    CONF="/etc/sockd.conf"
    SERVICE="sockd"
else
    echo "不支持的系统"
    exit 1
fi

echo "正在系统 ($OS) 上安装 SOCKS5 - 支持 TCP/UDP..."

# 1. 安装依赖
if [ "$OS" == "debian" ]; then
    $PM update -y
    $PM install -y dante-server
else
    # CentOS 需要先安装 EPEL 源
    $PM install -y epel-release
    $PM clean all && $PM makecache
    $PM install -y dante-server
fi

# 2. 获取网卡名称 (自动获取出口网卡)
NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
if [ -z "$NIC" ]; then
    NIC=$(ip add | grep "state UP" | awk -F': ' '{print $2}' | head -n 1)
fi

echo "检测到网卡: $NIC"

# 3. 写入配置文件 (根据系统选择 $CONF 路径)
cat > $CONF <<EOF
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

# 4. 创建代理用户 (如果已存在则更新密码)
if id "$USER" &>/dev/null; then
    echo "$USER:$PASS" | chpasswd
else
    useradd -r -s /bin/false $USER
    echo "$USER:$PASS" | chpasswd
fi

# 5. 配置防火墙
echo "正在配置防火墙开放 $PORT 端口 (TCP/UDP)..."
if command -v ufw > /dev/null; then
    ufw allow $PORT/tcp
    ufw allow $PORT/udp
elif command -v firewall-cmd > /dev/null; then
    firewall-cmd --permanent --add-port=$PORT/tcp
    firewall-cmd --permanent --add-port=$PORT/udp
    firewall-cmd --reload
fi

# 6. 启动服务
systemctl daemon-reload
systemctl stop $SERVICE 2>/dev/null
systemctl enable $SERVICE
systemctl start $SERVICE

# 7. 检查启动状态
if systemctl is-active --quiet $SERVICE; then
    IP=$(curl -s ifconfig.me)
    echo "------------------------------------------------"
    echo "SOCKS5 安装成功！"
    echo "系统服务: $SERVICE"
    echo "配置文件: $CONF"
    echo "服务器地址: $IP"
    echo "端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "TCP/UDP: 已全部开启"
    echo "连接链接: socks5://$USER:$PASS@$IP:$PORT"
    echo "------------------------------------------------"
else
    echo "安装可能失败，请运行 'systemctl status $SERVICE' 检查原因。"
fi
