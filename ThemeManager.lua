



local HttpService = game:GetService("HttpService")

local ThemeManager = {
    Library = nil,
    Folder = "aspect.sys",
    BuiltInThemes = {},
    DefaultThemeName = nil,
    AppliedToTab = false,
}

local SchemeIndexes = {
    "FontColor",
    "MainColor",
    "AccentColor",
    "BackgroundColor",
    "OutlineColor",
}

local function isString(value)
    return type(value) == "string" and value:gsub("%s+", "") ~= ""
end

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

local function hasFileApi(name)
    return type(getFileApi(name)) == "function"
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

local function ensureFolder(path)
    if path == "" or folderExists(path) then
        return true
    end
    local ok, result = callFile("makefolder", path)
    if ok then
        return true
    end
    return false, result
end

local function splitFolder(path)
    local parts = {}
    for part in tostring(path or ""):gmatch("[^/]+") do
        table.insert(parts, part)
    end
    return parts
end

local function ensureFolderTree(path)
    local current = ""
    for _, part in ipairs(splitFolder(path)) do
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
    local ok, value = pcall(function()
        return color:ToHex()
    end)
    if ok and type(value) == "string" then
        return value:gsub("#", "")
    end

    local r = math.floor(color.R * 255 + 0.5)
    local g = math.floor(color.G * 255 + 0.5)
    local b = math.floor(color.B * 255 + 0.5)
    return string.format("%02x%02x%02x", r, g, b)
end

local function fromHex(value, fallback)
    if type(value) ~= "string" then
        return fallback
    end
    local cleaned = value:gsub("#", "")
    if #cleaned ~= 6 or not cleaned:match("^%x%x%x%x%x%x$") then
        return fallback
    end
    local ok, result = pcall(Color3.fromHex, cleaned)
    if ok and typeof(result) == "Color3" then
        return result
    end
    return fallback
end

local function enumFontNames()
    local result = {}
    for _, item in ipairs(Enum.Font:GetEnumItems()) do
        table.insert(result, item.Name)
    end
    table.sort(result)
    return result
end

local function getCurrentFontName(library)
    local font = library and library.Font
    if typeof(font) == "EnumItem" then
        return font.Name
    end
    if typeof(font) == "Font" then
        local ok, enumItem = pcall(function()
            return font.Family
        end)
        if ok and type(enumItem) == "string" then
            return enumItem
        end
    end
    return "Code"
end

function ThemeManager:_getThemesPath()
    if not isString(self.Folder) then
        return nil
    end
    return tostring(self.Folder) .. "/themes"
end

function ThemeManager:_getThemePath(name)
    local safeName = sanitizeName(name)
    local base = self:_getThemesPath()
    if not safeName or not base then
        return nil
    end
    return base .. "/" .. safeName .. ".json"
end

function ThemeManager:_getDefaultPath()
    if not isString(self.Folder) then
        return nil
    end
    return tostring(self.Folder) .. "/default-theme.txt"
end

function ThemeManager:SetLibrary(library)
    assert(type(library) == "table", "ThemeManager:SetLibrary requires a Library table")
    self.Library = library
    library.ThemeManager = self

    library.Scheme = library.Scheme or {}
    for _, key in ipairs(SchemeIndexes) do
        if typeof(library.Scheme[key]) ~= "Color3" and typeof(library[key]) == "Color3" then
            library.Scheme[key] = library[key]
        end
    end
    if library.Scheme.Font == nil then
        library.Scheme.Font = library.Font
    end
    if library.Scheme.FontFace == nil then
        library.Scheme.FontFace = getCurrentFontName(library)
    end
    if library.Scheme.BackgroundImage == nil then
        library.Scheme.BackgroundImage = ""
    end

    return self
end

function ThemeManager:SetFolder(folder)
    folder = sanitizeName(folder)
    if not folder then
        return false, "Invalid theme folder"
    end
    self.Folder = folder
    return self:BuildFolderTree()
end

