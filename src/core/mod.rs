pub mod entry;
pub mod path_resolver;
pub mod places;
pub mod search;
pub mod watcher;

use std::path::{Path, PathBuf};
use entry::FileEntry;

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortField {
    Name,
    Type,
    Modified,
    Size,
}

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SortDirection {
    Ascending,
    Descending,
}

#[derive(Debug, Clone)]
pub struct FolderContent {
    pub current_path: PathBuf,
    pub entries: Vec<FileEntry>,
    pub total_items: usize,
    pub hidden_count: usize,
}

pub struct FolderLoader;

impl FolderLoader {
    pub fn load_directory(
        path: &Path,
        show_hidden: bool,
        sort_field: SortField,
        sort_direction: SortDirection,
    ) -> std::io::Result<FolderContent> {
        let read_dir = std::fs::read_dir(path)?;
        let mut entries = Vec::new();
        let mut hidden_count = 0;

        for res in read_dir {
            if let Ok(item) = res {
                if let Ok(entry) = FileEntry::from_path(item.path()) {
                    if entry.is_hidden {
                        hidden_count += 1;
                        if !show_hidden {
                            continue;
                        }
                    }
                    entries.push(entry);
                }
            }
        }

        // Ordenação padrão: Pastas sempre primeiro, depois pelo critério selecionado
        entries.sort_by(|a, b| {
            if a.is_dir != b.is_dir {
                return b.is_dir.cmp(&a.is_dir); // Diretórios primeiro
            }

            let cmp = match sort_field {
                SortField::Name => a.name.to_lowercase().cmp(&b.name.to_lowercase()),
                SortField::Type => a.kind.cmp(&b.kind).then_with(|| a.name.to_lowercase().cmp(&b.name.to_lowercase())),
                SortField::Modified => a.modified_timestamp.cmp(&b.modified_timestamp),
                SortField::Size => a.size_bytes.cmp(&b.size_bytes),
            };

            match sort_direction {
                SortDirection::Ascending => cmp,
                SortDirection::Descending => cmp.reverse(),
            }
        });

        let total_items = entries.len();

        Ok(FolderContent {
            current_path: path.to_path_buf(),
            entries,
            total_items,
            hidden_count,
        })
    }
}
