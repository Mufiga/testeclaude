# Gancho de voo · atualização 3: pêndulo de FÍSICA, controle no ar

Aplique **por cima** do que você já fez (guia 1 + correção + atualização 2). São 7 mudanças: 1 na
`ConfiguracaoPadrao`, 5 no `Gancho` do cliente e 1 opcional no `Monstro`. O servidor não muda. Tudo foi
aplicado numa cópia dos seus scripts e passou no verificador de tipos do Luau (`--!strict`, com a API do
Roblox): 0 erros, 0 avisos. A física eu simulei fora do Roblox (não consigo rodar o Studio daqui).

## Por que estava duro e sem graça
- **Era um trilho, não física.** Pendurado, um `AlignPosition` arrastava o carro a cada frame até um ponto calculado pelo script. A física de verdade do carro (embalo, peso, corda) era ignorada. Por isso o voo parecia "travado" e as teclas quase não mudavam nada.
- **No vídeo, de 3 a 7 s:** você pega o ponto com as rodas no chão, o carro dá um pulinho e o lançamento é gasto nesse pulinho. Depois ele fica pendurado quase parado embaixo do poste.
- **De 8 a 12 s:** ele capota de cabeça para baixo, sem controle nenhum.
- **De 13 a 18 s:** depois de soltar, o jogador não tem **nenhum controle no ar**. O carro só cai.

## Como fica agora
Quem move o carro é a **física do Roblox**: a corda de verdade (`RopeConstraint`), a gravidade e o embalo. O script só ajuda em 4 coisas:
1. **Lançamento:** quando a corda trava, o carro ganha velocidade para a FRENTE, uma vez por gancho. Se pegar o ponto com as rodas no chão, ele também dá um pulinho para sair do chão.
2. **Carretel:** a corda encurta até 35 studs. Na física, corda mais curta = gira mais rápido, e você não afunda no buraco.
3. **Controle**, pendurado **e depois de soltar, até pousar**:

   | Tecla | O que faz no ar |
   |---|---|
   | **W / S** | empurra para a frente / para trás do carro (pendurado, é "dar embalo" no balanço) |
   | **A / D** | vira o carro para a esquerda / direita (ele deita para o lado da curva) e empurra um pouco de lado |
   | **Botão esquerdo** | solta. Soltar **subindo e rápido** = PERFEITO (mais impulso) |
   | **Direito + esquerdo** | combo: segure o direito no próximo ponto (mira azul) e clique |

4. **Postura macia:** um endireitador suave deixa o carro de pé e virado para onde você mandou. Ele balança e reage à física, mas não sai capotando.

E a gravidade fica 25% mais leve durante o voo (`GanchoVooLeveza`), o que dá mais tempo no ar para mirar o próximo ponto.

Na simulação, com o ponto 40 studs à frente e 25 acima e você chegando a 50 studs/s, o carro desce só 10 studs, passa de 86 studs/s e o melhor momento de soltar é com 0,9 s. Com o ponto a 130 studs, ele desce 20 studs (antes eram 67).

---

