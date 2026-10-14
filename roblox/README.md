# ScenarioCasas — casas de cenário ao longo da pista

Casas de fundo no esquema de set de cinema: **são volume de verdade**
(têm profundidade, silhueta e leitura 3D), mas são **casca**. Sem
interior, sem porta que abre, sem MeshPart. Só `Part` e `WedgePart`.

O cenário **acompanha o caminho offroad**: você marca a trilha com uns
pontos e as casas nascem ao longo dela, dos dois lados, sempre viradas
pro caminho.

## Instalação

1. `ServerScriptService` → **ModuleScript** `ScenarioCasas`
   → cole [`ScenarioCasas.lua`](ScenarioCasas.lua).
2. Ao lado, um **Script** `MontarCenario`
   → cole [`ExemploUso.server.lua`](ExemploUso.server.lua).

## Os 3 passos (Command Bar do Studio)

**1. Marcar a trilha.** Voe a câmera seguindo o caminho offroad e vá
repetindo — seta pra cima + Enter, seta pra cima + Enter:

```lua
require(game.ServerScriptService.ScenarioCasas).MarcarPonto()
```

Cada Enter larga uma bolinha laranja onde a câmera está olhando, dentro
de `workspace.CaminhoPista`. **6 a 15 pontos dão conta de uma trilha
inteira** — a curva (Catmull-Rom) passa exatamente em cima deles, então
não precisa de muitos. Pode arrastar as bolinhas depois pra ajustar.

**2. Construir.**

```lua
require(game.ServerScriptService.ScenarioCasas).AoLongoDaPista()
```

Rodar de novo apaga e refaz. Pra limpar: `.Limpar("CenarioPista")`.

**3. Ajustar na mão.** Mira a câmera no lugar e:

```lua
local C = require(game.ServerScriptService.ScenarioCasas)
C.DefinirPista(workspace.CaminhoPista)   -- faz tudo virar pra trilha sozinho
C.Aqui()                                  -- casa onde a câmera está olhando
C.Aqui({ Arquetipo = "Capela", Escala = 1.3, Colidir = true })
C.NaSelecao({ Arquetipo = "Celeiro" })    -- uma em cada Part selecionada
```

## O jeito não-destrutivo (recomendado pra ir montando devagar)

Crie `workspace.MarcadoresCasas` e jogue Parts invisíveis onde você quer
cada construção. Depois:

```lua
C.Marcadores(workspace.MarcadoresCasas)
```

Mexa os marcadores, rode de novo, quantas vezes quiser. Cada marcador
aceita atributos: `Arquetipo`, `Tipo`, `Escala`, `Nevoa`, `Colidir`,
`Detalhe`, `Semente`, `Virar`. Mesma posição = mesma casa toda vez.

## As três faixas

Cada faixa é uma **distância lateral da pista**:

| Faixa | Recuo | O que é | Partes |
|---|---|---|---|
| `VOLUME` | ~55 | casa de meia-profundidade: janela, porta, chaminé, colisão | 6–14 |
| `CAIXA` | ~190 | mesma silhueta, sem detalhe, mais rasa | 3–6 |
| `PLACA` | ~650 | recorte de backlot: peças finas viradas pra pista | 3–4 |

`Densidade` controla quantos lugares viram casa (0.5 = metade). O resto
vira pinheiro (`ChanceArvore`) ou buraco. Isso é de propósito: vila é
grupinho, não é muro de casa.

## Os dois truques que fazem parecer caro

**Perspectiva aérea.** A cor de cada peça é interpolada na direção da cor
da atmosfera conforme a **distância lateral até a pista**. É o que o olho
usa pra julgar profundidade, mais do que contagem de polígono. Pra
funcionar inteiro, a névoa do jogo tem que ser da mesma cor:
`ScenarioCasas.AplicarAtmosfera()`.

**Perspectiva forçada.** As faixas distantes são construídas *menores do
que seriam de verdade* (escala 0.85 e 0.60). O vale passa a parecer ter o
dobro da profundidade.

## Performance

- Tudo `Anchored`, `CastShadow = false`, `CanQuery = false`,
  `CanTouch = false`, material `SmoothPlastic` (sem amostragem de textura).
- **Um** collider invisível por casa, não um por peça — e só na faixa da
  beira. As outras não colidem com nada.
- Modelos parenteados só no fim da montagem.
- Raiz com `ModelStreamingMode = Persistent`: o fundo nunca pisca nem
  aparece de repente quando o jogador anda.
- O custo exato (construções, partes, triângulos) sai no Output.

## Ajustes que costumam ser os primeiros

| Quero | Mexo em |
|---|---|
| outro desenho de vila | `Semente` (qualquer número) |
| mais casas | sobe `Densidade`, abaixa `Espacamento` |
| casas mais longe da pista | sobe `Recuo` da faixa |
| só de um lado da trilha | `Lados = "esquerda"` ou `"direita"` |
| vale mais fundo | abaixa a `Escala` das faixas distantes |
| fundo mais lavado | sobe `NevoaMaxima` (1 = some no fundo) |
| fundo mais nítido | sobe `NevoaInicio` e `NevoaFim` |
| sombra nas casas de perto | `Sombra = true` na faixa `Beira` |
| nenhuma árvore | `ChanceArvore = 0` |
| outra paleta | tabela `PALETA` no topo do módulo |

## Se os telhados saírem em V em vez de A

A `WedgePart` do Roblox tem a face vertical no `+Z` e a rampa descendo pro
`-Z`; o módulo inteiro assume isso. Se a sua versão do Studio fizer o
contrário, os telhados saem como vale em vez de duas águas. Conserto:
`CUNHA_INVERTIDA = true` no topo de `ScenarioCasas.lua`.

## API

```lua
-- pista (modo principal)
C.MarcarPonto(nomePasta)         -- larga o próximo ponto onde a câmera olha
C.AoLongoDaPista(opcoes)         -- monta o cenário inteiro seguindo a trilha
C.DefinirPista(origem, fechado)  -- registra a pista sem construir nada

-- colocar na mão
C.Aqui(opcoes)                   -- uma construção onde a câmera está olhando
C.NaSelecao(opcoes)              -- uma em cada Part selecionada no Studio
C.ColocarEm(posOuCFrame, opcoes) -- uma construção num lugar específico
C.Marcadores(pasta, opcoes)      -- constrói a partir de uma pasta de marcadores

-- utilidades
C.Limpar(nome, pai)              -- apaga um cenário construído
C.AplicarAtmosfera(opcoes)       -- alinha a névoa do jogo com as casas
C.Construir(opcoes)              -- modo secundário: leque em volta de um ponto
C.PALETA                         -- as cores, pra reaproveitar
```

Arquétipos: `Chale`, `Sobrado`, `Celeiro`, `Capela`, `Placa`.
