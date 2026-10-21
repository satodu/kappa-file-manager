# AGENTS.md — Guia de Engenharia e Convenções para Agentes de IA

Este documento orienta agentes autônomos e desenvolvedores que venham a manter, evoluir ou refatorar o **Kappa File Manager**.

---

## ⛩️ 1. Visão Geral e Filosofia do Projeto

O **Kappa File Manager** é um gerenciador de arquivos de alta performance feito para o **Ryoku OS**. É um projeto independente da comunidade, **não é um app oficial do Ryoku** (ambiente desktop brutalista oriental baseado em Arch Linux, Wayland, Hyprland/Niri e Quickshell).

- **Backend:** Rust 2024 (`tokio`, `walkdir`, `notify`, `trash-rs`, `mime_guess`).
- **Frontend:** QML nativo rodando sobre a runtime do **Quickshell** com o design system do **Ryoku** (`Ryoku.Ui` e `Ryoku.Ui.Singletons`).
- **Comunicação:** CLI assíncrona orientada a eventos JSON (não-bloqueante via `Quickshell.Io.Process` com `StdioCollector`).
- **Design Language:** Estética brutalista "Greek-noir yakuza": cantos arredondados vinculados dinamicamente ao Ryoku (`Tokens.radius` e `shell.json`), hairlines de 1px, sombras suaves autênticas (`MultiEffect` dropShadow do Figcraft), selo *Hanko* em vermillion (`#e2342a`), cruzes técnicas de registro (`+`) e o kanji monumental **河** (*Kappa*).

---

## 🏛️ 2. Arquitetura do Sistema

```text
kappa-file-manager/
├── Cargo.toml                   // Dependências Rust (tokio, notify, walkdir, trash, chrono, etc.)
├── run.sh                       // Script de inicialização rápida (compila Rust e executa Quickshell)
├── src/
│   ├── main.rs                  // CLI dispatcher (--list-json, --search-json, --places-json, etc.)
│   ├── core/
│   │   ├── mod.rs               // FolderLoader, SortField, SortDirection, FolderContent
│   │   ├── entry.rs             // FileEntry, FileKind, formatação de tamanhos e datas com locale
│   │   ├── path_resolver.rs     // PathResolver (regras de validação, polkit, device check, autocomplete)
│   │   ├── places.rs            // Places (XDG user dirs, discos montados, KDE Connect)
│   │   ├── search.rs            // SearchEngine assíncrono com cancelamento via AtomicBool
│   │   └── watcher.rs           // FolderWatcher (inotify em tempo real)
│   └── ops/
│       ├── mod.rs
│       └── file_ops.rs          // Operações de arquivos (abrir xdg-open, lixeira trash, renomear)
├── qml/
│   ├── shell.qml                // ShellRoot com FloatingWindow (1440x900)
│   ├── App.qml                  // Orquestrador de estado e processos
│   ├── Titlebar.qml             // Cabeçalho com marca Kappa, PixelMeander, PixelTorii e busca inline
│   ├── Sidebar.qml              // Rail com LUGARES_, DISPOSITIVOS_ e Marginalia
│   ├── TabBar.qml               // Gerenciador de abas (visível apenas quando tabs > 1)
│   ├── Toolbar.qml              // Breadcrumbs navegáveis e seletor Lista / Grade
│   ├── SearchFilterBar.qml      // Chips de categoria com contagem ao vivo e escopo de busca
│   ├── FileList.qml             // Lista e grade de arquivos com kanji 河 e cruzes técnicas
│   ├── DetailsPanel.qml         // Painel de detalhes deslizante (Frame 155, 340px)
│   ├── KdeDeviceView.qml        // Visualização dedicada de dispositivo pareado KDE Connect (kanji 繋)
│   ├── Statusbar.qml            // Contagem, detalhes de seleção e indicador de wallpaper
│   ├── ContextMenu.qml          // Menu flutuante com suporte especial a áudio (// RYOTUNES_)
│   ├── ConfirmModal.qml         // Confirmação genérica (abrir arquivo que pode executar código)
│   ├── KappaSafe.qml            // Singleton de segurança: URLs file:// codificadas, prévias limitadas, clipboard
│   ├── TransferCard.qml         // Cartão de progresso de cópia/movimentação (barra segmentada, pausar, cancelar)
│   ├── RenameModal.qml          // Modal de renomeação (F2 e nova pasta)
│   ├── DeleteModal.qml          // Modal de confirmação de exclusão (lixeira / permanente)
│   ├── AppearanceDialog.qml     // Diálogo de Aparência (tema próprio do Kappa)
│   ├── KappaTheme.qml           // Singleton de cores: segue Tokens ou paleta fixa via matugen
│   ├── SortMenu.qml             // Menu de ordenação e agrupamento por tipo (Frame 2866, 252x256)
│   ├── HankoSeal.qml            // Selo circular eki-stamp no estilo Ryoku
│   ├── TechCrosses.qml          // Grade de cruzes técnicas (+) de calibração do Figcraft
│   └── PixelGlyphs.qml          // Vetores pixel art (PixelMeander, PixelTorii, PixelWave)
└── design/
    └── kappa-file-manager.figcraft // Arquivo mestre de design inspecionável via figcraft-cli
```