## PASSO 1 — `ReplicatedStorage › Compartilhado › ConfiguracaoPadrao`
Apague o bloco inteiro do gancho de voo (da linha `-- ---------- (NOVO) GANCHO DE VOO ...` até `GanchoSegurarBalancaSemTag = false, ...`) e cole este no lugar:
```lua
	-- ---------- (NOVO) GANCHO DE VOO: o SEGURAR (gancho 2) num Model com a tag "Voar_Gancho" ----------
	-- Acertou um ponto de voo: o carro vira um PÊNDULO DE FÍSICA (corda de verdade + gravidade), é lançado para a
	-- frente e você controla no ar. SEM RECARGA (dá para emendar vários pontos). Fora deles, o SEGURAR é o de sempre.
	GanchoVooDistanciaMinima = 30, -- (studs) O ponto de voo só pega se estiver PELO MENOS a esta distância (mais perto = mira vermelha).
	GanchoVooAlcance = 150, -- (studs) ...e no máximo a esta. (O SEGURAR normal continua usando o GanchoAlcanceSegurar.)
	GanchoVooAlturaMinima = 0, -- (studs) O ponto precisa estar pelo menos isso ACIMA do carro (pendurar num ponto baixo joga você no buraco).
	GanchoVooCordaMaxima = 35, -- (studs) O tamanho do pêndulo. Pegou de longe? A corda é recolhida até aqui...
	GanchoVooRecolher = 120, -- (studs/s) ...nesta velocidade (puxa você para a frente e não deixa afundar no buraco).
	GanchoVooAproveitamento = 0.85, -- Quanto da velocidade de CHEGADA vira o lançamento (0.85 = 85%).
	GanchoVooImpulso = 12, -- (studs/s) Empurrão para a FRENTE que todo acerto dá, somado à conta de cima.
	GanchoVooVelocidadeMinima = 60, -- (studs/s) Chegou devagar? O lançamento é de pelo menos isso.
	GanchoVooVelocidadeMaxima = 120, -- (studs/s) Acima disso, as teclas não aceleram mais (a física ainda pode passar um pouco).
	GanchoVooDecolar = 25, -- (studs/s) Pegou o ponto com as rodas no chão? Um pulinho para cima junto com o lançamento.
	GanchoVooLeveza = 0.25, -- No voo, a gravidade fica 25% mais fraca (0 = a do jogo · 0.5 = metade). Mais leve = voa mais longe.
	GanchoVooControle = 70, -- (studs/s²) Pendurado: a força de W/S (frente/trás do carro) e A/D (de lado).
	GanchoVooControleNoAr = 35, -- (studs/s²) Depois de soltar: a força das teclas no ar (até pousar).
	GanchoVooControleNoArTempo = 4, -- (s) Depois de soltar, o controle no ar dura até pousar ou até este tempo.
	GanchoVooVirar = 120, -- (graus/s) Quão rápido A/D viram o carro no ar.
	GanchoVooInclinarCurva = 20, -- (graus) Virando no ar, o carro deita para o lado da curva (0 = não deita).
	GanchoVooBalancarCorpo = 0.3, -- Pendurado, o carro inclina para o lado da corda (0 = sempre reto · 0.45 = bastante).
	GanchoVooGiroSuave = 8, -- Quão FIRME o carro fica de pé no voo (menor = mais solto e balançante · maior = mais firme).
	GanchoVooSaidaBonus = 1.1, -- Ao SOLTAR: sai com 10% a mais da velocidade...
	GanchoVooSaidaSubida = 12, -- (studs/s) ...e mais este tanto para cima. Soltar SUBINDO e rápido = PERFEITO! (Nunca passa de VelocidadeMaximaTotal.)
	GanchoVooEmbaloTempo = 2.5, -- (s) Depois do pouso, os motores NÃO cortam a velocidade extra de uma vez: ela cai aos poucos neste tempo.
	GanchoVooMesmoPonto = 0.75, -- (s) Soltou de um ponto? O MESMO ponto só pega de novo depois disso (os outros pegam na hora).
	GanchoSegurarBalancaSemTag = false, -- true = o SEGURAR em superfície SEM a tag também balança (o jeito antigo: lento e com recarga).
```

## PASSO 2 — `StarterPlayer › StarterPlayerScripts › QuadricicloCliente › Gancho`

**2.1** Lá no começo, logo depois da linha `local embaloAte = 0 -- ...e até quando (os.clock). Vai caindo até 0.`, adicione:
```lua
-- (NOVO v3) PÊNDULO DE FÍSICA do gancho de voo
local rumoDoVoo = Vector3.new(0, 0, -1) -- para onde o carro está virado no voo (A/D giram)
local penduradoNoVoo = false -- true = no último frame o carro estava pendurado (no ar) num ponto de voo
local controleNoArAte = 0 -- (os.clock) até quando vale o controle no ar depois de soltar de um ponto de voo
```

