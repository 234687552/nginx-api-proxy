local _M = {}
local config_loader = require "config_loader"

function _M.get_token()
    -- 获取配置
    local config = config_loader.get_config()
    if not config or not config.claude or not config.claude.setup_token then
        ngx.log(ngx.ERR, "No setup_token found in config")
        ngx.status = 500
        ngx.say('{"error": "Token not available"}')
        ngx.exit(500)
    end
    
    return config.claude.setup_token
end

return _M