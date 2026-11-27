;; Measure intervals between camera frames submitted to the surface. Simulation
;; ticks and browser callbacks can both keep running while the picture stalls.
(define-library (snail shell game display)
  (export GameDisplay game-display display-frame! presented! interrupt-display! meter-view
          DisplayChange ShowMeter RefreshDivisor display-settings change-display!)
  (import
   (snail core base)
   (only (snail core io) Clock)
   (only (snail shell page) PageStorage)
   (only (snail shell dom) Checked Value Allow Chords Chord)
   (prefix (snail shell ui) ui:))
  (begin
    (record GameDisplay
      ((clock Clock)
       (storage PageStorage)
       (visible Bool)
       (divisor I32)
       (remaining I32)
       (elapsed I64)
       (entry String)
       (last I64)
       (report I64)
       (frames I64)
       (peaks (Array I64))
       (reading String)
       (graph String)))
    (define (game-display (clock Clock) (storage PageStorage)) (→ GameDisplay)
      (let ((divisor (max 1 ((● storage read-setting) "refresh-divisor" 1))))
        (new GameDisplay (clock clock) (storage storage)
             (visible (= 1 ((● storage read-setting) "frame-meter" 1)))
             (divisor divisor) (remaining 0) (elapsed 0) (entry (show divisor))
             (last -1) (report 0) (frames 0) (peaks (make-array 32 0))
             (reading "— FPS") (graph ""))))

    ;; ---- Display refresh ----

    ;; Physics still receives each host tick. The camera receives all the time
    ;; since its last draw, including the callbacks that this divisor skipped.
    (define (interrupt-display! (d GameDisplay)) (→ Unit)
      (set! (● d last) -1) (set! (● d remaining) 0) (set! (● d elapsed) 0))
    (define (display-frame! (d GameDisplay) (ms I32) (paused Bool) (redraw Bool)) (→ (Option I32))
      (let ((elapsed (min 2147483647 (+ (● d elapsed) (i32->i64 ms)))))
        (cond (paused (interrupt-display! d) (if redraw (Some ms) (None)))
              ((and (not redraw) (> (● d remaining) 0))
               (set! (● d remaining) (- (● d remaining) 1)) (set! (● d elapsed) elapsed) (None))
              (else (set! (● d remaining) (- (● d divisor) 1)) (set! (● d elapsed) 0)
                    (Some (i64->i32 elapsed))))))

    ;; ---- Pause settings ----

    (enum DisplayChange (ShowMeter ((on Bool))) (RefreshDivisor ((text String))))
    (define (positive-divisor (text String)) (→ (Option I32))
      (match (string->i64 text)
        ((Some n) (if (and (> n 0) (<= n 2147483647)) (Some (i64->i32 n)) (None)))
        (_ (None))))
    (define (change-display! (d GameDisplay) (change DisplayChange)) (→ Unit)
      (match change
        ((ShowMeter on)
         (set! (● d visible) on) (set! (● d last) -1)
         ((● d storage write-setting) "frame-meter" (if on 1 0)))
        ((RefreshDivisor text)
         (set! (● d entry) text)
         (match (positive-divisor text)
           ((Some n) (set! (● d divisor) n) (set! (● d remaining) 0)
            ((● d storage write-setting) "refresh-divisor" n))
           (_ (unit))))))
    (define (setting (name String) (attrs (List (ui:Attribute M)))) (→ (ui:Html M)) (∀ (M))
      (ui:Element "label" (list (ui:Attr "class" "setting display-setting"))
                  (list (ui:Element "span" (Nil) (list (ui:Text name)))
                        (ui:Element "input" attrs (Nil)))))
    (define (display-settings (d GameDisplay) (message (Fn DisplayChange → M)) (resume M))
      (→ (List (ui:Html M)))
      (∀ (M))
      (let ((dismiss (ui:On "keydown" (Nil)
                            (Chords (list (new Chord (key "Escape") (modifiers 0))
                                          (new Chord (key "p") (modifiers 0))))
                            (lambda (_) resume)))
            (toggle (ui:On "change"
                           (list (Checked))
                           (Allow)
                           (lambda (e) (message (ShowMeter (● e checked))))))
            (divide (ui:On "input"
                           (list (Value))
                           (Allow)
                           (lambda (e) (message (RefreshDivisor (● e value))))))
            (invalid (match (positive-divisor (● d entry)) ((Some _) "false") (_ "true"))))
        (list (setting "FPS and frame times"
                       (list (ui:Attr "class" "show-frame-meter") (ui:Attr "type" "checkbox")
                             (ui:FlagProperty "checked" (● d visible)) toggle dismiss))
              (setting "Refresh divisor (1 = full)"
                       (list (ui:Attr "class" "refresh-divisor") (ui:Attr "type" "text")
                             (ui:Attr "inputmode" "numeric") (ui:Attr "aria-invalid" invalid)
                             (ui:Attr "title"
                                      "Draw every Nth display refresh. Enter a positive whole number.")
                             (ui:StringProperty "value" (● d entry)) divide dismiss)))))

    ;; ---- Frame times ----

    ;; Each four-pixel column keeps the worst interval in a quarter second.
    ;; The vertical scale stays fixed at 100 ms. The readout retains the full peak.
    (define (graph-column (i I64) (us I64)) (→ String)
      (let ((y (string-append (show (- 100 (min 100 (quotient (+ us 500) 1000)))) "%")))
        (string-append (show (* i 4)) "px " y "," (show (* (+ i 1) 4)) "px " y)))
    (define (report! (m GameDisplay) (now I64) (bucket I64)) (→ Unit)
      (let* ((peaks (● m peaks))
             (peak (array-fold (lambda (a b) (max a b)) 0 peaks))
             (duration (- now (● m report)))
             (fps (quotient (+ (* (● m frames) 1000000) (quotient duration 2)) duration))
             (columns
              (map (lambda (i) (graph-column i (array-ref peaks (modulo (+ (+ bucket 1) i) 32))))
                   (iota 32))))
        (set! (● m reading)
              (string-append (show fps) " FPS · " (show (quotient (+ peak 500) 1000)) " ms max"))
        (set! (● m graph)
              (string-append "clip-path:polygon(0 100%," (string-join columns ",") ",100% 100%)"))
        (set! (● m report) now) (set! (● m frames) 0)))
    (define (clear-buckets! (peaks (Array I64)) (bucket I64) (count I64)) (→ Unit)
      (let loop ((n count))
        (when (> n 0)
          (array-set! peaks (modulo (- (+ bucket 1) n) 32) 0) (loop (- n 1)))))
    (define (presented! (m GameDisplay)) (→ Unit)
      (when (● m visible)
        (let* ((now (quotient ((● m clock monotonic-nanoseconds)) 1000)) (last (● m last))
               (bucket (quotient now 250000)) (slot (modulo bucket 32)) (peaks (● m peaks)))
          (set! (● m last) now)
          (if (< last 0)
              (begin (set! (● m report) now) (set! (● m frames) 0) (clear-buckets! peaks bucket 32))
              (let ((gap (- now last)))
                (clear-buckets! peaks bucket (min 32 (- bucket (quotient last 250000))))
                (array-set! peaks slot (max gap (array-ref peaks slot)))
                (set! (● m frames) (+ 1 (● m frames)))
                (when (>= (- now (● m report)) 250000) (report! m now bucket)))))))
    (define (meter-view (m GameDisplay)) (→ (ui:Html M)) (∀ (M))
      (ui:Element "aside"
                  (list (ui:Attr "class" "frame-meter")
                        (ui:FlagProperty "hidden" (not (● m visible)))
                        (ui:Attr "aria-label" "Frame pacing")
                        (ui:Attr "title"
                                 "Peak frame time in each quarter second over the last 8 seconds. The guide marks 16.7 ms."))
                  (list (ui:Text (● m reading))
                        (ui:Element "span"
                                    (list (ui:Attr "class" "frame-plot")
                                          (ui:Attr "aria-hidden" "true"))
                                    (list (ui:Element "i"
                                                      (list (ui:Attr "style" (● m graph)))
                                                      (Nil)))))))))
