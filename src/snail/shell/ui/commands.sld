;; Named commands and their keys. Registration checks names and chords once;
;; a palette and a keyboard listener then retrieve the same action. An action
;; may be any Copy value, including a Scheme function with its own effects.
(define-library (snail shell ui commands)
  (export
   Command Command-name Command-keys Command-action
   Registry Registry-commands register named keyed chords)
  (import
   (snail core base)
   (only (snail shell dom) Chord Chord-key Chord-modifiers))
  (begin

    ;; ---- Registration ----

    (struct (Command A)
      ((name String)
       (keys (List Chord))
       (action A)))

    (struct (Registry A)
      ((commands (List (Command A)))))

    (: same-key? (-> Chord Chord Bool))
    (define (same-key? first second)
      (and (string=? (Chord-key first) (Chord-key second))
           (= (Chord-modifiers first) (Chord-modifiers second))))

    (: repeated-key? (-> (List Chord) (List Chord) Bool))
    (define (repeated-key? keys held)
      (match keys
        ((Nil) #f)
        ((Cons key rest)
         (or (any? (lambda (other) (same-key? key other)) held)
             (repeated-key? rest (Cons key held))))))

    (: register (All (A) (requires (Copy A))
                     (-> (List (Command A)) (Result (Registry A) String))))
    (define (register commands)
      (let loop ((rest commands) (names (ann (Nil) (List String)))
                 (keys (ann (Nil) (List Chord))))
        (match rest
          ((Nil) (Ok (Registry commands)))
          ((Cons command rest)
           (let ((name (Command-name command)) (more (Command-keys command)))
             (cond ((string=? name "") (Err "a command needs a name"))
                   ((member? name names) (Err (string-append "duplicate command: " name)))
                   ((repeated-key? more keys) (Err (string-append "duplicate shortcut: " name)))
                   (else (loop rest (Cons name names) (append more keys)))))))))

    ;; ---- Dispatch ----

    (: named (All (A) (requires (Copy A)) (-> (Registry A) String (Option A))))
    (define (named registry name)
      (match (find (lambda (command) (string=? name (Command-name command)))
                   (Registry-commands registry))
        ((Some command) (Some (Command-action command)))
        ((None) (None))))

    (: keyed (All (A) (requires (Copy A)) (-> (Registry A) String I32 (Option A))))
    (define (keyed registry key modifiers)
      (match (find (lambda (command)
                     (any? (lambda (chord) (same-key? chord (Chord key modifiers)))
                           (Command-keys command)))
                   (Registry-commands registry))
        ((Some command) (Some (Command-action command)))
        ((None) (None))))

    (: chords (All (A) (requires (Copy A)) (-> (Registry A) (List Chord))))
    (define (chords registry)
      (concatenate (map Command-keys (Registry-commands registry))))))
