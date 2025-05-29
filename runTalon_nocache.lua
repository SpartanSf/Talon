local talon = require("talon")

local args = {...}

local codeFile = fs.open(args[1], "r")
local code = codeFile.readAll()
codeFile.close()

load(talon.process(code, "lua", true), "talon", "t", _ENV)()
