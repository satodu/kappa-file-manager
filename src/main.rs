mod core;
mod ops;

use std::env;
use std::path::PathBuf;
use std::process::Command;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use core::{
    FolderLoader, SortDirection, SortField,
    path_resolver::PathResolver,
    places::Places,
    search::{SearchEngine, SearchFilter, SearchScope},
};
use ops::file_ops::FileOperations;

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();

    if args.len() > 1 {
        match args[1].as_str() {
            "--list-json" => {
                let target = args.get(2).map(PathBuf::from).unwrap_or_else(|| {
                    dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"))
                });
                let show_hidden = args.iter().any(|a| a == "--hidden");

                let sort_field = if args.iter().any(|a| a == "--sort-type") {
                    SortField::Type
                } else if args.iter().any(|a| a == "--sort-modified" || a == "--sort-date") {
                    SortField::Modified
                } else if args.iter().any(|a| a == "--sort-size") {
                    SortField::Size
                } else {
                    SortField::Name
                };

                let sort_direction = if args.iter().any(|a| a == "--desc") {
                    SortDirection::Descending
                } else {
                    SortDirection::Ascending
                };

                match FolderLoader::load_directory(&target, show_hidden, sort_field, sort_direction) {
                    Ok(content) => {
                        let json = serde_json::json!({
                            "path": content.current_path.to_string_lossy(),
                            "entries": content.entries,
                            "total": content.total_items,
                            "hidden": content.hidden_count,
                            "ok": true
                        });
                        println!("{}", json);
                    }
                    Err(e) => {
                        let json = serde_json::json!({
                            "ok": false,
                            "error": e.to_string(),
                            "path": target.to_string_lossy()
                        });
                        println!("{}", json);
                    }
                }
                return;
            }
            "--places-json" => {
                let standard = Places::get_standard_places();
                let devices = Places::get_devices();
                let json = serde_json::json!({
                    "places": standard,
                    "devices": devices,
                    "ok": true
                });
                println!("{}", json);
                return;
            }
            "--resolve-json" => {
                let input = args.get(2).map(|s| s.as_str()).unwrap_or("~");
                match PathResolver::resolve(input) {
                    Ok(path) => {
                        let json = serde_json::json!({
                            "ok": true,
                            "path": path.to_string_lossy()
                        });
                        println!("{}", json);
                    }
                    Err(err) => {
                        let json = serde_json::json!({
                            "ok": false,
                            "error": err
                        });
                        println!("{}", json);
                    }
                }
                return;
            }
            "--autocomplete-json" => {
                let partial = args.get(2).map(|s| s.as_str()).unwrap_or("");
                let suggestions = PathResolver::autocomplete(partial);
                let json = serde_json::json!({
                    "suggestions": suggestions,
                    "ok": true
                });
                println!("{}", json);
                return;
            }
            "--search-json" => {
                let root = args.get(2).map(PathBuf::from).unwrap_or_else(|| {
                    dirs::home_dir().unwrap_or_else(|| PathBuf::from("/"))
                });
                let query = args.get(3).cloned().unwrap_or_default();
                let token = Arc::new(AtomicBool::new(false));

                let results = SearchEngine::search(
                    root,
                    SearchFilter {
                        query,
                        scope: SearchScope::CurrentFolder,
                        kind_filter: None,
                    },
                    token,
                    50,
                )
                .await;

                let json = serde_json::json!({
                    "results": results.into_iter().map(|r| {
                        serde_json::json!({
                            "entry": r.entry,
                            "parent": r.parent_folder_display,
                            "indices": r.match_indices
                        })
                    }).collect::<Vec<_>>(),
                    "ok": true
                });
                println!("{}", json);
                return;
            }
            "--open" => {
                if let Some(target) = args.get(2) {
                    if let Err(e) = FileOperations::open_default(target) {
                        eprintln!("Erro ao abrir arquivo: {}", e);
                    }
                }
                return;
            }
            "--trash" => {
                if let Some(target) = args.get(2) {
                    match FileOperations::move_to_trash(target) {
                        Ok(_) => println!("{}", serde_json::json!({ "ok": true })),
                        Err(e) => println!("{}", serde_json::json!({ "ok": false, "error": format!("Erro ao mover para lixeira: {}", e) })),
                    }
                }
                return;
            }
            "--delete" => {
                if let Some(target) = args.get(2) {
                    match FileOperations::delete_permanently(target) {
                        Ok(_) => println!("{}", serde_json::json!({ "ok": true })),
                        Err(e) => println!("{}", serde_json::json!({ "ok": false, "error": format!("Erro ao excluir: {}", e) })),
                    }
                }
                return;
            }
            "--copy" => {
                if let (Some(src), Some(dst)) = (args.get(2), args.get(3)) {
                    match FileOperations::copy_item(src, dst) {
                        Ok(p) => println!("{}", serde_json::json!({ "ok": true, "path": p })),
                        Err(e) => {
                            eprintln!("Erro ao copiar item: {}", e);
                            println!("{}", serde_json::json!({ "ok": false, "error": e.to_string() }));
                        }
                    }
                }
                return;
            }
            "--move" => {
                if let (Some(src), Some(dst)) = (args.get(2), args.get(3)) {
                    match FileOperations::move_item(src, dst) {
                        Ok(p) => println!("{}", serde_json::json!({ "ok": true, "path": p })),
                        Err(e) => {
                            eprintln!("Erro ao mover item: {}", e);
                            println!("{}", serde_json::json!({ "ok": false, "error": e.to_string() }));
                        }
                    }
                }
                return;
            }
            "--transfer" => {
                // --transfer <copy|move> <dest_dir> <src>...
                if let (Some(mode), Some(dst)) = (args.get(2), args.get(3)) {
                    let sources: Vec<std::path::PathBuf> = args.iter().skip(4).map(std::path::PathBuf::from).collect();
                    let mode = if mode == "move" { ops::transfer::TransferMode::Move } else { ops::transfer::TransferMode::Copy };
                    if let Err(e) = ops::transfer::Transfer::run(mode, &sources, std::path::Path::new(dst)) {
                        println!("{}", serde_json::json!({ "event": "error", "error": e.to_string() }));
                        std::process::exit(1);
                    }
                }
                return;
            }
            "--rename" => {
                if let (Some(old), Some(new_name)) = (args.get(2), args.get(3)) {
                    match FileOperations::rename_item(old, new_name) {
                        Ok(p) => println!("{}", serde_json::json!({ "ok": true, "path": p })),
                        Err(e) => {
                            eprintln!("Erro ao renomear: {}", e);
                            println!("{}", serde_json::json!({ "ok": false, "error": e.to_string() }));
                        }
                    }
                }
                return;
            }
            "--new-folder" => {
                if let (Some(parent), Some(name)) = (args.get(2), args.get(3)) {
                    match FileOperations::create_folder(parent, name) {
                        Ok(p) => println!("{}", serde_json::json!({ "ok": true, "path": p })),
                        Err(e) => {
                            eprintln!("Erro ao criar pasta: {}", e);
                            println!("{}", serde_json::json!({ "ok": false, "error": e.to_string() }));
                        }
                    }
                }
                return;
            }
            "--kde-share" => {
                if let (Some(dev), Some(target)) = (args.get(2), args.get(3)) {
                    if let Err(e) = FileOperations::kde_share(dev, target) {
                        eprintln!("Erro ao compartilhar via KDE Connect: {}", e);
                    }
                }
                return;
            }
            "--kde-ping" => {
                if let Some(dev) = args.get(2) {
                    let _ = FileOperations::kde_ping(dev);
                }
                return;
            }
            "--kde-ring" => {
                if let Some(dev) = args.get(2) {
                    let _ = FileOperations::kde_ring(dev);
                }
                return;
            }
            "--kde-clipboard" => {
                if let Some(dev) = args.get(2) {
                    let _ = FileOperations::kde_send_clipboard(dev);
                }
                return;
            }
            "--kde-mount" => {
                if let Some(dev) = args.get(2) {
                    let _ = FileOperations::kde_mount(dev);
                }
                return;
            }
            "--mount-device" => {
                if let Some(dev) = args.get(2) {
                    match FileOperations::mount_device(dev) {
                        Ok(p) => println!("{}", serde_json::json!({ "ok": true, "path": p })),
                        Err(e) => {
                            eprintln!("Erro ao montar dispositivo: {}", e);
                            println!("{}", serde_json::json!({ "ok": false, "error": e.to_string() }));
                        }
                    }
                }
                return;
            }
            "--eject-device" => {
                if let Some(dev) = args.get(2) {
                    let _ = FileOperations::eject_device(dev);
                    println!("{}", serde_json::json!({ "ok": true }));
                }
                return;
            }
            "--help" | "-h" => {
                println!("Kappa File Manager Core");
                println!("  --list-json <path> [--hidden]");
                println!("  --places-json");
                println!("  --resolve-json <path>");
                println!("  --autocomplete-json <partial>");
                println!("  --search-json <path> <query>");
                println!("  --open <path>");
                println!("  --delete <path>   (exclusão permanente)\n  --trash <path>");
                println!("  --mount-device <block_dev>");
                println!("  --eject-device <block_dev>");
                println!("  --kde-share <dev_id> <path>");
                println!("  --kde-ping <dev_id>");
                println!("  --kde-ring <dev_id>");
                println!("  --kde-clipboard <dev_id>");
                println!("  --kde-mount <dev_id>");
                println!("  --gui (ou sem argumentos para abrir UI)");
                return;
            }
            "--gui" => {
                // Cai no lançamento padrão da GUI abaixo
            }
            _ => {}
        }
    }

    // Por padrão (ou com --gui), lança a interface Quickshell QML
    // Localiza o shell.qml: KAPPA_QML_DIR, instalação do sistema ou a árvore de desenvolvimento (target/<perfil>/../..)
    let exe = env::current_exe().ok();
    let mut candidates: Vec<PathBuf> = Vec::new();
    if let Ok(dir) = env::var("KAPPA_QML_DIR") {
        candidates.push(PathBuf::from(dir).join("shell.qml"));
    }
    candidates.push(PathBuf::from("/usr/share/kappa-file-manager/qml/shell.qml"));
    if let Some(root) = exe.as_deref().and_then(|p| p.ancestors().nth(3)) {
        candidates.push(root.join("qml/shell.qml"));
    }

    match candidates.into_iter().find(|p| p.exists()) {
        Some(qml_shell) => {
            println!("» Lançando Kappa File Manager UI via Quickshell: {}", qml_shell.display());
            let mut cmd = Command::new("quickshell");
            cmd.arg("-p").arg(&qml_shell);
            if env::var_os("KAPPA_BACKEND").is_none() {
                if let Some(exe) = &exe {
                    cmd.env("KAPPA_BACKEND", exe);
                }
            }
            let mut child = cmd.spawn().expect("Falha ao executar o quickshell");
            let _ = child.wait();
        }
        None => eprintln!("Arquivo shell.qml não encontrado (defina KAPPA_QML_DIR)"),
    }
}
