--[[
    aspect.sys LinoriaPlus

    Base: official LinoriaLib
    Compatibility layer: only documented Obsidian-style helpers.

    Linoria remains the renderer and native control implementation.
    addons/ThemeManager.lua and addons/SaveManager.lua are local compatibility
    managers that use this bridge without fetching external source at runtime.
]]

local BASE_URL = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/Library.lua"
local VERSION = "5.1.8"

local env = (type(getgenv) == "function" and getgenv()) or (type(shared) == "table" and shared) or {}
local Previous = rawget(env, "LinoriaPlus")

if Previous and Previous.__AspectSysLinoriaPlusVersion == VERSION and not Previous.__AspectSysUnloaded then
    return Previous
end

if Previous and type(Previous.Unload) == "function" then
    pcall(function()
        Previous:Unload()
    end)
end

local function loadSource(url, name)
    local cacheKey = "__AspectSysLinoriaBaseSource_" .. VERSION
    local source = rawget(env, cacheKey)

    if type(source) ~= "string" or source == "" then
        local ok, fetched = pcall(function()
            return game:HttpGet(url)
        end)
        assert(ok and type(fetched) == "string" and fetched ~= "", "LinoriaPlus: failed to fetch " .. tostring(name))
        source = fetched
        pcall(function()
            env[cacheKey] = source
        end)
    end

    local chunk, compileError = loadstring(source)
    assert(chunk, "LinoriaPlus: " .. tostring(name) .. " compile error: " .. tostring(compileError))

    local ran, result = pcall(chunk)
    assert(ran, "LinoriaPlus: " .. tostring(name) .. " runtime error: " .. tostring(result))
    return result
end

local Library = loadSource(BASE_URL, "LinoriaLib")
assert(type(Library) == "table", "LinoriaPlus: LinoriaLib did not return a table")

local InputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer

Library.__AspectSysLinoriaPlusVersion = VERSION
Library.__AspectSysLinoriaPlusBase = "LinoriaLib"
Library.__AspectSysLinoriaBase = "LinoriaLib"
Library.LocalPlayer = Library.LocalPlayer or LocalPlayer

-- Linoria owns these tables. Reuse them instead of creating a second registry.
env.Options = Library.Options or env.Options or {}
env.Toggles = Library.Toggles or env.Toggles or {}
Library.Options = env.Options
Library.Toggles = env.Toggles

-- Defensive wrappers around a few Linoria primitives. These are intentionally
-- small: the upstream renderer still owns the real implementations, but a bad
-- nil/custom object must not bring down a large script during UI construction.
do
    local originalCreate = Library.Create
    if type(originalCreate) == "function" and not Library.__AspectSysCreateHardened then
        Library.__AspectSysCreateHardened = true
        Library.Create = function(self, className, properties, ...)
            if type(properties) ~= "table" then
                properties = {}
            end
            return originalCreate(self, className, properties, ...)
        end
    end

    local originalAddToRegistry = Library.AddToRegistry
    if type(originalAddToRegistry) == "function" and not Library.__AspectSysRegistryHardened then
        Library.__AspectSysRegistryHardened = true
        Library.AddToRegistry = function(self, instance, properties, isHud, ...)
            if instance == nil then
                return nil
            end
            if type(properties) ~= "table" then
                properties = {}
            end
            return originalAddToRegistry(self, instance, properties, isHud, ...)
        end
    end

    local originalGiveSignal = Library.GiveSignal
    if type(originalGiveSignal) == "function" and not Library.__AspectSysSignalHardened then
        Library.__AspectSysSignalHardened = true
        Library.GiveSignal = function(self, connection, ...)
            if connection == nil then
                return nil
            end
            local ok, disconnectMethod = pcall(function()
                return connection.Disconnect
            end)
            if not ok or type(disconnectMethod) ~= "function" then
                return nil
            end
            return originalGiveSignal(self, connection, ...)
        end
    end
end

local function callSafe(func, ...)
    if type(func) ~= "function" then
        return
    end
    if type(Library.SafeCallback) == "function" then
        return Library:SafeCallback(func, ...)
    end
    return func(...)
end

local function make(className, properties)
    properties = properties or {}
    local instance = Library:Create(className, properties)
    local parent = properties.Parent
    if Library.ScreenGui and parent == Library.ScreenGui and instance and instance.IsA and instance:IsA("GuiObject") then
        local scale = Library.DPIScale or 1
        local uiScale = instance:FindFirstChild("LinoriaPlusUIScale")
        if not uiScale then
            uiScale = Instance.new("UIScale")
            uiScale.Name = "LinoriaPlusUIScale"
            uiScale.Parent = instance
        end
        uiScale.Scale = scale
    end
    return instance
end

local function registerTheme(instance, properties, isHud)
    if not instance or type(Library.AddToRegistry) ~= "function" or type(properties) ~= "table" then
        return
    end
    pcall(function()
        Library:AddToRegistry(instance, properties, isHud == true)
    end)
end

local function normalizeAsset(value)
    if value == nil then
        return ""
    end

    if typeof(value) == "number" then
        return "rbxassetid://" .. tostring(value)
    end

    local text = tostring(value)
    if text:match("^%d+$") then
        return "rbxassetid://" .. text
    end

    return text
end

local function applyIcon(imageObject, value)
    local custom = nil
    if type(Library.GetCustomIcon) == "function" and value ~= nil then
        local ok, result = pcall(function()
            return Library:GetCustomIcon(value)
        end)
        if ok then
            custom = result
        end
    end

    if type(custom) == "table" and custom.Url then
        imageObject.Image = custom.Url
        if custom.ImageRectOffset then
            imageObject.ImageRectOffset = custom.ImageRectOffset
        end
        if custom.ImageRectSize then
            imageObject.ImageRectSize = custom.ImageRectSize
        end
    else
        imageObject.Image = normalizeAsset(value)
    end
end

local function disconnect(connection)
    if connection and connection.Connected then
        connection:Disconnect()
    end
end

local function safeDestroy(instance)
    if instance then
        pcall(function()
            instance:Destroy()
        end)
    end
end

local function normalizeGroupboxVisualState(groupbox)
    if type(groupbox) ~= "table" then
        return groupbox
    end

    local container = groupbox.Container
    local outer = container and container.Parent and container.Parent.Parent

    if outer and outer:IsA("GuiObject") then
        local visible = groupbox.__AspectSysVisible
        if visible == nil then
            visible = groupbox.Visible ~= false
        end
        outer.Visible = visible == true

        if groupbox.__AspectSysCollapsed == true then
            if container:IsA("GuiObject") then
                container.Visible = false
            end
        elseif groupbox.__AspectSysCollapsed == false then
            if container:IsA("GuiObject") then
                container.Visible = true
            end
        end
    end

    return groupbox
end

local function giveSignal(connection)
    if connection and type(Library.GiveSignal) == "function" then
        Library:GiveSignal(connection)
    end
    return connection
end

local function install(object, name, method)
    if type(object) ~= "table" then
        return false
    end

    if type(object[name]) == "function" then
        return false
    end

    pcall(function()
        object[name] = method
    end)

    local mt = getmetatable(object)
    local index = mt and mt.__index
    if type(index) == "table" and type(index[name]) ~= "function" then
        pcall(function()
            index[name] = method
        end)
    end

    return type(object[name]) == "function"
end

local function addToElements(groupbox, element)
    if type(groupbox.Elements) ~= "table" then
        groupbox.Elements = {}
    end
    if element ~= nil then
        table.insert(groupbox.Elements, element)
    end
end

local function removeFromElements(groupbox, element)
    if type(groupbox.Elements) ~= "table" then
        return
    end
    local index = table.find(groupbox.Elements, element)
    if index then
        table.remove(groupbox.Elements, index)
    end
end

---------------------------------------------------------------------
-- Dependency boxes.
--
-- Some Linoria releases document AddDependencyBox/SetupDependencies in their
-- example but do not ship the helper in Library.lua. LinoriaPlus provides the
-- helper locally and keeps it compatible with normal groupbox controls.
---------------------------------------------------------------------

Library.DependencyBoxes = type(Library.DependencyBoxes) == "table" and Library.DependencyBoxes or {}

local function resolveDependencyControl(control)
    if type(control) == "string" then
        return (Library.Toggles and Library.Toggles[control])
            or (Library.Options and Library.Options[control])
    end
    return control
end

local function dependencyMatches(control, expected)
    control = resolveDependencyControl(control)
    if type(control) ~= "table" then
        return false
    end

    if type(expected) == "function" then
        local ok, value = pcall(expected, control.Value, control)
        return ok and value == true
    end

    if type(control.GetState) == "function" and type(expected) == "boolean" then
        local ok, state = pcall(function()
            return control:GetState()
        end)
        if ok then
            return state == expected
        end
    end

    local value = control.Value
    if type(value) == "table" then
        if type(expected) == "string" then
            return value[expected] == true
        end
        if type(expected) == "table" then
            for key, wanted in pairs(expected) do
                if wanted == true and value[key] ~= true then
                    return false
                end
            end
            return true
        end
    end

    if expected == nil then
        return value ~= nil
    end

    return value == expected
end

