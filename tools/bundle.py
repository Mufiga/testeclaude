#!/usr/bin/env python3
"""Junta os modulos de src/shared/RockKit num unico arquivo Luau.

Serve para quem nao usa Rojo: o resultado cabe num unico ModuleScript.
Os `require(script.X)` / `require(script.Parent.X)` viram chamadas a um
require local, resolvido na tabela de modulos do proprio arquivo.

Uso: python3 tools/bundle.py
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCE = ROOT / "src" / "shared" / "RockKit"
OUTPUT = ROOT / "build" / "RockKit.standalone.luau"

REQUIRE = re.compile(r"require\(\s*script(?:\.Parent)?\.([A-Za-z_][A-Za-z0-9_]*)\s*\)")
EXPORT_TYPE = re.compile(r"^export type ", re.MULTILINE)

HEADER = """--!nocheck
--!nolint
--[[
	RockKit — versao de arquivo unico, gerada por tools/bundle.py.
	NAO EDITE AQUI: mexa em src/shared/RockKit/ e rode o bundler de novo.

	Como usar sem Rojo:
	  1. Em ReplicatedStorage, crie um ModuleScript chamado "RockKit".
	  2. Cole todo o conteudo deste arquivo dentro dele.
	  3. require(game.ReplicatedStorage.RockKit)
]]

local __modules: { [string]: () -> any } = {}
local __loaded: { [string]: any } = {}

local function __require(name: string): any
	local cached = __loaded[name]
	if cached ~= nil then
		return cached
	end
	local factory = __modules[name]
	if not factory then
		error("[RockKit] modulo nao encontrado no bundle: " .. name, 2)
	end
	local result = factory()
	__loaded[name] = result
	return result
end
"""


def module_name(path: pathlib.Path) -> str:
    return "RockKit" if path.stem == "init" else path.stem


def main() -> int:
    files = sorted(SOURCE.glob("*.luau"))
    if not files:
        print(f"nenhum modulo em {SOURCE}", file=sys.stderr)
        return 1

    chunks = [HEADER]
    for path in files:
        name = module_name(path)
        body = REQUIRE.sub(lambda m: f'__require("{m.group(1)}")', path.read_text())
        # `export type` so vale no topo de um modulo; dentro da fabrica vira type local
        body = EXPORT_TYPE.sub("type ", body)
        # indenta para o corpo ficar legivel dentro da funcao fabrica
        indented = "\n".join(("\t" + line) if line.strip() else line for line in body.splitlines())
        chunks.append(f'\n__modules["{name}"] = function()\n{indented}\nend\n')

    chunks.append('\nreturn __require("RockKit")\n')

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text("".join(chunks))
    print(f"gerado {OUTPUT.relative_to(ROOT)} a partir de {len(files)} modulos")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
