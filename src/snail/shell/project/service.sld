;; `snail-scheme watch`'s service in Snail Scheme: one project's builds and its
;; browser targets behind one local port. (snail shell development)'s pure
;; `step` decides; this library carries out what it decides, with tasks
;; that each wait on one thing:
;;
;; - the owner, which holds the service and everything the step leaves to
;;   its host, and receives every message;
;; - the disk task, which holds the latest inventory of the project's
;;   inputs, takes another when asked, hinted or each second, and reports
;;   what changed;
;; - the resident builder, `snail-scheme resident PROJECT`, in a child process,
;;   with a task writing its requests, one reading its replies and one its
;;   standard error and exit;
;; - a task for each HTTP connection, which serves a browser target's
;;   builds ((snail shell project bundle)) or the service's status, and for
;;   an event stream, writes what the owner sends it.
;;
;; The service's own paths are under /.snail/, for tools and tests to watch
;; it: its `status`, `events` for each change of it, and a POST to `build`
;; to ask for an attempt. Each browser target is
;; at /NAME/, which only reads. An editor needs none of them: it asks
;; `snail-scheme lsp` (snail shell lsp).
;;
;; No cell holds state: each task threads its own through its loop.
(define-library (snail shell project service)
  (export
   Setup
   develop)
  (import
   (snail core base)
   (only (snail core forms) host)
   (except (snail core io) write)
   (snail shell task)
   (snail shell socket)
   (rename (snail shell process)
           (Command ProcessCommand))
   (snail shell http)
   (snail shell http exchange)
   (snail shell json)
   (snail shell json read)
   (snail shell utf8)
   (snail shell watch)
   (snail shell development)
   (snail shell project bundle))
  (begin

    ;; ---- Setup ----

    ;; What the service runs with: the repository's root; the command
    ;; line's program and the runtime it links programs with, which the
    ;; resident runs as; Node, which runs them; the reload client's program,
    ;; which browser targets' pages load; the project, absolute; and the
    ;; port to listen on, 0 for any.
    (record Setup
      ((root String)
       (cli String)
       (runtime String)
       (node String)
       (client String)
       (project String)
       (port I32)))

    (define (runner (setup Setup)) (→ String)
      (string-append (● setup root) "/host/native/run-snail.mjs"))

    ;; ---- Messages ----

    ;; What the owner receives. `Step` is an event for the pure step; `Ask`
    ;; one an HTTP handler waits on, answered on its reply mailbox; the rest
    ;; are the host's own: the debounce timer, the resident and event
    ;; streams.
    (enum Message
      (Step ((event Event)))
      (Ask
       ((event Event)
        (reply (Mailbox Answer))))
      (Status ((reply (Mailbox Answer))))
      (Applications ((reply (Mailbox (List Application)))))
      (Fired ((serial I64)))
      (Built
       ((epoch I64)
        (reply Reply)
        (targets Json)))
      (ResidentGone ((message String)))
      (Overdue)
      (Joined
       ((id I64)
        (watching (Option String))
        (connection Connection)
        (frames (Mailbox (Option Bytes)))
        (reply (Mailbox Answer))))
      (Written
       ((id I64)
        (count I64)))
      (Connected
       ((id I64)
        (connection Connection)))
      (Disconnected ((id I64))))

    ;; The owner's answer to a handler, as the response it sends.
    (record Answer
      ((status I32)
       (body Json)))

    ;; What the disk task is asked: to reconcile for the step, to scan
    ;; because something may have changed, as after a hint, whether to go
    ;; on, for the 1 s timer, or to stop.
    (enum Scan
      (Reconciling)
      (Prompted)
      (Ticked ((reply (Mailbox Bool))))
      (Stopping))

    ;; ---- The owner's state ----

    ;; A browser target as the service serves it: its name and the builds
    ;; of it retained, newest first.
    (record Application
      ((name String)
       (builds (List BuildDirectory))))

    ;; An event stream, by its connection's number: the browser target a
    ;; page's stream hears of builds of, or none for the service's own; and
    ;; how many bytes the owner sent it that its writer has not written yet.
    (record Client
      ((id I64)
       (watching (Option String))
       (connection Connection)
       (frames (Mailbox (Option Bytes)))
       (pending I64)))

    ;; Everything the step leaves to its host. `targets` is the latest
    ;; reply's candidate, by epoch, and `published` the targets of the one
    ;; published, as the status shows them. `frames` is the last status
    ;; sent to the service's streams. `connections` are the ones whose
    ;; handlers have not finished, by number, and `clients` those of them
    ;; that are event streams; `told` is the event last sent to each browser
    ;; target's pages. `stopping` holds the commands after Shutdown, run
    ;; once `waiting`, the resident and the handlers still running, reaches
    ;; zero.
    (record Host
      ((setup Setup)
       (owner (Mailbox Message))
       (disk (Mailbox Scan))
       (requests (Mailbox (Option String)))
       (resident Process)
       (resident-alive Bool)
       (listener Listener)
       (service Service)
       (snapshot Snapshot)
       (serial I64)
       (reservation (Option (Pair I64 String)))
       (targets (Option (Pair I64 Json)))
       (published Json)
       (clients (List Client))
       (told (List (Pair String String)))
       (connections (List (Pair I64 Connection)))
       (frames String)
       (stopping (Option (List Command)))
       (waiting I64)
       (done Bool)))

    ;; ---- Starting ----

    ;; Dispatches the task that starts the service; the scheduler runs it
    ;; once the program's main returns. The service ends when the owner has
    ;; shut everything down, and fails the program if the step went fatal.

    (define (develop (setup Setup))
      (→ Unit)
      (! mut tcp process fs hints output-port signals host tasks)
      (dispatch (lambda () (start setup))))

    ;; Listens, starts the resident, announces the service's URL, and
    ;; dispatches every other task.

    (define (start (setup Setup))
      (→ Unit)
      (! mut tasks tcp process fs hints output-port signals host)
      (let* ((listener (listening setup))
             (setup (Setup-port-set setup (● listener port)))
             (resident (resident-process setup))
             (owner (make-mailbox))
             (disk (make-mailbox))
             (requests (make-mailbox)))
        (dispatch (lambda () (scan-disk setup owner disk)))
        (dispatch (lambda () (tick disk)))
        (dispatch (lambda () (write-requests resident requests)))
        (dispatch (lambda () (read-replies resident owner (Nil))))
        (dispatch (lambda () (await-resident resident owner (Nil))))
        (dispatch (lambda () (accept-connections listener owner setup)))
        (dispatch (lambda () (mailbox-post owner (Step (wait-for-signal)))))
        (mailbox-post owner (Step (ResidentStarted)))
        (write-line
         (string-append "developing " (● setup project) " at " (listener-origin listener) "/"))
        (write-line (string-append "serving its browser targets at "
                                   (listener-origin listener)
                                   "/NAME/"))
        (own (new-host setup owner disk requests resident listener))))

    (define (wait-for-signal) (→ Event) (! tasks signals)
      (termination)
      (Close))

    ;; The service listens on the loopback address alone.

    (define (listening (setup Setup)) (→ Listener) (! tasks tcp)
      (match (match (endpoint "127.0.0.1" (● setup port))
               ((Ok local) (listen local))
               ((Err error) (Err error)))
        ((Ok listener) listener)
        ((Err error)
         (panic (string-append "cannot listen on port "
                               (show (● setup port))
                               ": "
                               (● error code))))))

    (define (listener-host (listener Listener)) (→ String)
      (string-append "127.0.0.1:" (show (● listener port))))

    (define (listener-origin (listener Listener)) (→ String)
      (string-append "http://" (listener-host listener)))

    (define (new-host (setup Setup)
                      (owner (Mailbox Message))
                      (disk (Mailbox Scan))
                      (requests (Mailbox (Option String)))
                      (resident Process)
                      (listener Listener))
      (→ Host)
      (new Host (setup setup)
           (owner owner)
           (disk disk)
           (requests requests)
           (resident resident)
           (resident-alive #t)
           (listener listener)
           (service (new-service (● setup root) (● setup project)))
           (snapshot (new Snapshot
                       (phase (Starting))
                       (id 0)
                       (diagnostics (Nil))
                       (publications (Nil))))
           (serial 0)
           (reservation (None))
           (targets (None))
           (published (JsonNull))
           (clients (Nil))
           (told (Nil))
           (connections (Nil))
           (frames "")
           (stopping (None))
           (waiting 0)
           (done #f)))

    ;; ---- The owner ----

    (define (own (host Host)) (→ Unit) (! mut tasks tcp process fs host)
      (let ((host (receive host (mailbox-receive (● host owner)))))
        (if (● host done) (finish host) (own host))))

    ;; A fatal service fails the program, with the diagnostic that ended it.

    (define (finish (host Host)) (→ Unit)
      (match (● (● host snapshot) phase)
        ((Fatal) (panic (first-message (● host snapshot))))
        (_ (unit))))

    (define (first-message (snapshot Snapshot)) (→ String)
      (match (● snapshot diagnostics)
        ((Cons diagnostic _) (● diagnostic message))
        ((Nil) "the service failed")))

    (define (receive (host Host) (message Message)) (→ Host) (! mut tasks tcp process fs host)
      (match message
        ((Step event) (stepped host event))
        ((Ask event reply) (asked host event reply))
        ((Status reply)
         (mailbox-post reply (new Answer (status 200) (body (status->json host))))
         host)
        ((Applications reply) (mailbox-post reply (served-applications host)) host)
        ((Fired serial) (if (= serial (● host serial)) (stepped host (TimerFired)) host))
        ((Built epoch reply targets)
         (stepped (Host-targets-set host (Some (new Pair (first epoch) (second targets))))
                  (BuildReplied epoch reply)))
        ((ResidentGone message) (resident-gone host message))
        ((Overdue) (overdue host))
        ((Joined id watching connection frames reply)
         (joined host id watching connection frames reply))
        ((Written id count) (written host id count))
        ((Connected id connection) (connected host id connection))
        ((Disconnected id) (disconnected host id))))

    (define (stepped (host Host) (event Event)) (→ Host) (! mut tasks tcp process fs host)
      (let ((result (step (● host service) event)))
        (perform-all (Host-service-set host (● result first)) (● result second))))

    ;; A handler's event, answered once its commands ran: a build asked for
    ;; is answered with the status of the attempt it waits for.

    (define (asked (host Host) (event Event) (reply (Mailbox Answer)))
      (→ Host)
      (! mut tasks tcp process fs host)
      (let ((host (stepped host event)))
        (mailbox-post reply (new Answer (status 202) (body (status->json host))))
        host))

    ;; ---- Carrying out commands ----

    ;; Each command in order. The commands after Shutdown wait until the
    ;; resident has stopped.

    (define (perform-all (host Host) (commands (List Command)))
      (→ Host)
      (! mut tasks tcp process fs host)
      (match commands
        ((Nil) host)
        ((Cons (Shutdown) rest) (shut-down host rest))
        ((Cons command rest) (perform-all (perform host command) rest))))

    (define (perform (host Host) (command Command)) (→ Host) (! mut tcp fs host tasks)
      (match command
        ((Build epoch) (build host epoch))
        ((Reconcile) (mailbox-post (● host disk) (Reconciling)) host)
        ((Publish epoch) (request host (epoch-request "publish" epoch (Nil))))
        ((Discard epoch) (request host (epoch-request "discard" epoch (Nil))))
        ((Abandon epoch) (give-up host epoch #t))
        ((Release epoch) (give-up host epoch #f))
        ((Arm) (arm host))
        ((Notify snapshot) (notify host snapshot))
        ((Reclaim directories)
         (for-each (lambda (directory)
                     (remove-tree directory)
                     (unit))
                   directories)
         host)
        ((Shutdown) host)
        ((Closed) (Host-done-set host #t))))

    (define (request (host Host) (line String)) (→ Host) (! mut)
      (mailbox-post (● host requests) (Some line))
      host)

    (define (epoch-request (kind String) (epoch I64) (rest (List (Pair String Json)))) (→ String)
      (json->string (JsonObject (append (list (new Pair (first "kind") (second (JsonString kind)))
                                              (new Pair
                                                (first "epoch")
                                                (second (JsonInteger epoch))))
                                        rest))))

    ;; An attempt's build directory, reserved under build/ before the
    ;; resident makes generations beside it, named for it.

    (define (build (host Host) (epoch I64)) (→ Host) (! mut fs)
      (match (reserve (string-append (● (● host setup) project) "/build") 0)
        ((Ok directory)
         (request (Host-reservation-set host (Some (new Pair (first epoch) (second directory))))
                  (epoch-request "build"
                                 epoch
                                 (list (new Pair (first "prefix")
                                            (second (JsonString
                                                     (string-append (base-name directory)
                                                                    "-"))))))))
        ((Err message)
         (mailbox-post (● host owner) (Step (ResidentExited message)))
         host)))

    ;; A name no entry of build/ has, nor begins, so the generations the
    ;; resident names with it are this attempt's alone, even beside what an
    ;; earlier service left there.

    (define (reserve (build String) (number I64)) (→ (Result String String)) (! fs)
      (match (make-directories build)
        ((Err error) (Err (string-append "cannot make " build ": " (show error))))
        ((Ok _)
         (match (list-directory build)
           ((Err error) (Err (string-append "cannot list " build ": " (show error))))
           ((Ok names) (reserve-unused build names number))))))

    (define (reserve-unused (build String) (names (List String)) (number I64))
      (→ (Result String String))
      (! fs)
      (let* ((name (string-append ".snail-attempt-" (show number)))
             (taken? (any? (lambda (entry)
                             (or (string=? entry name)
                                 (starts-with? entry (string-append name "-"))))
                           names)))
        (if taken?
            (reserve-unused build names (+ number 1))
            (match (make-directory (string-append build "/" name))
              ((Ok _) (Ok (string-append build "/" name)))
              ((Err (AlreadyExists)) (reserve-unused build names (+ number 1)))
              ((Err error) (Err (string-append "cannot reserve " name ": " (show error))))))))

    (define (base-name (path String)) (→ String)
      (let loop ((index (string-length path)))
        (cond ((= index 0) path)
              ((char=? (string-ref path (- index 1)) #\/)
               (substring path index (string-length path)))
              (else (loop (- index 1))))))

    ;; Gives up an attempt's directory, and when the attempt still owns
    ;; them, the generations the resident named for it.

    (define (give-up (host Host) (epoch I64) (generations? Bool)) (→ Host) (! fs)
      (match (● host reservation)
        ((Some (Pair reserved directory))
         (if (= reserved epoch)
             (begin
               (when generations? (remove-generations directory))
               (remove-tree directory)
               (Host-reservation-set host (None)))
             host))
        ((None) host)))

    (define (remove-generations (directory String)) (→ Unit) (! fs)
      (let ((build (substring directory 0 (- (string-length directory)
                                             (+ (string-length (base-name directory)) 1))))
            (prefix (string-append (base-name directory) "-")))
        (match (list-directory build)
          ((Ok names)
           (for-each (lambda (name)
                       (when (starts-with? name prefix)
                         (remove-tree (string-append build "/" name))
                         (unit)))
                     names))
          ((Err _) (unit)))))

    (define (starts-with? (text String) (prefix String)) (→ Bool)
      (and (>= (string-length text) (string-length prefix))
           (string=? (substring text 0 (string-length prefix)) prefix)))

    ;; Arming replaces the timer armed before: the owner ignores a firing
    ;; whose serial is not the latest.

    (define (arm (host Host)) (→ Host) (! mut host tasks)
      (let ((serial (+ (● host serial) 1)) (owner (● host owner)))
        (dispatch (lambda ()
                    (sleep 40)
                    (mailbox-post owner (Fired serial))))
        (Host-serial-set host serial)))

    ;; ---- Status ----

    ;; A snapshot to every event stream, as the frames that changed. A
    ;; fatal one closes the service.

    (define (notify (host Host) (snapshot Snapshot)) (→ Host) (! mut tcp fs host)
      (let ((host (told-pages
                   (broadcast-changes (Host-snapshot-set (published host snapshot) snapshot)))))
        (match (● snapshot phase)
          ((Fatal) (mailbox-post (● host owner) (Step (Close))) host)
          (_ host))))

    ;; The published targets, once the snapshot names the build whose
    ;; candidate the owner kept; a browser target's has the URL it is
    ;; served at.

    (define (published (host Host) (snapshot Snapshot)) (→ Host)
      (match (new Pair (first (● snapshot publications)) (second (● host targets)))
        ((Pair (Cons build _) (Some (Pair epoch targets)))
         (if (= (● build id) epoch)
             (Host-published-set host
                                 (JsonObject
                                  (list (new Pair (first "id") (second (JsonInteger epoch)))
                                        (new Pair (first "targets")
                                             (second (with-urls host build targets))))))
             host))
        (_ host)))

    (define (with-urls (host Host) (build Published) (targets Json)) (→ Json)
      (let ((browsers (● (● (● build candidate) description) browsers)))
        (match targets
          ((JsonArray items)
           (JsonArray (map (lambda (target) (with-url host browsers target)) items)))
          (other other))))

    (define (with-url (host Host) (browsers (List String)) (target Json)) (→ Json)
      (let ((name (json-text target "name")))
        (match target
          ((JsonObject members)
           (if (member? name browsers)
               (JsonObject
                (append members
                        (list (new Pair
                                (first "url")
                                (second (JsonString (application-url host name)))))))
               target))
          (other other))))

    (define (application-url (host Host) (name String)) (→ String)
      (string-append (listener-origin (● host listener)) "/" name "/"))

    ;; The browser targets of the publication, each with its builds the
    ;; service retains, newest first. A target the latest description no
    ;; longer has is not served.

    (define (served-applications (host Host)) (→ (List Application))
      (let ((publications (● (● host snapshot) publications)))
        (match publications
          ((Cons latest _)
           (map (lambda (name) (new Application (name name) (builds (builds-of publications name))))
                (● (● (● latest candidate) description) browsers)))
          ((Nil) (Nil)))))

    (define (builds-of (publications (List Published)) (name String)) (→ (List BuildDirectory))
      (concatenate (map (lambda (published)
                          (map (lambda (generation)
                                 (new BuildDirectory (epoch (● published id))
                                      (directory (● generation directory))
                                      (files (● generation files))
                                      (milliseconds (● (● published candidate) milliseconds))))
                               (filter
                                (lambda (generation) (string=? (● generation name) name))
                                (● (● published candidate) generations))))
                        publications)))

    ;; All a client can observe in one snapshot: the attempt and its
    ;; diagnostics, the published targets, and the resident's process.

    (define (status->json (host Host)) (→ Json)
      (let ((snapshot (● host snapshot)))
        (JsonObject
         (list (new Pair (first "phase") (second (JsonString (phase-name (● snapshot phase)))))
               (new Pair (first "id") (second (JsonInteger (● snapshot id))))
               (new Pair
                 (first "diagnostics")
                 (second (JsonArray (map diagnostic->json (● snapshot diagnostics)))))
               (new Pair (first "published") (second (● host published)))
               (new Pair (first "compiler") (second (compiler->json host)))))))

    (define (compiler->json (host Host)) (→ Json)
      (if (● host resident-alive)
          (JsonObject (list (new Pair
                              (first "worker")
                              (second (JsonInteger (i32->i64 (● (● host resident) id)))))))
          (JsonNull)))

    (define (phase-name (phase Phase)) (→ String)
      (match phase
        ((Starting) "starting")
        ((Building) "building")
        ((Succeeded) "succeeded")
        ((Failed) "failed")
        ((Superseded) "superseded")
        ((Fatal) "fatal")))

    (define (diagnostic->json (diagnostic Diagnostic)) (→ Json)
      (JsonObject
       (list (new Pair (first "severity") (second (JsonString "error")))
             (new Pair (first "message") (second (JsonString (● diagnostic message))))
             (new Pair (first "source") (second (match (● diagnostic source)
                                                  ((Some point) (point->json point))
                                                  ((None) (JsonNull))))))))

    (define (point->json (point SourcePoint)) (→ Json)
      (JsonObject (list (new Pair (first "file") (second (JsonString (● point file))))
                        (new Pair (first "line") (second (JsonInteger (● point line))))
                        (new Pair (first "column") (second (JsonInteger (● point column)))))))

    ;; ---- Event streams ----

    ;; Each change of the status goes to the service's streams, as one
    ;; frame; a new stream starts with the current one.

    (define (broadcast-changes (host Host)) (→ Host) (! mut tcp host)
      (let ((text (status-frame host)))
        (if (string=? text (● host frames)) host
            (broadcast (Host-frames-set host text) text))))

    ;; A status as the browser's EventSource reads it, one line of JSON.

    (define (status-frame (host Host)) (→ String)
      (string-append "event: status\ndata: " (json->string (status->json host)) "\n\n"))

    ;; Each client gets the frame, unless 16 KiB it was sent before are
    ;; still unwritten, as Node's stream refuses more: then it is dropped,
    ;; and reconnecting gets it the current status.

    (define (broadcast (host Host) (text String)) (→ Host) (! mut tcp host)
      (Host-clients-set host
                        (sent-to (● host clients)
                                 (lambda (client) (not (option-some? (● client watching))))
                                 (string->utf8 text))))

    ;; Each client `chosen` picks gets the frame; the rest are left as they
    ;; are.

    (define (sent-to (clients (List Client)) (chosen (Fn Client → Bool ! mut)) (bytes Bytes))
      (→ (List Client))
      (! mut tcp host)
      (match clients
        ((Nil) (Nil))
        ((Cons client rest)
         (cond ((not (chosen client)) (Cons client (sent-to rest chosen bytes)))
               ((>= (● client pending) 16384)
                (close-connection (● client connection))
                (mailbox-post (● client frames) (None))
                (sent-to rest chosen bytes))
               (else
                (mailbox-post (● client frames) (Some bytes))
                (Cons (Client-pending-set client (+ (● client pending) (vector-length bytes)))
                      (sent-to rest chosen bytes)))))))

    ;; A new event stream gets its first frames, unless there are 64
    ;; already or the service is closing.

    (define (joined (host Host)
                    (id I64)
                    (watching (Option String))
                    (connection Connection)
                    (frames (Mailbox (Option Bytes)))
                    (reply (Mailbox Answer)))
      (→ Host)
      (! mut tcp fs host)
      (cond ((option-some? (● host stopping))
             (mailbox-post reply
                           (new Answer
                             (status 503)
                             (body (message->json "project development is closing"))))
             host)
            ((>= (length (● host clients)) 64)
             (mailbox-post reply
                           (new Answer
                             (status 429)
                             (body (message->json "too many event connections"))))
             host)
            (else
             (mailbox-post reply (new Answer (status 200) (body (JsonNull))))
             (Host-clients-set host
                               (append (sent-to (list (new Client
                                                        (id id)
                                                        (watching watching)
                                                        (connection connection)
                                                        (frames frames)
                                                        (pending 0)))
                                                (lambda (client) #t)
                                                (string->utf8 (match watching
                                                                ((Some name)
                                                                 (page-first-frames host name))
                                                                ((None)
                                                                 (string-append "retry: 1000\n\n"
                                                                                (status-frame
                                                                                 host))))))
                                       (● host clients))))))

    ;; ---- Pages' event streams ----

    ;; What a browser target's pages hear of the latest attempt, with the
    ;; target's latest build: the reload client relinks a page when one is
    ;; published, and shows when one is under way or why one failed.

    (define (page-event (snapshot Snapshot) (application Application)) (→ String) (! fs)
      (bundle-event (string-append "/" (● application name) "/")
                    (match (● snapshot phase)
                      ((Succeeded) (BuildPublished))
                      ((Failed) (BuildFailed (diagnostic-text snapshot)))
                      ((Fatal) (BuildFailed (diagnostic-text snapshot)))
                      (_ (BuildUnderway)))
                    (match (● application builds)
                      ((Cons latest _) (Some latest))
                      ((Nil) (None)))))

    ;; Each diagnostic as a compiler prints it, after its place when it has
    ;; one.

    (define (diagnostic-text (snapshot Snapshot)) (→ String)
      (string-join (map (lambda (diagnostic)
                          (match (● diagnostic source)
                            ((Some point)
                             (string-append (● point file)
                                            ":"
                                            (show (● point line))
                                            ":"
                                            (show (● point column))
                                            ": "
                                            (● diagnostic message)))
                            ((None) (● diagnostic message))))
                        (● snapshot diagnostics))
                   "\n\n"))

    ;; An event as the browser's EventSource reads it. It is one line, as
    ;; the strings in it are written with their newlines escaped.

    (define (page-frame (text String)) (→ String)
      (string-append "data: " text "\n\n"))

    ;; A page's stream starts with its target's current event, so a page
    ;; that reconnects hears of the build it missed.

    (define (page-first-frames (host Host) (name String)) (→ String) (! fs)
      (let ((snapshot (● host snapshot)))
        (string-append "retry: 1000\n\n"
                       (page-frame (page-event snapshot
                                               (new Application (name name)
                                                    (builds (builds-of
                                                             (● snapshot publications)
                                                             name))))))))

    ;; Each browser target's pages hear its event when it changes.

    (define (told-pages (host Host)) (→ Host) (! mut tcp fs host)
      (fold-left (lambda (host application)
                   (let ((name (● application name))
                         (event (page-event (● host snapshot) application)))
                     (match (assoc-ref (● host told) name)
                       ((Some told) (if (string=? told event) host (told-page host name event)))
                       ((None) (told-page host name event)))))
                 host
                 (served-applications host)))

    ;; `event` to the pages of target `name`, kept as the last they heard.

    (define (told-page (host Host) (name String) (event String)) (→ Host) (! mut tcp host)
      (Host-clients-set
       (Host-told-set host
                      (Cons (new Pair (first name) (second event))
                            (filter (lambda (told) (not (string=? (● told first) name)))
                                    (● host told))))
       (sent-to (● host clients)
                (lambda (client)
                  (match (● client watching)
                    ((Some watched) (string=? watched name))
                    ((None) #f)))
                (string->utf8 (page-frame event)))))

    (define (option-some? (option (Option T))) (→ Bool) (∀ (T))
      (match option
        ((Some _) #t)
        ((None) #f)))

    (define (written (host Host) (id I64) (count I64)) (→ Host)
      (Host-clients-set host
                        (map (lambda (client)
                               (if (= (● client id) id)
                                   (Client-pending-set client (- (● client pending) count))
                                   client))
                             (● host clients))))

    ;; ---- Shutting down ----

    ;; No new work: the listener and every stream close, and the
    ;; resident's input ends, so it finishes the request it is answering
    ;; and exits, or is killed after 2 s.

    (define (shut-down (host Host) (rest (List Command))) (→ Host) (! mut tasks tcp process fs host)
      (close-listener (● host listener))
      (for-each (lambda (client) (mailbox-post (● client frames) (None))) (● host clients))
      (for-each (lambda (open) (close-connection (● open second)) (unit))
                (● host connections))
      (mailbox-post (● host requests) (None))
      (mailbox-post (● host disk) (Stopping))
      (let ((owner (● host owner)))
        (dispatch (lambda () (sleep 2000) (mailbox-post owner (Overdue)))))
      (resumed
       (Host-waiting-set (Host-connections-set (Host-stopping-set (Host-clients-set host (Nil))
                                                                  (Some rest))
                                               (Nil))
                         (+ (length (● host connections)) (if (● host resident-alive) 1 0)))))

    ;; A connection accepted while stopping is closed at once; its handler
    ;; still reports that it finished.

    (define (connected (host Host) (id I64) (connection Connection)) (→ Host) (! tcp)
      (match (● host stopping)
        ((Some _)
         (close-connection connection)
         (Host-waiting-set host (+ (● host waiting) 1)))
        ((None)
         (Host-connections-set host
                               (Cons (new Pair (first id) (second connection))
                                     (● host connections))))))

    ;; A finished handler's connection, and its event stream if it had one.

    (define (disconnected (host Host) (id I64)) (→ Host) (! mut tasks tcp process fs host)
      (match (● host stopping)
        ((Some _) (stopped-one host))
        ((None)
         (Host-clients-set (Host-connections-set host
                                                 (filter
                                                  (lambda (open) (not (= (● open first) id)))
                                                  (● host connections)))
                           (filter (lambda (client) (not (= (● client id) id)))
                                   (● host clients))))))

    ;; Once nothing is still stopping, the commands after Shutdown.

    (define (resumed (host Host)) (→ Host) (! mut tasks tcp process fs host)
      (match (● host stopping)
        ((Some rest)
         (if (= (● host waiting) 0)
             (perform-all (Host-stopping-set host (Some (Nil))) rest)
             host))
        ((None) host)))

    (define (stopped-one (host Host)) (→ Host) (! mut tasks tcp process fs host)
      (resumed (Host-waiting-set host (- (● host waiting) 1))))

    (define (resident-gone (host Host) (message String)) (→ Host) (! mut tasks tcp process fs host)
      (let ((host (Host-resident-alive-set host #f)))
        (match (● host stopping)
          ((Some _) (stopped-one host))
          ((None) (stepped host (ResidentExited message))))))

    (define (overdue (host Host)) (→ Host) (! process)
      (when (● host resident-alive)
        (send-signal (● host resident) (Kill))
        (unit))
      host)

    ;; ---- The disk ----

    ;; The project, the libraries and the browser host, leaving out build
    ;; output and Git's directory.

    (define (watched (setup Setup)) (→ (Pair (List String) (List String)))
      (let ((root (● setup root)) (project (● setup project)))
        (new Pair
          (first (list project (string-append root "/src") (string-append root "/host/browser")))
          (second (list (string-append project "/build")
                        (string-append project "/.git")
                        (string-append root "/build"))))))

    (define (take-inventory (setup Setup)) (→ (Result Inventory String)) (! fs)
      (let ((roots (watched setup)))
        (inventory (● roots first) (● roots second))))

    ;; The last complete inventory, and why the latest failed, if it did.
    (record Disk
      ((taken Inventory)
       (failure (Option String))))

    ;; Takes the first inventory as what is there, then one for each scan
    ;; asked, reporting what changed since the last. Hints from a watch of
    ;; each root ask for one at once; the timer asks each second, as a
    ;; watch can miss a change. After Stopping it closes the watches,
    ;; answers the timer that it is done, and ends.

    (define (scan-disk (setup Setup) (owner (Mailbox Message)) (requests (Mailbox Scan)))
      (→ Unit)
      (! mut tasks fs hints host)
      (let* ((roots (watched setup))
             (watches (watch-roots (● roots first) (● roots second) requests)))
        (let loop ((disk
                    (rescan setup owner (new Disk (taken (empty-inventory)) (failure (None))) #f))
                   (stopping #f))
          (match (mailbox-receive requests)
            ((Stopping)
             (for-each close-watch watches)
             (loop disk #t))
            ((Ticked reply)
             (mailbox-post reply (not stopping))
             (unless stopping (loop (rescan setup owner disk #t) #f)))
            ((Prompted) (loop (if stopping disk (rescan setup owner disk #t)) stopping))
            ((Reconciling)
             (let ((next (rescan setup owner disk #t)))
               (mailbox-post owner (Step (Reconciled (disk-result next (unit)))))
               (loop next stopping)))))))

    ;; What the latest inventory found, unless it failed.

    (define (disk-result (disk Disk) (value T))
      (→ (Result T String))
      (∀ (T))
      (match (● disk failure)
        ((Some message) (Err message))
        ((None) (Ok value))))

    ;; A watch of each root that can be watched, each with a task that
    ;; turns its hints into scans until it closes.

    (define (watch-roots (roots (List String)) (excluded (List String)) (disk (Mailbox Scan)))
      (→ (List Watch))
      (! mut hints host tasks)
      (match roots
        ((Nil) (Nil))
        ((Cons root rest)
         (match (watch-tree root excluded)
           ((Some watch)
            (dispatch (lambda () (relay-hints watch disk)))
            (Cons watch (watch-roots rest excluded disk)))
           ((None) (watch-roots rest excluded disk))))))

    (define (relay-hints (watch Watch) (disk (Mailbox Scan))) (→ Unit) (! mut tasks hints host)
      (when (next-hint watch)
        (mailbox-post disk (Prompted))
        (relay-hints watch disk)))

    ;; Another inventory, reported as what changed since the last complete
    ;; one when `report?`, as it is but for the first. A failure keeps the
    ;; last, and is reported once, when it begins; the next inventory that
    ;; succeeds reports the recovery, after what changed meanwhile.

    (define (rescan (setup Setup) (owner (Mailbox Message)) (disk Disk) (report? Bool))
      (→ Disk)
      (! mut fs)
      (match (take-inventory setup)
        ((Ok next)
         (let ((changes (inventory-changes (● disk taken) next)))
           (when (and report? (not (null? changes)))
             (mailbox-post owner (Step (Touched changes))))
           (when (option-some? (● disk failure))
             (mailbox-post owner (Step (Uncertain (None)))))
           (new Disk (taken next) (failure (None)))))
        ((Err message)
         (unless (option-some? (● disk failure))
           (mailbox-post owner (Step (Uncertain (Some message)))))
         (Disk-failure-set disk (Some message)))))

    ;; A scan each second, until the disk task stops.

    (define (tick (disk (Mailbox Scan))) (→ Unit) (! mut tasks host)
      (sleep 1000)
      (let ((reply (make-mailbox)))
        (mailbox-post disk (Ticked reply))
        (when (mailbox-receive reply)
          (tick disk))))

    ;; ---- The resident ----

    (define (resident-process (setup Setup)) (→ Process) (! tasks process)
      (match (spawn (new ProcessCommand (program (● setup node))
                         (arguments (list "--no-warnings"
                                          (runner setup)
                                          (● setup cli)
                                          (● setup root)
                                          (● setup runtime)
                                          "resident"
                                          (● setup project)))
                         (directory ".")))
        ((Ok process) process)
        ((Err error)
         (panic (string-append "cannot start the resident builder: "
                               (● error code))))))

    ;; One request a line, until the input ends.

    (define (write-requests (resident Process) (requests (Mailbox (Option String))))
      (→ Unit)
      (! mut tasks process)
      (match (mailbox-receive requests)
        ((Some line)
         (match (write-all resident (string->utf8 (string-append line "\n")))
           ((Ok _) (write-requests resident requests))
           ((Err _) (unit))))
        ((None)
         (close-input resident)
         (unit))))

    (define (write-all (child Process) (bytes Bytes))
      (→ (Result Unit ProcessError))
      (! tasks process)
      (if (= (vector-length bytes) 0)
          (Ok (unit))
          (match (write-input child bytes)
            ((Ok count)
             (write-all child (subvector bytes (i32->i64 count) (vector-length bytes))))
            ((Err error) (Err error)))))

    ;; Each reply line, as the message it is. `pending` holds the bytes of a
    ;; line not yet ended, newest chunk first.

    (define (read-replies (resident Process) (owner (Mailbox Message)) (pending (List Bytes)))
      (→ Unit)
      (! mut tasks process host)
      (match (read-output resident (Stdout) 65536)
        ((Ok (Some bytes)) (read-replies resident owner (post-lines owner (Cons bytes pending))))
        (_ (unit))))

    ;; Posts each whole line in the chunks, and keeps what follows the last.

    (define (post-lines (owner (Mailbox Message)) (pending (List Bytes)))
      (→ (List Bytes))
      (! mut host)
      (let* ((bytes (vector-concatenate (reverse pending))) (end (vector-index-of bytes 10)))
        (match end
          ((Some at)
           (mailbox-post owner (reply-message (subvector bytes 0 at)))
           (post-lines owner (list (subvector bytes (+ at 1) (vector-length bytes)))))
          ((None) (list bytes)))))

    (define (vector-index-of (bytes Bytes) (code I32)) (→ (Option I64))
      (let loop ((index 0))
        (cond ((= index (vector-length bytes)) (None))
              ((= (u8->i32 (vector-ref bytes index)) code) (Some index))
              (else (loop (+ index 1))))))

    ;; A reply, by the members it has: a build's diagnostics, a
    ;; publication's error, or a discard's epoch alone. One that is not
    ;; JSON is the resident failing.

    (define (reply-message (line Bytes)) (→ Message)
      (match (match (utf8->string line)
               ((Ok text) (string->json text))
               ((Err _) (None)))
        ((Some json)
         (match (json-member json "epoch")
           ((Some (JsonInteger epoch)) (epoch-reply json epoch))
           (_ (Step (ResidentExited "the resident builder replied without an epoch")))))
        ((None)
         (Step (ResidentExited "the resident builder replied with something other than JSON")))))

    (define (epoch-reply (json Json) (epoch I64)) (→ Message)
      (cond ((option-some? (json-member json "diagnostics"))
             (Built epoch (json->reply json) (candidate-targets json)))
            ((option-some? (json-member json "error"))
             (Step (PublishReplied epoch (match (json-member json "error")
                                           ((Some (JsonString message)) (Some message))
                                           (_ (None))))))
            (else (Step (DiscardReplied epoch)))))

    ;; Reads what the resident writes to stderr, a panic's message, then
    ;; waits for it to exit, which the end of stderr means is near.

    (define (await-resident (resident Process) (owner (Mailbox Message)) (tail (List Bytes)))
      (→ Unit)
      (! mut tasks process host)
      (match (read-output resident (Stderr) 65536)
        ((Ok (Some bytes)) (await-resident resident owner (Cons bytes tail)))
        (_
         (mailbox-post owner
                       (ResidentGone (string-append "the resident builder exited with "
                                                    (exit-text (wait-exit resident))
                                                    (stderr-text tail)))))))

    (define (exit-text (exit (Result Exit ProcessError))) (→ String)
      (match exit
        ((Ok (Exited code)) (string-append "status " (show code)))
        ((Ok (Signaled name)) name)
        ((Err error) (● error code))))

    ;; The last 4096 bytes written, trimmed, after a colon.

    (define (stderr-text (tail (List Bytes))) (→ String)
      (let* ((bytes (vector-concatenate (reverse tail)))
             (start (max 0 (- (vector-length bytes) 4096)))
             (text (match (utf8->string (subvector bytes start (vector-length bytes)))
                     ((Ok text) (trimmed text))
                     ((Err _) ""))))
        (if (string=? text "") "" (string-append ": " text))))

    (define (trimmed (text String)) (→ String)
      (let loop ((start 0) (end (string-length text)))
        (cond
         ((and (< start end) (char-whitespace? (string-ref text start))) (loop (+ start 1) end))
         ((and (< start end) (char-whitespace? (string-ref text (- end 1))))
          (loop start (- end 1)))
         (else (substring text start end)))))

    ;; ---- The resident's replies ----

    (define (json->reply (json Json)) (→ Reply)
      (new Reply (description (match (json-object json "description")
                                ((Some description) (Some (json->description description)))
                                ((None) (None))))
           (candidate (match (json-object json "candidate")
                        ((Some candidate) (Some (json->candidate candidate)))
                        ((None) (None))))
           (diagnostics (map json->diagnostic (json-items json "diagnostics")))))

    (define (json->description (json Json)) (→ Description)
      (let ((builds (json-items json "builds")))
        (new Description (entries (map (lambda (build) (json-text build "entry")) builds))
             (publics (fold-right (lambda (build publics)
                                    (match (json-member build "public")
                                      ((Some (JsonString path)) (Cons path publics))
                                      (_ publics)))
                                  (Nil)
                                  builds))
             (browsers (map (lambda (build) (json-text build "name"))
                            (filter (lambda (build) (string=? (json-text build "kind") "browser"))
                                    builds))))))

    (define (json->candidate (json Json)) (→ Candidate)
      (new Candidate (description (match (json-member json "description")
                                    ((Some description) (json->description description))
                                    ((None)
                                     (new Description
                                       (entries (Nil))
                                       (publics (Nil))
                                       (browsers (Nil))))))
           (generations (map (lambda (target)
                               (new Generation (name (json-text target "name"))
                                    (directory (json-text target "directory"))
                                    (files (match (json-member target "files")
                                             ((Some (JsonObject members))
                                              (map (lambda (member)
                                                     (new Pair (first (● member first))
                                                          (second
                                                           (json-string-value (● member second)))))
                                                   members))
                                             (_ (Nil))))
                                    (linked (map json-string-value (json-items target "linked")))))
                             (json-items json "targets")))
           (milliseconds (json-integer json "milliseconds"))))

    ;; The candidate's targets as the status shows them.

    (define (candidate-targets (json Json)) (→ Json)
      (match (json-member json "candidate")
        ((Some candidate)
         (JsonArray (map (lambda (target)
                           (JsonObject (fold-right (lambda (name kept)
                                                     (match (json-member target name)
                                                       ((Some value)
                                                        (Cons (new Pair (first name) (second value))
                                                              kept))
                                                       ((None) kept)))
                                                   (Nil)
                                                   (list "name"
                                                         "directory"
                                                         "digest"
                                                         "compiled"))))
                         (json-items candidate "targets"))))
        ((None) (JsonArray (Nil)))))

    (define (json->diagnostic (json Json)) (→ Diagnostic)
      (new Diagnostic (message (json-text json "message"))
           (source (match (json-object json "source")
                     ((Some source)
                      (Some (new SourcePoint (file (json-text source "file"))
                                 (line (json-integer source "line"))
                                 (column (json-integer source "column")))))
                     ((None) (None))))))

    ;; A member that is an object, as a null one is not.

    (define (json-object (json Json) (name String)) (→ (Option Json))
      (match (json-member json name)
        ((Some (JsonObject members)) (Some (JsonObject members)))
        (_ (None))))

    (define (json-items (json Json) (name String)) (→ (List Json))
      (match (json-member json name)
        ((Some (JsonArray items)) items)
        (_ (Nil))))

    (define (json-text (json Json) (name String)) (→ String)
      (match (json-member json name)
        ((Some value) (json-string-value value))
        ((None) "")))

    (define (json-string-value (json Json)) (→ String)
      (match json
        ((JsonString text) text)
        (_ "")))

    (define (json-integer (json Json) (name String)) (→ I64)
      (match (json-member json name)
        ((Some (JsonInteger value)) value)
        (_ 0)))

    ;; ---- HTTP ----

    ;; One handler task for each connection.

    (define (accept-connections (listener Listener)
                                (owner (Mailbox Message))
                                (setup Setup))
      (→ Unit)
      (! mut tasks tcp fs host)
      (let loop ((id 0))
        (match (accept listener)
          ((Ok connection)
           (mailbox-post owner (Connected id connection))
           (dispatch (lambda ()
                       (serve-connection setup listener owner id connection)
                       (mailbox-post owner (Disconnected id))))
           (loop (+ id 1)))
          ((Err _) (unit)))))

    (define (security-headers) (→ (List Header))
      (list (new Header (name "Cache-Control") (value "no-store"))
            (new Header (name "X-Content-Type-Options") (value "nosniff"))
            (new Header (name "X-Frame-Options") (value "DENY"))))

    (define (json-response (status I32) (body Json)) (→ Response)
      (new Response (status status)
           (headers
            (Cons (new Header (name "Content-Type") (value "application/json")) (security-headers)))
           (body (if (= status 204) (empty-bytes) (string->utf8 (json->string body))))))

    (define (message->json (message String)) (→ Json)
      (JsonObject (list (new Pair (first "message") (second (JsonString message))))))

    (define (refused (status I32) (message String)) (→ Response)
      (json-response status (message->json message)))

    (define (empty-bytes) (→ Bytes)
      (make-vector 0 (i32->u8 0)))

    ;; A connection's one request, by the connection's number.

    (define (serve-connection (setup Setup)
                              (listener Listener)
                              (owner (Mailbox Message))
                              (id I64)
                              (connection Connection))
      (→ Unit)
      (! mut tasks tcp fs host)
      (match (read-request connection)
        ((Ok request)
         (let ((head (● request head)))
           (match (route setup listener owner id connection request)
             ((Some response) (finish-exchange connection (Some (● head method)) response))
             ((None) (unit)))))
        ((Err error) (finish-exchange connection (None) (exchange-refusal error)))))

    (define (finish-exchange (connection Connection) (method (Option String)) (response Response))
      (→ Unit)
      (! tcp tasks)
      (match (ann (respond connection 2000 method response) (Result Unit (ExchangeError Unit)))
        ((Ok _) (unit))
        ((Err _) (close-connection connection) (unit))))

    (define (exchange-refusal (error (ExchangeError Unit))) (→ Response)
      (match error
        ((ProtocolFailure (Unsupported "Transfer-Encoding"))
         (refused 411 "requests must give a Content-Length, not a Transfer-Encoding"))
        ((ProtocolFailure (HeadTooLarge)) (refused 431 "the request head is too large"))
        ((ProtocolFailure (BodyTooLarge)) (refused 413 "request exceeds 8 MiB"))
        (_ (refused 400 "malformed request"))))

    ;; Only for this service's own host, so a page of another site that
    ;; rebinds a name to this address reaches nothing. A browser target's
    ;; files are only read, and a build is asked for without a body. None
    ;; for an event stream, which this task then writes until it ends.

    (define (route (setup Setup)
                   (listener Listener)
                   (owner (Mailbox Message))
                   (id I64)
                   (connection Connection)
                   (request Request))
      (→ (Option Response))
      (! mut tasks tcp fs host)
      (let* ((head (● request head)) (method (● head method)))
        (cond ((not (same-strings? (header-values (● head headers) "host")
                                   (list (listener-host listener))))
               (Some (refused 403 "unexpected host")))
              (else
               (match (parse-target (● head target))
                 ((Err _) (Some (refused 400 "malformed request target")))
                 ((Ok target) (serve-path setup owner id connection request (● target path))))))))

    (define (serve-path (setup Setup)
                        (owner (Mailbox Message))
                        (id I64)
                        (connection Connection)
                        (request Request)
                        (path (List String)))
      (→ (Option Response))
      (! mut tasks tcp fs host)
      (let ((method (● (● request head) method)))
        (match path
          ((Cons ".snail" (Cons "build" (Nil)))
           (Some (if (string=? method "POST")
                     (build-requested request owner)
                     (refused 405 "a build is asked for with POST"))))
          (_
           (cond ((not (or (string=? method "GET") (string=? method "HEAD")))
                  (Some (refused 405 "the service only serves reads, and builds")))
                 (else (serve-read setup owner id connection path)))))))

    (define (serve-read (setup Setup)
                        (owner (Mailbox Message))
                        (id I64)
                        (connection Connection)
                        (path (List String)))
      (→ (Option Response))
      (! mut tasks tcp fs host)
      (match path
        ((Cons ".snail" (Cons "status" (Nil)))
         (Some (asking owner (lambda (reply) (Status reply)))))
        ((Cons ".snail" (Cons "events" (Nil)))
         (stream-events owner id connection (None))
         (None))
        ((Cons name (Cons ".snail" (Cons "events" (Nil))))
         (stream-events owner id connection (Some name))
         (None))
        (path (Some (application-file setup owner path)))))

    ;; A build takes no body; the owner answers it once the step has.

    (define (build-requested (request Request) (owner (Mailbox Message))) (→ Response) (! mut tasks)
      (if (> (vector-length (● request body)) 0)
          (refused 400 "a build takes no request body")
          (asking owner (lambda (reply) (Ask (RequestBuild) reply)))))

    (define (asking (owner (Mailbox Message)) (message (Fn (Mailbox Answer) → Message ! mut)))
      (→ Response)
      (! mut tasks)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (message reply))
        (let ((answer (mailbox-receive reply)))
          (json-response (● answer status) (● answer body)))))

    ;; The target `/`, which parses as no segment or one empty one.

    (define (root-path? (path (List String))) (→ Bool)
      (match path
        ((Nil) #t)
        ((Cons "" (Nil)) #t)
        (_ #f)))

    (define (same-strings? (left (List String)) (right (List String))) (→ Bool)
      (and (= (length left) (length right))
           (every? (lambda (pair) (string=? (● pair first) (● pair second)))
                   (zip left right))))

    ;; ---- Browser targets ----

    ;; `/` lists the browser targets, and /NAME/ serves one's builds.

    (define (application-file (setup Setup) (owner (Mailbox Message)) (path (List String)))
      (→ Response)
      (! mut tasks fs)
      (let ((reply (make-mailbox)))
        (mailbox-post owner (Applications reply))
        (let ((applications (mailbox-receive reply)))
          (match (if (root-path? path) (Nil) path)
            ((Nil) (application-index applications))
            ((Cons name rest)
             (match (find (lambda (application) (string=? (● application name) name))
                          applications)
               ((Some application)
                (bundle-response (string-append "/" name "/")
                                 (new Reloading
                                   (host (string-append (● setup root) "/host/browser"))
                                   (program (● setup client)))
                                 (● application builds)
                                 rest))
               ((None) (refused 404 (string-append "no browser target " name)))))))))

    (define (application-index (applications (List Application))) (→ Response)
      (new Response (status 200)
           (headers (Cons (new Header (name "Content-Type") (value "text/html; charset=utf-8"))
                          (security-headers)))
           (body (string->utf8
                  (string-append
                   "<!doctype html>\n<meta charset=\"utf-8\">\n<title>Browser targets</title>\n"
                   (if (null? applications)
                       "<p>No browser target is built yet.</p>\n"
                       (string-concatenate
                        (map (lambda (application)
                               (let ((name (html-text (● application name))))
                                 (string-append "<p><a href=\"/" name "/\">" name "</a></p>\n")))
                             applications))))))))

    (define (html-text (text String)) (→ String)
      (string-concatenate
       (map (lambda (char)
              (cond ((char=? char #\<) "&lt;")
                    ((char=? char #\>) "&gt;")
                    ((char=? char #\&) "&amp;")
                    ((char=? char #\") "&quot;")
                    (else (make-string 1 char))))
            (string->list text))))

    ;; ---- Writing an event stream ----

    ;; Joins the owner's streams, then writes each frame it sends until it
    ;; sends none, or a write fails. The handler's end tells the owner the
    ;; stream has gone.

    (define (stream-events (owner (Mailbox Message))
                           (id I64)
                           (connection Connection)
                           (watching (Option String)))
      (→ Unit)
      (! mut tasks tcp host)
      (let ((frames (make-mailbox)) (reply (make-mailbox)))
        (mailbox-post owner (Joined id watching connection frames reply))
        (let ((answer (mailbox-receive reply)))
          (if (= (● answer status) 200)
              (match (encode-stream-head 200
                                         (Cons (new Header
                                                 (name "Content-Type")
                                                 (value "text/event-stream"))
                                               (security-headers)))
                ((Ok head) (when (sent? connection head) (write-frames owner id connection frames)))
                ((Err _) (unit)))
              (finish-exchange connection
                               (Some "GET")
                               (json-response (● answer status) (● answer body)))))))

    (define (write-frames (owner (Mailbox Message))
                          (id I64)
                          (connection Connection)
                          (frames (Mailbox (Option Bytes))))
      (→ Unit)
      (! mut tasks tcp host)
      (match (mailbox-receive frames)
        ((Some bytes)
         (if (sent? connection bytes)
             (begin
               (mailbox-post owner (Written id (vector-length bytes)))
               (write-frames owner id connection frames))
             (begin
               (close-connection connection)
               (unit))))
        ((None) (close-connection connection) (unit))))

    (define (sent? (connection Connection) (bytes Bytes)) (→ Bool) (! tasks tcp)
      (if (= (vector-length bytes) 0)
          #t
          (match (write connection bytes)
            ((Ok count)
             (and (> count 0)
                  (sent? connection (subvector bytes (i32->i64 count) (vector-length bytes)))))
            ((Err _) #f))))))
