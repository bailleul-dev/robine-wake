//! Reboot with an argument for the kernel restart handler (OPS-001).
//!
//! `"0 tryboot"` makes the Raspberry Pi firmware boot the [tryboot] slot of
//! autoboot.txt once. BusyBox `reboot` cannot pass an argument, so inittab runs
//! this last during shutdown: when `/run/reboot-param` exists it restarts the
//! board itself, otherwise it returns and init reboots or powers off normally.

use std::ffi::CString;

const PARAM_FILE: &str = "/run/reboot-param";

fn main() {
    let param = match std::fs::read_to_string(PARAM_FILE) {
        Ok(text) if !text.trim().is_empty() => text.trim().to_owned(),
        _ => return,
    };
    let arg = CString::new(param).expect("reboot parameter without NUL bytes");

    // SAFETY: plain syscalls; `arg` outlives the call.
    unsafe {
        libc::sync();
        libc::syscall(
            libc::SYS_reboot,
            libc::LINUX_REBOOT_MAGIC1,
            libc::LINUX_REBOOT_MAGIC2,
            libc::LINUX_REBOOT_CMD_RESTART2,
            arg.as_ptr(),
        );
    }
    eprintln!("robine-reboot: {}", std::io::Error::last_os_error());
    std::process::exit(1);
}
