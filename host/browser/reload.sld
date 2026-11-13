;; The reload client: the part of a page that `snail dev` adds
;; ((snail shell project bundle)). It compares the manifest of the build
;; the page runs with the one each of the server's events carries, and
;; decides what the page does: fetch a style sheet again, relink the
;; program from the first module that changed or links a file that did,
;; reload the page, or show a notice. It runs as WebAssembly; the page
;; (host/browser/reload.mjs) passes it the
;; page's manifest and each event, a character at a time, and
;; host/browser/reload-client.mjs performs the `page` effect's commands.
(import
 (snail core base)
 (rename (snail shell compiler read) (Failed ParseFailed)))

;; ---- Page commands ----

;; A command is a name with string arguments, sent a character at a time,
;; and a number.
(effect page
  ((argument-character (Fn Char → Unit))
   (argument-end (Fn → Unit))
   (command (Fn I32 → I32)))
  (default
    ((argument-character host-argument-character)
     (argument-end host-argument-end)
     (command host-command))))

(extern host-argument-character "snail.page" "argument-character" (Fn Char → Unit))
(extern host-argument-end "snail.page" "argument-end" (Fn → Unit))
(extern host-command "snail.page" "command" (Fn I32 → I32))

(define (page-command (name String) (arguments (List String)) (number I32)) (→ Unit) (! page)
  (for-each send-argument (Cons name arguments))
  (command number)
  (unit))

(define (send-argument (text String)) (→ Unit) (! page)
  (let loop ((index 0))
    (when (< index (string-length text))
      (argument-character (string-ref text index))
      (loop (+ index 1))))
  (argument-end))

;; The commands, as host/browser/reload-client.mjs names them. A notice is
;; lasting, a failure, or brief.
(define lasting (→ I32) 0)

(define failure (→ I32) 1)

(define brief (→ I32) 2)

(define (notice! (text String) (kind I32)) (→ Unit) (! page)
  (page-command "notice" (list text) kind))

(define (hide!) (→ Unit) (! page)
  (page-command "hide" (Nil) 0))

;; Fetches a style sheet again, with its digest, from `base`, the build it
;; now belongs to.
(define (restyle! (file String) (digest String) (base String)) (→ Unit) (! page)
  (page-command "restyle" (list file digest base) 0))

;; Relinks the program from `module`, by the modules.json under `base`,
;; with a fresh state when `fresh`; the page reports how it went.
(define (relink! (module String) (base String) (fresh Bool)) (→ Unit) (! page)
  (page-command "relink" (list module (string-append base "modules.json")) (if fresh 1 0)))

;; Stores every application's save, then reloads the page.
(define (reload-page!) (→ Unit) (! page)
  (page-command "reload" (Nil) 0))

;; Shows a failure with a button that calls `reload_start_over`.
(define (offer-fresh-start! (text String)) (→ Unit) (! page)
  (page-command "offer-fresh-start" (list text) 0))

;; ---- Manifests ----

;; What a build serves: the base its files are served under, each file with
;; a digest, and each module, in program order, with the digest of its
;; bytes.
(struct Manifest
  ((base String)
   (files (List (Pair String String)))
   (modules (List (Pair String String)))))

(enum Event
  (Building ((manifest Manifest)))
  (Built ((milliseconds String) (manifest Manifest)))
  (Failed ((message String) (manifest Manifest))))

;; `(base BASE) (files (NAME DIGEST) ...) (modules (NAME DIGEST) ...)`.
(define (parse-manifest (data (List Syntax))) (→ Manifest)
  (match data
    ((Cons base (Cons files (Cons modules (Nil))))
     (Manifest (base-of base) (string-pairs "files" files) (string-pairs "modules" modules)))
    (_ (panic "reload: a manifest is (base ...) (files ...) (modules ...)"))))

(define (base-of (syntax Syntax)) (→ String)
  (match syntax
    ((Form (Cons (Ident "base" _ _) (Cons (Atom (DString base) _) (Nil))) _) base)
    (_ (panic "reload: expected (base BASE)"))))

(define (string-pairs (label String) (syntax Syntax)) (→ (List (Pair String String)))
  (match syntax
    ((Form (Cons (Ident tag _ _) entries) _)
     (unless (string=? label tag) (panic (string-append "reload: expected " label)))
     (map string-pair entries))
    (_ (panic "reload: expected a list of pairs"))))

(define (string-pair (syntax Syntax)) (→ (Pair String String))
  (match syntax
    ((Form (Cons (Atom (DString name) _) (Cons (Atom (DString value) _) (Nil))) _)
     (Pair name value))
    (_ (panic "reload: expected string NAME and VALUE"))))

