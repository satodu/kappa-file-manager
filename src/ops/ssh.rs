//! Servidores SSH (SFTP) via `sshfs`: o Kappa só monta/desmonta e guarda a lista de alvos
//! (`usuario@host[:porta]`) em `~/.config/kappa/servers.json`. Chaves, `ssh-agent`, `~/.ssh/config` e
//! `known_hosts` ficam com o OpenSSH. A senha, quando usada, vem pelo stdin do Kappa e vai direto
//! ao stdin do `sshfs` (`password_stdin`): nunca em argumento, arquivo, log nem na lista salva.
//! Host desconhecido é recusado (`StrictHostKeyChecking=yes`); apagar sempre passa pela confirmação permanente.

use std::io::{self, Read, Write};
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use serde_json::json;

use super::cloud::{is_mounted, runtime_dir};

const MOUNT_TIMEOUT: Duration = Duration::from_secs(30);
const MAX_SERVERS: usize = 32;
const MAX_PASSWORD: usize = 1024;

fn invalid(msg: &str) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidInput, msg.to_string())
}

/// Alvo já validado. Só letras, números, `.`, `_` e `-`: nunca vira opção do ssh nem caminho
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Target {
    user: String,
    host: String,
    port: u16,
}

impl Target {
    /// Forma canônica (`usuario@host` ou `usuario@host:porta`): também é o nome da pasta de montagem
    pub fn canonical(&self) -> String {
        if self.port == 22 { format!("{}@{}", self.user, self.host) } else { format!("{}@{}:{}", self.user, self.host, self.port) }
    }
}

fn edge_ok(s: &str) -> bool {
    let b = s.as_bytes();
    b.first().is_some_and(u8::is_ascii_alphanumeric) && b.last().is_some_and(u8::is_ascii_alphanumeric)
}

pub fn parse_target(text: &str) -> io::Result<Target> {
    let (user, rest) = text.split_once('@').ok_or_else(|| invalid("Use o formato usuario@host"))?;
    let (host, port) = match rest.split_once(':') {
        Some((h, p)) => {
            let port: u16 = p.parse().map_err(|_| invalid("Porta inválida"))?;
            if port == 0 || p.len() > 5 || !p.bytes().all(|c| c.is_ascii_digit()) {
                return Err(invalid("Porta inválida"));
            }
            (h, port)
        }
        None => (rest, 22),
    };
    let user_ok = !user.is_empty()
        && user.len() <= 64
        && edge_ok(user)
        && user.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'_' | b'-'));
    let host_ok = !host.is_empty()
        && host.len() <= 253
        && edge_ok(host)
        && !host.contains("..")
        && host.bytes().all(|c| c.is_ascii_alphanumeric() || matches!(c, b'.' | b'-'));
    if !user_ok {
        return Err(invalid("Usuário inválido"));
    }
    if !host_ok {
        return Err(invalid("Host inválido (use nome ou IPv4)"));
    }
    Ok(Target { user: user.to_string(), host: host.to_string(), port })
}

fn mount_base() -> io::Result<PathBuf> {
    Ok(runtime_dir()?.join("ssh"))
}

/// O caminho está dentro de um servidor montado pelo Kappa? (comparação léxica; caminhos da CLI já são absolutos)
pub fn is_ssh_path(path: &Path) -> bool {
    mount_base().map(|b| path.starts_with(&b)).unwrap_or(false)
}

fn mount_point(t: &Target) -> io::Result<PathBuf> {
    Ok(mount_base()?.join(t.canonical()))
}

fn servers_file() -> io::Result<PathBuf> {
    Ok(super::integration::config_dir()?.join("servers.json"))
}

/// Lê a lista salva: só alvos válidos, sem repetição, até `MAX_SERVERS`
pub fn parse_servers(text: &str) -> Vec<Target> {
    let value: serde_json::Value = serde_json::from_str(text).unwrap_or_default();
    let mut out: Vec<Target> = Vec::new();
    for item in value.get("servers").and_then(|v| v.as_array()).into_iter().flatten() {
        if let Some(t) = item.as_str().and_then(|s| parse_target(s).ok()) {
            if !out.contains(&t) && out.len() < MAX_SERVERS {
                out.push(t);
            }
        }
    }
    out
}

