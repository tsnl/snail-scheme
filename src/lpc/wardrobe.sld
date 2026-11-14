;; Characters dressed from the catalog, and what drawing one takes. Dressing
;; resolves an outfit into the sheets of a character's walking rows, so a
;; character always has a sheet for every layer it wears; this library
;; composes them into the character's picture and portrait.
(define-library (lpc wardrobe)
  (export
   Hair
   Worn
   Outfit
   Character
   dress
   character-paths
   fingerprint
   walk-picture
   portrait)
  (import
   (snail core base)
   (snail shell wire)
   (snail shell app)
   (lpc layout)
   (lpc catalog))
  (begin

    ;; ---- Outfits ----

    (record Hair
      ((style HairStyle)
       (color HairColor))
      (deriving Serialize Deserialize))

    (record Worn
      ((garment Garment)
       (dye Dye))
      (deriving Serialize Deserialize))

    ;; One garment at most in each slot.
    (record Outfit
      ((hair (Option Hair))
       (torso (Option Worn))
       (legs (Option Worn))
       (feet (Option Worn)))
      (deriving Serialize Deserialize))

    ;; ---- Dressing ----

    ;; The sheets of a character's walking rows, bottom first.
    (record Character
      ((sheets (List Sheet))))

    ;; A character wearing `outfit`, if every garment in it is worn in its
    ;; own slot and drawn for `build`. Its layers are the body, the feet,
    ;; the legs, the torso, the head, and the hair over the head.
    (define (dress (build Build) (head Head) (skin Skin) (outfit Outfit)) (→ (Option Character))
      (match (list (worn-sheets build (Feet) (● outfit feet))
                   (worn-sheets build (Legs) (● outfit legs))
                   (worn-sheets build (Torso) (● outfit torso)))
        ((Cons (Some feet) (Cons (Some legs) (Cons (Some torso) (Nil))))
         (Some (new Character (sheets (concatenate (list (list (body-sheet build skin))
                                                         feet
                                                         legs
                                                         torso
                                                         (list (head-sheet head skin))
                                                         (match (● outfit hair)
                                                           ((Some (Hair style color))
                                                            (list (hair-sheet build style color)))
                                                           ((None) (Nil)))))))))
        (_ (None))))

    ;; The sheet a slot's garment is drawn on, none for an empty slot, or
    ;; None for a garment worn in another slot or not drawn for `build`.
    (define (worn-sheets (build Build) (slot Slot) (worn (Option Worn))) (→ (Option (List Sheet)))
      (match worn
        ((Some (Worn garment dye))
         (if (same-slot? slot (garment-slot garment))
             (match (garment-sheet build garment dye)
               ((Some sheet) (Some (list sheet)))
               ((None) (None)))
             (None)))
        ((None) (Some (Nil)))))

    (define (same-slot? (a Slot) (b Slot)) (→ Bool)
      (match (new Pair (first a) (second b))
        ((Pair (Torso) (Torso)) #t)
        ((Pair (Legs) (Legs)) #t)
        ((Pair (Feet) (Feet)) #t)
        (_ #f)))

    ;; The files the character's layers come from, to embed.
    (define (character-paths (who Character)) (→ (List String))
      (map (lambda (record) (● record path)) (● who sheets)))

    ;; ---- Pictures ----

    ;; A 32-bit FNV-1a hash, a word at a time, of each layer's path and
    ;; swaps: equal characters agree, and a changed one almost surely
    ;; differs.
    (define (fingerprint (who Character)) (→ I32)
      (fold-left (lambda (hash word) (* (i32-xor hash word) 16777619))
                 -2128831035
                 (concatenate (map sheet-words (● who sheets)))))

    (define (sheet-words (sheet Sheet)) (→ (List I32))
      (append (map char->i32 (string->list (● sheet path)))
              (concatenate (map (lambda (swap) (list (● swap first) (● swap second)))
                                (● sheet swaps)))))

    ;; The character's walking rows as picture `key`, from the sources `art`
    ;; finds for each sheet. Its version is the character's fingerprint, so
    ;; the host composes it again only when the character changes. A sheet
    ;; whose file `art` lacks is left out.
    (define (walk-picture (art (Fn String → (Option Source))) (key I32) (who Character))
      (→ Picture)
      (new Picture
        (key key)
        (version (fingerprint who))
        (width (● (walk-region) width))
        (height (● (walk-region) height))
        (layers (lambda ()
                  (concatenate
                   (map (lambda (sheet)
                          (match (art (● sheet path))
                            ((Some source)
                             (list (new Layer
                                     (source source)
                                     (from (● sheet from))
                                     (x 0)
                                     (y 0)
                                     (swaps (● sheet swaps)))))
                            ((None) (Nil))))
                        (● who sheets)))))))

    ;; The character in picture `key`, shoulders up, each texel `scale`
    ;; pixels wide.
    (define (portrait (look-key String) (key I32) (scale I32)) (→ Widget)
      (Image (look look-key) key (face-region) scale))

    ))
