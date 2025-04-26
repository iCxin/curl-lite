# Curl Lite

一个轻量级的短链接生成服务，支持自定义短链接和链接管理功能。

## 功能特点

- 生成短链接
- 自定义短链接
- 链接管理（编辑、删除）
- 回收站功能
- Token 认证
- 每日使用限制
- 过期时间设置
- 二维码生成

## 项目结构

```
curl_lite/
├── app.py              # 主应用程序
├── config.py           # 配置文件
├── gunicorn.conf.py    # Gunicorn配置
├── requirements.txt    # 项目依赖
└── templates/          # 模板目录
    ├── index.html     # 主页
    ├── manage.html    # 管理页面
    ├── login.html     # 登录页面
    └── error.html     # 错误页面
```

## 部署说明

### 环境要求

- Python 3.x
- MySQL 5.7+
- Redis 6.0+

### 基本部署步骤

1. **克隆项目**
```bash
git clone https://github.com/iCxin/curl-lite.git
cd curl-lite
```

2. **修改配置文件**
编辑 `config.py` 文件：
```python
# Flask配置
SECRET_KEY = 'your_secret_key'  # 修改为随机字符串

# 数据库配置
SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://username:password@localhost:3306/dbname'

# Redis配置
REDIS_URL = 'redis://:password@localhost:6379/0'

# Token配置
VALID_TOKENS = {
    'admin_token': {  # 修改为自己的管理员token
        'name': '管理员',
        'daily_limit': None,
        'expires_at': None
    },
    'user_token': {   # 修改为自己的用户token
        'name': '普通用户',
        'daily_limit': 100,
        'expires_at': datetime.now() + timedelta(days=365)
    }
}
```

3. **配置Web服务**
- 配置反向代理（Nginx/Apache）指向 `127.0.0.1:8000`
- 使用 `gunicorn` 启动应用：
```bash
gunicorn -c gunicorn.conf.py app:app
```

## 使用说明

### 功能介绍

1. **创建短链接**
   - 支持自定义短码
   - 支持设置过期时间
   - 支持生成二维码
   - 支持添加备注说明

2. **链接管理**
   - 编辑原始链接
   - 修改过期时间
   - 添加/编辑备注
   - 删除链接（自动进入回收站）

3. **回收站功能**
   - 查看已删除链接
   - 查看删除原因（手动/过期）
   - 清空回收站

### API 接口

1. **创建短链接**
```
POST /api/shorten
Header: X-API-Token: your_token
Body: {
    "url": "原始链接",
    "custom_code": "自定义短码（可选）",
    "expires_at": "过期时间（可选）",
    "note": "备注（可选）"
}
```

### 访问限制

- 管理员token无使用限制
- 普通用户token默认每日限制100次
- 未认证用户每日限制50次

## 安全建议

1. 修改默认的 `SECRET_KEY`
2. 使用强密码的 token
3. 配置 SSL 证书
4. 定期更新依赖包
5. 根据需要调整访问限制

## 许可证

MIT License
 
