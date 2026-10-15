//! Operating-system resources behind ABI. IDs never name GC memory.
//!
//! Explicit close releases file/input resources. An optional host finalization
//! callback releases any remaining payload when its GC wrapper dies; WasmGC
//! alone does not run Rust destructors. Output-string buffers survive explicit
//! close so get-output-string remains useful, then are released by finalization.

use std::{
    fs::File,
    io::{BufReader, BufWriter, Cursor, Read, Write},
};

// ---- Ports ----

pub(crate) enum Port {
    Input(TextInput),
    Output { buffer: String, closed: bool },
    FileOutput(BufWriter<File>),
    BinaryInput(BufReader<File>),
    Closed { input: bool, binary: bool },
    Stdout,
    Stderr,
}

impl Port {
    pub(crate) fn input_file(path: &str) -> Result<Self, String> {
        let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
        Ok(Self::Input(TextInput::new(file)))
    }

    pub(crate) fn input_string(text: String) -> Self {
        Self::Input(TextInput::new(Cursor::new(text.into_bytes())))
    }

    pub(crate) fn stdin() -> Self {
        Self::Input(TextInput::new(std::io::stdin()))
    }

    pub(crate) fn output_file(path: &str) -> Result<Self, String> {
        File::create(path)
            .map(|file| Self::FileOutput(BufWriter::new(file)))
            .map_err(|e| format!("{path}: {e}"))
    }

    pub(crate) fn binary_input_file(path: &str) -> Result<Self, String> {
        File::open(path)
            .map(|file| Self::BinaryInput(BufReader::new(file)))
            .map_err(|e| format!("{path}: {e}"))
    }

    pub(crate) fn output_string() -> Self {
        Self::Output {
            buffer: String::new(),
            closed: false,
        }
    }

    pub(crate) fn is_input(&self) -> bool {
        matches!(
            self,
            Self::Input(_) | Self::BinaryInput(_) | Self::Closed { input: true, .. }
        )
    }

    pub(crate) fn is_output(&self) -> bool {
        matches!(
            self,
            Self::Output { .. }
                | Self::FileOutput(_)
                | Self::Stdout
                | Self::Stderr
                | Self::Closed { input: false, .. }
        )
    }

    pub(crate) fn is_open(&self) -> bool {
        !matches!(
            self,
            Self::Closed { .. } | Self::Output { closed: true, .. }
        )
    }

    pub(crate) fn is_binary(&self) -> bool {
        matches!(
            self,
            Self::BinaryInput(_) | Self::Closed { binary: true, .. }
        )
    }

    pub(crate) fn close(&mut self) -> Result<(), String> {
        if let Self::Output { closed, .. } = self {
            *closed = true;
            return Ok(());
        }
        let closed = Self::Closed {
            input: self.is_input(),
            binary: self.is_binary(),
        };
        if self.is_open() && self.is_output() {
            self.flush()?;
        }
        *self = closed;
        Ok(())
    }

    pub(crate) fn read_char(&mut self) -> Result<Option<char>, String> {
        self.text_input()?.read_char()
    }

    pub(crate) fn text_input(&mut self) -> Result<&mut TextInput, String> {
        match self {
            Self::Input(input) => Ok(input),
            Self::Closed { .. } => Err("port is closed".into()),
            _ => Err("expected an input port".into()),
        }
    }

    pub(crate) fn read_string(&mut self, count: usize) -> Result<Option<String>, String> {
        let input = self.text_input()?;
        let mut text = String::new();
        for _ in 0..count {
            let Some(character) = input.read_char()? else {
                break;
            };
            text.push(character);
        }
        Ok(if count > 0 && text.is_empty() {
            None
        } else {
            Some(text)
        })
    }

    pub(crate) fn read_bytes(&mut self, count: usize) -> Result<Option<Vec<u8>>, String> {
        let Self::BinaryInput(file) = self else {
            return Err("expected an open binary input port".into());
        };
        let mut bytes = Vec::new();
        file.take(count as u64)
            .read_to_end(&mut bytes)
            .map_err(|e| e.to_string())?;
        Ok(if count > 0 && bytes.is_empty() {
            None
        } else {
            Some(bytes)
        })
    }

    pub(crate) fn captured_output(&self) -> Result<&str, String> {
        match self {
            Self::Output { buffer, .. } => Ok(buffer),
            _ => Err("expected a string output port".into()),
        }
    }

    pub(crate) fn flush(&mut self) -> Result<(), String> {
        match self {
            Self::Output { closed: false, .. } => Ok(()),
            Self::FileOutput(file) => file.flush().map_err(|error| error.to_string()),
            Self::Stdout => std::io::stdout().flush().map_err(|error| error.to_string()),
            Self::Stderr => std::io::stderr().flush().map_err(|error| error.to_string()),
            _ => Err("expected an open output port".into()),
        }
    }

    pub(crate) fn write(&mut self, text: &str) -> Result<(), String> {
        match self {
            Self::Output {
                buffer,
                closed: false,
            } => {
                buffer.push_str(text);
                Ok(())
            }
            Self::FileOutput(file) => file.write_all(text.as_bytes()).map_err(|e| e.to_string()),
            Self::Stdout => write_stream(&mut std::io::stdout().lock(), text),
            Self::Stderr => write_stream(&mut std::io::stderr().lock(), text),
            Self::Output { closed: true, .. } | Self::Closed { .. } => Err("port is closed".into()),
            _ => Err("expected an output port".into()),
        }
    }
}

