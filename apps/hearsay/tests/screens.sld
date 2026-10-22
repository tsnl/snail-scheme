;; Clicks through both prototypes in the browser shell without a browser:
;; each HUD's panels are printed with their place, buttons in brackets and
;; marked - when disabled, with the number of shapes in each scene batch.
(import
 (lofi base)
 (lofi io)
 (lofi app)
 (hearsay shell))

(: widget-text (-> Widget String))
(define (widget-text widget)
  (match widget
    ((Label face text) text)
    ((Button face text caption action argument control ring)
     (string-append (match control ((Disabled) "-[") (_ "[")) text "]"))
    ((Dial face text fraction) text)
    ((Image face picture region scale) (string-append "<picture " (show picture) ">"))))

(: place-name (-> Place String))
(define (place-name place)
  (match place
    ((At corner column)
     (string-append (match corner ((TopLeft) "top left") ((TopRight) "top right") ((BottomLeft) "bottom left") ((BottomRight) "bottom right"))
                    " " (show column)))
    ((Dialog dismiss) "dialog")))

(: show-batches (-> Frame Unit ! console))
(define (show-batches frame)
  (match frame
    ((Frame camera light background motion batches pictures)
     (write-line (string-append "batches: "
                                (string-join (map (lambda (batch) (match batch ((Batch key version style items) (show (length (items))))))
                                                  batches)
                                             " "))))))

(: show-panel (-> Panel Unit ! console))
(define (show-panel panel)
  (match panel
    ((Panel key place widgets)
     (write-line (string-append "-- " key ", " (place-name place)))
     (for-each (lambda (widget) (write-line (widget-text widget))) widgets))))

(: click (-> Shell (List (Pair I32 I32)) Shell))
(define (click shell presses)
  (fold-left (lambda (shell press) (update-shell shell (Press (Pair-first press) (Pair-second press)))) shell presses))

(: step (-> Shell String (List (Pair I32 I32)) Shell ! console))
(define (step shell title presses)
  (let ((shell (click shell presses)))
    (write-line (string-append "==== " title))
    (show-batches (view-shell shell (lambda (path) (None))))
    (for-each show-panel (shell-hud shell))
    shell))

;; The ledger is the second prototype opened, so seed 5 deals it seed 7.
;; Buttons: 9000 with argument i opens rumor-mill scenario i, 9100 opens the
;; ledger, and 9999 is Menu. In the mill, 100 + p chooses person p, 3
;; delivers a job and 9 lies low. In the ledger, action 3 with argument i
;; does the i-th job, and 5 ends the round.
(let* ((shell (new-shell 5 1280 800))
       (shell (step shell "menu" (Nil)))
       (shell (step shell "two faces after delivering a job for Mo"
                    (list (Pair 9000 0) (Pair 112 0) (Pair 3 0) (Pair 9 0))))
       (shell (step shell "ledger" (list (Pair 9999 0) (Pair 9100 0))))
       (shell (step shell "ledger after doing job 2 and ending the round" (list (Pair 3 1) (Pair 5 0)))))
  (unit))
