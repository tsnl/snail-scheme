(import
 (snail core base)
 (snail core io)
 (snail shell development))

;; The development service's step, driven through the races its host can
;; deliver: edits that coalesce or supersede an attempt, replies that are
;; late or for another epoch, a disk that cannot be read, publication
;; that partly fails, closing and the resident's exit with an attempt in
;; flight, and generations kept while a page may still load them. Each line
;; is an event and the commands the step answers with.

;; ---- A project ----

(define (root) (→ String) "/r")

(define (project) (→ String) "/r/apps/p")

(define (description) (→ Description)
  (new Description (entries (list "main.sld"))
       (publics (list "public"))
       (browsers (Nil))))

(define (candidate (suffix String)) (→ Candidate)
  (new Candidate (description (description))
       (generations (list
                     (new Generation
                       (name "server")
                       (directory (string-append "/r/apps/p/build/s-" suffix))
                       (files (Nil))
                       (linked (Nil)))))
       (milliseconds 0)))

(define (succeeded (suffix String)) (→ Reply)
  (new Reply
    (description (Some (description)))
    (candidate (Some (candidate suffix)))
    (diagnostics (Nil))))

;; A build into generation `name`, as every build makes a new one.
(define (built-in (name String)) (→ Reply)
  (new Reply (description (Some (description)))
       (candidate (Some (new Candidate (description (description))
                             (generations (list (new Generation (name "server")
                                                     (directory
                                                      (string-append "/r/apps/p/build/" name))
                                                     (files (Nil))
                                                     (linked (Nil)))))
                             (milliseconds 0))))
       (diagnostics (Nil))))

;; An edit, and the attempt it starts built and published as `epoch`.
(define (rebuilt (epoch I64) (reply Reply)) (→ (List Event))
  (list (Touched (list "/r/apps/p/main.sld"))
        (TimerFired)
        (BuildReplied epoch reply)
        (Reconciled (Ok (unit)))
        (PublishReplied epoch (None))))

(define (failed) (→ Reply)
  (new Reply (description (Some (description)))
       (candidate (None))
       (diagnostics (list (new Diagnostic
                            (message "unbound identifier x")
                            (source (Some (new SourcePoint
                                            (file "/r/apps/p/main.sld")
                                            (line 1)
                                            (column 2)))))))))

;; A build whose program links the file at `path`.
(define (linking (path String)) (→ Reply)
  (new Reply (description (Some (description)))
       (candidate (Some (new Candidate (description (description))
                             (generations (list (new Generation
                                                  (name "server")
                                                  (directory "/r/apps/p/build/s-l")
                                                  (files (Nil))
                                                  (linked (list path)))))
                             (milliseconds 0))))
       (diagnostics (Nil))))

;; ---- Printing ----

(define (event->string (event Event)) (→ String)
  (match event
    ((ResidentStarted) "resident started")
    ((ResidentExited message) (string-append "resident exited: " message))
    ((Touched paths) (string-append "touched " (string-join paths " ")))
    ((Uncertain error)
     (match error
       ((Some message) (string-append "uncertain: " message))
       ((None) "uncertain")))
    ((Reconciled result)
     (match result
       ((Ok _) "reconciled")
       ((Err message) (string-append "reconcile failed: " message))))
    ((BuildReplied epoch reply)
     (string-append "built " (show epoch) (match (● reply candidate)
                                            ((Some _) " a candidate")
                                            ((None) " nothing"))))
    ((PublishReplied epoch error)
     (string-append "published " (show epoch) (match error
                                                ((Some message) (string-append ": " message))
                                                ((None) ""))))
    ((DiscardReplied epoch) (string-append "discarded " (show epoch)))
    ((TimerFired) "timer")
    ((RequestBuild) "build requested")
    ((Close) "close")))

(define (command->string (command Command)) (→ String)
  (match command
    ((Build epoch) (string-append "build " (show epoch)))
    ((Reconcile) "reconcile")
    ((Publish epoch) (string-append "publish " (show epoch)))
    ((Discard epoch) (string-append "discard " (show epoch)))
    ((Abandon epoch) (string-append "abandon " (show epoch)))
    ((Release epoch) (string-append "release " (show epoch)))
    ((Arm) "arm")
    ((Notify snapshot) (snapshot->string snapshot))
    ((Reclaim directories) (string-append "reclaim " (string-join directories " ")))
    ((Shutdown) "shutdown")
    ((Closed) "closed")))

(define (snapshot->string (snapshot Snapshot)) (→ String)
  (string-append "notify "
                 (phase->string (● snapshot phase))
                 " "
                 (show (● snapshot id))
                 (string-concatenate (map (lambda (diagnostic)
                                            (string-append " ["
                                                           (● diagnostic message)
                                                           "]"))
                                          (● snapshot diagnostics)))
                 (match (● snapshot publications)
                   ((Cons published _)
                    (string-append " published " (show (● published id))))
                   ((Nil) ""))))

(define (phase->string (phase Phase)) (→ String)
  (match phase
    ((Starting) "starting")
    ((Building) "building")
    ((Succeeded) "succeeded")
    ((Failed) "failed")
    ((Superseded) "superseded")
    ((Fatal) "fatal")))

