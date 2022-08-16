#include "ss-core/parser.hh"

#include <istream>
#include <fstream>
#include <algorithm>
#include <sstream>
#include <string>
#include <functional>
#include <optional>
#include <bitset>
#include <cassert>
#include <cstring>
#include <cctype>

#include "ss-core/gc.hh"
#include "ss-core/intern.hh"
#include "ss-core/common.hh"
#include "ss-core/feedback.hh"
#include "ss-core/printing.hh"
#include "ss-core/file-loc.hh"

namespace ss {

    //
    // Source Reader implementation:
    //

    class SourceReader {
    private:
        std::string m_input_desc;
        std::istream& m_input_stream;
        FLocPos m_cursor_pos;
        bool m_at_eof;

    public:
        SourceReader(std::string source_file_path, std::istream& file)
        :   m_input_desc(std::move(source_file_path)),
            m_input_stream(file),
            m_cursor_pos({0, 0}),
            m_at_eof(false)
        {}

    public:
        std::string const& file_path() const { return m_input_desc; }
        FLocPos const& cursor_pos() const { return m_cursor_pos; }

    public:
        bool eof() {
            return m_at_eof;
        }
        char peek() {
            if (!m_input_stream.eof()) {
                return m_input_stream.peek();
            } else {
                m_at_eof = true;
                return '\0';
            }
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
        if (m_input_stream.eof()) {
            m_at_eof = true;
        } else {
            char c = m_input_stream.get();
            
            bool c_is_new_line = false;
            if (c == '\r') {
                if (m_input_stream.peek() == '\n') {
                    // CRLF
                    m_input_stream.get();
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

    inline static bool is_first_identifier_or_number_char(char c) {
        return isalnum(c) || !!strchr("!$%&*+-./:<=>?@^_~", c);
    }
    inline static bool is_first_number_char(char c) {
        return isdigit(c) || !!strchr(".+-", c);
    }
    inline static bool is_number_char(char c) {
        return isdigit(c) || !!strchr(".", c);
    }
    inline static bool is_first_identifier_char(char c) {
        return isalpha(c) || !!strchr("!$%&*+-./:<=>?@^_~", c);
    }
    inline static bool is_identifier_char(char c) {
        return isalnum(c) || !!strchr("!$%&*+-./:<=>?@^_~", c);
    }

    enum class TokenKind {
        Eof = 0,
        LParen,
        RParen,
        Identifier,
        Boolean,
        Hashtag,
        Integer,
        Float,
        String,
        Quote,
        Backquote,
        Comma, 
        CommaAt,
        Backslash,
        Period
    };
    char const* tk_text(TokenKind tk) {
        switch (tk) {
            case TokenKind::Eof: return "<EOF>";
            case TokenKind::LParen: return "'('";
            case TokenKind::RParen: return "')'";
            case TokenKind::Identifier: return "<identifier>";
            case TokenKind::Boolean: return "<boolean>";
            case TokenKind::Hashtag: return "'#'";
            case TokenKind::Integer: return "<integer>";
            case TokenKind::Float: return "<floating-pt>";
            case TokenKind::String: return "<string>";
            case TokenKind::Quote: return "\"'\"";
            case TokenKind::Backquote: return "'`'";
            case TokenKind::Comma: return "','";
            case TokenKind::CommaAt: return "',@'";
            case TokenKind::Backslash: return "'\\'";
            case TokenKind::Period: return "'.'";
            default: {
                error("tk_text: Unknown token-kind");
                throw SsiError();
            }
        }
    }

    union KindDependentTokenInfo {
        IntStr identifier;
        bool boolean;
        my_ssize_t integer;
        my_float_t floating_pt;
        struct {
            size_t count;
            char* bytes;
        } string;
    };
    struct TokenInfo {
        FLocSpan span;
        KindDependentTokenInfo as;
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
        TokenKind help_scan_one_identifier_or_number_literal(TokenInfo* out_info_p, char opt_first_char);
        TokenKind help_scan_one_string_literal(TokenInfo* out_info_p, char quote_char);
        char help_scan_one_char_in_string_literal(char quote_char);

    public:
        void throw_expect_error(char const* expected) {
            std::stringstream expect_error_ss;
            TokenInfo la_ti;
            TokenKind la_tk = peek(&la_ti);
            expect_error_ss 
                << "Before " << tk_text(la_tk) << ", expected " << expected << std::endl
                << "see: " << la_ti.span.as_text();
            error(expect_error_ss.str());
            throw new SsiError();
        }

    public:
        void skip() {
            advance_cursor_by_one_token();
        }
        bool eof() const { 
            return m_peek_token_kind == TokenKind::Eof; 
        }
        TokenKind peek(TokenInfo* out_info = nullptr) const { 
            if (out_info) {
                *out_info = m_peek_token_info;
            }
            return m_peek_token_kind; 
        }
        bool match(TokenKind tk, TokenInfo* out_info = nullptr) {
            if (peek(out_info) == tk) {
                skip();
                return true;
            } else {
                return false;
            }
        }
        void expect(TokenKind tk, TokenInfo* out_info = nullptr) {
            if (!match(tk, out_info)) {
                throw_expect_error(tk_text(tk));
            }
        }
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
        auto start_pos = m_source_reader.cursor_pos();
        m_peek_token_kind = help_advance_cursor_by_one_token(&m_peek_token_info);
        auto end_pos = m_source_reader.cursor_pos();
        m_peek_token_info.span = {start_pos, end_pos};
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
                while (!f.eof() && nc != '\n' && nc != '\r') {
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
        
        // EOF:
        if (f.eof()) {
            return TokenKind::Eof;
        }

        // '#' codes: intercept certain codes, otherwise forward to parser
        if (f.peek() == '#') {
            f.get();

            if (f.match('t')) {
                out_info_p->as.boolean = true;
                return TokenKind::Boolean;
            }
            else if (f.match('f')) {
                out_info_p->as.boolean = false;
                return TokenKind::Boolean;
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


        // string literals:
        if (f.match('"')) {
            return help_scan_one_string_literal(out_info_p, '"');
        }
        if (f.match('\'')) {
            return help_scan_one_string_literal(out_info_p, '\'');
        }

        // identifiers & numbers:
        if (is_first_identifier_or_number_char(f.peek())) {
            return help_scan_one_identifier_or_number_literal(out_info_p, '\0');
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
    TokenKind Lexer::help_scan_one_identifier_or_number_literal(TokenInfo* out_info_p, char opt_first_char) {
        // scanning all relevant characters into `id_name_str`:
        std::string id_name_str;
        {
            auto& f = m_source_reader;
            std::stringstream id_name_ss;
            if (opt_first_char) {
                id_name_ss << opt_first_char;
            }
            while (!f.eof() && is_identifier_char(f.peek())) {
                id_name_ss << f.peek();
                f.get();
            }
            id_name_str = id_name_ss.str();
        }

        // checking if this ID is actually a number:
        if (!id_name_str.empty() && is_first_number_char(id_name_str[0])) {
            // need to deduce if this ID actually refers to a number.
            // this is true if it only contains digits, up to 1 '.' character, and up to 1 '+' or '-' initially.

            // if the first character is a digit, this is definitely a number.
            bool is_actually_number = isdigit(id_name_str[0]);

            // we track the '.' existence and position with `opt_dot_ix`
            //  - 'None' state when index == len(id_name_str)
            //  - 'Some i' state when 0 <= i < len(id_name_str)
            // thus, if first char is '.', initialize to 0, else to len(id_name_str)
            size_t opt_dot_ix = (id_name_str[0] == '.' ? 0 : id_name_str.size());

            // iterating through id_name_str[1:] to 
            for (size_t i = 1; i < id_name_str.size(); i++) {
                char ci = id_name_str[i];
                if (ci == '.') {
                    if (opt_dot_ix == id_name_str.size()) {
                        // first '.' in string-- is a floating point number.
                        opt_dot_ix = i;
                        is_actually_number = true;
                    } else {
                        // second '.' in string-- cannot be a number, is a general identifier.
                        is_actually_number = false;
                        break;
                    }
                } else if (isdigit(id_name_str[i])) {
                    is_actually_number = true;
                } else {
                    is_actually_number = false;
                    break;
                }
            }

            if (is_actually_number) {
                auto numeric_text = (
                    (isdigit(id_name_str[0])) ?
                    id_name_str :
                    id_name_str.substr(1)
                );
                if (opt_dot_ix == id_name_str.size()) {
                    // integer
                    out_info_p->as.integer = stoi(id_name_str);
                    return TokenKind::Integer;
                } else {
                    // floating point
                    out_info_p->as.floating_pt = stod(id_name_str);
                    return TokenKind::Float;
                }
            } else {
                // continue...
            }
        }

        // since this is a bonafide identifier (not a number literal), we can now intern it and return the 'ID' TokenKind.
        if (id_name_str == ".") {
            return TokenKind::Period;
        } else {
            out_info_p->as.identifier = intern(id_name_str);
            return TokenKind::Identifier;
        }
    }
    TokenKind Lexer::help_scan_one_string_literal(TokenInfo* out_info_p, char quote_char) {
        assert(quote_char == '"' || quote_char == '\'');
        auto& f = m_source_reader;

        std::vector<char> code_points;

        while (!f.eof()) {
            if (f.match(quote_char)) {
                break;
            }
            
            char sc = help_scan_one_char_in_string_literal(quote_char);
            code_points.push_back(sc);
        }

        size_t data_size = code_points.size() * sizeof(char);
        if (data_size > 0) {
            out_info_p->as.string.count = code_points.size();
            out_info_p->as.string.bytes = new char[code_points.size()];
            memcpy(out_info_p->as.string.bytes, code_points.data(), data_size); 
        } else {
            out_info_p->as.string.count = 0;
            out_info_p->as.string.bytes = nullptr;
        }
        return TokenKind::String;
    }
    char Lexer::help_scan_one_char_in_string_literal(char quote_char) {
        auto& f = m_source_reader;

        if (f.match('\\')) {
            if (f.match('n')) {
                return '\n';
            }
            if (f.match('r')) {
                return '\r';
            }
            if (f.match('t')) {
                return '\t';
            }
            if (f.match('\\')) {
                return '\\';
            }
            if (f.match(quote_char)) {
                return quote_char;
            }
            error("Invalid escape sequence: `\\" + std::string(1, f.peek()) + "'");
            throw SsiError();
        } else {
            char res_ch = f.peek();
            f.get();
            return res_ch;
        }
    }

    //
    // Parser Implementation:
    //

    class Parser {
    private:
        Lexer m_lexer;
        IntStr m_source;
        GcThreadFrontEnd* m_gc_tfe;
    public:
        explicit Parser(std::istream& istream, std::string file_path, GcThreadFrontEnd* gc_tfe);
    public:
        std::optional<OBJECT> parse_next_line();
        void run_lexer_test();
    private:
        OBJECT parse_top_level_line();
        OBJECT try_parse_constant();
        OBJECT parse_datum();
        
        template <bool contents_is_datum_not_exp>
        OBJECT parse_list();
        
        OBJECT parse_form();
    
    public:
        GcThreadFrontEnd* gc_tfe() const { return m_gc_tfe; }
    };

    Parser::Parser(std::istream& input_stream, std::string input_desc, GcThreadFrontEnd* gc_tfe) 
    :   m_lexer(input_stream, std::move(input_desc)),
        m_source(intern(input_desc)),
        m_gc_tfe(gc_tfe)
    {}

    std::optional<OBJECT> Parser::parse_next_line() {
        auto& ts = m_lexer;
        if (ts.eof()) {
            return {};
        } else {
            return {parse_top_level_line()};
        }
    }
    OBJECT Parser::parse_top_level_line() {
        return parse_form();
    }
    OBJECT Parser::try_parse_constant() {
        TokenInfo la_ti;
        TokenKind la_tk;

        Lexer& ts = m_lexer;

        la_tk = ts.peek(&la_ti);
        FLoc loc{m_source, la_ti.span};

        switch (la_tk) {
            case TokenKind::Identifier: {
                ts.skip();
                return OBJECT::make_ptr(
                    new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                    SyntaxObject{OBJECT::make_interned_symbol(la_ti.as.identifier), loc}
                );
            }
            case TokenKind::Boolean: {
                ts.skip();
                return OBJECT::make_ptr(
                    new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                    SyntaxObject{OBJECT::make_boolean(la_ti.as.boolean), loc}
                );
            }
            case TokenKind::Integer: {
                ts.skip();
                return OBJECT::make_ptr(
                    new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                    SyntaxObject{OBJECT::make_integer(la_ti.as.integer), loc}
                );
            }
            case TokenKind::Float: {
                ts.skip();
                return OBJECT::make_ptr(
                    new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                    SyntaxObject{OBJECT::make_float64(m_gc_tfe, la_ti.as.floating_pt), loc}
                );
            }
            case TokenKind::String: {
                ts.skip();
                return OBJECT::make_ptr(
                    new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                    SyntaxObject{OBJECT::make_string(m_gc_tfe, la_ti.as.string.count, la_ti.as.string.bytes, true), loc}
                );
            }
            default: {
                error("Expected constant, got unknown character.");
                throw SsiError();
            }
        }
    }
    OBJECT Parser::parse_datum() {
        TokenInfo la_ti;
        TokenKind la_tk;

        Lexer& ts = m_lexer;

        la_tk = ts.peek(&la_ti);
        
        switch (la_tk) {
            case TokenKind::Identifier:
            case TokenKind::Boolean:
            case TokenKind::Integer:
            case TokenKind::Float:
            case TokenKind::String: 
            {
                auto out = try_parse_constant();
                assert(out.is_syntax());
                return out;
            }
            case TokenKind::LParen: {
                auto out = parse_list<true>();
                assert(out.is_syntax());
                return out;
            }
            default: {
                error("Unexpected token in datum: " + std::string(tk_text(la_tk)));
                throw SsiError();
            }
        }
    }
    OBJECT Parser::parse_form() {
        TokenInfo la_ti;
        TokenKind la_tk;

        Lexer& ts = m_lexer;

        la_tk = ts.peek(&la_ti);
        
        switch (la_tk) {
            case TokenKind::Identifier:
            case TokenKind::Boolean:
            case TokenKind::Integer:
            case TokenKind::Float:
            case TokenKind::String: 
            {
                auto out = try_parse_constant();
                assert(out.is_syntax());
                return out;
            }
            case TokenKind::LParen: {
                return parse_list<false>();
            }
            case TokenKind::Quote: {
                ts.skip();
                OBJECT quoted = parse_datum();
                auto quoted_stx = static_cast<SyntaxObject*>(quoted.as_ptr());
                FLocSpan span{la_ti.span.first_pos, quoted_stx->loc().span.last_pos};
                
                FLoc loc{m_source, span};
                FLoc quote_loc{m_source, la_ti.span};

                return OBJECT::make_ptr(
                    new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                    SyntaxObject{
                        list(
                            m_gc_tfe,
                            OBJECT::make_ptr(
                                new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                                SyntaxObject{
                                    OBJECT::make_interned_symbol(intern("quote")),
                                    quote_loc
                                }
                            ),
                            quoted
                        ), 
                        loc
                    }
                );
            }
            default: {
                error("Unexpected token in primary expression: " + std::string(tk_text(la_tk)));
                throw SsiError();
            }
        }
    }

    template <bool contents_is_datum_not_exp>
    OBJECT Parser::parse_list() {
        Lexer& ts = m_lexer;

        TokenInfo lp_token_info;
        ts.expect(TokenKind::LParen, &lp_token_info);

        std::function<OBJECT()> parse_item;
        if (contents_is_datum_not_exp) {
            parse_item = [this] () -> OBJECT { return this->parse_datum(); };
        } else {
            parse_item = [this] () -> OBJECT { return this->parse_form(); };
        };

        // parsing each object in the list, pushing onto a stack:
        // NOTE: we match out the RParen in the loop
        // NOTE: we must handle improper/dotted lists: the '.' suffix builds a pair of this element.
        //  - a dotted pair is always the last element in this list
        //  - if the dotted pair is also the first element in the list, we return the dotted pair identically.
        std::vector<OBJECT> list_stack;
        TokenInfo rp_token_info;
        list_stack.reserve(8);
        bool ended_ok = false;
        bool parsed_improper_list = false;
        while (!ts.eof()) {
            if (ts.match(TokenKind::RParen, &rp_token_info)) {
                ended_ok = true;
                break;
            } else if (parsed_improper_list) {
                error("expected ')' after '.' in improper list");
                ended_ok = false;
                break;
            } else {
                OBJECT element_object = parse_item();
                if (ts.match(TokenKind::Period)) {
                    // dotted pair
                    OBJECT car = element_object;
                    OBJECT cdr = parse_item();
                    element_object = OBJECT::make_pair(m_gc_tfe, car, cdr);
                    parsed_improper_list = true;
                }
                assert(element_object.is_syntax() || element_object.is_pair() || element_object.is_vector());
                list_stack.push_back(element_object);
            }
        }
        if (!ended_ok) {
            TokenInfo ti;
            TokenKind tk = ts.peek(&ti);
            if (parsed_improper_list) {
                error("Before " + std::string(tk_text(tk)) + " and after dotted-pair, expected ')'");
                more("see: " + ti.span.as_text());
            } else {
                error("Before EOF, expected ')'");
            }
            throw SsiError();
        }

        // composing floc before return
        FLocSpan span;
        span.first_pos = lp_token_info.span.first_pos;
        span.last_pos = rp_token_info.span.last_pos;
        FLoc loc{m_source, span};
        
        // popping from the stack to build the pair-list, return:
        if (parsed_improper_list && list_stack.size() == 1) {
            // singleton pair
            return OBJECT::make_ptr(
                new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                SyntaxObject{list_stack[0], loc}
            );
        } else {
            // consing all but the last element to the last element recursively:
            // - iff improper list, then last item in the stack is post-dot.
            OBJECT pair_list = (parsed_improper_list) ? list_stack.back() : OBJECT::null;
            int start_index = (
                (parsed_improper_list) ?
                static_cast<int>(list_stack.size() - 2) :
                static_cast<int>(list_stack.size() - 1)
            );
            for (int i = start_index; i >= 0; i--) {
                pair_list = OBJECT::make_pair(m_gc_tfe, list_stack[i], pair_list);
                list_stack.pop_back();
            }
            return OBJECT::make_ptr(
                new(m_gc_tfe->allocate_size_class(SyntaxObject::sci))
                SyntaxObject{pair_list, loc}
            );
        }
    }
    void Parser::run_lexer_test() {
        std::cout << ">-- Lexer test: --<" << std::endl;
        while (!m_lexer.eof()) {
            // getting the peek token:
            TokenInfo ti;
            TokenKind tk = m_lexer.peek(&ti);

            // printing this token:
            std::cout 
                << "- " << tk_text(tk) << std::endl
                << "  " << "at " << ti.span.as_text()
                << std::endl;
            
            if (tk == TokenKind::Identifier) {
                std::cout
                    << "  content: `" << interned_string(ti.as.identifier) << "`"
                    << std::endl;
            }
            if (tk == TokenKind::Integer) {
                std::cout
                    << "  content: " << ti.as.integer
                    << std::endl;
            }
            if (tk == TokenKind::Float) {
                std::cout
                    << "  content: " << ti.as.floating_pt
                    << std::endl;
            }
            if (tk == TokenKind::String) {
                std::cout
                    << "  content: \"";
                for (size_t i = 0; i < ti.as.string.count; i++) {
                    char c = ti.as.string.bytes[i];
                    if (c == '\n') {
                        std::cout << "\n";
                    } else if (c == '\t') {
                        std::cout << "\t";
                    } else if (c == '\0') {
                        std::cout << "\0";
                    } else if (c == '"') {
                        std::cout << "\"";
                    } else {
                        std::cout << c;
                    }
                }
                std::cout 
                    << "\"" 
                    << std::endl;
            }

            // advancing for next iteration:
            m_lexer.skip();
        }
    }

    //
    // Interface:
    //

    Parser* create_parser(std::istream& input_stream, std::string input_desc, GcThreadFrontEnd* gc_tfe) {
        return new Parser(input_stream, std::move(input_desc), gc_tfe);
    }
    void dispose_parser(Parser* p) {
        delete p;
    }
    std::optional<OBJECT> parse_next_line_datum(Parser* p) {
        auto res = parse_next_line(p);
        if (res.has_value()) {
            return {
                static_cast<SyntaxObject*>(res.value().as_ptr())
                ->to_datum(p->gc_tfe())
            };
        } else {
            return {};
        }
    }
    std::vector<OBJECT> parse_all_subsequent_line_datums(Parser* p) {
        auto syntax_objs = parse_all_subsequent_lines(p);
        std::vector<OBJECT> objs;
        objs.reserve(syntax_objs.size());
        for (size_t i = 0; i < syntax_objs.size(); i++) {
            auto it = static_cast<SyntaxObject*>(syntax_objs[i].as_ptr())->to_datum(p->gc_tfe());
            objs.push_back(it);
        }
        return objs;
    }
    std::optional<OBJECT> parse_next_line(Parser* p) {
        return p->parse_next_line();
    }
    std::vector<OBJECT> parse_all_subsequent_lines(Parser* p) {
        std::vector<OBJECT> objects;
        objects.reserve(1024);
        for (;;) {
            std::optional<OBJECT> o = p->parse_next_line();
            if (o.has_value()) {
                // std::cerr << "LINE: " << o.value() << std::endl;
                objects.push_back(o.value());
            } else {
                break;
            }
        }
        return objects;
    }
    void run_lexer_test_and_dispose_parser(Parser* p) {
        p->run_lexer_test();
        dispose_parser(p);
    }

}   // namespace ss
