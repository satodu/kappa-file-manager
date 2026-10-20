use std::io::{Read, Write};
use std::os::unix::fs::OpenOptionsExt;
use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use serde_json::json;
use walkdir::WalkDir;

use super::file_ops::FileOperations;

const CHUNK: usize = 1024 * 1024;
const EMIT_EVERY: Duration = Duration::from_millis(100);

#[derive(Clone, Copy, PartialEq, Eq)]
pub enum TransferMode {
    Copy,
    Move,
}

/// Cópia/movimentação em lote que emite eventos JSON (um por linha) no stdout:
/// `start`, `progress`, `done` e `error`. Alimenta o cartão de progresso do Kappa.
pub struct Transfer {
    mode: TransferMode,
    total: u64,
    done: u64,
    items: usize,
    index: usize,
    name: String,
    dest: PathBuf,
    started: Instant,
    last_emit: Instant,
}

trait ModeBits {
    fn mode_bits(&self) -> u32;
}

impl ModeBits for std::fs::Permissions {
    fn mode_bits(&self) -> u32 {
        std::os::unix::fs::PermissionsExt::mode(self) & 0o7777
    }
}

pub(crate) fn emit(value: serde_json::Value) {
    let mut out = std::io::stdout().lock();
    let _ = writeln!(out, "{}", value);
    let _ = out.flush();
}

fn tree_size(path: &Path) -> u64 {
    WalkDir::new(path)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .filter_map(|e| e.metadata().ok())
        .map(|m| m.len())
        .sum()
}

impl Transfer {
    pub fn run(mode: TransferMode, sources: &[PathBuf], dst_dir: &Path) -> std::io::Result<Vec<PathBuf>> {
        std::fs::create_dir_all(dst_dir)?;
        for src in sources {
            if !src.exists() {
                return Err(std::io::Error::new(std::io::ErrorKind::NotFound, format!("Origem não encontrada: {}", src.display())));
            }
            FileOperations::ensure_not_into_self(src, dst_dir)?;
        }

        let total: u64 = sources
            .iter()
            .map(|s| match std::fs::symlink_metadata(s) {
                Ok(m) if m.is_dir() => tree_size(s),
                Ok(m) if m.is_file() => m.len(),
                _ => 0,
            })
            .sum();
        let now = Instant::now();
        let mut t = Transfer {
            mode,
            total,
            done: 0,
            items: sources.len(),
            index: 0,
            name: String::new(),
            dest: dst_dir.to_path_buf(),
            started: now,
            last_emit: now - EMIT_EVERY,
        };

        emit(json!({
            "event": "start",
            "mode": if mode == TransferMode::Copy { "copy" } else { "move" },
            "total": total,
            "items": sources.len(),
            "dest": dst_dir,
        }));

        let mut results = Vec::new();
        for (i, src) in sources.iter().enumerate() {
            t.index = i;
            let file_name = src.file_name().ok_or_else(|| std::io::Error::new(std::io::ErrorKind::InvalidInput, "Nome de arquivo inválido"))?;
            t.name = file_name.to_string_lossy().to_string();
            let is_real_dir = std::fs::symlink_metadata(src).map(|m| m.is_dir()).unwrap_or(false);
            let target = FileOperations::find_unique_target_path(dst_dir, file_name, is_real_dir);
            t.dest = target.clone();
            t.progress(true);
            t.transfer_one(src, &target)?;
            results.push(target);
        }

        t.progress(true);
        emit(json!({
            "event": "done",
            "paths": results,
            "bytes": t.done,
            "seconds": t.started.elapsed().as_secs_f64(),
        }));
        Ok(results)
    }

    fn progress(&mut self, force: bool) {
        if !force && self.last_emit.elapsed() < EMIT_EVERY {
            return;
        }
        self.last_emit = Instant::now();
        let secs = self.started.elapsed().as_secs_f64().max(0.001);
        emit(json!({
            "event": "progress",
            "done": self.done,
            "total": self.total,
            "index": self.index,
            "items": self.items,
            "name": self.name,
            "dest": self.dest,
            "speed": (self.done as f64 / secs) as u64,
        }));
    }

    fn transfer_one(&mut self, src: &Path, target: &Path) -> std::io::Result<()> {
        if self.mode == TransferMode::Move {
            // Mesmo sistema de arquivos: renomear é instantâneo
            // Sem sobrescrever: se alguém criou `target` entre a escolha do nome e agora, o rename falha e cai na cópia
            if super::file_ops::rename_no_replace(src, target).is_ok() {
                self.done += if target.is_dir() { tree_size(target) } else { target.metadata().map(|m| m.len()).unwrap_or(0) };
                return Ok(());
            }
        }

        let ty = std::fs::symlink_metadata(src)?.file_type();
        if ty.is_symlink() {
            // Links são recriados como links, nunca seguidos (evita copiar o que está fora da árvore)
            std::os::unix::fs::symlink(std::fs::read_link(src)?, target)?;
        } else if ty.is_dir() {
            self.copy_dir(src, target)?;
        } else if ty.is_file() {
            self.copy_file(src, target)?;
        } else {
            return Err(std::io::Error::new(std::io::ErrorKind::InvalidInput, "Tipo de arquivo não suportado (pipe, socket ou dispositivo)"));
        }

        if self.mode == TransferMode::Move {
            if ty.is_dir() {
                std::fs::remove_dir_all(src)?;
            } else {
                std::fs::remove_file(src)?;
            }
        }
        Ok(())
    }

