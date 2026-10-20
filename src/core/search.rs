use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use walkdir::WalkDir;

use super::entry::{FileEntry, FileKind};

#[allow(dead_code)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SearchScope {
    CurrentFolder,
    All,
}

#[derive(Debug, Clone)]
pub struct SearchFilter {
    pub query: String,
    pub scope: SearchScope,
    pub kind_filter: Option<FileKind>,
}

#[derive(Debug, Clone)]
pub struct SearchResult {
    pub entry: FileEntry,
    pub match_indices: Vec<(usize, usize)>, // Início e fim dos trechos coincidentes
    pub parent_folder_display: String,
}

pub struct SearchEngine;

impl SearchEngine {
    /// Executa busca assíncrona recursiva com suporte a cancelamento imediato
    pub async fn search(
        root_dir: PathBuf,
        filter: SearchFilter,
        cancel_token: Arc<AtomicBool>,
        max_results: usize,
    ) -> Vec<SearchResult> {
        tokio::task::spawn_blocking(move || {
            let mut results = Vec::new();
            let query_lower = filter.query.to_lowercase();

            let target_root = match filter.scope {
                SearchScope::CurrentFolder => root_dir,
                SearchScope::All => dirs::home_dir().unwrap_or(root_dir),
            };

            let walker = WalkDir::new(&target_root)
                .follow_links(false)
                .max_depth(if filter.scope == SearchScope::CurrentFolder { 8 } else { 5 })
                .into_iter();

            for entry_res in walker.filter_entry(|e| {
                // Pula pastas ocultas grandes como .git, node_modules, target
                let name = e.file_name().to_string_lossy();
                !name.starts_with('.') && name != "node_modules" && name != "target"
            }) {
                if cancel_token.load(Ordering::Relaxed) {
                    break;
                }

                let entry = match entry_res {
                    Ok(e) => e,
                    Err(_) => continue,
                };

                let path = entry.path();
                let file_name = entry.file_name().to_string_lossy();

                // Checa se corresponde ao texto buscado
                let file_name_lower = file_name.to_lowercase();
                if let Some(pos) = file_name_lower.find(&query_lower) {
                    if let Ok(file_entry) = FileEntry::from_path(path) {
                        // Se houver filtro de tipo (chip), valida
                        if let Some(kind) = filter.kind_filter {
                            if file_entry.kind != kind {
                                continue;
                            }
                        }

                        let match_range = (pos, pos + query_lower.len());
                        let parent_display = path
                            .parent()
                            .map(|p| p.file_name().unwrap_or(p.as_os_str()).to_string_lossy().to_string())
                            .unwrap_or_else(|| "/".to_string());

                        results.push(SearchResult {
                            entry: file_entry,
                            match_indices: vec![match_range],
                            parent_folder_display: parent_display,
                        });

                        if results.len() >= max_results {
                            break;
                        }
                    }
                }
            }

            results
        })
        .await
        .unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_search_current_folder() {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let token = Arc::new(AtomicBool::new(false));

        let results = SearchEngine::search(
            manifest_dir,
            SearchFilter {
                query: "entry".to_string(),
                scope: SearchScope::CurrentFolder,
                kind_filter: None,
            },
            token,
            10,
        )
        .await;

        assert!(!results.is_empty());
        assert!(results.iter().any(|r| r.entry.name.contains("entry")));
    }
}
