//! "Abrir com…": lista os aplicativos registrados para o tipo do arquivo (`mimeinfo.cache` + `.desktop`)
//! e abre o arquivo com um deles via `gio launch` (sem shell, sem interpretar `Exec` por conta própria).

use std::collections::HashSet;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use serde_json::json;

use super::file_ops::{invalid, require_absolute};

const MAX_APPS: usize = 40;
const MAX_ALL_APPS: usize = 2000;

#[derive(Debug, Clone, PartialEq)]
pub struct App {
    pub id: String,
    pub name: String,
    pub icon: String,
}

/// Id de `.desktop`: nome simples terminado em `.desktop`, sem `/`, sem começar com `-` (evita virar opção)
pub fn validate_desktop_id(id: &str) -> std::io::Result<()> {
    let ok = id.len() > ".desktop".len()
        && id.len() <= 255
        && id.ends_with(".desktop")
        && !id.starts_with(['-', '.'])
        && id.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b'-' | b'+'));
    if ok { Ok(()) } else { Err(invalid("Aplicativo inválido")) }
}

fn data_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    match std::env::var_os("XDG_DATA_HOME").filter(|v| !v.is_empty()) {
        Some(h) => dirs.push(PathBuf::from(h)),
        None => {
            if let Some(h) = dirs::home_dir() {
                dirs.push(h.join(".local/share"));
            }
        }
    }
    let sys = std::env::var("XDG_DATA_DIRS").ok().filter(|v| !v.is_empty()).unwrap_or_else(|| "/usr/local/share:/usr/share".into());
    dirs.extend(sys.split(':').filter(|p| p.starts_with('/')).map(PathBuf::from));
    dirs
}

/// Tipo MIME do alvo: pasta, conteúdo (`xdg-mime`) e, por último, a extensão
fn mime_of(path: &Path) -> String {
    if std::fs::metadata(path).map(|m| m.is_dir()).unwrap_or(false) {
        return "inode/directory".into();
    }
    let out = Command::new("xdg-mime").args(["query", "filetype"]).arg(path).stdin(Stdio::null()).stderr(Stdio::null()).output();
    if let Ok(o) = out {
        let m = String::from_utf8_lossy(&o.stdout).trim().to_string();
        if o.status.success() && m.contains('/') && m.len() < 128 {
            return m;
        }
    }
    mime_guess::from_path(path).first_or_octet_stream().essence_str().to_string()
}

/// Tipos que contam para o alvo: o próprio e, para texto, `text/plain` (editores só se registram nele)
fn mime_candidates(mime: &str) -> Vec<String> {
    let mut v = vec![mime.to_string()];
    if mime.starts_with("text/") || mime.ends_with("+xml") || mime.ends_with("json") || mime.ends_with("javascript") {
        v.push("text/plain".into());
    }
    v
}

/// Ids associados a `mime` numa tabela `mimeinfo.cache` (`tipo=a.desktop;b.desktop;`)
pub fn parse_mimeinfo(text: &str, mimes: &[String]) -> Vec<String> {
    let mut out = Vec::new();
    for line in text.lines() {
        let Some((m, ids)) = line.split_once('=') else { continue };
        if mimes.iter().any(|x| x == m) {
            out.extend(ids.split(';').filter(|i| !i.is_empty()).map(str::to_string));
        }
    }
    out
}

/// Campos úteis de um `.desktop`; `None` se escondido, que não é aplicativo ou sem `Exec`
pub fn parse_desktop(text: &str, lang: &str) -> Option<(String, String)> {
    let (mut in_entry, mut kind, mut name, mut local_name, mut icon) = (false, String::new(), None, None, String::new());
    let (mut hidden, mut has_exec) = (false, false);
    let local_key = format!("Name[{lang}]");
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('[') {
            in_entry = line == "[Desktop Entry]";
            continue;
        }
        if !in_entry {
            continue;
        }
        let Some((k, v)) = line.split_once('=') else { continue };
        match k.trim() {
            "Type" => kind = v.trim().to_string(),
            "Name" => name = Some(v.trim().to_string()),
            "Icon" => icon = v.trim().to_string(),
            "NoDisplay" | "Hidden" => hidden |= v.trim() == "true",
            "Exec" => has_exec = !v.trim().is_empty(),
            k if !lang.is_empty() && k == local_key => local_name = Some(v.trim().to_string()),
            _ => {}
        }
    }
    if hidden || !has_exec || kind != "Application" {
        return None;
    }
    let name = local_name.or(name).filter(|n| !n.is_empty())?;
    Some((name, icon))
}

