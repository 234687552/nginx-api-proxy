# Claude Relay Service 架构分析

## 项目概述

Claude Relay Service 是一个基于 Node.js 的自托管 Claude API 中继服务，提供多账户管理、自定义 API Key 和 OAuth 集成功能。主要技术栈：
- 后端：Node.js + Express
- 数据库：Redis
- 前端：Web 管理界面
- 容器化：Docker 支持

## 整体架构流程

```
客户端请求 → Express路由 → 身份验证 → 格式转换 → 账户选择 → Claude API → 响应转换 → 客户端
```

## 详细处理流程

### 1. 应用启动 (app.js)

应用启动时的初始化流程：

```javascript
// 关键初始化步骤
async function initializeApp() {
  // 1. 连接 Redis
  await connectToRedis();
  
  // 2. 初始化价格和成本服务
  await initializePricingAndCost();
  
  // 3. 设置安全中间件
  setupSecurityMiddleware();
  
  // 4. 配置路由
  setupRoutes();
  
  // 5. 启动服务器
  server.listen(PORT, HOST);
  
  // 6. 设置定期清理和监控任务
  setupPeriodicTasks();
}
```

### 2. 路由处理 (openaiClaudeRoutes.js)

主要 API 端点处理逻辑：

```javascript
// GET /v1/models - 获取可用模型列表
router.get('/models', authenticateRequest, async (req, res) => {
  try {
    // 验证 API Key 权限
    const hasPermission = await checkModelPermission(req.apiKey, 'claude');
    if (!hasPermission) {
      return res.status(403).json({ error: 'Insufficient permissions' });
    }
    
    // 返回 Claude 模型列表
    const models = getAvailableClaudeModels();
    res.json({ data: models });
  } catch (error) {
    handleError(error, res);
  }
});

// POST /v1/chat/completions - 处理聊天请求
router.post('/chat/completions', authenticateRequest, async (req, res) => {
  try {
    // 1. 验证请求和权限
    const validation = await validateChatRequest(req);
    if (!validation.valid) {
      return res.status(400).json({ error: validation.message });
    }
    
    // 2. 转换 OpenAI 格式到 Claude 格式
    const claudeRequest = await convertOpenAIToClaude(req.body);
    
    // 3. 选择 Claude 账户并转发请求
    const response = await relayToClaudeAPI(claudeRequest, req.headers);
    
    // 4. 转换响应格式并返回
    const openAIResponse = await convertClaudeToOpenAI(response);
    
    // 5. 记录使用统计
    await recordUsageStats(req.apiKey, openAIResponse.usage);
    
    res.json(openAIResponse);
  } catch (error) {
    handleError(error, res);
  }
});
```

### 3. 格式转换服务 (openaiToClaude.js)

OpenAI 与 Claude 格式互转的核心逻辑：

```javascript
class OpenAIToClaude {
  // OpenAI 请求转 Claude 请求
  convertRequest(openaiRequest) {
    const claudeRequest = {
      model: this.mapModel(openaiRequest.model),
      messages: this.convertMessages(openaiRequest.messages),
      max_tokens: openaiRequest.max_tokens || 4096,
      temperature: openaiRequest.temperature,
      stream: openaiRequest.stream || false
    };
    
    // 处理系统消息
    if (openaiRequest.messages[0]?.role === 'system') {
      claudeRequest.system = openaiRequest.messages[0].content;
      claudeRequest.messages = claudeRequest.messages.slice(1);
    }
    
    // 处理工具调用
    if (openaiRequest.tools) {
      claudeRequest.tools = this.convertTools(openaiRequest.tools);
    }
    
    // 处理多模态内容
    claudeRequest.messages = this.processMultiModalContent(claudeRequest.messages);
    
    return claudeRequest;
  }
  
  // 消息格式转换
  convertMessages(messages) {
    return messages.map(msg => {
      if (msg.role === 'assistant' && msg.tool_calls) {
        // 转换工具调用
        return {
          role: 'assistant',
          content: this.convertToolCalls(msg.tool_calls)
        };
      }
      return {
        role: msg.role,
        content: this.processContent(msg.content)
      };
    });
  }
  
  // Claude 响应转 OpenAI 响应
  convertResponse(claudeResponse) {
    return {
      id: `chatcmpl-${generateId()}`,
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model: this.mapModelBack(claudeResponse.model),
      choices: [{
        index: 0,
        message: {
          role: 'assistant',
          content: claudeResponse.content[0].text
        },
        finish_reason: this.mapStopReason(claudeResponse.stop_reason)
      }],
      usage: {
        prompt_tokens: claudeResponse.usage.input_tokens,
        completion_tokens: claudeResponse.usage.output_tokens,
        total_tokens: claudeResponse.usage.input_tokens + claudeResponse.usage.output_tokens
      }
    };
  }
  
  // 处理多模态内容（图片等）
  processMultiModalContent(messages) {
    return messages.map(msg => {
      if (Array.isArray(msg.content)) {
        msg.content = msg.content.map(item => {
          if (item.type === 'image_url') {
            // 转换 base64 图片格式
            return {
              type: 'image',
              source: {
                type: 'base64',
                media_type: this.detectImageType(item.image_url.url),
                data: this.extractBase64Data(item.image_url.url)
              }
            };
          }
          return item;
        });
      }
      return msg;
    });
  }
}
```

