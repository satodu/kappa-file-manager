//! Compactação (.zip, .tar.gz) e extração (.zip, .tar, .tar.gz/.tgz) com foco em segurança.
//!
//! Regras de segurança da extração:
//! - o conteúdo vai sempre para uma pasta NOVA criada com `create_dir` (nunca sobrescreve nada);
//! - caminhos absolutos, `..`, prefixos e nomes com NUL/controle são descartados (zip-slip);
//! - nunca se escreve através de um link simbólico (cada componente do caminho é checado com `lstat`)
//!   e os arquivos são abertos com `O_NOFOLLOW | O_EXCL`;
//! - links simbólicos só são recriados se o alvo for relativo e ficar dentro da pasta de destino;
//!   hard links, dispositivos, FIFOs e sockets são ignorados;
//! - setuid/setgid/sticky são removidos das permissões e o dono do arquivo nunca é restaurado;
//! - limites contra "zip bombs": nº de entradas, tamanho total, razão de compressão, tamanho por
//!   entrada (não passa do declarado) e reserva de espaço livre em disco;
//! - em qualquer erro a pasta parcial criada é removida.

use std::collections::HashSet;
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::ffi::OsStrExt;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::path::{Component, Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::json;
use walkdir::WalkDir;

use super::transfer::emit;

const MAX_ENTRIES: u64 = 1_000_000;
const MAX_TOTAL_BYTES: u64 = 100 * 1024 * 1024 * 1024;
const MAX_PATH_BYTES: usize = 4096;
const MAX_COMPONENT_BYTES: usize = 255;
const MAX_DEPTH: usize = 64;
const MAX_SYMLINK_TARGET: u64 = 4096;
/// Acima deste total extraído, a razão de compressão passa a ser verificada
const RATIO_CHECK_FROM: u64 = 2 * 1024 * 1024 * 1024;
const MAX_RATIO: u64 = 2000;
/// Espaço livre que sempre deve sobrar no disco
const DISK_RESERVE: u64 = 256 * 1024 * 1024;
const EMIT_EVERY: Duration = Duration::from_millis(100);
const CHUNK: usize = 256 * 1024;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum ArchiveFormat {
    Zip,
    TarGz,
}

impl ArchiveFormat {
    pub fn parse(s: &str) -> Option<Self> {
        match s {
            "zip" => Some(Self::Zip),
            "tar.gz" | "tgz" | "targz" => Some(Self::TarGz),
            _ => None,
        }
    }

    fn extension(self) -> &'static str {
        match self {
            Self::Zip => ".zip",
            Self::TarGz => ".tar.gz",
        }
    }
}

fn err(msg: impl Into<String>) -> io::Error {
    io::Error::new(io::ErrorKind::InvalidData, msg.into())
}

// ─── utilitários ─────────────────────────────────────────────────────────

/// Espaço livre (em bytes) para usuário comum no sistema de arquivos de `path`
fn available_space(path: &Path) -> u64 {
    let Ok(c) = std::ffi::CString::new(path.as_os_str().as_bytes()) else { return u64::MAX };
    let mut st: libc::statvfs = unsafe { std::mem::zeroed() };
    if unsafe { libc::statvfs(c.as_ptr(), &mut st) } != 0 {
        return u64::MAX;
    }
    (st.f_bavail as u64).saturating_mul(st.f_frsize as u64)
}

fn tree_size(path: &Path) -> u64 {
    WalkDir::new(path)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
        .filter(|e| e.file_type().is_file())
        .filter_map(|e| e.metadata().ok())
        .map(|m| m.len())
        .sum()
}

/// Nome seguro para um componente: sem NUL, controle, barra; tamanho limitado
fn component_ok(c: &OsStr) -> bool {
    let b = c.as_bytes();
    !b.is_empty() && b.len() <= MAX_COMPONENT_BYTES && !b.iter().any(|&x| x == 0 || x < 0x20 || x == 0x7f)
}

/// Converte o nome de uma entrada em caminho relativo seguro; `None` = descartar a entrada
fn safe_relative(raw: &[u8], backslash_is_sep: bool) -> Option<PathBuf> {
    if raw.is_empty() || raw.len() > MAX_PATH_BYTES || raw.contains(&0) {
        return None;
    }
    let normalized: Vec<u8> = if backslash_is_sep {
        raw.iter().map(|&b| if b == b'\\' { b'/' } else { b }).collect()
    } else {
        raw.to_vec()
    };
    let path = Path::new(OsStr::from_bytes(&normalized));
    let mut out = PathBuf::new();
    for comp in path.components() {
        match comp {
            Component::Normal(c) => {
                if !component_ok(c) {
                    return None;
                }
                out.push(c);
            }
            Component::CurDir => {}
            // `..`, raiz e prefixos nunca são aceitos
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => return None,
        }
    }
    if out.as_os_str().is_empty() || out.components().count() > MAX_DEPTH {
        return None;
    }
    Some(out)
}

/// Um alvo de link simbólico só é aceito se for relativo e permanecer dentro da raiz de extração
fn symlink_target_ok(link_rel: &Path, target: &[u8]) -> bool {
    if target.is_empty() || target.contains(&0) || target.len() > MAX_PATH_BYTES {
        return false;
    }
    let target = Path::new(OsStr::from_bytes(target));
    if target.is_absolute() {
        return false;
    }
    // Profundidade do diretório que contém o link, relativa à raiz
    let mut depth: i64 = link_rel.parent().map(|p| p.components().count() as i64).unwrap_or(0);
    for comp in target.components() {
        match comp {
            Component::Normal(_) => depth += 1,
            Component::CurDir => {}
            Component::ParentDir => {
                depth -= 1;
                if depth < 0 {
                    return false;
                }
            }
            _ => return false,
        }
    }
    true
}

