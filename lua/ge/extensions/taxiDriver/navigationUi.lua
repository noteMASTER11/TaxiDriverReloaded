local M = {}

local attentionMarkerFactory = nil
do
  local ok, factory = pcall(require, "scenario/raceMarkers/attention")
  if ok and type(factory) == "function" then attentionMarkerFactory = factory end
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, tonumber(value) or minimum))
end

function M.new(options)
  options = type(options) == "table" and options or {}
  local service = {}
  local originalMode = nil
  local owned = false
  local appVisible = true
  local uiBlocked = false
  local originalDrawPlayer = nil
  local wrappedDrawPlayer = nil
  local zoomMultiplier = nil
  local lastTransform = nil
  local visualOverrideActive = false
  local originalGroundmarkers = nil
  local originalArrows = nil
  local destinationMarker = nil
  local destinationMarkerSerial = 0

  local function restoreDynamicZoom()
    if ui_apps_minimap_vehicles and originalDrawPlayer and
      ui_apps_minimap_vehicles.drawPlayer == wrappedDrawPlayer then
      ui_apps_minimap_vehicles.drawPlayer = originalDrawPlayer
    end
    originalDrawPlayer, wrappedDrawPlayer, zoomMultiplier = nil, nil, nil
  end

  local function restoreVisualSettings()
    if not visualOverrideActive then return end
    settings.setValue("showNavigationGroundmarkers", originalGroundmarkers)
    settings.setValue("showNavigationArrows", originalArrows)
    if core_groundMarkers and core_groundMarkers.onSettingsChanged then
      core_groundMarkers.onSettingsChanged()
    end
    visualOverrideActive = false
    originalGroundmarkers, originalArrows = nil, nil
  end

  local function applyVisualSettings()
    if not visualOverrideActive then
      originalGroundmarkers = settings.getValue("showNavigationGroundmarkers") ~= false
      originalArrows = settings.getValue("showNavigationArrows") ~= false
      visualOverrideActive = true
    end
    local visible = not options.isRouteGuidanceHidden or not options.isRouteGuidanceHidden()
    settings.setValue("showNavigationGroundmarkers", visible)
    settings.setValue("showNavigationArrows", visible)
    if core_groundMarkers and core_groundMarkers.onSettingsChanged then
      core_groundMarkers.onSettingsChanged()
    elseif not visible and core_groundMarkerArrows then
      core_groundMarkerArrows.clearArrows()
    end
  end

  local function clearDestinationMarker()
    if destinationMarker and destinationMarker.clearMarkers then
      destinationMarker:clearMarkers()
    end
    destinationMarker = nil
  end

  local function setDestinationMarker(pos)
    clearDestinationMarker()
    if not attentionMarkerFactory or not pos then return end
    destinationMarkerSerial = destinationMarkerSerial + 1
    local ok, marker = pcall(attentionMarkerFactory,
      "taxiDriverDestination" .. tostring(destinationMarkerSerial))
    if not ok or not marker then return end
    destinationMarker = marker
    marker:createMarkers()
    marker:setToCheckpoint({pos = vec3(pos) + vec3(0, 0, 2), radius = 1.5})
    marker:setMode("default")
    marker:show()
  end

  local function installDynamicZoom()
    if wrappedDrawPlayer then return end
    if not ui_apps_minimap_vehicles then extensions.load("ui_apps_minimap_vehicles") end
    if not ui_apps_minimap_vehicles or
      type(ui_apps_minimap_vehicles.drawPlayer) ~= "function" then return end
    originalDrawPlayer = ui_apps_minimap_vehicles.drawPlayer
    local original = originalDrawPlayer
    wrappedDrawPlayer = function(dtReal, dtSim)
      local baseScale = original(dtReal, dtSim)
      if type(baseScale) ~= "number" or not owned or
        (options.isActive and not options.isActive()) then return baseScale end
      local vehicle = options.getVehicle and options.getVehicle() or nil
      local speedKmh = vehicle and options.getSpeedKmh and options.getSpeedKmh(vehicle) or 0
      local speedRatio = clamp(speedKmh / 120, 0, 1)
      local easedSpeed = speedRatio * speedRatio * (3 - 2 * speedRatio)
      local rawTargetMultiplier = 0.66 + (1.62 - 0.66) * easedSpeed
      local intensity = clamp(
        options.getZoomIntensity and options.getZoomIntensity() or 100, 0, 200) / 100
      local targetMultiplier = clamp(
        1 + (rawTargetMultiplier - 1) * intensity, 0.35, 2.30)
      if not zoomMultiplier then
        zoomMultiplier = targetMultiplier
      else
        local frameTime = clamp(dtReal or 0.016, 0, 0.1)
        local blend = 1 - math.exp(-frameTime * 2.4)
        zoomMultiplier = zoomMultiplier +
          (targetMultiplier - zoomMultiplier) * blend
      end
      return baseScale * zoomMultiplier
    end
    ui_apps_minimap_vehicles.drawPlayer = wrappedDrawPlayer
  end

  function service:clearNavigation()
    if core_groundMarkers then core_groundMarkers.setPath(nil) end
    clearDestinationMarker()
  end

  function service:restoreNavigationVisualSettings()
    restoreVisualSettings()
  end

  function service:setNavigationTarget(target)
    if not core_groundMarkers or not target or not target.pos then return end
    local guidanceVisible = not options.isRouteGuidanceHidden or
      not options.isRouteGuidanceHidden()
    applyVisualSettings()
    core_groundMarkers.setPath(target.pos, {
      clearPathOnReachingTarget = false,
      cutOffDrivability = tonumber(options.minimumDrivability) or 0
    })
    -- BeamNG 0.39 creates the floating-arrow pool at the end of setPath even
    -- when showNavigationArrows is false, so the disabled state must win last.
    if not guidanceVisible and core_groundMarkerArrows then
      core_groundMarkerArrows.clearArrows()
    end
    setDestinationMarker(target.pos)
    if options.onRouteChanged then options.onRouteChanged() end
  end

  function service:onPreRender(dtReal, dtSim)
    if destinationMarker and destinationMarker.update then
      destinationMarker:update(dtReal or 0, dtSim or 0)
    end
  end

  function service:hideMinimap()
    restoreDynamicZoom()
    if ui_apps_minimap_minimap then
      for _, id in ipairs({
        "taxiDriverRouteInfo", "taxiDriverSpeedLimit", "taxiDriverNotification",
        "taxiDriverAutopilot", "taxiDriverFleetStatus"
      }) do
        ui_apps_minimap_minimap.resetOcclusionTransform(id)
      end
      if owned then ui_apps_minimap_minimap.hide() end
    end
    if owned and originalMode and originalMode ~= "rect" then
      settings.setValue("minimapMode", originalMode)
      if ui_apps_minimap_minimap then
        ui_apps_minimap_minimap.onMinimapSettingsChanged()
      end
    end
    originalMode, owned, lastTransform = nil, false, nil
  end

  function service:canShow(allowFleet)
    return appVisible and not uiBlocked and
      ((options.isRouteActive and options.isRouteActive()) or allowFleet == true)
  end

  function service:setAppVisibility(visible)
    local nextVisible = visible == true
    if appVisible == nextVisible then return end
    appVisible = nextVisible
    if not appVisible then
      self:hideMinimap()
    elseif not uiBlocked then
      guihooks.trigger("TaxiDriverMinimapInvalidated")
    end
  end

  function service:setUiBlocked(value)
    uiBlocked = value == true
    if uiBlocked then self:hideMinimap() end
  end

  function service:resetVisibility()
    appVisible, uiBlocked = true, false
  end

  function service:canRenderWorld()
    return appVisible and not uiBlocked
  end

  function service:setTransform(x, y, width, height, allowFleet)
    if not self:canShow(allowFleet) then self:hideMinimap(); return end
    x, y, width, height = tonumber(x), tonumber(y), tonumber(width), tonumber(height)
    if not x or not y or not width or not height or width <= 0 or height <= 0 then return end
    x, y = clamp(x, 0, 1), clamp(y, 0, 1)
    width, height = clamp(width, 0, 1), clamp(height, 0, 1)
    if lastTransform and math.abs(lastTransform[1] - x) < 0.00001 and
      math.abs(lastTransform[2] - y) < 0.00001 and
      math.abs(lastTransform[3] - width) < 0.00001 and
      math.abs(lastTransform[4] - height) < 0.00001 then return end
    if not ui_apps_minimap_minimap then extensions.load("ui_apps_minimap_minimap") end
    if not ui_apps_minimap_minimap then return end
    if not owned then
      originalMode = settings.getValue("minimapMode") or "circle"
      if originalMode ~= "rect" then settings.setValue("minimapMode", "rect") end
      ui_apps_minimap_minimap.onMinimapSettingsChanged()
      owned = true
    end
    installDynamicZoom()
    lastTransform = {x, y, width, height}
    ui_apps_minimap_minimap.setDrawTransform(x, y, width, height)
  end

  function service:setOcclusions(values, allowFleet)
    if not self:canShow(allowFleet) then return end
    if not ui_apps_minimap_minimap then extensions.load("ui_apps_minimap_minimap") end
    if not ui_apps_minimap_minimap then return end
    local ids = {
      "taxiDriverRouteInfo", "taxiDriverSpeedLimit", "taxiDriverNotification",
      "taxiDriverAutopilot", "taxiDriverFleetStatus"
    }
    for index, id in ipairs(ids) do
      local offset = (index - 1) * 4
      local x, y = tonumber(values[offset + 1]), tonumber(values[offset + 2])
      local width, height = tonumber(values[offset + 3]), tonumber(values[offset + 4])
      if not x or not y or not width or not height or width <= 0 or height <= 0 then
        ui_apps_minimap_minimap.resetOcclusionTransform(id)
      else
        x, y = clamp(x, 0, 1), clamp(y, 0, 1)
        width, height = clamp(width, 0, 1 - x), clamp(height, 0, 1 - y)
        if width <= 0 or height <= 0 then
          ui_apps_minimap_minimap.resetOcclusionTransform(id)
        else
          ui_apps_minimap_minimap.setOcclusionTransform(id, x, y, width, height)
        end
      end
    end
  end

  return service
end

return M