---

## 📐 3. Regras Críticas de Design & UI

1. **Visibilidade da Barra de Abas:**
   - **1 aba aberta (modo padrão):** A `TabBar` DEVE ficar oculta (`Layout.preferredHeight: 0`, `visible: false`), unindo a `Toolbar` diretamente à `Titlebar` com uma hairline de 1px (estilo do Frame 2 `Kappa / Arquivos`).
   - **2 ou mais abas:** A `TabBar` transiciona suavemente com `Layout.preferredHeight: 38`, exibindo o botão `+` e o botão `✕`.
   - Atalhos suportados: `Ctrl+T` (nova aba) e `Ctrl+W` (fechar aba ativa).

2. **Decorações Técnicas Obrigatórias:**
   - Cruzes técnicas `+` de blueprint no fundo (`TechCrosses.qml`) nas coordenadas exatas do nó 145 do Figcraft, com opacidade reduzida e suave (`opacity: 0.12`).
   - **Marca d'água monumental (Nó 143 / Nó 495):** Kanji monumental **河** (*Kappa*) no `FileList.qml` e **繋** (*Tsunagu*) no `KdeDeviceView.qml`, com `font_size: 440px`, opacidade sutil (`0.05`), posicionado no **canto inferior direito** (`x: 760, y: 330` de `1171x806`), sangrando levemente para fora da margem conforme especificação exata do Figcraft.
   - Vetores pixel art exatos (`PixelMeander` 16x14, `PixelTorii` 16x16 e `PixelWave` 16x16) desenhados via `QtQuick.Shapes`.

3. **Inspiração e Reimplementação de Recursos do KDE Dolphin:**
   - O projeto adota a solidez funcional do Dolphin (gerenciador de arquivos referência do KDE), reimplementando em Rust seu modelo de integração com o ecossistema Linux/KDE.
   - **KIO-Fuse DBus (`org.kde.KIOFuse.VFS.mountUrl`):** Permite navegação direta em dispositivos remotos e celulares via `kdeconnect://<id>/`, mapeados para o sistema de arquivos local de forma transparente.

3. **Tipografia Estrita:**
   - **Títulos / Marca:** `Tokens.display` (*Fraunces*).
   - **Interface / Labels:** `Tokens.ui` (*Space Grotesk*).
   - **Dados / Metadados / Código:** `Tokens.mono` (*SpaceMono Nerd Font* ou *JetBrainsMono Nerd Font*).
   - **Kanji / Glifos Japoneses:** `Tokens.jp` (*Noto Sans CJK JP*).

