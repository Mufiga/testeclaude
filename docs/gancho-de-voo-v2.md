# Gancho de voo · atualização 2: pêndulo de verdade, corda curta, carro solto

Aplique **por cima** do que você já fez (guia 1 + a correção do 3.14/3.15). São 13 mudanças em 3 scripts. Tudo foi
aplicado numa cópia dos seus scripts e passou no verificador de tipos do Luau (`--!strict`, com a API do
Roblox): 0 erros, 0 avisos.

## O que o vídeo novo mostrou
- **0–2 s:** você prende o 1º ponto **logo embaixo dele** (corda de ~15–20 studs) e sai da beirada. Um pêndulo tão curto, recebendo 60+ studs/s, gira muito rápido, bate no penhasco e para seco no alto (o limite de altura cortava a subida de uma vez). Por isso parece "travado".
- **0–10 s:** o carro gira para os lados quando você aperta A/D. No balanço, as teclas viravam o carro inteiro na direção da câmera, com um "endireitador" forte (Responsiveness 14). Por isso ele fica "duro ao virar".
- **9,5 s:** o combo pegou o 2º ponto colado nele (corda curtíssima): o carro capota em volta do poste.
- **13–15 s:** você mira o 3º ponto de longe. A mira fica vermelha (ele estava a mais de 100 studs, o alcance do SEGURAR) e, quando pega, a corda nasce **enorme**. Um pêndulo de corda longa desce quase o tamanho da corda antes de subir: simulando um ponto a 130 studs, o carro afunda **67 studs**, e é assim que ele cai no buraco.

## O que muda
| Pedido | Como ficou |
|---|---|
| Voo baseado em pêndulo | Continua sendo um pêndulo de verdade: gravidade puxando, a corda segurando, e **a corda encurtando faz girar mais rápido** (como um patinador que fecha os braços). Lá no alto ele freia suave, não para seco. |
| Pelo menos 30 studs | O ponto de voo só pega entre **30 e 150 studs** (`GanchoVooDistanciaMinima` / `GanchoVooAlcance`) e **acima do carro**. Fora disso, a mira fica vermelha. |
| Corda enorme / cai no buraco | A corda é recolhida até **35 studs** a **140 studs/s**. No caso do ponto a 130 studs, o carro afunda 24 studs em vez de 67 e já pode soltar com 1,1 s (antes, 1,9 s). |
| Impulso para a frente | O lançamento agora vai sempre **para a frente** (para onde você estava indo), e o recolhimento da corda soma velocidade. |
| Carro duro ao voar e virar | No voo, A/D e W/S **empurram o pêndulo, mas não giram o carro**. Ele fica virado para onde foi lançado, e o endireitador fica bem mais solto (`GanchoVooGiroSuave` = 5, antes 14), também depois de soltar. |
| Combo sem soltar antes | Já existia: preso no 1º, **segure o botão direito** no 2º (mira azul) e **clique o esquerdo**. Ele solta o 1º com impulso e lança no 2º no mesmo clique. Agora alcança até 150 studs e não deixa pegar um ponto colado (menos de 30). |

---

