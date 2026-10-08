# Gancho de voo (gancho 2 · SEGURAR + tag `Voar_Gancho`)

Diagnóstico, solução, código, configuração e testes. Todo o código abaixo foi aplicado numa cópia dos
scripts que você mandou e passou no verificador de tipos do Luau em modo `--!strict`, com as definições da
API do Roblox: **0 erros, 0 avisos**. Os módulos que você não mandou (`Camera`, `Tela`, `BotoesDoCelular`,
`BoostPads`) entraram como "stubs", só com as funções que o gancho usa. A física em si eu simulei fora do
Roblox, com as mesmas fórmulas do script (não consigo rodar o Studio daqui).

---

## ETAPA 1 — Diagnóstico

### O que o vídeo mostra (22 s, analisei quadro a quadro)
- **9–10 s**: você mira no poste com o gancho 2 (SEGURAR).
- **10,5–11,5 s**: o gancho prende (ícone verde), mas o quadriciclo continua parado no chão: a corda só "segura".
- **12–19 s**: você sai da beirada e fica ~7 s pendurado, indo e voltando em volta do penhasco e batendo na
  parede. O arco é curto, lento e não ganha velocidade.
- **19,5–22 s**: você solta em cima de outro pilar e o ícone 2 mostra **20** (recarga). Um segundo ponto de voo seria impossível.

### Causas no código (da mais forte para a mais fraca)
| # | Onde | O que acontece |
|---|------|----------------|
| 1 | `Gancho` (cliente) › `comecarBalanco` | `velocidade -= direcao * velocidade:Dot(direcao)` joga fora a parte da velocidade que vai **na direção da corda**. Com o ponto à frente e acima, essa é justamente a sua velocidade "para a frente". Depois ainda corta em 55. Simulando: chegar a 50 studs/s faz o balanço começar a **26**; chegar a 95 faz começar a **55**. |
| 2 | `ConfiguracaoPadrao` › `Balanco...` | `BalancoGravidade = 55` (28% da gravidade do jogo, 196,2), `BalancoFlutuar = 0.4` (câmera lenta no alto), `BalancoAmortecimento = 0.35` (perde ~30% da velocidade por segundo), `BalancoVelocidadeMaxima = 55`. Meio balanço leva **2,5 a 3,7 s**: é a sensação de "flutuar devagar". |
| 3 | `balancar` | `BALANCO_ALTURA_LIMITE = -0.15`: ele nunca sobe até a altura do ponto. A subida é **apagada** (energia jogada fora), então não existe o momento de ser arremessado para cima. |
| 4 | `estilingue` | No SEGURAR, soltar só devolve a velocidade do balanço (≤ 55). O impulso extra (`GanchoImpulsoSoltar`) é só do IMPULSO. |
| 5 | `QuadricicloCliente` › `atualizar` | O alvo dos motores fica sempre a no máximo 4 studs/s da velocidade real, e a velocidade desejada nunca passa de `maximaAgora` (40 + ladeira). Ao pousar a 90 studs/s, os 4 motores freiam com torque máximo e você volta para ~40 em menos de meio segundo. Os BoostPads já têm uma exceção (`extraDoBoost`); o gancho não tinha. |
| 6 | `Gancho` (servidor) › `soltar` | Qualquer uso do SEGURAR grava `GanchoRecargaAteSegurar` = agora + 20 s. Por isso o combo é impossível (o "20" no fim do vídeo). |
| 7 | `comecarBalanco` | A corda é cortada em `BalancoCordaMaxima` (60) de uma vez: pegar de longe dá um puxão seco. |

### O que conferi e NÃO é problema
- **Network Ownership**: o `Motorista.aoMudarOcupante` passa a física para quem dirige. As forças do balanço (no cliente) têm efeito na hora e replicam para todo mundo. Nada a mudar.
- **Forças em conflito**: a escalada só liga com `ParedeEscalavel`; a força do IMPULSO é desligada a cada frame quando o gancho não é IMPULSO; o `Torque` do `Sensacao` só age com 3+ rodas no chão; a "leveza" do `Monstro` desliga quando acha o `BalancoGancho`. Os motores giram no ar, mas não freiam o veículo.
- **FPS**: o balanço já usa `dt`.

---

## ETAPA 2 — Solução

Não criei gancho novo nem sistema paralelo. O gancho de voo **é o SEGURAR**, com um "modo voo" que liga
sozinho quando o alvo está num Model com a tag `Voar_Gancho`. Ele reaproveita o balanço que já existe
(`comecarBalanco` → `balancar` → `estilingue`), só que com números próprios (`GanchoVoo...`):

1. **Lançamento** (uma vez por gancho): velocidade do voo = `chegada × 0.85 + 12`, nunca menos que 60 nem mais que 120 studs/s, aplicada no veículo inteiro na hora. Quem chega rápido aproveita; quem chega devagar ganha o mínimo.
2. **Balanço do voo**: gravidade 120, sem câmera lenta, quase sem amortecimento, máximo 120, sobe até um pouco acima do ponto. Corda comprida é recolhida até 45 studs, a 40 studs/s e sem tranco.
3. **Saída**: velocidade do balanço × 1.1, mais 12 para cima (mais o PERFEITO que já existe), limitada a `VelocidadeMaximaTotal`.
4. **Embalo**: ao pousar, os motores deixam a velocidade cair aos poucos em 2,5 s (o mesmo truque do BoostPads, mas sem acelerar).
5. **Recarga independente**: quem decide é o **servidor**, pela tag (não confia no cliente). O voo não lê, não inicia e não reinicia a recarga do SEGURAR. Contra clique repetido sem querer, só o **mesmo ponto** espera 0,75 s; os outros pegam na hora.
6. **Combo num clique (PC)**: preso num ponto, segure o botão direito sobre o próximo (a mira fica **azul**) e clique: solta um e pega o outro no mesmo clique.

