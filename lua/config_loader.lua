local _M = {}
local cjson = require "cjson"
local utils = require "utils"

local config_cache = ngx.shared.config_cache
local config_file_path = os.getenv("PROJECT_ROOT") .. "/config/app.json"

function _M.load_config()
    -- 获取项目根目录
    local project_root = os.getenv("PROJECT_ROOT")
    if not project_root then
        ngx.log(ngx.ERR, "PROJECT_ROOT environment variable not set")
        return nil
    end

    -- 加载配置文件
    local config = utils.load_json_from_file(config_file_path)
    if not config then
        ngx.log(ngx.ERR, "Failed to load config from: ", config_file_path)
        return nil
    end
    
    -- 缓存配置到共享内存
    local config_str = cjson.encode(config)
    local success, err = config_cache:set("app_config", config_str, 3600) -- 1小时缓存
    if not success then
        ngx.log(ngx.WARN, "Failed to cache config: ", err)
    end
    
    return config
end


function _M.get_config()
    local config_str = config_cache:get("app_config")
    if config_str then
        local ok, config = pcall(cjson.decode, config_str)
        if ok then
            return config
        end
    end
    
    -- 缓存未命中或解析失败，重新加载
    return _M.load_config()
end


return _M