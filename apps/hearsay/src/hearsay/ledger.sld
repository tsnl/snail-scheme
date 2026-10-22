;; The favor ledger: a solo fixer trading markers, promises and coins with
;; two rival fixers for standing. The rules are in prototypes.md;
;; (hearsay ledger-screen) plays them in the browser.
(define-library (hearsay ledger)
  (export
   Ledger
   new-ledger
   ledger-over?
   Command
   Accept
   Meet
   Work
   Honor
   EndRound
   ledger-act
   Choice
   Choice-command
   Choice-text
   Choice-refusal
   offer-choices
   contact-choices
   job-choices
   promise-choices
   ledger-header
   ledger-intro
   fixer-lines
   owed-lines
   last-round-lines
   ledger-result
   ledger-board)
  (import
   (lofi base)
   (lofi wire)
   (lofi random))
  (begin

    ;; ---- Pieces ----

    ;; Abilities, contacts and fixers are indices into these tables. Contact
    ;; c lends the ability (list-ref contact-abilities c).
    (: ability-names (List String))
    (define ability-names (list "doors" "muscle" "medicine" "fencing" "paperwork" "eyes"))

    (: ability-count I64)
    (define ability-count 6)

    (: contact-names (List String))
    (define contact-names (list "Ivo" "Ren" "Sal" "Tia" "Una" "Vik" "Wes" "Xan"))

    (: contact-abilities (List I64))
    (define contact-abilities (list 2 0 1 3 4 5 0 1))

    (: contact-count I64)
    (define contact-count 8)

    (: round-count I64)
    (define round-count 8)

    (: ability-name (-> I64 String))
    (define (ability-name ability)
      (list-ref ability-names ability))

    (: contact-name (-> I64 String))
    (define (contact-name contact)
      (list-ref contact-names contact))

    (: contact-ability (-> I64 I64))
    (define (contact-ability contact)
      (list-ref contact-abilities contact))

    ;; Fixer 0 is you; Vee and Kit are the rivals.
    (: you I64)
    (define you 0)

    (: kit I64)
    (define kit 2)

    (: rivals (List I64))
    (define rivals (list 1 2))

    (: everyone (List I64))
    (define everyone (list 0 1 2))

    (: fixer-name (-> I64 String))
    (define (fixer-name who)
      (list-ref (list "You" "Vee" "Kit") who))

    ;; ---- Markers ----

    ;; A marker lends its holder its contact's ability once. It lapses at the
    ;; end of round `lapses`, the second round after the one in which it was
    ;; granted, and keeps that date when it changes hands.
    (struct Marker
      ((contact I64)
       (lapses I64))
      (deriving Serialize Deserialize))

    (: grant-marker (-> I64 I64 Marker))
    (define (grant-marker contact granted)
      (Marker contact (+ granted 2)))

    (: marker-ability (-> Marker I64))
    (define (marker-ability marker)
      (contact-ability (Marker-contact marker)))

    ;; The older marker lapses first; between equal dates, the lower contact
    ;; is older.
    (: older? (-> Marker Marker Bool))
    (define (older? a b)
      (or (< (Marker-lapses a) (Marker-lapses b))
          (and (= (Marker-lapses a) (Marker-lapses b)) (< (Marker-contact a) (Marker-contact b)))))

    (: same-marker? (-> Marker Marker Bool))
    (define (same-marker? a b)
      (and (= (Marker-contact a) (Marker-contact b)) (= (Marker-lapses a) (Marker-lapses b))))

    ;; A hand of markers stays sorted oldest first, so the first marker with
    ;; an ability is the oldest one.
    (: insert-marker (-> Marker (List Marker) (List Marker)))
    (define (insert-marker marker markers)
      (match markers
        ((Nil) (list marker))
        ((Cons first rest)
         (if (older? first marker)
             (Cons first (insert-marker marker rest))
             (Cons marker markers)))))

    (: remove-marker (-> Marker (List Marker) (List Marker)))
    (define (remove-marker marker markers)
      (match markers
        ((Nil) (Nil))
        ((Cons first rest)
         (if (same-marker? first marker) rest (Cons first (remove-marker marker rest))))))

    (: oldest-with (-> (List Marker) I64 (Option Marker)))
    (define (oldest-with markers ability)
      (find (lambda (marker) (= (marker-ability marker) ability)) markers))

    ;; The abilities, in order, that no marker in the hand lends.
    (: lacking (-> (List Marker) (List I64) (List I64)))
    (define (lacking markers abilities)
      (filter (lambda (ability) (null? (filter (lambda (marker) (= (marker-ability marker) ability)) markers)))
              abilities))

    ;; Spends the oldest marker for each ability. The caller has checked that
    ;; none is lacking.
    (: spend-for (-> (List Marker) (List I64) (List Marker)))
    (define (spend-for markers abilities)
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
    (: job-coins (-> Job I64))
    (define (job-coins job)
      (* 2 (length (Job-abilities job))))

    (: job-standing (-> Job I64))
    (define (job-standing job)
      (- (length (Job-abilities job)) 1))

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
    (: offer-payer (-> Offer I64))
    (define (offer-payer offer)
      (match (Offer-deal offer)
        ((Buy _) (Offer-rival offer))
        ((PromiseWanted _ _) (Offer-rival offer))
        ((Sell _) you)
        ((PromiseOffered _ _) you)))

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
    ;; oldest first, for the board.
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

    (: replace-at (All (T) (-> (List T) I64 T (List T))))
    (define (replace-at items index value)
      (map-indexed (lambda (at item) (if (= at index) value item)) items))

    (: ledger-fixer (-> Ledger I64 Fixer))
    (define (ledger-fixer ledger who)
      (list-ref (Ledger-fixers ledger) who))

    (: ledger-fixer-set (-> Ledger I64 Fixer Ledger))
    (define (ledger-fixer-set ledger who fixer)
      (Ledger-fixers-set ledger (replace-at (Ledger-fixers ledger) who fixer)))

    (: markers-of (-> Ledger I64 (List Marker)))
    (define (markers-of ledger who)
      (Fixer-markers (ledger-fixer ledger who)))

    (: coins-of (-> Ledger I64 I64))
    (define (coins-of ledger who)
      (Fixer-coins (ledger-fixer ledger who)))

    ;; A roll below `bound`, and the ledger with its generator advanced past it.
    (: roll (-> Ledger I64 (Pair I64 Ledger)))
    (define (roll ledger bound)
      (let ((random (Ledger-random ledger)))
        (Pair (random-below random bound) (Ledger-random-set ledger (random-next random)))))

    (: note (-> Ledger String Ledger))
    (define (note ledger text)
      (Ledger-events-set ledger (Cons text (Ledger-events ledger))))

    ;; ---- Holdings ----

    (: add-coins (-> Ledger I64 I64 Ledger))
    (define (add-coins ledger who amount)
      (let ((fixer (ledger-fixer ledger who)))
        (ledger-fixer-set ledger who (Fixer-coins-set fixer (+ (Fixer-coins fixer) amount)))))

    (: transfer-coins (-> Ledger I64 I64 I64 Ledger))
    (define (transfer-coins ledger from to amount)
      (add-coins (add-coins ledger from (negate amount)) to amount))

    (: gain-marker (-> Ledger I64 Marker Ledger))
    (define (gain-marker ledger who marker)
      (let ((fixer (ledger-fixer ledger who)))
        (ledger-fixer-set ledger who (Fixer-markers-set fixer (insert-marker marker (Fixer-markers fixer))))))

    (: lose-marker (-> Ledger I64 Marker Ledger))
    (define (lose-marker ledger who marker)
      (let ((fixer (ledger-fixer ledger who)))
        (ledger-fixer-set ledger who (Fixer-markers-set fixer (remove-marker marker (Fixer-markers fixer))))))

    (: transfer-marker (-> Ledger I64 I64 Marker Ledger))
    (define (transfer-marker ledger from to marker)
      (gain-marker (lose-marker ledger from marker) to marker))

    ;; Doing a job spends one marker per ability and pays coins and standing.
    (: complete-job (-> Ledger I64 Job Ledger))
    (define (complete-job ledger who job)
      (let* ((fixer (ledger-fixer ledger who))
             (fixer (Fixer-markers-set fixer (spend-for (Fixer-markers fixer) (Job-abilities job))))
             (fixer (Fixer-coins-set fixer (+ (Fixer-coins fixer) (job-coins job))))
             (fixer (Fixer-standing-set fixer (+ (Fixer-standing fixer) (job-standing job)))))
        (note (Ledger-jobs-set (ledger-fixer-set ledger who fixer) (remove-job (Ledger-jobs ledger) job))
              (string-append (acts who "complete") " job " (show (Job-number job)) " for "
                             (coins-text (job-coins job)) " and " (show (job-standing job)) " standing."))))

    (: remove-job (-> (List Job) Job (List Job)))
    (define (remove-job jobs job)
      (filter (lambda (other) (not (= (Job-number other) (Job-number job)))) jobs))

    ;; ---- Promises ----

    (: make-promise (-> Ledger I64 I64 I64 I64 Ledger))
    (define (make-promise ledger debtor creditor ability due)
      (let ((promise (Promise (Ledger-next-promise ledger) debtor creditor ability due)))
        (Ledger-next-promise-set (Ledger-promises-set ledger (append (Ledger-promises ledger) (list promise)))
                                 (+ (Promise-number promise) 1))))

    (: drop-promise (-> Ledger Promise Ledger))
    (define (drop-promise ledger promise)
      (Ledger-promises-set ledger (filter (lambda (other) (not (= (Promise-number other) (Promise-number promise))))
                                          (Ledger-promises ledger))))

    ;; Keeping a promise gives the creditor the debtor's marker.
    (: keep-promise (-> Ledger Promise Marker Ledger))
    (define (keep-promise ledger promise marker)
      (let* ((debtor (Promise-debtor promise))
             (fixer (ledger-fixer ledger debtor))
             (ledger (ledger-fixer-set ledger debtor (Fixer-kept-set fixer (+ (Fixer-kept fixer) 1)))))
        (note (drop-promise (transfer-marker ledger debtor (Promise-creditor promise) marker) promise)
              (string-append (acts debtor "honor") " promise " (show (Promise-number promise)) ", giving "
                             (object-name (Promise-creditor promise)) " " (describe-marker marker) "."))))

    ;; Refusing costs the debtor 1 standing and goes on their record.
    (: refuse-promise (-> Ledger Promise Ledger))
    (define (refuse-promise ledger promise)
      (let* ((debtor (Promise-debtor promise))
             (fixer (ledger-fixer ledger debtor))
             (fixer (Fixer-standing-set (Fixer-refused-set fixer (+ (Fixer-refused fixer) 1))
                                        (- (Fixer-standing fixer) 1))))
        (note (drop-promise (ledger-fixer-set ledger debtor fixer) promise)
              (string-append (acts debtor "refuse") " promise " (show (Promise-number promise))
                             " and " (acts-object debtor "lose") " 1 standing."))))

    ;; Once you have refused a promise, rivals pay less, charge more and stop
    ;; asking you for promises.
    (: trusted? (-> Ledger Bool))
    (define (trusted? ledger)
      (= (Fixer-refused (ledger-fixer ledger you)) 0))

    ;; ---- Start of a round ----

    ;; Each fixer starts with 4 coins and two markers from contacts drawn at
    ;; random, dealt in turn and granted in round 1.
    (: new-ledger (-> I64 Ledger))
    (define (new-ledger seed)
      (let* ((fixer (Fixer 4 0 (Nil) 0 0 (None)))
             (ledger (Ledger (make-random seed) 1 (list fixer fixer fixer) (Nil) (Nil) (Nil) (Nil) (Nil) 1 1 (Nil) (Nil)))
             (ledger (fold-left deal-marker ledger (append everyone everyone))))
        (begin-round (draw-wants ledger))))

    (: deal-marker (-> Ledger I64 Ledger))
    (define (deal-marker ledger who)
      (let ((drawn (roll ledger contact-count)))
        (gain-marker (Pair-second drawn) who (grant-marker (Pair-first drawn) (Ledger-round ledger)))))

    (: draw-wants (-> Ledger Ledger))
    (define (draw-wants ledger)
      (fold-left (lambda (ledger contact)
                   (let ((drawn (draw-want ledger contact)))
                     (Ledger-wants-set (Pair-second drawn) (append (Ledger-wants ledger) (list (Pair-first drawn))))))
                 ledger (iota contact-count)))

    ;; Half the time a contact wants one of the five abilities other than
    ;; their own; otherwise 2, 3 or 4 coins.
    (: draw-want (-> Ledger I64 (Pair Want Ledger)))
    (define (draw-want ledger contact)
      (let ((kind (roll ledger 10)))
        (if (< (Pair-first kind) 5)
            (let ((offset (roll (Pair-second kind) 5)))
              (Pair (WantAbility (modulo (+ (contact-ability contact) (+ 1 (Pair-first offset))) ability-count))
                    (Pair-second offset)))
            (let ((coins (roll (Pair-second kind) 3)))
              (Pair (WantCoins (+ 2 (Pair-first coins))) (Pair-second coins))))))

    ;; Steps 1 to 3 of a round come before your move.
    (: begin-round (-> Ledger Ledger))
    (define (begin-round ledger)
      (post-offers (choose-targets (post-jobs (Ledger-met-set ledger (Nil))))))

    ;; 1. Market: new jobs are posted until three are open.
    (: post-jobs (-> Ledger Ledger))
    (define (post-jobs ledger)
      (if (>= (length (Ledger-jobs ledger)) 3)
          ledger
          (post-jobs (post-job ledger))))

    (: post-job (-> Ledger Ledger))
    (define (post-job ledger)
      (let* ((size (roll ledger 2))
             (drawn (draw-abilities (Pair-second size) (+ 2 (Pair-first size))))
             (ledger (Pair-second drawn))
             (job (Job (Ledger-next-job ledger) (Pair-first drawn) (+ (Ledger-round ledger) 1))))
        (Ledger-next-job-set (Ledger-jobs-set ledger (append (Ledger-jobs ledger) (list job)))
                             (+ (Job-number job) 1))))

    ;; Draws `count` different abilities and lists them in ascending order.
    (: draw-abilities (-> Ledger I64 (Pair (List I64) Ledger)))
    (define (draw-abilities ledger count)
      (let loop ((ledger ledger) (left (iota ability-count)) (drawn (Nil)))
        (if (= (length drawn) count)
            (Pair (filter (lambda (ability) (member? ability drawn)) (iota ability-count)) ledger)
            (let* ((pick (roll ledger (length left)))
                   (ability (list-ref left (Pair-first pick))))
              (loop (Pair-second pick) (filter (lambda (other) (not (= other ability))) left) (Cons ability drawn))))))

    ;; 2. Targets: each rival works toward the open job it lacks the fewest
    ;; abilities for; ties go to more standing, then to the job listed first.
    (: choose-targets (-> Ledger Ledger))
    (define (choose-targets ledger)
      (fold-left (lambda (ledger who)
                   (let ((fixer (ledger-fixer ledger who)))
                     (ledger-fixer-set ledger who (Fixer-target-set fixer (best-job (Fixer-markers fixer) (Ledger-jobs ledger))))))
                 ledger rivals))

    (: best-job (-> (List Marker) (List Job) (Option I64)))
    (define (best-job markers jobs)
      (match (fold-left (lambda (best job)
                          (match best
                            ((Some chosen) (if (better-target? markers job chosen) (Some job) best))
                            ((None) (Some job))))
                        (None) jobs)
        ((Some job) (Some (Job-number job)))
        ((None) (None))))

    (: better-target? (-> (List Marker) Job Job Bool))
    (define (better-target? markers job chosen)
      (let ((missing (length (lacking markers (Job-abilities job))))
            (chosen-missing (length (lacking markers (Job-abilities chosen)))))
        (or (< missing chosen-missing)
            (and (= missing chosen-missing) (> (job-standing job) (job-standing chosen))))))

    (: find-job (-> Ledger I64 (Option Job)))
    (define (find-job ledger number)
      (find (lambda (job) (= (Job-number job) number)) (Ledger-jobs ledger)))

    (: target-job (-> Ledger I64 (Option Job)))
    (define (target-job ledger who)
      (match (Fixer-target (ledger-fixer ledger who))
        ((Some number) (find-job ledger number))
        ((None) (None))))

    ;; A target someone else has done needs nothing.
    (: target-needs (-> Ledger I64 (List I64)))
    (define (target-needs ledger who)
      (match (target-job ledger who)
        ((Some job) (Job-abilities job))
        ((None) (Nil))))

    ;; 3. Offers: each rival posts its offers in order, numbered from 1
    ;; across both rivals. Accepting an offer removes it until the round ends.
    (: post-offers (-> Ledger Ledger))
    (define (post-offers ledger)
      (fold-left post-rival-offers (Ledger-offers-set ledger (Nil)) rivals))

    (: post-rival-offers (-> Ledger I64 Ledger))
    (define (post-rival-offers ledger who)
      (let ((promised (roll ledger ability-count)))
        (fold-left (lambda (ledger deal) (post-offer ledger who (Pair-first deal) (Pair-second deal)))
                   (Pair-second promised)
                   (rival-deals (Pair-second promised) who (Pair-first promised)))))

    (: post-offer (-> Ledger I64 I64 Deal Ledger))
    (define (post-offer ledger who price deal)
      (let ((offers (Ledger-offers ledger)))
        (Ledger-offers-set ledger (append offers (list (Offer (+ (length offers) 1) who price deal))))))

    ;; A rival buys the first ability its target lacks, sells a marker its
    ;; target does not need, wants your promise of the ability it lacks last,
    ;; and offers its promise of `promised`, skipping what it has nothing for.
    (: rival-deals (-> Ledger I64 I64 (List (Pair I64 Deal))))
    (define (rival-deals ledger who promised)
      (let* ((needs (target-needs ledger who))
             (missing (lacking (markers-of ledger who) needs))
             (spare (filter (lambda (marker) (not (member? (marker-ability marker) needs))) (markers-of ledger who)))
             (trusted (trusted? ledger))
             (due (+ (Ledger-round ledger) 2)))
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
    (: ledger-act (-> Ledger Command (Result (Pair Ledger String) String)))
    (define (ledger-act ledger command)
      (if (ledger-over? ledger)
          (Err "The game is over.")
          (match command
            ((Accept number) (accept-offer ledger number))
            ((Meet contact) (meet-contact ledger contact))
            ((Work number) (work-job ledger number))
            ((Honor number) (honor-promise ledger number))
            ((EndRound) (Ok (end-round ledger))))))

    (: accept-offer (-> Ledger I64 (Result (Pair Ledger String) String)))
    (define (accept-offer ledger number)
      (match (find (lambda (offer) (= (Offer-number offer) number)) (Ledger-offers ledger))
        ((Some offer)
         (if (< (coins-of ledger (offer-payer offer)) (Offer-price offer))
             (Err (string-append (fixer-name (offer-payer offer)) " cannot pay " (coins-text (Offer-price offer)) "."))
             (accept-deal ledger offer)))
        ((None) (Err "No such offer."))))

    ;; A rival loses markers only at the end of a round, when its offers are
    ;; withdrawn, so the marker it sells is still in its hand.
    (: accept-deal (-> Ledger Offer (Result (Pair Ledger String) String)))
    (define (accept-deal ledger offer)
      (let ((rival (Offer-rival offer)))
        (match (Offer-deal offer)
          ((Buy ability)
           (match (oldest-with (markers-of ledger you) ability)
             ((Some marker) (Ok (report (settle-offer (transfer-marker ledger you rival marker) offer))))
             ((None) (no-marker ability))))
          ((Sell marker) (Ok (report (settle-offer (transfer-marker ledger rival you marker) offer))))
          ((PromiseWanted ability due) (Ok (report (settle-offer (make-promise ledger you rival ability due) offer))))
          ((PromiseOffered ability due) (Ok (report (settle-offer (make-promise ledger rival you ability due) offer)))))))

    ;; The price changes hands and the offer is taken off the board.
    (: settle-offer (-> Ledger Offer Ledger))
    (define (settle-offer ledger offer)
      (let* ((payer (offer-payer offer))
             (payee (if (= payer you) (Offer-rival offer) you))
             (offers (filter (lambda (other) (not (= (Offer-number other) (Offer-number offer)))) (Ledger-offers ledger))))
        (note (Ledger-offers-set (transfer-coins ledger payer payee (Offer-price offer)) offers)
              (string-append "You accept: " (describe-offer offer)))))

    ;; Each contact can be met once a round.
    (: meet-contact (-> Ledger I64 (Result (Pair Ledger String) String)))
    (define (meet-contact ledger contact)
      (cond ((not (and (>= contact 0) (< contact contact-count))) (Err "No such contact."))
            ((member? contact (Ledger-met ledger)) (Err (string-append (contact-name contact) " has already been met this round.")))
            (else (meet-want ledger contact (list-ref (Ledger-wants ledger) contact)))))

    ;; You meet a want by paying its coins or spending your oldest marker
    ;; with its ability.
    (: meet-want (-> Ledger I64 Want (Result (Pair Ledger String) String)))
    (define (meet-want ledger contact want)
      (match want
        ((WantCoins coins)
         (if (< (coins-of ledger you) coins)
             (Err (string-append "You cannot pay " (coins-text coins) "."))
             (Ok (report (grant-favor (note (add-coins ledger you (negate coins))
                                            (string-append "You pay " (contact-name contact) " " (coins-text coins) "."))
                                      contact)))))
        ((WantAbility ability)
         (match (oldest-with (markers-of ledger you) ability)
           ((Some marker)
            (Ok (report (grant-favor (note (lose-marker ledger you marker)
                                           (string-append "You spend " (describe-marker marker) " for " (contact-name contact) "."))
                                     contact))))
           ((None) (no-marker ability))))))

    ;; A contact whose want is met grants you a marker and draws a new want.
    (: grant-favor (-> Ledger I64 Ledger))
    (define (grant-favor ledger contact)
      (let* ((marker (grant-marker contact (Ledger-round ledger)))
             (drawn (draw-want ledger contact))
             (ledger (Ledger-wants-set (Pair-second drawn) (replace-at (Ledger-wants ledger) contact (Pair-first drawn)))))
        (note (Ledger-met-set (gain-marker ledger you marker) (Cons contact (Ledger-met ledger)))
              (string-append (contact-name contact) " grants you a marker through round " (show (Marker-lapses marker))
                             " and now wants " (describe-want (Pair-first drawn)) "."))))

    (: work-job (-> Ledger I64 (Result (Pair Ledger String) String)))
    (define (work-job ledger number)
      (match (find-job ledger number)
        ((Some job)
         (match (lacking (markers-of ledger you) (Job-abilities job))
           ((Nil) (Ok (report (complete-job ledger you job))))
           (missing (Err (string-append "You lack " (abilities-text missing) ".")))))
        ((None) (Err "No such open job."))))

    (: honor-promise (-> Ledger I64 (Result (Pair Ledger String) String)))
    (define (honor-promise ledger number)
      (match (find (lambda (promise) (and (= (Promise-number promise) number) (= (Promise-debtor promise) you)))
                   (Ledger-promises ledger))
        ((Some promise)
         (match (oldest-with (markers-of ledger you) (Promise-ability promise))
           ((Some marker) (Ok (report (keep-promise ledger promise marker))))
           ((None) (no-marker (Promise-ability promise)))))
        ((None) (Err "You owe no such promise."))))

    (: no-marker (-> I64 (Result (Pair Ledger String) String)))
    (define (no-marker ability)
      (Err (string-append "You hold no marker with " (ability-name ability) ".")))

    ;; Answers a command with what it did, and clears the record.
    (: report (-> Ledger (Pair Ledger String)))
    (define (report ledger)
      (Pair (Ledger-events-set ledger (Nil)) (string-join (reverse (Ledger-events ledger)) "\n")))

    ;; ---- End of round ----

    (: end-round (-> Ledger (Pair Ledger String)))
    (define (end-round ledger)
      (report (advance-round (remember-round (expire-jobs (settle-promises (lapse-markers (rivals-recruit (rivals-work ledger)))))))))

    ;; The board shows what this end of round did until the next one.
    (: remember-round (-> Ledger Ledger))
    (define (remember-round ledger)
      (Ledger-last-round-set ledger (reverse (Ledger-events ledger))))

    ;; 1. Each rival holding markers for every ability its target needs does
    ;; the job.
    (: rivals-work (-> Ledger Ledger))
    (define (rivals-work ledger)
      (fold-left (lambda (ledger who)
                   (match (target-job ledger who)
                     ((Some job) (if (null? (lacking (markers-of ledger who) (Job-abilities job))) (complete-job ledger who job) ledger))
                     ((None) ledger)))
                 ledger rivals))

    ;; 2. Each rival gains a marker from a contact drawn at random.
    (: rivals-recruit (-> Ledger Ledger))
    (define (rivals-recruit ledger)
      (fold-left (lambda (ledger who)
                   (let* ((drawn (roll ledger contact-count))
                          (marker (grant-marker (Pair-first drawn) (Ledger-round ledger))))
                     (note (gain-marker (Pair-second drawn) who marker)
                           (string-append (acts who "gain") " " (describe-marker marker) "."))))
                 ledger rivals))

    ;; 4. Promises due this round are honored or refused.
    (: settle-promises (-> Ledger Ledger))
    (define (settle-promises ledger)
      (fold-left settle-promise ledger
                 (filter (lambda (promise) (= (Promise-due promise) (Ledger-round ledger))) (Ledger-promises ledger))))

    (: settle-promise (-> Ledger Promise Ledger))
    (define (settle-promise ledger promise)
      (let ((debtor (Promise-debtor promise)))
        (match (oldest-with (markers-of ledger debtor) (Promise-ability promise))
          ((Some marker)
           (if (willing? ledger debtor marker) (keep-promise ledger promise marker) (refuse-promise ledger promise)))
          ((None) (refuse-promise ledger promise)))))

    ;; You keep a promise only by honoring it during your move. Vee honors
    ;; every promise she can; Kit keeps a marker his target needs.
    (: willing? (-> Ledger I64 Marker Bool))
    (define (willing? ledger debtor marker)
      (cond ((= debtor you) #f)
            ((= debtor kit) (not (needed? ledger debtor marker)))
            (else #t)))

    ;; A marker is needed when the target needs its ability and no other
    ;; marker in the hand lends it.
    (: needed? (-> Ledger I64 Marker Bool))
    (define (needed? ledger who marker)
      (let ((ability (marker-ability marker)))
        (and (member? ability (target-needs ledger who))
             (member? ability (lacking (remove-marker marker (markers-of ledger who)) (list ability))))))

    ;; 3. Lapsed markers are removed before promises are settled, so no one
    ;; honors a promise with a marker about to lapse. 5. Expired jobs go
    ;; last, after Kit has judged what his target needs.
    (: lapse-markers (-> Ledger Ledger))
    (define (lapse-markers ledger)
      (fold-left (lambda (ledger who)
                   (fold-left (lambda (ledger marker)
                                (note (lose-marker ledger who marker)
                                      (string-append (possessive who) " " (describe-marker marker) " lapses.")))
                              ledger
                              (filter (lambda (marker) (<= (Marker-lapses marker) (Ledger-round ledger))) (markers-of ledger who))))
                 ledger everyone))

    (: expire-jobs (-> Ledger Ledger))
    (define (expire-jobs ledger)
      (fold-left (lambda (ledger job)
                   (note (Ledger-jobs-set ledger (remove-job (Ledger-jobs ledger) job))
                         (string-append "Job " (show (Job-number job)) " expires.")))
                 ledger
                 (filter (lambda (job) (<= (Job-expires job) (Ledger-round ledger))) (Ledger-jobs ledger))))

    ;; After round 8 the game is over; otherwise the next round begins.
    (: advance-round (-> Ledger Ledger))
    (define (advance-round ledger)
      (let ((ledger (Ledger-round-set ledger (+ (Ledger-round ledger) 1))))
        (if (ledger-over? ledger)
            (note ledger (ledger-result ledger))
            (note (begin-round ledger) (string-append "Round " (show (Ledger-round ledger)) " begins.")))))

    (: ledger-over? (-> Ledger Bool))
    (define (ledger-over? ledger)
      (> (Ledger-round ledger) round-count))

    ;; The most standing wins, and coins break ties.
    (: ahead? (-> Fixer Fixer Bool))
    (define (ahead? a b)
      (or (> (Fixer-standing a) (Fixer-standing b))
          (and (= (Fixer-standing a) (Fixer-standing b)) (> (Fixer-coins a) (Fixer-coins b)))))

    (: ledger-result (-> Ledger String))
    (define (ledger-result ledger)
      (let ((winners (filter (lambda (who)
                               (not (any? (lambda (other) (ahead? other (ledger-fixer ledger who))) (Ledger-fixers ledger))))
                             everyone)))
        (match winners
          ((Cons who (Nil)) (string-append "The game is over. " (acts who "win") "."))
          (_ (string-append "The game is over. " (string-join (map fixer-name winners) " and ") " tie.")))))

    ;; ---- Choices ----

    ;; A command the board offers, and why it would fail now, if it would.
    (struct Choice
      ((command Command)
       (text String)
       (refusal (Option String)))
      (deriving Serialize Deserialize))

    (: choice (-> Ledger Command String Choice))
    (define (choice ledger command text)
      (Choice command text
              (match (ledger-act ledger command)
                ((Ok _) (None))
                ((Err why) (Some why)))))

    (: offer-choices (-> Ledger (List Choice)))
    (define (offer-choices ledger)
      (map (lambda (offer) (choice ledger (Accept (Offer-number offer)) (describe-offer offer))) (Ledger-offers ledger)))

    (: contact-choices (-> Ledger (List Choice)))
    (define (contact-choices ledger)
      (map (lambda (contact) (choice ledger (Meet contact) (describe-contact ledger contact))) (iota contact-count)))

    (: job-choices (-> Ledger (List Choice)))
    (define (job-choices ledger)
      (map (lambda (job) (choice ledger (Work (Job-number job)) (describe-job job))) (Ledger-jobs ledger)))

    ;; Only the promises you owe can be honored.
    (: promise-choices (-> Ledger (List Choice)))
    (define (promise-choices ledger)
      (map (lambda (promise) (choice ledger (Honor (Promise-number promise)) (describe-promise promise)))
           (filter (lambda (promise) (= (Promise-debtor promise) you)) (Ledger-promises ledger))))

    ;; ---- Text ----

    ;; "You refuse", "Vee refuses".
    (: acts (-> I64 String String))
    (define (acts who verb)
      (string-append (fixer-name who) " " verb (if (= who you) "" "s")))

    ;; "and lose", "and loses".
    (: acts-object (-> I64 String String))
    (define (acts-object who verb)
      (string-append verb (if (= who you) "" "s")))

    (: object-name (-> I64 String))
    (define (object-name who)
      (if (= who you) "you" (fixer-name who)))

    (: possessive (-> I64 String))
    (define (possessive who)
      (if (= who you) "Your" (string-append (fixer-name who) "'s")))

    (: coins-text (-> I64 String))
    (define (coins-text coins)
      (string-append (show coins) (if (= coins 1) " coin" " coins")))

    (: abilities-text (-> (List I64) String))
    (define (abilities-text abilities)
      (string-join (map ability-name abilities) " + "))

    (: describe-marker (-> Marker String))
    (define (describe-marker marker)
      (string-append (contact-name (Marker-contact marker)) " (" (ability-name (marker-ability marker))
                     ", through round " (show (Marker-lapses marker)) ")"))

    (: describe-want (-> Want String))
    (define (describe-want want)
      (match want
        ((WantAbility ability) (string-append "a marker with " (ability-name ability)))
        ((WantCoins coins) (coins-text coins))))

    (: describe-job (-> Job String))
    (define (describe-job job)
      (string-append "Job " (show (Job-number job)) ": " (abilities-text (Job-abilities job)) ", for "
                     (coins-text (job-coins job)) " and " (show (job-standing job)) " standing, open through round "
                     (show (Job-expires job))))

    (: describe-offer (-> Offer String))
    (define (describe-offer offer)
      (let ((rival (fixer-name (Offer-rival offer)))
            (price (coins-text (Offer-price offer))))
        (match (Offer-deal offer)
          ((Buy ability) (string-append rival " buys your oldest " (ability-name ability) " marker for " price "."))
          ((Sell marker) (string-append rival " sells " (describe-marker marker) " for " price "."))
          ((PromiseWanted ability due)
           (string-append rival " pays " price " for your promise of " (ability-name ability) " by round " (show due) "."))
          ((PromiseOffered ability due)
           (string-append rival " promises you " (ability-name ability) " by round " (show due) " for " price ".")))))

    (: describe-promise (-> Promise String))
    (define (describe-promise promise)
      (string-append (acts (Promise-debtor promise) "owe") " "
                     (object-name (Promise-creditor promise)) " a marker with " (ability-name (Promise-ability promise))
                     ", due at the end of round " (show (Promise-due promise)) "."))

    ;; Everything the final standings show of a fixer.
    (: fixer-summary (-> Ledger I64 String))
    (define (fixer-summary ledger who)
      (let ((fixer (ledger-fixer ledger who)))
        (string-append (fixer-name who) ": " (coins-text (Fixer-coins fixer)) ", " (show (Fixer-standing fixer))
                       " standing, promises kept " (show (Fixer-kept fixer)) " and refused " (show (Fixer-refused fixer)))))

    (: describe-fixer (-> Ledger I64 String))
    (define (describe-fixer ledger who)
      (let ((markers (markers-of ledger who)))
        (string-append (fixer-summary ledger who)
                       (match (target-job ledger who)
                         ((Some job) (string-append ", targets job " (show (Job-number job))))
                         ((None) ""))
                       "\n    markers: " (if (null? markers) "none" (string-join (map describe-marker markers) ", ")))))

    (: describe-contact (-> Ledger I64 String))
    (define (describe-contact ledger contact)
      (string-append (contact-name contact) " (" (ability-name (contact-ability contact))
                     ") wants " (describe-want (list-ref (Ledger-wants ledger) contact))
                     (if (member? contact (Ledger-met ledger)) "; met this round" "")))

    ;; A title over indented lines.
    (: section (-> String (List String) String))
    (define (section title lines)
      (string-join (Cons title (map (lambda (line) (string-append "  " line)) (if (null? lines) (list "none") lines)))
                   "\n"))

    (: ledger-intro (-> String))
    (define (ledger-intro)
      (string-append "Trade markers, promises and coins with Vee and Kit for eight rounds; the most standing wins."
                     " Green buttons can be done now. End the round when you are done."))

    (: ledger-header (-> Ledger String))
    (define (ledger-header ledger)
      (if (ledger-over? ledger)
          "Final standings"
          (string-append "Round " (show (Ledger-round ledger)) " of " (show round-count))))

    (: fixer-lines (-> Ledger (List String)))
    (define (fixer-lines ledger)
      (map (lambda (who) (if (ledger-over? ledger) (fixer-summary ledger who) (describe-fixer ledger who))) everyone))

    ;; The promises rivals owe you; the ones you owe are choices.
    (: owed-lines (-> Ledger (List String)))
    (define (owed-lines ledger)
      (map describe-promise (filter (lambda (promise) (not (= (Promise-debtor promise) you))) (Ledger-promises ledger))))

    (: last-round-lines (-> Ledger (List String)))
    (define (last-round-lines ledger)
      (Ledger-last-round ledger))

    ;; Everything at once, for scripted tests.
    (: ledger-board (-> Ledger String))
    (define (ledger-board ledger)
      (if (ledger-over? ledger)
          (string-join (list (section (ledger-header ledger) (fixer-lines ledger)) (ledger-result ledger)
                             (section "Last round" (last-round-lines ledger)))
                       "\n\n")
          (playing-board ledger)))

    (: playing-board (-> Ledger String))
    (define (playing-board ledger)
      (let ((texts (lambda (choices) (map Choice-text choices))))
        (string-join (list (ledger-header ledger)
                           (section "Fixers" (fixer-lines ledger))
                           (section "Contacts" (texts (contact-choices ledger)))
                           (section "Jobs" (texts (job-choices ledger)))
                           (section "Offers" (texts (offer-choices ledger)))
                           (section "Promises" (append (texts (promise-choices ledger)) (owed-lines ledger)))
                           (section "Last round" (last-round-lines ledger)))
                     "\n\n")))

    ))