;; `(building MANIFEST)`, `(built MILLISECONDS MANIFEST)` or
;; `(failed MESSAGE MANIFEST)`.

(define (parse-event (text String)) (→ Event)
  (match (read-data text)
    ((Cons (Form (Cons (Ident tag _ _) rest) _) (Nil)) (event-body tag rest))
    (_ (panic "reload: expected one event"))))

(define (event-body (name String) (rest (List Syntax))) (→ Event)
  (if (string=? name "building") (Building (parse-manifest rest))
      (match (Pair name rest)
        ((Pair "built" (Cons (Atom (DInt milliseconds) _) manifest))
         (Built (show milliseconds) (parse-manifest manifest)))
        ((Pair "failed" (Cons (Atom (DString message) _) manifest))
         (Failed message (parse-manifest manifest)))
        (_ (panic (string-append "reload: invalid " name " event"))))))

(define (parse-page-manifest (text String)) (→ Manifest)
  (parse-manifest (read-data text)))

(define (read-data (text String)) (→ (List Syntax))
  (match (compiling (lambda () (read-text text "<reload>")))
    ((Ok forms) forms)
    ((Err (ParseFailed diagnostics)) (panic (diagnostics->string diagnostics)))
    ((Err (Requested _)) (panic "reload: reading cannot request generated input"))))

(define (same-manifest? (a Manifest) (b Manifest)) (→ Bool)
  (and (same-pairs? (● a files) (● b files))
       (same-pairs? (● a modules) (● b modules))))

(define (same-pairs? (a (List (Pair String String))) (b (List (Pair String String)))) (→ Bool)
  (and (= (length a) (length b))
       (every? (lambda (pair)
                 (and (string=? (● (● pair first) first) (● (● pair second) first))
                      (string=? (● (● pair first) second) (● (● pair second) second))))
               (zip a b))))

(define (event-manifest (event Event)) (→ Manifest)
  (match event
    ((Building manifest) manifest)
    ((Built _ manifest) manifest)
    ((Failed _ manifest) manifest)))

;; ---- Changes ----

;; The files whose digests differ, including files only one side has.
(define (changed-files (old Manifest) (new Manifest)) (→ (List String))
  (delete-duplicates string=?
                     (append (differing (● old files) (● new files))
                             (differing (● new files) (● old files)))))

