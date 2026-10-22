;; The LPC skin ramps, read from the character bases' palette file when this
;; library is built: `(ramp "olive")` gives that skin's colors, darkest
;; first, as 0xRRGGBB. A head drawn in one ramp is recolored to another by
;; swapping each color for the one at the same place.
(generate-library (lpc skins)
                  (import
                   (lofi base)
                   (lofi io)
                   (lpc embed))
                  (ramps-library "(lpc skins)" "lib/lpc/lpc-character-bases-v3_1/_build/palettes/skin.json"))
