local format = require("format")
local lex = require("lex")
local minify = require("minify")
local talon = {}

function talon.tokenize(code)
    local result = {}
    local current = ""
    local spacing = 0
    local i = 1

    while true do
        if i > #code then break end
        local c = code:sub(i, i)

        if c:match("%s") then
            if current ~= "" then
                table.insert(result, { text = current, spacing = spacing })
                current = ""
                spacing = 1
            else
                spacing = spacing + 1
            end
        elseif c == '(' or c == ')' or c == '{' or c == '}' or c == ';' or c == ',' then
            if current ~= "" then
                table.insert(result, { text = current, spacing = spacing })
                current = ""
            end
            table.insert(result, { text = c, spacing = spacing })
            spacing = 0
        elseif c == '"' then
            local j = i + 1
            local str = '"'
            while j <= #code do
                local ch = code:sub(j, j)
                str = str .. ch
                if ch == '"' then break end
                j = j + 1
            end
            table.insert(result, { text = str, spacing = spacing })
            i = j
            spacing = 0
        else
            current = current .. c
        end
        i = i + 1
    end

    if current ~= "" then
        table.insert(result, current)
    end

    return result
end

local walkStatement, walkBody

local function parseParameterList(tokens)
    assert(table.remove(tokens, 1).text == "(", "Expected '(' after function type identifier")
    local names = {}
    while #tokens > 0 do
        local token = table.remove(tokens, 1)
        if not token.text then
            error("Unexpected end of tokens while parsing parameter list")
        elseif token.text == ")" then
            break
        elseif token.text ~= "," then
            if token.text:sub(-1) ~= ":" then table.insert(names, token.text) end
        end
    end
    return names
end

local function parseCallList(tokens)
    local params = {}
    assert(table.remove(tokens, 1).text == "(", "Expected '(' after function type identifier")

    while #tokens > 0 do
        local token = table.remove(tokens, 1)
        if not token.text then
            error("Unexpected end of tokens while parsing parameter list")
        elseif token.text == ")" then
            break
        elseif token.text ~= "," then
            table.insert(params, token.text)
        end
    end

    return params
end

local function parseIfList(tokens)
    local params = {}
    assert(table.remove(tokens, 1).text == "(", "Expected '(' to start if condition")

    while true do
        local token = table.remove(tokens, 1).text
        if not token then
            error("Unexpected end of tokens while parsing parameter list")
        elseif token == ")" then
            break
        elseif token == "==" then
            table.insert(params, "==")
        elseif token == "!=" then
            table.insert(params, "~=")
        else
            table.insert(params, token)
        end
    end

    return table.concat(params)
end

local function parseLet(tokens)
    local initial = table.remove(tokens, 1)
    if tonumber(initial.text) then return tonumber(initial.text) end
    return initial.text
end

function walkStatement(initial, tokens)
    if initial == "define" then
        local defineType = table.remove(tokens, 1).text
        local defineName = table.remove(tokens, 1).text
        local argLen = parseParameterList(tokens)
        assert(table.remove(tokens, 1).text == "{", "Expected '{' to start function body")
        local blockContent = walkBody(tokens)
        assert(table.remove(tokens, 1).text == ";", "Expected closing ';'")
        return {
            type = "define",
            defineType = defineType,
            defineName = defineName,
            argLen = argLen,
            blockContent = blockContent
        }
    elseif initial == "if" then
        local condition = parseIfList(tokens)
        assert(table.remove(tokens, 1).text == "{", "Expected '{' to start if body")
        local blockContent = walkBody(tokens)
        assert(table.remove(tokens, 1).text == ";", "Expected closing ';'")
        return {
            type = "if",
            condition = condition,
            blockContent = blockContent
        }
    elseif initial == "let" then
        local varType = table.remove(tokens, 1).text:sub(1, -2)
        local identifier = table.remove(tokens, 1).text
        assert(table.remove(tokens, 1).text == "=", "Expected '=' after identifier")
        local value = parseLet(tokens)
        assert(table.remove(tokens, 1).text == ";", "Expected closing ';'")
        return {
            type = "let",
            varType = varType,
            identifier = identifier,
            value = value
        }
    elseif initial == "return" then
        assert(table.remove(tokens, 1).text == ";", "Expected closing ';'")
        return {
            type = "return"
        }
    elseif initial == "use" then
        local libPath = table.remove(tokens, 1).text
        assert(table.remove(tokens, 1).text == ";", "Expected closing ';'")
        return {
            type = "use",
            libPath = libPath
        }
    elseif tokens[1].text == "(" then
        local funcName = initial
        local callList = parseCallList(tokens)
        assert(table.remove(tokens, 1).text == ";", "Expected closing ';'")
        return {
            type = "func_call",
            funcName = funcName,
            callList = callList
        }
    elseif tokens[1].text == "+=" or tokens[1].text == "-=" or tokens[1].text == "*=" or tokens[1].text == "/=" then
        local lefthand = initial
        local operation = table.remove(tokens, 1).text
        local righthand = table.remove(tokens, 1).text
        return {
            type = "self_op",
            lefthand = lefthand,
            operation = operation,
            righthand = righthand
        }
    elseif tokens[1].text == "=" then
        local lefthand = initial
        local _ = table.remove(tokens, 1)
        local righthand = table.remove(tokens, 1).text
        return {
            type = "assignment",
            lefthand = lefthand,
            righthand = righthand
        }
    end
