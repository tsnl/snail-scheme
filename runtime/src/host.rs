//! Operating-system resources behind AWI. IDs never name GC memory.
//!
//! Explicit close releases file/input resources. An optional host finalization
//! callback releases any remaining payload when its GC wrapper dies; WasmGC
//! alone does not run Rust destructors. Output-string buffers survive explicit
//! close so get-output-string remains useful, then are released by finalization.

use std::{
    fs::File,
    io::{Read, Write},
};

// ---- Ports ----

#[derive(Debug)]
pub(crate) enum Port {
    Input { chars: Vec<char>, offset: usize },
    Output { buffer: String, closed: bool },
    FileOutput(File),
    Closed,
    Stdin,
    Stdout,
    Stderr,
}

impl Port {
    pub(crate) fn input_file(path: &str) -> Result<Self, String> {
        let text = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
        Ok(Self::Input {
            chars: text.chars().collect(),
            offset: 0,
        })
    }

    pub(crate) fn output_file(path: &str) -> Result<Self, String> {
        File::create(path)
            .map(Self::FileOutput)
            .map_err(|e| format!("{path}: {e}"))
    }

    pub(crate) fn output_string() -> Self {
        Self::Output {
            buffer: String::new(),
            closed: false,
        }
    }

    pub(crate) fn is_input(&self) -> bool {
        matches!(self, Self::Input { .. } | Self::Stdin)
    }

    pub(crate) fn is_output(&self) -> bool {
        matches!(
            self,
            Self::Output { closed: false, .. } | Self::FileOutput(_) | Self::Stdout | Self::Stderr
        )
    }

    pub(crate) fn close(&mut self) -> Result<(), String> {
        match self {
            Self::Output { closed, .. } => *closed = true,
            Self::FileOutput(file) => {
                file.flush().map_err(|e| e.to_string())?;
                *self = Self::Closed;
            }
            Self::Stdout => {
                std::io::stdout().flush().map_err(|e| e.to_string())?;
                *self = Self::Closed;
            }
            Self::Stderr => {
                std::io::stderr().flush().map_err(|e| e.to_string())?;
                *self = Self::Closed;
            }
            _ => *self = Self::Closed,
        }
        Ok(())
    }

    pub(crate) fn read_char(&mut self) -> Result<Option<char>, String> {
        match self {
            Self::Input { chars, offset } => {
                let character = chars.get(*offset).copied();
                *offset += usize::from(character.is_some());
                Ok(character)
            }
            Self::Stdin => read_stdin_char(),
            Self::Closed => Err("port is closed".into()),
            _ => Err("expected an input port".into()),
        }
    }

    pub(crate) fn read_string(&mut self, count: usize) -> Result<Option<String>, String> {
        if !self.is_input() {
            return Err("expected an open input port".into());
        }
        let mut text = String::new();
        for _ in 0..count {
            let Some(character) = self.read_char()? else {
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

    pub(crate) fn captured_output(&self) -> Result<&str, String> {
        match self {
            Self::Output { buffer, .. } => Ok(buffer),
            _ => Err("expected a string output port".into()),
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
            Self::Output { closed: true, .. } | Self::Closed => Err("port is closed".into()),
            _ => Err("expected an output port".into()),
        }
    }
}

// ---- UTF-8 and stream I/O ----

fn write_stream(output: &mut impl Write, text: &str) -> Result<(), String> {
    output
        .write_all(text.as_bytes())
        .and_then(|_| output.flush())
        .map_err(|e| e.to_string())
}

fn read_stdin_char() -> Result<Option<char>, String> {
    read_utf8_char(&mut std::io::stdin().lock()).map_err(|e| format!("read-char: {e}"))
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
        let mut port = Port::Input {
            chars: "aλ😀z".chars().collect(),
            offset: 0,
        };
        assert_eq!(port.read_string(0).unwrap(), Some(String::new()));
        assert_eq!(port.read_string(2).unwrap(), Some("aλ".into()));
        assert_eq!(port.read_string(99).unwrap(), Some("😀z".into()));
        assert_eq!(port.read_string(1).unwrap(), None);
        assert_eq!(port.read_string(0).unwrap(), Some(String::new()));
        port.close().unwrap();
        assert!(port.read_string(0).is_err());
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
    }
}
