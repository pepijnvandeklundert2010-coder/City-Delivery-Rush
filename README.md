# City Delivery Rush

A multiplayer Roblox game. Players pick up orders that NPCs place at city shops, then race to deliver them before the round timer runs out. Every delivery pays coins, and fast deliveries earn a tip.

This repository holds the game's scripts as files. [Rojo](https://rojo.space) syncs them into Roblox Studio.

## What works now (phase 2 prototype)

- A greybox city is generated when the place has no `Workspace.City` folder. It has a depot, six shops, houses, apartment blocks and a park.
- Rounds loop through intermission (20 s), countdown (5 s), the round itself (5 min) and results (15 s).
- Shops keep posting orders while a round runs. Accept one on the phone (button or **O** key), or walk up to a shop's yellow pad and pick one up there.
- A beam points to the shop, then to the customer's blue pad. Press the prompt there to deliver.
- Pay is base pay for distance plus a tip for speed. The HUD shows how long the current tip lasts.
- The player list shows each round's deliveries and coins. The top three get a bonus, and cash is saved between sessions.

Movement:

- Hold **Left Shift** (or the Sprint button on mobile) to sprint. Sprinting uses stamina, shown in the bar above the order card.
- The run uses Roblox's R15 Ninja run animation instead of the default one.
- Wall running: while moving along a wall, jump, then press jump again next to it. You run along the wall for up to 1.5 s. Press jump again to leap off. Each wall run costs stamina, and you can't run on the same wall twice before you land.

Movement feel (`src/character/MovementFeel.client.luau`, a LocalScript in StarterCharacterScripts): the character speeds up and slows down smoothly, leans into turns, crouches on landing, turns its head and torso toward the camera, plants its feet on slopes and stairs, and the camera bobs and widens at speed. Its tuning values are in the `CONFIG` table at the top of that script.

Every gameplay number you might want to balance is in `src/shared/Config.luau`.

## Setup on Windows

1. Install [Rokit](https://github.com/rojo-rbx/rokit), the toolchain manager. In PowerShell, follow the install line from its README.
2. Clone this repository, open a terminal in it and run:
   ```
   rokit install
   ```
   This installs the Rojo, Selene and StyLua versions listed in `rokit.toml`.
3. Install the Rojo plugin in Studio:
   ```
   rojo plugin install
   ```
4. Open a new Baseplate place in Studio. Then run:
   ```
   rojo serve
   ```
   In Studio, open the **Rojo** plugin and click **Connect**. The scripts appear under ServerScriptService, ReplicatedStorage and StarterPlayerScripts.
5. To test saving in Studio, go to **Game Settings > Security** and turn on **Enable Studio Access to API Services**. Without it the game still runs, but cash isn't saved.
6. Press **Play**.

## Connect Claude to Studio (optional)

Studio has a built-in MCP server. In Studio, open **Assistant**, then **⋯ > Manage MCP Servers**, and turn on **Enable Studio as MCP server**. Then add this to your Claude Code or Claude Desktop MCP config:

```json
{
  "mcpServers": {
    "Roblox_Studio": {
      "command": "cmd.exe",
      "args": ["/c", "%LOCALAPPDATA%\\Roblox\\mcp.bat"]
    }
  }
}
```

## Project layout

| Path | In Studio | What it does |
| --- | --- | --- |
| `src/server/Main.server.luau` | ServerScriptService.Server.Main | Starts every server service |
| `src/server/Services/MapBuilder.luau` | | Generates the greybox city |
| `src/server/Services/RoundService.luau` | | Round state machine, results, podium bonus |
| `src/server/Services/OrderService.luau` | | Creates orders and checks pickups and deliveries |
| `src/server/Services/EconomyService.luau` | | Calculates base pay and tips |
| `src/server/Services/DataService.luau` | | Saves cash and stats (DataStore) |
| `src/server/Services/LeaderboardService.luau` | | leaderstats for the round |
| `src/shared/` | ReplicatedStorage.Shared | Config, shared types, remote events |
| `src/client/` | StarterPlayerScripts.Client | HUD, order phone, waypoint beam, sprint and wall running |
| `src/character/` | StarterCharacterScripts | MovementFeel: momentum, lean, landing, head look, foot IK, camera bob |

## Building your own map

Put a folder named `City` in Workspace and the generator turns off. Mark the parts players interact with using CollectionService tags:

- `PickupZone`: a part in front of a shop. Give it a `ShopId` attribute that matches an `Id` in `Config.Shops`, and a `ShopName` attribute.
- `DeliveryPoint`: a part at a customer's door. Give it an `Address` attribute, for example `12 Oak Street`.
