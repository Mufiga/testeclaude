--===================== testes do cliente =====================
local pass, fail = 0, 0
local function check(label, cond, extra)
	if cond then pass += 1; print("  ok   " .. label)
	else fail += 1; print("  FALHA " .. label .. (extra and ("  -> " .. tostring(extra)) or "")) end
end

local board = boards[BOARD_PART]
print("\n== montagem ==")
check("placa montada", board ~= nil)
check("criou " .. ROWS .. " linhas", board and #board.rows == ROWS, board and #board.rows)
check("tem rodape SEU TEMPO", board and board.footerValue ~= nil)
check("uma SurfaceGui so", (function()
	local n = 0
	for _, i in ALL do if i.ClassName == "SurfaceGui" then n += 1 end end
	return n
end)() == 1)

local criadasDepoisDaMontagem = #ALL

print("\n== poucos jogadores: vagas vazias ==")
REMOTE.OnClientEvent:Fire({
	entries = {
		{ userId = 1, display = "Alfa", seconds = 7200, online = true },
		{ userId = 2, display = "Beta", seconds = 3600 },
	},
	you = { seconds = 100 },
})
check("linha 1 = Alfa", board.rows[1].name.Text == "Alfa", board.rows[1].name.Text)
check("linha 1 = 2h 00m", board.rows[1].time.Text == "2h 00m", board.rows[1].time.Text)
check("linha 5 vazia", board.rows[5].name.Text == Config.EmptyText, board.rows[5].name.Text)
check("linha 5 apagada", board.rows[5].name.TextColor3 == Config.Palette.InkSoft)
check("rodape preenchido", board.footerValue.Text == Config.FormatLong(100), board.footerValue.Text)

print("\n== REGRESSAO: vaga vazia que recebe jogador volta a cor normal ==")
local cheio = {}
for i = 1, ROWS do
	table.insert(cheio, { userId = 100 + i, display = "Jog" .. i, seconds = (ROWS - i + 1) * 600 })
end
REMOTE.OnClientEvent:Fire({ entries = cheio, you = { seconds = 100 } })
check("linha 5 agora tem nome", board.rows[5].name.Text == "Jog5", board.rows[5].name.Text)
check("linha 5 com texto ESCURO (bug corrigido)", board.rows[5].name.TextColor3 == Config.Palette.Ink)
check("linha 5 hora escura tambem", board.rows[5].time.TextColor3 == Config.Palette.Ink)

print("\n== destaque do proprio jogador ==")
local comVoce = {}
for i = 1, ROWS do
	table.insert(comVoce, { userId = (i == 3) and LOCAL_PLAYER.UserId or (200 + i), display = "P" .. i, seconds = (ROWS - i + 1) * 600 })
end
REMOTE.OnClientEvent:Fire({ entries = comVoce, you = { seconds = 100 } })
check("sua linha fica verde", board.rows[3].frame.BackgroundColor3 == Config.Palette.YouTint)
check("seu texto fica verde", board.rows[3].name.TextColor3 == Config.Palette.LeafDark)
check("linha 4 continua normal", board.rows[4].name.TextColor3 == Config.Palette.Ink)

print("\n== volta a ser linha comum quando voce sai do top ==")
REMOTE.OnClientEvent:Fire({ entries = cheio, you = { seconds = 100 } })
check("linha 3 sem destaque", board.rows[3].frame.BackgroundColor3 == Config.Palette.PanelAlt)
check("linha 3 texto normal", board.rows[3].name.TextColor3 == Config.Palette.Ink)

print("\n== relogio ao vivo ==")
REMOTE.OnClientEvent:Fire({
	entries = {
		{ userId = 1, display = "Online", seconds = 3600, online = true },
		{ userId = 2, display = "Offline", seconds = 3600 },
	},
	you = { seconds = 0 },
})
check("online 1h 00m", board.rows[1].time.Text == "1h 00m", board.rows[1].time.Text)
setClock(500 + 600)   -- 10 minutos depois, sem novo pacote do servidor
render(board)
check("online andou pra 1h 10m", board.rows[1].time.Text == "1h 10m", board.rows[1].time.Text)
check("offline ficou parado", board.rows[2].time.Text == "1h 00m", board.rows[2].time.Text)
check("rodape andou", board.footerValue.Text == Config.FormatLong(600), board.footerValue.Text)

print("\n== nao cria instancias ao redesenhar (performance) ==")
check("nenhuma instancia nova", #ALL == criadasDepoisDaMontagem, (#ALL - criadasDepoisDaMontagem) .. " criadas")

print(("\n==== %d passaram, %d falharam ====\n"):format(pass, fail))
if fail > 0 then error("TESTES DO CLIENTE FALHARAM", 0) end