**Simulação** (as mesmas fórmulas do script, soltando no melhor momento; "alcance" = distância na
horizontal até cair 40 studs abaixo de onde você pegou o gancho):

| Situação | Hoje: balanço (início → máx.) | Hoje: alcance | Novo: balanço | Novo: alcance |
|---|---|---|---|---|
| chega a 25 studs/s, ponto 30 à frente e 25 acima | 16 → 34 | 57 | 60 → 82 | 111 |
| chega a 50 studs/s, ponto 40 à frente e 25 acima | 26 → 45 | 77 | 60 → 91 | 173 |
| chega a 95 studs/s caindo, ponto 50 à frente e 30 acima | 55 → 55 | 100 | 95 → 119 | 261 |
| chega a 60 studs/s, ponto longe (70 à frente, 20 acima) | 17 → 54 | 111 | 63 → 116 | 264 |

O meio balanço cai de 2,5–3,7 s para 1,3–1,6 s. Em 30, 60, 144 e 240 FPS a velocidade do balanço muda menos de 1%.

**Duas decisões que tomei (as duas dá para mudar):**
- Fora dos pontos com a tag, o SEGURAR **não balança mais**: ele só segura (corda que salva da queda, escalada, prender jogador), porque o balanço é o "voo". Para manter o balanço antigo em superfícies normais, coloque `GanchoSegurarBalancaSemTag = true`.
- No chão, o gancho de voo prende e espera: o lançamento acontece quando as rodas saem do chão (pulo, rampa, beirada), ou na hora se você já estiver no ar. É a mesma regra de hoje (0,15 s no ar) e evita arrastar o quadriciclo pelo chão.

---

## ETAPA 3 — Implementação

Faça **na ordem**: a `ConfiguracaoPadrao` primeiro, porque o servidor lê os valores novos com tipo
(`--!strict`) e, sem eles, o Script Analysis acusa erro. Os scripts continuam com `--!strict` no topo e nada usa `wait`/`spawn`/`delay` antigos.

### PASSO 1 — `ReplicatedStorage › Compartilhado › ConfiguracaoPadrao`
Na tabela `PADRAO`, logo **depois** da linha `BalancoChuteParede = 25, ...` (a última do bloco "O BALANÇO"), adicione:
```lua
	-- ---------- (NOVO) GANCHO DE VOO: o SEGURAR (gancho 2) num Model com a tag "Voar_Gancho" ----------
	-- Acertou um ponto de voo: o veículo é LANÇADO num balanço rápido e SEM RECARGA (dá para emendar
	-- vários pontos seguidos). Em qualquer outra coisa, o SEGURAR continua igual (corda, escalada, jogador).
	GanchoVooAproveitamento = 0.85, -- Quanto da velocidade de CHEGADA vira velocidade do voo (0.85 = 85%).
	GanchoVooImpulso = 12, -- (studs/s) Empurrão que TODO acerto num ponto de voo dá, somado à conta de cima.
	GanchoVooVelocidadeMinima = 60, -- (studs/s) Chegou devagar? O voo começa com pelo menos isso.
	GanchoVooVelocidadeMaxima = 120, -- (studs/s) O balanço do voo nunca passa disso.
	GanchoVooGravidade = 120, -- (studs/s²) A "gravidade" do balanço do voo. Maior = desce mais rápido e ganha mais velocidade.
	GanchoVooAmortecimento = 0.05, -- (por segundo) Quanto o voo perde de velocidade sozinho (0 = nada · o balanço normal usa 0.35).
	GanchoVooAlturaLimite = 0.3, -- O mais alto que ele sobe: 0 = na altura do ponto · 0.3 = um pouco acima · -0.15 = o balanço normal.
	GanchoVooCordaMaxima = 45, -- (studs) Pegou o ponto de longe? A corda é recolhida até este tamanho...
	GanchoVooRecolher = 40, -- (studs/s) ...nesta velocidade (freando no fim, sem tranco).
	GanchoVooSaidaBonus = 1.1, -- Ao SOLTAR do ponto de voo: sai com 10% a mais da velocidade do balanço...
	GanchoVooSaidaSubida = 12, -- (studs/s) ...e mais este tanto para cima. (Nunca passa de VelocidadeMaximaTotal.)
	GanchoVooEmbaloTempo = 2.5, -- (s) Depois de soltar, os motores NÃO cortam a velocidade extra de uma vez: ela cai aos poucos neste tempo.
	GanchoVooMesmoPonto = 0.75, -- (s) Soltou de um ponto? O MESMO ponto só pega de novo depois disso (os outros pegam na hora).
	GanchoSegurarBalancaSemTag = false, -- true = o SEGURAR em superfície SEM a tag também balança (o jeito antigo: lento e com recarga).
```
*Por quê:* todos os números do voo ficam ajustáveis num lugar só, e todo veículo recebe os valores sozinho (o `Padrao.completar` preenche o que faltar).

