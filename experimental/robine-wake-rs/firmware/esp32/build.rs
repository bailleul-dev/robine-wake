fn main() {
    linker_be_nice();
    check_xtensa_linker_available();
    embed_wifi_credentials();
    embed_web_assets();
    // make sure linkall.x is the last linker script (otherwise might cause problems with flip-link)
    println!("cargo:rustc-link-arg=-Tlinkall.x");
}

/// Reads `wifi.ini` (ignored by git) and exposes `WIFI_SSID` / `WIFI_PASSWORD`
/// to the firmware through `env!`.
///
/// Accepted formats: `ssid=...` and `password=...` lines, or the bare SSID on
/// the first line and the password on the second. `#` only starts a comment
/// at the beginning of a line, since SSIDs may contain it.
fn embed_wifi_credentials() {
    println!("cargo:rerun-if-changed=wifi.ini");
    let content = std::fs::read_to_string("wifi.ini").unwrap_or_else(|_| {
        panic!("wifi.ini not found: create it with the SSID on line 1 and the password on line 2")
    });

    let lines: Vec<&str> = content
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#') && !line.starts_with('['))
        .collect();

    let keyed = |key: &str| {
        lines.iter().find_map(|line| {
            let (k, v) = line.split_once('=')?;
            k.trim().eq_ignore_ascii_case(key).then(|| v.trim().to_string())
        })
    };

    let (ssid, password) = match (keyed("ssid"), keyed("password")) {
        (Some(ssid), password) => (ssid, password.unwrap_or_default()),
        _ => (
            lines.first().map(|s| s.to_string()).unwrap_or_default(),
            lines.get(1).map(|s| s.to_string()).unwrap_or_default(),
        ),
    };

    assert!(!ssid.is_empty(), "wifi.ini: missing SSID");
    assert!(ssid.len() <= 32, "wifi.ini: SSID longer than 32 bytes");
    assert!(password.len() <= 64, "wifi.ini: password longer than 64 bytes");

    println!("cargo:rustc-env=WIFI_SSID={ssid}");
    println!("cargo:rustc-env=WIFI_PASSWORD={password}");
}

/// Gzips the mobile web build (`priv/web`, `make expo-web`) into the
/// firmware and generates the `ASSETS` table served by `web.rs`.
///
/// `ROBINE_WEB_DIR` overrides the source directory. Without it the firmware
/// still builds and only serves the API.
fn embed_web_assets() {
    use std::io::Write;
    use std::path::{Path, PathBuf};

    println!("cargo:rerun-if-env-changed=ROBINE_WEB_DIR");
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let root = std::env::var_os("ROBINE_WEB_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| manifest.join("../../../../priv/web"));
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap());

    fn walk(dir: &Path, files: &mut Vec<PathBuf>) {
        let Ok(entries) = std::fs::read_dir(dir) else { return };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, files);
            } else {
                files.push(path);
            }
        }
    }

    let mut files = Vec::new();
    walk(&root, &mut files);
    files.sort();
    if files.is_empty() {
        println!("cargo:warning=no web build in {}: only the API is served", root.display());
    }
    println!("cargo:rerun-if-changed={}", root.display());

    let mut table = String::from("pub static ASSETS: &[Asset] = &[\n");
    for (index, file) in files.iter().enumerate() {
        println!("cargo:rerun-if-changed={}", file.display());
        let relative = file.strip_prefix(&root).unwrap().to_string_lossy().replace('\\', "/");
        let content_type = match file.extension().and_then(|ext| ext.to_str()).unwrap_or("") {
            "html" => "text/html; charset=utf-8",
            "js" => "text/javascript; charset=utf-8",
            "css" => "text/css; charset=utf-8",
            "json" => "application/json",
            "ico" => "image/x-icon",
            "png" => "image/png",
            "svg" => "image/svg+xml",
            "ttf" => "font/ttf",
            "woff2" => "font/woff2",
            _ => "application/octet-stream",
        };
        let data = std::fs::read(file).unwrap();
        let mut encoder = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::best());
        encoder.write_all(&data).unwrap();
        let gzip = out.join(format!("web-{index}.gz"));
        std::fs::write(&gzip, encoder.finish().unwrap()).unwrap();
        table.push_str(&format!(
            "    Asset {{ path: \"/{relative}\", content_type: \"{content_type}\", gzip: include_bytes!({gzip:?}) }},\n"
        ));
    }
    table.push_str("];\n");
    std::fs::write(out.join("web_assets.rs"), table).unwrap();
}

