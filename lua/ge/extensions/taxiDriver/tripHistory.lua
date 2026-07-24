local M = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

local function money(value)
  return math.floor(math.max(0, tonumber(value) or 0) * 100 + 0.5) / 100
end

local function text(value, maximum)
  local result = tostring(value or "")
  if #result > maximum then result = result:sub(1, maximum) end
  return result
end

function M.snapshotPenalties(events)
  local result = {}
  for _, event in ipairs(type(events) == "table" and events or {}) do
    if type(event) == "table" and #result < 24 then
      result[#result + 1] = {
        kind = text(event.kind, 40),
        detail = text(event.detail, 180),
        penalty = math.max(0, tonumber(event.penalty) or 0),
        fareAmount = math.max(0, tonumber(event.fareAmount) or 0)
      }
    end
  end
  return result
end

function M.sanitizePenalties(events)
  return M.snapshotPenalties(events)
end

function M.sanitizeRandomEvents(events)
  local result = {}
  for _, event in ipairs(type(events) == "table" and events or {}) do
    if type(event) == "table" and #result < 8 then
      result[#result + 1] = {
        kind = text(event.kind, 40),
        status = text(event.status, 60),
        amount = math.max(0, tonumber(event.amount) or 0)
      }
    end
  end
  return result
end

function M.record(progress, entry, state, isValidEmoji)
  progress.sequence = math.max(0, math.floor(tonumber(progress.sequence) or 0)) + 1
  local timestamp = os.time()
  local passengerName = text(entry.passengerName, 160):gsub("^%s+", ""):gsub("%s+$", "")
  if passengerName == "" then passengerName = "Passenger" end
  local profileRating = clamp(entry.profileRating or state.rating or 5, 0, 5)
  local outcome = tostring(entry.outcome or "completed")
  progress.reviews[#progress.reviews + 1] = {
    id = progress.sequence,
    passengerName = passengerName,
    emoji = isValidEmoji(entry.emoji) and entry.emoji or "😐",
    quality = clamp(entry.quality, 0, 100),
    fare = money(entry.fare),
    rating = profileRating,
    orderRating = clamp(entry.orderRating or entry.profileRating or 0, 0, 5),
    usedAutopilot = entry.usedAutopilot == true,
    penalties = M.snapshotPenalties(entry.penalties),
    randomEvents = M.sanitizeRandomEvents(entry.randomEvents),
    timestamp = timestamp,
    outcome = outcome
  }
  progress.ratingHistory[#progress.ratingHistory + 1] = {
    index = progress.sequence, value = money(clamp(state.rating or 5, 0, 5)), timestamp = timestamp
  }
  progress.balanceHistory[#progress.balanceHistory + 1] = {
    index = progress.sequence, value = money(state.balance), timestamp = timestamp
  }
  if outcome == "completed" or outcome == "delivery" then
    if entry.usedAutopilot == true then progress.aiRideCount = (progress.aiRideCount or 0) + 1 end
    progress.aiRideHistory[#progress.aiRideHistory + 1] = {
      index = progress.sequence, value = progress.aiRideCount or 0, timestamp = timestamp
    }
  end
  return progress
end

return M
