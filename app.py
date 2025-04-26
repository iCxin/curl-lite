from flask import Flask, render_template, request, redirect, url_for, flash, session
from flask_sqlalchemy import SQLAlchemy
import string
import random
import pymysql
from urllib.parse import urlparse, urlunparse
from datetime import datetime, timedelta
import logging
import re
import traceback
from functools import wraps
import redis
from config import *

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

pymysql.install_as_MySQLdb()

app = Flask(__name__)
app.config.from_object('config')

# 初始化数据库
db = SQLAlchemy(app)

# 初始化Redis连接池
redis_pool = redis.ConnectionPool.from_url(
    app.config['REDIS_URL'],
    max_connections=10,
    socket_timeout=2,
    socket_connect_timeout=2,
    retry_on_timeout=False
)
redis_client = redis.Redis(connection_pool=redis_pool)

class URL(db.Model):
    __tablename__ = 'url'
    id = db.Column(db.Integer, primary_key=True)
    original_url = db.Column(db.String(500), nullable=False)
    short_code = db.Column(db.String(20), unique=True, nullable=False)  # 增加长度以适应自定义后缀
    created_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    expires_at = db.Column(db.DateTime, nullable=True)
    note = db.Column(db.String(200), nullable=True)  # 添加备注字段
    
    @property
    def is_expired(self):
        if self.expires_at is None:
            return False
        return datetime.utcnow() > self.expires_at

class RecycleBin(db.Model):
    __tablename__ = 'recycle_bin'
    id = db.Column(db.Integer, primary_key=True)
    original_url = db.Column(db.String(500), nullable=False)
    short_code = db.Column(db.String(20), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False)
    expired_at = db.Column(db.DateTime, nullable=True)
    deleted_at = db.Column(db.DateTime, nullable=False, default=datetime.utcnow)
    note = db.Column(db.String(200), nullable=True)
    delete_type = db.Column(db.String(20), nullable=False)  # 'expired' 或 'manual'

def check_and_create_table():
    """检查并创建数据库表"""
    try:
        # 尝试连接数据库
        db.session.execute('SELECT 1')
        logger.info("数据库连接成功")
        
        # 检查表是否存在
        inspector = db.inspect(db.engine)
        existing_tables = inspector.get_table_names()
        
        if 'url' not in existing_tables or 'recycle_bin' not in existing_tables:
            # 只有在表不存在时才创建
            db.create_all()
            logger.info("数据库表创建成功")
        else:
            logger.info("数据库表已存在，无需创建")
        
    except Exception as e:
        logger.error(f"数据库操作错误: {str(e)}")
        logger.error(f"错误详情: {traceback.format_exc()}")

def normalize_url(url):
    """验证URL格式"""
    if not url:
        return None
        
    try:
        parsed = urlparse(url)
        # 确保有协议和域名
        if not parsed.scheme or not parsed.netloc:
            return None
        return urlunparse(parsed)
    except Exception as e:
        logger.error(f"URL验证错误: {str(e)}")
        return None

def is_valid_url(url):
    """验证URL是否合法"""
    try:
        result = urlparse(url)
        return all([result.scheme, result.netloc])
    except Exception as e:
        logger.error(f"URL验证错误: {str(e)}")
        return False

def is_valid_custom_code(code):
    """验证自定义后缀是否合法"""
    # 只允许字母、数字和下划线，不限制长度
    pattern = re.compile(r'^[a-zA-Z0-9_]+$')
    return bool(pattern.match(code))

def generate_short_code(custom_code=None):
    """生成短链接代码，支持自定义后缀"""
    if custom_code:
        # 验证自定义后缀是否合法
        if not is_valid_custom_code(custom_code):
            raise ValueError("自定义后缀只能包含字母、数字和下划线")
        # 检查自定义后缀是否已存在
        if URL.query.filter_by(short_code=custom_code).first():
            raise ValueError("该自定义后缀已被使用")
        return custom_code
        
    # 如果没有自定义后缀，生成随机代码
    characters = string.ascii_letters + string.digits
    max_attempts = 10  # 最大尝试次数
    for _ in range(max_attempts):
        short_code = ''.join(random.choice(characters) for _ in range(6))
        if not URL.query.filter_by(short_code=short_code).first():
            return short_code
    raise Exception("无法生成唯一的短链接代码，请稍后重试")

