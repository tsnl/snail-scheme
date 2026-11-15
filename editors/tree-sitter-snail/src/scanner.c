// The tokens a regular expression cannot read as the reader does
// (src/snail/shell/compiler/read.sld, "Lexemes"):
//
// - Block comments nest: `#|` opens one level and `|#` closes one. A comment
//   the text ends inside runs to the end, as the reader's scan does before it
//   reports that the comment is not closed.
// - Every other token runs to a delimiter and only then is classified, by
//   its whole text, as `token-kind` does: a boolean, a number, or a name. A
//   lexer that tried each kind's pattern would stop `1.2.3` after `1.2`.
// - `#\` takes the character after it, whatever it is, then runs on to a
//   delimiter.
//
// `#;` and `#u8(` are left to the grammar's own lexer: the scanner declines
// them, and declining undoes what it read.

#include "tree_sitter/parser.h"

#include <stdbool.h>
#include <string.h>

enum TokenType { BLOCK_COMMENT, SYMBOL, NUMBER, BOOLEAN, CHARACTER };

void *tree_sitter_snail_external_scanner_create(void) { return NULL; }

void tree_sitter_snail_external_scanner_destroy(void *payload) {}

unsigned tree_sitter_snail_external_scanner_serialize(void *payload, char *buffer) { return 0; }

void tree_sitter_snail_external_scanner_deserialize(void *payload, const char *buffer,
                                                    unsigned length) {}

// ---- Characters ----

static bool whitespace(int32_t c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' || c == '\v';
}

static bool delimiter(TSLexer *lexer) {
  int32_t c = lexer->lookahead;
  return lexer->eof(lexer) || whitespace(c) || c == '(' || c == ')' || c == '[' || c == ']' ||
         c == '"' || c == ';' || c == '\'';
}

static bool digit(char c) { return c >= '0' && c <= '9'; }

// ---- Classifying a token ----

// A token's text, as far as classifying it needs: a number or boolean is
// short, so a longer token is a name whatever it holds.
#define KEPT 64

typedef struct {
  char text[KEPT + 1];
  unsigned length;
  bool long_token;
} Token;

static bool all_digits(const char *text, unsigned length) {
  if (length == 0) return false;
  for (unsigned i = 0; i < length; i++)
    if (!digit(text[i])) return false;
  return true;
}

// Digits with at most one point, and at least one digit.
static bool mantissa(const char *text, unsigned length) {
  unsigned digits = 0, points = 0;
  for (unsigned i = 0; i < length; i++) {
    if (digit(text[i])) digits++;
    else if (text[i] == '.') points++;
    else return false;
  }
  return digits > 0 && points <= 1;
}

static bool exponent(const char *text, unsigned length) {
  if (length > 0 && (text[0] == '-' || text[0] == '+')) {
    text++;
    length--;
  }
  return all_digits(text, length);
}

// An optionally signed decimal integer, or a decimal float with a point or
// an exponent, split at its first `e`.
static bool number(const char *text, unsigned length) {
  if (length > 0 && (text[0] == '-' || text[0] == '+')) {
    text++;
    length--;
  }
  if (length == 0 || !(digit(text[0]) || text[0] == '.')) return false;
  if (all_digits(text, length)) return true;
  for (unsigned i = 0; i < length; i++) {
    if (text[i] == 'e' || text[i] == 'E')
      return mantissa(text, i) && exponent(text + i + 1, length - i - 1);
  }
  return mantissa(text, length) && memchr(text, '.', length) != NULL;
}

static bool boolean(const char *text) {
  return strcmp(text, "#t") == 0 || strcmp(text, "#true") == 0 || strcmp(text, "#f") == 0 ||
         strcmp(text, "#false") == 0;
}

static enum TokenType token_type(Token *token) {
  if (token->long_token) return SYMBOL;
  if (boolean(token->text)) return BOOLEAN;
  if (number(token->text, token->length)) return NUMBER;
  return SYMBOL;
}

// ---- Reading ----

static void keep(Token *token, int32_t c) {
  if (token->length < KEPT && c < 128) token->text[token->length++] = (char)c;
  else token->long_token = true;
  token->text[token->length] = '\0';
}

static void take(TSLexer *lexer, Token *token) {
  keep(token, lexer->lookahead);
  lexer->advance(lexer, false);
}

static bool block_comment(TSLexer *lexer) {
  unsigned depth = 1;
  while (depth > 0 && !lexer->eof(lexer)) {
    int32_t c = lexer->lookahead;
    lexer->advance(lexer, false);
    if (c == '|' && lexer->lookahead == '#') {
      lexer->advance(lexer, false);
      depth--;
    } else if (c == '#' && lexer->lookahead == '|') {
      lexer->advance(lexer, false);
      depth++;
    }
  }
  lexer->mark_end(lexer);
  lexer->result_symbol = BLOCK_COMMENT;
  return true;
}

static bool finish(TSLexer *lexer, Token *token, enum TokenType type, const bool *valid_symbols) {
  while (!delimiter(lexer)) take(lexer, token);
  lexer->mark_end(lexer);
  lexer->result_symbol = type;
  return valid_symbols[type];
}

// After `#`: a block comment, a character, `#;` and `#u8(`, which the
// grammar reads, or a token.
static bool after_hash(TSLexer *lexer, Token *token, const bool *valid_symbols) {
  if (lexer->lookahead == '|') {
    lexer->advance(lexer, false);
    return valid_symbols[BLOCK_COMMENT] && block_comment(lexer);
  }
  if (lexer->lookahead == ';') return false;
  if (lexer->lookahead == '\\') {
    take(lexer, token);
    if (!lexer->eof(lexer)) take(lexer, token);
    return finish(lexer, token, CHARACTER, valid_symbols);
  }
  if (lexer->lookahead == 'u') {
    take(lexer, token);
    if (lexer->lookahead == '8') {
      take(lexer, token);
      if (lexer->lookahead == '(') return false;
    }
  }
  while (!delimiter(lexer)) take(lexer, token);
  return finish(lexer, token, token_type(token), valid_symbols);
}

bool tree_sitter_snail_external_scanner_scan(void *payload, TSLexer *lexer,
                                             const bool *valid_symbols) {
  while (whitespace(lexer->lookahead)) lexer->advance(lexer, true);
  if (delimiter(lexer)) return false;
  Token token = {.length = 0, .long_token = false};
  token.text[0] = '\0';
  if (lexer->lookahead == '#') {
    take(lexer, &token);
    return after_hash(lexer, &token, valid_symbols);
  }
  while (!delimiter(lexer)) take(lexer, &token);
  return finish(lexer, &token, token_type(&token), valid_symbols);
}
