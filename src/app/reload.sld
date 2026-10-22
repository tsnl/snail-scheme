;; The reload client: the part of a page that `lofi serve` adds. It compares
;; the manifest of the build the page runs with the one each of the
;; server's events carries, and decides what the page does: fetch a style
;; sheet again, relink the program from the first module that changed,
;; reload the page, or show a notice. It runs as WebAssembly;
;; src/app/reload.mjs passes it the page's manifest and each event, a
;; character at a time, and performs the `page` effect's commands.
(import
 (lofi base)
 (lofi datum)
 (lofi read)
 (lofi write))

;; ---- Page commands ----

;; A command is a number with string arguments, sent a character at a
;; time, and a number.
(effect page
  ((argument-character (-> Char Unit))
   (argument-end (-> Unit))
   (command (-> I32 I32 I32)))
  (host "snail.page"
        ((argument-character "argument-character")
         (argument-end "argument-end")
         (command "command"))))

(: page-command (-> I32 (List String) I32 Unit ! page))
(define (page-command code arguments number)
  (for-each send-argument arguments)
  (command code number)
  (unit))

(: send-argument (-> String Unit ! page))
(define (send-argument text)
  (let loop ((index 0))
    (when (< index (string-length text))
      (argument-character (string-ref text index))
      (loop (+ index 1))))
  (argument-end))

;; The commands, numbered as src/app/reload.mjs numbers them. A notice is
;; lasting, a failure, or brief.
(: lasting I32)
(define lasting 0)

(: failure I32)
(define failure 1)

(: brief I32)
(define brief 2)

(: notice! (-> String I32 Unit ! page))
(define (notice! text kind)
  (page-command 1 (list text) kind))

(: hide! (-> Unit ! page))
(define (hide!)
  (page-command 2 (Nil) 0))

(: restyle! (-> String String Unit ! page))
(define (restyle! file digest)
  (page-command 3 (list file digest) 0))

;; Relinks the program from `module`; the page reports how it went.
(: relink! (-> String Unit ! page))
(define (relink! module)
  (page-command 4 (list module) 0))

;; Stores every application's save, then reloads the page.
(: reload-page! (-> Unit ! page))
(define (reload-page!)
  (page-command 5 (Nil) 0))

;; Shows a failure with a button that relinks the whole program with a
;; fresh state.
(: offer-fresh-start! (-> String Unit ! page))
(define (offer-fresh-start! text)
  (page-command 6 (list text) 0))

;; ---- Manifests ----

;; What a build serves: each file with a digest, and each module, in
;; program order, with the file it lives in, which names its text.
(struct Manifest
  ((files (List (Pair String String)))
   (modules (List (Pair String String)))))

(enum Event
  (Building ((manifest Manifest)))
  (Built ((milliseconds String) (manifest Manifest)))
  (Failed ((message String) (manifest Manifest))))

;; `(files (NAME DIGEST) ...) (modules (NAME FILE) ...)`.
(: parse-manifest (-> (List Datum) Manifest))
(define (parse-manifest data)
  (match data
    ((Cons files (Cons modules (Nil))) (Manifest (string-pairs files) (string-pairs modules)))
    (_ (panic "reload: a manifest is (files ...) (modules ...)"))))

(: string-pairs (-> Datum (List (Pair String String))))
(define (string-pairs datum)
  (match (datum->list datum)
    ((Some (Cons _ entries)) (map string-pair entries))
    (_ (panic "reload: expected a list of pairs"))))

(: string-pair (-> Datum (Pair String String)))
(define (string-pair datum)
  (match datum
    ((PairDatum (StringDatum name) (PairDatum (StringDatum value) (NullDatum))) (Pair name value))
    (_ (panic (string-append "reload: expected (NAME VALUE), got " (datum->string datum))))))

;; `(building MANIFEST)`, `(built MILLISECONDS MANIFEST)` or
;; `(failed MESSAGE MANIFEST)`.
(: parse-event (-> String Event))
(define (parse-event text)
  (match (read-datums text)
    ((Ok (Cons event (Nil)))
     (match (datum->list event)
       ((Some (Cons (SymbolDatum "building") manifest)) (Building (parse-manifest manifest)))
       ((Some (Cons (SymbolDatum "built") (Cons milliseconds manifest))) (Built (datum->display-string milliseconds) (parse-manifest manifest)))
       ((Some (Cons (SymbolDatum "failed") (Cons (StringDatum message) manifest))) (Failed message (parse-manifest manifest)))
       (_ (panic (string-append "reload: an unknown event " text)))))
    (_ (panic (string-append "reload: an unreadable event " text)))))

(: parse-page-manifest (-> String Manifest))
(define (parse-page-manifest text)
  (match (read-datums text)
    ((Ok data) (parse-manifest data))
    ((Err message) (panic (string-append "reload: " message)))))

(: event-manifest (-> Event Manifest))
(define (event-manifest event)
  (match event
    ((Building manifest) manifest)
    ((Built _ manifest) manifest)
    ((Failed _ manifest) manifest)))

;; ---- Changes ----

