-- Incremental coroutine runner for expensive road-graph offer searches.
-- A search explicitly yields between graph candidates, keeping the work per
-- simulation tick bounded while allowing the dispatcher to take longer.
local M = {}

function M.create(factory, stepInterval, options)
  if type(factory) ~= "function" then return nil end
  options = options or {}
  return {
    thread = coroutine.create(factory),
    stepInterval = math.max(0, tonumber(stepInterval) or 0),
    cooldown = 0,
    maxResumes = math.max(1, math.min(32, math.floor(tonumber(options.maxResumes) or 16))),
    timeBudgetSeconds = math.max(0.0001, tonumber(options.timeBudgetSeconds) or 0.001),
    maxJobSeconds = math.max(0.01, tonumber(options.maxJobSeconds) or 8),
    clock = options.clock or os.clockhp or os.clock,
    elapsedSim = 0,
    totalResumes = 0,
    lastStepResumes = 0,
    lastStepSeconds = 0
  }
end

function M.step(job, dtSim)
  if not job or not job.thread then return "error", "Missing generation job" end
  job.lastStepResumes, job.lastStepSeconds = 0, 0
  dtSim = math.max(0, tonumber(dtSim) or 0)
  if dtSim == 0 then return "pending" end
  job.elapsedSim = job.elapsedSim + dtSim
  if job.elapsedSim > job.maxJobSeconds then return "error", "Offer generation timed out" end
  job.cooldown = math.max(0, (job.cooldown or 0) - dtSim)
  if job.cooldown > 0 then return "pending" end

  local started = job.clock()
  for _ = 1, job.maxResumes do
    -- The budget is cooperative: one native routing call cannot be preempted.
    -- Check elapsed time between every explicitly bounded search operation.
    local ok, firstResult, secondResult = coroutine.resume(job.thread)
    job.totalResumes = job.totalResumes + 1
    job.lastStepResumes = job.lastStepResumes + 1
    job.lastStepSeconds = math.max(0, job.clock() - started)
    if not ok then return "error", firstResult end
    if coroutine.status(job.thread) == "dead" then
      return "complete", firstResult, secondResult
    end
    if job.lastStepSeconds >= job.timeBudgetSeconds then break end
  end
  job.cooldown = job.stepInterval
  return "pending"
end

function M.yield()
  local running, isMain = coroutine.running()
  if running and not isMain then coroutine.yield() end
end

return M
