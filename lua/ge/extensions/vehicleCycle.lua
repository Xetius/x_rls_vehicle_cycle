-- Step through every config of one or more vehicle models (or the configs listed in a file), one
-- spawned at a time, always at the same spot.
-- Console:  extensions.load('vehicleCycle')  then
--   vehicleCycle.useModel([model])  cycle every config of a model ('pickup', 'us_semi', or a table of
--                                   models); no argument = the model of the vehicle you're in
--   vehicleCycle.useFile([path])    cycle only the configs in a file (default vehicleCycle_flagged.txt)
--   vehicleCycle.useAll()           back to every config of the model(s)
--   vehicleCycle.next() / prev() / go(n) / list() / setSpot([metres]) / current() / logCurrent() / clear()
--   vehicleCycle.scan() checks the seats of every config in the active list, stopScan() stops it
local M = {}

local jbeamIO = require('jbeam/io')

local logTag = 'vehicleCycle'
local spotDistance = 10 -- metres in front of the vehicle you're in when the spot is set
local logFile = 'vehicleCycle_flagged.txt' -- in the BeamNG user folder
local models = nil -- model keys to cycle; nil = the model of the vehicle you're in, picked on first use
local entries, idx, vehId, spot = {}, 0, nil, nil -- entries: {model = 'pickup', key = 'd15_4wd_A'}
local sourceFile = nil -- nil = cycle all configs of the models, otherwise cycle the configs listed in this file

local function message(msg)
  log('I', logTag, msg)
  guihooks.trigger('Message', {ttl = 6, msg = msg, category = logTag, icon = 'directions_car'})
end

local function tr(s)
  return type(s) == 'string' and translateLanguage and translateLanguage(s, s, true) or tostring(s)
end

local function modelName(model)
  local m = core_vehicles.getModel(model).model
  return m and (tr(m.Brand) .. ' ' .. tr(m.Name)) or model
end

local function configInfo(e)
  return (core_vehicles.getModel(e.model).configs or {})[e.key] or {}
end

local function describe(e)
  local info = configInfo(e)
  return string.format('%s  (%s, %s)', e.key, tr(info.Name), tostring(info.Source))
end

local function modelEntries()
  local list = {}
  for _, model in ipairs(models) do
    local keys = {}
    for key, _ in pairs(core_vehicles.getModel(model).configs or {}) do table.insert(keys, key) end
    table.sort(keys)
    for _, key in ipairs(keys) do table.insert(list, {model = model, key = key}) end
  end
  return list
end

-- a config key with no model: one of the active models, else 'pickup' (old dsCycle logs were all D-Series)
local function resolveModel(key)
  for _, model in ipairs(models or {}) do
    if (core_vehicles.getModel(model).configs or {})[key] then return model end
  end
  return 'pickup'
end

-- configs from a file, one per line ('#' lines are skipped):
--   our log format, tab separated: time, list position, model, key, ...
--   the old dsCycle log format, tab separated: time, list position, key, ...
--   the seat scan format, tab separated: model, key, ...
--   model/key, or a bare key
local function fileEntries(path)
  local f = io.open(path, 'r')
  if not f then return nil end
  local list, seen = {}, {}
  for line in f:lines() do
    local cols = {}
    for col in (line .. '\t'):gmatch('([^\t]*)\t') do table.insert(cols, (col:match('^%s*(.-)%s*$'))) end
    local model, key
    if cols[1]:match('^%d%d%d%d%-%d%d%-%d%d') then
      if #cols >= 6 then model, key = cols[3], cols[4] else key = cols[3] end
    elseif #cols >= 2 then
      model, key = cols[1], cols[2]
    else
      model, key = cols[1]:match('^([^/]+)/(.+)$')
      key = key or cols[1]
    end
    if key and key ~= '' and cols[1]:sub(1, 1) ~= '#' then
      model = model or resolveModel(key)
      local id = model .. '/' .. key
      if not seen[id] then
        seen[id] = true
        if (core_vehicles.getModel(model).configs or {})[key] then
          table.insert(list, {model = model, key = key})
        else
          log('W', logTag, 'config not found, skipped: ' .. id)
        end
      end
    end
  end
  f:close()
  return list
end

local function currentModel()
  local veh = getPlayerVehicle(0)
  return veh and veh:getJBeamFilename()
end