local function installDependencyBox(groupbox)
    if type(groupbox) ~= "table" or type(groupbox.Container) ~= "userdata" then
        return groupbox
    end

    if type(groupbox.DependencyBoxes) ~= "table" then
        groupbox.DependencyBoxes = {}
    end

    if type(groupbox.AddDependencyBox) == "function" then
        return groupbox
    end

    local parentGroupbox = groupbox

    groupbox.AddDependencyBox = function(self)
        local container = make("Frame", {
            Name = "LinoriaPlusDependencyBox",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 0),
            Visible = false,
            Parent = self.Container,
        })

        local layout = make("UIListLayout", {
            FillDirection = Enum.FillDirection.Vertical,
            SortOrder = Enum.SortOrder.LayoutOrder,
            Padding = UDim.new(0, 8),
            Parent = container,
        })

        local depbox = {
            Visible = false,
            Dependencies = {},
            Holder = container,
            Container = container,
            Elements = {},
            DependencyBoxes = {},
            ParentGroupbox = self,
            __AspectSysDependencyHardened = true,
        }

        local mt = getmetatable(self)
        if mt then
            pcall(function() setmetatable(depbox, mt) end)
        end

        function depbox:Resize()
            local height = 0
            pcall(function()
                height = math.max(0, layout.AbsoluteContentSize.Y)
            end)

            local scale = tonumber(Library.DPIScale) or 1
            if scale <= 0 then
                scale = 1
            end
            container.Size = UDim2.new(1, 0, 0, height / scale)

            if self.Visible ~= true then
                container.Visible = false
                container.Size = UDim2.new(1, 0, 0, 0)
            else
                container.Visible = true
            end

            if self.ParentGroupbox and type(self.ParentGroupbox.Resize) == "function" then
                pcall(function()
                    self.ParentGroupbox:Resize()
                end)
            end
            return self
        end

        function depbox:Update()
            local visible = true
            for _, dependency in ipairs(self.Dependencies or {}) do
                if type(dependency) ~= "table" then
                    visible = false
                    break
                end

                local control = dependency[1] or dependency.Control or dependency.Option or dependency.Toggle
                local expected = dependency[2]
                if dependency.Expected ~= nil then
                    expected = dependency.Expected
                end

                if not dependencyMatches(control, expected) then
                    visible = false
                    break
                end
            end

            self.Visible = visible
            container.Visible = visible
            self:Resize()

            for _, nested in pairs(self.DependencyBoxes or {}) do
                if type(nested.Update) == "function" then
                    pcall(function() nested:Update() end)
                end
            end

            return self
        end

        function depbox:SetupDependencies(dependencies)
            if dependencies == nil then
                dependencies = {}
            end
            assert(type(dependencies) == "table", "SetupDependencies expects a table or nil")
            self.Dependencies = dependencies

            self.__AspectSysDependencyBindings = self.__AspectSysDependencyBindings or {}
            for _, dependency in ipairs(dependencies) do
                if type(dependency) == "table" then
                    local control = resolveDependencyControl(dependency[1] or dependency.Control or dependency.Option or dependency.Toggle)
                    if type(control) == "table" and not self.__AspectSysDependencyBindings[control]
                        and type(control.OnChanged) == "function" then
                        local callback = function()
                            if self.Holder and self.Holder.Parent then
                                self:Update()
                            end
                        end
                        local ok = pcall(function() control:OnChanged(callback) end)
                        if ok then
                            self.__AspectSysDependencyBindings[control] = true
                        end
                    end
                end
            end

            self:Update()
            return self
        end

        function depbox:SetDependencies(dependencies)
            return self:SetupDependencies(dependencies)
        end

        function depbox:GetDependencies()
            return self.Dependencies
        end

        function depbox:Show()
            self.Visible = true
            container.Visible = true
            return self:Resize()
        end

        function depbox:Hide()
            self.Visible = false
            container.Visible = false
            return self:Resize()
        end

        giveSignal(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            if depbox.Visible == true then
                depbox:Resize()
            end
        end))

        -- Dependency boxes are themselves valid groupboxes. Install the same
        -- helper recursively so nested dependency boxes work instead of
        -- stopping script execution with an `AddDependencyBox` nil-call.
        installDependencyBox(depbox)

        table.insert(self.DependencyBoxes, depbox)
        table.insert(Library.DependencyBoxes, depbox)

        depbox:Update()
        return depbox
    end

    return groupbox
end

---------------------------------------------------------------------
-- Linoria theme bridge for the official Obsidian ThemeManager.
---------------------------------------------------------------------

local originalUpdateColors = Library.UpdateColorsUsingRegistry
local originalSetFont = Library.SetFont
local originalSetBackgroundImage = Library.SetBackgroundImage

Library.Scheme = Library.Scheme or {
    FontColor = Library.FontColor,
    MainColor = Library.MainColor,
    AccentColor = Library.AccentColor,
    BackgroundColor = Library.BackgroundColor,
    OutlineColor = Library.OutlineColor,
    Font = Library.Font,
    BackgroundImage = "",
}

local function syncSchemeToLinoria()
    local scheme = Library.Scheme or {}
    local colorKeys = {
        "FontColor",
        "MainColor",
        "AccentColor",
        "BackgroundColor",
        "OutlineColor",
    }

    for _, key in ipairs(colorKeys) do
        if typeof(scheme[key]) == "Color3" then
            Library[key] = scheme[key]
        end
    end

    if scheme.Font ~= nil then
        Library.Font = scheme.Font
    end
end

if not Library.__AspectSysThemeBridge then
    Library.__AspectSysThemeBridge = true

    Library.UpdateColorsUsingRegistry = function(self, ...)
        syncSchemeToLinoria()
        if type(originalUpdateColors) == "function" then
            local result = originalUpdateColors(self, ...)
            if type(self.GetDarkerColor) == "function" and typeof(self.AccentColor) == "Color3" then
                self.AccentColorDark = self:GetDarkerColor(self.AccentColor)
            end
            return result
        end
        if type(self.GetDarkerColor) == "function" and typeof(self.AccentColor) == "Color3" then
            self.AccentColorDark = self:GetDarkerColor(self.AccentColor)
        end
    end

    Library.SetFont = function(self, font, ...)
        local extraArgs = {...}
        if font ~= nil then
            self.Font = font
            self.Scheme.Font = font
        end

        if type(originalSetFont) == "function" then
            pcall(function()
                originalSetFont(self, font, table.unpack(extraArgs))
            end)
        end

        if self.ScreenGui then
            for _, instance in ipairs(self.ScreenGui:GetDescendants()) do
                if instance:IsA("TextLabel") or instance:IsA("TextButton") or instance:IsA("TextBox") then
                    instance.Font = self.Font
                end
            end
        end

        return self
    end

    Library.SetBackgroundImage = function(self, image, ...)
        local extraArgs = {...}
        local value = tostring(image or "")
        self.Scheme.BackgroundImage = value

        if type(originalSetBackgroundImage) == "function" then
            pcall(function()
                originalSetBackgroundImage(self, value, table.unpack(extraArgs))
            end)
        end

        if self.Window and type(self.Window.SetBackgroundImage) == "function" then
            pcall(function()
                self.Window:SetBackgroundImage(value)
            end)
        end

        return self
    end
end

syncSchemeToLinoria()

---------------------------------------------------------------------
-- Groupbox media helpers.
---------------------------------------------------------------------

local function addImage(groupbox, index, info)
    info = type(info) == "table" and info or {}

    local holder = make("Frame", {
        Name = "LinoriaPlusImage_" .. tostring(index),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, tonumber(info.Height) or 100),
        Visible = info.Visible ~= false,
        ZIndex = 5,
        Parent = groupbox.Container,
    })

    local image = make("ImageLabel", {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        Image = normalizeAsset(info.Image or info.Asset or ""),
        ImageColor3 = typeof(info.Color) == "Color3" and info.Color or Color3.new(1, 1, 1),
        ImageTransparency = tonumber(info.Transparency) or 0,
        ScaleType = info.ScaleType or Enum.ScaleType.Fit,
        ZIndex = 6,
        Parent = holder,
    })

    local object = {
        Holder = holder,
        Image = image,
        Type = "Image",
        Visible = info.Visible ~= false,
    }

    function object:SetHeight(value)
        holder.Size = UDim2.new(1, 0, 0, math.max(0, tonumber(value) or 0))
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function object:SetImage(value)
        applyIcon(image, value)
        return self
    end

    function object:SetColor(value)
        if typeof(value) == "Color3" then
            image.ImageColor3 = value
        end
        return self
    end

    function object:SetRectOffset(value)
        if typeof(value) == "Vector2" then
            image.ImageRectOffset = value
        end
        return self
    end

    function object:SetRectSize(value)
        if typeof(value) == "Vector2" then
            image.ImageRectSize = value
        end
        return self
    end

    function object:SetScaleType(value)
        image.ScaleType = value
        return self
    end

    function object:SetTransparency(value)
        image.ImageTransparency = math.clamp(tonumber(value) or 0, 0, 1)
        return self
    end

    function object:SetVisible(value)
        self.Visible = value == true
        holder.Visible = self.Visible
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function object:Destroy()
        if holder then
            holder:Destroy()
        end
        removeFromElements(groupbox, self)
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
    end

    addToElements(groupbox, object)
    if type(groupbox.Resize) == "function" then
        groupbox:Resize()
    end

    return object
end

local function getViewportPivot(instance)
    if instance:IsA("BasePart") then
        return instance.CFrame
    end
    if instance:IsA("Model") then
        return instance:GetPivot()
    end
    return CFrame.new()
end

local function getViewportSize(instance)
    if instance:IsA("BasePart") then
        return instance.Size
    end
    if instance:IsA("Model") then
        local _, size = instance:GetBoundingBox()
        return size
    end
    return Vector3.new(4, 4, 4)
end

local function addViewport(groupbox, index, info)
    info = type(info) == "table" and info or {}
    local sourceObject = info.Object
    assert(typeof(sourceObject) == "Instance" and (sourceObject:IsA("BasePart") or sourceObject:IsA("Model")), "AddViewport: Object must be a BasePart or Model")

    local viewportObject = sourceObject
    local ownsViewportObject = false
    if info.Clone ~= false then
        local oldArchivable = sourceObject.Archivable
        if not oldArchivable then
            sourceObject.Archivable = true
        end
        local ok, clone = pcall(function()
            return sourceObject:Clone()
        end)
        sourceObject.Archivable = oldArchivable
        if ok and clone then
            viewportObject = clone
            ownsViewportObject = true
        end
    end

    local camera = info.Camera
    local ownsCamera = false
    if not (typeof(camera) == "Instance" and camera:IsA("Camera")) then
        camera = Instance.new("Camera")
        ownsCamera = true
    end

    local holder = make("Frame", {
        Name = "LinoriaPlusViewport_" .. tostring(index),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, tonumber(info.Height) or 140),
        Visible = info.Visible ~= false,
        ZIndex = 5,
        Parent = groupbox.Container,
    })

    local frame = make("ViewportFrame", {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,
        Size = UDim2.fromScale(1, 1),
        CurrentCamera = camera,
        Ambient = Color3.fromRGB(255, 255, 255),
        LightColor = Color3.fromRGB(255, 255, 255),
        Visible = true,
        Active = info.Interactive == true,
        ZIndex = 6,
        Parent = holder,
    })
    registerTheme(frame, {
        BackgroundColor3 = "MainColor",
        BorderColor3 = "OutlineColor",
    })

    viewportObject.Parent = frame
    camera.Parent = frame

    local objectTable = {
        Holder = holder,
        Frame = frame,
        Camera = camera,
        Object = viewportObject,
        Interactive = info.Interactive == true,
        Visible = info.Visible ~= false,
        Type = "Viewport",
        OwnsObject = ownsViewportObject,
        OwnsCamera = ownsCamera,
    }

    local yaw = 0
    local pitch = 0
    local distance = nil

    local function focus()
        if not viewportObject or viewportObject.Parent ~= frame then
            return
        end
        local size = getViewportSize(viewportObject)
        local maxExtent = math.max(size.X, size.Y, size.Z, 1)
        local pivot = getViewportPivot(viewportObject).Position
        distance = distance or maxExtent * 2.4
        local rotation = CFrame.Angles(math.rad(pitch), math.rad(yaw), 0)
        camera.CFrame = CFrame.new(pivot) * rotation * CFrame.new(0, maxExtent * 0.35, distance)
        camera.Focus = CFrame.new(pivot)
    end

    function objectTable:SetObject(newObject, cloneObject)
        assert(typeof(newObject) == "Instance" and (newObject:IsA("BasePart") or newObject:IsA("Model")), "AddViewport: Object must be a BasePart or Model")

        if viewportObject and viewportObject.Parent == frame then
            if ownsViewportObject then
                pcall(function() viewportObject:Destroy() end)
            else
                viewportObject.Parent = nil
            end
        end

        viewportObject = newObject
        ownsViewportObject = false
        if cloneObject ~= false then
            local oldArchivable = newObject.Archivable
            if not oldArchivable then
                newObject.Archivable = true
            end
            local ok, clone = pcall(function()
                return newObject:Clone()
            end)
            newObject.Archivable = oldArchivable
            if ok and clone then
                viewportObject = clone
                ownsViewportObject = true
            end
        end

        objectTable.Object = viewportObject
        objectTable.OwnsObject = ownsViewportObject
        viewportObject.Parent = frame
        if info.AutoFocus ~= false then
            focus()
        end
        return self
    end

    function objectTable:SetHeight(value)
        holder.Size = UDim2.new(1, 0, 0, math.max(0, tonumber(value) or 0))
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function objectTable:Focus()
        focus()
        return self
    end

    function objectTable:SetCamera(newCamera)
        assert(typeof(newCamera) == "Instance" and newCamera:IsA("Camera"), "AddViewport: Camera must be a Camera")
        if camera and camera ~= newCamera and camera.Parent == frame then
            if ownsCamera then
                pcall(function() camera:Destroy() end)
            else
                camera.Parent = nil
            end
        end
        camera = newCamera
        ownsCamera = false
        camera.Parent = frame
        frame.CurrentCamera = camera
        objectTable.Camera = camera
        objectTable.OwnsCamera = ownsCamera
        focus()
        return self
    end

    function objectTable:SetInteractive(value)
        self.Interactive = value == true
        frame.Active = self.Interactive
        return self
    end

    function objectTable:SetVisible(value)
        self.Visible = value == true
        holder.Visible = self.Visible
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function objectTable:Destroy()
        if camera and camera.Parent == frame then
            if ownsCamera then
                pcall(function() camera:Destroy() end)
            else
                camera.Parent = nil
            end
        end
        if viewportObject and viewportObject.Parent == frame then
            if ownsViewportObject then
                pcall(function() viewportObject:Destroy() end)
            else
                viewportObject.Parent = nil
            end
        end
        if holder then
            holder:Destroy()
        end
        removeFromElements(groupbox, self)
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
    end

    giveSignal(frame.InputBegan:Connect(function(input)
        if not objectTable.Interactive then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            objectTable.__DragStart = input.Position
            objectTable.__DragYaw = yaw
            objectTable.__DragPitch = pitch
        end
    end))

    giveSignal(InputService.InputChanged:Connect(function(input)
        if not objectTable.Interactive or not objectTable.__DragStart then
            return
        end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then
            return
        end
        if not frame.Parent then
            return
        end
        local delta = input.Position - objectTable.__DragStart
        yaw = (objectTable.__DragYaw or yaw) - delta.X * 0.35
        pitch = math.clamp((objectTable.__DragPitch or pitch) + delta.Y * 0.25, -80, 80)
        focus()
    end))

    giveSignal(InputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            objectTable.__DragStart = nil
        end
    end))

    if info.AutoFocus ~= false then
        focus()
    end

    addToElements(groupbox, objectTable)
    if type(groupbox.Resize) == "function" then
        groupbox:Resize()
    end

    return objectTable
