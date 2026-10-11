--=====================================================================
-- Testes (rodam DEPOIS do script servidor, enxergando os locals dele)
--=====================================================================
local pass, fail = 0, 0
local function check(label, cond, extra)
	if cond then
		pass += 1
		print("  ok   " .. label)
	else
		fail += 1
		print("  FALHA " .. label .. (extra and ("  -> " .. tostring(extra)) or ""))
	end
end

print("\n== formato do tempo ==")
check("45m",        Config.FormatShort(45 * 60) == "45m", Config.FormatShort(45 * 60))
check("2h 15m",     Config.FormatShort(2 * 3600 + 15 * 60) == "2h 15m", Config.FormatShort(2 * 3600 + 15 * 60))
check("3d 4h",      Config.FormatShort(3 * 86400 + 4 * 3600) == "3d 4h", Config.FormatShort(3 * 86400 + 4 * 3600))
check("0m",         Config.FormatShort(0) == "0m", Config.FormatShort(0))
check("negativo",   Config.FormatShort(-500) == "0m", Config.FormatShort(-500))
check("long 02m09s", Config.FormatLong(129) == "02m 09s", Config.FormatLong(129))
check("long 01h00m05s", Config.FormatLong(3605) == "01h 00m 05s", Config.FormatLong(3605))

print("\n== contagem de tempo ==")
local ana = makePlayer("Ana", 101)
joinPlayer(ana)
check("comeca do zero", totalFor(ana) == 0, totalFor(ana))
advance(300)
check("300s depois de 5min", totalFor(ana) == 300, totalFor(ana))

DB[Config.KeyPrefix .. "202"] = 7200
local bia = makePlayer("Bia", 202)
joinPlayer(bia)
check("carrega 7200 salvos", totalFor(bia) == 7200, totalFor(bia))
advance(60)
check("7260 depois de 1min", totalFor(bia) == 7260, totalFor(bia))

print("\n== autosave ==")
advance(200) -- passa do AutosaveInterval (120)
local function salvoRecente(key, player)
	local v = DB[Config.KeyPrefix .. key]
	local agora = totalFor(player)
	-- snapshot do ultimo autosave: positivo, nunca no futuro, e recente
	return v ~= nil and v > 0 and v <= agora and (agora - v) <= (Config.AutosaveInterval + 100)
end
check("salvou Ana", salvoRecente("101", ana), DB[Config.KeyPrefix .. "101"] .. " vs " .. totalFor(ana))
check("salvou Bia", salvoRecente("202", bia), DB[Config.KeyPrefix .. "202"] .. " vs " .. totalFor(bia))
check("ranking tem Ana", RANK["101"] ~= nil, RANK["101"])
check("ranking tem Bia", RANK["202"] ~= nil, RANK["202"])

print("\n== nunca regride ==")
local antes = DB[Config.KeyPrefix .. "202"]
DB[Config.KeyPrefix .. "202"] = 999999   -- valor maior vindo de outro servidor
savePlayer(bia)
check("mantem o maior valor", DB[Config.KeyPrefix .. "202"] == 999999, DB[Config.KeyPrefix .. "202"])
DB[Config.KeyPrefix .. "202"] = antes

print("\n== ranking ==")
-- jogadores offline so no OrderedDataStore
for i = 1, 12 do RANK[tostring(900 + i)] = i * 1000 end
task.spawn(function() refreshBoard() end)
check("corta no TopCount", #cachedList == Config.TopCount, #cachedList)
local ordenado = true
for i = 2, #cachedList do
	if cachedList[i - 1].seconds < cachedList[i].seconds then ordenado = false end
end
check("ordem decrescente", ordenado)
check("1o e o maior", cachedList[1].seconds == 12000, cachedList[1].seconds)
check("tem nome", cachedList[1].display ~= nil and cachedList[1].display ~= "...", cachedList[1].display)

print("\n== tempo ao vivo passa na frente do salvo ==")
-- Bia esta online e ja passou do valor salvo dela no ranking
RANK["202"] = 1000
local carlos = makePlayer("Carlos", 303)
DB[Config.KeyPrefix .. "303"] = 50000
joinPlayer(carlos)
advance(120)
task.spawn(function() refreshBoard() end)
local carlosEntry, biaEntry
for _, e in cachedList do
	if e.userId == 303 then carlosEntry = e end
	if e.userId == 202 then biaEntry = e end
end
check("Carlos aparece no top", carlosEntry ~= nil)
check("Carlos com tempo ao vivo", carlosEntry and carlosEntry.seconds == totalFor(carlos), carlosEntry and carlosEntry.seconds)
check("Carlos marcado online", carlosEntry and carlosEntry.online == true)
check("Bia usa o tempo ao vivo, nao o 1000 salvo", biaEntry and biaEntry.seconds == totalFor(bia), biaEntry and biaEntry.seconds)

print("\n== o que chega no cliente ==")
pushTo(carlos)
local payload = SENT["Carlos"]
check("recebeu payload", payload ~= nil)
check("payload tem entries", payload and type(payload.entries) == "table")
check("payload tem o SEU tempo", payload and payload.you and payload.you.seconds == totalFor(carlos), payload and payload.you and payload.you.seconds)

print("\n== leaderstats ==")
local ls = ana:FindFirstChild("leaderstats")
check("criou leaderstats", ls ~= nil)
local stat = ls and ls:FindFirstChild(Config.LeaderstatsName)
check("criou o valor", stat ~= nil)
check("valor formatado", stat and stat.Value == Config.FormatShort(totalFor(ana)), stat and stat.Value)

print("\n== falha passageira do ranking NAO desliga o save (regressao) ==")
FAIL_SORTED = true
task.spawn(function() refreshBoard() end)
advance(20)
check("dataOk continua true", dataOk == true)
FAIL_SORTED = false
local marcoAntes = DB[Config.KeyPrefix .. "101"]
advance(300)
check("ainda salva depois da falha", DB[Config.KeyPrefix .. "101"] > marcoAntes, DB[Config.KeyPrefix .. "101"])

print("\n== saida do jogador ==")
local tempoFinal = totalFor(ana)
leavePlayer(ana)
check("salvou ao sair", DB[Config.KeyPrefix .. "101"] == tempoFinal, DB[Config.KeyPrefix .. "101"])
check("limpou a sessao", sessions[ana] == nil)

print("\n== fechamento do servidor ==")
check("registrou BindToClose", CLOSE_HANDLER ~= nil)

print("\n== placa construida ==")
local tagged = game:GetService("CollectionService"):GetTagged(Config.BoardTag)
check("placa criada e marcada", #tagged == 1, #tagged)
check("painel tem o tamanho certo", tagged[1] and tagged[1].Size.X == Config.BoardWidth, tagged[1] and tagged[1].Size.X)
check("painel nao bloqueia raycast", tagged[1] and tagged[1].CanQuery == false)

print(("\n==== %d passaram, %d falharam ====\n"):format(pass, fail))
if fail > 0 then error("TESTES FALHARAM", 0) end
