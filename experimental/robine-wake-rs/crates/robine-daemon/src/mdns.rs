//! Local mDNS advertisement (PLT-003.1).
//!
//! Announces `robine-wake.local` on the local network with HTTP and SSH services
//! so the mobile app and ESP32 remote button can locate the alarm clock without
//! requiring external Avahi or D-Bus dependencies.

use mdns_sd::{ServiceDaemon, ServiceInfo};

pub struct MdnsResponder {
    _daemon: ServiceDaemon,
}

impl MdnsResponder {
    pub fn start(http_port: u16, ssh_port: u16) -> Result<Self, String> {
        let daemon = ServiceDaemon::new().map_err(|e| format!("cannot create mdns daemon: {e}"))?;

        let http_info = ServiceInfo::new(
            "_http._tcp.local.",
            "robine-wake",
            "robine-wake.local.",
            "",
            http_port,
            &[("path", "/")][..],
        )
        .map_err(|e| format!("invalid http mdns service: {e}"))?;

        daemon
            .register(http_info)
            .map_err(|e| format!("cannot register http mdns service: {e}"))?;

        if ssh_port > 0 {
            let empty_props: &[(&str, &str)] = &[];
            let ssh_info = ServiceInfo::new(
                "_ssh._tcp.local.",
                "robine-wake",
                "robine-wake.local.",
                "",
                ssh_port,
                empty_props,
            )
            .map_err(|e| format!("invalid ssh mdns service: {e}"))?;

            daemon
                .register(ssh_info)
                .map_err(|e| format!("cannot register ssh mdns service: {e}"))?;
        }

        eprintln!("  mdns   announcing robine-wake.local (http: {http_port}, ssh: {ssh_port})");
        Ok(Self { _daemon: daemon })
    }
}
