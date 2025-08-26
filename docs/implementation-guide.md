# Claude API 代理服务实现指南

## 1. 架构概览

本项目实现了一个基于 OpenResty 的 Claude API 代理服务，支持完整的 OAuth2.0 认证流程和智能 token 管理。

### 1.1 核心功能

- **API Key 校验**: 基于配置文件的客户端 API Key 白名单验证
- **OAuth2.0 认证**: 完整的 Claude Code CLI 兼容的 OAuth 认证流程
- **智能 Token 管理**: 自动获取、刷新和缓存 Claude API tokens
- **路径代理**: `/claude/` 路径下的请求无缝代理到 Claude API
- **配置热重载**: 支持运行时配置更新

### 1.2 技术栈

- **OpenResty**: 高性能 HTTP 代理服务器
- **Lua**: 业务逻辑实现语言
- **JSON**: 配置文件格式
- **OAuth2.0 + PKCE**: 安全认证标准

## 2. 技术选型

### 2.1 核心组件

- **OpenResty**: 基于 Nginx 的 Web 应用服务器，内置 Lua 支持
- **Lua**: 用于实现业务逻辑和动态配置
- **JSON 配置文件**: 用于 API Key 白名单和 Claude token 配置

### 2.2 选型理由

- OpenResty 提供高性能的 HTTP 代理能力
- Lua 脚本支持灵活的业务逻辑实现
- 成熟的生态系统和丰富的第三方模块

## 3. 系统架构

### 3.1 请求处理流程

```
客户端请求
    ↓
[Header 校验] → 校验失败 → 返回 403
    ↓  
[路径匹配] → /claude/* → [OAuth Token获取]
    ↓                      ↓
[健康检查] ← 返回200    [Token刷新/验证]
    ↓                      ↓
[内部API] ← 返回结果    [代理到Claude API]
    ↓                      ↓
[404错误]              [流式响应返回]
```

### 3.2 OAuth2.0 认证流程

```
1. 生成授权URL → 2. 浏览器授权 → 3. 获取授权码 → 4. 交换Token
    ↓               ↓               ↓              ↓
[内部API]     [Claude OAuth]   [回调URL]     [Token存储]
    ↓               ↓               ↓              ↓
URL + State    授权页面        Authorization Code  access_token
code_verifier   用户确认        + state           refresh_token
```

## 4. 项目结构

```
nginx-api-proxy/
├── nginx/                      # OpenResty 配置
│   ├── conf/
│   │   ├── nginx.conf          # 主配置文件
│   │   ├── claude-proxy.conf   # Claude 代理配置
│   │   └── mime.types          # MIME 类型配置
│   └── logs/                   # 日志目录（自动生成）
├── lua/                        # Lua 业务模块
│   ├── config_loader.lua       # 配置加载器
│   ├── header_validator.lua    # Header 校验器  
│   ├── utils.lua               # 工具函数库
│   └── claude/
│       └── token_manager.lua   # OAuth Token 管理器
├── config/
│   ├── app.json.template       # 配置模板
│   ├── app.json               # 应用配置（手动创建）
│   └── tokens.json            # Token 存储（自动生成）
├── scripts/                   # 管理脚本
│   ├── start.sh              # 启动服务
│   ├── stop.sh               # 停止服务  
│   └── reload.sh             # 重载配置
└── docs/                     # 项目文档
    ├── claude-cli-login.md   # OAuth 认证文档
    └── implementation-guide.md # 本实现指南
```

## 5. 核心模块详解

### 5.1 配置加载器 (config_loader.lua)

**功能：**
- 加载 `config/app.json` 应用配置
- 提供共享内存缓存机制（1小时TTL）
- 支持配置热重载

**关键函数：**
- `load_config()`: 从文件加载配置到内存缓存
- `get_config()`: 获取配置，支持缓存未命中时自动加载
- `reload_config()`: 清除缓存并重新加载配置

### 5.2 Header校验器 (header_validator.lua)

**功能：**
- 提取客户端API Key（支持 `X-API-Key` 和 `Authorization` 头）
- 验证API Key是否在配置白名单中且已启用
- 校验失败时返回403状态码

**校验逻辑：**
```lua
-- 支持两种格式：
-- X-API-Key: your-api-key
-- Authorization: Bearer your-api-key
```

### 5.3 OAuth Token管理器 (claude/token_manager.lua)

**核心功能：**
- **OAuth授权URL生成**: 支持PKCE安全扩展
- **授权码换取Token**: 完整的OAuth2.0流程
- **Token自动刷新**: 提前5分钟自动刷新即将过期的token
- **双重缓存机制**: 内存缓存(1小时) + 文件持久化

**主要函数：**
- `get_authorization_url()`: 生成OAuth登录URL
- `callback_authorization_code()`: 处理授权码回调
- `exchange_code()`: 授权码换取access_token
- `refresh_token()`: 使用refresh_token刷新access_token
- `get_token()`: 获取有效token（自动刷新）

### 5.4 工具函数库 (utils.lua)

**提供：**
- JSON文件读写操作
- PKCE code_verifier生成和校验
- URL编码/解码
- 随机字符串生成
- 文件操作封装

## 6. 部署指南

### 6.1 环境要求