/// Garante que nenhum componente já existente de `root/rel` (exceto o último) seja link simbólico
/// e cria os diretórios que faltam. Devolve o caminho completo.
fn prepare_parent(root: &Path, rel: &Path) -> io::Result<PathBuf> {
    let mut cur = root.to_path_buf();
    let comps: Vec<_> = rel.components().collect();
    for comp in &comps[..comps.len().saturating_sub(1)] {
        cur.push(comp.as_os_str());
        match fs::symlink_metadata(&cur) {
            Ok(m) if m.file_type().is_symlink() => return Err(err("caminho passa por link simbólico")),
            Ok(m) if !m.is_dir() => return Err(err("componente do caminho não é diretório")),
            Ok(_) => {}
            Err(e) if e.kind() == io::ErrorKind::NotFound => {
                fs::create_dir(&cur)?;
                fs::set_permissions(&cur, fs::Permissions::from_mode(0o755))?;
            }
            Err(e) => return Err(e),
        }
    }
    Ok(cur.join(comps.last().map(|c| c.as_os_str()).unwrap_or_default()))
}

/// Permissões seguras: nunca setuid/setgid/sticky, sem escrita para grupo/outros; o dono sempre lê/escreve
fn safe_mode(mode: u32, is_dir: bool) -> u32 {
    let m = mode & 0o755;
    if is_dir { m | 0o700 } else { m | 0o600 }
}

fn create_new_file(path: &Path) -> io::Result<File> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW)
        .open(path)
}

