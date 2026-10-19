--// Example script - replace USER/REPO with your GitHub repo (files must be in the repo root, branch "main")
local BASE = "https://raw.githubusercontent.com/USER/REPO/main/"

local Library     = loadstring(game:HttpGet(BASE .. "UiLib.lua"))()
local SaveManager = loadstring(game:HttpGet(BASE .. "SaveManager.lua"))()

-- every control is mirrored into this table by its key/path (Farm.Enabled -> Config.Farm.Enabled)
local Config = {}

local Window = Library:CreateWindow({
	Title = "My Hub",              -- window title
	Folder = "MyHub",              -- config folder + unique window id
	Target = Config,               -- optional: live config table
	ToggleKeyCode = Enum.KeyCode.RightShift,
	ToggleText = "M",              -- letter on the launcher square (or ToggleIcon = "rbxassetid://...")
	Width = 600, Height = 440,
	StartOpen = true,
	-- Theme = { Accent = Color3.fromRGB(255, 120, 120), Header = Color3.fromRGB(255, 80, 80) },
})

----------------------------------------------------------------------------------------------------
local Main = Window:AddTab("Main")

Main:AddSection("Farm")
Main:AddLabel("Everything here is just an example.")
Main:AddToggle({
	key = "Farm.Enabled", label = "Auto Farm", default = false,
	callback = function(v) print("Auto Farm:", v) end,
})
Main:AddSlider({
	key = "Farm.Speed", label = "Speed", min = 20, max = 400, step = 10, default = 100, suffix = " studs/s",
	callback = function(v) print("Speed:", v) end,
})
Main:AddDropdown({
	key = "Farm.Target", label = "Target", options = { "Bandit", "Marine", "Boss" }, default = "Bandit",
})
Main:AddMultiDropdown({
	label = "Bosses",
	options = {
		{ key = "Bosses.Borj",  label = "Borj",  default = true },
		{ key = "Bosses.Ryuma", label = "Ryuma", default = true },
		{ key = "Bosses.Roger", label = "Roger", default = false },
	},
})
Main:AddDivider()
Main:AddInput({ key = "Webhook.Url", label = "Webhook", placeholder = "https://..." })
Main:AddInput({ key = "Farm.Delay", label = "Delay (s)", numeric = true, default = 1 })
Main:AddButton({ label = "Say hi", callback = function() Window:Notify("Hello", "Button clicked!", 3) end })

----------------------------------------------------------------------------------------------------
local Visuals = Window:AddTab("Visuals")
Visuals:AddSection("ESP")
Visuals:AddToggle({ key = "Esp.Enabled", label = "Enable ESP", default = false })
Visuals:AddColorPicker({ key = "Esp.Color", label = "Box colour", default = Color3.fromRGB(255, 255, 255) })
Visuals:AddKeybind({
	key = "Esp.Key", label = "Toggle ESP key", default = "None",
	onPress = function() Window:Set("Esp.Enabled", not Window:Get("Esp.Enabled")) end,
})

----------------------------------------------------------------------------------------------------
-- config tab (save / load / autoload / delete)
local SM = SaveManager.new(Window, { Folder = "MyHub" })
SM:SetIgnore({ "Webhook.Url" })    -- never saved into configs (optional)
SM:BuildConfigTab("Config")

----------------------------------------------------------------------------------------------------
-- use the values anywhere, either through Config or Window:Get
task.spawn(function()
	while task.wait(1) do
		if Config.Farm and Config.Farm.Enabled then
			-- print("farming at", Config.Farm.Speed, Window:Get("Farm.Target"))
		end
	end
end)

SM:LoadAutoload()          -- keep this last, after every control exists
Window:RunCallbacks()      -- optional: fire all callbacks once with the loaded values