def parse_expiry_date(expiry_date_str):
    """解析过期日期字符串"""
    if not expiry_date_str:
        return None
    try:
        # 解析前端发送的 Y/m/d H:i 格式的日期
        expires_at = datetime.strptime(expiry_date_str, '%Y/%m/%d %H:%M')
        return expires_at
    except ValueError as e:
        logger.error(f"无效的日期格式: {expiry_date_str}")
        logger.error(f"日期解析错误: {str(e)}")
        raise  # 向上层抛出异常

def check_token(token):
    """验证token是否有效"""
    if token not in app.config['VALID_TOKENS']:
        return False, "无效的Token"
    
    token_info = app.config['VALID_TOKENS'][token]
    
    # 检查token是否过期
    if token_info.get('expires_at'):
        if datetime.now() > token_info['expires_at']:
            return False, "Token已过期"
    
    return True, token_info

def get_daily_usage(token):
    """获取token的当日使用次数"""
    try:
        today = datetime.now().strftime('%Y-%m-%d')
        key = f"token_usage:{token}:{today}"
        usage = redis_client.get(key)
        return int(usage) if usage else 0
    except redis.RedisError as e:
        logger.error(f"Redis错误: {str(e)}")
        return 0  # 发生错误时返回0，允许继续使用

def increment_usage(token):
    """增加token的使用次数"""
    try:
        today = datetime.now().strftime('%Y-%m-%d')
        key = f"token_usage:{token}:{today}"
        pipe = redis_client.pipeline()
        pipe.incr(key)
        pipe.expire(key, 86400)  # 24小时后过期
        result = pipe.execute()
        return result[0]  # 返回当前使用次数
    except redis.RedisError as e:
        logger.error(f"Redis错误: {str(e)}")
        return 0  # 发生错误时返回0，允许继续使用

def token_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        token = session.get('token')
        
        if not token:
            return render_template('error.html',
                                 error_message='请先输入有效的Token',
                                 error_code='401')
        
        valid, token_info = check_token(token)
        if not valid:
            session.pop('token', None)
            return render_template('error.html',
                                 error_message=token_info,
                                 error_code='401')
        
        # 如果是管理员token（daily_limit为None），则不检查使用次数
        if token_info.get('daily_limit') is not None:
            # 检查使用次数限制
            daily_usage = get_daily_usage(token)
            if daily_usage >= token_info.get('daily_limit', app.config['DEFAULT_DAILY_LIMIT']):
                return render_template('error.html',
                                     error_message='已达到今日使用次数限制',
                                     error_code='429')
        
        return f(*args, **kwargs)
    return decorated_function

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        token = request.form.get('token', '').strip()
        valid, token_info = check_token(token)
        
        if valid:
            session['token'] = token
            session['user_name'] = token_info['name']
            flash(f'欢迎回来，{token_info["name"]}')
            return redirect(url_for('index'))
        else:
            return render_template('error.html',
                                 error_message=token_info,
                                 error_code='401')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    return redirect(url_for('login'))