4. **Tratamento de Idioma e Internacionalização:**
   - Use os tokens do sistema Ryoku (`~/.config/ryoku/shell.json` e `I18n.qml`). O Ryoku adota inglês como source-of-truth em código (`isPt ? "..." : "..."` quando necessário ou fallbacks transparentes).
   - Datas e tamanhos formatados respeitando `formatLocale` / `LANG` do sistema.

5. **Layout e Espaçamento da Sidebar (Nó 8 e Frame 425):**
   - Rail de 268px de largura com padding `[24, 16, 24, 16]` e `gap: 4px` entre itens.
   - Itens de lugares e dispositivos com dimensões fixas de `236x36px` e padding horizontal de `12px`.
   - Espaçador vertical fixo de exatamente `16px` entre a seção `PLACES_` e `DEVICES_`.
   - Dispositivos conectados KDE Connect exibem ícone de telefone `󰄡`, nome do dispositivo e plaqueta retangular `KDE` (`35x16px`).

6. **Integração Real com KDE Connect:**
   - Detecção live via `kdeconnect-cli -a --id-name-only` e ponto de montagem via `--get-mount-point`.
   - Ação de envio no menu de contexto de arquivos (`--kde-share <device_id> <path>`).
   - Painel dedicado do dispositivo (`KdeDeviceView.qml`) no Frame 425 com o kanji monumental **繋** (*Tsunagu*), estado da bateria, rede, armazenamento e ações rápidas (Ping, Ring, Send Clipboard, Mount).

7. **Especificação Exata da Grade (Nós 908 a 966 / Frame 759):**
   - Container de grade: margens de `24px` e `gap: 16px` (`cellWidth: 184`, `cellHeight: 196`).
   - Dimensões do Tile: `168x176px` com padding de `8px` e gap de `8px`.
   - Área de miniatura: `152x100px` em `Tokens.paperLift` com preview de imagem real ou blueprint com 5 linhas técnicas (`Tokens.lineStrong`, `Tokens.line`, `Tokens.lineSoft`) para código/documentos, e ícone de pasta grande de `44px` em `Tokens.sun`.
   - Tipografia: Nome em 13px (*Space Grotesk*) e metadados em 11px mono (*SpaceMono Nerd Font*) no formato `<data> · <tamanho>`.
   - Seleção técnica (Nó 919): Quatro cantos em L de 7px (*corner ticks*) nos 4 vértices do card selecionado em vermillion (`Tokens.sun`).

8. **Painel de Detalhes e Split View (Frame 155 e Frame 2414 / 2574):**
   - **Painel de Detalhes (`DetailsPanel.qml`):** Largura de `340px` com animação de slide (`OutExpo`), acionado por `Ctrl+I`, `Alt+Enter` ou item *Propriedades* do menu de contexto. Exibe placa `02 // DETALHES`, preview de imagem/arquivo (292x190) com ticks de canto, metadados (tipo, modificado, tamanho, local), amostras de paleta de cor e botão de definir wallpaper.
   - **Visualização Dividida (Split View - Frame 2414 `Kappa / Split de abas` e Nó 2574 `Split` - `F3`):**
     - Ao ativar o split, a barra de ferramentas global se oculta, e cada painel (`Pane A` e `Pane B`) exibe sua própria barra de navegação/endereços (`Toolbar.qml`, Nós 2499 e 2577, 52px) com breadcrumbs dedicados, botão subir pasta, seletor de modo `Lista` | `Grade` e botão fechar split `✕`.
     - **Linhas ativas (`Linha ativa A` e `B`, Nós 2651 e 2652):** Hairline de 2px em ciano (`#80d4d9`) na base da toolbar de cada painel: 100% opacidade no painel em foco e 35% no inativo.
     - **Divisor e Alça de Redimensionamento (`Alca divisor`, Nós 2646 e 2647):** Divisor com alça retangular de 9x40px, cantos com `systemRadius`, borda ciano e 3 pontos técnicos de 3x3px; permite arrastar horizontalmente para alterar dinamicamente a proporção dos painéis (`splitRatio`).

