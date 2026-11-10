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

(enum Delivery
  (Input ((message Msg)))
  (Produced ((read I64)
             (result CommandResult))))

;; This race driver controls when a command runs, using the IDE's actual
;; pure transitions. The other IDE tests run the owned-future reactor.
(struct Model
  ((ide Ide)
   (answers I64)))

(: jobs (-> Bool (Mailbox Unit) (Ref I64) (Ref I64) (List Command)
            (List (FnOnce Delivery ! mut console tasks dom fetch))))
(define (jobs delayed gate completed reads commands)
  (match commands
    ((Nil) (Nil))
    ((Cons (Command work _) rest)
     (Cons (once (lambda ()
                   (when delayed
                     (mailbox-receive gate)
                     (ref-set! completed (+ 1 (ref-get completed))))
                   (observed work reads)))
           (jobs delayed gate completed reads rest)))))

;; Record the request identity at its boundary, before it can suspend.
(: observed (-> (FnOnce CommandResult ! tasks dom fetch) (Ref I64) Delivery ! mut tasks dom fetch))
(define (observed work reads)
  (let ((issued (ref (ann 0 I64))))
    (let ((result
           (handle fetch
               ((request (lambda (method url headers body)
                           (when (and (>= (string-length url) 10)
                                      (string=? (substring url 0 10) "/api/file?"))
                             (ref-set! issued (+ 1 (ref-get reads))))
                           (request method url headers body)))
                (stream-open (lambda (url kinds) (stream-open url kinds)))
                (stream-next (lambda (stream) (stream-next stream)))
                (stream-close (lambda (stream) (stream-close stream))))
             (work))))
      (Produced (ref-get issued) result))))

(: update-test (-> Bool (Mailbox Unit) (Ref I64) (Ref I64) Model Delivery
                   (Pair Model (List (FnOnce Delivery ! mut console tasks dom fetch)))))
(define (update-test delayed-read gate completed reads model message)
  (match message
    ((Input message)
     (match (update (::ide model) message)
       ((Pair next commands)
        (Pair (Model next (::answers model)) (jobs #f gate completed reads commands)))))
    ((Produced read (CommandResult accept))
     (let ((transition (accept)))
       (match (transition (::ide model))
         ((Pair next commands)
          (Pair (Model next (+ (::answers model) (if (> read 0) 1 0)))
                (jobs (and (not delayed-read) (= read 2)) gate completed reads commands))))))))

(: shown (-> Model (Html Delivery)))
(define (shown model)
  (map-html Input (view (::ide model))))

(: window-test (-> Model (List (Attribute Delivery))))
(define (window-test model)
  (match (map-html Input (Element "window" (window (::ide model)) (Nil)))
    ((Element _ attributes _) attributes)
    (_ (panic "window attributes"))))

(: input (-> String Cue))
(define (input text) (Fire "command-query" "input" (Event-value-set no-event text)))
(: enter Cue)
(define enter (Fire "command-query" "keydown" (Event-key-set no-event "Enter")))

(: verify-focus (-> (Pair Node Document) Unit))
(define (verify-focus result)
  (let ((expected (string-append "focus " (show (::handle (::first result)))))
        (last (find (lambda (line) (and (>= (string-length line) 6)
                                        (string=? (substring line 0 6) "focus ")))
                    (reverse (document-trace (::second result))))))
    (match last
      ((Some line) (unless (string=? line expected) (panic "old task stole focus")))
      ((None) (panic "no focus")))))

(: run (-> Bool Unit ! mut console tasks))
(define (run delayed-read)
  (let ((reads (ref 0))
        (answers (ref 0))
        (completed (ref 0))
        (events (ref #f))
        (gate (make-mailbox))
        (hides (ref 0)))
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
                           (input "search-project") enter (input "needle") (Hide) enter
                           (if delayed-read (FireWindow "online" no-event)
                               (FireWindow "keydown"
                                           (Event-modifiers-set (Event-key-set no-event "\\")
                                                                control-key)))
                           (Hide))
                     (lambda ()
                       (let ((final (run-ui (Model initial 0) (list (Input (Open "notes.txt")))
                                            (lambda (model message)
                                              (update-test delayed-read
                                                           gate
                                                           completed
                                                           reads
                                                           model
                                                           message))
                                            shown
                                            window-test
                                            (lambda (model) (unit))
                                            (lambda (model)
                                              (ref-set! hides (+ 1 (ref-get hides)))
                                              (if (= (ref-get hides) 1)
                                                  (sleep 150)
                                                  (mailbox-post gate (unit)))))))
                         (unless (= (ref-get reads) (::answers final))
                           (panic "the delayed read did not finish")))
                       (match (element-by-id "text-0")
                         ((Some field) (write-line (show (::first (selection-range field)))))
                         ((None) (panic "missing original field")))
                       (match (element-by-id (if delayed-read "text-0" "text-1"))
                         ((Some node) node)
                         ((None) (panic "missing expected editor"))))))
      (unless (= (ref-get completed) 1)
        (panic "the delayed operation did not finish"))
      (write-line (if delayed-read "obsolete failure cannot reveal cached coordinates"
                      "queued reveal cannot steal focus after a split")))))

(dispatch-local (once (lambda () (run #t) (run #f))))
