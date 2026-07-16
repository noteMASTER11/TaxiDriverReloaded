local M = {}

local function money(value)
  return math.floor(math.max(0, tonumber(value) or 0) * 100 + 0.5) / 100
end

local function snapshot(source)
  source = type(source) == "table" and source or {}
  return {
    startedAt = math.max(0, math.floor(tonumber(source.startedAt) or 0)),
    endedAt = math.max(0, math.floor(tonumber(source.endedAt) or 0)),
    rides = math.max(0, math.floor(tonumber(source.rides) or 0)),
    grossIncome = money(source.grossIncome),
    fuelCost = money(source.fuelCost),
    penaltyLoss = money(source.penaltyLoss),
    netIncome = money(source.netIncome),
    ratingTotal = math.max(0, tonumber(source.ratingTotal) or 0),
    averageRating = math.max(0, math.min(5, tonumber(source.averageRating) or 0))
  }
end

function M.new(lastShift)
  local service = {active = nil, last = snapshot(lastShift)}

  function service:start()
    self.active = snapshot({startedAt = os.time()})
  end

  function service:recordRide(fare, rating, penaltyLoss)
    if not self.active then return end
    self.active.rides = self.active.rides + 1
    self.active.grossIncome = money(self.active.grossIncome + math.max(0, tonumber(fare) or 0))
    self.active.penaltyLoss = money(self.active.penaltyLoss + math.max(0, tonumber(penaltyLoss) or 0))
    self.active.ratingTotal = self.active.ratingTotal + math.max(0, math.min(5, tonumber(rating) or 0))
    self.active.averageRating = self.active.ratingTotal / math.max(1, self.active.rides)
    self.active.netIncome = money(self.active.grossIncome - self.active.fuelCost)
  end

  function service:recordFuelCost(cost)
    if not self.active then return end
    self.active.fuelCost = money(self.active.fuelCost + math.max(0, tonumber(cost) or 0))
    self.active.netIncome = money(self.active.grossIncome - self.active.fuelCost)
  end

  function service:finish()
    if not self.active then return self.last end
    self.active.endedAt = os.time()
    self.active.netIncome = money(self.active.grossIncome - self.active.fuelCost)
    self.last = snapshot(self.active)
    self.active = nil
    return self.last
  end

  function service:getHud()
    return {active = self.active ~= nil, current = snapshot(self.active), last = snapshot(self.last)}
  end

  return service
end

M.sanitize = snapshot
return M
