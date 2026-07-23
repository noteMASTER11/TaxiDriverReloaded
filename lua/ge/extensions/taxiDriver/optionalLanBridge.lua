local logger = require("taxiDriver/logger")

local M = {}
local implementation = nil
local loadAttempted = false
local loadError = ""
local requestedEnabled = false
local pendingPerformance = nil
local pendingState = nil

local function invoke(service, name, fallback, ...)
  local callback = service and service[name] or nil
  if type(callback) ~= "function" then return fallback end
  local ok, first, second = pcall(callback, ...)
  if not ok then
    logger.error("lan", "optional_call_failed", {
      operation = name, reason = tostring(first)
    })
    return fallback
  end
  return first, second
end

local function ensureLoaded()
  if implementation then return implementation end
  if loadAttempted then return nil end
  loadAttempted = true
  local ok, value = pcall(require, "taxiDriver/lanBridge")
  if not ok or type(value) ~= "table" then
    loadError = tostring(value or "LAN module unavailable")
    logger.error("lan", "optional_module_unavailable", {reason = loadError})
    return nil
  end
  implementation = value
  if pendingPerformance then
    invoke(implementation, "setPerformanceOptions", nil, pendingPerformance)
  end
  if pendingState then invoke(implementation, "setState", nil, pendingState) end
  return implementation
end

function M.setEnabled(value)
  requestedEnabled = value == true
  if not requestedEnabled then
    if implementation then invoke(implementation, "setEnabled", false, false) end
    if not implementation then
      loadAttempted = false
      loadError = ""
    end
    return true
  end
  local service = ensureLoaded()
  return invoke(service, "setEnabled", false, true)
end

function M.setPerformanceOptions(options)
  pendingPerformance = type(options) == "table" and options or {}
  if implementation then
    invoke(implementation, "setPerformanceOptions", nil, pendingPerformance)
  end
end

function M.setState(state)
  pendingState = type(state) == "table" and state or {}
  if implementation then invoke(implementation, "setState", nil, pendingState) end
end

function M.getStatus()
  if implementation then
    return invoke(implementation, "getStatus", nil) or {
      enabled = false, connected = 0, bridgeReady = 0,
      bridgeError = "LAN status unavailable", address = "127.0.0.1", port = 8085, url = ""
    }
  end
  return {
    enabled = false,
    connected = 0,
    bridgeReady = 0,
    bridgeError = requestedEnabled and loadError or "",
    address = "127.0.0.1",
    port = 8085,
    url = ""
  }
end

function M.update(dtReal)
  return invoke(implementation, "update", nil, dtReal)
end

function M.consumeStatusChanged()
  return invoke(implementation, "consumeStatusChanged", false)
end

function M.isConnected()
  return invoke(implementation, "isConnected", false)
end

function M.externalHeartbeat(...)
  return invoke(implementation, "externalHeartbeat", false, ...)
end

function M.requestExternalMap(...)
  return invoke(implementation, "requestExternalMap", nil, ...)
end

function M.setExternalView(...)
  return invoke(implementation, "setExternalView", false, ...)
end

function M.stop()
  requestedEnabled = false
  invoke(implementation, "stop", nil)
end

return M