/// Cria a pasta de destino com nome único; falha se não conseguir (sem sobrescrever)
fn create_unique_dir(parent: &Path, base: &str) -> io::Result<PathBuf> {
    for i in 0..10_000u32 {
        let name = if i == 0 { base.to_string() } else { format!("{} ({})", base, i) };
        let candidate = parent.join(&name);
        match fs::create_dir(&candidate) {
            Ok(_) => {
                fs::set_permissions(&candidate, fs::Permissions::from_mode(0o755))?;
                return Ok(candidate);
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(err("não foi possível escolher um nome de pasta livre"))
}

fn archive_stem(path: &Path) -> String {
    let name = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    let lower = name.to_lowercase();
    for ext in [".tar.gz", ".tgz", ".zip", ".tar"] {
        if lower.ends_with(ext) && name.len() > ext.len() {
            return name[..name.len() - ext.len()].to_string();
        }
    }
    if name.is_empty() { "extracted".to_string() } else { name }
}

struct Progress {
    done: u64,
    total: u64,
    index: usize,
    items: usize,
    name: String,
    dest: PathBuf,
    started: Instant,
    last_emit: Instant,
}

impl Progress {
    fn new(total: u64, items: usize, dest: &Path) -> Self {
        let now = Instant::now();
        Progress { done: 0, total, index: 0, items, name: String::new(), dest: dest.to_path_buf(), started: now, last_emit: now - EMIT_EVERY }
    }

    fn emit(&mut self, force: bool) {
        if !force && self.last_emit.elapsed() < EMIT_EVERY {
            return;
        }
        self.last_emit = Instant::now();
        let secs = self.started.elapsed().as_secs_f64().max(0.001);
        emit(json!({
            "event": "progress",
            "done": self.done,
            "total": self.total,
            "index": self.index,
            "items": self.items,
            "name": self.name,
            "dest": self.dest,
            "speed": (self.done as f64 / secs) as u64,
        }));
    }
}

/// Leitor que conta bytes lidos num contador compartilhado (posição no arquivo compactado)
struct CountingReader<R> {
    inner: R,
    count: Arc<AtomicU64>,
}

impl<R: Read> Read for CountingReader<R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = self.inner.read(buf)?;
        self.count.fetch_add(n as u64, Ordering::Relaxed);
        Ok(n)
    }
}

// ─── extração ────────────────────────────────────────────────────────────

#[derive(Clone, Copy, PartialEq, Eq)]
enum Detected {
    Zip,
    Gzip,
    Tar,
}

fn detect(path: &Path) -> io::Result<Detected> {
    let mut f = File::open(path)?;
    let mut head = [0u8; 512];
    let n = f.read(&mut head)?;
    if n >= 4 && head[0] == b'P' && head[1] == b'K' && matches!((head[2], head[3]), (3, 4) | (5, 6)) {
        return Ok(Detected::Zip);
    }
    if n >= 2 && head[0] == 0x1f && head[1] == 0x8b {
        return Ok(Detected::Gzip);
    }
    if n >= 262 && &head[257..262] == b"ustar" {
        return Ok(Detected::Tar);
    }
    Err(err("formato de arquivo compactado não suportado (use .zip, .tar ou .tar.gz)"))
}

struct Extractor {
    root: PathBuf,
    written: u64,
    entries: u64,
    skipped: u64,
    compressed_hint: u64,
    seen: HashSet<PathBuf>,
    last_space_check: u64,
}

impl Extractor {
    fn new(root: &Path, archive_size: u64) -> Self {
        Extractor { root: root.to_path_buf(), written: 0, entries: 0, skipped: 0, compressed_hint: archive_size, seen: HashSet::new(), last_space_check: 0 }
    }

    fn count_entry(&mut self) -> io::Result<()> {
        self.entries += 1;
        if self.entries > MAX_ENTRIES {
            return Err(err("arquivo compactado com entradas demais (limite de 1.000.000)"));
        }
        Ok(())
    }

    fn check_limits(&mut self) -> io::Result<()> {
        if self.written > MAX_TOTAL_BYTES {
            return Err(err("conteúdo extraído excede o limite de 100 GiB"));
        }
        if self.written > RATIO_CHECK_FROM && self.written / self.compressed_hint.max(1) > MAX_RATIO {
            return Err(err("razão de compressão suspeita (possível zip bomb); extração abortada"));
        }
        if self.written - self.last_space_check >= 64 * 1024 * 1024 {
            self.last_space_check = self.written;
            if available_space(&self.root) < DISK_RESERVE {
                return Err(err("espaço em disco insuficiente"));
            }
        }
        Ok(())
    }

    fn make_dir(&mut self, rel: &Path, mode: u32) -> io::Result<()> {
        let full = prepare_parent(&self.root, rel)?;
        match fs::symlink_metadata(&full) {
            Ok(m) if m.is_dir() => {}
            Ok(_) => return Err(err("conflito entre arquivo e diretório")),
            Err(e) if e.kind() == io::ErrorKind::NotFound => fs::create_dir(&full)?,
            Err(e) => return Err(e),
        }
        fs::set_permissions(&full, fs::Permissions::from_mode(safe_mode(mode, true)))?;
        Ok(())
    }

    fn make_symlink(&mut self, rel: &Path, target: &[u8]) -> io::Result<()> {
        if !symlink_target_ok(rel, target) {
            self.skipped += 1;
            return Ok(());
        }
        let full = prepare_parent(&self.root, rel)?;
        std::os::unix::fs::symlink(OsStr::from_bytes(target), full)
    }

    /// Escreve um arquivo regular lendo no máximo `declared` bytes (a entrada não pode mentir sobre o tamanho)
    fn write_file(&mut self, rel: &Path, mode: u32, reader: &mut dyn Read, declared: u64, prog: &mut Progress, on_bytes: &mut dyn FnMut(u64) -> u64) -> io::Result<()> {
        let full = prepare_parent(&self.root, rel)?;
        // Em sistemas sem diferenciar maiúsculas (FAT/NTFS), "README" e "readme" colidem: o segundo é ignorado, nunca sobrescreve
        let mut out = match create_new_file(&full) {
            Ok(f) => f,
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => {
                self.skipped += 1;
                return Ok(());
            }
            Err(e) => return Err(e),
        };
        let mut buf = vec![0u8; CHUNK];
        let mut remaining = declared;
        while remaining > 0 {
            let want = buf.len().min(remaining as usize);
            let n = reader.read(&mut buf[..want])?;
            if n == 0 {
                break;
            }
            out.write_all(&buf[..n])?;
            remaining -= n as u64;
            self.written += n as u64;
            self.check_limits()?;
            prog.done = on_bytes(n as u64);
            prog.emit(false);
        }
        // Se ainda há dados além do tamanho declarado, a entrada mente: aborta
        let mut probe = [0u8; 1];
        if remaining == 0 && reader.read(&mut probe)? > 0 {
            return Err(err("entrada maior que o tamanho declarado"));
        }
        out.flush()?;
        drop(out);
        fs::set_permissions(&full, fs::Permissions::from_mode(safe_mode(mode, false)))?;
        Ok(())
    }
}

/// Extrai `archive` para uma pasta nova dentro de `out_dir`. Devolve a pasta criada.
pub fn extract(archive: &Path, out_dir: &Path) -> io::Result<PathBuf> {
    let meta = fs::metadata(archive)?;
    if !meta.is_file() {
        return Err(err("o item escolhido não é um arquivo"));
    }
    if !out_dir.is_dir() {
        return Err(io::Error::new(io::ErrorKind::NotFound, "pasta de destino não existe"));
    }
    let kind = detect(archive)?;
    let archive_size = meta.len();
    if available_space(out_dir) < DISK_RESERVE {
        return Err(err("espaço em disco insuficiente"));
    }

    let root = create_unique_dir(out_dir, &archive_stem(archive))?;
    let started = Instant::now();
    let result = match kind {
        Detected::Zip => extract_zip(archive, &root, archive_size),
        Detected::Gzip => extract_tar(archive, &root, archive_size, true),
        Detected::Tar => extract_tar(archive, &root, archive_size, false),
    };

    match result {
        Ok((bytes, skipped)) => {
            emit(json!({
                "event": "done",
                "paths": [&root],
                "bytes": bytes,
                "seconds": started.elapsed().as_secs_f64(),
                "skipped": skipped,
            }));
            Ok(root)
        }
        Err(e) => {
            // Remove só a pasta que nós mesmos criamos
            let _ = fs::remove_dir_all(&root);
            Err(e)
        }
    }
}

fn extract_zip(archive: &Path, root: &Path, archive_size: u64) -> io::Result<(u64, u64)> {
    let file = File::open(archive)?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| err(format!("zip inválido: {e}")))?;
    if zip.len() as u64 > MAX_ENTRIES {
        return Err(err("arquivo compactado com entradas demais (limite de 1.000.000)"));
    }

    // Tamanho total declarado: serve para barra de progresso e checagem prévia de espaço
    let mut declared_total: u64 = 0;
    for i in 0..zip.len() {
        if let Ok(f) = zip.by_index_raw(i) {
            declared_total = declared_total.saturating_add(f.size());
        }
    }
    if declared_total > MAX_TOTAL_BYTES {
        return Err(err("conteúdo extraído excede o limite de 100 GiB"));
    }
    if declared_total.saturating_add(DISK_RESERVE) > available_space(root) {
        return Err(err("espaço em disco insuficiente"));
    }

    let mut ex = Extractor::new(root, archive_size);
    let mut prog = Progress::new(declared_total, 1, root);
    emit(json!({ "event": "start", "mode": "extract", "total": declared_total, "items": 1, "dest": root }));

    let mut done: u64 = 0;
    for i in 0..zip.len() {
        let mut entry = match zip.by_index(i) {
            Ok(e) => e,
            Err(zip::result::ZipError::UnsupportedArchive(m)) if m.to_lowercase().contains("password") || m.to_lowercase().contains("encrypt") => {
                return Err(err("arquivo protegido por senha não é suportado"));
            }
            Err(e) => return Err(err(format!("entrada inválida no zip: {e}"))),
        };
        ex.count_entry()?;

        let raw_name = entry.name_raw().to_vec();
        let Some(rel) = safe_relative(&raw_name, true) else {
            ex.skipped += 1;
            continue;
        };
        prog.name = rel.to_string_lossy().to_string();
        let mode = entry.unix_mode().unwrap_or(if entry.is_dir() { 0o755 } else { 0o644 });
        let kind_bits = mode & 0o170000;

        if entry.is_dir() {
            ex.make_dir(&rel, mode)?;
        } else if kind_bits == 0o120000 {
            let mut target = Vec::new();
            (&mut entry).take(MAX_SYMLINK_TARGET + 1).read_to_end(&mut target)?;
            if target.len() as u64 > MAX_SYMLINK_TARGET {
                ex.skipped += 1;
            } else {
                ex.make_symlink(&rel, &target)?;
            }
        } else if kind_bits != 0 && kind_bits != 0o100000 {
            // FIFO, dispositivo, socket...
            ex.skipped += 1;
        } else {
            if !ex.seen.insert(rel.clone()) {
                ex.skipped += 1;
                continue;
            }
            let declared = entry.size();
            ex.compressed_hint = archive_size;
            let before = done;
            let mut counter = before;
            let mut on_bytes = |n: u64| { counter += n; counter };
            ex.write_file(&rel, mode, &mut entry, declared, &mut prog, &mut on_bytes)?;
            done = counter;
        }
        prog.done = done;
        prog.index = 0;
    }
    prog.done = prog.total.max(done);
    prog.emit(true);
    Ok((ex.written, ex.skipped))
}