end

local function addVideo(groupbox, index, info)
    info = type(info) == "table" and info or {}

    local holder = make("Frame", {
        Name = "LinoriaPlusVideo_" .. tostring(index),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, tonumber(info.Height) or 100),
        Visible = info.Visible ~= false,
        ZIndex = 5,
        Parent = groupbox.Container,
    })

    local video = make("VideoFrame", {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,
        Size = UDim2.fromScale(1, 1),
        Video = tostring(info.Video or ""),
        Looped = info.Looped == true,
        Volume = tonumber(info.Volume) or 0.5,
        ZIndex = 6,
        Parent = holder,
    })
    registerTheme(video, {
        BackgroundColor3 = "MainColor",
        BorderColor3 = "OutlineColor",
    })

    local object = {
        Holder = holder,
        Video = video,
        Type = "Video",
        Visible = info.Visible ~= false,
    }

    function object:SetHeight(value)
        holder.Size = UDim2.new(1, 0, 0, math.max(0, tonumber(value) or 0))
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function object:SetVideo(value)
        video.Video = tostring(value or "")
        return self
    end

    function object:SetLooped(value)
        video.Looped = value == true
        return self
    end

    function object:SetVolume(value)
        video.Volume = math.clamp(tonumber(value) or 0, 0, 10)
        return self
    end

    function object:SetPlaying(value)
        video.Playing = value == true
        return self
    end

    function object:Play()
        video:Play()
        return self
    end

    function object:Pause()
        video:Pause()
        return self
    end

    function object:SetVisible(value)
        self.Visible = value == true
        holder.Visible = self.Visible
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function object:Destroy()
        if holder then
            holder:Destroy()
        end
        removeFromElements(groupbox, self)
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
    end

    if info.Playing == true then
        video:Play()
    end

    addToElements(groupbox, object)
    if type(groupbox.Resize) == "function" then
        groupbox:Resize()
    end

    return object
end

local function addUIPassthrough(groupbox, index, info)
    info = type(info) == "table" and info or {}
    local instance = info.Instance
    assert(typeof(instance) == "Instance" and instance:IsA("GuiObject"), "AddUIPassthrough: Instance must be a GuiObject")

    local holder = make("Frame", {
        Name = "LinoriaPlusPassthrough_" .. tostring(index),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, tonumber(info.Height) or 30),
        Visible = info.Visible ~= false,
        ZIndex = 5,
        Parent = groupbox.Container,
    })

    if instance:IsA("GuiButton") or instance:IsA("TextLabel") or instance:IsA("TextBox") or instance:IsA("ImageLabel") or instance:IsA("ImageButton") or instance:IsA("Frame") then
        instance.ZIndex = math.max(instance.ZIndex, 6)
    end
    instance.Parent = holder
    if info.Fill ~= false then
        instance.Position = UDim2.fromScale(0, 0)
        instance.Size = UDim2.fromScale(1, 1)
    end

    local object = {
        Holder = holder,
        Instance = instance,
        Type = "UIPassthrough",
        Visible = info.Visible ~= false,
    }

    function object:SetHeight(value)
        holder.Size = UDim2.new(1, 0, 0, math.max(0, tonumber(value) or 0))
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function object:SetInstance(newInstance, fill)
        assert(typeof(newInstance) == "Instance" and newInstance:IsA("GuiObject"), "AddUIPassthrough: Instance must be a GuiObject")
        instance.Parent = nil
        instance = newInstance
        object.Instance = newInstance
        if newInstance:IsA("GuiButton") or newInstance:IsA("TextLabel") or newInstance:IsA("TextBox") or newInstance:IsA("ImageLabel") or newInstance:IsA("ImageButton") or newInstance:IsA("Frame") then
            newInstance.ZIndex = math.max(newInstance.ZIndex, 6)
        end
        newInstance.Parent = holder
        if fill ~= false then
            newInstance.Position = UDim2.fromScale(0, 0)
            newInstance.Size = UDim2.fromScale(1, 1)
        end
        return self
    end

    function object:SetVisible(value)
        self.Visible = value == true
        holder.Visible = self.Visible
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
        return self
    end

    function object:Destroy()
        if holder then
            holder:Destroy()
        end
        removeFromElements(groupbox, self)
        if type(groupbox.Resize) == "function" then
            groupbox:Resize()
        end
    end

    addToElements(groupbox, object)
    if type(groupbox.Resize) == "function" then
        groupbox:Resize()
    end

    return object
end

---------------------------------------------------------------------
-- Groupbox / tab compatibility.
---------------------------------------------------------------------

local augmentGroupbox
local augmentTabbox
local augmentTab

augmentGroupbox = function(groupbox)
    if type(groupbox) ~= "table" then
        return groupbox
    end
    if groupbox.__AspectSysGroupboxPatched then
        return groupbox
    end
    groupbox.__AspectSysGroupboxPatched = true

    install(groupbox, "AddImage", addImage)
    install(groupbox, "AddViewport", addViewport)
    install(groupbox, "AddVideo", addVideo)
    install(groupbox, "AddUIPassthrough", addUIPassthrough)
    installDependencyBox(groupbox)

    install(groupbox, "AddCheckbox", function(self, index, info)
        return self:AddToggle(index, info)
    end)

    if type(groupbox.AddDivider) ~= "function" then
        install(groupbox, "AddDivider", function(self, marginTop, marginBottom)
            local holder = make("Frame", {
                Name = "LinoriaPlusDivider",
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 1 + (tonumber(marginTop) or 0) + (tonumber(marginBottom) or 0)),
                Parent = self.Container,
            })
            local line = make("Frame", {
                BackgroundColor3 = Library.OutlineColor,
                BorderSizePixel = 0,
                Position = UDim2.new(0, 0, 0.5, 0),
                Size = UDim2.new(1, 0, 0, 1),
                Parent = holder,
            })
            registerTheme(line, { BackgroundColor3 = "OutlineColor" })
            addToElements(self, holder)
            if type(self.Resize) == "function" then
                self:Resize()
            end
            return line
        end)
    end

    if type(groupbox.SetDescription) ~= "function" then
        install(groupbox, "SetDescription", function(self, text)
            local value = tostring(text or "")
            local label = self.__AspectSysDescription
            if not label then
                label = make("TextLabel", {
                    Name = "LinoriaPlusDescription",
                    BackgroundTransparency = 1,
                    Font = Library.Font,
                    TextColor3 = Library.FontColor,
                    TextSize = 12,
                    TextWrapped = true,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Size = UDim2.new(1, -4, 0, 16),
                    Parent = self.Container,
                })
                self.__AspectSysDescription = label
                self.Elements = self.Elements or {}
                table.insert(self.Elements, label)
                registerTheme(label, { TextColor3 = "FontColor" })
            end

            label.Text = value
            label.Visible = value ~= ""
            if type(self.Resize) == "function" then
                self:Resize()
            end
            return self
        end)
    end

    if type(groupbox.SetCollapsed) ~= "function" then
        install(groupbox, "SetCollapsed", function(self, collapsed)
            self.Collapsed = collapsed == true
            local container = self.Container
            if container then
                container.Visible = not self.Collapsed
            end
            if type(self.Resize) == "function" then
                self:Resize()
            end
            return self
        end)
    end

    if type(groupbox.ToggleCollapsed) ~= "function" then
        install(groupbox, "ToggleCollapsed", function(self)
            return self:SetCollapsed(not (self.Collapsed == true))
        end)
    end

    if type(groupbox.IsCollapsed) ~= "function" then
        install(groupbox, "IsCollapsed", function(self)
            return self.Collapsed == true
        end)
    end

    if type(groupbox.SetVisible) ~= "function" then
        install(groupbox, "SetVisible", function(self, visible)
            self.Visible = visible == true
            if self.Holder then
                self.Holder.Visible = self.Visible
            elseif self.BoxHolder then
                self.BoxHolder.Visible = self.Visible
            end
            if type(self.Resize) == "function" then
                self:Resize()
            end
            return self
        end)
    end

    if type(groupbox.Show) ~= "function" then
        install(groupbox, "Show", function(self)
            return self:SetVisible(true)
        end)
    end

    if type(groupbox.Hide) ~= "function" then
        install(groupbox, "Hide", function(self)
            return self:SetVisible(false)
        end)
    end

    if type(groupbox.AddTabbox) == "function" and not groupbox.__AspectSysAddTabboxPatched then
        groupbox.__AspectSysAddTabboxPatched = true
        local originalAddTabbox = groupbox.AddTabbox
        groupbox.AddTabbox = function(self, ...)
            local tabbox = originalAddTabbox(self, ...)
            if type(tabbox) == "table" then
                augmentTabbox(tabbox)
            end
            return tabbox
        end
    end

    return groupbox
