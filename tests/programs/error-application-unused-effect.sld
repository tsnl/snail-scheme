(import
 (snail core base)
 (snail core io)
 (snail shell app))

(: initial (-> I32 I32 I32 I64))
(define (initial seed width height)
  0)

(: step (-> I64 Input I64))
(define (step state input)
  state)

(: draw (-> I64 Frame))
(define (draw state)
  (panic "unused"))

(: panels (-> I64 (List Panel)))
(define (panels state)
  (Nil))

(: saved (-> I64 I64))
(define (saved state)
  state)

;; The default reset prints nothing, so claiming `console` for the root
;; claims an effect its body never performs.
(define-application I64
  (reset: default-reset)
  (effects: console)
  (init: initial)
  (update: step)
  (view: draw)
  (hud: panels)
  (save: saved)
  (restore: saved))
