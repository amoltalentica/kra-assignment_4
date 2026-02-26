--[[
  Custom Token Validator & Header Injector Plugin for Kong

  Purpose: Custom request/response header injection (hackathon requirement).
  - Injects audit/tracing headers into upstream requests
  - Injects platform-identity headers into downstream responses
  - Logs token validation events for observability

  Schema is defined in schema.lua (handler + schema split required by Kong).
  Version: 1.0.0
]]--

local plugin = {
  PRIORITY = 999,  -- runs after JWT plugin (PRIORITY 1005)
  VERSION  = "1.0.0",
}

-- ──────────────────────────────────────────────────────────────────
-- access phase: inject headers into the upstream request
-- ──────────────────────────────────────────────────────────────────
function plugin:access(config)
  local service_name = config.service_name or "secure-api-platform"
  local client_ip    = kong.client.get_forwarded_ip() or "unknown"
  local request_path = kong.request.get_path()         or "/"
  local method       = kong.request.get_method()       or "UNKNOWN"

  kong.service.request.set_header("X-Kong-Gateway",      service_name)
  kong.service.request.set_header("X-Gateway-Version",   plugin.VERSION)
  kong.service.request.set_header("X-Request-Timestamp", tostring(os.time()))
  kong.service.request.set_header("X-Client-IP",         client_ip)
  kong.service.request.set_header("X-RateLimit-Policy",  "10-per-minute")
  kong.service.request.set_header("X-Forwarded-By",      "kong-gateway")

  kong.log.debug("custom-token-validator: ", method, " ", request_path, " from ", client_ip)
end

-- ──────────────────────────────────────────────────────────────────
-- header_filter phase: inject headers into the downstream response
-- ──────────────────────────────────────────────────────────────────
function plugin:header_filter(config)
  if config.inject_headers then
    local service_name = config.service_name or "secure-api-platform"
    kong.response.set_header("X-Kong-Gateway",         service_name)
    kong.response.set_header("X-API-Platform-Version", plugin.VERSION)
    kong.response.set_header("X-Powered-By",           "Kong-OSS-3.5")
    kong.response.set_header("X-Validation-Timestamp", tostring(os.time()))
  end
end

return plugin
