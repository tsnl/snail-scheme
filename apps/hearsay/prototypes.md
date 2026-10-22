# Hearsay prototypes

Each prototype asks one question about whether the [design](README.md) is
fun. The rumor mill and the favor ledger can be played on paper or in a
browser; the third prototype waits until both hold up.

```sh
make site
python3 -m http.server 4192 --directory build/hearsay
```

Open `http://127.0.0.1:4192` in a browser with WebGPU and choose a
prototype from the menu. Each prototype's rules live in one library under
`src/hearsay/` (`mill`, `ledger`), and its screen in another (`mill-screen`,
`ledger-screen`); `shell` holds the menu. `tests/` replays scripted games
through the rules and clicks through both screens.

## 1. The rumor mill

*Is steering what people believe fun, and can a player predict it?* If it
is not, nothing else in the design will save it.

### The town

Twenty-four people in three audiences of eight: the Market (people 0–7),
the Docks (8–15) and the Tower (16–23). Each audience is a ring: every
person is tied to the next, and the eighth to the first. Six more ties
cross the rings and join the audiences:

| Tie | Between |
| --- | --- |
| 1–5 | Bix and Fen, across the Market |
| 9–13 | Jun and Nia, across the Docks |
| 17–21 | Rhea and Vic, across the Tower |
| 0–12 | Ana of the Market and Mo of the Docks |
| 7–19 | Hana of the Market and Tam of the Tower |
| 13–17 | Nia of the Docks and Rhea of the Tower |

Bix (1), Kas (10), Nia (13) and Rhea (17) are hubs.

### Stories

A story is about you. It has a trait and an intensity from 1 to 3. Traits
come in opposed pairs: *dangerous* against *harmless*, and *reliable*
against *unreliable*. Each person holds copies of stories, and each copy
remembers its intensity, the shift it was heard and whom it was heard
from.

A person **believes** the most intense story they hold on each pair. First
impressions stick: on a tie, they believe the one they heard first, then
the older story. An audience **believes a trait at level N** when at
least four of its eight members believe that trait at intensity N or more.
Its level is the highest such N, or 0.

### A shift

1. **Act.** Do exactly one of the following.
   - *Deed.* A witness you choose hears a new story:

     | Deed | Story |
     | --- | --- |
     | Rough someone up | dangerous 2 |
     | Make a threat | dangerous 1 |
     | Deliver a job | reliable 2 |
     | Keep a small promise | reliable 1 |
     | Walk away from a fight | harmless 1 |

   - *Pay.* Spend 2 coins. The person drops every story they hold and
     passes nothing on for this shift and the next three. They can still
     hear stories. You take on a liability: you paid them.
   - *Lie.* Tell someone a story you did not earn: reliable 1 or
     harmless 1. You take on a liability: the lie and its first listener.
   - *Lie low.* Do nothing.
2. **Spread.** Everyone who is not keeping quiet passes on each story they
   heard before this shift. A story goes to each tied person who does not
   hold it yet; a hub also passes it one step further, through each of its
   ties. A copy that crosses into another audience grows by 1, up to 3.
   When several copies of one story reach a person in the same shift, they
   keep the most intense.

A new story therefore waits one shift at its witness before it moves,
which is the moment to pay the witness.

**Exposed lies.** A lie is exposed while its first listener holds a story
of the opposite trait that is not a lie. Each exposed lie raises the
listener's audience's level of *unreliable* by 1, up to 3.

### Scenarios

Everyone starts with 10 coins.

1. **Two faces.** Eight shifts. On shift 3 you must rough someone up or
   make a threat in the Docks, in front of a crowd: the witness and
   everyone tied to them hear it at once. You win if, after the eighth
   shift, the Market believes you reliable at 3 and the Tower does not
   believe you dangerous at all.
2. **The smear.** Ten shifts. A rival has told Lia (11) and Oda (14) that
   you skipped out on a debt: unreliable 2. It spreads from the first
   shift. You lose
   the moment the Tower believes you unreliable; you win if it still does
   not after the tenth shift.
3. **Sandbox.** Twelve shifts and no goal.

### In the browser

The town is drawn as its graph: each audience a ring of balls in its own
color, hubs larger, ties as lines. Pillars over a person show what they
believe, colored by trait and as tall as the intensity: dangerous or
harmless on the left, reliable or unreliable on the right. A yellow square
marks who heard something new in the last shift, a dark one who is keeping
quiet.

Point at a person to read their ties and stories, with the path each story
took to reach them; click to choose them, or choose one of their ties from
the list. The buttons below act toward the chosen person, or lie low. The
corner panels show the audiences' levels, your liabilities, and a forecast:
the next changes in each audience's levels if you lie low from now on.

### On paper

Write the town on 24 cards and draw the ties. Stories are slips naming a
deed, a trait and an intensity; copy a slip to spread it, noting the
shift. Use coins and liability cards as above.

### Watch for

- Do players count fronts several shifts ahead, or act one shift at a
  time? Does the forecast make that easy, or does it play the game for
  them?