function ThemeManager:BuildFolderTree()
    local root = self.Folder
    local themes = self:_getThemesPath()
    if not root or not themes then
        return false, "Theme folder is not configured"
    end
    if not hasFileApi("makefolder") then
        return false, "Executor file APIs are unavailable"
    end
    local ok, err = ensureFolderTree(root)
    if not ok then
        return false, err
    end
    ok, err = ensureFolderTree(themes)
    if not ok then
        return false, err
    end
    return true
end

ThemeManager.CheckFolderTree = ThemeManager.BuildFolderTree

function ThemeManager:LoadBuiltInThemes()
    if next(self.BuiltInThemes) ~= nil then
        return self.BuiltInThemes
    end

    self.BuiltInThemes = {
        Default = {
            FontColor = "d6d6d6",
            MainColor = "141414",
            AccentColor = "d6d6d6",
            BackgroundColor = "0f0f0f",
            OutlineColor = "1f1f1f",
            BackgroundImage = "",
            FontFace = "Code",
        },
        Dark = {
            FontColor = "ffffff",
            MainColor = "202020",
            AccentColor = "5b8cff",
            BackgroundColor = "121212",
            OutlineColor = "303030",
            BackgroundImage = "",
            FontFace = "Code",
        },
        Light = {
            FontColor = "151515",
            MainColor = "e9e9e9",
            AccentColor = "5a43c7",
            BackgroundColor = "f4f4f4",
            OutlineColor = "c7c7c7",
            BackgroundImage = "",
            FontFace = "Gotham",
        },
    }
    return self.BuiltInThemes
end

function ThemeManager:GetCustomTheme(name)
    local path = self:_getThemePath(name)
    if not path or not fileExists(path) then
        return nil
    end

    local ok, content = callFile("readfile", path)
    if not ok or type(content) ~= "string" then
        return nil
    end

    local decodeOk, decoded = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not decodeOk or type(decoded) ~= "table" then
        return nil
    end
    return decoded
end

function ThemeManager:DoesThemeExist(name, includeBuiltIn)
    if includeBuiltIn == true then
        self:LoadBuiltInThemes()
        if self.BuiltInThemes[sanitizeName(name) or ""] then
            return true
        end
    end
    local path = self:_getThemePath(name)
    return path ~= nil and fileExists(path)
end

function ThemeManager:BuildThemeList()
    self:LoadBuiltInThemes()
    local result = {}
    for name in pairs(self.BuiltInThemes) do
        table.insert(result, name)
    end
    for _, name in ipairs(self:GetCustomThemes()) do
        table.insert(result, name)
    end
    table.sort(result, function(a, b)
        return a:lower() < b:lower()
    end)
    return result
end

ThemeManager.GetThemes = ThemeManager.BuildThemeList

function ThemeManager:RefreshThemeList()
    if not self.Library or not self.Library.Options then
        return self:BuildThemeList()
    end
    local option = self.Library.Options.ThemeManager_ThemeList
    local values = self:BuildThemeList()
    if option and type(option.SetValues) == "function" then
        pcall(function() option:SetValues(values) end)
    end
    return values
end

function ThemeManager:GetSelectedTheme()
    if not self.Library or not self.Library.Options then
        return nil
    end
    local option = self.Library.Options.ThemeManager_ThemeList
    if option and type(option.Value) == "string" and trim(option.Value) ~= "" then
        return option.Value
    end
    return nil
end

function ThemeManager:GetCustomThemes()
    local result = {}
    local path = self:_getThemesPath()
    if not path or not hasFileApi("listfiles") then
        return result
    end

    local ok, files = callFile("listfiles", path)
    if not ok or type(files) ~= "table" then
        return result
    end

    for _, filePath in ipairs(files) do
        if type(filePath) == "string" and filePath:lower():sub(-5) == ".json" then
            local name = filePath:match("([^/\\]+)%.json$")
            if name and name:lower() ~= "default" then
                table.insert(result, name)
            end
        end
    end
    table.sort(result, function(a, b) return a:lower() < b:lower() end)
    return result
