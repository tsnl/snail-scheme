;; Characters dressed from the catalog, and what drawing one takes: the
;; layers of its walking rows in order, the picture composed from them, its
;; spritebook and its portrait. A character is data, so a program can keep,
;; save and compare it; this library turns it into pictures, the way a
;; prefab becomes an instance.
(define-library (lpc wardrobe)
  (export
   Hair
   Worn
   Outfit
   bare
   Character
   Character-build
   Character-head
   Character-skin
   Character-outfit
   dress
   character-sheets
   character-paths
   fingerprint
   walk-picture
   character-book
   portrait)
  (import
   (lofi base)
   (lofi wire)
   (lofi app)
   (lofi sprite)
   (lpc layout)
   (lpc catalog))
  (begin

    ;; ---- Characters ----

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

    (define bare (Outfit (None) (None) (None) (None)))

    (struct Character
      ((build Build)
       (head Head)
       (skin Skin)
       (outfit Outfit))
      (deriving Serialize Deserialize))

    ;; A character wearing `outfit`, if every garment in it is worn in its
    ;; own slot and drawn for `build`. A character made here always has a
    ;; sheet for each layer.
    (: dress (-> Build Head Skin Outfit (Option Character)))
    (define (dress build head skin outfit)
      (if (and (fits? build (Torso) (Outfit-torso outfit)) (fits? build (Legs) (Outfit-legs outfit))
               (fits? build (Feet) (Outfit-feet outfit)))
          (Some (Character build head skin outfit))
          (None)))

    (: fits? (-> Build Slot (Option Worn) Bool))
    (define (fits? build slot worn)
      (match worn
        ((Some (Worn garment dye))
         (and (same-slot? slot (garment-slot garment)) (match (garment-sheet build garment dye) ((Some _) #t) ((None) #f))))
        ((None) #t)))

    (: same-slot? (-> Slot Slot Bool))
    (define (same-slot? a b)
      (match (Pair a b)
        ((Pair (Torso) (Torso)) #t)
        ((Pair (Legs) (Legs)) #t)
        ((Pair (Feet) (Feet)) #t)
        (_ #f)))

    ;; ---- Layers ----

    ;; The sheets of the walking rows, bottom first: body, feet, legs, torso,
    ;; head, then hair over the head.
    (: character-sheets (-> Character (List Sheet)))
    (define (character-sheets who)
      (let* ((build (Character-build who)) (outfit (Character-outfit who))
             (worn (lambda (slot) (match slot
                                    ((Some (Worn garment dye)) (match (garment-sheet build garment dye) ((Some sheet) (list sheet)) ((None) (Nil))))
                                    ((None) (Nil))))))
        (concatenate
         (list (list (body-sheet build (Character-skin who)))
               (worn (Outfit-feet outfit)) (worn (Outfit-legs outfit)) (worn (Outfit-torso outfit))
               (list (head-sheet (Character-head who) (Character-skin who)))
               (match (Outfit-hair outfit)
                 ((Some (Hair style color)) (list (hair-sheet build style color)))
                 ((None) (Nil)))))))

    ;; The files the character's layers come from, to embed.
    (: character-paths (-> Character (List String)))
    (define (character-paths who)
      (map Sheet-path (character-sheets who)))

    ;; ---- Pictures ----

    ;; A 32-bit FNV-1a hash of the character's wire encoding: equal
    ;; characters agree, and a changed one almost surely differs.
    (: fingerprint (-> Character I32))
    (define (fingerprint who)
      (vector-fold (lambda (hash byte) (* (i32-xor hash (u8->i32 byte)) 16777619)) -2128831035 (serialize who)))

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
                           ((Some source) (list (Layer source (Sheet-from sheet) 0 0 (Sheet-swaps sheet))))
                           ((None) (Nil))))
                       (character-sheets who))))))

    (: character-book (-> I32 (Spritebook Gait)))
    (define (character-book key)
      (walk-book key))

    ;; The character in picture `key`, shoulders up, each texel `scale`
    ;; pixels wide.
    (: portrait (-> String I32 I32 Widget))
    (define (portrait look-key key scale)
      (Image (look look-key) key face-region scale))

    ))
