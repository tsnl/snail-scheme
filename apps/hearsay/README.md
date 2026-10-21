# Hearsay

*Working title.* A role-playing game that generates stories from a dense
social simulation: a city where the scarcest resource is what people
believe.

**Status: design only.** Nothing here is implemented. This folder records
the design and, in [prototypes](prototypes.md), the experiments that will
test whether it is fun. Implementation is deliberately out of scope.

## The idea

RimWorld generates stories from survival. Colonists build, starve and break
under pressures the player can see and itemize. Hearsay generates stories
from reputation. The player survives by managing who owes whom, who knows
what, and which stories about them are going around. Material resources
still matter, and every material thing has a social history.

The setting borrows cyberpunk's premises without its lore: corporations
above, gangs below, surveillance that turns information into evidence, and
augmentation that buys capability with trust. Conflicts resolve through
fighting, sneaking, talking and paying, and through planning: seeing a
conflict coming and defusing it before it starts.

## Two kinds of things

Everything the player can hold is one of two kinds.

**Material things are affine.** A pistol, a keycard, cash, a car, a hard
drive, an implant: each is in exactly one place. It can be moved, used up
or destroyed, but never duplicated. Giving it away means no longer having
it; stealing it means taking it from someone. The question about a material
thing is *who has it*.

**Information is copyable.** A secret, an address, a password, a person's
want, the contents of a recording: telling it to someone does not lose it.
The question about information is *who knows it*, and the answer is a set
that only grows. Nothing can be untold. Information can be contained, by
reaching the next listener first; discredited, by making people doubt it;
or buried under a louder story. It can never be recalled.

The two kinds behave differently in every way that matters to play:

- **Value.** A material thing is worth its use. Information is worth its
  exclusivity: a secret known to one person is leverage, and a secret known
  to everyone is news. Every copy spends some of its value.
- **Loss.** Material things are lost all at once and can be recovered.
  Information leaks gradually and can only be contained. Theft is an event;
  a leak is a process.
- **Evidence** is where the kinds meet: information on a material carrier.
  The contents of a recording copy freely, but only the original proves
  anything. Destroy the drive and what it showed becomes hearsay. Copies
  can be forged; originals can be stolen.
- **Obligations** have two sides. A favor someone owes you is affine: you
  can spend it once, give it away or let it lapse. The same favor, seen by
  the person who owes it, is linear: it stays on their books until it is
  honored, bought out or refused, and refusing is a public act that costs
  them their reputation for keeping their word.

An item's kind tells the player its verbs. Material things can be given,
sold, stolen, used and destroyed. Information can be told, sold, leaked,
forged and discredited. A player who has learned the two kinds can read the
affordances of any item in the game, and so can every character in it.

## The reputation inventory

The main screen is an inventory of social items, each with a receipt.

| Section | Kind | Holds |
| --- | --- | --- |
| Holdings | affine | Money, gear, implants and the carriers of evidence. |
| Markers | affine and linear | Favors owed to you, and favors you owe. |
| Knowledge | copyable | Secrets, wants and intentions you have learned, and who else knows each. |
| Standing | copyable | What each audience believes about you, and where each belief came from. |
| Liabilities | copyable | Lies still standing, grudges against you, and heat. |

Standing is the strange section: it lists copies held by other people. You
cannot hold your reputation, only observe it, and only as far as your
sources reach.

Every line can be traced. "The dock workers think you're dangerous" expands
into the deed, its witness, and the chain of people the story passed
through, with how much it grew at each step.

## Legibility

A dense simulation is only fun if the player can predict it, because only
then can they influence it. Five rules keep it readable.

- **Every number has a receipt**, as in RimWorld's mood breakdown: "Rosa
  distrusts you: you lied about Tuesday (−2); she suspects you killed her
  cousin (−3)."
- **Counts, not decimals.** Favors are tokens, standing comes in tiers and
  plans are clocks with segments. A player can reason about "she owes me
  two" but not about "affinity 0.63".
- **Characters show their plans, and intel is how you see them.** Into the
  Breach is fun because the enemy's next move is visible. Social
  intentions should be visible too, once you have learned them.
- **Unknowns are marked.** A `?` stands where information is missing, so
  the player knows what to investigate.
- **Characters have the player's verbs.** You understand a betrayal because
  you have committed one.

## Mechanics

### Favors

Favors are markers: earned by doing something for someone, spent to make
them act against their inclination. They can be transferred: "Dex owes me
one; I'll sign it over to you." A fixer is a favor broker. Owing a favor is
a liability, because the gang lieutenant who holds your marker chooses when
to collect.

### Reputation is held by audiences

There is no global reputation. Each audience (a gang, a floor of the tower,
a police precinct) holds beliefs about you along a few traits: dangerous,
reliable, discreet, competent. Beliefs come only from deeds someone
witnessed, and then they spread.

That sets the central tension: **fame against heat**. Unwitnessed work is
safe and builds nothing. A signed job, with a calling card or a witness
left alive, turns the deed into standing and also into heat. You can let
someone else take the credit, or frame them.

### Rumors spread like fire

RimWorld's fire is legible: you watch it spread and build firebreaks.
Rumors work the same way. They travel along relationships one step per
shift, speed up through hubs like bartenders, fixers and message boards,
and grow as they cross between audiences. The player sees the front: "The
dock workers will hear about the warehouse in about two days." Firebreaks
are paying the witness, planting a counter-story, leaving the district, or
getting ahead of the story and owning it.

