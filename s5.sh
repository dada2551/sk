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

# 2. 针对 CentOS 8 的仓库彻底重写
if [ "$OS" == "centos" ] && [ "$CENTOS_VER" == "8" ]; then
    echo "正在彻底修复 CentOS 8 官方源及 EPEL 源..."
    # 备份并清理旧源
    mkdir -p /etc/yum.repos.d/bak
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/bak/ 2>/dev/null
    
    # 写入阿里云 Vault 基础源
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

[extras]
name=CentOS-8-Vault-Extras
baseurl=https://mirrors.aliyun.com/centos-vault/8.5.2111/extras/x86_64/os/
gpgcheck=0
enabled=1
EOF

    # 写入阿里云 EPEL 源 (dante-server 在这里)
    cat > /etc/yum.repos.d/epel.repo <<EOF
[epel]
name=Extra Packages for Enterprise Linux 8
baseurl=https://mirrors.aliyun.com/epel/8/Everything/x86_64/
gpgcheck=0
enabled=1
EOF

    yum clean all
    yum makecache
fi

# 3. 安装依赖
echo "正在安装 dante-server..."
if [ "$OS" == "debian" ]; then
    $PM update -y
    $PM install -y dante-server
else
    # CentOS 7 等其他版本如果没安装 EPEL 则安装
    if [ "$CENTOS_VER" != "8" ]; then
        $PM install -y epel-release
    fi
    $PM install -y dante-server
fi

# 4. 再次检查安装情况
if ! rpm -q dante-server &>/dev/null && ! dpkg -l | grep -q dante-server; then
    echo "错误: dante-server 安装失败。尝试直接下载 rpm 包安装..."
    if [ "$OS" == "centos" ]; then
        # 最后的兜底方案：直接从镜像站拉取 rpm 包
        rpm -ivh https://mirrors.aliyun.com/epel/8/Everything/x86_64/Packages/d/dante-server-1.4.2-13.el8.x86_64.rpm --nodeps
    fi
fi

# 5. 获取网卡名称
NIC=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5; exit}')
[ -z "$NIC" ] && NIC=$(ip add | grep "state UP" | awk -F': ' '{print $2}' | head -n 1)

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

# 7. 创建用户
if id "$USER" &>/dev/null; then
    echo "$USER:$PASS" | chpasswd
else
    useradd -r -s /bin/false $USER
    echo "$USER:$PASS" | chpasswd
fi

# 8. 启动服务
systemctl daemon-reload
systemctl enable $SERVICE
systemctl restart $SERVICE

# 9. 输出结果
if systemctl is-active --quiet $SERVICE; then
    IP=$(curl -s ifconfig.me)
    echo "------------------------------------------------"
    echo "SOCKS5 安装成功！"
    echo "地址: $IP:$PORT"
    echo "用户: $USER"
    echo "密码: $PASS"
    echo "------------------------------------------------"
else
    echo "服务启动失败，请检查配置或端口是否被占用。"
fi
