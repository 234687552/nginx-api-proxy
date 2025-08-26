local _M = {}
local resty_string = require "resty.string"
local resty_random = require "resty.random"
local resty_sha256 = require "resty.sha256"
local cjson = require "cjson"
local io = require "io"

-- 生成随机字符串（Base64URL编码，与JS版本保持一致）
function _M.generate_random_string(length)
    length = length or 128  -- 默认128字符，与JS版本一致
    local bytes = resty_random.bytes(32)  -- 32字节随机数
    local b64_str = _M.base64_url_safe_encode(bytes)
    return b64_str:sub(1, length)
end

-- URL编码
function _M.url_encode(str)
    str = string.gsub(str, "([^%w%-%.%_%~])",
        function(c) return string.format("%%%02X", string.byte(c)) end)
    return str
end

-- Base64 URL Safe编码
function _M.base64_url_safe_encode(str)
    local b64 = ngx.encode_base64(str)
    -- 转换为URL safe格式
    b64 = string.gsub(b64, "+", "-")
    b64 = string.gsub(b64, "/", "_")
    b64 = string.gsub(b64, "=", "")  -- 移除padding
    return b64
end

-- 生成PKCE challenge（使用SHA-256，与JS版本保持一致）
function _M.generate_pkce_challenge(verifier)
    local sha256 = resty_sha256:new()
    sha256:update(verifier)
    local hash = sha256:final()
    return _M.base64_url_safe_encode(hash)
end

-- 创建目录（递归）
local function create_directory(dir_path)
    local cmd = "mkdir -p " .. dir_path
    local result = os.execute(cmd)
    return result == 0
end

-- 保存JSON数据到文件
function _M.write_json_to_file(file_path, json_data)
    if not file_path or not json_data then
        ngx.log(ngx.ERR, "Missing file_path or json_data")
        return false
    end
    
    -- 尝试直接打开文件
    local file = io.open(file_path, "w")
    if not file then
        -- 如果失败，尝试创建目录
        local dir_path = string.match(file_path, "(.*/)")
        if dir_path then
            if create_directory(dir_path) then
                -- 重新尝试打开文件
                file = io.open(file_path, "w")
            end
        end
        
        if not file then
            ngx.log(ngx.ERR, "Failed to open file for writing: ", file_path)
            return false
        end
    end
    
    local ok, json_str = pcall(cjson.encode, json_data)
    if not ok then
        ngx.log(ngx.ERR, "Failed to encode data to JSON")
        file:close()
        return false
    end
    
    file:write(json_str)
    file:close()
    return true
end

-- 从文件加载JSON数据
function _M.load_json_from_file(file_path)
    if not file_path then
        ngx.log(ngx.ERR, "Missing file_path")
        return nil
    end
    
    local file = io.open(file_path, "r")
    if not file then
        return nil
    end
    
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        return nil
    end
    
    local ok, json_data = pcall(cjson.decode, content)
    if not ok then
        ngx.log(ngx.WARN, "Failed to decode JSON from file: ", file_path)
        return nil
    end
    
    return json_data
end

return _M