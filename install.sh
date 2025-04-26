#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# 版本信息
VERSION="1.0.0"
MIN_PYTHON_VERSION="3.8.0"
MIN_MYSQL_VERSION="8.0.0"
MIN_REDIS_VERSION="6.0.0"

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

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 未安装，请先安装 $1"
        exit 1
    fi
}

# 检查Python版本
check_python_version() {
    local python_version=$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
    if ! printf '%s\n%s\n' "$MIN_PYTHON_VERSION" "$python_version" | sort -V -C; then
        print_error "Python版本过低，需要 $MIN_PYTHON_VERSION 或更高版本"
        exit 1
    fi
}

# 检查MySQL版本
check_mysql_version() {
    local mysql_version=$(mysql --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    if ! printf '%s\n%s\n' "$MIN_MYSQL_VERSION" "$mysql_version" | sort -V -C; then
        print_error "MySQL版本过低，需要 $MIN_MYSQL_VERSION 或更高版本"
        exit 1
    fi
}

# 检查Redis版本
check_redis_version() {
    local redis_version=$(redis-cli --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    if ! printf '%s\n%s\n' "$MIN_REDIS_VERSION" "$redis_version" | sort -V -C; then
        print_error "Redis版本过低，需要 $MIN_REDIS_VERSION 或更高版本"
        exit 1
    fi
}

# 检查系统依赖
check_dependencies() {
    print_step "检查系统依赖..."
    
    local deps=("python3" "python3-venv" "mysql" "redis-cli" "nginx" "git" "certbot")
    for dep in "${deps[@]}"; do
        check_command $dep
    done
    
    check_python_version
    check_mysql_version
    check_redis_version
}

# 检查端口占用
check_ports() {
    print_step "检查端口占用..."
    
    local ports=(80 443 8000)
    for port in "${ports[@]}"; do
        if netstat -tuln | grep -q ":$port "; then
            print_warn "端口 $port 已被占用，请确保该端口可用"
            read -p "是否继续安装？[y/N] " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        fi
    done
}

# 备份现有安装
backup_existing() {
    if [ -d "$INSTALL_DIR" ]; then
        print_step "备份现有安装..."
        local backup_dir="${INSTALL_DIR}_backup_$(date +%Y%m%d_%H%M%S)"
        mv "$INSTALL_DIR" "$backup_dir"
        print_info "已备份到: $backup_dir"
    fi
}

# 主安装流程
main() {
    echo "======================================"
    echo "   Curl Lite 安装脚本 v${VERSION}"
    echo "======================================"
    
    # 检查root权限
    if [ "$EUID" -ne 0 ]; then
        print_error "请使用root权限运行此脚本"
        exit 1
    fi
    
    # 检查依赖
    check_dependencies
    
    # 检查端口
    check_ports
    
    # 配置信息
    print_step "收集配置信息..."
    read -p "请输入域名: " DOMAIN
    while [[ ! $DOMAIN =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; do
        print_error "无效的域名格式"
        read -p "请重新输入域名: " DOMAIN
    done
    
    read -p "请输入MySQL用户名: " MYSQL_USER
    read -s -p "请输入MySQL密码: " MYSQL_PASS
    echo
    read -s -p "请输入Redis密码: " REDIS_PASS
    echo
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
    backup_existing
    mkdir -p $INSTALL_DIR
    
    # 克隆代码
    print_step "克隆项目代码..."
    if ! git clone https://github.com/iCxin/curl-lite.git $INSTALL_DIR; then
        print_error "克隆代码失败"
        exit 1
    fi
    cd $INSTALL_DIR
    
    # 创建虚拟环境
    print_step "创建Python虚拟环境..."
    python3 -m venv venv
    source venv/bin/activate
    
    # 安装依赖
    print_step "安装Python依赖..."
    if ! pip install -r requirements.txt; then
        print_error "安装依赖失败"
        exit 1
    fi

    # 更新配置文件
    print_step "更新配置文件..."
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
After=network.target mysql.service redis.service

[Service]
User=www
Group=www
WorkingDirectory=${INSTALL_DIR}
Environment="PATH=${INSTALL_DIR}/venv/bin"
ExecStart=${INSTALL_DIR}/venv/bin/gunicorn -c ${INSTALL_DIR}/gunicorn.conf.py app:app
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
    
    # 创建数据库
    print_step "创建数据库..."
    if ! mysql -u${MYSQL_USER} -p${MYSQL_PASS} -e "CREATE DATABASE IF NOT EXISTS curl_lite CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"; then
        print_error "创建数据库失败"
        exit 1
    fi

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