//! Nuvem via `rclone`: o Kappa só lê quais remotes existem e monta/desmonta com `rclone mount`.
//! Login, tokens e protocolo ficam com o rclone; o Kappa nunca abre `rclone.conf`, não repassa
//! segredos e só monta em modo somente leitura, sem cache em disco.

use std::io;
use std::os::unix::fs::DirBuilderExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::json;

use super::file_ops::parse_mountinfo;

const MOUNT_TIMEOUT: Duration = Duration::from_secs(60);
const SUPPORTED_TYPES: [&str; 2] = ["drive", "onedrive"];

fn invalid(msg: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, msg.to_string())
}

/// Nome de remote: só letras, números, `_` e `-`, sem começar com `-` (nunca vira opção do rclone)
pub fn validate_remote_name(name: &str) -> io::Result<()> {
    let ok = !name.is_empty()
        && name.len() <= 64
        && !name.starts_with('-')
        && name.bytes().all(|c| c.is_ascii_alphanumeric() || c == b'_' || c == b'-');
    if ok { Ok(()) } else { Err(invalid("Nome de remote inválido")) }
}

/// Pasta própria (0700) onde as nuvens são montadas; nunca um caminho vindo de fora
fn mount_base() -> io::Result<PathBuf> {
    let root = match std::env::var_os("XDG_RUNTIME_DIR").filter(|v| !v.is_empty()) {
        Some(run) => PathBuf::from(run),
        None => PathBuf::from(std::env::var_os("HOME").ok_or_else(|| invalid("HOME indefinido"))?).join(".cache"),
    };
    if !root.is_absolute() {
        return Err(invalid("Pasta de montagem inválida"));
    }
    Ok(root.join("kappa").join("cloud"))
}

pub fn mount_point(name: &str) -> io::Result<PathBuf> {
    validate_remote_name(name)?;
    Ok(mount_base()?.join(name))
}

fn is_mounted(mp: &std::path::Path) -> bool {
    let table = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    parse_mountinfo(&table).iter().any(|m| m == mp)
}

/// Saída de `rclone listremotes --long` ("nome:  tipo"): só remotes de Google Drive e OneDrive com nome válido
pub fn parse_remotes(text: &str) -> Vec<(String, String)> {
    text.lines()
        .filter_map(|line| {
            let (name, kind) = line.split_once(':')?;
            let kind = kind.trim();
            if !SUPPORTED_TYPES.contains(&kind) || validate_remote_name(name).is_err() {
                return None;
            }
            Some((name.to_string(), kind.to_string()))
        })
        .collect()
}

/// Lista os remotes. `available: false` quando o rclone não está instalado.
pub fn list() -> serde_json::Value {
    let out = match Command::new("rclone").args(["listremotes", "--long"]).stdin(Stdio::null()).stderr(Stdio::null()).output() {
        Ok(o) if o.status.success() => o,
        Ok(_) => return json!({ "ok": true, "available": true, "remotes": [] }),
        Err(_) => return json!({ "ok": true, "available": false, "remotes": [] }),
    };
    let remotes: Vec<_> = parse_remotes(&String::from_utf8_lossy(&out.stdout))
        .into_iter()
        .map(|(name, kind)| {
            let mp = mount_point(&name).ok();
            let mounted = mp.as_deref().map(is_mounted).unwrap_or(false);
            json!({ "name": name, "type": kind, "mounted": mounted, "path": mp.filter(|_| mounted) })
        })
        .collect();
    json!({ "ok": true, "available": true, "remotes": remotes })
}

fn is_supported_remote(name: &str) -> bool {
    let Ok(out) = Command::new("rclone").args(["listremotes", "--long"]).stdin(Stdio::null()).stderr(Stdio::null()).output() else {
        return false;
    };
    parse_remotes(&String::from_utf8_lossy(&out.stdout)).iter().any(|(n, _)| n == name)
}

/// Monta o remote (somente leitura, sem cache em disco) e devolve o ponto de montagem
pub fn mount(name: &str) -> io::Result<PathBuf> {
    let mp = mount_point(name)?;
    if is_mounted(&mp) {
        return Ok(mp);
    }
    if !is_supported_remote(name) {
        return Err(invalid("Remote desconhecido ou não suportado"));
    }
    let base = mount_base()?;
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&base)?;
    match std::fs::DirBuilder::new().mode(0o700).create(&mp) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(e),
    }
    // Só monta sobre pasta vazia que seja uma pasta de verdade (nunca um link)
    let meta = std::fs::symlink_metadata(&mp)?;
    if !meta.is_dir() || std::fs::read_dir(&mp)?.next().is_some() {
        return Err(invalid("Ponto de montagem ocupado"));
    }

    let mut child = Command::new("rclone")
        .arg("mount")
        .arg(format!("{name}:"))
        .arg(&mp)
        .args(["--read-only", "--daemon", "--vfs-cache-mode", "off", "--dir-cache-time", "5m"])
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    let started = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait()? {
            break s;
        }
        if started.elapsed() > MOUNT_TIMEOUT {
            let _ = child.kill();
            let _ = child.wait();
            return Err(io::Error::new(io::ErrorKind::TimedOut, "Tempo esgotado ao montar"));
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    if !status.success() {
        let _ = std::fs::remove_dir(&mp);
        return Err(io::Error::other("O rclone não conseguiu montar"));
    }
    // O modo daemon volta quando o mount sobe; confere antes de entrar na pasta
    let started = Instant::now();
    while !is_mounted(&mp) {
        if started.elapsed() > Duration::from_secs(10) {
            let _ = std::fs::remove_dir(&mp);
            return Err(io::Error::other("A montagem não apareceu"));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Ok(mp)
}

/// Desmonta uma nuvem que o próprio Kappa montou (só na pasta própria)
pub fn unmount(name: &str) -> io::Result<()> {
    let mp = mount_point(name)?;
    if !is_mounted(&mp) {
        return Ok(());
    }
    let ok = ["fusermount3", "fusermount"].iter().any(|bin| {
        Command::new(bin)
            .arg("-u")
            .arg(&mp)
            .stdin(Stdio::null())
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
    });
    if !ok {
        return Err(io::Error::other("Não foi possível desmontar (arquivos em uso?)"));
    }
    let _ = std::fs::remove_dir(&mp);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remote_names_cannot_become_options_or_paths() {
        for bad in ["", "-x", "--config", "a/b", "../x", "a:b", "a b", "a\n", "é", &"x".repeat(65)] {
            assert!(validate_remote_name(bad).is_err(), "deveria rejeitar {bad:?}");
        }
        for ok in ["gdrive", "my-drive_2", "OneDrive"] {
            assert!(validate_remote_name(ok).is_ok(), "deveria aceitar {ok:?}");
        }
    }

    #[test]
    fn only_drive_and_onedrive_remotes_are_listed() {
        let text = "gdrive: drive\nwork:  onedrive\nbackup: s3\n--evil: drive\nspace name: drive\nnocolon\n";
        assert_eq!(
            parse_remotes(text),
            vec![("gdrive".to_string(), "drive".to_string()), ("work".to_string(), "onedrive".to_string())]
        );
    }

    #[test]
    fn mount_points_stay_inside_the_kappa_cloud_folder() {
        let mp = mount_point("gdrive").unwrap();
        assert!(mp.ends_with("kappa/cloud/gdrive"));
        assert!(mount_point("../etc").is_err());
    }
}
