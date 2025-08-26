#!/bin/bash

# API代理服务启动脚本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" #当前脚本目录
PROJECT_DIR="$(dirname "$SCRIPT_DIR")" #项目根目录
NGINX_DIR="$PROJECT_DIR/nginx" #nginx配置目录
CONFIG_FILE="$NGINX_DIR/conf/nginx.conf" #nginx配置文件
PID_FILE="$NGINX_DIR/logs/nginx.pid" #nginx进程文件

# 设置环境变量供nginx lua脚本使用
export PROJECT_ROOT="$PROJECT_DIR" #项目根目录

echo "启动API代理服务..."
echo "项目根路径: $PROJECT_ROOT"

# 检查配置文件
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 配置文件不存在 $CONFIG_FILE"
    exit 1
fi

# 检查app.json配置文件
APP_CONFIG="$PROJECT_DIR/config/app.json"
if [ ! -f "$APP_CONFIG" ]; then
    echo "错误: 应用配置文件不存在 $APP_CONFIG"
    exit 1
fi

# 创建日志目录
mkdir -p "$NGINX_DIR/logs"

# 检查是否已经运行
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "服务已经在运行中 (PID: $PID)"
        exit 0
    else
        echo "删除过期的PID文件"
        rm -f "$PID_FILE"
    fi
fi

# 测试nginx配置
echo "测试nginx配置..."
if ! openresty -t -c "$CONFIG_FILE" -p "$NGINX_DIR"; then
    echo "错误: nginx配置测试失败"
    exit 1
fi

# 启动nginx
echo "启动nginx..."
if openresty -c "$CONFIG_FILE" -p "$NGINX_DIR"; then
    echo "API代理服务启动成功"
    echo "服务地址: http://localhost:19981"
    echo "健康检查: http://localhost:19981/health"
    echo "日志文件: $NGINX_DIR/logs/"
    
    # 等待一秒后检查服务状态
    sleep 1
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "服务PID: $PID"
    fi
else
    echo "错误: 服务启动失败"
    exit 1
fi