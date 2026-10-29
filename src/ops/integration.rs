//! Integração com o desktop: abrir o Kappa a partir de outros apps (`org.freedesktop.FileManager1`,
//! "Mostrar na pasta"), de `kappa-file-manager <pasta|arquivo|file://…>` e como gerenciador padrão.
//!
//! O serviço D-Bus só *abre janelas* com caminhos validados: não devolve dados, não lê nem altera arquivos.

use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use super::file_ops::{invalid, require_absolute};

const MAX_TARGETS_PER_CALL: usize = 8;
const MAX_WINDOWS_PER_MINUTE: usize = 16;
const IDLE_EXIT: Duration = Duration::from_secs(60);
const DESKTOP_ID: &str = "kappa-file-manager.desktop";
const BUS_NAME: &str = "org.freedesktop.FileManager1";
const SERVICE_MARKER: &str = "# kappa-file-manager (gerado por --set-default)";

fn percent_decode(s: &str) -> Option<Vec<u8>> {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' {
            let hex = std::str::from_utf8(b.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    Some(out)
}

/// `file:///x/y%20z` ou `/x/y` viram caminho absoluto. Só `file://` (host vazio ou `localhost`):
/// `trash://`, `smb://`, `recent://` etc. são recusados, assim como NUL e quebras de linha.
pub fn uri_to_path(arg: &str) -> std::io::Result<PathBuf> {
    let raw = match arg.strip_prefix("file://") {
        Some(rest) => {
            let rest = rest.strip_prefix("localhost").unwrap_or(rest);
            let decoded = percent_decode(rest).ok_or_else(|| invalid("URI inválida"))?;
            String::from_utf8(decoded).map_err(|_| invalid("URI inválida"))?
        }
        None if arg.contains("://") => return Err(invalid("Só caminhos locais são aceitos")),
        None => arg.to_string(),
    };
    if raw.contains(['\0', '\n', '\r']) || raw.len() > 4096 {
        return Err(invalid("Caminho inválido"));
    }
    require_absolute(&raw)?;
    Ok(PathBuf::from(raw))
}

/// Alvo de abertura: `(pasta a abrir, item a selecionar)`. Arquivo → pasta que o contém, com o arquivo selecionado.
pub fn resolve_target(arg: &str) -> std::io::Result<(PathBuf, Option<PathBuf>)> {
    let path = uri_to_path(arg)?;
    let meta = std::fs::symlink_metadata(&path).map_err(|_| invalid("O item não existe"))?;
    // Link para pasta abre a pasta; o resto é tratado como item dentro da pasta pai
    if std::fs::metadata(&path).map(|m| m.is_dir()).unwrap_or(false) && !meta.file_type().is_symlink() {
        return Ok((path, None));
    }
    let parent = path.parent().ok_or_else(|| invalid("Item sem pasta"))?.to_path_buf();
    Ok((parent, Some(path)))
}

/// Pasta e item para o launcher: duas linhas (pasta, item ou vazio)
pub fn start_from(arg: &str) -> std::io::Result<String> {
    let (dir, sel) = resolve_target(arg)?;
    Ok(format!("{}\n{}\n", dir.display(), sel.map(|s| s.display().to_string()).unwrap_or_default()))
}

/// Janelas abertas nos últimos 60 s: evita que um app em laço abra centenas de janelas
struct WindowBudget(Mutex<Vec<Instant>>);

impl WindowBudget {
    fn take(&self, n: usize) -> usize {
        let mut v = self.0.lock().unwrap();
        v.retain(|t| t.elapsed() < Duration::from_secs(60));
        let free = MAX_WINDOWS_PER_MINUTE.saturating_sub(v.len());
        let n = n.min(free);
        v.extend(std::iter::repeat_n(Instant::now(), n));
        n
    }
}

fn launcher() -> PathBuf {
    match std::env::var_os("KAPPA_LAUNCHER") {
        Some(p) if Path::new(&p).is_absolute() => PathBuf::from(p),
        _ => PathBuf::from("/usr/bin/kappa-file-manager"),
    }
}

/// Abre uma janela do Kappa para cada alvo válido (sem shell: o caminho vai como um único argumento)
fn open_windows(uris: &[String], budget: &WindowBudget, only_first_item: bool) {
    let mut targets: Vec<String> = Vec::new();
    for u in uris.iter().take(MAX_TARGETS_PER_CALL) {
        if let Ok(path) = uri_to_path(u) {
            let s = path.to_string_lossy().to_string();
            if !targets.contains(&s) {
                targets.push(s);
            }
        }
    }
    if only_first_item {
        targets.truncate(1);
    }
    let n = budget.take(targets.len());
    for t in targets.into_iter().take(n) {
        let _ = Command::new(launcher())
            .arg(&t)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .spawn();
    }
}

struct FileManager1 {
    budget: WindowBudget,
    last_call: std::sync::Arc<Mutex<Instant>>,
}

impl FileManager1 {
    fn touch(&self) {
        *self.last_call.lock().unwrap() = Instant::now();
    }
}

#[zbus::interface(name = "org.freedesktop.FileManager1")]
impl FileManager1 {
    async fn show_folders(&self, uris: Vec<String>, _startup_id: String) {
        self.touch();
        open_windows(&uris, &self.budget, false);
    }

    async fn show_items(&self, uris: Vec<String>, _startup_id: String) {
        self.touch();
        open_windows(&uris, &self.budget, false);
    }

    /// O Kappa mostra as propriedades no painel de detalhes: abre a pasta com o item selecionado
    async fn show_item_properties(&self, uris: Vec<String>, _startup_id: String) {
        self.touch();
        open_windows(&uris, &self.budget, true);
    }
}

/// Serviço D-Bus: assume `org.freedesktop.FileManager1` e sai sozinho depois de 60 s sem chamadas
pub async fn run_dbus_service() -> zbus::Result<()> {
    let last_call = std::sync::Arc::new(Mutex::new(Instant::now()));
    let iface = FileManager1 { budget: WindowBudget(Mutex::new(Vec::new())), last_call: last_call.clone() };
    let _conn = zbus::connection::Builder::session()
        .name(BUS_NAME)
        .serve_at("/org/freedesktop/FileManager1", iface)
        .build()
        .await?;
    loop {
        tokio::time::sleep(Duration::from_secs(5)).await;
        if last_call.lock().unwrap().elapsed() > IDLE_EXIT {
            return Ok(());
        }
    }
}

fn data_home() -> std::io::Result<PathBuf> {
    match std::env::var_os("XDG_DATA_HOME").filter(|v| !v.is_empty()).map(PathBuf::from) {
        Some(p) if p.is_absolute() => Ok(p),
        _ => dirs::home_dir().map(|h| h.join(".local/share")).ok_or_else(|| invalid("HOME não definido")),
    }
}

fn config_dir() -> std::io::Result<PathBuf> {
    match std::env::var_os("XDG_CONFIG_HOME").filter(|v| !v.is_empty()).map(PathBuf::from) {
        Some(p) if p.is_absolute() => Ok(p.join("kappa")),
        _ => dirs::home_dir().map(|h| h.join(".config/kappa")).ok_or_else(|| invalid("HOME não definido")),
    }
}

fn service_file() -> std::io::Result<PathBuf> {
    Ok(data_home()?.join("dbus-1/services/org.freedesktop.FileManager1.service"))
}

/// Conteúdo do arquivo de ativação D-Bus. `Exec` é dividido por espaços, então o executável não pode ter espaços ou controles.
pub fn service_contents(exe: &Path) -> std::io::Result<String> {
    let exe = exe.to_string_lossy();
    if !exe.starts_with('/') || exe.chars().any(|c| c.is_whitespace() || c.is_control() || c == '"' || c == '\\') {
        return Err(invalid("Caminho do executável não pode ir para o arquivo de serviço"));
    }
    Ok(format!("{SERVICE_MARKER}\n[D-BUS Service]\nName={BUS_NAME}\nExec={exe} --dbus-service\n"))
}

fn xdg_mime(args: &[&str]) -> Option<String> {
    let o = Command::new("xdg-mime").args(args).stdin(Stdio::null()).stderr(Stdio::null()).output().ok()?;
    o.status.success().then(|| String::from_utf8_lossy(&o.stdout).trim().to_string())
}

/// Grava `data` em `dest` sem seguir links e sem deixar arquivo pela metade
fn write_atomic(dest: &Path, data: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let dir = dest.parent().ok_or_else(|| invalid("Destino inválido"))?;
    std::fs::create_dir_all(dir)?;
    let tmp = dir.join(format!(".kappa-tmp-{}", std::process::id()));
    let _ = std::fs::remove_file(&tmp);
    let mut f = std::fs::OpenOptions::new().write(true).create_new(true).mode(0o644).custom_flags(libc::O_NOFOLLOW).open(&tmp)?;
    f.write_all(data.as_bytes())?;
    f.sync_all()?;
    std::fs::rename(&tmp, dest)
}

/// Torna o Kappa o gerenciador padrão do usuário: `inode/directory` e o serviço `FileManager1`.
/// Tudo no perfil do usuário; guarda o padrão anterior para `unset_default`.
pub fn set_default() -> std::io::Result<String> {
    let exe = std::env::var_os("KAPPA_BACKEND").map(PathBuf::from).filter(|p| p.is_absolute()).map(Ok).unwrap_or_else(std::env::current_exe)?;
    let exe = std::fs::canonicalize(exe)?;
    let contents = service_contents(&exe)?;
    let svc = service_file()?;
    if let Ok(existing) = std::fs::read_to_string(&svc) {
        if !existing.starts_with(SERVICE_MARKER) {
            return Err(invalid("Já existe um serviço FileManager1 seu que não é do Kappa; remova-o antes"));
        }
    }

    let previous = xdg_mime(&["query", "default", "inode/directory"]).unwrap_or_default();
    let backup = config_dir()?.join("previous-default");
    if previous != DESKTOP_ID && !previous.is_empty() && !backup.exists() {
        write_atomic(&backup, &previous)?;
    }
    write_atomic(&svc, &contents)?;
    if xdg_mime(&["default", DESKTOP_ID, "inode/directory"]).is_none() && xdg_mime(&["query", "default", "inode/directory"]).as_deref() != Some(DESKTOP_ID) {
        return Err(invalid("xdg-mime não conseguiu definir o padrão"));
    }
    Ok("O Kappa agora é o gerenciador de arquivos padrão (pastas e \"Mostrar na pasta\"). Um gerenciador que já esteja aberto continua atendendo até fechar.".into())
}

/// Desfaz `set_default`: apaga o serviço do Kappa e restaura o gerenciador anterior
pub fn unset_default() -> std::io::Result<String> {
    let svc = service_file()?;
    if let Ok(existing) = std::fs::read_to_string(&svc) {
        if existing.starts_with(SERVICE_MARKER) {
            std::fs::remove_file(&svc)?;
        }
    }
    let backup = config_dir()?.join("previous-default");
    if let Ok(prev) = std::fs::read_to_string(&backup) {
        let prev = prev.trim();
        if super::openwith::validate_desktop_id(prev).is_ok() && prev != DESKTOP_ID {
            let _ = xdg_mime(&["default", prev, "inode/directory"]);
        }
        let _ = std::fs::remove_file(&backup);
    }
    Ok("O Kappa deixou de ser o gerenciador padrão.".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uris_become_absolute_local_paths_only() {
        assert_eq!(uri_to_path("file:///home/a/b%20c").unwrap(), PathBuf::from("/home/a/b c"));
        assert_eq!(uri_to_path("file://localhost/tmp/x").unwrap(), PathBuf::from("/tmp/x"));
        assert_eq!(uri_to_path("/tmp/x").unwrap(), PathBuf::from("/tmp/x"));
        assert_eq!(uri_to_path("file:///tmp/%E6%B2%B3").unwrap(), PathBuf::from("/tmp/河"));
        for bad in [
            "", "relativo/x", "file://host/tmp/x", "trash:///x", "smb://srv/x", "recent:///", "sftp://h/x", "http://x/y",
            "file:///tmp/a%00b", "file:///tmp/a%0Ab", "file:///tmp/%zz", "file:///tmp/%4", "file:///tmp/%FF", "/tmp/a\nb", "-rf",
        ] {
            assert!(uri_to_path(bad).is_err(), "deveria rejeitar {bad:?}");
        }
        assert!(uri_to_path(&format!("/{}", "x".repeat(5000))).is_err());
    }

    #[test]
    fn files_open_their_folder_with_selection() {
        let dir = std::env::temp_dir().join(format!("kappa-integ-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        let file = dir.join("a b.txt");
        std::fs::write(&file, "x").unwrap();
        let link = dir.join("link");
        std::os::unix::fs::symlink(&dir, &link).unwrap();

        assert_eq!(resolve_target(dir.to_str().unwrap()).unwrap(), (dir.clone(), None));
        assert_eq!(resolve_target(file.to_str().unwrap()).unwrap(), (dir.clone(), Some(file.clone())));
        // Link para pasta não é seguido: abre a pasta que o contém, selecionando o link
        assert_eq!(resolve_target(link.to_str().unwrap()).unwrap(), (dir.clone(), Some(link.clone())));
        assert!(resolve_target(dir.join("nao-existe").to_str().unwrap()).is_err());
        assert_eq!(start_from(file.to_str().unwrap()).unwrap(), format!("{}\n{}\n", dir.display(), file.display()));
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn window_budget_caps_a_flood() {
        let b = WindowBudget(Mutex::new(Vec::new()));
        assert_eq!(b.take(10), 10);
        assert_eq!(b.take(10), MAX_WINDOWS_PER_MINUTE - 10);
        assert_eq!(b.take(1), 0);
    }

    #[test]
    fn service_file_refuses_unsafe_executable_paths() {
        assert!(service_contents(Path::new("/usr/lib/kappa-file-manager/kappa-file-manager")).unwrap().contains("Exec=/usr/lib/kappa-file-manager/kappa-file-manager --dbus-service\n"));
        for bad in ["relativo/kappa", "/opt/my app/kappa", "/opt/a\nExec=/bin/sh/kappa", "/opt/a\"b", "/opt/a\\b", "/opt/a\tb"] {
            assert!(service_contents(Path::new(bad)).is_err(), "deveria rejeitar {bad:?}");
        }
    }
}
