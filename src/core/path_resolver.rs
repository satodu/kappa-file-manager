use std::path::{Path, PathBuf};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", content = "payload")]
pub enum PathError {
    /// O caminho não existe. Contém a pasta existente mais próxima e eventuais sugestões.
    NotFound {
        input: String,
        nearest_existing_parent: PathBuf,
        suggestion: Option<PathBuf>,
    },
    /// Sem permissão de leitura (ex: /root). Sinaliza suporte a abrir com polkit/admin.
    PermissionDenied {
        path: PathBuf,
        requires_elevation: bool,
    },
    /// O caminho digitado aponta para um arquivo comum, não para uma pasta.
    NotADirectory {
        file_path: PathBuf,
        parent_dir: PathBuf,
    },
    /// Ponto de montagem não acessível ou pendrive/dispositivo desconectado (ex: /run/media/...)
    DeviceDisconnected {
        path: PathBuf,
        device_name: String,
    },
    /// Link simbólico cujo destino não existe
    BrokenSymlink {
        symlink_path: PathBuf,
        target_path: PathBuf,
    },
    /// Caminho excede o limite POSIX de 4096 caracteres
    PathTooLong {
        length: usize,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AutocompleteSuggestion {
    pub display: String,
    pub full_path: PathBuf,
    pub is_dir: bool,
}

pub struct PathResolver;

impl PathResolver {
    /// Valida e resolve um caminho digitado pelo usuário.
    pub fn resolve(raw_input: &str) -> Result<PathBuf, PathError> {
        if raw_input.len() > 4096 {
            return Err(PathError::PathTooLong {
                length: raw_input.len(),
            });
        }

        let trimmed = raw_input.trim();
        if trimmed.is_empty() {
            let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"));
            return Ok(home);
        }

        // Expansão de ~
        let expanded = if trimmed == "~" || trimmed.starts_with("~/") {
            if let Some(home) = dirs::home_dir() {
                if trimmed == "~" {
                    home
                } else {
                    home.join(&trimmed[2..])
                }
            } else {
                PathBuf::from(trimmed)
            }
        } else {
            PathBuf::from(trimmed)
        };

        // Verifica symlink quebrado
        if let Ok(meta) = std::fs::symlink_metadata(&expanded) {
            if meta.file_type().is_symlink() {
                if let Ok(target) = std::fs::read_link(&expanded) {
                    if !expanded.exists() {
                        return Err(PathError::BrokenSymlink {
                            symlink_path: expanded,
                            target_path: target,
                        });
                    }
                }
            }
        }

        // Se o caminho não existe
        if !expanded.exists() {
            // Checa se é um caminho em /run/media/ ou /media/ que não está montado
            let path_str = expanded.to_string_lossy();
            if path_str.starts_with("/run/media/") || path_str.starts_with("/media/") {
                let parts: Vec<&str> = path_str.split('/').filter(|s| !s.is_empty()).collect();
                // /run/media/<user>/<device> -> índice 3
                // /media/<user>/<device> -> índice 2
                let dev_name = if path_str.starts_with("/run/media/") && parts.len() >= 4 {
                    parts[3].to_string()
                } else if path_str.starts_with("/media/") && parts.len() >= 3 {
                    parts[2].to_string()
                } else {
                    parts.last().unwrap_or(&"dispositivo").to_string()
                };

                return Err(PathError::DeviceDisconnected {
                    path: expanded,
                    device_name: dev_name,
                });
            }

            let nearest_parent = Self::find_nearest_existing_parent(&expanded);
            let suggestion = Self::suggest_similar_path(&expanded, &nearest_parent);

            return Err(PathError::NotFound {
                input: raw_input.to_string(),
                nearest_existing_parent: nearest_parent,
                suggestion,
            });
        }

        // Se existe, mas não é diretório
        if expanded.is_file() {
            let parent_dir = expanded
                .parent()
                .map(|p| p.to_path_buf())
                .unwrap_or_else(|| PathBuf::from("/"));

            return Err(PathError::NotADirectory {
                file_path: expanded,
                parent_dir,
            });
        }

        // Checagem de permissão de leitura
        match std::fs::read_dir(&expanded) {
            Ok(_) => Ok(expanded),
            Err(e) if e.kind() == std::io::ErrorKind::PermissionDenied => {
                Err(PathError::PermissionDenied {
                    path: expanded,
                    requires_elevation: true,
                })
            }
            Err(_e) => Err(PathError::NotFound {
                input: raw_input.to_string(),
                nearest_existing_parent: Self::find_nearest_existing_parent(&expanded),
                suggestion: None,
            }),
        }
    }

    /// Encontra a pasta pai mais próxima que realmente existe no disco
    pub fn find_nearest_existing_parent(path: &Path) -> PathBuf {
        let mut curr = path.parent();
        while let Some(p) = curr {
            if p.exists() && p.is_dir() {
                return p.to_path_buf();
            }
            curr = p.parent();
        }
        dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"))
    }

    /// Sugere um nome parecido dentro da pasta pai existente
    fn suggest_similar_path(target: &Path, parent: &Path) -> Option<PathBuf> {
        let target_name = target.file_name()?.to_str()?.to_lowercase();
        let entries = std::fs::read_dir(parent).ok()?;

        let mut best_match: Option<PathBuf> = None;
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            let lower = name.to_lowercase();
            if lower.starts_with(&target_name) || target_name.starts_with(&lower) {
                best_match = Some(entry.path());
                break;
            }
        }
        best_match
    }

    /// Autocomplete de caminho ao digitar na barra de endereço
    pub fn autocomplete(partial: &str) -> Vec<AutocompleteSuggestion> {
        let mut results = Vec::new();
        let trimmed = partial.trim();

        let (base_dir, prefix) = if trimmed.ends_with('/') {
            let path = if trimmed.starts_with('~') {
                if let Some(home) = dirs::home_dir() {
                    home.join(trimmed.trim_start_matches("~/"))
                } else {
                    PathBuf::from(trimmed)
                }
            } else {
                PathBuf::from(trimmed)
            };
            (path, "")
        } else {
            let p = Path::new(trimmed);
            let parent = p.parent().unwrap_or_else(|| Path::new(""));
            let file_prefix = p.file_name().and_then(|f| f.to_str()).unwrap_or("");
            let resolved_parent = if parent.as_os_str().is_empty() {
                PathBuf::from(".")
            } else if parent.starts_with("~") {
                if let Some(home) = dirs::home_dir() {
                    home.join(parent.to_string_lossy().trim_start_matches("~/"))
                } else {
                    parent.to_path_buf()
                }
            } else {
                parent.to_path_buf()
            };
            (resolved_parent, file_prefix)
        };

        if let Ok(entries) = std::fs::read_dir(base_dir) {
            for entry in entries.flatten() {
                let name = entry.file_name().to_string_lossy().to_string();
                if prefix.is_empty() || name.to_lowercase().starts_with(&prefix.to_lowercase()) {
                    let is_dir = entry.file_type().map(|t| t.is_dir()).unwrap_or(false);
                    results.push(AutocompleteSuggestion {
                        display: name,
                        full_path: entry.path(),
                        is_dir,
                    });
                }
            }
        }

        results.sort_by(|a, b| b.is_dir.cmp(&a.is_dir).then_with(|| a.display.cmp(&b.display)));
        results
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_resolve_root_and_home() {
        let res = PathResolver::resolve("/");
        assert!(res.is_ok());
        assert_eq!(res.unwrap(), PathBuf::from("/"));

        let res_home = PathResolver::resolve("~");
        assert!(res_home.is_ok());
    }

    #[test]
    fn test_not_a_directory() {
        let cargo_toml = Path::new(env!("CARGO_MANIFEST_DIR")).join("Cargo.toml");
        let res = PathResolver::resolve(cargo_toml.to_str().unwrap());
        match res {
            Err(PathError::NotADirectory { file_path, .. }) => {
                assert_eq!(file_path, cargo_toml);
            }
            _ => panic!("Esperava NotADirectory"),
        }
    }

    #[test]
    fn test_device_disconnected() {
        let res = PathResolver::resolve("/run/media/panda/Kingston/docs");
        match res {
            Err(PathError::DeviceDisconnected { device_name, .. }) => {
                assert_eq!(device_name, "Kingston");
            }
            _ => panic!("Esperava DeviceDisconnected"),
        }
    }

    #[test]
    fn test_path_too_long() {
        let long_str = "a".repeat(4097);
        let res = PathResolver::resolve(&long_str);
        match res {
            Err(PathError::PathTooLong { length }) => {
                assert_eq!(length, 4097);
            }
            _ => panic!("Esperava PathTooLong"),
        }
    }
}