// ---- Text input ----

// One lookahead belongs to the port, not the reader invocation. A parser can
// inspect a delimiter without stealing it from a later read-char or peek-char.
// Buffered streams return available input; they never read to EOF up front.
pub(crate) struct TextInput {
    input: BufReader<Box<dyn Read>>,
    peeked: Option<Option<char>>,
    pub(crate) fold_case: bool,
}

impl TextInput {
    fn new(input: impl Read + 'static) -> Self {
        Self {
            input: BufReader::new(Box::new(input)),
            peeked: None,
            fold_case: false,
        }
    }

    pub(crate) fn peek_char(&mut self) -> Result<Option<char>, String> {
        if self.peeked.is_none() {
            self.peeked = Some(read_utf8_char(&mut self.input)?);
        }
        Ok(self.peeked.unwrap())
    }

    pub(crate) fn read_char(&mut self) -> Result<Option<char>, String> {
        match self.peeked.take() {
            Some(character) => Ok(character),
            None => read_utf8_char(&mut self.input),
        }
    }

    pub(crate) fn read_line(&mut self) -> Result<Option<String>, String> {
        let mut text = String::new();
        while let Some(character) = self.read_char()? {
            match character {
                '\n' => return Ok(Some(text)),
                '\r' => {
                    if self.peek_char()? == Some('\n') {
                        self.read_char()?;
                    }
                    return Ok(Some(text));
                }
                character => text.push(character),
            }
        }
        Ok(if text.is_empty() { None } else { Some(text) })
    }
}

// ---- UTF-8 and stream I/O ----

fn write_stream(output: &mut impl Write, text: &str) -> Result<(), String> {
    output
        .write_all(text.as_bytes())
        .and_then(|_| output.flush())
        .map_err(|e| e.to_string())
}

/// Read one Unicode scalar without buffering past it or waiting for stdin EOF.
fn read_utf8_char(input: &mut impl Read) -> Result<Option<char>, String> {
    let mut bytes = [0_u8; 4];
    loop {
        match input.read(&mut bytes[..1]) {
            Ok(0) => return Ok(None),
            Ok(_) => break,
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
            Err(e) => return Err(e.to_string()),
        }
    }
    let length = utf8_width(bytes[0])?;
    input
        .read_exact(&mut bytes[1..length])
        .map_err(|e| e.to_string())?;
    let text = std::str::from_utf8(&bytes[..length]).map_err(|e| e.to_string())?;
    Ok(text.chars().next())
}

fn utf8_width(first: u8) -> Result<usize, String> {
    match first {
        0x00..=0x7f => Ok(1),
        0xc2..=0xdf => Ok(2),
        0xe0..=0xef => Ok(3),
        0xf0..=0xf4 => Ok(4),
        _ => Err("invalid UTF-8".into()),
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reads_unicode_without_consuming_the_next_scalar() {
        let mut bytes = "aλ😀".as_bytes();
        for character in ['a', 'λ', '😀'] {
            assert_eq!(read_utf8_char(&mut bytes).unwrap(), Some(character));
        }
        assert_eq!(read_utf8_char(&mut bytes).unwrap(), None);
        assert!(read_utf8_char(&mut &[0xff][..]).is_err());
        assert!(read_utf8_char(&mut &[0xf0, 0x9f][..]).is_err());
    }

    #[test]
    fn empty_reads_and_eof_remain_distinct() {
        let mut port = Port::input_string("aλ😀z".into());
        assert_eq!(port.read_string(0).unwrap(), Some(String::new()));
        assert_eq!(port.read_string(2).unwrap(), Some("aλ".into()));
        assert_eq!(port.read_string(99).unwrap(), Some("😀z".into()));
        assert_eq!(port.read_string(1).unwrap(), None);
        assert_eq!(port.read_string(0).unwrap(), Some(String::new()));
        port.close().unwrap();
        assert!(port.read_string(0).is_err());
        port.close().unwrap();
        assert!(port.is_input() && !port.is_binary() && !port.is_open());
    }

    #[test]
    fn lookahead_and_line_endings_share_the_character_cursor() {
        let mut port = Port::input_string("λ\r\nnext\rfinal".into());
        let input = port.text_input().unwrap();
        assert_eq!(input.peek_char().unwrap(), Some('λ'));
        assert_eq!(input.peek_char().unwrap(), Some('λ'));
        assert_eq!(input.read_line().unwrap(), Some("λ".into()));
        assert_eq!(input.read_line().unwrap(), Some("next".into()));
        assert_eq!(input.read_line().unwrap(), Some("final".into()));
        assert_eq!(input.peek_char().unwrap(), None);
        assert_eq!(input.read_line().unwrap(), None);
    }

    #[test]
    fn string_output_survives_close_but_rejects_further_writes() {
        let mut port = Port::output_string();
        port.write("λ\n").unwrap();
        port.close().unwrap();
        assert_eq!(port.captured_output().unwrap(), "λ\n");
        assert!(port.write("x").is_err());
        port.close().unwrap();
        assert_eq!(port.captured_output().unwrap(), "λ\n");
        assert!(port.is_output() && !port.is_binary() && !port.is_open());
    }
}
