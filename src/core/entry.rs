use std::path::{Path, PathBuf};
use std::time::SystemTime;
use chrono::{DateTime, Local, Datelike};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum FileKind {
    Folder,
    Document,
    Image,
    Audio,
    Video,
    Code,
    Archive,
    Executable,
    Other,
}

impl FileKind {
    pub fn from_mime_and_path(mime: &str, path: &Path, is_dir: bool) -> Self {
        if is_dir {
            return FileKind::Folder;
        }

        if mime.starts_with("image/") {
            return FileKind::Image;
        }
        if mime.starts_with("audio/") {
            return FileKind::Audio;
        }
        if mime.starts_with("video/") {
            return FileKind::Video;
        }

        // Extensões de código / scripts
        if let Some(ext) = path.extension().and_then(|s| s.to_str()).map(|s| s.to_lowercase()) {
            match ext.as_str() {
                "rs" | "qml" | "js" | "mjs" | "ts" | "py" | "c" | "cpp" | "h" | "hpp" | "sh" | "bash"
                | "zsh" | "fish" | "json" | "toml" | "yaml" | "yml" | "html" | "css" | "scss" => {
                    return FileKind::Code;
                }
                "zip" | "tar" | "gz" | "xz" | "bz2" | "7z" | "rar" | "zst" | "figcraft" => {
                    return FileKind::Archive;
                }
                "pdf" | "md" | "txt" | "doc" | "docx" | "odt" | "rtf" => {
                    return FileKind::Document;
                }
                _ => {}
            }
        }

        if mime.starts_with("text/") {
            return FileKind::Document;
        }

        FileKind::Other
    }

    pub fn icon_name(&self) -> &'static str {
        match self {
            FileKind::Folder => "folder",
            FileKind::Document => "doc",
            FileKind::Image => "img",
            FileKind::Audio => "music",
            FileKind::Video => "video",
            FileKind::Code => "code",
            FileKind::Archive => "archive",
            FileKind::Executable => "executable",
            FileKind::Other => "file",
        }
    }

    #[allow(dead_code)]
    pub fn as_str(&self) -> &'static str {
        match self {
            FileKind::Folder => "folder",
            FileKind::Document => "document",
            FileKind::Image => "image",
            FileKind::Audio => "audio",
            FileKind::Video => "video",
            FileKind::Code => "code",
            FileKind::Archive => "archive",
            FileKind::Executable => "executable",
            FileKind::Other => "other",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileEntry {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
    pub is_symlink: bool,
    /// Arquivo comum (não é pasta, pipe, socket nem dispositivo): só esses podem ter miniatura ou ser lidos
    pub is_regular: bool,
    pub is_hidden: bool,
    pub size_bytes: u64,
    pub size_formatted: String,
    pub modified_timestamp: i64,
    pub modified_formatted: String,
    pub mime_type: String,
    pub kind: FileKind,
    pub icon_name: String,
}

impl FileEntry {
    pub fn from_path(path: impl AsRef<Path>) -> std::io::Result<Self> {
        let path = path.as_ref().to_path_buf();
        let symlink_meta = std::fs::symlink_metadata(&path)?;
        let is_symlink = symlink_meta.file_type().is_symlink();

        // Se for symlink, tenta obter metadata do destino, senão usa symlink_meta
        let meta = if is_symlink {
            std::fs::metadata(&path).unwrap_or_else(|_| symlink_meta.clone())
        } else {
            symlink_meta
        };

        let is_dir = meta.is_dir();
        let name = path
            .file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| path.to_string_lossy().to_string());

        let is_hidden = name.starts_with('.');
        let size_bytes = if is_dir { 0 } else { meta.len() };
        let size_formatted = if is_dir {
            "—".to_string()
        } else {
            format_file_size(size_bytes)
        };

        let modified_time = meta.modified().unwrap_or(SystemTime::UNIX_EPOCH);
        let modified_timestamp = modified_time
            .duration_since(SystemTime::UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0);

        let modified_formatted = format_date(modified_time);

        let mime_type = if is_dir {
            "inode/directory".to_string()
        } else {
            mime_guess::from_path(&path)
                .first_or_octet_stream()
                .to_string()
        };

        let kind = FileKind::from_mime_and_path(&mime_type, &path, is_dir);
        let icon_name = kind.icon_name().to_string();

        Ok(Self {
            name,
            path,
            is_dir,
            is_symlink,
            is_regular: meta.is_file(),
            is_hidden,
            size_bytes,
            size_formatted,
            modified_timestamp,
            modified_formatted,
            mime_type,
            kind,
            icon_name,
        })
    }
}

