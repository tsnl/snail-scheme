// `snail-scheme`'s syntax for editors, following the compiler's reader
// (src/snail/shell/compiler/read.sld, "Lexemes"). The reader decides what a
// program means; this grammar only has to agree with it on where each datum
// and each comment starts and ends, so editors can color, indent, match
// brackets and outline. tests/tree-sitter.mjs parses every tracked Scheme
// file with it and fails on any error.
//
// The rules the reader uses:
// - Atmosphere between data: whitespace, `;` to the end of the line, `#|`
//   block comments, which nest, and `#;`, which comments out
//   the datum after it.
// - A list opens with `(` or `[` and closes with the same kind of bracket;
//   `#u8(` opens a byte array; `'` quotes the datum after it.
// - A string runs to the first quote no backslash escapes, across lines.
// - `#\` takes the character after it, whatever it is, then runs on to a
//   delimiter, as in `#\space`.
// - Any other text up to a delimiter is one token: `#t`, `#true`, `#f` and
//   `#false` are booleans, a decimal integer or float is a number, and the
//   rest are names. The delimiters are whitespace, the brackets, `"`, `;`
//   and `'`, so a backtick or comma is part of a name.
//
// src/scanner.c reads the block comments and the tokens, since only a
// token's whole text says what it is. A token the reader rejects, such as
// `.` or `#x1F`, is a name here: the compiler reports it, and the editor
// still sees where it ends. So Chez's own syntax, in host/chez/, parses too.

// tree-sitter's generator (0.26) leaves U+017F, the long s, and U+212A, the
// Kelvin sign, out of every negated class and out of `.`: the two scalars
// that case-fold to an ASCII letter. A string or a comment holding one
// would end there, so each such class names them beside it.
const folded = /[\u017F\u212A]/;
const any = pattern => choice(pattern, folded);

module.exports = grammar({
  name: 'snail_scheme',

  externals: $ => [$.block_comment, $.symbol, $.number, $.boolean, $.character],

  extras: $ => [/\s/, $.line_comment, $.block_comment, $.datum_comment],

  rules: {
    source: $ => repeat($._datum),

    _datum: $ => choice(
      $.list,
      $.bytes,
      $.quote,
      $.string,
      $.character,
      $.boolean,
      $.number,
      $.symbol,
    ),

    list: $ => choice(
      seq('(', repeat($._datum), ')'),
      seq('[', repeat($._datum), ']'),
    ),

    bytes: $ => seq('#u8(', repeat($._datum), ')'),

    quote: $ => seq('\'', $._datum),

    string: _ => token(seq('"', repeat(choice(any(/[^"\\]/), seq('\\', any(/[\s\S]/)))), '"')),

    line_comment: _ => token(seq(';', repeat(any(/./)))),

    datum_comment: $ => seq('#;', $._datum),
  },
});
