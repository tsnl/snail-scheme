;; The rumor mill: 24 people in three audiences, joined by ties along which
;; stories about the player spread one step per shift. The rules are in
;; prototypes.md; (hearsay mill-screen) plays them in the browser.
(define-library (hearsay mill)
  (export
   Mill
   Scenario
   TwoFaces
   Smear
   Sandbox
   scenarios
   Rules
   scenario-rules
   new-mill
   mill-over?
   Deed
   Rough
   Threat
   Deliver
   Keep
   Walk
   deeds
   deed-name
   deed-effect
   Trait
   Dangerous
   Harmless
   Reliable
   Unreliable
   Action
   Do
   Pay
   Mislead
   Wait
   take-shift
   refusal
   last-shift
   Progress
   Met
   Unmet
   Upcoming
   Due
   Done
   Goal
   mill-goals
   mill-result
   forced?
   audience-name
   audience-beliefs
   person-beliefs
   trait-name
   story-lines
   person-count
   person-name
   first-name
   market
   docks
   tower
   audiences
   audience-of
   hub?
   ties
   neighbors
   belief
   quiet?
   newly-heard
   liabilities
   forecast)
  (import
   (snail core base)
   (snail shell wire))
  (begin

    ;; ---- Town ----

    (define person-count (→ I64) 24)

    ;; The audiences in order. Person p belongs to audience p / 8.
    (define market (→ I64) 0)

    (define docks (→ I64) 1)

    (define tower (→ I64) 2)

    (define audiences (→ (List I64)) (list market docks tower))

    (define (audience-of (person I64)) (→ I64)
      (quotient person 8))

    (define (audience-name (audience I64)) (→ String)
      (list-ref (list "Market" "Docks" "Tower") audience))

    (define (person-name (person I64)) (→ String)
      (list-ref (list "Ana, courier" "Bix, bartender" "Cal, noodle cook" "Dee, tailor"
                      "Eli, pawnbroker" "Fen, street medic" "Gus, vendor" "Hana, rickshaw driver"
                      "Ike, crane operator" "Jun, stevedore" "Kas, union steward" "Lia, net mender"
                      "Mo, smuggler" "Nia, dock foreman" "Oda, welder" "Pim, night guard"
                      "Quin, analyst" "Rhea, concierge" "Sol, lawyer" "Tam, driver"
                      "Uma, executive" "Vic, security chief" "Wen, architect" "Yara, assistant")
                person))

    ;; Hubs pass a story two steps per shift instead of one.
    (define (hub? (person I64)) (→ Bool)
      (member? person (list 1 10 13 17)))

    ;; Each audience is a ring of eight; chords cross three of the rings and
    ;; three bridges join the audiences.
    (define (ring-next (person I64)) (→ I64)
      (+ (* 8 (audience-of person)) (remainder (+ person 1) 8)))

    (define ties (→ (List (Pair I64 I64)))
      (append (map (lambda (person) (Pair person (ring-next person))) (iota person-count))
              (list (Pair 1 5) (Pair 9 13) (Pair 17 21)
                    (Pair 0 12) (Pair 7 19) (Pair 13 17))))

    (define (neighbors (person I64)) (→ (List I64))
      (append (map ::second (filter (lambda (tie) (= (::first tie) person)) ties))
              (map ::first (filter (lambda (tie) (= (::second tie) person)) ties))))

    (define (first-name (person I64)) (→ String)
      (let ((name (person-name person)))
        (match (string-index name #\,)
          ((Some end) (substring name 0 end))
          ((None) name))))

    (define (members (audience I64)) (→ (List I64))
      (map (lambda (k) (+ (* 8 audience) k)) (iota 8)))

    ;; ---- Stories ----

    ;; Traits come in opposed pairs: indices 0 and 1 are one pair, 2 and 3
    ;; the other.
    (enum Trait
      (Dangerous)
      (Harmless)
      (Reliable)
      (Unreliable)
      (deriving Serialize Deserialize))

    (define traits (→ (List Trait))
      (list (Dangerous) (Harmless) (Reliable) (Unreliable)))

    (define (trait-index (trait Trait)) (→ I64)
      (match trait
        ((Dangerous) 0)
        ((Harmless) 1)
        ((Reliable) 2)
        ((Unreliable) 3)))

    (define (trait-name (trait Trait)) (→ String)
      (list-ref (list "dangerous" "harmless" "reliable" "unreliable") (trait-index trait)))

    (define (same-pair? (a Trait) (b Trait)) (→ Bool)
      (= (quotient (trait-index a) 2) (quotient (trait-index b) 2)))

    (define (same-trait? (a Trait) (b Trait)) (→ Bool)
      (= (trait-index a) (trait-index b)))

    (define (opposite? (a Trait) (b Trait)) (→ Bool)
      (and (same-pair? a b) (not (same-trait? a b))))

    ;; Who started a story: a deed of yours someone witnessed, a lie of
    ;; yours, or a rival.
    (enum Source
      (Witnessed)
      (Lie)
      (Rival)
      (deriving Serialize Deserialize))

    ;; A story's id is its place in creation order, so a lower id is older.
    ;; Its listener is the witness or first listener.
    (struct Story
      ((id I64)
       (trait Trait)
       (intensity I64)
       (label String)
       (source Source)
       (listener I64))
      (deriving Serialize Deserialize))

    ;; A person's copy of a story: how intense it was when it reached them,
    ;; the shift they heard it, and the people it passed through on the way,
    ;; nearest first. The path is fixed when the copy is heard, so it stays
    ;; true even after someone along it is paid to forget.
    (struct Copy
      ((story I64)
       (intensity I64)
       (heard I64)
       (path (List I64)))
      (deriving Serialize Deserialize))

    ;; ---- State ----

    (enum Liability
      (Paid ((person I64) (shift I64)))
      (Told ((story I64)))
      (deriving Serialize Deserialize))

    (enum Outcome
      (Playing)
      (Won ((reason String)))
      (Lost ((reason String)))
      (Ended)
      (deriving Serialize Deserialize))

    ;; `copies` and `quiet` are indexed by person. A person keeps quiet
    ;; through the shift recorded in `quiet`. After the last shift, `shift`
    ;; is one past it.
    (struct Mill
      ((scenario Scenario)
       (shift I64)
       (coins I64)
       (stories (List Story))
       (copies (Vector (List Copy)))
       (quiet (Vector I64))
       (liabilities (List Liability))
       (outcome Outcome))
      (deriving Serialize Deserialize))

    (define (copies-of (mill Mill) (person I64)) (→ (List Copy))
      (vector-ref (::copies mill) person))

    (define (story (mill Mill) (id I64)) (→ Story)
      (list-ref (::stories mill) id))

    (define (holds? (mill Mill) (person I64) (id I64)) (→ Bool)
      (any? (lambda (copy) (= (::story copy) id)) (copies-of mill person)))

    (define (hear (mill Mill) (person I64) (copy Copy)) (→ Mill)
      (Mill-copies-set mill
                       (vector-set (::copies mill)
                                   person
                                   (append (copies-of mill person) (list copy)))))

    ;; Starts a new story at its first listener.
    (define (tell (mill Mill)
                  (trait Trait)
                  (intensity I64)
                  (label String)
                  (source Source)
                  (listener I64))
      (→ Mill)
      (let ((id (length (::stories mill))))
        (hear (Mill-stories-set mill
                                (append (::stories mill)
                                        (list (Story id trait intensity label source listener))))
              listener
              (Copy id intensity (::shift mill) (Nil)))))

    ;; ---- Beliefs ----

    ;; First impressions stick: between equally intense copies, the one
    ;; heard first wins, then the older story.
    (define (stronger? (a Copy) (b Copy)) (→ Bool)
      (cond
       ((not (= (::intensity a) (::intensity b))) (> (::intensity a) (::intensity b)))
       ((not (= (::heard a) (::heard b))) (< (::heard a) (::heard b)))
       (else (< (::story a) (::story b)))))

    ;; The copy a person believes on a trait's pair.
    (define (believed (mill Mill) (person I64) (trait Trait)) (→ (Option Copy))
      (fold-left (lambda (best copy)
                   (cond
                    ((not (same-pair? (::trait (story mill (::story copy))) trait)) best)
                    ((match best ((Some other) (stronger? other copy)) ((None) #f)) best)
                    (else (Some copy))))
                 (None)
                 (copies-of mill person)))

    ;; How intensely a person believes a trait, or 0 if they believe its
    ;; opposite or nothing.
    (define (belief (mill Mill) (person I64) (trait Trait)) (→ I64)
      (match (believed mill person trait)
        ((Some copy)
         (if (same-trait? (::trait (story mill (::story copy))) trait)
             (::intensity copy)
             0))
        ((None) 0)))

    ;; The highest N such that four members believe the trait at N or more.
    (define (raw-level (mill Mill) (audience I64) (trait Trait)) (→ I64)
      (let ((beliefs (map (lambda (person) (belief mill person trait)) (members audience))))
        (fold-left
         (lambda (level n) (if (>= (length (filter (lambda (b) (>= b n)) beliefs)) 4) n level))
         0
         (list 1 2 3))))

    (define (lie? (s Story)) (→ Bool)
      (match (::source s)
        ((Lie) #t)
        (_ #f)))

    ;; A lie is exposed while its first listener holds a story of the
    ;; opposite trait that is not a lie.
    (define (exposed? (mill Mill) (lie Story)) (→ Bool)
      (and (lie? lie)
           (any? (lambda (copy)
                   (let ((other (story mill (::story copy))))
                     (and (opposite? (::trait other) (::trait lie)) (not (lie? other)))))
                 (copies-of mill (::listener lie)))))

    ;; Each exposed lie raises its listener's audience's level of
    ;; unreliable by 1.
    (define (level (mill Mill) (audience I64) (trait Trait)) (→ I64)
      (let ((exposed (filter (lambda (s)
                               (and (exposed? mill s)
                                    (= (audience-of (::listener s)) audience)))
                             (::stories mill))))
        (min 3 (+ (raw-level mill audience trait)
                  (match trait
                    ((Unreliable) (length exposed))
                    (_ 0))))))

    ;; ---- Spread ----

    ;; A copy offered to a person at the end of a shift. Its path starts with
    ;; whoever passes it, so it is never empty.
    (struct Offer
      ((person I64)
       (story I64)
       (intensity I64)
       (path (List I64))))

    (define (quiet? (mill Mill) (person I64)) (→ Bool)
      (>= (vector-ref (::quiet mill) person) (::shift mill)))

    ;; Crossing into another audience grows a story by 1, up to 3.
    (define (grow (intensity I64) (from I64) (to I64)) (→ I64)
      (min 3 (+ intensity (if (= (audience-of from) (audience-of to)) 0 1))))

    ;; One step along each tie, and for a hub a second step onward from
    ;; each neighbor.
    (define (offers-of-copy (person I64) (copy Copy)) (→ (List Offer))
      (concatenate
       (map (lambda (next)
              (let ((intensity (grow (::intensity copy) person next)))
                (Cons (Offer next (::story copy) intensity (Cons person (::path copy)))
                      (if (hub? person)
                          (map (lambda (far)
                                 (Offer far
                                        (::story copy)
                                        (grow intensity next far)
                                        (Cons next (Cons person (::path copy)))))
                               (filter (lambda (far) (not (= far person))) (neighbors next)))
                          (Nil)))))
            (neighbors person))))

    ;; Everyone not keeping quiet passes on each story heard before this
    ;; shift.
    (define (offers (mill Mill)) (→ (List Offer))
      (concatenate
       (map (lambda (person)
              (if (quiet? mill person)
                  (Nil)
                  (concatenate (map (lambda (copy) (offers-of-copy person copy))
                                    (filter (lambda (copy) (< (::heard copy) (::shift mill)))
                                            (copies-of mill person))))))
            (iota person-count))))

    (define (better-offer? (a Offer) (b Offer)) (→ Bool)
      (or (> (::intensity a) (::intensity b))
          (and (= (::intensity a) (::intensity b))
               (< (list-ref (::path a) 0) (list-ref (::path b) 0)))))

    (define (keep-better (best (List Offer)) (offer Offer)) (→ (List Offer))
      (let ((others (filter (lambda (o) (not (= (::story o) (::story offer)))) best)))
        (match (find (lambda (o) (= (::story o) (::story offer))) best)
          ((Some held) (if (better-offer? offer held) (Cons offer others) best))
          ((None) (Cons offer best)))))

    ;; The best offer of each story a person does not hold yet.
    (define (arrivals (mill Mill) (all (List Offer)) (person I64)) (→ (List Offer))
      (reverse
       (fold-left (lambda (best offer)
                    (if (or (not (= (::person offer) person))
                            (holds? mill person (::story offer)))
                        best
                        (keep-better best offer)))
                  (Nil)
                  all)))

    ;; Ends the shift. Offers are all computed from the state before
    ;; anyone hears anything, so a story moves its full distance at once.
    (define (spread (mill Mill)) (→ Mill)
      (let* ((all (offers mill))
             (heard (fold-left (lambda (current person)
                                 (fold-left (lambda (current offer)
                                              (hear current person
                                                    (Copy (::story offer)
                                                          (::intensity offer)
                                                          (::shift mill)
                                                          (::path offer))))
                                            current
                                            (arrivals mill all person)))
                               mill
                               (iota person-count))))
        (Mill-shift-set heard (+ (::shift mill) 1))))

    ;; ---- Scenarios ----

    (enum Scenario
      (TwoFaces)
      (Smear)
      (Sandbox)
      (deriving Serialize Deserialize))

    (define scenarios (→ (List Scenario))
      (list (TwoFaces) (Smear) (Sandbox)))

    ;; What a scenario asks: its name and what the menu says of it, its last
    ;; shift, when its goal is judged, and the shift, if any, on which you
    ;; must rough someone up or make a threat in the Docks, in front of a
    ;; crowd.
    (struct Rules
      ((name String)
       (pitch String)
       (last-shift I64)
       (deadline String)
       (forced-shift (Option I64))))

    (define (scenario-rules (scenario Scenario)) (→ Rules)
      (match scenario
        ((TwoFaces)
         (Rules "Two faces"
                "Look reliable to the Market without the Tower hearing you are dangerous."
                8
                "Judged after shift 8."
                (Some 3)))
        ((Smear)
         (Rules "The smear"
                "A rival's lie is spreading; keep it from the Tower for ten shifts."
                10
                "Hold out through shift 10."
                (None)))
        ((Sandbox)
         (Rules "Sandbox"
                "Twelve shifts and no goal: see how stories travel."
                12
                "Twelve shifts to try things; there is no goal."
                (None)))))

    (define (last-shift (mill Mill)) (→ I64)
      (::last-shift (scenario-rules (::scenario mill))))

    (define (new-mill (scenario Scenario)) (→ Mill)
      (let ((mill (Mill scenario
                        1
                        10
                        (Nil)
                        (make-vector person-count (Nil))
                        (make-vector person-count 0)
                        (Nil)
                        (Playing))))
        (match scenario
          ((Smear) (smear mill))
          (_ mill))))

    ;; The rival told Lia and Oda before the first shift.
    (define (smear (mill Mill)) (→ Mill)
      (let ((told (tell (Mill-shift-set mill 0)
                        (Unreliable)
                        2
                        "a rival says you skipped out on a debt"
                        (Rival)
                        11)))
        (Mill-shift-set (hear told 14 (Copy 0 2 0 (Nil))) 1)))

    (define (two-faces-outcome (mill Mill)) (→ Outcome)
      (let ((reliable (level mill market (Reliable))) (dangerous (level mill tower (Dangerous))))
        (cond ((< reliable 3)
               (Lost
                (string-append "The Market believes you reliable at only " (show reliable) ".")))
              ((> dangerous 0)
               (Lost (string-append "The Tower believes you dangerous at " (show dangerous) ".")))
              (else (Won "The Market trusts you, and the Tower never heard you were dangerous.")))))

    ;; Decides the game after a spread, which has already advanced `shift`.
    (define (judge (mill Mill)) (→ Mill)
      (let ((done (= (- (::shift mill) 1) (last-shift mill))))
        (Mill-outcome-set mill
                          (match (::scenario mill)
                            ((TwoFaces) (if done (two-faces-outcome mill) (Playing)))
                            ((Smear)
                             (cond ((> (level mill tower (Unreliable)) 0)
                                    (Lost "The Tower believes you unreliable."))
                                   (done (Won "The Tower never believed the smear."))
                                   (else (Playing))))
                            ((Sandbox) (if done (Ended) (Playing)))))))

    (define (mill-over? (mill Mill)) (→ Bool)
      (match (::outcome mill)
        ((Playing) #f)
        (_ #t)))

    ;; ---- Actions ----

    (enum Action
      (Do ((deed Deed) (person I64)))
      (Pay ((person I64)))
      (Mislead ((trait Trait) (person I64)))
      (Wait))

    (enum Deed
      (Rough)
      (Threat)
      (Deliver)
      (Keep)
      (Walk)
      (deriving Serialize Deserialize))

    (define deeds (→ (List Deed))
      (list (Rough) (Threat) (Deliver) (Keep) (Walk)))

    ;; The story a deed's witness hears: its trait, its intensity, and what
    ;; it says.
    (define (deed-trait (deed Deed)) (→ Trait)
      (match deed
        ((Rough) (Dangerous))
        ((Threat) (Dangerous))
        ((Deliver) (Reliable))
        ((Keep) (Reliable))
        ((Walk) (Harmless))))

    (define (deed-intensity (deed Deed)) (→ I64)
      (match deed
        ((Rough) 2)
        ((Threat) 1)
        ((Deliver) 2)
        ((Keep) 1)
        ((Walk) 1)))

    ;; "you roughed someone up in front of Mo".
    (define (deed-label (deed Deed) (person I64)) (→ String)
      (string-append (match deed
                       ((Rough) "you roughed someone up in front of ")
                       ((Threat) "you made a threat in front of ")
                       ((Deliver) "you delivered a job for ")
                       ((Keep) "you kept a small promise to ")
                       ((Walk) "you walked away from a fight in front of "))
                     (first-name person)))

    ;; What the player does: "Rough someone up".
    (define (deed-name (deed Deed)) (→ String)
      (match deed
        ((Rough) "Rough someone up")
        ((Threat) "Make a threat")
        ((Deliver) "Deliver a job")
        ((Keep) "Keep a small promise")
        ((Walk) "Walk away from a fight")))

    ;; The story it starts: "dangerous 2".
    (define (deed-effect (deed Deed)) (→ String)
      (string-append (trait-name (deed-trait deed)) " " (show (deed-intensity deed))))

    ;; On the scenario's forced shift, only a dangerous deed in the Docks
    ;; will do, and a crowd sees it.
    (define (forced? (mill Mill)) (→ Bool)
      (match (::forced-shift (scenario-rules (::scenario mill)))
        ((Some shift) (= shift (::shift mill)))
        ((None) #f)))

    ;; Everyone tied to the witness hears the newest story from them at
    ;; once, grown if they belong to another audience.
    (define (crowd (mill Mill) (witness I64)) (→ Mill)
      (let* ((id (- (length (::stories mill)) 1)) (intensity (::intensity (story mill id))))
        (fold-left (lambda (current person)
                     (hear current
                           person
                           (Copy id
                                 (grow intensity witness person)
                                 (::shift mill)
                                 (list witness))))
                   mill
                   (neighbors witness))))

    (define (allowed? (mill Mill) (action Action)) (→ Bool)
      (or (not (forced? mill))
          (match action
            ((Do deed person)
             (and (same-trait? (deed-trait deed) (Dangerous)) (= (audience-of person) docks)))
            (_ #f))))

    ;; A payment empties the person's memory of you and keeps them quiet
    ;; for this shift and the next three.
    (define (pay (mill Mill) (person I64)) (→ Mill)
      (let ((paid (Mill-coins-set mill (- (::coins mill) 2))))
        (Mill-liabilities-set
         (Mill-quiet-set (Mill-copies-set paid (vector-set (::copies paid) person (Nil)))
                         (vector-set (::quiet paid) person (+ (::shift mill) 3)))
         (append (::liabilities mill) (list (Paid person (::shift mill)))))))

    (define (lie (mill Mill) (trait Trait) (person I64)) (→ Mill)
      (Mill-liabilities-set
       (tell mill
             trait
             1
             (string-append "your lie to " (first-name person) " that you are " (trait-name trait))
             (Lie)
             person)
       (append (::liabilities mill) (list (Told (length (::stories mill)))))))

    ;; A deed's witness hears its story, and on a forced shift so does the
    ;; crowd.
    (define (witness (mill Mill) (deed Deed) (person I64)) (→ (Pair Mill String))
      (let ((told (tell mill
                        (deed-trait deed)
                        (deed-intensity deed)
                        (deed-label deed person)
                        (Witnessed)
                        person)))
        (Pair (if (forced? mill) (crowd told person) told)
              (string-append (first-name person)
                             (if (forced? mill) " and the crowd" "")
                             " heard it: "
                             (deed-effect deed)
                             "."))))

    ;; Applies the player's action for this shift, which `refusal` allows,
    ;; and says what it did.
    (define (act (mill Mill) (action Action)) (→ (Pair Mill String))
      (match action
        ((Do deed person) (witness mill deed person))
        ((Pay person)
         (Pair (pay mill person)
               (string-append "You paid "
                              (first-name person)
                              ". "
                              (first-name person)
                              " forgets every story and keeps quiet through shift "
                              (show (+ (::shift mill) 3)) ".")))
        ((Mislead trait person)
         (Pair (lie mill trait person)
               (string-append "You told "
                              (first-name person)
                              " you are "
                              (trait-name trait)
                              ": a lie.")))
        ((Wait) (Pair mill "You lie low."))))

    ;; ---- Shifts ----

    ;; Who holds more stories after a shift than before it.
    (define (newly-heard (before Mill) (after Mill)) (→ (List I64))
      (filter
       (lambda (person) (> (length (copies-of after person)) (length (copies-of before person))))
       (iota person-count)))

    ;; How many people in each audience heard something new.
    (define (news (before Mill) (after Mill)) (→ String)
      (let* ((fresh (newly-heard before after))
             (counts (map (lambda (audience)
                            (Pair audience
                                  (length
                                   (filter (lambda (person) (= (audience-of person) audience))
                                           fresh))))
                          audiences))
             (reached (filter (lambda (count) (> (::second count) 0)) counts)))
        (string-append "End of shift " (show (::shift before)) ": "
                       (if (null? reached)
                           "no story moved."
                           (string-append "new stories reached "
                                          (string-join (map (lambda (count)
                                                              (string-append
                                                               (show (::second count))
                                                               " in the "
                                                               (audience-name (::first count))))
                                                            reached)
                                                       ", ")
                                          ".")))))

    ;; An audience's level of a trait at two moments.
    (struct Change
      ((audience I64)
       (trait Trait)
       (was I64)
       (now I64)))

    (define (level-changes (before Mill) (after Mill)) (→ (List Change))
      (filter (lambda (change) (not (= (::was change) (::now change))))
              (concatenate (map (lambda (audience)
                                  (map (lambda (trait)
                                         (Change audience
                                                 trait
                                                 (level before audience trait)
                                                 (level after audience trait)))
                                       traits))
                                audiences))))

    (define (change-text (change Change)) (→ String)
      (let ((now (::now change)))
        (string-append "The " (audience-name (::audience change))
                       (if (= now 0) " no longer believes you " " now believes you ")
                       (trait-name (::trait change))
                       (if (= now 0) "" (string-append " " (show now)))
                       " (was " (show (::was change)) ").")))

    ;; Why the action cannot be taken this shift, if it cannot.
    (define (refusal (mill Mill) (action Action)) (→ (Option String))
      (cond ((mill-over? mill) (Some "The game is over."))
            ((not (allowed? mill action))
             (Some
              "This shift you must rough someone up or make a threat in front of someone in the Docks."))
            ((match action ((Pay _) (< (::coins mill) 2)) (_ #f)) (Some "Paying costs 2 coins."))
            (else (None))))

    ;; One shift: the action, the spread and the verdict, with what changed,
    ;; or why the action cannot be taken.
    (define (take-shift (mill Mill) (action Action)) (→ (Result (Pair Mill (List String)) String))
      (match (refusal mill action)
        ((Some why) (Err why))
        ((None) (Ok (finish-shift mill (act mill action))))))

    ;; Spreads and judges after the action, and reports what changed since
    ;; the shift began, a line each.
    (define (finish-shift (mill Mill) (acted (Pair Mill String))) (→ (Pair Mill (List String)))
      (let* ((before (::first acted)) (after (judge (spread before))))
        (Pair after
              (Cons (::second acted)
                    (Cons (news before after) (map change-text (level-changes mill after)))))))

    ;; ---- Forecast ----

    ;; The level changes over the coming shifts if you lie low throughout,
    ;; at most six.
    (define (forecast (mill Mill)) (→ (List String))
      (let loop ((current mill)
                 (left (min 6 (+ (- (last-shift mill) (::shift mill)) 1)))
                 (lines (Nil)))
        (if (= left 0)
            (take (reverse lines) (min 6 (length lines)))
            (let ((next (spread current)))
              (loop next
                    (- left 1)
                    (append (reverse (forecast-changes mill current next)) lines))))))

    ;; `now` is the present, for comparison; `current` is the shift ending.
    (define (forecast-changes (now Mill) (current Mill) (next Mill)) (→ (List String))
      (map (lambda (change)
             (string-append "After shift "
                            (show (::shift current))
                            ": the "
                            (audience-name (::audience change))
                            " believes you "
                            (trait-name (::trait change))
                            " "
                            (show (::now change))
                            " (now "
                            (show (level now (::audience change) (::trait change)))
                            ")."))
           (level-changes current next)))

    ;; ---- Goals ----

    ;; Where a part of the goal stands now: met or not yet, a duty still to
    ;; come or due this shift, or one done.
    (enum Progress
      (Met)
      (Unmet)
      (Upcoming)
      (Due)
      (Done))

    (struct Goal
      ((text String)
       (progress Progress)))

    (define (holds (condition Bool)) (→ Progress)
      (if condition (Met) (Unmet)))

    ;; The scenario's goal, part by part, judged against the present.
    (define (mill-goals (mill Mill)) (→ (List Goal))
      (append (match (::scenario mill)
                ((TwoFaces)
                 (list (Goal "The Market believes you reliable at 3"
                             (holds (>= (level mill market (Reliable)) 3)))
                       (Goal "The Tower does not believe you dangerous"
                             (holds (= (level mill tower (Dangerous)) 0)))))
                ((Smear)
                 (list (Goal "The Tower never believes you unreliable"
                             (holds (= (level mill tower (Unreliable)) 0)))))
                ((Sandbox) (Nil)))
              (match (::forced-shift (scenario-rules (::scenario mill)))
                ((Some shift)
                 (list (Goal (string-append "On shift "
                                            (show shift)
                                            ", rough someone up or threaten someone in the Docks")
                             (cond ((< (::shift mill) shift) (Upcoming))
                                   ((= (::shift mill) shift) (Due))
                                   (else (Done))))))
                ((None) (Nil)))))

    ;; The verdict once the game is over.
    (define (mill-result (mill Mill)) (→ (Option (Pair Bool String)))
      (match (::outcome mill)
        ((Won reason) (Some (Pair #t (string-append "You win. " reason))))
        ((Lost reason) (Some (Pair #f (string-append "You lose. " reason))))
        ((Ended) (Some (Pair #t "The sandbox is over.")))
        ((Playing) (None))))

    ;; What an audience, or a person, believes about you, strongest traits
    ;; as levels.
    (define (audience-beliefs (mill Mill) (audience I64)) (→ (List (Pair Trait I64)))
      (filter (lambda (pair) (> (::second pair) 0))
              (map (lambda (trait) (Pair trait (level mill audience trait))) traits)))

    (define (person-beliefs (mill Mill) (person I64)) (→ (List (Pair Trait I64)))
      (filter (lambda (pair) (> (::second pair) 0))
              (map (lambda (trait) (Pair trait (belief mill person trait))) traits)))

    ;; ---- Liabilities ----

    (define (liability-text (mill Mill) (liability Liability)) (→ String)
      (match liability
        ((Paid person shift)
         (string-append "Paid " (first-name person) " on shift " (show shift) "."))
        ((Told id)
         (let ((s (story mill id)))
           (string-append "Lied to "
                          (first-name (::listener s))
                          ": "
                          (trait-name (::trait s))
                          " 1"
                          (if (exposed? mill s) " (exposed)." "."))))))

    ;; The payments and lies that could come back to bite, a line each.
    (define (liabilities (mill Mill)) (→ (List String))
      (map (lambda (item) (liability-text mill item)) (::liabilities mill)))

    ;; ---- Stories held ----

    ;; "from Mo, who heard it from Lia".
    (define (path-text (path (List I64))) (→ String)
      (string-append "from " (string-join (map first-name path) ", who heard it from ")))

    ;; A story a person holds: its trait and strength, what it says, and the
    ;; path it took to them.
    (define (story-line (mill Mill) (copy Copy)) (→ String)
      (let ((s (story mill (::story copy))) (heard (show (::heard copy))))
        (string-append (trait-name (::trait s))
                       " "
                       (show (::intensity copy))
                       ": "
                       (::label s)
                       (match (::path copy)
                         ((Nil) (string-append ". First heard here on shift " heard "."))
                         (path
                          (string-append ". Heard on shift " heard " " (path-text path) "."))))))

    (define (story-lines (mill Mill) (person I64)) (→ (List String))
      (map (lambda (copy) (story-line mill copy)) (copies-of mill person)))

    ))