- Do they use payments as firebreaks, and do lies come back to bite?
- If the town proves too solvable, hide some ties and let `look` reveal
  them. If beliefs pile up, let copies fade by one intensity after six
  shifts.

## 2. The favor ledger

*Does an economy of favors produce interesting trades, or collapse into
hoarding?* On paper, three or four players are fixers trading with each
other. In the browser, one player trades with two rival fixers.

### Pieces

- **Abilities:** doors, muscle, medicine, fencing, paperwork and eyes.
- **Contacts:** Ivo (medicine), Ren (doors), Sal (muscle), Tia (fencing),
  Una (paperwork), Vik (eyes), Wes (doors) and Xan (muscle). Each contact
  wants one thing at a time: half the time an ability other than their own,
  otherwise 2, 3 or 4 coins. Once their want is met, they draw a new one.
- **Markers.** A marker names the contact who owes its holder a favor and
  lends its holder that contact's ability once. A marker is affine: it can
  be spent, given away or traded, never copied, and it lapses at the end of
  the second round after the one in which its contact granted it. A marker
  that changes hands keeps its lapse date.
- **Jobs.** Each requires two or three different abilities. A job needing
  two pays 4 coins and 1 standing; one needing three pays 6 coins and 2
  standing. A job posted in round *r* expires at the end of round *r* + 1.
- **Promises.** A promise is a written debt of one marker with a given
  ability, due at the end of a given round. It is linear: it stays on the
  books until it is honored or refused, and a promise still unhonored when
  it falls due is refused.

### In the browser

You and the two rivals, Vee and Kit, each start with 4 coins, no
standing, and two markers from contacts drawn at random. Vee honors every
promise she can. Kit honors a promise only when the marker is not one he
needs for his own target job. Eight rounds; the most standing wins, and
coins break ties.

Each round:

1. **Market.** New jobs are posted until three are open.
2. **Targets.** Each rival targets the open job for which it lacks the
   fewest abilities among its markers; ties go to the job paying more
   standing, then the one listed first.
3. **Offers.** Each rival posts, in order:
   - a *buy*: 3 coins for a marker with the first ability it lacks;
   - a *sell*: one of its markers that its target does not need, for 2
     coins;
   - a *promise wanted*: 2 coins now for your promise of a marker with the
     ability it lacks last, due at the end of the round after next;
   - a *promise offered*: its promise of a marker with a random ability,
     due at the end of the round after next, for 1 coin now.

   A rival with nothing to buy or sell skips that offer. Once you have
   refused a promise, buys pay 2, sells cost 3, and no one asks you for a
   promise. Each offer can be accepted once, until the round ends.
4. **Your move.** Do any number of the following, then end the round.
   - *Accept an offer.* A marker you give is your oldest with the ability
     asked for.
   - *Meet a contact's want* by paying the coins, or by spending your
     oldest marker with the ability they want. They grant you one of their
     markers. Each contact can be met once a round.
   - *Do a job* by spending your oldest marker for each ability it needs.
   - *Honor a promise* by giving your oldest marker with its ability.
5. **End of round**, in this order:
   1. Each rival that holds markers for every ability its target needs
      does the job, spending one marker per ability.
   2. Each rival gains one marker from a contact drawn at random.
   3. Lapsed markers are removed, so no one can honor a promise with a
      marker about to lapse.
   4. Promises due this round are honored or refused. Refusing costs the
      one who refuses 1 standing, and the board shows everyone's record of
      promises kept.
   5. Expired jobs are removed.

Every offer, contact, job and promise you owe is a button, green when it
would succeed now; the board shows everyone's coins, standing, record and
markers, and what the last end of round did. Each new game from the menu
deals the next seed.

### On paper

Deal the contacts face up and give each player two markers. Each round,
reveal jobs until three are open, then let players trade markers, coins
and written promises freely before anyone meets wants or does jobs. A
refusal costs 1 standing and is marked beside the refuser's name, so the
table can price their promises.

### Watch for

- Do players broker, buying a marker from one fixer to sell to another?
- Do players accept promises, and does a refusal change what others will
  accept from that player?
- Does lapsing keep markers moving, or does hoarding still win?

## 3. One job, start to finish

*Does social engineering feel like a puzzle with several solutions, and
does the fallout feel caused by the player?*

### Scope

- One target: a locked room in the clinic on floor 40.
- About twelve residents with routines across a week, three of them
  keyholders, each with a want, a fear and a price.
- Legwork verbs: watch (learn routines), ask around (learn ties and wants,
  at the cost of a rumor), and tail (follow one person for a shift).
- The reputation inventory as the main screen from the first build.
- The rumor rules from the rumor mill and the markers from the favor
  ledger, revised by what those prototypes taught.
- A week of fallout after the job, shift by shift.

### Watch for

- Without prompting, do testers find at least two ways in?
- Afterwards, can testers explain why each consequence happened, using the
  receipts?
- Do they want to play again with a different approach?
