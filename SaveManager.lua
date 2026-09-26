


local HttpService = game:GetService("HttpService")

local SaveManager = {
    Library = nil,
    Folder = "aspect.sys",
    SubFolder = nil,
    Ignore = {},
    DefaultConfig = "Default",
    Autoload = nil,
    AutoloadConfig = nil,
    Version = 1,
}

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function isString(value)
    return type(value) == "string" and trim(value) ~= ""
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

local function getFileApi(name)
    local value = rawget(_G, name)
    if type(value) == "function" then
        return value
    end
    if type(getgenv) == "function" then
        local ok, globalEnv = pcall(getgenv)
        if ok and type(globalEnv) == "table" and type(globalEnv[name]) == "function" then
            return globalEnv[name]
        end
    end
    return nil
end

local function callFile(name, ...)
    local fn = getFileApi(name)
    if not fn then
        return false, "Executor file API '" .. tostring(name) .. "' is unavailable"
    end
    return pcall(fn, ...)
end

local function folderExists(path)
    local fn = getFileApi("isfolder")
    if not fn then
        return false
    end
    local ok, result = pcall(fn, path)
    return ok and result == true
end

local function fileExists(path)
    local fn = getFileApi("isfile")
    if not fn then
        return false
    end
    local ok, result = pcall(fn, path)
    return ok and result == true
end

local function ensureFolderTree(path)
    local current = ""
    for part in tostring(path or ""):gmatch("[^/]+") do
        current = current == "" and part or (current .. "/" .. part)
        if not folderExists(current) then
            local ok, err = callFile("makefolder", current)
            if not ok and not folderExists(current) then
                return false, err
            end
        end
    end
    return true
end