#[cfg(unix)]
fn check_xtensa_linker_available() {
    println!("cargo:rerun-if-env-changed=PATH");

    let target = std::env::var("TARGET").unwrap_or_default();
    println!(
        "cargo:rerun-if-env-changed={}",
        cargo_linker_env_var(&target)
    );

    let linker = xtensa_linker(&target);

    let error = match std::process::Command::new(&linker)
        .arg("--version")
        .output()
    {
        Ok(_) => return,
        Err(error) => error,
    };

    let export_file = std::env::var("HOME")
        .map(|home| format!("{home}/export-esp.sh"))
        .unwrap_or_else(|_| "$HOME/export-esp.sh".to_string());

    panic!(
        "Xtensa linker `{linker}` was not found in PATH or could not be executed: {error}.\n\n\
         Xtensa targets on Unix require espup's environment export file to be sourced before building.\n\
         Try: `source {export_file}`\n\n\
         If the export file does not exist, run `espup install` first.\n\
         For more details, see:\n\
         https://github.com/esp-rs/espup?tab=readme-ov-file#environment-variables-setup"
    );
}

#[cfg(not(unix))]
fn check_xtensa_linker_available() {}

#[cfg(unix)]
fn xtensa_linker(target: &str) -> String {
    if let Some(linker) = cargo_configured_linker(target) {
        return linker;
    }

    target
        .strip_prefix("xtensa-")
        .and_then(|target| target.strip_suffix("-none-elf"))
        .map(|chip| format!("xtensa-{chip}-elf-gcc"))
        .unwrap_or_else(|| "xtensa-esp32-elf-gcc".to_string())
}

#[cfg(unix)]
fn cargo_configured_linker(target: &str) -> Option<String> {
    std::env::var(cargo_linker_env_var(target)).ok()
}

#[cfg(unix)]
fn cargo_linker_env_var(target: &str) -> String {
    let target = target.replace('-', "_").to_ascii_uppercase();
    format!("CARGO_TARGET_{target}_LINKER")
}

fn linker_be_nice() {
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 {
        let kind = &args[1];
        let what = &args[2];

        match kind.as_str() {
            "undefined-symbol" => match what.as_str() {
                what if what.starts_with("_defmt_") => {
                    eprintln!();
                    eprintln!(
                        "💡 `defmt` not found - make sure `defmt.x` is added as a linker script and you have included `use defmt_rtt as _;`"
                    );
                    eprintln!();
                }
                "_stack_start" => {
                    eprintln!();
                    eprintln!("💡 Is the linker script `linkall.x` missing?");
                    eprintln!();
                }
                what if what.starts_with("esp_rtos_") => {
                    eprintln!();
                    eprintln!(
                        "💡 `esp-radio` has no scheduler enabled. Make sure you have initialized `esp-rtos` or provided an external scheduler."
                    );
                    eprintln!();
                }
                "embedded_test_linker_file_not_added_to_rustflags" => {
                    eprintln!();
                    eprintln!(
                        "💡 `embedded-test` not found - make sure `embedded-test.x` is added as a linker script for tests"
                    );
                    eprintln!();
                }
                "free"
                | "malloc"
                | "calloc"
                | "get_free_internal_heap_size"
                | "malloc_internal"
                | "realloc_internal"
                | "calloc_internal"
                | "free_internal" => {
                    eprintln!();
                    eprintln!(
                        "💡 Did you forget the `esp-alloc` dependency or didn't enable the `compat` feature on it?"
                    );
                    eprintln!();
                }
                _ => (),
            },
            // we don't have anything helpful for "missing-lib" yet
            _ => {
                std::process::exit(1);
            }
        }

        std::process::exit(0);
    }

    println!(
        "cargo:rustc-link-arg=-Wl,--error-handling-script={}",
        std::env::current_exe().unwrap().display()
    );
}
