(import
 (snail core base)
 (snail core io)
 (snail shell task)
 (snail shell future)
 (snail shell dom)
 (snail shell dom memory)
 (snail shell fetch)
 (snail shell json)
 (snail shell ui)
 (snail shell ide application)
 (only (snail shell ide palette) visible?))

;; The actual IDE update/view/command loop, with HTTP replies controlled at
;; the fetch effect. A Hide cue releases a held reply only after later input
;; has reached the model. Completion counts prove the test did not merely
;; close the document with the important command still suspended.
(enum Delay
  (NoDelay)
  (SaveReply)
  (ReloadReply)
  (SecondRead))

(: reply (-> String String (Result Reply String)))
(define (reply text revision)
  (Ok (Reply 200
             (json->string (JsonObject (list (Pair "text" (JsonString text))
                                             (Pair "revision" (JsonString revision))))))))

(: key (-> String I32 Cue))
(define (key name modifiers)
  (FireWindow "keydown" (Event-modifiers-set (Event-key-set no-event name) modifiers)))

(: input (-> String String Cue))
(define (input id text)
  (Fire id "input" (Event-value-set no-event text)))

(: invoke (-> String (List Cue)))
(define (invoke name)
  (list (key "F1" 0) (input "command-query" name)
        (Fire "command-query" "keydown" (Event-key-set no-event "Enter"))))

(: snapshot (-> (Borrow Session) Ide))
(define (snapshot session)
  (::ide session))

(: finished (-> Session Ide ! mut))
(define (finished session)
  (match session
    ((Session ide pending) (drop pending) ide)))

(: run (-> Delay (List Cue) (Pair Ide Document) ! mut console tasks))
(define (run delay cues)
  (let ((disk (ref "disk")) (revision (ref "initial")) (reads (ref 0))
        (writes (ref 0)) (completed (ref 0)) (streamed (ref #f)) (gate (make-mailbox)))
    (let ((result
           (handle fetch
               ((request
                 (lambda (method url headers body)
                   (if (string=? url "/api/project")
                       (Ok (Reply 200
                                  "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"notes.txt\"],\"directories\":[]}"))
                       (let ((saving (string=? method "PUT")))
                         (if saving
                             (begin (ref-set! disk body) (ref-set! revision "saved")
                                    (ref-set! writes (+ 1 (ref-get writes))))
                             (ref-set! reads (+ 1 (ref-get reads))))
                         (let ((answer (reply (ref-get disk) (ref-get revision))))
                           (when (and (= 2 (ref-get reads)) (match delay ((ReloadReply) #t) (_ #f)))
                             (ref-set! disk "watcher") (ref-set! revision "watched"))
                           (when (match delay
                                   ((SaveReply) saving)
                                   ((SecondRead) (and (not saving) (= 2 (ref-get reads))))
                                   ((ReloadReply) (and (not saving) (= 2 (ref-get reads))))
                                   ((NoDelay) #f))
                             (mailbox-receive gate))
                           (ref-set! completed (+ 1 (ref-get completed)))
                           answer)))))
                (stream-open (lambda (url kinds) (Stream 1)))
                (stream-next (lambda (stream)
                               (if (ref-get streamed) (None)
                                   (begin
                                     (ref-set! streamed #t)
                                     (Some (StreamEvent "open" ""))))))
                (stream-close (lambda (stream) (panic "unexpected stream close"))))
             (with-memory-dom cues
                              (lambda ()
                                (finished (run-reactor (begin-session initial)
                                                       (list (Open "notes.txt"))
                                                       (ann update-session
                                                            (-> Session
                                                                (Option Msg)
                                                                Session
                                                                ! mut completion console dom fetch))
                                                       session-view
                                                       session-window
                                                       snapshot
                                                       (lambda (model) (unit))
                                                       (lambda (model)
                                                         (mailbox-post gate (unit))))))))))
      (unless (= (ref-get completed) (+ (ref-get reads) (ref-get writes)))
        (panic "the document closed before all replies completed"))
      (write-line (string-append "requests " (show (ref-get reads)) "/" (show (ref-get writes))))
      result)))

(: report (-> Ide Unit ! console))
(define (report model)
  (match (buffer-at model "notes.txt")
    ((Some buffer)
     (write-line (::text buffer))
     (write-line (match (::baseline buffer)
                   ((Some snapshot) (::text snapshot))
                   ((None) "missing")))
     (write-line (show (dirty? buffer))))
    ((None) (panic "missing buffer"))))

(: panes-after (-> (List Cue) Unit ! mut console tasks))
(define (panes-after cues)
  (let ((model (::first (run (NoDelay) cues))))
    (write-line (show (length (::panes model))))))

(: files-after (-> (List Cue) Unit ! mut console tasks))
(define (files-after cues)
  (write-line (show (::files-shown (::first (run (NoDelay) cues))))))

(dispatch-local
 (once (lambda ()
         ;; A successful save changes the baseline, never subsequent typing.
         (report (::first (run (SaveReply)
                               (list (input "text-0" "submitted") (key "s" control-key)
                                     (input "text-0" "later") (Hide)))))
         ;; A newer watcher read can finish a confirmed dirty reload. Typing
         ;; after that read survives the original reload's delayed reply.
         (report (::first (run (ReloadReply)
                               (concatenate (list (list (input "text-0" "discard"))
                                                  (invoke "reload-buffer")
                                                  (list (FireWindow "online" no-event)
                                                        (input "text-0" "later") (Hide)))))))
         ;; Save invalidates reads that began before it.
         (report (::first (run (SecondRead)
                               (append (invoke "reload-buffer")
                                       (list (input "text-0" "submitted") (key "s" control-key)
                                             (Hide))))))
         ;; Observe each transition: two broken operations must not cancel out.
         (panes-after (invoke "spri"))
         (panes-after (append (invoke "spri") (list (key "w" alt-key))))
         (files-after (invoke "toggle-files"))
         (files-after (append (invoke "toggle-files") (list (key "b" control-key))))
         (let ((model (::first (run (NoDelay) (invoke "no-such-command")))))
           (write-line (show (visible? (::palette model))))))))
