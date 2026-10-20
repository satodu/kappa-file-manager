use std::path::{Path, PathBuf};
use std::process::Command;

#[allow(dead_code)]
pub struct FileOperations;

/// Erro de entrada inválida (nome, caminho ou argumento rejeitado por segurança)
pub fn invalid(msg: impl Into<String>) -> std::io::Error {
    std::io::Error::new(std::io::ErrorKind::InvalidInput, msg.into())
}

/// Um nome de arquivo/pasta novo não pode ser um caminho: sem `/`, sem `.`/`..`, sem NUL ou controle
pub fn validate_file_name(name: &str) -> std::io::Result<()> {
    let b = name.as_bytes();
    if b.is_empty() || b.len() > 255 {
        return Err(invalid("Nome vazio ou longo demais (máximo de 255 bytes)"));
    }
    if name == "." || name == ".." {
        return Err(invalid("Nome inválido"));
    }
    if b.iter().any(|&c| c == b'/' || c == 0 || c < 0x20 || c == 0x7f) {
        return Err(invalid("O nome não pode conter '/' nem caracteres de controle"));
    }
    Ok(())
}

/// Todo caminho recebido pela CLI precisa ser absoluto e sem NUL (nada de caminhos relativos ou opções disfarçadas)
pub fn require_absolute(path: &str) -> std::io::Result<()> {
    if !path.starts_with('/') || path.contains('\0') {
        return Err(invalid("Caminho precisa ser absoluto"));
    }
    Ok(())
}

/// Recusa apagar/mover para a lixeira a raiz, diretórios de topo (`/home`, `/etc`...) e a própria home
pub fn ensure_not_protected(path: &Path) -> std::io::Result<()> {
    let comps = path.components().filter(|c| matches!(c, std::path::Component::Normal(_))).count();
    let home = std::env::var_os("HOME").map(PathBuf::from);
    if comps < 2 || home.as_deref() == Some(path) {
        return Err(invalid("Este item é protegido e não pode ser removido"));
    }
    Ok(())
}

/// Id de dispositivo KDE Connect: só letras, números, `_` e `-`, sem começar com `-` (evita virar opção)
pub fn validate_device_id(id: &str) -> std::io::Result<()> {
    let ok = !id.is_empty() && id.len() <= 128 && !id.starts_with('-') && id.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-');
    if ok { Ok(()) } else { Err(invalid("Id de dispositivo inválido")) }
}

/// Dispositivo de bloco: só `/dev/<nome>` simples (sem `..`, espaços ou opções disfarçadas)
pub fn validate_block_device(dev: &str) -> std::io::Result<()> {
    let ok = dev.starts_with("/dev/")
        && dev.len() <= 64
        && !dev.contains("..")
        && dev.bytes().skip(5).all(|c| c.is_ascii_alphanumeric() || matches!(c, b'/' | b'_' | b'-' | b'.'));
    if ok && dev.len() > 5 { Ok(()) } else { Err(invalid("Dispositivo inválido")) }
}

/// Por que abrir este arquivo poderia executar código? `None` = abertura comum.
/// Olha o conteúdo (ELF, shebang, `[Desktop Entry]`) e as extensões que o desktop trata como lançadores,
/// porque o nome pode mentir (`fatura.pdf` que na verdade é um script).
pub fn open_risk(path: &Path) -> Option<&'static str> {
    use std::io::Read;
    let meta = std::fs::metadata(path).ok()?;
    if !meta.is_file() {
        return None;
    }
    let ext = path.extension().map(|e| e.to_string_lossy().to_lowercase()).unwrap_or_default();
    if matches!(ext.as_str(), "desktop" | "directory") {
        return Some("launcher");
    }
    let mut head = [0u8; 512];
    let n = std::fs::File::open(path).and_then(|mut f| f.read(&mut head)).unwrap_or(0);
    let head = &head[..n];
    let text = String::from_utf8_lossy(head);
    if text.trim_start().starts_with("[Desktop Entry]") {
        return Some("launcher");
    }
    if head.starts_with(b"\x7fELF") {
        return Some("program");
    }
    if head.starts_with(b"#!") {
        return Some("script");
    }
    if matches!(ext.as_str(), "sh" | "bash" | "zsh" | "fish" | "run" | "appimage" | "jar" | "exe" | "msi" | "bat" | "cmd" | "com" | "scr" | "vbs" | "ps1" | "bin") {
        return Some("program");
    }
    None
}

