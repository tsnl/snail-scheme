;; The credits of the LPC sheets the cast wears, read from the packs'
;; credit files when this library is built: the same files
;; (apps hearsay art) embeds, so the credits name every sheet the program
;; carries. The menu's Credits screen shows them.
(generate-library (apps hearsay credits)
                  (import
                   (snail core base)
                   (lpc credits)
                   (lpc wardrobe)
                   (apps hearsay cast))
                  (credits-library (list "apps" "hearsay" "credits")
                                   (delete-duplicates string=?
                                                      (concatenate
                                                       (map character-paths everyone)))))