### PASSO 2 — `ServerScriptService › QuadricicloServidor › Gancho` (servidor)

**2.1** Logo depois de `local TEMPO_MAX_VOO = 3 -- ...`, adicione:
```lua
local TAG_VOAR_GANCHO = "Voar_Gancho" -- (NOVO) o SEGURAR num Model com esta tag vira o GANCHO DE VOO (sem recarga)
```

**2.2** Dentro de `type Estado = {`, logo depois de `tipo: string, -- o TIPO do gancho ...`, adicione:
```lua
	voo: Instance?, -- (NOVO) o ponto de VOO (o Model com a tag) do gancho atual (nil = gancho normal)
	ultimoVoo: Instance?, -- (NOVO) o último ponto de voo de onde este veículo soltou...
	ultimoVooEm: number, -- (NOVO) ...e quando (os.clock)
```

**2.3** Logo **depois** da função `pecaFixa` (antes do comentário `-- CENÁRIO: RopeConstraint do Chassi até a ponta...`), adicione:
```lua
-- (NOVO) GANCHO DE VOO: o Model com a tag "Voar_Gancho" onde esta peça está (sobe pelos Models e
-- Folders de cima, até os aninhados), ou nil. (A própria peça com a tag também vale.)
local function pontoDeVoo(parte: Instance): Instance?
	local atual: Instance? = parte
	while atual and atual ~= workspace do
		if CollectionService:HasTag(atual, TAG_VOAR_GANCHO) then
			return atual
		end
		atual = atual.Parent
	end
	return nil
end

```
*Por quê:* sobe pelos pais da peça (Models aninhados também) e só olha esta tag, sem conflito com as outras.

**2.4** Na função `soltar`, localize:
```lua
	local dono = estado.dono
	estado.dono = nil
	if dono then
```
e troque por:
```lua
	local dono = estado.dono
	estado.dono = nil
	local voo = estado.voo -- (NOVO)
	estado.voo = nil
	if voo then
		-- (NOVO) GANCHO DE VOO: não usa nem começa a recarga. Só guarda de qual ponto você soltou
		-- (o MESMO ponto espera um pouquinho; os outros, não).
		estado.ultimoVoo = voo
		estado.ultimoVooEm = os.clock()
	elseif dono then
```
(O `dono:SetAttribute(...)` e o `end` logo abaixo continuam iguais.) *Por quê:* o voo não grava a recarga.

**2.5** Em `Gancho.ligar`, troque a linha `local estado: Estado = { v = v, ... tipo = "Segurar" }` por:
```lua
	local estado: Estado = { v = v, saida = saida, alvo = alvo, pecas = {}, conexao = nil, desfazer = nil, dono = nil, tipo = "Segurar",
		voo = nil, ultimoVoo = nil, ultimoVooEm = 0 } -- (NOVO: voo, ultimoVoo e ultimoVooEm)
```

**2.6** Em `Gancho.aoLigar`, localize:
```lua
	-- RECARGA DESTE TIPO: enquanto não passar o horário marcado no Player, este gancho não funciona.
	local recargaAte = jogador:GetAttribute("GanchoRecargaAte" .. tipo)
	if typeof(recargaAte) == "number" and recargaAte > workspace:GetServerTimeNow() then
		return
	end
```
e troque por:
```lua
	-- (NOVO) GANCHO DE VOO: o SEGURAR num Model com a tag "Voar_Gancho" NÃO depende da recarga.
	local voo = if tipo == "Segurar" then pontoDeVoo(alvo) else nil
	if voo and voo == estado.ultimoVoo and os.clock() - estado.ultimoVooEm < v.Config.GanchoVooMesmoPonto * 0.5 then
		return -- acabou de soltar DESTE ponto: clique repetido sem querer. (Metade do tempo: a internet atrasa o "soltar".)
	end
	-- RECARGA DESTE TIPO: enquanto não passar o horário marcado no Player, este gancho não funciona.
	local recargaAte = jogador:GetAttribute("GanchoRecargaAte" .. tipo)
	if voo == nil and typeof(recargaAte) == "number" and recargaAte > workspace:GetServerTimeNow() then
		return
	end
```
*Por quê:* o servidor decide pela tag: um trapaceiro não consegue pular a recarga mandando "é voo".

**2.7** No fim de `Gancho.aoLigar`, logo **antes** de `lancar(estado, jogador, alvo, ponto, humanoide, raiz, tipo)`, adicione:
```lua
	estado.voo = voo -- (NOVO) o soltar precisa saber se este gancho é de voo (sem recarga)
```

### PASSO 3 — `StarterPlayer › StarterPlayerScripts › QuadricicloCliente › Gancho` (cliente)

**3.1** No topo, logo depois de `local TAG_PAREDE_ESCALAVEL = "ParedeEscalavel" -- ...`, adicione:
```lua
local TAG_VOAR_GANCHO = "Voar_Gancho" -- (NOVO) o SEGURAR num Model com esta tag vira o GANCHO DE VOO
local COR_MIRA_VOO = Color3.fromRGB(80, 210, 255) -- (NOVO) a mira fica azul em cima de um ponto de voo
```