end

augmentTabbox = function(tabbox)
    if type(tabbox) ~= "table" then
        return tabbox
    end
    if tabbox.__AspectSysTabboxPatched then
        return tabbox
    end
    tabbox.__AspectSysTabboxPatched = true

    local originalAddTab = tabbox.AddTab
    if type(originalAddTab) == "function" then
        install(tabbox, "AddTab", function(self, name, icon)
            local subTab = originalAddTab(self, name, icon)
            if type(subTab) == "table" then
                augmentGroupbox(subTab)
            end
            return subTab
        end)
    end

    return tabbox
end

augmentTab = function(tab)
    if type(tab) ~= "table" then
        return tab
    end
    if tab.__AspectSysTabPatched then
        return tab
    end
    tab.__AspectSysTabPatched = true

    local function patchGroupboxCreator(methodName)
        local original = tab[methodName]
        if type(original) ~= "function" then
            return
        end
        local marker = "__AspectSys" .. methodName .. "Patched"
        if tab[marker] then
            return
        end
        tab[marker] = true
        tab[methodName] = function(self, ...)
            local groupbox = original(self, ...)
            if type(groupbox) == "table" then
                augmentGroupbox(groupbox)
                normalizeGroupboxVisualState(groupbox)
            end
            return groupbox
        end
    end

    patchGroupboxCreator("AddGroupbox")
    patchGroupboxCreator("AddLeftGroupbox")
    patchGroupboxCreator("AddRightGroupbox")

    local function patchTabboxCreator(methodName)
        local original = tab[methodName]
        if type(original) ~= "function" then
            return
        end
        local marker = "__AspectSys" .. methodName .. "Patched"
        if tab[marker] then
            return
        end
        tab[marker] = true
        tab[methodName] = function(self, ...)
            local tabbox = original(self, ...)
            if type(tabbox) == "table" then
                augmentTabbox(tabbox)
            end
            return tabbox
        end
    end

    patchTabboxCreator("AddTabbox")
    patchTabboxCreator("AddLeftTabbox")
    patchTabboxCreator("AddRightTabbox")

    if type(tab.SetVisible) ~= "function" then
        install(tab, "SetVisible", function(self, visible)
            self.Visible = visible == true
            if self.Button then
                self.Button.Visible = self.Visible
            end
            if self.Container then
                self.Container.Visible = self.Visible
            end
            return self
        end)
    end

    if type(tab.Show) ~= "function" then
        install(tab, "Show", function(self)
            return self:SetVisible(true)
        end)
    end

    if type(tab.Hide) ~= "function" then
        install(tab, "Hide", function(self)
            return self:SetVisible(false)
        end)
    end

    if type(tab.SetOrder) ~= "function" then
        install(tab, "SetOrder", function(self, order)
            self.Order = tonumber(order) or 0
            if self.Button then
                pcall(function()
                    self.Button.LayoutOrder = self.Order
                end)
            end
            return self
        end)
    end

    if type(tab.SetTooltip) ~= "function" then
        install(tab, "SetTooltip", function(self, text)
            self.Tooltip = tostring(text or "")
            return self
        end)
    end

    if type(tab.Hover) ~= "function" then
        install(tab, "Hover", function(self, hovering)
            self.__AspectSysHovering = hovering == true
            if self.Button and self.Button:IsA("GuiButton") then
                self.Button.BackgroundTransparency = self.__AspectSysHovering and 0.82 or 1
            end
            return self
        end)
    end

    local groupboxes = tab.Groupboxes or {}
    for _, groupbox in pairs(groupboxes) do
        augmentGroupbox(groupbox)
    end

    local tabboxes = tab.Tabboxes or {}
    for _, tabbox in pairs(tabboxes) do
        augmentTabbox(tabbox)
    end

    return tab
end

---------------------------------------------------------------------
-- Window compatibility. Existing Linoria methods remain authoritative.
---------------------------------------------------------------------

local function augmentWindow(window)
    if type(window) ~= "table" then
        return window
    end
    if window.__AspectSysWindowPatched then
        return window
    end
    window.__AspectSysWindowPatched = true

    if type(window.ChangeTitle) ~= "function" and type(window.SetWindowTitle) == "function" then
        install(window, "ChangeTitle", function(self, title)
            self:SetWindowTitle(tostring(title or ""))
            return self
        end)
    end

    if type(window.SetFooter) ~= "function" then
        install(window, "SetFooter", function(self, footer)
            self.Footer = tostring(footer or "")
            local root = self.Holder
            if not root then
                return self
            end
            local label = root:FindFirstChild("LinoriaPlusFooter")
            if not label then
                label = make("TextLabel", {
                    Name = "LinoriaPlusFooter",
                    BackgroundTransparency = 1,
                    AnchorPoint = Vector2.new(1, 1),
                    Position = UDim2.new(1, -8, 1, -4),
                    Size = UDim2.fromOffset(250, 16),
                    Font = Library.Font,
                    TextColor3 = Library.FontColor,
                    TextSize = 11,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Parent = root,
                })
                registerTheme(label, { TextColor3 = "FontColor" })
            end
            label.Text = self.Footer
            return self
        end)
    end

    if type(window.SetAlwaysOnTop) ~= "function" then
        install(window, "SetAlwaysOnTop", function(self, enabled)
            if Library.ScreenGui then
                Library.ScreenGui.DisplayOrder = enabled == true and 10000 or 1
            end
            self.AlwaysOnTop = enabled == true
            return self
        end)
    end

    if type(window.SetCornerRadius) ~= "function" then
        install(window, "SetCornerRadius", function(self, radius)
            radius = math.max(0, tonumber(radius) or 0)
            local root = self.Holder
            if not root then
                return self
            end
            local corner = root:FindFirstChild("LinoriaPlusCorner")
            if not corner then
                corner = make("UICorner", {
                    Name = "LinoriaPlusCorner",
                    Parent = root,
                })
            end
            corner.CornerRadius = UDim.new(0, radius)
            return self
        end)
    end

    if type(window.SetSnapping) ~= "function" then
        install(window, "SetSnapping", function(self, enabled, distance)
            disconnect(self.__AspectSysSnapConnection)
            self.__AspectSysSnapConnection = nil
            self.Snapping = enabled == true
            if not self.Snapping then
                return self
            end

            local root = self.Holder
            if not root then
                return self
            end

            local snapDistance = tonumber(distance) or 18
            self.__AspectSysSnapConnection = RunService.RenderStepped:Connect(function()
                if not root.Parent or not root.Visible then
                    return
                end
                local camera = workspace.CurrentCamera
                if not camera then
                    return
                end
                local viewport = camera.ViewportSize
                local p = root.AbsolutePosition
                local s = root.AbsoluteSize
                local x, y = p.X, p.Y
                if math.abs(p.X) <= snapDistance then x = 0 end
                if math.abs(p.Y) <= snapDistance then y = 0 end
                if math.abs(p.X + s.X - viewport.X) <= snapDistance then x = viewport.X - s.X end
                if math.abs(p.Y + s.Y - viewport.Y) <= snapDistance then y = viewport.Y - s.Y end
                if x ~= p.X or y ~= p.Y then
                    local current = root.Position
                    local anchor = root.AnchorPoint
                    root.Position = UDim2.new(
                        current.X.Scale,
                        x + s.X * anchor.X,
                        current.Y.Scale,
                        y + s.Y * anchor.Y
                    )
                end
            end)
            giveSignal(self.__AspectSysSnapConnection)
            return self
        end)
    end

    if type(window.SetBackgroundImage) ~= "function" then
        install(window, "SetBackgroundImage", function(self, image)
            local root = self.Holder
            self.BackgroundImage = tostring(image or "")
            if not root then
                return self
            end

            local background = root:FindFirstChild("LinoriaPlusBackground")
            if self.BackgroundImage == "" then
                if background then
                    background:Destroy()
                end
                return self
            end

            if not background then
                background = make("ImageLabel", {
                    Name = "LinoriaPlusBackground",
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                    Position = UDim2.fromScale(0, 0),
                    Size = UDim2.fromScale(1, 1),
                    ImageTransparency = 0.82,
                    ZIndex = 0,
                    Parent = root,
                })
            end

            background.Image = normalizeAsset(self.BackgroundImage)
            return self
        end)
    end

    if type(window.AddDialog) ~= "function" then
        install(window, "AddDialog", function(self, index, info)
            info = type(info) == "table" and info or {}
            local overlay = make("Frame", {
                Name = "LinoriaPlusDialog_" .. tostring(index),
                BackgroundColor3 = Color3.new(0, 0, 0),
                BackgroundTransparency = 0.35,
                BorderSizePixel = 0,
                Size = UDim2.fromScale(1, 1),
                ZIndex = 4000,
                Parent = Library.ScreenGui,
            })
            local frame = make("Frame", {
                BackgroundColor3 = Library.BackgroundColor,
                BorderColor3 = Library.OutlineColor,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.fromScale(0.5, 0.5),
                Size = UDim2.fromOffset(360, 150),
                ZIndex = 4001,
                Parent = overlay,
            })
            registerTheme(frame, {
                BackgroundColor3 = "BackgroundColor",
                BorderColor3 = "OutlineColor",
            })
            local title = make("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 10),
                Size = UDim2.new(1, -24, 0, 22),
                Font = Library.Font,
                Text = tostring(info.Title or "Dialog"),
                TextColor3 = Library.FontColor,
                TextSize = 16,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 4002,
                Parent = frame,
            })
            registerTheme(title, { TextColor3 = "FontColor" })
            local description = make("TextLabel", {
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(12, 38),
                Size = UDim2.new(1, -24, 0, 56),
                Font = Library.Font,
                Text = tostring(info.Description or ""),
                TextColor3 = Library.FontColor,
                TextSize = 13,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextYAlignment = Enum.TextYAlignment.Top,
                ZIndex = 4002,
                Parent = frame,
            })
            registerTheme(description, { TextColor3 = "FontColor" })

            local dialog = {
                Holder = overlay,
                Frame = frame,
                Title = title,
                Description = description,
            }

            local buttons = type(info.FooterButtons) == "table" and info.FooterButtons or {}
            local buttonList = {}
            for name, buttonInfo in pairs(buttons) do
                if type(buttonInfo) == "table" then
                    table.insert(buttonList, { Name = name, Info = buttonInfo })
                elseif buttonInfo ~= nil then
                    table.insert(buttonList, { Name = name, Info = { Title = tostring(buttonInfo) } })
                end
            end
            table.sort(buttonList, function(a, b)
                return (tonumber(a.Info.Order) or 0) < (tonumber(b.Info.Order) or 0)
            end)

            local x = 12
            for _, entry in ipairs(buttonList) do
                local buttonInfo = entry.Info or {}
                local button = make("TextButton", {
                    Name = tostring(entry.Name),
                    AutoButtonColor = true,
                    BackgroundColor3 = buttonInfo.Variant == "Destructive" and Library.RiskColor or Library.MainColor,
                    BorderColor3 = Library.OutlineColor,
                    Position = UDim2.new(0, x, 1, -34),
                    Size = UDim2.fromOffset(100, 22),
                    Font = Library.Font,
                    Text = tostring(buttonInfo.Title or entry.Name),
                    TextColor3 = Library.FontColor,
                    TextSize = 12,
                    ZIndex = 4002,
                    Parent = frame,
                })
                registerTheme(button, {
                    BackgroundColor3 = buttonInfo.Variant == "Destructive" and "RiskColor" or "MainColor",
                    BorderColor3 = "OutlineColor",
                    TextColor3 = "FontColor",
                })
                x = x + 106
                giveSignal(button.MouseButton1Click:Connect(function()
                    if buttonInfo.Disabled == true then
                        return
                    end
                    if type(buttonInfo.Callback or buttonInfo.Func) == "function" then
                        callSafe(buttonInfo.Callback or buttonInfo.Func, dialog)
                    end
                    if buttonInfo.AutoDismiss ~= false then
                        dialog:Dismiss()
                    end
                end))
            end

            function dialog:SetTitle(value)
                title.Text = tostring(value or "")
                return self
            end

            function dialog:SetDescription(value)
                description.Text = tostring(value or "")
                return self
            end

            function dialog:AddFooterButton(buttonIndex, buttonInfo)
                buttonInfo = buttonInfo or {}
                local button = make("TextButton", {
                    Name = tostring(buttonIndex),
                    BackgroundColor3 = buttonInfo.Variant == "Destructive" and Library.RiskColor or Library.MainColor,
                    BorderColor3 = Library.OutlineColor,
                    AnchorPoint = Vector2.new(1, 1),
                    Position = UDim2.new(1, -8, 1, -8),
                    Size = UDim2.fromOffset(100, 22),
                    Font = Library.Font,
                    Text = tostring(buttonInfo.Title or buttonIndex),
                    TextColor3 = Library.FontColor,
                    TextSize = 12,
                    ZIndex = 4002,
                    Parent = frame,
                })
                registerTheme(button, {
                    BackgroundColor3 = buttonInfo.Variant == "Destructive" and "RiskColor" or "MainColor",
                    BorderColor3 = "OutlineColor",
                    TextColor3 = "FontColor",
                })
                giveSignal(button.MouseButton1Click:Connect(function()
                    if buttonInfo.Disabled == true then
                        return
                    end
                    local callback = buttonInfo.Callback or buttonInfo.Func
                    if type(callback) == "function" then
                        callSafe(callback, dialog)
                    end
                    if buttonInfo.AutoDismiss ~= false then
                        dialog:Dismiss()
                    end
                end))
                return button
            end

            function dialog:RemoveFooterButton(buttonIndex)
                local button = frame:FindFirstChild(tostring(buttonIndex))
                if button then
                    button:Destroy()
                end
                return self
            end

            function dialog:SetButtonDisabled(buttonIndex, disabled)
                local button = frame:FindFirstChild(tostring(buttonIndex))
                if button and button:IsA("GuiButton") then
                    button.Active = disabled ~= true
                    button.AutoButtonColor = disabled ~= true
                end
                return self
            end

            function dialog:SetButtonOrder(buttonIndex, order)
                local button = frame:FindFirstChild(tostring(buttonIndex))
                if button then
                    button.LayoutOrder = tonumber(order) or 0
                end
                return self
            end

            function dialog:Dismiss()
                if overlay then
                    overlay:Destroy()
                end
                return self
            end

            self.__AspectSysLastDialog = dialog
            return dialog
        end)
    end

    if type(window.IsSidebarCompacted) ~= "function" then
        install(window, "IsSidebarCompacted", function(self)
            return self.__AspectSysSidebarCompacted == true
        end)
    end

    if type(window.GetSidebarWidth) ~= "function" then
        install(window, "GetSidebarWidth", function(self)
            local root = self.Holder
            if root and type(root.AbsoluteSize) == "Vector2" then
                return self.__AspectSysSidebarWidth or 0
            end
            return self.__AspectSysSidebarWidth or 0
        end)
    end

    if type(window.SetSidebarWidth) ~= "function" then
        install(window, "SetSidebarWidth", function(self, width)
            self.__AspectSysSidebarWidth = tonumber(width) or 0
            return self
        end)
    end

    if type(window.SetCompact) ~= "function" then
        install(window, "SetCompact", function(self, state)
            self.__AspectSysSidebarCompacted = state == true
            return self
        end)
    end

    if type(window.ShowTabInfo) ~= "function" then
        install(window, "ShowTabInfo", function(self, name, description)
            self.__AspectSysTabInfo = tostring(name or "") .. (description and (" • " .. tostring(description)) or "")
            return self
        end)
    end

    if type(window.HideTabInfo) ~= "function" then
        install(window, "HideTabInfo", function(self)
            self.__AspectSysTabInfo = nil
            return self
        end)
    end

    if type(window.AddKeyTab) ~= "function" then
        install(window, "AddKeyTab", function(self, info, icon, description)
            local tab = self:AddTab(info, icon, description)
            tab.IsKeyTab = true
            if type(tab.AddKeyBox) ~= "function" then
                install(tab, "AddKeyBox", function(keyTab, expectedKey, callback)
                    keyTab.__AspectSysExpectedKey = expectedKey
                    keyTab.__AspectSysKeyCallback = callback
                    return keyTab
                end)
            end
            return tab
        end)
    end

    if type(window.SetAnimations) ~= "function" then
        install(window, "SetAnimations", function(self, animations, tabTransitionTime, tabSwipeOffset, tabSwipeFrom)
            if type(animations) == "table" then
                self.Animations = animations
            end
            if tabTransitionTime ~= nil then
                self.TabTransitionTime = tabTransitionTime
            end
            if tabSwipeOffset ~= nil then
                self.TabSwipeOffset = tabSwipeOffset
            end
            if tabSwipeFrom ~= nil then
                self.TabSwipeFrom = tabSwipeFrom
            end
            return self
        end)
    end

    local baseAddTab = window.AddTab
    if type(baseAddTab) == "function" and not window.__AspectSysAddTabPatched then
        window.__AspectSysAddTabPatched = true
        window.AddTab = function(self, info, icon, description)
            local name = info
            if type(info) == "table" then
                name = info.Name or info.Title or "Tab"
                icon = info.Icon
                description = info.Description
            end

            local tab = baseAddTab(self, name, icon, description)
            if type(tab) == "table" then
                tab.Icon = icon or tab.Icon
                tab.Description = description or tab.Description
                augmentTab(tab)
            end
            return tab
        end
    end

    for _, tab in pairs(window.Tabs or {}) do
        augmentTab(tab)
    end

    return window
