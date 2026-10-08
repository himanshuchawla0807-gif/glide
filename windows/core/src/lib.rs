use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    io::{self, Read, Write},
    path::PathBuf,
};
pub const ORIGIN: &str = "chrome-extension://ampmdcedpokcijoakniagpieaebfooio/";
pub const MAX_FRAME: usize = 64 * 1024;
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub theme: String,
    pub google: bool,
    pub history: bool,
    pub profile: String,
    pub paired: Option<String>,
}
impl Default for Settings {
    fn default() -> Self {
        Self {
            theme: "Purple".into(),
            google: false,
            history: false,
            profile: "Default".into(),
            paired: None,
        }
    }
}
pub fn directory() -> PathBuf {
    dirs::data_local_dir()
        .expect("No local application directory")
        .join("Glide")
}
pub fn load_settings() -> Settings {
    std::fs::read(directory().join("settings.json"))
        .ok()
        .and_then(|b| serde_json::from_slice(&b).ok())
        .unwrap_or_default()
}
pub fn save_settings(s: &Settings) -> io::Result<()> {
    std::fs::create_dir_all(directory())?;
    std::fs::write(
        directory().join("settings.json"),
        serde_json::to_vec_pretty(s)?,
    )
}
pub fn valid_profile(s: &str) -> bool {
    s == "Default"
        || s.strip_prefix("Profile ")
            .is_some_and(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
}
pub fn destination(input: &str) -> Option<String> {
    let s = input.trim();
    if s.is_empty() {
        return None;
    }
    if let Ok(url) = url::Url::parse(s) {
        if matches!(url.scheme(), "http" | "https")
            && url.host_str().is_some()
            && !s.chars().any(char::is_whitespace)
        {
            return Some(url.to_string());
        }
    }
    if !s.chars().any(char::is_whitespace)
        && !s.contains("://")
        && (s.split('/').next()?.contains('.') || s.starts_with("localhost"))
    {
        let candidate = format!(
            "{}://{s}",
            if s.starts_with("localhost") {
                "http"
            } else {
                "https"
            }
        );
        if let Ok(url) = url::Url::parse(&candidate) {
            if url.host_str().is_some() {
                return Some(url.to_string());
            }
        }
    }
    let mut url = url::Url::parse("https://www.google.com/search").ok()?;
    url.query_pairs_mut().append_pair("q", s);
    Some(url.to_string())
}
pub fn read_frame(reader: &mut impl Read) -> io::Result<Value> {
    let mut header = [0u8; 4];
    reader.read_exact(&mut header)?;
    let n = u32::from_le_bytes(header) as usize;
    if n == 0 || n > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Invalid frame size",
        ));
    }
    let mut data = vec![0; n];
    reader.read_exact(&mut data)?;
    serde_json::from_slice(&data).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))
}
pub fn write_frame(writer: &mut impl Write, value: &Value) -> io::Result<()> {
    let bytes = serde_json::to_vec(value)?;
    if bytes.is_empty() || bytes.len() > MAX_FRAME {
        return Err(io::Error::new(
            io::ErrorKind::InvalidData,
            "Frame too large",
        ));
    }
    writer.write_all(&(bytes.len() as u32).to_le_bytes())?;
    writer.write_all(&bytes)?;
    writer.flush()
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn query_escaping_and_schemes() {
        let u = destination("a & b + café").unwrap();
        let parsed = url::Url::parse(&u).unwrap();
        assert_eq!(parsed.query_pairs().next().unwrap().1, "a & b + café");
        assert!(destination("javascript:alert(1)")
            .unwrap()
            .starts_with("https://www.google.com/search"));
        assert_eq!(
            destination("example.com/a").unwrap(),
            "https://example.com/a"
        );
        assert!(destination(" ").is_none());
    }
    #[test]
    fn bounded_transport() {
        let v = serde_json::json!({"query":"你好 🌊"});
        let mut bytes = vec![];
        write_frame(&mut bytes, &v).unwrap();
        assert_eq!(read_frame(&mut bytes.as_slice()).unwrap(), v);
        assert!(read_frame(&mut [0u8; 4].as_slice()).is_err());
        assert!(read_frame(&mut 999999u32.to_le_bytes().as_slice()).is_err());
    }
    #[test]
    fn privacy_and_profiles() {
        let s = Settings::default();
        assert!(!s.google && !s.history && s.paired.is_none());
        assert!(valid_profile("Profile 12"));
        assert!(!valid_profile("Profile 2 --remote-debugging-port=9"));
        assert!(!valid_profile("../Default"));
    }
}
