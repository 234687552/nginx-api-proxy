#!/bin/bash

# API代理服务重载脚本
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "重载API代理服务..."

# 先停止服务
echo "停止服务..."
"$SCRIPT_DIR/stop.sh"

# 再启动服务
echo "启动服务..."
"$SCRIPT_DIR/start.sh"

echo "服务重载完成"