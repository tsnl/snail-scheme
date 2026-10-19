# Starter ore versus paid exploration

`scripts/starter-economy-test` measures the money needed to find and buy a second
mine across 64 fixed seeds. It builds only the small Scheme model probe shared
with [`max-dps-test`](max-dps-test.md), without compiling a renderer. The full
application CI runner reuses its already compiled probe.

```sh
scripts/starter-economy-test --output build/starter-economy-test/report.json
scripts/starter-economy-test --seed 25226
# Repeat without recompiling, including after a max-dps-test build:
node tests/applications/starter-economy-test.mjs build/max-dps-test/probe.wasm
```

This is a budget experiment, **not a calibrated survival guarantee**. The current
600-ore starter reserve was not selected from a measured average exploration
cost. The older DPS test assumes free discovery every three minutes and spends
nothing on observation towers or route defenses. This test makes that missing
cost visible; it does not change the reserve or any other game rule.

## Facts, fixture, and knowledge boundary

`max-dps-probe.sld` reads real prices, initial cash/workers, sight radii, terrain,
deposit rates/reserves, mine upgrades, and mining slots. Actual model ticks measure
the production period. Tick duration comes from the game settings. The host does
not duplicate terrain generation, balancing constants, or purchase acceptance.

Each experiment begins with the actual seeded initial World. It buys the nearest
visible reachable deposit using starting cash. Only after that purchase, the
fixture withdraws that deposit's exact remaining reserve and moves it into the
produced, delivered and bank ledgers. Other deposits remain untouched and supply
no income. This models eventual availability of the starter reserve, not money
available at the start of real play.

Every later purchase runs through `place-cell-outcome`: visibility, permanent
survey, terrain, site occupancy, funds, source and a known walking route must
permit the order. The fixture consumes the already-paid kit into the completed
building, returns its builders to idle hub positions, remembers its real survey
radius, and rebuilds transport. The actual state validator checks the resulting
World, including materials, reservations, workers and finite underground reserves.
Rejected commands leave the fixture unchanged and the next ranked candidate is
tried. This validates the constructed states; it does not prove that ordinary
gameplay reaches them on this instantaneous schedule.

No ticks, enemies, losses, hiring, upgrades, excavation or hauling delays occur.
Towers remain in place and stay paid for. There is no disposal/refund assumption.
Worker sight stays at the hub. The host receives terrain/resource observations
only for cells both visible and surveyed. It floods only that observed ground to
rank possible walking access. It consults the unrestricted map only **after** the
scout stops, to compute the separate oracle comparison.

## Two explicit scout policies

Both policies first try any visible, reachable second deposit, ordered by visible
walking distance from the hub and then cell index. Otherwise they rank legal
level-one tower sites by:

- **Area:** the number of previously unknown cells the tower would reveal, then
  shortest visible hub walk, then cell index.
- **Nearby:** unknown cells revealed per visible hub-walk cell, then area gained,
  walk distance and cell index. Integer cross-products compare the ratios.

Unknown area is scored geometrically: its hidden terrain and deposits are never
inspected. After a successful purchase, the forecast must equal the real model's
newly visible area. Both policies reserve the price of a second extractor and
stop if no revealing purchase is accepted or the next tower would spend that
reserve. They are deterministic heuristics, not models of typical players or
optimal search. The coordinate tie-break favors low rows/columns.

The fixed seeds are `1`, `7`, `65535`, and `1 + 1009*k` for `k = 1..61`.
They sample the seed domain reproducibly, without claiming random-population
confidence or coverage of all 65,535 seeds. The report retains every seed,
accepted/rejected order, stopping reason, and the probe's SHA-256.

## Fuzzy math and the checked invariant

Amounts below are ore; lengths are map cells; times are simulation seconds.
Let `I` be initial cash, `R` the starter reserve, `M` an extractor price, `T` a
level-one tower price, and `G` a level-one artillery price. Available money after
paying the starter is:

```text
B = I - M + R                         currently 160 - 40 + 600 = 720
C(n) = n*T + M                       bare paid expansion through n towers
D_fixed(n) = C(n) + 2*G               one gun allowance at each mine
D_outposts(n) = C(n) + (n+2)*G        also one gun per purchased tower
S = T + M                            spare tower/extractor allowance: 65
```

The defense terms are **price allowances only**. The experiment does not place
those guns, check line of sight, cover all three fronts, or prove the chain safe.
Their extra sight is not credited to scouting. Spare allowance `S` is an explicit
policy margin for one additional or replacement tower and extractor. It is not a
measured repair budget and assumes no refunds. Mine upgrades, additional workers,
hub capacity, other weapons and losses all compete for `B` in real play.