fn extract_tar(archive: &Path, root: &Path, archive_size: u64, gz: bool) -> io::Result<(u64, u64)> {
    let file = File::open(archive)?;
    let pos = Arc::new(AtomicU64::new(0));
    let counting = CountingReader { inner: file, count: pos.clone() };
    let reader: Box<dyn Read> = if gz { Box::new(flate2::read::GzDecoder::new(counting)) } else { Box::new(counting) };
    let mut tar = tar::Archive::new(reader);

    let mut ex = Extractor::new(root, archive_size);
    let mut prog = Progress::new(archive_size, 1, root);
    emit(json!({ "event": "start", "mode": "extract", "total": archive_size, "items": 1, "dest": root }));

    let entries = tar.entries().map_err(|e| err(format!("tar inválido: {e}")))?;
    for entry in entries {
        let mut entry = entry.map_err(|e| err(format!("entrada inválida no tar: {e}")))?;
        ex.count_entry()?;

        let raw = entry.path_bytes().to_vec();
        let Some(rel) = safe_relative(&raw, false) else {
            ex.skipped += 1;
            continue;
        };
        prog.name = rel.to_string_lossy().to_string();
        let mode = entry.header().mode().unwrap_or(0o644);
        let etype = entry.header().entry_type();

        use tar::EntryType as T;
        match etype {
            T::Directory => ex.make_dir(&rel, mode)?,
            T::Regular | T::Continuous => {
                if !ex.seen.insert(rel.clone()) {
                    ex.skipped += 1;
                    continue;
                }
                let declared = entry.header().size().map_err(|e| err(format!("tamanho inválido: {e}")))?;
                let pos2 = pos.clone();
                let mut on_bytes = move |_n: u64| pos2.load(Ordering::Relaxed);
                ex.write_file(&rel, mode, &mut entry, declared, &mut prog, &mut on_bytes)?;
            }
            T::Symlink => {
                let target = entry.link_name_bytes().map(|c| c.to_vec()).unwrap_or_default();
                ex.make_symlink(&rel, &target)?;
            }
            // Hard links, dispositivos, FIFOs e extensões: ignorados
            _ => ex.skipped += 1,
        }
        prog.done = pos.load(Ordering::Relaxed).min(prog.total);
        prog.emit(false);
    }
    prog.done = prog.total;
    prog.emit(true);
    Ok((ex.written, ex.skipped))
}

// ─── compactação ─────────────────────────────────────────────────────────

/// Compacta `sources` em um arquivo novo dentro de `out_dir`. `name` é o nome-base quando há vários itens.
pub fn compress(format: ArchiveFormat, sources: &[PathBuf], out_dir: &Path, name: Option<&str>) -> io::Result<PathBuf> {
    if sources.is_empty() {
        return Err(err("nada para compactar"));
    }
    if !out_dir.is_dir() {
        return Err(io::Error::new(io::ErrorKind::NotFound, "pasta de destino não existe"));
    }
    let mut total: u64 = 0;
    for src in sources {
        let m = fs::symlink_metadata(src).map_err(|_| io::Error::new(io::ErrorKind::NotFound, format!("origem não encontrada: {}", src.display())))?;
        if src.file_name().is_none() {
            return Err(err("nome de origem inválido"));
        }
        // Não permite compactar a pasta de destino dentro de si própria de forma recursiva infinita:
        // o arquivo de saída é excluído da varredura abaixo.
        total = total.saturating_add(if m.is_dir() { tree_size(src) } else if m.is_file() { m.len() } else { 0 });
    }
    if total.saturating_add(DISK_RESERVE) > available_space(out_dir) {
        return Err(err("espaço em disco insuficiente"));
    }

    let base = if sources.len() == 1 {
        sources[0].file_name().unwrap().to_string_lossy().to_string()
    } else {
        name.filter(|n| !n.is_empty() && !n.contains('/') && !n.contains('\0')).unwrap_or("Archive").to_string()
    };

    // Escreve num arquivo temporário (O_EXCL) e só publica com link atômico no fim
    let (part_path, part_file) = create_part_file(out_dir, &base, format)?;
    let mut prog = Progress::new(total, sources.len(), &part_path);
    emit(json!({ "event": "start", "mode": "compress", "total": total, "items": sources.len(), "dest": part_path }));
    let started = Instant::now();

    let result = match format {
        ArchiveFormat::Zip => write_zip(part_file, sources, &part_path, &mut prog),
        ArchiveFormat::TarGz => write_targz(part_file, sources, &part_path, &mut prog),
    };

    let skipped = match result {
        Ok(s) => s,
        Err(e) => {
            let _ = fs::remove_file(&part_path);
            return Err(e);
        }
    };

    match publish(&part_path, out_dir, &base, format) {
        Ok(final_path) => {
            prog.emit(true);
            emit(json!({
                "event": "done",
                "paths": [&final_path],
                "bytes": prog.done,
                "seconds": started.elapsed().as_secs_f64(),
                "skipped": skipped,
            }));
            Ok(final_path)
        }
        Err(e) => {
            let _ = fs::remove_file(&part_path);
            Err(e)
        }
    }
}

