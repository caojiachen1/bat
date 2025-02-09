#!/bin/bash
set -e

# 检测root权限
if [ "$EUID" -ne 0 ]; then
  echo "请使用sudo或root用户运行此脚本"
  exit 1
fi

# 函数：检查端口占用
check_port() {
  local port=$1
  if ss -lnt | grep -q ":$port "; then
    echo "错误：端口 $port 已被占用！"
    echo "以下进程正在使用该端口："
    lsof -i :$port || true
    return 1
  fi
  return 0
}

# 获取有效端口输入
while true; do
  read -p "请输入WebDAV端口（默认1000）: " PORT
  PORT=${PORT:-1000}
  
  # 验证端口格式
  if [[ ! $PORT =~ ^[0-9]+$ ]] || [ $PORT -lt 1 ] || [ $PORT -gt 65535 ]; then
    echo "错误：端口号必须是1-65535之间的数字"
    continue
  fi
  
  # 检查端口占用
  if check_port $PORT; then
    break
  else
    read -p "是否强制使用该端口？(y/N) " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]] && break || continue
  fi
done

# 检测APT锁（Debian/Ubuntu）
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
  echo "等待其他软件安装完成..."
  sleep 5
done

# 安装依赖（增加端口检查工具）
if [ -f /etc/redhat-release ]; then
  yum install -y httpd httpd-tools policycoreutils-python-utils lsof
elif [ -f /etc/debian_version ]; then
  apt update && apt install -y apache2 apache2-utils lsof
else
  echo "不支持的Linux发行版"
  exit 1
fi

# 配置WebDAV目录
DATA_DIR="/var/www/webdav-$PORT"  # 使用端口号区分不同实例
mkdir -p $DATA_DIR
chown -R www-data:www-data $DATA_DIR  # Debian/Ubuntu
chmod 775 $DATA_DIR

# 设置认证信息
read -p "输入WebDAV用户名: " USERNAME
PASSWD_FILE="/etc/apache2/webdav_${PORT}_passwd"  # Debian路径
[ -f /etc/redhat-release ] && PASSWD_FILE="/etc/httpd/webdav_${PORT}_passwd"  # CentOS路径

htpasswd -c $PASSWD_FILE $USERNAME

# 生成配置文件
if [ -f /etc/redhat-release ]; then
  CONF_FILE="/etc/httpd/conf.d/webdav_$PORT.conf"
  # 配置端口监听
  grep -q "^Listen $PORT" /etc/httpd/conf/httpd.conf || echo "Listen $PORT" >> /etc/httpd/conf/httpd.conf
else
  CONF_FILE="/etc/apache2/sites-available/webdav_$PORT.conf"
  # 配置端口监听
  grep -q "^Listen $PORT" /etc/apache2/ports.conf || echo "Listen $PORT" >> /etc/apache2/ports.conf
fi

cat > $CONF_FILE <<EOF
DavLockDB \${APACHE_LOCK_DIR}/DavLock_$PORT
<VirtualHost *:$PORT>
    DocumentRoot $DATA_DIR
    <Directory "$DATA_DIR">
        DAV On
        AuthType Basic
        AuthName "WebDAV Port $PORT"
        AuthUserFile $PASSWD_FILE
        Require valid-user
        Options Indexes
    </Directory>
</VirtualHost>
EOF

# 系统配置
if [ -f /etc/redhat-release ]; then
  systemctl restart httpd
  systemctl enable httpd
  firewall-cmd --permanent --add-port=$PORT/tcp
  firewall-cmd --reload
  # SELinux端口授权
  if semanage port -l | grep -wq "http_port_t.*tcp.*$PORT"; then
    echo "SELinux端口规则已存在"
  else
    semanage port -a -t http_port_t -p tcp $PORT
  fi
else
  a2enmod dav dav_fs
  a2ensite webdav_$PORT.conf
  ufw allow $PORT/tcp
  systemctl restart apache2
fi

# SELinux目录权限（CentOS）
if [ -x "$(command -v setsebool)" ]; then
  setsebool -P httpd_use_davfs 1
  chcon -R -t httpd_sys_rw_content_t $DATA_DIR
fi

echo -e "\n\033[32m配置完成！\033[0m"
echo "访问地址：http://$(hostname -I | awk '{print $1}'):$PORT/"
echo "测试命令：curl -u $USERNAME http://localhost:$PORT/"