### 4. Claude 中继服务 (claudeRelayService.js)

实际与 Claude API 通信的核心服务：

```javascript
class ClaudeRelayService {
  async relayRequest(request, headers, apiKey) {
    try {
      // 1. 选择可用的 Claude 账户
      const account = await this.selectAccount(apiKey);
      if (!account) {
        throw new Error('No available Claude accounts');
      }
      
      // 2. 准备请求配置
      const requestConfig = this.prepareRequestConfig(request, account, headers);
      
      // 3. 发送请求到 Claude API
      const response = await this.sendToClaudeAPI(requestConfig);
      
      // 4. 处理响应
      if (request.stream) {
        return this.handleStreamResponse(response);
      } else {
        return this.handleNormalResponse(response);
      }
      
    } catch (error) {
      await this.handleRequestError(error, account);
      throw error;
    }
  }
  
  // 选择 Claude 账户（负载均衡）
  async selectAccount(apiKey) {
    const accounts = await this.getAvailableAccounts(apiKey);
    
    // 过滤掉被限流或不可用的账户
    const activeAccounts = accounts.filter(acc => 
      acc.status === 'active' && !acc.rateLimited
    );
    
    if (activeAccounts.length === 0) {
      return null;
    }
    
    // 使用轮询或最少使用策略选择账户
    return this.selectByStrategy(activeAccounts, 'round_robin');
  }
  
  // 发送请求到 Claude API
  async sendToClaudeAPI(config) {
    const options = {
      hostname: 'api.anthropic.com',
      port: 443,
      path: '/v1/messages',
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${config.account.token}`,
        'anthropic-version': '2023-06-01',
        ...this.filterHeaders(config.headers)
      }
    };
    
    // 支持代理配置
    if (config.proxy) {
      options.agent = this.createProxyAgent(config.proxy);
    }
    
    return new Promise((resolve, reject) => {
      const req = https.request(options, (res) => {
        if (config.stream) {
          resolve(res); // 直接返回流
        } else {
          let data = '';
          res.on('data', chunk => data += chunk);
          res.on('end', () => {
            try {
              const response = JSON.parse(data);
              resolve(response);
            } catch (error) {
              reject(new Error('Invalid JSON response'));
            }
          });
        }
      });
      
      req.on('error', reject);
      req.write(JSON.stringify(config.request));
      req.end();
    });
  }
  
  // 处理流式响应
  handleStreamResponse(response) {
    return new Transform({
      transform(chunk, encoding, callback) {
        try {
          // 解析 SSE 格式数据
          const lines = chunk.toString().split('\n');
          for (const line of lines) {
            if (line.startsWith('data: ')) {
              const data = line.slice(6);
              if (data === '[DONE]') {
                this.push('data: [DONE]\n\n');
                continue;
              }
              
              // 转换 Claude SSE 格式到 OpenAI 格式
              const claudeEvent = JSON.parse(data);
              const openaiEvent = this.convertStreamEvent(claudeEvent);
              this.push(`data: ${JSON.stringify(openaiEvent)}\n\n`);
            }
          }
          callback();
        } catch (error) {
          callback(error);
        }
      }
    });
  }
  
  // 错误处理和重试逻辑
  async handleRequestError(error, account) {
    if (error.status === 429) {
      // 限流错误，标记账户临时不可用
      await this.markAccountRateLimited(account, 60000); // 1分钟
    } else if (error.status === 401) {
      // 认证错误，标记账户为未授权
      await this.markAccountUnauthorized(account);
    }
    
    // 记录错误日志
    logger.error('Claude API request failed', {
      accountId: account.id,
      error: error.message,
      status: error.status
    });
  }
}
```

### 5. 账户管理和调度

```javascript
// 统一 Claude 调度器 (unifiedClaudeScheduler.js)
class UnifiedClaudeScheduler {
  async selectBestAccount(requirements) {
    const accounts = await this.getAllAccounts();
    
    // 根据不同策略选择账户
    switch (this.strategy) {
      case 'round_robin':
        return this.roundRobinSelect(accounts);
      case 'least_used':
        return this.leastUsedSelect(accounts);
      case 'performance':
        return this.performanceBasedSelect(accounts);
      default:
        return this.randomSelect(accounts);
    }
  }
  
