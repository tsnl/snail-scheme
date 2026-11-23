;; Fit, render and inspect a small Radiant Foam on the CPU.
;; ./snail-scheme run --target node src/apps/foam/main.scm
(import
 (snail core base)
 (snail core io)
 (snail core table)
 (snail shell wire)
 (snail shell random)
 (only (snail shell png) rgba->png)
 (only (snail shell gpu) host-gpu)
 (only (snail shell json) JsonNumber JsonInteger)
 (only (snail shell json read) string->json)
 (snail shell graphics radiant-foam)
 (only (apps train dataset) settings-of setting)
 (apps foam views))

;; ---- Fitting and rendering ----

(define (batch (samples (Array Sample)) (seed I64)) (→ (List Sample))
  (let loop ((left 96) (rng (make-random seed)) (rays (Nil)))
    (if (= left 0) rays
        (loop (- left 1) (random-next rng)
              (Cons (array-ref samples (random-below rng (array-length samples))) rays)))))

(define (fit (initial Foam) (samples (Array Sample)) (steps I64)) (→ Foam)
  (let loop ((i 0) (foam initial))
    (if (= i steps) foam
        (loop (+ i 1) (fit-step foam (batch samples i) 1.0)))))

(define (draw (foam Foam) (view View)) (→ (Array Vec3d))
  (array-map (lambda (s) (render-ray foam (● s ray))) (● view samples)))

(define (mse (drawn (Array Vec3d)) (view View)) (→ F64)
  (let loop ((i 0) (total 0.0))
    (if (= i (array-length drawn)) (/ total (* 3.0 (i64->f64 i)))
        (let ((error (v- (array-ref drawn i) (● (array-ref (● view samples) i) rgb))))
          (loop (+ i 1) (+ total (dot error error)))))))

(define (image-bytes (view View) (rgb (Array Vec3d))) (→ Bytes)
  (let* ((byte (lambda (v) (i32->u8 (f64->i32 (round (* 255.0 (max 0.0 (min 1.0 v))))))))
         (pixels (array-generate (* 4 (array-length rgb))
                                 (lambda (i)
                                   (let ((p (array-ref rgb (quotient i 4))))
                                     (case (remainder i 4)
                                       ((0) (byte (● p x))) ((1) (byte (● p y)))
                                       ((2) (byte (● p z))) (else (i32->u8 255))))))))
    (rgba->png (i64->i32 (● view width)) (i64->i32 (● view height)) pixels)))

;; ---- The threshold surface ----

;; Several cells compute each corner. Weld roundoff in normalized
;; coordinates, then write the shared corner at full world precision.
(define (vertex-key (p Vec3d)) (→ String)
  (let ((key (lambda (x) (show (f64->i64 (round (* 1e9 x)))))))
    (string-join (map key (list (● p x) (● p y) (● p z))) " ")))

(define (vertex-line (model Model) (p Vec3d)) (→ String)
  (let ((w (v+ (● model center) (v* p (● model radius)))))
    (string-append "v " (string-join (map f64->string (list (● w x) (● w y) (● w z))) " "))))

(define (triangles (indices (List I64))) (→ (List String))
  (match indices
    ((Cons a (Cons b rest))
     (let loop ((b b) (rest rest) (lines (Nil)))
       (match rest
         ((Nil) (reverse lines))
         ((Cons c tail)
          (loop c tail (if (or (= a b) (= a c) (= b c)) lines
                           (Cons (string-append "f " (show a) " " (show b) " " (show c))
                                 lines)))))))
    (_ (Nil))))

(define (surface-obj (model Model) (faces (List (List Vec3d))) (threshold F64)) (→ String)
  (let* ((points (table-values (fold-left (lambda (t p) (table-set t (vertex-key p) p))
                                          (empty-table) (concatenate faces))))
         (ids (fold-left
               (lambda (t pair) (table-set t (vertex-key (● pair second)) (+ (● pair first) 1)))
               (empty-table) (zip (iota (length points)) points)))
         (index (lambda (p) (match (table-ref ids (vertex-key p))
                              ((Some i) i) ((None) (panic "missing face vertex")))))
         (facets (concatenate (map (lambda (face) (triangles (map index face))) faces))))
    (string-append "# Voronoi interfaces at density " (f64->string threshold) " per model unit\n"
                   (string-join (append (map (lambda (p) (vertex-line model p)) points) facets)
                                "\n")
                   "\n")))

;; ---- The run ----

(define (option (query String) (key String) (fallback String)) (→ String)
  (match (setting query key) ((Some value) value) ((None) fallback)))

(define (count-option (query String) (key String) (fallback String)) (→ I64)
  (match (string->i64 (option query key fallback))
    ((Some n) (if (>= n 0) n (panic (string-append key " must be nonnegative"))))
    ((None) (panic (string-append key " needs a whole number")))))

(define (density-option (query String)) (→ F64)
  (match (string->json (option query "threshold" "1.0"))
    ((Some (JsonInteger n)) (i64->f64 n))
    ((Some (JsonNumber n)) n)
    (_ (panic "threshold needs a number"))))

(define (run (fs Fs)
             (out OutputPort)
             (directory String)
             (experiment Experiment)
             (steps I64)
             (level F64))
  (→ Unit)
  (let* ((path (lambda (name) (string-append directory "/" name)))
         (view (● experiment held)) (model (● experiment initial))
         (initial (make-foam (● model sites))) (before (draw initial view))
         (trained (fit initial (● experiment training) steps)) (after (draw trained view))
         (faces (density-faces trained level)))
    (write-bytes fs (path "model.foam") (serialize (new Model
                                                     (center (● model center))
                                                     (radius (● model radius))
                                                     (sites (array->list trained)))))
    (write-file fs (path "surface.obj") (surface-obj model faces level))
    (write-bytes fs
                 (path "target.png")
                 (image-bytes view (array-map (lambda (s) (● s rgb)) (● view samples))))
    (write-bytes fs (path "before.png") (image-bytes view before))
    (write-bytes fs (path "render.png") (image-bytes view after))
    (write-line out (string-append (show (array-length trained)) " sites, " (show steps)
                                   " steps, held-out " (● view name) " " (show (● view width)) "x"
                                   (show (● view height))
                                   ", RGB MSE "
                                   (f64->string (mse before view))
                                   " -> " (f64->string (mse after view))))
    (write-line out
                (string-append (show (length faces)) " density interfaces at " (f64->string level)
                               " written to " (path "surface.obj")))))

(define (main (host Host) (arguments Arguments) (fs Fs) (out OutputPort)) (→ Unit)
  (let* ((query (string-append "?" (string-join (list-tail (command-line arguments) 1) "&")))
         (saved (match (setting query "load")
                  ((Some path) (Some (ann (deserialize (read-bytes fs path)) Model)))
                  ((None) (None))))
         (steps (count-option query "steps" (match saved ((Some _) "0") ((None) "500"))))
         (index (count-option query "view" "0")) (directory (option query "out" "build/foam"))
         (level (density-option query)))
    (match (make-directories fs directory)
      ((Err _) (panic (string-append "cannot create " directory))) ((Ok _) (unit)))
    (let ((experiment (match (setting query "scene")
                        ((None) (demo-experiment saved (> steps 0) index))
                        ((Some _)
                         (let ((gpu (host-gpu host)))
                           ((● gpu request-device))
                           (photo-experiment gpu (lambda (p) (read-bytes fs p))
                                             (settings-of query) saved (> steps 0) index))))))
      (run fs out directory experiment steps level))))