9. **Arredondamento de Bordas Dinâmico do Ryoku (`app.systemRadius`):**
   - Todos os componentes visíveis da aplicação (janela, botões da toolbar, seletor de modo, abas, chips de categoria e escopo, cards da grade, miniaturas, linhas da lista, painel de detalhes, cards e botões do KDE Connect e menu de contexto) DEVEM respeitar o raio configurado no Ryoku (`app.systemRadius`).
   - Carrega reativamente de `~/.config/ryoku/shell.json` (`theme.attributes.sizing.radius_widget`) com fallback a `Tokens.radius` (`px(6)`).

10. **Menu de Contexto Pixel-Perfect (Nós 616, 665 e 1380):**
   - **Menu Normal (Nó 616, 252px):** `Abrir`, `Abrir em nova aba`, `Abrir terminal aqui`, separador, `Recortar`, `Copiar`, `Colar`, separador, `Enviar para >`, separador, `Renomear`, `Mover para a lixeira` (ícone e texto sempre em vermillion `Tokens.sun`), separador, `Propriedades`.
   - **Menu de Áudio (Nó 1380, 268px):** Cabeçalho `// RYOTUNES_`, `Tocar no Ryotunes` (destaque ciano `#80d4d9`), `Adicionar à fila` (Ctrl+Q), `Tocar a seguir`, separador, `Abrir com >`, `Enviar para >`, separador, `Copiar` (Ctrl+C), `Renomear` (F2), `Mover para a lixeira` (Del), separador, `Propriedades`.
   - **Submenu Enviar para (Nó 665, 260px):** Dispositivos pareados KDE Connect e pendrives conectados com badges, `Pasta compactada (.zip)` e `Área de transferência`.
   - **Sombras:** Renderizadas com fidelidade máxima via `QtQuick.Effects.MultiEffect` (dropShadow com offset vertical 14px, blur 0.8, opacidade 0.65).

11. **Ordenações e Agrupamento por Tipo (Nós 51, 2707, 2866, 2710 e 3182):**
   - **Menu Ordenar (`SortMenu.qml`, Frame 2866 - 252x256):** Overlay elegante com `Nome`, `Tipo`, `Data`, `Tamanho`, separador, `Crescente` (`A→Z`), `Decrescente` (`Z→A`), separador, `Agrupar por tipo`.
   - **Botões da Toolbar:** Botão `Ordenar` (Nó 51) com indicador de campo e seta (`Nome ↑`, `Data ↓`, `Tipo ↑`, `Tamanho ↓`) e botão `Agrupar` (Nó 2707) com `Nenhum` / `Tipo`.
   - **Cabeçalhos de Coluna Interativos:** Clique em `NOME`, `MODIFICADO` ou `TAMANHO` alterna campo e direção de ordenação (exibindo `NOME · TIPO ↑` conforme Nó 3270 ao ordenar por tipo).
   - **Agrupamento por Tipo (`07 // TIPOS` - Frame 2710):** Agrupa os arquivos em seções brutas (`PASTAS_`, `IMAGENS_`, `DOCUMENTOS_`, `ÁUDIO_`, `VÍDEOS_`, `CÓDIGO_`, `OUTROS_`) com contagem e régua técnica com tick, transicionando a placa do cabeçalho para `07 // TIPOS`.

12. **Operações de Clipboard e Atalhos (`Ctrl+C`, `Ctrl+X`, `Ctrl+V`):**
   - **Copiar (`Ctrl+C`):** Armazena o item selecionado e disponibiliza o caminho no clipboard do sistema (`Quickshell.clipboardText`).
   - **Recortar (`Ctrl+X`):** Marca o item selecionado para movimentação e atualiza o clipboard.
   - **Colar (`Ctrl+V`):** Realiza a cópia recursiva (`--copy`) ou movimentação atômica (`--move`) para o painel em foco ativo (`Pane A` ou `Pane B`), com resolução inteligente de conflitos de nomes (`nome (1).ext`, `nome (2).ext`), recarregando o diretório de destino instantaneamente.
   - **Hotplug Reativo de Mídias:** Monitora `/proc/mounts` e portas USB em tempo real, adicionando e removendo dispositivos na barra lateral sem necessidade de recarregar a janela.

