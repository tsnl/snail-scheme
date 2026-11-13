(import
 (snail core base)
 (snail core io)
 (snail shell watch))

;; Inventories of a scratch tree and the changes between them: an edit
;; that renames a file over another, twice, as `sed -i` does (#547); what
;; is made and removed; and nothing under an excluded directory. The
;; edits differ in size, since two writes within one tick of the file
;; system's clock carry the same time.
(define (root) (→ String) "build/tests/watch-inventory")

(define (at (name String)) (→ String)
  (string-append (root) "/" name))

(define (excluded) (→ (List String)) (list (at "build")))

(define (take (ignored Unit)) (→ Inventory) (! fs)
  (match (inventory (list (at "src") (at "build") (at "missing")) (excluded))
    ((Ok taken) taken)
    ((Err message) (panic message))))

;; Saves as an atomic save does: writes beside the file, then renames over
;; it.
(define (save (name String) (text String)) (→ Unit) (! fs)
  (write-file (at (string-append name ".next")) text)
  (match (rename-file (at (string-append name ".next")) (at name))
    ((Ok _) (unit))
    ((Err error) (panic (show error)))))

;; The changes as names under the root, in order.
(define (changes (before Inventory) (after Inventory)) (→ String)
  (let ((names
         (map (lambda (path) (substring path (+ (string-length (root)) 1) (string-length path)))
              (inventory-changes before after))))
    (string-append "(" (string-join (sorted names) " ") ")")))

(define (sorted (names (List String))) (→ (List String))
  (fold-left insert (Nil) names))

(define (insert (names (List String)) (name String)) (→ (List String))
  (match names
    ((Nil) (list name))
    ((Cons first rest)
     (if (string<? name first) (Cons name names) (Cons first (insert rest name))))))

(define (report (label String) (before Inventory) (after Inventory)) (→ Inventory) (! output-port)
  (write-line (string-append label " -> " (changes before after)))
  after)

(define (main) (→ Unit) (! fs output-port)
  (remove-tree (root))
  (make-directories (at "src/lib"))
  (make-directories (at "build"))
  (write-file (at "src/main.sld") "one")
  (write-file (at "src/lib/util.sld") "util")
  (let* ((first (take (unit)))
         (_ (report "from nothing" (empty-inventory) first))
         (same (report "unchanged" first (take (unit))))
         (saved (begin
                  (save "src/main.sld" "three")
                  (report "saved by rename" same (take (unit)))))
         (again (begin
                  (save "src/main.sld" "eleven")
                  (report "saved by rename again" saved (take (unit)))))
         (built (begin
                  (write-file (at "build/output") "out")
                  (report "written under build" again (take (unit)))))
         (made (begin
                 (make-directory (at "src/new"))
                 (write-file (at "src/new/added.sld") "added")
                 (report "made" built (take (unit)))))
         (removed (begin
                    (remove-file (at "src/lib/util.sld"))
                    (report "removed" made (take (unit))))))
    (report "back to nothing" removed (empty-inventory))
    (remove-tree (root))
    (unit))
  (unit))
