# Enemy AI redesign: working notes

Status: **design complete 2026-10-22; implementation started.** Local notes, not upstream.

## Already built (local, uncommitted)

- `wave-interval` 300 → 600 ticks (`siege.sld`): waves every 60 s.
- Turrets have 0 reach: no sight, no wire reach (`world.sld` `kind-reach`).
- Turrets wire **only to pylons** (`joinable?` / `node-kind` in `world.sld`,
  used by `link` and by `in-reach?` in `colony.sld`).

## Decided

- **Decision per step.** Each enemy decides from:
  - its own position,
  - the hub position,
  - structures within 4 cells of it,
  - the full terrain map.
- **Knowledge (revised 2026-10-22).** Enemies know the whole terrain map.
  They know the hub's position always, but other structures only when
  within 4 cells of that enemy. (Replaces the earlier "discover terrain
  through sight" idea.)
- **Navigation.** Head for the hub on roughly the shortest path, with small
  per-enemy differences for variety.
- **Burrowing is a choice, not a flag (2026-10-22).** The `burrower` flag
  goes away. Every species can dig through rock, and chooses to:
  - with **low** probability normally,
  - with **medium** probability if digging gives a shorter path,
  - with **high** probability if there is no other path.
  - **When:** the choice is made once each time the enemy plans its route.
  - **Chances:** low = 5%. Shorter-path chance = 5% + x·n%, where n is how
    many cells digging saves and x is a tuning factor. So small savings
    barely raise the chance and there is no separate minimum.
  - **Dig speed is damage-based:** an enemy digs at its own attack damage.
    Different terrain has different health.
- **Aggression.** Each enemy has an aggression level. It decides whether the
  enemy attacks a structure within 4 cells or ignores it.
- **Attack chain.** Once an enemy attacks a structure in sight, it keeps
  attacking structures in sight until none are left, then goes back to
  heading for the hub.
- **Workers are targets (2026-10-22).** Workers within 4 cells count like
  structures for the aggression roll and the attack chain. Workers fight
  back.
- **Repeatable randomness.** Any randomness (aggression, path differences)
  comes from the enemy's id and the tick, because saves replay the order
  journal.

## Decided in the 2026-10-22 question round (enemy side)

- **Dig choice** is made once per route plan. Two candidate routes: the
  best walking route and the best route allowed to dig. Each cell of
  rock or wall on the digging route costs its dig time, which is that
  terrain's health divided by the enemy's dig rate.
  - n = seconds saved by the digging route, counting the dig time.
  - chance = min(100%, base + x·n%). If n ≤ 0, the chance is just the base.
  - No walking route means n is infinite, so the chance is 100%.
  - Normal enemies: base 5%, x = 2 (each second saved adds 2%). *(x chosen
    by Claude, to tune.)*
  - **Burrowers** come back as a flag: 5% of enemies. They dig 3× faster,
    and are more likely to dig: base 15%, x = 4. *(numbers chosen by
    Claude.)*
- **Terrain health:** rock 300, ice 200, water can't be dug. Walls 200 /
  250 / 300 by level (base 100 × 2 / 2.5 / 3).
- **Dig rate:** an enemy's rank damage per hit, with dig hits every 2 ticks;
  burrowers ×3.
- **Path variety:** a fixed left or right lean per enemy, plus random
  sideways steps that are not longer.
- **Sight:** 4 cells. Rock and walls do NOT block it.
- **Aggression:** rolled once for each structure or worker that comes into
  sight. Normal enemies roll 10–50%, raiders 30–90%, Beasts 10%. Raiders and
  Beasts are presets on top of that; raiders keep their speed and lower
  health.
- **No revenge.** Being shot doesn't make an enemy target the turret
  unless that turret is within its 4-cell sight anyway.
- **Attack mode:** the nearest structure or worker in sight. Skip anything
  unreachable (for example across water).

## Workers and the Portal (added 2026-10-22)

The doc now covers more than enemy AI: this section is colony-side.

### Decided

- **Workers are back, labour only.** Building, upgrading and repairing need
  a worker to walk to the site. Workers don't carry the cost or ore.
- **Workers:** 20 energy, 3 s to build, maximum 20, start with 3. They're
  built from a "Build worker" button on the hub, in the same queue as
  buildings, and they replace the hub's build slots.
  - Stats: 60 health, 6 damage per second, adjacent range only, a move
    every 5 ticks.
  - **No fleeing.** They fight back when hit or when an enemy is next to
    them, then resume work.
  - Jobs are taken automatically: oldest job first, nearest free worker.
  - A worker's death leaves the site's progress for the next worker.
  - Workers can't dig.
- **Portal is an upgrade on a pylon.** It's a separate upgrade choice on
  any built pylon (level 1–3), costing 60 energy and taking 4 s. The
  pylon keeps its pylon role: it carries power and powers turrets, with
  its current level's reach. Portals are linked: workers jump instantly
  between powered portals and the hub, then walk from whichever is
  closest to the job by walking route. They return to the nearest one.
  **A portal works only while powered** (revised: earlier notes said
  portals need no power).
- **Walls:** player-built terrain on open ground only, built and upgraded
  by workers.
  - Costs 10, then +10, then +15 energy, 2 s each. Health 200 / 250 / 300.
  - Enemies treat walls as terrain: they know them from the map and dig
    through them.
  - A wall carries power to any pylon that can see it (within the pylon's
    sight radius, no rock in the way). Power passes along chains of
    touching walls. Walls never power turrets directly. Walls block shots
    like rock, but not enemy sight.
  - Removing a wall refunds half its energy.
- **Hotkeys:** 4 wall, 5 portal (on top of 1–3 build and U upgrade).

### Practical

- Delete all existing Siegework saves.
- Tests need recalibrating to the new rules.
- Work on local branch `nitin/siegework-patches`; nothing pushed.

### Reference

The old worker system is in commit `bf828bc8`,
`apps/siegework/src/siegework/model.sld`. It was much bigger: workers
carried paid "kits", ore went through workers and depot freight, workers
were assembled at the hub, and routes avoided known threats. `#363`
replaced workers with the energy network and build slots.

### Open questions

None. Design is complete; implementation is next.

## Current AI (being replaced), for reference

See `src/siegework/siege.sld`. Targets are revenge on a turret that hit
them, raiders picking exposed outposts more than 9 cells from the hub, and
otherwise the hub. Routes are distance fields over the full terrain.
Enemies stop at the first building they bump into.
