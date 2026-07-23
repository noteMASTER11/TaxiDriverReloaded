local logger = require("taxiDriver/logger")

local M = {}

local function now()
  return type(os.clockhp) == "function" and os.clockhp() or os.clock()
end

function M.new(options)
  options = type(options) == "table" and options or {}
  local retrySeconds = math.max(0.1, tonumber(options.retrySeconds) or 1)
  local failures = {}
  local service = {}

  local function recordFailure(name, errorMessage)
    local previous = failures[name]
    local count = previous and previous.count + 1 or 1
    failures[name] = {count = count, retryAt = now() + retrySeconds}
    logger.error("runtime", "subsystem_failed", {
      subsystem = name,
      failureCount = count,
      reason = tostring(errorMessage or "unknown")
    })
  end

  function service:call(name, callback, ...)
    name = tostring(name or "unknown")
    if type(callback) ~= "function" then return false, nil, "callbackUnavailable" end
    local failure = failures[name]
    if failure and now() < failure.retryAt then return false, nil, "circuitOpen" end
    local ok, first, second, third = pcall(callback, ...)
    if not ok then
      recordFailure(name, first)
      return false, nil, first
    end
    failures[name] = nil
    return true, first, second, third
  end

  function service:cleanup(name, callback, ...)
    if type(callback) ~= "function" then return false end
    local ok, errorMessage = pcall(callback, ...)
    if not ok then recordFailure(tostring(name or "cleanup"), errorMessage) end
    return ok
  end

  function service:reset()
    failures = {}
  end

  return service
end

return M
