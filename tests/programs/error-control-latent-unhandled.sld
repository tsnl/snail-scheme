(import
 (snail core base)
 (snail core io))

;; An Io handler may be installed with no Async handler in scope, since
;; fetch's Async is resolved where fetch is performed. Performing it where
;; no Async handler is in scope is the error, as for any unhandled effect.
(effect Async
  ((ctl await (-> I64 I64))))

(effect Io
  ((fetch (-> I64 I64 ! Async))))

(handle Io
    ((fetch (lambda (ticket) (await ticket))))
  (write-line (show (fetch 10))))
