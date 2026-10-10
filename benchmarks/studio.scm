;; Deterministic studio ray tracer. Arguments: output.ppm width sample-grid.
(import (scheme base) (scheme cxr) (scheme inexact) (scheme file) (scheme write) (scheme process-context))

;; ---- Vectors and materials ----

(define (v+ a b)
  (vector (+ (vector-ref a 0) (vector-ref b 0))
          (+ (vector-ref a 1) (vector-ref b 1))
          (+ (vector-ref a 2) (vector-ref b 2))))

(define (scale k a)
  (vector (* k (vector-ref a 0)) (* k (vector-ref a 1)) (* k (vector-ref a 2))))

(define (v- a b) (v+ a (scale -1.0 b)))

(define (dot a b)
  (+ (* (vector-ref a 0) (vector-ref b 0))
     (* (vector-ref a 1) (vector-ref b 1))
     (* (vector-ref a 2) (vector-ref b 2))))

(define (unit a) (scale (/ 1.0 (sqrt (dot a a))) a))

(define (cross a b)
  (vector (- (* (vector-ref a 1) (vector-ref b 2)) (* (vector-ref a 2) (vector-ref b 1)))
          (- (* (vector-ref a 2) (vector-ref b 0)) (* (vector-ref a 0) (vector-ref b 2)))
          (- (* (vector-ref a 0) (vector-ref b 1)) (* (vector-ref a 1) (vector-ref b 0)))))

(define (mix amount a b) (v+ (scale (- 1.0 amount) a) (scale amount b)))
(define black (vector 0.0 0.0 0.0))
(define white (vector 1.0 1.0 1.0))
(define epsilon 0.0001)