local function refresh()
  idx = 0
  if not models then
    local model = currentModel()
    if not model then message('vehicleCycle: get in a vehicle, or pick a model with vehicleCycle.useModel(\'pickup\')') entries = {} return end
    models = {model}
  end
  if sourceFile then
    entries = fileEntries(sourceFile)
    if not entries then
      message('vehicleCycle: unable to read ' .. sourceFile .. ', using all configs')
      sourceFile = nil
    elseif #entries == 0 then
      message('vehicleCycle: no configs in ' .. sourceFile .. ', using all configs')
      sourceFile = nil
    else
      message(string.format('vehicleCycle: %d configs from %s', #entries, sourceFile))
      return
    end
  end
  entries = modelEntries()
  local names = {}
  for _, model in ipairs(models) do table.insert(names, modelName(model)) end
  message(string.format('vehicleCycle: all %d %s configs', #entries, table.concat(names, ' + ')))
end

local function useModel(model)
  if type(model) == 'string' then
    models = {model}
  elseif type(model) == 'table' then
    models = model
  else
    model = currentModel()
    if not model then message('vehicleCycle: get in a vehicle to pick its model') return end
    models = {model}
  end
  sourceFile = nil
  refresh()
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

local function setSpot(distance)
  local veh = getPlayerVehicle(0)
  if not veh then message('vehicleCycle: get in a vehicle to set the spawn spot') return end
  spotDistance = tonumber(distance) or spotDistance
  local dir = veh:getDirectionVector()
  dir.z = 0
  dir:normalize()
  spot = {pos = veh:getPosition() + dir * spotDistance, rot = quatFromDir(dir)}
  message(string.format('vehicleCycle: spawn spot set %dm ahead', spotDistance))
end

local function ready()
  if #entries == 0 then refresh() end
  if #entries == 0 then return false end
  if not spot then setSpot() end
  return spot ~= nil
end

-- replaces the previously spawned vehicle with this config at the spot
local function spawnEntry(e, autoEnter)
  -- remove the previous one first so it doesn't block the spot
  local old = vehId and getObjectByID(vehId)
  if old then old:delete() end
  vehId = nil

  local veh = core_vehicles.spawnNewVehicle(e.model, {config = e.key, pos = spot.pos, rot = spot.rot, autoEnterVehicle = autoEnter})
  if veh then
    vehId = veh:getID()
    spawn.safeTeleport(veh, spot.pos, spot.rot)
  end
  return veh
end

local function go(i)
  if not ready() then return end
  idx = ((i - 1) % #entries) + 1
  spawnEntry(entries[idx])
  message(string.format('[%d/%d] %s', idx, #entries, describe(entries[idx])))
end

local function list()
  if #entries == 0 then refresh() end
  for i, e in ipairs(entries) do log('I', logTag, i .. '  ' .. e.model .. '/' .. e.key) end
end

-- shows which config is spawned and returns: vehicle object, model, config key, index
local function current()
  if idx == 0 then message('vehicleCycle: nothing spawned yet') return end
  local e = entries[idx]
  message(string.format('[%d/%d] %s', idx, #entries, describe(e)))
  return vehId and getObjectByID(vehId), e.model, e.key, idx
end

-- appends the current config to <user folder>/vehicleCycle_flagged.txt
-- (tab separated: time, list position, model, key, name, source)
local function logCurrent()
  if idx == 0 then message('vehicleCycle: nothing spawned yet') return end
  local e = entries[idx]
  local info = configInfo(e)
  local f = io.open(logFile, 'a')
  if not f then message('vehicleCycle: unable to write ' .. logFile) return end
  f:write(table.concat({os.date('%Y-%m-%d %H:%M:%S'), idx, e.model, e.key, tr(info.Name), tostring(info.Source)}, '\t'), '\n')
  f:close()
  message(string.format('vehicleCycle: logged [%d] %s/%s', idx, e.model, e.key))
end

-- Seat scan: spawns every config in the active list (without getting in) and checks the 0.40
-- occupant seats the game finds, the same data seatOccupants uses to seat the player.
-- Problems go to <user folder>/vehicleCycle_seats.txt with the interior/dash/seat parts and the mod
-- each one comes from.
local scanFile = 'vehicleCycle_seats.txt'
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

-- Why a config with no seats might be meant that way: trailers, rolling chassis and bare frames have
-- no dashboard/interior part, and some configs (e.g. Gamers' bed trailers) keep the dashboard but leave
-- every seat slot empty. Either way the config chose no seats, so it isn't a fault.
local function seatlessReason(vehData)
  local hasInterior, seatSlots, filledSeatSlots = false, 0, 0
  local function walk(node)
    for _, child in pairs(node and node.children or {}) do
      local slot, filled = tostring(child.id):lower(), (child.chosenPartName or '') ~= ''
      if filled and (slot:find('interior$') or slot:find('dash')) then hasInterior = true end
      if slot:find('seat', 1, true) and not slot:find('^skin_') then
        seatSlots = seatSlots + 1
        if filled then filledSeatSlots = filledSeatSlots + 1 end
      end
      walk(child)
    end
  end
  walk(vehData.config and vehData.config.partsTree)
  if not hasInterior then return 'NO_INTERIOR' end
  if seatSlots > 0 and filledSeatSlots == 0 then return 'NO_SEATS_FITTED' end
end

local expectedStatus = { OK = true, NO_INTERIOR = true, NO_SEATS_FITTED = true }

local function checkSeats(e, id)
  local info = configInfo(e)
  local vehData = core_vehicle_manager.getVehicleData(id)
  local slots = vehData.vdata.occupantSlotsById or {}
  local seatIds, hasDriver = {}, false
  for seatId, slot in pairs(slots) do
    table.insert(seatIds, seatId)
    if slot.defaultPermissionMode == 'driver' then hasDriver = true end
  end
  table.sort(seatIds)
  -- 0.40 makes each seat's in-car camera from its occupant (cameras.occupant[seatId]). A pre-0.40 'dash'
  -- or 'driver' camera left on a part is turned into a separate, seatless 'driver' (cameras.driver).
  local cams = vehData.vdata.cameras or {}
  local occupantCams, noCam = cams.occupant or {}, {}
  for _, seatId in ipairs(seatIds) do
    if not occupantCams[seatId] then table.insert(noCam, seatId) end
  end
  local camInfo = {}
  if #noCam > 0 then table.insert(camInfo, 'no camera: ' .. table.concat(noCam, ',')) end
  if cams.driver then table.insert(camInfo, 'legacy driver camera') end

  local status
  if #seatIds == 0 then status = seatlessReason(vehData) or 'UNSEATED'
  elseif #noCam > 0 then status = 'NO_SEAT_CAMERA'
  elseif cams.driver then status = 'LEGACY_DRIVER_CAMERA'
  elseif not hasDriver then status = 'NO_DRIVER_SEAT'
  else status = 'OK' end
  return status, {e.model, e.key, tr(info.Name), tostring(info.Source), status, #seatIds, table.concat(seatIds, ','),
    table.concat(camInfo, '; '), seatParts(vehData)}
end

local function writeScanRow(row)
  local f = io.open(scanFile, 'a')
  if f then f:write(table.concat(row, '\t'), '\n'); f:close() end
end

local function finishScan(reason)
  M.clear()
  local s = scan
  scan = nil
  local f = io.open(scanFile, 'a')
  if f then
    f:write(string.format('# %s: %d checked, %d OK, %d with no seats by design, %d with problems\n',
      reason, s.checked, s.ok, s.seatless, s.checked - s.ok - s.seatless))
    f:close()
  end
  message(string.format('vehicleCycle: scan %s. %d checked, %d with seat problems (%d with no seats by design), see %s',
    reason, s.checked, s.checked - s.ok - s.seatless, s.seatless, scanFile))
end

local function startScan()
  if scan then message('vehicleCycle: scan already running') return end
  if not ready() then return end
  local f = io.open(scanFile, 'w')
  if not f then message('vehicleCycle: unable to write ' .. scanFile) return end
  f:write(string.format('# seat scan %s, %d configs from %s\n', os.date('%Y-%m-%d %H:%M:%S'), #entries, sourceFile or table.concat(models, ', ')))
  f:write('# model\tkey\tname\tsource\tstatus\tseat count\tseat ids\tcameras\tinterior/dash/seat parts [mod]\n')
  f:close()
  scan = {i = 0, checked = 0, ok = 0, seatless = 0, wait = 0, vehId = nil}
  message(string.format('vehicleCycle: scanning %d configs, stay out of the way of the spawn spot', #entries))
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
    local e = entries[scan.i]
    local row
    if vehData and vehData.vdata then
      local status
      status, row = checkSeats(e, scan.vehId)
      -- OK configs aren't listed; seatless-by-design ones are, but not counted as problems
      if status == 'OK' then
        scan.ok = scan.ok + 1
        row = nil
      elseif expectedStatus[status] then
        scan.seatless = scan.seatless + 1
      end
    elseif scan.wait > scanTimeout then
      row = {e.model, e.key, '', '', 'NO_DATA', 0, '', '', ''}
    else
      return
    end
    scan.checked = scan.checked + 1
    if row then writeScanRow(row) end
    scan.vehId = nil
  end

  scan.i = scan.i + 1
  if scan.i > #entries then finishScan('finished') return end
  local e = entries[scan.i]
  if scan.i % 10 == 1 then message(string.format('vehicleCycle: scanning %d/%d', scan.i, #entries)) end
  local veh = spawnEntry(e, false)
  if veh then
    scan.vehId, scan.wait = veh:getID(), 0
  else
    scan.checked = scan.checked + 1
    writeScanRow({e.model, e.key, '', '', 'SPAWN_FAILED', 0, '', '', ''})
  end
end

M.onUpdate = onUpdate
M.scan = startScan
M.stopScan = stopScan
M.current = current
M.logCurrent = logCurrent
M.refresh = refresh
M.useModel = useModel
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
