# Hearsay prototypes

Each prototype asks one question about whether the [design](README.md) is
fun. The first two are played on paper, so that the rules can change
between rounds; the third is the first one that needs code. Play the first
two in either order, and build the third only after both hold up.

## 1. The rumor mill

*Is steering what people believe fun, and can a player predict it?* If it
is not, nothing else in the design will save it.

### Materials

- 24 person cards in three audiences of eight: the Market, the Docks and
  the Tower. Lay them out and draw ties between them, two to four per
  person, with a few ties crossing between audiences. Mark four people as
  hubs.
- Story slips. Each names a deed, a trait and an intensity from 1 to 3:
  "beat up the fence: dangerous 2".
- Ten coins and a pile of liability cards.

### A turn

Each turn is one shift.

1. **Act.** Do one of the following.
   - *Deed.* Write a story slip and give it to the person who witnesses it.
   - *Pay a witness.* Spend 2 coins to take one slip back from a person
     before it spreads. That person now holds a secret: you paid them.
     Draw a liability card naming them.
   - *Plant a story.* Give someone a slip for the opposite trait at
     intensity 1. It is a lie: draw a liability card naming its first
     listener.
   - *Lie low.* Do nothing.
2. **Spread.** Every slip copies to each tied person who does not hold it
   yet. Hubs pass it two steps. A copy that crosses into another audience
   grows by 1, up to 3.
3. **Settle.** A person holding a story and its opposite believes the more
   intense one; on a tie, the older one. An audience believes a trait at
   intensity N when at least half its members believe a story of that
   trait at N or more.

### Scenarios

- By shift 8, the Market believes you are reliable at 2 and the Tower does
  not believe you are dangerous at all. On shift 3 you must commit a
  dangerous deed in the Docks.
- On shift 1 a rival starts "unreliable 2" at the farthest hub from you.
  Keep the Tower from believing it by shift 10.
- At the end, any liability whose named person holds a slip contradicting
  your lie comes due: lose 1 from your best belief in that person's
  audience.

### Watch for

- Do players count fronts several shifts ahead, or act one turn at a time?
- Do they use firebreaks, and do the liabilities they take on matter
  later?
- If deterministic spread proves too solvable, hide some ties face down
  and let asking around reveal them, at the cost of starting a rumor that
  you were asking. If beliefs pile up, drop each slip one intensity after
  six shifts.

## 2. The favor ledger

*Does an economy of favors produce interesting trades, or collapse into
hoarding?* Three or four players play fixers. They stand in for the
characters, so the economy can be tested before any character behavior
exists.

### Materials

- A deck of contact cards. Each names a person, one ability (doors,
  muscle, medicine, fencing, paperwork or eyes) and one want, which costs
  an ability or money.
- Marker tokens, one stack per contact, each naming the contact who owes
  its holder.
- A deck of jobs. Each requires two or three abilities and pays money and
  standing.
- Paper for promises.

### A round

1. **Market.** Reveal three jobs.
2. **Deal.** Players trade markers, money and promises freely. A promise is
   a written note, "I owe you one paperwork", and it is linear: it stays in
   front of its writer until it is honored or refused.
3. **Act.** Spend a contact's marker to use their ability for one job.
   Meet a contact's want to take one of their markers. Complete jobs.
4. **Upkeep.** A marker held for three rounds without being spent lapses.
   A player who refuses a promise loses one standing, and every promise
   they hold out is marked "refused once".

The player with the most standing after eight rounds wins.

### Watch for

- Do players broker, buying a marker from one player to sell to another?
- Do players accept promises, and does a refusal change what others will
  accept from that player?
- Does lapsing keep markers moving, or does hoarding still win?

## 3. One job, start to finish

*Does social engineering feel like a puzzle with several solutions, and
does the fallout feel caused by the player?* This is the first prototype
that needs code.

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