/// Rodar como root só com opt-in explícito
pub fn root_allowed(euid: u32, opt_in: bool) -> bool {
    euid != 0 || opt_in
}

/// `rename` que nunca sobrescreve um destino existente (RENAME_NOREPLACE; plano B: checa antes)
pub(crate) fn rename_no_replace(from: &Path, to: &Path) -> std::io::Result<()> {
    use std::os::unix::ffi::OsStrExt;
    let (Ok(f), Ok(t)) = (std::ffi::CString::new(from.as_os_str().as_bytes()), std::ffi::CString::new(to.as_os_str().as_bytes())) else {
        return Err(invalid("Caminho inválido"));
    };
    let rc = unsafe { libc::renameat2(libc::AT_FDCWD, f.as_ptr(), libc::AT_FDCWD, t.as_ptr(), libc::RENAME_NOREPLACE) };
    if rc == 0 {
        return Ok(());
    }
    let e = std::io::Error::last_os_error();
    match e.raw_os_error() {
        // Sistema de arquivos sem suporte ao flag: confere antes de renomear
        Some(libc::EINVAL) | Some(libc::ENOSYS) | Some(libc::EOPNOTSUPP) => {
            if std::fs::symlink_metadata(to).is_ok() {
                return Err(std::io::Error::new(std::io::ErrorKind::AlreadyExists, "Já existe um item com esse nome"));
            }
            std::fs::rename(from, to)
        }
        Some(libc::EEXIST) => Err(std::io::Error::new(std::io::ErrorKind::AlreadyExists, "Já existe um item com esse nome")),
        _ => Err(e),
    }
}

#[allow(dead_code)]
impl FileOperations {
    pub fn require_abs_ok(path: &str) -> std::io::Result<()> {
        require_absolute(path)
    }

