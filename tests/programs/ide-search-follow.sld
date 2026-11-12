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

(define (jobs (delayed Bool)
              (gate (Mailbox Unit))
              (completed (Ref I64))
              (reads (Ref I64))
              (commands (List Command)))
  (→ (List (FnOnce → Delivery ! mut output-port tasks dom fetch)))
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
(define (observed (work (FnOnce → CommandResult ! tasks dom fetch)) (reads (Ref I64)))
  (→ Delivery)
  (! mut tasks dom fetch)
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

(define (update-test (delayed-read Bool)
                     (gate (Mailbox Unit))
                     (completed (Ref I64))
                     (reads (Ref I64))
                     (model Model)
                     (message Delivery))
  (→ (Pair Model
           (List (FnOnce → Delivery ! mut output-port tasks dom fetch))))
  (match message
    ((Input message)
     (match (update (● model ide) message)
       ((Pair next commands)
        (Pair (Model next (● model answers)) (jobs #f gate completed reads commands)))))
    ((Produced read (CommandResult accept))
     (let ((transition (accept)))
       (match (transition (● model ide))
         ((Pair next commands)
          (Pair (Model next (+ (● model answers) (if (> read 0) 1 0)))
                (jobs (and (not delayed-read) (= read 2)) gate completed reads commands))))))))

(define (shown (model Model)) (→ (Html Delivery))
  (map-html Input (view (● model ide))))

(define (window-test (model Model)) (→ (List (Attribute Delivery)))
  (match (map-html Input (Element "window" (window (● model ide)) (Nil)))
    ((Element _ attributes _) attributes)
    (_ (panic "window attributes"))))

(define (input (text String))
  (→ Cue)
  (Fire "command-query" "input" (Event-value-set no-event text)))

(define enter (→ Cue) (Fire "command-query" "keydown" (Event-key-set no-event "Enter")))

(define (verify-focus (result (Pair Node Document))) (→ Unit)
  (let ((expected (string-append "focus " (show (● (● result first) handle))))
        (last (find (lambda (line) (and (>= (string-length line) 6)
                                        (string=? (substring line 0 6) "focus ")))
                    (reverse (document-trace (● result second))))))
    (match last
      ((Some line) (unless (string=? line expected) (panic "old task stole focus")))
      ((None) (panic "no focus")))))

(define (run (delayed-read Bool)) (→ Unit) (! mut output-port tasks)
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
                         (unless (= (ref-get reads) (● final answers))
                           (panic "the delayed read did not finish")))
                       (match (element-by-id "text-0")
                         ((Some field) (write-line (show (● (selection-range field) first))))
                         ((None) (panic "missing original field")))
                       (match (element-by-id (if delayed-read "text-0" "text-1"))
                         ((Some node) node)
                         ((None) (panic "missing expected editor"))))))
      (unless (= (ref-get completed) 1)
        (panic "the delayed operation did not finish"))
      (write-line (if delayed-read "obsolete failure cannot reveal cached coordinates"
                      "queued reveal cannot steal focus after a split")))))

(define main
  (lambda ()
    (dispatch-local (once (lambda () (run #t) (run #f))))
    (unit)))
