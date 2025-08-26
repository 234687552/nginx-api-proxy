# Token管理设计方案

基于 Claude Code CLI 的 OAuth2.0 + PKCE 认证流程设计的API代理token管理系统。

## 核心功能

### 1. OAuth2.0授权码换取Token
- **端点**: `POST https://api.anthropic.com/oauth/token`
- **请求参数**:
  ```json
  {
    "grant_type": "authorization_code",
    "code": "ac_2PJ3kL5mN7qR9sT...",
    "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
    "code_verifier": "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk",
    "redirect_uri": "https://console.anthropic.com/oauth/code/callback"
  }
  ```

### 2. Token自动刷新机制
- **端点**: `POST https://api.anthropic.com/oauth/token`
- **请求参数**:
  ```json
  {
    "grant_type": "refresh_token",
    "refresh_token": "sk-ant-ort01-...",
    "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
  }
  ```

### 3. Token存储格式
参考 Claude Code CLI 的 `.credentials.json` 格式：

```json
{
  "claudeAiOauth": {
    "accessToken": "sk-ant-oat01-...",
    "refreshToken": "sk-ant-ort01-...",
    "expiresAt": 1754945252465,
    "scopes": ["user:inference", "user:profile"],
    "subscriptionType": "max"
  }
}
```

**字段说明**:
- `accessToken`: API调用令牌（动态有效期，以接口返回为准）
- `refreshToken`: 刷新令牌（长期有效）
- `expiresAt`: accessToken的过期时间戳（毫秒）
- `scopes`: 权限范围
- `subscriptionType`: 订阅类型

## 实现架构

### 存储层次
1. **内存缓存**: `ngx.shared.token_cache` - 快速访问
2. **文件存储**: `config/tokens.json` - 持久化保存

### 核心流程
1. **授权码换取**: `exchange_code(authorization_code, code_verifier)`
2. **Token获取**: `get_token()` - 自动处理过期和刷新
3. **Token刷新**: `refresh_token(refresh_token)`
4. **Token验证**: `validate()` - 检查token有效性

### 安全机制
1. **PKCE验证**: 支持code_verifier/code_challenge机制
2. **文件权限**: 限制token文件访问权限
3. **日志安全**: 不在日志中输出token内容
4. **内存清理**: 定期清理过期token缓存

### API接口
- `exchange_code(code, verifier)` - 授权码换取token
- `get_token()` - 获取有效token（自动刷新）
- `validate()` - 验证token有效性
- `refresh_token(refresh_token)` - 刷新token
- `save_tokens(token_data)` - 保存token到文件和缓存
- `load_tokens_from_file()` - 从文件加载token
- `cache_token(token_data)` - 更新内存缓存

### 配置要求
配置文件需包含OAuth2.0相关参数：

```json
{
  "claude": {
    "oauth": {
      "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
      "redirect_uri": "https://console.anthropic.com/oauth/code/callback"
    }
  }
}
```

### 错误处理
- Token过期自动刷新
- 网络错误重试机制
- 无效token时返回null
- 详细错误日志记录

### 使用场景
1. **初次认证**: 使用授权码换取token
2. **日常使用**: 自动获取有效token
3. **token过期**: 自动使用refresh_token刷新
4. **系统重启**: 从文件恢复token到内存

这个设计确保了token的安全管理和自动生命周期处理，符合OAuth2.0标准。