@app.route('/', methods=['GET', 'POST'])
def index():
    # 检查是否已登录
    if 'token' not in session:
        return redirect(url_for('login'))
        
    # 检查token是否有效
    token = session.get('token')
    valid, token_info = check_token(token)
    if not valid:
        session.clear()
        return redirect(url_for('login'))
    
    if request.method == 'POST':
        try:
            original_url = request.form['url'].strip()
            if not original_url:
                flash('请输入URL地址')
                return render_template('index.html')

            custom_code = request.form.get('custom_code', '').strip()
            expiry_date_str = request.form.get('expiry_date', '').strip()
            
            # 规范化URL
            normalized_url = normalize_url(original_url)
            if not normalized_url:
                flash('请输入有效的URL地址，确保包含正确的域名')
                return render_template('index.html')
            
            try:
                # 尝试连接数据库
                db.session.execute('SELECT 1')
                logger.info("数据库连接正常")
            except Exception as e:
                logger.error(f"数据库连接错误: {str(e)}")
                logger.error(f"错误详情: {traceback.format_exc()}")
                flash('数据库连接失败，请稍后重试')
                return render_template('index.html')
                
            try:
                # 生成短链接代码
                try:
                    short_code = generate_short_code(custom_code if custom_code else None)
                    logger.info(f"生成短链接代码: {short_code}")
                except ValueError as e:
                    flash(str(e))
                    return render_template('index.html')
                    
                # 解析过期时间
                try:
                    expires_at = parse_expiry_date(expiry_date_str)
                    logger.info(f"接收到的过期时间字符串: {expiry_date_str}")
                    logger.info(f"解析后的过期时间: {expires_at}")
                except ValueError as e:
                    flash(str(e))
                    return render_template('index.html')
                
                # 增加token使用次数
                token = session.get('token')
                current_usage = increment_usage(token)
                logger.info(f"Token {token} 当前使用次数: {current_usage}")
                
                new_url = URL(
                    original_url=normalized_url, 
                    short_code=short_code,
                    expires_at=expires_at
                )
                db.session.add(new_url)
                db.session.commit()
                logger.info(f"成功保存URL: {normalized_url} -> {short_code}")
                
                # 格式化过期时间显示
                formatted_expires_at = None
                if expires_at:
                    formatted_expires_at = expires_at.strftime('%Y/%m/%d %H:%M')
                    logger.info(f"格式化后的过期时间显示: {formatted_expires_at}")
                
                return render_template('index.html', 
                                     short_url=request.host_url + short_code,
                                     expires_at=expires_at,
                                     formatted_expires_at=formatted_expires_at,
                                     show_refresh=True)
            except Exception as e:
                db.session.rollback()
                logger.error(f"保存URL时发生错误: {str(e)}")
                logger.error(f"错误详情: {traceback.format_exc()}")
                if 'Duplicate entry' in str(e):
                    flash('生成的短链接已存在，请重试')
                else:
                    flash('保存链接时发生错误，请稍后重试')
                return render_template('index.html')
                
        except Exception as e:
            logger.error(f"处理请求时发生错误: {str(e)}")
            logger.error(f"错误详情: {traceback.format_exc()}")
            flash('处理请求时发生错误，请稍后重试')
            return render_template('index.html')
            
    return render_template('index.html')

@app.route('/refresh', methods=['POST'])
def refresh():
    """刷新页面，清除表单数据"""
    return redirect(url_for('index'))

@app.route('/<short_code>')
def redirect_to_url(short_code):
    try:
        url = URL.query.filter_by(short_code=short_code).first()
        if not url:
            return render_template('error.html', 
                                 error_message='您访问的链接不存在',
                                 error_code='404')
            
        # 检查是否过期
        now = datetime.now()
        if url.expires_at and now >= url.expires_at:
            # 移动到回收站
            recycled = RecycleBin(
                original_url=url.original_url,
                short_code=url.short_code,
                created_at=url.created_at,
                expired_at=url.expires_at,
                note=url.note,
                delete_type='expired'
            )
            db.session.add(recycled)
            
            # 删除原链接
            db.session.delete(url)
            db.session.commit()
            
            return render_template('error.html', 
                                 error_message='此链接已过期',
                                 error_code='410')
            
        return redirect(url.original_url)
    except Exception as e:
        logger.error(f"重定向时发生错误: {str(e)}")
        logger.error(f"错误详情: {traceback.format_exc()}")
        return render_template('error.html', 
                             error_message='访问链接时发生错误，请稍后重试',
                             error_code='500')

@app.errorhandler(404)
def page_not_found(e):
    return render_template('error.html', 
                         error_message='页面不存在',
                         error_code='404'), 404

@app.errorhandler(500)
def internal_server_error(e):
    return render_template('error.html', 
                         error_message='服务器内部错误，请稍后重试',
                         error_code='500'), 500

# 添加定时清理过期链接的函数
def cleanup_expired_urls():
    """清理过期的短链接"""
    try:
        now = datetime.now()
        expired_urls = URL.query.filter(
            URL.expires_at.isnot(None),  # 只查找设置了过期时间的链接
            URL.expires_at <= now  # 已经过期的链接
        ).all()
        
        for url in expired_urls:
            try:
                db.session.delete(url)
                logger.info(f"清理过期链接: {url.short_code}, 过期时间: {url.expires_at}")
            except Exception as e:
                logger.error(f"删除过期链接时发生错误: {str(e)}")
                continue
        
        db.session.commit()
        logger.info(f"成功清理 {len(expired_urls)} 个过期链接")
    except Exception as e:
        logger.error(f"清理过期链接时发生错误: {str(e)}")
        logger.error(f"错误详情: {traceback.format_exc()}")
        db.session.rollback()