**2.2** Logo **antes** do comentário `-- ESTILINGUE: o gancho de IMPULSO estava preso? ...` (que fica em cima da função `estilingue`), cole o bloco novo inteiro:
```lua
-- =====================================================================
-- (NOVO v3) GANCHO DE VOO = PÊNDULO DE FÍSICA
-- =====================================================================
-- Quem move o carro pendurado é a FÍSICA do Roblox: a corda de verdade (RopeConstraint), a gravidade e o
-- embalo. Nada de "trilho". O script só ajuda em 4 coisas:
--   1. LANÇAMENTO: quando a corda trava, o carro ganha velocidade para a FRENTE (uma vez por gancho).
--   2. CARRETEL: a corda encurta até GanchoVooCordaMaxima (não afunda no buraco e gira mais rápido).
--   3. CONTROLE: W/S empurram para a frente/trás do carro; A/D viram o carro e empurram de lado.
--   4. POSTURA: um "endireitador" macio deixa o carro de pé e virado para o rumo, sem ficar duro.
-- Depois de soltar, o CONTROLE NO AR continua até as rodas tocarem o chão.

-- A direção "deitada" (só na horizontal) de um vetor, ou nil se ele for quase vertical.
local function deitado(vetor: Vector3): Vector3?
	local plano = Vector3.new(vetor.X, 0, vetor.Z)
	return if plano.Magnitude > 0.01 then plano.Unit else nil
end

-- A/D giram o rumo do carro no ar (D = direita).
local function virarRumo(quad: Quadriciclo, volante: number, dt: number)
	local graus = numeroDaConfig(quad.Config.GanchoVooVirar, 120)
	rumoDoVoo = CFrame.Angles(0, -volante * math.rad(graus) * dt, 0):VectorToWorldSpace(rumoDoVoo)
end

-- A força das teclas no ar (W/S para a frente/trás do carro, A/D de lado) e a "leveza" (menos gravidade).
-- É uma força de verdade (VectorForce): a física soma com a corda e com a gravidade.
local function empurrarNoAr(quad: Quadriciclo, pedal: number, volante: number, aceleracao: number)
	local direita = rumoDoVoo:Cross(Vector3.yAxis)
	local desejo = rumoDoVoo * pedal + direita * volante * 0.6
	local velocidade = quad.chassi.AssemblyLinearVelocity
	if velocidade:Dot(desejo) > 0 and velocidade.Magnitude > numeroDaConfig(quad.Config.GanchoVooVelocidadeMaxima, 120) then
		desejo = Vector3.zero -- já está no máximo: as teclas não aceleram mais (frear ainda vale)
	end
	local leveza = math.clamp(numeroDaConfig(quad.Config.GanchoVooLeveza, 0.25), 0, 0.9)
	local forca = pegarForcaImpulso(quad) -- (a mesma força do gancho de IMPULSO: o atualizarImpulso desliga a cada frame)
	forca.Force = (desejo * aceleracao + Vector3.yAxis * workspace.Gravity * leveza) * massaTotal(quad)
	forca.Enabled = true
end

-- A POSTURA: de pé ("cima"), virado para o rumo e deitando um pouco para o lado da curva. É macia
-- (GanchoVooGiroSuave): o carro balança e reage à física, só não sai capotando.
local function posturaNoVoo(quad: Quadriciclo, cima: Vector3, volante: number)
	local Config = quad.Config
	local frente = rumoDoVoo - cima * rumoDoVoo:Dot(cima)
	if frente.Magnitude < 0.01 then
		return
	end
	local inclinar = math.rad(numeroDaConfig(Config.GanchoVooInclinarCurva, 20))
	local giro = pegarAlinharPouso(quad)
	giro.CFrame = CFrame.lookAt(Vector3.zero, frente.Unit, cima) * CFrame.Angles(0, 0, -volante * inclinar)
	giro.Responsiveness = numeroDaConfig(Config.GanchoVooGiroSuave, 8)
	giro.Enabled = true
end

-- Preso num ponto de voo (o atualizarImpulso chama a cada frame).
local function voarNoPendulo(quad: Quadriciclo, pedal: number, volante: number, dt: number, corda: RopeConstraint, noChao: boolean)
	local a0, a1 = corda.Attachment0, corda.Attachment1
	if a0 == nil or a1 == nil then
		return
	end
	local Config = quad.Config
	controleNoArAte = 0 -- (pendurado, quem manda é o pêndulo; o controle "solto" volta quando você soltar)
	-- 1) LANÇAMENTO (uma vez por gancho): para a FRENTE, para onde você estava indo, aproveitando a velocidade
	--    com que chegou (devagar = ganha o mínimo). A parte de subir/cair continua a mesma: a corda segura.
	if impulsoDoVooPendente then
		impulsoDoVooPendente = false
		local velocidade = quad.chassi.AssemblyLinearVelocity
		local horizontal = Vector3.new(velocidade.X, 0, velocidade.Z)
		local frente: Vector3 = if horizontal.Magnitude > 5
			then horizontal.Unit
			else (deitado(Veiculo.referencia(quad).LookVector) or Vector3.new(0, 0, -1))
		local minima = numeroDaConfig(Config.GanchoVooVelocidadeMinima, 60)
		local maxima = math.max(numeroDaConfig(Config.GanchoVooVelocidadeMaxima, 120), minima)
		local rapidez = math.clamp(
			horizontal.Magnitude * numeroDaConfig(Config.GanchoVooAproveitamento, 0.85) + numeroDaConfig(Config.GanchoVooImpulso, 12),
			minima,
			maxima
		)
		local subir = if noChao then numeroDaConfig(Config.GanchoVooDecolar, 25) else 0
		local lancamento = frente * rapidez + Vector3.yAxis * (velocidade.Y + subir)
		for _, parte in quad.pecasFisicas do
			parte.AssemblyLinearVelocity = lancamento -- todas as peças juntas: o carro sai inteiro
		end
		rumoDoVoo = frente
		CameraModulo.tremer(0.1) -- um tranco na tela: "fui lançado!"
	end
	-- 2) CARRETEL: a corda de verdade encurta até GanchoVooCordaMaxima. Quando ela está esticada, a física puxa o
	--    carro para o ponto e, como num pêndulo de verdade, corda mais curta = gira mais rápido.
	local alvo = math.max(numeroDaConfig(Config.GanchoVooCordaMaxima, 35), 8)
	if corda.Length > alvo then
		corda.Length = math.max(alvo, corda.Length - numeroDaConfig(Config.GanchoVooRecolher, 120) * dt)
	end
	if noChao then
		return -- no chão, quem manda são as rodas (o lançamento acima já tira você do chão)
	end
	penduradoNoVoo = true
	-- 3) CONTROLE: A/D viram o carro; W/S/A/D empurram (força de verdade, somada à corda e à gravidade).
	virarRumo(quad, volante, dt)
	empurrarNoAr(quad, pedal, volante, numeroDaConfig(Config.GanchoVooControle, 70))
	-- 4) POSTURA: de pé, inclinando um pouco para o lado da corda, como quem está num balanço.
	local paraCorda = (a1.WorldPosition - a0.WorldPosition).Unit
	local cima = Vector3.yAxis:Lerp(paraCorda, math.clamp(numeroDaConfig(Config.GanchoVooBalancarCorpo, 0.3), 0, 0.45)).Unit
	posturaNoVoo(quad, cima, volante)
end

-- Soltou de um ponto de voo (clique, L1 ou o combo). A física já leva o carro com a velocidade do pêndulo: aqui
-- só entra um empurrão extra, o PERFEITO (soltar subindo e rápido), o embalo do pouso e o controle no ar.
local function soltarDoVoo(quad: Quadriciclo)
	penduradoNoVoo = false
	local Config = quad.Config
	local corda = cordaDoGancho(quad)
	if corda then
		corda.Enabled = false -- solta AQUI, na hora (o Servidor apaga a corda logo depois)
	end
	local velocidade = quad.chassi.AssemblyLinearVelocity
	local bonus = numeroDaConfig(Config.GanchoVooSaidaBonus, 1.1)
	local subida = numeroDaConfig(Config.GanchoVooSaidaSubida, 12)
	local maxima = numeroDaConfig(Config.GanchoVooVelocidadeMaxima, 120)
	if velocidade.Y > 0 and velocidade.Magnitude >= maxima * numeroDaConfig(Config.BalancoPerfeito, 0.7) then
		bonus *= numeroDaConfig(Config.BalancoBonusPerfeito, 1.3) -- PERFEITO: soltou subindo e rápido
		subida += numeroDaConfig(Config.BalancoPuloPerfeito, 18)
		comemorarPerfeito(quad)
	end
	velocidade = velocidade * bonus + Vector3.yAxis * subida
	local limite = numeroDaConfig(Config.VelocidadeMaximaTotal, 130)
	if velocidade.Magnitude > limite then
		velocidade = velocidade.Unit * limite
	end
	for _, parte in quad.pecasFisicas do
		parte.AssemblyLinearVelocity = velocidade
	end
	embaloNoPouso = true -- (o embalo começa quando as rodas tocarem o chão)
	controleNoArAte = os.clock() + numeroDaConfig(Config.GanchoVooControleNoArTempo, 4)
end

-- Depois de soltar de um ponto de voo: no ar, W/S/A/D continuam valendo até as rodas tocarem o chão.
local function controlarNoAr(quad: Quadriciclo, pedal: number, volante: number, dt: number, noChao: boolean)
	if controleNoArAte == 0 then
		return
	end
	if noChao or os.clock() > controleNoArAte then
		controleNoArAte = 0 -- pousou (ou passou do tempo): o carro volta a ser carro
		return
	end
	virarRumo(quad, volante, dt)
	empurrarNoAr(quad, pedal, volante, numeroDaConfig(quad.Config.GanchoVooControleNoAr, 35))
	posturaNoVoo(quad, Vector3.yAxis, volante)
end

```

