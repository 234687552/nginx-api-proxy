local _M = {}
local config_loader = require "config_loader"

-- 校验请求头中的API Key
function _M.validate(headers)
    if not headers then
        return false
    end
    
    -- 提取header的key
    local api_key =  headers["x-api-key"] or headers["X-API-Key"]
    if not api_key or api_key == "" then
        return false
    end
    
    -- 获取配置中的key
    local config = config_loader.get_config()
    if not config or not config.api_keys then
        return false
    end
    
    -- 验证API key是否在配置中
    local is_valid = false
    if config.api_keys then
        for _, key_config in ipairs(config.api_keys) do
            if key_config.key == api_key and key_config.enabled then
                is_valid = true
                break
            end
        end
    end
    
    -- 验证通过后删除API key header，避免透传
    if is_valid then
        ngx.req.clear_header("x-api-key")
        ngx.req.clear_header("X-API-Key")
    end
    
    return is_valid
end

-- 校验请求头，失败时直接退出
function _M.check_and_exit()
    if not _M.validate(ngx.req.get_headers()) then
        ngx.status = 403
        ngx.say('{"error": "Invalid headers"}')
        ngx.exit(403)
    end
end

return _M