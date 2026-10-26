//! Buffered streams for scalar Lofi I/O: text by Unicode scalar, and binary
//! files by byte. The owning file registry closes them explicitly; borrowed
//! stdin/stdout remain open after invocation cleanup.

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

    pub(crate) fn read_byte(&mut self) -> Result<Option<u8>, String> {
        self.text_input()?.read_byte()
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

    pub(crate) fn write_bytes(&mut self, bytes: &[u8]) -> Result<(), String> {
        match self {
            Self::FileOutput(file) => file.write_all(bytes).map_err(|e| e.to_string()),
            Self::Closed => Err("port is closed".into()),
            _ => Err("expected a file output port".into()),
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

    // Reading by byte shares the buffer, so a file read partly as text and
    // partly as bytes sees one stream.
    pub(crate) fn read_byte(&mut self) -> Result<Option<u8>, String> {
        let mut byte = [0_u8; 1];
        loop {
            match self.input.read(&mut byte) {
                Ok(0) => return Ok(None),
                Ok(_) => return Ok(Some(byte[0])),
                Err(e) if e.kind() == std::io::ErrorKind::Interrupted => continue,
                Err(e) => return Err(e.to_string()),
            }
        }
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
    write_patiently(&mut output, &bytes).map_err(|e| e.to_string())
}

// A host may hand over standard output as a non-blocking pipe, which
// refuses writes while it is full, as when a program prints faster than
// its reader reads. Waiting a moment and writing the rest keeps the output
// whole; other failures end the program.
fn write_patiently(output: &mut impl Write, mut bytes: &[u8]) -> std::io::Result<()> {
    let wait = || std::thread::sleep(std::time::Duration::from_millis(1));
    while !bytes.is_empty() {
        match output.write(bytes) {
            Ok(0) => return Err(std::io::ErrorKind::WriteZero.into()),
            Ok(count) => bytes = &bytes[count..],
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => wait(),
            Err(e) => return Err(e),
        }
    }
    loop {
        match output.flush() {
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => wait(),
            Err(e) if e.kind() == std::io::ErrorKind::Interrupted => {}
            result => return result,
        }
    }
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

    // Refuses every other write, as a full non-blocking pipe does.
    struct Busy {
        written: Vec<u8>,
        ready: bool,
    }

    impl Write for Busy {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.ready = !self.ready;
            if !self.ready {
                return Err(std::io::ErrorKind::WouldBlock.into());
            }
            let count = bytes.len().min(3);
            self.written.extend_from_slice(&bytes[..count]);
            Ok(count)
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn writes_whole_output_to_a_busy_pipe() {
        let mut pipe = Busy {
            written: Vec::new(),
            ready: false,
        };
        write_patiently(&mut pipe, b"a long line of output").unwrap();
        assert_eq!(pipe.written, b"a long line of output");
    }

    #[test]
    fn reads_bytes_that_are_not_text() {
        let mut port = Port::Input(TextInput::new(std::io::Cursor::new(vec![0x89, b'P', 0xff])));
        for byte in [0x89, b'P', 0xff] {
            assert_eq!(port.read_byte().unwrap(), Some(byte));
        }
        assert_eq!(port.read_byte().unwrap(), None);
        port.close().unwrap();
        assert!(port.read_byte().is_err());
    }

    #[test]
    fn writes_bytes_that_are_not_text() {
        let path = std::env::temp_dir().join(format!("snail-write-bytes-{}", std::process::id()));
        let mut port = Port::output_file(path.to_str().unwrap()).unwrap();
        port.write_bytes(&[0x89, b'P', 0xff]).unwrap();
        port.close().unwrap();
        assert!(port.write_bytes(&[0]).is_err());
        assert_eq!(std::fs::read(&path).unwrap(), [0x89, b'P', 0xff]);
        std::fs::remove_file(path).unwrap();
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