end

local originalCreateWindow = Library.CreateWindow
if type(originalCreateWindow) == "function" and not Library.__AspectSysCreateWindowPatched then
    Library.__AspectSysCreateWindowPatched = true

    Library.CreateWindow = function(self, info)
        local config = type(info) == "table" and info or {}
        local window = originalCreateWindow(self, info)
        window = augmentWindow(window)
        self.Window = window

        if config.Footer then
            window:SetFooter(config.Footer)
        end
        if config.BackgroundImage then
            window:SetBackgroundImage(config.BackgroundImage)
            self.Scheme.BackgroundImage = tostring(config.BackgroundImage)
        end
        if config.CornerRadius then
            window:SetCornerRadius(config.CornerRadius)
        end
        if config.NotifySide then
            self.NotifySide = config.NotifySide
        end

        -- Upstream Linoria remains authoritative for rendering and tab state.
        -- We only normalize newly-created groupbox visibility and then refresh
        -- the first tab on the next scheduler turn, after the initial UI tree exists.
        task.defer(function()
            if window and window.Holder and window.Holder.Parent then
                for _, tab in pairs(window.Tabs or {}) do
                    for _, groupbox in pairs(tab.Groupboxes or {}) do
                        normalizeGroupboxVisualState(groupbox)
                    end
                end
                local firstTab
                for _, tab in pairs(window.Tabs or {}) do
                    firstTab = tab
                    break
                end
                if firstTab and type(firstTab.ShowTab) == "function" then
                    pcall(function() firstTab:ShowTab() end)
                end
            end
        end)

        return window
    end
end

---------------------------------------------------------------------
-- Library utility compatibility.
---------------------------------------------------------------------

if type(Library.SetDPI) ~= "function" and type(Library.SetDPIScale) == "function" then
    Library.SetDPI = function(self, percent)
        return self:SetDPIScale((tonumber(percent) or 100) / 100)
    end
end

if type(Library.SetDPI) ~= "function" then
    Library.SetDPI = function(self, percent)
        local scale = (tonumber(percent) or 100) / 100
        self.DPIScale = scale
        if self.ScreenGui then
            for _, child in ipairs(self.ScreenGui:GetChildren()) do
                if child:IsA("GuiObject") then
                    local uiScale = child:FindFirstChild("LinoriaPlusUIScale")
                    if not uiScale then
                        uiScale = make("UIScale", {
                            Name = "LinoriaPlusUIScale",
                            Parent = child,
                        })
                    end
                    uiScale.Scale = scale
                end
            end
        end
        return self
    end
end

if type(Library.SetDPIScale) ~= "function" then
    Library.SetDPIScale = function(self, percent)
        if type(percent) ~= "number" then
            percent = 1
        elseif percent > 2 then
            percent = percent / 100
        end
        self.DPIScale = percent
        return self:SetDPI(percent * 100)
    end
end

if type(Library.GetDPI) ~= "function" then
    Library.GetDPI = function(self)
        return math.floor((self.DPIScale or 1) * 100 + 0.5)
    end
end

if type(Library.SetNotifySide) ~= "function" then
    Library.SetNotifySide = function(self, side)
        side = side == "Left" and "Left" or "Right"
        self.NotifySide = side
        return self
    end
end

do
    local dragStates = setmetatable({}, { __mode = "k" })

    function Library:MakeDraggable(instance, cutoff)
        if not instance or not instance:IsA("GuiObject") then
            return
        end

        local previous = dragStates[instance]
        if previous then
            if previous.began then previous.began:Disconnect() end
            if previous.changed then previous.changed:Disconnect() end
            if previous.ended then previous.ended:Disconnect() end
            dragStates[instance] = nil
        end

        instance.Active = true

        local state = {
            dragging = false,
            startInput = nil,
            startPosition = nil,
            began = nil,
            changed = nil,
            ended = nil,
        }
        dragStates[instance] = state

        state.began = instance.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            local pointer = input.Position
            local absolutePosition = instance.AbsolutePosition
            local localY = pointer.Y - absolutePosition.Y
            local limit = tonumber(cutoff) or 40
            if localY > limit then
                return
            end

            state.dragging = true
            state.startInput = pointer
            state.startPosition = instance.Position
        end)

        state.changed = InputService.InputChanged:Connect(function(input)
            if not state.dragging or not state.startInput or not state.startPosition then
                return
            end

            if input.UserInputType ~= Enum.UserInputType.MouseMovement
                and input.UserInputType ~= Enum.UserInputType.Touch then
                return
            end

            if not instance.Parent then
                state.dragging = false
                return
            end

            local delta = input.Position - state.startInput
            local startPosition = state.startPosition
            instance.Position = UDim2.new(
                startPosition.X.Scale,
                startPosition.X.Offset + delta.X,
                startPosition.Y.Scale,
                startPosition.Y.Offset + delta.Y
            )
        end)

        state.ended = InputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                state.dragging = false
                state.startInput = nil
                state.startPosition = nil
            end
        end)

        return instance
    end
