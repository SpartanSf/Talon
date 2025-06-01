local width, _ = term.getSize()

local function centerText(text, y)
    term.setCursorPos(math.floor(width / 2 - #text / 2), y)
    write(text)
end

local function clearLines(startLine, count)
    for i = 0, count - 1 do
        term.setCursorPos(1, startLine + i)
        term.clearLine()
    end
end

local function updateStatus(text)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    clearLines(9, 1)
    centerText(text, 9)
end

local function drawProgressBar(ratio)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.lime)
    term.setCursorPos(1, 11)

    for i = 1, width do
        if i / width < ratio then
            write("]")
        else
            write(" ")
        end
    end
end

local function downloadFile(remotePath, localPath)
    term.setCursorPos(1, 13)
    print("Accessing: " .. remotePath)
    local response = http.get(remotePath)
    if not response then
        error("Failed to download: " .. remotePath)
    end
    local data = response.readAll()
    response.close()

    local file = fs.open(localPath, "w")
    file.write(data)
    file.close()
end

local function install()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.yellow)
    term.clear()
    centerText("Talon Installer", 2)

    updateStatus("Loading manifest...")
    drawProgressBar(0)

    local manifestUrl = "https://raw.githubusercontent.com/SpartanSf/Talon/master/manifest.txt"
    local response = http.get(manifestUrl)
    if not response then
        error("Failed to load manifest from: " .. manifestUrl)
    end
    local manifestContent = response.readAll()
    response.close()

    local steps = {}
    for line in manifestContent:gmatch("[^\r\n]+") do
        local parts = {}
        for word in line:gmatch("%S+") do
            table.insert(parts, word)
        end
        if parts[1] == "file" then
            table.insert(steps, {
                type = "file",
                remote = parts[2],
                localPath = parts[3]
            })
        elseif parts[1] == "dir" then
            table.insert(steps, {
                type = "dir",
                path = parts[2]
            })
        end
    end

    for i, step in ipairs(steps) do
        local ratio = i / #steps
        if step.type == "file" then
            updateStatus("Downloading " .. step.localPath .. "...")
            local fileUrl = "https://raw.githubusercontent.com/SpartanSf/Talon/master/" .. step.remote
            downloadFile(fileUrl, step.localPath)
        elseif step.type == "dir" then
            updateStatus("Creating folder: " .. step.path)
            fs.makeDir(step.path)
        end
        drawProgressBar(ratio)
    end

    updateStatus("Installation complete!")
    sleep(1)

    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    write("Finished installation!\nPress any key to close...")
    os.pullEventRaw()
    term.clear()
    term.setCursorPos(1, 1)
end

install()