;; The files whose digests differ, including files only one side has.
(: changed-files (-> Manifest Manifest (List String)))
(define (changed-files old new)
  (delete-duplicates string=?
                     (append (differing (Manifest-files old) (Manifest-files new)) (differing (Manifest-files new) (Manifest-files old)))))

(: differing (-> (List (Pair String String)) (List (Pair String String)) (List String)))
(define (differing these those)
  (map Pair-first (filter (lambda (entry) (match (assoc-ref those (Pair-first entry))
                                            ((Some digest) (not (string=? digest (Pair-second entry))))
                                            ((None) #t)))
                          these)))

;; The first module, in program order, whose file differs; the modules
;; before it cannot import from it, so they stay linked.
(: first-changed-module (-> Manifest Manifest (Option String)))
(define (first-changed-module old new)
  (let loop ((old (Manifest-modules old)) (new (Manifest-modules new)))
    (match new
      ((Cons (Pair name file) rest)
       (match old
         ((Cons (Pair old-name old-file) old-rest)
          (if (and (string=? name old-name) (string=? file old-file)) (loop old-rest rest) (Some name)))
         ((Nil) (Some name))))
      ((Nil) (None)))))

;; Only a style sheet is fetched again in place; any other file changes
;; the page, which must load again.
(: style-sheet? (-> String Bool))
(define (style-sheet? file)
  (let ((length (string-length file)))
    (and (> length 4) (string=? (substring file (- length 4) length) ".css"))))

;; ---- Decisions ----

;; The manifest of what the page runs, and the latest build's time.
(: loaded (Ref Manifest))
(define loaded (ref (Manifest (Nil) (Nil))))

(: last-time (Ref String))
(define last-time (ref ""))

(: receive! (-> Event Unit ! mut page))
(define (receive! event)
  (let* ((manifest (event-manifest event)) (files (changed-files (ref-get loaded) manifest)))
    (if (any? (lambda (file) (not (style-sheet? file))) files)
        (reload-page!)
        (begin (for-each (lambda (file) (restyle! file (digest-of manifest file))) files)
               (match (first-changed-module (ref-get loaded) manifest)
                 ((Some module) (ref-set! loaded manifest) (remember-time! event) (relink! module))
                 ((None) (ref-set! loaded manifest) (show! event (not (null? files)))))))))

(: digest-of (-> Manifest String String))
(define (digest-of manifest file)
  (match (assoc-ref (Manifest-files manifest) file)
    ((Some digest) digest)
    ((None) "")))

(: remember-time! (-> Event Unit ! mut))
(define (remember-time! event)
  (match event
    ((Built milliseconds _) (ref-set! last-time milliseconds))
    (_ (unit))))

(: show! (-> Event Bool Unit ! mut page))
(define (show! event changed)
  (remember-time! event)
  (match event
    ((Building _) (notice! "Building..." lasting))
    ((Built _ _) (if changed (notice! (reloaded) brief) (hide!)))
    ((Failed message _) (notice! message failure))))

(: reloaded (-> String ! mut))
(define (reloaded)
  (string-append "Reloaded, built in " (ref-get last-time) " ms"))

;; A relink that failed leaves the old program running; starting over with
;; the new one is the developer's choice.
(: relinked! (-> Bool String Unit ! mut page))
(define (relinked! ok message)
  (if ok
      (notice! (reloaded) brief)
      (offer-fresh-start! (string-append "The new program could not take over the running state; the old one is still running.\n\n" message))))

;; An uncaught error in the page, such as a trap, with the lines the
;; program last wrote to standard error. A trap during a display frame
;; stops the clock with the state from before it; the next build that
;; relinks the program resumes it.
(: page-error! (-> String Bool Unit ! page))
(define (page-error! message stopped)
  (notice! (if stopped
               (string-append message "\n\nThe application stopped. Fix it and save: the next build resumes from the state before the trap.")
               message)
           failure))

;; ---- Entry points ----

(: input (Ref (List Char)))
(define input (ref (Nil)))

(: take-input (-> String ! mut))
(define (take-input)
  (let ((text (list->string (reverse (ref-get input)))))
    (ref-set! input (Nil))
    text))

(: reload-character (-> I32 Unit ! mut))
(define (reload-character code)
  (ref-set! input (Cons (i32->char code) (ref-get input))))

;; The page's own manifest first, then each event; the page reports each
;; relink, with its error, and each uncaught error, with whether the clock
;; stopped.
(: reload-start (-> Unit ! mut))
(define (reload-start)
  (ref-set! loaded (parse-page-manifest (take-input))))

(: reload-event (-> Unit ! mut page))
(define (reload-event)
  (receive! (parse-event (take-input))))

(: reload-relinked (-> I32 Unit ! mut page))
(define (reload-relinked status)
  (relinked! (= status 0) (take-input)))

(: reload-page-error (-> I32 Unit ! mut page))
(define (reload-page-error stopped)
  (page-error! (take-input) (not (= stopped 0))))

(expose reload-character "reload_character")
(expose reload-start "reload_start")
(expose reload-event "reload_event")
(expose reload-relinked "reload_relinked")
(expose reload-page-error "reload_page_error")