end

if type(Library.AddDraggableLabel) ~= "function" then
    local floats = Library.__AspectSysFloats
    if not (floats and floats.Parent) then
        floats = make("Frame", {
            Name = "LinoriaPlusFloats",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromScale(0, 0),
            ZIndex = 100,
            Parent = Library.ScreenGui,
        })
        Library.__AspectSysFloats = floats
    end

    local function nextFloatPosition(self, height, explicit)
        if explicit then
            return explicit
        end
        local y = tonumber(self.__AspectSysFloatCursorY) or 10
        local position = UDim2.fromOffset(10, y)
        self.__AspectSysFloatCursorY = y + math.max(22, tonumber(height) or 24) + 6
        return position
    end

    local function refreshSize(item)
        local holder, label = item.Holder, item.Label
        if not holder or not holder.Parent or not label then
            return
        end

        local text = tostring(label.Text or "")
        local width = 28
        local ok, textWidth = pcall(function()
            return select(1, Library:GetTextBounds(text, Library.Font, label.TextSize))
        end)
        if ok and tonumber(textWidth) then
            width = tonumber(textWidth) + 8
        end

        if item.Icon then
            width = width + 20
        end

        local requested = tonumber(item.Width)
        if requested and requested > width then
            width = requested
        end

        holder.Size = UDim2.fromOffset(math.max(28, math.ceil(width)), holder.Size.Y.Offset)

        if item.Icon then
            if item.IconPosition == "right" then
                item.Icon.Position = UDim2.new(1, -18, 0.5, -8)
                label.Position = UDim2.fromOffset(0, 0)
                label.Size = UDim2.new(1, -20, 1, 0)
            else
                item.Icon.Position = UDim2.fromOffset(0, 5)
                label.Position = UDim2.fromOffset(20, 0)
                label.Size = UDim2.new(1, -20, 1, 0)
            end
        else
            label.Position = UDim2.fromOffset(0, 0)
            label.Size = UDim2.fromScale(1, 1)
        end
    end

    local function drag(ui)
        return Library:MakeDraggable(ui, math.huge)
    end

    Library.AddDraggableLabel = function(self, text, icon, iconPosition)
        local config
        if type(text) == "table" then
            config = text
            icon = config.Icon
            iconPosition = config.IconPosition
            text = config.Text
        else
            config = {}
        end

        local textValue = tostring(text or "")
        local width = tonumber(config.Width)
        if not width then
            local ok, measured = pcall(function()
                return select(1, Library:GetTextBounds(textValue, Library.Font, 13))
            end)
            width = (ok and tonumber(measured) or 20) + 8 + (icon and 20 or 0)
        end

        local holder = make("Frame", {
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(math.max(28, math.ceil(width)), tonumber(config.Height) or 26),
            Position = nextFloatPosition(self, tonumber(config.Height) or 26, config.Position),
            ZIndex = tonumber(config.ZIndex) or 100,
            Parent = floats,
        })
        local label = make("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Font = Library.Font,
            TextColor3 = Library.FontColor,
            TextSize = tonumber(config.TextSize) or 13,
            TextXAlignment = config.TextXAlignment or Enum.TextXAlignment.Left,
            Text = textValue,
            TextWrapped = config.TextWrapped == true,
            ZIndex = (tonumber(config.ZIndex) or 100) + 1,
            Parent = holder,
        })

        registerTheme(label, { TextColor3 = "FontColor" })

        local image
        if icon then
            image = make("ImageLabel", {
                BackgroundTransparency = 1,
                Size = UDim2.fromOffset(16, 16),
                Position = iconPosition == "right" and UDim2.new(1, -18, 0.5, -8) or UDim2.fromOffset(0, 5),
                Image = "",
                ZIndex = (tonumber(config.ZIndex) or 100) + 1,
                Parent = holder,
            })
            applyIcon(image, icon)
        end

        local item = {
            Holder = holder,
            Label = label,
            Icon = image,
            IconPosition = iconPosition or "left",
            Width = tonumber(config.Width),
        }

        refreshSize(item)
        Library.__AspectSysDrag = drag
        drag(holder)

        function item:SetText(value)
            label.Text = tostring(value or "")
            refreshSize(self)
            return self
        end

        function item:SetVisible(value)
            holder.Visible = value == true
            return self
        end

        function item:SetPosition(value)
            if typeof(value) == "UDim2" then
                holder.Position = value
            end
            return self
        end

        function item:SetSize(value)
            if typeof(value) == "UDim2" then
                holder.Size = value
            end
            return self
        end

        function item:SetIcon(value)
            if not image then
                image = make("ImageLabel", {
                    BackgroundTransparency = 1,
                    Size = UDim2.fromOffset(16, 16),
                    Position = UDim2.fromOffset(0, 5),
                    ZIndex = holder.ZIndex + 1,
                    Parent = holder,
                })
                item.Icon = image
            end
            applyIcon(image, value)
            refreshSize(self)
            return self
        end

        function item:SetIconPosition(position)
            self.IconPosition = position == "right" and "right" or "left"
            refreshSize(self)
            return self
        end

        function item:Destroy()
            if holder then
                holder:Destroy()
            end
        end

        return item
    end
end

if type(Library.AddDraggableButton) ~= "function" then
    Library.AddDraggableButton = function(self, text, callback, excludeScaling, excludeDragging, icon, iconPosition)
        local options = nil
        if type(text) == "table" then
            options = text
            callback = options.Callback or options.Func
            excludeScaling = options.ExcludeScaling
            excludeDragging = options.ExcludeDragging
            icon = options.Icon
            iconPosition = options.IconPosition
            text = options.Text
        end

        local item = self:AddDraggableLabel({
            Text = text or "Button",
            Icon = icon,
            IconPosition = iconPosition,
            Position = options and options.Position or nil,
            Width = options and options.Width or nil,
            Height = options and options.Height or nil,
            ZIndex = options and options.ZIndex or nil,
        })
        local button = make("TextButton", {
            BackgroundTransparency = 1,
            Size = UDim2.fromScale(1, 1),
            Text = "",
            AutoButtonColor = false,
            ZIndex = item.Holder.ZIndex + 2,
            Parent = item.Holder,
        })
        giveSignal(button.MouseButton1Click:Connect(function()
            callSafe(callback, item)
        end))
        item.Button = button
        item.ExcludeScaling = excludeScaling == true
        item.ExcludeDragging = excludeDragging == true
        return item
    end
end

if type(Library.AddDraggableImageButton) ~= "function" then
    Library.AddDraggableImageButton = function(self, icon, iconSize, callback, excludeScaling, excludeDragging)
        local options = nil
        if type(icon) == "table" then
            options = icon
            iconSize = options.IconSize
            callback = options.Callback or options.Func
            excludeScaling = options.ExcludeScaling
            excludeDragging = options.ExcludeDragging
            icon = options.Icon
        end

        local item = self:AddDraggableLabel({
            Text = "",
            Position = options and options.Position or nil,
            Height = options and options.Height or nil,
            ZIndex = options and options.ZIndex or nil,
            Width = (tonumber(iconSize) or 20) + 12,
        })
        local size = tonumber(iconSize) or 20
        item.Holder.Size = UDim2.fromOffset(size + 12, size + 12)
        local image = make("ImageButton", {
            BackgroundTransparency = 1,
            Size = UDim2.fromOffset(size, size),
            Position = UDim2.fromOffset(6, 6),
            Image = "",
            AutoButtonColor = false,
            ZIndex = item.Holder.ZIndex + 2,
            Parent = item.Holder,
        })
        applyIcon(image, icon)
        giveSignal(image.MouseButton1Click:Connect(function()
            callSafe(callback, item)
        end))
        item.Button = image
        item.ExcludeScaling = excludeScaling == true
        item.ExcludeDragging = excludeDragging == true
        item.SetIconSize = function(self, newSize)
            newSize = tonumber(newSize) or size
            size = newSize
            image.Size = UDim2.fromOffset(size, size)
            item.Holder.Size = UDim2.fromOffset(size + 12, size + 12)
            return self
        end
        item.SetIcon = function(self, value)
            applyIcon(image, value)
            return self
        end
        return item
    end
end

if type(Library.AddDraggableMenu) ~= "function" then
    Library.AddDraggableMenu = function(self, name)
        local config = type(name) == "table" and name or {}
        local titleText = type(name) == "table" and (name.Name or name.Text) or name
        local floatsRoot = Library.__AspectSysFloats or Library.ScreenGui
        local y = tonumber(self.__AspectSysFloatCursorY) or 10
        local holderHeight = 34
        local position = config.Position or UDim2.fromOffset(10, y)
        if not config.Position then
            self.__AspectSysFloatCursorY = y + holderHeight + 6
        end
        local holder = make("Frame", {
            BackgroundColor3 = Library.MainColor,
            BorderColor3 = Library.OutlineColor,
            Size = UDim2.fromOffset(180, holderHeight),
            Position = position,
            ZIndex = tonumber(config.ZIndex) or 100,
            Parent = floatsRoot,
        })
        registerTheme(holder, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
        local title = make("TextLabel", {
            BackgroundTransparency = 1,
            Size = UDim2.new(1, -10, 0, 24),
            Position = UDim2.fromOffset(5, 0),
            Font = Library.Font,
            TextColor3 = Library.FontColor,
            TextSize = 12,
            Text = tostring(titleText or "Menu"),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 101,
            Parent = holder,
        })
        registerTheme(title, { TextColor3 = "FontColor" })
        local container = make("Frame", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(4, 28),
            Size = UDim2.new(1, -8, 0, 0),
            ZIndex = 101,
            Parent = holder,
        })
        local layout = make("UIListLayout", {
            Padding = UDim.new(0, 4),
            Parent = container,
        })
        local function addButton(text, callback)
            local button = make("TextButton", {
                BackgroundColor3 = Library.BackgroundColor,
                BorderColor3 = Library.OutlineColor,
                Size = UDim2.new(1, 0, 0, 22),
                Font = Library.Font,
                Text = tostring(text or "Button"),
                TextColor3 = Library.FontColor,
                TextSize = 12,
                ZIndex = 102,
                Parent = container,
            })
            registerTheme(button, {
                BackgroundColor3 = "BackgroundColor",
                BorderColor3 = "OutlineColor",
                TextColor3 = "FontColor",
            })
            giveSignal(button.MouseButton1Click:Connect(function()
                callSafe(callback)
            end))
            container.Size = UDim2.new(1, -8, 0, layout.AbsoluteContentSize.Y + 4)
            holder.Size = UDim2.new(0, 180, 0, 32 + container.Size.Y.Offset)
            return button
        end
        if type(Library.__AspectSysDrag) == "function" then
            Library.__AspectSysDrag(holder)
        end
        return holder, container, addButton
    end
end

---------------------------------------------------------------------
-- Watermark.
---------------------------------------------------------------------