(define (differing (these (List (Pair String String))) (those (List (Pair String String))))
  (→ (List String))
  (map (lambda (record) (● record first))
       (filter (lambda (entry) (match (assoc-ref those (● entry first))
                                 ((Some digest)
                                  (not (string=? digest (● entry second))))
                                 ((None) #t)))
               these)))

;; The first module, in program order, whose digest differs; the modules
;; before it cannot import from it, so they stay linked. A module's bytes
;; name the digest of each file it links, so editing a linked file changes
;; the module that links it.
(define (first-changed-module (old Manifest) (new Manifest)) (→ (Option String))
  (let loop ((old (● old modules)) (new (● new modules)))
    (match new
      ((Cons (Pair name digest) rest)
       (match old
         ((Cons (Pair old-name old-digest) old-rest)
          (if (and (string=? name old-name) (string=? digest old-digest))
              (loop old-rest rest)
              (Some name)))
         ((Nil) (Some name))))
      ((Nil) (None)))))

;; A style sheet is fetched again in place; any other file changes the
;; page, which must load again. Modules and linked files are named for
;; their contents, so the build reports neither.
(define (style-sheet? (file String)) (→ Bool)
  (let ((length (string-length file)))
    (and (> length 4) (string=? (substring file (- length 4) length) ".css"))))

;; ---- Decisions ----

;; `loaded` is the manifest of what the page runs, which changes only when a
;; relink succeeds. While one is in flight, `relinking` holds its target and
;; `pending` the latest event since, which waits for it. `refused` is a
;; target whose program could not take over the state, so it is not tried
;; again until the developer starts over.

(struct ReloadState
  ((loaded Manifest)
   (relinking (Option Manifest))
   (pending (Option Event))
   (refused (Option Manifest))
   (last-time String)
   (input (List Char))))
(define (make-reload-state) (→ ReloadState)
  (ReloadState (Manifest "" (Nil) (Nil)) (None) (None) (None) "" (Nil)))

(expose make-reload-state "reload_create")

(define (receive! (state ReloadState) (event Event)) (→ Unit) (! mut page)
  (remember-time! state event)
  (match (● state relinking)
    ((Some _) (set! (● state pending) (Some event)))
    ((None) (apply-event! state event))))

(define (apply-event! (state ReloadState) (event Event)) (→ Unit) (! mut page)
  (let* ((manifest (event-manifest event)) (files (changed-files (● state loaded) manifest)))
    (cond ((refused? state manifest) (unit))
          ((any? (lambda (file) (not (style-sheet? file))) files) (reload-page!))
          (else (for-each (lambda (file)
                            (restyle! file (digest-of manifest file) (● manifest base)))
                          (filter style-sheet? files))
                (match (first-changed-module (● state loaded) manifest)
                  ((Some module)
                   (set! (● state relinking) (Some manifest))
                   (relink! module (● manifest base) #f))
                  ((None)
                   (set! (● state loaded) manifest)
                   (show! state event (not (null? files)))))))))

(define (refused? (state ReloadState) (manifest Manifest)) (→ Bool)
  (match (● state refused)
    ((Some target) (same-manifest? target manifest))
    ((None) #f)))

(define (digest-of (manifest Manifest) (file String)) (→ String)
  (match (assoc-ref (● manifest files) file)
    ((Some digest) digest)
    ((None) "")))

(define (remember-time! (state ReloadState) (event Event)) (→ Unit) (! mut)
  (match event
    ((Built milliseconds _) (set! (● state last-time) milliseconds))
    (_ (unit))))

(define (show! (state ReloadState) (event Event) (changed Bool)) (→ Unit) (! page)
  (match event
    ((Building _) (notice! "Building..." lasting))
    ((Built _ _) (if changed (notice! (reloaded state) brief) (hide!)))
    ((Failed message _) (notice! message failure))))

(define (reloaded (state ReloadState)) (→ String)
  (string-append "Reloaded, built in " (● state last-time) " ms"))

;; A relink that failed leaves the old program running; starting over with
;; the new one is the developer's choice. Either way, the event that waited
;; is applied next.
(define (relinked! (state ReloadState) (ok Bool) (message String)) (→ Unit) (! mut page)
  (match (● state relinking)
    ((Some target)
     (set! (● state relinking) (None))
     (if ok
         (begin
           (set! (● state loaded) target)
           (set! (● state refused) (None))
           (notice! (reloaded state) brief))
         (begin (set! (● state refused) (Some target))
                (offer-fresh-start!
                 (string-append
                  "The new program could not take over the running state; the old one is still running.\n\n"
                  message)))))
    ((None) (unit)))
  (apply-pending! state))

(define (apply-pending! (state ReloadState)) (→ Unit) (! mut page)
  (match (● state pending)
    ((Some event) (set! (● state pending) (None)) (receive! state event))
    ((None) (unit))))

;; Relinks the refused program from its first module with a fresh state.
(define (start-over! (state ReloadState)) (→ Unit) (! mut page)
  (match (Pair (● state refused) (● state relinking))
    ((Pair (Some target) (None))
     (match (● target modules)
       ((Cons (Pair first _) _)
        (set! (● state relinking) (Some target))
        (relink! first (● target base) #t))
       ((Nil) (unit))))
    (_ (unit))))

;; An uncaught error in the page, such as a trap, with the lines the
;; program last wrote to standard error. A trap during a display frame
;; stops the clock with the state from before it; the next build that
;; relinks the program resumes it.
(define (page-error! (message String) (stopped Bool)) (→ Unit) (! page)
  (notice! (if stopped
               (string-append message
                              "\n\nThe application stopped. Fix it and save: the next build resumes from the state before the trap.")
               message)
           failure))

;; ---- Entry points ----

(define (take-input (state ReloadState)) (→ String) (! mut)
  (let ((text (list->string (reverse (● state input)))))
    (set! (● state input) (Nil))
    text))

(define (reload-character (state ReloadState) (code I32)) (→ Unit) (! mut)
  (set! (● state input) (Cons (i32->char code) (● state input))))

;; The page's own manifest first, then each event; the page reports each
;; relink, with its error, each uncaught error, with whether the clock
;; stopped, and the developer's choice to start over.
(define (reload-start (state ReloadState)) (→ Unit) (! mut)
  (set! (● state loaded) (parse-page-manifest (take-input state))))

(define (reload-event (state ReloadState)) (→ Unit) (! mut page)
  (receive! state (parse-event (take-input state))))

(define (reload-relinked (state ReloadState) (status I32)) (→ Unit) (! mut page)
  (relinked! state (= status 0) (take-input state)))

(define (reload-page-error (state ReloadState) (stopped I32)) (→ Unit) (! mut page)
  (page-error! (take-input state) (not (= stopped 0))))

(define (reload-start-over (state ReloadState)) (→ Unit) (! mut page)
  (start-over! state))

(expose reload-character "reload_character")
(expose reload-start "reload_start")
(expose reload-event "reload_event")
(expose reload-relinked "reload_relinked")
(expose reload-page-error "reload_page_error")
(expose reload-start-over "reload_start_over")
