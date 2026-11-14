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

    (record Binding
      ((chord Chord)
       (name String)))

    (record Shortcuts
      ((bindings (Vector Binding))))

    (define (same-chord? (first Chord) (second Chord)) (→ Bool)
      (and (string=? (● first key) (● second key))
           (= (● first modifiers) (● second modifiers))))

    (define (register (names (Vector String)) (bindings (Vector Binding)))
      (→ (Result Shortcuts String))
      (let loop ((index 0))
        (if (= index (vector-length bindings)) (Ok (new Shortcuts (bindings bindings)))
            (let ((binding (vector-ref bindings index)))
              (cond ((string=? (● binding name) "") (Err "a shortcut needs a command name"))
                    ((not (vector-fold
                           (lambda (found name) (or found (string=? name (● binding name))))
                           #f
                           names))
                     (Err (string-append "unknown command: " (● binding name))))
                    ((bound-before? bindings index (● binding chord))
                     (Err (string-append "duplicate shortcut: " (● binding name))))
                    (else (loop (+ index 1))))))))

    (define (bound-before? (bindings (Vector Binding)) (end I64) (chord Chord)) (→ Bool)
      (let loop ((index 0))
        (and (< index end)
             (or (same-chord? (● (vector-ref bindings index) chord) chord)
                 (loop (+ index 1))))))

    (define (matching (shortcuts Shortcuts) (chord Chord)) (→ (Option String))
      (let ((bindings (● shortcuts bindings)))
        (let loop ((index 0))
          (cond ((= index (vector-length bindings)) (None))
                ((same-chord? (● (vector-ref bindings index) chord) chord)
                 (Some (● (vector-ref bindings index) name)))
                (else (loop (+ index 1)))))))

    (define (chords (shortcuts Shortcuts)) (→ (List Chord))
      (vector->list (vector-map (lambda (record) (● record chord)) (● shortcuts bindings))))))
