# `max-dps-test`

Run `scripts/max-dps-test` to check whether an idealized investment policy can
clear each wave before the next one spawns, using half its theoretical artillery
DPS and discovering another resource deposit every three minutes. A failure exits
with status 1. The script builds a small Scheme model probe; it does not build the
game renderer or run a real-map survival strategy.

```sh
scripts/max-dps-test
scripts/max-dps-test --minutes 10 --output build/max-dps-test/ten-minute.json
scripts/max-dps-test --discovery-minutes 5 --multiplier 0.5 --minutes 360
scripts/max-dps-test --seed 7 --output build/max-dps-test/seed7.json
```

The default six-hour horizon includes the current model's fully escalated enemy
health and maximum ordinary, raid and boss wave sizes. The game has no final
wave. The report states its finite horizon and never treats surviving a timer as
a nest victory. `--minutes 10` checks the intended expedition window and its
first nine-minute boss. It includes twenty spawn windows through minute 10.25.
The requested horizon selects waves by spawn time. Evaluation continues until
the next spawn after the final selected wave, and the console reports that actual
endpoint. With the current schedule, `--minutes 36` includes the boss at minute
36 and checks its damage budget through minute 36.25.

For repeated experiments after one build, run
`node tests/applications/max-dps-test.mjs build/max-dps-test/probe.wasm` with the
same options. Rebuild after changing the game model. The JSON report records the
probe's SHA-256, extracted facts, every wave, discoveries and the final economy.

## What comes from the game

`max-dps-probe.sld` imports `(siegework model)` and `(siegework terrain)` and runs
through linked Wasm. It reads initial ore/workers, construction and upgrade
prices, worker assembly time and population limit, building limits, map deposit
yields, and the wave schedule. Controlled actual model ticks measure artillery
shot damage/cooldown, mining production cadence, occupied slots per mine level,
and each spawned wave's complete HP. Wave composition, rank scaling and the
terrain-dependent raider health reduction therefore remain in Scheme. The host
reads tick duration from the game's settings.

## What is idealized

The initial nearby deposit is known at time zero. Later actual deposits appear
in increasing Manhattan distance from the hub, with cell index breaking ties.
Discovery costs nothing. Every deposit keeps its actual map yield.

The policy first buys productive mine slots and the workers to staff them. It
saves for its next resource purchase before buying artillery, and assigns miners
to the highest-yield slots. Hires pay the real price and retain their assembly
delay without taking an existing miner away for assembly. Once the available
useful resource investment is funded, remaining ore buys the greatest extra shot
damage per ore; ties upgrade an existing gun first. All artillery levels share
the same cooldown, so extra shot damage per ore also ranks extra DPS per ore.
The policy obeys the game's population and total-building limits. It does not
claim to find an exact globally optimal purchase schedule.

Construction and kit deliveries are instantaneous, including both kits of a new
gun. Mine upgrades, worker relocation and hauling are also instantaneous, so all
workers may mine and produced ore is immediately spendable. No worker or building
dies. No ore pays for exploration towers, transport, shields or repairs. These
assumptions remove the practical labor and logistics costs of a real settlement.

The theoretical DPS uses each gun's maximum point-blank shot damage and actual
cooldown. Multiplying by 0.5 halves that continuous capacity. The model permits
perfect target access and allocation: no obstruction, travel, range loss,
overkill or shot-phase penalty. Damage starts when a wave spawns. Unused damage
cannot be saved for another wave. Each wave must fit the integrated capacity
before the next spawn; the report records its HP, effective starting DPS, clear
time and capacity/HP ratio. This is a damage-budget bound, not a discrete combat
simulation.

Wave windows are independent. A missed deadline fails the test and retains the
remaining HP in that wave's JSON result, but that surviving HP is not carried
into later windows. Later results measure each wave's own damage budget rather
than the consequences of an earlier failure.

A pass establishes sufficient damage capacity for this optimistic policy and
horizon. It does not establish real survival. A failure identifies a capacity
deficit in the selected policy; it does not prove that every possible investment
schedule fails. Changing `--multiplier` changes only usable damage, while
`--discovery-minutes` changes resource access.

## Guardrail checks

Every invocation checks a controlled one-gun firing window: full utilization
meets exactly one shot's damage budget, half utilization misses that deadline,
and a long preceding idle period cannot supply a second shot's damage. The
economy also asserts ore conservation and forbids spending future income on
every simulation tick. These checks protect the timing and utilization contract
without copying game balance values into JavaScript.
