//! Mobile web build embedded by `build.rs`, served gzipped.

pub struct Asset {
    pub path: &'static str,
    pub content_type: &'static str,
    pub gzip: &'static [u8],
}

include!(concat!(env!("OUT_DIR"), "/web_assets.rs"));

/// Asset for a request path. Unknown paths without an extension are client
/// routes of the single-page app (`/alarmes`, `/soir`…) and get `index.html`.
pub fn find(path: &str) -> Option<&'static Asset> {
    let path = if path == "/" { "/index.html" } else { path };
    ASSETS.iter().find(|asset| asset.path == path).or_else(|| {
        let last = path.rsplit('/').next().unwrap_or("");
        (!last.contains('.'))
            .then(|| ASSETS.iter().find(|asset| asset.path == "/index.html"))
            .flatten()
    })
}
