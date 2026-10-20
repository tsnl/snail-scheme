;; Direct casualty settlement has no preceding movement, healing, production or
;; combat. Only the test build exposes clear-casualties in a temporary model copy.
(define-library (tests casualty)
  (export answer)
  (import
   (scheme base)
   (application reducer)
   (application bridge)
   (browser application)
   (siegework model)
   (siegework state)
   (only (lofi core) ann -> I32 I64))
  (begin
    (define (wound bots id)
      (if (null? bots) bots
          (let ((bot (car bots)))
            (cons (if (= (bot-id bot) id)
                      (make-bot id (bot-x bot) (bot-y bot) (bot-job bot) (bot-target bot)
                                (bot-cargo bot) (bot-timer bot) (bot-path bot) 0
                                (bot-order bot) (bot-source bot) (bot-flight bot)) bot)
                  (wound (cdr bots) id)))))
    (application world (state World 15) (initial-world)
                 (settle (value (id I32))
                         (no-effects (clear-casualties (world-bots-set value (wound (world-bots value) id))))))
    (application local (state I32 1) 0
                 (noop (value) (no-effects value)))
    (define (encode-local value) (vector (ann 1 I32) value))
    (define (decode-local words) (vector-ref words (ann 1 I64)))
    (define (view world local) (empty-list))
    (define (status world local) "casualty settlement fixture")
    (define app (program world local 0 2 decode-world encode-world decode-local encode-local view status))
    (define answer
      (ann (lambda (operation a b c) (run-program app operation a b c))
           (-> I32 I32 I32 I32 I32)))))
