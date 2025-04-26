#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# 打印带颜色的信息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    print_error "请使用root权限运行此脚本"
    exit 1
fi

# 配置信息
read -p "请输入域名: " DOMAIN
read -p "请输入MySQL用户名: " MYSQL_USER
read -s -p "请输入MySQL密码: " MYSQL_PASS
echo
read -s -p "请输入Redis密码: " REDIS_PASS
echo
read -p "请输入管理员Token (留空将自动生成): " ADMIN_TOKEN
read -p "请输入普通用户Token (留空将自动生成): " USER_TOKEN

# 如果token为空，生成随机token
if [ -z "$ADMIN_TOKEN" ]; then
    ADMIN_TOKEN=$(openssl rand -hex 16)
    print_info "生成的管理员Token: $ADMIN_TOKEN"
fi

if [ -z "$USER_TOKEN" ]; then
    USER_TOKEN=$(openssl rand -hex 16)
    print_info "生成的普通用户Token: $USER_TOKEN"
fi

# 生成随机的Secret Key
SECRET_KEY=$(openssl rand -hex 32)

# 创建工作目录
INSTALL_DIR="/www/wwwroot/curl_lite"
print_info "创建工作目录..."
mkdir -p $INSTALL_DIR
cd $INSTALL_DIR

# 创建Python虚拟环境
print_info "创建Python虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 安装依赖
print_info "安装Python依赖..."
pip install -r requirements.txt

# 更新配置文件
print_info "更新配置文件..."
cat > config.py << EOL
import os
from datetime import datetime, timedelta

# Flask配置
SECRET_KEY = '${SECRET_KEY}'

# 数据库配置
SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://${MYSQL_USER}:${MYSQL_PASS}@localhost/curl_lite'
SQLALCHEMY_TRACK_MODIFICATIONS = False

# Redis配置
REDIS_URL = 'redis://:${REDIS_PASS}@localhost:6379/0'

# Token配置
VALID_TOKENS = {
    '${ADMIN_TOKEN}': {
        'name': '管理员',
        'daily_limit': None,
        'expires_at': None
    },
    '${USER_TOKEN}': {
        'name': '普通用户',
        'daily_limit': 100,
        'expires_at': datetime.now() + timedelta(days=365)
    }
}

# 默认每日使用限制
DEFAULT_DAILY_LIMIT = 50

# 请求限制配置
RATE_LIMIT_WINDOW = timedelta(days=1)
EOL

# 创建Nginx配置
print_info "配置Nginx..."
cat > /www/server/panel/vhost/nginx/${DOMAIN}.conf << EOL
server {
    listen 80;
    server_name ${DOMAIN};

    access_log /www/wwwlogs/curl_lite_access.log;
    error_log /www/wwwlogs/curl_lite_error.log;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /static {
        alias ${INSTALL_DIR}/static;
        expires 30d;
    }
}
EOL

# 创建日志目录
print_info "创建日志目录..."
mkdir -p /www/wwwlogs
touch /www/wwwlogs/curl_lite_access.log
touch /www/wwwlogs/curl_lite_error.log
chmod 666 /www/wwwlogs/curl_lite_*.log

# 创建systemd服务
print_info "创建系统服务..."
cat > /etc/systemd/system/curl_lite.service << EOL
[Unit]
Description=Curl Lite URL Shortener
After=network.target

[Service]
User=www
Group=www
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/gunicorn -c ${INSTALL_DIR}/gunicorn.conf.py app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOL

# 重载systemd并启动服务
systemctl daemon-reload
systemctl enable curl_lite
systemctl start curl_lite

# 重启Nginx
print_info "重启Nginx..."
systemctl restart nginx

# 创建数据库
print_info "创建数据库..."
mysql -u${MYSQL_USER} -p${MYSQL_PASS} -e "CREATE DATABASE IF NOT EXISTS curl_lite CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"

print_info "部署完成！"
echo "============================================"
echo "管理员Token: ${ADMIN_TOKEN}"
echo "用户Token: ${USER_TOKEN}"
echo "网站地址: http://${DOMAIN}"
echo "============================================"
echo "请保存好以上信息！"

# 提示配置SSL
print_info "建议配置SSL证书以确保安全性"
echo "您可以使用以下命令安装SSL："
echo "certbot --nginx -d ${DOMAIN}" 