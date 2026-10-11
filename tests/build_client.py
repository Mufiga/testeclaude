import io, os
SP = os.path.join(os.path.dirname(os.path.abspath(__file__)))
r = lambda p: io.open(p, encoding="utf-8").read()
config = r("src/ReplicatedStorage/PlaytimeConfig.luau")
client = r("src/StarterPlayer/StarterPlayerScripts/PlaytimeScoreboardClient.client.luau")
old = 'local Config = require(ReplicatedStorage:WaitForChild("PlaytimeConfig"))'
assert client.count(old) == 1
client = client.replace(old, "local Config = __CONFIG")
out = "\n".join([r(SP+"/client_stubs.luau"),
                 "local __CONFIG = (function()\n"+config+"\nend)()\n", client, r(SP+"/client_tests.luau")])
io.open(SP+"/run_client.luau","w",encoding="utf-8").write(out)
