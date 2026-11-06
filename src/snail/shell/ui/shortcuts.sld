;; Keyboard policy is a mapping from complete chords to command names.
;; A key is only the key's spelling; a chord also includes its modifiers.
;; This module knows no command implementation or application model.
(define-library (snail shell ui shortcuts)
  (export Binding
          Shortcuts
          register
          matching
          chords
          same-chord?)
  (import
   (snail core base)
   (only (snail shell dom) Chord))
  (begin

    (struct Binding
      ((chord Chord)
       (name String)))

    (struct Shortcuts
      ((bindings (Vector Binding))))

    (: same-chord? (-> Chord Chord Bool))
    (define (same-chord? first second)
      (and (string=? (::key first) (::key second))
           (= (::modifiers first) (::modifiers second))))

    (: register (-> (Vector String) (Vector Binding) (Result Shortcuts String)))
    (define (register names bindings)
      (let loop ((index 0))
        (if (= index (vector-length bindings)) (Ok (Shortcuts bindings))
            (let ((binding (vector-ref bindings index)))
              (cond ((string=? (::name binding) "") (Err "a shortcut needs a command name"))
                    ((not (vector-fold
                           (lambda (found name) (or found (string=? name (::name binding))))
                           #f
                           names))
                     (Err (string-append "unknown command: " (::name binding))))
                    ((bound-before? bindings index (::chord binding))
                     (Err (string-append "duplicate shortcut: " (::name binding))))
                    (else (loop (+ index 1))))))))

    (: bound-before? (-> (Vector Binding) I64 Chord Bool))
    (define (bound-before? bindings end chord)
      (let loop ((index 0))
        (and (< index end)
             (or (same-chord? (::chord (vector-ref bindings index)) chord)
                 (loop (+ index 1))))))

    (: matching (-> Shortcuts Chord (Option String)))
    (define (matching shortcuts chord)
      (let ((bindings (::bindings shortcuts)))
        (let loop ((index 0))
          (cond ((= index (vector-length bindings)) (None))
                ((same-chord? (::chord (vector-ref bindings index)) chord)
                 (Some (::name (vector-ref bindings index))))
                (else (loop (+ index 1)))))))

    (: chords (-> Shortcuts (List Chord)))
    (define (chords shortcuts)
      (vector->list (vector-map ::chord (::bindings shortcuts))))))