fn load_servers() -> Vec<Target> {
    servers_file().ok().and_then(|p| std::fs::read_to_string(p).ok()).map(|t| parse_servers(&t)).unwrap_or_default()
}

fn save_servers(list: &[Target]) -> io::Result<()> {
    let file = servers_file()?;
    let dir = file.parent().ok_or_else(|| invalid("Pasta de configuração inválida"))?;
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(dir)?;
    let body = json!({ "servers": list.iter().map(Target::canonical).collect::<Vec<_>>() }).to_string();
    let tmp = file.with_extension("json.tmp");
    let mut f = std::fs::OpenOptions::new().write(true).create(true).truncate(true).mode(0o600).open(&tmp)?;
    f.write_all(body.as_bytes())?;
    f.sync_all()?;
    std::fs::rename(&tmp, &file)
}

fn sshfs_available() -> bool {
    std::env::var_os("PATH").is_some_and(|paths| std::env::split_paths(&paths).any(|d| d.join("sshfs").is_file()))
}

/// Servidores salvos e se estão montados. `available: false` quando o `sshfs` não está instalado.
pub fn list() -> serde_json::Value {
    let servers: Vec<_> = load_servers()
        .iter()
        .map(|t| {
            let mp = mount_point(t).ok();
            let mounted = mp.as_deref().map(is_mounted).unwrap_or(false);
            json!({
                "name": t.canonical(), "type": "ssh", "mounted": mounted, "path": mp.filter(|_| mounted),
            })
        })
        .collect();
    json!({ "ok": true, "available": sshfs_available(), "servers": servers })
}

/// Classe do erro, sem repassar o texto cru do servidor para a interface
pub fn classify_error(stderr: &str) -> &'static str {
    let s = stderr.to_ascii_lowercase();
    if s.contains("host key verification failed") || s.contains("remote host identification has changed") {
        "HostKey"
    } else if s.contains("permission denied") || s.contains("authentication") {
        "Auth"
    } else if s.contains("connection refused")
        || s.contains("timed out")
        || s.contains("no route to host")
        || s.contains("could not resolve")
        || s.contains("network is unreachable")
    {
        "Network"
    } else {
        "Other"
    }
}

/// Senha de uma linha do stdin (sem a quebra de linha); vazia significa "só chave/agent"
pub fn read_password(mut input: impl Read) -> io::Result<String> {
    let mut buf = Vec::new();
    let mut byte = [0u8; 1];
    while input.read(&mut byte)? == 1 {
        if byte[0] == b'\n' {
            break;
        }
        if buf.len() >= MAX_PASSWORD {
            return Err(invalid("Senha longa demais"));
        }
        buf.push(byte[0]);
    }
    if buf.last() == Some(&b'\r') {
        buf.pop();
    }
    if buf.contains(&0) {
        return Err(invalid("Senha inválida"));
    }
    String::from_utf8(buf).map_err(|_| invalid("Senha inválida"))
}

/// O `sshfs` esconde o erro do `ssh` (só "Connection reset"): repete a conexão com o `ssh` em modo
/// não interativo só para descobrir a causa (host desconhecido, login recusado, rede)
fn diagnose(t: &Target) -> &'static str {
    let out = Command::new("ssh")
        .args(["-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=8", "-p"])
        .arg(t.port.to_string())
        .arg("--")
        .arg(format!("{}@{}", t.user, t.host))
        .arg("true")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output();
    match out {
        Ok(o) => classify_error(&String::from_utf8_lossy(&o.stderr[..o.stderr.len().min(8192)])),
        Err(_) => "Other",
    }
}

pub struct MountError {
    pub kind: &'static str,
    pub message: String,
}