---

13. **Exclusão, Aparência e Atalhos (alpha):**
   - **Delete** abre `DeleteModal.qml` (lixeira, `--trash`); **Shift+Delete** ou o link "Excluir permanentemente" exige a caixa de confirmação e usa `--delete`. `Enter` confirma, `Esc` cancela.
   - **Atalhos de edição** (`Ctrl+C/X/V/A`, `Delete`, `F2`) são `Shortcut` com UMA sequência cada (`StandardKey.*`); listar `"Ctrl+C"` junto de `StandardKey.Copy` é ambíguo no Qt e desativa o atalho. Ficam desligados (`app.shortcutsEnabled`) com modal ou busca em foco.
   - **Aparência** (`Ctrl+,` ou clique em `Tema:` na statusbar): `KappaTheme` lê `~/.config/kappa/theme.json` (`mode`: `follow` | `fixed`, `scheme`, `source`, `appearance`). No modo `fixed` gera os papéis Material com `matugen color hex ... --dry-run`. Todo QML usa `KappaTheme.<cor>` em vez de `Tokens.<cor>`; não nomeie o singleton `Palette` (colide com o tipo do QtQuick).
   - `KAPPA_START=<dir>` define a pasta inicial (útil para testes).
   - Colar pasta dentro dela mesma é recusado pelo backend (evita recursão infinita).

14. **Seleção múltipla, transferências e nova pasta:**
   - **Seleção:** `app.selectedPaths` / `rightSelectedPaths` (+ `selectionAnchor`). Clique simples seleciona um, `Ctrl+clique` alterna, `Shift+clique` e `Shift+setas` selecionam intervalo, `Ctrl+A` seleciona tudo. Na grade as setas andam por célula/linha (`app.gridColumns()`). Ações usam `app.targetsFor(item)`: a seleção inteira se o item clicado faz parte dela.
   - **Transferência (`--transfer <copy|move> <destino> <origens...>`):** emite JSON por linha (`start`, `progress`, `done`, `error`) lido pelo `SplitParser` em `App.qml` e mostrado no `TransferCard`. `Esc` cancela (SIGTERM e remove o arquivo parcial); Pausar usa SIGSTOP/SIGCONT. Ao concluir, os itens colados ficam selecionados.
   - **Nova pasta** (`F7`/`Ctrl+Shift+N`): cria a pasta e abre o `RenameModal` já nela (`pendingRenamePath`).
   - **Localização:** `Ctrl+Shift+C` (e "Copiar localização" no menu) copia o caminho em texto via `app.copyPath()`. Enquanto o campo de caminho está em edição (`app.anyPathEditing`), os atalhos de arquivos ficam desligados para `Ctrl+C/V/A` valerem para o texto. Os níveis da barra de caminho que não cabem viram o menu `…` (`Toolbar.relayoutCrumbs`).
   - **Arrastar para fora:** `FileList.dragMime()` envia só `text/uri-list` (URIs `file://` codificadas) via `Drag.Automatic`; não mande `text/plain` junto (duplica em terminais e abre brecha com quebras de linha). O único drop aceito é o da `Sidebar` (`DropArea`): arrastar pasta do próprio `FileList` fixa um atalho em Lugares (`app.pinPlaces`, `~/.config/kappa/places.json`, até 32, kanji aleatório de `app.pinKanji`). O drop ignora o conteúdo recebido e usa `app.draggingFolders`, preenchido pelo `FileList` ao iniciar o arrasto; drop de fora é recusado (`canPin`). Não passe a usar `drop.urls`.
   - Variáveis de ambiente de teste: `KAPPA_START=<dir>`, `KAPPA_VIEW=list|grid`.

