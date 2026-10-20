//! Buffered text streams for scalar Lofi I/O. The owning file registry closes
//! them explicitly; borrowed stdin/stdout remain open after invocation cleanup.

use std::{
    cell::RefCell,
    fs::File,
    io::{BufRead, BufReader, BufWriter, Read, Write},
};

// ---- Ports ----

pub(crate) enum Port {
    Input(TextInput),
    FileOutput(BufWriter<File>),
    Stdout,
    Closed,
    #[cfg(test)]
    Capture(String),
}

impl Port {
    pub(crate) fn input_file(path: &str) -> Result<Self, String> {
        let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
        Ok(Self::Input(TextInput::new(file)))
    }

    pub(crate) fn stdin() -> Self {
        Self::Input(TextInput::new(std::io::stdin()))
    }

    pub(crate) fn output_file(path: &str) -> Result<Self, String> {
        File::create(path)
            .map(|file| Self::FileOutput(BufWriter::new(file)))
            .map_err(|e| format!("{path}: {e}"))
    }

    pub(crate) fn is_output(&self) -> bool {
        match self {
            Self::FileOutput(_) | Self::Stdout => true,
            #[cfg(test)]
            Self::Capture(_) => true,
            _ => false,
        }
    }

    pub(crate) fn is_open(&self) -> bool {
        !matches!(self, Self::Closed)
    }

    pub(crate) fn close(&mut self) -> Result<(), String> {
        if self.is_output() {
            self.flush()?;
        }
        *self = Self::Closed;
        Ok(())
    }

    pub(crate) fn read_char(&mut self) -> Result<Option<char>, String> {
        self.text_input()?.read_char()
    }

    pub(crate) fn text_input(&mut self) -> Result<&mut TextInput, String> {
        match self {
            Self::Input(input) => Ok(input),
            Self::Closed => Err("port is closed".into()),
            _ => Err("expected an input port".into()),
        }
    }

    pub(crate) fn flush(&mut self) -> Result<(), String> {
        match self {
            Self::FileOutput(file) => file.flush().map_err(|error| error.to_string()),
            Self::Stdout => flush_standard_output(),
            #[cfg(test)]
            Self::Capture(_) => Ok(()),
            _ => Err("expected an open output port".into()),
        }
    }

