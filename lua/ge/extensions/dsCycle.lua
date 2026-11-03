-- Step through every Gavril D-Series ('pickup') config, one spawned at a time, always at the same spot.
-- Console:  extensions.load('dsCycle')  then  dsCycle.next() / dsCycle.prev() / dsCycle.go(n) / dsCycle.list() / dsCycle.setSpot() / dsCycle.current() / dsCycle.logCurrent()
--           dsCycle.useFile([path]) cycles only the configs in a file (default dsCycle_flagged.txt), dsCycle.useAll() goes back to every config
local M = {}

local model = 'pickup'
local spotDistance = 10 -- metres in front of the vehicle you're in when the spot is set
local logFile = 'dsCycle_flagged.txt' -- in the BeamNG user folder
local keys, idx, vehId, spot = {}, 0, nil, nil
local sourceFile = nil -- nil = cycle all configs, otherwise cycle the configs listed in this file

local function message(msg)
  log('I', 'dsCycle', msg)
  guihooks.trigger('Message', {ttl = 6, msg = msg, category = 'dsCycle', icon = 'directions_car'})
end

local function allKeys()
  local list = {}
  for key, _ in pairs(core_vehicles.getModel(model).configs or {}) do table.insert(list, key) end
  table.sort(list)
  return list
end

-- config keys from a file: one per line, either a bare key or our tab-separated log format (key in column 3)
local function fileKeys(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local configs = core_vehicles.getModel(model).configs or {}
  local list, seen = {}, {}
  for line in f:lines() do
    local cols = {}
    for col in (line .. '\t'):gmatch('([^\t]*)\t') do table.insert(cols, col) end
    local key = (#cols >= 3 and cols[3] or cols[1] or ''):match('^%s*(.-)%s*$')
    if key ~= '' and not seen[key] then
      seen[key] = true
      if configs[key] then
        table.insert(list, key)
      else
        log('W', 'dsCycle', 'config not found, skipped: ' .. key)
      end
    end
  end
  f:close()
  return list
end

local function refresh()
  idx = 0
  if sourceFile then
    keys = fileKeys(sourceFile)
    if not keys then
      message('dsCycle: unable to read ' .. sourceFile .. ', using all configs')
      sourceFile = nil
    elseif #keys == 0 then
      message('dsCycle: no configs in ' .. sourceFile .. ', using all configs')
      sourceFile = nil
    else
      message(string.format('dsCycle: %d configs from %s', #keys, sourceFile))
      return
    end
  end
  keys = allKeys()
  message(string.format('dsCycle: all %d %s configs', #keys, model))
end

local function useFile(path)
  sourceFile = path or logFile
  refresh()
end

local function useAll()
  sourceFile = nil
  refresh()
end

local function toggleSource()
  if sourceFile then useAll() else useFile() end
end

local function setSpot()
  local veh = getPlayerVehicle(0)
  if not veh then message('dsCycle: get in a vehicle to set the spawn spot') return end
  local dir = veh:getDirectionVector()
  dir.z = 0
  dir:normalize()
  spot = {pos = veh:getPosition() + dir * spotDistance, rot = quatFromDir(dir)}
  message(string.format('dsCycle: spawn spot set %dm ahead', spotDistance))
end

local function go(i)
  if #keys == 0 then refresh() end
  if not spot then setSpot() end
  if not spot then return end
  idx = ((i - 1) % #keys) + 1
  local key = keys[idx]
  local info = core_vehicles.getModel(model).configs[key] or {}

  -- remove the previous one first so it doesn't block the spot
  local old = vehId and getObjectByID(vehId)
  if old then old:delete() end
  vehId = nil

  local veh = core_vehicles.spawnNewVehicle(model, {config = key, pos = spot.pos, rot = spot.rot})
  if veh then
    vehId = veh:getID()
    spawn.safeTeleport(veh, spot.pos, spot.rot)
  end
  message(string.format('[%d/%d] %s  (%s, %s)', idx, #keys, key, tostring(info.Name), tostring(info.Source)))
end

local function list()
  if #keys == 0 then refresh() end
  for i, k in ipairs(keys) do log('I', 'dsCycle', i .. '  ' .. k) end
end

-- shows which config is spawned and returns: vehicle object, config key, index
local function current()
  if idx == 0 then message('dsCycle: nothing spawned yet') return end
  local key = keys[idx]
  local info = core_vehicles.getModel(model).configs[key] or {}
  message(string.format('[%d/%d] %s  (%s, %s)', idx, #keys, key, tostring(info.Name), tostring(info.Source)))
  return vehId and getObjectByID(vehId), key, idx
end

-- appends the current config to <user folder>/dsCycle_flagged.txt (tab separated)
local function logCurrent()
  if idx == 0 then message('dsCycle: nothing spawned yet') return end
  local key = keys[idx]
  local info = core_vehicles.getModel(model).configs[key] or {}
  local f = io.open(logFile, 'a')
  if not f then message('dsCycle: unable to write ' .. logFile) return end
  f:write(table.concat({os.date('%Y-%m-%d %H:%M:%S'), idx, key, tostring(info.Name), tostring(info.Source)}, '\t'), '\n')
  f:close()
  message(string.format('dsCycle: logged [%d] %s', idx, key))
end

M.current = current
M.logCurrent = logCurrent
M.refresh = refresh
M.useFile = useFile
M.useAll = useAll
M.toggleSource = toggleSource
M.setSpot = setSpot
M.go = go
M.next = function() go(idx + 1) end
M.prev = function() go(idx - 1) end
M.list = list
M.clear = function() local v = vehId and getObjectByID(vehId); if v then v:delete() end; vehId = nil end

return M
