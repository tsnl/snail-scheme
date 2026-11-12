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

(define context (→ palette-Context)
  (palette-Context (list (palette-Entry "save-buffer" "Ctrl+S")) (list "main.sld")))

(define (state (step palette-Step)) (→ palette-State) (! dom fetch)
  (match step ((palette-Step next _ commands) (drop commands) next)))

(define (send (state palette-State) (message palette-Message)) (→ palette-State) (! dom fetch)
  (state-of-update state context message))

(define (state-of-update (before palette-State) (context palette-Context) (message palette-Message))
  (→ palette-State)
  (! dom fetch)
  (state (palette-update before context message)))

(define (check (ok Bool) (label String)) (→ Unit) (! output-port)
  (if ok (write-line label) (panic label)))

(define (requested? (step palette-Step)) (→ Bool) (! dom fetch)
  (match step
    ((palette-Step _ _ commands)
     (match commands ((Nil) #f) ((Cons first rest) (drop first) (drop rest) #t)))))

(define (no-outcome? (step palette-Step)) (→ Bool) (! dom fetch)
  (match step
    ((palette-Step _ outcome commands) (drop commands) (match outcome ((None) #t) (_ #f)))))

(define (result (path String)) (→ (Result search-Results Failure))
  (Ok (search-SavedResults (SearchResults (list (Hit (Point path 2 3) "revision" "text")) 0 #f))))

(define (click (html (Html palette-Message))) (→ (List palette-Message))
  (match html
    ((Text _) (Nil))
    ((Element _ attributes children)
     (append (concatenate (map (lambda (attribute)
                                 (match attribute
                                   ((On "click" _ _ message) (list (message no-event)))
                                   (_ (Nil)))) attributes))
             (concatenate (map click children))))))

(define draft (→ search-Draft) (search-Draft "main.sld" "before"))

(define (reply (path String)) (→ Reply)
  (Reply 200 (json->string
              (search->json (SearchResults (list (Hit (Point path 2 3) "revision" "text")) 0 #f)))))

;; Execute the real returned command, but choose when to apply its result.
;; A logical timer advances immediately; HTTP responses are fixed values.
(define (execute (step palette-Step) (reply Reply))
  (→ (Pair palette-State palette-CommandResult))
  (! dom fetch)
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

(define (accept (before palette-State) (result palette-CommandResult))
  (→ palette-State)
  (! dom fetch)
  (state (result before)))

(define (run) (→ Unit) (! dom fetch output-port)
  (let* ((start (state (palette-open palette-initial
                                     (palette-Searching
                                      (palette-Search (search-SavedProject)
                                                      (palette-Debouncing))))))
         (a1 (execute (palette-update start context (palette-Query "a")) (reply "unused")))
         (b (execute (palette-update (● a1 first) context (palette-Query "b")) (reply "unused")))
         (a2 (execute (palette-update (● b first) context (palette-Query "a")) (reply "unused")))
         (old (execute ((● a1 second) (● a1 first)) (reply "old.sld")))
         (failed (execute ((● b second) (● b first))
                          (Reply 500 "{\"message\":\"obsolete failure\"}")))
         (new (execute ((● a2 second) (● a2 first)) (reply "new.sld")))
         (pending (● new first))
         (ready (accept pending (● new second)))
         (stale (accept (accept ready (● old second)) (● failed second)))
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
         (draft-panel (● draft-work first))
         (replaced (state (palette-reconcile draft-panel (Some (search-Draft "main.sld" "after")))))
         (creation (send (state (palette-open palette-initial
                                              (palette-Creating (palette-Creation #f #f ""))))
                         (palette-Query "new.sld")))
         (write (execute (palette-update creation context (palette-KeyPressed "Enter" 0))
                         (Reply 200 "{}")))
         (writing (● write first)))
    (check (not (requested? ((● a1 second) (● a2 first)))) "old debounce is ignored")
    (check (not (requested? ((● a2 second) pending))) "one request per generation")
    (match (palette-update stale context (palette-KeyPressed "Enter" 0))
      ((palette-Step next (Some (palette-OpenSavedHit hit)) commands)
       (drop commands)
       (check (and (string=? (● (● hit point) file) "new.sld")
                   (not (palette-visible? next))
                   (> (● next generation) (● stale generation)))
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
    (check (and (no-outcome? ((● new second) closed))
                (not (palette-visible? (accept closed (● new second)))))
           "completion after closing stays closed")
    (check (no-outcome? ((● new second) reopened)) "completion cannot replace a reopened picker")
    (check (> (● replaced generation) (● draft-panel generation))
           "draft replacement starts a new search")
    (check (not (requested? ((● draft-work second) replaced))) "old draft debounce is ignored")
    (check (not (requested? (palette-update writing context (palette-KeyPressed "Enter" 0))))
           "creation cannot be submitted twice")
    (check (= (● (send writing (palette-Query "changed")) generation) (● writing generation))
           "pending creation keeps its submitted path")
    (check (no-outcome? ((● write second) (palette-cancel writing)))
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