if type(Library.SetWatermark) ~= "function" or type(Library.AddWatermark) ~= "function" then
    Library.__AspectSysWatermark = Library.__AspectSysWatermark or nil

    Library.AddWatermark = function(self, config)
        config = type(config) == "table" and config or {}
        if self.__AspectSysWatermark then
            self.__AspectSysWatermark:Destroy()
        end

        local label = self:AddDraggableLabel("")
        label.Holder.Position = config.Position or UDim2.fromOffset(10, 10)
        label.SetSegments = function(item, segments)
            item.Segments = segments
            return item:Refresh()
        end
        label.SetText = function(item, text)
            item.Label.Text = tostring(text or "")
            return item
        end
        label.Refresh = function(item)
            local segments = item.Segments or config.Segments or {}
            local parts = {}
            for _, segment in ipairs(segments) do
                local value = segment.Text
                if type(value) == "function" then
                    value = value()
                end
                table.insert(parts, tostring(value or ""))
            end
            item.Label.Text = table.concat(parts, "  |  ")
            return item
        end
        label:Refresh()
        label:SetVisible(config.Visible ~= false)
        self.__AspectSysWatermark = label
        return label
    end

    Library.SetWatermark = function(self, text)
        if not self.__AspectSysWatermark then
            self:AddWatermark({ Visible = false })
        end
        self.__AspectSysWatermark:SetText(text)
        return self
    end

    Library.SetWatermarkVisibility = function(self, visible)
        if not self.__AspectSysWatermark then
            self:AddWatermark({ Visible = false })
        end
        self.__AspectSysWatermark:SetVisible(visible == true)
        return self
    end
end

---------------------------------------------------------------------
-- Optional loading + context menu helpers. These stay separate from the
-- Linoria controls and are not used to replace the renderer.
---------------------------------------------------------------------

