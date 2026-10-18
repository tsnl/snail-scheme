(define-library (tutorial board)
  (export application-entry)
  (import
   (scheme base)
   (scheme immutable)
   (application reducer)
   (application bridge)
   (application serialization)
   (lofi serialization)
   (browser application)
   (only (lofi core) ann -> I32 deriving)
   (only (lofi base) string-append unreachable))
  (begin

    ;; ---- One shared marker and one cursor per browser ----

    (define-immutable-record Cell cell
      (x I32 cell-x cell-x-set)
      (y I32 cell-y cell-y-set)
      (deriving derive-serialize derive-deserialize))
    (define (inside? x y) (and (>= x 0) (< x 8) (>= y 0) (< y 6)))
    (define (move-cell previous x y) (if (inside? x y) (cell x y) previous))
    (define (validate-cell value)
      (unless (inside? (cell-x value) (cell-y value)) (unreachable))
      value)

    ;; ---- Authority commands and local input ----

    (application board-app (state Cell 1) (cell 0 0)
                 (place (state (x I32) (y I32)) (no-effects (move-cell state x y)))
                 ;; This board has no simulation clock, but the host requires a tick endpoint.
                 (idle (state) (no-effects state))
                 (clear (state) (no-effects (cell 0 0))))
    (define board-target (destination match-owner board-app))
    (application cursor-app (state Cell 1) (cell 0 0)
                 (move (state (x I32) (y I32)) (no-effects (move-cell state x y)))
                 (confirm (state)
                          (transition state (list (enqueue board-target (place (cell-x state) (cell-y state))))))
                 (restart (state) (transition state (list (enqueue board-target (clear))))))

    ;; ---- Presentation in logical pixels ----

    (define marker-color (ann 16753920 I32))
    (define (tile value color opacity)
      (quad (+ (* (cell-x value) 40) 2) (+ (* (cell-y value) 40) 2) 36 36 color opacity))
    (define (view board cursor)
      (list (quad 0 0 320 240 1055781 255)
            (tile board marker-color 255)
            (tile cursor 16777215 90)))
    (define (position-text value)
      (string-append (integer-text (cell-x value)) (string-append "," (integer-text (cell-y value)))))
    (define (status board cursor)
      (string-append "Marker " (string-append (position-text board)
                                              (string-append " | Cursor " (position-text cursor)))))

    ;; ---- Typed snapshots and the host entry ----

    (define board-program
      (serialized-program board-app cursor-app validate-cell validate-cell view status))
    (define application-entry
      (ann (lambda (operation a b c) (run-program board-program operation a b c))
           (-> I32 I32 I32 I32 I32)))))
