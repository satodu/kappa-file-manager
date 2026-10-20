# Security

Kappa is a file manager, so it handles untrusted names, links and paths. Notes on how it behaves:

- File and folder names are always drawn as plain text, never as HTML.
- Symbolic links are copied as links and never followed; pipes, sockets and devices are skipped during copies.
- External commands (`xdg-open`, `kdeconnect-cli`, `udisksctl`, `matugen`, ...) are started with argument lists, never through a shell, and values read from `~/.config/kappa/theme.json` are validated first.
- Deleting asks for confirmation; `Shift+Del` deletes permanently and needs an explicit extra confirmation.

To report a vulnerability, please open a private security advisory on GitHub (Security tab of the repository) instead of a public issue.
