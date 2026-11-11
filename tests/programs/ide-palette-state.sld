(import
 (snail core base)
 (snail core io)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell task)
 (snail shell ui)
 (snail shell json)
 (snail shell project client)
 (snail shell project protocol)
 (prefix (snail shell ide search) search-)
 (prefix (snail shell ide palette) palette-))

(: context palette-Context)
(define context
  (palette-Context (list (palette-Entry "save-buffer" "Ctrl+S")) (list "main.sld")))

(: state (impl (Fn palette-Step -> palette-State ! dom fetch)))
(define (state step)
  (match step ((palette-Step next _ commands) (drop commands) next)))

(: send (impl (Fn palette-State palette-Message -> palette-State ! dom fetch)))
(define (send state message)
  (state-of-update state context message))

(: state-of-update
   (impl (Fn palette-State palette-Context palette-Message -> palette-State ! dom fetch)))
(define (state-of-update before context message)
  (state (palette-update before context message)))

(: check (impl (Fn Bool String -> Unit ! console)))
(define (check ok label)
  (if ok (write-line label) (panic label)))

(: requested? (impl (Fn palette-Step -> Bool ! dom fetch)))
(define (requested? step)
  (match step
    ((palette-Step _ _ commands)
     (match commands ((Nil) #f) ((Cons first rest) (drop first) (drop rest) #t)))))

(: no-outcome? (impl (Fn palette-Step -> Bool ! dom fetch)))
(define (no-outcome? step)
  (match step
    ((palette-Step _ outcome commands) (drop commands) (match outcome ((None) #t) (_ #f)))))

(: result (impl (Fn String -> (Result search-Results Failure))))
(define (result path)
  (Ok (search-SavedResults (SearchResults (list (Hit (Point path 2 3) "revision" "text")) 0 #f))))

(: click (impl (Fn (Html palette-Message) -> (List palette-Message))))
(define (click html)
  (match html
    ((Text _) (Nil))
    ((Element _ attributes children)
     (append (concatenate (map (lambda (attribute)
                                 (match attribute
                                   ((On "click" _ _ message) (list (message no-event)))
                                   (_ (Nil)))) attributes))
             (concatenate (map click children))))))

(: draft search-Draft)
(define draft (search-Draft "main.sld" "before"))

(: reply (impl (Fn String -> Reply)))
(define (reply path)
  (Reply 200 (json->string
              (search->json (SearchResults (list (Hit (Point path 2 3) "revision" "text")) 0 #f)))))

;; Execute the real returned command, but choose when to apply its result.
;; A logical timer advances immediately; HTTP responses are fixed values.
(: execute (impl (Fn palette-Step Reply -> (Pair palette-State palette-CommandResult) ! dom fetch)))
(define (execute step reply)
  (match step
    ((palette-Step state _ (Cons (palette-Command command _) rest))
     (drop rest)
     (handle tasks
         ((yield (lambda (resume) (resume (unit))))
          (sleep (lambda (delay resume) (resume (unit))))
          (await (lambda (ticket resume) (drop resume) (panic "unexpected wait")))
          (ticket (lambda () 0)))
       (handle fetch
           ((request (lambda (method url headers body) (Ok reply)))
            (stream-open (lambda (url kinds) (panic "stream")))
            (stream-next (lambda (stream) (panic "stream")))
            (stream-close (lambda (stream) (unit))))
         (Pair state (command)))))
    (other (drop other) (panic "expected one command"))))

(: accept (impl (Fn palette-State palette-CommandResult -> palette-State ! dom fetch)))
(define (accept before result)
  (state (result before)))

(: run (impl (Fn -> Unit ! dom fetch console)))
(define (run)
  (let* ((start (state (palette-open palette-initial
                                     (palette-Searching
                                      (palette-Search (search-SavedProject)
                                                      (palette-Debouncing))))))
         (a1 (execute (palette-update start context (palette-Query "a")) (reply "unused")))
         (b (execute (palette-update (::first a1) context (palette-Query "b")) (reply "unused")))
         (a2 (execute (palette-update (::first b) context (palette-Query "a")) (reply "unused")))
         (old (execute ((::second a1) (::first a1)) (reply "old.sld")))
         (failed (execute ((::second b) (::first b))
                          (Reply 500 "{\"message\":\"obsolete failure\"}")))
         (new (execute ((::second a2) (::first a2)) (reply "new.sld")))
         (pending (::first new))
         (ready (accept pending (::second new)))
         (stale (accept (accept ready (::second old)) (::second failed)))
         (clicks (concatenate (map click (palette-view ready context))))
         (closed (palette-cancel pending))
         (reopened (state (palette-open closed (palette-Files))))
         (draft-work
          (execute (palette-update
                    (state (palette-open palette-initial
                                         (palette-Searching
                                          (palette-Search (search-CurrentDraft draft)
                                                          (palette-Debouncing)))))
                    context (palette-Query "before")) (reply "unused")))
         (draft-panel (::first draft-work))
         (replaced (state (palette-reconcile draft-panel (Some (search-Draft "main.sld" "after")))))
         (creation (send (state (palette-open palette-initial
                                              (palette-Creating (palette-Creation #f #f ""))))
                         (palette-Query "new.sld")))
         (write (execute (palette-update creation context (palette-KeyPressed "Enter" 0))
                         (Reply 200 "{}")))
         (writing (::first write)))
    (check (not (requested? ((::second a1) (::first a2)))) "old debounce is ignored")
    (check (not (requested? ((::second a2) pending))) "one request per generation")
    (match (palette-update stale context (palette-KeyPressed "Enter" 0))
      ((palette-Step next (Some (palette-OpenSavedHit hit)) commands)
       (drop commands)
       (check (and (string=? (::file (::point hit)) "new.sld")
                   (not (palette-visible? next))
                   (> (::generation next) (::generation stale)))
              "A-B-A keeps the new result and selection advances authority"))
      (other (drop other) (panic "selection")))
    (for-each (lambda (message)
                (match message
                  ((palette-Pick _ _)
                   (check (no-outcome?
                           (palette-update (send ready (palette-Query "different"))
                                           context
                                           message))
                          "old rendered choice is ignored"))
                  (_ (unit)))) clicks)
    (check (and (no-outcome? ((::second new) closed))
                (not (palette-visible? (accept closed (::second new)))))
           "completion after closing stays closed")
    (check (no-outcome? ((::second new) reopened)) "completion cannot replace a reopened picker")
    (check (> (::generation replaced) (::generation draft-panel))
           "draft replacement starts a new search")
    (check (not (requested? ((::second draft-work) replaced))) "old draft debounce is ignored")
    (check (not (requested? (palette-update writing context (palette-KeyPressed "Enter" 0))))
           "creation cannot be submitted twice")
    (check (= (::generation (send writing (palette-Query "changed"))) (::generation writing))
           "pending creation keeps its submitted path")
    (check (no-outcome? ((::second write) (palette-cancel writing)))
           "cancelled creation cannot navigate")))

(dispatch-local
 (once (lambda ()
         (handle fetch
             ((request (lambda (method url headers body) (panic "unexpected request")))
              (stream-open (lambda (url kinds) (panic "stream")))
              (stream-next (lambda (stream) (panic "stream")))
              (stream-close (lambda (stream) (panic "stream"))))
           (with-memory-dom (Nil) run))
         (unit))))
