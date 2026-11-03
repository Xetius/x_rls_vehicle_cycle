-- Step through every Gavril D-Series ('pickup') config, one spawned at a time, always at the same spot.
-- Console:  extensions.load('dsCycle')  then  dsCycle.next() / dsCycle.prev() / dsCycle.go(n) / dsCycle.list() / dsCycle.setSpot() / dsCycle.current() / dsCycle.logCurrent()
--           dsCycle.useFile([path]) cycles only the configs in a file (default dsCycle_flagged.txt), dsCycle.useAll() goes back to every config
--           dsCycle.scan() checks the seats of every config in the active list, dsCycle.stopScan() stops it
local M = {}

local jbeamIO = require('jbeam/io')

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

-- replaces the previously spawned vehicle with this config at the spot
local function spawnKey(key, autoEnter)
  -- remove the previous one first so it doesn't block the spot
  local old = vehId and getObjectByID(vehId)
  if old then old:delete() end
  vehId = nil

  local veh = core_vehicles.spawnNewVehicle(model, {config = key, pos = spot.pos, rot = spot.rot, autoEnterVehicle = autoEnter})
  if veh then
    vehId = veh:getID()
    spawn.safeTeleport(veh, spot.pos, spot.rot)
  end
  return veh
end

local function go(i)
  if #keys == 0 then refresh() end
  if not spot then setSpot() end
  if not spot then return end
  idx = ((i - 1) % #keys) + 1
  local key = keys[idx]
  local info = core_vehicles.getModel(model).configs[key] or {}
  spawnKey(key)
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

-- Seat scan: spawns every config in the active list (without getting in) and checks the 0.40
-- occupant seats the game finds, the same data seatOccupants uses to seat the player.
-- Problems go to <user folder>/dsCycle_seats.txt with the interior/dash/seat parts and the mod
-- each one comes from.
local scanFile = 'dsCycle_seats.txt'
local scanTimeout = 10 -- seconds to wait for a vehicle's data before giving up on it
local partPattern = { 'seat', 'interior', 'dash' } -- slots/parts worth reporting
local scan = nil

local function partSource(ioCtx, partName)
  local _, filename = jbeamIO.getPart(ioCtx, partName)
  if not filename then return '?' end
  local real = FS:getFileRealPath(filename) or filename
  return real:match('([^/\\]+%.zip)') or (real:find('[/\\]content[/\\]vehicles[/\\]') and 'vanilla') or real
end

local function seatParts(vehData)
  local found = {}
  local function walk(node)
    for _, child in pairs(node and node.children or {}) do
      local slot, part = tostring(child.id), child.chosenPartName
      if part and part ~= '' then
        for _, p in ipairs(partPattern) do
          if slot:lower():find(p, 1, true) or part:lower():find(p, 1, true) then
            table.insert(found, string.format('%s=%s [%s]', slot, part, partSource(vehData.ioCtx, part)))
            break
          end
        end
      end
      walk(child)
    end
  end
  walk(vehData.config and vehData.config.partsTree)
  table.sort(found)
  return table.concat(found, '; ')
end

local function checkSeats(key, id)
  local info = core_vehicles.getModel(model).configs[key] or {}
  local vehData = core_vehicle_manager.getVehicleData(id)
  local slots = vehData.vdata.occupantSlotsById or {}
  local seatIds, hasDriver = {}, false
  for seatId, slot in pairs(slots) do
    table.insert(seatIds, seatId)
    if slot.defaultPermissionMode == 'driver' then hasDriver = true end
  end
  table.sort(seatIds)
  local status = #seatIds == 0 and 'UNSEATED' or (not hasDriver and 'NO_DRIVER_SEAT') or 'OK'
  return status, {key, tostring(info.Name), tostring(info.Source), status, #seatIds, table.concat(seatIds, ','), seatParts(vehData)}
end

local function finishScan(reason)
  M.clear()
  local s = scan
  scan = nil
  local f = io.open(scanFile, 'a')
  if f then
    f:write(string.format('# %s: %d checked, %d OK, %d with problems\n', reason, s.checked, s.ok, s.checked - s.ok))
    f:close()
  end
  message(string.format('dsCycle: scan %s. %d checked, %d with seat problems, see %s', reason, s.checked, s.checked - s.ok, scanFile))
end

local function startScan()
  if scan then message('dsCycle: scan already running') return end
  if #keys == 0 then refresh() end
  if not spot then setSpot() end
  if not spot then return end
  local f = io.open(scanFile, 'w')
  if not f then message('dsCycle: unable to write ' .. scanFile) return end
  f:write(string.format('# seat scan %s, %d configs from %s\n', os.date('%Y-%m-%d %H:%M:%S'), #keys, sourceFile or 'all configs'))
  f:write('# key\tname\tsource\tstatus\tseat count\tseat ids\tinterior/dash/seat parts [mod]\n')
  f:close()
  scan = {i = 0, checked = 0, ok = 0, wait = 0, vehId = nil}
  message(string.format('dsCycle: scanning %d configs, stay out of the way of the spawn spot', #keys))
end

local function stopScan()
  if scan then finishScan('stopped') end
end

local function onUpdate(dtReal)
  if not scan then return end
  if scan.vehId then
    -- waiting for the spawned vehicle's jbeam data
    local vehData = core_vehicle_manager.getVehicleData(scan.vehId)
    scan.wait = scan.wait + dtReal
    local key = keys[scan.i]
    local row
    if vehData and vehData.vdata then
      local status
      status, row = checkSeats(key, scan.vehId)
      if status == 'OK' then scan.ok = scan.ok + 1; row = nil end
    elseif scan.wait > scanTimeout then
      row = {key, '', '', 'NO_DATA', 0, '', ''}
    else
      return
    end
    scan.checked = scan.checked + 1
    if row then
      local f = io.open(scanFile, 'a')
      if f then f:write(table.concat(row, '\t'), '\n'); f:close() end
    end
    scan.vehId = nil
  end

  scan.i = scan.i + 1
  if scan.i > #keys then finishScan('finished') return end
  local key = keys[scan.i]
  if scan.i % 10 == 1 then message(string.format('dsCycle: scanning %d/%d', scan.i, #keys)) end
  local veh = spawnKey(key, false)
  if veh then
    scan.vehId, scan.wait = veh:getID(), 0
  else
    scan.checked = scan.checked + 1
    local f = io.open(scanFile, 'a')
    if f then f:write(table.concat({key, '', '', 'SPAWN_FAILED', 0, '', ''}, '\t'), '\n'); f:close() end
  end
end

M.onUpdate = onUpdate
M.scan = startScan
M.stopScan = stopScan
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