The oracle obtains a lower bound `n_min` from the complete initial hub-and-starter
survey circles. Each new unupgraded tower center must lie in existing survey, so
one tower can extend geometric reach by at most its radius. For each other
physically reachable deposit, find the smallest integer `n` for which its distance
from an initial center is at most `initial_radius + n*tower_radius`; take the
minimum across centers and deposits. Squared integer distances avoid rounding
at circle boundaries. The bound ignores obstacles, occupied sites, integer
placement and the intermediate survey required by walking routes. It is **not
an achievable route or its paid cost**, even when its selected deposit has a
short unrestricted walking path. It applies to these level-one tower policies,
not every possible strategy involving upgrades or relocation.

CI checks the following necessary budget condition on every sampled seed:

```text
M + n_min*T + (n_min+2)*G + S <= B
```

This leaves room for the optimistic tower chain, the stated gun allowance, and
the spare allowance. Passing is necessary for that protected-price target under
this bound; it is not sufficient for a blind scout, actual gun coverage or
survival. Every accepted order must also deduct its exact price once, rejected
orders spend nothing, and `credits + spent = I + R` after the one-time reserve
delivery. No purchase borrows beyond that explicit eventual budget. Whenever a
scout succeeds, its paid cost must be at least the oracle floor.

Policy success rates, bare/defended margins and timing are diagnostics. A failed
policy does not prove mathematical impossibility, and a passed geometric check
does not erase a failed policy. There is no frozen failing-seed exception or
assertion that either scout reliably succeeds.

## Measured baseline and remaining calibration gap

The initial 64-seed run using the current rules gives:

| Measurement | Area policy | Nearby policy |
| --- | ---: | ---: |
| Second mine reached | 63/64 | 63/64 |
| Mean expansion ore, successful seeds only | 99.13 | 238.41 |
| Median / 90th / 95th percentile ore, successes only | 90 / 90 / 140 | 240 / 290 / 390 |
| Maximum successful expansion ore | 365 | 715 |
| Maximum successful tower count | 13 | 27 |
| Reached with two-gun price allowance affordable | 63/64 | 62/64 |
| Reached with outpost-gun price allowance affordable | 61/64 | 21/64 |

**Both policies exhaust their tower budget on seed 25226.** They spend 675 ore
on 27 towers, retain 45, and still have not bought a second extractor. That seed
stays in every success/affordability denominator. Cost quantiles are conditional
on success; there is no complete-sample mean completion cost for a run that never
completes. The JSON includes the unsuccessful spending and full purchase trace, not an
invented completion price.

The area policy's long-chain bias is concrete: on that seed it moves from a hub
at `(64,56)` far west and south while chasing unknown area, despite a nearby
oracle target only 33 walking cells away. Nearby scoring buys more overlapping
coverage but still fails that seed. No further policy tuning or economy retuning
is hidden in these results.

Across all 64 seeds, the geometric bare floor is 65–90 ore (mean 89.22), and its
chosen target is 16–33 unrestricted walking cells away. Including the oracle gun
allowance and spare allowance requires 280–355 ore against `B=720`. These figures
show cheap geometric opportunity, not a demonstrated protected scouting plan.
The observed policy failures and defense deficits leave the calibration question
open. They do not establish that throwing away unprotected towers is intended.

## Reserve size is not a deadline

For reserve `R`, yield per occupied slot `q`, occupied slots `s`, production period
`p` ticks, and tick duration `dt`, an ideal fully staffed depletion window is:

```text
ceil(R / (q*s)) * p * dt
```

This assumes an already operational mine, uninterrupted mining, enough workers,
and immediate removal of all output so storage never blocks production. The report
also caps staffing by the initial worker count. Construction, kit travel, hauling,
other worker jobs, danger and recovery are absent; real depletion can take longer.
These are production bounds, not measured expedition completion times.

| Mine level | Slots | Cumulative upgrade cost | Ideal full-reserve duration | Ideal final 10% |
| --- | ---: | ---: | ---: | ---: |
| 1 | 1 | 0 | 300 s | 30 s |
| 2 | 2 | 40 | 150 s | 15 s |
| 3 | 3 | 200 | 100 s | 10 s |

All levels share the same 600 reserve. Upgrading spends part of the expansion
budget and depletes it faster; it never creates more ore. A 10% depletion warning
can therefore arrive with only 10–30 ideal mining seconds left. It is an urgent
warning, not evidence that there is enough time to begin paid exploration then.
