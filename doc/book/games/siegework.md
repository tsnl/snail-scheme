# Siegework

**[Play Siegework](../play/siegework/)**

Explore, build a supply network, and destroy **all three enemy nests** before
their growing waves overwhelm your hub. Workers choose their own jobs, carry
materials and build your orders. You choose the sites and priorities.

## Your first colony

1. **Tap the glowing ore deposit**, then choose Extractor. It costs **40 ore**
   from your starting 160. This first purchase starts the clock; take your time
   looking around before you order it. Other purchases unlock after this order.
2. **Build a tower** on empty ground to reveal more terrain and extend your
   supply network. Towers cost **25 ore** and provide sight, storage and carts.
3. **Add artillery** to defend your workers and hub. Each gun costs **50 ore**;
   place it where its range covers an approach. Towers themselves provide
   observation and transport, so leave room in your budget for guns.
4. **Expand toward new deposits and the nests.** Ore runs out. Keep enough for
   your next extractor, protect the route, and advance your guns as you explore.

Selecting a tile is free. On empty ground, the popup offers Tower and Artillery.
Tap the same tile again to order the previewed building, or choose its button.
Tapping another tile moves your selection without spending ore. If an order
cannot proceed, the popup explains why: it may need tower coverage, a surveyed
walking route, reachable supplies or more ore.

## Moving around

| Action | Mouse or keyboard | Touch |
| --- | --- | --- |
| Select a tile or structure | Click; or move the cursor with arrow keys and press Enter/Space | Tap |
| Pan | Drag the world or hold WASD | Drag with one finger |
| Zoom | Mouse wheel | Pinch with two fingers |
| Turn the camera | Q / E, or the turn buttons | Turn buttons |
| Return to the hub | Home button or H | Home button |
| Pause | Pause button or P | Pause button |

The construction buttons show their keyboard shortcuts. On a deposit, **1**
orders an extractor. On empty ground, **1** orders a tower and **2** orders
artillery. Select a building before using **U** to upgrade or **C** to cancel its
pending work. At the hub, **F** hires a worker and **R** requests repair.

Click another tile or press Escape to dismiss a selection. Closing a construction
popup leaves an accepted order running. Pause opens a menu with Resume, Restart
and a setting to put the controls on either side. Escape or a tap outside the
pause menu resumes play. Restart asks for confirmation first.

## Keep the colony supplied

Extractors mine **finite deposits**. Upgrades add mining slots and output but do
not refill the ground. **Purple bars** show the fraction of ore remaining in each
known deposit; an extractor carries that bar below its **green health bar**. Empty
reserves keep an empty purple frame. These bars have no text, red warning or
pulse. Workers haul the final stock, then seek other work. Green bars above other
units show their health.

Completed towers connect to the hub and each other along known, passable routes.
Carts move workers and ore through this network. A distant project can stall if
its route or supplies are inaccessible, or its site is no longer visible. Expand
your observation network and keep workers' routes protected. Water blocks travel.

Select a completed structure to see its upgrade price. Tower upgrades improve
observation or transport; artillery upgrades add firepower. Their current services
continue while upgrade materials are on the way. Canceling pending work returns
unused materials, but a worker already carrying a kit must bring it home first.

## Workers, capacity and repair

The hub starts with **12 worker places**. Hiring a worker costs **25 ore** and
requires an existing worker to return and assemble the recruit. Queued recruits
use capacity too.

Select the hub and choose **Upgrade** to add **two places**. The six upgrades cost
100, 200, 400, 800, 1,600 and 3,200 ore, reaching a maximum of **24 workers**.
Capacity increases only when a worker completes the upgrade. Hiring and capacity
upgrades are separate purchases.

**Repair** is a separate hub action. It shows an affordable target percentage and
price before you order it. A worker must return and perform the repair; there is
no automatic healing, and attacks during the job can lower the final health.

The HUD has four readouts:

| Readout | Meaning |
| --- | --- |
| Ore | Available ore for your next orders |
| Health | Remaining hub health |
| Workers | Busy workers out of all workers; the ring shows activity, not capacity |
| Difficulty | Progress toward the next increase in enemy strength |

## Win the siege

Three nests lie beyond your initial view, on different sides of the colony.
Enemy approach directions help you find them and new ore: deposits become
significantly denser as you approach a nest. Select a red attack notification
to move the camera to the trouble spot; its close button briefly mutes that area.

The first wave starts **45 seconds after your first extractor order**. Ordinary
waves are 30 seconds apart and enemy strength increases every **90 seconds**.
Stronger ranks and raids arrive as the run continues. There is no victory timer:
you win by destroying every nest, and lose if the hub falls.

Destroying a nest stops its future waves, lowers difficulty by **two levels**
(to a minimum of one), and reveals a rich **2,400-ore deposit** beneath it.
Build an extractor to mine that reserve; destroying the nest gives no immediate
ore. Its cleared site remains available, and loading a save never refills it.
Enemies already on the map keep their existing health and strength. An early
clear delays the next difficulty increase even at level one; wave timing
continues normally. Artillery has limited range and does more damage up close. Defeated
enemies drop no ore, so a working supply network matters throughout the siege.

If the hub falls, the entire map is revealed. You can pan around and inspect
the frozen colony before restarting; construction and purchases are stopped.

## Saving, help and recordings

Use a current Chromium browser with **WebGPU and WasmGC** support. The hosted game
uses HTTPS and needs no installation or game server. If it cannot start, check
the message at the bottom of the game and your browser's graphics support.

Your colony saves automatically in this browser. One tab can own the save at a
time. Return with the same browser profile and website address to continue;
clearing site data removes the save. A colony played on `localhost` does **not**
automatically transfer to this website: browser storage belongs to its origin.

Open **Pause → Help** to return to this guide in a new tab while the colony stays
paused. Restart replaces your colony with a new seeded world after confirmation.

Pause also offers an optional recorder and replay controls. **Export dump** keeps
a `.snailrun` history you can reopen for viewing; it is not a transferable colony
save. History starts at the page's checkpoint and is bounded, so export before
reloading if you want to keep it. Replay leaves your live saved colony intact.

## For developers

The player guide ends here. For implementation and experiments, see the
[source and local build instructions](https://github.com/tsnl/snail-scheme/tree/main/apps/siegework),
[architecture tour](https://github.com/tsnl/snail-scheme/blob/main/apps/siegework/TOUR.md),
[headless environment](https://github.com/tsnl/snail-scheme/blob/main/apps/siegework/headless.md)
and [recording format](https://github.com/tsnl/snail-scheme/blob/main/apps/siegework/recording.md).