    /// Abre o arquivo ou pasta usando o aplicativo padrão do sistema (xdg-open)
    pub fn open_default(path: impl AsRef<Path>) -> std::io::Result<()> {
        let p = path.as_ref();
        require_absolute(&p.to_string_lossy())?;
        // Absoluto nunca começa com "-", então não vira opção do xdg-open
        if std::fs::symlink_metadata(p).is_err() {
            return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "O arquivo não existe mais"));
        }
        let status = Command::new("xdg-open")
            .arg(p)
            .stdin(std::process::Stdio::null())
            .spawn()?
            .wait()?;
        if status.success() { Ok(()) } else { Err(invalid("Nenhum aplicativo conseguiu abrir este arquivo")) }
    }

    /// Move o item para a lixeira seguindo o FreeDesktop Trash spec
    pub fn move_to_trash(path: impl AsRef<Path>) -> Result<(), trash::Error> {
        let p = path.as_ref();
        if let Err(e) = require_absolute(&p.to_string_lossy()).and_then(|_| ensure_not_protected(p)) {
            return Err(trash::Error::Unknown { description: e.to_string() });
        }
        trash::delete(p)
    }

    /// Remove o item definitivamente do disco (sem passar pela lixeira)
    pub fn delete_permanently(path: impl AsRef<Path>) -> std::io::Result<()> {
        let p = path.as_ref();
        require_absolute(&p.to_string_lossy())?;
        ensure_not_protected(p)?;
        let meta = std::fs::symlink_metadata(p)?;
        if meta.is_dir() {
            std::fs::remove_dir_all(p)
        } else {
            std::fs::remove_file(p)
        }
    }

    /// Cria uma nova pasta no diretório atual com nome único se já existir
    pub fn create_folder(parent: impl AsRef<Path>, folder_name: &str) -> std::io::Result<PathBuf> {
        let parent_path = parent.as_ref();
        require_absolute(&parent_path.to_string_lossy())?;
        validate_file_name(folder_name)?;
        if !parent_path.is_dir() {
            return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "A pasta de destino não existe"));
        }
        // `create_dir` falha se o nome já existir: tenta nomes únicos até conseguir (sem corrida)
        for i in 0..10_000u32 {
            let name = if i == 0 { folder_name.to_string() } else { format!("{} ({})", folder_name, i) };
            let target = parent_path.join(&name);
            match std::fs::create_dir(&target) {
                Ok(_) => return Ok(target),
                Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
                Err(e) => return Err(e),
            }
        }
        Err(invalid("Não foi possível escolher um nome livre"))
    }

    /// Renomeia um arquivo ou pasta
    pub fn rename_item(old_path: impl AsRef<Path>, new_name: &str) -> std::io::Result<PathBuf> {
        let old = old_path.as_ref();
        require_absolute(&old.to_string_lossy())?;
        validate_file_name(new_name)?;
        let parent = old.parent().unwrap_or_else(|| Path::new("/"));
        let new_path = parent.join(new_name);
        if new_path != old {
            rename_no_replace(old, &new_path)?;
        }
        Ok(new_path)
    }

    /// Impede copiar/mover uma pasta para dentro dela mesma (recursão infinita)
    pub(crate) fn ensure_not_into_self(src: &Path, dst_dir: &Path) -> std::io::Result<()> {
        if !src.is_dir() {
            return Ok(());
        }
        let src_c = src.canonicalize()?;
        let dst_c = dst_dir.canonicalize().unwrap_or_else(|_| dst_dir.to_path_buf());
        if dst_c.starts_with(&src_c) {
            return Err(std::io::Error::new(
                std::io::ErrorKind::InvalidInput,
                "Não é possível copiar ou mover uma pasta para dentro dela mesma",
            ));
        }
        Ok(())
    }

    pub(crate) fn find_unique_target_path(target_dir: &Path, file_name: &std::ffi::OsStr, is_dir: bool) -> PathBuf {
        let initial_path = target_dir.join(file_name);
        if !initial_path.exists() {
            return initial_path;
        }

        let name_str = file_name.to_string_lossy().to_string();
        let (stem, ext) = if is_dir {
            (name_str.clone(), String::new())
        } else {
            let p = Path::new(&name_str);
            let stem = p.file_stem().and_then(|s| s.to_str()).unwrap_or(&name_str).to_string();
            let ext = p.extension().and_then(|e| e.to_str()).map(|e| format!(".{}", e)).unwrap_or_default();
            (stem, ext)
        };

        for i in 1..10000 {
            let candidate_name = if ext.is_empty() {
                format!("{} ({})", stem, i)
            } else {
                format!("{} ({}){}", stem, i, ext)
            };
            let candidate_path = target_dir.join(candidate_name);
            if !candidate_path.exists() {
                return candidate_path;
            }
        }

        target_dir.join(format!("{}_{}", stem, chrono::Local::now().timestamp()))
    }

    /// Compartilha arquivo via KDE Connect
    pub fn kde_share(device_id: &str, file_path: impl AsRef<Path>) -> std::io::Result<()> {
        let p = file_path.as_ref();
        validate_device_id(device_id)?;
        require_absolute(&p.to_string_lossy())?;
        Command::new("kdeconnect-cli")
            .arg("-d")
            .arg(device_id)
            .arg("--share")
            .arg(p)
            .spawn()?
            .wait()?;
        Ok(())
    }

    /// Envia ping para dispositivo KDE Connect
    pub fn kde_ping(device_id: &str) -> std::io::Result<()> {
        validate_device_id(device_id)?;
        Command::new("kdeconnect-cli")
            .arg("-d")
            .arg(device_id)
            .arg("--ping")
            .spawn()?
            .wait()?;
        Ok(())
    }

    /// Faz o dispositivo KDE Connect tocar
    pub fn kde_ring(device_id: &str) -> std::io::Result<()> {
        validate_device_id(device_id)?;
        Command::new("kdeconnect-cli")
            .arg("-d")
            .arg(device_id)
            .arg("--ring")
            .spawn()?
            .wait()?;
        Ok(())
    }

    /// Envia área de transferência via KDE Connect
    pub fn kde_send_clipboard(device_id: &str) -> std::io::Result<()> {
        validate_device_id(device_id)?;
        Command::new("kdeconnect-cli")
            .arg("-d")
            .arg(device_id)
            .arg("--send-clipboard")
            .spawn()?
            .wait()?;
        Ok(())
    }

    /// Monta o sistema de arquivos do dispositivo KDE Connect
    pub fn kde_mount(device_id: &str) -> std::io::Result<()> {
        validate_device_id(device_id)?;
        Command::new("kdeconnect-cli")
            .arg("-d")
            .arg(device_id)
            .arg("--mount")
            .spawn()?
            .wait()?;
        Ok(())
    }

    /// Monta dispositivo de bloco (pendrive/disco) via udisksctl e retorna o ponto de montagem
    pub fn mount_device(device_block: &str) -> std::io::Result<PathBuf> {
        validate_block_device(device_block)?;
        // 1. Checa se o dispositivo já está montado no sistema
        if let Ok(out) = Command::new("lsblk")
            .arg("-J")
            .arg("-p")
            .arg("-o")
            .arg("NAME,MOUNTPOINTS")
            .arg(device_block)
            .output()
        {
            if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                if let Some(devices) = val["blockdevices"].as_array() {
                    for dev in devices {
                        if let Some(mps) = dev["mountpoints"].as_array() {
                            for mp in mps {
                                if let Some(s) = mp.as_str() {
                                    if !s.is_empty() {
                                        return Ok(PathBuf::from(s));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 2. Invoca o udisksctl para montar sem necessidade de root
        let output = Command::new("udisksctl")
            .arg("mount")
            .arg("-b")
            .arg(device_block)
            .arg("--no-user-interaction")
            .output()?;

        let full_output = format!("{}\n{}", String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));

        // Procura "at `path`" ou "at path."
        if let Some(pos) = full_output.find(" at ") {
            let rest = &full_output[pos + 4..];
            let clean = rest
                .lines()
                .next()
                .unwrap_or("")
                .trim()
                .trim_matches('\'')
                .trim_matches('`')
                .trim_end_matches('.');
            if !clean.is_empty() {
                return Ok(PathBuf::from(clean));
            }
        }

        // 3. Fallback: re-consulta o lsblk após o comando
        if let Ok(out) = Command::new("lsblk")
            .arg("-J")
            .arg("-p")
            .arg("-o")
            .arg("NAME,MOUNTPOINTS")
            .arg(device_block)
            .output()
        {
            if let Ok(val) = serde_json::from_slice::<serde_json::Value>(&out.stdout) {
                if let Some(devices) = val["blockdevices"].as_array() {
                    for dev in devices {
                        if let Some(mps) = dev["mountpoints"].as_array() {
                            for mp in mps {
                                if let Some(s) = mp.as_str() {
                                    if !s.is_empty() {
                                        return Ok(PathBuf::from(s));
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Err(std::io::Error::new(std::io::ErrorKind::Other, full_output))
    }

    /// Desmonta e ejeta mídia removível (pendrive) via udisksctl
    pub fn eject_device(device_or_path: &str) -> std::io::Result<()> {
        validate_block_device(device_or_path)?;
        let _ = Command::new("udisksctl")
            .arg("unmount")
            .arg("-b")
            .arg(device_or_path)
            .output();
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kappa-fileops-{}-{}", name, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn names_cannot_be_paths() {
        for bad in ["", ".", "..", "a/b", "../x", "/etc/x", "a\0b", "tab\tname", &"x".repeat(256)] {
            assert!(validate_file_name(bad).is_err(), "deveria rejeitar {bad:?}");
        }
        for ok in ["file.txt", ".hidden", "com espaço", "日本語", "a..b", "-rf"] {
            assert!(validate_file_name(ok).is_ok(), "deveria aceitar {ok:?}");
        }
    }

    #[test]
    fn rename_cannot_escape_or_overwrite() {
        let root = scratch("rename");
        std::fs::create_dir_all(root.join("sub")).unwrap();
        std::fs::write(root.join("sub/a.txt"), "A").unwrap();
        std::fs::write(root.join("sub/b.txt"), "B").unwrap();

        assert!(FileOperations::rename_item(root.join("sub/a.txt"), "../escaped.txt").is_err());
        assert!(FileOperations::rename_item(root.join("sub/a.txt"), &root.join("abs.txt").to_string_lossy()).is_err());
        assert!(FileOperations::rename_item(root.join("sub/a.txt"), "b.txt").is_err(), "não pode sobrescrever");
        assert_eq!(std::fs::read_to_string(root.join("sub/b.txt")).unwrap(), "B");
        assert!(root.join("sub/a.txt").exists());

        let renamed = FileOperations::rename_item(root.join("sub/a.txt"), "c.txt").unwrap();
        assert_eq!(renamed, root.join("sub/c.txt"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn new_folder_validates_name_and_never_reuses() {
        let root = scratch("newfolder");
        assert!(FileOperations::create_folder(&root, "../x").is_err());
        assert!(FileOperations::create_folder(root.join("nao-existe"), "x").is_err());
        let a = FileOperations::create_folder(&root, "Nova").unwrap();
        let b = FileOperations::create_folder(&root, "Nova").unwrap();
        assert_ne!(a, b);
        assert!(b.ends_with("Nova (1)"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn critical_paths_are_protected_and_args_must_be_absolute() {
        assert!(ensure_not_protected(Path::new("/")).is_err());
        assert!(ensure_not_protected(Path::new("/home")).is_err());
        assert!(ensure_not_protected(Path::new("/etc")).is_err());
        if let Some(h) = std::env::var_os("HOME") {
            assert!(ensure_not_protected(Path::new(&h)).is_err());
        }
        assert!(ensure_not_protected(Path::new("/tmp/algo")).is_ok());
        assert!(FileOperations::delete_permanently("relativo/x").is_err());
        assert!(FileOperations::delete_permanently("/").is_err());
        assert!(require_absolute("-rf").is_err());
    }

    #[test]
    fn root_requires_explicit_opt_in() {
        assert!(root_allowed(1000, false));
        assert!(!root_allowed(0, false));
        assert!(root_allowed(0, true));
    }

    #[test]
    fn block_devices_are_validated() {
        for bad in ["--help", "sda1", "/dev/", "/dev/../etc/passwd", "/dev/sda1 --foo", "/etc/passwd", "/dev/sd\na"] {
            assert!(validate_block_device(bad).is_err(), "deveria rejeitar {bad:?}");
        }
        for ok in ["/dev/sdb1", "/dev/nvme0n1p2", "/dev/disk/by-label/PEN", "/dev/mapper/vg-root"] {
            assert!(validate_block_device(ok).is_ok(), "deveria aceitar {ok:?}");
        }
        assert!(FileOperations::mount_device("--help").is_err());
    }

    #[test]
    fn kde_ids_cannot_become_options() {
        assert!(validate_device_id("--help").is_err());
        assert!(validate_device_id("-d").is_err());
        assert!(validate_device_id("a b").is_err());
        assert!(validate_device_id("").is_err());
        assert!(validate_device_id("4f1c_a2b3-77").is_ok());
        assert!(FileOperations::kde_share("--version", "/tmp/x").is_err());
    }

    #[test]
    fn executables_and_launchers_are_flagged_by_content_not_by_name() {
        let root = scratch("risk");
        let write = |n: &str, c: &[u8]| { std::fs::write(root.join(n), c).unwrap(); root.join(n) };
        assert_eq!(open_risk(&write("fatura.pdf", b"#!/bin/sh\nrm -rf ~\n")), Some("script"));
        assert_eq!(open_risk(&write("foto.png", b"\x7fELF\x02\x01\x01")), Some("program"));
        assert_eq!(open_risk(&write("doc.txt", b"[Desktop Entry]\nExec=evil\n")), Some("launcher"));
        assert_eq!(open_risk(&write("app.desktop", b"x")), Some("launcher"));
        assert_eq!(open_risk(&write("setup.AppImage", b"x")), Some("program"));
        assert_eq!(open_risk(&write("notas.txt", b"apenas texto")), None);
        assert_eq!(open_risk(&write("img.png", b"\x89PNG\r\n\x1a\n")), None);
        assert_eq!(open_risk(&root), None);
        let _ = std::fs::remove_dir_all(&root);
    }
}
