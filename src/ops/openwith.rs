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
    let result = if all {
        require_absolute(path).map(|_| all_apps())
    } else {
        apps_for(Path::new(path))
    };
    match result {
        Ok(apps) => {
            let apps: Vec<_> = apps.into_iter().map(|a| json!({ "id": a.id, "name": a.name, "icon": a.icon })).collect();
            json!({ "ok": true, "apps": apps })
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
    fn open_with_refuses_relative_and_unlisted() {
        assert!(open_with("kate.desktop", "relativo.txt").is_err());
        assert!(open_with("../kate.desktop", "/etc/hostname").is_err());
        assert!(open_with("kappa-inexistente-xyz.desktop", "/etc/hostname").is_err());
    }
}