/// Formata tamanhos no estilo exibido no design do Ryoku ("2,1 KB", "17,9 KB", "4,2 MB")
pub fn format_file_size(bytes: u64) -> String {
    const KB: f64 = 1024.0;
    const MB: f64 = KB * 1024.0;
    const GB: f64 = MB * 1024.0;
    const TB: f64 = GB * 1024.0;

    let b = bytes as f64;
    if b < KB {
        format!("{} B", bytes)
    } else if b < MB {
        format!("{:.1} KB", b / KB).replace('.', ",")
    } else if b < GB {
        format!("{:.1} MB", b / MB).replace('.', ",")
    } else if b < TB {
        format!("{:.1} GB", b / GB).replace('.', ",")
    } else {
        format!("{:.1} TB", b / TB).replace('.', ",")
    }
}

/// Formata datas no estilo do design respeitando o idioma do sistema/Ryoku
pub fn format_date(time: SystemTime) -> String {
    let dt: DateTime<Local> = time.into();

    // Checa idioma do Ryoku em ~/.config/ryoku/shell.json ou LANG
    let is_english = std::fs::read_to_string(dirs::home_dir().map(|h| h.join(".config/ryoku/shell.json")).unwrap_or_default())
        .ok()
        .and_then(|s| serde_json::from_str::<serde_json::Value>(&s).ok())
        .and_then(|j| j.get("language").and_then(|l| l.as_str().map(|s| s == "en")))
        .unwrap_or_else(|| {
            std::env::var("LANG").map(|l| l.starts_with("en")).unwrap_or(false)
        });

    let month_str = if is_english {
        match dt.month() {
            1 => "Jan",
            2 => "Feb",
            3 => "Mar",
            4 => "Apr",
            5 => "May",
            6 => "Jun",
            7 => "Jul",
            8 => "Aug",
            9 => "Sep",
            10 => "Oct",
            11 => "Nov",
            12 => "Dec",
            _ => "???",
        }
    } else {
        match dt.month() {
            1 => "jan",
            2 => "fev",
            3 => "mar",
            4 => "abr",
            5 => "mai",
            6 => "jun",
            7 => "jul",
            8 => "ago",
            9 => "set",
            10 => "out",
            11 => "nov",
            12 => "dez",
            _ => "???",
        }
    };

    format!("{:02} {} {}", dt.day(), month_str, dt.year())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_format_file_size() {
        assert_eq!(format_file_size(500), "500 B");
        assert_eq!(format_file_size(2150), "2,1 KB");
        assert_eq!(format_file_size(18329), "17,9 KB");
        assert_eq!(format_file_size(4404019), "4,2 MB");
    }

    #[test]
    fn test_file_kind() {
        let qml_path = Path::new("/test/Tokens.qml");
        assert_eq!(
            FileKind::from_mime_and_path("text/plain", qml_path, false),
            FileKind::Code
        );

        let img_path = Path::new("/test/wallpaper.png");
        assert_eq!(
            FileKind::from_mime_and_path("image/png", img_path, false),
            FileKind::Image
        );

        let dir_path = Path::new("/test/projects");
        assert_eq!(
            FileKind::from_mime_and_path("inode/directory", dir_path, true),
            FileKind::Folder
        );
    }
}
