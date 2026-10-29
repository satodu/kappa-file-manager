//! Estado ao vivo de um dispositivo KDE Connect (bateria, rede celular, montagem), lido do D-Bus do `kdeconnectd`.
//! Só leitura: o id é validado e vira parte do caminho D-Bus, nada é executado.

use std::time::Duration;

use serde_json::{Value, json};
use zbus::proxy::{Builder, CacheProperties};

use super::file_ops::{parse_mountinfo, validate_device_id};

const SERVICE: &str = "org.kde.kdeconnect";
const TIMEOUT: Duration = Duration::from_secs(3);

/// Monta o JSON entregue ao QML; campos ausentes (plugin desligado, celular sem dados) viram `null`
pub fn status_value(battery: Option<(i32, bool)>, network: Option<(String, i32)>, mounted: bool) -> Value {
    json!({
        "ok": true,
        "battery": battery.map(|(charge, charging)| json!({ "charge": charge.clamp(0, 100), "charging": charging })),
        "network": network.map(|(kind, strength)| json!({ "type": kind, "strength": strength.clamp(0, 4) })),
        "mounted": mounted,
    })
}

async fn read_prop<T>(conn: &zbus::Connection, path: &str, iface: &str, name: &str) -> Option<T>
where
    T: zbus::Type + serde::de::DeserializeOwned,
{
    let proxy = Builder::<zbus::Proxy>::new(conn)
        .destination(SERVICE)
        .path(path.to_string())
        .interface(iface.to_string())
        .cache_properties(CacheProperties::No)
        .build()
        .await
        .ok()?;
    tokio::time::timeout(TIMEOUT, proxy.get_property::<T>(name)).await.ok()?.ok()
}

/// O kdeconnectd monta o celular em `/run/user/<uid>/<id>`; o Kappa navega numa subpasta dele
pub fn is_device_mounted(mounts: &[std::path::PathBuf], id: &str) -> bool {
    mounts.iter().any(|m| m.starts_with("/run/user") && m.file_name().is_some_and(|n| n == id))
}

pub async fn status(id: &str) -> Value {
    if let Err(e) = validate_device_id(id) {
        return json!({ "ok": false, "error": e.to_string() });
    }
    let Ok(conn) = zbus::Connection::session().await else {
        return json!({ "ok": false, "error": "D-Bus indisponível" });
    };
    let base = format!("/modules/kdeconnect/devices/{id}");

    let battery_path = format!("{base}/battery");
    let battery_iface = "org.kde.kdeconnect.device.battery";
    let has: Option<bool> = read_prop(&conn, &battery_path, battery_iface, "hasBattery").await;
    let battery = if has == Some(true) {
        let charge: Option<i32> = read_prop(&conn, &battery_path, battery_iface, "charge").await;
        let charging: Option<bool> = read_prop(&conn, &battery_path, battery_iface, "isCharging").await;
        charge.filter(|c| *c >= 0).map(|c| (c, charging.unwrap_or(false)))
    } else {
        None
    };

    let net_path = format!("{base}/connectivity_report");
    let net_iface = "org.kde.kdeconnect.device.connectivity_report";
    let kind: Option<String> = read_prop(&conn, &net_path, net_iface, "cellularNetworkType").await;
    let strength: Option<i32> = read_prop(&conn, &net_path, net_iface, "cellularNetworkStrength").await;
    let network = kind.filter(|k| !k.is_empty() && k.len() < 16).map(|k| (k, strength.unwrap_or(0)));

    let table = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let mounted = is_device_mounted(&parse_mountinfo(&table), id);

    status_value(battery, network, mounted)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn status_json_clamps_and_nulls_missing_parts() {
        let v = status_value(Some((130, true)), Some(("LTE".into(), 9)), false);
        assert_eq!(v["battery"]["charge"], 100);
        assert_eq!(v["battery"]["charging"], true);
        assert_eq!(v["network"]["type"], "LTE");
        assert_eq!(v["network"]["strength"], 4);
        assert_eq!(v["mounted"], false);
        let v = status_value(None, None, true);
        assert!(v["battery"].is_null() && v["network"].is_null());
        assert_eq!(v["mounted"], true);
    }

    #[test]
    fn mount_is_matched_by_device_id_under_run_user() {
        let mounts: Vec<std::path::PathBuf> = ["/", "/run/user/1000/abc123", "/home"].iter().map(Into::into).collect();
        assert!(is_device_mounted(&mounts, "abc123"));
        assert!(!is_device_mounted(&mounts, "abc12"));
        assert!(!is_device_mounted(&["/mnt/abc123".into()], "abc123"));
    }

    #[tokio::test]
    async fn bad_ids_never_reach_the_bus() {
        for bad in ["", "-x", "a/b", "../x", "a b", "a\n"] {
            let v = status(bad).await;
            assert_eq!(v["ok"], false, "deveria recusar {bad:?}");
        }
    }
}