## PASSO 1 — `ReplicatedStorage › Compartilhado › ConfiguracaoPadrao`
Apague o bloco inteiro do gancho de voo que você colou (da linha `-- ---------- (NOVO) GANCHO DE VOO ...` até a linha `GanchoSegurarBalancaSemTag = false, ...`) e cole este no lugar:
```lua
	-- ---------- (NOVO) GANCHO DE VOO: o SEGURAR (gancho 2) num Model com a tag "Voar_Gancho" ----------
	-- Acertou um ponto de voo: o veículo vira um PÊNDULO pendurado no ponto e é lançado para a frente, SEM
	-- RECARGA (dá para emendar vários pontos). Em qualquer outra coisa, o SEGURAR continua igual.
	GanchoVooDistanciaMinima = 30, -- (studs) O ponto de voo só pega se estiver PELO MENOS a esta distância (mais perto = mira vermelha).
	GanchoVooAlcance = 150, -- (studs) ...e no máximo a esta. (O SEGURAR normal continua usando o GanchoAlcanceSegurar.)
	GanchoVooAlturaMinima = 0, -- (studs) O ponto precisa estar pelo menos isso ACIMA do veículo (pendurar num ponto baixo joga você no buraco).
	GanchoVooCordaMaxima = 35, -- (studs) O tamanho do pêndulo. Pegou de longe? A corda é recolhida até aqui...
	GanchoVooRecolher = 140, -- (studs/s) ...nesta velocidade. Rápido = um puxão para a frente, sem afundar no buraco.
	GanchoVooAproveitamento = 0.85, -- Quanto da velocidade de CHEGADA vira velocidade do voo (0.85 = 85%).
	GanchoVooImpulso = 12, -- (studs/s) Empurrão para a FRENTE que todo acerto num ponto de voo dá, somado à conta de cima.
	GanchoVooVelocidadeMinima = 60, -- (studs/s) Chegou devagar? O voo começa com pelo menos isso.
	GanchoVooVelocidadeMaxima = 120, -- (studs/s) O pêndulo do voo nunca passa disso.
	GanchoVooGravidade = 120, -- (studs/s²) A "gravidade" do pêndulo. Maior = desce mais rápido e ganha mais velocidade.
	GanchoVooAmortecimento = 0.05, -- (por segundo) Quanto o voo perde de velocidade sozinho (0 = nada).
	GanchoVooAlturaLimite = 0.3, -- O mais alto que ele sobe: 0 = na altura do ponto · 0.3 = um pouco acima (lá em cima ele freia suave).
	GanchoVooGiroSuave = 5, -- Quão FIRME o carro é virado no voo e logo depois de soltar (o balanço normal usa 14 · menor = mais solto).
	GanchoVooSaidaBonus = 1.1, -- Ao SOLTAR do ponto de voo: sai com 10% a mais da velocidade do pêndulo...
	GanchoVooSaidaSubida = 12, -- (studs/s) ...e mais este tanto para cima. (Nunca passa de VelocidadeMaximaTotal.)
	GanchoVooEmbaloTempo = 2.5, -- (s) Depois do pouso, os motores NÃO cortam a velocidade extra de uma vez: ela cai aos poucos neste tempo.
	GanchoVooMesmoPonto = 0.75, -- (s) Soltou de um ponto? O MESMO ponto só pega de novo depois disso (os outros pegam na hora).
	GanchoSegurarBalancaSemTag = false, -- true = o SEGURAR em superfície SEM a tag também balança (o jeito antigo: lento e com recarga).
```

## PASSO 2 — `ServerScriptService › QuadricicloServidor › Gancho` (servidor)
Os dois trechos ficam dentro da `Gancho.aoLigar`.

**2.1** Troque a linha `local alcanceMaximo = alcanceDoTipo(v.Config, tipo) + 15 + v.chassi.AssemblyLinearVelocity.Magnitude * 0.5` por:
```lua
	local alcanceMaximo = (if voo then v.Config.GanchoVooAlcance else alcanceDoTipo(v.Config, tipo)) + 15 + v.chassi.AssemblyLinearVelocity.Magnitude * 0.5 -- (NOVO: nos pontos de voo, GanchoVooAlcance)
```

**2.2** Localize:
```lua
	if (referencia - v.chassi.Position).Magnitude > alcanceMaximo then
		return
	end
```
e troque por:
```lua
	local distanciaAoAlvo = (referencia - v.chassi.Position).Magnitude -- (NOVO)
	if distanciaAoAlvo > alcanceMaximo or (voo and distanciaAoAlvo < v.Config.GanchoVooDistanciaMinima - 10) then
		return -- longe demais (ou, no voo, perto demais: o mínimo tem 10 studs de folga por causa do atraso da internet)
	end
```

## PASSO 3 — `StarterPlayer › StarterPlayerScripts › QuadricicloCliente › Gancho` (cliente)

**3.1** Na função `alcanceDoTipo` (lá no começo do script), localize:
```lua
	if id == "Segurar" and typeof(Config.GanchoAlcanceSegurar) == "number" then
		return Config.GanchoAlcanceSegurar
	end
```
e troque por:
```lua
	if id == "Segurar" and typeof(Config.GanchoAlcanceSegurar) == "number" then
		-- (NOVO) a mira do SEGURAR enxerga até o alcance dos pontos de VOO (a alvoValido confere cada caso)
		return math.max(Config.GanchoAlcanceSegurar, tonumber(Config.GanchoVooAlcance) or 0)
	end
```

