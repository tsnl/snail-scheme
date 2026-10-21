//! Buffered text streams for scalar Lofi I/O. The owning file registry closes
//! them explicitly; borrowed stdin/stdout remain open after invocation cleanup.

use std::{
    cell::RefCell,
    fs::File,
    io::{BufReader, BufWriter, Read, Write},
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
}

impl TextInput {
    fn new(input: impl Read + 'static) -> Self {
        Self {
            input: BufReader::new(Box::new(input)),
        }
    }

    pub(crate) fn read_char(&mut self) -> Result<Option<char>, String> {
        read_utf8_char(&mut self.input)
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
    fn reads_end_at_eof_and_after_close() {
        let mut port = Port::input_string("λ\r\n😀".into());
        for character in ['λ', '\r', '\n', '😀'] {
            assert_eq!(port.read_char().unwrap(), Some(character));
        }
        assert_eq!(port.read_char().unwrap(), None);
        port.close().unwrap();
        port.close().unwrap();
        assert!(port.read_char().is_err());
        assert!(port.text_input().is_err());
    }
}
