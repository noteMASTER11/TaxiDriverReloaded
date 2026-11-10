-- Each native minimap module keeps mutable camera/drawing state in its chunk.
-- Instantiate the game's modules in a private environment instead of taking
-- over the stock widget's singleton, texture and ImGui window.
local M = {}

function M.new(options)
  options = options or {}
  local service = {}
  local modules, environment = nil, nil
  local loadFailed = false
  local earthRoads,earthFailed,lastNodes=nil,false,nil
  local names = {"utils", "roads", "vehicles", "route", "topomap", "additionalInfo", "minimap"}

  local function loadNative(name, env)
    if options.loadModule then return options.loadModule(name, env) end
    local path = "/lua/ge/extensions/ui/apps/minimap/" .. name .. ".lua"
    local source = readFile(path)
    if not source then error("Native minimap module unavailable: " .. path) end
    local chunk, message = loadstring(source, "@" .. path)
    if not chunk then error(message) end
    setfenv(chunk, env)
    return chunk()
  end

  function service:getModules()
    if modules then return modules end
    if loadFailed then return nil end
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.settings = setmetatable({
      getValue = function(key, ...)
        if key == "minimapMode" then return "rect" end
        return settings.getValue(key, ...)
      end
    }, {__index = settings})
    env.extensions = setmetatable({
      -- The owner ticks this instance; it is not a global extension.
      hookUpdate = function() end,
      hook = function(name, ...)
        -- Draw callbacks from other extensions close over the stock map's
        -- utilities. Calling them here would write into the other texture.
        if name == "onDrawOnMinimap" then return end
        return extensions.hook(name, ...)
      end
    }, {__index = extensions})
    if gameplay_playmodeMarkers then
      -- Native POI marker methods also close over the global map utilities.
      -- Render their positions locally instead of invoking those methods.
      -- One reusable facade avoids a table/closure allocation per POI/frame.
      local marker = {}
      marker.drawOnMinimap = function(self)
        if self.pos then env.ui_apps_minimap_utils.simpleCircle(self.pos) end
      end
      env.gameplay_playmodeMarkers = setmetatable({
        getMarkerForCluster = function(cluster)
          local native = gameplay_playmodeMarkers.getMarkerForCluster(cluster)
          marker.pos = cluster.showOnMinimap ~= false and
            (cluster.visibilityPos or (native and native.pos)) or nil
          return marker
        end
      }, {__index = gameplay_playmodeMarkers})
    end
    env.ui_imgui = setmetatable({
      Begin = function(name, ...)
        if name == "SDF Minimap" then name = "TaxiDriver SDF Minimap" end
        if name == "SDF Minimap debugSettings" then name = "TaxiDriver SDF Minimap debugSettings" end
        return ui_imgui.Begin(name, ...)
      end
    }, {__index = ui_imgui})
    env.TextureDrawPrimitiveRegistry = setmetatable({
      getOrCreate = function(_, name, ...)
        if name == "sdfMinimap" then name = "sdfTaxiDriverMinimap" end
        return TextureDrawPrimitiveRegistry:getOrCreate(name, ...)
      end
    }, {__index = TextureDrawPrimitiveRegistry})
    local ok, result = pcall(function()
      local loaded = {}
      for _, name in ipairs(names) do
        local native = loadNative(name, env)
        if type(native) ~= "table" then error("Invalid native minimap module: " .. name) end
        loaded[name] = native
        env["ui_apps_minimap_" .. name] = native
      end
      loaded.minimap.onMinimapSettingsChanged()
      return loaded
    end)
    if not ok then
      loadFailed = true
      if type(log) == "function" then log("E", "taxiDriver.nativeMinimap", tostring(result)) end
      return nil
    end
    modules, environment = result, env
    return modules
  end

  function service:update(dtReal, dtSim)
    local renderer = modules and modules.minimap
    if renderer and renderer.onUpdate then
      local graph=map and map.getMap and map.getMap()
      local nodes=graph and graph.nodes
      if nodes~=lastNodes then self:invalidateRoads();lastNodes=nodes end
      local api=rawget(_G,'beamngEarth_api')
      if api and api.inWorld and api.inWorld() then
        if not earthRoads and not earthFailed then
          -- Earth's stock hook closes over the stock texture's utilities.
          -- Load its existing renderer in our private environment instead.
          local ok,value=pcall(function()
            if options.loadEarthModule then return options.loadEarthModule(environment) end
            local source=assert(readFile('/lua/ge/extensions/beamngEarth/minimaproads.lua'))
            local chunk=assert(loadstring(source,'@beamngEarth/minimaproads.lua'))
            setfenv(chunk,environment)
            return chunk()
          end)
          if ok then earthRoads=value else earthFailed=true end
        end
        if earthRoads then
          local ok,err=pcall(function()
            local graph=options.getEarthGraph and options.getEarthGraph() or require('beamngEarth/navgraph').currentGraph()
            earthRoads.hook();earthRoads.update(graph)
          end)
          if not ok then
            earthRoads.unhook();earthRoads=nil;earthFailed=true
            log('W','taxiDriver.nativeMinimap',tostring(err))
          end
        end
      elseif earthRoads then earthRoads.unhook();earthRoads=nil end
    end
    if renderer and renderer.onUpdate then renderer.onUpdate(dtReal, dtSim) end
  end

  function service:invalidateRoads()
    if modules and modules.roads.reset then modules.roads.reset() end
  end

  function service:stats()
    return {earth=earthRoads and earthRoads.status() or nil,earthFailed=earthFailed}
  end

  function service:reset()
    if earthRoads then earthRoads.unhook() end
    earthRoads,earthFailed,lastNodes=nil,false,nil
    if modules and modules.minimap.hide then modules.minimap.hide() end
    modules, environment, loadFailed = nil, nil, false
  end

  return service
end

return M