fn fail(kind: &'static str, message: &str) -> MountError {
    MountError { kind, message: message.to_string() }
}

/// Monta a home do servidor. Com `password`, usa `password_stdin`; sem ela, `BatchMode` (nunca fica esperando).
pub fn mount(target: &str, password: &str) -> Result<PathBuf, MountError> {
    let t = parse_target(target).map_err(|e| fail("Invalid", &e.to_string()))?;
    if !sshfs_available() {
        return Err(fail("Missing", "sshfs não está instalado"));
    }
    let io_err = |e: io::Error| fail("Other", &e.to_string());
    let mp = mount_point(&t).map_err(io_err)?;
    if is_mounted(&mp) {
        return Ok(mp);
    }
    let base = mount_base().map_err(io_err)?;
    std::fs::DirBuilder::new().recursive(true).mode(0o700).create(&base).map_err(io_err)?;
    match std::fs::DirBuilder::new().mode(0o700).create(&mp) {
        Ok(()) => {}
        Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(io_err(e)),
    }
    // Só monta sobre pasta vazia que seja uma pasta de verdade (nunca um link)
    let meta = std::fs::symlink_metadata(&mp).map_err(io_err)?;
    if !meta.is_dir() || std::fs::read_dir(&mp).map_err(io_err)?.next().is_some() {
        return Err(fail("Other", "Ponto de montagem ocupado"));
    }

    let mut cmd = Command::new("sshfs");
    cmd.arg(format!("{}@{}:", t.user, t.host)).arg(&mp).arg("-p").arg(t.port.to_string());
    for opt in [
        "reconnect",
        "ServerAliveInterval=15",
        "ServerAliveCountMax=3",
        "ConnectTimeout=10",
        "StrictHostKeyChecking=yes",
        "NumberOfPasswordPrompts=1",
        "umask=077",
        "idmap=user",
    ] {
        cmd.arg("-o").arg(opt);
    }
    if password.is_empty() {
        cmd.arg("-o").arg("BatchMode=yes").stdin(Stdio::null());
    } else {
        cmd.arg("-o").arg("password_stdin").stdin(Stdio::piped());
    }
    cmd.stdout(Stdio::null()).stderr(Stdio::null());
    let mut child = cmd.spawn().map_err(io_err)?;
    if !password.is_empty() {
        if let Some(mut stdin) = child.stdin.take() {
            let _ = stdin.write_all(password.as_bytes());
            let _ = stdin.write_all(b"\n");
        }
    }
    let started = Instant::now();
    let status = loop {
        if let Some(s) = child.try_wait().map_err(io_err)? {
            break s;
        }
        if started.elapsed() > MOUNT_TIMEOUT {
            let _ = child.kill();
            let _ = child.wait();
            let _ = std::fs::remove_dir(&mp);
            return Err(fail("Network", "Tempo esgotado ao conectar"));
        }
        std::thread::sleep(Duration::from_millis(100));
    };
    if !status.success() {
        let _ = std::fs::remove_dir(&mp);
        return Err(fail(diagnose(&t), "O sshfs não conseguiu conectar"));
    }
    let started = Instant::now();
    while !is_mounted(&mp) {
        if started.elapsed() > Duration::from_secs(10) {
            let _ = std::fs::remove_dir(&mp);
            return Err(fail("Other", "A montagem não apareceu"));
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    // Conectou: lembra só o alvo (nunca a senha)
    let mut saved = load_servers();
    if !saved.contains(&t) && saved.len() < MAX_SERVERS {
        saved.push(t);
        let _ = save_servers(&saved);
    }
    Ok(mp)
}

/// Desmonta um servidor que o próprio Kappa montou (só na pasta própria)
pub fn unmount(target: &str) -> io::Result<()> {
    let t = parse_target(target)?;
    let mp = mount_point(&t)?;
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

/// Tira o servidor da lista salva (recusa enquanto estiver montado, para não deixar montagem órfã)
pub fn forget(target: &str) -> io::Result<()> {
    let t = parse_target(target)?;
    if is_mounted(&mount_point(&t)?) {
        return Err(invalid("Desmonte o servidor antes de esquecê-lo"));
    }
    let list: Vec<Target> = load_servers().into_iter().filter(|s| *s != t).collect();
    save_servers(&list)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn targets_are_canonical_and_default_port_is_dropped() {
        assert_eq!(parse_target("panda@192.168.0.14").unwrap().canonical(), "panda@192.168.0.14");
        assert_eq!(parse_target("panda@192.168.0.14:22").unwrap().canonical(), "panda@192.168.0.14");
        assert_eq!(parse_target("a.b-c@home-lab.local:2222").unwrap().canonical(), "a.b-c@home-lab.local:2222");
    }

    #[test]
    fn targets_cannot_become_options_paths_or_commands() {
        for bad in [
            "", "panda", "@host", "panda@", "-oProxyCommand=x@host", "panda@-oProxyCommand=x", "pa nda@host", "panda@ho st",
            "panda@host:0", "panda@host:70000", "panda@host:22a", "panda@host:", "pan/da@host", "panda@ho/st", "../x@host",
            "panda@host..evil", "panda@.host", "panda@host.", "panda@host\n", "panda;ls@host", "panda@host;ls", "panda@[::1]",
            "panda@host:22:33", "pandá@host", "panda@ho$(id)",
        ] {
            assert!(parse_target(bad).is_err(), "deveria rejeitar {bad:?}");
        }
        assert!(parse_target(&format!("{}@host", "x".repeat(65))).is_err());
    }

    #[test]
    fn distinct_targets_never_share_a_mount_folder() {
        let a = parse_target("a.b@host").unwrap().canonical();
        let b = parse_target("a-b@host").unwrap().canonical();
        let c = parse_target("a.b@host:2222").unwrap().canonical();
        assert!(a != b && a != c && b != c);
    }

    #[test]
    fn ssh_paths_are_only_under_the_mount_base() {
        let base = mount_base().unwrap();
        assert!(is_ssh_path(&base.join("panda@host").join("a.txt")));
        assert!(!is_ssh_path(Path::new("/home/x/a.txt")));
        assert!(!is_ssh_path(&base.with_file_name("ssh-evil").join("a")));
        assert!(base.ends_with("kappa/ssh"));
    }

    #[test]
    fn saved_servers_drop_invalid_and_duplicate_entries() {
        let text = r#"{"servers":["panda@h","panda@h","-oX=1@h","bad","root@10.0.0.1:2222", 5]}"#;
        let names: Vec<_> = parse_servers(text).iter().map(Target::canonical).collect();
        assert_eq!(names, vec!["panda@h", "root@10.0.0.1:2222"]);
        assert!(parse_servers("not json").is_empty());
        let many: Vec<String> = (0..100).map(|i| format!("\"u@h{i}\"")).collect();
        assert_eq!(parse_servers(&format!("{{\"servers\":[{}]}}", many.join(","))).len(), MAX_SERVERS);
    }

    #[test]
    fn errors_are_classified_without_leaking_server_text() {
        assert_eq!(classify_error("Host key verification failed."), "HostKey");
        assert_eq!(classify_error("panda@h: Permission denied (publickey,password)."), "Auth");
        assert_eq!(classify_error("ssh: connect to host h port 22: Connection refused"), "Network");
        assert_eq!(classify_error("ssh: Could not resolve hostname x"), "Network");
        assert_eq!(classify_error("algo estranho"), "Other");
    }

    #[test]
    fn password_is_one_line_without_nul() {
        assert_eq!(read_password(&b"banana\nresto"[..]).unwrap(), "banana");
        assert_eq!(read_password(&b"banana\r\n"[..]).unwrap(), "banana");
        assert_eq!(read_password(&b""[..]).unwrap(), "");
        assert!(read_password(&b"a\0b\n"[..]).is_err());
        assert!(read_password(&vec![b'x'; MAX_PASSWORD + 1][..]).is_err());
    }
}
