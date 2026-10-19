--[[
    SaveManager for UiLib  (extracted from the Wyvern config tab)

    local SaveManager = loadstring(game:HttpGet(".../SaveManager.lua"))()
    local SM = SaveManager.new(Window, { Folder = "MyHub" })
    SM:SetIgnore({ "Some.Key" })         -- keys that must never be saved
    SM:BuildConfigTab("Config")          -- or SM:BuildConfigTab(existingTab)
    SM:LoadAutoload()                    -- call at the END of your script

    Files:   <Folder>/<name>.json              configs
             <Folder>/autoload_<Username>.txt  per-account autoload (falls back to <Folder>/autoload.txt)
    No filesystem in the executor -> configs are kept in memory for the session.
]]

local cloneref = cloneref or function(i) return i end
local HttpService = cloneref(game:GetService("HttpService"))
local Players = cloneref(game:GetService("Players"))
local genv = (getgenv and getgenv()) or _G

local fs = {
	write = writefile, read = readfile, isFile = isfile, isFolder = isfolder,
	makeFolder = makefolder, list = listfiles, delete = delfile,
}
local hasFS = type(fs.write) == "function" and type(fs.read) == "function"
	and type(fs.isFile) == "function" and type(fs.list) == "function"

local function clean(name)
	return (string.gsub(string.gsub(string.gsub(tostring(name or ""), "[^%w%-_ ]", ""), "^%s+", ""), "%s+$", ""))
end

local function ensureFolder(path)
	if type(fs.makeFolder) ~= "function" then return end
	local cur
	for part in string.gmatch(path, "[^/]+") do
		cur = cur and (cur .. "/" .. part) or part
		local ok, exists = pcall(fs.isFolder, cur)
		if not ok or not exists then pcall(fs.makeFolder, cur) end
	end
end

-- value (de)serialisation: JSON can't hold Color3 ------------------------------------------------
local function encode(v)
	if typeof(v) == "Color3" then return { __t = "Color3", r = v.R, g = v.G, b = v.B } end
	return v
end

local function decode(v)
	if type(v) == "table" and v.__t == "Color3" then return Color3.new(v.r, v.g, v.b) end
	return v
end

local SaveManager = {}
SaveManager.__index = SaveManager

function SaveManager.new(window, opts)
	opts = opts or {}
	local self = setmetatable({}, SaveManager)
	self.Window = window
	self.Folder = clean(opts.Folder or window.Folder or "UiLib")
	if self.Folder == "" then self.Folder = "UiLib" end
	self.User = clean(Players.LocalPlayer and Players.LocalPlayer.Name or "Player")
	self.Ignore = {}
	self.Quiet = opts.Quiet == true
	if opts.Ignore then self:SetIgnore(opts.Ignore) end

	genv.__SaveManagerMemory = genv.__SaveManagerMemory or {}
	genv.__SaveManagerMemory[self.Folder] = genv.__SaveManagerMemory[self.Folder] or { configs = {}, autoload = {} }
	self._mem = genv.__SaveManagerMemory[self.Folder]
	return self
end

function SaveManager:SetIgnore(list)
	for _, k in ipairs(list) do self.Ignore[tostring(k)] = true end
	return self
end

function SaveManager:_say(title, text)
	if self.Quiet then return end
	print("[SaveManager] " .. title .. ": " .. text)
	pcall(function() self.Window:Notify(title, text, 3) end)
end

function SaveManager:_path(name) return self.Folder .. "/" .. clean(name) .. ".json" end
function SaveManager:_autoPath() return self.Folder .. "/autoload_" .. self.User .. ".txt" end
function SaveManager:_sharedAutoPath() return self.Folder .. "/autoload.txt" end

