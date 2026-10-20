use std::path::PathBuf;
use std::process::Command;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlaceItem {
    pub id: String,
    pub label: String,
    pub path: PathBuf,
    pub icon_name: String,
    pub is_removable: bool,
    pub is_network: bool,
    pub detail: Option<String>, // ex: "412 GB", "1,8 TB"
    #[serde(default)]
    pub device_block: Option<String>, // ex: "/dev/sdb1"
    #[serde(default)]
    pub is_mounted: bool,
}

#[derive(Debug, Clone, Deserialize)]
struct LsblkItem {
    name: String,
    label: Option<String>,
    fstype: Option<String>,
    size: Option<String>,
    mountpoints: Option<Vec<Option<String>>>,
    rm: Option<bool>,
    hotplug: Option<bool>,
    model: Option<String>,
    tran: Option<String>,
    children: Option<Vec<LsblkItem>>,
}

#[derive(Debug, Clone, Deserialize)]
struct LsblkOutput {
    blockdevices: Vec<LsblkItem>,
}

pub struct Places;

impl Places {
    /// Detecta se o Ryoku está configurado em inglês ou português
    fn is_english_locale() -> bool {
        let shell_json = dirs::home_dir().map(|h| h.join(".config/ryoku/shell.json")).unwrap_or_default();
        if let Ok(content) = std::fs::read_to_string(shell_json) {
            if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
                if let Some(lang) = val.get("language").and_then(|l| l.as_str()) {
                    return lang == "en";
                }
            }
        }
        std::env::var("LANG").map(|l| l.starts_with("en")).unwrap_or(true)
    }

    pub fn get_standard_places() -> Vec<PlaceItem> {
        let mut places = Vec::new();
        let en = Self::is_english_locale();

        if let Some(home) = dirs::home_dir() {
            places.push(PlaceItem {
                id: "home".to_string(),
                label: if en { "Home".to_string() } else { "Home".to_string() },
                path: home,
                icon_name: "home".to_string(),
                is_removable: false,
                is_network: false,
                detail: None,
                device_block: None,
                is_mounted: true,
            });
        }

        if let Some(docs) = dirs::document_dir() {
            places.push(PlaceItem {
                id: "documents".to_string(),
                label: if en { "Documents".to_string() } else { "Documentos".to_string() },
                path: docs,
                icon_name: "doc".to_string(),
                is_removable: false,
                is_network: false,
                detail: None,
                device_block: None,
                is_mounted: true,
            });
        }

        if let Some(downloads) = dirs::download_dir() {
            places.push(PlaceItem {
                id: "downloads".to_string(),
                label: if en { "Downloads".to_string() } else { "Downloads".to_string() },
                path: downloads,
                icon_name: "down".to_string(),
                is_removable: false,
                is_network: false,
                detail: None,
                device_block: None,
                is_mounted: true,
            });
        }

        if let Some(pictures) = dirs::picture_dir() {
            places.push(PlaceItem {
                id: "pictures".to_string(),
                label: if en { "Pictures".to_string() } else { "Imagens".to_string() },
                path: pictures,
                icon_name: "img".to_string(),
                is_removable: false,
                is_network: false,
                detail: None,
                device_block: None,
                is_mounted: true,
            });
        }

        if let Some(music) = dirs::audio_dir() {
            places.push(PlaceItem {
                id: "music".to_string(),
                label: if en { "Music".to_string() } else { "Músicas".to_string() },
                path: music,
                icon_name: "music".to_string(),
                is_removable: false,
                is_network: false,
                detail: None,
                device_block: None,
                is_mounted: true,
            });
        }

        if let Some(videos) = dirs::video_dir() {
            places.push(PlaceItem {
                id: "videos".to_string(),
                label: if en { "Videos".to_string() } else { "Vídeos".to_string() },
                path: videos,
                icon_name: "video".to_string(),
                is_removable: false,
                is_network: false,
                detail: None,
                device_block: None,
                is_mounted: true,
            });
        }

        places
    }

    /// Obtém o ponto de montagem real e acessível do dispositivo KDE Connect
    pub fn get_kde_mount_point(dev_id: &str) -> PathBuf {
        // O id vira parte de caminhos e de argumentos do DBus: aceita só o alfabeto dos ids do KDE Connect
        if dev_id.is_empty() || !dev_id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-') {
            return PathBuf::new();
        }
        // 1. Assegura que o KDE Connect monte o dispositivo via SFTP
        let _ = Command::new("kdeconnect-cli")
            .arg("-d")
            .arg(dev_id)
            .arg("--mount")
            .output();

        // 2. Consulta o DBus do KDE Connect (org.kde.kdeconnect.device.sftp.getDirectories)
        // Isso retorna o diretório raiz real no Android (ex: /run/user/1000/<dev_id>/storage/emulated/0)
        if let Ok(out) = Command::new("busctl")
            .arg("--user")
            .arg("call")
            .arg("org.kde.kdeconnect")
            .arg(format!("/modules/kdeconnect/devices/{}/sftp", dev_id))
            .arg("org.kde.kdeconnect.device.sftp")
            .arg("getDirectories")
            .output()
        {
            if out.status.success() {
                let stdout = String::from_utf8_lossy(&out.stdout);
                for part in stdout.split('"') {
                    if part.starts_with('/') {
                        let p = PathBuf::from(part);
                        if p.exists() {
                            return p;
                        }
                    }
                }
            }
        }

        // 3. Checa o caminho direto do storage Android no run/user/<UID>
        let uid = std::env::var("UID").unwrap_or_else(|_| "1000".to_string());
        let standard_android_storage = PathBuf::from(format!("/run/user/{}/{}/storage/emulated/0", uid, dev_id));
        if standard_android_storage.exists() {
            return standard_android_storage;
        }

        let standard_sftp_root = PathBuf::from(format!("/run/user/{}/{}", uid, dev_id));
        if standard_sftp_root.exists() {
            return standard_sftp_root;
        }

        // 4. Fallback: KIO-Fuse do Dolphin
        let _ = Command::new("systemctl").arg("--user").arg("start").arg("kio-fuse").output();
        let kio_url = format!("kdeconnect://{}/", dev_id);
        if let Ok(out) = Command::new("busctl")
            .arg("--user")
            .arg("call")
            .arg("org.kde.KIOFuse")
            .arg("/org/kde/KIOFuse")
            .arg("org.kde.KIOFuse.VFS")
            .arg("mountUrl")
            .arg("s")
            .arg(&kio_url)
            .output()
        {
            if out.status.success() {
                let stdout = String::from_utf8_lossy(&out.stdout);
                for part in stdout.split('"') {
                    if part.starts_with('/') {
                        let p = PathBuf::from(part);
                        if p.exists() {
                            return p;
                        }
                    }
                }
            }
        }

        PathBuf::from(format!("/run/user/{}/{}", uid, dev_id))
    }

    /// Detecta mídias do sistema, partições, pendrives conectados (montados ou não) e dispositivos KDE Connect
    pub fn get_devices() -> Vec<PlaceItem> {
        let mut devices = Vec::new();
        let en = Self::is_english_locale();

        // 1. Sistema (Raiz /)
        devices.push(PlaceItem {
            id: "system".to_string(),
            label: if en { "System".to_string() } else { "Sistema".to_string() },
            path: PathBuf::from("/"),
            icon_name: "drive".to_string(),
            is_removable: false,
            is_network: false,
            detail: Some("System".to_string()),
            device_block: None,
            is_mounted: true,
        });

        // 2. Dados / Home
        if let Some(home) = dirs::home_dir() {
            devices.push(PlaceItem {
                id: "data".to_string(),
                label: if en { "Data".to_string() } else { "Dados".to_string() },
                path: home,
                icon_name: "drive".to_string(),
                is_removable: false,
                is_network: false,
                detail: Some("Home".to_string()),
                device_block: None,
                is_mounted: true,
            });
        }

        // 3. Detecção via lsblk para pendrives e discos removíveis conectados
        if let Ok(out) = Command::new("lsblk")
            .arg("-J")
            .arg("-p")
            .arg("-o")
            .arg("NAME,LABEL,FSTYPE,SIZE,MOUNTPOINTS,RM,HOTPLUG,MODEL,TRAN")
            .output()
        {
            if out.status.success() {
                if let Ok(parsed) = serde_json::from_slice::<LsblkOutput>(&out.stdout) {
                    Self::process_lsblk_root_devices(&parsed.blockdevices, &mut devices);
                }
            }
        }

        // 4. Integração REAL com KDE Connect via kdeconnect-cli e DBus sftp
        if let Ok(output) = Command::new("kdeconnect-cli").arg("-a").arg("--id-name-only").output() {
            if output.status.success() {
                let stdout = String::from_utf8_lossy(&output.stdout);
                for line in stdout.lines() {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if parts.len() >= 2 {
                        let dev_id = parts[0];
                        let dev_name = parts[1..].join(" ");
                        let mount_point = Self::get_kde_mount_point(dev_id);

                        devices.push(PlaceItem {
                            id: dev_id.to_string(),
                            label: dev_name,
                            path: mount_point,
                            icon_name: "phone".to_string(),
                            is_removable: false,
                            is_network: true,
                            detail: Some("KDE".to_string()),
                            device_block: None,
                            is_mounted: true,
                        });
                    }
                }
            }
        }

        devices
    }

    fn is_boot_or_system_mount(mp: &str) -> bool {
        mp == "/" || mp == "/home" || mp == "/boot" || mp == "/efi" || mp.starts_with("/var")
    }

    fn should_skip_helper_partition(child: &LsblkItem, siblings: &[LsblkItem]) -> bool {
        if siblings.len() <= 1 {
            return false;
        }
        let label_upper = child.label.as_deref().unwrap_or("").to_uppercase();
        if label_upper.contains("EFI") || label_upper.contains("BOOT") || label_upper.contains("ESP") {
            return true;
        }
        // Se for partição vfat minúscula (< 400M) e tiver outra partição no disco, é partição de boot/EFI auxiliar
        if child.fstype.as_deref() == Some("vfat") {
            if let Some(sz) = &child.size {
                if sz.ends_with('M') || sz.ends_with("MB") || sz.ends_with('K') {
                    return true;
                }
            }
        }
        false
    }

    fn process_lsblk_root_devices(
        root_devices: &[LsblkItem],
        devices: &mut Vec<PlaceItem>,
    ) {
        for root_dev in root_devices {
            let is_rem = root_dev.rm.unwrap_or(false)
                || root_dev.hotplug.unwrap_or(false)
                || root_dev.tran.as_deref() == Some("usb");

            let children = root_dev.children.as_deref().unwrap_or(&[]);

            if is_rem {
                // Filtra partições auxiliares (como ARCHISO_EFI / boot loaders de instaladores)
                let valid_children: Vec<&LsblkItem> = children
                    .iter()
                    .filter(|c| !Self::should_skip_helper_partition(c, children))
                    .filter(|c| c.fstype.as_deref() != Some("swap"))
                    .collect();

                let targets: Vec<&LsblkItem> = if !valid_children.is_empty() {
                    valid_children
                } else if !children.is_empty() {
                    vec![&children[0]]
                } else {
                    vec![root_dev]
                };

                for item in targets {
                    let mountpoint = item.mountpoints.as_ref().and_then(|mps| {
                        mps.iter().filter_map(|m| m.as_ref()).find(|s| !s.is_empty())
                    });

                    let label = item.label.as_deref()
                        .or(root_dev.label.as_deref())
                        .or(root_dev.model.as_deref())
                        .unwrap_or_else(|| {
                            item.name.rsplit('/').next().unwrap_or(&item.name)
                        })
                        .to_string();

                    let size_str = item.size.clone().or_else(|| root_dev.size.clone()).unwrap_or_default();
                    let detail_text = if size_str.is_empty() {
                        None
                    } else {
                        Some(size_str)
                    };

                    let is_mounted = mountpoint.is_some();
                    let path = mountpoint.map(PathBuf::from).unwrap_or_else(|| PathBuf::from(&item.name));

                    let dev_id = format!("device_{}", item.name.replace('/', "_"));
                    if !devices.iter().any(|d| d.id == dev_id || d.device_block.as_deref() == Some(&item.name)) {
                        devices.push(PlaceItem {
                            id: dev_id,
                            label,
                            path,
                            icon_name: "usb".to_string(),
                            is_removable: true,
                            is_network: false,
                            detail: detail_text,
                            device_block: Some(item.name.clone()),
                            is_mounted,
                        });
                    }
                }
            } else {
                // Discos não removíveis (checa se há partições montadas em /run/media, /media, /mnt)
                for item in std::iter::once(root_dev).chain(children.iter()) {
                    if item.fstype.as_deref() == Some("swap") || item.name.starts_with("/dev/loop") {
                        continue;
                    }

                    let mountpoint = item.mountpoints.as_ref().and_then(|mps| {
                        mps.iter().filter_map(|m| m.as_ref()).find(|s| !s.is_empty())
                    });

                    if let Some(mp) = mountpoint {
                        if Self::is_boot_or_system_mount(mp) {
                            continue;
                        }

                        if mp.starts_with("/run/media/") || mp.starts_with("/media/") || mp.starts_with("/mnt/") {
                            let label = item.label.as_deref()
                                .or(root_dev.model.as_deref())
                                .unwrap_or_else(|| {
                                    item.name.rsplit('/').next().unwrap_or(&item.name)
                                })
                                .to_string();

                            let dev_id = format!("device_{}", item.name.replace('/', "_"));
                            if !devices.iter().any(|d| d.id == dev_id || d.device_block.as_deref() == Some(&item.name) || d.path == PathBuf::from(mp)) {
                                devices.push(PlaceItem {
                                    id: dev_id,
                                    label,
                                    path: PathBuf::from(mp),
                                    icon_name: "drive".to_string(),
                                    is_removable: false,
                                    is_network: false,
                                    detail: item.size.clone(),
                                    device_block: Some(item.name.clone()),
                                    is_mounted: true,
                                });
                            }
                        }
                    }
                }
            }
        }
    }
}
