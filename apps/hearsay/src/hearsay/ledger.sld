;; The favor ledger: a solo fixer trading markers, promises and coins with
;; two rival fixers for standing. The rules are in prototypes.md;
;; (hearsay ledger-screen) plays them in the browser.
(define-library (hearsay ledger)
  (export
   Ledger
   new-ledger
   ledger-over?
   round-count
   you
   vee
   kit
   fixer-name
   Command
   Accept
   Meet
   Work
   Honor
   EndRound
   ledger-act
   Choice
   offer-choices
   contact-choices
   job-choices
   promise-choices
   ledger-header
   fixer-stats
   fixer-holdings
   due-now
   owed-lines
   ledger-result)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell random))
  (begin

    ;; ---- Pieces ----

    ;; Abilities, contacts and fixers are indices into these tables. Contact
    ;; c lends the ability (list-ref contact-abilities c).
    (define (ability-names)
      (→ (List String))
      (list "doors" "muscle" "medicine" "fencing" "paperwork" "eyes"))

    (define (ability-count) (→ I64) 6)

    (define (contact-names)
      (→ (List String))
      (list "Ivo" "Ren" "Sal" "Tia" "Una" "Vik" "Wes" "Xan"))

    (define (contact-abilities) (→ (List I64)) (list 2 0 1 3 4 5 0 1))

    (define (contact-count) (→ I64) 8)

    (define (round-count) (→ I64) 8)

    (define (ability-name (ability I64)) (→ String)
      (list-ref (ability-names) ability))

    (define (contact-name (contact I64)) (→ String)
      (list-ref (contact-names) contact))

    (define (contact-ability (contact I64)) (→ I64)
      (list-ref (contact-abilities) contact))

    ;; Fixer 0 is you; Vee and Kit are the rivals.
    (define (you) (→ I64) 0)

    (define (vee) (→ I64) 1)

    (define (kit) (→ I64) 2)

    (define (rivals) (→ (List I64)) (list (vee) (kit)))

    (define (everyone) (→ (List I64)) (list (you) (vee) (kit)))

    (define (fixer-name (who I64)) (→ String)
      (list-ref (list "You" "Vee" "Kit") who))

    ;; ---- Markers ----

    ;; A marker lends its holder its contact's ability once. It lapses at the
    ;; end of round `lapses`, the second round after the one in which it was
    ;; granted, and keeps that date when it changes hands.
    (struct Marker
      ((contact I64)
       (lapses I64))
      (deriving Serialize Deserialize))

    (define (grant-marker (contact I64) (granted I64)) (→ Marker)
      (Marker contact (+ granted 2)))

    (define (marker-ability (marker Marker)) (→ I64)
      (contact-ability (● marker contact)))

    ;; The older marker lapses first; between equal dates, the lower contact
    ;; is older.
    (define (older? (a Marker) (b Marker)) (→ Bool)
      (or (< (● a lapses) (● b lapses))
          (and (= (● a lapses) (● b lapses)) (< (● a contact) (● b contact)))))

    (define (same-marker? (a Marker) (b Marker)) (→ Bool)
      (and (= (● a contact) (● b contact)) (= (● a lapses) (● b lapses))))

    ;; A hand of markers stays sorted oldest first, so the first marker with
    ;; an ability is the oldest one.
    (define (insert-marker (marker Marker) (markers (List Marker))) (→ (List Marker))
      (match markers
        ((Nil) (list marker))
        ((Cons first rest)
         (if (older? first marker)
             (Cons first (insert-marker marker rest))
             (Cons marker markers)))))

    (define (remove-marker (marker Marker) (markers (List Marker))) (→ (List Marker))
      (match markers
        ((Nil) (Nil))
        ((Cons first rest)
         (if (same-marker? first marker) rest (Cons first (remove-marker marker rest))))))

    (define (oldest-with (markers (List Marker)) (ability I64)) (→ (Option Marker))
      (find (lambda (marker) (= (marker-ability marker) ability)) markers))

    ;; The abilities, in order, that no marker in the hand lends.
    (define (lacking (markers (List Marker)) (abilities (List I64))) (→ (List I64))
      (filter (lambda (ability)
                (null? (filter (lambda (marker) (= (marker-ability marker) ability)) markers)))
              abilities))

    ;; Spends the oldest marker for each ability. The caller has checked that
    ;; none is lacking.
    (define (spend-for (markers (List Marker)) (abilities (List I64))) (→ (List Marker))
      (fold-left (lambda (left ability)
                   (match (oldest-with left ability)
                     ((Some marker) (remove-marker marker left))
                     ((None) left)))
                 markers abilities))

    ;; ---- Jobs, wants, offers and promises ----

    ;; A job needs two or three different abilities, in ascending order, and
    ;; expires at the end of round `expires`, the round after it is posted.
    (struct Job
      ((number I64)
       (abilities (List I64))
       (expires I64))
      (deriving Serialize Deserialize))

    ;; Two abilities pay 4 coins and 1 standing; three pay 6 and 2.
    (define (job-coins (job Job)) (→ I64)
      (* 2 (length (● job abilities))))

    (define (job-standing (job Job)) (→ I64)
      (- (length (● job abilities)) 1))

    (enum Want
      (WantAbility ((ability I64)))
      (WantCoins ((coins I64)))
      (deriving Serialize Deserialize))

    ;; What changes hands when you accept an offer, besides its price. A buy
    ;; takes your oldest marker with the ability; a sell gives you the
    ;; rival's marker; the promises create a debt due at the end of `due`.
    (enum Deal
      (Buy ((ability I64)))
      (Sell ((marker Marker)))
      (PromiseWanted ((ability I64) (due I64)))
      (PromiseOffered ((ability I64) (due I64)))
      (deriving Serialize Deserialize))

    (struct Offer
      ((number I64)
       (rival I64)
       (price I64)
       (deal Deal))
      (deriving Serialize Deserialize))

    ;; The rival pays for a buy or for your promise; you pay for the rest.
    (define (offer-payer (offer Offer)) (→ I64)
      (match (● offer deal)
        ((Buy _) (● offer rival))
        ((PromiseWanted _ _) (● offer rival))
        ((Sell _) (you))
        ((PromiseOffered _ _) (you))))

    ;; A debt of one marker with `ability`. It stays on the books until it is
    ;; honored or refused, and is refused if still owed at the end of `due`.
    (struct Promise
      ((number I64)
       (debtor I64)
       (creditor I64)
       (ability I64)
       (due I64))
      (deriving Serialize Deserialize))

    ;; ---- State ----

    ;; A rival's target is the job it works toward this round; yours is None.
    (struct Fixer
      ((coins I64)
       (standing I64)
       (markers (List Marker))
       (kept I64)
       (refused I64)
       (target (Option I64)))
      (deriving Serialize Deserialize))

    ;; `wants` and `fixers` are indexed by contact and fixer; `met` lists the
    ;; contacts met this round. `events` records what the current command
    ;; did, newest first; `last-round` keeps what the last end of round did,
    ;; oldest first, for the screen.
    (struct Ledger
      ((random Random)
       (round I64)
       (fixers (List Fixer))
       (wants (List Want))
       (met (List I64))
       (jobs (List Job))
       (offers (List Offer))
       (promises (List Promise))
       (next-job I64)
       (next-promise I64)
       (events (List String))
       (last-round (List String)))
      (deriving Serialize Deserialize))

    (define (replace-at (items (List T)) (index I64) (value T))
      (→ (List T))
      (∀ (T))
      (⊨ (Copy T) (Drop (!) T))
      (map-indexed (lambda (at item) (if (= at index) value item)) items))

    (define (ledger-fixer (ledger Ledger) (who I64)) (→ Fixer)
      (list-ref (● ledger fixers) who))

    (define (ledger-fixer-set (ledger Ledger) (who I64) (fixer Fixer)) (→ Ledger)
      (Ledger-fixers-set ledger (replace-at (● ledger fixers) who fixer)))

    (define (markers-of (ledger Ledger) (who I64)) (→ (List Marker))
      (● (ledger-fixer ledger who) markers))

    (define (coins-of (ledger Ledger) (who I64)) (→ I64)
      (● (ledger-fixer ledger who) coins))

    ;; A roll below `bound`, and the ledger with its generator advanced past it.
    (define (roll (ledger Ledger) (bound I64)) (→ (Pair I64 Ledger))
      (let ((random (● ledger random)))
        (Pair (random-below random bound) (Ledger-random-set ledger (random-next random)))))

    (define (note (ledger Ledger) (text String)) (→ Ledger)
      (Ledger-events-set ledger (Cons text (● ledger events))))

    ;; ---- Holdings ----

    (define (add-coins (ledger Ledger) (who I64) (amount I64)) (→ Ledger)
      (let ((fixer (ledger-fixer ledger who)))
        (ledger-fixer-set ledger who (Fixer-coins-set fixer (+ (● fixer coins) amount)))))

    (define (transfer-coins (ledger Ledger) (from I64) (to I64) (amount I64)) (→ Ledger)
      (add-coins (add-coins ledger from (negate amount)) to amount))

    (define (gain-marker (ledger Ledger) (who I64) (marker Marker)) (→ Ledger)
      (let ((fixer (ledger-fixer ledger who)))
        (ledger-fixer-set ledger
                          who
                          (Fixer-markers-set fixer (insert-marker marker (● fixer markers))))))

    (define (lose-marker (ledger Ledger) (who I64) (marker Marker)) (→ Ledger)
      (let ((fixer (ledger-fixer ledger who)))
        (ledger-fixer-set ledger
                          who
                          (Fixer-markers-set fixer (remove-marker marker (● fixer markers))))))

    (define (transfer-marker (ledger Ledger) (from I64) (to I64) (marker Marker)) (→ Ledger)
      (gain-marker (lose-marker ledger from marker) to marker))

    ;; Doing a job spends one marker per ability and pays coins and standing.
    (define (complete-job (ledger Ledger) (who I64) (job Job)) (→ Ledger)
      (let* ((fixer (ledger-fixer ledger who))
             (fixer (Fixer-markers-set fixer (spend-for (● fixer markers) (● job abilities))))
             (fixer (Fixer-coins-set fixer (+ (● fixer coins) (job-coins job))))
             (fixer (Fixer-standing-set fixer (+ (● fixer standing) (job-standing job)))))
        (note
         (Ledger-jobs-set (ledger-fixer-set ledger who fixer) (remove-job (● ledger jobs) job))
         (string-append (acts who "complete") " job " (show (● job number)) " for "
                        (coins-text (job-coins job))
                        " and "
                        (show (job-standing job))
                        " standing."))))

    (define (remove-job (jobs (List Job)) (job Job)) (→ (List Job))
      (filter (lambda (other) (not (= (● other number) (● job number)))) jobs))

    ;; ---- Promises ----

    (define (make-promise (ledger Ledger) (debtor I64) (creditor I64) (ability I64) (due I64))
      (→ Ledger)
      (let ((promise (Promise (● ledger next-promise) debtor creditor ability due)))
        (Ledger-next-promise-set
         (Ledger-promises-set ledger (append (● ledger promises) (list promise)))
         (+ (● promise number) 1))))

    (define (drop-promise (ledger Ledger) (promise Promise)) (→ Ledger)
      (Ledger-promises-set ledger
                           (filter (lambda (other)
                                     (not (= (● other number) (● promise number))))
                                   (● ledger promises))))

    ;; Keeping a promise gives the creditor the debtor's marker.
    (define (keep-promise (ledger Ledger) (promise Promise) (marker Marker)) (→ Ledger)
      (let* ((debtor (● promise debtor))
             (fixer (ledger-fixer ledger debtor))
             (ledger
              (ledger-fixer-set ledger debtor (Fixer-kept-set fixer (+ (● fixer kept) 1)))))
        (note
         (drop-promise (transfer-marker ledger debtor (● promise creditor) marker) promise)
         (string-append (acts debtor "honor")
                        " promise "
                        (show (● promise number))
                        ", giving "
                        (object-name (● promise creditor))
                        " "
                        (describe-marker marker)
                        "."))))

    ;; Refusing costs the debtor 1 standing and goes on their record.
    (define (refuse-promise (ledger Ledger) (promise Promise)) (→ Ledger)
      (let* ((debtor (● promise debtor))
             (fixer (ledger-fixer ledger debtor))
             (fixer (Fixer-standing-set (Fixer-refused-set fixer (+ (● fixer refused) 1))
                                        (- (● fixer standing) 1))))
        (note (drop-promise (ledger-fixer-set ledger debtor fixer) promise)
              (string-append (acts debtor "refuse") " promise " (show (● promise number))
                             " and " (acts-object debtor "lose") " 1 standing."))))

    ;; Once you have refused a promise, rivals pay less, charge more and stop
    ;; asking you for promises.
    (define (trusted? (ledger Ledger)) (→ Bool)
      (= (● (ledger-fixer ledger (you)) refused) 0))

    ;; ---- Start of a round ----

    ;; Each fixer starts with 4 coins and two markers from contacts drawn at
    ;; random, dealt in turn and granted in round 1.
    (define (new-ledger (seed I64)) (→ Ledger)
      (let* ((fixer (Fixer 4 0 (Nil) 0 0 (None)))
             (ledger (Ledger (make-random seed)
                             1
                             (list fixer fixer fixer)
                             (Nil)
                             (Nil)
                             (Nil)
                             (Nil)
                             (Nil)
                             1
                             1
                             (Nil)
                             (Nil)))
             (ledger (fold-left deal-marker ledger (append (everyone) (everyone)))))
        (begin-round (draw-wants ledger))))

    (define (deal-marker (ledger Ledger) (who I64)) (→ Ledger)
      (let ((drawn (roll ledger (contact-count))))
        (gain-marker (● drawn second)
                     who
                     (grant-marker (● drawn first) (● ledger round)))))

    (define (draw-wants (ledger Ledger)) (→ Ledger)
      (fold-left (lambda (ledger contact)
                   (let ((drawn (draw-want ledger contact)))
                     (Ledger-wants-set (● drawn second)
                                       (append (● ledger wants) (list (● drawn first))))))
                 ledger (iota (contact-count))))

    ;; Half the time a contact wants one of the five abilities other than
    ;; their own; otherwise 2, 3 or 4 coins.
    (define (draw-want (ledger Ledger) (contact I64)) (→ (Pair Want Ledger))
      (let ((kind (roll ledger 10)))
        (if (< (● kind first) 5)
            (let ((offset (roll (● kind second) 5)))
              (Pair (WantAbility
                     (modulo (+ (contact-ability contact) (+ 1 (● offset first))) (ability-count)))
                    (● offset second)))
            (let ((coins (roll (● kind second) 3)))
              (Pair (WantCoins (+ 2 (● coins first))) (● coins second))))))

    ;; Steps 1 to 3 of a round come before your move.
    (define (begin-round (ledger Ledger)) (→ Ledger)
      (post-offers (choose-targets (post-jobs (Ledger-met-set ledger (Nil))))))

    ;; 1. Market: new jobs are posted until three are open.
    (define (post-jobs (ledger Ledger)) (→ Ledger)
      (if (>= (length (● ledger jobs)) 3)
          ledger
          (post-jobs (post-job ledger))))

    (define (post-job (ledger Ledger)) (→ Ledger)
      (let* ((size (roll ledger 2))
             (drawn (draw-abilities (● size second) (+ 2 (● size first))))
             (ledger (● drawn second))
             (job (Job (● ledger next-job) (● drawn first) (+ (● ledger round) 1))))
        (Ledger-next-job-set (Ledger-jobs-set ledger (append (● ledger jobs) (list job)))
                             (+ (● job number) 1))))

    ;; Draws `count` different abilities and lists them in ascending order.
    (define (draw-abilities (ledger Ledger) (count I64)) (→ (Pair (List I64) Ledger))
      (let loop ((ledger ledger) (left (iota (ability-count))) (drawn (Nil)))
        (if (= (length drawn) count)
            (Pair (filter (lambda (ability) (member? ability drawn)) (iota (ability-count))) ledger)
            (let* ((pick (roll ledger (length left)))
                   (ability (list-ref left (● pick first))))
              (loop (● pick second)
                    (filter (lambda (other) (not (= other ability))) left)
                    (Cons ability drawn))))))

    ;; 2. Targets: each rival works toward the open job it lacks the fewest
    ;; abilities for; ties go to more standing, then to the job listed first.
    (define (choose-targets (ledger Ledger)) (→ Ledger)
      (fold-left (lambda (ledger who)
                   (let ((fixer (ledger-fixer ledger who)))
                     (ledger-fixer-set ledger
                                       who
                                       (Fixer-target-set fixer
                                                         (best-job (● fixer markers)
                                                                   (● ledger jobs))))))
                 ledger (rivals)))

    (define (best-job (markers (List Marker)) (jobs (List Job))) (→ (Option I64))
      (match (fold-left (lambda (best job)
                          (match best
                            ((Some chosen) (if (better-target? markers job chosen) (Some job) best))
                            ((None) (Some job))))
                        (None) jobs)
        ((Some job) (Some (● job number)))
        ((None) (None))))

    (define (better-target? (markers (List Marker)) (job Job) (chosen Job)) (→ Bool)
      (let ((missing (length (lacking markers (● job abilities))))
            (chosen-missing (length (lacking markers (● chosen abilities)))))
        (or (< missing chosen-missing)
            (and (= missing chosen-missing) (> (job-standing job) (job-standing chosen))))))

    (define (find-job (ledger Ledger) (number I64)) (→ (Option Job))
      (find (lambda (job) (= (● job number) number)) (● ledger jobs)))

    (define (target-job (ledger Ledger) (who I64)) (→ (Option Job))
      (match (● (ledger-fixer ledger who) target)
        ((Some number) (find-job ledger number))
        ((None) (None))))

    ;; A target someone else has done needs nothing.
    (define (target-needs (ledger Ledger) (who I64)) (→ (List I64))
      (match (target-job ledger who)
        ((Some job) (● job abilities))
        ((None) (Nil))))

    ;; 3. Offers: each rival posts its offers in order, numbered from 1
    ;; across both rivals. Accepting an offer removes it until the round ends.
    (define (post-offers (ledger Ledger)) (→ Ledger)
      (fold-left post-rival-offers (Ledger-offers-set ledger (Nil)) (rivals)))

    (define (post-rival-offers (ledger Ledger) (who I64)) (→ Ledger)
      (let ((promised (roll ledger (ability-count))))
        (fold-left
         (lambda (ledger deal) (post-offer ledger who (● deal first) (● deal second)))
         (● promised second)
         (rival-deals (● promised second) who (● promised first)))))

    (define (post-offer (ledger Ledger) (who I64) (price I64) (deal Deal)) (→ Ledger)
      (let ((offers (● ledger offers)))
        (Ledger-offers-set ledger
                           (append offers (list (Offer (+ (length offers) 1) who price deal))))))

    ;; A rival buys the first ability its target lacks, sells a marker its
    ;; target does not need, wants your promise of the ability it lacks last,
    ;; and offers its promise of `promised`, skipping what it has nothing for.
    (define (rival-deals (ledger Ledger) (who I64) (promised I64)) (→ (List (Pair I64 Deal)))
      (let* ((needs (target-needs ledger who))
             (missing (lacking (markers-of ledger who) needs))
             (spare (filter (lambda (marker) (not (member? (marker-ability marker) needs)))
                            (markers-of ledger who)))
             (trusted (trusted? ledger))
             (due (+ (● ledger round) 2)))
        (concatenate
         (list (match missing
                 ((Cons ability _) (list (Pair (if trusted 3 2) (Buy ability))))
                 ((Nil) (Nil)))
               (match spare
                 ((Cons marker _) (list (Pair (if trusted 2 3) (Sell marker))))
                 ((Nil) (Nil)))
               (match (last missing)
                 ((Some ability) (if trusted (list (Pair 2 (PromiseWanted ability due))) (Nil)))
                 ((None) (Nil)))
               (list (Pair 1 (PromiseOffered promised due)))))))

    ;; ---- Your move ----

    ;; A command names an offer, job or promise by its number on the board,
    ;; and a contact by its index.
    (enum Command
      (Accept ((offer I64)))
      (Meet ((contact I64)))
      (Work ((job I64)))
      (Honor ((promise I64)))
      (EndRound)
      (deriving Serialize Deserialize))

    ;; Applies a command and says what it did, or says why it cannot be done.
    (define (ledger-act (ledger Ledger) (command Command))
      (→ (Result (Pair Ledger (List String)) String))
      (if (ledger-over? ledger)
          (Err "The game is over.")
          (match command
            ((Accept number) (accept-offer ledger number))
            ((Meet contact) (meet-contact ledger contact))
            ((Work number) (work-job ledger number))
            ((Honor number) (honor-promise ledger number))
            ((EndRound) (Ok (end-round ledger))))))

    (define (accept-offer (ledger Ledger) (number I64))
      (→ (Result (Pair Ledger (List String)) String))
      (match (find (lambda (offer) (= (● offer number) number)) (● ledger offers))
        ((Some offer)
         (if (< (coins-of ledger (offer-payer offer)) (● offer price))
             (Err (string-append (fixer-name (offer-payer offer))
                                 " cannot pay "
                                 (coins-text (● offer price))
                                 "."))
             (accept-deal ledger offer)))
        ((None) (Err "No such offer."))))

    ;; A rival loses markers only at the end of a round, when its offers are
    ;; withdrawn, so the marker it sells is still in its hand.
    (define (accept-deal (ledger Ledger) (offer Offer))
      (→ (Result (Pair Ledger (List String)) String))
      (let ((rival (● offer rival)))
        (match (● offer deal)
          ((Buy ability)
           (match (oldest-with (markers-of ledger (you)) ability)
             ((Some marker)
              (Ok (report (settle-offer (transfer-marker ledger (you) rival marker) offer))))
             ((None) (no-marker ability))))
          ((Sell marker)
           (Ok (report (settle-offer (transfer-marker ledger rival (you) marker) offer))))
          ((PromiseWanted ability due)
           (Ok (report (settle-offer (make-promise ledger (you) rival ability due) offer))))
          ((PromiseOffered ability due)
           (Ok (report (settle-offer (make-promise ledger rival (you) ability due) offer)))))))

    ;; The price changes hands and the offer is taken off the board.
    (define (settle-offer (ledger Ledger) (offer Offer)) (→ Ledger)
      (let* ((payer (offer-payer offer))
             (payee (if (= payer (you)) (● offer rival) (you)))
             (offers (filter (lambda (other) (not (= (● other number) (● offer number))))
                             (● ledger offers))))
        (note (Ledger-offers-set (transfer-coins ledger payer payee (● offer price)) offers)
              (string-append "You accept: " (describe-offer offer)))))

    ;; Each contact can be met once a round.
    (define (meet-contact (ledger Ledger) (contact I64))
      (→ (Result (Pair Ledger (List String)) String))
      (cond ((not (and (>= contact 0) (< contact (contact-count)))) (Err "No such contact."))
            ((member? contact (● ledger met))
             (Err (string-append (contact-name contact) " has already been met this round.")))
            (else (meet-want ledger contact (list-ref (● ledger wants) contact)))))

    ;; You meet a want by paying its coins or spending your oldest marker
    ;; with its ability.
    (define (meet-want (ledger Ledger) (contact I64) (want Want))
      (→ (Result (Pair Ledger (List String)) String))
      (match want
        ((WantCoins coins)
         (if (< (coins-of ledger (you)) coins)
             (Err (string-append "You cannot pay " (coins-text coins) "."))
             (Ok (report (grant-favor (note (add-coins ledger (you) (negate coins))
                                            (string-append "You pay "
                                                           (contact-name contact)
                                                           " "
                                                           (coins-text coins)
                                                           "."))
                                      contact)))))
        ((WantAbility ability)
         (match (oldest-with (markers-of ledger (you)) ability)
           ((Some marker)
            (Ok (report (grant-favor (note (lose-marker ledger (you) marker)
                                           (string-append "You spend "
                                                          (describe-marker marker)
                                                          " for "
                                                          (contact-name contact)
                                                          "."))
                                     contact))))
           ((None) (no-marker ability))))))

    ;; A contact whose want is met grants you a marker and draws a new want.
    (define (grant-favor (ledger Ledger) (contact I64)) (→ Ledger)
      (let* ((marker (grant-marker contact (● ledger round)))
             (drawn (draw-want ledger contact))
             (ledger (Ledger-wants-set (● drawn second)
                                       (replace-at (● ledger wants)
                                                   contact
                                                   (● drawn first)))))
        (note (Ledger-met-set (gain-marker ledger (you) marker) (Cons contact (● ledger met)))
              (string-append (contact-name contact)
                             " grants you a marker through round "
                             (show (● marker lapses))
                             " and now wants " (describe-want (● drawn first)) "."))))

    (define (work-job (ledger Ledger) (number I64)) (→ (Result (Pair Ledger (List String)) String))
      (match (find-job ledger number)
        ((Some job)
         (match (lacking (markers-of ledger (you)) (● job abilities))
           ((Nil) (Ok (report (complete-job ledger (you) job))))
           (missing (Err (string-append "You lack " (abilities-text missing) ".")))))
        ((None) (Err "No such open job."))))

    (define (honor-promise (ledger Ledger) (number I64))
      (→ (Result (Pair Ledger (List String)) String))
      (match (find (lambda (promise)
                     (and (= (● promise number) number) (= (● promise debtor) (you))))
                   (● ledger promises))
        ((Some promise)
         (match (oldest-with (markers-of ledger (you)) (● promise ability))
           ((Some marker) (Ok (report (keep-promise ledger promise marker))))
           ((None) (no-marker (● promise ability)))))
        ((None) (Err "You owe no such promise."))))

    (define (no-marker (ability I64)) (→ (Result (Pair Ledger (List String)) String))
      (Err (string-append "You hold no marker with " (ability-name ability) ".")))

    ;; Answers a command with what it did, a line each, and clears the
    ;; record.
    (define (report (ledger Ledger)) (→ (Pair Ledger (List String)))
      (Pair (Ledger-events-set ledger (Nil)) (reverse (● ledger events))))

    ;; ---- End of round ----

    (define (end-round (ledger Ledger)) (→ (Pair Ledger (List String)))
      (report
       (advance-round
        (remember-round
         (expire-jobs (settle-promises (lapse-markers (rivals-recruit (rivals-work ledger)))))))))

    ;; The screen shows what this end of round did until the next one.
    (define (remember-round (ledger Ledger)) (→ Ledger)
      (Ledger-last-round-set ledger (reverse (● ledger events))))

    ;; 1. Each rival holding markers for every ability its target needs does
    ;; the job.
    (define (rivals-work (ledger Ledger)) (→ Ledger)
      (fold-left (lambda (ledger who)
                   (match (target-job ledger who)
                     ((Some job)
                      (if (null? (lacking (markers-of ledger who) (● job abilities)))
                          (complete-job ledger who job)
                          ledger))
                     ((None) ledger)))
                 ledger (rivals)))

    ;; 2. Each rival gains a marker from a contact drawn at random.
    (define (rivals-recruit (ledger Ledger)) (→ Ledger)
      (fold-left (lambda (ledger who)
                   (let* ((drawn (roll ledger (contact-count)))
                          (marker (grant-marker (● drawn first) (● ledger round))))
                     (note (gain-marker (● drawn second) who marker)
                           (string-append (acts who "gain") " " (describe-marker marker) "."))))
                 ledger (rivals)))

    ;; 4. Promises due this round are honored or refused.
    (define (settle-promises (ledger Ledger)) (→ Ledger)
      (fold-left settle-promise ledger
                 (filter (lambda (promise) (= (● promise due) (● ledger round)))
                         (● ledger promises))))

    (define (settle-promise (ledger Ledger) (promise Promise)) (→ Ledger)
      (let ((debtor (● promise debtor)))
        (match (oldest-with (markers-of ledger debtor) (● promise ability))
          ((Some marker)
           (if (willing? ledger debtor marker)
               (keep-promise ledger promise marker)
               (refuse-promise ledger promise)))
          ((None) (refuse-promise ledger promise)))))

    ;; You keep a promise only by honoring it during your move. Vee honors
    ;; every promise she can; Kit keeps a marker his target needs.
    (define (willing? (ledger Ledger) (debtor I64) (marker Marker)) (→ Bool)
      (cond ((= debtor (you)) #f)
            ((= debtor (kit)) (not (needed? ledger debtor marker)))
            (else #t)))

    ;; A marker is needed when the target needs its ability and no other
    ;; marker in the hand lends it.
    (define (needed? (ledger Ledger) (who I64) (marker Marker)) (→ Bool)
      (let ((ability (marker-ability marker)))
        (and (member? ability (target-needs ledger who))
             (member? ability
                      (lacking (remove-marker marker (markers-of ledger who)) (list ability))))))

    ;; 3. Lapsed markers are removed before promises are settled, so no one
    ;; honors a promise with a marker about to lapse. 5. Expired jobs go
    ;; last, after Kit has judged what his target needs.
    (define (lapse-markers (ledger Ledger)) (→ Ledger)
      (fold-left (lambda (ledger who)
                   (fold-left (lambda (ledger marker)
                                (note (lose-marker ledger who marker)
                                      (string-append (possessive who)
                                                     " "
                                                     (describe-marker marker)
                                                     " lapses.")))
                              ledger
                              (filter
                               (lambda (marker) (<= (● marker lapses) (● ledger round)))
                               (markers-of ledger who))))
                 ledger (everyone)))

    (define (expire-jobs (ledger Ledger)) (→ Ledger)
      (fold-left (lambda (ledger job)
                   (note (Ledger-jobs-set ledger (remove-job (● ledger jobs) job))
                         (string-append "Job " (show (● job number)) " expires.")))
                 ledger
                 (filter (lambda (job) (<= (● job expires) (● ledger round)))
                         (● ledger jobs))))

    ;; After round 8 the game is over; otherwise the next round begins.
    (define (advance-round (ledger Ledger)) (→ Ledger)
      (let ((ledger (Ledger-round-set ledger (+ (● ledger round) 1))))
        (if (ledger-over? ledger)
            (note ledger (ledger-result ledger))
            (note (begin-round ledger)
                  (string-append "Round " (show (● ledger round)) " begins.")))))

    (define (ledger-over? (ledger Ledger)) (→ Bool)
      (> (● ledger round) (round-count)))

    ;; The most standing wins, and coins break ties.
    (define (ahead? (a Fixer) (b Fixer)) (→ Bool)
      (or (> (● a standing) (● b standing))
          (and (= (● a standing) (● b standing)) (> (● a coins) (● b coins)))))

    (define (ledger-result (ledger Ledger)) (→ String)
      (let ((winners (filter (lambda (who)
                               (not (any? (lambda (other) (ahead? other (ledger-fixer ledger who)))
                                          (● ledger fixers))))
                             (everyone))))
        (match winners
          ((Cons who (Nil)) (string-append "The game is over. " (acts who "win") "."))
          (_ (string-append "The game is over. "
                            (string-join (map fixer-name winners) " and ")
                            " tie.")))))

    ;; ---- Choices ----

    ;; A command the board offers: what it does, its terms in a caption, and
    ;; why it would fail now, if it would.
    (struct Choice
      ((command Command)
       (text String)
       (caption String)
       (refusal (Option String)))
      (deriving Serialize Deserialize))

    (define (choice (ledger Ledger) (command Command) (parts (Pair String String))) (→ Choice)
      (Choice command (● parts first) (● parts second)
              (match (ledger-act ledger command)
                ((Ok _) (None))
                ((Err why) (Some why)))))

    ;; One rival's offers.
    (define (offer-choices (ledger Ledger) (rival I64)) (→ (List Choice))
      (map (lambda (offer) (choice ledger (Accept (● offer number)) (offer-parts offer)))
           (filter (lambda (offer) (= (● offer rival) rival)) (● ledger offers))))

    (define (contact-choices (ledger Ledger)) (→ (List Choice))
      (map (lambda (contact) (choice ledger (Meet contact) (contact-parts ledger contact)))
           (iota (contact-count))))

    (define (job-choices (ledger Ledger)) (→ (List Choice))
      (map (lambda (job) (choice ledger (Work (● job number)) (job-parts job)))
           (● ledger jobs)))

    ;; Only the promises you owe can be honored.
    (define (promise-choices (ledger Ledger)) (→ (List Choice))
      (map
       (lambda (promise) (choice ledger (Honor (● promise number)) (promise-parts promise)))
       (filter (lambda (promise) (= (● promise debtor) (you))) (● ledger promises))))

    ;; The rivals you owe a marker by the end of this round.
    (define (due-now (ledger Ledger)) (→ (List String))
      (map (lambda (promise) (fixer-name (● promise creditor)))
           (filter (lambda (promise)
                     (and (= (● promise debtor) (you))
                          (= (● promise due) (● ledger round))))
                   (● ledger promises))))

    ;; ---- Text ----

    ;; "You refuse", "Vee refuses".
    (define (acts (who I64) (verb String)) (→ String)
      (string-append (fixer-name who) " " verb (if (= who (you)) "" "s")))

    ;; "and lose", "and loses".
    (define (acts-object (who I64) (verb String)) (→ String)
      (string-append verb (if (= who (you)) "" "s")))

    (define (object-name (who I64)) (→ String)
      (if (= who (you)) "you" (fixer-name who)))

    (define (possessive (who I64)) (→ String)
      (if (= who (you)) "Your" (string-append (fixer-name who) "'s")))

    (define (coins-text (coins I64)) (→ String)
      (string-append (show coins) (if (= coins 1) " coin" " coins")))

    (define (abilities-text (abilities (List I64))) (→ String)
      (string-join (map ability-name abilities) " + "))

    (define (describe-marker (marker Marker)) (→ String)
      (string-append (contact-name (● marker contact))
                     " ("
                     (ability-name (marker-ability marker))
                     ", through round " (show (● marker lapses)) ")"))

    (define (describe-want (want Want)) (→ String)
      (match want
        ((WantAbility ability) (string-append "a marker with " (ability-name ability)))
        ((WantCoins coins) (coins-text coins))))

    (define (describe-offer (offer Offer)) (→ String)
      (let ((rival (fixer-name (● offer rival)))
            (price (coins-text (● offer price))))
        (match (● offer deal)
          ((Buy ability)
           (string-append rival
                          " buys your oldest "
                          (ability-name ability)
                          " marker for "
                          price
                          "."))
          ((Sell marker) (string-append rival " sells " (describe-marker marker) " for " price "."))
          ((PromiseWanted ability due)
           (string-append rival
                          " pays "
                          price
                          " for your promise of "
                          (ability-name ability)
                          " by round "
                          (show due)
                          "."))
          ((PromiseOffered ability due)
           (string-append rival
                          " promises you "
                          (ability-name ability)
                          " by round "
                          (show due)
                          " for "
                          price
                          ".")))))

    ;; A choice's text and caption: what it does, and its terms.
    (define (offer-parts (offer Offer)) (→ (Pair String String))
      (let ((price (coins-text (● offer price))))
        (match (● offer deal)
          ((Buy ability)
           (Pair (string-append "Buys your oldest " (ability-name ability) " marker")
                 (string-append "pays " price)))
          ((Sell marker)
           (Pair (string-append "Sells "
                                (contact-name (● marker contact))
                                " ("
                                (ability-name (marker-ability marker))
                                ")")
                 (string-append "for "
                                price
                                ", lapses after round "
                                (show (● marker lapses)))))
          ((PromiseWanted ability due)
           (Pair (string-append "Wants your promise of " (ability-name ability))
                 (string-append "pays " price " now, due at the end of round " (show due))))
          ((PromiseOffered ability due)
           (Pair (string-append "Promises you " (ability-name ability))
                 (string-append "for " price ", due at the end of round " (show due)))))))

    (define (contact-parts (ledger Ledger) (contact I64)) (→ (Pair String String))
      (Pair (string-append (contact-name contact) " (" (ability-name (contact-ability contact)) ")")
            (if (member? contact (● ledger met))
                "met this round"
                (string-append "wants " (describe-want (list-ref (● ledger wants) contact))))))

    (define (job-parts (job Job)) (→ (Pair String String))
      (Pair (string-append "Job " (show (● job number)) ": " (abilities-text (● job abilities)))
            (string-append (coins-text (job-coins job))
                           " and "
                           (show (job-standing job))
                           " standing, open through round "
                           (show (● job expires)))))

    (define (promise-parts (promise Promise)) (→ (Pair String String))
      (Pair (string-append "Give "
                           (object-name (● promise creditor))
                           " a "
                           (ability-name (● promise ability))
                           " marker")
            (string-append "due at the end of round " (show (● promise due)))))

    ;; A fixer's coins, standing and record of promises.
    (define (fixer-stats (ledger Ledger) (who I64)) (→ String)
      (let ((fixer (ledger-fixer ledger who)))
        (string-append (coins-text (● fixer coins))
                       " · "
                       (show (● fixer standing))
                       " standing · kept "
                       (show (● fixer kept)) ", refused " (show (● fixer refused)))))

    ;; A fixer's markers, and for a rival the job it works toward, a line
    ;; each.
    (define (fixer-holdings (ledger Ledger) (who I64)) (→ (List String))
      (let ((markers (markers-of ledger who)))
        (Cons (if (null? markers)
                  "No markers"
                  (string-append "Markers: " (string-join (map describe-marker markers) ", ")))
              (match (target-job ledger who)
                ((Some job) (list (string-append "Working toward job " (show (● job number)))))
                ((None) (Nil))))))

    (define (describe-promise (promise Promise)) (→ String)
      (string-append (acts (● promise debtor) "owe") " "
                     (object-name (● promise creditor))
                     " a marker with "
                     (ability-name (● promise ability))
                     ", due at the end of round " (show (● promise due)) "."))

    (define (ledger-header (ledger Ledger)) (→ String)
      (if (ledger-over? ledger)
          "Final standings"
          (string-append "Round " (show (● ledger round)) " of " (show (round-count)))))

    ;; The promises rivals owe you; the ones you owe are choices.
    (define (owed-lines (ledger Ledger)) (→ (List String))
      (map describe-promise
           (filter (lambda (promise) (not (= (● promise debtor) (you))))
                   (● ledger promises))))

    ))