function SaveManager:List()
	local out, seen = {}, {}
	if hasFS then
		ensureFolder(self.Folder)
		local ok, files = pcall(fs.list, self.Folder)
		if ok and type(files) == "table" then
			for _, f in ipairs(files) do
				local n = string.match(f, "([^/\\]+)%.json$")
				if n and not seen[n] then
					seen[n] = true
					out[#out + 1] = n
				end
			end
		end
	else
		for k in pairs(self._mem.configs) do out[#out + 1] = k end
	end
	table.sort(out)
	return out
end

function SaveManager:Save(name)
	name = clean(name)
	if name == "" then return false, "a config needs a name" end
	local values = {}
	for k, v in pairs(self.Window:Values(true)) do
		if not self.Ignore[k] then values[k] = encode(v) end
	end
	local ok, json = pcall(function()
		return HttpService:JSONEncode({ __ui = "UiLib", __user = self.User, values = values })
	end)
	if not ok then return false, "could not encode: " .. tostring(json) end
	if hasFS then
		ensureFolder(self.Folder)
		local ok2, err = pcall(fs.write, self:_path(name), json)
		if not ok2 then return false, tostring(err) end
	else
		self._mem.configs[name] = json
	end
	return true, name
end

function SaveManager:Load(name)
	name = clean(name)
	if name == "" then return false, "a config needs a name" end
	local json
	if hasFS then
		local ok, exists = pcall(fs.isFile, self:_path(name))
		if not ok or not exists then return false, "no config named '" .. name .. "'" end
		local ok2, data = pcall(fs.read, self:_path(name))
		if not ok2 then return false, tostring(data) end
		json = data
	else
		json = self._mem.configs[name]
		if not json then return false, "no config named '" .. name .. "'" end
	end
	local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
	if not ok or type(data) ~= "table" or type(data.values) ~= "table" then
		return false, "'" .. name .. "' isn't a valid config"
	end
	self.Window.Loading = true
	local applied, skipped = 0, 0
	for k, v in pairs(data.values) do
		local ctrl = self.Window._controls[k]
		if ctrl and ctrl.def.save ~= false and not self.Ignore[k] then
			self.Window:Set(k, decode(v))
			applied += 1
		else
			skipped += 1
		end
	end
	self.Window.Loading = false
	if skipped > 0 then warn("[SaveManager] loaded '" .. name .. "' (" .. applied .. " applied, " .. skipped .. " unknown keys ignored)") end
	return true, name
end

function SaveManager:Delete(name)
	name = clean(name)
	if name == "" then return false, "a config needs a name" end
	if hasFS then
		if type(fs.delete) ~= "function" then return false, "this executor can't delete files" end
		local ok, err = pcall(fs.delete, self:_path(name))
		if not ok then return false, tostring(err) end
	else
		self._mem.configs[name] = nil
	end
	if self:GetAutoload() == name then self:ClearAutoload() end
	return true, name
end

function SaveManager:SetAutoload(name)
	name = clean(name)
	if name == "" then return false end
	if hasFS then
		ensureFolder(self.Folder)
		pcall(fs.write, self:_autoPath(), name)
	else
		self._mem.autoload[self.User] = name
	end
	return true, name
end

function SaveManager:ClearAutoload()
	if hasFS then
		ensureFolder(self.Folder)
		pcall(fs.write, self:_autoPath(), "")
	else
		self._mem.autoload[self.User] = false
	end
end

function SaveManager:GetAutoload()
	if hasFS then
		for _, p in ipairs({ self:_autoPath(), self:_sharedAutoPath() }) do
			local ok, exists = pcall(fs.isFile, p)
			if ok and exists then
				local ok2, data = pcall(fs.read, p)
				if ok2 then
					local n = clean(data)
					if n ~= "" then return n end
					if p == self:_autoPath() then return nil end -- explicitly cleared for this account
				end
			end
		end
		return nil
	end
	local v = self._mem.autoload[self.User]
	return v or nil
end

function SaveManager:LoadAutoload()
	local name = self:GetAutoload()
	if not name then return false, "No autoload configured." end
	local ok, res = self:Load(name)
	if ok then self:_say("Autoload", "loaded '" .. res .. "'") end
	return ok, res
end

-- ready-made UI ----------------------------------------------------------------------------------
function SaveManager:BuildConfigTab(tabOrName)
	local win = self.Window
	local tab = tabOrName
	if tab == nil or type(tab) == "string" then
		tab = win:AddTab(tab or "Config")
	end
	self._tab = tab

	tab:AddSection("Configs")
	tab:AddDropdown({ key = "__sm.selected", label = "Config", options = self:List(), save = false, path = false })
	tab:AddInput({ key = "__sm.name", label = "Name", placeholder = "new config name", save = false, path = false })

	local function refresh()
		win:SetOptions("__sm.selected", self:List())
	end
	local function target()
		local typed = clean(win:Get("__sm.name"))
		if typed ~= "" then return typed end
		return clean(win:Get("__sm.selected"))
	end

	tab:AddButton({ label = "Save", callback = function()
		local ok, res = self:Save(target())
		self:_say(ok and "Saved" or "Save failed", tostring(res))
		if ok then
			refresh()
			win:Set("__sm.selected", res, true)
			win:Set("__sm.name", "", true)
		end
	end })
	tab:AddButton({ label = "Load", colour = Color3.fromRGB(58, 122, 96), callback = function()
		local ok, res = self:Load(clean(win:Get("__sm.selected")))
		self:_say(ok and "Loaded" or "Load failed", tostring(res))
	end })
	tab:AddButton({ label = "Refresh list", colour = win.Theme and win.Theme.Neutral or Color3.fromRGB(60, 60, 78), callback = refresh })

	tab:AddSection("Autoload")
	tab:AddLabel("Every account can use a different autoload config.")
	tab:AddButton({ label = "Set as autoload", colour = Color3.fromRGB(60, 60, 78), callback = function()
		local n = clean(win:Get("__sm.selected"))
		if n == "" then self:_say("Autoload", "pick a config first") return end
		self:SetAutoload(n)
		self:_say("Autoload", "'" .. n .. "' will load on start")
	end })
	tab:AddButton({ label = "Clear autoload", colour = Color3.fromRGB(60, 60, 78), callback = function()
		self:ClearAutoload()
		self:_say("Autoload", "cleared")
	end })

	tab:AddSection("Danger")
	tab:AddButton({ label = "Delete selected", colour = Color3.fromRGB(235, 51, 90), callback = function()
		local n = clean(win:Get("__sm.selected"))
		if n == "" then self:_say("Delete", "pick a config first") return end
		local ok, res = self:Delete(n)
		self:_say(ok and "Deleted" or "Delete failed", tostring(res))
		if ok then
			refresh()
			win:Set("__sm.selected", self:List()[1] or "", true)
		end
	end })

	local auto = self:GetAutoload()
	if auto then win:Set("__sm.selected", auto, true) end
	return tab
end

return SaveManager