@app.route('/manage')
@token_required
def manage():
    """短链接管理页面"""
    try:
        # 获取所有短链接
        links = URL.query.order_by(URL.created_at.desc()).all()
        # 获取回收站数据
        deleted_links = RecycleBin.query.order_by(RecycleBin.deleted_at.desc()).all()
        return render_template('manage.html', links=links, deleted_links=deleted_links, now=datetime.now())
    except Exception as e:
        logger.error(f"获取短链接列表时发生错误: {str(e)}")
        return render_template('error.html',
                             error_message='获取短链接列表失败',
                             error_code='500')

@app.route('/api/link/delete/<short_code>', methods=['POST'])
@token_required
def delete_link(short_code):
    """删除短链接"""
    try:
        link = URL.query.filter_by(short_code=short_code).first()
        if not link:
            return {'success': False, 'message': '短链接不存在'}, 404
        
        # 将链接移动到回收站
        recycled = RecycleBin(
            original_url=link.original_url,
            short_code=link.short_code,
            created_at=link.created_at,
            expired_at=link.expires_at,
            note=link.note,
            delete_type='manual'
        )
        db.session.add(recycled)
        
        # 删除原链接
        db.session.delete(link)
        db.session.commit()
        return {'success': True, 'message': '删除成功'}
    except Exception as e:
        logger.error(f"删除短链接时发生错误: {str(e)}")
        db.session.rollback()
        return {'success': False, 'message': '删除失败'}, 500

@app.route('/api/link/update/<short_code>', methods=['POST'])
@token_required
def update_link(short_code):
    """更新短链接"""
    try:
        link = URL.query.filter_by(short_code=short_code).first()
        if not link:
            return {'success': False, 'message': '短链接不存在'}, 404
        
        data = request.get_json()
        
        # 更新原始URL
        if 'original_url' in data:
            new_url = data['original_url'].strip()
            if not new_url:
                return {'success': False, 'message': 'URL不能为空'}, 400
            
            normalized_url = normalize_url(new_url)
            if not normalized_url:
                return {'success': False, 'message': '无效的URL格式'}, 400
            
            link.original_url = normalized_url
        
        # 更新过期时间
        if 'expires_at' in data:
            try:
                if data['expires_at']:
                    expires_at = parse_expiry_date(data['expires_at'])
                else:
                    expires_at = None
                link.expires_at = expires_at
            except ValueError:
                return {'success': False, 'message': '无效的日期格式'}, 400
        
        db.session.commit()
        return {
            'success': True,
            'message': '更新成功',
            'data': {
                'short_code': link.short_code,
                'original_url': link.original_url,
                'expires_at': link.expires_at.strftime('%Y/%m/%d %H:%M') if link.expires_at else None
            }
        }
    except Exception as e:
        logger.error(f"更新短链接时发生错误: {str(e)}")
        db.session.rollback()
        return {'success': False, 'message': '更新失败'}, 500

@app.route('/api/link/note/<short_code>', methods=['POST'])
@token_required
def update_note(short_code):
    """更新短链接备注"""
    try:
        link = URL.query.filter_by(short_code=short_code).first()
        if not link:
            return {'success': False, 'message': '短链接不存在'}, 404
        
        data = request.get_json()
        link.note = data.get('note', '').strip()
        db.session.commit()
        return {'success': True, 'message': '备注更新成功'}
    except Exception as e:
        logger.error(f"更新备注时发生错误: {str(e)}")
        db.session.rollback()
        return {'success': False, 'message': '更新失败'}, 500

@app.route('/api/recycle-bin/clear', methods=['POST'])
@token_required
def clear_recycle_bin():
    """清空回收站"""
    try:
        RecycleBin.query.delete()
        db.session.commit()
        return {'success': True, 'message': '回收站已清空'}
    except Exception as e:
        logger.error(f"清空回收站时发生错误: {str(e)}")
        db.session.rollback()
        return {'success': False, 'message': '清空失败'}, 500

if __name__ == '__main__':
    with app.app_context():
        check_and_create_table()
        # 启动时清理一次过期链接
        cleanup_expired_urls()
    app.run(debug=True) 