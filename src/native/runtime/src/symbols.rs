//! Stable symbol IDs for the scalar datum services. Rust owns the UTF-8 names
//! and indexed Unicode scalars; compiled Lofi carries a nonnegative I32 ID.

use std::collections::HashMap;

// ---- Names and stable identifiers ----

const ID_LIMIT: u32 = 1 << 31;

#[derive(Default)]
pub(crate) struct Symbols {
    ids: HashMap<String, u32>,
    names: Vec<Vec<u32>>,
}

fn next_id(length: usize) -> Result<u32, String> {
    u32::try_from(length)
        .ok()
        .filter(|&id| id < ID_LIMIT)
        .ok_or_else(|| "symbol ID space exhausted".into())
}

impl Symbols {
    pub(crate) fn intern(&mut self, text: String) -> Result<u32, String> {
        if let Some(&id) = self.ids.get(&text) {
            return Ok(id);
        }
        let id = next_id(self.names.len())?;
        let characters = text.chars().map(u32::from).collect();
        self.ids.insert(text, id);
        self.names.push(characters);
        Ok(id)
    }

    fn name(&self, id: u32) -> Result<&[u32], String> {
        self.names
            .get(id as usize)
            .map(Vec::as_slice)
            .ok_or_else(|| "invalid symbol ID".into())
    }

    pub(crate) fn length(&self, id: u32) -> Result<u32, String> {
        u32::try_from(self.name(id)?.len()).map_err(|_| "symbol is too long".into())
    }

    pub(crate) fn character(&self, id: u32, index: u32) -> Result<u32, String> {
        self.name(id)?
            .get(index as usize)
            .copied()
            .ok_or_else(|| "symbol character index out of range".into())
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[test]
    fn names_share_ids_and_unicode_scalar_indices() {
        let mut symbols = Symbols::default();
        assert_eq!(symbols.intern("quoted".into()).unwrap(), 0);
        assert_eq!(symbols.intern("λ😀".into()).unwrap(), 1);
        assert_eq!(symbols.intern("quoted".into()).unwrap(), 0);
        assert_eq!(symbols.intern("λ😀".into()).unwrap(), 1);
        assert_eq!(symbols.length(1).unwrap(), 2);
        assert_eq!(symbols.character(1, 0).unwrap(), 'λ' as u32);
        assert_eq!(symbols.character(1, 1).unwrap(), '😀' as u32);
        assert!(symbols.character(1, 2).is_err());
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
    fn identifiers_fit_the_signed_scalar_boundary() {
        assert_eq!(next_id((ID_LIMIT - 1) as usize).unwrap(), ID_LIMIT - 1);
        assert!(next_id(ID_LIMIT as usize).is_err());
        assert!(next_id(usize::MAX).is_err());
    }

    #[test]
    fn threads_share_symbol_identities() {
        let mut initial = Symbols::default();
        assert_eq!(initial.intern("literal".into()).unwrap(), 0);
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