**2.3** Logo **depois** da linha `local function estilingue(quad: Quadriciclo)` (a primeira linha da função), adicione:
```lua
	if penduradoNoVoo then -- (NOVO v3) pendurado num ponto de voo: solta do jeito do voo (física)
		soltarDoVoo(quad)
		return
	end
```

**2.4** Na `Gancho.atualizarImpulso`, localize o bloco do SEGURAR que você colou no guia 1:
```lua
	-- SEGURAR pendurado (rodas fora do chão e sem estar escalando parede): balança.
	-- (NOVO) Só num ponto de VOO (tag "Voar_Gancho"). Fora deles o SEGURAR só segura (corda e escalada),
	-- a não ser que GanchoSegurarBalancaSemTag = true na Configuracao.
	if enviadoEm ~= nil and tipoAtivo == "Segurar" and corda ~= nil and corda.Enabled
		and tempoNoAr >= TEMPO_NO_AR and not escalando
		and (pontoVooAtivo ~= nil or Config.GanchoSegurarBalancaSemTag == true)
	then
		balancar(quad, pedal, volante or 0, dt, corda)
	end
```
e troque por:
```lua
	-- (NOVO v3) GANCHO DE VOO: preso num ponto de voo = PÊNDULO DE FÍSICA (no chão, o lançamento tira você do
	-- chão). Sem gancho, depois de soltar de um ponto de voo, vale o CONTROLE NO AR até pousar.
	penduradoNoVoo = false
	if enviadoEm ~= nil and tipoAtivo == "Segurar" and pontoVooAtivo ~= nil and corda ~= nil and corda.Enabled then
		voarNoPendulo(quad, pedal, volante or 0, dt, corda, noChao)
	else
		controlarNoAr(quad, pedal, volante or 0, dt, noChao)
	end
	-- SEGURAR pendurado FORA dos pontos de voo: só balança (do jeito antigo) se GanchoSegurarBalancaSemTag = true.
	if enviadoEm ~= nil and tipoAtivo == "Segurar" and pontoVooAtivo == nil and corda ~= nil and corda.Enabled
		and tempoNoAr >= TEMPO_NO_AR and not escalando and Config.GanchoSegurarBalancaSemTag == true
	then
		balancar(quad, pedal, volante or 0, dt, corda)
	end
```

