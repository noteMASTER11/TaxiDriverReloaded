package.path = "lua/ge/extensions/?.lua;" .. package.path
log = function() end

local saved = {}
FS = {fileExists = function(_, path) return saved[path] ~= nil end,
  directoryExists = function() return true end}
jsonReadFile = function(path) return saved[path] end
jsonWriteFile = function(path, value) saved[path] = value end

local trackerModule = require("taxiDriver/shiftTracker")
local history = require("taxiDriver/shiftHistory")
local tracker = trackerModule.new(nil)
tracker:start()
tracker:recordFuelCost(25.12)
assert(tracker:getHud().current.netIncome == -25.12,
  "fuel purchased before the first fare must count as a shift loss")
tracker:recordRide(10, 5, 0, false)
tracker:recordRepairCost(40.25)
local finished = tracker:finish()
assert(finished.netIncome == -55.37, "shift expenses may exceed gross income")
assert(tracker:getHud().last.netIncome == -55.37, "the last-shift HUD must preserve the loss")
assert(trackerModule.new(finished):getHud().last.netIncome == -55.37,
  "reloading progress must preserve the last-shift loss")

history.load("test")
local id = history.begin({modelKey = "etki", configKey = "2400_A"},
  {energyType = "gasoline", percent = 50}, finished)
history.finish(nil, nil, finished)
assert(history.get(id).summary.netIncome == -55.37, "shift history must preserve the loss")
assert(history.buildHud().items[1].netIncome == -55.37, "history HUD must preserve the loss")
history.load("test")
assert(history.get(id).summary.netIncome == -55.37, "history save/load must preserve the loss")

local sanitized = trackerModule.sanitize({netIncome = -5.123, grossIncome = -1,
  fuelCost = -2, repairCost = -3, penaltyLoss = -4})
assert(sanitized.netIncome == -5.12, "signed net income still rounds to cents")
assert(sanitized.grossIncome == 0 and sanitized.fuelCost == 0 and
  sanitized.repairCost == 0 and sanitized.penaltyLoss == 0,
  "income and expense components must retain their nonnegative validation")

print("TaxiDriver negative shift income regressions passed")
