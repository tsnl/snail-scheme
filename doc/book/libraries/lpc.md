# Liberated Pixel Cup art

`src/lpc/` holds packs of [Liberated Pixel Cup](https://lpc.opengameart.org/)
character art and the libraries that draw from them: bodies and heads from
the character bases, hair, and garments from the clothing updates and
wulax's sprites. A program dresses its characters from the catalog, and a
generated library embeds exactly the sheets they wear, with their credits
([the LPC test](https://github.com/tsnl/snail-scheme/blob/main/tests/programs/lpc.sld)
does this for a small cast).

## `(lpc layout)`

The geometry every LPC sheet shares: 832 by 1344 pixels of 64-pixel cells,
four rows each of casting, thrusting, walking and slashing, four of
shooting, and one of falling hurt, each motion's four rows facing away,
left, toward the viewer and right. `walk-region` is the four walking rows
alone, the first frame of each the figure standing still, and
`face-region`, in a picture of those rows, the standing figure facing the
viewer from the shoulders up: a portrait. `universal-book` and `walk-book`
are a whole sheet and its walking rows as `(snail shell sprite)`
spritebooks.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/lpc/layout.sld)

## `(lpc catalog)`

What the packs draw, and where: the adult `Build`s and `Head`s, `Skin`s,
`HairStyle`s and `HairColor`s, and `Garment`s in their `Dye`s, each named as
the pack's files name it. For each layer the catalog gives the file and
region holding its walking rows and the color swaps that recolor it
(`body-sheet`, `head-sheet`, `hair-sheet`, `garment-sheet`), and which
builds can wear each garment, in which dyes. Children, skeletons and zombies
are not catalogued yet.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/lpc/catalog.sld)

## `(lpc wardrobe)`

Characters dressed from the catalog: `dress` resolves an `Outfit` into the
sheets of a `Character`'s walking rows, so a character has a sheet for every
layer it wears, and `walk-picture` and `portrait` compose them into
`(snail shell graphics atlas)` pictures. `character-paths` lists the files a
character's layers come from, to embed, and `fingerprint` hashes its layers
and their swaps: equal characters agree, and a changed one almost surely
differs.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/lpc/wardrobe.sld)

## `(lpc skins)`

A generated library: the skin ramps, read from the character bases' palette
file when it is built. `(ramp "olive")` is that skin's colors, darkest
first; a head drawn in one ramp is recolored to another by swapping each
color for the one at the same place.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/lpc/skins.sld)

## `(lpc credits)`

Who made the sheets a program embeds, and under which licenses, read from
the packs' own credit files when the program is built: each `Credit` names
a part as its pack does, with its authors, its licenses and its sources,
which a CC-BY credit asks for. `credits-library` fails the build when an
embedded sheet has no credit, so what a program credits cannot fall behind
what it carries.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/lpc/credits.sld)

## `(lpc embed)`

Helpers for the `generate-library` recipes that embed the packs:
`embed-library` makes image files byte array literals, and `ramps-library`
makes the packs' JSON palettes color lists. A recipe runs when its library
is built, so an image's bytes reach the compiler as they are
([generated libraries](../snail-scheme/macros.md)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/lpc/embed.sld)
