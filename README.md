# Forever Maps

Directions to anywhere in the world, the way a phone map works. Type where you want to go, or right-click the world map, and Forever Maps finds your way from where you stand.

## Features
- **Your location is automatic.** Just enter the destination: town, flight master, dock, dungeon entrance or landmark, with suggestions as you type.
- **Drop a pin.** Right-click anywhere on the world map and choose **Route here**.
- **Three ways to get there.** Run, Fly and Boat tabs, each with a travel time.
- **Faction aware.** Alliance and Horde get different routes: only your own and neutral flight masters, boats and zeppelins. Running routes avoid enemy towns, or warn you when there is no other way.
- **Your flight paths.** Open any flight master's map once and the flight paths you know are saved for that character. Tick or untick any flight path yourself and the route updates instantly.
- **Live guidance.** A next-step box with an arrow and distance, the full step list, and the route drawn on the world map. Leave the route and it recalculates.
- **Zone names everywhere.** Every step names the place and its zone, e.g. *Take the boat from Theramore (Dustwallow Marsh) to Menethil Harbor (Wetlands)*.
- Covers both continents, the Deeprun Tram, boats, zeppelins and lifts.

## Install
1. Download `ForeverMaps-<version>.zip` from the latest release, or install and update it from the Relax Coach desktop app (**Updates → More addons**).
2. Copy the `ForeverMaps` folder into `World of Warcraft\_forever_\Interface\AddOns\`, so the file ends up at `AddOns\ForeverMaps\ForeverMaps.toc`.
3. Restart the game, or type `/reload`.

## First time
A welcome window shows your nearest flight master. Visit it and open the flight map once so Forever Maps knows which flight paths you have.

## Commands
- `/fmaps` opens or closes the window
- `/fmaps <place>` routes straight to a place
- `/fmaps welcome` shows the welcome window again
- `/fmaps reset` clears this character's saved flight paths

## Notes
Boat and zeppelin times are estimates. Walking data is based on shortest-path-forever (GPL-3.0).

## Tests
Offline checks with a mock client:

```sh
lua5.1 test/route_test.lua ForeverMaps
lua5.1 test/harness.lua ForeverMaps
```

## Compatibility
Built for WoW: Forever (Interface 16001).

## License
GPL-3.0. See `LICENSE`.
