;; An elitist evolution strategy. Rank closed-loop policies on identical
;; physical trials. Only parameter vectors and scores survive a generation.
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (snail shell math)
 (snail shell random)
 (snail shell resource)
 (only (snail shell tensor) View param Float Unsigned gather)
 (snail shell tensor eval)
 (snail shell game biped)
 (only (snail shell game terrain) Terrain)
 (apps iygtw walk)
 (apps iygtw walking reference))

;; ---- Episodes ----

(record Trial
  ((ground (Array F64))
   (name String)
   (first F64)
   (second F64)
   (phase F64)))

(record ResultOfWalk
  ((score F64)
   (ticks I64)
   (distance F64)
   (halfway F64)
   (speed-error F64)
   (joint-rms F64)))

(define (rollout (clip Stride) (w (Array F64)) (trial Trial) (limit I64)) (→ ResultOfWalk)
  (let ((g (● trial ground)))
    (reset-walk! g clip (● trial phase))
    (let loop ((tick 0)
               (phase (● trial phase))
               (score 0.0)
               (error 0.0)
               (pose-error 0.0)
               (halfway 0.0))
      (if (or (= tick limit) (fallen? g))
          (let ((x (link-x 0)) (n (i64->f64 limit)) (mid (quotient limit 2)))
            (end-biped!)
            ;; A fallen walker covers no more distance. Its remaining commanded
            ;; speed counts in MAE, and its remaining score is zero.
            (new ResultOfWalk
              (score (/ score n))
              (ticks tick)
              (distance x)
              (halfway (if (<= tick mid) x halfway))
              (speed-error (/ (+ error (+ (* (i64->f64 (max 0 (- mid tick))) (● trial first))
                                          (* (i64->f64 (- limit (max mid tick))) (● trial second))))
                              n))
              (joint-rms (sqrt (/ pose-error (i64->f64 (max 1 tick)))))))
          (let* ((command (if (< tick (quotient limit 2)) (● trial first) (● trial second)))
                 (p (next-phase clip phase command)) (pose (reference-pose clip p)))
            (step-walk! w pose command g)
            (let ((d (- (forward-speed) command)) (e (joint-error pose)))
              (loop (+ tick 1)
                    p
                    (+ score (walk-reward d e))
                    (+ error (abs d))
                    (+ pose-error e)
                    (if (= (+ tick 1) (quotient limit 2)) (link-x 0) halfway))))))))

;; ---- Search ----

(define offspring (→ I64) 32)
(define survivors (→ I64) 6)
(define (uniform (r Random)) (→ F64) (/ (+ 0.5 (i64->f64 (random-below r 16777216))) 16777216.0))
(define (normal (r Random)) (→ F64)
  (* (sqrt (* -2.0 (log (uniform r)))) (cos (* (* 2.0 pi) (uniform (random-next r))))))

(record Candidate
  ((weights (Array F64))
   (score F64)))

;; Rows are children, columns are feedback gains. A child inherits a parent
;; row, then gets Gaussian noise scaled by gain units and a per-child radius.
(define (population-graph) (→ View)
  (let ((parents (param "parents" (list survivors policy-size) (Float)))
        (ids (param "ids" (list offspring) (Unsigned)))
        (noise (param "noise" (list offspring policy-size) (Float)))
        (units (param "units" (list policy-size) (Float)))
        (radius (param "radius" (list offspring 1) (Float))))
    (+ (gather parents ids) (* noise (* units radius)))))

(define (children (graph View) (parents (List Candidate)) (seed I64)) (→ (Array F64))
  (define (rng (i I64)) (→ Random) (make-random (+ seed i)))
  (let* ((rows (array-concatenate (map (lambda (p) (● p weights)) parents)))
         (ids (array-generate offspring (lambda (i) (i64->f64 (random-below (rng i) survivors)))))
         (radius (array-generate offspring (lambda (i) (let ((u (uniform (rng (+ offspring i)))))
                                                         (+ 0.035 (* 1.2 (* u (* u u))))))))
         (noise (array-generate (* offspring policy-size)
                                (lambda (i) (normal (rng (+ (* 2 offspring) i))))))
         (units (list->array (list 1.5 0.4 0.7 0.6 0.8 0.6 0.65 0.9 0.3 0.45 0.85 0.5 0.8 0.3 0.4)))
         (inputs (fold-left (lambda (t kv) (table-set t (● kv first) (● kv second))) (empty-table)
                            (zip (list "parents" "ids" "radius" "noise" "units")
                                 (list rows ids radius noise units)))))
    (list-ref (evaluate (list graph) inputs) 0)))

(define (candidate (clip Stride) (w (Array F64)) (trials (List Trial))) (→ Candidate)
  (let* ((scores (map (lambda (t) (● (rollout clip w t 150) score)) trials))
         (mean (/ (fold-left + 0.0 scores) (i64->f64 (length scores)))))
    (new Candidate (weights w) (score (+ (* 0.6 mean) (* 0.4 (fold-left min 1.0 scores)))))))