fn create_part_file(dir: &Path, base: &str, format: ArchiveFormat) -> io::Result<(PathBuf, File)> {
    for i in 0..10_000u32 {
        let name = format!(".{}{}.{}.part", base, format.extension(), if i == 0 { std::process::id().to_string() } else { format!("{}-{}", std::process::id(), i) });
        let path = dir.join(name);
        match create_new_file(&path) {
            Ok(f) => return Ok((path, f)),
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => return Err(e),
        }
    }
    Err(err("não foi possível criar arquivo temporário"))
}

/// Move o temporário para o nome final sem sobrescrever nada (hard link falha se o destino existe)
fn publish(part: &Path, dir: &Path, base: &str, format: ArchiveFormat) -> io::Result<PathBuf> {
    for i in 0..10_000u32 {
        let name = if i == 0 { format!("{}{}", base, format.extension()) } else { format!("{} ({}){}", base, i, format.extension()) };
        let target = dir.join(name);
        match fs::hard_link(part, &target) {
            Ok(_) => {
                fs::set_permissions(&target, fs::Permissions::from_mode(0o600))?;
                let _ = fs::remove_file(part);
                return Ok(target);
            }
            Err(e) if e.kind() == io::ErrorKind::AlreadyExists => continue,
            Err(e) => {
                // Sistemas sem hard link (FAT/exFAT): rename só se o destino realmente não existe
                if !target.exists() && fs::rename(part, &target).is_ok() {
                    return Ok(target);
                }
                return Err(e);
            }
        }
    }
    Err(err("não foi possível escolher um nome livre para o arquivo compactado"))
}

struct Item {
    abs: PathBuf,
    rel: String,
    kind: ItemKind,
    mode: u32,
    mtime: i64,
    size: u64,
}

enum ItemKind {
    Dir,
    File,
    Symlink(PathBuf),
}

/// Lista, sem seguir links simbólicos, tudo o que entra no arquivo. Ignora o próprio arquivo de saída.
fn collect_items(sources: &[PathBuf], part: &Path, skipped: &mut u64) -> io::Result<Vec<Item>> {
    use std::os::unix::fs::MetadataExt;
    let part_id = fs::metadata(part).map(|m| (m.dev(), m.ino())).ok();
    let mut items = Vec::new();
    let mut seen_top: HashSet<String> = HashSet::new();
    for src in sources {
        let top = src.file_name().unwrap().to_string_lossy().to_string();
        if !seen_top.insert(top.clone()) {
            return Err(err(format!("dois itens com o mesmo nome: {top}")));
        }
        for entry in WalkDir::new(src).follow_links(false).sort_by_file_name() {
            let entry = match entry {
                Ok(e) => e,
                Err(_) => { *skipped += 1; continue; }
            };
            let abs = entry.path().to_path_buf();
            let Ok(meta) = entry.metadata() else { *skipped += 1; continue };
            // Nunca inclui o arquivo que está sendo gerado (compara dispositivo e inode)
            if Some((meta.dev(), meta.ino())) == part_id {
                continue;
            }
            let relp = abs.strip_prefix(src.parent().unwrap_or(Path::new("/"))).unwrap_or(&abs);
            let Some(rel) = relp.to_str().map(|s| s.to_string()) else { *skipped += 1; continue };
            let mode = meta.permissions().mode() & 0o777;
            let mtime = meta.mtime();
            let ft = meta.file_type();
            if ft.is_dir() {
                items.push(Item { abs, rel, kind: ItemKind::Dir, mode, mtime, size: 0 });
            } else if ft.is_file() {
                items.push(Item { abs, rel, kind: ItemKind::File, mode, mtime, size: meta.len() });
            } else if ft.is_symlink() {
                match fs::read_link(entry.path()) {
                    Ok(t) => items.push(Item { abs, rel, kind: ItemKind::Symlink(t), mode, mtime, size: 0 }),
                    Err(_) => *skipped += 1,
                }
            } else {
                // sockets, FIFOs, dispositivos
                *skipped += 1;
            }
        }
    }
    if items.len() as u64 > MAX_ENTRIES {
        return Err(err("itens demais para compactar (limite de 1.000.000)"));
    }
    Ok(items)
}

fn open_for_read(path: &Path) -> io::Result<File> {
    OpenOptions::new().read(true).custom_flags(libc::O_NOFOLLOW).open(path)
}

