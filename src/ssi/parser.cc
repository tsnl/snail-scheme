#include "parser.hh"

#include <istream>
#include <fstream>
#include <cstring>
#include <cctype>
#include <sstream>

#include "intern.hh"
#include "core.hh"
#include "feedback.hh"

//
// Lexer Implementation:
//

inline static bool is_first_number_char(char c) {
    return isdigit(c) || !!strrchr(".+-", c);
}
inline static bool is_first_identifier_char(char c) {
    return isalnum(c) || !!strchr("!$%&*+-./:<=>?@^_~", c);
}

enum class TokenKind {
    Eof = 0,
    LParen,
    RParen,
    Identifier,
    Bool_True,
    Bool_False,
    Hashtag,
    Integer,
    Float,
    String,
    Quote,
    Backquote,
    Comma, CommaAt,
    Backslash,
    Period
};

union KindDependentTokenInfo {
    IntStr identifier;
    my_ssize_t integer;
    double float_;
    struct {
        size_t count;
        char* bytes;
    } string;
};

struct FLocPos {
    long line_index;
    long column_index;
};
struct FLocSpan {
    FLocPos first_pos;
    FLocPos last_pos;
};
struct TokenInfo {
    FLocSpan span;
    KindDependentTokenInfo kd_info;
};

class Lexer {
  private:
    std::istream& m_file;
    std::string const& m_file_path;
    FLocPos m_cursor_pos;
    TokenKind m_peek_token_kind;
    TokenInfo m_peek_token_info;

  public:
    explicit Lexer(std::istream& file, std::string const& file_path);

  private:
    void advance_cursor_by_one_token();
    TokenKind help_advance_cursor_by_one_token(TokenInfo* out_info_p);
    TokenKind help_scan_one_identifier(TokenInfo* out_info_p);

  public:
    TokenKind peek(TokenInfo* out_info) const;
    
    bool match(TokenKind tk, TokenInfo* out_info);
    void expect(TokenKind tk, TokenInfo* out_info);
};

Lexer::Lexer(std::istream& file, std::string const& file_path)
:   m_file(file),
    m_file_path(file_path),
    m_cursor_pos({0, 0}),
    m_peek_token_kind(),
    m_peek_token_info()
{
    // populating the initial 'peek' variables:
    advance_cursor_by_one_token();
}

void Lexer::advance_cursor_by_one_token() {
    m_peek_token_kind = help_advance_cursor_by_one_token(&m_peek_token_info);
}
TokenKind Lexer::help_advance_cursor_by_one_token(TokenInfo* out_info_p) {
    // scanning out all leading whitespace and comments:
    for (;;) {
        // culling whitespace:
        bool whitespace_culled = std::isspace(m_file.peek());
        if (whitespace_culled) {
            while (std::isspace(m_file.peek())) {
                m_file.get();
            }
        }

        // culling line-comments:
        bool line_comment_culled = (m_file.peek() == ';');
        if (line_comment_culled) {
            char nc = m_file.peek();
            while (nc != '\n' && nc != '\r') {
                m_file.get();
                nc = m_file.peek();
            }
            continue;
        }
        
        // terminating this loop if nothing culled this iteration:
        if (!whitespace_culled && !line_comment_culled) {
            break;
        }
    }

    auto& f = m_file;

    // '#' codes: intercept certain codes, otherwise forward to parser
    if (f.peek() == '#') {
        f.get();

        if (f.get() == 't') {
            return TokenKind::Bool_True;
        }
        else if (f.get() == 'f') {
            return TokenKind::Bool_False;
        }
        else {
            // return '#' and let the parser figure it out
            // NOTE: do not 'get' again here.
            return TokenKind::Hashtag;
        }
        
    }

    // punctuation marks:
    if (f.peek() == '\'') {
        f.get();
        return TokenKind::Quote;
    }
    if (f.peek() == '`') {
        f.get();
        return TokenKind::Backquote;
    }
    if (f.peek() == ',') {
        f.get();

        if (f.peek() == '@') {
            f.get();
            return TokenKind::CommaAt;
        } else {
            return TokenKind::Comma;
        }
    }
    if (f.peek() == '\\') {
        return TokenKind::Backslash;
    }

    // parens:
    if (f.peek() == '(') {
        f.get();
        return TokenKind::LParen;
    }
    if (f.peek() == ')') {
        f.get();
        return TokenKind::RParen;
    }


    // numbers:
    if (is_first_number_char(f.peek())) {
        bool is_neg = false;
        bool is_float_lt1 = false;
        if (f.peek() == '+') {
            f.get();
        }
        if (f.peek() == '-') {
            is_neg = true;
            f.get();
        }
        if (f.peek() == '.') {
            f.get();
            if (isspace(f.peek())) {
                // is actually a delimited period
                return TokenKind::Period;
            }
            else if (!isdigit(f.peek())) {
                // is actually an identifier
                f.unget();
                return help_scan_one_identifier(out_info_p);
            }
            else {
                // is actually a floating point number < 1; continue scanning...
                is_float_lt1 = true;
            }
        }
        // todo: finish scanning numbers
    }

    // string literals:
    // todo: actually scan string literals

    // identifiers:
    if (is_first_identifier_char(f.peek())) {
        return help_scan_one_identifier(out_info_p);
    }

    // EOF:
    if (f.eof()) {
        return TokenKind::Eof;
    }

    // error:
    {
        std::stringstream error_ss;
        char nc = f.peek();
        if (nc > 0) {
            error_ss 
                << "Parser error: "
                << "before '" << nc << "', expected a valid character." << std::endl
                << "see: " << m_file_path << ":" << 1+m_cursor_pos.line_index << ":" << 1+m_cursor_pos.column_index;
        } else {
            error_ss
                << "Parser error: "
                << "invalid character encountered; is this an ASCII file?";
        }
        error(error_ss.str());
        throw new SsiError();
    }
}
TokenKind Lexer::help_scan_one_identifier(TokenInfo* out_info_p) {
    // todo: implement me!
    //  - need interning first
    //  - beware of special case-- only '.': return `TokenKind::Period`
}

TokenKind Lexer::peek(TokenInfo* out_info) const {
    *out_info = m_peek_token_info;
    return m_peek_token_kind;
}


//
// Parser Implementation:
//

class Parser {
  private:  
    std::string m_file_path;    // important to init first; Lexer takes ptr to it.
    Lexer m_lexer;
  public:
    explicit Parser(std::istream& istream);
  public:
    Object* parse_next_line();
};

Parser::Parser(std::istream& istream, std::string file_path) 
:   m_file_path(file_path),
    m_lexer(istream, m_file_path)
{}

Object* Parser::parse_next_line() {
    
}

//
// Interface:
//

Parser* create_parser(std::string file_path) {
    std::ifstream f;
    f.open(file_path);
    if (!f.is_open()) {
        return nullptr;
    }
    return new Parser(f, std::move(file_path));
}
void dispose_parser(Parser* p) {
    delete p;
}
Object* parse_next_line(Parser* p) {
    return p->parse_next_line();
}
std::vector<Object*> parse_all_subsequent_lines(Parser* p) {
    std::vector<Object*> objects;
    objects.reserve(1024);
    for (;;) {
        Object* o = p->parse_next_line();
        objects.push_back(o);
    }
    return objects;
}