(import
 (snail core base)
 (snail core io)
 (snail shell watch))

;; Inventories of a scratch tree and the changes between them: an edit
;; that renames a file over another, twice, as `sed -i` does (#547); what
;; is made and removed; and nothing under an excluded directory. The
;; edits differ in size, since two writes within one tick of the file
;; system's clock carry the same time.
(define root "build/tests/watch-inventory")

(: at (-> String String))
(define (at name)
  (string-append root "/" name))

(: excluded (List String))
(define excluded (list (at "build")))

(: take (-> Unit Inventory ! fs))
(define (take ignored)
  (inventory (list (at "src") (at "build") (at "missing")) excluded))

;; Saves as an atomic save does: writes beside the file, then renames over
;; it.
(: save (-> String String Unit ! fs))
(define (save name text)
  (write-file (at (string-append name ".next")) text)
  (match (rename-file (at (string-append name ".next")) (at name))
    ((Ok _) (unit))
    ((Err error) (panic (show error)))))

;; The changes as names under the root, in order.
(: changes (-> Inventory Inventory String))
(define (changes before after)
  (let ((names (map (lambda (path) (substring path (+ (string-length root) 1) (string-length path)))
                    (inventory-changes before after))))
    (string-append "(" (string-join (sorted names) " ") ")")))

(: sorted (-> (List String) (List String)))
(define (sorted names)
  (fold-left insert (Nil) names))

(: insert (-> (List String) String (List String)))
(define (insert names name)
  (match names
    ((Nil) (list name))
    ((Cons first rest)
     (if (string<? name first) (Cons name names) (Cons first (insert rest name))))))

(: report (-> String Inventory Inventory Inventory ! console))
(define (report label before after)
  (write-line (string-append label " -> " (changes before after)))
  after)

(remove-tree root)
(make-directories (at "src/lib"))
(make-directories (at "build"))
(write-file (at "src/main.sld") "one")
(write-file (at "src/lib/util.sld") "util")

(let* ((first (take (unit)))
       (_ (report "from nothing" empty-inventory first))
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
  (report "back to nothing" removed empty-inventory)
  (remove-tree root)
  (unit))
