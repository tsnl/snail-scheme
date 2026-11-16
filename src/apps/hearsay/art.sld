;; The LPC sheets the cast wears, embedded when this library is built: the
;; recipe reads exactly the files the cast's characters need, and `art`
;; gives each one's bytes as a Source, keyed from 1000. See
;; src/lpc/ATTRIBUTION.md for the licenses and credits of these images.
(generate-library (apps hearsay art)
                  (import
                   (snail core base)
                   (lpc embed)
                   (lpc wardrobe)
                   (apps hearsay cast))
                  (embed-library (list "apps" "hearsay" "art")
                                 1000
                                 (delete-duplicates string=?
                                                    (concatenate
                                                     (map character-paths everyone)))))
