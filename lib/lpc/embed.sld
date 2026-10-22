;; Helpers for `generate-library` recipes that turn the LPC packs into
;; libraries a program compiles in: image files become byte literals, and
;; the packs' JSON palettes become color lists. A recipe runs when its
;; library is built and reads files relative to the repository's root.
(define-library (lpc embed)
  (export
   embed-library
   ramps-library)
  (import
   (lofi base)
   (lofi io))
  (begin

    ;; ---- Images ----

    ;; The text of a library `name` exporting `art`, which gives the image at
    ;; each path of `paths` as a Source keyed from `first-key` on, and None
    ;; for any other path. The paths' files are read now, as bytes.
    (: embed-library (-> String I32 (List String) String ! fs))
    (define (embed-library name first-key paths)
      (string-join (append (list (string-append "(define-library " name)
                                 "  (export art)"
                                 "  (import (lofi base) (lofi app))"
                                 "  (begin"
                                 "    (: art (-> String (Option Source)))"
                                 "    (define (art path)"
                                 "      (cond")
                           (append (map-indexed (lambda (index path) (art-clause first-key index path)) paths)
                                   (Cons "            (else (None))))"
                                         (append (map-indexed (lambda (index path) (bytes-definition index path)) paths)
                                                 (list "    ))")))))
                   "\n"))

    (: art-clause (-> I32 I64 String String))
    (define (art-clause first-key index path)
      (string-append "            ((string=? path \"" path "\") (Some (Source " (show (+ first-key (i64->i32 index)))
                     " image-" (show index) ")))"))

    (: bytes-definition (-> I64 String String ! fs))
    (define (bytes-definition index path)
      (string-append "    (: image-" (show index) " (-> Bytes))\n"
                     "    (define (image-" (show index) ") #u8(" (bytes-text (read-bytes path)) "))"))

    (: bytes-text (-> Bytes String))
    (define (bytes-text bytes)
      (string-join (map (lambda (byte) (show (u8->i32 byte))) (vector->list bytes)) " "))

    ;; ---- Palettes ----

    ;; The text of a library `name` exporting `ramp`, which gives the colors,
    ;; as 0xRRGGBB, of each ramp in the JSON file at `path`: an object whose
    ;; keys name lists of "#rrggbbaa" strings, as the LPC packs keep their
    ;; palettes. A missing ramp is empty.
    (: ramps-library (-> String String String ! fs))
    (define (ramps-library name path)
      (string-join (append (list (string-append "(define-library " name)
                                 "  (export ramp)"
                                 "  (import (lofi base))"
                                 "  (begin"
                                 "    (: ramp (-> String (List I32)))"
                                 "    (define (ramp name)"
                                 "      (cond")
                           (append (map ramp-clause (json-ramps (read-file path)))
                                   (list "            (else (Nil))))" "    ))")))
                   "\n"))

    (: ramp-clause (-> (Pair String (List I32)) String))
    (define (ramp-clause entry)
      (string-append "            ((string=? name \"" (Pair-first entry) "\") (list "
                     (string-join (map show (Pair-second entry)) " ") "))"))

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
