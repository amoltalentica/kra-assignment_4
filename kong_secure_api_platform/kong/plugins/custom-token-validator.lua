--[[
  Custom Token Validator Plugin for Kong
  
  This plugin provides advanced token validation including:
  - Additional JWT claims validation
  - Token expiry time checking with custom logic
  - Request header injection with validation metadata
  - Structured logging of token validation events
  
  Version: 1.0.0
]]--

local kong = kong
local cjson = require "cjson"
local jwt_decoder = require "kong.plugins.jwt.jwt_parser"

local plugin = {
  PRIORITY = 999,  -- Execute after JWT plugin (1005)
  VERSION = "1.0.0",
}

-- Plugin schema
local schema = {
  name = "custom-token-validator",
  fields = {
    { config = {
        type = "record",
        fields = {
          { required_claims = {
              type = "array",
              elements = { type = "string" },
              default = { "sub", "exp" },
          }},
          { max_token_age_seconds = {
              type = "number",
              default = 3600,  -- 1 hour
          }},
          { inject_headers = {
              type = "boolean",
              default = true,
          }},
          { log_tokens = {
              type = "boolean",
              default = true,
          }},
        },
    }},
  },
}

-- Extract JWT token from Authorization header
local function extract_token()
  local authorization = kong.request.get_header("Authorization")
  if not authorization then
    return nil, "missing Authorization header"
  end
  
  local parts = {}
  for part in authorization:gmatch("%S+") do
    table.insert(parts, part)
  end
  
  if #parts ~= 2 or parts[1]:lower() ~= "bearer" then
    return nil, "invalid Authorization header format"
  end
  
  return parts[2], nil
end

-- Validate JWT token structure and claims
local function validate_token(token, config)
  if not token then
    return false, "token is required"
  end
  
  -- Parse JWT token
  local jwt, err = jwt_decoder:new(token)
  if err then
    kong.log.warn("JWT parsing error: ", err)
    return false, "invalid token format: " .. err
  end
  
  local claims = jwt.claims
  
  -- Validate required claims
  for _, claim_name in ipairs(config.required_claims) do
    if not claims[claim_name] then
      kong.log.warn("Missing required claim: ", claim_name)
      return false, "missing required claim: " .. claim_name
    end
  end
  
  -- Validate token age (time since issuance)
  if claims.iat then
    local current_time = os.time()
    local token_age = current_time - claims.iat
    
    if token_age > config.max_token_age_seconds then
      kong.log.warn("Token age exceeded: ", token_age, " seconds")
      return false, "token is too old"
    end
    
    if token_age < 0 then
      kong.log.warn("Token issued in future: ", claims.iat)
      return false, "token issued in future"
    end
  end
  
  -- Validate expiration (exp claim)
  if claims.exp then
    local current_time = os.time()
    if current_time >= claims.exp then
      kong.log.warn("Token expired at: ", claims.exp)
      return false, "token has expired"
    end
  end
  
  -- Additional custom validations can be added here
  -- For example: check specific claim values, validate audience, etc.
  
  return true, claims
end

-- Plugin access phase
function plugin:access(config)
  -- Get the current route to check if it requires authentication
  local route = kong.router.get_route()
  if not route then
    return
  end
  
  -- Extract token from request
  local token, err = extract_token()
  
  -- If no token is present, let the JWT plugin handle it
  if not token then
    kong.log.debug("No token found, skipping custom validation")
    return
  end
  
  -- Validate token with custom logic
  local valid, result = validate_token(token, config)
  
  if not valid then
    kong.log.warn("Token validation failed: ", result)
    -- Add custom header to indicate validation failure reason
    if config.inject_headers then
      kong.response.set_header("X-Token-Validation-Error", result)
    end
    -- Don't return error here; let JWT plugin handle final auth decision
    return
  end
  
  -- Token is valid - inject custom headers
  if config.inject_headers and type(result) == "table" then
    kong.service.request.set_header("X-Token-Subject", result.sub or "unknown")
    kong.service.request.set_header("X-Token-Validated", "true")
    kong.service.request.set_header("X-Token-Issued-At", tostring(result.iat or ""))
    
    if result.email then
      kong.service.request.set_header("X-Token-Email", result.email)
    end
  end
  
  -- Log token validation event
  if config.log_tokens then
    local log_data = {
      event = "token_validated",
      subject = result.sub,
      email = result.email,
      issued_at = result.iat,
      expires_at = result.exp,
      route = route.name,
      method = kong.request.get_method(),
      path = kong.request.get_path(),
      client_ip = kong.client.get_forwarded_ip(),
      timestamp = os.time(),
    }
    kong.log.info("Token validation: ", cjson.encode(log_data))
  end
end

-- Plugin header_filter phase (add custom response headers)
function plugin:header_filter(config)
  if config.inject_headers then
    kong.response.set_header("X-Token-Validator", "custom-v1.0.0")
    kong.response.set_header("X-Validation-Time", tostring(os.time()))
  end
end

-- Return plugin
return plugin
