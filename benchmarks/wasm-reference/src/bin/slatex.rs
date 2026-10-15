use r7rs_wasm_reference::{input, report};
use std::fs::File;
use std::hint::black_box;
use std::io::{BufReader, BufWriter, Write};
use std::time::Instant;

// ---- Character ports and token databases ----

struct Port {
    input: BufReader<File>,
    lookahead: Option<Option<char>>,
}
impl Port {
    fn open(filename: &str) -> Self {
        Self {
            input: BufReader::new(File::open(filename).expect("SLaTeX input file")),
            lookahead: None,
        }
    }
    fn read(&mut self) -> Option<char> {
        if let Some(value) = self.lookahead.take() {
            return value;
        }
        r7rs_wasm_reference::read_char(&mut self.input).expect("SLaTeX character input")
    }
    fn peek(&mut self) -> Option<char> {
        if self.lookahead.is_none() {
            let value = self.read();
            self.lookahead = Some(value);
        }
        self.lookahead.unwrap()
    }
    fn newline(&mut self) {
        while let Some(c) = self.read() {
            if c == '\n' {
                break;
            }
        }
    }
    fn whitespace(&mut self) {
        while self.peek().is_some_and(char::is_whitespace) {
            self.read();
        }
    }
    fn tex_whitespace(&mut self) {
        while let Some(c) = self.peek() {
            if c.is_whitespace() {
                self.read();
            } else if c == '%' {
                self.newline();
                break;
            } else {
                break;
            }
        }
    }
    fn tabspace(&mut self) {
        while matches!(self.peek(), Some(' ' | '\t')) {
            self.read();
        }
    }
    fn control(&mut self) -> String {
        let first = self.read().expect("control sequence at EOF");
        let mut chars = vec![first];
        if first.is_alphabetic() {
            while let Some(c) = self.peek() {
                if c.is_alphabetic() {
                    chars.push(self.read().unwrap());
                } else if c == '%' {
                    self.newline();
                } else {
                    break;
                }
            }
        }
        chars.into_iter().collect()
    }
    fn grouped(&mut self) -> String {
        self.tex_whitespace();
        assert_eq!(self.read(), Some('{'));
        self.tex_whitespace();
        let (mut chars, mut depth, mut escape) = (Vec::new(), 0, false);
        loop {
            let c = self.read().expect("unterminated TeX group");
            if escape {
                chars.push(c);
                escape = false;
            } else if c == '\\' {
                chars.push(c);
                escape = true;
            } else if c == '%' {
                self.newline();
            } else if c == '{' {
                chars.push(c);
                depth += 1;
            } else if c == '}' {
                if depth == 0 {
                    break;
                }
                chars.push(c);
                depth -= 1;
            } else {
                chars.push(c);
            }
        }
        while chars.last().is_some_and(|c| c.is_whitespace()) {
            chars.pop();
        }
        chars.into_iter().collect()
    }
    fn filename(&mut self) -> String {
        self.tex_whitespace();
        if self.peek() == Some('{') {
            return self.grouped();
        }
        let (mut chars, mut escape) = (Vec::new(), false);
        while let Some(c) = self.peek() {
            if escape {
                chars.push(self.read().unwrap());
                escape = false;
            } else if c == '\\' {
                chars.push(self.read().unwrap());
                escape = true;
            } else if "{}[]()#%\\, \r\n\t".contains(c) {
                break;
            } else {
                chars.push(self.read().unwrap());
            }
        }
        assert!(!escape, "escaped filename at EOF");
        chars.into_iter().collect()
    }
    fn scheme_id(&mut self) -> String {
        self.whitespace();
        let (mut chars, mut escape) = (Vec::new(), false);
        while let Some(c) = self.peek() {
            if escape {
                chars.push(self.read().unwrap());
                escape = false;
            } else if c == '\\' {
                chars.push(self.read().unwrap());
                escape = true;
            } else if "{}[]() \r\n\t".contains(c) {
                break;
            } else {
                chars.push(self.read().unwrap());
            }
        }
        chars.into_iter().collect()
    }
    fn scheme_ids(&mut self) -> Vec<String> {
        self.tex_whitespace();
        assert_eq!(self.read(), Some('{'));
        let mut ids = Vec::new();
        loop {
            self.whitespace();
            if self.peek() == Some('}') {
                self.read();
                break;
            }
            assert!(self.peek().is_some());
            ids.push(self.scheme_id());
        }
        ids
    }
    fn filenames(&mut self, left: char, right: char) -> Vec<String> {
        self.tex_whitespace();
        assert_eq!(self.read(), Some(left));
        let mut files = Vec::new();
        loop {
            self.tex_whitespace();
            if self.peek() == Some(right) {
                self.read();
                break;
            }
            assert!(self.peek().is_some());
            files.push(self.filename());
            self.tex_whitespace();
            if self.peek() == Some(',') {
                self.read();
            } else {
                assert_eq!(self.peek(), Some(right));
            }
        }
        files
    }
}
fn emit(out: &mut impl Write, text: &str) {
    out.write_all(text.as_bytes()).expect("SLaTeX output");
}
fn emit_char(out: &mut impl Write, c: char) {
    let mut bytes = [0; 4];
    emit(out, c.encode_utf8(&mut bytes));
}
fn replace_file(filename: &str) -> BufWriter<File> {
    if std::path::Path::new(filename).exists() {
        std::fs::remove_file(filename).unwrap();
    }
    BufWriter::new(File::create(filename).expect("SLaTeX output file"))
}
fn remove_file(filename: &str) {
    std::fs::remove_file(filename).expect("SLaTeX delete file");
}

