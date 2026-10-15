//! Native diagnostics and terminal resource cleanup. Scalar services retain
//! no managed references and never call guest code while borrowing a resource.

unsafe extern "C" {
    fn native_report_error(pointer: *const u8, length: usize) -> !;
    fn native_resource_released();
}

pub(crate) fn report_error(message: &str) -> ! {
    unsafe { native_report_error(message.as_ptr(), message.len()) }
}

pub(crate) fn resource_released() {
    unsafe { native_resource_released() };
}

#[unsafe(no_mangle)]
pub extern "C" fn snail_native_cleanup() -> i32 {
    // close_all takes the owned registry before releasing resources, so a
    // repeated terminal cleanup is empty. Borrowed standard streams stay open.
    crate::strict_io::close_all()
}