**3.2** Logo depois de `local tipoAtivo: string? = nil -- ...`, adicione:
```lua
-- (NOVO) GANCHO DE VOO (o SEGURAR num ponto com a tag "Voar_Gancho")
local pontoVooAtivo: Instance? = nil -- o ponto de voo onde o NOSSO gancho está agora (nil = gancho normal)
local impulsoDoVooPendente = false -- true = este gancho ainda vai dar o lançamento (uma vez só por gancho)
local ultimoPontoVoo: Instance? = nil -- o último ponto de voo de onde você soltou...
local soltouVooEm = 0 -- ...e quando (os.clock)
local embaloNoPouso = false -- true = soltou de um ponto de voo e ainda não pousou (o embalo começa no pouso)
local embaloExtra = 0 -- (studs/s) depois do pouso: quanto acima da velocidade máxima os motores deixam passar...
local embaloAte = 0 -- ...e até quando (os.clock). Vai caindo até 0.
```

**3.3** Logo **antes** do comentário `-- Dá para prender o gancho neste acerto da mira? ...` (que fica em cima da `alvoValido`), adicione:
```lua
-- (NOVO) GANCHO DE VOO: o Model com a tag "Voar_Gancho" onde está a peça que a mira acertou (sobe pelos
-- Models e Folders de cima, até os aninhados), ou nil. Só vale para o SEGURAR: é ele que vira o gancho de voo.
local function pontoDeVooNaMira(acerto: RaycastResult?): Instance?
	if acerto == nil or tipoSelecionado ~= "Segurar" then
		return nil
	end
	local atual: Instance? = acerto.Instance
	while atual and atual ~= workspace do
		if CollectionService:HasTag(atual, TAG_VOAR_GANCHO) then
			return atual
		end
		atual = atual.Parent
	end
	return nil
end

```
E **dentro** da `alvoValido`, logo antes de `return not zonaNoCaminho(quad.chassi.Position, acerto.Position, tipoSelecionado) -- ...`, adicione:
```lua
	-- (NOVO) Acabou de soltar DESTE ponto de voo? Ele espera um pouquinho (evita repetir sem querer).
	local ponto = pontoDeVooNaMira(acerto)
	if ponto and ponto == ultimoPontoVoo and os.clock() - soltouVooEm < (tonumber(quad.Config.GanchoVooMesmoPonto) or 0.75) then
		return false
	end
```

**3.4** Na `soltarMeuGancho`, localize:
```lua
	local estadoServidor = quad.modelo:GetAttribute("GanchoEstado")
	if estadoServidor == "NoAr" or estadoServidor == "Preso" then
		-- o ícone deste tipo já mostra a recarga (o Servidor confirma logo depois)
		recargaPrevista[tipo] = workspace:GetServerTimeNow() + recargaDoTipo(quad, tipo)
	end
```
e troque por:
```lua
	local estadoServidor = quad.modelo:GetAttribute("GanchoEstado")
	local ponto = pontoVooAtivo -- (NOVO)
	pontoVooAtivo = nil
	impulsoDoVooPendente = false
	if ponto then
		-- (NOVO) GANCHO DE VOO: sem recarga. Só guarda de qual ponto você soltou (o MESMO espera um pouquinho).
		ultimoPontoVoo = ponto
		soltouVooEm = os.clock()
	elseif estadoServidor == "NoAr" or estadoServidor == "Preso" then
		-- o ícone deste tipo já mostra a recarga (o Servidor confirma logo depois)
		recargaPrevista[tipo] = workspace:GetServerTimeNow() + recargaDoTipo(quad, tipo)
	end
```

**3.5** No `type Balanco = {`, logo depois de `ultimaBatida: number, -- ...`, adicione:
```lua
	voo: boolean, -- (NOVO) é o balanço do GANCHO DE VOO? (aí valem os números GanchoVoo...)
```

**3.6** Logo **antes** do comentário `-- Começou a balançar: guarda o gancho, o tamanho da corda...` (em cima da `comecarBalanco`), adicione a função nova:
```lua
-- (NOVO) O LANÇAMENTO DO GANCHO DE VOO: a velocidade com que o voo começa.
--   Chegou rápido = aproveita GanchoVooAproveitamento da velocidade (+ GanchoVooImpulso).
--   Chegou devagar = ganha pelo menos GanchoVooVelocidadeMinima. Nunca passa de GanchoVooVelocidadeMaxima.
-- Vale UMA vez por gancho: se ele encostar no chão e voltar a balançar, continua com a velocidade que tem
-- (sem ganhar outro lançamento). O veículo inteiro já sai nessa velocidade, na hora (sem "atraso").
local function impulsoDoVoo(quad: Quadriciclo, chegada: Vector3, deLado: Vector3, corda: Vector3): Vector3
	local Config = quad.Config
	local minima = numeroDaConfig(Config.GanchoVooVelocidadeMinima, 60)
	local maxima = math.max(numeroDaConfig(Config.GanchoVooVelocidadeMaxima, 120), minima)
	if not impulsoDoVooPendente then
		return if deLado.Magnitude > maxima then deLado.Unit * maxima else deLado -- (já ganhou o deste gancho)
	end
	impulsoDoVooPendente = false
	-- Para onde: para onde você já ia ("de lado" para a corda: é o único jeito de um balanço andar).
	-- Quase parado, ou caindo bem na direção da corda? Para a frente do veículo.
	local rumo = deLado
	if rumo.Magnitude < 2 then
		local frente = Veiculo.referencia(quad).LookVector
		rumo = frente - corda * frente:Dot(corda)
	end
	if rumo.Magnitude < 0.01 then
		return deLado -- (caso raro: a frente aponta bem na direção da corda)
	end
	local aproveitamento = numeroDaConfig(Config.GanchoVooAproveitamento, 0.85)
	local impulso = numeroDaConfig(Config.GanchoVooImpulso, 12)
	local rapidez = math.clamp(chegada.Magnitude * aproveitamento + impulso, minima, maxima)
	local velocidade = rumo.Unit * rapidez
	for _, parte in quad.pecasFisicas do
		parte.AssemblyLinearVelocity = velocidade -- todas as peças juntas: o veículo sai inteiro
	end
	CameraModulo.tremer(0.08) -- um tranco na tela: "fui lançado!"
	return velocidade
end

```
*Por quê:* é o "impulso perceptível" que depende da velocidade de chegada, com mínimo e máximo.

