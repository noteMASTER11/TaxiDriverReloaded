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
  local originalSetMinimapState = nil
  local wrappedSetMinimapState = nil
  local activeMinimapTexture = nil
  local forceFullTextureClear = false
  local zoomMultiplier = nil
  local lastReturnedScale = nil
  local clearOnceSupported = nil
  local lastTransform = nil
  local visualOverrideActive = false
  local originalGroundmarkers = nil
  local originalArrows = nil
  local destinationMarker = nil
  local destinationMarkerSerial = 0
  local originalSetUtilsState, wrappedSetUtilsState = nil, nil
  local mapView = nil
  local inspectionCenter, inspectionRotation, inspectionInverse = nil, nil, nil
  local manualZoom = 1
  local mapViewChanged = false

  local function restoreDynamicZoom()
    if ui_apps_minimap_utils and originalSetUtilsState and
      ui_apps_minimap_utils.setMinimapState == wrappedSetUtilsState then
      ui_apps_minimap_utils.setMinimapState = originalSetUtilsState
    end
    originalSetUtilsState, wrappedSetUtilsState, mapView = nil, nil, nil
    if ui_apps_minimap_vehicles and originalDrawPlayer and
      ui_apps_minimap_vehicles.drawPlayer == wrappedDrawPlayer then
      ui_apps_minimap_vehicles.drawPlayer = originalDrawPlayer
    end
    if activeMinimapTexture and activeMinimapTexture.setClearFlag then
      activeMinimapTexture:setClearFlag("WhenDirty")
    end
    if ui_apps_minimap_vehicles and originalSetMinimapState and
      ui_apps_minimap_vehicles.setMinimapState == wrappedSetMinimapState then
      ui_apps_minimap_vehicles.setMinimapState = originalSetMinimapState
    end
    originalSetMinimapState, wrappedSetMinimapState = nil, nil
    activeMinimapTexture, forceFullTextureClear = nil, false
    clearOnceSupported = nil
    originalDrawPlayer, wrappedDrawPlayer, zoomMultiplier = nil, nil, nil
    lastReturnedScale = nil
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
    local visible = not options.isRouteGuidanceHidden or not options.isRouteGuidanceHidden()
    if visible then
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
    if core_groundMarkers and core_groundMarkers.onSettingsChanged then
      core_groundMarkers.onSettingsChanged()
    elseif core_groundMarkerArrows then
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
    if not ui_apps_minimap_vehicles then extensions.load("ui_apps_minimap_vehicles") end
    if not ui_apps_minimap_vehicles then return end

    if ui_apps_minimap_utils and not wrappedSetUtilsState and
      type(ui_apps_minimap_utils.setMinimapState) == "function" then
      originalSetUtilsState = ui_apps_minimap_utils.setMinimapState
      local original = originalSetUtilsState
      wrappedSetUtilsState = function(w, h, cx, cy, pos, rot, inverse, scale, ...)
        if owned and pos and rot and inverse and type(scale) == "number" then
          -- 0.39 passes these same vector/quaternion objects to utilities,
          -- vehicles and roads. Adjust before the first drawing consumer so
          -- every map layer uses the same camera while inspecting a location.
          if inspectionCenter then
            pos:set(inspectionCenter)
            rot:set(inspectionRotation)
            inverse:set(inspectionInverse)
          end
          mapView = {width = w, height = h, scale = scale,
            center = vec3(pos), rotation = quat(rot), inverse = quat(inverse)}
        end
        if mapViewChanged then
          local texture = select(2, ...)
          if texture and type(texture.clearOnceBeforeRender) == "function" then
            pcall(function() texture:clearOnceBeforeRender(0) end)
          end
          mapViewChanged = false
        end
        return original(w, h, cx, cy, pos, rot, inverse, scale, ...)
      end
      ui_apps_minimap_utils.setMinimapState = wrappedSetUtilsState
    end

    if not wrappedSetMinimapState and
      type(ui_apps_minimap_vehicles.setMinimapState) == "function" then
      originalSetMinimapState = ui_apps_minimap_vehicles.setMinimapState
      local originalSetState = originalSetMinimapState
      wrappedSetMinimapState = function(...)
        local result = originalSetState(...)
        local textureDraw = select(10, ...)
        if textureDraw and textureDraw.setClearFlag then
          local textureChanged = activeMinimapTexture ~= textureDraw
          activeMinimapTexture = textureDraw
          if textureChanged then clearOnceSupported = nil end
          -- BeamNG 0.39 computes the next scale at the end of drawPlayer(), after
          -- roads and navigation have already been submitted with the old scale.
          -- Keep normal dirty-region rendering here; drawPlayer schedules one full
          -- clear specifically for the next frame when that scale actually changes.
          textureDraw:setClearFlag("WhenDirty")
        end
        return result
      end
      ui_apps_minimap_vehicles.setMinimapState = wrappedSetMinimapState
    end

    if not wrappedDrawPlayer and
      type(ui_apps_minimap_vehicles.drawPlayer) == "function" then
      originalDrawPlayer = ui_apps_minimap_vehicles.drawPlayer
      local original = originalDrawPlayer
      wrappedDrawPlayer = function(dtReal, dtSim)
        local baseScale = original(dtReal, dtSim)
        if type(baseScale) ~= "number" or not owned then return baseScale end
        local shiftActive = not options.isActive or options.isActive()
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
        local returnedScale = baseScale * (shiftActive and zoomMultiplier or 1) * manualZoom
        local scaleDelta = lastReturnedScale and math.abs(returnedScale - lastReturnedScale) or 0
        local scaleChanged = lastReturnedScale ~= nil and scaleDelta > 0.00001
        if forceFullTextureClear and scaleChanged and clearOnceSupported ~= false and
          activeMinimapTexture and
          type(activeMinimapTexture.clearOnceBeforeRender) == "function" then
          local ok = pcall(function()
            -- 0 is BeamNG's transparent clear color. The 0.39 binding requires
            -- this numeric argument even when the primitive already has color 0.
            return activeMinimapTexture:clearOnceBeforeRender(0)
          end)
          clearOnceSupported = ok
        end
        lastReturnedScale = returnedScale
        return returnedScale
      end
      ui_apps_minimap_vehicles.drawPlayer = wrappedDrawPlayer
    end
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
    applyVisualSettings()
    core_groundMarkers.setPath(target.pos, {
      clearPathOnReachingTarget = false,
      cutOffDrivability = tonumber(options.minimumDrivability) or 0
    })
    -- BeamNG 0.39 creates the floating-arrow pool at the end of setPath even
    -- when showNavigationArrows is false, so the disabled state must win last.
    if settings.getValue("showNavigationArrows") == false and core_groundMarkerArrows then
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
        "taxiDriverAutopilot", "taxiDriverFleetStatus", "taxiDriverMapControls"
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
    self:resetMinimapView()
  end

  function service:panMinimap(dx, dy)
    dx, dy = tonumber(dx), tonumber(dy)
    if not owned or not mapView or not dx or not dy or dx ~= dx or dy ~= dy then return end
    local offset = mapView.inverse * vec3(
      -clamp(dx, -1, 1) * mapView.width * mapView.scale,
      clamp(dy, -1, 1) * mapView.height * mapView.scale, 0)
    inspectionCenter = (inspectionCenter or mapView.center) + offset
    inspectionRotation, inspectionInverse = mapView.rotation, mapView.inverse
    mapViewChanged = true
  end

  function service:zoomMinimap(factor)
    factor = tonumber(factor)
    if not owned or not factor or factor ~= factor or factor <= 0 then return end
    manualZoom = clamp(manualZoom * factor, 0.25, 4)
  end

  function service:resetMinimapView()
    mapViewChanged = inspectionCenter ~= nil
    inspectionCenter, inspectionRotation, inspectionInverse = nil, nil, nil
    manualZoom = 1
  end

  function service:canRenderWorld()
    return appVisible and not uiBlocked
  end

  function service:setTransform(x, y, width, height, allowFleet, fullTextureClear)
    if not self:canShow(allowFleet) then self:hideMinimap(); return end
    forceFullTextureClear = fullTextureClear == true
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
      "taxiDriverAutopilot", "taxiDriverFleetStatus", "taxiDriverMapControls"
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
