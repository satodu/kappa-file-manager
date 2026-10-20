# Security

Kappa is a file manager, so it handles untrusted names, links, paths and archives. How it behaves:

**Opening files**
- Opening a file that could run code (an ELF program, a script with `#!`, a `.desktop` launcher, `.sh`, `.AppImage`, ...) asks for confirmation first. The check looks at the file *content*, so `invoice.pdf` that is really a script is still caught. `Enter` never confirms; you must click "Open anyway".
- Kappa never executes a file itself: it hands it to `xdg-open`, and only with an absolute path.

**Paths and names**
- A new name (rename, new folder) is a single path component: no `/`, no `.`/`..`, no control characters. Renaming never overwrites an existing item.
- Every path received by the backend must be absolute. Deleting refuses `/`, top-level folders (`/home`, `/etc`, ...) and `$HOME`.
- File and folder names are always drawn as plain text, never as HTML.

**Archives (`.zip`, `.tar`, `.tar.gz`, `.tgz`)**
- Extraction always goes to a brand new folder; nothing existing is overwritten. On any error the partial folder is removed.
- Entries with absolute paths, `..`, control characters or over-long names are skipped (zip-slip). Writes never go through a symbolic link and files are opened with `O_NOFOLLOW | O_EXCL`.
- Symbolic links are recreated only if relative and pointing inside the destination. Hard links, devices, pipes and sockets are skipped. setuid/setgid/sticky bits and group/other write are dropped, and ownership is never restored.
- Limits against decompression bombs: 1,000,000 entries, 100 GiB total, a compression-ratio check, no entry larger than it declares, and a free-disk-space reserve. Password-protected zips are refused.
- Compression never follows symbolic links, skips pipes/sockets/devices, never includes its own output, never overwrites an existing archive, writes to a private temporary file and publishes it atomically. New archives are created with mode `0600`.

**Copy and move**
- Symbolic links are copied as links and never followed; pipes, sockets and devices are skipped.
- Folders keep their permissions (a private `0700` folder stays private) and setuid/setgid bits are not copied.
- Text pasted from other applications is only treated as files when it is a list of `file://` URIs.

**Thumbnails and previews**
- Only PNG, JPEG, GIF, WebP and BMP up to 32 MiB are decoded, scaled while decoding. No SVG, PDF or video is ever parsed.

**Commands, network and credentials**
- External commands (`xdg-open`, `kdeconnect-cli`, `udisksctl`, `matugen`, ...) are started with argument lists, never by building a shell string. Device ids and block devices are validated before use, so they cannot become options. Values read from `~/.config/kappa/theme.json` are validated first.
- Kappa has no custom actions or plugins, no network protocol client and stores no credentials. Phone access goes through KDE Connect, which owns its keys and trust.
- Kappa does not change file permissions or ownership (no `chmod`/`chown`).
- Deleting asks for confirmation; `Shift+Del` deletes permanently and needs an explicit extra confirmation.

**Races (TOCTOU) and privileges**
- Kappa refuses to run as root unless `KAPPA_ALLOW_ROOT` is set, and never asks for elevated privileges (no `sudo`, `pkexec` or setuid helpers). A race therefore cannot be turned into privilege escalation: every operation runs with your own permissions.
- Files are created with `O_EXCL` (never overwriting), source files are opened with `O_NOFOLLOW`, and moves and renames use `RENAME_NOREPLACE`. A source swapped for a symbolic link after it was checked makes the operation fail instead of following the link.

**Logs, history and caches**
- Kappa keeps no history: no recent files, no search history, no remembered tabs or locations. Thumbnails are decoded in memory and never written to `~/.cache/thumbnails` or anywhere else.
- The only file Kappa writes is `~/.config/kappa/theme.json` (colour settings, no paths or names).
- Error messages shown in the app are not logged by Kappa itself. Qt/Quickshell warnings go to a log under `/run/user/<uid>/` (RAM, readable only by you).

**Drag and drop, clipboard and URIs**
- Kappa does not accept drops and does not start drags, so a dropped payload cannot reach it. Between applications it only uses the clipboard, and pasted text counts as files only when it is a list of `file://` URIs.
- Kappa works with plain filesystem paths only. It does not parse `trash://`, `recent://`, `smb://` or percent-encoded paths (`%2e%2e` stays a literal name), so such URIs cannot redirect navigation. File URLs shown in the interface are built with every path segment percent-encoded. `~` is the only expansion.

**D-Bus and privileged actions**
- Kappa is only a D-Bus *client* (`busctl` calls to KDE Connect and KIO-Fuse). It exports no service, name or method, so there is nothing for another process to call. Ids placed in those calls are validated first.
- Mounting and ejecting go through `udisksctl`, so authorisation stays with udisks and Polkit. Kappa never talks to Polkit itself, and the block device passed to it must be a plain `/dev/...` path.

Known limits: Image decoding still happens inside the app process using Qt's image plugins; a malicious archive can still fill the allowed disk reserve before the limits stop it; a file's content can change between the check and the open; and a process running as *your own user* can still race Kappa (it has the same access to your files anyway).

To report a vulnerability, please open a private security advisory on GitHub (Security tab of the repository) instead of a public issue.