**3.7** Na `comecarBalanco`, localize:
```lua
	local comprimento = math.clamp(daAncora.Magnitude, minima, maxima)
	-- A velocidade de agora vira a do balanço (só a parte "de lado" para a corda, e sem exagero).
	local velocidade = quad.chassi.AssemblyLinearVelocity
	velocidade -= direcao * velocidade:Dot(direcao)
	if velocidade.Magnitude > velocidadeMaxima then
		velocidade = velocidade.Unit * velocidadeMaxima
	end
```
e troque por:
```lua
	local voo = pontoVooAtivo ~= nil -- (NOVO) é o GANCHO DE VOO? (o SEGURAR num ponto com a tag)
	-- (NOVO) No voo, a corda começa do tamanho de verdade (sem pular): o carretel do balancar recolhe aos poucos.
	local comprimento = if voo then math.max(daAncora.Magnitude, minima) else math.clamp(daAncora.Magnitude, minima, maxima)
	-- A velocidade de agora vira a do balanço (só a parte "de lado" para a corda, e sem exagero).
	local chegada = quad.chassi.AssemblyLinearVelocity -- (NOVO) a velocidade com que você chegou (inteira)
	local velocidade = chegada - direcao * chegada:Dot(direcao)
	if voo then
		velocidade = impulsoDoVoo(quad, chegada, velocidade, direcao) -- (NOVO) o lançamento do voo
	elseif velocidade.Magnitude > velocidadeMaxima then
		velocidade = velocidade.Unit * velocidadeMaxima
	end
```
E no `return { ... }` do fim da mesma função, logo depois de `ultimaBatida = 0,`, adicione:
```lua
		voo = voo, -- (NOVO)
```

**3.8** Na `balancar`, logo depois de `penduradoAgora = true`, adicione:
```lua
	-- (NOVO) GANCHO DE VOO: os números do voo (mais rápido, sem câmera lenta, sobe mais) e o carretel.
	local alturaLimite = BALANCO_ALTURA_LIMITE
	if estado.voo then
		gravidade = numeroDaConfig(Config.GanchoVooGravidade, 120)
		velocidadeMaxima = numeroDaConfig(Config.GanchoVooVelocidadeMaxima, 120)
		amortecimento = numeroDaConfig(Config.GanchoVooAmortecimento, 0.05)
		flutuar = 0 -- nada de câmera lenta lá no alto
		alturaLimite = numeroDaConfig(Config.GanchoVooAlturaLimite, 0.3)
		-- CARRETEL: pegou de longe? A corda encurta até GanchoVooCordaMaxima (freando nos últimos 4 studs).
		local falta = estado.comprimento - numeroDaConfig(Config.GanchoVooCordaMaxima, 45)
		if falta > 0 then
			local recolher = numeroDaConfig(Config.GanchoVooRecolher, 40)
			estado.comprimento -= math.min(falta, recolher * math.clamp(falta / 4, 0.25, 1) * dt)
		end
	end
```
Mais abaixo na mesma função, troque a linha `if u.Y > BALANCO_ALTURA_LIMITE then` por:
```lua
	if u.Y > alturaLimite then -- (NOVO: era BALANCO_ALTURA_LIMITE; no voo ele sobe mais)
```
E troque a linha `puxador.MaxForce = estado.massa * 900 -- ...` por:
```lua
	puxador.MaxForce = estado.massa * (if estado.voo then 1800 else 900) -- (NOVO) no voo, força para as curvas rápidas
```

**3.9** Na `estilingue`, logo depois de `local maximaDoBalanco = numeroDaConfig(ajustes.BalancoVelocidadeMaxima, BALANCO_VELOCIDADE_MAXIMA)`, adicione:
```lua
		if doBalanco.voo then
			maximaDoBalanco = numeroDaConfig(ajustes.GanchoVooVelocidadeMaxima, 120) -- (NOVO) o PERFEITO do voo usa a máxima do voo
		end
```
E, na mesma função, logo **antes** do `for _, parte in quad.pecasFisicas do` que tem `parte.AssemblyLinearVelocity = lancamento`, adicione:
```lua
		if doBalanco.voo then
			-- (NOVO) GANCHO DE VOO: ao soltar, sai um pouco mais forte e para cima ("fui lançado!"), sem passar
			-- da VelocidadeMaximaTotal. E arma o EMBALO: no pouso, os motores não cortam essa velocidade de uma vez.
			lancamento = lancamento * numeroDaConfig(ajustes.GanchoVooSaidaBonus, 1.1)
				+ Vector3.yAxis * numeroDaConfig(ajustes.GanchoVooSaidaSubida, 12)
			local limite = numeroDaConfig(ajustes.VelocidadeMaximaTotal, 130)
			if lancamento.Magnitude > limite then
				lancamento = lancamento.Unit * limite
			end
			embaloNoPouso = true -- (o embalo começa quando as rodas tocarem o chão: veja o atualizarImpulso)
		end
```