/// Acha o `.desktop` de um id nos diretórios XDG (`a-b.desktop` também pode estar em `a/b.desktop`)
fn find_desktop(id: &str) -> Option<PathBuf> {
    for dir in data_dirs() {
        let apps = dir.join("applications");
        let mut name = id.to_string();
        loop {
            let p = apps.join(&name);
            if p.is_file() {
                return Some(p);
            }
            match name.find('-') {
                Some(i) => name.replace_range(i..=i, "/"),
                None => break,
            }
        }
    }
    None
}

fn default_app(mime: &str) -> Option<String> {
    let o = Command::new("xdg-mime").args(["query", "default", mime]).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
    let id = String::from_utf8_lossy(&o.stdout).trim().to_string();
    if validate_desktop_id(&id).is_ok() { Some(id) } else { None }
}

fn ui_lang() -> String {
    let l = std::env::var("LC_MESSAGES").or_else(|_| std::env::var("LANG")).unwrap_or_default();
    l.split(['.', '@']).next().unwrap_or("").to_string()
}

/// Aplicativos que abrem `path`, com o padrão do sistema primeiro
pub fn apps_for(path: &Path) -> std::io::Result<Vec<App>> {
    require_absolute(&path.to_string_lossy())?;
    if std::fs::symlink_metadata(path).is_err() {
        return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "O arquivo não existe mais"));
    }
    let mime = mime_of(path);
    let mimes = mime_candidates(&mime);
    let lang = ui_lang();
    let short = lang.split('_').next().unwrap_or("").to_string();

    let mut ids: Vec<String> = Vec::new();
    if let Some(d) = default_app(&mime) {
        ids.push(d);
    }
    for dir in data_dirs() {
        if let Ok(t) = std::fs::read_to_string(dir.join("applications/mimeinfo.cache")) {
            ids.extend(parse_mimeinfo(&t, &mimes));
        }
    }

    let mut seen = HashSet::new();
    let mut apps = Vec::new();
    for id in ids {
        if apps.len() >= MAX_APPS || validate_desktop_id(&id).is_err() || !seen.insert(id.clone()) {
            continue;
        }
        let Some(file) = find_desktop(&id) else { continue };
        let Ok(text) = std::fs::read_to_string(&file) else { continue };
        let parsed = parse_desktop(&text, &lang).or_else(|| if short.is_empty() { None } else { parse_desktop(&text, &short) });
        if let Some((name, icon)) = parsed {
            apps.push(App { id, name, icon });
        }
    }
    Ok(apps)
}

/// Todos os aplicativos instalados e visíveis (para "Outro aplicativo…"), em ordem alfabética
pub fn all_apps() -> Vec<App> {
    let lang = ui_lang();
    let short = lang.split('_').next().unwrap_or("").to_string();
    let mut seen = HashSet::new();
    let mut apps = Vec::new();
    for dir in data_dirs() {
        for entry in walkdir::WalkDir::new(dir.join("applications")).max_depth(3).into_iter().filter_map(Result::ok) {
            if !entry.file_type().is_file() || apps.len() >= MAX_ALL_APPS {
                continue;
            }
            let Ok(rel) = entry.path().strip_prefix(dir.join("applications")) else { continue };
            // `a/b.desktop` é o id `a-b.desktop`
            let id = rel.to_string_lossy().replace('/', "-");
            if validate_desktop_id(&id).is_err() || !seen.insert(id.clone()) {
                continue;
            }
            let Ok(text) = std::fs::read_to_string(entry.path()) else { continue };
            let parsed = parse_desktop(&text, &lang).or_else(|| if short.is_empty() { None } else { parse_desktop(&text, &short) });
            if let Some((name, icon)) = parsed {
                apps.push(App { id, name, icon });
            }
        }
    }
    apps.sort_by_key(|a| a.name.to_lowercase());
    apps
}

