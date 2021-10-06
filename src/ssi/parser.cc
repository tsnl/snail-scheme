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
// Source Reader implementation:
//

struct FLocPos {
    long line_index;
    long column_index;
};
class SourceReader {
  private:
    std::string m_source_file_path;
    std::istream& m_file;
    FLocPos m_cursor_pos;
    bool m_at_eof;

  public:
    SourceReader(std::string source_file_path, std::istream& file)
    :   m_source_file_path(std::move(source_file_path)),
        m_file(file),
        m_cursor_pos({0, 0}),
        m_at_eof(true)
    {}

  public:
    std::string const& file_path() const { return m_source_file_path; }
    FLocPos const& cursor_pos() const { return m_cursor_pos; }

  public:
    bool eof() {
        return m_at_eof;
    }
    char peek() {
        return m_file.peek();
    }
    void get();
    bool match(char c) {
        if (peek() == c) {
            get();
            return true;
        } else {
            return false;
        }
    }
};

void SourceReader::get() {
    if (m_file.eof()) {
        m_at_eof = true;
    } else {
        char c = m_file.get();
        
        bool c_is_new_line = false;
        if (c == '\r') {
            if (m_file.peek() == '\n') {
                // CRLF
                m_file.get();
            }
            // CR
            c_is_new_line = true;
        } 
        else if (c == '\n') {
            // LF
            c_is_new_line = true;
        }

        if (c_is_new_line) {
            m_cursor_pos.line_index++;
            m_cursor_pos.column_index = 0;
        } else {
            m_cursor_pos.column_index++;
        }
    }
}

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
    SourceReader m_source_reader;
    TokenKind m_peek_token_kind;
    TokenInfo m_peek_token_info;

  public:
    explicit Lexer(std::istream& file, std::string file_path);

  public:
    SourceReader source() const { return m_source_reader; }

  private:
    void advance_cursor_by_one_token();
    TokenKind help_advance_cursor_by_one_token(TokenInfo* out_info_p);
    TokenKind help_scan_one_identifier(TokenInfo* out_info_p, char opt_first_char);

  public:
    bool eof() const { 
        return m_peek_token_kind == TokenKind::Eof; 
    }
    TokenKind peek(TokenInfo* out_info) const { 
        *out_info = m_peek_token_info;
        return m_peek_token_kind; 
    }
    
    bool match(TokenKind tk, TokenInfo* out_info);
    void expect(TokenKind tk, TokenInfo* out_info);
};

Lexer::Lexer(std::istream& file, std::string file_path)
:   m_source_reader(std::move(file_path), file),
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
    auto& f = m_source_reader;

    // scanning out all leading whitespace and comments:
    for (;;) {
        // culling whitespace:
        bool whitespace_culled = std::isspace(f.peek());
        if (whitespace_culled) {
            while (std::isspace(f.peek())) {
                f.get();
            }
        }

        // culling line-comments:
        bool line_comment_culled = (f.peek() == ';');
        if (line_comment_culled) {
            char nc = f.peek();
            while (nc != '\n' && nc != '\r') {
                f.get();
                nc = f.peek();
            }
            continue;
        }
        
        // terminating this loop if nothing culled this iteration:
        if (!whitespace_culled && !line_comment_culled) {
            break;
        }
    }

    // '#' codes: intercept certain codes, otherwise forward to parser
    if (f.peek() == '#') {
        f.get();

        if (f.match('t')) {
            return TokenKind::Bool_True;
        }
        else if (f.match('f')) {
            return TokenKind::Bool_False;
        }
        else {
            // return '#' and let the parser figure it out
            // NOTE: do not 'get' again here.
            return TokenKind::Hashtag;
        }
        
    }

    // punctuation marks:
    if (f.match('\'')) {
        return TokenKind::Quote;
    }
    if (f.match('`')) {
        return TokenKind::Backquote;
    }
    if (f.match(',')) {
        if (f.peek() == '@') {
            f.get();
            return TokenKind::CommaAt;
        } else {
            return TokenKind::Comma;
        }
    }
    if (f.match('\\')) {
        return TokenKind::Backslash;
    }

    // parens:
    if (f.match('(')) {
        return TokenKind::LParen;
    }
    if (f.match(')')) {
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
                return help_scan_one_identifier(out_info_p, '.');
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
        return help_scan_one_identifier(out_info_p, '\0');
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
                << "see: " 
                << source().file_path() << ":" 
                << 1+source().cursor_pos().line_index << ":" << 1+source().cursor_pos().column_index;
        } else {
            error_ss
                << "Parser error: "
                << "invalid character encountered; is this an ASCII file?";
        }
        error(error_ss.str());
        throw new SsiError();
    }
}
TokenKind Lexer::help_scan_one_identifier(TokenInfo* out_info_p, char opt_first_char) {
    // todo: implement me!
    //  - need interning first
    //  - beware of special case-- only '.': return `TokenKind::Period`
    //  - if opt_first_char is not `\0`, it must be processed first.
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
    explicit Parser(std::istream& istream, std::string file_path);
  public:
    Object* parse_next_line();
};

Parser::Parser(std::istream& istream, std::string file_path) 
:   m_file_path(file_path),
    m_lexer(istream, std::move(m_file_path))
{}

Object* Parser::parse_next_line() {
    if (m_lexer.eof()) {
        return nullptr;
    }
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