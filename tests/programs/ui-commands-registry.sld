(import
 (snail core base)
 (snail core io)
 (snail shell dom)
 (prefix (snail shell ui commands) command-)
 (prefix (snail shell ui shortcuts) shortcut-))

(: add (impl (Fn I64 -> I64)))
(define (add value) (+ value 1))

(: entries (Vector (command-Command (dyn (Fn I64 -> I64)))))
(define entries
  (list->vector (list (command-Command "add" add)
                      (command-Command "double" (lambda (value) (* value 2))))))

(: invoke (impl (Fn (Option (dyn (Fn I64 -> I64))) I64 -> I64)))
(define (invoke command value)
  (match command ((Some run) (run value)) ((None) -1)))

(match (command-register entries)
  ((Ok registry)
   (write-line (show (invoke (command-named registry "add") 4)))
   (write-line (show (invoke (command-named registry "double") 4)))
   (match (shortcut-register (vector-map ::name entries)
                             (list->vector (list (shortcut-Binding (Chord "a" control-key) "add"))))
     ((Ok shortcuts)
      (write-line (show (match (shortcut-matching shortcuts (Chord "a" control-key))
                          ((Some name) (invoke (command-named registry name) 4)) ((None) -1))))
      (write-line (show (match (shortcut-matching shortcuts (Chord "a" meta-key))
                          ((Some _) #f) ((None) #t)))))
     ((Err message) (panic message))))
  ((Err message) (panic message)))

(match (command-register (vector-append entries (list->vector (list (command-Command "add" add)))))
  ((Ok _) (panic "accepted a duplicate command"))
  ((Err message) (write-line message)))

(for-each
 (lambda (bindings)
   (match (shortcut-register (list->vector (list "add" "double")) (list->vector bindings))
     ((Ok _) (panic "accepted an invalid binding"))
     ((Err message) (write-line message))))
 (list (list (shortcut-Binding (Chord "z" 0) "add") (shortcut-Binding (Chord "z" 0) "double"))
       (list (shortcut-Binding (Chord "z" 0) "missing"))))
