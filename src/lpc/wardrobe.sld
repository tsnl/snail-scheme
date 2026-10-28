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
   Character-sheets
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

    (struct Hair
      ((style HairStyle)
       (color HairColor))
      (deriving Serialize Deserialize))

    (struct Worn
      ((garment Garment)
       (dye Dye))
      (deriving Serialize Deserialize))

    ;; One garment at most in each slot.
    (struct Outfit
      ((hair (Option Hair))
       (torso (Option Worn))
       (legs (Option Worn))
       (feet (Option Worn)))
      (deriving Serialize Deserialize))

    ;; ---- Dressing ----

    ;; The sheets of a character's walking rows, bottom first.
    (struct Character
      ((sheets (List Sheet))))

    ;; A character wearing `outfit`, if every garment in it is worn in its
    ;; own slot and drawn for `build`. Its layers are the body, the feet,
    ;; the legs, the torso, the head, and the hair over the head.
    (: dress (-> Build Head Skin Outfit (Option Character)))
    (define (dress build head skin outfit)
      (match (list (worn-sheets build (Feet) (Outfit-feet outfit))
                   (worn-sheets build (Legs) (Outfit-legs outfit))
                   (worn-sheets build (Torso) (Outfit-torso outfit)))
        ((Cons (Some feet) (Cons (Some legs) (Cons (Some torso) (Nil))))
         (Some (Character (concatenate (list (list (body-sheet build skin))
                                             feet
                                             legs
                                             torso
                                             (list (head-sheet head skin))
                                             (match (Outfit-hair outfit)
                                               ((Some (Hair style color))
                                                (list (hair-sheet build style color)))
                                               ((None) (Nil))))))))
        (_ (None))))

    ;; The sheet a slot's garment is drawn on, none for an empty slot, or
    ;; None for a garment worn in another slot or not drawn for `build`.
    (: worn-sheets (-> Build Slot (Option Worn) (Option (List Sheet))))
    (define (worn-sheets build slot worn)
      (match worn
        ((Some (Worn garment dye))
         (if (same-slot? slot (garment-slot garment))
             (match (garment-sheet build garment dye)
               ((Some sheet) (Some (list sheet)))
               ((None) (None)))
             (None)))
        ((None) (Some (Nil)))))

    (: same-slot? (-> Slot Slot Bool))
    (define (same-slot? a b)
      (match (Pair a b)
        ((Pair (Torso) (Torso)) #t)
        ((Pair (Legs) (Legs)) #t)
        ((Pair (Feet) (Feet)) #t)
        (_ #f)))

    ;; The files the character's layers come from, to embed.
    (: character-paths (-> Character (List String)))
    (define (character-paths who)
      (map Sheet-path (Character-sheets who)))

    ;; ---- Pictures ----

    ;; A 32-bit FNV-1a hash, a word at a time, of each layer's path and
    ;; swaps: equal characters agree, and a changed one almost surely
    ;; differs.
    (: fingerprint (-> Character I32))
    (define (fingerprint who)
      (fold-left (lambda (hash word) (* (i32-xor hash word) 16777619))
                 -2128831035
                 (concatenate (map sheet-words (Character-sheets who)))))

    (: sheet-words (-> Sheet (List I32)))
    (define (sheet-words sheet)
      (append (map char->i32 (string->list (Sheet-path sheet)))
              (concatenate (map (lambda (swap) (list (Pair-first swap) (Pair-second swap)))
                                (Sheet-swaps sheet)))))

    ;; The character's walking rows as picture `key`, from the sources `art`
    ;; finds for each sheet. Its version is the character's fingerprint, so
    ;; the host composes it again only when the character changes. A sheet
    ;; whose file `art` lacks is left out.
    (: walk-picture (-> (-> String (Option Source)) I32 Character Picture))
    (define (walk-picture art key who)
      (Picture key (fingerprint who) (Rect-width walk-region) (Rect-height walk-region)
               (lambda ()
                 (concatenate
                  (map (lambda (sheet)
                         (match (art (Sheet-path sheet))
                           ((Some source)
                            (list (Layer source (Sheet-from sheet) 0 0 (Sheet-swaps sheet))))
                           ((None) (Nil))))
                       (Character-sheets who))))))

    ;; The character in picture `key`, shoulders up, each texel `scale`
    ;; pixels wide.
    (: portrait (-> String I32 I32 Widget))
    (define (portrait look-key key scale)
      (Image (look look-key) key face-region scale))

    ))
