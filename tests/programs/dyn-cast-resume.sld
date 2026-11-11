(import
 (snail core base)
 (snail core io))
(effect audit ((note (dyn (Fn String → Unit)))))
(effect Ask ((ctl ask (dyn (Fn → Unit)))))
(struct Resource
  ((name String)))
(instance (Drop (! audit) Resource)
  (define drop (lambda (resource) (match resource ((Resource name) (note name))))))
(define (work) (→ Unit) (! Ask audit)
  (let ((resource (Resource "held")))
    (ask)
    (drop resource)))

;; A saved resumption uses the handlers at its eventual drop site.
(handle audit ((note (lambda (name) (write-line (string-append "allocation: " name)))))
  (handle Ask
      ((ask (lambda (resume)
              (handle audit
                  ((note (lambda (name) (write-line (string-append "drop site: " name)))))
                (drop resume)))))
    (work)))

;; Running it moves ownership into the resumed frames. A later conversion
;; failure releases it there exactly once before the failure handler runs.
(define (resumed-work) (→ Unit) (! Ask audit dyn-cast)
  (let ((resource (Resource "resumed")))
    (ask)
    (ann (ann "bad" Any) I64)
    (drop resource)))
(handle audit ((note (lambda (name) (write-line name))))
  (handle dyn-cast ((conversion-failed (lambda (_) (write-line "caught after resume"))))
    (handle Ask ((ask (lambda (resume) (resume (unit)))))
      (resumed-work))))

;; The owner is held only for cleanup, never by the ordinary continuation.
(define (only-cleanup) (→ Unit) (! Ask audit)
  (let ((resource (Resource "only cleanup")))
    (ask)
    (panic "the test drops this resumption")))
(handle audit ((note (lambda (name) (write-line name))))
  (handle Ask ((ask (lambda (resume) (drop resume))))
    (only-cleanup)))

;; A mixed effect may save frames even for an operation that answers Never.
;; Its abortive dispatcher must drain them before calling the handler.
(effect Mixed
  ((ctl pause (dyn (Fn → Unit)))
   (ctl stop (dyn (Fn → Never)))))
(define (mixed) (→ Unit) (! Mixed audit)
  (let ((resource (Resource "mixed")))
    (absurd (stop))))
(handle audit ((note (lambda (name) (write-line name))))
  (handle Mixed
      ((pause (lambda (resume) (resume (unit))))
       (stop (lambda () (write-line "mixed caught"))))
    (mixed)))
