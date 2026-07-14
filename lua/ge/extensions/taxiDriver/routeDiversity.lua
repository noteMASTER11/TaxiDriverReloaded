-- Pure helpers for keeping generated A/B route pairs spatially varied.
-- The main extension owns the history and decides when strict diversity is
-- required; this module only compares endpoint cells and distances.
local M = {}

local function endpoint(offer, key)
  return offer and offer[key] and offer[key].pos or nil
end

local function cellKey(pos, cellSize)
  if not pos then return "missing" end
  cellSize = math.max(1, tonumber(cellSize) or 400)
  return string.format(
    "%d:%d",
    math.floor((tonumber(pos.x) or 0) / cellSize),
    math.floor((tonumber(pos.y) or 0) / cellSize)
  )
end

function M.routeKey(offer, cellSize)
  local pointA = cellKey(endpoint(offer, "pickup"), cellSize)
  local pointB = cellKey(endpoint(offer, "destination"), cellSize)
  -- Treat A→B and B→A as the same repeated pair. Driving the same two
  -- neighbourhoods in reverse still feels like the same route.
  if pointA > pointB then pointA, pointB = pointB, pointA end
  return pointA .. "|" .. pointB
end

local function isNear(candidatePos, reference, separation)
  if not candidatePos or not reference then return false end
  for _, key in ipairs({"pickup", "destination"}) do
    local referencePos = endpoint(reference, key)
    if referencePos and candidatePos:distance(referencePos) < separation then return true end
  end
  return false
end

function M.isDiverse(candidate, activeOffers, recentRoutes, config, strictEndpoints)
  if not candidate or not candidate.pickup or not candidate.destination then return false end
  config = config or {}
  local cellSize = config.routeDiversityCellSize or 400
  local separation = math.max(0, config.routeDiversityEndpointSeparation or 280)
  local candidateKey = M.routeKey(candidate, cellSize)
  local pickupPos = endpoint(candidate, "pickup")
  local destinationPos = endpoint(candidate, "destination")

  local function conflicts(reference)
    if not reference then return false end
    if M.routeKey(reference, cellSize) == candidateKey then return true end
    if strictEndpoints and (
      isNear(pickupPos, reference, separation) or
      isNear(destinationPos, reference, separation)
    ) then return true end
    return false
  end

  for _, reference in ipairs(activeOffers or {}) do
    if conflicts(reference) then return false end
  end
  for _, reference in ipairs(recentRoutes or {}) do
    if conflicts(reference) then return false end
  end
  return true
end

function M.remember(history, offer, limit, cellSize)
  if type(history) ~= "table" or not offer or not offer.pickup or not offer.destination then
    return
  end
  cellSize = math.max(1, tonumber(cellSize) or 400)
  local key = M.routeKey(offer, cellSize)
  if history[#history] and M.routeKey(history[#history], cellSize) == key then return end
  table.insert(history, {
    pickup = {pos = offer.pickup.pos},
    destination = {pos = offer.destination.pos}
  })
  while #history > math.max(1, tonumber(limit) or 20) do table.remove(history, 1) end
end

return M
