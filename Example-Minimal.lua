local Library = loadstring(readfile("Library.lua"))()

local Window = Library:CreateWindow({
    Title = "aspect.sys • LinoriaPlus 5.1.5 smoke test",
    Center = true,
    AutoShow = true,
    TabPadding = 8,
})

local Main = Window:AddTab("Main")
local Controls = Window:AddTab("Controls")
local Settings = Window:AddTab("Settings")

local MainLeft = Main:AddLeftGroupbox("Main")
local MainRight = Main:AddRightGroupbox("Other")
MainLeft:AddLabel("Core renderer is working.")
MainLeft:AddToggle("SmokeToggle", { Text = "Smoke toggle", Default = true })
MainLeft:AddSlider("SmokeSlider", { Text = "Smoke slider", Default = 50, Min = 0, Max = 100, Rounding = 0 })
MainLeft:AddButton("Notify", function() Library:Notify("Smoke test OK", 2) end)
MainRight:AddDropdown("SmokeDropdown", { Text = "Dropdown", Values = { "One", "Two", "Three" }, Default = 1 })
MainRight:AddInput("SmokeInput", { Text = "Input", Default = "aspect.sys" })

local ControlsLeft = Controls:AddLeftGroupbox("Controls")
ControlsLeft:AddToggle("ControlToggle", { Text = "Toggle", Default = false })
ControlsLeft:AddColorPicker("ControlColor", { Default = Color3.fromRGB(0, 170, 255), Title = "Color" })
ControlsLeft:AddLabel("Controls tab is populated.")

local SettingsLeft = Settings:AddLeftGroupbox("Menu")
SettingsLeft:AddLabel("Unload is here.")
SettingsLeft:AddButton("Unload", function() Library:Unload() end)

print("[aspect.sys] 5.1.5 core smoke test loaded")
