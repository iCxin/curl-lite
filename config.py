import os
from datetime import datetime, timedelta

# Flask配置
SECRET_KEY = 'your-secret-key-here'  # 请更改为随机字符串

# 数据库配置
SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://username:password@localhost/curl_lite'
SQLALCHEMY_TRACK_MODIFICATIONS = False

# Redis配置
REDIS_URL = 'redis://:password@localhost:6379/0'  # 根据实际Redis配置修改

# Token配置
VALID_TOKENS = {
    'admin_token': {
        'name': '管理员',
        'daily_limit': None,  # None表示无限制
        'expires_at': None    # None表示永不过期
    },
    'user_token': {
        'name': '普通用户',
        'daily_limit': 100,   # 每日可创建100个短链接
        'expires_at': datetime.now() + timedelta(days=365)  # 一年后过期
    }
}

# 默认每日使用限制
DEFAULT_DAILY_LIMIT = 50

# 请求限制配置
RATE_LIMIT_WINDOW = timedelta(days=1)  # 限制窗口 