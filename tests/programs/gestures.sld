;; What pointer events mean: pointing, a tap, a drag past eight pixels, a
;; two-finger pinch and a cancelled touch.
(import
 (snail core base)
 (snail core io)
 (snail shell app))

(define (gesture-text (gesture Gesture)) (→ String)
  (match gesture
    ((Point x y) (string-append "point " (show x) "," (show y)))
    ((Tap x y button) (string-append "tap " (show x) "," (show y) " button " (show button)))
    ((Drag dx dy) (string-append "drag " (show dx) "," (show dy)))
    ((Pinch ratio) (string-append "pinch " (show ratio)))))

;; Feeds the inputs in order and prints what each one meant.
(define (play (name String) (inputs (List Input))) (→ Unit) (! Output-port)
  (write-line (string-append name ": "
                             (string-join (● (fold-left (lambda (state input)
                                                          (match (recognize
                                                                  (● state first)
                                                                  input)
                                                            ((Pair gestures meanings)
                                                             (new Pair (first gestures)
                                                                  (second (append
                                                                           (● state second)
                                                                           (map gesture-text
                                                                                meanings)))))))
                                                        (new Pair
                                                          (first (no-gestures))
                                                          (second (Nil)))
                                                        inputs)
                                             second)
                                          "; "))))

(define (main) (→ Unit) (! Output-port)

  (play "pointing" (list (Pointer-move 1 10 10) (Pointer-move 1 12 11)))
  (play "tap" (list (Pointer-down 1 10 10 0) (Pointer-move 1 13 12) (Pointer-up 1 13 12)))
  (play "right tap" (list (Pointer-down 1 10 10 2) (Pointer-up 1 10 10)))
  (play "drag"
        (list (Pointer-down 1 10 10 0)
              (Pointer-move 1 15 10)
              (Pointer-move 1 20 10)
              (Pointer-move 1 24 13)
              (Pointer-up 1 24 13)))
  (play "pinch"
        (list (Pointer-down 1 0 0 0)
              (Pointer-down 2 100 0 0)
              (Pointer-move 2 50 0)
              (Pointer-move 1 -50 0)
              (Pointer-up 2 50 0)
              (Pointer-up 1 -50 0)))
  (play "cancel"
        (list (Pointer-down 1 10 10 0)
              (Pointer-cancel 1)
              (Pointer-up 1 10 10)
              (Pointer-move 1 11 11)))
  (play "lifting a finger from a pinch"
        (list (Pointer-down 1 0 0 0)
              (Pointer-down 2 100 0 0)
              (Pointer-up 2 100 0)
              (Pointer-move 1 40 0)
              (Pointer-up 1 40 0)))
  (play "a press that never released"
        (list (Pointer-down 1 0 0 0) (Pointer-down 1 50 50 0) (Pointer-up 1 51 50)))
  (unit))