;; ---- Driving ----

(define (drive (service Service) (events (List Event))) (→ Service) (! output-port)
  (fold-left (lambda (service event)
               (let ((stepped (step service event)))
                 (write-line (string-append "  "
                                            (event->string event)
                                            " -> "
                                            (match (● stepped second)
                                              ((Nil) "nothing")
                                              (commands
                                               (string-join (map command->string commands) "; ")))))
                 (● stepped first)))
             service
             events))

(define (scenario (name String) (events (List Event))) (→ Service) (! output-port)
  (write-line name)
  (drive (new-service (root) (project)) events))

;; Starting up, and the first attempt replied to and published.
(define (started) (→ (List Event)) (list (ResidentStarted) (Reconciled (Ok (unit))) (TimerFired)))

(define (first-published) (→ (List Event))
  (append (started)
          (list (BuildReplied 1 (succeeded "a"))
                (Reconciled (Ok (unit)))
                (PublishReplied 1 (None)))))

(define (main) (→ Unit) (! output-port)
  ;; ---- Scenarios ----

  (scenario "edits coalesce into one attempt"
            (append (started)
                    (list (BuildReplied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (PublishReplied 1 (None))
                          (Touched (list "/r/apps/p/main.sld"))
                          (Touched (list "/r/src/snail/core/base.sld"))
                          (TimerFired)
                          (TimerFired))))
  (scenario "an input edited while building supersedes the attempt"
            (append (started)
                    (list (Touched (list "/r/apps/p/lib/util.sld"))
                          (BuildReplied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (DiscardReplied 1)
                          (TimerFired))))
  (scenario "a file the build does not read does not"
            (append (started)
                    (list (Touched (list "/r/apps/p/notes.txt"))
                          (BuildReplied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (PublishReplied 1 (None)))))
  (scenario "a public file is an input once a reply names the directory"
            (list (ResidentStarted)
                  (Reconciled (Ok (unit)))
                  (Touched (list "/r/apps/p/public/index.html"))
                  (TimerFired)
                  (Touched (list "/r/apps/p/public/index.html"))
                  (BuildReplied 1 (succeeded "a"))
                  (Reconciled (Ok (unit)))))
  (scenario "a linked file is an input once a published program links it"
            (append (started)
                    (list (Touched (list "/r/apps/p/art.bin"))
                          (BuildReplied 1 (linking "/r/apps/p/art.bin"))
                          (Reconciled (Ok (unit)))
                          (PublishReplied 1 (None))
                          (Touched (list "/r/apps/p/art.bin"))
                          (TimerFired))))
  (scenario "a reply for another epoch is fatal"
            (append (first-published)
                    (list (Touched (list "/r/apps/p/main.sld"))
                          (TimerFired)
                          (BuildReplied 1 (failed)))))
  (scenario "a publication that fails releases the attempt and reports it"
            (append (started)
                    (list (BuildReplied 1 (succeeded "a"))
                          (Reconciled (Ok (unit)))
                          (PublishReplied 1 (Some "cannot rename build/server")))))
  (scenario "a failed build reports its diagnostics and keeps what was published"
            (append (first-published)
                    (list (Touched (list "/r/apps/p/main.sld"))
                          (TimerFired)
                          (BuildReplied 2 (failed))
                          (Reconciled (Ok (unit))))))
  (scenario "a disk that cannot be read discards the candidate until it can"
            (append (started)
                    (list (BuildReplied 1 (succeeded "a"))
                          (Reconciled (Err "cannot reconcile /r/apps/p"))
                          (DiscardReplied 1)
                          (Uncertain (Some "still failing"))
                          (Uncertain (None))
                          (TimerFired))))
  (scenario "a disk that cannot be read at start-up waits for it"
            (list (ResidentStarted)
                  (RequestBuild)
                  (Reconciled (Err "cannot reconcile /r/apps/p"))
                  (Uncertain (Some "still failing"))
                  (Uncertain (None))
                  (TimerFired)))
  (scenario "closing with an attempt in flight abandons it, and nothing after"
            (append (started)
                    (list (Close) (BuildReplied 1 (succeeded "a")) (Close))))
  (scenario "closing while publishing releases"
            (append (started)
                    (list (BuildReplied 1 (succeeded "a")) (Reconciled (Ok (unit))) (Close))))
  (scenario "the resident's exit is fatal"
            (append (started)
                    (list (ResidentExited "status 1: snail: out of memory")
                          (ResidentExited "again"))))
  (scenario "the resident's exit before the first reconciliation stays what failed"
            (list (ResidentStarted)
                  (ResidentExited "SIGKILL")
                  (Reconciled (Ok (unit)))
                  (TimerFired)))
  (scenario "generations stay while they are the latest two published"
            (concatenate
             (list (started)
                   (list (BuildReplied 1 (built-in "g1"))
                         (Reconciled (Ok (unit)))
                         (PublishReplied 1 (None)))
                   (rebuilt 2 (built-in "g2"))
                   (rebuilt 3 (built-in "g3"))
                   (rebuilt 4 (built-in "g4")))))
  (unit))