  // 健康检查
  async healthCheck() {
    const accounts = await this.getAllAccounts();
    for (const account of accounts) {
      try {
        await this.pingAccount(account);
        await this.updateAccountStatus(account.id, 'healthy');
      } catch (error) {
        await this.updateAccountStatus(account.id, 'unhealthy');
      }
    }
  }
}
```

## 关键特性

### 1. 多账户管理
- 支持多个 Claude 账户轮询使用
- 自动故障切换和负载均衡
- 账户健康状态监控

### 2. 格式兼容
- 提供 OpenAI 兼容的 API 接口
- 自动转换请求/响应格式
- 支持多模态内容处理

### 3. 流式响应
- 支持 Server-Sent Events (SSE)
- 实时流式数据转换
- 低延迟响应处理

### 4. 监控统计
- 详细的 API 使用统计
- 错误率和性能监控
- 成本跟踪和分析

### 5. 安全控制
- API Key 验证和权限管理
- 请求限流和访问控制
- 敏感信息过滤

## 部署架构

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   客户端    │───▶│  Nginx/LB   │───▶│  Node.js    │
│   应用      │    │   (可选)    │    │  Express    │
└─────────────┘    └─────────────┘    └─────────────┘
                                              │
                   ┌─────────────┐            │
                   │    Redis    │◀───────────┘
                   │   (缓存)    │
                   └─────────────┘
                                              │
                   ┌─────────────┐            │
                   │  Claude API │◀───────────┘
                   │  (多账户)   │
                   └─────────────┘
```

## Claude Account Token 获取详细流程

### Token 的产生逻辑

`${config.account.token}` 的获取过程涉及多个步骤和组件：

#### 1. OAuth 授权流程 (oauthHelper.js)

```javascript
// 生成 OAuth 授权 URL
function generateAuthUrl() {
  // 生成 PKCE 参数
  const codeVerifier = generateCodeVerifier(); // 随机字符串
  const codeChallenge = crypto.createHash('sha256')
    .update(codeVerifier)
    .digest('base64url');
  const state = generateRandomString(32);
  
  const authUrl = new URL('https://console.anthropic.com/oauth/authorize');
  authUrl.searchParams.set('client_id', CLAUDE_CLIENT_ID);
  authUrl.searchParams.set('response_type', 'code');
  authUrl.searchParams.set('scope', 'openid profile email');
  authUrl.searchParams.set('redirect_uri', REDIRECT_URI);
  authUrl.searchParams.set('state', state);
  authUrl.searchParams.set('code_challenge', codeChallenge);
  authUrl.searchParams.set('code_challenge_method', 'S256');
  
  return { authUrl: authUrl.toString(), codeVerifier, state };
}

// 用授权码交换 token
async function exchangeCodeForToken(code, codeVerifier, proxy = null) {
  const tokenEndpoint = 'https://console.anthropic.com/v1/oauth/token';
  
  const requestData = {
    grant_type: 'authorization_code',
    client_id: CLAUDE_CLIENT_ID,
    code: code,
    redirect_uri: REDIRECT_URI,
    code_verifier: codeVerifier
  };
  
  const options = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    },
    body: new URLSearchParams(requestData)
  };
  
  // 支持代理配置
  if (proxy) {
    options.agent = createProxyAgent(proxy);
  }
  
  try {
    const response = await fetch(tokenEndpoint, options);
    const tokenData = await response.json();
    
    if (!response.ok) {
      throw new Error(`Token exchange failed: ${tokenData.error}`);
    }
    
    return {
      access_token: tokenData.access_token,
      refresh_token: tokenData.refresh_token,
      expires_in: tokenData.expires_in,
      token_type: tokenData.token_type,
      scope: tokenData.scope
    };
  } catch (error) {
    logger.error('OAuth token exchange failed', { error: error.message });
    throw error;
  }
}
```