**3.10** Logo **antes** do comentário `-- Chamada pelo QuadricicloCliente ANTES de cada passo da física...` (em cima da `Gancho.atualizarImpulso`), adicione:
```lua
-- (NOVO) EMBALO DO GANCHO DE VOO: logo depois de POUSAR de um voo, quanto (studs/s) o veículo pode passar
-- da velocidade máxima SEM os motores frearem. Começa com toda a sobra do pouso e cai até 0 em
-- GanchoVooEmbaloTempo segundos: a velocidade do voo vai embora aos poucos, e não num tranco ao pousar.
-- (O QuadricicloCliente chama a cada frame, igual ao extra do BoostPads.)
function Gancho.embaloDoVoo(quad: Quadriciclo): number
	local restante = embaloAte - os.clock()
	if restante <= 0 then
		return 0
	end
	local duracao = math.max(numeroDaConfig(quad.Config.GanchoVooEmbaloTempo, 2.5), 0.1)
	return embaloExtra * math.clamp(restante / duracao, 0, 1)
end

```

**3.11** Dentro da `Gancho.atualizarImpulso`, logo depois de `tempoNoAr = if noChao then 0 else tempoNoAr + dt`, adicione:
```lua
	-- (NOVO) EMBALO DO VOO: soltou de um ponto de voo e as rodas tocaram o chão agora? O embalo começa AQUI,
	-- com a velocidade do pouso (e vai caindo até a velocidade normal em GanchoVooEmbaloTempo segundos).
	if embaloNoPouso and noChao then
		embaloNoPouso = false
		embaloExtra = math.max(chassi.AssemblyLinearVelocity.Magnitude - numeroDaConfig(Config.MaxSpeed, 40), 0)
		embaloAte = os.clock() + numeroDaConfig(Config.GanchoVooEmbaloTempo, 2.5)
	end
```
E, mais abaixo, localize:
```lua
	-- (NOVO) SEGURAR pendurado (rodas fora do chão e sem estar escalando parede): balança solto.
	if enviadoEm ~= nil and tipoAtivo == "Segurar" and corda ~= nil and corda.Enabled
		and tempoNoAr >= TEMPO_NO_AR and not escalando
	then
```
e troque por:
```lua
	-- SEGURAR pendurado (rodas fora do chão e sem estar escalando parede): balança.
	-- (NOVO) Só num ponto de VOO (tag "Voar_Gancho"). Fora deles o SEGURAR só segura (corda e escalada),
	-- a não ser que GanchoSegurarBalancaSemTag = true na Configuracao.
	if enviadoEm ~= nil and tipoAtivo == "Segurar" and corda ~= nil and corda.Enabled
		and tempoNoAr >= TEMPO_NO_AR and not escalando
		and (pontoVooAtivo ~= nil or Config.GanchoSegurarBalancaSemTag == true)
	then
```
(O `balancar(quad, pedal, volante or 0, dt, corda)` e o `end` logo abaixo continuam iguais.)

**3.12** Na `atualizarGancho`:
- no primeiro `if` (o do "O Servidor recusou o alvo..."), logo depois de `tipoAtivo = nil`, adicione:
```lua
		pontoVooAtivo = nil -- (NOVO)
		impulsoDoVooPendente = false -- (NOVO)
```
- troque a linha `atualizarEscalada(quad, enviado ~= nil and estadoServidor == "Preso" and tipoAtivo == "Segurar")` por:
```lua
	atualizarEscalada(quad, enviado ~= nil and estadoServidor == "Preso" and tipoAtivo == "Segurar" and pontoVooAtivo == nil) -- (NOVO: no voo não escala)
```
- no fim da função, dentro do `if quad.mirandoGancho then`, troque estas 2 linhas:
```lua
		local pode = recargaRestante(tipoSelecionado) <= 0 and alvoValido(quad, mirarGancho(quad))
		hud.mira.GroupColor3 = if pode then Color3.new(1, 1, 1) else corProibida(quad)
```
por:
```lua
		-- (NOVO) Num ponto de VOO ela fica AZUL, mesmo com o SEGURAR recarregando (o voo não usa a recarga).
		local acerto = mirarGancho(quad)
		local valido = alvoValido(quad, acerto)
		if valido and pontoDeVooNaMira(acerto) ~= nil then
			hud.mira.GroupColor3 = COR_MIRA_VOO
		elseif valido and recargaRestante(tipoSelecionado) <= 0 then
			hud.mira.GroupColor3 = Color3.new(1, 1, 1)
		else
			hud.mira.GroupColor3 = corProibida(quad)
		end
```

