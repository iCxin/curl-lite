import os
from datetime import datetime, timedelta

# Flask配置
SECRET_KEY = 'your_secret_key'  # 请修改为自己的密钥

# 数据库配置
SQLALCHEMY_DATABASE_URI = 'mysql+pymysql://username:password@localhost:3306/dbname'
SQLALCHEMY_TRACK_MODIFICATIONS = False

# Redis配置
REDIS_URL = 'redis://:password@localhost:6379/0'

# Token配置
VALID_TOKENS = {
    'admin_token': {
        'name': '管理员',
        'daily_limit': None,
        'expires_at': None
    },
    'user_token': {
        'name': '普通用户',
        'daily_limit': 100,
        'expires_at': datetime.now() + timedelta(days=365)
    }
}

# 默认每日使用限制
DEFAULT_DAILY_LIMIT = 50

# 请求限制配置
RATE_LIMIT_WINDOW = timedelta(days=1) 