    fn copy_dir(&mut self, src: &Path, dst: &Path) -> std::io::Result<()> {
        // A pasta nasce privada (0700) e só recebe as permissões da origem depois de copiar o conteúdo:
        // assim uma pasta 0700 nunca fica visível a outros durante nem depois da cópia
        std::os::unix::fs::DirBuilderExt::mode(&mut std::fs::DirBuilder::new(), 0o700).create(dst)?;
        let src_mode = std::fs::symlink_metadata(src)?.permissions().mode_bits() & 0o777;
        for entry in std::fs::read_dir(src)? {
            let entry = entry?;
            let ty = entry.file_type()?;
            let child_dst = dst.join(entry.file_name());
            if ty.is_symlink() {
                let link = std::fs::read_link(entry.path())?;
                std::os::unix::fs::symlink(link, &child_dst)?;
            } else if ty.is_dir() {
                self.copy_dir(&entry.path(), &child_dst)?;
            } else if ty.is_file() {
                self.copy_file(&entry.path(), &child_dst)?;
            }
            // pipes, sockets e dispositivos são ignorados: abrir um pipe travaria a cópia
        }
        // Nunca copia setuid/setgid/sticky; o dono continua podendo entrar na pasta
        std::fs::set_permissions(dst, std::os::unix::fs::PermissionsExt::from_mode(src_mode | 0o700))?;
        if src_mode & 0o700 != 0o700 {
            // permissões restritivas da origem (ex.: 0500) são aplicadas por último
            std::fs::set_permissions(dst, std::os::unix::fs::PermissionsExt::from_mode(src_mode))?;
        }
        Ok(())
    }

    fn copy_file(&mut self, src: &Path, dst: &Path) -> std::io::Result<()> {
        // O_NOFOLLOW: se a origem virou um link simbólico depois da checagem, a abertura falha em vez de segui-lo
        let mut reader = std::fs::OpenOptions::new().read(true).custom_flags(libc::O_NOFOLLOW).open(src)?;
        // Cria já com as permissões da origem (sujeitas ao umask), sem janela de arquivo exposto
        let mode = reader.metadata()?.permissions().mode_bits() & 0o777;
        let mut writer = std::fs::OpenOptions::new().write(true).create_new(true).mode(mode).open(dst)?;
        let mut buf = vec![0u8; CHUNK];
        loop {
            let n = reader.read(&mut buf)?;
            if n == 0 {
                break;
            }
            writer.write_all(&buf[..n])?;
            self.done += n as u64;
            self.progress(false);
        }
        writer.flush()?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kappa-transfer-{}-{}", name, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn copies_file_and_tree_with_unique_names() {
        let root = scratch("copy");
        let dst = root.join("dst");
        std::fs::create_dir_all(root.join("tree/inner")).unwrap();
        std::fs::write(root.join("tree/inner/a.txt"), "hello").unwrap();
        std::fs::write(root.join("f.txt"), "data").unwrap();

        let out = Transfer::run(TransferMode::Copy, &[root.join("f.txt"), root.join("tree")], &dst).unwrap();
        assert_eq!(out.len(), 2);
        assert_eq!(std::fs::read_to_string(dst.join("tree/inner/a.txt")).unwrap(), "hello");

        let again = Transfer::run(TransferMode::Copy, &[root.join("f.txt")], &dst).unwrap();
        assert!(again[0].ends_with("f (1).txt"));
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn move_removes_source_and_refuses_folder_into_itself() {
        let root = scratch("move");
        std::fs::create_dir_all(root.join("d")).unwrap();
        std::fs::write(root.join("d/x"), "1").unwrap();
        assert!(Transfer::run(TransferMode::Move, &[root.join("d")], &root.join("d")).is_err());

        let dst = root.join("out");
        Transfer::run(TransferMode::Move, &[root.join("d")], &dst).unwrap();
        assert!(!root.join("d").exists());
        assert!(dst.join("d/x").exists());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn symlinks_are_copied_as_links_and_pipes_are_skipped() {
        let root = scratch("links");
        let dst = root.join("dst");
        std::fs::create_dir_all(root.join("outside")).unwrap();
        std::fs::write(root.join("outside/secret"), "s").unwrap();
        std::fs::create_dir_all(root.join("tree")).unwrap();
        std::os::unix::fs::symlink(root.join("outside"), root.join("tree/link")).unwrap();
        std::process::Command::new("mkfifo").arg(root.join("tree/pipe")).status().unwrap();

        Transfer::run(TransferMode::Copy, &[root.join("tree")], &dst).unwrap();
        let copied = dst.join("tree/link");
        assert!(std::fs::symlink_metadata(&copied).unwrap().file_type().is_symlink());
        assert!(!dst.join("tree/pipe").exists());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn copied_folders_keep_private_modes_and_drop_special_bits() {
        use std::os::unix::fs::PermissionsExt;
        let root = scratch("modes");
        let dst = root.join("dst");
        std::fs::create_dir_all(root.join("ssh")).unwrap();
        std::fs::write(root.join("ssh/key"), "k").unwrap();
        std::fs::write(root.join("ssh/pub"), "p").unwrap();
        std::fs::set_permissions(root.join("ssh/key"), std::fs::Permissions::from_mode(0o600)).unwrap();
        std::fs::set_permissions(root.join("ssh/pub"), std::fs::Permissions::from_mode(0o4755)).unwrap();
        std::fs::set_permissions(root.join("ssh"), std::fs::Permissions::from_mode(0o700)).unwrap();

        Transfer::run(TransferMode::Copy, &[root.join("ssh")], &dst).unwrap();
        let mode = |p: &str| std::fs::metadata(dst.join(p)).unwrap().permissions().mode() & 0o7777;
        assert_eq!(mode("ssh"), 0o700, "pasta privada continua privada");
        assert_eq!(mode("ssh/key"), 0o600);
        assert_eq!(mode("ssh/pub") & 0o7000, 0, "setuid não é copiado");
        let _ = std::fs::remove_dir_all(&root);
    }
}
