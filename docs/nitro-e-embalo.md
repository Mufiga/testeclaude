# Nitro e embalo: velocidade que dura

São 5 mudanças: 3 na `ConfiguracaoPadrao` e 2 no `QuadricicloCliente`. Tudo foi aplicado numa cópia dos seus
scripts e passou no verificador de tipos do Luau (`--!strict`, com a API do Roblox): 0 erros, 0 avisos.

## O que o vídeo mostrou (li o velocímetro quadro a quadro)
| Momento | Velocímetro | O que é |
|---|---|---|
| 0,0–0,7 s (nitro ligado) | 48, 48, 48 | o nitro **trava em 48**: soma só 8 studs/s à máxima de 40 |
| 1,0–2,3 s | 54 → 110 | é o **gancho IMPULSO** (o ícone 1 entra em recarga logo depois), não o nitro |
| 2,3–5,0 s | 110 → 99 → 87 → 75 → 65 → 51 → 40 | cai **~35 studs/s a cada segundo**: parece freio |
| 12,7–14,0 s (nitro ligado de novo) | 47, 48, 48, 49 | de novo travado em 48 |
| 15,3–18,0 s | 113 → 89 → 67 → 46 → 40 | a mesma queda rápida |

## Por que
1. **`NitroSpeedBonus = 8`:** o nitro só leva de 40 para 48. Os efeitos de velocidade da câmera só começam a 60 (`EfeitoVelocidadeInicio`), então com o nitro eles nunca aparecem.
2. **Segurando W acima da máxima, o carro freia.** No `atualizar`, quando você está mais rápido que a máxima de agora, o alvo dos motores volta para a máxima a `Acceleration` (35 studs/s²). Os motores viram freio. Segurando W ele perde velocidade **mais rápido** do que soltando o acelerador (que perde só 8). Isso vale depois do nitro, do gancho, do boost pad e da descida.

## Como fica
- O nitro leva de 40 para **70** (aí a câmera já mostra a velocidade) e dá um **coice** de 10 studs/s quando liga.
- Acima da máxima, o carro perde no máximo **15 studs/s por segundo**, sem freio (`EmbaloPerda`).

Simulando (velocidade a cada 0,5 s, segurando W):

| | Hoje | Novo |
|---|---|---|
| Nitro (2,5 s de tanque) | 48, 48, 48, 48, 48, **40** | 68, 70, 70, 70, 70, 64, 56, 49, 41 |
| Depois do gancho a 110 | 95, 77, 60, 42, **40** | 103, 96, 88, 81, 73, 66, 58, 51, 43, 40 |

---

## PASSO 1 — `ReplicatedStorage › Compartilhado › ConfiguracaoPadrao`
**1.1** Logo depois da linha `CoastDeceleration = 8, -- "Freio motor" quando você solta o acelerador (studs/s²).`, adicione:
```lua
	EmbaloPerda = 15, -- (studs/s²) (NOVO) Acima da velocidade máxima (depois do nitro, do gancho, de um boost pad...), segurando W ele perde só isso por segundo. Menor = o embalo dura mais.
```

**1.2** Troque a linha `NitroSpeedBonus = 8, -- Velocidade extra no nitro (studs/s).` por:
```lua
	NitroSpeedBonus = 30, -- (NOVO: era 8) Velocidade extra no nitro (studs/s). 30 = de 40 para 70, e aí a câmera já mostra a sensação de velocidade.
```

**1.3** Logo depois da linha `NitroEmpinar = 1.5, -- (rad/s) ...e a frente sobe...`, adicione:
```lua
	NitroEmpurrao = 10, -- (studs/s) (NOVO) Ao LIGAR o nitro, o carro ganha este tanto para a frente na hora (o "coice"). 0 = sem coice.
```

> Se a `Configuracao` do seu quadriciclo (`Quadriciclo › Scripts › Configuracao`) tiver o seu próprio `NitroSpeedBonus`, mude lá também: o valor do veículo vale mais que o padrão.

## PASSO 2 — `StarterPlayer › StarterPlayerScripts › QuadricicloCliente` (LocalScript)
**2.1** Na função `pancadaDoNitro`, logo depois da linha `quad.chassi.AssemblyAngularVelocity += referencia.RightVector * empinar -- a frente sobe, a traseira senta`, adicione:
```lua
	-- (NOVO) O COICE: o carro inteiro ganha Config.NitroEmpurrao studs/s para a frente no instante em que o nitro liga.
	local empurrao = if typeof(Config.NitroEmpurrao) == "number" then Config.NitroEmpurrao else 10
	for _, parte in quad.pecasFisicas do
		parte.AssemblyLinearVelocity += referencia.LookVector * empurrao
	end
```

**2.2** Na função `atualizar`, logo depois do bloco do EMBALO DO GANCHO DE VOO (o que termina com estas 3 linhas):
```lua
		desejada = math.max(desejada, math.min(velocidadeFrente, maximaAgora + extraDoVoo))
		ritmo = math.max(ritmo, Config.Acceleration * 2)
	end
```
adicione:
```lua
	-- (NOVO) EMBALO: passou da velocidade máxima de agora (o nitro acabou, saiu de um boost pad, do gancho, de uma
	-- descida...)? Os motores NÃO freiam mais: o carro perde a velocidade extra aos poucos, no máximo
	-- Config.EmbaloPerda studs/s a cada segundo. (Antes, segurando W, ele "freava" a 35 studs/s² até voltar à máxima.)
	if velocidadeFrente > math.max(desejada, maximaAgora) + 0.5 and pedal > -ZONA_MORTA and not freando then
		ritmo = math.min(ritmo, if typeof(Config.EmbaloPerda) == "number" then Config.EmbaloPerda else 15)
	end
```

---

## Ajustes rápidos
| Se... | Mude |
|---|---|
| o embalo acaba rápido demais | `EmbaloPerda` 15 → 10 |
| o carro fica rápido tempo demais | `EmbaloPerda` 15 → 25 |
| quer o nitro ainda mais rápido | `NitroSpeedBonus` 30 → 45 (o teto continua sendo `VelocidadeMaximaTotal` = 130) |
| quer um coice mais forte (ou nenhum) | `NitroEmpurrao` 10 → 18 (ou 0) |
| quer o nitro durando mais | `NitroDuration` 2.5 → 3.5 |
| quer a sensação de velocidade mais cedo | `EfeitoVelocidadeInicio` 60 → 50 |

## Testes
1. Na reta, segure Shift: o velocímetro tem que subir para ~70 e a câmera abrir (riscos na borda da tela).
2. Quando o tanque acabar, continue segurando W: a velocidade cai devagar (70 → 40 em ~2 s), sem o carro "frear".
3. Use o gancho IMPULSO e, depois de soltar, segure W: a velocidade cai aos poucos (~110 → 40 em ~5 s).
4. Aperte S depois do nitro: aí sim ele freia forte (o freio continua igual).
