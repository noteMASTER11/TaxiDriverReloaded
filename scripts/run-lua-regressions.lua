-- Run repository tests inside separate Lua environments, including when invoked
-- from the game's MCP. Test mocks and require caches never enter the live VM.
return function(root, files, sources)
  local result = {passed = {}, failed = {}}
  root = root:gsub("\\", "/"):gsub("/$", "")
  local function copy(source)
    local target = {}
    for key, value in pairs(source or {}) do target[key] = value end
    return target
  end
  local function sourceAt(path)
    if sources then return sources[path] or sources[path:sub(#root + 2)] end
    local file = io.open(path, "rb")
    if not file then return nil end
    local text = file:read("*a"); file:close()
    return text:gsub("\r\n", "\n")
  end
  for _, path in ipairs(files) do
    local env = {}
    for _, key in ipairs({"assert", "error", "getfenv", "setfenv", "getmetatable", "setmetatable",
      "ipairs", "pairs", "next", "pcall", "xpcall", "rawequal", "rawget", "rawset", "select",
      "tonumber", "tostring", "type", "unpack", "newproxy", "loadstring", "collectgarbage"}) do
      env[key] = _G[key]
    end
    for _, key in ipairs({"math", "string", "table", "os", "io", "coroutine", "debug"}) do
      env[key] = copy(_G[key])
    end
    env._G = env
    env.loadstring = function(text, name)
      local chunk, message = loadstring(text, name or "@test-generated.lua")
      if chunk then setfenv(chunk, env) end
      return chunk, message
    end
    env.package = {path = "lua/ge/extensions/?.lua;lua/vehicle/extensions/?.lua", loaded = {}, preload = {}}
    env.print = function() end
    env.log = function() end
    local function resolve(p)
      if p:match("^lua/") or p:match("^ui/") or p:match("^tests/") then return root .. "/" .. p end
      return p
    end
    env.io.open = function(p, ...)
      if sources then
        local text = sourceAt(resolve(p))
        if not text then return nil, "Test file unavailable: " .. p end
        return {read = function() return text end, close = function() end}
      end
      return io.open(resolve(p), ...)
    end
    env.loadfile = function(p)
      local text = sourceAt(resolve(p))
      if not text then return nil, "File unavailable: " .. p end
      local chunk, message = loadstring(text, "@" .. p)
      if chunk then setfenv(chunk, env) end
      return chunk, message
    end
    env.dofile = function(p) return assert(env.loadfile(p))() end
    env.require = function(name)
      if env.package.loaded[name] ~= nil then return env.package.loaded[name] end
      local loader = env.package.preload[name]
      if not loader then
        for template in (env.package.path .. ";"):gmatch("(.-);") do
          local p = template:gsub("%?", name)
          loader = env.loadfile(p)
          if loader then break end
        end
      end
      if not loader then error("Test module unavailable: " .. name) end
      setfenv(loader, env)
      local value = loader(name)
      if value == nil then value = true end
      env.package.loaded[name] = value
      return value
    end
    local ok, message = pcall(function() env.dofile(path) end)
    if ok then result.passed[#result.passed + 1] = path
    else result.failed[#result.failed + 1] = {path = path, message = message} end
  end
  return result
end
