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

    (define (same-chord? (first Chord) (second Chord)) (→ Bool)
      (and (string=? (::key first) (::key second))
           (= (::modifiers first) (::modifiers second))))

    (define (register (names (Vector String)) (bindings (Vector Binding)))
      (→ (Result Shortcuts String))
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

    (define (bound-before? (bindings (Vector Binding)) (end I64) (chord Chord)) (→ Bool)
      (let loop ((index 0))
        (and (< index end)
             (or (same-chord? (::chord (vector-ref bindings index)) chord)
                 (loop (+ index 1))))))

    (define (matching (shortcuts Shortcuts) (chord Chord)) (→ (Option String))
      (let ((bindings (::bindings shortcuts)))
        (let loop ((index 0))
          (cond ((= index (vector-length bindings)) (None))
                ((same-chord? (::chord (vector-ref bindings index)) chord)
                 (Some (::name (vector-ref bindings index))))
                (else (loop (+ index 1)))))))

    (define (chords (shortcuts Shortcuts)) (→ (List Chord))
      (vector->list (vector-map ::chord (::bindings shortcuts))))))