fn write_zip(out: File, sources: &[PathBuf], part: &Path, prog: &mut Progress) -> io::Result<u64> {
    use zip::write::SimpleFileOptions;
    let mut skipped = 0u64;
    let items = collect_items(sources, part, &mut skipped)?;
    let mut zw = zip::ZipWriter::new(out);

    for item in &items {
        prog.name = item.rel.clone();
        let opts = SimpleFileOptions::default()
            .compression_method(zip::CompressionMethod::Deflated)
            .unix_permissions(item.mode)
            .large_file(item.size >= 4 * 1024 * 1024 * 1024);
        match &item.kind {
            ItemKind::Dir => zw.add_directory(&item.rel, opts).map_err(|e| err(e.to_string()))?,
            ItemKind::Symlink(target) => zw
                .add_symlink(&item.rel, target.to_string_lossy(), opts)
                .map_err(|e| err(e.to_string()))?,
            ItemKind::File => {
                let mut f = match open_for_read(&item.abs) {
                    Ok(f) => f,
                    Err(_) => { skipped += 1; continue }
                };
                zw.start_file(&item.rel, opts).map_err(|e| err(e.to_string()))?;
                let mut buf = vec![0u8; CHUNK];
                loop {
                    let n = f.read(&mut buf)?;
                    if n == 0 { break; }
                    zw.write_all(&buf[..n])?;
                    prog.done += n as u64;
                    prog.emit(false);
                }
            }
        }
    }
    let mut file = zw.finish().map_err(|e| err(e.to_string()))?;
    file.flush()?;
    Ok(skipped)
}

fn write_targz(out: File, sources: &[PathBuf], part: &Path, prog: &mut Progress) -> io::Result<u64> {
    let mut skipped = 0u64;
    let items = collect_items(sources, part, &mut skipped)?;
    let gz = flate2::write::GzEncoder::new(out, flate2::Compression::default());
    let mut builder = tar::Builder::new(gz);
    builder.follow_symlinks(false);

    for item in &items {
        prog.name = item.rel.clone();
        let mut header = tar::Header::new_gnu();
        header.set_mode(item.mode);
        header.set_mtime(item.mtime.max(0) as u64);
        // Não vaza dono/grupo da máquina de origem
        header.set_uid(0);
        header.set_gid(0);
        match &item.kind {
            ItemKind::Dir => {
                header.set_entry_type(tar::EntryType::Directory);
                header.set_size(0);
                builder.append_data(&mut header, format!("{}/", item.rel.trim_end_matches('/')), io::empty())?;
            }
            ItemKind::Symlink(target) => {
                header.set_entry_type(tar::EntryType::Symlink);
                header.set_size(0);
                builder.append_link(&mut header, &item.rel, target)?;
            }
            ItemKind::File => {
                let f = match open_for_read(&item.abs) {
                    Ok(f) => f,
                    Err(_) => { skipped += 1; continue }
                };
                // O tamanho vem do arquivo já aberto, para não divergir se ele mudar durante a leitura
                let size = f.metadata()?.len();
                header.set_entry_type(tar::EntryType::Regular);
                header.set_size(size);
                let mut counter = ProgressReader { inner: f.take(size), prog };
                builder.append_data(&mut header, &item.rel, &mut counter)?;
            }
        }
    }
    let gz = builder.into_inner()?;
    let mut file = gz.finish()?;
    file.flush()?;
    Ok(skipped)
}

struct ProgressReader<'a, R> {
    inner: R,
    prog: &'a mut Progress,
}

