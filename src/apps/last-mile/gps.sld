(define-library (apps last-mile gps)
  (export Gps
          new-gps
          navigate!
          guidance
          gps-distance
          route-ink
          map-pin
          map-window
          chart-placement
          chart-source)
  (import
   (snail core base)
   (snail shell base64)
   (only (snail shell utf8) string->utf8)
   (snail shell game physics)
   (snail shell game roads)
   (snail shell game atlas))
  (begin
    (record Gps
      ((goal XZ)
       (path (List I64))
       (revision I64)
       (last-tick I64)))
    (define (new-gps)
      (→ Gps)
      (new Gps (goal (xz 1e30 1e30)) (path (Nil)) (revision 0) (last-tick -50)))
    (define (projection (p XZ) (u XZ) (v XZ)) (→ XZ)
      (let ((t (edge-fraction p u v)))
        (xz (+ (● u x) (* t (- (● v x) (● u x)))) (+ (● u z) (* t (- (● v z) (● u z)))))))
    (define (remaining (r Roads) (p XZ) (path (List I64))) (→ (Pair F64 (List I64)))
      (let loop ((rest path) (best 1e30) (out path))
        (match rest
          ((Cons a (Cons b bs)) (let ((d (distance p (projection p (node-at r a) (node-at r b)))))
                                  (if (< d best)
                                      (loop (Cons b bs) d rest)
                                      (loop (Cons b bs) best out))))
          (_ (new Pair (first best) (second out))))))
    (define (navigate! (gps Gps) (r Roads) (p XZ) (goal XZ) (tick I64)) (→ Unit)
      (let ((changed (> (distance goal (● gps goal)) 0.5)))
        (when (or changed (< tick (● gps last-tick)) (>= (- tick (● gps last-tick)) 16))
          (let ((near (remaining r p (● gps path))))
            (cond ((or changed (and (> (● near first) 32.0) (> (distance p goal) 28.0)))
                   (set! (● gps path) (road-route r (nearest-road r p) (nearest-road r goal)))
                   (set! (● gps goal) goal) (set! (● gps revision) (+ 1 (● gps revision))))
                  (else (set! (● gps path) (● near second)))))
          (set! (● gps last-tick) tick))))
    (define (gps-distance (gps Gps) (r Roads) (p XZ)) (→ F64)
      (let ((straight (distance p (● gps goal))))
        (match (● gps path) ((Cons a (Cons b bs))
                             (if (< straight 28.0)
                                 straight
                                 (+ (distance (projection p (node-at r a) (node-at r b))
                                              (node-at r b))
                                    (route-length r (Cons b bs)))))
               (_ straight))))
    (define (guidance (gps Gps) (r Roads) (p XZ)) (→ String)
      (cond ((< (distance p (● gps goal)) 28.0) "Pull up to the marked curb")
            ((null? (● gps path)) "No connected road found")
            (else (next-turn r (● gps path) p))))
    (define (coordinate (a Atlas) (p XZ)) (→ String)
      (string-append (show (- (f64->i64 (● p x)) (● a west)))
                     ","
                     (show (- (f64->i64 (● p z)) (● a north)))))
    (define (chart-box (g Area) (wide Bool)) (→ String)
      (let* ((a (● g atlas)) (side (● a side)) (id (● g center)) (width (show (* 3 side))))
        (if wide (string-append "0 0 " (show (* side (● a cols))) " " (show (* side (● a rows))))
            (string-append (show (* side (- (modulo id (● a cols)) 1))) " "
                           (show (* side (- (quotient id (● a cols)) 1))) " " width " " width))))
    (define (chart-placement (g Area)) (→ String)
      (let* ((a (● g atlas))
             (cols (i64->f64 (● a cols)))
             (rows (i64->f64 (● a rows)))
             (id (● g center)))
        (string-append "left:" (pc (/ (* 100.0 (i64->f64 (- (modulo id (● a cols)) 1))) cols))
                       ";top:" (pc (/ (* 100.0 (i64->f64 (- (quotient id (● a cols)) 1))) rows))
                       ";width:" (pc (/ 300.0 cols)) ";height:" (pc (/ 300.0 rows)) ";")))
    ;; Draw all names last so a neighbouring tile cannot paint over half a street name.
    (define (chart-label (s Sector)) (→ String)
      (string-append "<use href='#street-" (show (● s id)) "'/>"))
    (define (chart-source (g Area)) (→ String)
      (let ((size (show (* 3 (● g atlas side)))))
        (data-url "image/svg+xml"
                  (string->utf8
                   (string-append "<svg xmlns='http://www.w3.org/2000/svg' width='"
                                  size
                                  "' height='"
                                  size
                                  "' viewBox='"
                                  (chart-box g #f)
                                  "'>"
                                  (string-join (map (lambda (s) (● s chart)) (● g sectors)) "")
                                  (string-join (map chart-label (● g sectors)) "")
                                  "</svg>")))))
    (define (route-ink (g Area) (r Roads) (gps Gps) (wide Bool)) (→ String)
      (let* ((a (● g atlas)) (coords (map (lambda (n) (coordinate a (node-at r n))) (● gps path)))
             (line (string-join (append coords (list (coordinate a (● gps goal)))) " ")))
        (string-append (if wide "" (chart-placement g))
                       "background-image:url(\"data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='"
                       (chart-box g wide)
                       "' preserveAspectRatio='none'%3E%3Cpolyline fill='none' stroke='%23412d19' stroke-linecap='round' stroke-linejoin='round' stroke-width='"
                       (if wide "65" "9")
                       "' points='"
                       line
                       "'/%3E%3Cpolyline fill='none' stroke='%23ffcc48' stroke-linecap='round' stroke-linejoin='round' stroke-width='"
                       (if wide "40" "5.5") "' points='" line "'/%3E%3C/svg%3E\")")))
    (define (pc (v F64)) (→ String) (string-append (show v) "%"))
    (define (map-pin (a Atlas) (p XZ)) (→ String)
      (string-append "left:"
                     (pc (/ (* 100.0 (- (● p x) (i64->f64 (● a west))))
                            (i64->f64 (* (● a cols) (● a side)))))
                     ";top:"
                     (pc (/ (* 100.0 (- (● p z) (i64->f64 (● a north))))
                            (i64->f64 (* (● a rows) (● a side)))))))
    (define (map-window (a Atlas) (p XZ) (wide Bool)) (→ String)
      (if wide "inset:0;width:100%;height:100%"
          (string-append "width:" (pc (/ (i64->f64 (* (● a cols) (● a side))) 3.9))
                         ";height:" (pc (/ (i64->f64 (* (● a rows) (● a side))) 2.6))
                         ";left:" (pc (- 50.0 (/ (- (● p x) (i64->f64 (● a west))) 3.9)))
                         ";top:" (pc (- 50.0 (/ (- (● p z) (i64->f64 (● a north))) 2.6))))))))
