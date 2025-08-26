#!/bin/bash

# API代理服务停止脚本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" #当前脚本目录
PROJECT_DIR="$(dirname "$SCRIPT_DIR")" #项目根目录
NGINX_DIR="$PROJECT_DIR/nginx" #nginx配置目录
PID_FILE="$NGINX_DIR/logs/nginx.pid" #nginx进程文件

echo "停止API代理服务..."

# 检查PID文件是否存在
if [ ! -f "$PID_FILE" ]; then
    echo "PID文件不存在，服务可能没有运行"
    
    # 尝试查找并停止nginx进程
    NGINX_PIDS=$(pgrep -f "nginx.*$PROJECT_DIR")
    if [ -n "$NGINX_PIDS" ]; then
        echo "发现相关nginx进程，正在停止..."
        echo "$NGINX_PIDS" | xargs kill -TERM
        sleep 2
        
        # 强制停止仍在运行的进程
        REMAINING_PIDS=$(pgrep -f "nginx.*$PROJECT_DIR")
        if [ -n "$REMAINING_PIDS" ]; then
            echo "强制停止剩余进程..."
            echo "$REMAINING_PIDS" | xargs kill -KILL
        fi
        echo "服务已停止"
    else
        echo "没有找到运行中的服务"
    fi
    exit 0
fi

# 读取PID
PID=$(cat "$PID_FILE")

# 检查进程是否存在
if ! ps -p "$PID" > /dev/null 2>&1; then
    echo "进程不存在 (PID: $PID)，清理PID文件"
    rm -f "$PID_FILE"
    exit 0
fi

# 优雅停止
echo "正在停止服务 (PID: $PID)..."
if kill -TERM "$PID"; then
    # 等待进程停止
    for i in {1..10}; do
        if ! ps -p "$PID" > /dev/null 2>&1; then
            echo "服务已停止"
            rm -f "$PID_FILE"
            exit 0
        fi
        sleep 1
    done
    
    # 强制停止
    echo "优雅停止超时，强制停止服务..."
    if kill -KILL "$PID" 2>/dev/null; then
        echo "服务已强制停止"
        rm -f "$PID_FILE"
    else
        echo "无法停止服务"
        exit 1
    fi
else
    echo "无法发送停止信号"
    exit 1
fi