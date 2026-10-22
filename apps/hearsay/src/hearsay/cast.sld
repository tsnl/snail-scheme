;; How the people of the prototypes look: an LPC character for each of the
;; rumor mill's 24 residents and for the favor ledger's rivals. Looks are
;; dealt from a fixed seed per person, so everyone looks the same in every
;; game and can be recognized across them. Each audience dresses in its own
;; colors: warm in the Market, workwear in the Docks, dark in the Tower.
(define-library (hearsay cast)
  (export
   resident
   rival
   everyone)
  (import
   (lofi base)
   (lofi random)
   (lpc catalog)
   (lpc wardrobe))
  (begin

    ;; ---- Dealing ----

    ;; One item of a list, and the generator after the draw.
    (: deal (All (T) (-> Random (List T) (Pair T Random))))
    (define (deal random items)
      (Pair (list-ref items (random-below random (length items))) (random-next random)))

    (: names->dyes (-> (List String) (List Dye)))
    (define (names->dyes names)
      (map Dye names))

    ;; ---- Wardrobe ----

    (: audience-dyes (-> I64 (List Dye)))
    (define (audience-dyes audience)
      (names->dyes (list-ref (list (list "maroon" "orange" "teal" "rose")
                                   (list "forest" "brown" "slate" "tan")
                                   (list "charcoal" "navy" "black" "white"))
                             audience)))

    (: build-heads (-> Build (List Head)))
    (define (build-heads build)
      (match build
        ((Female) (list (HumanFemale) (HumanFemale) (HumanFemale) (HumanFemaleElderly)))
        (_ (list (HumanMale) (HumanMale) (HumanMale) (HumanMaleElderly)))))

    (: elderly? (-> Head Bool))
    (define (elderly? head)
      (match head
        ((HumanMaleElderly) #t)
        ((HumanFemaleElderly) #t)
        (_ #f)))

    (define human-skins (map Skin (list "light" "amber" "olive" "taupe" "bronze" "brown" "black")))

    (define cuts (map HairStyle (list "bob" "buzzcut" "curly_short" "long_messy" "high_ponytail" "afro" "cowlick" "bangs_bun")))

    (: hair-shades (-> Head (List HairColor)))
    (define (hair-shades head)
      (map HairColor (if (elderly? head) (list "gray" "white") (list "black" "dark_brown" "chestnut" "blonde" "ginger"))))

    (: tops (-> Build (List Garment)))
    (define (tops build)
      (match build
        ((Male) (list (Longsleeve) (Shortsleeve) (Overalls) (Tabard)))
        ((Female) (list (Longsleeve) (Blouse) (Tunic) (Tanktop)))
        (_ (list (Longsleeve)))))

    (: bottoms (-> Build (List Garment)))
    (define (bottoms build)
      (match build
        ((Female) (list (Pants) (Skirt) (Leggings)))
        (_ (list (Pants)))))

    ;; Male pants come only in green; teens go barefoot, as no pack draws
    ;; their shoes.
    (: bottom-dye (-> Build Dye Dye))
    (define (bottom-dye build dye)
      (match build
        ((Male) (Dye "green"))
        (_ dye)))

    (: footwear (-> Build (List Garment)))
    (define (footwear build)
      (match build
        ((Teen) (Nil))
        (_ (list (Shoes) (Boots)))))

    ;; ---- People ----

    ;; A character dealt from `seed`, dressed in `palette`.
    (: dealt (-> I64 (List Dye) Character))
    (define (dealt seed palette)
      (let* ((r (make-random seed))
             (build (deal r (list (Male) (Female) (Teen)))) (head (deal (Pair-second build) (build-heads (Pair-first build))))
             (skin (deal (Pair-second head) human-skins)) (cut (deal (Pair-second skin) cuts))
             (shade (deal (Pair-second cut) (hair-shades (Pair-first head)))))
        (outfitted (Pair-first build) (Pair-first head) (Pair-first skin) (Hair (Pair-first cut) (Pair-first shade)) palette
                   (Pair-second shade))))

    (: outfitted (-> Build Head Skin Hair (List Dye) Random Character))
    (define (outfitted build head skin hair palette r)
      (let* ((top (deal r (tops build))) (top-dye (deal (Pair-second top) palette))
             (bottom (deal (Pair-second top-dye) (bottoms build))) (bottom-dye-drawn (deal (Pair-second bottom) palette))
             (shoes (match (footwear build)
                      ((Nil) (None))
                      (choices (Some (Worn (Pair-first (deal (Pair-second bottom-dye-drawn) choices)) (Dye "brown"))))))
             (outfit (Outfit (Some hair) (Some (Worn (Pair-first top) (Pair-first top-dye)))
                             (Some (Worn (Pair-first bottom) (bottom-dye build (Pair-first bottom-dye-drawn)))) shoes)))
        (match (dress build head skin outfit)
          ((Some character) character)
          ((None) (Character build head skin bare)))))

    ;; Resident `person` of the rumor mill, dressed in their audience's
    ;; colors.
    (: resident (-> I64 Character))
    (define (resident person)
      (dealt (+ 1000 (* 7919 person)) (audience-dyes (quotient person 8))))

    ;; The favor ledger's rivals: Vee (0) and Kit (1).
    (: rival (-> I64 Character))
    (define (rival index)
      (match index
        (0 (Character (Female) (HumanFemale) (Skin "bronze")
                      (Outfit (Some (Hair (HairStyle "high_ponytail") (HairColor "raven"))) (Some (Worn (Tunic) (Dye "purple")))
                              (Some (Worn (Leggings) (Dye "black"))) (Some (Worn (Boots) (Dye "black"))))))
        (_ (Character (Male) (HumanMale) (Skin "light")
                      (Outfit (Some (Hair (HairStyle "spiked") (HairColor "carrot"))) (Some (Worn (Tabard) (Dye "red")))
                              (Some (Worn (Pants) (Dye "green"))) (Some (Worn (Shoes) (Dye "black"))))))))

    ;; Everyone drawn, for embedding their art.
    (: everyone (List Character))
    (define everyone
      (append (map resident (iota 24)) (list (rival 0) (rival 1))))

    ))
