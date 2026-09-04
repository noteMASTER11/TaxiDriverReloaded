local M = {}

-- The road graph has no tunnel flag. BeamNG's droneChase camera uses an
-- upward static ray to identify tunnel/overpass ceilings; use the same probe
-- so random road points under cover cannot become passenger stops.
function M.isOpenAir(pos)
  if not pos then return false end
  if type(castRayStatic) ~= "function" then return true end
  local reach = 60
  local ok, distance = pcall(castRayStatic,
    vec3(pos.x, pos.y, pos.z + 1), vec3(0, 0, 1), reach)
  return ok and type(distance) == "number" and distance >= reach
end

function M.isOfferAllowed(offer)
  if not offer or not offer.pickup or not offer.destination then return false end
  if not M.isOpenAir(offer.pickup.pos) or not M.isOpenAir(offer.destination.pos) then return false end
  for _, stop in ipairs(offer.stops or {}) do
    if not M.isOpenAir(stop.pos) then return false end
  end
  return true
end

return M