(define (generation (graph View)
                    (clip Stride)
                    (parents (List Candidate))
                    (trials (List Trial))
                    (seed I64))
  (→ (List Candidate))
  (let* ((w (children graph parents seed))
         (kids (map (lambda (i) (let ((at (* i policy-size)))
                                  (candidate clip (subarray w at (+ at policy-size)) trials)))
                    (iota offspring))))
    (take (list-sort (lambda (a b) (> (● a score) (● b score))) (append parents kids)) survivors)))

(define (train (out OutputPort) (clip Stride) (trials (List Trial)) (steps I64) (seed I64))
  (→ (Array F64))
  (let* ((graph (population-graph))
         (flat
          (map (lambda (t) (Trial-second-set (Trial-ground-set t (make-array 49 0.0)) (● t first)))
               trials))
         (mild
          (map (lambda (t) (Trial-ground-set t (array-map (lambda (h) (* h 0.4)) (● t ground))))
               trials))
         (warmup (quotient steps 5))
         (transition (* 2 warmup))
         (start (candidate clip (initial-policy) flat)))
    (let loop ((step 0) (parents (map (lambda (i) start) (iota survivors))))
      (if (= step steps) (● (list-ref parents 0) weights)
          (let* ((courses (cond ((< step warmup) flat) ((< step transition) mild) (else trials)))
                 (ranked (if (or (= step warmup) (= step transition))
                             (map (lambda (p) (candidate clip (● p weights) courses)) parents)
                             parents))
                 (next (generation graph clip ranked courses (+ seed (* step 104729)))))
            (when (= (modulo (+ step 1) 4) 0)
              (write-line out (string-append "generation " (show (+ step 1)) "  selection score "
                                             (f64->string (● (list-ref next 0) score)))))
            (loop (+ step 1) next))))))

;; ---- Training and held-out courses ----

(define (course-trial (g Terrain) (route Route) (before F64) (after F64) (phase F64)) (→ Trial)
  (new Trial (ground (course g route)) (name (● route name))
       (first before) (second after) (phase phase)))

(define (training (g Terrain)) (→ (List Trial))
  (list (course-trial g lantern-row 0.80 1.15 0.0)
        (course-trial g orchard-rise 1.15 0.85 0.48)
        (course-trial g lower-fields 0.95 1.10 0.16)))

(define (held-out (g Terrain)) (→ (List Trial))
  (list (course-trial g mill-bridge 0.80 1.20 0.06)
        (course-trial g foxglove-farm 1.20 0.80 0.52)
        (course-trial g high-meadow 0.90 1.10 0.28)))

(define (report (out OutputPort) (clip Stride) (weights (Array F64)) (trial Trial)) (→ Unit)
  (let ((r (rollout clip weights trial 240)))
    (write-line out (string-join (list (● trial name) (f64->string (● trial first))
                                       (f64->string (● trial second))
                                       (show (● r ticks))
                                       (f64->string (● r distance))
                                       (f64->string (/ (● r halfway) 4.0))
                                       (f64->string (/ (- (● r distance) (● r halfway)) 4.0))
                                       (f64->string (● r speed-error))
                                       (f64->string (● r joint-rms))
                                       (f64->string (● r score)))
                                 "\t"))))

(define (integer (s String)) (→ I64)
  (match (string->i64 s) ((Some n) n) (_ (panic "expected an integer"))))
(define (run (args (List String)) (clip Stride) (g Terrain) (fs Fs) (out OutputPort)) (→ Unit)
  (let ((w (match args
             ((Cons "train" (Cons steps (Cons seed (Cons path (Nil)))))
              (let ((n (integer steps)))
                (when (<= n 0) (panic "training needs positive iterations"))
                (let ((weights (train out clip (training g) n (integer seed))))
                  (write-bytes fs path (values->bytes weights (Float))) weights)))
             ((Cons "eval" (Cons path (Nil))) (read-policy (read-bytes fs path)))
             ((Cons "baseline" (Nil)) (initial-policy))
             (_ (panic "use: train ITERATIONS SEED FILE | eval FILE | baseline")))))
    (write-line out
                "course\tfirst_m/s\tsecond_m/s\tupright_ticks/240\tdistance_m\tfirst_actual_m/s\tsecond_actual_m/s\tspeed_MAE_m/s\tjoint_RMS_rad\tscore")
    (for-each (lambda (t) (report out clip w t)) (held-out g))
    ;; Matched flat trials isolate the effect of a command from the grade.
    (for-each (lambda (v) (report out clip w (new Trial (ground (make-array 49 0.0)) (name "Flat")
                                                  (first v) (second v) (phase 0.0))))
              (list 0.8 1.2))))

(define (main (args Arguments) (resources Resources) (fs Fs) (out OutputPort)) (→ Unit)
  (let ((g (walking-ground resources)))
    (match (list-tail (command-line args) 1)
      ((Cons "--reference" (Cons path rest))
       (run rest (decode-stride (read-bytes fs path)) g fs out))
      (rest (run rest (read-stride resources) g fs out)))))
