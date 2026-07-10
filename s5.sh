#!/bin/bash

# 配置信息
PORT=36470
USER="proxyuser"
PASS="Aaaaqqqq@1"

# 1. 识别系统
if [ -f /etc/debian_version ]; then
    OS="debian"; PM="apt-get"; CONF="/etc/danted.conf"; SERVICE="danted"
elif [ -f /etc/redhat-release ]; then
    OS="centos"; PM="yum"; CONF="/etc/sockd.conf"; SERVICE="sockd"
    CENTOS_VER=$(cat /etc/redhat-release | sed -r 's/.* ([0-9]+)\..*/\1/')
else
    echo "不支持的系统"; exit 1
fi

echo "检测到系统: $OS $CENTOS_VER"

# 2. 针对 CentOS 8 内存不足和源失效的特殊处理
if [ "$OS" == "centos" ] && [ "$CENTOS_VER" == "8" ]; then
    echo "步骤 1: 正在创建临时虚拟内存 (防止内存不足导致 Killed)..."
    swapoff -a
    dd if=/dev/zero of=/tmp/swapfile bs=1M count=1024
    chmod 600 /tmp/swapfile
    mkswap /tmp/swapfile
    swapon /tmp/swapfile

    echo "步骤 2: 正在彻底修复 CentOS 8 官方源及 EPEL 源..."
    mkdir -p /etc/yum.repos.d/bak
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null
    
    cat > /etc/yum.repos.d/CentOS-Vault.repo <<EOF
[baseos]
name=CentOS-8-Vault-BaseOS
baseurl=https://mirrors.aliyun.com/centos-vault/8.5.2111/BaseOS/x86_64/os/
gpgcheck=0
enabled=1

[appstream]
name=CentOS-8-Vault-AppStream
baseurl=https://mirrors.aliyun.com/centos-vault/8.5.2111/AppStream/x86_64/os/
gpgcheck=0
enabled=1
EOF

    cat > /etc/yum.repos.d/epel.repo <<EOF
[epel]
name=Extra Packages for Enterprise Linux 8
baseurl=https://mirrors.aliyun.com/epel/8/Everything/x86_64/
gpgcheck=0
enabled=1
EOF
    yum clean all
    echo "正在生成缓存 (这可能需要 1-2 分钟，请稍候)..."
    yum makecache
fi

# 3. 安装依赖
echo "步骤 3: 正在安装 dante-server..."
if [ "$OS" == "debian" ]; then
    $PM update -y && $PM install -y dante-server
else
    # 非 8 版本的 CentOS 安装 epel
    if [ "$CENTOS_VER" != "8" ]; then $PM install -y epel-release; fi
    $PM install -y dante-server
fi

# 4. 获取网卡
NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[ -z "$NIC" ] && NIC=$(ip add | grep "state UP" | awk -F': ' '{print $2}' | head -n 1)

# 5. 写入配置
cat > $CONF <<EOF
logoutput: syslog
user.privileged: root
user.unprivileged: nobody
internal: 0.0.0.0 port = $PORT
external: $NIC
socksmethod: username
clientmethod: none
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    command: bind connect udpassociate
    log: error
    socksmethod: username
}
EOF

# 6. 创建用户
id "$USER" &>/dev/null || useradd -r -s /bin/false $USER
echo "$USER:$PASS" | chpasswd

# 7. 启动服务
systemctl daemon-reload
systemctl enable $SERVICE
systemctl restart $SERVICE

# 8. 清理临时交换文件 (如果是 CentOS 8)
if [ "$OS" == "centos" ] && [ "$CENTOS_VER" == "8" ]; then
    swapoff /tmp/swapfile
    rm -f /tmp/swapfile
fi

# 9. 结果展示
if systemctl is-active --quiet $SERVICE; then
    IP=$(curl -s ifconfig.me)
    echo "------------------------------------------------"
    echo "SOCKS5 安装成功！"
    echo "连接信息: $IP:$PORT"
    echo "用户名: $USER"
    echo "密码: $PASS"
    echo "------------------------------------------------"
else
    echo "安装失败，请手动运行 systemctl status $SERVICE 查看具体报错。"
fi
