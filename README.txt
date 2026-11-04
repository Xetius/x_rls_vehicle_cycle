x_rls_vehicle_cycle

Steps through every config of a vehicle model (D-Series, T-Series, anything) one at a time,
spawning each at the same spot, so they can all be checked for problems. Flagged configs are logged
to a file, the cycler can then step through just that file, and a seat scan finds configs that
spawn "Unseated".

The configs are the same list the vehicle selector shows (core_vehicles.getModel(model).configs),
so they include every enabled mod's. Use it in freeroam. In RLS career the spawned vehicles aren't
in the garage inventory, so don't save afterwards.

Which model: by default the model of the vehicle you're in when you first use it. Get in a
T-Series and press "cycle this model" (or vehicleCycle.useModel()) to switch. From the console you
can name one or more models: vehicleCycle.useModel('us_semi'), vehicleCycle.useModel({'pickup',
'us_semi'}). Model keys are the vehicle folder names (pickup = D-Series, us_semi = T-Series).

Which mod: vehicleCycle.useMod('gamer') cycles every config from one mod, on whichever models it
covers. Part of the name is enough if it only matches one mod; if it matches several they're shown
and the list stays as it was. A mod's configs are the ones the vehicle selector shows it as the
source of, so a parts-only mod has none. 'BeamNG - Official' is vanilla, 'Custom' your own saved
configs. useModel switches back to models.

Finding the names, printed to the console (optionally only those containing some text; the first
use can take a moment with a lot of mods):
- vehicleCycle.listModel(['gavril']): model key, config count, name
- vehicleCycle.listMod(['gamer']): config count, mod name, the models it covers

Bindings (Options > Controls > Bindings, Gameplay, search "Vehicle cycler"):
- cycle this model: every config of the model of the vehicle you're in
- next config / previous config
- set spawn spot: 10m ahead of the vehicle you're in, facing the same way (set automatically on
  the first spawn; vehicleCycle.setSpot(15) for more room, e.g. for trucks)
- show current config
- log current config to file: appends to vehicleCycle_flagged.txt in the BeamNG user folder
  (time, list position, model, config key, name, source; tab separated)
- switch flagged list / all configs
- scan seats / stop seat scan

Seat scan: spawns every config in the active list at the spot without getting in, and reads the
0.40 occupant seats the game finds for it (the same data it uses to seat you; no seats means you
get "Unseated"). Problems are written to vehicleCycle_seats.txt in the user folder, tab separated:
model, key, name, source, status, seat count, seat ids, camera problems, and the interior/dash/seat
parts with the mod zip each comes from. Status is one of:
- UNSEATED: no seats, though the config has a dashboard and doesn't leave its seats empty (a fault)
- NO_SEAT_CAMERA: a seat has no camera (its occupant doesn't give one)
- LEGACY_DRIVER_CAMERA: seats are fine, but a pre-0.40 dashboard adds its own driver camera with
  no seat (0.40 takes the driver camera from the seat occupant)
- NO_DRIVER_SEAT: seats, but none marked driver
- SPAWN_FAILED / NO_DATA: the config didn't load
- NO_INTERIOR: no seats and no dashboard/interior part (trailers, rolling chassis, bare frames)
- NO_SEATS_FITTED: no seats because every seat slot is left empty (e.g. Gamers' bed trailers)
The last two are seatless by design: they're listed but not counted as problems. Configs that
seat you aren't listed. The file is rewritten on each scan and ends with a summary line.

Console (GE Lua):
  extensions.load('vehicleCycle')
  vehicleCycle.useModel([model or {models}]) / vehicleCycle.useMod(name) / vehicleCycle.useFile([path])
  vehicleCycle.useAll() / vehicleCycle.listModel([text]) / vehicleCycle.listMod([text])
  vehicleCycle.next() / vehicleCycle.prev() / vehicleCycle.go(n) / vehicleCycle.list()
  vehicleCycle.setSpot([metres]) / vehicleCycle.current() / vehicleCycle.logCurrent() / vehicleCycle.clear()
  vehicleCycle.toggleSource() / vehicleCycle.scan() / vehicleCycle.stopScan()

useFile reads one config per line, in any of these forms, and can mix models:
- the flagged log (time, position, model, key, ...)
- the seat scan output (model, key, ...), so vehicleCycle.useFile('vehicleCycle_seats.txt') steps
  through the problem configs
- the old dsCycle log (time, position, key, ...)
- model/key, or a bare key
A key with no model is looked up in the active model(s), then the D-Series. Paths are relative to
the user folder; the default is vehicleCycle_flagged.txt. The launcher's cleanup moves loose files
like these into a dated __cleanup folder, so look there if a list goes missing.

Releasing: push a semver tag without a v prefix (e.g. 1.0.0). GitHub Actions builds
x_rls_vehicle_cycle_<version>.zip and publishes it as a release.
