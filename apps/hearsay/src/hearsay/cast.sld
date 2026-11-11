;; How the people of the prototypes look: an LPC character for each of the
;; rumor mill's residents and for the favor ledger's rivals. Looks are
;; dealt from a fixed seed per person, so everyone looks the same in every
;; game and can be recognized across them. Each audience dresses in its own
;; colors: warm in the Market, workwear in the Docks, dark in the Tower.
(define-library (hearsay cast)
  (export
   resident
   rival
   everyone
   person-picture
   rival-picture)
  (import
   (snail core base)
   (snail shell random)
   (lpc catalog)
   (lpc wardrobe)
   (only (hearsay mill) person-count audience-of)
   (only (hearsay ledger) vee kit))
  (begin

    ;; ---- Dealing ----

    ;; One item of a list, and the generator after the draw.
    (: deal (All (T) (requires (Copy T)) (impl (Fn Random (List T) -> (Pair T Random)))))
    (define (deal random items)
      (Pair (list-ref items (random-below random (length items))) (random-next random)))

    (: names->dyes (impl (Fn (List String) -> (List Dye))))
    (define (names->dyes names)
      (map Dye names))

    ;; ---- Wardrobe ----

    (: audience-dyes (impl (Fn I64 -> (List Dye))))
    (define (audience-dyes audience)
      (names->dyes (list-ref (list (list "maroon" "orange" "teal" "rose")
                                   (list "forest" "brown" "slate" "tan")
                                   (list "charcoal" "navy" "black" "white"))
                             audience)))

    (: build-heads (impl (Fn Build -> (List Head))))
    (define (build-heads build)
      (match build
        ((Female) (list (HumanFemale) (HumanFemale) (HumanFemale) (HumanFemaleElderly)))
        (_ (list (HumanMale) (HumanMale) (HumanMale) (HumanMaleElderly)))))

    (: elderly? (impl (Fn Head -> Bool)))
    (define (elderly? head)
      (match head
        ((HumanMaleElderly) #t)
        ((HumanFemaleElderly) #t)
        (_ #f)))

    (define human-skins (map Skin (list "light" "amber" "olive" "taupe" "bronze" "brown" "black")))

    (define cuts
      (map HairStyle
           (list "bob"
                 "buzzcut"
                 "curly_short"
                 "long_messy"
                 "high_ponytail"
                 "afro"
                 "cowlick"
                 "bangs_bun")))

    (: hair-shades (impl (Fn Head -> (List HairColor))))
    (define (hair-shades head)
      (map HairColor
           (if (elderly? head)
               (list "gray" "white")
               (list "black" "dark_brown" "chestnut" "blonde" "ginger"))))

    (: tops (impl (Fn Build -> (List Garment))))
    (define (tops build)
      (match build
        ((Male) (list (Longsleeve) (Shortsleeve) (Overalls) (Tabard)))
        ((Female) (list (Longsleeve) (Blouse) (Tunic) (Tanktop)))
        (_ (list (Longsleeve)))))

    (: bottoms (impl (Fn Build -> (List Garment))))
    (define (bottoms build)
      (match build
        ((Female) (list (Pants) (Skirt) (Leggings)))
        (_ (list (Pants)))))

    (define footwear (list (Shoes) (Boots)))

    ;; Dark enough to tell from skin and floor at sprite size.
    (define shoe-dyes (map Dye (list "black" "charcoal" "walnut")))

    ;; A garment in the dye dealt, if the catalog draws it in that for the
    ;; build, and otherwise in the first dye it does: male pants come only
    ;; in green.
    (: worn-in (impl (Fn Build Garment Dye -> Worn)))
    (define (worn-in build garment dye)
      (let ((drawn (garment-dyes build garment)))
        (Worn garment
              (if (any? (lambda (other) (string=? (::name other) (::name dye))) drawn)
                  dye
                  (match drawn
                    ((Cons first _) first)
                    ((Nil) dye))))))

    ;; Every look dealt here is one the catalog draws, so dressing never
    ;; fails. Were the tables to drift from the catalog, building (hearsay
    ;; art), which dresses everyone, would stop here.
    (: dressed (impl (Fn Build Head Skin Outfit -> Character)))
    (define (dressed build head skin outfit)
      (match (dress build head skin outfit)
        ((Some character) character)
        ((None) (panic "the cast wears something the catalog does not draw"))))

    ;; ---- People ----

    ;; A character dealt from `seed`, dressed in `palette`.
    (: dealt (impl (Fn I64 (List Dye) -> Character)))
    (define (dealt seed palette)
      (let* ((r (make-random seed))
             (build (deal r (list (Male) (Female) (Teen))))
             (head (deal (::second build) (build-heads (::first build))))
             (skin (deal (::second head) human-skins)) (cut (deal (::second skin) cuts))
             (shade (deal (::second cut) (hair-shades (::first head)))))
        (outfitted (::first build)
                   (::first head)
                   (::first skin)
                   (Hair (::first cut) (::first shade))
                   palette
                   (::second shade))))

    (: outfitted (impl (Fn Build Head Skin Hair (List Dye) Random -> Character)))
    (define (outfitted build head skin hair palette r)
      (let* ((top (deal r (tops build))) (top-dye (deal (::second top) palette))
             (bottom (deal (::second top-dye) (bottoms build)))
             (bottom-dye (deal (::second bottom) palette))
             (shoe (deal (::second bottom-dye) footwear))
             (shoe-dye (deal (::second shoe) shoe-dyes)))
        (dressed build head skin
                 (Outfit (Some hair) (Some (worn-in build (::first top) (::first top-dye)))
                         (Some (worn-in build (::first bottom) (::first bottom-dye)))
                         (Some (worn-in build (::first shoe) (::first shoe-dye)))))))

    ;; Resident `person` of the rumor mill, dressed in their audience's
    ;; colors.
    (: resident (impl (Fn I64 -> Character)))
    (define (resident person)
      (dealt (+ 1000 (* 7919 person)) (audience-dyes (audience-of person))))

    ;; The favor ledger's rivals, by fixer: Vee, and otherwise Kit.
    (: rival (impl (Fn I64 -> Character)))
    (define (rival who)
      (if (= who vee)
          (dressed (Female) (HumanFemale) (Skin "bronze")
                   (Outfit (Some (Hair (HairStyle "high_ponytail") (HairColor "raven")))
                           (Some (Worn (Tunic) (Dye "purple")))
                           (Some (Worn (Leggings) (Dye "black")))
                           (Some (Worn (Boots) (Dye "black")))))
          (dressed (Male) (HumanMale) (Skin "light")
                   (Outfit (Some (Hair (HairStyle "spiked") (HairColor "carrot")))
                           (Some (Worn (Tabard) (Dye "red")))
                           (Some (Worn (Pants) (Dye "green")))
                           (Some (Worn (Shoes) (Dye "black")))))))

    ;; Everyone drawn, for embedding their art.
    (: everyone (List Character))
    (define everyone
      (append (map resident (iota person-count)) (list (rival vee) (rival kit))))

    ;; ---- Pictures ----

    ;; The screens key the pictures they compose of the cast: 100 + p for
    ;; resident p, and 200 + f for the rival who is fixer f.
    (: person-picture (impl (Fn I64 -> I32)))
    (define (person-picture person)
      (i64->i32 (+ 100 person)))

    (: rival-picture (impl (Fn I64 -> I32)))
    (define (rival-picture who)
      (i64->i32 (+ 200 who)))

    ))
