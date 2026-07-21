local M = {}

local prefix = "[TaxiDriver]"
local enabledProvider = function() return true end
local eventSink = nil
local unpackValues = unpack or table.unpack
local defaultOperations = {
  "startMode", "openVehicleSelector", "toggleAutopilot", "acceptOrder", "acceptNextOffer", "expireNextOffer",
  "stopMode", "confirmDriverAbandonment", "purchaseRealisticFuel", "requestFuelStop",
  "completeFuelStop", "cancelFuelStop", "saveDriverProfile", "setDifficulty", "saveSettings",
  "disableExternalPhone", "setExternalPhoneView", "cheatSetRating", "cheatSetEnergyPercent",
  "cheatAddMoney", "cheatAddRandomReview", "cheatResetProgress", "onVehicleSwitched",
  "onVehicleResetted", "onClientStartMission", "onUiChangedState", "onExtensionLoaded",
  "onClientEndMission", "onExtensionUnloaded", "onDeserialized"
}

local function isEnabled()
  local ok, value = pcall(enabledProvider)
  return not ok or value ~= false
end

local function compact(value)
  local valueType = type(value)
  if valueType == "string" then
    value = value:gsub("[%c]+", " ")
    if #value > 160 then value = value:sub(1, 157) .. "..." end
    return string.format("%q", value)
  end
  if valueType == "number" or valueType == "boolean" then return tostring(value) end
  if value == nil then return "nil" end
  return "<" .. valueType .. ">"
end

local function fieldsToText(fields)
  if type(fields) ~= "table" then return "" end
  local keys = {}
  for key in pairs(fields) do keys[#keys + 1] = tostring(key) end
  table.sort(keys)
  local values = {}
  for _, key in ipairs(keys) do values[#values + 1] = key .. "=" .. compact(fields[key]) end
  return #values > 0 and (" " .. table.concat(values, " ")) or ""
end

local function emit(level, area, event, fields, always)
  if type(eventSink) == "function" then
    pcall(eventSink, level, area, event, fields)
  end
  if not always and not isEnabled() then return end
  log(level, "taxiDriver", string.format(
    "%s area=%s event=%s%s",
    prefix,
    tostring(area or "core"),
    tostring(event or "unknown"),
    fieldsToText(fields)
  ))
end

function M.setEnabledProvider(provider)
  enabledProvider = type(provider) == "function" and provider or enabledProvider
end

function M.setEventSink(sink)
  eventSink = type(sink) == "function" and sink or nil
end

function M.debug(area, event, fields) emit("D", area, event, fields, false) end
function M.info(area, event, fields) emit("I", area, event, fields, false) end
function M.warn(area, event, fields) emit("W", area, event, fields, true) end
function M.error(area, event, fields) emit("E", area, event, fields, true) end
function M.isEnabled() return isEnabled() end

local lastRuntimeSignature = ""
function M.observeRuntime(state, trip, offerCount)
  state = type(state) == "table" and state or {}
  trip = type(trip) == "table" and trip or nil
  local fields = {
    active = state.active == true,
    activeVehicleId = state.activeVehicleId,
    offerCount = tonumber(offerCount) or 0,
    phase = state.phase or "inactive",
    tripId = trip and trip.id or nil,
    tripType = trip and (trip.isDelivery and "delivery" or "passenger") or nil
  }
  local signature = table.concat({
    tostring(fields.active), tostring(fields.activeVehicleId), tostring(fields.offerCount),
    tostring(fields.phase), tostring(fields.tripId), tostring(fields.tripType)
  }, "|")
  if signature == lastRuntimeSignature then return end
  lastRuntimeSignature = signature
  M.info("runtime", "state_changed", fields)
end

local function pack(...)
  return {n = select("#", ...), ...}
end

function M.attachOperations(module, names)
  for _, name in ipairs(names or defaultOperations) do
    local original = module[name]
    if type(original) == "function" then
      module[name] = function(...)
        if not isEnabled() then return original(...) end
        local started = type(os.clockhp) == "function" and os.clockhp() or os.clock()
        local arguments = pack(...)
        local fields = {argumentCount = arguments.n}
        for index = 1, math.min(arguments.n, 3) do fields["arg" .. index] = arguments[index] end
        M.info("operation", name .. ".begin", fields)
        local results = pack(original(...))
        local finished = type(os.clockhp) == "function" and os.clockhp() or os.clock()
        M.info("operation", name .. ".end", {
          durationMs = math.floor((finished - started) * 1000000 + 0.5) / 1000,
          resultCount = results.n
        })
        return unpackValues(results, 1, results.n)
      end
    end
  end
end

return M