end

ThemeManager.ReloadCustomThemes = ThemeManager.RefreshThemeList

function ThemeManager:BuildCurrentThemeData()
    assert(self.Library, "Library is not set, call ThemeManager:SetLibrary(Library) first.")
    local library = self.Library
    local data = {
        FontFace = getCurrentFontName(library),
        BackgroundImage = tostring((library.Scheme and library.Scheme.BackgroundImage) or ""),
    }

    for _, key in ipairs(SchemeIndexes) do
        local value = library.Options and library.Options[key] and library.Options[key].Value
        if typeof(value) ~= "Color3" then
            value = library.Scheme and library.Scheme[key] or library[key]
        end
        data[key] = toHex(value)
    end

    return data
end

function ThemeManager:SaveJSON()
    local data = self:BuildCurrentThemeData()
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode(data)
    end)
    if not ok then
        return "", false, tostring(encoded)
    end
    return encoded, true
end

function ThemeManager:_applyFont(name)
    if type(name) ~= "string" then
        return
    end
    local enumFont = Enum.Font[name]
    if enumFont and self.Library and type(self.Library.SetFont) == "function" then
        pcall(function()
            self.Library:SetFont(enumFont)
        end)
    end
    if self.Library and self.Library.Scheme then
        self.Library.Scheme.FontFace = name
    end
end

function ThemeManager:ThemeUpdate()
    if not self.Library then
        return false, "Library is not set"
    end

    local library = self.Library
    library.Scheme = library.Scheme or {}
    for _, key in ipairs(SchemeIndexes) do
        local option = library.Options and library.Options[key]
        if option and typeof(option.Value) == "Color3" then
            library.Scheme[key] = option.Value
            library[key] = option.Value
        end
    end

    if type(library.UpdateColorsUsingRegistry) == "function" then
        local ok, err = pcall(function()
            library:UpdateColorsUsingRegistry()
        end)
        if not ok then
            return false, err
        end
    end

    return true
end

function ThemeManager:ApplyThemeData(themeData)
    if type(themeData) ~= "table" then
        return false, "Invalid theme data"
    end
    if not self.Library then
        return false, "Library is not set"
    end

    local library = self.Library
    library.Scheme = library.Scheme or {}

    for _, key in ipairs(SchemeIndexes) do
        local fallback = library.Scheme[key] or library[key]
        local color = fromHex(themeData[key], fallback)
        if color then
            library.Scheme[key] = color
            library[key] = color
            local option = library.Options and library.Options[key]
            if option and type(option.SetValue) == "function" then
                pcall(function() option:SetValue(color) end)
            end
        end
    end

    if type(themeData.FontFace) == "string" and Enum.Font[themeData.FontFace] then
        self:_applyFont(themeData.FontFace)
    end

    if type(themeData.BackgroundImage) == "string" then
        library.Scheme.BackgroundImage = themeData.BackgroundImage
        if type(library.SetBackgroundImage) == "function" then
            pcall(function()
                library:SetBackgroundImage(themeData.BackgroundImage)
            end)
        end
    end

    local ok, err = self:ThemeUpdate()
    if not ok then
        return false, err
    end
    return true
end

function ThemeManager:ApplyTheme(name)
    name = sanitizeName(name)
    if not name then
        return false, "No theme is selected"
    end

    self:LoadBuiltInThemes()
    local data = self:GetCustomTheme(name) or self.BuiltInThemes[name]
    if not data then
        return false, "Theme not found"
    end
    local ok, err = self:ApplyThemeData(data)
    if ok then
        local option = self.Library and self.Library.Options and self.Library.Options.ThemeManager_ThemeList
        if option and type(option.SetValue) == "function" then
            pcall(function() option:SetValue(name) end)
        end
    end
    return ok, err
end

