mod core;
mod ops;

use std::env;
use std::path::PathBuf;
use std::path::Path;
use std::process::Command;
use std::sync::atomic::AtomicBool;
use std::sync::Arc;

use core::{
    FolderLoader, SortDirection, SortField,
    path_resolver::PathResolver,
    places::Places,
    search::{SearchEngine, SearchFilter, SearchScope},
};
use ops::file_ops::{self, FileOperations};

#[tokio::main]
async fn main() {
    let args: Vec<String> = env::args().collect();

    // Um gerenciador de arquivos como root transforma qualquer corrida ou link malicioso em escalada de privilégio
    if !ops::file_ops::root_allowed(unsafe { libc::geteuid() }, env::var_os("KAPPA_ALLOW_ROOT").is_some()) {
        println!("{}", serde_json::json!({ "ok": false, "event": "error", "error": "O Kappa não deve rodar como root (use o seu usuário comum)" }));
        eprintln!("Kappa recusa rodar como root. Defina KAPPA_ALLOW_ROOT=1 apenas se tiver certeza.");
        std::process::exit(1);
    }

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
                            "truncated": content.truncated,
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
                // --open <path> [--confirmed]: arquivos que podem executar código pedem confirmação antes
                if let Some(target) = args.get(2) {
                    let confirmed = args.iter().skip(3).any(|a| a == "--confirmed");
                    let result = FileOperations::require_abs_ok(target).and_then(|_| {
                        if !confirmed {
                            if let Some(reason) = file_ops::open_risk(Path::new(target)) {
                                println!("{}", serde_json::json!({ "ok": false, "needs_confirm": true, "reason": reason }));
                                return Ok(false);
                            }
                        }
                        FileOperations::open_default(target).map(|_| true)
                    });
                    match result {
                        Ok(true) => println!("{}", serde_json::json!({ "ok": true })),
                        Ok(false) => {}
                        Err(e) => println!("{}", serde_json::json!({ "ok": false, "error": format!("Erro ao abrir arquivo: {}", e) })),
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
            "--compress" => {
                // --compress <zip|tar.gz> <out_dir> <nome-base|-> <origem>...
                if let (Some(fmt), Some(out_dir), Some(name)) = (args.get(2), args.get(3), args.get(4)) {
                    let fail = |msg: String| {
                        println!("{}", serde_json::json!({ "event": "error", "error": msg }));
                        std::process::exit(1);
                    };
                    let Some(format) = ops::archive::ArchiveFormat::parse(fmt) else { fail("Formato não suportado".into()); return; };
                    if !std::iter::once(out_dir).chain(args.iter().skip(5)).all(|a| file_ops::require_absolute(a).is_ok()) {
                        fail("Caminho precisa ser absoluto".into());
                    }
                    let sources: Vec<std::path::PathBuf> = args.iter().skip(5).map(std::path::PathBuf::from).collect();
                    let base = if name == "-" { None } else { Some(name.as_str()) };
                    if let Err(e) = ops::archive::compress(format, &sources, Path::new(out_dir), base) {
                        fail(e.to_string());
                    }
                }
                return;
            }
            "--extract" => {
                // --extract <arquivo> <out_dir>
                if let (Some(archive), Some(out_dir)) = (args.get(2), args.get(3)) {
                    let fail = |msg: String| {
                        println!("{}", serde_json::json!({ "event": "error", "error": msg }));
                        std::process::exit(1);
                    };
                    if file_ops::require_absolute(archive).is_err() || file_ops::require_absolute(out_dir).is_err() {
                        fail("Caminho precisa ser absoluto".into());
                    }
                    if let Err(e) = ops::archive::extract(Path::new(archive), Path::new(out_dir)) {
                        fail(e.to_string());
                    }
                }
                return;
            }
            "--transfer" => {
                // --transfer <copy|move> <dest_dir> <src>...
                if let (Some(mode), Some(dst)) = (args.get(2), args.get(3)) {
                    let all_abs = std::iter::once(dst).chain(args.iter().skip(4)).all(|a| file_ops::require_absolute(a).is_ok());
                    if !all_abs {
                        println!("{}", serde_json::json!({ "event": "error", "error": "Caminho precisa ser absoluto" }));
                        std::process::exit(1);
                    }
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
            // Classe da janela (app_id): faz a dock e o launcher associarem a janela ao kappa-file-manager.desktop
            if env::var_os("QS_APP_ID").is_none() {
                cmd.env("QS_APP_ID", "kappa-file-manager");
            }
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
