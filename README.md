# Placa de Tempo de Jogo (Roblox)

Um ranking de tempo jogado em forma de **placa de madeira no mundo**, feita pra
combinar com cenário estilizado de floresta/pedra: moldura de madeira escura,
telhadinho de duas águas, fundo cor de pergaminho, detalhe verde puxando o verde
da grama e medalhas de ouro/prata/bronze nos três primeiros.

```
            /\                       <- telhadinho de madeira
       ____/__\____
      |            |
      |  TEMPO DE JOGO     |         <- cabeçalho de madeira escura
      |  Top 8 jogadores   |
      | ================== |         <- faixa verde
      | (1) O  Jogador  12h 30m |    <- ouro
      | (2) O  Jogador   9h 10m |    <- prata
      | (3) O  Jogador   7h 45m |    <- bronze
      | (4) O  Jogador   5h 02m |
      | ...                     |
      | SEU TEMPO   02h 15m 09s |    <- barra verde, relógio andando
      |____________________|
         ||            ||            <- pernas de madeira
```

O tempo é **salvo entre sessões** (DataStore) e o ranking é **global**, somando
todos os servidores (OrderedDataStore).

---

## Instalação (Roblox Studio, 3 passos)

Nenhum modelo pra importar: a placa é construída pelo script.

1. **ReplicatedStorage** → novo **ModuleScript** chamado exatamente
   `PlaytimeConfig` → cole o conteúdo de
   [`src/ReplicatedStorage/PlaytimeConfig.luau`](src/ReplicatedStorage/PlaytimeConfig.luau)

2. **ServerScriptService** → novo **Script** → cole
   [`src/ServerScriptService/PlaytimeScoreboardServer.server.luau`](src/ServerScriptService/PlaytimeScoreboardServer.server.luau)

3. **StarterPlayer → StarterPlayerScripts** → novo **LocalScript** → cole
   [`src/StarterPlayer/StarterPlayerScripts/PlaytimeScoreboardClient.client.luau`](src/StarterPlayer/StarterPlayerScripts/PlaytimeScoreboardClient.client.luau)

Dê Play. A placa aparece sozinha perto do seu spawn.

> **Importante pra testar no Studio:** ligue
> `Home → Game Settings → Security → Enable Studio Access to API Services`.
> Sem isso o DataStore não funciona — a placa ainda aparece e conta, mas só o
> tempo da sessão atual, e o script avisa isso no Output.

### Onde colocar a placa

No `PlaytimeConfig`, mude:

```lua
Config.BoardPosition = Vector3.new(-24, 14, 87)  -- centro do painel
Config.BoardRotationY = 90                        -- girar em graus
```

Pra achar os números: clique numa Part no lugar que você quer, olhe `Position`
nas Propriedades e copie. Deixando `Config.BoardPosition = nil`, o script
escolhe um lugar perto do SpawnLocation.

**Quer usar a sua própria placa em vez da de madeira?** Coloque
`Config.AutoBuildBoard = false` e marque a parte da frente da sua placa com a
tag `PlaytimeBoard` (Studio: `Modelo → Avançado → Editor de Tags`). A tela é
desenhada na face **Front** dessa parte.

---

## Configuração

Tudo fica em `PlaytimeConfig`. Os mais usados:

| Opção | Padrão | O que faz |
|---|---|---|
| `BoardPosition` | `nil` | Onde a placa fica. `nil` = perto do spawn |
| `BoardRotationY` | `0` | Gira a placa, em graus |
| `BoardWidth` / `BoardHeight` | `12` / `9` | Tamanho do painel em studs |
| `ShowPosts` / `PostHeight` | `true` / `6` | Pernas de madeira embaixo |
| `TopCount` | `8` | Quantas linhas o ranking mostra |
| `Title` / `Subtitle` | — | Textos do cabeçalho |
| `ShowAvatars` | `true` | Fotinha do rosto em cada linha |
| `ShowYourTime` | `true` | Barra verde "SEU TEMPO" no rodapé |
| `Leaderstats` | `true` | Também mostra o tempo na lista de jogadores |
| `MaxRenderDistance` | `90` | Distância (studs) em que a tela para de ser desenhada |
| `PixelsPerStud` | `42` | Resolução da tela. Menor = mais leve |
| `LightInfluence` | `0` | `0` = brilho próprio, `0.3`+ = escurece com a iluminação |
| `Palette` | — | Todas as cores |
| `DataStoreName` | `PlaytimeV1` | **Mudar esse nome zera o ranking** |

---

## Por que isso é leve

Essa parte foi o foco: a placa não deve custar FPS.

**Servidor** — 2 loops no jogo inteiro, nenhum por frame:

- O tempo **não é contado num loop**. Ele é calculado na hora em que alguém
  pergunta: `tempo salvo + (os.time() - hora que entrou)`. Zero custo contínuo,
  e imune a lag.
- Ranking lido a cada `60s` e guardado em cache. Autosave a cada `120s`, com os
  saves **espaçados** entre jogadores pra não estourar o limite do DataStore.
- Os nomes dos jogadores vêm de **uma** chamada só pra todos os IDs de uma vez
  (`UserService:GetUserInfosByUserIdsAsync`), com cache permanente.
- A placa tem 7 partes, todas `Anchored`, com `CanTouch = false` e
  `CanQuery = false` (raycasts e eventos de toque ignoram ela).

**Cliente** — 1 loop de 1 segundo, e ele só faz algo se você estiver perto:

- `SurfaceGui.MaxDistance` faz a tela **parar de ser desenhada** a mais de 90
  studs. É o ajuste que mais economiza FPS.
- A `SurfaceGui` mora na `PlayerGui` com `Adornee`, e não dentro da Part. Assim
  os elementos da interface **não são replicados pela rede** pra todo mundo.
- A interface é montada **uma vez**. Depois disso o redesenho nunca cria nem
  destrói instância nenhuma — só troca texto e cor (tem teste garantindo isso).
- Texto só é escrito quando **realmente mudou**.
- Os avatares usam `rbxthumb://`, que não faz requisição web pelo Lua.
- Entre uma atualização e outra, o relógio de quem está online continua andando
  no cliente — parece ao vivo sem gastar rede.

---

## Testes

A lógica (contagem, salvamento, ordenação do ranking, desenho) é testada fora do
Roblox, com um ambiente falso e relógio virtual — **60 testes**:

```bash
./tests/run.sh      # precisa do binário "luau" no PATH
```

Isso não tem nada a ver com o jogo: pra usar no Studio só interessa a pasta
`src/`.

---

## Rojo (opcional)

Quem usa [Rojo](https://rojo.space/) pode sincronizar direto:

```bash
rojo serve
```