Investigating leaks too. Asking around about the night nurse starts a
rumor that someone is asking about the night nurse.

### Every lie is a debt

A lie is a copyable belief planted on purpose, and it becomes a liability:
who believes it, and what evidence would contradict it. "Rosa believes you
were at the club on Tuesday. The club's cameras disagree." Material things
leave trails that make such evidence: a pistol with a history, an implant's
serial number, a car caught on camera.

### Your contacts are your abilities

A back-room surgeon is healing and implants. A fence is a place to sell. A
precinct clerk makes heat go away. A netrunner opens doors. Contacts need
upkeep, with favors flowing both ways, and they have lives of their own:
when your surgeon is arrested, you break her out or find another.
Progression is the network, and a network can be poached, killed or
turned.

The crew works the same way. Recruits arrive with backgrounds that tie them
into the city, so **when you hire someone, you hire their enemies**, along
with their exes, debts and siblings.

### Every door has a keyholder

Every obstacle is guarded by people, and every person has a want, a fear
and a price, as in Hitman's opportunities. Legwork finds the keyholders.
Suppose you need into the clinic on floor 40, and legwork turns up three:

- a night nurse who wants her brother out of a gang;
- a guard who owes a loan shark six thousand;
- a director who secretly sells organs.

You pay off the guard's debt, so now he owes you. The loan shark notices
someone paid and starts asking around. A rumor, "someone is buying the
clinic's staff", heads toward the clinic's head of security and will
arrive in two days, so you go tomorrow. Three weeks later the guard is
fired, blames you, and sells what he knows. None of that was scripted.

### Every approach leaves a footprint

Every approach acts on the same social state, so their consequences can be
compared:

- **Fighting** leaves bodies, witnesses, grudges among the dead's kin (as
  in Shadow of Mordor's Nemesis system) and a reputation for danger.
- **Sneaking** builds no standing and little heat, unless evidence surfaces
  later.
- **Talking** spends trust, fear or leverage.
- **Paying** costs money and leaves a trail. A bribe is also a secret the
  two parties share.

Before committing, the player sees a consequence preview, limited to what
they know: "This kill angers the dock workers, Rosa (sister), and `?`."
Standing pays off in standoffs: fights that end before they start, because
the other side has heard what you did on floor 12.

Talking is a set of moves with visible odds, not a dialogue tree: ask,
offer, threaten, lie, reveal, call in a favor. Each move draws on one named
source. Trust drives asks and lies, fear drives threats, a matching want
drives offers, and a secret gives leverage.

### Clocks, calendars and planning ahead

Every faction and every character's scheme advances on a clock with
segments, as in Blades in the Dark: "The corporation buys out the market
floor: 5 of 8." Jobs are steps of those schemes put out for hire, so the
job board shows the tower's politics, and taking a job takes a side. A
fixer's service is hiding who the client is; discovering who really hired
you is a story.

Planning resolves conflicts too. You know the lieutenant meets his boss on
Friday, so you plant the rumor on Wednesday. You see a rival's scheme
against you at 4 of 6 and defuse it before it fires. The best fight is the
one you prevented.

Blades-style flashbacks fit here, constrained by the simulation. Legwork
earns preparation. During a job, spending one preparation reveals that you
had already bribed the elevator technician, but only if the tower holds an
elevator technician whose want you could have met.

### Augmentation

Implants are material things with social effects. They raise capability
and your reputation for danger, lower trust, close gentle options in
conversation, and tie you to the surgeon who maintains them, who now holds
leverage over you.

## Scope: dense, not vast

The world is one tower of about 150 residents, near Dunbar's number, so
that a player can know everyone. Height is class: corporate offices at the
top, markets in the middle, gangs and squats below. Infrastructure is
leverage: whoever runs a floor's power junction has that floor in their
debt.

## Traps

- **Noise.** Dense simulations produce endless meaningless events. Surface
  only events near the player in the social graph, and let a storyteller
  ripen tensions that already exist rather than inject random ones.
- **Vending-machine characters.** "Give a gift, gain opinion" makes people
  feel like machines. Wants are specific and finite: once you have paid her
  brother's debt, money no longer buys her.
- **Killing every witness.** Violence must cost socially. Missing people
  raise questions, and the dead have kin.

## Influences

| Game | What to take |
| --- | --- |
| RimWorld | Stories from visible pressures; itemized moods; fire as a legible threat. |
| Crusader Kings III | Hooks as countable leverage; schemes with visible odds. |
| Blades in the Dark | Clocks, heat, faction standing and flashbacks. |
| Into the Breach | Telegraphed intent turns threats into puzzles. |
| Hitman | Every target guarded by people with routines and opportunities. |
| Shadows of Doubt | A dense city of residents whose belongings and records are evidence. |
| Talk of the Town | Characters whose beliefs can be wrong and spread by conversation. |
| Prom Week | Social exchanges with explicit, inspectable reasons. |
| Shadow of Mordor | Enemies who remember. |

## Open questions

- **Who is the player?** A lone operator, a crew boss or a fixer who
  brokers other people's jobs. The crew is where RimWorld's drama lives,
  among the player's own people. The current lean is a small crew led by
  the player's character, with becoming a fixer as the late game.
- **How does time pass?** Turns of one shift each make rumor fronts
  countable; real time with pause feels more alive. The current lean is
  shifts.
- **How does a story end?** Retiring, leaving the tower, becoming a legend,
  or dying and continuing as someone in the crew.
