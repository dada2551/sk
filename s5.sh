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

# 1. 识别系统
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
    CENTOS_VER=$(cat /etc/redhat-release | sed -r 's/.* ([0-9]+)\..*/\1/')
else
    echo "不支持的系统"
    exit 1
fi

echo "检测到系统: $OS $CENTOS_VER"

# 2. 针对 CentOS 8 的暴力修复 (解决源失效问题)
if [ "$OS" == "centos" ] && [ "$CENTOS_VER" == "8" ]; then
    echo "正在暴力修复 CentOS 8 软件源..."
    # 备份旧源
    mkdir -p /etc/yum.repos.d/bak
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null
    
    # 直接写入新的阿里云 Vault 源配置
    cat > /etc/yum.repos.d/CentOS-Stream-Vault.repo <<EOF
[baseos]
name=CentOS-Stream - BaseOS - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/8.5.2111/BaseOS/x86_64/os/
gpgcheck=0
enabled=1

[appstream]
name=CentOS-Stream - AppStream - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/8.5.2111/AppStream/x86_64/os/
gpgcheck=0
enabled=1

[extras]
name=CentOS-Stream - Extras - mirrors.aliyun.com
baseurl=https://mirrors.aliyun.com/centos-vault/8.5.2111/extras/x86_64/os/
gpgcheck=0
enabled=1
EOF
    # 清理缓存
    yum clean all
    yum makecache
fi

# 3. 安装依赖
echo "正在安装 SOCKS5 (Dante)..."
if [ "$OS" == "debian" ]; then
    $PM update -y
    $PM install -y dante-server
else
    # CentOS 安装 EPEL
    $PM install -y epel-release
    # 修复可能出现的 EPEL 报错 (failovermethod)
    sed -i '/failovermethod/d' /etc/yum.repos.d/epel*.repo 2>/dev/null
    $PM install -y dante-server
fi

# 4. 检查安装是否成功
if ! command -v sockd &> /dev/null && ! command -v danted &> /dev/null; then
    echo "错误: 软件安装失败，请检查网络或源配置。"
    exit 1
fi

# 5. 获取网卡名称
NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[ -z "$NIC" ] && NIC=$(ip add | grep "state UP" | awk -F': ' '{print $2}' | head -n 1)
echo "使用网卡: $NIC"

# 6. 写入配置文件
cat > $CONF <<EOF
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
EOF

# 7. 创建代理用户
if id "$USER" &>/dev/null; then
    echo "$USER:$PASS" | chpasswd
else
    useradd -r -s /bin/false $USER
    echo "$USER:$PASS" | chpasswd
fi

# 8. 防火墙处理
if systemctl is-active --quiet firewalld; then
    firewall-cmd --permanent --add-port=$PORT/tcp
    firewall-cmd --permanent --add-port=$PORT/udp
    firewall-cmd --reload
fi

# 9. 启动服务
systemctl daemon-reload
systemctl enable $SERVICE
systemctl restart $SERVICE

# 10. 最终检查
if systemctl is-active --quiet $SERVICE; then
    IP=$(curl -s ifconfig.me)
    echo "------------------------------------------------"
    echo "SOCKS5 安装成功！"
    echo "服务器地址: $IP"
    echo "端口: $PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "测试命令: curl -v --proxy-user \"$USER:$PASS\" --socks5-hostname $IP:$PORT https://www.google.com"
    echo "------------------------------------------------"
else
    echo "安装失败，尝试查看日志: journalctl -u $SERVICE -n 20"
fi
