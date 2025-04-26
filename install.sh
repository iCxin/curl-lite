#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 版本信息
VERSION="1.0.0"

# 打印带颜色的信息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 主安装流程
main() {
    clear
    echo -e "${BLUE}"
    cat << "EOF"
   ______          __    __    _ __     
  / ____/_ _______/ /   / /   (_) /____
 / /   / // / ___/ /   / /   / / __/ _ \
/ /___/ // / /  / /___/ /___/ / /_/  __/
\____/\_,_/_/  /_____/_____/_/\__/\___/ 
                                        
EOF
    echo -e "${NC}"
    echo -e "${GREEN}Version: ${VERSION}${NC}"
    echo "======================================"
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 配置信息
    print_step "收集配置信息..."
    read -p "请输入域名: " DOMAIN
    while [[ ! $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; do
        print_error "无效的域名格式"
        read -p "请重新输入域名: " DOMAIN
    done
    
    # 数据库配置
    print_step "配置远程数据库连接..."
    read -p "请输入MySQL主机地址: " MYSQL_HOST
    read -p "请输入MySQL端口 (默认3306): " MYSQL_PORT
    MYSQL_PORT=${MYSQL_PORT:-3306}
    read -p "请输入MySQL用户名: " MYSQL_USER
    read -s -p "请输入MySQL密码: " MYSQL_PASS
    echo
    read -p "请输入数据库名 (默认curl_lite): " MYSQL_DB
    MYSQL_DB=${MYSQL_DB:-curl_lite}
    
    # Redis配置
    print_step "配置远程Redis连接..."
    read -p "请输入Redis主机地址: " REDIS_HOST
    read -p "请输入Redis端口 (默认6379): " REDIS_PORT
    REDIS_PORT=${REDIS_PORT:-6379}
    read -s -p "请输入Redis密码: " REDIS_PASS
    echo
    read -p "请输入Redis数据库编号 (默认0): " REDIS_DB
    REDIS_DB=${REDIS_DB:-0}
    
    read -p "请输入管理员Token (留空将自动生成): " ADMIN_TOKEN
    read -p "请输入普通用户Token (留空将自动生成): " USER_TOKEN
    
    # 生成Token
    if [ -z "$ADMIN_TOKEN" ]; then
        ADMIN_TOKEN=$(openssl rand -hex 16)
        print_info "生成的管理员Token: $ADMIN_TOKEN"
    fi
    
    if [ -z "$USER_TOKEN" ]; then
        USER_TOKEN=$(openssl rand -hex 16)
        print_info "生成的普通用户Token: $USER_TOKEN"
    fi
    
    # 生成Secret Key
    SECRET_KEY=$(openssl rand -hex 32)
    
    # 创建安装目录
    INSTALL_DIR="/www/wwwroot/curl_lite"
    print_step "准备安装目录..."
    if [ -d "$INSTALL_DIR" ]; then
        local backup_dir="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        mv "$INSTALL_DIR" "$backup_dir"
        print_info "已备份到: $backup_dir"
    fi
    mkdir -p $INSTALL_DIR
    
    # 克隆代码
    print_step "克隆项目代码..."
    if ! git clone https://github.com/iCxin/curl-lite.git $INSTALL_DIR; then
        print_error "克隆代码失败"
        exit 1
    fi
    cd $INSTALL_DIR
    
    # 更新配置文件
    print_step "更新配置文件..."
    cat > config.py << EOL
import os
from datetime import datetime, timedelta

# Flask配置
SECRET_KEY = '${SECRET_KEY}'

# 数据库配置
SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${MYSQL_PORT}/${MYSQL_DB}'
SQLALCHEMY_TRACK_MODIFICATIONS = False

# Redis配置
REDIS_URL = 'redis://:${REDIS_PASS}@${REDIS_HOST}:${REDIS_PORT}/${REDIS_DB}'

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
    print_step "配置Nginx..."
    cat > /www/server/panel/vhost/nginx/${DOMAIN}.conf << EOL
server {
    listen 80;
    server_name ${DOMAIN};
    
    # 安全相关头部
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    
    access_log /www/wwwlogs/curl_lite_access.log;
    error_log /www/wwwlogs/curl_lite_error.log;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # 安全设置
        proxy_hide_header X-Powered-By;
        proxy_hide_header Server;
    }

    location /static {
        alias ${INSTALL_DIR}/static;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }
    
    # 禁止访问敏感文件
    location ~ \.(git|sql|conf|md|sh|log)$ {
        deny all;
        return 404;
    }
}
EOL

    # 创建日志目录
    print_step "创建日志目录..."
    mkdir -p /www/wwwlogs
    touch /www/wwwlogs/curl_lite_access.log
    touch /www/wwwlogs/curl_lite_error.log
    chmod 666 /www/wwwlogs/curl_lite_*.log

    # 创建systemd服务
    print_step "创建系统服务..."
    cat > /etc/systemd/system/curl_lite.service << EOL
[Unit]
Description=Curl Lite URL Shortener
After=network.target

[Service]
User=www
Group=www
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 -m gunicorn -c ${INSTALL_DIR}/gunicorn.conf.py app:app
Restart=always
RestartSec=5
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
EOL

    # 设置权限
    print_step "设置文件权限..."
    chown -R www:www $INSTALL_DIR
    chmod -R 755 $INSTALL_DIR

    # 启动服务
    print_step "启动服务..."
    systemctl daemon-reload
    systemctl enable curl_lite
    systemctl start curl_lite
    systemctl restart nginx

    # 完成安装
    print_info "安装完成！"
    echo "============================================"
    echo "管理员Token: ${ADMIN_TOKEN}"
    echo "用户Token: ${USER_TOKEN}"
    echo "网站地址: http://${DOMAIN}"
    echo "============================================"
    echo "请保存好以上信息！"

    # SSL配置提示
    print_warn "强烈建议配置SSL证书以确保安全性"
    read -p "是否现在配置SSL证书？[Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        if certbot --nginx -d ${DOMAIN}; then
            print_info "SSL证书配置成功！"
            echo "网站地址: https://${DOMAIN}"
        else
            print_error "SSL证书配置失败，请稍后手动配置"
            echo "手动配置命令: certbot --nginx -d ${DOMAIN}"
        fi
    fi
}

# 捕获错误
set -e
trap 'print_error "安装过程中出现错误，请检查日志"; exit 1' ERR

# 运行主程序
main 