pub fn list_json(path: &str, all: bool) -> serde_json::Value {
    if !all {
        return list_json_with_defaults(path);
    }
    let result = require_absolute(path).map(|_| all_apps());
    match result {
        Ok(apps) => {
            let apps: Vec<_> = apps.into_iter().map(|a| json!({ "id": a.id, "name": a.name, "icon": a.icon })).collect();
            let ext = can_remember(Path::new(path));
            json!({ "ok": true, "apps": apps, "ext": ext, "can_remember": ext.is_some() })
        }
        Err(e) => json!({ "ok": false, "error": e.to_string(), "apps": [] }),
    }
}

/// Abre `path` com o aplicativo `id`: precisa ser um aplicativo instalado e visível (um `.desktop` dos
/// diretórios XDG), não necessariamente um dos registrados para o tipo do arquivo
pub fn open_with(id: &str, path: &str) -> std::io::Result<()> {
    validate_desktop_id(id)?;
    require_absolute(path)?;
    if std::fs::symlink_metadata(path).is_err() {
        return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "O arquivo não existe mais"));
    }
    let desktop = find_desktop(id).ok_or_else(|| invalid("Aplicativo não encontrado"))?;
    let installed = std::fs::read_to_string(&desktop).ok().and_then(|t| parse_desktop(&t, "")).is_some();
    if !installed {
        return Err(invalid("Aplicativo não encontrado"));
    }
    let status = Command::new("gio")
        .arg("launch")
        .arg(&desktop)
        .arg(path)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?
        .wait()?;
    if status.success() { Ok(()) } else { Err(invalid("Não foi possível abrir com este aplicativo")) }
}

// ---------------------------------------------------------------------------------------------
// Padrão do Kappa por extensão: `~/.config/kappa/open-defaults.json` (`{"by_extension":{"png":"x.desktop"}}`).
// Vale só dentro do Kappa (não toca em `mimeapps.list`). Nunca vale para scripts, lançadores e
// executáveis, nem para arquivos cujo conteúdo parece executável: esses continuam no `ConfirmModal`.
// ---------------------------------------------------------------------------------------------

const MAX_DEFAULTS: usize = 256;

/// Extensões que nunca ganham padrão no Kappa: um padrão aqui faria o duplo clique rodar código
const BLOCKED_EXTENSIONS: &[&str] = &[
    "sh", "bash", "zsh", "fish", "csh", "tcsh", "ksh", "dash", "command", "run", "bin", "out", "elf", "so", "appimage", "flatpak", "jar",
    "exe", "msi", "bat", "cmd", "com", "scr", "vbs", "ps1", "desktop", "directory", "py", "pyw", "pyc", "pl", "pm", "rb", "php", "lua", "tcl",
];

/// Chave da extensão de `path`: última parte, minúscula, só `[a-z0-9]`, até 16 caracteres.
/// Sem extensão, oculto sem extensão (`.bashrc`) ou extensão bloqueada: `None`.
pub fn extension_key(path: &Path) -> Option<String> {
    let name = path.file_name()?.to_str()?;
    let (stem, ext) = name.rsplit_once('.')?;
    if stem.is_empty() || stem.chars().all(|c| c == '.') {
        return None;
    }
    let ext = ext.to_ascii_lowercase();
    let ok = (1..=16).contains(&ext.len()) && ext.bytes().all(|c| c.is_ascii_alphanumeric());
    if !ok || BLOCKED_EXTENSIONS.contains(&ext.as_str()) {
        return None;
    }
    Some(ext)
}

/// O arquivo pode ganhar padrão no Kappa? Arquivo comum, extensão permitida e conteúdo que não executa
pub fn can_remember(path: &Path) -> Option<String> {
    if !std::fs::metadata(path).map(|m| m.is_file()).unwrap_or(false) {
        return None;
    }
    let ext = extension_key(path)?;
    if super::file_ops::open_risk(path).is_some() {
        return None;
    }
    Some(ext)
}