**3.2** Na `alvoValido`, localize o bloco que você colou no guia 1:
```lua
	-- (NOVO) Acabou de soltar DESTE ponto de voo? Ele espera um pouquinho (evita repetir sem querer).
	local ponto = pontoDeVooNaMira(acerto)
	if ponto and ponto == ultimoPontoVoo and os.clock() - soltouVooEm < (tonumber(quad.Config.GanchoVooMesmoPonto) or 0.75) then
		return false
	end
```
e troque por:
```lua
	-- (NOVO) GANCHO DE VOO: o ponto precisa estar entre GanchoVooDistanciaMinima e GanchoVooAlcance de distância
	-- e ACIMA do veículo (é um pêndulo: pendurar num ponto baixo joga você no buraco). O mesmo ponto de onde
	-- você acabou de soltar espera um pouquinho (evita repetir sem querer).
	local Config = quad.Config
	local distancia = (acerto.Position - quad.chassi.Position).Magnitude
	local ponto = pontoDeVooNaMira(acerto)
	if ponto then
		if distancia < (tonumber(Config.GanchoVooDistanciaMinima) or 30)
			or distancia > (tonumber(Config.GanchoVooAlcance) or 150)
			or acerto.Position.Y - quad.chassi.Position.Y < (tonumber(Config.GanchoVooAlturaMinima) or 0)
			or (ponto == ultimoPontoVoo and os.clock() - soltouVooEm < (tonumber(Config.GanchoVooMesmoPonto) or 0.75))
		then
			return false
		end
	elseif tipoSelecionado == "Segurar" and distancia > (tonumber(Config.GanchoAlcanceSegurar) or 100) then
		return false -- (o alcance maior é só para os pontos de voo)
	end
```

**3.3** Na `impulsoDoVoo`, localize:
```lua
	-- Para onde: para onde você já ia ("de lado" para a corda: é o único jeito de um balanço andar).
	-- Quase parado, ou caindo bem na direção da corda? Para a frente do veículo.
	local rumo = deLado
	if rumo.Magnitude < 2 then
		local frente = Veiculo.referencia(quad).LookVector
		rumo = frente - corda * frente:Dot(corda)
	end
```
e troque por:
```lua
	-- (NOVO) Para onde: PARA A FRENTE, para onde você estava indo na horizontal (quase parado: a frente do
	-- carro). Sempre "de lado" para a corda: é o único jeito de um pêndulo andar.
	local horizontal = Vector3.new(chegada.X, 0, chegada.Z)
	local frente = if horizontal.Magnitude > 5 then horizontal.Unit else Veiculo.referencia(quad).LookVector
	local rumo = frente - corda * frente:Dot(corda)
```
(A linha de baixo, `if rumo.Magnitude < 0.01 then`, continua igual.)

**3.4** Na `comecarBalanco`, localize:
```lua
	local referencia = Veiculo.referencia(quad)
	local frente = Vector3.new(referencia.LookVector.X, 0, referencia.LookVector.Z)
```
e troque por:
```lua
	local referencia = Veiculo.referencia(quad)
	local frente = Vector3.new(referencia.LookVector.X, 0, referencia.LookVector.Z)
	local rumoDoVoo = Vector3.new(velocidade.X, 0, velocidade.Z)
	if voo and rumoDoVoo.Magnitude > 5 then
		frente = rumoDoVoo -- (NOVO) no voo, ele começa virado para onde foi lançado
	end
```

**3.5** Na `balancar`, dentro do bloco `if estado.voo then` que você colou no guia 1, localize:
```lua
		-- CARRETEL: pegou de longe? A corda encurta até GanchoVooCordaMaxima (freando nos últimos 4 studs).
		local falta = estado.comprimento - numeroDaConfig(Config.GanchoVooCordaMaxima, 45)
		if falta > 0 then
			local recolher = numeroDaConfig(Config.GanchoVooRecolher, 40)
			estado.comprimento -= math.min(falta, recolher * math.clamp(falta / 4, 0.25, 1) * dt)
		end
```
e troque por:
```lua
		-- CARRETEL: pegou de longe? A corda encurta RÁPIDO até GanchoVooCordaMaxima (freando nos últimos studs).
		-- (NOVO) Como num pêndulo de verdade, corda encurtando = gira mais rápido: é o puxão para a frente.
		local falta = estado.comprimento - math.max(numeroDaConfig(Config.GanchoVooCordaMaxima, 35), 8)
		if falta > 0 then
			local recolher = numeroDaConfig(Config.GanchoVooRecolher, 140)
			local antes = estado.comprimento
			estado.comprimento -= math.min(falta, recolher * math.clamp(falta / 6, 0.25, 1) * dt)
			estado.velocidade *= antes / estado.comprimento
		end
```

