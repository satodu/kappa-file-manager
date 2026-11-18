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

/// Como o texto buscado é interpretado:
/// - `re:<padrão>`: expressão regular (sem diferenciar maiúsculas), procurada em qualquer ponto do nome;
/// - com `*` ou `?`: padrão glob (`*.pdf`), que precisa casar o nome inteiro;
/// - senão: trecho do nome.
pub enum NameMatcher {
    Substring(String),
    Pattern(regex::Regex),
}

impl NameMatcher {
    /// Devolve `None` se o padrão for inválido (nenhum resultado, sem pânico).
    pub fn new(query: &str) -> Option<Self> {
        let q = query.trim();
        if let Some(pat) = q.strip_prefix("re:") {
            return Self::compile(pat);
        }
        if q.contains('*') || q.contains('?') {
            let mut re = String::from("^");
            for c in q.chars() {
                match c {
                    '*' => re.push_str(".*"),
                    '?' => re.push('.'),
                    c => re.push_str(&regex::escape(&c.to_string())),
                }
            }
            re.push('$');
            return Self::compile(&re);
        }
        Some(NameMatcher::Substring(q.to_lowercase()))
    }

    fn compile(pat: &str) -> Option<Self> {
        if pat.is_empty() {
            return None;
        }
        // Tetos de tamanho evitam padrões gigantes (sem retrocesso: o motor `regex` é linear)
        regex::RegexBuilder::new(pat)
            .case_insensitive(true)
            .size_limit(1 << 20)
            .build()
            .ok()
            .map(NameMatcher::Pattern)
    }

    /// Faixa (início, fim) em bytes do trecho que casou.
    pub fn find(&self, name: &str) -> Option<(usize, usize)> {
        match self {
            NameMatcher::Substring(q) => {
                let lower = name.to_lowercase();
                lower.find(q.as_str()).map(|p| (p, p + q.len()))
            }
            NameMatcher::Pattern(re) => re.find(name).map(|m| (m.start(), m.end())),
        }
    }
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
            let matcher = match NameMatcher::new(&filter.query) {
                Some(m) => m,
                None => return results,
            };

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
                if let Some(match_range) = matcher.find(&file_name) {
                    if let Ok(file_entry) = FileEntry::from_path(path) {
                        // Se houver filtro de tipo (chip), valida
                        if let Some(kind) = filter.kind_filter {
                            if file_entry.kind != kind {
                                continue;
                            }
                        }

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

    #[test]
    fn glob_matches_whole_name() {
        let m = NameMatcher::new("*.pdf").unwrap();
        assert!(m.find("Relatório.PDF").is_some());
        assert!(m.find("a.pdf.txt").is_none());
        let m = NameMatcher::new("img_?.png").unwrap();
        assert!(m.find("img_1.png").is_some());
        assert!(m.find("img_12.png").is_none());
        // pontos e colchetes do glob são literais
        assert!(NameMatcher::new("a.b*").unwrap().find("axb").is_none());
    }

    #[test]
    fn regex_prefix_and_substring() {
        let m = NameMatcher::new(r"re:^foto_\d{2}\.(jpg|png)$").unwrap();
        assert!(m.find("FOTO_07.JPG").is_some());
        assert!(m.find("foto_7.jpg").is_none());
        assert!(NameMatcher::new("re:(").is_none());
        assert!(NameMatcher::new("re:").is_none());
        assert_eq!(NameMatcher::new("Ent").unwrap().find("entry.rs"), Some((0, 3)));
    }

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
