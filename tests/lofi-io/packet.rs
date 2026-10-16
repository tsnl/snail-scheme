#[path = "../native-support.rs"]
mod support;
unsafe extern "C" {
    #[link_name = "wasm.main"]
    fn guest_main();
    #[link_name = "wasm.copy-characters"]
    fn copy_characters() -> i64;
    #[link_name = "wasm.copy-standard"]
    fn copy_standard() -> i64;
    #[link_name = "wasm.mixed-readers"]
    fn mixed_readers() -> i32;
    #[link_name = "wasm.cached-close"]
    fn cached_close();
    #[link_name = "wasm.open-growing"]
    fn open_growing();
    #[link_name = "wasm.peek-growing"]
    fn peek_growing() -> i64;
    #[link_name = "wasm.read-growing"]
    fn read_growing() -> i64;
    #[link_name = "wasm.close-growing"]
    fn close_growing();
}

use std::io::Write;

// ---- Cached EOF is distinct from newly appended file bytes ----

unsafe fn eof_growth() {
    unsafe {
        open_growing();
        for byte in b'A'..=b'B' {
            assert_eq!(peek_growing(), -1);
            std::fs::OpenOptions::new()
                .append(true)
                .open("input.txt")
                .unwrap()
                .write_all(&[byte])
                .unwrap();
            assert_eq!(peek_growing(), -1);
            assert_eq!(read_growing(), -1);
            assert_eq!(peek_growing(), i64::from(byte));
            assert_eq!(read_growing(), i64::from(byte));
        }
        close_growing();
    }
}

extern "C" fn observe_borrowed_input() {
    unsafe extern "C" {
        fn fcntl(descriptor: i32, command: i32, ...) -> i32;
    }
    assert!(unsafe { fcntl(0, 1) } >= 0);
}

fn main() {
    support::observe_releases();
    unsafe extern "C" {
        fn atexit(callback: extern "C" fn()) -> i32;
        fn dup2(source: i32, destination: i32) -> i32;
    }
    assert_eq!(unsafe { atexit(observe_borrowed_input) }, 0);
    if std::env::args().nth(1).as_deref() == Some("copy-standard") {
        use std::os::fd::AsRawFd;
        let input = std::fs::File::open("input.txt").unwrap();
        assert_eq!(unsafe { dup2(input.as_raw_fd(), 0) }, 0);
    }
    let arguments = support::initialize();
    assert_eq!(arguments.len(), 3);
    unsafe {
        guest_main();
        match arguments[1].as_str() {
            "copy-characters" => {
                assert_eq!(copy_characters(), arguments[2].parse::<i64>().unwrap())
            }
            "copy-standard" => assert_eq!(copy_standard(), arguments[2].parse::<i64>().unwrap()),
            "mixed-readers" => assert_ne!(mixed_readers(), 0),
            "cached-close" => cached_close(),
            "eof-growth" => eof_growth(),
            _ => panic!("unknown packet action"),
        }
    }
    support::finish(0);
}
