-- Incremental coroutine runner for expensive road-graph offer searches.
-- A search explicitly yields between graph candidates, keeping the work per
-- simulation tick bounded while allowing the dispatcher to take longer.
local M = {}

function M.create(factory, stepInterval)
  if type(factory) ~= "function" then return nil end
  return {
    thread = coroutine.create(factory),
    stepInterval = math.max(0, tonumber(stepInterval) or 0),
    cooldown = 0
  }
end

function M.step(job, dtSim)
  if not job or not job.thread then return "error", "Missing generation job" end
  job.cooldown = math.max(0, (job.cooldown or 0) - math.max(0, tonumber(dtSim) or 0))
  if job.cooldown > 0 then return "pending" end

  local ok, firstResult, secondResult = coroutine.resume(job.thread)
  if not ok then return "error", firstResult end
  if coroutine.status(job.thread) == "dead" then
    return "complete", firstResult, secondResult
  end
  job.cooldown = job.stepInterval
  return "pending"
end

function M.yield()
  local running, isMain = coroutine.running()
  if running and not isMain then coroutine.yield() end
end

return M