**3.13** Na `dispararGancho`, localize:
```lua
	local acerto = mirarGancho(quad) -- (a câmera ainda está na posição de mira neste instante)
	if recargaRestante(tipoSelecionado) > 0 then
```
e troque por:
```lua
	local acerto = mirarGancho(quad) -- (a câmera ainda está na posição de mira neste instante)
	local pontoVoo = pontoDeVooNaMira(acerto) -- (NOVO) ponto de VOO: o SEGURAR funciona mesmo recarregando
	if recargaRestante(tipoSelecionado) > 0 and pontoVoo == nil then
```
E, logo depois de `esquecerMeuGancho() -- (por garantia: nenhuma corda velha sobrando)`, adicione:
```lua
		pontoVooAtivo = pontoVoo -- (NOVO) este gancho é de VOO? (nil = gancho normal)
		impulsoDoVooPendente = if pontoVoo then true else false -- (NOVO) ...então ele dá o lançamento (uma vez só)
```

**3.14** Na `aoGancho` (controle e celular), localize estas 3 linhas:
```lua
		elseif recargaRestante(tipoSelecionado) > 0 then
			avisarRecarga(quad, tipoSelecionado)
		elseif dentroDeZona(quad, tipoSelecionado) then
```
e troque as 3 por:
```lua
		elseif recargaRestante(tipoSelecionado) > 0 and tipoSelecionado ~= "Segurar" then -- (NOVO) o SEGURAR mira mesmo recarregando (pode ser um ponto de voo)
			avisarRecarga(quad, tipoSelecionado)
		elseif dentroDeZona(quad, tipoSelecionado) then
```
(Só a 1ª linha muda; a 2ª e a 3ª ficam iguais. Não duplique o `elseif dentroDeZona`.)

**3.15** Na `aoApertarMouse`, no ramo do botão DIREITO, localize estas 2 linhas:
```lua
		if recargaRestante(tipoSelecionado) > 0 then
			avisarRecarga(quad, tipoSelecionado) -- avisa que este gancho ainda está recarregando
```
e troque as 2 por:
```lua
		if recargaRestante(tipoSelecionado) > 0 and tipoSelecionado ~= "Segurar" then -- (NOVO) o SEGURAR pode mirar um ponto de voo
			avisarRecarga(quad, tipoSelecionado) -- avisa que este gancho ainda está recarregando
```
(Só a 1ª linha muda. Não duplique o `avisarRecarga`.)
E, no ramo do botão ESQUERDO, localize:
```lua
		if enviadoEm ~= nil then
			estilingue(quad) -- (só faz algo se for o gancho de IMPULSO preso)
			soltarMeuGancho(quad)
		elseif quad.mirandoGancho then
			dispararGancho(quad)
		end
```
e troque por:
```lua
		if enviadoEm ~= nil then
			estilingue(quad) -- (só faz algo se for o gancho de IMPULSO preso)
			soltarMeuGancho(quad)
			-- (NOVO) COMBO DE VOO: segurando o botão direito em OUTRO ponto de voo? O próximo gancho já sai
			-- neste mesmo clique: solta um ponto e pega o seguinte sem perder tempo.
			local acerto = if quad.mirandoGancho then mirarGancho(quad) else nil
			if pontoDeVooNaMira(acerto) ~= nil and alvoValido(quad, acerto) then
				dispararGancho(quad)
			end
		elseif quad.mirandoGancho then
			dispararGancho(quad)
		end
```

**3.16** Na `Gancho.criarVisual` (lá embaixo, na parte VISUAL):
- logo depois de `local curvaCorda = 0`, adicione:
```lua
	local alvoDoDesenho: Instance? = nil -- (NOVO) o alvo que o desenho está seguindo (para perceber a troca no COMBO)
```
- dentro da `atualizarVisualGancho`, logo depois de `visualGancho = visual`, adicione:
```lua
		-- (NOVO) COMBO DE VOO: o gancho trocou de alvo direto (sem sumir antes)? O desenho recomeça o voo.
		if alvo ~= alvoDoDesenho then
			alvoDoDesenho = alvo
			percorridoVisual = 0
			visual.prendeu = false
		end
```
*Por quê:* no combo, o servidor solta um ponto e prende o próximo no mesmo frame. Sem isto, o desenho do gancho não recomeça o voo.

### PASSO 4 — `StarterPlayer › StarterPlayerScripts › QuadricicloCliente` (LocalScript)
Na função `atualizar`, logo depois do bloco do BoostPads (o `if extraDoBoost > 0 ... end`), adicione:
```lua
	-- (NOVO) EMBALO DO GANCHO DE VOO: logo depois de POUSAR de um voo, os motores NÃO cortam de uma vez
	-- a velocidade que você trouxe do voo: ela cai aos poucos, em GanchoVooEmbaloTempo segundos.
	-- (O math.min só MANTÉM a sua velocidade: não acelera além da que você já tem.)
	local extraDoVoo = Gancho.embaloDoVoo(quad)
	if extraDoVoo > 0 and pedal > -ZONA_MORTA and velocidadeFrente > -VELOCIDADE_TROCA_SENTIDO then
		desejada = math.max(desejada, math.min(velocidadeFrente, maximaAgora + extraDoVoo))
		ritmo = math.max(ritmo, Config.Acceleration * 2)
	end
```
*Por quê:* é a causa 5. Sem isto, os motores cortam a velocidade do voo no instante do pouso.

---

## ETAPA 4 — Configuração

### Colocar a tag `Voar_Gancho`
1. No Explorer, selecione o **Model** do ponto (ex.: `Workspace › Cenario › GanchoDoCenario`).
2. Na janela **Properties**, desça até a seção **Tags**, clique em **+**, digite `Voar_Gancho` e aperte Enter (maiúsculas e o `_` contam).
3. (Atalho pela Command Bar: `game:GetService("CollectionService"):AddTag(workspace.Cenario.GanchoDoCenario, "Voar_Gancho")`.)
4. As peças do ponto precisam estar **Anchored** (o servidor só aceita cenário preso no mundo).
5. Copie e cole o Model para criar vários pontos: a tag vai junto.

