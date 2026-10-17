(define-library (ui-lab game)
  (export application-entry)
  (import
   (scheme base)
   (scheme immutable)
   (application reducer)
   (application bridge)
   (application serialization)
   (lofi serialization)
   (browser application)
   (ui core)
   (ui browser)
   (only (lofi core) ann -> I32)
   (only (lofi base) string-append))
  (begin

    ;; ---- Two explicit owners and ordinary lexical handlers ----

    (application match-app (state I32 1) 10
                 (advance (state) (no-effects state))
                 (reset (state) (no-effects 10)))
    (application client-app (state I32 1) 10
                 (move (state (x I32) (y I32)) (no-effects state))
                 (increment (state) (no-effects (+ state 1)))
                 (decrement (state) (no-effects (- state 1)))
                 (set-value (state (value I32)) (no-effects value)))
    (define target (destination client-owner client-app))
    (define (encode state) (encode-snapshot 1 state))
    (define (decode words) (ann (decode-snapshot words) I32))

    ;; ---- The entire UI is a pure value rebuilt from current state ----

    (define (controls value)
      (ui-panel "controls" (grow 1) (grow 1) 20 12
                (list (ui-label "title" (grow 1) (px 34) "A small Scheme interface" 2)
                      (ui-label "explanation" (grow 1) (px 64)
                                "Rows and columns assign rectangles in one top-down pass. Buttons carry typed application requests." 0)
                      (ui-meter "level" (grow 1) (px 38)
                                (string-append "Current value: " (integer-text value)) value 100 0)
                      (ui-row "buttons" (grow 1) (px 48) 10
                              (list (ui-button "less" (grow 1) (grow 1) "Decrease" "Keyboard and touch" #t #f (decrement))
                                    (ui-button "more" (grow 1) (grow 1) "Increase" "Enter activates focus" #t #t (increment))))
                      (ui-label "input-label" (grow 1) (px 24) "Set a value from 0 to 100" 1)
                      (ui-number "amount" (grow 1) (px 70) "Value" "An unfinished edit survives redraws."
                                 value 0 100 (set-value 0))
                      (ui-scroll "details" (grow 1) (grow 1) 160 12
                                 (list (ui-label "contract" (grow 1) (px 80)
                                                 "Fixed sizes never become negative. Growth shares remaining space. Content never asks ancestors to measure again." 1)
                                       (ui-label "draft" (grow 1) (px 68)
                                                 "Focus this field and type while another control updates state. Stable widget keys retain the same browser input." 1))))))
    (define (view world value)
      (present-ui! target (controls value)) (empty-list))
    (define (status world value) (string-append "Value " (integer-text value)))
    (define app (program match-app client-app 0 0 decode encode decode encode view status))
    (define application-entry
      (ann (lambda (operation a b c) (run-program app operation a b c)) (-> I32 I32 I32 I32 I32)))))
