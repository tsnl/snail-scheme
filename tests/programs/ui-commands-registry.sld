(import
 (snail core base)
 (snail core io)
 (snail shell dom)
 (prefix (snail shell ui commands) command-))

(: add (-> I64 I64))
(define (add value) (+ value 1))

(: entries (List (command-Command (-> I64 I64))))
(define entries
  (list (command-Command "add" (list (Chord "a" control-key)) add)
        (command-Command "double" (Nil) (lambda (value) (* value 2)))))

(: invoke (-> (Option (-> I64 I64)) I64 I64))
(define (invoke command value)
  (match command
    ((Some run) (run value))
    ((None) -1)))

(match (command-register entries)
  ((Ok registry)
   (write-line (show (invoke (command-named registry "add") 4)))
   (write-line (show (invoke (command-keyed registry "a" control-key) 4)))
   (write-line (show (invoke (command-named registry "double") 4)))
   (write-line (show (invoke (command-keyed registry "a" meta-key) 4)))
   (write-line (show (length (command-chords registry)))))
  ((Err message) (panic message)))

(for-each (lambda (extra)
            (match (command-register (Cons extra entries))
              ((Ok _) (panic "accepted a duplicate"))
              ((Err message) (write-line message))))
          (list (command-Command "add" (Nil) add)
                (command-Command "again" (list (Chord "a" control-key)) add)
                (command-Command "twice" (list (Chord "z" 0) (Chord "z" 0)) add)))
