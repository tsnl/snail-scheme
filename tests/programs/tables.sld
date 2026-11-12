(import
 (snail core base)
 (snail core io)
 (snail core table))

(define table
  (fold-left (lambda (table i) (table-set table (string-append "key" (show i)) (* i i)))
             empty-table
             (iota 1000)))

(define updated (table-set table "key7" -1))

(define (main) (→ Unit) (! output-port)
  (display (table-count updated))
  (newline)
  (write (table-ref updated "key7"))
  (newline)
  ;; Setting a key makes a new table; the old one still has its value.
  (write (table-ref table "key7"))
  (newline)
  (write (table-ref updated "key999"))
  (newline)
  (write (table-ref updated "missing"))
  (newline)
  (display (fold-left + 0 (table-values updated)))
  (newline)
  (write (delete-duplicates string=? (list "a" "b" "a" "c" "b")))
  (newline)
  (write (list (take (iota 5) 2) (list-drop (iota 5) 3)))
  (newline)
  (unit))
