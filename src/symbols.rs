//! Process-local symbol IDs. Rust owns names; Scheme carries a tagged 31-bit ID.
//! Literal IDs are fixed by the compiler, and dynamic IDs follow them.

use crate::{Kind, Root, arguments, fail_message, finish};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, MutexGuard, OnceLock},
};

// ---- Names and stable identifiers ----

const SYMBOL_BIT: u32 = 1 << 31;

struct Name {
    spelling: Arc<str>,
    characters: Vec<u32>,
}

#[derive(Default)]
struct Symbols {
    ids: HashMap<Arc<str>, u32>,
    names: Vec<Name>,
}

fn next_id(length: usize) -> Result<u32, String> {
    u32::try_from(length)
        .ok()
        .filter(|&id| id < SYMBOL_BIT)
        .ok_or_else(|| "symbol ID space exhausted".into())
}

impl Symbols {
    fn intern(&mut self, text: String) -> Result<u32, String> {
        if let Some(&id) = self.ids.get(text.as_str()) {
            return Ok(id);
        }
        let id = next_id(self.names.len())?;
        let characters = text.chars().map(u32::from).collect();
        let spelling: Arc<str> = text.into();
        self.ids.insert(spelling.clone(), id);
        self.names.push(Name {
            spelling,
            characters,
        });
        Ok(id)
    }

    fn literal(&mut self, expected: u32, text: String) -> Result<(), String> {
        if self.intern(text)? != expected {
            return Err("duplicate name in literal symbol table".into());
        }
        Ok(())
    }

    fn name(&self, id: u32) -> Result<&Name, String> {
        self.names
            .get(id as usize)
            .ok_or_else(|| "invalid symbol ID".into())
    }

    fn from_module() -> Result<Self, String> {
        let literals = Root::literal_symbol_names();
        if literals.kind() != Kind::Vector {
            return Err("literal symbol names must be a vector".into());
        }
        let mut symbols = Self::default();
        for index in 0..literals.len()? {
            let name = literals.at(index)?;
            if name.kind() != Kind::String {
                return Err("literal symbol name must be a string".into());
            }
            symbols.literal(next_id(index)?, name.text()?)?;
        }
        Ok(symbols)
    }
}

// One table per native process or linked Wasm instance, never per OS thread.
// Initialization reads only strings from the private literal vector: these
// AWI operations cannot reenter symbol services. Copy before taking even the
// OnceLock initialization gate, then publish only the complete, root-free table.
// The current executable links one Scheme module; separately loaded modules
// would need to register and relocate their literal IDs instead.
static SYMBOLS: OnceLock<Mutex<Symbols>> = OnceLock::new();

fn symbols() -> Result<MutexGuard<'static, Symbols>, String> {
    let table = match SYMBOLS.get() {
        Some(table) => table,
        None => {
            let candidate = Symbols::from_module()?;
            SYMBOLS.get_or_init(|| Mutex::new(candidate))
        }
    };
    table
        .lock()
        .map_err(|_| "symbol table lock poisoned".into())
}

pub(crate) fn spelling(id: u32) -> Result<Arc<str>, String> {
    Ok(symbols()?.name(id)?.spelling.clone())
}

// ---- Scheme and AWI boundaries ----

fn intern_string(value: Root) -> Result<Root, String> {
    if value.kind() != Kind::String {
        return Err("string->symbol: expected a string".into());
    }
    let text = value.text()?;
    let id = symbols()?.intern(text)?;
    // Release the table lock before allocating a Scheme object or AWI root.
    Ok(Root::symbol(id))
}

#[unsafe(export_name = "snail:string->symbol")]
pub extern "C" fn string_to_symbol(raw: u32) -> u32 {
    finish(
        arguments(raw, "string->symbol", 1, 1)
            .get(0)
            .and_then(intern_string),
    )
}

#[unsafe(export_name = "snail:symbol->string")]
pub extern "C" fn symbol_to_string(raw: u32) -> u32 {
    finish(
        arguments(raw, "symbol->string", 1, 1)
            .get(0)
            .and_then(|value| {
                let name = spelling(value.symbol_id()?)?;
                Ok(Root::string(&name))
            }),
    )
}

#[unsafe(export_name = "snail:symbol-length")]
pub extern "C" fn symbol_length(id: u32) -> u32 {
    symbols()
        .and_then(|symbols| symbols.name(id).map(|name| name.characters.len() as u32))
        .unwrap_or_else(|error| fail_message(&error))
}

#[unsafe(export_name = "snail:symbol-character")]
pub extern "C" fn symbol_character(id: u32, index: u32) -> u32 {
    symbols()
        .and_then(|symbols| {
            symbols
                .name(id)?
                .characters
                .get(index as usize)
                .copied()
                .ok_or_else(|| "symbol character index out of range".into())
        })
        .unwrap_or_else(|error| fail_message(&error))
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn literal_and_dynamic_names_share_ids() {
        let mut symbols = Symbols::default();
        symbols.literal(0, "quoted".into()).unwrap();
        symbols.literal(1, "λ😀".into()).unwrap();
        assert_eq!(symbols.intern("quoted".into()).unwrap(), 0);
        assert_eq!(symbols.intern("λ😀".into()).unwrap(), 1);
        assert_eq!(symbols.intern("dynamic".into()).unwrap(), 2);
        assert_eq!(
            symbols.name(1).unwrap().characters,
            ['λ' as u32, '😀' as u32]
        );
        assert_eq!(&*symbols.name(1).unwrap().spelling, "λ😀");
        assert!(symbols.literal(3, "quoted".into()).is_err());
    }

    #[test]
    fn empty_names_and_growth_preserve_identity() {
        let mut symbols = Symbols::default();
        assert_eq!(symbols.intern(String::new()).unwrap(), 0);
        for index in 1..10000 {
            assert_eq!(symbols.intern(format!("name-{index}")).unwrap(), index);
        }
        for index in (1..10000).rev() {
            assert_eq!(symbols.intern(format!("name-{index}")).unwrap(), index);
        }
        assert_eq!(symbols.intern(String::new()).unwrap(), 0);
        assert!(symbols.name(10000).is_err());
    }

    #[test]
    fn identifiers_fit_the_tag_payload() {
        assert_eq!(next_id((SYMBOL_BIT - 1) as usize).unwrap(), SYMBOL_BIT - 1);
        assert!(next_id(SYMBOL_BIT as usize).is_err());
        assert!(next_id(usize::MAX).is_err());
    }

    #[test]
    fn threads_share_the_literal_prefix_and_dynamic_identities() {
        let mut initial = Symbols::default();
        initial.literal(0, "literal".into()).unwrap();
        let table = Arc::new(Mutex::new(initial));
        let threads: Vec<_> = (0..4)
            .map(|_| {
                let table = table.clone();
                std::thread::spawn(move || {
                    (0..1000)
                        .map(|index| {
                            table
                                .lock()
                                .unwrap()
                                .intern(format!("name-{index}"))
                                .unwrap()
                        })
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        let ids: Vec<_> = threads
            .into_iter()
            .map(|thread| thread.join().unwrap())
            .collect();
        assert!(ids.iter().all(|values| values == &ids[0]));
        let mut table = table.lock().unwrap();
        assert_eq!(table.intern("literal".into()).unwrap(), 0);
        assert_eq!(table.names.len(), 1001);
    }
}
