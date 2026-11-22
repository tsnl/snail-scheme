(import
 (snail core base)
 (snail core io))

;; Each suspension goes to the nearest `with-prompt` of its own prompt,
;; past those of other prompts, which are kept with the rest of the body
;; and are around it again when it resumes.
;; ANCHOR: nested
(define outer (→ (Prompt String Unit)) (make-prompt))

(define inner (→ (Prompt I64 I64)) (make-prompt))

;; Doubles what its body asks `inner` for, and tells `outer` about it
;; first: that suspension passes this `with-prompt` on its way out.
(define (doubling (body (Fn → I64))) (→ I64)
  (with-prompt inner
               body
               (lambda (n resume)
                 (suspend outer (string-append "doubling " (show n)))
                 (resume (* n 2)))))

;; Every line the body tells `outer`, then its value.
(define (told (out OutputPort) (body (Fn → I64))) (→ I64)
  (with-prompt outer
               body
               (lambda (line resume)
                 (write-line out line)
                 (resume (unit)))))

;; ANCHOR_END: nested

;; Of two `with-prompt`s of one prompt, the inner one catches, and a
;; suspension its handler makes goes to the outer one.
(define (twice-told (out OutputPort)) (→ I64)
  (told out
        (lambda ()
          (with-prompt outer
                       (lambda ()
                         (suspend outer "from the body")
                         1)
                       (lambda (line resume)
                         (suspend outer (string-append "inner heard: " line))
                         (+ 10 (resume (unit))))))))

(define (main (out OutputPort)) (→ Unit)
  ;; ANCHOR: run-nested
  (display out
           (told out
                 (lambda ()
                   (doubling (lambda ()
                               (suspend outer "asking")
                               (+ (suspend inner 1) (suspend inner 20)))))))
  (newline out)
  ;; ANCHOR_END: run-nested
  (display out (twice-told out))
  (newline out)
  (unit))
