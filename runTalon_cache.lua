local talon = require("talon")

local args = {...}

local data

if not fs.exists("."..args[1]..".cache") then
    local codeFile = fs.open(args[1], "r")
    local code = codeFile.readAll()
    codeFile.close()

    local cache = fs.open("."..args[1]..".cache", "w")
    data = talon.process(code, "lua", true)
    cache.write(data)
    cache.close()
else
    local cacheFile = fs.open("."..args[1]..".cache", "r")
    data = cacheFile.readAll()
    cacheFile.close()
end

load(data, "talon", "t", _ENV)()
