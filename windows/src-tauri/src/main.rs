#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]
use glide_core::{
    destination, directory, load_settings, read_frame, save_settings, valid_profile, write_frame,
    Settings, ORIGIN,
};
use interprocess::local_socket::{prelude::*, GenericNamespaced, ListenerOptions, Stream};
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::{mpsc, Arc, Mutex},
    thread,
    time::{Duration, Instant},
};
use tauri::{Emitter, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, ShortcutState};
use uuid::Uuid;
#[derive(Clone)]
struct Client {
    stream: Arc<Stream>,
    generation: String,
    profile: String,
    write: Arc<Mutex<()>>,
}
impl Client {
    fn send(&self, value: &Value) -> Result<(), String> {
        let _guard = self.write.lock().unwrap();
        write_frame(&mut &*self.stream, value).map_err(|e| e.to_string())
    }
}
struct Bridge {
    settings: Mutex<Settings>,
    client: Mutex<Option<Client>>,
    candidate: Mutex<Option<Client>>,
    pending: Mutex<HashMap<String, (String, mpsc::Sender<Value>)>>,
    error: Mutex<Option<String>>,
}
impl Bridge {
    fn status(&self) -> Value {
        json!({"settings":*self.settings.lock().unwrap(), "connected":self.client.lock().unwrap().is_some(), "pairPending":self.candidate.lock().unwrap().is_some(), "error":*self.error.lock().unwrap()})
    }
    fn request(&self, mut value: Value) -> Result<Value, String> {
        let client = self
            .client
            .lock()
            .unwrap()
            .clone()
            .ok_or("Chrome companion is disconnected. Open your paired Chrome profile.")?;
        let id = Uuid::new_v4().to_string();
        value["id"] = json!(id);
        let (tx, rx) = mpsc::channel();
        self.pending
            .lock()
            .unwrap()
            .insert(id.clone(), (client.generation.clone(), tx));
        let result = client.send(&value).and_then(|_| {
            rx.recv_timeout(Duration::from_secs(5))
                .map_err(|_| "Chrome did not respond. Check the companion connection.".into())
        });
        self.pending.lock().unwrap().remove(&id);
        result
    }
}
fn show(app: &tauri::AppHandle, settings: bool) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_size(tauri::LogicalSize::new(
            600.,
            if settings { 530. } else { 164. },
        ));
        let _ = w.center();
        let _ = w.show();
        let _ = w.set_focus();
        let _ = w.emit("show", json!({"settings":settings}));
    }
}
fn start_bridge(app: tauri::AppHandle, bridge: Arc<Bridge>) -> Result<(), String> {
    let name = format!("glide-{}", Uuid::new_v4());
    let token = Uuid::new_v4().to_string();
    let listener = ListenerOptions::new()
        .name(
            name.clone()
                .to_ns_name::<GenericNamespaced>()
                .map_err(|e| e.to_string())?,
        )
        .create_sync()
        .map_err(|e| e.to_string())?;
    std::fs::create_dir_all(directory()).map_err(|e| e.to_string())?;
    std::fs::write(
        directory().join("session.json"),
        json!({"name":name,"token":token}).to_string(),
    )
    .map_err(|e| e.to_string())?;
    thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            let app = app.clone();
            let bridge = bridge.clone();
            let token = token.clone();
            thread::spawn(move || {
                let stream = Arc::new(stream);
                let Ok(auth) = read_frame(&mut &*stream) else {
                    return;
                };
                if auth["token"].as_str() != Some(&token) {
                    return;
                }
                let generation = Uuid::new_v4().to_string();
                while let Ok(v) = read_frame(&mut &*stream) {
                    if matches!(v["type"].as_str(), Some("hello" | "pair")) {
                        let Some(profile) = v["profileID"]
                            .as_str()
                            .filter(|s| Uuid::parse_str(s).is_ok())
                        else {
                            continue;
                        };
                        let c = Client {
                            stream: stream.clone(),
                            generation: generation.clone(),
                            profile: profile.into(),
                            write: Arc::new(Mutex::new(())),
                        };
                        if v["type"] == "pair" {
                            *bridge.candidate.lock().unwrap() = Some(c.clone());
                            show(&app, true);
                        }
                        if bridge.settings.lock().unwrap().paired.as_deref() == Some(profile) {
                            *bridge.client.lock().unwrap() = Some(c);
                        }
                        let _ = app.emit("status", bridge.status());
                    } else if let Some(id) = v["id"].as_str() {
                        let pending = bridge.pending.lock().unwrap();
                        if let Some((g, tx)) = pending.get(id) {
                            if *g == generation {
                                let _ = tx.send(v.clone());
                            }
                        }
                    }
                }
                let mut c = bridge.client.lock().unwrap();
                if c.as_ref().is_some_and(|c| c.generation == generation) {
                    *c = None;
                }
                drop(c);
                let mut c = bridge.candidate.lock().unwrap();
                if c.as_ref().is_some_and(|c| c.generation == generation) {
                    *c = None;
                }
                drop(c);
                let _ = app.emit("status", bridge.status());
            });
        }
    });
    Ok(())
}
#[cfg(windows)]
fn register_host() -> Result<(), String> {
    use winreg::{enums::HKEY_CURRENT_USER, RegKey};
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let helper = exe
        .parent()
        .ok_or("Missing install directory")?
        .join("glide-native-host.exe");
    if !helper.is_file() {
        return Err(
            "Keep glide-native-host.exe beside Glide.exe. Reinstall the complete package.".into(),
        );
    }
    let path = directory().join("native-host.json");
    std::fs::create_dir_all(directory()).map_err(|e| e.to_string())?;
    std::fs::write(&path,json!({"name":"com.himanshu.glide","description":"Glide local Chrome bridge","path":helper,"type":"stdio","allowed_origins":[ORIGIN]}).to_string()).map_err(|e|e.to_string())?;
    let (key, _) = RegKey::predef(HKEY_CURRENT_USER)
        .create_subkey("Software\\Google\\Chrome\\NativeMessagingHosts\\com.himanshu.glide")
        .map_err(|e| e.to_string())?;
    key.set_value("", &path.to_string_lossy().to_string())
        .map_err(|e| e.to_string())
}
#[cfg(not(windows))]
fn register_host() -> Result<(), String> {
    let _ = ORIGIN;
    Ok(())
}
#[tauri::command]
fn status(state: tauri::State<Arc<Bridge>>) -> Value {
    state.status()
}
#[tauri::command]
fn preferences(
    state: tauri::State<Arc<Bridge>>,
    theme: String,
    google: bool,
    history: bool,
    profile: String,
) -> Result<Value, String> {
    if !["Purple", "Blue", "Black", "Graphite", "Midnight", "Rose"].contains(&theme.as_str())
        || !valid_profile(&profile)
    {
        return Err(
            "Choose a valid theme and Chrome folder: Default or Profile 2, for example.".into(),
        );
    }
    let mut s = state.settings.lock().unwrap();
    let mut next = s.clone();
    next.theme = theme;
    next.google = google;
    next.history = history;
    next.profile = profile;
    save_settings(&next).map_err(|e| e.to_string())?;
    *s = next;
    drop(s);
    Ok(state.status())
}
#[tauri::command]
fn approve_pair(state: tauri::State<Arc<Bridge>>) -> Result<Value, String> {
    let c = state
        .candidate
        .lock()
        .unwrap()
        .clone()
        .ok_or("Click Glide Companion in your chosen Chrome profile first.")?;
    let mut s = state.settings.lock().unwrap();
    let mut next = s.clone();
    next.paired = Some(c.profile.clone());
    save_settings(&next).map_err(|e| e.to_string())?;
    *s = next;
    drop(s);
    *state.client.lock().unwrap() = Some(c);
    *state.candidate.lock().unwrap() = None;
    Ok(state.status())
}
#[tauri::command]
fn unpair(state: tauri::State<Arc<Bridge>>) -> Result<Value, String> {
    let mut s = state.settings.lock().unwrap();
    let mut next = s.clone();
    next.paired = None;
    save_settings(&next).map_err(|e| e.to_string())?;
    *s = next;
    drop(s);
    *state.client.lock().unwrap() = None;
    *state.candidate.lock().unwrap() = None;
    Ok(state.status())
}
#[tauri::command]
async fn suggest(state: tauri::State<'_, Arc<Bridge>>, query: String) -> Result<Value, String> {
    if query.len() > 2000 {
        return Err("Query too long".into());
    }
    let bridge = state.inner().clone();
    let s = bridge.settings.lock().unwrap().clone();
    if query.trim().is_empty() || (!s.google && !s.history) {
        return Ok(json!({"rows":[]}));
    }
    tauri::async_runtime::spawn_blocking(move || {
        bridge
            .request(json!({"type":"suggest","query":query,"google":s.google,"history":s.history}))
    })
    .await
    .map_err(|e| e.to_string())?
}
fn launch_chrome(profile: &str) -> Result<(), String> {
    if !valid_profile(profile) {
        return Err("Invalid Chrome profile directory".into());
    }
    for base in ["PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"] {
        if let Some(path) = std::env::var_os(base) {
            let exe = std::path::PathBuf::from(path).join("Google/Chrome/Application/chrome.exe");
            if exe.is_file() {
                std::process::Command::new(exe)
                    .arg(format!("--profile-directory={profile}"))
                    .spawn()
                    .map_err(|e| e.to_string())?;
                return Ok(());
            }
        }
    }
    Err("Google Chrome was not found. Install Chrome or open your paired profile manually.".into())
}
#[tauri::command]
async fn open_query(state: tauri::State<'_, Arc<Bridge>>, input: String) -> Result<(), String> {
    if input.len() > 8000 {
        return Err("Query too long".into());
    }
    let url = destination(&input).ok_or("Type a search or URL first")?;
    let bridge = state.inner().clone();
    tauri::async_runtime::spawn_blocking(move || {
        let s = bridge.settings.lock().unwrap().clone();
        if s.paired.is_none() {
            return Err("Connect a Chrome profile in Settings first.".into());
        }
        if bridge.client.lock().unwrap().is_none() {
            launch_chrome(&s.profile)?;
            let end = Instant::now() + Duration::from_secs(10);
            while bridge.client.lock().unwrap().is_none() && Instant::now() < end {
                thread::sleep(Duration::from_millis(100));
            }
        }
        let response = bridge.request(json!({"type":"open","url":url}))?;
        if response["ok"] == true {
            Ok(())
        } else {
            Err("Chrome could not open this tab. Check your paired profile.".into())
        }
    })
    .await
    .map_err(|e| e.to_string())?
}
#[tauri::command]
fn panel_height(app: tauri::AppHandle, height: f64) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.set_size(tauri::LogicalSize::new(600., height.clamp(164., 640.)));
    }
}
#[tauri::command]
fn hide(app: tauri::AppHandle) {
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.hide();
    }
}
#[tauri::command]
fn companion_folder() -> Result<(), String> {
    let path = std::env::current_exe()
        .map_err(|e| e.to_string())?
        .parent()
        .ok_or("Missing install directory")?
        .join("Companion");
    #[cfg(windows)]
    {
        std::process::Command::new("explorer.exe")
            .arg(path)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(not(windows))]
    {
        let _ = path;
    }
    Ok(())
}
fn main() {
    let bridge = Arc::new(Bridge {
        settings: Mutex::new(load_settings()),
        client: Mutex::new(None),
        candidate: Mutex::new(None),
        pending: Mutex::new(HashMap::new()),
        error: Mutex::new(None),
    });
    let b = bridge.clone();
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, _, _| {
            show(app, false)
        }))
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .manage(bridge)
        .setup(move |app| {
            if let Err(e) =
                register_host().and_then(|_| start_bridge(app.handle().clone(), b.clone()))
            {
                *b.error.lock().unwrap() = Some(e);
            }
            if let Err(e) = app
                .global_shortcut()
                .on_shortcut("Shift+Space", |app, _, event| {
                    if event.state == ShortcutState::Pressed {
                        if app
                            .get_webview_window("main")
                            .is_some_and(|w| w.is_visible().unwrap_or(false))
                        {
                            let _ = app.get_webview_window("main").unwrap().hide();
                        } else {
                            show(app, false);
                        }
                    }
                })
            {
                *b.error.lock().unwrap() = Some(format!(
                    "Shift+Space is unavailable: {e}. Use the tray icon."
                ));
            }
            let search =
                tauri::menu::MenuItem::with_id(app, "search", "Search", true, None::<&str>)?;
            let settings =
                tauri::menu::MenuItem::with_id(app, "settings", "Settings", true, None::<&str>)?;
            let quit =
                tauri::menu::MenuItem::with_id(app, "quit", "Quit Glide", true, None::<&str>)?;
            let menu = tauri::menu::Menu::with_items(app, &[&search, &settings, &quit])?;
            let mut rgba = vec![0u8; 32 * 32 * 4];
            for y in 0..32 {
                for x in 0..32 {
                    let r = ((x as f32 - 15.5).powi(2) + (y as f32 - 15.5).powi(2)).sqrt();
                    if (8.0..13.0).contains(&r) {
                        let i = (y * 32 + x) * 4;
                        rgba[i..i + 4].copy_from_slice(&[188, 164, 255, 255]);
                    }
                }
            }
            tauri::tray::TrayIconBuilder::new()
                .icon(tauri::image::Image::new_owned(rgba, 32, 32))
                .menu(&menu)
                .tooltip("Glide · Shift+Space")
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "search" => show(app, false),
                    "settings" => show(app, true),
                    "quit" => app.exit(0),
                    _ => {}
                })
                .build(app)?;
            let window = app.get_webview_window("main").unwrap();
            if b.settings.lock().unwrap().paired.is_some() {
                let _ = window.hide();
            } else {
                let _ = window.set_size(tauri::LogicalSize::new(600., 530.));
            }
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            status,
            preferences,
            approve_pair,
            unpair,
            suggest,
            open_query,
            panel_height,
            hide,
            companion_folder
        ])
        .run(tauri::generate_context!())
        .expect("Unable to start Glide");
}
