//! Random source for identifiers.
//!
//! With the `std` feature the operating system provides the randomness. A
//! `no_std` build has none: the firmware registers its hardware generator with
//! [`set_source`] at startup.

use core::sync::atomic::{AtomicPtr, Ordering};

static SOURCE: AtomicPtr<()> = AtomicPtr::new(core::ptr::null_mut());

/// Registers the function used to fill buffers with random bytes.
pub fn set_source(fill: fn(&mut [u8])) {
    SOURCE.store(fill as *mut (), Ordering::Release);
}

/// Fills `bytes` from the registered source, or from the OS with `std`.
///
/// # Panics
///
/// Without `std`, panics if no source was registered.
pub fn fill(bytes: &mut [u8]) {
    let source = SOURCE.load(Ordering::Acquire);
    if !source.is_null() {
        // SAFETY: only `set_source` stores into SOURCE, always a `fn(&mut [u8])`.
        let fill: fn(&mut [u8]) = unsafe { core::mem::transmute(source) };
        fill(bytes);
        return;
    }
    fill_default(bytes);
}

#[cfg(feature = "std")]
fn fill_default(bytes: &mut [u8]) {
    for chunk in bytes.chunks_mut(16) {
        let random = uuid::Uuid::new_v4();
        chunk.copy_from_slice(&random.as_bytes()[..chunk.len()]);
    }
}

#[cfg(not(feature = "std"))]
fn fill_default(_bytes: &mut [u8]) {
    panic!("robine_core::random::set_source must be called before generating identifiers");
}
