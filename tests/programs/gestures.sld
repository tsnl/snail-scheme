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
(define (play (out OutputPort) (name String) (inputs (List Input))) (→ Unit) (! mut)
  (write-line out (string-append name ": "
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
                                                          (first no-gestures)
                                                          (second (Nil)))
                                                        inputs)
                                             second)
                                          "; "))))

(define (main (out OutputPort)) (→ Unit) (! mut)

  (play out "pointing" (list (PointerMove 1 10 10) (PointerMove 1 12 11)))
  (play out "tap" (list (PointerDown 1 10 10 0) (PointerMove 1 13 12) (PointerUp 1 13 12)))
  (play out "right tap" (list (PointerDown 1 10 10 2) (PointerUp 1 10 10)))
  (play out "drag"
        (list (PointerDown 1 10 10 0)
              (PointerMove 1 15 10)
              (PointerMove 1 20 10)
              (PointerMove 1 24 13)
              (PointerUp 1 24 13)))
  (play out "pinch"
        (list (PointerDown 1 0 0 0)
              (PointerDown 2 100 0 0)
              (PointerMove 2 50 0)
              (PointerMove 1 -50 0)
              (PointerUp 2 50 0)
              (PointerUp 1 -50 0)))
  (play out "cancel"
        (list (PointerDown 1 10 10 0)
              (PointerCancel 1)
              (PointerUp 1 10 10)
              (PointerMove 1 11 11)))
  (play out "lifting a finger from a pinch"
        (list (PointerDown 1 0 0 0)
              (PointerDown 2 100 0 0)
              (PointerUp 2 100 0)
              (PointerMove 1 40 0)
              (PointerUp 1 40 0)))
  (play out "a press that never released"
        (list (PointerDown 1 0 0 0) (PointerDown 1 50 50 0) (PointerUp 1 51 50)))
  (unit))
