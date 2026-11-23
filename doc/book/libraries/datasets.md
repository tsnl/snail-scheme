# Datasets

`src/datasets/` holds no data. Its libraries are recipes that read a
published dataset into the machine's cache the first time a program that
imports one is built, and link each of its files, so the program reads
them as resources and ships them in its `store/`
([generated libraries](../snail-scheme/macros.md#generated-libraries)).
A dataset is then a dependency of the program, as the LPC art is
([LPC](lpc.md)): what a program imports is what it carries, and which
scene it trains on is in its source, not in a path given when it runs.

## `(datasets mipnerf360)`

Mip-NeRF 360's nine scenes (Barron et al., 2022), each photographed from
all around, with COLMAP's sparse reconstruction, `sparse/0`, and the
photographs at their full size, `images`, and at a half, a quarter and an
eighth of it, `images_2`, `images_4` and `images_8`. Google publishes
seven in one archive of 12.5 GB and flowers and treehill in another of
4.5 GB; each is pinned here by its end's digest, and a scene's files are
read from it a member at a time ([`(snail shell web zip)`](system.md#snail-shell-web-zip)),
so a scene at the size 3D Gaussian Splatting trains it is a few hundred
megabytes, fetched once a machine.

`scene-library` is a recipe's work: the library of a scene's
reconstruction and one folder of its photographs, exporting `files`, each
file by its path in the scene, such as `"sparse/0/cameras.bin"`, with its
`Resource`, and `photographs`, the folder's name. A program that wants
another folder makes a library of its own, as each scene's below does
with the paper's:

```scheme
(generate-library (apps train full)
                  (import
                   (snail core base)
                   (only (snail core io) Fs ProcessEnvironment)
                   (only (snail shell web) Web)
                   (datasets mipnerf360))
                  (lambda ((fs Fs) (web Web) (environment ProcessEnvironment))
                    (scene-library fs web environment
                                   (list "apps" "train" "full")
                                   "bicycle"
                                   "images")))
```

`scene-folder` reads the same files and answers where the cache keeps
them, for a program that reads a folder, as the reference trainers of
[`benches/splat-training`](https://github.com/tsnl/snail-scheme/blob/main/benches/splat-training/README.md)
do. Bicycle's are in
`~/.cache/snail-scheme/zip/0be64f576d63b68855fc9746daa2d62262f013c2ddf82abf20aadbf62c0f8477/bicycle/`,
its `sparse/0/images.bin` among them, which the splat viewer turns a
trained cloud upright by.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/datasets/mipnerf360.sld)

## The scenes

Each scene's library holds its reconstruction and its photographs at the
size the paper trains it: the outdoor scenes at a quarter, the indoor at a
half. Its files are what the program ships; the archive keeps them
deflated, so less is fetched.

| Library | Photographs | Files | Fetched |
| --- | --- | ---: | ---: |
| `(datasets mipnerf360 bicycle)` | 194 at `images_4` | 225 MB | 201 MB |
| `(datasets mipnerf360 flowers)` | 173 at `images_4` | 223 MB | 201 MB |
| `(datasets mipnerf360 garden)` | 185 at `images_4` | 257 MB | 233 MB |
| `(datasets mipnerf360 stump)` | 125 at `images_4` | 139 MB | 125 MB |
| `(datasets mipnerf360 treehill)` | 141 at `images_4` | 168 MB | 151 MB |
| `(datasets mipnerf360 bonsai)` | 292 at `images_2` | 373 MB | 335 MB |
| `(datasets mipnerf360 counter)` | 240 at `images_2` | 320 MB | 291 MB |
| `(datasets mipnerf360 kitchen)` | 279 at `images_2` | 431 MB | 385 MB |
| `(datasets mipnerf360 room)` | 311 at `images_2` | 336 MB | 315 MB |

The first build of a program that imports bicycle took about 40 seconds
here, most of it fetching; later builds, in any checkout, link the files
from the cache, and the library's recipe adds about half a second to a
build. An editor that checks such a program runs its recipes as a build
does ([editors](../snail-scheme/toolchain.md#editors)), so it may be the
one that fetches first. The build also places each file in the workspace's store, as it
places every linked file, so each checkout that builds the program holds
a copy of the scene beside the machine's.

[Source](https://github.com/tsnl/snail-scheme/tree/main/src/datasets/mipnerf360)