    pub(crate) fn write(&mut self, text: &str) -> Result<(), String> {
        match self {
            Self::FileOutput(file) => file.write_all(text.as_bytes()).map_err(|e| e.to_string()),
            Self::Stdout => write_standard_output(text),
            #[cfg(test)]
            Self::Capture(buffer) => {
                buffer.push_str(text);
                Ok(())
            }
            Self::Closed => Err("port is closed".into()),
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
}

impl TextInput {
    fn new(input: impl Read + 'static) -> Self {
        Self {
            input: BufReader::new(Box::new(input)),
            peeked: None,
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

    // Positive packets hold up to seven ASCII code+1 byte lanes. Zero ends
    // the lanes; -1 is EOF; other negatives hold one scalar as -code-2.
    // Only the first character may fill the buffer or decode UTF-8. Extra
    // lanes never wait for input or report a later malformed suffix early.
    pub(crate) fn read_packet(&mut self) -> Result<i64, String> {
        Ok(match self.read_char()? {
            None => -1,
            Some(character) if character.is_ascii() => self.ascii_packet(character as u8),
            Some(character) => -i64::from(character as u32) - 2,
        })
    }

    fn ascii_packet(&mut self, first: u8) -> i64 {
        let mut packet = i64::from(first) + 1;
        let mut count = 0;
        for &byte in self.input.buffer().iter().take(6) {
            if !byte.is_ascii() {
                break;
            }
            packet |= (i64::from(byte) + 1) << (8 * (count + 1));
            count += 1;
        }
        self.input.consume(count);
        packet
    }
}

// ---- Standard output ----

// Standard output is line buffered. A newline, a full buffer, a standard-input
// read, an explicit flush or cleanup writes it. Taking the buffer before the
// write reports a failure once; the text that failed to write is discarded.
thread_local! {
    static STANDARD_OUTPUT: RefCell<Vec<u8>> = const { RefCell::new(Vec::new()) };
}

const STANDARD_OUTPUT_CAPACITY: usize = 8192;

fn write_standard_output(text: &str) -> Result<(), String> {
    let full = STANDARD_OUTPUT.with_borrow_mut(|buffer| {
        buffer.extend_from_slice(text.as_bytes());
        text.contains('\n') || buffer.len() >= STANDARD_OUTPUT_CAPACITY
    });
    if full {
        flush_standard_output()
    } else {
        Ok(())
    }
}

pub(crate) fn flush_standard_output() -> Result<(), String> {
    let bytes = STANDARD_OUTPUT.with_borrow_mut(std::mem::take);
    if bytes.is_empty() {
        return Ok(());
    }
    let mut output = std::io::stdout().lock();
    output
        .write_all(&bytes)
        .and_then(|()| output.flush())
        .map_err(|e| e.to_string())
}

// ---- UTF-8 input ----

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
impl Port {
    pub(crate) fn input_string(text: String) -> Self {
        Self::Input(TextInput::new(std::io::Cursor::new(text.into_bytes())))
    }

    pub(crate) fn output_string() -> Self {
        Self::Capture(String::new())
    }

    pub(crate) fn captured_output(&self) -> Result<&str, String> {
        match self {
            Self::Capture(text) => Ok(text),
            _ => Err("expected captured output".into()),
        }
    }
}

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
    fn lookahead_eof_and_close_share_one_character_cursor() {
        let mut port = Port::input_string("λ\r\n😀".into());
        for character in ['λ', '\r', '\n', '😀'] {
            assert_eq!(
                port.text_input().unwrap().peek_char().unwrap(),
                Some(character)
            );
            assert_eq!(
                port.text_input().unwrap().peek_char().unwrap(),
                Some(character)
            );
            assert_eq!(port.read_char().unwrap(), Some(character));
        }
        assert_eq!(port.text_input().unwrap().peek_char().unwrap(), None);
        assert_eq!(port.read_char().unwrap(), None);
        port.close().unwrap();
        port.close().unwrap();
        assert!(!port.is_open());
        assert!(port.read_char().is_err());
        assert!(port.text_input().is_err());
    }

    #[test]
    fn ascii_packets_distinguish_nul_del_exhaustion_unicode_and_eof() {
        let mut input = TextInput::new(std::io::Cursor::new(
            "\0\u{7f}abcdeZλ😀\u{10ffff}".as_bytes(),
        ));
        let mut packet = input.read_packet().unwrap();
        for byte in b"\0\x7fabcde" {
            assert_eq!(packet & 255, i64::from(*byte) + 1);
            packet >>= 8;
        }
        assert_eq!(packet, 0);
        assert_eq!(input.read_packet().unwrap(), i64::from(b'Z') + 1);
        for character in ['λ', '😀', '\u{10ffff}'] {
            assert_eq!(
                input.read_packet().unwrap(),
                -i64::from(character as u32) - 2
            );
        }
        assert_eq!(input.read_packet().unwrap(), -1);
        assert_eq!(input.read_packet().unwrap(), -1);
    }

    #[test]
    fn packet_returns_valid_prefix_before_malformed_or_truncated_utf8() {
        for suffix in [
            &b"\xff"[..],
            &b"\xf0\x9f"[..],
            &b"\xed\xa0\x80"[..],
            &b"\xc2a"[..],
        ] {
            let mut bytes = b"abc".to_vec();
            bytes.extend_from_slice(suffix);
            let mut input = TextInput::new(std::io::Cursor::new(bytes));
            assert_eq!(input.read_packet().unwrap(), 98 | (99 << 8) | (100 << 16));
            assert!(input.read_packet().is_err());
        }
    }

    #[test]
    fn packet_preserves_lookahead_and_scalars_split_across_buffer_fills() {
        let mut input = TextInput {
            input: BufReader::with_capacity(4, Box::new(std::io::Cursor::new("abcλ😀".as_bytes()))),
            peeked: None,
        };
        assert_eq!(input.peek_char().unwrap(), Some('a'));
        assert_eq!(input.read_packet().unwrap(), 98 | (99 << 8) | (100 << 16));
        assert_eq!(input.read_packet().unwrap(), -i64::from('λ' as u32) - 2);
        assert_eq!(input.read_packet().unwrap(), -i64::from('😀' as u32) - 2);
        assert_eq!(input.read_packet().unwrap(), -1);
    }

    struct OneRead(bool);

    impl Read for OneRead {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            assert!(!self.0, "packet attempted an extra underlying read");
            self.0 = true;
            buffer[0] = b'a';
            Ok(1)
        }
    }

    #[test]
    fn packet_does_not_fill_again_after_one_available_character() {
        for peek in [false, true] {
            let mut input = TextInput::new(OneRead(false));
            if peek {
                assert_eq!(input.peek_char().unwrap(), Some('a'));
            }
            assert_eq!(input.read_packet().unwrap(), i64::from(b'a') + 1);
        }
    }
}