;; A surface stores center, radius, linear RGB, and reflectivity. The floor's
;; center is #f. Geometry and materials are fixed for every render size.
(define floor-surface (vector #f 0.0 (vector 0.72 0.74 0.77) 0.025))
(define surfaces
  (list (vector (vector -0.7 1.25 0.0) 1.25 (vector 0.95 0.25 0.01) 0.10)
        (vector (vector 1.6 1.0 -0.65) 1.0 (vector 0.018 0.26 0.29) 0.18)
        (vector (vector -2.2 0.52 1.2) 0.52 (vector 0.065 0.13 0.24) 0.35)
        (vector (vector 0.85 0.46 1.65) 0.46 (vector 0.92 0.84 0.68) 0.16)
        (vector (vector -3.0 0.65 -1.4) 0.65 (vector 0.8 0.84 0.88) 0.88)
        (vector (vector 2.65 0.3 0.85) 0.3 (vector 0.7 0.32 0.07) 0.32)
        floor-surface))

;; A fixed Hammersley sequence covers the area light without aligned shadow
;; bands or random seeds. Reversing binary digits gives the second coordinate.
(define (radical-inverse n)
  (let loop ((n n) (weight 0.5) (sum 0.0))
    (if (= n 0) sum
        (loop (quotient n 2) (* weight 0.5) (+ sum (* weight (modulo n 2)))))))

(define lights
  (let loop ((i 0) (result '()))
    (if (= i 64) result
        (loop (+ i 1)
              (cons (vector (+ -3.5 (* 3.2 (- (/ (+ i 0.5) 64) 0.5)))
                            7.0 (+ 4.0 (* 2.4 (- (radical-inverse i) 0.5))))
                    result)))))

;; ---- Positive intersections ----

;; All ray directions are unit vectors: intersection t is world distance.
;; Both sphere roots matter for rays starting inside a sphere. Secondary rays
;; start just outside their surface, so they cannot immediately hit it again.
(define (sphere-distance origin direction surface)
  (let* ((offset (v- origin (vector-ref surface 0)))
         (b (dot offset direction))
         (radius (vector-ref surface 1))
         (d (- (* b b) (- (dot offset offset) (* radius radius)))))
    (and (>= d 0.0)
         (let* ((root (sqrt d)) (near (- (- b) root)) (far (+ (- b) root)))
           (cond ((> near epsilon) near) ((> far epsilon) far) (else #f))))))

(define (distance-to origin direction surface)
  (if (eq? surface floor-surface)
      (let ((dy (vector-ref direction 1)))
        (and (< dy (- epsilon))
             (let ((t (/ (- (vector-ref origin 1)) dy))) (and (> t epsilon) t))))
      (sphere-distance origin direction surface)))

(define (nearest origin direction)
  (let loop ((remaining surfaces) (hit #f) (closest 1e30))
    (if (null? remaining) hit
        (let ((t (distance-to origin direction (car remaining))))
          (if (and t (< t closest))
              (loop (cdr remaining) (cons t (car remaining)) t)
              (loop (cdr remaining) hit closest))))))

(define (normal-at point surface)
  (if (eq? surface floor-surface) (vector 0.0 1.0 0.0)
      (unit (v- point (vector-ref surface 0)))))

;; ---- Illumination and bounded reflections ----

(define (sky-color direction)
  (let ((height (max 0.0 (min 1.0 (* 0.5 (+ 1.0 (vector-ref direction 1)))))))
    (mix height (vector 0.92 0.91 0.87) (vector 0.48 0.61 0.76))))

(define (light-contribution point normal view surface light)
  (let* ((toward (v- light point)) (distance (sqrt (dot toward toward)))
         (direction (scale (/ 1.0 distance) toward))
         (blocker (nearest point direction)))
    (if (or (<= (dot normal direction) 0.0)
            (and blocker (< (car blocker) distance))) black
            (let* ((diffuse (* 0.78 (max 0.0 (dot normal direction))))
                   (halfway (unit (v+ direction view)))
                   (specular (* 0.48 (expt (max 0.0 (dot normal halfway)) 64))))
              (v+ (scale diffuse (vector-ref surface 2)) (scale specular white))))))

(define (illuminate point normal view surface)
  (let loop ((remaining lights) (color black))
    (if (null? remaining)
        (v+ (scale (if (eq? surface floor-surface) 0.4 0.2) (vector-ref surface 2)) (scale (/ 1.0 (length lights)) color))
        (loop (cdr remaining)
              (v+ color (light-contribution point normal view surface (car remaining)))))))

(define (shade origin direction hit depth)
  (let* ((surface (cdr hit)) (point (v+ origin (scale (car hit) direction)))
         (normal (normal-at point surface)) (start (v+ point (scale epsilon normal)))
         (local (illuminate start normal (scale -1.0 direction) surface)))
    (if (= depth 0) local
        (let ((reflected (unit (v- direction (scale (* 2.0 (dot direction normal)) normal)))))
          (mix (vector-ref surface 3) local (trace-ray start reflected (- depth 1)))))))

(define (trace-ray origin direction depth)
  (let ((hit (nearest origin direction)))
    (if hit (shade origin direction hit depth) (sky-color direction))))

;; ---- Camera and deterministic anti-aliasing ----

(define camera (vector 6.5 4.2 9.0))
(define forward (unit (v- (vector 0.0 0.9 0.0) camera)))
(define right (unit (cross forward (vector 0.0 1.0 0.0))))
(define up (cross right forward))

(define (camera-ray x y width height)
  (unit (v+ forward
            (v+ (scale (* 0.49 (/ width height) (- (/ x width) 0.5)) right)
                (scale (* 0.49 (- 0.5 (/ y height))) up)))))

(define (pixel x y width height grid)
  (let loop ((i 0) (color black))
    (if (= i (* grid grid)) (scale (/ 1.0 (* grid grid)) color)
        (let* ((sx (+ x (/ (+ 0.5 (modulo i grid)) grid)))
               (sy (+ y (/ (+ 0.5 (quotient i grid)) grid)))
               (ray (camera-ray sx sy width height)))
          (loop (+ i 1) (v+ color (trace-ray camera ray 2)))))))

(define (channel value)
  ;; Gamma 2 transfer is deterministic; clamp before integer quantization.
  (exact (floor (+ 0.5 (* 255.0 (sqrt (max 0.0 (min 1.0 value))))))))

(define (write-pixel color port)
  (write (channel (vector-ref color 0)) port) (display " " port)
  (write (channel (vector-ref color 1)) port) (display " " port)
  (write (channel (vector-ref color 2)) port) (newline port))

(define (render path width grid)
  (let ((height (quotient (* width 3) 5)))
    (call-with-output-file path
      (lambda (port)
        (display "P3\n" port) (write width port) (display " " port)
        (write height port) (display "\n255\n" port)
        (do ((y 0 (+ y 1))) ((= y height))
          (do ((x 0 (+ x 1))) ((= x width))
            (write-pixel (pixel x y width height grid) port)))))))

;; ---- Command line ----

(let* ((args (cdr (command-line)))
       (path (if (pair? args) (car args) "studio.ppm"))
       (width (if (> (length args) 1) (string->number (cadr args)) 800))
       (grid (if (> (length args) 2) (string->number (caddr args)) 2)))
  (if (not (and (exact-integer? width) (>= width 5)
                (exact-integer? grid) (> grid 0)))
      (error "studio" "expected width >= 5 and sample grid >= 1"))
  (render path width grid))
