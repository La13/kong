local resty_lock = require "resty.lock"
local cache = ngx.shared.cache
local ngx_log = ngx.log

local CACHE_KEYS = {
  APIS = "apis",
  CONSUMERS = "consumers",
  PLUGINS = "plugins",
  BASICAUTH_CREDENTIAL = "basicauth_credentials",
  HMACAUTH_CREDENTIAL = "hmacauth_credentials",
  KEYAUTH_CREDENTIAL = "keyauth_credentials",
  OAUTH2_CREDENTIAL = "oauth2_credentials",
  JWTAUTH_CREDENTIAL = "jwtauth_credentials",
  OAUTH2_TOKEN = "oauth2_token",
  ACLS = "acls",
  SSL = "ssl",
  REQUESTS = "requests",
  AUTOJOIN_RETRIES = "autojoin_retries",
  TIMERS = "timers",
  ALL_APIS_BY_DIC = "ALL_APIS_BY_DIC",
  LDAP_CREDENTIAL = "ldap_credentials",
  BOT_DETECTION = "bot_detection"
}

local _M = {}

-- Shared Dictionary

function _M.sh_set(key, value, exptime)
  return cache:set(key, value, exptime or 0)
end

function _M.sh_get(key)
  return cache:get(key)
end

function _M.sh_incr(key, value)
  return cache:incr(key, value)
end

function _M.sh_delete(key)
  cache:delete(key)
end

function _M.sh_delete_all()
  cache:flush_all() -- This does not free up the memory, only marks the items as expired
  cache:flush_expired() -- This does actually remove the elements from the memory
end

-- Local Cache

local DATA = {}

function _M.set(key, value)
  DATA[key] = value
end

function _M.get(key)
  return DATA[key]
end

function _M.incr(key, value)
  local n = DATA[key]
  if not tonumber(n) then
    return nil, "Counter not initialized"
  end
  local newval = n + value
  DATA[key] = newval
  return newval
end

function _M.delete(key)
  DATA[key] = nil
end

function _M.delete_all()
  DATA = {}
end

--[[
function _M.incr(key, value)
  local n = _M.get(key)
  if tonumber(n) == nil then
    return nil, "Counter not initialized"
  end

  local result = n + value
  _M.set(result)
  return result
end
--]]

function _M.get_or_set(key, cb)
  -- Try to get the value from the cache
  local value = _M.get(key)
  if value then return value end

  local lock, err = resty_lock:new("cache_locks", {
    exptime = 10
  })
  if not lock then
    ngx_log(ngx.ERR, "could not create lock: ", err)
    return
  end

  -- The value is missing, acquire a lock
  local elapsed, err = lock:lock(ngx.worker.id()..key)
  if not elapsed then
    ngx_log(ngx.ERR, "failed to acquire cache lock: ", err)
  end

  -- Lock acquired. Since in the meantime another worker may have
  -- populated the value we have to check again
  value = _M.get(key)
  if not value then
    -- Get from closure
    value = cb()
    if value then
      _M.set(key, value)
    end
  end

  local ok, err = lock:unlock()
  if not ok and err then
    ngx_log(ngx.ERR, "failed to unlock: ", err)
  end
  
  return value
end

-- Utility Functions

function _M.requests_key()
  return CACHE_KEYS.REQUESTS
end

function _M.autojoin_retries_key()
  return CACHE_KEYS.AUTOJOIN_RETRIES
end

function _M.api_key(host)
  return CACHE_KEYS.APIS..":"..host
end

function _M.consumer_key(id)
  return CACHE_KEYS.CONSUMERS..":"..id
end

function _M.plugin_key(name, api_id, consumer_id)
  return CACHE_KEYS.PLUGINS..":"..name..(api_id and ":"..api_id or "")..(consumer_id and ":"..consumer_id or "")
end

function _M.basicauth_credential_key(username)
  return CACHE_KEYS.BASICAUTH_CREDENTIAL..":"..username
end

function _M.oauth2_credential_key(client_id)
  return CACHE_KEYS.OAUTH2_CREDENTIAL..":"..client_id
end

function _M.oauth2_token_key(access_token)
  return CACHE_KEYS.OAUTH2_TOKEN..":"..access_token
end

function _M.keyauth_credential_key(key)
  return CACHE_KEYS.KEYAUTH_CREDENTIAL..":"..key
end

function _M.hmacauth_credential_key(username)
  return CACHE_KEYS.HMACAUTH_CREDENTIAL..":"..username
end

function _M.jwtauth_credential_key(secret)
  return CACHE_KEYS.JWTAUTH_CREDENTIAL..":"..secret
end

function _M.ldap_credential_key(username)
  return CACHE_KEYS.LDAP_CREDENTIAL.."/"..username
end

function _M.acls_key(consumer_id)
  return CACHE_KEYS.ACLS..":"..consumer_id
end

function _M.ssl_data(api_id)
  return CACHE_KEYS.SSL..":"..api_id
end

function _M.bot_detection_key(key)
  return CACHE_KEYS.BOT_DETECTION..":"..key
end

function _M.all_apis_by_dict_key()
  return CACHE_KEYS.ALL_APIS_BY_DIC
end

return _M