local function toHex(color)
    if typeof(color) ~= "Color3" then
        return "ffffff"
    end
    local ok, value = pcall(function() return color:ToHex() end)
    if ok and type(value) == "string" then
        return value:gsub("#", "")
    end
    return string.format("%02x%02x%02x", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

local function optionValue(option)
    if type(option) ~= "table" then
        return nil
    end

    if option.Type == "ColorPicker" then
        return {
            Color = toHex(option.Value),
            Transparency = tonumber(option.Transparency) or 0,
        }
    end

    if option.Type == "KeyPicker" then
        return {
            Key = tostring(option.Value or "None"),
            Mode = tostring(option.Mode or "Toggle"),
            Toggled = option.Toggled == true,
        }
    end

    if option.Type == "Dropdown" then
        return option.Value
    end

    return option.Value
end

local function isSavableOption(option)
    if type(option) ~= "table" then
        return false
    end
    if type(option.SetValue) ~= "function" and option.Type ~= "ColorPicker" then
        return false
    end
    return option.Type ~= "Button" and option.Type ~= "Divider" and option.Type ~= "Label"
end

function SaveManager:SetLibrary(library)
    assert(type(library) == "table", "SaveManager:SetLibrary requires a Library table")
    self.Library = library
    library.SaveManager = self
    return self
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
    if not isString(self.Folder) then
        return nil
    end
    if isString(self.SubFolder) then
        return self.Folder .. "/" .. self.SubFolder
    end
    return self.Folder
end

function SaveManager:_getConfigPath(name)
    local safeName = sanitizeName(name)
    local folder = self:_getConfigFolder()
    if not safeName or not folder then
        return nil
    end
    return folder .. "/" .. safeName .. ".json"
end

function SaveManager:_getAutoloadPath()
    local folder = self:_getConfigFolder()
    if not folder then
        return nil
    end
    return folder .. "/autoload.txt"
end

function SaveManager:BuildFolderTree()
    local folder = self:_getConfigFolder()
    if not folder then
        return false, "Config folder is not configured"
    end
    if not getFileApi("makefolder") then
        return false, "Executor file APIs are unavailable"
    end
    return ensureFolderTree(folder)
end

function SaveManager:BuildConfigList()
    local result = {}
    local folder = self:_getConfigFolder()
    if not folder or not getFileApi("listfiles") then
        return result
    end

    local ok, files = callFile("listfiles", folder)
    if not ok or type(files) ~= "table" then
        return result
    end

    for _, filePath in ipairs(files) do
        if type(filePath) == "string" and filePath:lower():sub(-5) == ".json" then
            local name = filePath:match("([^/\\]+)%.json$")
            if name then
                table.insert(result, name)
            end
        end
    end
    table.sort(result, function(a, b) return a:lower() < b:lower() end)
    return result
end

SaveManager.GetConfigs = SaveManager.BuildConfigList
SaveManager.GetConfigList = SaveManager.BuildConfigList

function SaveManager:SetIgnoreIndexes(list)
    
    
    
    self.Ignore = self.Ignore or {}
    for _, index in ipairs(type(list) == "table" and list or {}) do
        if type(index) == "string" then
            local cleaned = trim(index)
            if cleaned ~= "" then
                self.Ignore[cleaned] = true
            end
        end
    end
    return self
end

function SaveManager:_isIgnored(index)
    index = tostring(index)
    if self.Ignore[index] then
        return true
    end
    if index:sub(1, 12) == "SaveManager_" then
        return true
    end
    if index:sub(1, 13) == "ThemeManager_" then
        return true
    end
    return false
end

function SaveManager:IgnoreThemeSettings()
    return self:SetIgnoreIndexes({
        "ThemeManager_FontFace",
        "ThemeManager_BackgroundImage",
        "ThemeManager_ThemeName",
        "FontFace",
        "BackgroundImage",
    })
end

function SaveManager:GetIgnoreIndexes()
    local result = {}
    for index in pairs(self.Ignore) do
        table.insert(result, index)
    end
    table.sort(result)
    return result
end

function SaveManager:SaveJSON()
    if not self.Library then
        return "", false, "Library is not set"
    end

    local data = {
        version = self.Version,
        objects = {},
    }

    local function collect(source)
        for index, option in pairs(source or {}) do
            local key = tostring(index)
            if not self:_isIgnored(key) and isSavableOption(option) then
                local value = optionValue(option)
                if value ~= nil then
                    data.objects[key] = {
                        Type = option.Type,
                        Value = value,
                    }
                end
            end
        end
    end

    collect(self.Library.Options)
    collect(self.Library.Toggles)

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then
        return "", false, tostring(encoded)
    end
    return encoded, true
end

local function setOptionValue(option, saved)
    if type(option) ~= "table" or type(saved) ~= "table" then
        return true
    end

    local kind = option.Type or saved.Type
    local value = saved.Value

    if kind == "ColorPicker" then
        if type(value) ~= "table" then
            return false
        end
        local hex = tostring(value.Color or "ffffff"):gsub("#", "")
        local ok, color = pcall(Color3.fromHex, hex)
        if not ok then
            return false
        end
        if type(option.SetValue) == "function" then
            pcall(function()
                option:SetValue(color, tonumber(value.Transparency) or 0)
            end)
        elseif type(option.SetValueRGB) == "function" then
            pcall(function()
                option:SetValueRGB(color, tonumber(value.Transparency) or 0)
            end)
        end
        return true
    end

    if kind == "KeyPicker" then
        if type(value) == "table" and type(option.SetValue) == "function" then
            local ok = pcall(function()
                option:SetValue({
                    tostring(value.Key or "None"),
                    tostring(value.Mode or "Toggle"),
                })
            end)
            option.Toggled = value.Toggled == true
            return ok
        end
        return false
    end

    if type(option.SetValue) ~= "function" then
        return false
    end

    local ok = pcall(function()
        option:SetValue(value)
    end)
    return ok
end

function SaveManager:Save(name)
    name = sanitizeName(name or self.DefaultConfig)
    if not name then
        return false, "Invalid config name"
    end

    local folderOk, folderErr = self:BuildFolderTree()
    if not folderOk then
        return false, folderErr
    end

    local path = self:_getConfigPath(name)
    local json, encoded, encodeError = self:SaveJSON()
    if not encoded then
        return false, encodeError
    end

    local ok, err = callFile("writefile", path, json)
    if not ok then
        return false, err
    end
    return true
end

function SaveManager:Load(name)
    if type(name) ~= "string" or trim(name) == "" then
        return false, "No config selected"
    end
    name = sanitizeName(name)
    local path = self:_getConfigPath(name)
    if not path or not fileExists(path) then
        return false, "Config does not exist"
    end
    local ok, content = callFile("readfile", path)
    if not ok or type(content) ~= "string" then
        return false, content
    end

    local decodeOk, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not decodeOk or type(data) ~= "table" then
        return false, "Invalid config JSON"
    end

    local objects = data.objects or data
    if type(objects) ~= "table" then
        return false, "Invalid config object table"
    end

    for index, saved in pairs(objects) do
        if not self:_isIgnored(index) then
            local options = self.Library and self.Library.Options or {}
            local toggles = self.Library and self.Library.Toggles or {}
            local option = options[index] or toggles[index]
            if option then
                pcall(setOptionValue, option, saved)
            end
        end
    end

    self:UpdateConfigList()
    return true
end

function SaveManager:Delete(name)
    name = sanitizeName(name)
    local path = self:_getConfigPath(name)
    if not path or not fileExists(path) then
        return false, "Config does not exist"
    end
    local ok, err = callFile("delfile", path)
    if not ok then
        return false, err
    end
    if self.Autoload == name then
        self:SaveAutoloadConfig(nil)
    end
    self:UpdateConfigList()
    return true
end

function SaveManager:GetAutoloadConfig()
    if type(self.Autoload) == "string" and trim(self.Autoload) ~= "" then
        return self.Autoload
    end
    if type(self.AutoloadConfig) == "string" and trim(self.AutoloadConfig) ~= "" then
        return self.AutoloadConfig
    end

    local path = self:_getAutoloadPath()
    if not path or not fileExists(path) then
        return nil
    end
    local ok, value = callFile("readfile", path)
    if ok and type(value) == "string" and trim(value) ~= "" then
        self.Autoload = trim(value)
        self.AutoloadConfig = self.Autoload
        return self.Autoload
    end
    return nil
end

function SaveManager:SaveAutoloadConfig(name)
    if name == nil or (type(name) == "string" and trim(name) == "") then
        self.Autoload = nil
        self.AutoloadConfig = nil
        local path = self:_getAutoloadPath()
        if path and fileExists(path) then
            callFile("delfile", path)
        end
        return true
    end

    if type(name) ~= "string" then
        return false, "Autoload config must be a string or nil"
    end
    name = sanitizeName(name)
    if not name then
        return false, "Autoload config must not be empty"
    end

    local configPath = self:_getConfigPath(name)
    if not configPath or not fileExists(configPath) then
        return false, "Config does not exist"
    end

    local ok, err = self:BuildFolderTree()
    if not ok then
        return false, err
    end
    local path = self:_getAutoloadPath()
    ok, err = callFile("writefile", path, name)
    if not ok then
        return false, err
    end
    self.Autoload = name
    self.AutoloadConfig = name
    return true
end

function SaveManager:LoadAutoloadConfig()
    local name = self:GetAutoloadConfig()
    if type(name) ~= "string" or trim(name) == "" then
        
        
        return false, "No autoload config selected"
    end
    return self:Load(name)
end


SaveManager.LoadAutoload = SaveManager.LoadAutoloadConfig
SaveManager.SetAutoload = SaveManager.SaveAutoloadConfig

function SaveManager:UpdateConfigList()
    if not self.Library or not self.Library.Options then
        return
    end
    local option = self.Library.Options.SaveManager_ConfigList
    if option and type(option.SetValues) == "function" then
        pcall(function()
            option:SetValues(self:BuildConfigList())
        end)
    end
end

function SaveManager:BuildConfigSection(tabOrGroupbox)
    assert(self.Library, "SaveManager:SetLibrary(Library) must be called first")
    assert(tabOrGroupbox, "SaveManager:BuildConfigSection requires a tab or groupbox")

    local groupbox = tabOrGroupbox
    if type(groupbox.AddLeftGroupbox) == "function" then
        groupbox = groupbox:AddLeftGroupbox("Configs")
    end
    self.ConfigGroupbox = groupbox

    local library = self.Library
    self:BuildFolderTree()

    if type(groupbox.AddDropdown) == "function" then
        groupbox:AddDropdown("SaveManager_ConfigList", {
            Text = "Config",
            Values = self:BuildConfigList(),
            Default = self.DefaultConfig,
            AllowNull = true,
        })
    end

    if type(groupbox.AddInput) == "function" then
        groupbox:AddInput("SaveManager_ConfigName", {
            Text = "Config name",
            Default = self.DefaultConfig,
            Placeholder = "Config name",
        })
    end

    if type(groupbox.AddToggle) == "function" and not (library.Toggles and library.Toggles.SaveManager_Autoload) then
        groupbox:AddToggle("SaveManager_Autoload", {
            Text = "Autoload selected",
            Default = self:GetAutoloadConfig() ~= nil,
            Callback = function(value)
                local option = library.Options.SaveManager_ConfigList
                local selected = option and option.Value
                if value then
                    local ok, err = self:SaveAutoloadConfig(selected)
                    if not ok and type(library.Notify) == "function" then
                        library:Notify("Autoload: " .. tostring(err), 3)
                    end
                else
                    self:SaveAutoloadConfig(nil)
                end
            end,
        })
    end

    if type(groupbox.AddButton) == "function" then
        groupbox:AddButton("Save config", function()
            local input = library.Options.SaveManager_ConfigName
            local name = input and input.Value or self.DefaultConfig
            local ok, err = self:Save(name)
            if not ok and type(library.Notify) == "function" then
                library:Notify("Save: " .. tostring(err), 3)
            end
        end)
        groupbox:AddButton("Load config", function()
            local selection = library.Options.SaveManager_ConfigList
            local name = selection and selection.Value
            local ok, err = self:Load(name)
            if not ok and type(library.Notify) == "function" then
                library:Notify("Load: " .. tostring(err), 3)
            end
        end)
        groupbox:AddButton("Delete config", function()
            local selection = library.Options.SaveManager_ConfigList
            local name = selection and selection.Value
            local ok, err = self:Delete(name)
            if not ok and type(library.Notify) == "function" then
                library:Notify("Delete: " .. tostring(err), 3)
            end
        end)
        groupbox:AddButton("Refresh configs", function()
            self:UpdateConfigList()
        end)
        groupbox:AddButton("Load autoload", function()
            local ok, err = self:LoadAutoloadConfig()
            if not ok and type(library.Notify) == "function" then
                library:Notify("Autoload: " .. tostring(err), 3)
            end
        end)
    end

    return groupbox
end

return SaveManager