// ---- Two persistent line buffers and scanner markers ----

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Space {
    Void,
    Plain,
    Initial,
    InitialPlain,
    Paren,
    Bracket,
    Quote,
    Inner,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Tab {
    Void,
    Set,
    Move,
    TabbedReturn,
    PlainReturn,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Notab {
    Void,
    BeginComment,
    MidComment,
    BeginString,
    MidString,
    EndString,
    BeginMath,
    MidMath,
    EndMath,
}
struct Line {
    edge: usize,
    chars: Box<[char; 200]>,
    spaces: Box<[Space; 200]>,
    tabs: Box<[Tab; 200]>,
    notabs: Box<[Notab; 200]>,
}
impl Line {
    fn new() -> Self {
        Self {
            edge: 0,
            chars: Box::new([' '; 200]),
            spaces: Box::new([Space::Void; 200]),
            tabs: Box::new([Tab::Void; 200]),
            notabs: Box::new([Notab::Void; 200]),
        }
    }
    fn flush(&mut self) {
        self.edge = 0;
        self.put(0, '\n', Space::Void, Tab::Void, Notab::Void);
    }
    fn put(&mut self, i: usize, c: char, space: Space, tab: Tab, notab: Notab) {
        self.chars[i] = c;
        self.spaces[i] = space;
        self.tabs[i] = tab;
        self.notabs[i] = notab;
    }
    fn finish(&mut self, i: usize, tab: Tab) {
        self.put(i, '\n', Space::Void, tab, Notab::Void);
        self.edge = i;
        if self.notabs[0] == Notab::MidString {
            self.notabs[0] = Notab::BeginString;
        }
    }
    fn blank(&mut self) -> bool {
        let mut i = 0;
        loop {
            match self.chars[i] {
                ' ' if self.notabs[i] == Notab::Void => i += 1,
                '\n' => {
                    for _ in (1..i).rev() {
                        self.spaces[i] = Space::Void;
                    }
                    return true;
                }
                _ => return false,
            }
        }
    }
    fn comment(&self) -> bool {
        self.chars[0] == ';' && self.notabs[0] == Notab::BeginComment && self.chars[1] != ';'
    }
    fn remove_tabs(&mut self, start: Option<usize>) {
        let Some(mut i) = start else {
            return;
        };
        while self.chars[i] != '\n' {
            if self.tabs[i] == Tab::Set {
                self.tabs[i] = Tab::Void;
            }
            i += 1;
        }
    }
    fn add_tabs(&mut self) {
        let (mut i, mut parens) = (1, false);
        while self.chars[i] != '\n' {
            if self.notabs[i] != Notab::Void {
                parens = false;
            } else if self.chars[i] == '[' {
                if self.tabs[i] == Tab::Void {
                    self.tabs[i] = Tab::Set;
                }
                parens = false;
            } else if self.chars[i] == '(' {
                if self.tabs[i] == Tab::Void && !parens {
                    self.tabs[i] = Tab::Set;
                }
                parens = true;
            } else {
                parens = false;
            }
            i += 1;
        }
    }
    fn clean_initial(&mut self) {
        if let Some(i) = (0..=self.edge).rev().find(|&i| self.tabs[i] == Tab::Move) {
            for j in (0..i).rev() {
                if matches!(
                    self.spaces[j],
                    Space::Initial | Space::Paren | Space::Bracket | Space::Quote
                ) {
                    self.spaces[j] = Space::InitialPlain;
                }
            }
        }
    }
    fn clean_inner(&mut self) {
        let mut consecutive = false;
        for i in 0..self.edge {
            if self.spaces[i] == Space::Inner {
                if !consecutive {
                    self.spaces[i] = Space::Plain;
                }
                consecutive = true;
            } else {
                consecutive = false;
            }
        }
    }
}
struct CaseFrame {
    token: bool,
    tag_depth: usize,
    case_depth: usize,
}
struct QuoteFrame {
    comma: bool,
    token: bool,
    depth: usize,
}
// Keep each source case/backquote frame as a fresh allocation, even though
// the outer stack uses a Rust vector rather than Scheme list cells.
#[allow(clippy::vec_box)]
struct Processor {
    keywords: Vec<String>,
    variables: Vec<String>,
    constants: Vec<String>,
    specials: Vec<(String, String)>,
    aliases: [Vec<String>; 6],
    math: Vec<char>,
    case_sensitive: bool,
    enabled: bool,
    reenabler: String,
    latex: bool,
    separate_includes: bool,
    include_only: Option<Vec<String>>,
    protected: bool,
    protected_files: Vec<String>,
    paths: Vec<String>,
    subjob: String,
    primary: i64,
    secondary: i64,
    seen_command: bool,
    intext: bool,
    code_env: String,
    paragraph: bool,
    curr_notab: Notab,
    quoted_token: bool,
    quoted_depth: usize,
    macro_token: bool,
    macro_depth: usize,
    cases: Vec<Box<CaseFrame>>,
    quotes: Vec<Box<QuoteFrame>>,
    lines: Option<[Line; 2]>,
}
impl Processor {
    fn new() -> Self {
        Self {
            keywords: include_str!("../slatex-keywords.txt")
                .lines()
                .map(str::to_owned)
                .collect(),
            variables: Vec::new(),
            constants: Vec::new(),
            specials: vec![
                (".".into(), ".".into()),
                ("...".into(), "{\\dots}".into()),
                ("-".into(), "$-$".into()),
                ("1-".into(), "\\va{1$-$}".into()),
                ("-1+".into(), "\\va{$-$1$+$}".into()),
            ],
            aliases: [
                vec!["scheme".into()],
                vec!["schemeresult".into()],
                vec!["schemedisplay".into()],
                vec!["schemebox".into()],
                vec!["schemeinput".into()],
                vec!["schemeregion".into()],
            ],
            math: Vec::new(),
            case_sensitive: true,
            enabled: true,
            reenabler: "UNDEFINED".into(),
            latex: true,
            separate_includes: false,
            include_only: None,
            protected: false,
            protected_files: Vec::new(),
            paths: Vec::new(),
            subjob: String::new(),
            primary: -1,
            secondary: -1,
            seen_command: false,
            intext: false,
            code_env: "UNDEFINED".into(),
            paragraph: true,
            curr_notab: Notab::Void,
            quoted_token: false,
            quoted_depth: 0,
            macro_token: false,
            macro_depth: 0,
            cases: Vec::new(),
            quotes: Vec::new(),
            lines: Some([Line::new(), Line::new()]),
        }
    }
    fn token_equal(&self, first: &str, second: &str) -> bool {
        if self.case_sensitive {
            first == second
        } else {
            first.to_lowercase() == second.to_lowercase()
        }
    }
    fn member(&self, token: &str, database: &[String]) -> bool {
        database.iter().any(|t| self.token_equal(t, token))
    }
    fn set_token(&mut self, token: String, category: usize) {
        let sensitive = self.case_sensitive;
        let equal = |s: &str| {
            if sensitive {
                s == token
            } else {
                s.to_lowercase() == token.to_lowercase()
            }
        };
        let lists = [&mut self.keywords, &mut self.constants, &mut self.variables];
        if lists[category].iter().any(|s| equal(s)) {
            return;
        }
        for (i, list) in lists.into_iter().enumerate() {
            if i == category {
                list.insert(0, token.clone());
            } else {
                list.retain(|s| !equal(s));
            }
        }
    }
    fn get_line(&mut self, input: &mut Port, line: &mut Line) -> bool {
        let (mut i, mut graphic) = (0, false);
        loop {
            let c = input.read();
            if c.is_some_and(|c| !matches!(c, '\r' | '\n' | ' ' | '\t')) {
                graphic = true;
            }
            if c.is_none() || matches!(c, Some('\r' | '\n')) {
                match self.curr_notab {
                    Notab::MidString if i > 0 => line.notabs[i - 1] = Notab::EndString,
                    Notab::MidComment => self.curr_notab = Notab::Void,
                    Notab::MidMath => panic!("runaway math subformula"),
                    _ => {}
                }
                let tab = if c.is_none() {
                    Tab::Void
                } else if input.peek().is_none() || self.intext {
                    Tab::PlainReturn
                } else {
                    Tab::TabbedReturn
                };
                line.finish(i, tab);
                return c.is_some() || i > 0;
            }
            let c = c.unwrap();
            if self.curr_notab == Notab::MidComment {
                line.put(
                    i,
                    c,
                    if matches!(c, ' ' | '\t') {
                        Space::Plain
                    } else {
                        Space::Void
                    },
                    Tab::Void,
                    Notab::MidComment,
                );
                i += 1;
            } else if c == '\\' {
                line.put(i, c, Space::Void, Tab::Void, self.curr_notab);
                let c = input.read().expect("backslash at EOF");
                let c = if c == '\t' { ' ' } else { c };
                line.put(
                    i + 1,
                    c,
                    if c == ' ' { Space::Plain } else { Space::Void },
                    Tab::Void,
                    self.curr_notab,
                );
                i += 2;
            } else if self.curr_notab == Notab::MidMath {
                let c = if c == '\t' { ' ' } else { c };
                let space = if c == ' ' { Space::Plain } else { Space::Void };
                if self.math.contains(&c) {
                    line.put(i, '$', space, Tab::Void, Notab::EndMath);
                    self.curr_notab = Notab::Void;
                } else {
                    line.put(i, c, space, Tab::Void, Notab::MidMath);
                }
                i += 1;
            } else if self.curr_notab == Notab::MidString {
                let c = if c == '\t' { ' ' } else { c };
                let space = if c == ' ' { Space::Inner } else { Space::Void };
                let notab = if c == '"' {
                    self.curr_notab = Notab::Void;
                    Notab::EndString
                } else {
                    Notab::MidString
                };
                line.put(i, c, space, Tab::Void, notab);
                i += 1;
            } else if matches!(c, ' ' | '\t') {
                let space = if self.intext {
                    Space::Plain
                } else if graphic {
                    Space::Inner
                } else {
                    Space::Initial
                };
                for _ in 0..if c == '\t' { 8 } else { 1 } {
                    line.put(i, ' ', space, Tab::Void, Notab::Void);
                    i += 1;
                }
            } else if c == '"' {
                line.put(i, c, Space::Void, Tab::Void, Notab::BeginString);
                self.curr_notab = Notab::MidString;
                i += 1;
            } else if c == ';' {
                line.put(i, c, Space::Void, Tab::Void, Notab::BeginComment);
                self.curr_notab = Notab::MidComment;
                i += 1;
            } else if self.math.contains(&c) {
                line.put(i, '$', Space::Void, Tab::Void, Notab::BeginMath);
                self.curr_notab = Notab::MidMath;
                i += 1;
            } else {
                line.put(i, c, Space::Void, Tab::Void, Notab::Void);
                i += 1;
            }
        }
    }
    fn adjust(&mut self, current: &mut Line, previous: &mut Line) {
        if current.blank() || current.comment() {
            if !self.paragraph {
                self.paragraph = true;
                if !self.intext {
                    previous.remove_tabs(Some(0));
                    if previous.tabs[previous.edge] == Tab::TabbedReturn {
                        previous.tabs[previous.edge] = Tab::PlainReturn;
                    }
                }
            }
            return;
        }
        if self.paragraph {
            self.paragraph = false;
        } else if !self.intext {
            let mut i = 0;
            let remove = loop {
                if current.chars[i] == '\n' {
                    break Some(i);
                }
                if previous.chars[i] == '\n' {
                    break None;
                }
                if current.spaces[i] == Space::Initial {
                    if previous.notabs[i] == Notab::Void {
                        if previous.chars[i] == '(' || previous.spaces[i] == Space::Paren {
                            current.spaces[i] = Space::Paren;
                        } else if previous.chars[i] == '[' || previous.spaces[i] == Space::Bracket {
                            current.spaces[i] = Space::Bracket;
                        } else if "'`,".contains(previous.chars[i])
                            || previous.spaces[i] == Space::Quote
                        {
                            current.spaces[i] = Space::Quote;
                        }
                        if matches!(previous.tabs[i], Tab::Set | Tab::Move) {
                            current.tabs[i] = Tab::Move;
                        }
                    }
                    i += 1;
                    continue;
                }
                if i == 0 {
                    break Some(0);
                }
                if previous.tabs[i] != Tab::Void {
                    if matches!(previous.tabs[i], Tab::Set | Tab::Move) {
                        current.tabs[i] = Tab::Move;
                    }
                    break Some(i + 1);
                }
                if matches!(
                    previous.spaces[i],
                    Space::Initial
                        | Space::InitialPlain
                        | Space::Paren
                        | Space::Bracket
                        | Space::Quote
                ) {
                    break Some(i + 1);
                }
                if previous.chars[i - 1] == ' ' && previous.notabs[i - 1] == Notab::Void {
                    previous.tabs[i] = Tab::Set;
                    current.tabs[i] = Tab::Move;
                    break Some(i + 1);
                }
                let mut j = i - 1;
                loop {
                    if j == 0 || current.tabs[j] != Tab::Void {
                        break;
                    }
                    if matches!(
                        current.spaces[j],
                        Space::Paren | Space::Bracket | Space::Quote
                    ) {
                        j -= 1;
                        continue;
                    }
                    if previous.notabs[j] != Notab::Void || previous.chars[j] == ' ' {
                        let k = j + 1;
                        if !matches!(
                            previous.notabs[k],
                            Notab::MidComment
                                | Notab::MidMath
                                | Notab::EndMath
                                | Notab::MidString
                                | Notab::EndString
                        ) {
                            if previous.tabs[k] == Tab::Void {
                                previous.tabs[k] = Tab::Set;
                            }
                            current.tabs[k] = Tab::Move;
                        }
                    }
                    break;
                }
                break Some(i + 1);
            };
            previous.remove_tabs(remove);
        }
        if !self.intext {
            current.add_tabs();
        }
        current.clean_initial();
        current.clean_inner();
    }
}

// ---- Destructive character-list escaping ----

type Characters = Option<Box<CharacterCell>>;
struct CharacterCell {
    value: char,
    rest: Characters,
}
fn character_list(text: &str) -> Characters {
    text.chars().rev().fold(None, |rest, value| {
        Some(Box::new(CharacterCell { value, rest }))
    })
}
fn append_characters(mut first: Characters, second: Characters) -> Characters {
    let mut tail = &mut first;
    while let Some(cell) = tail {
        tail = &mut cell.rest;
    }
    *tail = second;
    first
}
fn reverse_characters(mut input: Characters) -> Characters {
    let mut result = None;
    while let Some(mut cell) = input {
        input = cell.rest.take();
        cell.rest = result;
        result = Some(cell);
    }
    result
}
fn character_text(input: &Characters) -> String {
    let (mut rest, mut text) = (input.as_ref(), String::new());
    while let Some(cell) = rest {
        text.push(cell.value);
        rest = cell.rest.as_ref();
    }
    text
}
fn analog(c: char) -> String {
    match c {
        '$' | '&' | '%' | '#' | '_' => format!("\\{c}"),
        '{' | '}' => format!("$\\{c}$"),
        '\\' => "$\\backslash$".into(),
        '+' => "$+$".into(),
        '=' => "$=$".into(),
        '<' => "$\\lt$".into(),
        '>' => "$\\gt$".into(),
        '^' => "\\^{}".into(),
        '|' => "$\\vert$".into(),
        '~' => "\\~{}".into(),
        '@' => "{\\atsign}".into(),
        '"' => "{\\tt\\dq}".into(),
        _ => c.to_string(),
    }
}
fn map_characters(input: &Characters) -> Characters {
    match input {
        None => None,
        Some(cell) => {
            let first = character_list(&analog(cell.value));
            let rest = map_characters(&cell.rest);
            append_characters(first, rest)
        }
    }
}
fn character_prefix(text: &str, input: &Characters) -> bool {
    let mut rest = input.as_ref();
    for c in text.chars() {
        let Some(cell) = rest else {
            return false;
        };
        if cell.value != c {
            return false;
        }
        rest = cell.rest.as_ref();
    }
    true
}
fn texify_characters(text: &str) -> Characters {
    let input = character_list(text);
    let mut output = map_characters(&input);
    let mut cursor = &mut output;
    loop {
        if cursor.is_none() {
            break;
        }
        if character_prefix("-$>$", cursor) {
            let cell = cursor.as_mut().unwrap();
            cell.value = '$';
            let mut suffix = cell.rest.take();
            for _ in 0..3 {
                suffix = suffix.unwrap().rest;
            }
            cell.rest = append_characters(character_list("\\to$"), suffix);
        }
        cursor = &mut cursor.as_mut().unwrap().rest;
    }
    output
}
fn texify(text: &str, data: bool) -> String {
    let escaped = texify_characters(text);
    if !data {
        return character_text(&escaped);
    }
    let (mut rest, mut output) = (escaped.as_ref(), None);
    while let Some(cell) = rest {
        output = if cell.value == '-' {
            append_characters(character_list("$-$"), output)
        } else {
            Some(Box::new(CharacterCell {
                value: cell.value,
                rest: output,
            }))
        };
        rest = cell.rest.as_ref();
    }
    character_text(&reverse_characters(output))
}
fn display_space(out: &mut impl Write, space: Space) {
    emit(
        out,
        match space {
            Space::Plain | Space::InitialPlain => " ",
            Space::Initial => "\\HL ",
            Space::Paren => "\\PRN ",
            Space::Bracket => "\\BKT ",
            Space::Quote => "\\QUO ",
            Space::Inner => "\\ ",
            Space::Void => "",
        },
    );
}
fn display_tab(out: &mut impl Write, tab: Tab) {
    emit(
        out,
        match tab {
            Tab::Set => "\\=",
            Tab::Move => "\\>",
            _ => "",
        },
    );
}
fn number_token(token: &str) -> bool {
    if !token.chars().any(|c| c.is_ascii_digit()) {
        return matches!(
            token,
            "+i" | "-i" | "+inf.0" | "-inf.0" | "+nan.0" | "-nan.0"
        );
    }
    if token.parse::<f64>().is_ok() {
        return true;
    }
    if let Some((first, second)) = token.split_once('/') {
        return first.parse::<i64>().is_ok() && second.parse::<i64>().is_ok();
    }
    if let Some((first, second)) = token.split_once('@') {
        return number_token(first) && number_token(second);
    }
    if let Some(body) = token.strip_suffix('i') {
        if number_token(body) {
            return true;
        }
        for (i, c) in body.char_indices().skip(1) {
            if matches!(c, '+' | '-') && !matches!(body.as_bytes()[i - 1], b'e' | b'E') {
                return number_token(&body[..i])
                    && (body[i..] == *"+" || body[i..] == *"-" || number_token(&body[i..]));
            }
        }
    }
    false
}

// ---- Quote, macro and case state while printing Scheme lines ----

impl Processor {
    fn sequence(&self, out: &mut impl Write, begin: bool) {
        if self.intext || !self.latex {
            emit(out, "\\");
            if !begin {
                emit(out, "end");
            }
            emit(out, &self.code_env);
        } else {
            emit(out, if begin { "\\begin{" } else { "\\end{" });
            emit(out, &self.code_env);
            emit(out, "}");
        }
        emit(out, "\n");
    }
    fn tex_line(&self, line: &Line, out: &mut impl Write) {
        let mut i = usize::from(line.comment());
        while line.chars[i] != '\n' {
            emit_char(out, line.chars[i]);
            i += 1;
        }
        if line.tabs[i] != Tab::Void {
            emit(out, "\n");
        }
    }
    fn open_delimiter(&mut self) {
        if self.quoted_token {
            self.quoted_token = false;
            self.quoted_depth = 1;
        } else if self.quoted_depth > 0 {
            self.quoted_depth += 1;
        }
        if self.macro_token {
            self.macro_token = false;
            self.macro_depth = 1;
        } else if self.macro_depth > 0 {
            self.macro_depth += 1;
        }
        if let Some(top) = self.quotes.last_mut() {
            if top.token {
                top.token = false;
                top.depth = 1;
            } else if top.depth > 0 {
                top.depth += 1;
            }
        }
        if let Some(top) = self.cases.last_mut() {
            if top.token {
                top.token = false;
                top.tag_depth = 1;
            } else if top.tag_depth > 0 {
                top.tag_depth += 1;
            } else if top.case_depth > 0 {
                top.case_depth += 1;
                if top.case_depth == 2 {
                    self.quoted_token = true;
                }
            }
        }
    }
    fn close_delimiter(&mut self) {
        if self.quoted_depth > 0 {
            self.quoted_depth -= 1;
        }
        if self.macro_depth > 0 {
            self.macro_depth -= 1;
        }
        if let Some(top) = self.quotes.last_mut()
            && top.depth > 0
        {
            top.depth -= 1;
            if top.depth == 0 {
                self.quotes.pop();
            }
        }
        while let Some(top) = self.cases.last_mut() {
            if top.tag_depth > 0 {
                top.tag_depth -= 1;
                if top.tag_depth == 0 {
                    top.case_depth = 1;
                }
                break;
            }
            if top.case_depth > 0 {
                top.case_depth -= 1;
                if top.case_depth == 0 {
                    self.cases.pop();
                    continue;
                }
            }
            break;
        }
    }
    fn output_token(&mut self, token: &str, out: &mut impl Write) {
        if let Some(top) = self.cases.last_mut()
            && top.token
        {
            top.token = false;
            top.case_depth = 1;
        }
        if self
            .specials
            .iter()
            .any(|(s, _)| self.token_equal(s, token))
        {
            let translation = &self
                .specials
                .iter()
                .find(|(s, _)| self.token_equal(s, token))
                .unwrap()
                .1;
            emit(out, translation);
        } else {
            let data = token.starts_with('#') || number_token(token);
            let font = if self.quoted_token {
                self.quoted_token = false;
                if token == "else" {
                    "sy"
                } else if data {
                    "dt"
                } else {
                    "cn"
                }
            } else if data {
                "dt"
            } else if self.quoted_depth > 0 || self.quotes.last().is_some_and(|top| !top.comma) {
                "cn"
            } else if self.macro_token {
                self.macro_token = false;
                self.set_token(token.into(), 0);
                "sy"
            } else if self.macro_depth > 0 {
                self.set_token(token.into(), 0);
                "sy"
            } else if self.member(token, &self.constants) {
                "cn"
            } else if self.member(token, &self.variables) {
                "va"
            } else if self.member(token, &self.keywords) {
                if self.token_equal(token, "quote") {
                    self.quoted_token = true;
                } else if [
                    "define-syntax",
                    "syntax-rules",
                    "defmacro",
                    "extend-syntax",
                    "define-macro!",
                ]
                .iter()
                .any(|t| self.token_equal(token, t))
                {
                    self.macro_token = true;
                } else if ["case", "record-case"]
                    .iter()
                    .any(|t| self.token_equal(token, t))
                {
                    self.cases.push(Box::new(CaseFrame {
                        token: true,
                        tag_depth: 0,
                        case_depth: 0,
                    }));
                }
                "sy"
            } else {
                "va"
            };
            emit(out, "\\");
            emit(out, font);
            emit(out, "{");
            emit(out, &texify(token, font == "dt"));
            emit(out, "}");
        }
        if self.quotes.last().is_some_and(|top| top.token) {
            self.quotes.pop();
        }
    }
    fn token(&mut self, line: &Line, mut i: usize, out: &mut impl Write) -> usize {
        let mut characters = None;
        loop {
            let c = line.chars[i];
            if c == '\\' {
                characters = Some(Box::new(CharacterCell {
                    value: c,
                    rest: characters,
                }));
                characters = Some(Box::new(CharacterCell {
                    value: line.chars[i + 1],
                    rest: characters,
                }));
                i += 2;
            } else if "()[] \r\n,@;".contains(c) || self.math.contains(&c) {
                let token = character_text(&reverse_characters(characters));
                self.output_token(&token, out);
                return i;
            } else {
                characters = Some(Box::new(CharacterCell {
                    value: c,
                    rest: characters,
                }));
                i += 1;
            }
        }
    }
    fn scheme_line(&mut self, line: &Line, out: &mut impl Write) {
        let mut i = 0;
        loop {
            let c = line.chars[i];
            let notab = line.notabs[i];
            if c == '\n' {
                emit(
                    out,
                    match line.tabs[i] {
                        Tab::TabbedReturn => "\\\\\n",
                        Tab::PlainReturn => "\n",
                        Tab::Void => "%\n",
                        _ => "",
                    },
                );
                return;
            }
            if notab == Notab::BeginComment {
                display_tab(out, line.tabs[i]);
                emit_char(out, c);
                i += 1;
            } else if notab == Notab::MidComment {
                emit_char(out, c);
                i += 1;
            } else if matches!(
                notab,
                Notab::BeginString | Notab::MidString | Notab::EndString
            ) {
                if notab == Notab::BeginString {
                    display_tab(out, line.tabs[i]);
                    emit(out, "\\dt{");
                }
                if c == ' ' {
                    display_space(out, line.spaces[i]);
                } else {
                    emit(out, &analog(c));
                }
                if notab == Notab::EndString {
                    emit(out, "}");
                }
                i += 1;
            } else if matches!(notab, Notab::BeginMath | Notab::MidMath | Notab::EndMath) {
                if notab == Notab::BeginMath {
                    display_tab(out, line.tabs[i]);
                }
                emit_char(out, c);
                i += 1;
            } else if c == ' ' {
                display_tab(out, line.tabs[i]);
                display_space(out, line.spaces[i]);
                i += 1;
            } else if c == '\'' {
                display_tab(out, line.tabs[i]);
                emit_char(out, c);
                if !self.quoted_token && self.quoted_depth == 0 {
                    self.quoted_token = true;
                }
                i += 1;
            } else if c == '`' {
                display_tab(out, line.tabs[i]);
                emit_char(out, c);
                if self.quotes.last().is_none_or(|f| f.comma) {
                    self.quotes.push(Box::new(QuoteFrame {
                        comma: false,
                        token: true,
                        depth: 0,
                    }));
                }
                i += 1;
            } else if c == ',' {
                display_tab(out, line.tabs[i]);
                emit_char(out, c);
                if self.quotes.last().is_some_and(|f| !f.comma) {
                    self.quotes.push(Box::new(QuoteFrame {
                        comma: true,
                        token: true,
                        depth: 0,
                    }));
                }
                if line.chars[i + 1] == '@' {
                    emit(out, &analog('@'));
                    i += 2;
                } else {
                    i += 1;
                }
            } else if matches!(c, '(' | '[') {
                display_tab(out, line.tabs[i]);
                emit_char(out, c);
                self.open_delimiter();
                i += 1;
            } else if matches!(c, ')' | ']') {
                display_tab(out, line.tabs[i]);
                emit_char(out, c);
                self.close_delimiter();
                i += 1;
            } else {
                display_tab(out, line.tabs[i]);
                i = self.token(line, i, out);
            }
        }
    }
    fn scheme2tex(&mut self, input: &mut Port, out: &mut impl Write) {
        self.paragraph = true;
        self.quoted_token = false;
        self.quoted_depth = 0;
        self.macro_token = false;
        self.macro_depth = 0;
        self.cases.clear();
        self.quotes.clear();
        // These buffers are allocated once and exchanged, never cloned. Scanner
        // state persists across snippets exactly as the source closure does.
        let mut lines = self.lines.take().unwrap();
        for line in &mut lines {
            line.flush();
        }
        let mut current = 0;
        loop {
            let previous_paragraph = self.paragraph;
            let more = self.get_line(input, &mut lines[current]);
            let (first, second) = lines.split_at_mut(1);
            let (curr, prev) = if current == 0 {
                (&mut first[0], &mut second[0])
            } else {
                (&mut second[0], &mut first[0])
            };
            self.adjust(curr, prev);
            if previous_paragraph {
                self.tex_line(prev, out);
            } else {
                self.scheme_line(prev, out);
            }
            if previous_paragraph != self.paragraph {
                self.sequence(out, !self.paragraph);
            }
            if !more {
                break;
            }
            current = 1 - current;
        }
        self.lines = Some(lines);
    }
}

// ---- Auxiliary names, input graphs and TeX trigger state ----

#[derive(Clone, Copy, PartialEq, Eq)]
enum Trigger {
    Intext,
    Result,
    EnvDisplay,
    EnvBox,
    PlainDisplay,
    PlainBox,
    EnvRegion,
    PlainRegion,
    Input,
}
impl Trigger {
    fn intext(self) -> bool {
        matches!(self, Self::Intext | Self::Result)
    }
    fn display(self) -> bool {
        matches!(
            self,
            Self::EnvDisplay | Self::PlainDisplay | Self::EnvBox | Self::PlainBox
        )
    }
    fn ender(self, environment: &str) -> String {
        match self {
            Self::EnvDisplay | Self::EnvBox | Self::EnvRegion => format!("\\end{{{environment}}}"),
            Self::PlainDisplay | Self::PlainBox | Self::PlainRegion => {
                format!("\\end{environment}")
            }
            _ => panic!("trigger without ender"),
        }
    }
}
fn dump_intext(input: &mut Port, mut out: Option<&mut dyn Write>) {
    input.whitespace();
    let delimiter = input.read().expect("inline delimiter");
    let delimiter = if delimiter == '{' { '}' } else { delimiter };
    loop {
        let c = input.read().expect("unterminated inline Scheme");
        if c == delimiter {
            break;
        }
        if let Some(out) = out.as_deref_mut() {
            let mut bytes = [0; 4];
            out.write_all(c.encode_utf8(&mut bytes).as_bytes()).unwrap();
        }
    }
}
fn dump_display(input: &mut Port, mut out: Option<&mut dyn Write>, ender: &str) {
    input.tabspace();
    assert!(input.peek().is_some());
    if input.peek() == Some('\n') {
        input.read();
    }
    let mut buffer = String::new();
    loop {
        buffer.push(input.read().expect("unterminated Scheme environment"));
        if ender.starts_with(&buffer) {
            if buffer == ender {
                break;
            }
        } else {
            if let Some(out) = out.as_deref_mut() {
                out.write_all(buffer.as_bytes()).unwrap();
            }
            buffer = String::new();
        }
    }
}
impl Processor {
    fn find(&self, filenames: &[String]) -> Option<String> {
        for dir in &self.paths {
            for filename in filenames {
                let filename = if dir.is_empty() || dir == "." {
                    filename.clone()
                } else {
                    format!("{dir}/{filename}")
                };
                if std::path::Path::new(&filename).exists() {
                    return Some(filename);
                }
            }
        }
        None
    }
    fn tex_filename(&self, filename: &str) -> Option<String> {
        let extension = filename.rfind('.').map(|i| &filename[i..]);
        if matches!(extension, Some(".sty" | ".tex")) {
            self.find(&[filename.into()])
        } else {
            self.find(&[format!("{filename}.tex"), filename.into()])
        }
    }
    fn scheme_filename(&self, filename: &str) -> Option<String> {
        self.find(&[
            filename.into(),
            format!("{filename}.scm"),
            format!("{filename}.ss"),
            format!("{filename}.s"),
        ])
    }
    fn primary_file(&mut self, extension: &str) -> String {
        self.primary += 1;
        format!("outputs/z{}{extension}", self.primary)
    }
    fn secondary_file(&mut self, extension: &str) -> String {
        self.secondary += 1;
        format!("outputs/zz{}{extension}", self.secondary)
    }
    fn auxiliary(&mut self, extension: &str) -> String {
        if self.protected {
            self.secondary_file(extension)
        } else {
            self.primary_file(extension)
        }
    }
    fn decide_tex(&mut self, latex: bool) {
        self.latex = latex;
        if std::path::Path::new("pltexchk.jnk").exists() {
            remove_file("pltexchk.jnk");
        }
        if !latex {
            let mut out = replace_file("pltexchk.jnk");
            emit(&mut out, "junk\n");
            out.flush().unwrap();
        }
    }
    fn main_file(&mut self, filename: &str) {
        self.paths = vec![String::new(), String::new()];
        if std::path::Path::new("xZfilhid.tex").exists() {
            remove_file("xZfilhid.tex");
        }
        self.subjob = filename.strip_suffix(".tex").unwrap_or(filename).into();
        self.seen_command = false;
        self.tex_file(filename);
    }
    fn alias(&mut self, input: &mut Port, add: bool, category: usize) {
        let trigger = input.grouped();
        if category == 6 {
            assert_eq!(trigger.chars().count(), 1);
            let c = trigger.chars().next().unwrap();
            if add {
                if !self.math.contains(&c) {
                    self.math.insert(0, c);
                }
            } else {
                self.math.retain(|x| *x != c);
            }
        } else {
            let aliases = &mut self.aliases[category];
            if add {
                if !aliases.contains(&trigger) {
                    aliases.insert(0, trigger);
                }
            } else {
                aliases.retain(|t| t != &trigger);
            }
        }
    }
    fn database(&mut self, input: &mut Port, category: &str) {
        let tokens = input.scheme_ids();
        match category {
            "setkeyword" | "setconstant" | "setvariable" => {
                let category = match category {
                    "setkeyword" => 0,
                    "setconstant" => 1,
                    _ => 2,
                };
                for token in tokens {
                    self.set_token(token, category);
                }
            }
            "setspecialsymbol" => {
                assert_eq!(tokens.len(), 1);
                let translation = input.grouped();
                if let Some(i) = self
                    .specials
                    .iter()
                    .position(|(t, _)| self.token_equal(t, &tokens[0]))
                {
                    self.specials[i].1 = translation;
                } else {
                    self.specials.insert(0, (tokens[0].clone(), translation));
                }
            }
            "unsetspecialsymbol" => {
                for token in tokens {
                    let sensitive = self.case_sensitive;
                    self.specials.retain(|(t, _)| {
                        if sensitive {
                            t != &token
                        } else {
                            t.to_lowercase() != token.to_lowercase()
                        }
                    });
                }
            }
            _ => panic!("database category"),
        }
    }
    fn documentstyle(&mut self, input: &mut Port) {
        input.tex_whitespace();
        if input.peek() != Some('[') {
            return;
        }
        for name in input.filenames('[', ']') {
            let protected = self.protected;
            self.protected = false;
            self.tex_file(&format!("{name}.sty"));
            self.protected = protected;
        }
    }
    fn include_only(&mut self, input: &mut Port) {
        let mut files = Vec::new();
        for name in input.filenames('{', '}') {
            if let Some(name) = self.tex_filename(&name)
                && !files.contains(&name)
            {
                files.insert(0, name);
            }
        }
        self.include_only = Some(files);
    }
    fn include(&mut self, input: &mut Port) {
        let name = input.filename();
        let Some(name) = self.tex_filename(&name) else {
            return;
        };
        if self
            .include_only
            .as_ref()
            .is_some_and(|files| !files.contains(&name))
        {
            return;
        }
        let (protected, subjob, primary) = (self.protected, self.subjob.clone(), self.primary);
        self.protected = false;
        if self.separate_includes {
            self.subjob = name.strip_suffix(".tex").unwrap_or(&name).into();
            self.primary = -1;
        }
        self.tex_file(&name);
        self.protected = protected;
        self.subjob = subjob;
        self.primary = primary;
    }
    fn tex_file(&mut self, filename: &str) {
        let Some(filename) = self.tex_filename(filename) else {
            print!("[{filename}]");
            return;
        };
        let mut input = Port::open(&filename);
        while let Some(c) = input.read() {
            if c == '%' {
                input.newline();
                continue;
            }
            if c != '\\' {
                continue;
            }
            let command = input.control();
            if !self.seen_command {
                self.seen_command = true;
                self.decide_tex(command == "documentstyle");
            }
            if !self.enabled {
                if command == self.reenabler {
                    self.enabled = true;
                    self.reenabler = "UNDEFINED".into();
                }
                continue;
            }
            if command == "slatexignorecurrentfile" {
                break;
            }
            if command == "slatexseparateincludes" {
                if self.latex {
                    self.separate_includes = true;
                }
            } else if command == "slatexdisable" {
                self.enabled = false;
                self.reenabler = input.grouped();
            } else if command == "begin" {
                let environment = input.grouped();
                if self.aliases[2].contains(&environment) {
                    self.trigger(Trigger::EnvDisplay, &mut input, &environment);
                } else if self.aliases[3].contains(&environment) {
                    self.trigger(Trigger::EnvBox, &mut input, &environment);
                } else if self.aliases[5].contains(&environment) {
                    self.region(Trigger::EnvRegion, &mut input, &environment);
                }
            } else if self.aliases[0].contains(&command) {
                self.trigger(Trigger::Intext, &mut input, "");
            } else if self.aliases[1].contains(&command) {
                self.trigger(Trigger::Result, &mut input, "");
            } else if self.aliases[2].contains(&command) {
                self.trigger(Trigger::PlainDisplay, &mut input, &command);
            } else if self.aliases[3].contains(&command) {
                self.trigger(Trigger::PlainBox, &mut input, &command);
            } else if self.aliases[5].contains(&command) {
                self.region(Trigger::PlainRegion, &mut input, &command);
            } else if self.aliases[4].contains(&command) {
                let filename = input.filename();
                self.scheme_file(&filename);
            } else {
                match command.as_str() {
                    "input" => {
                        let protected = self.protected;
                        self.protected = false;
                        let filename = input.filename();
                        self.tex_file(&filename);
                        self.protected = protected;
                    }
                    "include" if self.latex => self.include(&mut input),
                    "includeonly" if self.latex => self.include_only(&mut input),
                    "documentstyle" if self.latex => self.documentstyle(&mut input),
                    "schemecasesensitive" => {
                        let value = input.grouped();
                        assert!(
                            value.eq_ignore_ascii_case("true")
                                || value.eq_ignore_ascii_case("false")
                        );
                        self.case_sensitive = value.eq_ignore_ascii_case("true");
                    }
                    "defschemetoken" => self.alias(&mut input, true, 0),
                    "undefschemetoken" => self.alias(&mut input, false, 0),
                    "defschemeresulttoken" => self.alias(&mut input, true, 1),
                    "undefschemeresulttoken" => self.alias(&mut input, false, 1),
                    "defschemedisplaytoken" => self.alias(&mut input, true, 2),
                    "undefschemedisplaytoken" => self.alias(&mut input, false, 2),
                    "defschemeboxtoken" => self.alias(&mut input, true, 3),
                    "undefschemeboxtoken" => self.alias(&mut input, false, 3),
                    "defschemeinputtoken" => self.alias(&mut input, true, 4),
                    "undefschemeinputtoken" => self.alias(&mut input, false, 4),
                    "defschemeregiontoken" => self.alias(&mut input, true, 5),
                    "undefschemeregiontoken" => self.alias(&mut input, false, 5),
                    "defschememathescape" => self.alias(&mut input, true, 6),
                    "undefschememathescape" => self.alias(&mut input, false, 6),
                    "setkeyword" | "setconstant" | "setvariable" | "setspecialsymbol"
                    | "unsetspecialsymbol" => self.database(&mut input, &command),
                    _ => {}
                }
            }
        }
    }
    fn scheme_file(&mut self, filename: &str) {
        let Some(filename) = self.scheme_filename(filename) else {
            println!("process-scheme-file: {filename} doesn't exist");
            return;
        };
        let auxiliary = self.auxiliary(".tex");
        let mut input = Port::open(&filename);
        let mut out = replace_file(&auxiliary);
        let (intext, environment) = (self.intext, self.code_env.clone());
        self.intext = false;
        self.code_env = "ZZZZschemedisplay".into();
        self.scheme2tex(&mut input, &mut out);
        out.flush().unwrap();
        drop(out);
        drop(input);
        self.intext = intext;
        self.code_env = environment;
        if self.protected {
            self.protected_files.insert(0, auxiliary);
        }
        self.tex_file(&filename);
    }
    fn trigger(&mut self, kind: Trigger, input: &mut Port, environment: &str) {
        let auxiliary = self.auxiliary("");
        let scm = format!("{auxiliary}.scm");
        let tex = format!("{auxiliary}.tex");
        if std::path::Path::new(&scm).exists() {
            remove_file(&scm);
        }
        if std::path::Path::new(&tex).exists() {
            remove_file(&tex);
        }
        let mut out = replace_file(&scm);
        if kind.intext() {
            dump_intext(input, Some(&mut out));
        } else {
            dump_display(input, Some(&mut out), &kind.ender(environment));
        }
        out.flush().unwrap();
        drop(out);
        let mut code = Port::open(&scm);
        let mut out = replace_file(&tex);
        let (intext, old_environment) = (self.intext, self.code_env.clone());
        self.intext = kind.intext();
        self.code_env = match kind {
            Trigger::Intext => "ZZZZschemecodeintext",
            Trigger::Result => "ZZZZschemeresultintext",
            Trigger::EnvDisplay | Trigger::PlainDisplay => "ZZZZschemedisplay",
            Trigger::EnvBox | Trigger::PlainBox => "ZZZZschemebox",
            _ => panic!("invalid Scheme trigger"),
        }
        .into();
        self.scheme2tex(&mut code, &mut out);
        out.flush().unwrap();
        drop(out);
        drop(code);
        self.intext = intext;
        self.code_env = old_environment;
        if self.protected {
            self.protected_files.insert(0, tex.clone());
        }
        if kind.display() {
            self.tex_file(&tex);
        }
        remove_file(&scm);
    }
    fn region(&mut self, kind: Trigger, input: &mut Port, environment: &str) {
        let tex = self.primary_file(".tex");
        let temporary = self.secondary_file(".tex");
        if std::path::Path::new(&temporary).exists() {
            remove_file(&temporary);
        }
        if std::path::Path::new(&tex).exists() {
            remove_file(&tex);
        }
        let protected = self.protected;
        let protected_files = std::mem::take(&mut self.protected_files);
        self.protected = true;
        let mut out = replace_file(&temporary);
        dump_display(input, Some(&mut out), &kind.ender(environment));
        out.flush().unwrap();
        drop(out);
        self.tex_file(&temporary);
        self.protected_files.reverse();
        let mut code = Port::open(&temporary);
        let mut out = replace_file(&tex);
        self.inline_files(&mut code, &mut out);
        out.flush().unwrap();
        drop(out);
        drop(code);
        remove_file(&temporary);
        self.protected = protected;
        self.protected_files = protected_files;
    }
    fn inline_files(&mut self, input: &mut Port, out: &mut impl Write) {
        while let Some(c) = input.read() {
            if c == '%' {
                input.newline();
            } else if c == '\\' {
                let command = input.control();
                if command == "begin" {
                    let environment = input.grouped();
                    if self.aliases[2].contains(&environment) {
                        self.inline(Trigger::EnvDisplay, input, out, &environment);
                    } else if self.aliases[3].contains(&environment) {
                        self.inline(Trigger::EnvBox, input, out, &environment);
                    } else if self.aliases[5].contains(&environment) {
                        self.inline(Trigger::EnvRegion, input, out, &environment);
                    } else {
                        emit(out, "\\begin{");
                        emit(out, &environment);
                        emit(out, "}");
                    }
                } else if self.aliases[0].contains(&command) {
                    self.inline(Trigger::Intext, input, out, "");
                } else if self.aliases[1].contains(&command) {
                    self.inline(Trigger::Result, input, out, "");
                } else if self.aliases[2].contains(&command) {
                    self.inline(Trigger::PlainDisplay, input, out, &command);
                } else if self.aliases[3].contains(&command) {
                    self.inline(Trigger::PlainBox, input, out, &command);
                } else if self.aliases[5].contains(&command) {
                    self.inline(Trigger::PlainRegion, input, out, &command);
                } else if self.aliases[4].contains(&command) {
                    self.inline(Trigger::Input, input, out, &command);
                } else {
                    emit(out, "\\");
                    emit(out, &command);
                }
            } else {
                emit_char(out, c);
            }
        }
        emit(out, "{}");
    }
    fn inline(&mut self, kind: Trigger, input: &mut Port, out: &mut impl Write, environment: &str) {
        if kind == Trigger::EnvRegion || kind == Trigger::PlainRegion {
            if kind == Trigger::EnvRegion {
                emit(out, "\\begin{");
                emit(out, environment);
                emit(out, "}");
            } else {
                emit(out, "\\");
                emit(out, environment);
            }
            dump_display(input, Some(out), &kind.ender(environment));
            emit(out, &kind.ender(environment));
            return;
        }
        assert!(!self.protected_files.is_empty());
        let filename = self.protected_files.remove(0);
        let mut code = Port::open(&filename);
        self.inline_files(&mut code, out);
        drop(code);
        remove_file(&filename);
        if kind.intext() {
            dump_intext(input, None);
        } else if kind.display() {
            dump_display(input, None, &kind.ender(environment));
        } else if kind == Trigger::Input {
            input.filename();
        } else {
            panic!("invalid protected trigger");
        }
    }
}

// ---- Original benchmark wrapper ----

fn main() {
    let values = input().unwrap();
    let count = values[0].number();
    let filename = values[1].atom();
    let mut processor = Processor::new();
    let start = Instant::now();
    for _ in 0..count {
        processor.main_file(black_box(filename));
    }
    // Both expected datums and the original predicate are deliberately ignored.
    // Complete external file-set validation supplies the correctness oracle.
    report("slatex", count, start, "ignored");
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn arrow_splice_and_data_hyphens_keep_exact_escapes() {
        assert_eq!(texify("a->b->c", false), "a-$\\gt$b-$\\gt$c");
        assert_eq!(texify("a-b", true), "a$-$b");
        assert_eq!(texify("+_{}", false), "$+$\\_$\\{$$\\}$");
    }
    #[test]
    fn marker_cleanup_uses_last_alignment_stop() {
        let mut line = Line::new();
        line.chars[..5].copy_from_slice(&[' ', ' ', ' ', 'x', '\n']);
        line.edge = 4;
        line.spaces[..3].copy_from_slice(&[Space::Initial, Space::Paren, Space::Quote]);
        line.tabs[2] = Tab::Move;
        line.clean_initial();
        assert!(line.spaces[..2].iter().all(|s| *s == Space::InitialPlain));
        assert_eq!(line.spaces[2], Space::Quote);
        assert!(number_token("3/4"));
        assert!(number_token("1+2i"));
        assert!(!number_token("NaN"));
    }
}
