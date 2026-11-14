;; Clicks through both prototypes in the browser shell without a browser:
;; each HUD's panels are printed with their place, buttons in brackets with
;; their caption and marked - when disabled, and labels with their tone when
;; it is not plain, with the number of shapes in each scene batch.
(import
 (snail core base)
 (snail core io)
 (snail shell app)
 (hearsay shell)
 (only (hearsay hud) guide-next guide-close))

(define (widget-text (widget Widget)) (→ String)
  (match widget
    ((Label face text) (string-append (tone-mark face) text))
    ((Button face text caption action argument control ring)
     (string-append (match control ((Disabled) "-[") (_ "["))
                    text
                    (if (string=? caption "") "" (string-append " | " caption))
                    "]"))
    ((Dial face text fraction) text)
    ((Link face text url) (string-append text " <" url ">"))
    ((Text face spans) (string-concatenate (map span-words spans)))
    ((Image face picture region scale) (string-append "<picture " (show picture) ">"))))

(define (span-words (span Span)) (→ String)
  (match span
    ((Normal words) words)
    ((Strong words) words)))

(define (tone-mark (face Look)) (→ String)
  (match face
    ((Look key icon help tone badge)
     (match tone
       ((Plain) "")
       ((Good) "(good) ")
       ((Warning) "(warning) ")
       ((Danger) "(danger) ")
       ((Muted) "(muted) ")
       ((Suggested) "(suggested) ")))))

(define (place-name (place Place)) (→ String)
  (match place
    ((At corner column)
     (string-append (match corner
                      ((TopLeft) "top left")
                      ((TopRight) "top right")
                      ((BottomLeft) "bottom left")
                      ((BottomRight) "bottom right"))
                    " " (show column)))
    ((Dialog dismiss) "dialog")
    ((Banner) "banner")))

(define (show-batches (frame Frame)) (→ Unit) (! output-port)
  (match frame
    ((Frame camera light background motion batches pictures)
     (write-line (string-append "batches: "
                                (string-join (map (lambda (batch)
                                                    (match batch
                                                      ((Batch key version style items)
                                                       (show (length (items))))))
                                                  batches)
                                             " "))))))

(define (show-panel (panel Panel)) (→ Unit) (! output-port)
  (match panel
    ((Panel key place widgets)
     (write-line (string-append "-- " key ", " (place-name place)))
     (for-each (lambda (widget) (write-line (widget-text widget))) widgets))))

(define (click (shell Shell) (presses (List (Pair I32 I32)))) (→ Shell)
  (fold-left
   (lambda (shell press) (update-shell shell (Press (● press first) (● press second))))
   shell
   presses))

(define (step (shell Shell) (title String) (presses (List (Pair I32 I32))))
  (→ Shell)
  (! output-port)
  (let ((shell (click shell presses)))
    (write-line (string-append "==== " title))
    (show-batches (view-shell shell (lambda (path) (None))))
    (for-each show-panel (shell-hud shell))
    shell))

(define (main) (→ Unit) (! output-port)

  ;; The ledger is the second prototype opened, so seed 5 deals it seed 7.
  ;; Buttons: 9000 with argument i opens rumor-mill scenario i, 9100 opens the
  ;; ledger, and 9999 is Menu. Each guide opens by itself the first time;
  ;; `guide-next` turns to its next page, closing it after the last, and
  ;; `guide-close` closes it. In the mill, 100 + p chooses person p, 3
  ;; delivers a job and 9 lies low. In the ledger, action 3 with argument i
  ;; does the i-th job, and 5 ends the round.
  (let* ((shell (new-shell 5 1280 800))
         (shell (step shell "menu" (Nil)))
         (shell
          (step shell "two faces with its guide open" (list (new Pair (first 9000) (second 0)))))
         (shell (step shell "two faces after delivering a job for Mo"
                      (list (new Pair (first (guide-close)) (second 0))
                            (new Pair (first 112) (second 0))
                            (new Pair (first 3) (second 0))
                            (new Pair (first 9) (second 0)))))
         (shell (step shell
                      "ledger with its guide on the last page"
                      (list (new Pair (first 9999) (second 0))
                            (new Pair (first 9100) (second 0))
                            (new Pair (first (guide-next)) (second 0))
                            (new Pair (first (guide-next)) (second 0))
                            (new Pair (first (guide-next)) (second 0))
                            (new Pair (first (guide-next)) (second 0)))))
         (shell (step shell
                      "ledger after doing job 2 and ending the round"
                      (list (new Pair (first (guide-next)) (second 0))
                            (new Pair (first 3) (second 1))
                            (new Pair (first 5) (second 0))))))
    (unit))
  (unit))