**Dicas de montagem:** a tag vale para o Model inteiro, inclusive Models aninhados dentro dele. Se a base do poste também estiver no Model, acertar a base também vale. Para só o gancho valer, coloque a tag num Model menor que tenha só o gancho. Coloque os pontos **acima** do caminho (corda bem inclinada), a até 100 studs do jogador (`GanchoAlcanceSegurar`), uns 50–80 studs um do outro para o combo. Uma `ZonaSemGancho` continua valendo por cima de tudo.

### Parâmetros (na `ConfiguracaoPadrao`, ou na `Configuracao` de um veículo para valer só nele)
| Parâmetro | Padrão | Para quê |
|---|---|---|
| `GanchoVooVelocidadeMinima` | 60 | Impulso de quem chega devagar. Se ele não atravessa o penhasco, suba para 70–75. |
| `GanchoVooAproveitamento` | 0.85 | Quanto da velocidade de chegada fica. 1.0 = tudo; 0.7 = premia menos quem chega rápido. |
| `GanchoVooImpulso` | 12 | O "empurrão" de cada acerto. Mais alto = combos ganham mais velocidade. |
| `GanchoVooVelocidadeMaxima` | 120 | Teto do voo. É o que impede virar uma "nave descontrolada". |
| `GanchoVooGravidade` | 120 | Mais alto (150) = arco mais rápido e "pesado"; mais baixo (90) = mais solto. |
| `GanchoVooAmortecimento` | 0.05 | Perda de velocidade no balanço. 0 = nenhuma. |
| `GanchoVooAlturaLimite` | 0.3 | Até onde sobe acima do ponto. 0 = só até a altura dele. |
| `GanchoVooCordaMaxima` / `GanchoVooRecolher` | 45 / 40 | Tamanho máximo da corda e a velocidade com que ela recolhe. Corda curta = balanço mais rápido. |
| `GanchoVooSaidaBonus` / `GanchoVooSaidaSubida` | 1.1 / 12 | A força do "arremesso" ao soltar. |
| `GanchoVooEmbaloTempo` | 2.5 | Quanto tempo a velocidade extra demora para sumir depois do pouso. 0 = como hoje. |
| `GanchoVooMesmoPonto` | 0.75 | Espera para pegar o MESMO ponto de novo (os outros pegam na hora). |
| `GanchoSegurarBalancaSemTag` | false | `true` = o SEGURAR volta a balançar (do jeito antigo) em qualquer superfície. |
| `GanchoVelocidadeVoo` (já existia) | 220 | Velocidade do gancho voando até o ponto. 300 deixa o combo mais rápido (vale para todos os ganchos). |

Dica: mude um valor por vez e teste. Primeiro acerte a `GanchoVooVelocidadeMinima` (a travessia), depois a gravidade (a sensação).

---

## ETAPA 5 — Testes

1. **Voo simples**: gancho 2, mire no ponto com a tag (a mira fica **azul**), lance, saia da beirada. Ele tem que dar um tranco e sair rápido, sem câmera lenta. Solte **subindo**: tem que ser arremessado para a frente e para cima.
2. **Velocidade de chegada**: chegue devagar e depois com nitro ou ladeira. O devagar ainda atravessa (mínimo de 60); o rápido vai bem mais longe.
3. **Embalo**: pouse depois do voo olhando o velocímetro. A velocidade tem que cair aos poucos (~2,5 s), e não de uma vez.
4. **Combo**: 3 pontos em linha sobre um buraco. Preso no 1º, segure o botão direito no 2º (azul) e clique. Repita até o 3º. (Controle/celular: aperte para soltar e depois segure e solte para lançar no próximo.)
5. **Recarga independente**: use o SEGURAR numa parede comum (aparece o 20). Durante a contagem, use um ponto de voo: tem que funcionar, e a contagem continua igual (não reinicia nem aumenta). Depois de soltar de um ponto de voo, nenhuma contagem nova aparece.
6. **Clique repetido**: solte de um ponto e clique de novo NELE na hora. A mira fica vermelha por 0,75 s e depois volta a funcionar. Um ponto diferente pega na hora.
7. **Alvos inválidos**: parede sem tag = SEGURAR normal (corda, sem voo, com recarga). Jogador ou veículo = prende como antes. IMPULSO num ponto de voo = IMPULSO normal (com a recarga dele). BOTÃO não muda. Ponto dentro de `ZonaSemGancho` = não pega.
8. **Models aninhados**: coloque a tag num Model que tem outro Model dentro, com o gancho. Acertar a peça de dentro tem que ativar o voo.
9. **Multiplayer**: *Test › Clients and Servers* com 2 jogadores. O jogador 2 vê o gancho, a corda e o quadriciclo do jogador 1 voando liso. No servidor, em `Players › Jogador1 › Attributes`, o `GanchoRecargaAteSegurar` **não muda** quando ele usa um ponto de voo.
10. **FPS**: no jogo publicado, mude a taxa de quadros máxima nas configurações do Roblox (30 e 144/240, se a sua versão tiver essa opção). O voo tem que ir igual.
