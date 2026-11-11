(import
 (snail core base)
 (snail core io))

;; Dropping a resumption drops the linear values its frames hold, and
;; dropping a once lambda unrun drops what it captured, each under the
;; FnOnce's own row. The book's ownership chapter includes the text between
;; ANCHOR and ANCHOR_END.
(effect audit
  ((note (dyn (Fn String → Unit)))))

(effect Ask
  ((ctl ask (dyn (Fn → I64)))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (note (string-append "closed " name)))))))

;; ANCHOR: cancelled
;; The handle is live across `ask`, so the frame saved there holds it. Its
;; drop performs `audit`, which this function's row allows, so a handler
;; that drops the resumption drops the handle.
(define (use-after-ask) (→ I64) (! Ask audit)
  (let ((handle (Handle "h")))
    (let ((answer (ask)))
      (drop handle)
      answer)))

;; Dropping `resume` performs its row, `audit`, which is charged here.
(define (cancelled) (→ I64) (! audit)
  (handle Ask
      ((ask (lambda (resume)
              (drop resume)
              -1)))
    (use-after-ask)))
;; ANCHOR_END: cancelled

;; A once lambda whose row allows `audit` may capture the handle; dropping
;; the lambda unrun drops the handle.
(define (unrun) (→ Unit) (! audit)
  (let ((handle (Handle "w")))
    (let ((work (once (lambda () (drop handle)))))
      (drop work))))

(handle audit
    ((note (lambda (text) (write-line text))))
  (write-line (show (cancelled)))
  (unrun)
  (write-line "done"))
