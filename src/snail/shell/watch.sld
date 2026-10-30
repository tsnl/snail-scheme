;; What a tree holds, as a watcher reconciles it. A native watch is a hint:
;; Node's recursive watch keeps following a file renamed over, as `sed -i`
;; and editors' atomic saves leave it, and sees nothing of its next edit
;; (#547). An inventory of the tree, taken again and compared with the one
;; before, finds every change, whatever the watch saw: a file edited, made
;; or removed is a path whose fingerprint differs, or that only one
;; inventory has. A hint says only when to take the next one.
(define-library (snail shell watch)
  (export
   Inventory
   empty-inventory
   inventory
   inventory-changes
   inventory-files
   hints
   Watch
   watch-tree
   next-hint
   close-watch)
  (import
   (snail core base)
   (snail core io)
   (snail core table)
   (only (snail shell task) tasks through-host))
  (begin

    ;; ---- Inventories ----

    ;; Each path under the roots, with its fingerprint.
    (struct Inventory
      ((fingerprints (Table String))))

    (: empty-inventory Inventory)
    (define empty-inventory (Inventory empty-table))

    ;; The paths under `roots`, the roots among them, leaving out each path
    ;; in `excluded` and what is under it. A path that vanishes while the
    ;; inventory is taken is left out, as removed, so the next inventory
    ;; that has it reports it again. One that cannot be read otherwise
    ;; fails the inventory, which leaving it out would report removed.
    (: inventory (-> (List String) (List String) (Result Inventory String) ! fs))
    (define (inventory roots excluded)
      (match (take-paths empty-table roots excluded)
        ((Ok fingerprints) (Ok (Inventory fingerprints)))
        ((Err message) (Err message))))

    (: take-paths
       (-> (Table String) (List String) (List String) (Result (Table String) String) ! fs))
    (define (take-paths fingerprints paths excluded)
      (match paths
        ((Nil) (Ok fingerprints))
        ((Cons path rest)
         (match (take-path fingerprints path excluded)
           ((Ok fingerprints) (take-paths fingerprints rest excluded))
           ((Err message) (Err message))))))

    (: take-path (-> (Table String) String (List String) (Result (Table String) String) ! fs))
    (define (take-path fingerprints path excluded)
      (if (member? path excluded)
          (Ok fingerprints)
          (match (file-status path)
            ((Ok status)
             (let ((fingerprints (table-set fingerprints path (fingerprint status))))
               (match (FileStatus-kind status)
                 ((Directory) (take-directory fingerprints path excluded))
                 (_ (Ok fingerprints)))))
            ((Err (NotFound)) (Ok fingerprints))
            ((Err error) (Err (unreadable path error))))))

    (: take-directory (-> (Table String) String (List String) (Result (Table String) String) ! fs))
    (define (take-directory fingerprints directory excluded)
      (match (list-directory directory)
        ((Ok names)
         (take-paths fingerprints
                     (map (lambda (name) (string-append directory "/" name)) names)
                     excluded))
        ((Err (NotFound)) (Ok fingerprints))
        ((Err error) (Err (unreadable directory error)))))

    (: unreadable (-> String FileError String))
    (define (unreadable path error)
      (string-append "cannot read " path ": " (show error)))

    ;; What tells an edit to a path apart. A file's is its size and
    ;; modification time in nanoseconds, so the file an atomic save renames
    ;; over another differs from it. A directory's is its kind alone: what
    ;; it holds has fingerprints of its own, and its timestamps change with
    ;; any of them. A symbolic link is fingerprinted, not followed.
    (: fingerprint (-> FileStatus String))
    (define (fingerprint status)
      (let ((stamp (string-append (i64->string (FileStatus-size status))
                                  " "
                                  (i64->string (FileStatus-modified status)))))
        (match (FileStatus-kind status)
          ((RegularFile) (string-append "file " stamp))
          ((Directory) "directory")
          ((SymbolicLink) (string-append "link " stamp))
          ((OtherKind) (string-append "other " stamp)))))

    ;; ---- Changes ----

    ;; The paths that differ between two inventories of the same roots:
    ;; those `after` fingerprints otherwise than `before`, or has and
    ;; `before` has not, and then those only `before` has.
    (: inventory-changes (-> Inventory Inventory (List String)))
    (define (inventory-changes before after)
      (let ((old (Inventory-fingerprints before)) (new (Inventory-fingerprints after)))
        (append (filter (lambda (path) (not (same-fingerprint? old new path))) (table-keys new))
                (filter (lambda (path) (not (table-contains? new path))) (table-keys old)))))

    ;; The regular files an inventory found, in no particular order.
    (: inventory-files (-> Inventory (List String)))
    (define (inventory-files taken)
      (let ((fingerprints (Inventory-fingerprints taken)))
        (filter (lambda (path)
                  (match (table-ref fingerprints path)
                    ((Some print) (and (>= (string-length print) 5)
                                       (string=? (substring print 0 5) "file ")))
                    ((None) #f)))
                (table-keys fingerprints))))

    (: same-fingerprint? (-> (Table String) (Table String) String Bool))
    (define (same-fingerprint? old new path)
      (match (Pair (table-ref old path) (table-ref new path))
        ((Pair (Some was) (Some is)) (string=? was is))
        (_ #f)))

    ;; ---- Hints ----

    ;; Node's recursive watch of a tree, which hints that something under
    ;; it changed, outside its excluded directories. A hint names nothing:
    ;; the next inventory finds what changed. Nor is one needed to find it,
    ;; since a watch can miss a change or be lost: hints only make an
    ;; inventory prompt. Only Node implements them, as WASI has no watch.
    ;; Starting and closing a watch are commands, its root and exclusions
    ;; sent a character at a time, as `modes` sends paths in
    ;; (snail shell project files); waiting is by ticket.
    (effect hints
      ((hint-character (-> Char Unit))
       (hint-end (-> Unit))
       (hint-command (-> I32 I32))
       (next-hint-of (-> I32 Bool ! tasks)))
      (host "snail.runtime.native.files"
            ((hint-character "argument-character")
             (hint-end "argument-end")
             (hint-command "command")))
      (default
        ((next-hint-of
          (lambda (id)
            (= (through-host (lambda (ticket) (start-hint ticket id)) finish-hint) 1))))))

    (extern start-hint "snail.runtime.native.files" "start-hint" (-> I64 I32 Unit))
    (extern finish-hint "snail.runtime.native.files" "finish-hint" (-> I64 I32))

    ;; A watch the host keeps, by number.
    (struct Watch
      ((id I32)))

    ;; A watch of `root` and what is under it, but for each path in
    ;; `excluded` and what is under that; None when the host cannot watch
    ;; it, as when it is missing.
    (: watch-tree (-> String (List String) (Option Watch) ! hints))
    (define (watch-tree root excluded)
      (for-each send-hint-text (list "watch" root))
      (for-each send-hint-text excluded)
      (let ((id (hint-command 0)))
        (if (< id 0) (None) (Some (Watch id)))))

    (: send-hint-text (-> String Unit ! hints))
    (define (send-hint-text text)
      (for-each hint-character (string->list text))
      (hint-end))

    ;; Waits for a hint since the last one taken, #t, or for the watch to
    ;; close or be lost, #f.
    (: next-hint (-> Watch Bool ! hints tasks))
    (define (next-hint watch)
      (next-hint-of (Watch-id watch)))

    ;; Ends the watch, and answers a wait on it with #f.
    (: close-watch (-> Watch Unit ! hints))
    (define (close-watch watch)
      (send-hint-text "unwatch")
      (hint-command (Watch-id watch))
      (unit))))

