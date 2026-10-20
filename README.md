# ◩ Kappa File Manager (河)

> Gerenciador de arquivos brutalista de alta performance feito **para** o ecossistema **Ryoku OS**, construído com **Rust** no backend e interface nativa em **QML / Quickshell**.
>
> ⚠️ **Projeto independente da comunidade: o Kappa não é um app oficial do Ryoku** e não é mantido pelo time do Ryoku.
> 
> Inspirado na profundidade e robustez do **KDE Dolphin**, o Kappa pega as melhores funcionalidades do Dolphin (navegação transparente em dispositivos, KIO-Fuse, integração nativa com KDE Connect, lugares XDG e separação limpa de modelo) e as recria do zero com um motor ultrarrápido em **Rust 2024** e o design system brutalista oriental do Ryoku.

---

## 🖼️ Capturas de Tela

| | |
| :---: | :---: |
| ![Lista](screenshots/01-list.png)<br>**Lista** | ![Grade com seleção múltipla](screenshots/02-grid-multiselect.png)<br>**Grade e seleção múltipla** |
| ![Painel de detalhes](screenshots/03-details.png)<br>**Painel de detalhes** | ![Agrupar por tipo](screenshots/04-grouped-by-type.png)<br>**Agrupar por tipo** |
| ![Menu ordenar](screenshots/05-sort-menu.png)<br>**Ordenar** | ![Menu de contexto](screenshots/06-context-menu.png)<br>**Menu de contexto** |
| ![Split view](screenshots/07-split-view.png)<br>**Split view (F3)** | ![Barra de caminho](screenshots/13-path-bar.png)<br>**Barra de caminho editável com sugestões** |
| ![Cópia em andamento](screenshots/11-copy-progress.png)<br>**Progresso de cópia** | ![Cópia concluída](screenshots/12-copy-done.png)<br>**Cópia concluída** |
| ![Confirmar exclusão](screenshots/08-delete-confirm.png)<br>**Confirmação de exclusão** | ![Aparência](screenshots/09-appearance.png)<br>**Aparência** |
| ![Tema fixo no Kappa](screenshots/10-appearance-fixed.png)<br>**Tema próprio do Kappa (esquema Fidelity)** | ![KDE Connect](screenshots/14-kde-connect.png)<br>**Dispositivo KDE Connect** |

---

## ✨ Destaques do Projeto

- 🦀 **Núcleo em Rust Puro:** Varredura assíncrona ultra rápida, monitoramento inotify sem recarregar a tela, lixeira segura (FreeDesktop Trash spec) e cálculo dinâmico de metadados.
- 🐬 **Evolução Espiritual do Dolphin em Rust:** Traz a força de acesso a sistemas remotos e dispositivos do KDE Dolphin através de integração nativa com `kio-fuse` e DBus, permitindo explorar sistemas de arquivos de smartphones e dispositivos remotos de forma transparente e em alta velocidade.
- 🎨 **Linguagem Visual Ryoku ("Greek-noir yakuza"):** Cantos com o raio configurado no Ryoku, hairlines de 1px, sombras suaves, selo *Hanko* (*eki-stamp*) em vermillion, kanji **河** monumental ao fundo e marcas técnicas de calibração blueprint (+).
- 📑 **Sistema Dinâmico de Abas:** Navegação limpa de janela única por padrão; a barra de abas surge suavemente com múltiplas abas (`Ctrl+T` e `Ctrl+W`).
- 🔍 **Busca Inline Sem Modal:** Filtro ao vivo com debounce de 150ms, chips de categoria com contagem em tempo real e alternador de escopo (*Esta pasta* vs *Tudo*).
- 🖱️ **Menu de Contexto Rico:** Suporte inteligente a tipos de arquivo, incluindo a seção **`// RYOTUNES_`** para tocar áudio no Ryotunes, abrir em nova aba, terminal integrado e compartilhamento direto com dispositivos pareados.
- 🖼️ **Painel de Detalhes Lateral (Frame 155):** Drawer brutalista deslizante (`340px`) acionado por `Ctrl+I`, `Alt+Enter` ou menu de contexto, exibindo preview em alta resolução, metadados detalhados (MIME, permissões, local), paleta de cores para imagens e ação de definir wallpaper.
- 🪟 **Divisão de Visualização (Split View - F3):** Modo lado a lado herdado da produtividade do Dolphin, permitindo visualizar duas pastas ou abas simultaneamente com navegação independente.
- 📱 **Integração Real com KDE Connect & KIO-Fuse:** Detecção ao vivo de dispositivos emparelhados (ex: seu celular), navegação real por todas as pastas internas do celular (`DCIM`, `Download`, `Documents`, `Pictures`), envio de arquivos pelo menu de contexto (`--kde-share`), painel dedicado do dispositivo (Frame 425 com kanji **繋**), ping, ring, envio de clipboard e montagem de sistema de arquivos.
- ☑️ **Seleção Múltipla:** `Ctrl+clique` alterna, `Shift+clique` e `Shift+setas` selecionam intervalos, `Ctrl+A` seleciona tudo; copiar, recortar, colar e excluir agem em todos os itens.
- 📦 **Transferências com Progresso:** cópia e movimentação com cartão de progresso (velocidade, tempo restante, pausar e cancelar com `Esc`), inclusive para arquivos de vários GB.
- 🛡️ **Exclusão com Confirmação:** `Del` abre um modal e envia para a lixeira; `Shift+Del` exclui permanentemente, com confirmação explícita.
- 🧭 **Barra de Caminho Usual:** clique no espaço vazio ou `Ctrl+L` para digitar o caminho, com sugestões, `Tab` para completar e aviso de caminho inexistente.
- 🎨 **Aparência Própria:** `Ctrl+,` permite seguir o tema do Ryoku ou fixar uma paleta só no Kappa (esquema, cor de origem e modo claro/escuro).
- 🌐 **Internacionalização Nativa Ryoku:** Sincronização automática com as preferências de idioma do sistema (`~/.config/ryoku/shell.json` e `I18n.qml`), exibindo interface nativa em inglês ou português conforme configurado.

