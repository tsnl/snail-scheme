;; The rumor mill: 24 people in three audiences, joined by ties along which
;; stories about the player spread one step per shift. The rules are in
;; prototypes.md; (hearsay mill-screen) plays them in the browser.
(define-library (hearsay mill)
  (export
   Mill
   mill-scenario-count
   mill-scenario-name
   new-mill
   mill-over?
   Deed
   Rough
   Threat
   Deliver
   Keep
   Walk
   deeds
   deed-summary
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
   person-count
   person-name
   first-name
   audience-of
   hub?
   ties
   neighbors
   belief
   quiet?
   newly-heard
   mill-status
   mill-audiences
   liability-lines
   mill-outlook
   look-text
   mill-board)
  (import
   (lofi base)
   (lofi wire))
  (begin

    ;; ---- Town ----

    (define person-count 24)

    ;; Person p belongs to audience p / 8: the Market, the Docks or the
    ;; Tower.
    (: audience-of (-> I64 I64))
    (define (audience-of person)
      (quotient person 8))

    (: audience-name (-> I64 String))
    (define (audience-name audience)
      (list-ref (list "Market" "Docks" "Tower") audience))

    (: person-name (-> I64 String))
    (define (person-name person)
      (list-ref (list "Ana, courier" "Bix, bartender" "Cal, noodle cook" "Dee, tailor"
                      "Eli, pawnbroker" "Fen, street medic" "Gus, vendor" "Hana, rickshaw driver"
                      "Ike, crane operator" "Jun, stevedore" "Kas, union steward" "Lia, net mender"
                      "Mo, smuggler" "Nia, dock foreman" "Oda, welder" "Pim, night guard"
                      "Quin, analyst" "Rhea, concierge" "Sol, lawyer" "Tam, driver"
                      "Uma, executive" "Vic, security chief" "Wen, architect" "Yara, assistant")
                person))

    ;; Hubs pass a story two steps per shift instead of one.
    (: hub? (-> I64 Bool))
    (define (hub? person)
      (member? person (list 1 10 13 17)))

    ;; Each audience is a ring of eight; chords cross three of the rings and
    ;; three bridges join the audiences.
    (: ring-next (-> I64 I64))
    (define (ring-next person)
      (+ (* 8 (audience-of person)) (remainder (+ person 1) 8)))

    (: ties (List (Pair I64 I64)))
    (define ties
      (append (map (lambda (person) (Pair person (ring-next person))) (iota person-count))
              (list (Pair 1 5) (Pair 9 13) (Pair 17 21)
                    (Pair 0 12) (Pair 7 19) (Pair 13 17))))

    (: neighbors (-> I64 (List I64)))
    (define (neighbors person)
      (append (map Pair-second (filter (lambda (tie) (= (Pair-first tie) person)) ties))
              (map Pair-first (filter (lambda (tie) (= (Pair-second tie) person)) ties))))

    (: first-name (-> I64 String))
    (define (first-name person)
      (let ((name (person-name person)))
        (match (string-index name #\,)
          ((Some end) (substring name 0 end))
          ((None) name))))

    (: members (-> I64 (List I64)))
    (define (members audience)
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

    (: traits (List Trait))
    (define traits
      (list (Dangerous) (Harmless) (Reliable) (Unreliable)))

    (: trait-index (-> Trait I64))
    (define (trait-index trait)
      (match trait
        ((Dangerous) 0)
        ((Harmless) 1)
        ((Reliable) 2)
        ((Unreliable) 3)))

    (: trait-name (-> Trait String))
    (define (trait-name trait)
      (list-ref (list "dangerous" "harmless" "reliable" "unreliable") (trait-index trait)))

    (: same-pair? (-> Trait Trait Bool))
    (define (same-pair? a b)
      (= (quotient (trait-index a) 2) (quotient (trait-index b) 2)))

    (: opposite? (-> Trait Trait Bool))
    (define (opposite? a b)
      (and (same-pair? a b) (not (= (trait-index a) (trait-index b)))))

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
      ((scenario I64)
       (shift I64)
       (coins I64)
       (stories (List Story))
       (copies (Vector (List Copy)))
       (quiet (Vector I64))
       (liabilities (List Liability))
       (outcome Outcome))
      (deriving Serialize Deserialize))

    (: copies-of (-> Mill I64 (List Copy)))
    (define (copies-of mill person)
      (vector-ref (Mill-copies mill) person))

    (: story (-> Mill I64 Story))
    (define (story mill id)
      (list-ref (Mill-stories mill) id))

    (: holds? (-> Mill I64 I64 Bool))
    (define (holds? mill person id)
      (any? (lambda (copy) (= (Copy-story copy) id)) (copies-of mill person)))

    (: hear (-> Mill I64 Copy Mill))
    (define (hear mill person copy)
      (Mill-copies-set mill (vector-set (Mill-copies mill) person (append (copies-of mill person) (list copy)))))

    ;; Starts a new story at its first listener.
    (: tell (-> Mill Trait I64 String Source I64 Mill))
    (define (tell mill trait intensity label source listener)
      (let ((id (length (Mill-stories mill))))
        (hear (Mill-stories-set mill (append (Mill-stories mill) (list (Story id trait intensity label source listener))))
              listener
              (Copy id intensity (Mill-shift mill) (Nil)))))

    ;; ---- Beliefs ----

    ;; First impressions stick: between equally intense copies, the one
    ;; heard first wins, then the older story.
    (: stronger? (-> Copy Copy Bool))
    (define (stronger? a b)
      (cond ((not (= (Copy-intensity a) (Copy-intensity b))) (> (Copy-intensity a) (Copy-intensity b)))
            ((not (= (Copy-heard a) (Copy-heard b))) (< (Copy-heard a) (Copy-heard b)))
            (else (< (Copy-story a) (Copy-story b)))))

    ;; The copy a person believes on a trait's pair.
    (: believed (-> Mill I64 Trait (Option Copy)))
    (define (believed mill person trait)
      (fold-left (lambda (best copy)
                   (cond ((not (same-pair? (Story-trait (story mill (Copy-story copy))) trait)) best)
                         ((match best ((Some other) (stronger? other copy)) ((None) #f)) best)
                         (else (Some copy))))
                 (None)
                 (copies-of mill person)))

    ;; How intensely a person believes a trait, or 0 if they believe its
    ;; opposite or nothing.
    (: belief (-> Mill I64 Trait I64))
    (define (belief mill person trait)
      (match (believed mill person trait)
        ((Some copy)
         (if (= (trait-index (Story-trait (story mill (Copy-story copy)))) (trait-index trait)) (Copy-intensity copy) 0))
        ((None) 0)))

    ;; The highest N such that four members believe the trait at N or more.
    (: raw-level (-> Mill I64 Trait I64))
    (define (raw-level mill audience trait)
      (let ((beliefs (map (lambda (person) (belief mill person trait)) (members audience))))
        (fold-left (lambda (level n) (if (>= (length (filter (lambda (b) (>= b n)) beliefs)) 4) n level))
                   0
                   (list 1 2 3))))

    (: lie? (-> Story Bool))
    (define (lie? s)
      (match (Story-source s)
        ((Lie) #t)
        (_ #f)))

    ;; A lie is exposed while its first listener holds a story of the
    ;; opposite trait that is not a lie.
    (: exposed? (-> Mill Story Bool))
    (define (exposed? mill lie)
      (and (lie? lie)
           (any? (lambda (copy)
                   (let ((other (story mill (Copy-story copy))))
                     (and (opposite? (Story-trait other) (Story-trait lie)) (not (lie? other)))))
                 (copies-of mill (Story-listener lie)))))

    ;; Each exposed lie raises its listener's audience's level of
    ;; unreliable by 1.
    (: level (-> Mill I64 Trait I64))
    (define (level mill audience trait)
      (let ((exposed (filter (lambda (s) (and (exposed? mill s) (= (audience-of (Story-listener s)) audience)))
                             (Mill-stories mill))))
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

    (: quiet? (-> Mill I64 Bool))
    (define (quiet? mill person)
      (>= (vector-ref (Mill-quiet mill) person) (Mill-shift mill)))

    ;; Crossing into another audience grows a story by 1, up to 3.
    (: grow (-> I64 I64 I64 I64))
    (define (grow intensity from to)
      (min 3 (+ intensity (if (= (audience-of from) (audience-of to)) 0 1))))

    ;; One step along each tie, and for a hub a second step onward from
    ;; each neighbor.
    (: offers-of-copy (-> I64 Copy (List Offer)))
    (define (offers-of-copy person copy)
      (concatenate
       (map (lambda (next)
              (let ((intensity (grow (Copy-intensity copy) person next)))
                (Cons (Offer next (Copy-story copy) intensity (Cons person (Copy-path copy)))
                      (if (hub? person)
                          (map (lambda (far)
                                 (Offer far (Copy-story copy) (grow intensity next far) (Cons next (Cons person (Copy-path copy)))))
                               (filter (lambda (far) (not (= far person))) (neighbors next)))
                          (Nil)))))
            (neighbors person))))

    ;; Everyone not keeping quiet passes on each story heard before this
    ;; shift.
    (: offers (-> Mill (List Offer)))
    (define (offers mill)
      (concatenate
       (map (lambda (person)
              (if (quiet? mill person)
                  (Nil)
                  (concatenate (map (lambda (copy) (offers-of-copy person copy))
                                    (filter (lambda (copy) (< (Copy-heard copy) (Mill-shift mill)))
                                            (copies-of mill person))))))
            (iota person-count))))

    (: better-offer? (-> Offer Offer Bool))
    (define (better-offer? a b)
      (or (> (Offer-intensity a) (Offer-intensity b))
          (and (= (Offer-intensity a) (Offer-intensity b)) (< (list-ref (Offer-path a) 0) (list-ref (Offer-path b) 0)))))

    (: keep-better (-> (List Offer) Offer (List Offer)))
    (define (keep-better best offer)
      (let ((others (filter (lambda (o) (not (= (Offer-story o) (Offer-story offer)))) best)))
        (match (find (lambda (o) (= (Offer-story o) (Offer-story offer))) best)
          ((Some held) (if (better-offer? offer held) (Cons offer others) best))
          ((None) (Cons offer best)))))

    ;; The best offer of each story a person does not hold yet.
    (: arrivals (-> Mill (List Offer) I64 (List Offer)))
    (define (arrivals mill all person)
      (reverse
       (fold-left (lambda (best offer)
                    (if (or (not (= (Offer-person offer) person)) (holds? mill person (Offer-story offer)))
                        best
                        (keep-better best offer)))
                  (Nil)
                  all)))

    ;; Ends the shift. Offers are all computed from the state before
    ;; anyone hears anything, so a story moves its full distance at once.
    (: spread (-> Mill Mill))
    (define (spread mill)
      (let* ((all (offers mill))
             (heard (fold-left (lambda (current person)
                                 (fold-left (lambda (current offer)
                                              (hear current person
                                                    (Copy (Offer-story offer) (Offer-intensity offer) (Mill-shift mill)
                                                          (Offer-path offer))))
                                            current
                                            (arrivals mill all person)))
                               mill
                               (iota person-count))))
        (Mill-shift-set heard (+ (Mill-shift mill) 1))))

    ;; ---- Scenarios ----

    (define mill-scenario-count 3)

    (: mill-scenario-name (-> I64 String))
    (define (mill-scenario-name scenario)
      (list-ref (list "Two faces" "The smear" "Sandbox") scenario))

    (: last-shift (-> Mill I64))
    (define (last-shift mill)
      (list-ref (list 8 10 12) (Mill-scenario mill)))

    (: scenario-goal (-> I64 String))
    (define (scenario-goal scenario)
      (list-ref (list (string-append "Goal: after shift 8, the Market believes you reliable at 3, and the Tower does not"
                                     " believe you dangerous at all. On shift 3 you must rough someone up or make a"
                                     " threat in the Docks, in front of a crowd: the witness and everyone tied to"
                                     " them hear it at once.")
                      (string-append "Goal: a rival has told Lia and Oda that you skipped out on a debt. You lose the"
                                     " moment the Tower believes you unreliable; hold out through shift 10.")
                      "Twelve shifts and no goal.")
                scenario))

    (: new-mill (-> I64 Mill))
    (define (new-mill scenario)
      (let ((mill (Mill scenario 1 10 (Nil) (make-vector person-count (Nil)) (make-vector person-count 0) (Nil) (Playing))))
        (if (= scenario 1) (smear mill) mill)))

    ;; The rival told Lia and Oda before the first shift.
    (: smear (-> Mill Mill))
    (define (smear mill)
      (let ((told (tell (Mill-shift-set mill 0) (Unreliable) 2 "a rival says you skipped out on a debt" (Rival) 11)))
        (Mill-shift-set (hear told 14 (Copy 0 2 0 (Nil))) 1)))

    (: two-faces-outcome (-> Mill Outcome))
    (define (two-faces-outcome mill)
      (let ((reliable (level mill 0 (Reliable))) (dangerous (level mill 2 (Dangerous))))
        (cond ((< reliable 3) (Lost (string-append "The Market believes you reliable at only " (show reliable) ".")))
              ((> dangerous 0) (Lost (string-append "The Tower believes you dangerous at " (show dangerous) ".")))
              (else (Won "The Market trusts you, and the Tower never heard you were dangerous.")))))

    ;; Decides the game after a spread, which has already advanced `shift`.
    (: judge (-> Mill Mill))
    (define (judge mill)
      (let ((done (= (- (Mill-shift mill) 1) (last-shift mill))))
        (Mill-outcome-set mill
                          (case (Mill-scenario mill)
                            ((0) (if done (two-faces-outcome mill) (Playing)))
                            ((1) (cond ((> (level mill 2 (Unreliable)) 0) (Lost "The Tower believes you unreliable."))
                                       (done (Won "The Tower never believed the smear."))
                                       (else (Playing))))
                            (else (if done (Ended) (Playing)))))))

    (: mill-over? (-> Mill Bool))
    (define (mill-over? mill)
      (match (Mill-outcome mill)
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

    (: deeds (List Deed))
    (define deeds
      (list (Rough) (Threat) (Deliver) (Keep) (Walk)))

    (: deed-index (-> Deed I64))
    (define (deed-index deed)
      (match deed
        ((Rough) 0)
        ((Threat) 1)
        ((Deliver) 2)
        ((Keep) 3)
        ((Walk) 4)))

    ;; The story a deed's witness hears.
    (: deed-story (-> Deed I64 Story))
    (define (deed-story deed person)
      (let ((index (deed-index deed)))
        (Story 0
               (list-ref (list (Dangerous) (Dangerous) (Reliable) (Reliable) (Harmless)) index)
               (list-ref (list 2 1 2 1 1) index)
               (string-append (list-ref (list "you roughed someone up in front of " "you made a threat in front of "
                                              "you delivered a job for " "you kept a small promise to "
                                              "you walked away from a fight in front of ")
                                        index)
                              (first-name person))
               (Witnessed)
               person)))

    ;; "Rough someone up: dangerous 2".
    (: deed-summary (-> Deed String))
    (define (deed-summary deed)
      (let ((s (deed-story deed 0)))
        (string-append (list-ref (list "Rough someone up" "Make a threat" "Deliver a job" "Keep a small promise"
                                       "Walk away from a fight")
                                 (deed-index deed))
                       ": " (trait-name (Story-trait s)) " " (show (Story-intensity s)))))

    ;; On shift 3 of Two faces, only a dangerous deed in the Docks will do,
    ;; and a crowd sees it.
    (: forced? (-> Mill Bool))
    (define (forced? mill)
      (and (= (Mill-scenario mill) 0) (= (Mill-shift mill) 3)))

    ;; Everyone tied to the witness hears the newest story from them at
    ;; once, grown if they belong to another audience.
    (: crowd (-> Mill I64 Mill))
    (define (crowd mill witness)
      (let* ((id (- (length (Mill-stories mill)) 1)) (intensity (Story-intensity (story mill id))))
        (fold-left (lambda (current person)
                     (hear current person (Copy id (grow intensity witness person) (Mill-shift mill) (list witness))))
                   mill
                   (neighbors witness))))

    (: allowed? (-> Mill Action Bool))
    (define (allowed? mill action)
      (or (not (forced? mill))
          (match action
            ((Do deed person) (and (< (deed-index deed) 2) (= (audience-of person) 1)))
            (_ #f))))

    ;; A payment empties the person's memory of you and keeps them quiet
    ;; for this shift and the next three.
    (: pay (-> Mill I64 Mill))
    (define (pay mill person)
      (let ((paid (Mill-coins-set mill (- (Mill-coins mill) 2))))
        (Mill-liabilities-set (Mill-quiet-set (Mill-copies-set paid (vector-set (Mill-copies paid) person (Nil)))
                                              (vector-set (Mill-quiet paid) person (+ (Mill-shift mill) 3)))
                              (append (Mill-liabilities mill) (list (Paid person (Mill-shift mill)))))))

    (: lie (-> Mill Trait I64 Mill))
    (define (lie mill trait person)
      (Mill-liabilities-set
       (tell mill trait 1 (string-append "your lie to " (first-name person) " that you are " (trait-name trait)) (Lie) person)
       (append (Mill-liabilities mill) (list (Told (length (Mill-stories mill)))))))

    ;; A deed's witness hears its story, and on a forced shift so does the
    ;; crowd.
    (: witness (-> Mill Deed I64 (Pair Mill String)))
    (define (witness mill deed person)
      (let* ((s (deed-story deed person))
             (told (tell mill (Story-trait s) (Story-intensity s) (Story-label s) (Witnessed) person)))
        (Pair (if (forced? mill) (crowd told person) told)
              (string-append (first-name person) (if (forced? mill) " and the crowd" "") " heard it: "
                             (trait-name (Story-trait s)) " " (show (Story-intensity s)) "."))))

    ;; Applies the player's action for this shift, or explains why not.
    (: act (-> Mill Action (Result (Pair Mill String) String)))
    (define (act mill action)
      (match action
        ((Do deed person) (Ok (witness mill deed person)))
        ((Pay person)
         (if (< (Mill-coins mill) 2)
             (Err "Paying costs 2 coins.")
             (Ok (Pair (pay mill person)
                       (string-append "You paid " (first-name person) ". " (first-name person)
                                      " forgets every story and keeps quiet through shift "
                                      (show (+ (Mill-shift mill) 3)) ".")))))
        ((Mislead trait person)
         (Ok (Pair (lie mill trait person)
                   (string-append "You told " (first-name person) " you are " (trait-name trait) ": a lie."))))
        ((Wait) (Ok (Pair mill "You lie low.")))))

    ;; ---- Shifts ----

    ;; Who holds more stories after a shift than before it.
    (: newly-heard (-> Mill Mill (List I64)))
    (define (newly-heard before after)
      (filter (lambda (person) (> (length (copies-of after person)) (length (copies-of before person))))
              (iota person-count)))

    ;; How many people in each audience heard something new.
    (: news (-> Mill Mill String))
    (define (news before after)
      (let* ((fresh (lambda (person) (> (length (copies-of after person)) (length (copies-of before person)))))
             (counts (map (lambda (audience)
                            (Pair audience (length (filter fresh (members audience)))))
                          (list 0 1 2)))
             (reached (filter (lambda (count) (> (Pair-second count) 0)) counts)))
        (string-append "End of shift " (show (Mill-shift before)) ": "
                       (if (null? reached)
                           "no story moved."
                           (string-append "new stories reached "
                                          (string-join (map (lambda (count)
                                                              (string-append (show (Pair-second count)) " in the "
                                                                             (audience-name (Pair-first count))))
                                                            reached)
                                                       ", ")
                                          ".")))))

    ;; An audience's level of a trait at two moments.
    (struct Change
      ((audience I64)
       (trait Trait)
       (was I64)
       (now I64)))

    (: level-changes (-> Mill Mill (List Change)))
    (define (level-changes before after)
      (filter (lambda (change) (not (= (Change-was change) (Change-now change))))
              (concatenate (map (lambda (audience)
                                  (map (lambda (trait) (Change audience trait (level before audience trait) (level after audience trait)))
                                       traits))
                                (list 0 1 2)))))

    (: change-text (-> Change String))
    (define (change-text change)
      (let ((now (Change-now change)))
        (string-append "The " (audience-name (Change-audience change))
                       (if (= now 0) " no longer believes you " " now believes you ")
                       (trait-name (Change-trait change)) (if (= now 0) "" (string-append " " (show now)))
                       " (was " (show (Change-was change)) ").")))

    ;; One shift: the action, the spread, and the verdict, with what changed.
    ;; Or why the action cannot be taken.
    (: take-shift (-> Mill Action (Result (Pair Mill String) String)))
    (define (take-shift mill action)
      (cond ((mill-over? mill) (Err "The game is over."))
            ((not (allowed? mill action))
             (Err "This shift you must rough someone up or make a threat in front of someone in the Docks."))
            (else (match (act mill action)
                    ((Ok acted) (Ok (finish-shift mill acted)))
                    ((Err message) (Err message))))))

    ;; Spreads and judges after the action, and reports what changed since
    ;; the shift began.
    (: finish-shift (-> Mill (Pair Mill String) (Pair Mill String)))
    (define (finish-shift mill acted)
      (let* ((before (Pair-first acted)) (after (judge (spread before))))
        (Pair after
              (string-join (Cons (Pair-second acted) (Cons (news before after) (map change-text (level-changes mill after))))
                           "\n"))))

    ;; ---- Forecast ----

    ;; The level changes over the coming shifts if you lie low throughout,
    ;; at most six.
    (: forecast (-> Mill (List String)))
    (define (forecast mill)
      (let loop ((current mill) (left (min 6 (+ (- (last-shift mill) (Mill-shift mill)) 1))) (lines (Nil)))
        (if (= left 0)
            (take (reverse lines) (min 6 (length lines)))
            (let ((next (spread current)))
              (loop next (- left 1) (append (reverse (forecast-changes mill current next)) lines))))))

    ;; `now` is the present, for comparison; `current` is the shift ending.
    (: forecast-changes (-> Mill Mill Mill (List String)))
    (define (forecast-changes now current next)
      (map (lambda (change)
             (string-append "After shift " (show (Mill-shift current)) ": the " (audience-name (Change-audience change))
                            " believes you " (trait-name (Change-trait change)) " " (show (Change-now change))
                            " (now " (show (level now (Change-audience change) (Change-trait change))) ")."))
           (level-changes current next)))

    ;; ---- Text ----

    (: pad (-> String I64 String))
    (define (pad text width)
      (string-append text (make-string (max 0 (- width (string-length text))) #\space)))

    (: beliefs-text (-> Mill I64 String))
    (define (beliefs-text mill person)
      (let ((held (filter (lambda (trait) (> (belief mill person trait) 0)) traits)))
        (if (null? held)
            "-"
            (string-join (map (lambda (trait) (string-append (trait-name trait) " " (show (belief mill person trait)))) held)
                         ", "))))

    (: person-line (-> Mill I64 String))
    (define (person-line mill person)
      (string-append (pad (show person) 4)
                     (pad (string-append (person-name person) (if (hub? person) " (hub)" "")) 30)
                     (beliefs-text mill person)
                     (if (quiet? mill person)
                         (string-append "  [quiet through shift " (show (vector-ref (Mill-quiet mill) person)) "]")
                         "")))

    (: audience-line (-> Mill I64 String))
    (define (audience-line mill audience)
      (let ((held (filter (lambda (trait) (> (level mill audience trait) 0)) traits)))
        (string-append "The " (audience-name audience) " believes "
                       (if (null? held)
                           "nothing about you."
                           (string-append "you "
                                          (string-join (map (lambda (trait)
                                                              (string-append (trait-name trait) " "
                                                                             (show (level mill audience trait))))
                                                            held)
                                                       ", ")
                                          ".")))))

    (: liability-text (-> Mill Liability String))
    (define (liability-text mill liability)
      (match liability
        ((Paid person shift) (string-append "  Paid " (first-name person) " on shift " (show shift) "."))
        ((Told id)
         (let ((s (story mill id)))
           (string-append "  Lied to " (first-name (Story-listener s)) ": " (trait-name (Story-trait s)) " 1"
                          (if (exposed? mill s) " (exposed)." "."))))))

    (: header (-> Mill String))
    (define (header mill)
      (string-append (mill-scenario-name (Mill-scenario mill)) ": "
                     (if (mill-over? mill)
                         (string-append "after shift " (show (last-shift mill)))
                         (string-append "shift " (show (Mill-shift mill)) " of " (show (last-shift mill))))
                     ", " (show (Mill-coins mill)) " coins."))

    ;; The scenario, the shift, your coins and the goal.
    (: mill-status (-> Mill (List String)))
    (define (mill-status mill)
      (list (header mill) (scenario-goal (Mill-scenario mill))))

    (: mill-audiences (-> Mill (List String)))
    (define (mill-audiences mill)
      (map (lambda (audience) (audience-line mill audience)) (list 0 1 2)))

    (: liability-lines (-> Mill (List String)))
    (define (liability-lines mill)
      (Cons "Liabilities:"
            (match (Mill-liabilities mill)
              ((Nil) (list "  none."))
              (items (map (lambda (item) (liability-text mill item)) items)))))

    ;; The forecast while the game is on, and the verdict once it is over.
    (: mill-outlook (-> Mill (List String)))
    (define (mill-outlook mill)
      (match (Mill-outcome mill)
        ((Playing)
         (append (if (forced? mill)
                     (list "This shift you must rough someone up or make a threat in front of someone in the Docks.")
                     (Nil))
                 (Cons "If you lie low:"
                       (match (forecast mill)
                         ((Nil) (list "  Nothing changes."))
                         (lines (map (lambda (line) (string-append "  " line)) lines))))))
        ((Won reason) (list (string-append "You win. " reason)))
        ((Lost reason) (list (string-append "You lose. " reason)))
        ((Ended) (list "The sandbox is over."))))

    ;; Everything at once, for scripted tests.
    (: mill-board (-> Mill String))
    (define (mill-board mill)
      (string-join (append (list (header mill) "")
                           (append (concatenate (map (lambda (audience)
                                                       (Cons (audience-line mill audience)
                                                             (map (lambda (person) (person-line mill person))
                                                                  (members audience))))
                                                     (list 0 1 2)))
                                   (append (liability-lines mill) (mill-outlook mill))))
                   "\n"))

    ;; ---- Look ----

    ;; "from Mo, who heard it from Lia".
    (: path-text (-> (List I64) String))
    (define (path-text path)
      (string-append "from " (string-join (map first-name path) ", who heard it from ")))

    (: copy-text (-> Mill Copy String))
    (define (copy-text mill copy)
      (let ((s (story mill (Copy-story copy))) (heard (show (Copy-heard copy))))
        (string-append "  " (trait-name (Story-trait s)) " " (show (Copy-intensity copy)) ": " (Story-label s)
                       (match (Copy-path copy)
                         ((Nil) (string-append ". First heard here on shift " heard "."))
                         (path (string-append ". Heard on shift " heard " " (path-text path) "."))))))

    (: look-text (-> Mill I64 String))
    (define (look-text mill person)
      (string-join (append (list (string-append (show person) " " (person-name person) ", " (audience-name (audience-of person))
                                                (if (hub? person) ", hub" "") ". Ties: "
                                                (string-join (map first-name (neighbors person)) ", ") ".")
                                 (string-append "Believes: " (beliefs-text mill person) "."))
                           (match (copies-of mill person)
                             ((Nil) (list "Holds no stories about you."))
                             (copies (map (lambda (copy) (copy-text mill copy)) copies))))
                   "\n"))

    ))
