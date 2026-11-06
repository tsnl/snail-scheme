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

(: state (-> palette-Step palette-State ! dom fetch))
(define (state step)
  (match step ((palette-Step next _ commands) (drop commands) next)))

(: send (-> palette-State palette-Message palette-State ! dom fetch))
(define (send state message)
  (state-of-update state context message))

(: state-of-update (-> palette-State palette-Context palette-Message palette-State ! dom fetch))
(define (state-of-update before context message)
  (state (palette-update before context message)))

(: check (-> Bool String Unit ! console))
(define (check ok label)
  (if ok (write-line label) (panic label)))

(: requested? (-> palette-Step Bool ! dom fetch))
(define (requested? step)
  (match step
    ((palette-Step _ _ commands)
     (match commands ((Nil) #f) ((Cons first rest) (drop first) (drop rest) #t)))))

(: no-outcome? (-> palette-Step Bool ! dom fetch))
(define (no-outcome? step)
  (match step
    ((palette-Step _ outcome commands) (drop commands) (match outcome ((None) #t) (_ #f)))))

(: result (-> String (Result search-Results Failure)))
(define (result path)
  (Ok (search-SavedResults (SearchResults (list (Hit (Point path 2 3) "revision" "text")) 0 #f))))

(: click (-> (Html palette-Message) (List palette-Message)))
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

;; No timer or network decides delivery order. Commands are explicitly
;; discarded, and Due/Found/Created messages are supplied by each scenario.
(: run (-> Unit ! dom fetch console))
(define (run)
  (let* ((start (state (palette-open palette-initial
                                     (palette-Searching
                                      (palette-Search (search-SavedProject)
                                                      (palette-Debouncing))))))
         (a1 (send start (palette-Query "a")))
         (b (send a1 (palette-Query "b")))
         (a2 (send b (palette-Query "a")))
         (pending (send a2 (palette-Due (::generation a2))))
         (ready
          (send pending (palette-Found (::generation pending) (result "new.sld"))))
         (stale (send (send ready (palette-Found (::generation a1) (result "old.sld")))
                      (palette-Found (::generation b)
                                     (Err (Failure 500 "obsolete failure")))))
         (clicks (concatenate (map click (palette-view ready context))))
         (closed (palette-cancel pending))
         (reopened (state (palette-open closed (palette-Files))))
         (draft-panel (send (state (palette-open palette-initial
                                                 (palette-Searching
                                                  (palette-Search (search-CurrentDraft draft)
                                                                  (palette-Debouncing)))))
                            (palette-Query "before")))
         (replaced (state (palette-reconcile draft-panel
                                             (Some (search-Draft "main.sld" "after")))))
         (creation (send (state (palette-open palette-initial
                                              (palette-Creating (palette-Creation #f #f ""))))
                         (palette-Query "new.sld")))
         (writing (send creation (palette-KeyPressed "Enter" 0))))
    (check
     (not (requested? (palette-update a2 context (palette-Due (::generation a1)))))
     "old debounce is ignored")
    (check (not (requested?
                 (palette-update pending context (palette-Due (::generation pending)))))
           "one request per generation")
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
    (check (and (no-outcome? (palette-update closed
                                             context
                                             (palette-Found (::generation pending)
                                                            (result "old"))))
                (not (palette-visible?
                      (send closed
                            (palette-Found (::generation pending) (result "old"))))))
           "completion after closing stays closed")
    (check (no-outcome? (palette-update reopened
                                        context
                                        (palette-Found (::generation pending)
                                                       (result "old"))))
           "completion cannot replace a reopened picker")
    (check (> (::generation replaced) (::generation draft-panel))
           "draft replacement starts a new search")
    (check (not (requested? (palette-update replaced
                                            context
                                            (palette-Due (::generation draft-panel)))))
           "old draft debounce is ignored")
    (check (not (requested? (palette-update writing context (palette-KeyPressed "Enter" 0))))
           "creation cannot be submitted twice")
    (check (= (::generation (send writing (palette-Query "changed")))
              (::generation writing))
           "pending creation keeps its submitted path")
    (check (no-outcome? (palette-update (palette-cancel writing) context
                                        (palette-Created (::generation writing)
                                                         (Ok (JsonNull)))))
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
