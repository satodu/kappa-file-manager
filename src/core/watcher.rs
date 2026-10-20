use notify::{Config, Event, RecommendedWatcher, RecursiveMode, Watcher};
use std::path::{Path, PathBuf};
use tokio::sync::mpsc;

#[allow(dead_code)]
pub struct FolderWatcher {
    _watcher: RecommendedWatcher,
}

#[allow(dead_code)]
impl FolderWatcher {
    /// Inicia a observação da pasta atual em uma thread de background, enviando eventos via canal Tokio
    pub fn watch(
        path: impl AsRef<Path>,
        tx: mpsc::UnboundedSender<PathBuf>,
    ) -> notify::Result<Self> {
        let watched_path = path.as_ref().to_path_buf();
        let mut watcher = RecommendedWatcher::new(
            move |res: notify::Result<Event>| {
                if let Ok(event) = res {
                    // Notifica sobre alterações relevantes
                    if event.kind.is_create()
                        || event.kind.is_remove()
                        || event.kind.is_modify()
                    {
                        for p in event.paths {
                            let _ = tx.send(p);
                        }
                    }
                }
            },
            Config::default(),
        )?;

        watcher.watch(&watched_path, RecursiveMode::NonRecursive)?;

        Ok(Self {
            _watcher: watcher,
        })
    }
}