if type(Library.CreateLoading) ~= "function" then
    Library.CreateLoading = function(self, info)
        info = type(info) == "table" and info or {}
        local holder = make("Frame", {
            BackgroundColor3 = Library.BackgroundColor,
            BorderColor3 = Library.OutlineColor,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.fromScale(0.5, 0.5),
            Size = UDim2.fromOffset(340, 110),
            ZIndex = 3500,
            Parent = Library.ScreenGui,
        })
        registerTheme(holder, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" })
        local title = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, 10),
            Size = UDim2.new(1, -24, 0, 20),
            Font = Library.Font,
            TextColor3 = Library.FontColor,
            TextSize = 16,
            Text = tostring(info.Title or "Loading"),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 3501,
            Parent = holder,
        })
        registerTheme(title, { TextColor3 = "FontColor" })
        local description = make("TextLabel", {
            BackgroundTransparency = 1,
            Position = UDim2.fromOffset(12, 35),
            Size = UDim2.new(1, -24, 0, 32),
            Font = Library.Font,
            TextColor3 = Library.FontColor,
            TextSize = 12,
            TextWrapped = true,
            Text = tostring(info.Description or ""),
            TextXAlignment = Enum.TextXAlignment.Left,
            ZIndex = 3501,
            Parent = holder,
        })
        registerTheme(description, { TextColor3 = "FontColor" })
        local barBack = make("Frame", {
            BackgroundColor3 = Library.MainColor,
            BorderColor3 = Library.OutlineColor,
            Position = UDim2.new(0, 12, 1, -24),
            Size = UDim2.new(1, -24, 0, 8),
            ZIndex = 3501,
            Parent = holder,
        })
        registerTheme(barBack, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" })
        local bar = make("Frame", {
            BackgroundColor3 = Library.AccentColor,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(0, 1),
            ZIndex = 3502,
            Parent = barBack,
        })
        registerTheme(bar, { BackgroundColor3 = "AccentColor" })

        local object = {
            Holder = holder,
            ScreenGui = Library.ScreenGui,
            CurrentStep = tonumber(info.CurrentStep) or 0,
            TotalSteps = tonumber(info.TotalSteps) or 100,
            Closed = false,
        }
        function object:SetDescription(value) description.Text = tostring(value or ""); return self end
        function object:SetCurrentStep(value)
            self.CurrentStep = tonumber(value) or 0
            local total = math.max(1, tonumber(self.TotalSteps) or 1)
            bar.Size = UDim2.fromScale(math.clamp(self.CurrentStep / total, 0, 1), 1)
            return self
        end
        function object:SetTotalSteps(value)
            self.TotalSteps = math.max(1, tonumber(value) or 1)
            return self:SetCurrentStep(self.CurrentStep)
        end
        function object:SetWindowWidth(value) holder.Size = UDim2.fromOffset(tonumber(value) or 340, holder.Size.Y.Offset); return self end
        function object:SetWindowHeight(value) holder.Size = UDim2.fromOffset(holder.Size.X.Offset, tonumber(value) or 110); return self end
        function object:Destroy()
            self.Closed = true
            if self.ScreenGui and self.ScreenGui == Library.ScreenGui and Library.ActiveLoading == self then
                Library.ActiveLoading = nil
            end
            if holder then holder:Destroy() end
        end
        object:SetCurrentStep(object.CurrentStep)
        self.ActiveLoading = object
        return object
    end
end

if type(Library.AddContextMenu) ~= "function" then
    Library.AddContextMenu = function(self, target, items, config)
        config = type(config) == "table" and config or {}
        local menu = make("Frame", {
            BackgroundColor3 = Library.BackgroundColor,
            BorderColor3 = Library.OutlineColor,
            Size = UDim2.fromOffset(170, 0),
            Visible = false,
            ZIndex = 5000,
            Parent = Library.ScreenGui,
        })
        registerTheme(menu, { BackgroundColor3 = "BackgroundColor", BorderColor3 = "OutlineColor" })
        local layout = make("UIListLayout", {
            Padding = UDim.new(0, 2),
            Parent = menu,
        })

        local object = { Menu = menu, Target = target }
        local entries = {}
        for _, entry in ipairs(type(items) == "table" and items or {}) do
            if entry.Divider then
                local divider = make("Frame", {
                    BackgroundColor3 = Library.OutlineColor,
                    BorderSizePixel = 0,
                    Size = UDim2.new(1, -8, 0, 1),
                    Parent = menu,
                })
                table.insert(entries, divider)
            else
                local button = make("TextButton", {
                    BackgroundColor3 = Library.MainColor,
                    BorderColor3 = Library.OutlineColor,
                    Size = UDim2.new(1, -8, 0, 22),
                    Font = Library.Font,
                    Text = tostring(entry.Text or entry.Name or "Item"),
                    TextColor3 = Library.FontColor,
                    TextSize = 12,
                    Parent = menu,
                })
                giveSignal(button.MouseButton1Click:Connect(function()
                    if type(entry.Callback) == "function" then
                        callSafe(entry.Callback, object)
                    end
                    object:Close()
                end))
                table.insert(entries, button)
            end
        end

        local function updateSize()
            menu.Size = UDim2.fromOffset(170, layout.AbsoluteContentSize.Y + 8)
        end
        giveSignal(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(updateSize))
        updateSize()

        function object:Open()
            if not menu or not menu.Parent then
                return self
            end
            local mouse = InputService:GetMouseLocation()
            local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
            local width = menu.AbsoluteSize.X > 0 and menu.AbsoluteSize.X or 170
            local height = menu.AbsoluteSize.Y > 0 and menu.AbsoluteSize.Y or 30
            local x = mouse.X
            local y = mouse.Y
            if viewport then
                x = math.clamp(x, 0, math.max(0, viewport.X - width))
                y = math.clamp(y, 0, math.max(0, viewport.Y - height))
            end
            menu.Position = UDim2.fromOffset(x, y)
            menu.Visible = true
            return self
        end
        function object:Close()
            if menu and menu.Parent then
                menu.Visible = false
            end
            return self
        end
        function object:Destroy()
            if menu then
                menu:Destroy()
            end
            menu = nil
            self.Menu = nil
            self.Destroyed = true
            return self
        end

        if target and target:IsA("GuiButton") then
            giveSignal(target.MouseButton2Click:Connect(function()
                object:Open()
            end))
        end

        return object
    end
end

---------------------------------------------------------------------
-- Non-invasive runtime normalization.
--
-- The upstream Linoria renderer owns tab/groupbox state. LinoriaPlus only
-- provides a safe visual refresh helper rather than wrapping ShowTab/Resize.
---------------------------------------------------------------------

Library.RefreshUI = function(self, window)
    window = window or self.Window
    if type(window) ~= "table" then
        return self
    end

    for _, tab in pairs(window.Tabs or {}) do
        for _, groupbox in pairs(tab.Groupboxes or {}) do
            normalizeGroupboxVisualState(groupbox)
        end
        for _, tabbox in pairs(tab.Tabboxes or {}) do
            if type(tabbox) == "table" and type(tabbox.Tabs) == "table" then
                for _, subTab in pairs(tabbox.Tabs) do
                    for _, groupbox in pairs(subTab.Groupboxes or {}) do
                        normalizeGroupboxVisualState(groupbox)
                    end
                end
            end
        end
    end

    return self
end

-- Normalize notification input so both Linoria's string API and Obsidian-style
-- {Title, Description, Time} notifications are accepted.
do
    local originalNotify = Library.Notify
    if type(originalNotify) == "function" and not Library.__AspectSysNotifyHardened then
        Library.__AspectSysNotifyHardened = true
        Library.Notify = function(self, message, time)
            if type(message) == "table" then
                local title = message.Title or message.Name or message.Text
                local description = message.Description or message.Message
                local textValue
                if title and description and tostring(description) ~= "" then
                    textValue = tostring(title) .. ": " .. tostring(description)
                else
                    textValue = tostring(title or description or "")
                end
                local duration = tonumber(message.Time or message.Duration or time) or 5
                if textValue == "" then
                    return self
                end
                return originalNotify(self, textValue, duration)
            end

            if message == nil then
                return self
            end

            local duration = tonumber(time) or 5
            return originalNotify(self, tostring(message), duration)
        end
    end
end

-- Ensure AttemptSave exists even when a different Linoria fork is supplied.
if type(Library.AttemptSave) ~= "function" then
    Library.AttemptSave = function(self)
        local manager = self.SaveManager
        if manager and type(manager.Save) == "function" then
            return manager:Save()
        end
    end
end

-- Watermark: disabled by default, single-instance, and automatically refreshed.
do
    if Library.__AspectSysWatermarkRefreshSignal then
        disconnect(Library.__AspectSysWatermarkRefreshSignal)
        Library.__AspectSysWatermarkRefreshSignal = nil
    end

    Library.AddWatermark = function(self, config)
        config = type(config) == "table" and config or {}

        if self.__AspectSysWatermark then
            safeDestroy(self.__AspectSysWatermark.Holder)
            self.__AspectSysWatermark = nil
        end

        local label = self:AddDraggableLabel({
            Text = "",
            Icon = config.Icon,
            IconPosition = config.IconPosition,
        })
        label.Holder.Position = config.Position or UDim2.fromOffset(10, 10)
        label.Segments = type(config.Segments) == "table" and config.Segments or {}
        label.Visible = config.Visible == true

        function label:SetSegments(segments)
            self.Segments = type(segments) == "table" and segments or {}
            return self:Refresh()
        end

        function label:SetText(value)
            self.Segments = nil
            self.Label.Text = tostring(value or "")
            return self
        end

        function label:Refresh()
            if type(self.Segments) == "table" then
                local parts = {}
                for _, segment in ipairs(self.Segments) do
                    if type(segment) == "table" then
                        local value = segment.Text
                        if type(value) == "function" then
                            local ok, result = pcall(value)
                            value = ok and result or ""
                        end
                        table.insert(parts, tostring(value or ""))
                    elseif segment ~= nil then
                        table.insert(parts, tostring(segment))
                    end
                end
                self.Label.Text = table.concat(parts, "  |  ")
            end
            return self
        end

        function label:SetVisible(value)
            self.Visible = value == true
            self.Holder.Visible = self.Visible
            return self
        end

        label:Refresh()
        label:SetVisible(config.Visible == true)
        self.__AspectSysWatermark = label

        local accumulator = 0
        self.__AspectSysWatermarkRefreshSignal = RunService.Heartbeat:Connect(function(dt)
            accumulator = accumulator + dt
            if accumulator < 0.25 then
                return
            end
            accumulator = 0

            if label.Holder and label.Holder.Parent and label.Visible and type(label.Refresh) == "function" then
                label:Refresh()
            end
        end)
        giveSignal(self.__AspectSysWatermarkRefreshSignal)

        return label
    end

    Library.SetWatermark = function(self, value)
        if not self.__AspectSysWatermark then
            self:AddWatermark({ Visible = false })
        end
        return self.__AspectSysWatermark:SetText(value)
    end

    Library.SetWatermarkSegments = function(self, segments)
        if not self.__AspectSysWatermark then
            self:AddWatermark({ Visible = false })
        end
        return self.__AspectSysWatermark:SetSegments(segments)
    end

    Library.SetWatermarkVisibility = function(self, visible)
        if not self.__AspectSysWatermark then
            self:AddWatermark({ Visible = false })
        end
        return self.__AspectSysWatermark:SetVisible(visible == true)
    end
end

-- Keybind list: disabled by default, rebuilt from Library.Options, and kept in sync.
do
    Library.KeybindListVisible = false
    Library.KeybindFrame = Library.KeybindFrame or nil

    local function getKeybinds()
        local result = {}
        for index, option in pairs(Library.Options or {}) do
            if type(option) == "table" and option.Type == "KeyPicker" then
                local key = option.Value
                if key ~= nil and tostring(key) ~= "" and tostring(key) ~= "Unknown" then
                    local mode = tostring(option.Mode or "Toggle")
                    local state = option.Toggled == true
                    table.insert(result, {
                        Index = tostring(index),
                        Name = tostring(option.__AspectSysDisplayName or option.Text or index),
                        Key = tostring(key),
                        Mode = mode,
                        State = state,
                    })
                end
            end
        end
        table.sort(result, function(a, b)
            return a.Name:lower() < b.Name:lower()
        end)
        return result
    end

    function Library:RefreshKeybinds()
        local frame = self.KeybindFrame
        if not frame or not frame.Parent then
            return self
        end

        for _, child in ipairs(frame:GetChildren()) do
            if child:IsA("TextLabel") and child.Name ~= "Title" then
                child:Destroy()
            end
        end

        local keybinds = getKeybinds()
        frame.Size = UDim2.fromOffset(230, 28 + (#keybinds * 20))

        for rowIndex, bind in ipairs(keybinds) do
            local stateText = bind.Mode == "Toggle" and (bind.State and "ON" or "OFF") or bind.Mode:upper()
            local row = make("TextLabel", {
                Name = "Keybind_" .. tostring(rowIndex),
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(8, 22 + ((rowIndex - 1) * 20)),
                Size = UDim2.new(1, -16, 0, 18),
                Font = Library.Font,
                TextColor3 = Library.FontColor,
                TextSize = 12,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = string.format("%s  [%s]  %s", bind.Name, bind.Key, stateText),
                ZIndex = 2002,
                Parent = frame,
            })
            pcall(function()
                Library:AddToRegistry(row, { TextColor3 = "FontColor" }, true)
            end)
        end

        return self
    end

    function Library:SetKeybindListVisibility(visible)
        self.KeybindListVisible = visible == true
        if self.__AspectSysNativeKeybindFrame == nil then
            self.__AspectSysNativeKeybindFrame = rawget(self, "KeybindFrame")
        end
        if self.__AspectSysNativeKeybindFrame then
            self.__AspectSysNativeKeybindFrame.Visible = false
        end
        if self.KeybindListVisible and not self.KeybindFrame then
            self.KeybindFrame = make("Frame", {
                Name = "LinoriaPlusKeybinds",
                BackgroundColor3 = Library.MainColor,
                BorderColor3 = Library.OutlineColor,
                Size = UDim2.fromOffset(230, 28),
                Position = UDim2.fromOffset(10, 60),
                ZIndex = 2000,
                Parent = Library.ScreenGui,
            })
            self.KeybindFrame.Title = make("TextLabel", {
                Name = "Title",
                BackgroundTransparency = 1,
                Position = UDim2.fromOffset(8, 4),
                Size = UDim2.new(1, -16, 0, 18),
                Font = Library.Font,
                TextColor3 = Library.FontColor,
                TextSize = 13,
                TextXAlignment = Enum.TextXAlignment.Left,
                Text = "Keybinds",
                ZIndex = 2001,
                Parent = self.KeybindFrame,
            })
            pcall(function()
                Library:AddToRegistry(self.KeybindFrame, {
                    BackgroundColor3 = "MainColor",
                    BorderColor3 = "OutlineColor",
                }, true)
                Library:AddToRegistry(self.KeybindFrame.Title, {
                    TextColor3 = "FontColor",
                }, true)
            end)
            if type(self.__AspectSysDrag) == "function" then
                self.__AspectSysDrag(self.KeybindFrame)
            end
        end

        if self.KeybindFrame then
            self.KeybindFrame.Visible = self.KeybindListVisible
        end
        self:RefreshKeybinds()
        return self
    end

    function Library:ToggleKeybindList()
        return self:SetKeybindListVisibility(not self.KeybindListVisible)
    end

    Library:SetKeybindListVisibility(false)

    if not Library.__AspectSysKeybindRefreshSignal then
        local timer = 0
        Library.__AspectSysKeybindRefreshSignal = RunService.Heartbeat:Connect(function(dt)
            timer = timer + dt
            if timer < 0.15 then
                return
            end
            timer = 0
            if Library.KeybindListVisible then
                pcall(function()
                    Library:RefreshKeybinds()
                end)
            end
        end)
        giveSignal(Library.__AspectSysKeybindRefreshSignal)
    end
end

-- Keep every registered dependency box synchronized with the controls it watches.
do
    local originalUpdateDependencies = Library.UpdateDependencyBoxes
    if not Library.__AspectSysDependencyUpdateHardened then
        Library.__AspectSysDependencyUpdateHardened = true
        Library.UpdateDependencyBoxes = function(self, ...)
            local forwardedArgs = { ... }
            local result
            local ok
            if type(originalUpdateDependencies) == "function" then
                ok, result = pcall(function()
                    return originalUpdateDependencies(self, table.unpack(forwardedArgs))
                end)
            else
                ok = true
            end

            for _, depbox in ipairs(self.DependencyBoxes or {}) do
                if type(depbox) == "table" and depbox.__AspectSysDependencyHardened and type(depbox.Update) == "function" then
                    pcall(function() depbox:Update() end)
                end
            end

            if not ok then
                return self
            end
            return result or self
        end
    end
end

-- DPI is applied to every top-level GUI root and to roots created after SetDPI.
do
    local function applyDPIToRoot(root, scale)
        if not root or not root:IsA("GuiObject") then
            return
        end
        local uiScale = root:FindFirstChild("LinoriaPlusUIScale")
        if not uiScale then
            uiScale = make("UIScale", {
                Name = "LinoriaPlusUIScale",
                Parent = root,
            })
        end
        uiScale.Scale = scale
    end

    Library.SetDPI = function(self, percent)
        local numeric = tonumber(percent)
        if not numeric or numeric <= 0 then
            numeric = 100
        end
        local scale = numeric / 100
        self.DPIScale = scale

        if self.ScreenGui then
            for _, child in ipairs(self.ScreenGui:GetChildren()) do
                if child:IsA("GuiObject") then
                    applyDPIToRoot(child, scale)
                end
            end
        end
        return self
    end

    Library.SetDPIScale = function(self, value)
        local numeric = tonumber(value)
        if not numeric or numeric <= 0 then
            numeric = 1
        elseif numeric > 2 then
            numeric = numeric / 100
        end
        return self:SetDPI(numeric * 100)
    end

    Library.GetDPI = function(self)
        return math.floor(((self.DPIScale or 1) * 100) + 0.5)
    end

    if not Library.DPIScale then
        Library.DPIScale = 1
    end
end

-- Unload is idempotent and clears the executor cache so the next load gets a fresh GUI.
do
    local originalUnloadFinal = Library.Unload
    if type(originalUnloadFinal) == "function" and not Library.__AspectSysUnloadHardened then
        Library.__AspectSysUnloadHardened = true
        Library.Unload = function(self, ...)
            local forwardedArgs = { ... }
            if self.__AspectSysUnloaded then
                return self
            end
            self.__AspectSysUnloaded = true

            local watermark = self.__AspectSysWatermark
            self.__AspectSysWatermark = nil
            if watermark then
                safeDestroy(watermark.Holder)
            end

            local keybindFrame = self.KeybindFrame
            self.KeybindFrame = nil
            if keybindFrame then
                safeDestroy(keybindFrame)
            end

            local ok, result = pcall(function()
                return originalUnloadFinal(self, table.unpack(forwardedArgs))
            end)

            if not ok and self.ScreenGui then
                safeDestroy(self.ScreenGui)
            end

            if rawget(env, "LinoriaPlus") == self then
                env.LinoriaPlus = nil
            end
            if rawget(env, "Library") == self then
                env.Library = nil
            end

            if not ok then
                return self
            end
            return result or self
        end
    end
end


for _, windowTab in pairs((Library.Window and Library.Window.Tabs) or {}) do
    for _, groupbox in pairs(windowTab.Groupboxes or {}) do
        installDependencyBox(groupbox)
    end
    for _, tabbox in pairs(windowTab.Tabboxes or {}) do
        for _, subtab in pairs(tabbox.Tabs or {}) do
            installDependencyBox(subtab)
        end
    end
end

-- Convenience aliases used by older aspect.sys code.
Library.AddTooltip = Library.AddTooltip or Library.AddToolTip
Library.CreateLoadingWindow = Library.CreateLoadingWindow or Library.CreateLoading
Library.ShowLoading = Library.ShowLoading or Library.CreateLoading
Library.ShowDialog = Library.ShowDialog or function(self, info)
    if self.Window and type(self.Window.AddDialog) == "function" then
        return self.Window:AddDialog("LinoriaPlusDialog", info or {})
    end
end

-- Create a tiny, predictable marker for local addons/scripts.
env.LinoriaPlus = Library
return Library