function ThemeManager:SaveCustomTheme(name)
    name = sanitizeName(name)
    if not name or name:lower() == "default" then
        return false, "Invalid theme name"
    end
    local path = self:_getThemePath(name)
    if not path then
        return false, "Invalid theme path"
    end
    local ok, err = self:BuildFolderTree()
    if not ok then
        return false, err
    end

    local json, encoded, encodeError = self:SaveJSON()
    if not encoded then
        return false, encodeError
    end
    local writeOk, writeError = callFile("writefile", path, json)
    if not writeOk then
        return false, writeError
    end
    self:RefreshThemeList()
    return true
end

function ThemeManager:Delete(name)
    name = sanitizeName(name)
    local path = self:_getThemePath(name)
    if not path or not fileExists(path) then
        return false, "Theme file does not exist"
    end
    local ok, err = callFile("delfile", path)
    if not ok then
        return false, err
    end

    if self.DefaultThemeName == name then
        self:DeleteDefaultTheme()
    end
    self:RefreshThemeList()
    return true
end

function ThemeManager:GetDefaultTheme()
    local path = self:_getDefaultPath()
    if not path or not fileExists(path) then
        return "none", false, "Default theme is not set"
    end
    local ok, value = callFile("readfile", path)
    if not ok or type(value) ~= "string" then
        return "none", false, value
    end
    local name = sanitizeName(value)
    if not name or not self:DoesThemeExist(name, true) then
        return "none", false, "Theme file not found"
    end
    self.DefaultThemeName = name
    return name, true
end

function ThemeManager:SetDefaultTheme(theme)
    local path = self:_getDefaultPath()
    local name = sanitizeName(theme)
    if not path then
        return false, "Invalid theme path"
    end
    if not name then
        self.DefaultThemeName = nil
        if fileExists(path) then
            callFile("delfile", path)
        end
        return true
    end
    if not self:DoesThemeExist(name, true) then
        return false, "Theme not found"
    end
    local ok, err = self:BuildFolderTree()
    if not ok then
        return false, err
    end
    ok, err = callFile("writefile", path, name)
    if not ok then
        return false, err
    end
    self.DefaultThemeName = name
    return true
end

function ThemeManager:DeleteDefaultTheme()
    local path = self:_getDefaultPath()
    self.DefaultThemeName = nil
    if path and fileExists(path) then
        return callFile("delfile", path)
    end
    return true
end

function ThemeManager:LoadJSON(content)
    if not isString(content) then
        return false, "No JSON provided"
    end
    local ok, data = pcall(function()
        return HttpService:JSONDecode(content)
    end)
    if not ok or type(data) ~= "table" then
        return false, "Invalid theme JSON"
    end
    return self:ApplyThemeData(data)
end

local function addColorPicker(groupbox, library, key, label)
    if not groupbox or type(groupbox.AddLabel) ~= "function" then
        return
    end
    local row = groupbox:AddLabel(label)
    if row and type(row.AddColorPicker) == "function" then
        row:AddColorPicker("ThemeManager_" .. key, {
            Default = library.Scheme[key] or library[key],
            Title = label,
        })
        local option = library.Options and library.Options["ThemeManager_" .. key]
        if option and type(option.OnChanged) == "function" then
            option:OnChanged(function(value)
                if typeof(value) == "Color3" then
                    library.Scheme[key] = value
                    library[key] = value
                    if type(library.UpdateColorsUsingRegistry) == "function" then
                        pcall(function() library:UpdateColorsUsingRegistry() end)
                    end
                end
            end)
        end
    end
end

