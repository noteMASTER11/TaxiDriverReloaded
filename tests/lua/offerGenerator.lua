package.path = "lua/ge/extensions/?.lua;" .. package.path
local generator = require("taxiDriver/offerGenerator")
local now = 0
local function clock() return now end
local count = 0
local job = generator.create(function()
  for _ = 1, 40 do count = count + 1; generator.yield() end
  return "offer", "detail"
end, 0.02, {maxResumes = 16, timeBudgetSeconds = 0.001, clock = clock})
assert(generator.step(job, 0) == "pending" and count == 0, "paused simulation must not advance work")
assert(generator.step(job, 0.02) == "pending" and count == 16, "one tick must batch cheap yields")
assert(generator.step(job, 0.01) == "pending" and count == 16, "batch cooldown must remain effective")
assert(generator.step(job, 0.01) == "pending" and count == 32)
local status, offer, detail = generator.step(job, 0.02)
assert(status == "complete" and offer == "offer" and detail == "detail")
assert(job.totalResumes == 41 and job.lastStepResumes == 9, "resume counters must measure actual work")

count = 0
job = generator.create(function()
  while true do count = count + 1; now = now + 0.0006; generator.yield() end
end, 0, {maxResumes = 16, timeBudgetSeconds = 0.001, clock = clock})
assert(generator.step(job, 0.016) == "pending" and count == 2, "elapsed budget must stop another resume")
assert(job.lastStepSeconds >= 0.001, "record measured work duration")

job = generator.create(function() while true do generator.yield() end end, 0,
  {maxJobSeconds = 0.05, clock = clock})
assert(generator.step(job, 0.03) == "pending")
local errorStatus, message = generator.step(job, 0.03)
assert(errorStatus == "error" and message:find("timed out"), "impossible jobs must terminate")

job = generator.create(function() error("route failure") end, 0, {clock = clock})
errorStatus, message = generator.step(job, 0.016)
assert(errorStatus == "error" and message:find("route failure"), "errors must propagate")
print("TaxiDriver offer generation budget regressions passed")
