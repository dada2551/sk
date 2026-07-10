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
    # 获取 CentOS 大版本号
    CENTOS_VER=$(cat /etc/redhat-release | sed -r 's/.* ([0-9]+)\..*/\1/')
else
    echo "不支持的系统"
    exit 1
fi

echo "正在系统 ($OS $CENTOS_VER) 上安装 SOCKS5 - 支持 TCP/UDP..."

# 1. 针对 CentOS 8 停止维护的特殊处理 (EOL Fix)
if [ "$OS" == "centos" ] && [ "$CENTOS_VER" == "8" ]; then
    echo "检测到 CentOS 8，正在修复软件源地址..."
    sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/CentOS-*
    sed -i 's|#baseurl=http://mirror.centos.org|baseurl=http://vault.centos.org|g' /etc/yum.repos.d/CentOS-*
    sed -i '/failovermethod/d' /etc/yum.repos.d/CentOS-epel.repo 2>/dev/null
fi

# 2. 安装依赖
if [ "$OS" == "debian" ]; then
    $PM update -y
    $PM install -y dante-server
else
    # CentOS 需要先安装 EPEL 源
    $PM install -y epel-release
    if [ "$CENTOS_VER" == "8" ]; then
        # 再次修复 EPEL 产生的错误
        sed -i 's/mirrorlist/#mirrorlist/g' /etc/yum.repos.d/epel*
        sed -i 's|#baseurl=https://download.fedoraproject.org/pub/epel|baseurl=https://archives.fedoraproject.org/pub/archive/epel|g' /etc/yum.repos.d/epel*
    fi
    $PM clean all && $PM makecache
    $PM install -y dante-server
fi

# 3. 获取网卡名称 (自动获取出口网卡)
NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
if [ -z "$NIC" ]; then
    NIC=$(ip add | grep "state UP" | awk -F': ' '{print $2}' | head -n 1)
fi

echo "检测到网卡: $NIC"

# 4. 写入配置文件 (根据系统选择 $CONF 路径)
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
    # connect 为 TCP, udpassociate 为 UDP
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF

# 5. 创建代理用户 (如果已存在则更新密码)
if id "$USER" &>/dev/null; then
    echo "$USER:$PASS" | chpasswd
else
    useradd -r -s /bin/false $USER
    echo "$USER:$PASS" | chpasswd
fi

# 6. 配置防火墙
echo "正在配置防火墙开放 $PORT 端口 (TCP/UDP)..."
if command -v ufw > /dev/null; then
    ufw allow $PORT/tcp
    ufw allow $PORT/udp
elif command -v firewall-cmd > /dev/null; then
    # 检查 firewalld 是否在运行，在运行才执行
    if systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port=$PORT/tcp
        firewall-cmd --permanent --add-port=$PORT/udp
        firewall-cmd --reload
    fi
fi

# 7. 启动服务
systemctl daemon-reload
systemctl stop $SERVICE 2>/dev/null
systemctl enable $SERVICE
systemctl start $SERVICE

# 8. 检查启动状态
if systemctl is-active --quiet $SERVICE; then
    IP=$(curl -s ifconfig.me)
    # 如果 curl 获取 IP 失败，尝试第二个源
    [ -z "$IP" ] && IP=$(curl -s api.ipify.org)
    
    echo "------------------------------------------------"
    echo "SOCKS5 安装成功！"
    echo "系统服务: $SERVICE"
    echo "配置文件: $CONF"
    echo "服务器地址: $IP"
    echo "端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "TCP/UDP: 已全部开启"
    echo "测试链接: socks5://$USER:$PASS@$IP:$PORT"
    echo "------------------------------------------------"
else
    echo "安装可能失败，请运行 'systemctl status $SERVICE' 检查原因。"
    # 输出最后几行日志辅助排查
    journalctl -u $SERVICE --no-pager | tail -n 10
fi