#### 2. 账户创建和存储 (claudeAccountService.js)

```javascript
// 创建 Claude 账户并存储 token
async function createAccount(accountData) {
  try {
    const accountId = uuidv4();
    const encryptedData = {
      id: accountId,
      name: accountData.name,
      email: encrypt(accountData.email),
      password: encrypt(accountData.password),
      access_token: encrypt(accountData.access_token),
      refresh_token: encrypt(accountData.refresh_token),
      token_expires_at: accountData.token_expires_at,
      account_type: accountData.account_type || 'shared',
      subscription_type: accountData.subscription_type,
      proxy: accountData.proxy ? encrypt(JSON.stringify(accountData.proxy)) : null,
      status: 'active',
      created_at: new Date().toISOString(),
      last_used: null,
      session_window_start: null,
      session_window_duration: null
    };
    
    // 存储到 Redis
    await redis.hset(`claude_account:${accountId}`, encryptedData);
    await redis.sadd('claude_accounts', accountId);
    
    logger.info('Claude account created successfully', { accountId, name: accountData.name });
    return accountId;
  } catch (error) {
    logger.error('Failed to create Claude account', { error: error.message });
    throw error;
  }
}

// 获取有效的访问 token
async function getValidAccessToken(accountId) {
  try {
    const account = await getAccountById(accountId);
    if (!account) {
      throw new Error(`Account not found: ${accountId}`);
    }
    
    // 检查 token 是否即将过期（60秒内）
    const now = Math.floor(Date.now() / 1000);
    const expiresAt = account.token_expires_at;
    const willExpireSoon = (expiresAt - now) < 60;
    
    if (willExpireSoon) {
      logger.info('Token expiring soon, attempting refresh', { accountId });
      
      // 尝试刷新 token
      const refreshSuccess = await refreshAccountToken(accountId);
      if (refreshSuccess) {
        // 获取刷新后的 token
        const refreshedAccount = await getAccountById(accountId);
        return decrypt(refreshedAccount.access_token);
      } else {
        logger.warn('Token refresh failed, using current token', { accountId });
      }
    }
    
    // 更新最后使用时间
    await redis.hset(`claude_account:${accountId}`, 'last_used', new Date().toISOString());
    
    return decrypt(account.access_token);
  } catch (error) {
    logger.error('Failed to get valid access token', { accountId, error: error.message });
    throw error;
  }
}
```

#### 3. Token 刷新机制 (claudeAccountService.js + tokenRefreshService.js)