**2.5** Na `apagarImpulso`, logo depois da linha `pousoAte = 0`, adicione:
```lua
	controleNoArAte = 0 -- (NOVO v3) saiu do banco: acaba o voo e o controle no ar
	penduradoNoVoo = false -- (NOVO v3)
```

## PASSO 3 (só se você usa o caminhão monstro) — `QuadricicloCliente › Monstro`
Na `Monstro.atualizar`, logo depois destas 2 linhas:
```lua
	local puxador = chassi:FindFirstChild("BalancoGancho")
	local pendurado = puxador ~= nil and puxador:IsA("AlignPosition") and puxador.Enabled
```
adicione:
```lua
	-- (NOVO v3) ...ou voando no gancho de voo (a força "ImpulsoGancho" ligada): aí quem manda no ar é o voo
	local forcaDoGancho = chassi:FindFirstChild("ImpulsoGancho")
	if forcaDoGancho and forcaDoGancho:IsA("VectorForce") and forcaDoGancho.Enabled then
		pendurado = true
	end
```
*Por quê:* sem isso, as teclas de "mortal no ar" do monstro brigam com o controle do voo.

---

**Sobre o código antigo do voo:** a `impulsoDoVoo` e os trechos `if estado.voo then` da `balancar`/`comecarBalanco` (dos guias 1 e 2) ficam sem uso agora. Pode deixar: não atrapalham. Os valores `GanchoVooGravidade`, `GanchoVooAmortecimento` e `GanchoVooAlturaLimite` também saíram da configuração por isso.

