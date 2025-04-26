import multiprocessing

# 监听地址和端口
bind = "0.0.0.0:8000"

# 工作进程数
workers = multiprocessing.cpu_count() * 2 + 1

# 工作模式
worker_class = "sync"

# 最大客户端并发数量
worker_connections = 1000

# 进程名称
proc_name = "curl_lite"

# 超时时间
timeout = 30

# 最大请求数
max_requests = 2000
max_requests_jitter = 200

# 日志配置
accesslog = "/www/wwwlogs/curl_lite_access.log"
errorlog = "/www/wwwlogs/curl_lite_error.log"
loglevel = "info" 