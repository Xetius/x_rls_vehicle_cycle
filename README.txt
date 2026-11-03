x_rls_vehicle_cycle

Steps through every Gavril D-Series ('pickup') config one at a time, spawning each at the same
spot, so they can all be checked for problems. Flagged configs are logged to a file, and the
cycler can then step through just that file.

The vehicle selector lists configs from every enabled mod; the cycler uses the same list
(core_vehicles.getModel('pickup').configs). Use it in freeroam. In RLS career the spawned trucks
aren't in the garage inventory, so don't save afterwards.

Bindings (Options > Controls > Bindings, Gameplay, search "D-Series cycler"):
- next config / previous config
- set spawn spot: 10m ahead of the vehicle you're in, facing the same way (set automatically on
  the first spawn)
- show current config
- log current config to file: appends to dsCycle_flagged.txt in the BeamNG user folder
  (time, list position, config key, name, source; tab separated)
- switch flagged list / all configs
- scan seats / stop seat scan

Seat scan: spawns every config in the active list (all configs, or the flagged list) at the spot
without getting in, and reads the 0.40 occupant seats the game finds for it (the same data it uses
to seat you; no seats means you get "Unseated"). Problems are written to dsCycle_seats.txt in the
user folder, tab separated: key, name, source, status, seat count, seat ids, and the
interior/dash/seat parts with the mod zip each comes from. Status is UNSEATED (no seats at all),
NO_DRIVER_SEAT (seats, but none marked driver), SPAWN_FAILED or NO_DATA. The file is rewritten
on each scan and ends with a summary line.

Console (GE Lua):
  extensions.load('dsCycle')
  dsCycle.next() / dsCycle.prev() / dsCycle.go(n) / dsCycle.list()
  dsCycle.setSpot() / dsCycle.current() / dsCycle.logCurrent() / dsCycle.clear()
  dsCycle.useFile([path]) / dsCycle.useAll() / dsCycle.toggleSource()
  dsCycle.scan() / dsCycle.stopScan()

useFile reads one config key per line, or the tab-separated log format (key in column 3).
Paths are relative to the user folder; the default is dsCycle_flagged.txt. The launcher's
cleanup moves loose files like these into a dated __cleanup folder, so look there if a list
goes missing.

Releasing: push a semver tag without a v prefix (e.g. 1.0.0). GitHub Actions builds
x_rls_vehicle_cycle_<version>.zip and publishes it as a release.
