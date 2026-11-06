(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell json)
 (snail shell ui)
 (snail shell ide application)
 (prefix (snail shell ide palette) palette-))

(: widened (-> (List (FnOnce Msg ! tasks dom fetch))
               (List (FnOnce Msg ! mut console tasks dom fetch))))
(define (widened commands)
  (match commands
    ((Nil) (Nil))
    ((Cons command rest) (Cons (once (lambda () (command))) (widened rest)))))

(: delayed (-> (Mailbox Unit) (Ref I64) (List (FnOnce Msg ! tasks dom fetch))
               (List (FnOnce Msg ! mut console tasks dom fetch))))
(define (delayed gate completed commands)
  (match commands
    ((Nil) (Nil))
    ((Cons command rest)
     (Cons (once (lambda ()
                   (mailbox-receive gate)
                   (let ((message (command)))
                     (ref-set! completed (+ 1 (ref-get completed)))
                     message)))
           (delayed gate completed rest)))))

;; Substitute immediate timer delivery, keeping all application messages and
;; service tasks real. Delay either the read or the DOM task it produces.
(struct Model
  ((ide Ide)
   (answers I64)))

(: update-test (-> Bool (Mailbox Unit) (Ref I64) Model Msg
                   (Pair Model (List (FnOnce Msg ! mut console tasks dom fetch)))))
(define (update-test delayed-read gate completed model message)
  (let ((answers (+ (Model-answers model) (match message ((Answered _ _) 1) (_ 0)))))
    (match (update (Model-ide model) message)
      ((Pair next commands)
       (Pair (Model next answers)
             (match message
               ((PaletteEvent (palette-Query _))
                (Cons (once (lambda ()
                              (PaletteEvent
                               (palette-Due (palette-State-generation (Ide-palette next))))))
                      (widened commands)))
               ((Answered _ _)
                (if (and (not delayed-read) (= 2 answers))
                    (delayed gate completed commands) (widened commands)))
               (_ (widened commands))))))))

(: input (-> String Cue))
(define (input text) (Fire "command-query" "input" (Event-value-set no-event text)))
(: enter Cue)
(define enter (Fire "command-query" "keydown" (Event-key-set no-event "Enter")))

(: verify-focus (-> (Pair Node Document) Unit))
(define (verify-focus result)
  (let ((expected (string-append "focus " (show (Node-handle (Pair-first result)))))
        (last (find (lambda (line) (and (>= (string-length line) 6)
                                        (string=? (substring line 0 6) "focus ")))
                    (reverse (document-trace (Pair-second result))))))
    (match last
      ((Some line) (unless (string=? line expected) (panic "old task stole focus")))
      ((None) (panic "no focus")))))

(: run (-> Bool Unit ! mut console tasks))
(define (run delayed-read)
  (let ((reads (ref 0))
        (answers (ref 0))
        (completed (ref 0))
        (events (ref #f))
        (gate (make-mailbox)))
    (handle fetch
        ((request (lambda (method url headers body)
                    (cond ((string=? url "/api/project")
                           (Ok (Reply 200
                                      "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"notes.txt\"],\"directories\":[]}")))
                          ((string=? url "/api/search?q=needle")
                           (Ok (Reply 200
                                      "{\"hits\":[{\"path\":\"notes.txt\",\"revision\":\"r\",\"line\":2,\"column\":1,\"snippet\":\"needle\"}],\"skipped\":0,\"limited\":false}")))
                          (else
                           (ref-set! reads (+ 1 (ref-get reads)))
                           (if (and delayed-read (= 2 (ref-get reads)))
                               (begin (mailbox-receive gate)
                                      (ref-set! completed (+ 1 (ref-get completed)))
                                      (Err "obsolete failed read"))
                               (Ok
                                (Reply 200 "{\"text\":\"line\\nneedle\",\"revision\":\"r\"}")))))))
         (stream-open (lambda (url kinds) (Stream 1)))
         (stream-next (lambda (stream)
                        (if (ref-get events) (None)
                            (begin (ref-set! events #t) (Some (StreamEvent "open" ""))))))
         (stream-close (lambda (stream) (unit))))
      (verify-focus (with-memory-dom
                     (list (FireWindow "keydown" (Event-key-set no-event "F1"))
                           (input "search-project") enter (input "needle") enter
                           (if delayed-read (FireWindow "online" no-event)
                               (FireWindow "keydown"
                                           (Event-modifiers-set (Event-key-set no-event "\\")
                                                                control-key)))
                           (Hide))
                     (lambda ()
                       (let ((final (run-ui (Model initial 0) (list (Open "notes.txt"))
                                            (lambda (model message)
                                              (update-test delayed-read
                                                           gate
                                                           completed
                                                           model
                                                           message))
                                            (lambda (model) (view (Model-ide model)))
                                            (lambda (model) (window (Model-ide model)))
                                            (lambda (model) (unit))
                                            (lambda (model) (mailbox-post gate (unit))))))
                         (unless (= (ref-get reads) (Model-answers final))
                           (panic "the delayed read did not finish")))
                       (match (element-by-id "text-0")
                         ((Some field) (write-line (show (Pair-first (selection-range field)))))
                         ((None) (panic "missing original field")))
                       (match (element-by-id (if delayed-read "text-0" "text-1"))
                         ((Some node) node)
                         ((None) (panic "missing expected editor"))))))
      (unless (= (ref-get completed) 1)
        (panic "the delayed operation did not finish"))
      (write-line (if delayed-read "obsolete failure cannot reveal cached coordinates"
                      "queued reveal cannot steal focus after a split")))))

(dispatch-local (once (lambda () (run #t) (run #f))))
