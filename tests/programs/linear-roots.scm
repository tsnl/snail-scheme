(import
 (snail core base)
 (snail core io)
 (only (snail shell task)
       Mailbox
       make-mailbox
       mailbox-receive
       make-scheduler
       dispatch-in
       tasks-turn))

;; Force collection at every allocation while the only path to a value is
;; through a cycle, an array, a suspended frame, or an earlier operand.
(extern stress! "snail.core.support" "snail:gc/stress" (Fn I32 → Unit))
(extern collect! "snail.core.support" "snail:gc/collect" (Fn → Unit))
(extern profile! "snail.core.support" "snail:gc/profile" (Fn I32 → Unit))
(extern allocations "snail.core.support" "snail:gc/profile-allocations" (Fn → I64))
(extern live-bytes "snail.core.support" "snail:gc/live" (Fn → I32))

(record Link
  ((value I64)
   (next (Option Link))))

(define (link (n I64)) (→ Link) (new Link (value n) (next (None))))

(define (cycle) (→ Link)
  (let ((a (link 19)) (b (link 23)))
    (set! (● a next) (Some b))
    (set! (● b next) (Some a))
    a))

(define (read-cycle (a Link)) (→ I64)
  (match (● a next) ((Some b) (+ (● a value) (● b value))) (_ 0)))

(define (earlier (a Link) (b Link)) (→ I64)
  (+ (read-cycle a) (● b value)))

(define question (→ (Prompt I64 I64)) (make-prompt))

(define (paused) (→ I64)
  (let* ((saved (cycle)) (reply (suspend question 1)))
    (+ (read-cycle saved) reply)))

(define (bump! (n I64) (slot (MutRef I64))) (→ Unit)
  (if (= n 0) (unit)
      (begin (ref-set! slot (+ (ref-get slot) 1))
             (bump! (- n 1) (ref! slot)))))

;; The scheduler retains the suspended receiver, the receiver retains its
;; mailbox, and the mailbox's waker captures the scheduler. Abandon all three.
(define (park-receiver) (→ Unit)
  (let ((scheduler (make-scheduler)) (mailbox (ann (make-mailbox) (Mailbox I64))))
    (dispatch-in scheduler (lambda () (mailbox-receive mailbox) (unit)))
    (unless (= (tasks-turn scheduler 0) -2) (panic "the receiver did not park"))))

(define (fill-cache (memo (Fn I64 → I64))) (→ Unit)
  (unless (= (+ (+ (memo 1) (memo 2)) (+ (memo 3) (memo 1))) 11) (panic "wrong cache result")))

;; Both memoizers link adjacent entries in both directions. The bounded
;; case also evicts and then reinserts a key.
(define (abandon-caches) (→ Unit)
  (let ((inc (lambda ((n I64)) (→ I64) (+ n 1))))
    (fill-cache (cache inc))
    (fill-cache (lru-cache 2 inc))))

(define (drop-graphs (count I64) (build (Fn → Unit))) (→ Unit)
  (unless (= count 0) (build) (drop-graphs (- count 1) build)))

(define (live-after-graphs (count I64) (build (Fn → Unit))) (→ I32)
  (drop-graphs count build)
  (collect!)
  (live-bytes))

(define (reclaimed? (build (Fn → Unit))) (→ Bool)
  (let ((before (live-after-graphs 1 build)))
    (= before (live-after-graphs 128 build))))

(define (main (out OutputPort)) (→ Unit)
  (stress! (i64->i32 1))
  (let ((links (list->array (list (cycle) (link 11)))))
    (collect!)
    (unless (= (read-cycle (array-ref links 0)) 42) (panic "lost a cycle through an array"))
    (unless (= (earlier (cycle) (link 7)) 49) (panic "lost an earlier operand")))
  (unless (= (with-prompt question paused (lambda (n resume) (collect!) (resume n))) 43)
    (panic "lost a suspended frame"))
  (stress! (i64->i32 0))
  (unless (reclaimed? park-receiver)
    (panic "unreachable mailbox waiters retained their schedulers"))
  (unless (reclaimed? abandon-caches) (panic "unreachable caches retained their entries"))
  (profile! (i64->i32 1))
  (let ((slot (ref-local 0)))
    (bump! 100000 (ref! slot))
    (unless (= (ref-get slot) 100000) (panic "lost a tail-forwarded ref")))
  (unless (= (allocations) 0) (panic "a scoped scalar allocated in the shared heap"))
  (profile! (i64->i32 0))
  (write-line out "shared cycles, operands and frames survive collection")
  (write-line out "abandoned mailbox and scheduler cycles are reclaimed")
  (write-line out "abandoned memoizer entry cycles are reclaimed")
  (write-line out "scoped calls allocate zero objects"))
