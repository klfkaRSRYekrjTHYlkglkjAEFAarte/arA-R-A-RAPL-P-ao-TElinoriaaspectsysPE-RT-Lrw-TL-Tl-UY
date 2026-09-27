local HttpService = game:GetService("HttpService")

local SaveManager = {
    Library = nil,
    Folder = "aspect.sys",
    SubFolder = "settings",
    Ignore = {},
    DefaultConfig = "Default",
    Autoload = nil,
    AutoloadConfig = nil,
    Version = 2,
    Loading = false,
    LoadGeneration = 0,
}

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function sanitizeName(value)
    local name = trim(value)
    if name == "" then
        return nil
    end
    name = name:gsub("[/\\:*?<>|\"%c]", "_")
    name = name:gsub("%s+$", "")
    if name == "" or name == "." or name == ".." then
        return nil
    end
    return name
end

local function fileFunction(name)
    local fn = rawget(_G, name)
    if type(fn) == "function" then
        return fn
    end
    if type(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok and type(env) == "table" and type(env[name]) == "function" then
            return env[name]
        end
    end
    return nil
end

local function callFile(name, ...)
    local fn = fileFunction(name)
    if not fn then
        return false, "Executor file API '" .. tostring(name) .. "' is unavailable"
    end
    return pcall(fn, ...)
end

local function isfile(path)
    local fn = fileFunction("isfile")
    if not fn then return false end
    local ok, value = pcall(fn, path)
    return ok and value == true
end

local function isfolder(path)
    local fn = fileFunction("isfolder")
    if not fn then return false end
    local ok, value = pcall(fn, path)
    return ok and value == true
end

local function ensureFolderTree(path)
    local current = ""
    for part in tostring(path or ""):gmatch("[^/]+") do
        current = current == "" and part or (current .. "/" .. part)
        if not isfolder(current) then
            local ok, err = callFile("makefolder", current)
            if not ok and not isfolder(current) then
                return false, err
            end
        end
    end
    return true
end

local function colorToHex(color)
    if typeof(color) ~= "Color3" then
        return "ffffff"
    end
    local ok, value = pcall(function()
        return color:ToHex()
    end)
    if ok and type(value) == "string" then
        return value:gsub("#", "")
    end
    return string.format("%02x%02x%02x", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function parserFor(option)
    return type(option) == "table" and SaveManager.Parser[option.Type] or nil
end

SaveManager.Parser = {
    Toggle = {
        Save = function(idx, object)
            return { type = "Toggle", idx = idx, value = object.Value == true }
        end,
        Load = function(idx, data, library)
            local toggle = library and library.Toggles and library.Toggles[idx]
            if toggle and type(toggle.SetValue) == "function" then
                toggle:SetValue(data.value == true)
            end
        end,
    },
    Slider = {
        Save = function(idx, object)
            return { type = "Slider", idx = idx, value = object.Value }
        end,
        Load = function(idx, data, library)
            local option = library and library.Options and library.Options[idx]
            if option and type(option.SetValue) == "function" then
                option:SetValue(data.value)
            end
        end,
    },
    Dropdown = {
        Save = function(idx, object)
            return { type = "Dropdown", idx = idx, value = object.Value, multi = object.Multi == true }
        end,
        Load = function(idx, data, library)
            local option = library and library.Options and library.Options[idx]
            if option and type(option.SetValue) == "function" then
                option:SetValue(data.value)
            end
        end,
    },
    ColorPicker = {
        Save = function(idx, object)
            return {
                type = "ColorPicker",
                idx = idx,
                value = colorToHex(object.Value),
                transparency = tonumber(object.Transparency) or 0,
            }
        end,
        Load = function(idx, data, library)
            local option = library and library.Options and library.Options[idx]
            if option and type(option.SetValueRGB) == "function" then
                option:SetValueRGB(Color3.fromHex(tostring(data.value or "ffffff"):gsub("#", "")), tonumber(data.transparency) or 0)
            elseif option and type(option.SetValue) == "function" then
                option:SetValue(Color3.fromHex(tostring(data.value or "ffffff"):gsub("#", "")), tonumber(data.transparency) or 0)
            end
        end,
    },
    KeyPicker = {
        Save = function(idx, object)
            return { type = "KeyPicker", idx = idx, mode = tostring(object.Mode or "Toggle"), key = tostring(object.Value or "None") }
        end,
        Load = function(idx, data, library)
            local option = library and library.Options and library.Options[idx]
            if option and type(option.SetValue) == "function" then
                option:SetValue({ tostring(data.key or "None"), tostring(data.mode or "Toggle") })
            end
        end,
    },
    Input = {
        Save = function(idx, object)
            return { type = "Input", idx = idx, text = tostring(object.Value or "") }
        end,
        Load = function(idx, data, library)
            local option = library and library.Options and library.Options[idx]
            if option and type(option.SetValue) == "function" and type(data.text) == "string" then
                option:SetValue(data.text)
            end
        end,
    },
}

function SaveManager:SetLibrary(library)
    assert(type(library) == "table", "SaveManager:SetLibrary requires a Library table")
    self.Library = library
    library.SaveManager = self
    return self
end

function SaveManager:SetIgnoreIndexes(list)
    self.Ignore = self.Ignore or {}
    for _, index in ipairs(type(list) == "table" and list or {}) do
        if type(index) == "string" and trim(index) ~= "" then
            self.Ignore[trim(index)] = true
        end
    end
    return self
end

function SaveManager:_isIgnored(index)
    index = tostring(index)
    if self.Ignore[index] then return true end
    return index:sub(1, 12) == "SaveManager_" or index:sub(1, 13) == "ThemeManager_"
end

function SaveManager:IgnoreThemeSettings()
    return self:SetIgnoreIndexes({
        "BackgroundColor", "MainColor", "AccentColor", "OutlineColor", "FontColor",
        "FontFace", "BackgroundImage", "ThemeManager_FontFace", "ThemeManager_BackgroundImage", "ThemeManager_ThemeName",
    })
end

function SaveManager:GetIgnoreIndexes()
    local result = {}
    for index in pairs(self.Ignore or {}) do
        table.insert(result, index)
    end
    table.sort(result)
    return result
end

function SaveManager:SetFolder(folder)
    folder = sanitizeName(folder)
    if not folder then
        return false, "Invalid config folder"
    end
    self.Folder = folder
    return self:BuildFolderTree()
end

function SaveManager:SetSubFolder(subFolder)
    subFolder = sanitizeName(subFolder)
    self.SubFolder = subFolder
    return self:BuildFolderTree()
end

function SaveManager:_getConfigFolder()
    if type(self.Folder) ~= "string" or self.Folder == "" then return nil end
    if type(self.SubFolder) == "string" and self.SubFolder ~= "" then
        return self.Folder .. "/" .. self.SubFolder
    end
    return self.Folder
end

function SaveManager:_getConfigPath(name)
    local folder = self:_getConfigFolder()
    local safe = sanitizeName(name)
    if not folder or not safe then return nil end
    return folder .. "/" .. safe .. ".json"
end

function SaveManager:_getAutoloadPath()
    local folder = self:_getConfigFolder()
    return folder and (folder .. "/autoload.txt") or nil
end

function SaveManager:BuildFolderTree()
    local folder = self:_getConfigFolder()
    if not folder then return false, "Config folder is not configured" end
    if not fileFunction("makefolder") then return false, "Executor file APIs are unavailable" end
    return ensureFolderTree(folder)
end

function SaveManager:BuildConfigList()
    local result = {}
    local folder = self:_getConfigFolder()
    if not folder or not fileFunction("listfiles") then return result end
    local ok, files = callFile("listfiles", folder)
    if not ok or type(files) ~= "table" then return result end
    for _, filePath in ipairs(files) do
        if type(filePath) == "string" and filePath:lower():sub(-5) == ".json" then
            local name = filePath:match("([^/\\]+)%.json$")
            if name then table.insert(result, name) end
        end
    end
    table.sort(result, function(a, b) return a:lower() < b:lower() end)
    return result
end

SaveManager.RefreshConfigList = SaveManager.BuildConfigList
SaveManager.GetConfigs = SaveManager.BuildConfigList
SaveManager.GetConfigList = SaveManager.BuildConfigList

function SaveManager:SaveJSON()
    assert(self.Library, "SaveManager:SetLibrary(Library) must be called first")
    local data = { version = self.Version, objects = {} }

    local function collect(source, defaultParser)
        for idx, object in pairs(source or {}) do
            if not self:_isIgnored(idx) then
                local parser = parserFor(object)
                if parser and parser.Save then
                    local ok, item = pcall(parser.Save, idx, object)
                    if ok and type(item) == "table" then
                        table.insert(data.objects, item)
                    end
                end
            end
        end
    end

    collect(self.Library.Toggles)
    collect(self.Library.Options)

    local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
    if not ok then return "", false, "failed to encode data" end
    return encoded, true
end

function SaveManager:_readConfig(name)
    local path = self:_getConfigPath(name)
    if not path or not isfile(path) then return false, "invalid file" end
    local ok, content = callFile("readfile", path)
    if not ok or type(content) ~= "string" then return false, content or "read error" end
    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, content)
    if not decodeOk or type(data) ~= "table" then return false, "decode error" end
    return true, data
end

local function normalizeLegacyObjects(objects)
    local result = {}
    if type(objects) ~= "table" then return result end

    local numeric = true
    for key in pairs(objects) do
        if type(key) ~= "number" then numeric = false break end
    end

    if numeric then
        for _, item in ipairs(objects) do
            if type(item) == "table" then
                table.insert(result, item)
            end
        end
        return result
    end

    for idx, item in pairs(objects) do
        if type(item) == "table" then
            local value = item.Value
            local kind = item.Type
            if kind == "ColorPicker" and type(value) == "table" then
                table.insert(result, { type = kind, idx = idx, value = value.Color, transparency = value.Transparency })
            elseif kind == "KeyPicker" and type(value) == "table" then
                table.insert(result, { type = kind, idx = idx, key = value.Key, mode = value.Mode })
            else
                table.insert(result, { type = kind, idx = idx, value = value })
            end
        end
    end
    return result
end

function SaveManager:_applyItem(item)
    if type(item) ~= "table" then return end
    local library = self.Library
    local parser = self.Parser[item.type]
    if not parser or type(item.idx) ~= "string" and type(item.idx) ~= "number" then return end
    pcall(parser.Load, tostring(item.idx), item, library)
end

function SaveManager:Load(name)
    name = sanitizeName(name)
    if not name then return false, "no config file is selected" end
    local ok, data = self:_readConfig(name)
    if not ok then return false, data end

    local objects = normalizeLegacyObjects(data.objects or data)
    self.LoadGeneration = (self.LoadGeneration or 0) + 1
    local generation = self.LoadGeneration
    self.Loading = true

    task.spawn(function()
        local processed = 0
        for _, item in ipairs(objects) do
            if generation ~= self.LoadGeneration then break end
            self:_applyItem(item)
            processed += 1
            if processed % 2 == 0 then
                task.wait()
            end
        end
        if generation == self.LoadGeneration then
            self.Loading = false
            if self.OnLoadFinished then
                pcall(self.OnLoadFinished, self, name, processed)
            end
        end
    end)

    return true
end

function SaveManager:Save(name)
    name = sanitizeName(name or self.DefaultConfig)
    if not name then return false, "Invalid config name" end
    local ok, err = self:BuildFolderTree()
    if not ok then return false, err end
    local path = self:_getConfigPath(name)
    local json, encoded, encodeErr = self:SaveJSON()
    if not encoded then return false, encodeErr end
    local wrote, writeErr = callFile("writefile", path, json)
    if not wrote then return false, writeErr end
    self:UpdateConfigList()
    return true
end

function SaveManager:Delete(name)
    name = sanitizeName(name)
    local path = self:_getConfigPath(name)
    if not path or not isfile(path) then return false, "Config does not exist" end
    local ok, err = callFile("delfile", path)
    if not ok then return false, err end
    if self:GetAutoloadConfig() == name then self:SaveAutoloadConfig(nil) end
    self:UpdateConfigList()
    return true
end

function SaveManager:GetAutoloadConfig()
    if type(self.Autoload) == "string" and trim(self.Autoload) ~= "" then return self.Autoload end
    if type(self.AutoloadConfig) == "string" and trim(self.AutoloadConfig) ~= "" then return self.AutoloadConfig end
    local path = self:_getAutoloadPath()
    if not path or not isfile(path) then return nil end
    local ok, value = callFile("readfile", path)
    if ok and type(value) == "string" and trim(value) ~= "" then
        value = sanitizeName(value)
        self.Autoload = value
        self.AutoloadConfig = value
        return value
    end
    return nil
end

function SaveManager:SaveAutoloadConfig(name)
    if name == nil or trim(tostring(name)) == "" then
        self.Autoload = nil
        self.AutoloadConfig = nil
        local path = self:_getAutoloadPath()
        if path and isfile(path) then callFile("delfile", path) end
        return true
    end

    name = sanitizeName(name)
    if not name then return false, "Autoload config must not be empty" end
    local configPath = self:_getConfigPath(name)
    if not configPath or not isfile(configPath) then return false, "Config does not exist" end
    local ok, err = self:BuildFolderTree()
    if not ok then return false, err end
    local path = self:_getAutoloadPath()
    ok, err = callFile("writefile", path, name)
    if not ok then return false, err end
    self.Autoload = name
    self.AutoloadConfig = name
    self:UpdateConfigList()
    return true
end

function SaveManager:LoadAutoloadConfig()
    local name = self:GetAutoloadConfig()
    if not name then return false, "no autoload config selected" end
    return self:Load(name)
end

SaveManager.LoadAutoload = SaveManager.LoadAutoloadConfig
SaveManager.SetAutoload = SaveManager.SaveAutoloadConfig

function SaveManager:UpdateConfigList()
    local library = self.Library
    local option = library and library.Options and library.Options.SaveManager_ConfigList
    if option and type(option.SetValues) == "function" then
        local values = self:BuildConfigList()
        pcall(function() option:SetValues(values) end)
        local current = option.Value
        local exists = false
        for _, value in ipairs(values) do
            if value == current then exists = true break end
        end
        if not exists and type(option.SetValue) == "function" then
            pcall(function() option:SetValue(nil) end)
        end
    end

    local label = self.AutoloadLabel
    if label and type(label.SetText) == "function" then
        local current = self:GetAutoloadConfig()
        pcall(function()
            label:SetText(current and ("Current autoload config: " .. current) or "Current autoload config: none")
        end)
    end
end

function SaveManager:BuildConfigSection(tabOrGroupbox)
    assert(self.Library, "Must set SaveManager.Library")
    local groupbox = tabOrGroupbox
    if groupbox and type(groupbox.AddRightGroupbox) == "function" then
        groupbox = groupbox:AddRightGroupbox("Configuration")
    elseif groupbox and type(groupbox.AddLeftGroupbox) == "function" then
        groupbox = groupbox:AddLeftGroupbox("Configuration")
    end
    assert(groupbox, "SaveManager:BuildConfigSection requires a tab or groupbox")

    self:BuildFolderTree()
    local library = self.Library
    self.OnLoadFinished = function(manager, name)
        if type(library.Notify) == "function" then
            library:Notify("Loaded config " .. tostring(name), 2)
        end
    end
    local configs = self:BuildConfigList()
    local autoload = self:GetAutoloadConfig()
    local selectedAutoload = nil
    if autoload then
        for _, configName in ipairs(configs) do
            if configName == autoload then
                selectedAutoload = autoload
                break
            end
        end
    end

    groupbox:AddInput("SaveManager_ConfigName", {
        Text = "Config name",
        Default = "",
        Placeholder = "Config name",
    })

    groupbox:AddDropdown("SaveManager_ConfigList", {
        Text = "Config list",
        Values = configs,
        AllowNull = true,
        Default = selectedAutoload,
        Callback = function(value)
            if type(value) ~= "string" or value == "" then return end
            local input = library.Options and library.Options.SaveManager_ConfigName
            if input and type(input.SetValue) == "function" then
                pcall(function() input:SetValue(value) end)
            end
        end,
    })

    groupbox:AddDivider()

    groupbox:AddButton("Save config", function()
        local input = library.Options.SaveManager_ConfigName
        local name = input and input.Value
        if type(name) ~= "string" or trim(name) == "" then
            local selection = library.Options.SaveManager_ConfigList
            name = selection and selection.Value
        end
        local ok, err = self:Save(name)
        if ok then
            local safe = sanitizeName(name)
            local selection = library.Options.SaveManager_ConfigList
            if selection and safe and type(selection.SetValues) == "function" then
                self:UpdateConfigList()
                if type(selection.SetValue) == "function" then pcall(function() selection:SetValue(safe) end) end
            end
            if input and safe and type(input.SetValue) == "function" then pcall(function() input:SetValue(safe) end) end
        elseif type(library.Notify) == "function" then
            library:Notify("Save: " .. tostring(err), 3)
        end
    end)

    groupbox:AddButton("Load config", function()
        local selection = library.Options.SaveManager_ConfigList
        local name = selection and selection.Value
        local ok, err = self:Load(name)
        if ok then
            local input = library.Options.SaveManager_ConfigName
            if input and type(name) == "string" and type(input.SetValue) == "function" then
                pcall(function() input:SetValue(name) end)
            end
            if type(library.Notify) == "function" then
                library:Notify("Loading config " .. tostring(name) .. "...", 2)
            end
        elseif type(library.Notify) == "function" then
            library:Notify("Load: " .. tostring(err), 3)
        end
    end)

    groupbox:AddButton("Overwrite config", function()
        local selection = library.Options.SaveManager_ConfigList
        local name = selection and selection.Value
        local ok, err = self:Save(name)
        if not ok and type(library.Notify) == "function" then
            library:Notify("Save: " .. tostring(err), 3)
        end
    end)

    groupbox:AddButton("Refresh list", function()
        self:UpdateConfigList()
    end)

    groupbox:AddToggle("SaveManager_Autoload", {
        Text = "Autoload selected",
        Default = selectedAutoload ~= nil,
        Callback = function(value)
            local selection = library.Options.SaveManager_ConfigList
            local name = selection and selection.Value
            if value then
                local ok, err = self:SaveAutoloadConfig(name)
                if not ok and type(library.Notify) == "function" then
                    library:Notify("Autoload: " .. tostring(err), 3)
                end
            else
                self:SaveAutoloadConfig(nil)
            end
            self:UpdateConfigList()
        end,
    })

    groupbox:AddButton("Clear autoload", function()
        self:SaveAutoloadConfig(nil)
        self:UpdateConfigList()
    end)

    self.AutoloadLabel = groupbox:AddLabel("Current autoload config: " .. tostring(selectedAutoload or "none"), true)
    self.ConfigGroupbox = groupbox
    self:UpdateConfigList()
    return groupbox
end

return SaveManager
