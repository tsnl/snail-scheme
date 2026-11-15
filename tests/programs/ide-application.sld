(import
 (snail core base)
 (only (snail core forms) host)
 (snail core io)
 (snail shell task)
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
(record Requests
  ((disk String)
   (revision String)
   (reads I64)
   (writes I64)
   (completed I64)
   (streamed Bool)))

(enum Delay
  (NoDelay)
  (SaveReply)
  (ReloadReply)
  (SecondRead))

(define (reply (text String) (revision String)) (→ (Result Reply String))
  (Ok (new Reply (status 200)
           (body
            (json->string (JsonObject (list (new Pair (first "text") (second (JsonString text)))
                                            (new Pair
                                              (first "revision")
                                              (second (JsonString revision))))))))))

(define (key (name String) (modifiers I32)) (→ Cue)
  (FireWindow "keydown" (Event-modifiers-set (Event-key-set (no-event) name) modifiers)))

(define (input (id String) (text String)) (→ Cue)
  (Fire id "input" (Event-value-set (no-event) text)))

(define (invoke (name String)) (→ (List Cue))
  (list (key "F1" 0) (input "command-query" name)
        (Fire "command-query" "keydown" (Event-key-set (no-event) "Enter"))))

(define (run (delay Delay) (cues (List Cue)))
  (→ (Pair Ide Document))
  (! mut host output-port tasks)
  (let ((state (new Requests
                 (disk "disk")
                 (revision "initial")
                 (reads 0)
                 (writes 0)
                 (completed 0)
                 (streamed #f)))
        (gate (make-mailbox)))
    (let ((result
           (handle fetch
               ((request
                 (lambda (method url headers body)
                   (if (string=? url "/api/project")
                       (Ok (new Reply (status 200)
                                (body
                                 "{\"name\":\"test\",\"directory\":\"/test\",\"files\":[\"notes.txt\"],\"directories\":[]}")))
                       (let ((saving (string=? method "PUT")))
                         (if saving
                             (begin (set! (● state disk) body) (set! (● state revision) "saved")
                                    (set! (● state writes) (+ 1 (● state writes))))
                             (set! (● state reads) (+ 1 (● state reads))))
                         (let ((answer (reply (● state disk) (● state revision))))
                           (when (and (= 2 (● state reads)) (match delay ((ReloadReply) #t) (_ #f)))
                             (set! (● state disk) "watcher") (set! (● state revision) "watched"))
                           (when (match delay
                                   ((SaveReply) saving)
                                   ((SecondRead) (and (not saving) (= 2 (● state reads))))
                                   ((ReloadReply) (and (not saving) (= 2 (● state reads))))
                                   ((NoDelay) #f))
                             (mailbox-receive gate))
                           (set! (● state completed) (+ 1 (● state completed)))
                           answer)))))
                (stream-open (lambda (url kinds) (new Stream (id 1))))
                (stream-next (lambda (stream)
                               (if (● state streamed) (None)
                                   (begin
                                     (set! (● state streamed) #t)
                                     (Some (new StreamEvent (kind "open") (data "")))))))
                (stream-close (lambda (stream) (panic "unexpected stream close"))))
             (with-memory-dom cues
                              (lambda ()
                                (run-ui (initial)
                                        (list (Open "notes.txt"))
                                        (lambda (model message) (ui-update model message))
                                        (lambda (model) (view model))
                                        (lambda (model) (window model))
                                        (lambda (model) (unit))
                                        (lambda (model) (mailbox-post gate (unit)))))))))
      (unless (= (● state completed) (+ (● state reads) (● state writes)))
        (panic "the document closed before all replies completed"))
      (write-line (string-append "requests " (show (● state reads)) "/" (show (● state writes))))
      result)))

(define (report (model Ide)) (→ Unit) (! output-port)
  (match (buffer-at model "notes.txt")
    ((Some buffer)
     (write-line (● buffer text))
     (write-line (match (● buffer baseline)
                   ((Some snapshot) (● snapshot text))
                   ((None) "missing")))
     (write-line (show (dirty? buffer))))
    ((None) (panic "missing buffer"))))

(define (panes-after (cues (List Cue))) (→ Unit) (! mut host output-port tasks)
  (let ((model (● (run (NoDelay) cues) first)))
    (write-line (show (length (● model panes))))))

(define (files-after (cues (List Cue))) (→ Unit) (! mut host output-port tasks)
  (write-line (show (● (● (run (NoDelay) cues) first) files-shown))))

(define (main) (→ Unit) (! host mut output-port tasks)
  (dispatch
   (lambda ()
     ;; A successful save changes the baseline, never subsequent typing.
     (report (● (run (SaveReply)
                     (list (input "text-0" "submitted") (key "s" (control-key))
                           (input "text-0" "later") (Hide))) first))
     ;; A newer watcher read can finish a confirmed dirty reload. Typing
     ;; after that read survives the original reload's delayed reply.
     (report (● (run (ReloadReply)
                     (concatenate (list (list (input "text-0" "discard"))
                                        (invoke "reload-buffer")
                                        (list (FireWindow "online" (no-event))
                                              (input "text-0" "later") (Hide))))) first))
     ;; Save invalidates reads that began before it.
     (report (● (run (SecondRead)
                     (append (invoke "reload-buffer")
                             (list (input "text-0" "submitted") (key "s" (control-key))
                                   (Hide)))) first))
     ;; Observe each transition: two broken operations must not cancel out.
     (panes-after (invoke "spri"))
     (panes-after (append (invoke "spri") (list (key "w" (alt-key)))))
     (files-after (invoke "toggle-files"))
     (files-after (append (invoke "toggle-files") (list (key "b" (control-key)))))
     (let ((model (● (run (NoDelay) (invoke "no-such-command")) first)))
       (write-line (show (visible? (● model palette)))))))
  (unit))
