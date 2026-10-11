import io, os
SP = os.path.join(os.path.dirname(os.path.abspath(__file__)))
r = lambda p: io.open(p, encoding="utf-8").read()
config = r("src/ReplicatedStorage/PlaytimeConfig.luau")
server = r("src/ServerScriptService/PlaytimeScoreboardServer.server.luau")
old = 'local Config = require(ReplicatedStorage:WaitForChild("PlaytimeConfig"))'
assert server.count(old) == 1
server = server.replace(old, "local Config = __CONFIG")
out = "\n".join([r(SP+"/stubs.luau"), r(SP+"/services.luau"),
                 "local __CONFIG = (function()\n"+config+"\nend)()\n", server, r(SP+"/tests.luau")])
io.open(SP+"/run_tests.luau","w",encoding="utf-8").write(out)
