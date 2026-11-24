# Text and data

Pure libraries over values: numbers, text, and the encodings that carry
values to files, to the host and to the compiler.

## `(snail shell math)`

`pi`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `atan2`, `exp`, `log`
and `expt` on `F64`. They are FreeBSD's msun (fdlibm) as Rust's libm crate
carries it: the same polynomials, argument reductions and special cases, so
each result is within one ulp of the true value and equal to libm's bit for
bit, as `tests/programs/math` checks. WebAssembly has no floating-point
exception flags, so the originals' arithmetic done only to raise them is
left out.

`half-bits` rounds an `F32` to the nearest f16, ties to even, and answers
its 16 bits; `half-value` answers the value of such bits, exactly. Data
that the GPU reads as f16s packs them two to a 32-bit word, low first, as
WGSL's `unpack2x16float` reads them (`halves` in
[`(snail shell tensor)`](tensors.md)).

The point of porting rather than importing is that both hosts agree: the
same program gives the same bits on Node, on a page and on stage 0.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/math.sld)

## `(snail shell random)`

A SplitMix64 generator as a value: `make-random` from a seed, and
`random-next`, the generator after it. `random-value` is a generator's
number and `random-below` that number below a bound. Nothing is global, so
a program that threads its generator replays exactly, as Hearsay's games
and casts do, and as the trainer picks the order of its photographs.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/random.sld)

## `(snail shell text)`

Unicode character properties and case mapping: `char-upcase`,
`char-downcase` and `char-foldcase`, the `char-unicode-…?` and
`char-…-case?` tests, `char-digit-value`, and `string-upcase`,
`string-downcase` and `string-foldcase`. They read the constant arrays of
`(snail shell text unicode)`, which `make unicode-tables` generates from
Rust's Unicode 17.0.0 properties
(`crates/snail-scheme-support/examples/unicode-tables`); do not edit that
file, and `make check` fails when it falls behind its generator.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/text.sld)

## `(snail shell utf8)`

`string->utf8`, and `utf8->string`, which answers a `Utf8Error` with the
offset of the first ill-formed sequence rather than replacing it, as a
fatal `TextDecoder` does; a byte order mark stays text. Bytes become text
only when they are UTF-8, so a `String` is always well formed.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/utf8.sld)

## `(snail shell json)`

The `Json` value, with integer numbers apart from others and objects as
ordered members, and `json->string`, which writes what JavaScript's
`JSON.stringify` writes for the same value. It is a writer only.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/json.sld)

## `(snail shell json read)`

`string->json` reads any JSON text back as a `Json`, such as a language
server's message or a glTF scene, and `json-member` finds an object's
member. It is a library of its own so that a program that only writes JSON
does not carry a parser.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/json/read.sld)

## `(snail shell wire)`

Values as bytes and back. `(deriving Serialize Deserialize)` at the end of a
record or enum makes both instances; `serialize` writes a value and
`deserialize` reads it:

```scheme
(record Point
  ((x I64)
   (y I64))
  (deriving Serialize Deserialize))

(ann (deserialize (serialize (new Point (x 1) (y 2)))) Point)
```

Each record and enum case has a 32-bit TypeId hashed from its library, its
name and its fields' schema, and a value is written as its case's TypeId
followed by its fields. So data written for another schema fails to read at
the first type that changed, instead of being misread. Siegework and Hearsay
encode their saves this way, and `(snail shell explore)` identifies states
by their encoding.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/wire.sld)

## `(snail shell syntax)`

The `Syntax` a `generate-library` recipe returns: the `define-library` form
of the library it generates, built with `form` and `library-syntax`. Its
producer writes the form as bytes (`write-generated-library`), which the
compiler decodes, so no text is printed or parsed in between and a byte
array reaches the compiler as the bytes it holds. Generated syntax has no
locations: the compiler places every generated form at the recipe
([generated libraries](../snail-scheme/macros.md)). `linked-files` is the
definition of a list of files, each by a path of its own with the linked
file it names, as a dataset's library holds them
([datasets](datasets.md)).

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/syntax.sld)

## `(snail shell inflate)`

`inflate`, which decodes a DEFLATE stream (RFC 1951), the format a zip
archive's members, gzip files and PNG images keep their bytes in, into the
number of bytes it must make, as a zip archive's directory gives it. Its
stored, fixed and dynamic blocks are each a section of the source. The
input is read as a stream of bits whose place is threaded through every
step as a number, so decoding allocates nothing but its output and each
block's codes; a code of up to 10 bits is found in a table, and a longer
one a bit at a time. A stream that breaks the format, or makes more or
fewer bytes than it should, answers why. It decodes about 55 MB a second
on Node.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/inflate.sld)

## `(snail shell zip)`

Zip archives, read a member at a time, as from a server that answers any
range of an archive's bytes: `zip-directory` finds the directory from the
archive's last `end-bytes`, `zip-entries` reads it into `ZipEntry`
records, each with its span of the archive, from its local header to the
next member's, and `entry-contents` gives a member's bytes from its span,
kept as they are or deflated, checked against the directory's length and
CRC-32 (`crc32`). An archive past 4 GiB, or of more than 65,535 members,
keeps its wide numbers in Zip64's records, which every function reads.
Nothing here reads a file or the web: each function reads the bytes it is
given. Encrypted members, other methods and names that are not UTF-8 are
refused.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/zip.sld)

## `(snail shell compiler sha256)`

`sha256` over a byte array, and `bytes->hex`, the lowercase hex Node's
`digest('hex')` writes. The compiler names each file it links by this
digest, so stage 0 must compute the same one: a word is an `I64` holding an
unsigned 32-bit value, masked back to 32 bits after each sum and shift,
where WebAssembly's `i32` would wrap and Chez's integers would grow.

[Source](https://github.com/tsnl/snail-scheme/blob/main/src/snail/shell/compiler/sha256.sld)
