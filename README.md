# Curl Lite 短链接生成服务

Curl Lite 是一个轻量级的短链接生成服务，帮助用户将长URL转换为简短、易于分享的链接。本项目采用Python Flask框架开发，具有部署简单、性能优秀的特点。

## ✨ 功能特点

- 🔗 长链接转短链接
- 🎯 自定义短链接（可选）
- 📊 访问统计和分析
- 🔄 短链接自动过期机制
- 🗑️ 回收站功能
- 👥 多用户支持
- 🔒 API访问控制
- 📱 响应式界面设计
- 🚀 一键部署支持

## 🛠️ 技术栈

- **后端**: Python 3.x + Flask
- **数据库**: MySQL 8.0+
- **缓存**: Redis
- **Web服务器**: Nginx
- **WSGI服务器**: Gunicorn
- **前端**: Bootstrap 5 + jQuery

## 📦 环境要求

- Python 3.8+
- MySQL 8.0+
- Redis 6.0+
- Nginx 1.18+

## 🚀 快速开始

### 一键部署（推荐）

```bash
# 1. 下载安装脚本
wget https://raw.githubusercontent.com/iCxin/curl-lite/main/install.sh

# 2. 添加执行权限
chmod +x install.sh

# 3. 运行安装脚本
sudo ./install.sh
```

### 卸载说明

如果您需要卸载 Curl Lite，可以使用以下命令：

```bash
# 1. 停止并禁用服务
sudo systemctl stop curl_lite
sudo systemctl disable curl_lite

# 2. 删除服务文件
sudo rm /etc/systemd/system/curl_lite.service
sudo systemctl daemon-reload

# 3. 删除网站文件
sudo rm -rf /www/wwwroot/curl_lite

# 4. 删除Nginx配置（替换为您的域名）
sudo rm /www/server/panel/vhost/nginx/your_domain.conf
sudo nginx -s reload

# 5. 删除日志文件
sudo rm /www/wwwlogs/curl_lite_*.log

# 6. 删除数据库（请谨慎操作）
mysql -u root -p -e "DROP DATABASE curl_lite;"

# 7. 清理Redis缓存（可选）
redis-cli
> FLUSHDB
> exit

# 8. 删除安装脚本
rm -f install.sh
```

> 注意：执行删除操作前请确保已备份重要数据！

安装过程中需要提供以下信息：
- 域名（必填）：您的网站域名，如 `short.example.com`
- MySQL用户名和密码（必填）：用于创建和访问数据库
- Redis密码（必填）：用于缓存服务
- 管理员Token（可选）：留空将自动生成
- 普通用户Token（可选）：留空将自动生成

脚本将自动完成以下任务：
- ✅ 克隆最新代码
- ✅ 创建并配置Python虚拟环境
- ✅ 安装所需依赖
- ✅ 配置MySQL数据库
- ✅ 配置Redis缓存
- ✅ 设置Nginx服务器
- ✅ 配置SSL证书（可选）
- ✅ 创建系统服务
- ✅ 启动应用程序

安装完成后，您将看到以下信息：
- 网站访问地址
- 管理员Token
- 普通用户Token
- SSL证书配置说明

> 注意：请务必保存好生成的Token信息！

### 手动部署

1. **安装依赖**
```bash
pip install -r requirements.txt
```

2. **配置数据库**
```bash
# 创建数据库
mysql -u root -p
CREATE DATABASE curl_lite CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

3. **修改配置**
```bash
cp config.example.py config.py
# 编辑 config.py 文件，填写数据库等配置信息
```

4. **初始化数据库**
```bash
python manage.py init_db
```

5. **启动服务**
```bash
python app.py
```

## 📝 配置说明

### 数据库配置
```python
MYSQL_HOST = 'localhost'
MYSQL_PORT = 3306
MYSQL_USER = 'your_username'
MYSQL_PASSWORD = 'your_password'
MYSQL_DATABASE = 'curl_lite'
```

### Redis配置
```python
REDIS_HOST = 'localhost'
REDIS_PORT = 6379
REDIS_PASSWORD = 'your_password'
```

### 应用配置
```python
# 短链接长度
SHORT_URL_LENGTH = 6

# 链接过期时间（天）
LINK_EXPIRE_DAYS = 365

# API访问限制（次/分钟）
API_RATE_LIMIT = 60
```

## 🔒 安全配置

1. **防火墙设置**
```bash
# 只开放必要端口
ufw allow 80
ufw allow 443
ufw allow 22
```

2. **SSL证书配置**
```bash
# 使用certbot申请证书
certbot --nginx -d yourdomain.com
```

## 📈 性能优化

1. **Nginx配置优化**
```nginx
# 开启gzip压缩
gzip on;
gzip_types text/plain text/css application/json application/javascript;

# 设置缓存
location /static/ {
    expires 30d;
    add_header Cache-Control "public, no-transform";
}
```

2. **Gunicorn配置优化**
```python
# gunicorn.conf.py
workers = 4
worker_class = 'gevent'
worker_connections = 1000
```

## 🔍 监控和日志

### 日志位置
- 应用日志: `/var/log/curl-lite/app.log`
- 访问日志: `/var/log/curl-lite/access.log`
- 错误日志: `/var/log/curl-lite/error.log`

### 监控指标
- CPU使用率
- 内存使用
- 响应时间
- 请求成功率
- 并发连接数

## 🛡️ 备份策略

1. **数据库备份**
```bash
# 每日自动备份
0 2 * * * /usr/bin/mysqldump -u root -p curl_lite > /backup/curl_lite_$(date +\%Y\%m\%d).sql
```

2. **配置文件备份**
```bash
# 定期备份配置
0 3 * * * tar -czf /backup/config_$(date +\%Y\%m\%d).tar.gz /etc/curl-lite/
```

## 📚 API文档

### 创建短链接
```http
POST /api/v1/shorten
Content-Type: application/json

{
    "url": "https://example.com/very/long/url",
    "custom_alias": "mylink",  // 可选
    "expire_days": 30  // 可选
}
```

### 获取链接信息
```http
GET /api/v1/links/{short_code}
```

## 🤝 贡献指南

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 提交 Pull Request

## 📄 开源协议

本项目采用 MIT 协议开源 - 查看 [LICENSE](LICENSE) 文件了解更多细节

## 👥 联系方式

- 项目作者：iCxin
- 邮箱：[cxin@cin.xin]
- 项目主页：[https://github.com/iCxin/curl-lite]

## 🙏 致谢

感谢所有为这个项目做出贡献的开发者！（虽然目前只有我和我的ai们嘻嘻）
 
