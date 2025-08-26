# Claude API Proxy

基于 OpenResty 实现的 Claude API 代理服务，支持简单的 setup token 认证。

## 功能特性

1. **API Key 校验**: 基于配置文件的 API Key 白名单验证
2. **Setup Token 认证**: 使用 Claude CLI setup token 进行认证
3. **路径代理**: `/claude/` 路径下的请求直接代理到 Claude API
4. **请求透传**: 完全透传客户端请求头，只添加认证头
5. **配置热重载**: 支持简单的重载机制
6. **轻量设计**: 精简的代码结构和高性能

## 快速开始

### 1. 环境要求

- OpenResty (brew install openresty)
- curl 工具
- jq 工具（可选，用于配置验证）

### 2. 获取代码

```bash
# 克隆仓库
git clone <your-repo-url>
cd nginx-api-proxy

# 复制配置模板
cp config/app.json.template config/app.json

# 给脚本添加执行权限
chmod +x scripts/*.sh
```

### 3. 配置 Setup Token

编辑 `config/app.json` 配置文件：

```json
{
  "api_keys": [
    {
      "key": "your-custom-api-key",
      "name": "My API Key",
      "enabled": true
    }
  ],
  "claude": {
    "base_url": "https://api.anthropic.com",
    "setup_token": "执行命令得到：claude setup-token"
  }
}
```

**获取 Setup Token:**

```bash
# 安装 Claude CLI
pip install anthropic-cli

# 生成 setup token
claude setup-token
```

### 4. 启动服务

```bash
# 启动服务
./scripts/start.sh

# 检查服务状态
curl http://localhost:19981/health
```

### 5. 测试 API

```bash
# 测试Claude API代理
改本地claude的setting文件，配置baseurl,api-key
```

## 项目结构

```
nginx-api-proxy/
├── nginx/                      # nginx配置和日志
│   ├── conf/
│   │   ├── nginx.conf          # 主配置文件
│   │   ├── claude-proxy.conf   # Claude代理配置
│   │   └── mime.types          # MIME类型配置
│   └── logs/                   # 日志目录（自动生成）
├── lua/                        # Lua模块
│   ├── config_loader.lua       # 配置加载器
│   ├── header_validator.lua    # Header校验器
│   ├── utils.lua               # 工具函数
│   └── claude/
│       ├── token_manager.lua   # 简化的Token管理器
│       └── token_manager.lua.backup # 原OAuth版本的备份
├── config/
│   ├── app.json.template       # 配置模板
│   └── app.json               # 应用配置（复制模板创建）
├── scripts/                   # 管理脚本
│   ├── start.sh              # 启动脚本
│   ├── stop.sh               # 停止脚本
│   └── reload.sh             # 简化的重载脚本
└── docs/                     # 文档目录
```

## 配置详解

### 应用配置 `config/app.json`

```json
{
  "api_keys": [
    {
      "key": "your-custom-api-key",
      "name": "Default Key",
      "enabled": true
    },
    {
      "key": "backup-key-123",
      "name": "Backup Key",
      "enabled": false
    }
  ],
  "claude": {
    "base_url": "https://api.anthropic.com",
    "setup_token": "执行命令得到：claude setup-token"
  }
}
```

**配置说明：**

- `api_keys`: 客户端访问密钥列表，支持多个密钥
- `claude.setup_token`: 从 claude CLI 获取的 setup token
- `claude.base_url`: Claude API 基础 URL（可选）

## 服务管理

### 启动服务

```bash
./scripts/start.sh
```

启动脚本会：

- 设置 `PROJECT_ROOT` 环境变量
- 检查配置文件完整性
- 验证 nginx 配置语法
- 启动 OpenResty 服务
- 监听端口 19981

### 停止服务

```bash
./scripts/stop.sh
```

### 重载配置

```bash
./scripts/reload.sh
```

重载脚本会：

- 先停止服务
- 再启动服务
- 完全重载所有配置

## 日志查看

```bash
# 访问日志
tail -f nginx/logs/access.log

# 错误日志
tail -f nginx/logs/error.log
```

## API 接口

### 客户端接口

所有 `/claude/` 路径下的请求都会被代理到 Claude API：

- `POST /claude/v1/messages` - Claude 消息接口（主要接口）
- `GET /claude/v1/models` - 获取模型列表
- `POST /claude/*` - 其他 Claude API 路径

**请求头要求：**

- `X-API-Key: your-custom-api-key` 或
- `Authorization: Bearer your-custom-api-key`

**特性：**

- 完全透传客户端请求头
- 自动添加 Claude API 认证头
- 保持原始请求格式

### 系统接口

- `GET /health` - 健康检查接口

## 故障排除

### 常见问题

1. **服务启动失败**

   - 检查 OpenResty 是否正确安装：`openresty -v`
   - 验证配置文件语法：`openresty -t -c nginx/conf/nginx.conf -p nginx/`
   - 查看错误日志：`tail -f nginx/logs/error.log`

2. **Lua 模块找不到**

   ```bash
   # 如果出现 "module 'config_loader' not found" 错误
   # 检查项目结构是否完整
   ls -la lua/

   # 确保环境变量正确设置
   export PROJECT_ROOT=$(pwd)

   # 重新启动服务
   ./scripts/start.sh
   ```

3. **API Key 验证失败**

   - 检查请求头中是否包含 Authorization 或 X-API-Key
   - 确认 API Key 在 config/app.json 中已配置且 enabled=true
   - 检查 API Key 是否拼写正确

4. **Setup Token 获取失败**

   - 检查 config/app.json 中 setup_token 是否正确配置
   - 确认 setup_token 是否有效（可通过 claude CLI 重新生成）
   - 查看错误日志了解具体原因

5. **Setup Token 获取方法**

   ```bash
   # 安装 Claude CLI
   pip install anthropic-cli

   # 生成新的 setup token
   claude setup-token

   # 将返回的 token 填入 config/app.json 的 claude.setup_token 字段
   ```

## 代码变更说明

相比原版本，当前版本进行了以下简化：

1. **Token 管理简化**: 移除了复杂的 OAuth 流程，直接使用 setup token
2. **请求透传**: 完全透传客户端请求头，只添加认证头
3. **配置简化**: 移除了 OAuth 相关配置和内部管理接口
4. **日志优化**: 删除了调试日志，减少性能损耗
5. **重载简化**: 重载脚本改为简单的停止-启动流程

## 许可证

本项目仅用于学习和研究目的。
