use std::path::{Path, PathBuf};
use std::process::Command;

#[allow(dead_code)]
pub struct FileOperations;

#[allow(dead_code)]
impl FileOperations {
    /// Abre o arquivo ou pasta usando o aplicativo padrão do sistema (xdg-open)
    pub fn open_default(path: impl AsRef<Path>) -> std::io::Result<()> {
        let p = path.as_ref();
        // Um nome começando com "-" seria lido como opção pelo xdg-open
        let safe: PathBuf = if p.to_string_lossy().starts_with('-') { Path::new(".").join(p) } else { p.to_path_buf() };
        Command::new("xdg-open")
            .arg(&safe)
            .spawn()?
            .wait()?;
        Ok(())
    }

    /// Move o item para a lixeira seguindo o FreeDesktop Trash spec
    pub fn move_to_trash(path: impl AsRef<Path>) -> Result<(), trash::Error> {
        trash::delete(path)
    }

    /// Remove o item definitivamente do disco (sem passar pela lixeira)
    pub fn delete_permanently(path: impl AsRef<Path>) -> std::io::Result<()> {
        let p = path.as_ref();
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
        if !parent_path.exists() {
            std::fs::create_dir_all(parent_path)?;
        }
        let target = Self::find_unique_target_path(parent_path, std::ffi::OsStr::new(folder_name), true);
        std::fs::create_dir_all(&target)?;
        Ok(target)
    }

    /// Renomeia um arquivo ou pasta
    pub fn rename_item(old_path: impl AsRef<Path>, new_name: &str) -> std::io::Result<PathBuf> {
        let old = old_path.as_ref();
        let parent = old.parent().unwrap_or_else(|| Path::new("/"));
        let new_path = parent.join(new_name);
        std::fs::rename(old, &new_path)?;
        Ok(new_path)
    }

    /// Copia um arquivo ou diretório recursivamente para a pasta de destino
    pub fn copy_item(source: impl AsRef<Path>, target_dir: impl AsRef<Path>) -> std::io::Result<PathBuf> {
        let src = source.as_ref();
        let dst_dir = target_dir.as_ref();

        if !src.exists() {
            return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "Arquivo ou pasta de origem não encontrado"));
        }
        if !dst_dir.exists() {
            std::fs::create_dir_all(dst_dir)?;
        }
        Self::ensure_not_into_self(src, dst_dir)?;

        let file_name = src.file_name().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, "Nome de arquivo inválido")
        })?;

        let dest_path = Self::find_unique_target_path(dst_dir, file_name, src.is_dir());

        if src.is_dir() {
            Self::copy_dir_recursive(src, &dest_path)?;
        } else {
            std::fs::copy(src, &dest_path)?;
        }

        Ok(dest_path)
    }

    /// Move um arquivo ou diretório para a pasta de destino
    pub fn move_item(source: impl AsRef<Path>, target_dir: impl AsRef<Path>) -> std::io::Result<PathBuf> {
        let src = source.as_ref();
        let dst_dir = target_dir.as_ref();

        if !src.exists() {
            return Err(std::io::Error::new(std::io::ErrorKind::NotFound, "Arquivo ou pasta de origem não encontrado"));
        }
        if !dst_dir.exists() {
            std::fs::create_dir_all(dst_dir)?;
        }
        Self::ensure_not_into_self(src, dst_dir)?;

        let file_name = src.file_name().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::InvalidInput, "Nome de arquivo inválido")
        })?;

        let dest_path = Self::find_unique_target_path(dst_dir, file_name, src.is_dir());

        if src == dest_path {
            return Ok(dest_path);
        }

        match std::fs::rename(src, &dest_path) {
            Ok(_) => Ok(dest_path),
            Err(_) => {
                // Se falhar (ex: partições diferentes / EXDEV), copia e remove original
                if src.is_dir() {
                    Self::copy_dir_recursive(src, &dest_path)?;
                    let _ = std::fs::remove_dir_all(src);
                } else {
                    std::fs::copy(src, &dest_path)?;
                    let _ = std::fs::remove_file(src);
                }
                Ok(dest_path)
            }
        }
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

    fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
        std::fs::create_dir_all(dst)?;
        for entry in std::fs::read_dir(src)? {
            let entry = entry?;
            let ty = entry.file_type()?;
            let child_dst = dst.join(entry.file_name());
            if ty.is_dir() {
                Self::copy_dir_recursive(&entry.path(), &child_dst)?;
            } else {
                std::fs::copy(entry.path(), child_dst)?;
            }
        }
        Ok(())
    }

    /// Compartilha arquivo via KDE Connect
    pub fn kde_share(device_id: &str, file_path: impl AsRef<Path>) -> std::io::Result<()> {
        let p = file_path.as_ref();
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
        let _ = Command::new("udisksctl")
            .arg("unmount")
            .arg("-b")
            .arg(device_or_path)
            .output();
        Ok(())
    }
}
