# Strict Unicode character helpers and string ordering

Import `(snail text)` alongside `(snail strict)` for these concrete operations:

| Operation | Signature | Behavior |
| --- | --- | --- |
| `char-downcase` | `Char -> Char` | Existing Unicode simple lowercase mapping |
| `char-alphabetic?` | `Char -> Bool` | Existing Rust Unicode Alphabetic property |
| `char-numeric?` | `Char -> Bool` | Unicode decimal digit membership |
| `char-whitespace?` | `Char -> Bool` | The strict datum reader's exact whitespace provider |
| `string<?` | `String, String -> Bool` | Lexicographic Unicode scalar ordering |

The character operations reuse the ordinary runtime's semantics. Simple
lowercase returns one scalar and has no locale or surrounding-string context:
`İ` becomes `i`, `Σ` becomes `σ`, and supplementary-plane letters retain their
simple mappings. It does not perform full string lowercase expansion or case
folding. Decimal digits include `٣` and digits from other scripts; superscript
`²` and Roman `Ⅷ` are not decimal digits.

`unicode.rs` supplies the existing Unicode 16.0 simple casing exceptions and
decimal tables. Alphabetic and whitespace use the Rust runtime's Unicode
property tables, as the existing legacy character operations do; this API does
not independently freeze their version. The corresponding Rust
[`char` predicates](https://doc.rust-lang.org/std/primitive.char.html) document
those Unicode properties. Whitespace directly binds `snail:datum/whitespace`,
so its meaning and malformed-input handling are shared with the strict reader.

The three new Rust exports accept a scalar code point and return a scalar code
point or a 0/1 I32 predicate result. Scheme turns predicate results into Bool.
Neither side transfers Scheme values, roots or callback state. Invalid raw
foreign callers report `invalid Unicode scalar` after terminal file/token
cleanup. NUL, supplementary scalars, private-use characters and noncharacters
remain valid. The same Rust functions execute through linked Wasm and native64.

`string<?` is an ordinary Scheme loop over the current String contents. All
characters before its index are equal. It checks both ends before reading;
the first unequal scalar decides, otherwise the proper prefix is smaller.
Equal strings, including the same storage, return false. For example,
`"Z" < "a"`, U+E000 sorts before U+10000, and `"e\x301;"` sorts before `"é"`.
It performs no normalization, case folding, locale collation, byte conversion,
allocation or input mutation. Each call reads the current contents, including
mutations made since an earlier comparison. Concurrent mutation during a call
is outside this sequential library contract. The supported arity is two strings.

`scripts/test-strict-text` retains sources, artifacts, commands and complete
scalar output on raw/optimized linked Wasm and native64. Its independent casing
and decimal oracle requires Python's Unicode 16.0.0 data and includes all
changed lowercase mappings, all decimal digits, fixed Alphabetic/White_Space
cases, ASCII and seeded scalar samples. Additional tests cover prefix and
scalar ordering, long equal prefixes, mutable contents and terminal malformed
raw callers with observed release before the error.
