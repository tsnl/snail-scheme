;; Helpers for `generate-library` recipes that turn the LPC packs into
;; libraries a program compiles in: image files become byte vector literals,
;; and the packs' JSON palettes become color lists. A recipe runs when its
;; library is built and returns the library as syntax, so an image's bytes
;; reach the compiler as they are. A palette comes from bytes its recipe
;; includes; images are still read from paths relative to the repository's
;; root.
(define-library (lpc embed)
  (export
   embed-library
   ramps-library)
  (import
   (snail core base)
   (snail core io)
   (snail shell syntax)
   (only (snail shell utf8) utf8->string))
  (begin

    ;; `(define (name (key String)) (→ result) (cond ...))`,
    ;; a function giving each entry's value for its string and `fallback`
    ;; for any other.
    (define (lookup-definitions (name String)
                                (result Syntax)
                                (entries (List (Pair String Syntax)))
                                (fallback Syntax))
      (→ (List Syntax))
      (list (form "define"
                  (list (form name (list (form "key" (list (SymbolSyntax "String")))))
                        (form "→" (list result))
                        (form "cond"
                              (append (map lookup-clause entries)
                                      (list (form "else" (list fallback)))))))))

    ;; `((string=? key "K") VALUE)`.
    (define (lookup-clause (entry (Pair String Syntax))) (→ Syntax)
      (ListSyntax
       (list (form "string=?" (list (SymbolSyntax "key") (StringSyntax (● entry first))))
             (● entry second))))

    ;; ---- Images ----

    ;; The library `name` exporting `art`, which gives the image at each path
    ;; of `paths` as a Source keyed from `first-key` on, and None for any
    ;; other path. The paths' files are read now, as bytes.
    (define (embed-library (name (List String)) (first-key I32) (paths (List String)))
      (→ Syntax)
      (! fs)
      (library-syntax name
                      (list "art")
                      (list (list "snail" "core" "base") (list "snail" "shell" "app"))
                      (append
                       (lookup-definitions "art" (form "Option" (list (SymbolSyntax "Source")))
                                           (map-indexed
                                            (lambda (index path) (art-entry first-key index path))
                                            paths)
                                           (form "None" (Nil)))
                       (concatenate (map-indexed image-definitions paths)))))

    ;; Path P gives `(Some (Source KEY image-I))`.
    (define (art-entry (first-key I32) (index I64) (path String)) (→ (Pair String Syntax))
      (new Pair (first path)
           (second (form "Some"
                         (list (form "Source"
                                     (list (IntegerSyntax (+ (i32->i64 first-key) index))
                                           (image-name index))))))))

    (define (image-name (index I64)) (→ Syntax)
      (SymbolSyntax (string-append "image-" (show index))))

    ;; An image is a thunk of its bytes, so they are copied out of their
    ;; data segment only when the host asks for them.
    (define (image-definitions (index I64) (path String)) (→ (List Syntax)) (! fs)
      (list (form "define"
                  (list (ListSyntax (list (image-name index)))
                        (form "→" (list (SymbolSyntax "Bytes")))
                        (BytesSyntax (read-bytes path))))))

    ;; ---- Palettes ----

    ;; The library `name` exporting `ramp`, which gives the colors, as
    ;; 0xRRGGBB, of each ramp in `json`, a palette file's bytes: an object
    ;; whose keys name lists of "#rrggbbaa" strings, as the LPC packs keep
    ;; their palettes. A missing ramp is empty.
    (define (ramps-library (name (List String)) (json Bytes)) (→ Syntax)
      (library-syntax name (list "ramp") (list (list "snail" "core" "base"))
                      (lookup-definitions "ramp"
                                          (form "List" (list (SymbolSyntax "I32")))
                                          (map ramp-entry (json-ramps (palette-text json)))
                                          (form "Nil" (Nil)))))

    (define (palette-text (json Bytes)) (→ String)
      (match (utf8->string json)
        ((Ok text) text)
        ((Err _) (panic "the palette file is not UTF-8"))))

    ;; Ramp K gives `(list C ...)`.
    (define (ramp-entry (ramp (Pair String (List I32)))) (→ (Pair String Syntax))
      (new Pair (first (● ramp first))
           (second (form "list"
                         (map (lambda (color) (IntegerSyntax (i32->i64 color))) (● ramp second))))))

    ;; The quoted strings of the file in order: each key is followed by its
    ;; colors, so a string that is not a color starts the next ramp.
    (define (json-ramps (text String)) (→ (List (Pair String (List I32))))
      (reverse
       (fold-left (lambda (ramps word)
                    (match (color-value word)
                      ((Some color) (match ramps
                                      ((Cons (Pair key colors) rest)
                                       (Cons
                                        (new Pair (first key) (second (append colors (list color))))
                                        rest))
                                      ((Nil) ramps)))
                      ((None) (Cons (new Pair (first word) (second (Nil))) ramps))))
                  (Nil)
                  (quoted-strings text))))

    (define (quoted-strings (text String)) (→ (List String))
      (let loop ((index 0) (start -1) (found (Nil)))
        (cond ((= index (string-length text)) (reverse found))
              ((not (char=? (string-ref text index) #\")) (loop (+ index 1) start found))
              ((< start 0) (loop (+ index 1) (+ index 1) found))
              (else (loop (+ index 1) -1 (Cons (substring text start index) found))))))

    ;; "#rrggbb" or "#rrggbbaa", as 0xRRGGBB.
    (define (color-value (word String)) (→ (Option I32))
      (if (and (or (= (string-length word) 7) (= (string-length word) 9))
               (char=? (string-ref word 0) #\#))
          (fold-left (lambda (value index)
                       (match value
                         ((Some sum) (match (hex-digit (string-ref word index))
                                       ((Some digit) (Some (+ (* sum 16) digit)))
                                       ((None) (None))))
                         ((None) (None))))
                     (Some 0)
                     (list 1 2 3 4 5 6))
          (None)))

    (define (hex-digit (c Char)) (→ (Option I32))
      (let ((code (char->i32 c)))
        (cond ((and (<= 48 code) (<= code 57)) (Some (- code 48)))
              ((and (<= 97 code) (<= code 102)) (Some (- code 87)))
              ((and (<= 65 code) (<= code 70)) (Some (- code 55)))
              (else (None)))))

    ))