```bash
# macOS 环境
brew install openresty
brew install jq  # 可选，用于配置验证

# 验证安装
openresty -v
```

### 6.2 快速部署

```bash
# 1. 获取项目代码
git clone <repo-url>
cd nginx-api-proxy

# 2. 创建配置文件
cp config/app.json.template config/app.json

# 3. 给脚本添加执行权限
chmod +x scripts/*.sh

# 4. 编辑配置文件
nano config/app.json

# 5. 启动服务
./scripts/start.sh

# 6. 验证服务
curl http://localhost:19981/health
```

### 6.3 OAuth认证配置

```bash
# 1. 启动服务
./scripts/start.sh

# 2. 生成OAuth登录URL
curl http://localhost:19981/internal/oauth/login-url

# 3. 浏览器完成授权，获取authorization_code

# 4. 交换Token
curl -X POST http://localhost:19981/internal/oauth/exchange \
  -H "Content-Type: application/json" \
  -d '{"code": "ac_xxx", "state": "xxx"}'
```

### 6.4 服务管理

```bash
# 启动服务
./scripts/start.sh

# 重载配置（支持热更新）
./scripts/reload.sh  

# 停止服务
./scripts/stop.sh

# 查看日志
tail -f nginx/logs/error.log
tail -f nginx/logs/access.log
```

## 7. 配置参考

### 7.1 应用配置示例 (config/app.json)

```json
{
  "api_keys": [
    {
      "key": "your-custom-api-key",
      "name": "Default API Key",
      "enabled": true
    },
    {
      "key": "backup-key-123",
      "name": "Backup Key",
      "enabled": false
    }
  ],
  "claude": {
    "base_url": "https://api.anthropic.com"
  },
  "server": {
    "port": 19981,
    "host": "127.0.0.1"
  },
  "logging": {
    "level": "info"
  }
}
```

### 7.2 Token存储示例 (config/tokens.json)

OAuth认证成功后自动生成的Token文件：

```json
{
  "access_token": "sk-ant-oat01-xxxxxxxxx",
  "refresh_token": "sk-ant-ort01-xxxxxxxxx", 
  "expires_at": 1754945252465,
  "expires_in": 3600,
  "token_type": "bearer",
  "scope": "user:inference",
  "state": "random-state-value",
  "code_verifier": "pkce-code-verifier",
  "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  "status": "token_exchanged",
  "created_at": 1704945252,
  "exchange_at": 1704945252,
  "refresh_at": 1704948852
}
```

## 8. 高级特性

### 8.1 Token自动管理

系统实现了智能的Token管理机制：

**自动刷新：**
- 监控Token过期时间，提前5分钟自动刷新
- 使用refresh_token无缝更新access_token  
- 失败时自动降级到重新OAuth认证

**双重缓存：**
- 内存缓存：1小时TTL，提高响应性能
- 文件持久化：重启后自动恢复Token状态

**状态跟踪：**
```
pending → callback_received → token_exchanged → token_refreshed
```

### 8.2 配置热重载

支持运行时配置更新：

```bash
# 修改 config/app.json 后
./scripts/reload.sh

# 系统会：
# 1. 验证JSON格式
# 2. 测试nginx配置
# 3. 发送HUP信号重载
# 4. 清除配置缓存
```

### 8.3 安全特性

**PKCE扩展：**
- OAuth2.0使用PKCE防止授权码拦截攻击
- code_verifier和code_challenge动态生成

**访问限制：**
- 内部API仅允许本地访问（127.0.0.1）
- 客户端API需要有效的API Key

**SSL安全：**
- 所有外部API调用使用HTTPS
- 支持自定义SSL证书验证

## 9. 故障排除

### 9.1 常见问题

**服务启动失败：**
```bash
# 检查OpenResty是否安装
openresty -v

# 验证配置语法
openresty -t -c nginx/conf/nginx.conf -p nginx/

# 检查端口占用
lsof -i :19981
```

**API Key验证失败：**
```bash
# 检查配置文件格式
jq . config/app.json

# 验证API Key设置
curl -H "X-API-Key: your-key" http://localhost:19981/health
```

**Token相关错误：**
```bash
# 检查token文件
ls -la config/tokens.json

# 重新OAuth认证
rm config/tokens.json
curl http://localhost:19981/internal/oauth/login-url
```

**环境变量问题：**
```bash
# 如果出现 "attempt to concatenate a nil value" 错误
# 检查PROJECT_ROOT环境变量
echo $PROJECT_ROOT

# 确保环境变量正确设置并重启服务
export PROJECT_ROOT=$(pwd)
./scripts/stop.sh
./scripts/start.sh
```

### 9.2 日志分析

```bash
# 查看详细错误
tail -f nginx/logs/error.log

# 监控访问日志
tail -f nginx/logs/access.log

# 按错误级别过滤
grep "ERROR" nginx/logs/error.log
```

## 10. 性能优化

### 10.1 缓存策略
- 配置文件：1小时内存缓存
- Token：1小时内存缓存 + 文件持久化
- 共享内存：使用nginx shared_dict提高性能

### 10.2 连接优化
- 代理连接池：复用到Claude API的连接
- 超时设置：合理的连接、发送、接收超时
- 缓冲设置：关闭不必要的缓冲以支持流式响应