```javascript
// 刷新 Claude 账户 token
async function refreshAccountToken(accountId) {
  let lockAcquired = false;
  
  try {
    // 获取分布式锁，防止并发刷新
    lockAcquired = await tokenRefreshService.acquireRefreshLock('claude', accountId);
    if (!lockAcquired) {
      logger.info('Token refresh already in progress', { accountId });
      return false;
    }
    
    const account = await getAccountById(accountId);
    if (!account || !account.refresh_token) {
      throw new Error('No refresh token available');
    }
    
    const refreshToken = decrypt(account.refresh_token);
    const proxy = account.proxy ? JSON.parse(decrypt(account.proxy)) : null;
    
    // 调用 Claude 的 token 刷新端点
    const tokenData = await refreshClaudeToken(refreshToken, proxy);
    
    // 更新账户信息
    const updateData = {
      access_token: encrypt(tokenData.access_token),
      token_expires_at: Math.floor(Date.now() / 1000) + tokenData.expires_in,
      status: 'active',
      last_token_refresh: new Date().toISOString()
    };
    
    // 如果返回了新的 refresh_token，也要更新
    if (tokenData.refresh_token) {
      updateData.refresh_token = encrypt(tokenData.refresh_token);
    }
    
    await redis.hmset(`claude_account:${accountId}`, updateData);
    
    // 尝试更新账户档案信息
    try {
      await updateAccountProfile(accountId);
    } catch (profileError) {
      logger.warn('Failed to update profile after token refresh', { 
        accountId, 
        error: profileError.message 
      });
    }
    
    logger.info('Token refreshed successfully', { accountId });
    return true;
    
  } catch (error) {
    logger.error('Token refresh failed', { accountId, error: error.message });
    
    // 标记账户为错误状态
    await redis.hset(`claude_account:${accountId}`, 'status', 'error');
    
    // 发送 webhook 通知
    await sendWebhookNotification('claude_account_error', {
      accountId,
      error: error.message,
      timestamp: new Date().toISOString()
    });
    
    return false;
  } finally {
    if (lockAcquired) {
      await tokenRefreshService.releaseRefreshLock('claude', accountId);
    }
  }
}

// 实际的 Claude token 刷新请求
async function refreshClaudeToken(refreshToken, proxy = null) {
  const tokenEndpoint = 'https://console.anthropic.com/v1/oauth/token';
  
  const requestData = {
    grant_type: 'refresh_token',
    client_id: CLAUDE_CLIENT_ID,
    refresh_token: refreshToken
  };
  
  const options = {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    },
    body: new URLSearchParams(requestData)
  };
  
  if (proxy) {
    options.agent = createProxyAgent(proxy);
  }
  
  const response = await fetch(tokenEndpoint, options);
  const data = await response.json();
  
  if (!response.ok) {
    throw new Error(`Token refresh failed: ${data.error || response.statusText}`);
  }
  
  return {
    access_token: data.access_token,
    refresh_token: data.refresh_token,
    expires_in: data.expires_in || 3600,
    token_type: data.token_type || 'Bearer'
  };
}
```

#### 4. Token 使用流程

在实际 API 调用中，`${config.account.token}` 的使用：

```javascript
// claudeRelayService.js 中的使用
async function relayRequest(request, headers, apiKey) {
  // 1. 选择可用账户
  const account = await selectAccount(apiKey);
  
  // 2. 获取有效的 access token
  const accessToken = await claudeAccountService.getValidAccessToken(account.id);
  
  // 3. 准备请求配置
  const config = {
    account: {
      ...account,
      token: accessToken  // 这里就是 ${config.account.token}
    },
    request: request,
    headers: headers,
    proxy: account.proxy
  };
  
  // 4. 发送到 Claude API
  const response = await sendToClaudeAPI(config);
  return response;
}

// 在 HTTPS 请求中使用
async function sendToClaudeAPI(config) {
  const options = {
    hostname: 'api.anthropic.com',
    port: 443,
    path: '/v1/messages',
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${config.account.token}`, // 实际使用位置
      'anthropic-version': '2023-06-01',
      ...filterHeaders(config.headers)
    }
  };
  
  // 后续请求处理...
}
```

### Token 生命周期总结

1. **初始获取**: OAuth 授权码交换 → 获得 access_token + refresh_token
2. **安全存储**: AES-256-CBC 加密存储到 Redis
3. **有效性检查**: 每次使用前检查是否在60秒内过期
4. **自动刷新**: 使用 refresh_token 获取新的 access_token
5. **分布式锁**: 防止并发刷新冲突
6. **错误处理**: 刷新失败时的降级和通知机制

这个架构提供了一个高可用、可扩展的 Claude API 代理解决方案，具备完善的账户管理、格式转换和监控功能。