fn defaults_file() -> std::io::Result<PathBuf> {
    Ok(super::integration::config_dir()?.join("open-defaults.json"))
}

/// Lê o mapa: descarta chaves e ids inválidos, extensões bloqueadas e o que passar de `MAX_DEFAULTS`
pub fn parse_defaults(text: &str) -> Vec<(String, String)> {
    let value: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
    let mut out: Vec<(String, String)> = Vec::new();
    let Some(map) = value.get("by_extension").and_then(|v| v.as_object()) else { return out };
    for (ext, id) in map {
        let Some(id) = id.as_str() else { continue };
        let ext_ok = extension_key(Path::new(&format!("x.{ext}"))).as_deref() == Some(ext.as_str());
        if ext_ok && validate_desktop_id(id).is_ok() && out.len() < MAX_DEFAULTS && !out.iter().any(|(e, _)| e == ext) {
            out.push((ext.clone(), id.to_string()));
        }
    }
    out
}

fn load_defaults_from(file: &Path) -> Vec<(String, String)> {
    std::fs::read_to_string(file).map(|t| parse_defaults(&t)).unwrap_or_default()
}

fn save_defaults_to(file: &Path, list: &[(String, String)]) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
    let dir = file.parent().ok_or_else(|| invalid("Pasta de configuração inválida"))?;
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    let map: serde_json::Map<String, serde_json::Value> = list.iter().map(|(e, id)| (e.clone(), json!(id))).collect();
    let body = json!({ "by_extension": map }).to_string();
    let tmp = file.with_extension(format!("json.{}.tmp", std::process::id()));
    let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
    f.write_all(body.as_bytes())?;
    f.sync_all()?;
    std::fs::rename(&tmp, file)
}

/// Grava (`Some(id)`) ou esquece (`None`) o padrão de `ext` em `file`
fn update_default_in(file: &Path, ext: &str, id: Option<&str>) -> std::io::Result<()> {
    let mut list = load_defaults_from(file);
    list.retain(|(e, _)| e != ext);
    if let Some(id) = id {
        validate_desktop_id(id)?;
        if list.len() >= MAX_DEFAULTS {
            return Err(invalid("Limite de padrões do Kappa atingido"));
        }
        list.push((ext.to_string(), id.to_string()));
    }
    save_defaults_to(file, &list)
}

/// Aplicativo instalado e visível para o id (o mesmo critério do `open_with`)
fn installed_app(id: &str) -> Option<App> {
    let file = find_desktop(id)?;
    let text = std::fs::read_to_string(file).ok()?;
    let lang = ui_lang();
    let (name, icon) = parse_desktop(&text, &lang).or_else(|| parse_desktop(&text, ""))?;
    Some(App { id: id.to_string(), name, icon })
}

/// Padrão do Kappa válido para `path` agora (extensão permitida, conteúdo seguro, app ainda instalado)
pub fn kappa_default_for(path: &Path) -> Option<App> {
    let ext = can_remember(path)?;
    let id = load_defaults_from(&defaults_file().ok()?).into_iter().find(|(e, _)| *e == ext)?.1;
    installed_app(&id)
}

/// Marca `id` como padrão do Kappa para a extensão de `path`
pub fn remember(id: &str, path: &str) -> std::io::Result<String> {
    validate_desktop_id(id)?;
    require_absolute(path)?;
    let ext = can_remember(Path::new(path)).ok_or_else(|| invalid("Este tipo de arquivo não pode ter padrão no Kappa"))?;
    installed_app(id).ok_or_else(|| invalid("Aplicativo não encontrado"))?;
    update_default_in(&defaults_file()?, &ext, Some(id))?;
    Ok(ext)
}

