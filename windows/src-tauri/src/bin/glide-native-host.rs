use glide_core::{directory, read_frame, write_frame, ORIGIN};
use interprocess::local_socket::{prelude::*, GenericNamespaced, Stream};
use serde_json::{json, Value};
use std::{
    io,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};
fn main() {
    if std::env::args().nth(1).as_deref() != Some(ORIGIN) {
        std::process::exit(1);
    }
    let writer: Arc<Mutex<Option<Arc<Stream>>>> = Arc::new(Mutex::new(None));
    let shared = writer.clone();
    thread::spawn(move || loop {
        let config: Value = match std::fs::read(directory().join("session.json"))
            .ok()
            .and_then(|b| serde_json::from_slice(&b).ok())
        {
            Some(v) => v,
            None => {
                thread::sleep(Duration::from_secs(1));
                continue;
            }
        };
        let Some(name) = config["name"].as_str() else {
            return;
        };
        let Ok(name) = name.to_ns_name::<GenericNamespaced>() else {
            return;
        };
        let Ok(stream) = Stream::connect(name) else {
            thread::sleep(Duration::from_secs(1));
            continue;
        };
        let stream = Arc::new(stream);
        if write_frame(&mut &*stream, &json!({"token":config["token"]})).is_err() {
            continue;
        }
        *shared.lock().unwrap() = Some(stream.clone());
        let mut stdout = io::stdout().lock();
        if write_frame(&mut stdout, &json!({"type":"handshake"})).is_err() {
            std::process::exit(0)
        }
        while let Ok(v) = read_frame(&mut &*stream) {
            if write_frame(&mut stdout, &v).is_err() {
                std::process::exit(0)
            }
        }
        *shared.lock().unwrap() = None;
        thread::sleep(Duration::from_secs(1));
    });
    while let Ok(v) = read_frame(&mut io::stdin().lock()) {
        if let Some(stream) = writer.lock().unwrap().as_ref() {
            let _ = write_frame(&mut &**stream, &v);
        }
    }
}
