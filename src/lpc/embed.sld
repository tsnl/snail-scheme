;; Helpers for `generate-library` recipes that turn the LPC packs into
;; libraries a program compiles in: image files become byte vector literals,
;; and the packs' JSON palettes become color lists. A recipe runs when its
;; library is built and reads files relative to the repository's root. It
;; returns the library as syntax, so an image's bytes reach the compiler as
;; they are.
(define-library (lpc embed)
  (export
   embed-library
   ramps-library)
  (import
   (lofi base)
   (lofi io)
   (lofi syntax))
  (begin

    ;; `(: name (-> String result))` and `(define (name key) (cond ...))`,
    ;; a function giving each entry's value for its string and `fallback`
    ;; for any other.
    (: lookup-definitions (-> String Syntax (List (Pair String Syntax)) Syntax (List Syntax)))
    (define (lookup-definitions name result entries fallback)
      (list (form ":" (list (SymbolSyntax name) (form "->" (list (SymbolSyntax "String") result))))
            (form "define"
                  (list (form name (list (SymbolSyntax "key")))
                        (form "cond" (append (map lookup-clause entries) (list (form "else" (list fallback)))))))))

    ;; `((string=? key "K") VALUE)`.
    (: lookup-clause (-> (Pair String Syntax) Syntax))
    (define (lookup-clause entry)
      (ListSyntax (list (form "string=?" (list (SymbolSyntax "key") (StringSyntax (Pair-first entry)))) (Pair-second entry))))

    ;; ---- Images ----

    ;; The library `name` exporting `art`, which gives the image at each path
    ;; of `paths` as a Source keyed from `first-key` on, and None for any
    ;; other path. The paths' files are read now, as bytes.
    (: embed-library (-> (List String) I32 (List String) Syntax ! fs))
    (define (embed-library name first-key paths)
      (library-syntax name (list "art") (list (list "lofi" "base") (list "lofi" "app"))
                      (append (lookup-definitions "art" (form "Option" (list (SymbolSyntax "Source")))
                                                  (map-indexed (lambda (index path) (art-entry first-key index path)) paths) (form "None" (Nil)))
                              (concatenate (map-indexed image-definitions paths)))))

    ;; Path P gives `(Some (Source KEY image-I))`.
    (: art-entry (-> I32 I64 String (Pair String Syntax)))
    (define (art-entry first-key index path)
      (Pair path (form "Some" (list (form "Source" (list (IntegerSyntax (+ (i32->i64 first-key) index)) (image-name index)))))))

    (: image-name (-> I64 Syntax))
    (define (image-name index)
      (SymbolSyntax (string-append "image-" (show index))))

    ;; An image is a thunk of its bytes, so they are copied out of their
    ;; data segment only when the host asks for them.
    (: image-definitions (-> I64 String (List Syntax) ! fs))
    (define (image-definitions index path)
      (list (form ":" (list (image-name index) (form "->" (list (SymbolSyntax "Bytes")))))
            (form "define" (list (ListSyntax (list (image-name index))) (BytesSyntax (read-bytes path))))))

    ;; ---- Palettes ----

    ;; The library `name` exporting `ramp`, which gives the colors, as
    ;; 0xRRGGBB, of each ramp in the JSON file at `path`: an object whose
    ;; keys name lists of "#rrggbbaa" strings, as the LPC packs keep their
    ;; palettes. A missing ramp is empty.
    (: ramps-library (-> (List String) String Syntax ! fs))
    (define (ramps-library name path)
      (library-syntax name (list "ramp") (list (list "lofi" "base"))
                      (lookup-definitions "ramp" (form "List" (list (SymbolSyntax "I32"))) (map ramp-entry (json-ramps (read-file path)))
                                          (form "Nil" (Nil)))))

    ;; Ramp K gives `(list C ...)`.
    (: ramp-entry (-> (Pair String (List I32)) (Pair String Syntax)))
    (define (ramp-entry ramp)
      (Pair (Pair-first ramp) (form "list" (map (lambda (color) (IntegerSyntax (i32->i64 color))) (Pair-second ramp)))))

    ;; The quoted strings of the file in order: each key is followed by its
    ;; colors, so a string that is not a color starts the next ramp.
    (: json-ramps (-> String (List (Pair String (List I32)))))
    (define (json-ramps text)
      (reverse
       (fold-left (lambda (ramps word)
                    (match (color-value word)
                      ((Some color) (match ramps
                                      ((Cons (Pair key colors) rest) (Cons (Pair key (append colors (list color))) rest))
                                      ((Nil) ramps)))
                      ((None) (Cons (Pair word (Nil)) ramps))))
                  (Nil)
                  (quoted-strings text))))

    (: quoted-strings (-> String (List String)))
    (define (quoted-strings text)
      (let loop ((index 0) (start -1) (found (Nil)))
        (cond ((= index (string-length text)) (reverse found))
              ((not (char=? (string-ref text index) #\")) (loop (+ index 1) start found))
              ((< start 0) (loop (+ index 1) (+ index 1) found))
              (else (loop (+ index 1) -1 (Cons (substring text start index) found))))))

    ;; "#rrggbb" or "#rrggbbaa", as 0xRRGGBB.
    (: color-value (-> String (Option I32)))
    (define (color-value word)
      (if (and (or (= (string-length word) 7) (= (string-length word) 9)) (char=? (string-ref word 0) #\#))
          (fold-left (lambda (value index)
                       (match value
                         ((Some sum) (match (hex-digit (string-ref word index))
                                       ((Some digit) (Some (+ (* sum 16) digit)))
                                       ((None) (None))))
                         ((None) (None))))
                     (Some 0)
                     (list 1 2 3 4 5 6))
          (None)))

    (: hex-digit (-> Char (Option I32)))
    (define (hex-digit c)
      (let ((code (char->i32 c)))
        (cond ((and (<= 48 code) (<= code 57)) (Some (- code 48)))
              ((and (<= 97 code) (<= code 102)) (Some (- code 87)))
              ((and (<= 65 code) (<= code 70)) (Some (- code 55)))
              (else (None)))))

    ))