/// Esquece o padrão do Kappa da extensão de `path` (volta ao padrão do sistema)
pub fn forget(path: &str) -> std::io::Result<()> {
    require_absolute(path)?;
    let name = Path::new(path);
    let ext = extension_key(name).ok_or_else(|| invalid("Este arquivo não tem extensão"))?;
    update_default_in(&defaults_file()?, &ext, None)
}

/// Lista para o submenu: padrão do Kappa primeiro (`badge: kappa`), depois o do sistema (`badge: system`)
pub fn list_json_with_defaults(path: &str) -> serde_json::Value {
    let p = Path::new(path);
    let mut apps = match apps_for(p) {
        Ok(a) => a,
        Err(e) => return json!({ "ok": false, "error": e.to_string(), "apps": [] }),
    };
    let ext = can_remember(p);
    let kappa = kappa_default_for(p);
    let system_id = apps.first().map(|a| a.id.clone());
    if let Some(k) = &kappa {
        apps.retain(|a| a.id != k.id);
        apps.insert(0, k.clone());
    }
    let list: Vec<_> = apps
        .into_iter()
        .map(|a| {
            let badge = if kappa.as_ref().is_some_and(|k| k.id == a.id) {
                "kappa"
            } else if system_id.as_deref() == Some(a.id.as_str()) {
                "system"
            } else {
                ""
            };
            json!({ "id": a.id, "name": a.name, "icon": a.icon, "badge": badge })
        })
        .collect();
    json!({ "ok": true, "apps": list, "ext": ext, "can_remember": ext.is_some(), "kappa_default": kappa.map(|k| k.id) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn desktop_ids_cannot_become_options_or_paths() {
        for bad in ["", ".desktop", "-x.desktop", ".x.desktop", "a/b.desktop", "../x.desktop", "a b.desktop", "a.desktop\n", "a.sh", "é.desktop", &format!("{}.desktop", "x".repeat(250))] {
            assert!(validate_desktop_id(bad).is_err(), "deveria rejeitar {bad:?}");
        }
        for ok in ["kate.desktop", "org.kde.kate.desktop", "firefox-esr.desktop", "my_app+x.desktop"] {
            assert!(validate_desktop_id(ok).is_ok(), "deveria aceitar {ok:?}");
        }
    }

    #[test]
    fn mimeinfo_matches_only_requested_types() {
        let t = "[MIME Cache]\ntext/plain=kate.desktop;gedit.desktop;\nimage/png=gwenview.desktop;\ntext/x-rust=code.desktop;\n";
        let got = parse_mimeinfo(t, &["text/x-rust".into(), "text/plain".into()]);
        assert_eq!(got, ["kate.desktop", "gedit.desktop", "code.desktop"]);
        assert!(parse_mimeinfo(t, &["video/mp4".into()]).is_empty());
    }

    #[test]
    fn text_types_also_match_plain_text_editors() {
        assert_eq!(mime_candidates("text/x-rust"), ["text/x-rust", "text/plain"]);
        assert_eq!(mime_candidates("image/png"), ["image/png"]);
    }

    #[test]
    fn desktop_files_are_filtered_and_localized() {
        let ok = "[Desktop Entry]\nType=Application\nName=Kate\nName[pt_BR]=Kate BR\nIcon=kate\nExec=kate %U\n[Desktop Action x]\nName=Outra\n";
        assert_eq!(parse_desktop(ok, "pt_BR"), Some(("Kate BR".into(), "kate".into())));
        assert_eq!(parse_desktop(ok, "en_US"), Some(("Kate".into(), "kate".into())));
        assert!(parse_desktop(&format!("{ok}NoDisplay=true\n").replace("[Desktop Action x]", ""), "").is_none());
        assert!(parse_desktop("[Desktop Entry]\nType=Link\nName=X\nExec=x\n", "").is_none());
        assert!(parse_desktop("[Desktop Entry]\nType=Application\nName=X\n", "").is_none());
    }

    #[test]
    fn all_apps_are_unique_valid_and_sorted() {
        let apps = all_apps();
        let mut ids = HashSet::new();
        for a in &apps {
            assert!(validate_desktop_id(&a.id).is_ok(), "id inválido {:?}", a.id);
            assert!(ids.insert(&a.id), "id repetido {:?}", a.id);
        }
        assert!(apps.windows(2).all(|w| w[0].name.to_lowercase() <= w[1].name.to_lowercase()));
    }

    #[test]
    fn extension_keys_are_normalized_and_scripts_are_blocked() {
        assert_eq!(extension_key(Path::new("/a/Foto.PNG")).as_deref(), Some("png"));
        assert_eq!(extension_key(Path::new("/a/b.tar.gz")).as_deref(), Some("gz"));
        assert_eq!(extension_key(Path::new("/a/relatorio.md")).as_deref(), Some("md"));
        for none in ["/a/sem", "/a/.bashrc", "/a/..x", "/a/x.", "/a/x.tar-gz", "/a/x.é", "/a/x.abcdefghijklmnopq"] {
            assert_eq!(extension_key(Path::new(none)), None, "{none:?}");
        }
        for blocked in ["/a/x.sh", "/a/x.SH", "/a/x.py", "/a/x.desktop", "/a/x.AppImage", "/a/x.jar", "/a/x.exe", "/a/x.run"] {
            assert_eq!(extension_key(Path::new(blocked)), None, "deveria bloquear {blocked:?}");
        }
    }

    #[test]
    fn saved_defaults_drop_invalid_blocked_and_duplicate_entries() {
        let t = r#"{"by_extension":{"png":"org.kde.gwenview.desktop","sh":"bash.desktop","PDF":"x.desktop","md":"../x.desktop","txt":"kate.desktop","jpg":3}}"#;
        assert_eq!(parse_defaults(t), [("png".to_string(), "org.kde.gwenview.desktop".to_string()), ("txt".into(), "kate.desktop".into())]);
        assert!(parse_defaults("lixo").is_empty());
        assert!(parse_defaults(r#"{"by_extension":[]}"#).is_empty());
    }

    #[test]
    fn defaults_file_round_trip_is_private() {
        use std::os::unix::fs::PermissionsExt;
        let dir = std::env::temp_dir().join(format!("kappa-openwith-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let file = dir.join("kappa/open-defaults.json");
        update_default_in(&file, "png", Some("a.desktop")).unwrap();
        update_default_in(&file, "txt", Some("b.desktop")).unwrap();
        update_default_in(&file, "png", Some("c.desktop")).unwrap();
        // O mapa é gravado em ordem alfabética
        assert_eq!(load_defaults_from(&file), [("png".to_string(), "c.desktop".to_string()), ("txt".into(), "b.desktop".into())]);
        assert_eq!(std::fs::metadata(&file).unwrap().permissions().mode() & 0o777, 0o600);
        assert!(update_default_in(&file, "md", Some("-x.desktop")).is_err());
        update_default_in(&file, "png", None).unwrap();
        assert_eq!(load_defaults_from(&file), [("txt".to_string(), "b.desktop".to_string())]);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn risky_content_never_gets_a_default() {
        let dir = std::env::temp_dir().join(format!("kappa-openwith-risk-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let fake = dir.join("fatura.pdf");
        std::fs::write(&fake, "#!/bin/sh\necho oi\n").unwrap();
        let elf = dir.join("foto.png");
        std::fs::write(&elf, b"\x7fELF\x02\x01").unwrap();
        let ok = dir.join("nota.txt");
        std::fs::write(&ok, "texto").unwrap();
        assert_eq!(can_remember(&fake), None);
        assert_eq!(can_remember(&elf), None);
        assert_eq!(can_remember(&dir), None);
        assert_eq!(can_remember(&ok).as_deref(), Some("txt"));
        assert!(remember("kate.desktop", &fake.to_string_lossy()).is_err());
        assert!(remember("kate.desktop", "relativo.txt").is_err());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn open_with_refuses_relative_and_unlisted() {
        assert!(open_with("kate.desktop", "relativo.txt").is_err());
        assert!(open_with("../kate.desktop", "/etc/hostname").is_err());
        assert!(open_with("kappa-inexistente-xyz.desktop", "/etc/hostname").is_err());
    }
}