impl<R: Read> Read for ProgressReader<'_, R> {
    fn read(&mut self, buf: &mut [u8]) -> io::Result<usize> {
        let n = self.inner.read(buf)?;
        self.prog.done += n as u64;
        self.prog.emit(false);
        Ok(n)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;

    fn scratch(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("kappa-archive-{}-{}", name, std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    /// Monta um .tar.gz "à mão", com o nome da entrada escrito direto no cabeçalho (sem a validação do crate)
    fn raw_tar_gz(entries: &[(&str, tar::EntryType, &[u8], u32, &str)]) -> Vec<u8> {
        let mut raw = Vec::new();
        for (name, ty, data, mode, link) in entries {
            let mut h = tar::Header::new_gnu();
            h.set_entry_type(*ty);
            h.set_size(data.len() as u64);
            h.set_mode(*mode);
            {
                let old = h.as_old_mut();
                old.name[..name.len()].copy_from_slice(name.as_bytes());
                if !link.is_empty() {
                    old.linkname[..link.len()].copy_from_slice(link.as_bytes());
                }
            }
            h.set_cksum();
            raw.extend_from_slice(h.as_bytes());
            raw.extend_from_slice(data);
            let pad = (512 - data.len() % 512) % 512;
            raw.extend(std::iter::repeat(0u8).take(pad));
        }
        raw.extend(std::iter::repeat(0u8).take(1024));
        let mut gz = flate2::write::GzEncoder::new(Vec::new(), flate2::Compression::default());
        gz.write_all(&raw).unwrap();
        gz.finish().unwrap()
    }

    fn raw_zip(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let mut w = zip::ZipWriter::new(io::Cursor::new(Vec::new()));
        for (name, data) in entries {
            w.start_file(*name, zip::write::SimpleFileOptions::default()).unwrap();
            w.write_all(data).unwrap();
        }
        w.finish().unwrap().into_inner()
    }

    fn files_under(root: &Path) -> Vec<String> {
        let mut v: Vec<String> = WalkDir::new(root).into_iter().filter_map(|e| e.ok()).filter(|e| e.file_type().is_file()).map(|e| e.path().strip_prefix(root).unwrap().to_string_lossy().to_string()).collect();
        v.sort();
        v
    }

    #[test]
    fn rejects_unsafe_entry_names() {
        for bad in ["../x", "a/../../x", "/etc/passwd", "a/../..", "..", "", "a\0b", "a/\nb"] {
            assert!(safe_relative(bad.as_bytes(), false).is_none(), "deveria rejeitar {bad:?}");
        }
        assert!(safe_relative(b"..\\evil", true).is_none());
        assert!(safe_relative(b"dir\\..\\..\\evil", true).is_none());
        assert_eq!(safe_relative(b"./a/./b.txt", false).unwrap(), PathBuf::from("a/b.txt"));
        assert!(safe_relative("x".repeat(300).as_bytes(), false).is_none());
    }

    #[test]
    fn symlink_targets_must_stay_inside() {
        assert!(symlink_target_ok(Path::new("a/link"), b"../b"));
        assert!(symlink_target_ok(Path::new("link"), b"dir/file"));
        assert!(!symlink_target_ok(Path::new("link"), b"../outside"));
        assert!(!symlink_target_ok(Path::new("a/link"), b"../../outside"));
        assert!(!symlink_target_ok(Path::new("link"), b"/etc/passwd"));
        assert!(!symlink_target_ok(Path::new("link"), b""));
    }

    #[test]
    fn zip_slip_entries_never_leave_the_destination() {
        let root = scratch("zipslip");
        let out = root.join("out");
        fs::create_dir_all(&out).unwrap();
        let zip_path = root.join("evil.zip");
        fs::write(&zip_path, raw_zip(&[("../escaped.txt", b"x"), ("/tmp/kappa-abs-escape.txt", b"x"), ("a/../../escaped2.txt", b"x"), ("..\\win.txt", b"x"), ("ok/fine.txt", b"fine")])).unwrap();

        let dir = extract(&zip_path, &out).unwrap();
        assert_eq!(files_under(&dir), vec!["ok/fine.txt".to_string()]);
        assert!(!root.join("escaped.txt").exists());
        assert!(!out.join("escaped.txt").exists());
        assert!(!root.join("escaped2.txt").exists());
        assert!(!Path::new("/tmp/kappa-abs-escape.txt").exists());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn tar_traversal_and_symlink_escape_are_blocked() {
        let root = scratch("tarslip");
        let out = root.join("out");
        let outside = root.join("outside");
        fs::create_dir_all(&out).unwrap();
        fs::create_dir_all(&outside).unwrap();

        use tar::EntryType as T;
        let abs_link = outside.to_string_lossy().to_string();
        let data = raw_tar_gz(&[
            ("../traversal.txt", T::Regular, b"x", 0o644, ""),
            ("abslink", T::Symlink, b"", 0o777, &abs_link),
            ("abslink/pwned.txt", T::Regular, b"x", 0o644, ""),
            ("uplink", T::Symlink, b"", 0o777, "../outside"),
            ("uplink/pwned2.txt", T::Regular, b"x", 0o644, ""),
            ("hard", T::Link, b"", 0o644, "/etc/passwd"),
            ("good.txt", T::Regular, b"ok", 0o644, ""),
        ]);
        let archive = root.join("evil.tar.gz");
        fs::write(&archive, data).unwrap();

        let dir = extract(&archive, &out).unwrap();
        // Os links hostis são descartados; os arquivos "dentro" deles viram pastas comuns dentro do destino
        assert_eq!(files_under(&dir), vec!["abslink/pwned.txt".to_string(), "good.txt".to_string(), "uplink/pwned2.txt".to_string()]);
        assert!(fs::read_dir(&outside).unwrap().next().is_none(), "nada pode ser escrito fora da pasta");
        assert!(!root.join("traversal.txt").exists());
        assert!(!fs::symlink_metadata(dir.join("abslink")).unwrap().file_type().is_symlink());
        assert!(!fs::symlink_metadata(dir.join("uplink")).unwrap().file_type().is_symlink());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn writes_never_go_through_a_link_created_by_the_archive() {
        // Link relativo permitido (aponta para dentro); gravar "via" ele ainda é bloqueado
        let root = scratch("viasym");
        let out = root.join("out");
        fs::create_dir_all(&out).unwrap();
        use tar::EntryType as T;
        let data = raw_tar_gz(&[
            ("real", T::Directory, b"", 0o755, ""),
            ("via", T::Symlink, b"", 0o777, "real"),
            ("via/file.txt", T::Regular, b"x", 0o644, ""),
        ]);
        let archive = root.join("a.tar.gz");
        fs::write(&archive, data).unwrap();
        let res = extract(&archive, &out);
        // O arquivo atravessaria um link: a extração falha e a pasta parcial some
        assert!(res.is_err());
        assert_eq!(fs::read_dir(&out).unwrap().count(), 0, "pasta parcial deve ser removida");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn special_bits_are_stripped_and_special_files_skipped() {
        let root = scratch("modes");
        let out = root.join("out");
        fs::create_dir_all(&out).unwrap();
        use tar::EntryType as T;
        let data = raw_tar_gz(&[
            ("suid", T::Regular, b"x", 0o4777, ""),
            ("sgid", T::Regular, b"x", 0o2755, ""),
            ("private", T::Regular, b"x", 0o600, ""),
            ("fifo", T::Fifo, b"", 0o644, ""),
            ("dev", T::Char, b"", 0o644, ""),
        ]);
        let archive = root.join("m.tar.gz");
        fs::write(&archive, data).unwrap();
        let dir = extract(&archive, &out).unwrap();
        let mode = |n: &str| fs::metadata(dir.join(n)).unwrap().permissions().mode() & 0o7777;
        assert_eq!(mode("suid"), 0o755);
        assert_eq!(mode("sgid"), 0o755);
        assert_eq!(mode("private"), 0o600);
        assert!(!dir.join("fifo").exists() && !dir.join("dev").exists());
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn extraction_never_overwrites_existing_folders() {
        let root = scratch("nooverwrite");
        fs::write(root.join("pack.zip"), raw_zip(&[("a.txt", b"new")])).unwrap();
        fs::create_dir_all(root.join("pack")).unwrap();
        fs::write(root.join("pack/a.txt"), "OLD").unwrap();

        let dir = extract(&root.join("pack.zip"), &root).unwrap();
        assert_eq!(dir, root.join("pack (1)"));
        assert_eq!(fs::read_to_string(root.join("pack/a.txt")).unwrap(), "OLD");
        assert_eq!(fs::read_to_string(dir.join("a.txt")).unwrap(), "new");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn rejects_unknown_formats_and_cleans_up() {
        let root = scratch("unknown");
        fs::write(root.join("notes.zip"), b"this is not an archive").unwrap();
        assert!(extract(&root.join("notes.zip"), &root).is_err());
        assert_eq!(fs::read_dir(&root).unwrap().count(), 1, "nenhuma pasta deve ser deixada para trás");
        // zip truncado/corrompido: erro e sem sobra
        let mut bytes = raw_zip(&[("a.txt", b"hello world")]);
        bytes.truncate(bytes.len() / 2);
        fs::write(root.join("broken.zip"), bytes).unwrap();
        assert!(extract(&root.join("broken.zip"), &root).is_err());
        assert_eq!(fs::read_dir(&root).unwrap().count(), 2);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn compress_roundtrip_keeps_links_unfollowed_and_modes_private() {
        for format in [ArchiveFormat::Zip, ArchiveFormat::TarGz] {
            let root = scratch(&format!("rt-{}", format.extension().trim_start_matches('.').replace('.', "")));
            let secret_dir = root.join("secret");
            fs::create_dir_all(&secret_dir).unwrap();
            fs::write(secret_dir.join("token.txt"), "TOP-SECRET").unwrap();

            let src = root.join("proj");
            fs::create_dir_all(src.join("sub")).unwrap();
            fs::write(src.join("sub/a.txt"), "hello").unwrap();
            fs::write(src.join("run.sh"), "#!/bin/sh\n").unwrap();
            fs::set_permissions(src.join("run.sh"), fs::Permissions::from_mode(0o755)).unwrap();
            // Link para fora: deve ser guardado como link, jamais seguido
            symlink(&secret_dir, src.join("leak")).unwrap();

            let out = compress(format, &[src.clone()], &root, None).unwrap();
            assert_eq!(fs::metadata(&out).unwrap().permissions().mode() & 0o777, 0o600, "arquivo gerado é privado");
            assert!(!fs::read_dir(&root).unwrap().filter_map(|e| e.ok()).any(|e| e.file_name().to_string_lossy().ends_with(".part")), "sem temporários");

            // O conteúdo do alvo do link não pode ter sido copiado para dentro do arquivo
            let bytes = fs::read(&out).unwrap();
            assert!(!bytes.windows(10).any(|w| w == b"TOP-SECRET"));

            let extracted = extract(&out, &root).unwrap();
            assert_eq!(fs::read_to_string(extracted.join("proj/sub/a.txt")).unwrap(), "hello");
            assert_eq!(fs::metadata(extracted.join("proj/run.sh")).unwrap().permissions().mode() & 0o777, 0o755);
            // O link vem como link (alvo absoluto é descartado na extração por segurança)
            assert!(!extracted.join("proj/leak/token.txt").exists());
            let _ = fs::remove_dir_all(&root);
        }
    }

    #[test]
    fn compress_never_overwrites_and_skips_its_own_output() {
        let root = scratch("noover");
        let src = root.join("data");
        fs::create_dir_all(&src).unwrap();
        fs::write(src.join("f.txt"), "x").unwrap();
        // Já existe um data.zip: o novo recebe outro nome
        fs::write(root.join("data.zip"), "KEEP").unwrap();
        let out = compress(ArchiveFormat::Zip, &[src.clone()], &root, None).unwrap();
        assert_eq!(out, root.join("data (1).zip"));
        assert_eq!(fs::read_to_string(root.join("data.zip")).unwrap(), "KEEP");

        // Compactar a pasta que recebe o arquivo gerado: o arquivo não entra nele mesmo
        let out2 = compress(ArchiveFormat::TarGz, &[src.clone()], &src, None).unwrap();
        let dir = extract(&out2, &root).unwrap();
        assert_eq!(files_under(&dir), vec!["data/f.txt".to_string()]);
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn compress_rejects_missing_sources_and_duplicate_names() {
        let root = scratch("reject");
        assert!(compress(ArchiveFormat::Zip, &[root.join("nope")], &root, None).is_err());
        fs::create_dir_all(root.join("x/a")).unwrap();
        fs::create_dir_all(root.join("y/a")).unwrap();
        assert!(compress(ArchiveFormat::Zip, &[root.join("x/a"), root.join("y/a")], &root, Some("Pack")).is_err());
        assert_eq!(fs::read_dir(&root).unwrap().filter_map(|e| e.ok()).filter(|e| e.file_name().to_string_lossy().starts_with('.')).count(), 0, "sem temporários");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn colliding_names_are_skipped_never_overwritten() {
        let root = scratch("collide");
        let out = root.join("out");
        fs::create_dir_all(&out).unwrap();
        use tar::EntryType as T;
        // Mesma entrada duas vezes (em FAT/NTFS "README" e "readme" colidem do mesmo jeito)
        let data = raw_tar_gz(&[("a.txt", T::Regular, b"first", 0o644, ""), ("b/../a.txt", T::Regular, b"x", 0o644, ""), ("a.txt", T::Regular, b"second", 0o644, "")]);
        let archive = root.join("c.tar.gz");
        fs::write(&archive, data).unwrap();
        let dir = extract(&archive, &out).unwrap();
        assert_eq!(fs::read_to_string(dir.join("a.txt")).unwrap(), "first");
        let _ = fs::remove_dir_all(&root);
    }

    #[test]
    fn hostile_names_survive_a_compress_extract_roundtrip() {
        for format in [ArchiveFormat::Zip, ArchiveFormat::TarGz] {
            let root = scratch("hostile-rt");
            let src = root.join("pack");
            fs::create_dir_all(&src).unwrap();
            let names = ["-rf", "$(touch PWNED)", "@x", "a b; c", "<b>x<b>"];
            for n in names {
                fs::write(src.join(n), n).unwrap();
            }
            let arc = compress(format, &[src.clone()], &root, None).unwrap();
            let dir = extract(&arc, &root).unwrap();
            for n in names {
                assert_eq!(fs::read_to_string(dir.join("pack").join(n)).unwrap(), n);
            }
            assert!(!root.join("PWNED").exists());
            let _ = fs::remove_dir_all(&root);
        }
    }
}
