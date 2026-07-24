local M = {}

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
  local visualOverrideActive = false
  local originalGroundmarkers = nil
  local originalArrows = nil

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
    visualOverrideActive = false
    originalGroundmarkers, originalArrows = nil, nil
  end

  local function applyVisualSettings()
    if not options.isRouteGuidanceHidden or not options.isRouteGuidanceHidden() then
      restoreVisualSettings()
      return
    end
    if not visualOverrideActive then
      originalGroundmarkers = settings.getValue("showNavigationGroundmarkers") ~= false
      originalArrows = settings.getValue("showNavigationArrows") ~= false
      visualOverrideActive = true
    end
    settings.setValue("showNavigationGroundmarkers", false)
    settings.setValue("showNavigationArrows", false)
    if core_groundMarkerArrows then core_groundMarkerArrows.clearArrows() end
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
  end

  function service:restoreNavigationVisualSettings()
    restoreVisualSettings()
  end

  function service:setNavigationTarget(target)
    if not core_groundMarkers or not target or not target.pos then return end
    applyVisualSettings()
    core_groundMarkers.setPath(target.pos, {
      clearPathOnReachingTarget = false,
      cutOffDrivability = tonumber(options.minimumDrivability) or 0
    })
    if options.onRouteChanged then options.onRouteChanged() end
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
    originalMode, owned = nil, false
  end

  function service:canShow(allowFleet)
    return appVisible and not uiBlocked and
      ((options.isRouteActive and options.isRouteActive()) or allowFleet == true)
  end

  function service:setAppVisibility(visible)
    appVisible = visible == true
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
    if not ui_apps_minimap_minimap then extensions.load("ui_apps_minimap_minimap") end
    if not ui_apps_minimap_minimap then return end
    if not owned then
      originalMode = settings.getValue("minimapMode") or "circle"
      if originalMode ~= "rect" then settings.setValue("minimapMode", "rect") end
      ui_apps_minimap_minimap.onMinimapSettingsChanged()
      owned = true
    end
    installDynamicZoom()
    ui_apps_minimap_minimap.setDrawTransform(
      clamp(x, 0, 1), clamp(y, 0, 1), clamp(width, 0, 1), clamp(height, 0, 1))
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