---

## 🏛️ Arquitetura

O Kappa divide-se em duas camadas desacopladas e resilientes:

1. **`kappa-core` (Rust):**
   - [`src/core/entry.rs`](src/core/entry.rs): Modelagem de arquivos, MIME types e formatação de datas/tamanhos com locale.
   - [`src/core/path_resolver.rs`](src/core/path_resolver.rs): Validação rigorosa de caminhos (sugestão de pastas existentes, verificação de permissões polkit, links simbólicos órfãos e discos desconectados).
   - [`src/core/search.rs`](src/core/search.rs): Motor de busca assíncrono com cancelamento instantâneo via `AtomicBool`.
   - [`src/core/places.rs`](src/core/places.rs): Mapeamento de lugares padrão do sistema e pontos de montagem.

2. **Interface Visual (QML / Quickshell):**
   - Consome os tokens do sistema instalados em `/usr/lib/qt6/qml/Ryoku/` (`Tokens.qml`, `I18n.qml`).
   - Vetores pixel art puros com `QtQuick.Shapes` ([`qml/PixelGlyphs.qml`](qml/PixelGlyphs.qml)).
   - Cruzes técnicas de calibração em grade ([`qml/TechCrosses.qml`](qml/TechCrosses.qml)).
   - Selo circular oriental ([`qml/HankoSeal.qml`](qml/HankoSeal.qml)).

---

## 🚀 Como Executar

### Pré-requisitos
- **Rust & Cargo** (edição 2024+)
- **Qt 6 & Quickshell** (instalado no Ryoku OS)

### Inicialização Rápida

Basta executar o script de inicialização na raiz do projeto:

```bash
git clone https://github.com/.../kappa-file-manager.git
cd kappa-file-manager
./run.sh
```

Ou diretamente via Cargo:
```bash
cargo run
```

---

## ⌨️ Atalhos de Teclado

| Atalho | Ação |
| :--- | :--- |
| `Ctrl+T` | Abrir nova aba na pasta atual |
| `Ctrl+W` | Fechar aba ativa (ou clique com o botão do meio na aba) |
| `/` ou `Ctrl+F` | Focar na busca inline |
| `Esc` | Limpar busca / fechar menus e modais / cancelar transferência |
| `Enter` | Abrir pasta ou arquivo no aplicativo padrão |
| `Del` / `Shift+Del` | Mover para a lixeira (com confirmação) / excluir permanentemente |
| `Ctrl+C` / `Ctrl+X` / `Ctrl+V` | Copiar / recortar / colar |
| `Ctrl+A` | Selecionar tudo |
| `F2` | Renomear |
| `F7` ou `Ctrl+Shift+N` | Nova pasta (já abre para renomear) |
| `Ctrl+L` ou `Alt+D` | Editar o caminho |
| `Ctrl+,` | Abrir Aparência |
| `F3` | Dividir visualização (Split View em dois painéis/abas) |
| `Ctrl+I` ou `Alt+Enter` | Alternar Painel de Detalhes (Frame 155) |

---

## 🎨 Design System e Customização Ryoku

- **Arredondamento Dinâmico:** Todos os componentes do Kappa adaptam seu `radius` reativamente ao valor configurado no **Ryoku OS** (`~/.config/ryoku/shell.json` `theme.attributes.sizing.radius_widget` e singleton `Tokens.radius`).
- **Menu de Ordenação e Agrupamento (Nós 51, 2707, 2866, 2710):**
  - Botão **Ordenar** na Toolbar abrindo o overlay com ordenação por **Nome**, **Tipo**, **Data** e **Tamanho**, em ordem **Crescente** (`A→Z`) ou **Decrescente** (`Z→A`).
  - Cabeçalhos de colunas interativos com setas e rótulo contextual (ex: `NOME · TIPO ↑`).
  - Botão **Agrupar por Tipo** com seções brutalistas (`PASTAS_`, `IMAGENS_`, `DOCUMENTOS_`, `ÁUDIO_`, `VÍDEOS_`, `CÓDIGO_`, `OUTROS_`), contagem ao vivo e placa `07 // TIPOS` na Titlebar.
- **Menu de Contexto Completo:** Alinhado 100% aos nós 616, 665 e 1380 do Figcraft, com submenu para envio a celulares via KDE Connect, pen drives, zip e clipboard, além de layout e atalhos dedicados para faixas de áudio integradas ao Ryotunes.

---

## 📄 Licença e Design

- Design original criado no **FigCraft** em [`design/kappa-file-manager.figcraft`](design/kappa-file-manager.figcraft).
- Alinhado às diretrizes e identidade visual do **Ryoku**, sem ser um projeto oficial dele.
