package.path = "lua/ge/extensions/?.lua;" .. package.path
local reads, writes, pretty, failWrites = 0, 0, nil, false
local currentMap = "first"
local cacheSchema = 2
getCurrentLevelIdentifier = function() return currentMap end
log = function() end
FS = {directoryExists = function() return true end, directoryCreate = function() end,
  fileExists = function() return true end}
jsonReadFile = function()
  reads = reads + 1
  return {schemaVersion = cacheSchema, mapId = currentMap, routes = {}}
end
jsonWriteFile = function(_, document, formatted)
  writes = writes + 1; pretty = formatted
  assert(document.mapId == currentMap)
  return not failWrites
end
local cache = require("taxiDriver/routeCache")
local function point(x)
  return {pos = {x=x,y=0,z=0}, dir = {x=1,y=0,z=0},
    nodeA="a", nodeB="b", routeDistance=100}
end
local function offer(x) return {pickup=point(x), destination=point(x+100), rideDistance=100} end
assert(cache.ensureCurrentMapFile())
assert(cache.appendOffer(offer(0)))
assert(cache.appendOffer(offer(50)))
assert(#cache.loadOffers() == 2, "queued offers must be immediately readable")
assert(reads == 1, "map cache must be read once per session")
assert(writes == 0, "publishing must not synchronously rewrite an existing cache")
cache.update(1)
assert(writes == 0)
cache.update(1)
assert(writes == 1 and pretty == false, "debounce must write a single compact document")
assert(cache.appendOffer(offer(50)))
assert(#cache.loadOffers() == 2, "replacement must retain deduplication")
failWrites = true
assert(cache.flush() == false, "failed flush must report failure")
failWrites = false
assert(cache.flush() == true and writes == 3, "failed writes must retain queued routes")
currentMap = "second"
assert(#cache.loadOffers() == 0 and reads == 2, "maps must have independent in-memory documents")
currentMap = "first"
assert(#cache.loadOffers() == 2 and reads == 2)
currentMap, cacheSchema = "legacy", 1
assert(cache.ensureCurrentMapFile() and writes == 4,
  "initialization must migrate legacy cache documents immediately")
print("TaxiDriver route-cache IO regressions passed")
