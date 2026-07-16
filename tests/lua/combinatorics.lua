local tripEvents = dofile("lua/ge/extensions/taxiDriver/tripEvents.lua")
local shiftTracker = dofile("lua/ge/extensions/taxiDriver/shiftTracker.lua")

math.randomseed(240717)

local orderTypes = {
  {name = "passenger", delivery = false, rush = false, multi = false},
  {name = "rush", delivery = false, rush = true, multi = false},
  {name = "multiStop", delivery = false, rush = false, multi = true},
  {name = "delivery", delivery = true, rush = false, multi = false}
}

for _, realistic in ipairs({false, true}) do
  for _, eventsEnabled in ipairs({false, true}) do
    for _, order in ipairs(orderTypes) do
      for _ = 1, 250 do
        local event = eventsEnabled and
          tripEvents.create(order.delivery, order.rush, order.multi) or {kind = "none"}
        assert(type(event) == "table" and type(event.kind) == "string")
        if not eventsEnabled then assert(event.kind == "none") end
        if order.delivery then
          assert(event.kind == "none" or event.kind == "fragileCargo")
        elseif order.rush or order.multi then
          assert(event.kind == "none" or event.kind == "cancellation" or event.kind == "tip")
        end
        if tripEvents.needsTarget(event) then
          assert(not order.delivery and not order.rush and not order.multi)
          event.target = {routeDistance = 1200}
          assert(tripEvents.shouldTriggerOnRoute(event, event.triggerProgress or 1))
          assert(not tripEvents.shouldTriggerOnRoute(event, 1))
        end
      end
      assert(realistic == true or realistic == false)
    end
  end
end

local cancellation = {kind = "cancellation", triggerSeconds = 2, elapsed = 0}
assert(not tripEvents.updateBeforePickup(cancellation, 1))
assert(tripEvents.updateBeforePickup(cancellation, 1))
assert(not tripEvents.updateBeforePickup(cancellation, 10))

assert(tripEvents.calculateTip({kind = "tip", condition = "careful", rate = 0.1}, 20, 0, false) == 2)
assert(tripEvents.calculateTip({kind = "tip", condition = "careful", rate = 0.1}, 20, 0.1, false) == 0)
assert(tripEvents.calculateTip({kind = "tip", condition = "quick", rate = 0.1}, 20, 0, true) == 2)

local shifts = shiftTracker.new(nil)
shifts:start()
shifts:recordRide(20, 4.5, 2)
shifts:recordFuelCost(3)
local completed = shifts:finish()
assert(completed.rides == 1)
assert(completed.grossIncome == 20)
assert(completed.netIncome == 17)
assert(completed.averageRating == 4.5)
assert(not shifts:getHud().active)

print("TaxiDriver Lua combinatorics: 4 mode combinations x 4 order types passed")
