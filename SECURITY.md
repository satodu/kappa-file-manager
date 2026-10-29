# Security

Kappa is a file manager, so it handles untrusted names, links, paths and archives. How it behaves:

**Opening files**
- Opening a file that could run code (an ELF program, a script with `#!`, a `.desktop` launcher, `.sh`, `.AppImage`, ...) asks for confirmation first. The check looks at the file *content*, so `invoice.pdf` that is really a script is still caught. `Enter` never confirms; you must click "Open anyway".
- Kappa never executes a file itself: it hands it to `xdg-open`, and only with an absolute path.
- "Open with" (`--open-with-json`, `--open-with`) lists the applications that the system registers for the file type (`mimeinfo.cache` and the `.desktop` files under the XDG data dirs; nothing else is scanned). Launching goes through `gio launch <desktop> <path>` in an argument list, never a shell string, so Kappa does not parse `Exec` itself. The app id must be a plain `*.desktop` name (no `/`, no leading `-` or `.`), must resolve inside the XDG applications dirs and be a visible application entry, otherwise the backend refuses. The path is absolute. "Other application…" lists every visible installed `.desktop` (same XDG dirs, capped at 2,000) and accepts any of them: the id must still be a plain `*.desktop` name that resolves inside the XDG applications dirs and is a visible `Type=Application` entry; arbitrary commands or paths are never accepted. Choosing the app is the explicit decision, so this route does not ask the executable-file confirmation of the plain open.

**Opened from other apps (`FileManager1`, default file manager)**
- The D-Bus service (`--dbus-service`, `org.freedesktop.FileManager1` on the session bus) only *opens Kappa windows*: it returns no data and never reads, lists or changes files. `ShowFolders`, `ShowItems` and `ShowItemProperties` take URIs; only `file://` (empty host or `localhost`) and absolute paths are accepted, so `trash://`, `smb://`, `recent://`, `http://`, NUL/newlines, malformed `%` escapes and relative paths are dropped.
- A call opens at most 8 windows and the service at most 16 per minute, so a looping app cannot flood the desktop. The target path reaches the launcher as a single argument (no shell) and is validated again by `--start-from` before it becomes `KAPPA_START`/`KAPPA_SELECT`. A symbolic link is never followed: a link to a folder opens its parent with the link selected.
- The service exits after 60 s without calls and refuses to run as root like the rest of the backend.
- `--set-default` writes only inside the user's profile (`~/.local/share/dbus-1/services/`, `~/.config/kappa/`), with `O_NOFOLLOW` and an atomic rename. It never overwrites a `FileManager1` service file that is not Kappa's (marker line), refuses an executable path with spaces or control characters, and `--unset-default` removes only Kappa's own file and restores the previous `inode/directory` default. Nothing is installed system-wide, so it never collides with Nautilus or Dolphin packages.

**Paths and names**
- A new name (rename, new folder) is a single path component: no `/`, no `.`/`..`, no control characters. Renaming never overwrites an existing item.
- Every path received by the backend must be absolute. Deleting refuses `/`, top-level folders (`/home`, `/etc`, ...) and `$HOME`.
- File and folder names are always drawn as plain text, never as HTML.

**Browsing runs nothing**
- Opening or listing a folder never starts a helper program: no `git status`, no thumbnailers (ImageMagick, ffmpeg, Ghostscript), no metadata readers. Listing only reads names and sizes, so a hostile `.git/config` or a crafted media file cannot execute anything just by being in a folder. The few helpers Kappa does run (`lsblk`, `kdeconnect-cli`, `busctl`, `udisksctl`, `matugen`) use fixed arguments that never come from folder contents.

**Data loss**
- A move first tries an instant `rename`; across drives it copies, flushes every file to disk (`fsync`), checks the copied size against the source, and only then deletes the source. Any failure removes the partial copy and keeps the original.
- Nothing is overwritten: copies and moves pick a new name (`name (1)`), renames use `RENAME_NOREPLACE`, files are created with `O_EXCL`. On case-insensitive drives (FAT/exFAT/NTFS) `README` and `readme` count as the same name, so the second one gets a new name or, in an archive, is skipped and reported.
- Deleting a symbolic link removes only the link, never its target. Deleting, trashing or moving a folder that contains a mount point (a USB stick, a network share, a mounted phone) is refused, so it can never empty another disk.

**Names**
- Names such as `-rf`, `--help`, `$(cmd)`, `` `cmd` ``, `a; b`, `@file` or `<b>x</b>` are plain data: commands receive absolute paths in argument lists (never a shell string), and names are drawn as plain text. This is covered by tests that create, rename, copy and archive such names.

**Resources**
- The KDE Connect screen reads the phone's battery and cellular signal with D-Bus `Properties.Get` calls to `kdeconnectd` (read-only, 3 s timeout per call, validated device id). Nothing is written and no command is executed.
- The usage bars in the sidebar come from `statvfs` on the mount point of each *local* mounted disk (numbers only). Network devices (KDE Connect) are skipped, so a hung share cannot block the places refresh.
- A folder is listed in a separate process with a cap of 200,000 entries (the app says when it truncates), so huge folders cannot freeze or exhaust the window. Image previews load asynchronously, only for regular files (a FIFO or device named `x.png` is never opened), only from a short list of formats and up to 32 MiB. Pipes, sockets and devices are skipped by copy and compress, symbolic links are never followed (no link loops), and a stuck folder load is killed as soon as you navigate elsewhere.

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

