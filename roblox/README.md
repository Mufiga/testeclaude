# ScenarioCasas — casas de cenário para Roblox

Casas de fundo no esquema de set de cinema: **são volume de verdade**
(têm profundidade, silhueta e leitura 3D), mas são **casca**. Sem
interior, sem porta que abre, sem MeshPart. Só `Part` e `WedgePart`.

## Instalação (Studio)

1. `ServerScriptService` → novo **ModuleScript** chamado `ScenarioCasas`
   → cole o conteúdo de [`ScenarioCasas.lua`](ScenarioCasas.lua).
2. Ao lado dele, um **Script** chamado `MontarCenario`
   → cole [`ExemploUso.server.lua`](ExemploUso.server.lua).
3. Dê Play. O Output imprime quantas partes e triângulos entraram.

Pra iterar rápido sem dar Play, cole isto na **Command Bar** do Studio:

```lua
require(game.ServerScriptService.ScenarioCasas).Construir({
    Foco = workspace.CurrentCamera.CFrame.Position,
    Direcao = workspace.CurrentCamera.CFrame.LookVector,
})
```

Rodar de novo apaga a versão anterior e reconstrói. Pra limpar:
`require(...).Limpar("CenarioVila")`.

## Como apontar o cenário

Tudo é construído em volta de **um ponto de vista** — de onde o jogador
olha. Pelo print, é o pórtico de largada olhando pro fundo do vale.

Jeito prático: ponha uma Part onde a câmera do jogador fica, chame de
`PontoDeVista`, marque `Anchored`, `Transparency = 1`, e gire pra apontar
pro fundo. O script de exemplo usa ela sozinho.

## As três faixas

| Faixa | Distância | O que é | Partes por construção |
|---|---|---|---|
| `VOLUME` | perto | casa com casca de meia-profundidade, janela, porta, chaminé | 6–14 |
| `CAIXA` | meio | mesma silhueta, sem detalhe, mais rasa, já puxada pra névoa | 3–6 |
| `PLACA` | longe | recorte de backlot: 3–4 peças finas viradas pro foco | 3–4 |

## Os dois truques que fazem parecer caro

**Perspectiva aérea.** Toda peça tem a cor interpolada na direção da cor
da atmosfera conforme a distância do foco (`NevoaInicio`, `NevoaFim`,
`NevoaMaxima`, `NevoaCurva`). É isso que o olho usa pra julgar
profundidade — muito mais do que contagem de polígono. Pra funcionar
inteiro, a névoa do jogo tem que ser da mesma cor: use
`ScenarioCasas.AplicarAtmosfera()`.

**Perspectiva forçada.** As camadas distantes são construídas *menores do
que seriam de verdade* (`Escala` 0.8 e 0.55) e todas apontam pro ponto de
foco. O vale passa a parecer ter o dobro da profundidade que tem.

## Performance

- Tudo `Anchored`, `CastShadow = false`, `CanQuery = false`,
  `CanTouch = false`, material `SmoothPlastic` (sem amostragem de textura).
- **Um** collider invisível por casa, não um por peça — e só na camada
  perto. As outras não colidem com nada.
- Modelos parenteados só no fim da montagem (uma inserção, não trezentas).
- Raiz com `ModelStreamingMode = Persistent`: o fundo nunca pisca nem
  aparece de repente quando o jogador anda.
- O custo exato sai no Output ao construir.

## Ajustes que costumam ser os primeiros

| Quero | Mexo em |
|---|---|
| outro desenho de vila | `Semente` (qualquer número) |
| mais/menos casas | `Quantidade` da camada |
| vale mais fundo | abaixa a `Escala` das camadas distantes |
| fundo mais lavado | sobe `NevoaMaxima` (até 1 = some) |
| fundo mais nítido | sobe `NevoaInicio` e `NevoaFim` |
| casas mais espalhadas | sobe `Abertura` e `Espalhamento` |
| sombra nas casas de perto | `Sombra = true` na camada `Vila` |
| só casas, sem árvore | `Vegetacao = false` |
| outra paleta | tabela `PALETA` no topo do módulo |

## Se os telhados saírem em V em vez de A

A `WedgePart` do Roblox tem a face vertical no `+Z` e a rampa descendo pro
`-Z`; o módulo inteiro assume isso. Se a sua versão do Studio fizer o
contrário, os telhados saem como vale em vez de duas águas. Conserto:
`CUNHA_INVERTIDA = true` no topo de `ScenarioCasas.lua`.

## API

```lua
ScenarioCasas.Construir(opcoes)            -- monta tudo, devolve o Model raiz
ScenarioCasas.CasaAvulsa(cf, opcoes)       -- uma casa onde você quiser
ScenarioCasas.Limpar(nome, pai)            -- apaga um cenário construído
ScenarioCasas.AplicarAtmosfera(opcoes)     -- alinha a névoa do jogo
ScenarioCasas.PALETA                       -- as cores, pra reaproveitar
```

Arquétipos disponíveis: `Chale`, `Sobrado`, `Celeiro`, `Capela`, `Placa`.