function ThemeManager:CreateThemeManager(groupbox)
    assert(self.Library, "ThemeManager:SetLibrary(Library) must be called first")
    assert(groupbox, "ThemeManager:CreateThemeManager requires a groupbox")

    self:LoadBuiltInThemes()
    local library = self.Library
    self.AppliedToTab = true

    if type(groupbox.AddDropdown) == "function" and not (library.Options and library.Options.ThemeManager_ThemeList) then
        local defaultTheme = self:GetDefaultTheme()
        local defaultName = type(defaultTheme) == "string" and defaultTheme or "Default"
        groupbox:AddDropdown("ThemeManager_ThemeList", {
            Text = "Themes",
            Values = self:BuildThemeList(),
            Default = defaultName,
            AllowNull = true,
            Callback = function(value)
                if type(value) ~= "string" or trim(value) == "" then
                    return
                end
            end,
        })
    end

    for _, key in ipairs(SchemeIndexes) do
        addColorPicker(groupbox, library, key, key)
    end

    local fontOptions = enumFontNames()
    if type(groupbox.AddDropdown) == "function" and #fontOptions > 0 then
        local font = groupbox:AddDropdown("ThemeManager_FontFace", {
            Text = "Font",
            Values = fontOptions,
            Default = getCurrentFontName(library),
        })
        if font and type(font.OnChanged) == "function" then
            font:OnChanged(function(value)
                self:_applyFont(value)
            end)
        end
    end

    if type(groupbox.AddInput) == "function" then
        groupbox:AddInput("ThemeManager_ThemeName", {
            Text = "Theme name",
            Default = "MyTheme",
            Placeholder = "Theme name",
        })
        groupbox:AddInput("ThemeManager_BackgroundImage", {
            Text = "Background image",
            Default = tostring(library.Scheme.BackgroundImage or ""),
            Placeholder = "Asset URL / rbxasset id",
        })
        local bg = library.Options and library.Options.ThemeManager_BackgroundImage
        if bg and type(bg.OnChanged) == "function" then
            bg:OnChanged(function(value)
                library.Scheme.BackgroundImage = tostring(value or "")
                if type(library.SetBackgroundImage) == "function" then
                    pcall(function() library:SetBackgroundImage(library.Scheme.BackgroundImage) end)
                end
            end)
        end
    end

    if type(groupbox.AddButton) == "function" then
        groupbox:AddButton("Apply selected theme", function()
            local listOption = library.Options and library.Options.ThemeManager_ThemeList
            local nameOption = library.Options and library.Options.ThemeManager_ThemeName
            local name = (listOption and listOption.Value) or (nameOption and nameOption.Value)
            if type(name) == "string" and name ~= "" then
                local ok, err = self:ApplyTheme(name)
                if not ok and type(library.Notify) == "function" then
                    library:Notify("Theme: " .. tostring(err), 3)
                end
            end
        end)
        groupbox:AddButton("Save custom theme", function()
            local listOption = library.Options and library.Options.ThemeManager_ThemeList
            local nameOption = library.Options and library.Options.ThemeManager_ThemeName
            local name = (listOption and listOption.Value) or (nameOption and nameOption.Value)
            local ok, err = self:SaveCustomTheme(name)
            if not ok and type(library.Notify) == "function" then
                library:Notify("Theme save: " .. tostring(err), 3)
            end
        end)
        groupbox:AddButton("Delete custom theme", function()
            local listOption = library.Options and library.Options.ThemeManager_ThemeList
            local nameOption = library.Options and library.Options.ThemeManager_ThemeName
            local name = (listOption and listOption.Value) or (nameOption and nameOption.Value)
            local ok, err = self:Delete(name)
            if not ok and type(library.Notify) == "function" then
                library:Notify("Theme delete: " .. tostring(err), 3)
            end
        end)
        groupbox:AddButton("Set as default theme", function()
            local listOption = library.Options and library.Options.ThemeManager_ThemeList
            local nameOption = library.Options and library.Options.ThemeManager_ThemeName
            local name = (listOption and listOption.Value) or (nameOption and nameOption.Value)
            local ok, err = self:SetDefaultTheme(name)
            if not ok and type(library.Notify) == "function" then
                library:Notify("Theme default: " .. tostring(err), 3)
            end
        end)
        groupbox:AddButton("Clear default theme", function()
            self:DeleteDefaultTheme()
        end)
    end

    return self
end

return ThemeManager
