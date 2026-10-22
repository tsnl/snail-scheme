;; The development server's program when it runs as WebAssembly:
;;
;;   develop ROOT RUNTIME CLIENT serve PORT APP-DIRECTORY
;;   develop ROOT RUNTIME CLIENT watch SOURCE DIRECTORY ... -- ARGUMENT ...
;;
;; It starts the loop of (lofi develop), which builds first, and exposes
;; the events its host, scripts/develop.mjs, reports: a changed file, a
;; timer, and a build that panicked. The host sends an event's text, a
;; path or the panic's message, a character at a time before the event.
(import
 (lofi base)
 (lofi io)
 (lofi develop))

(: loop (Ref (Option Loop)))
(define loop (ref (None)))

(: input (Ref (List Char)))
(define input (ref (Nil)))

(: develop-character (-> I32 Unit ! mut))
(define (develop-character code)
  (ref-set! input (Cons (i32->char code) (ref-get input))))

;; Event 1 is a changed file, 2 the timer the loop asked for, and 3 a build
;; that panicked.
(: develop-event (-> I32 Unit ! mut fs console develop))
(define (develop-event kind)
  (let ((text (list->string (reverse (ref-get input)))))
    (ref-set! input (Nil))
    (match (ref-get loop)
      ((Some current) (deliver-event! current kind text))
      ((None) (unit)))))

(expose develop-character "develop_character")
(expose develop-event "develop_event")

;; The loop is kept before it starts, so a first build that panics leaves
;; it ready for the next event.
(match (command-line)
  ((Cons _ arguments)
   (let ((started (new-loop arguments)))
     (ref-set! loop (Some started))
     (start-loop! started)))
  ((Nil) (panic "usage: develop ROOT RUNTIME CLIENT REQUEST ...")))