15. **Compactar e extrair (0.1.1-beta) e regras de segurança:**
   - Menu de contexto: `Comprimir em .zip`, `Comprimir em .tar.gz` (usa a seleção toda) e `Extrair aqui` (para `.zip`, `.tar`, `.tar.gz`, `.tgz`). Backend: `--compress <zip|tar.gz> <pasta> <nome|-> <origens...>` e `--extract <arquivo> <pasta>`, com os mesmos eventos JSON e o mesmo `TransferCard` da cópia; `Esc` cancela e remove o parcial.
   - **Nunca** relaxe as defesas de `src/ops/archive.rs`: pasta de destino nova (`create_dir`), caminhos relativos seguros, nada escrito através de links, `O_NOFOLLOW|O_EXCL`, bits especiais removidos, limites de bomba, arquivo gerado `0600` e publicado de forma atômica. Todo ajuste exige teste em `archive.rs`.
   - Abrir arquivo: o backend (`--open`) devolve `needs_confirm` para executáveis, scripts e lançadores (por conteúdo); o QML mostra `ConfirmModal` e só então chama `--open <caminho> --confirmed`.
   - Nomes novos passam por `validate_file_name`; caminhos da CLI por `require_absolute`; ids KDE e dispositivos de bloco por `validate_device_id` / `validate_block_device`; exclusão por `ensure_not_protected`. Imagens usam `KappaSafe.previewUrl` (extensões permitidas, até 32 MiB, `sourceSize`). Mapa completo em `SECURITY.md`.
   - O backend recusa rodar como root (`root_allowed`); aberturas de origem usam `O_NOFOLLOW`, movimentações `RENAME_NOREPLACE`. Kappa não guarda histórico (só a última pasta, em `~/.config/kappa/state.json`, restaurada ao abrir; `KAPPA_START` desliga), não grava cache de miniaturas, só aceita o drop interno de pastas na Sidebar e só lida com caminhos simples (sem `trash://`/`recent://`). Se isso mudar, atualize `SECURITY.md`.
   - Mover entre discos: copia, `fsync`, confere tamanho e só então apaga a origem; falha remove o destino parcial. Apagar/mover/lixeira de pasta com ponto de montagem é recusado (`contains_mount`). Listagens têm teto de 200.000 itens (`MAX_LISTED_ENTRIES`); prévias exigem `is_regular`.

16. **Nuvem via rclone (Google Drive / OneDrive):**
   - `src/ops/cloud.rs`: `--cloud-json` (lista remotes `drive`/`onedrive` de `rclone listremotes --long`), `--cloud-mount <remote>` e `--cloud-unmount <remote>`. Monta com `--read-only --vfs-cache-mode off` em `$XDG_RUNTIME_DIR/kappa/cloud/<remote>` (`0700`). O nome do remote passa por `validate_remote_name` e precisa ser um dos listados pelo próprio rclone.
   - **Nunca** abra `rclone.conf`, nem leia/repasse token, nem use `rclone config dump`; o login é do usuário (`rclone config`). Não monte com escrita nem com cache em disco sem atualizar `SECURITY.md`.
   - QML: `app.cloudList`, `cloudClicked`, `cloudUnmount`, grupo `NUVEM_`/`CLOUD_` na `Sidebar` (só aparece com remotes). Mensagens seguem o idioma do Ryoku (`app.isPt`).

---

## 🛠️ 4. Comandos e Verificações de Qualidade

Antes de concluir qualquer modificação no código:

```bash
# 1. Executar testes unitários do núcleo em Rust
cargo test

# 2. Compilar sem warnings
cargo build

# 3. Validar a sintaxe de todos os arquivos QML
qmllint qml/*.qml

# 4. Testar a inicialização headless do Quickshell
timeout 2s quickshell -p qml/shell.qml
```

Para inspecionar o arquivo de design `.figcraft`:
```bash
/home/panda/.local/opt/figcraft/usr/bin/figcraft-cli info design/kappa-file-manager.figcraft --json
/home/panda/.local/opt/figcraft/usr/bin/figcraft-cli export design/kappa-file-manager.figcraft -o /tmp/export/ --format png
```