## Ajustes rápidos
| Se... | Mude |
|---|---|
| quer voar mais longe / mais "flutuante" | `GanchoVooLeveza` 0.25 → 0.35 |
| quer mais peso e velocidade na descida | `GanchoVooLeveza` 0.25 → 0.1 |
| as teclas mexem pouco no ar | `GanchoVooControle` 70 → 100 · `GanchoVooControleNoAr` 35 → 50 |
| vira devagar demais | `GanchoVooVirar` 120 → 180 |
| o carro balança e gira demais | `GanchoVooGiroSuave` 8 → 12 |
| o carro está firme demais | `GanchoVooGiroSuave` 8 → 5 · `GanchoVooBalancarCorpo` 0.3 → 0.4 |
| o lançamento está fraco | `GanchoVooVelocidadeMinima` 60 → 75 · `GanchoVooImpulso` 12 → 20 |
| ainda afunda no buraco | `GanchoVooCordaMaxima` 35 → 30 · `GanchoVooRecolher` 120 → 160 |

## Testes
1. **Do chão:** mire num ponto à frente e acima (30+ studs). O carro tem que ser lançado para a frente e para cima e balançar sozinho, sem ficar parado embaixo do poste.
2. **Pendurado:** segure W no ponto mais baixo do balanço e o balanço tem que crescer. A/D viram o carro e ele deita na curva.
3. **Soltar subindo:** ele sai voando. No ar, A/D ainda viram e W/S ainda empurram, até pousar.
4. **Combo:** preso no 1º, segure o direito no 2º e clique o esquerdo. Repita até atravessar.
5. **Pouso:** a velocidade cai aos poucos (embalo) e o carro volta a ser dirigido normalmente.