end

function walkBody(tokens)
    local ast = {}
    while #tokens > 0 do
        local token = tokens[1]
        if token.text == "}" then
            table.remove(tokens, 1)
            break
        end
        local initial = table.remove(tokens, 1)
        ast[#ast + 1] = walkStatement(initial.text, tokens)
    end
    return ast
end

function talon.buildAST(tokens)
    local ast = {}
    while #tokens > 0 do
        local initial = table.remove(tokens, 1)
        ast[#ast + 1] = walkStatement(initial.text, tokens)
    end
    return ast
end

local parseBlock

local blockHandlers = {
    lua = {
        statement_define = function(code, block)
            code[#code + 1] = "function " .. block.defineName .. "("
            local added = false
            for _, arg in ipairs(block.argLen) do
                code[#code] = code[#code] .. arg .. ","
                added = true
            end
            if added then code[#code] = code[#code]:sub(1, -2) end
            code[#code] = code[#code] .. ")"
            parseBlock(code, block.blockContent, "lua")

            local codeEnd = code[#code]
            local codeEndTokens = talon.tokenize(codeEnd)
            if codeEndTokens[2].text == "(" then
                code[#code] = "return " .. codeEnd
            end

            code[#code + 1] = "end"
        end,
        statement_if = function(code, block)
            code[#code + 1] = "if " .. block.condition .. " then"
            parseBlock(code, block.blockContent, "lua")
            code[#code + 1] = "end"
        end,
        statement_let = function(code, block)
            code[#code + 1] = "local " .. block.identifier .. " = " .. block.value
        end,
        statement_func_call = function(code, block)
            code[#code + 1] = block.funcName .. "("
            local added = false
            for _, var in ipairs(block.callList) do
                code[#code] = code[#code] .. var .. ","
                added = true
            end
            if added then code[#code] = code[#code]:sub(1, -2) end
            code[#code] = code[#code] .. ")"
        end,
        statement_self_op = function(code, block)
            code[#code + 1] = block.lefthand .. "=" .. block.lefthand .. block.operation:sub(1, -2) .. block.righthand
        end,
        statement_assignment = function(code, block)
            code[#code + 1] = block.lefthand .. "=" .. block.righthand
        end,
        statement_return = function(code, block)
            code[#code + 1] = "return"
        end,
        statement_use = function(code, block)
            local parts = {}
            for part in string.gmatch(block.libPath, "[^/]+") do
                table.insert(parts, part)
            end
            code[#code + 1] = parts[#parts] .. " = require(\"" .. block.libPath .. "\")"
        end
    }
}

function parseBlock(code, astBlock, lang)
    if astBlock then
        for _, block in ipairs(astBlock) do
            if block.type == "define" then
                blockHandlers[lang].statement_define(code, block)
            elseif block.type == "if" then
                blockHandlers[lang].statement_if(code, block)
            elseif block.type == "func_call" then
                blockHandlers[lang].statement_func_call(code, block)
            elseif block.type == "self_op" then
                blockHandlers[lang].statement_self_op(code, block)
            elseif block.type == "assignment" then
                blockHandlers[lang].statement_assignment(code, block)
            elseif block.type == "let" then
                blockHandlers[lang].statement_let(code, block)
            elseif block.type == "return" then
                blockHandlers[lang].statement_return(code, block)
            elseif block.type == "use" then
                blockHandlers[lang].statement_use(code, block)
            end
        end
    else
        return
    end
end

function talon.compile(ast, lang)
    local code = {}
    if lang == "lua" then
        for _, block in ipairs(ast) do
            if block.type == "define" then
                code[#code + 1] = "local " .. block.defineName
            end
        end
    end

    parseBlock(code, ast, lang)

    if lang == "lua" then
        code[#code + 1] = "main()"
    end

    return code
end

function talon.process(code, lang, release)
    if not release then
        return format(table.concat(talon.compile(talon.buildAST(talon.tokenize(code)), lang), "\n"))
    else
        local data = format(table.concat(talon.compile(talon.buildAST(talon.tokenize(code)), lang), "\n"))
        local tokens = lex(data, 1, 2)
        minify(tokens)
        local retval = ""
        local lastchar, lastdot = false, false
        for _, v in ipairs(tokens) do
            v = v.text
            if (lastchar and v:match "^[A-Za-z0-9_]") or (lastdot and v:match "^%.") then retval = retval .. " " end
            retval = retval .. v
            lastchar, lastdot = v:match "[A-Za-z0-9_]$", v:match "%.$"
        end
        return retval
    end
end

return talon
