;; What a tree holds, as a watcher reconciles it. A native watch is a hint:
;; Node's recursive watch keeps following a file renamed over, as `sed -i`
;; and editors' atomic saves leave it, and sees nothing of its next edit
;; (#547). An inventory of the tree, taken again and compared with the one
;; before, finds every change, whatever the watch saw: a file edited, made
;; or removed is a path whose fingerprint differs, or that only one
;; inventory has.
(define-library (snail shell watch)
  (export
   Inventory
   empty-inventory
   inventory
   inventory-changes)
  (import
   (snail core base)
   (snail core io)
   (snail core table))
  (begin

    ;; ---- Inventories ----

    ;; Each path under the roots, with its fingerprint.
    (struct Inventory
      ((fingerprints (Table String))))

    (: empty-inventory Inventory)
    (define empty-inventory (Inventory empty-table))

    ;; The paths under `roots`, the roots among them, leaving out each path
    ;; in `excluded` and what is under it. A path that vanishes or cannot
    ;; be read while the inventory is taken is left out, as if removed, so
    ;; the next inventory that has it reports it again.
    (: inventory (-> (List String) (List String) Inventory ! fs))
    (define (inventory roots excluded)
      (Inventory (fold-left (lambda (fingerprints root) (take-path fingerprints root excluded))
                            empty-table
                            roots)))

    (: take-path (-> (Table String) String (List String) (Table String) ! fs))
    (define (take-path fingerprints path excluded)
      (if (member? path excluded)
          fingerprints
          (match (file-status path)
            ((Ok status)
             (let ((fingerprints (table-set fingerprints path (fingerprint status))))
               (match (FileStatus-kind status)
                 ((Directory) (take-directory fingerprints path excluded))
                 (_ fingerprints))))
            ((Err _) fingerprints))))

    (: take-directory (-> (Table String) String (List String) (Table String) ! fs))
    (define (take-directory fingerprints directory excluded)
      (match (list-directory directory)
        ((Ok names)
         (fold-left (lambda (fingerprints name)
                      (take-path fingerprints (string-append directory "/" name) excluded))
                    fingerprints
                    names))
        ((Err _) fingerprints)))

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

    (: same-fingerprint? (-> (Table String) (Table String) String Bool))
    (define (same-fingerprint? old new path)
      (match (Pair (table-ref old path) (table-ref new path))
        ((Pair (Some was) (Some is)) (string=? was is))
        (_ #f)))))