**3.6** Ainda na `balancar`, troque a linha `velocidade -= subir * subindo` (fica dentro do `if u.Y > alturaLimite then`) por:
```lua
				velocidade -= subir * subindo * (if estado.voo then math.min(dt * 6, 1) else 1) -- (NOVO) no voo, freia suave lá no alto (antes parava seco)
```

**3.7** Ainda na `balancar`, troque a linha `if mistura.Magnitude > 0.01 then` (logo abaixo de `local mistura = estado.frente:Lerp(...)`) por:
```lua
			if mistura.Magnitude > 0.01 and not estado.voo then -- (NOVO) no voo, as teclas empurram o pêndulo mas não giram o carro
```

**3.8** Ainda na `balancar`, troque a linha que começa com `giro.Responsiveness = 14` por:
```lua
		giro.Responsiveness = if estado.voo then numeroDaConfig(Config.GanchoVooGiroSuave, 5) else 14 -- (NOVO) no voo, mais solto
```

**3.9** Na `estilingue`, logo depois da linha `local doBalanco = balanco`, adicione:
```lua
	local saiuDoVoo = doBalanco ~= nil and doBalanco.voo -- (NOVO)
```
E, no fim da mesma função, localize:
```lua
	alinhar.CFrame = direcaoDoPouso(quad)
	alinhar.Enabled = true
```
e troque por:
```lua
	alinhar.CFrame = direcaoDoPouso(quad)
	alinhar.Responsiveness = if saiuDoVoo then numeroDaConfig(Config.GanchoVooGiroSuave, 5) else 12 -- (NOVO) depois do voo, endireita sem tranco
	alinhar.Enabled = true
```

---

## Como montar os pontos (importante)
- Coloque a tag `Voar_Gancho` só no **gancho**, não na base. Se a base estiver no mesmo Model, acertar a base também conta como ponto de voo, e você fica pendurado embaixo de um ponto baixo. Faça um Model pequeno só com o gancho e ponha a tag nele.
- Ponha os pontos **bem acima** do caminho: no mínimo uns 35–40 studs acima do fundo do buraco (é o tamanho do pêndulo).
- Distância entre pontos: de 40 a 120 studs. Lembre que cada ponto só pega a partir de 30 studs de distância.

## Ajustes rápidos
| Se... | Mude |
|---|---|
| ainda afunda demais | `GanchoVooCordaMaxima` 35 → 30, ou `GanchoVooRecolher` 140 → 180 |
| o pêndulo está rápido demais | `GanchoVooGravidade` 120 → 100 |
| o carro ainda está duro | `GanchoVooGiroSuave` 5 → 3 |
| o carro está mole demais (gira à toa) | `GanchoVooGiroSuave` 5 → 8 |
| o impulso para a frente está fraco | `GanchoVooImpulso` 12 → 20, ou `GanchoVooVelocidadeMinima` 60 → 70 |
| o gancho demora a chegar no 2º ponto | `GanchoVelocidadeVoo` 220 → 320 (vale para todos os ganchos) |

## Testes
1. Fique a menos de 30 studs de um ponto: a mira tem que ficar **vermelha**. Afaste-se: fica **azul**.
2. Pegue um ponto de longe (100+ studs): a corda tem que **encurtar rápido**, puxando você para a frente, sem afundar no buraco.
3. No ar, aperte A/D: o pêndulo vai para o lado, mas o carro **não gira** de uma vez.
4. Combo: preso no 1º, segure o direito no 2º e clique o esquerdo. Repita até atravessar.
5. Solte subindo: ele é lançado para a frente e, no ar, endireita devagar (sem tranco).
