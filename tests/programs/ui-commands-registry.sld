(import
 (snail core base)
 (snail core io)
 (snail shell dom)
 (prefix (snail shell ui commands) command-)
 (prefix (snail shell ui shortcuts) shortcut-))

(define (add (value I64)) (→ I64) (+ value 1))

(define (entries) (→ (Vector (command-Command (Fn I64 → I64))))
  (list->vector (list (new command-Command (name "add") (action add))
                      (new command-Command (name "double") (action (lambda (value) (* value 2)))))))

(define (invoke (command (Option (Fn I64 → I64))) (value I64)) (→ I64)
  (match command ((Some run) (run value)) ((None) -1)))

(define (main) (→ Unit) (! output-port)
  (match (command-register (entries))
    ((Ok registry)
     (write-line (show (invoke (command-named registry "add") 4)))
     (write-line (show (invoke (command-named registry "double") 4)))
     (match (shortcut-register (vector-map (lambda (record) (● record name)) (entries))
                               (list->vector
                                (list (new shortcut-Binding
                                        (chord (new Chord (key "a") (modifiers (control-key))))
                                        (name "add")))))
       ((Ok shortcuts)
        (write-line
         (show (match (shortcut-matching shortcuts (new Chord (key "a") (modifiers (control-key))))
                 ((Some name) (invoke (command-named registry name) 4)) ((None) -1))))
        (write-line
         (show (match (shortcut-matching shortcuts (new Chord (key "a") (modifiers (meta-key))))
                 ((Some _) #f) ((None) #t)))))
       ((Err message) (panic message))))
    ((Err message) (panic message)))
  (match (command-register
          (vector-append (entries)
                         (list->vector (list (new command-Command (name "add") (action add))))))
    ((Ok _) (panic "accepted a duplicate command"))
    ((Err message) (write-line message)))
  (for-each
   (lambda (bindings)
     (match (shortcut-register (list->vector (list "add" "double")) (list->vector bindings))
       ((Ok _) (panic "accepted an invalid binding"))
       ((Err message) (write-line message))))
   (list (list (new shortcut-Binding (chord (new Chord (key "z") (modifiers 0))) (name "add"))
               (new shortcut-Binding (chord (new Chord (key "z") (modifiers 0))) (name "double")))
         (list
          (new shortcut-Binding (chord (new Chord (key "z") (modifiers 0))) (name "missing")))))
  (unit))