**Cloud storage (rclone)**
- Kappa does not talk to any cloud API. If `rclone` is installed, it lists the remotes with `rclone listremotes --long` (names and types only) and shows the `drive` and `onedrive` ones. Login, tokens and the protocol stay with rclone: Kappa never opens `rclone.conf`, never receives or forwards a token, and has no OAuth code.
- Mounting runs `rclone mount NAME: <dir> --vfs-cache-mode writes --umask 077 --cache-dir <dir> --vfs-cache-max-age 15m --vfs-cache-max-size 2G`, so you can copy files up to Drive or OneDrive. The remote name is validated (`[A-Za-z0-9_-]`, at most 64 characters, never starting with `-`) and must be one of the remotes rclone itself reported, so it can never become an rclone option or a path. The mount point is a private `0700` folder Kappa creates, checked to be an empty real directory (not a link) before mounting; unmounting only touches that folder, with `fusermount3 -u`. Permission to write is still whatever your rclone login allows; Kappa adds no credentials of its own.
- Writing needs rclone's write cache. It lives in `$XDG_RUNTIME_DIR/kappa/cloud-cache/<remote>` (`0700`, RAM-backed, gone on reboot, entries expire after 15 minutes, soft cap 2 GiB), so nothing from the cloud is stored on disk across sessions. A very large upload can use that much memory.
- Deleting on a cloud mount is always the permanent-delete confirmation (Kappa has no trash there, and the backend refuses `--trash` on cloud paths so a file is never silently downloaded into your local trash). The dialog says the items are deleted in the cloud; the provider may keep them in its own trash.
- The existing mount-point guards (`contains_mount`) still stop Kappa from deleting or moving a folder that contains a cloud mount.
- A slow or hung remote can make a listing wait (the same limit as any network mount); mounting gives up after 60 seconds.

**Logs, history and caches**
- Kappa keeps no history: no recent files, no search history, no remembered tabs. The one thing it remembers is the last folder, so it can reopen there: a single path in `~/.config/kappa/state.json` (directory `0700`), overwritten on each navigation, validated as a plain absolute path on load, ignored if the folder is gone, and never read or written when `KAPPA_START` is set. Thumbnails are decoded in memory and never written to `~/.cache/thumbnails` or anywhere else.
- The only files Kappa writes are in `~/.config/kappa/`: `theme.json` (colour settings), `state.json` (the last folder) and `places.json` (pinned folders). Cloud mount points and rclone's write cache live under `$XDG_RUNTIME_DIR/kappa/` (RAM, `0700`).
- Error messages shown in the app are not logged by Kappa itself. Qt/Quickshell warnings go to a log under `/run/user/<uid>/` (RAM, readable only by you).

**Drag and drop, clipboard and URIs**
- You can drag files out of Kappa into another window (a terminal, a chat, an editor). Only the location of the items you dragged leaves, as a `text/uri-list` of percent-encoded `file://` URIs: no plain-text copy, so a file name containing a newline can never turn into a command when dropped on a terminal. Kappa accepts drops only for drags that started in its own file list, and it ignores the dropped data entirely: it uses the list of items the file list itself recorded when the drag started, so anything dragged in from another program is rejected. Two things can happen: dropping on a folder (in the list, on the background of a pane, or on a sidebar entry) asks *Copy or move?* and then runs the usual transfer, with the same safeguards as copy and paste (nothing is overwritten, no folder into itself, moves use `RENAME_NOREPLACE`); the destination comes from the interface state, never from the dropped data, and Enter does not confirm. Dropping a folder elsewhere on the Places sidebar pins it as a shortcut. Pins live in `~/.config/kappa/places.json` (at most 32; each path must be absolute and plain, each icon one of a fixed set of kanji, labels shown as plain text); a pin only navigates, it never opens or runs anything. Besides that it only uses the clipboard, and pasted text counts as files only when it is a list of `file://` URIs.
- Kappa works with plain filesystem paths only. It does not parse `trash://`, `recent://`, `smb://` or percent-encoded paths (`%2e%2e` stays a literal name), so such URIs cannot redirect navigation. File URLs shown in the interface are built with every path segment percent-encoded. `~` is the only expansion.

**D-Bus and privileged actions**
- Kappa is a D-Bus *client* (calls to KDE Connect and KIO-Fuse; ids placed in those calls are validated first). Its only exported object is the optional `org.freedesktop.FileManager1` service described above, which only opens windows and exists only if the user ran `--set-default`.
- Mounting and ejecting go through `udisksctl`, so authorisation stays with udisks and Polkit. Kappa never talks to Polkit itself, and the block device passed to it must be a plain `/dev/...` path.

Known limits: a folder on a hung network mount can still block its own listing process until it answers (the window stays responsive); Image decoding still happens inside the app process using Qt's image plugins; a malicious archive can still fill the allowed disk reserve before the limits stop it; a file's content can change between the check and the open; and a process running as *your own user* can still race Kappa (it has the same access to your files anyway).

To report a vulnerability, please open a private security advisory on GitHub (Security tab of the repository) instead of a public issue.
