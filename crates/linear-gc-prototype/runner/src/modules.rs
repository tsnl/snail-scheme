//! Workloads are written as Wasm instructions so spills remain inspectable.
//! @P@ is the address type, @W@ its width; numeric work stays i32 in both ABIs.

pub fn workload(bits: u32) -> String {
    let mut text = include_str!("../../../../tests/linear-gc/workload.wat").to_owned();
    for roots in [1, 4, 16] {
        for mode in ["locals", "shadow", "stack"] {
            text.push_str(&calls(roots, mode, (bits / 8) as usize));
        }
    }
    if bits == 64 {
        text.push_str(
            r#"(func (export "test_high_candidate") (result i32) (local $p i64)
          (local.set $p (call $object))
          (call $push (i64.add (local.get $p) (i64.const 4294967296)))
          (call $gc) (i32.eqz (call $contains (local.get $p))))"#,
        );
    }
    text.push(')');
    text.replace("@P@", if bits == 32 { "i32" } else { "i64" })
        .replace("@W@", &(bits / 8).to_string())
        .replace("@MEM@", if bits == 32 { "" } else { "i64" })
        .replace("@ROOT_BYTES@", &(8192 * bits / 8).to_string())
        .replace("@ROOT_OVERFLOW@", &(8192 * bits / 8 + 8).to_string())
}

fn calls(roots: usize, mode: &str, word: usize) -> String {
    let name = format!("{mode}_{roots}");
    let mut body = String::new();
    let mut parameters = String::new();
    let mut arguments = String::new();
    for index in 0..roots {
        parameters += &format!("(param $p{index} @P@) ");
        arguments += &format!("(local.get $p{index}) ");
    }
    // Three versions have the same loads, calls, arithmetic and checksum.
    // Only frame operations differ. 'locals' is a no-collection lower bound.
    body += &format!(
        "(func ${name} {parameters} (param $x i32) (param $work i32) (result i32) (local $frame @P@) (local $i i32)\n"
    );
    if mode != "locals" {
        body += "(local.set $frame (global.get $sp))\n";
        for index in 0..roots {
            body += &format!(
                "(@P@.store offset={} (local.get $frame) (local.get $p{index}))\n",
                index * word
            );
        }
        // Root slots have the target pointer width. The extra eight bytes
        // hold the scalar accumulator in the memory-backed frame arm.
        body += &format!(
            "(global.set $sp (@P@.add (local.get $frame) (@P@.const {})))\n",
            roots * word + 8
        );
        if mode == "stack" {
            body += &format!(
                "(i32.store offset={} (local.get $frame) (local.get $x))\n",
                roots * word
            );
        }
    }
    body += "(call $safepoint)\n";
    for index in 0..roots {
        let address = if mode == "stack" {
            format!("(@P@.load offset={} (local.get $frame))", index * word)
        } else {
            format!("(local.get $p{index})")
        };
        body += &format!("(local.set $x (i32.xor (local.get $x) (i32.load {address})))\n");
    }
    if mode == "stack" {
        body += &format!(
            "(i32.store offset={} (local.get $frame) (local.get $x))\n",
            roots * word
        );
    }
    body += "(loop $mix\n";
    let old = if mode == "stack" {
        format!("(i32.load offset={} (local.get $frame))", roots * word)
    } else {
        "(local.get $x)".into()
    };
    body += &format!(
        "(local.set $x (i32.add (i32.mul {old} (i32.const 1664525)) (i32.const 1013904223)))\n"
    );
    if mode == "stack" {
        body += &format!(
            "(i32.store offset={} (local.get $frame) (local.get $x))\n",
            roots * word
        );
    }
    body += "(local.set $i (i32.add (local.get $i) (i32.const 1))) (br_if $mix (i32.lt_u (local.get $i) (local.get $work))))\n";
    if mode != "locals" {
        body += "(global.set $sp (local.get $frame))\n";
    }
    body += "(local.get $x))\n";
    body += &format!(
        "(func (export \"{name}\") (param $n i32) (param $work i32) (result i32) (local $x i32)\n"
    );
    for index in 0..roots {
        body += &format!("(local $p{index} @P@)\n");
    }
    for index in 0..roots {
        body += &format!("(local.set $p{index} (call $alloc (@P@.const 32) (global.get $sp)))\n");
        body += &format!(
            "(i32.store (local.get $p{index}) (i32.const {}))\n",
            index * 37 + 11
        );
        body += &format!(
            "(i32.store offset=16 (local.get $p{index}) (i32.const {}))\n",
            index * 37 + 19
        );
        // Harness roots keep the baseline valid if the safepoint is enabled.
        // They are identical in all modes and outside the measured inner loop.
        body += &format!("(call $push (local.get $p{index}))\n");
    }
    body += "(loop $again\n";
    // Alternate base/interior addresses: constant arguments would let the
    // engine coalesce repeated publication. Each allocation is 32-byte aligned.
    for index in 0..roots {
        body += &format!("(local.set $p{index} (@P@.xor (local.get $p{index}) (@P@.const 16)))\n");
    }
    body +=
        &format!("(local.set $x (call ${name} {arguments} (local.get $x) (local.get $work)))\n");
    body +=
        "(local.set $n (i32.sub (local.get $n) (i32.const 1))) (br_if $again (local.get $n)))\n";
    body += &format!(
        "(global.set $sp (@P@.sub (global.get $sp) (@P@.const {}))) (local.get $x))\n",
        roots * word
    );
    body
}

pub const HIGH_ADDRESS: &str = r#"(module
  (memory (export "memory") i64 1 65538)
  (func (export "probe") (result i32)
    (drop (memory.grow (i64.const 65537)))
    (i32.store (i64.const 4294967312) (i32.const 1234567))
    (i32.load (i64.const 4294967312))))"#;
