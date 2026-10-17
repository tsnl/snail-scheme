use std::io::Write;
use std::sync::atomic::{AtomicI32, Ordering};
static COUNTER: AtomicI32 = AtomicI32::new(0);
unsafe extern "C" {
    fn fork() -> i32;
    fn pause() -> i32;
    fn signal(signal: i32, handler: usize) -> usize;
    fn native_gc_collect();
    fn native_gc_collections() -> usize;
    #[link_name = "snail:io/path-begin"]
    fn pathname_start();
    #[link_name = "snail:io/path-character"]
    fn pathname_character(scalar: u32);
    #[link_name = "snail:io/open-output-file"]
    fn open_output() -> i32;
    #[link_name = "snail:io/write-character"]
    fn write_character(handle: i32, scalar: u32);
}

// ---- Provider state belongs to one isolated native instance ----

#[unsafe(export_name = "tick")]
pub extern "C" fn tick() -> i32 {
    COUNTER.fetch_add(1, Ordering::SeqCst) + 1
}
#[unsafe(export_name = "bad_bool")]
pub extern "C" fn bad_bool() -> i32 {
    7
}
#[unsafe(export_name = "bad_char")]
pub extern "C" fn bad_char() -> i32 {
    0xd800
}
#[unsafe(export_name = "hang")]
pub extern "C" fn hang() -> i32 {
    loop {
        unsafe { pause() };
    }
}
#[unsafe(export_name = "mark")]
pub extern "C" fn mark(value: i32) {
    unsafe { native_gc_collect() };
    assert!(unsafe { native_gc_collections() } > 0);
    let mut file = std::fs::OpenOptions::new()
        .append(true)
        .create(true)
        .open(std::env::var("SNAIL_TEST_EFFECTS").unwrap())
        .unwrap();
    writeln!(file, "{} {value}", std::process::id()).unwrap();
    println!("provider output is separate from scalar transport");
}
#[unsafe(export_name = "spawn_child")]
pub extern "C" fn spawn_child() {
    let child = unsafe { fork() };
    assert!(child >= 0);
    if child == 0 {
        unsafe {
            signal(15, 1);
        }
        loop {
            unsafe { pause() };
        }
    }
    std::fs::write(
        std::env::var("SNAIL_TEST_CHILD").unwrap(),
        format!("{child}\n"),
    )
    .unwrap();
}
extern "C" fn construct_provider() {
    if std::env::var_os("SNAIL_TEST_CONSTRUCTOR").is_some() {
        spawn_child();
    }
    if std::env::var_os("SNAIL_TEST_CONSTRUCTOR_HANG").is_some() {
        hang();
    }
}
#[used]
#[unsafe(link_section = ".init_array")]
static CONSTRUCTOR: extern "C" fn() = construct_provider;
#[unsafe(export_name = "open_resource")]
pub extern "C" fn open_resource() {
    unsafe {
        pathname_start();
        for byte in std::env::var("SNAIL_TEST_RESOURCE").unwrap().bytes() {
            pathname_character(u32::from(byte));
        }
        write_character(open_output(), u32::from(b'x'));
    }
}
