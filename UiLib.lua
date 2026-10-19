--[[
    UiLib  -  sketch-style Roblox UI library (extracted + cleaned from the Wyvern/Kraken panel)

    local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/<user>/<repo>/main/UiLib.lua"))()
    local Window  = Library:CreateWindow({ Title = "My Hub" })
    local Tab     = Window:AddTab("Main")
    Tab:AddToggle({ key = "Farm.Enabled", label = "Auto Farm", default = false, callback = function(v) end })

    Controls (all take a table, `key` must be unique per window):
        Tab:AddSection(text)
        Tab:AddLabel(text)
        Tab:AddDivider()
        Tab:AddButton{ label, callback, colour }
        Tab:AddToggle{ key, label, default, callback }
        Tab:AddSlider{ key, label, min, max, step, default, suffix, callback }
        Tab:AddDropdown{ key, label, options, default, callback }
        Tab:AddMultiDropdown{ label, options = { {key,label,default}, ... } }
        Tab:AddInput{ key, label, default, placeholder, numeric, callback }
        Tab:AddColorPicker{ key, label, default (Color3), callback }
        Tab:AddKeybind{ key, label, default ("None" / "F"), callback, onPress }

    Extra field on any control:  save = false   -> not stored in configs
                                 path = "A.B.C" -> where it is mirrored inside opts.Target (defaults to key)

    Window methods: Get, Set, SetMany, Values, ApplyTo, OnChange, SetOptions, GetOptions, RunCallbacks,
                    Open, Close, Toggle, IsOpen, SetTitle, SetVisible, Notify, SelectTab, GetTab, Destroy
]]

local cloneref = cloneref or function(i) return i end

local Players = cloneref(game:GetService("Players"))
local TweenService = cloneref(game:GetService("TweenService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TextService = cloneref(game:GetService("TextService"))
local LocalPlayer = Players.LocalPlayer

local genv = (getgenv and getgenv()) or _G

--------------------------------------------------------------------------------------------------
-- Library table / theme (edit Library.Theme fields BEFORE CreateWindow to restyle everything)
--------------------------------------------------------------------------------------------------
local Library = {}

Library.FontFace = Font.new("rbxassetid://12187375716", Enum.FontWeight.Regular, Enum.FontStyle.Normal)
Library.TextScale = 1 -- multiplies every text size in the UI (e.g. 1.15 = 15% bigger)
Library.Version = 3

Library.Theme = {
	Background = Color3.fromRGB(18, 14, 14),
	BackgroundTransparency = 0.04,
	Ink = Color3.fromRGB(240, 232, 222),
	Header = Color3.fromRGB(255, 170, 50),
	Label = Color3.fromRGB(245, 245, 240),
	Muted = Color3.fromRGB(175, 168, 160),
	Value = Color3.fromRGB(255, 255, 255),
	Accent = Color3.fromRGB(228, 122, 50),
	On = Color3.fromRGB(140, 230, 160),
	Off = Color3.fromRGB(50, 46, 44),
	Flash = Color3.fromRGB(255, 228, 190),
	Shadow = Color3.fromRGB(0, 0, 0),
	Danger = Color3.fromRGB(235, 51, 90),
	Well = Color3.fromRGB(24, 22, 22),
	List = Color3.fromRGB(22, 18, 18),
	Neutral = Color3.fromRGB(70, 62, 56),
}
local Theme = Library.Theme

Library.Defaults = {
	Title = "Menu",
	Folder = "UiLib",
	Width = 560,
	Height = 430,
	SidebarWidth = 148,
	Position = UDim2.new(0.5, 0, 0.5, 0),
	AnchorPoint = Vector2.new(0.5, 0.5),
	TogglePosition = UDim2.new(0, 24, 0.5, 0),
	ToggleSize = 60,
	AlwaysShowLauncher = true, -- launcher square stays visible while the window is open
	ToggleText = nil,
	ToggleIcon = nil, -- "rbxassetid://..."
	ToggleKeyCode = nil, -- Enum.KeyCode.RightShift
	StartOpen = false,
	Draggable = true,
	Resizable = true,
	MinWidth = 340,
	MinHeight = 150,
	MaxWidth = 900,
	MaxHeight = 600,
	Target = nil, -- table that mirrors every control value (by path)
	DisplayOrder = 14,
	ForceEnglish = true, -- disables Roblox auto-translation (AutoLocalize) on every UI element
}

--------------------------------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------------------------------
local function create(class, props, parent)
	local obj = Instance.new(class)
	for k, v in pairs(props or {}) do
		obj[k] = v
	end
	if parent then
		obj.Parent = parent
	end
	return obj
end

local function clamp(v, lo, hi)
	if v < lo then return lo end
	if v > hi then return hi end
	return v
end

local function randomName()
	local chars = table.create(10)
	for i = 1, 10 do
		chars[i] = string.char(math.random(97, 122))
	end
	return table.concat(chars)
end

local function decimalsOf(step)
	if not step or step <= 0 or step >= 1 then return 0 end
	local d = 0
	while d < 4 and math.abs(step - math.floor(step + 0.5)) > 1e-6 do
		step *= 10
		d += 1
	end
	return d
end

local function snap(value, min, step)
	if not step or step <= 0 then return value end
	local n = math.floor((value - min) / step + 0.5) * step + min
	local d = decimalsOf(step)
	if d == 0 then return n end
	local m = 10 ^ d
	return math.floor(n * m + 0.5) / m
end

local function formatNumber(value, step)
	local d = decimalsOf(step)
	if d == 0 then return tostring(math.floor(value + 0.5)) end
	return string.format("%." .. d .. "f", value)
end

local function splitPath(path)
	local parts = {}
	for p in string.gmatch(tostring(path), "[^%.]+") do
		parts[#parts + 1] = p
	end
	return parts
end

local function getPath(tbl, path)
	for _, p in ipairs(splitPath(path)) do
		if type(tbl) ~= "table" then return nil end
		tbl = tbl[p]
	end
	return tbl
end

local function setPath(tbl, path, value)
	local parts = splitPath(path)
	for i = 1, #parts - 1 do
		local nxt = tbl[parts[i]]
		if type(nxt) ~= "table" then
			nxt = {}
			tbl[parts[i]] = nxt
		end
		tbl = nxt
	end
	tbl[parts[#parts]] = value
end

local function getGuiParent()
	local ok, res = pcall(function() return gethui and gethui() or nil end)
	if ok and typeof(res) == "Instance" then return res, true end
	local ok2, core = pcall(function() return cloneref(game:GetService("CoreGui")) end)
	if ok2 and core then return core, true end
	return LocalPlayer:WaitForChild("PlayerGui"), false
end

local function protect(gui)
	pcall(function()
		if syn and syn.protect_gui then syn.protect_gui(gui)
		elseif protect_gui then protect_gui(gui) end
	end)
end

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- visuals --------------------------------------------------------------------------------------
local function textLabel(text, size, align)
	local l = create("TextLabel", {
		BackgroundTransparency = 1, BorderSizePixel = 0, Text = tostring(text), AutoLocalize = false,
		FontFace = Library.FontFace, TextSize = math.floor((size or 15) * (Library.TextScale or 1) + 0.5), TextColor3 = Theme.Label,
		TextXAlignment = align or Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		RichText = false,
	})
	create("UIStroke", { Color = Theme.Shadow, Thickness = 1.5, Transparency = 0.35, LineJoinMode = Enum.LineJoinMode.Round }, l)
	return l
end

local function sketchEdge(parent, color, thickness, transparency, rotation, pad, z)
	local f = create("Frame", {
		Name = "SketchEdge", BackgroundTransparency = 1, BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1, pad, 1, pad), Rotation = rotation, ZIndex = z or 0,
	}, parent)
	create("UIStroke", { Color = color, Thickness = thickness, Transparency = transparency, LineJoinMode = Enum.LineJoinMode.Round }, f)
	return f
end

local function addEdge(parent, color, z, scale)
	scale = scale or 1
	sketchEdge(parent, color, 2 * scale, 0.25, 0.35, 2 * scale, z)
	sketchEdge(parent, color, 1.5 * scale, 0.55, -0.5, -1 * scale, z)
end

local function plainStroke(parent, color, transparency)
	return create("UIStroke", {
		Color = color or Theme.Ink, Thickness = 1.5, Transparency = transparency or 0.8,
		LineJoinMode = Enum.LineJoinMode.Round,
	}, parent)
end

local HOVER_IN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local HOVER_OUT = TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local function hoverScale(parent, trigger, scale)
	trigger = trigger or parent
	scale = tonumber(scale) or 1.08
	local us = create("UIScale", { Scale = 1 }, parent)
	trigger.MouseEnter:Connect(function() TweenService:Create(us, HOVER_IN, { Scale = scale }):Play() end)
	trigger.MouseLeave:Connect(function() TweenService:Create(us, HOVER_OUT, { Scale = 1 }):Play() end)
	return us
end

local function hoverGlow(parent, trigger, color, baseTransparency)
	trigger = trigger or parent
	color = color or Theme.Accent
	local stroke = create("UIStroke", {
		Name = "HoverGlow", Thickness = 2, LineJoinMode = Enum.LineJoinMode.Round, Color = color,
		Transparency = baseTransparency == nil and 1 or baseTransparency,
	}, parent)
	local c0, t0, tr0 = stroke.Color, stroke.Thickness, stroke.Transparency
	trigger.MouseEnter:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.16, Enum.EasingStyle.Sine), { Color = color, Thickness = t0 + 0.5, Transparency = 0.1 }):Play()
	end)
	trigger.MouseLeave:Connect(function()
		TweenService:Create(stroke, TweenInfo.new(0.28, Enum.EasingStyle.Sine), { Color = c0, Thickness = t0, Transparency = tr0 }):Play()
	end)
	return stroke
end

local function pseudo(n) return (n * 9301 + 49297) % 233280 / 233280 * 2 - 1 end

local function makeRule(seed)
	local f = create("Frame", { Name = "Rule", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 6) })
	for i = 1, 6 do
		create("Frame", {
			Name = "Ink", BorderSizePixel = 0, BackgroundColor3 = Theme.Ink,
			BackgroundTransparency = 0.2 + 0.12 * math.abs(pseudo(seed * 31 + i)),
			AnchorPoint = Vector2.new(0, 0.5), Size = UDim2.new(0.1767, 0, 0, 2),
			Position = UDim2.new((i - 1) / 6, 0, 0.5, math.floor(pseudo(seed * 17 + i) * 1.6)),
			Rotation = pseudo(seed * 7 + i * 2) * 1.1,
		}, f)
	end
	return f
end

local function newRow(height)
	return create("Frame", { Name = "Row", BackgroundTransparency = 1, BorderSizePixel = 0, ClipsDescendants = false, Size = UDim2.new(1, 0, 0, height) })
end

local function newWell(size)
	local f = create("Frame", { Name = "Well", BackgroundColor3 = Theme.Well, BackgroundTransparency = 0.1, BorderSizePixel = 0, Size = UDim2.new(0, 0, 0, size) })
	addEdge(f, Theme.Ink, nil, 0.5)
	return f
end

local function newCheckBox(parent, size)
	local box = newWell(size)
	box.AnchorPoint = Vector2.new(1, 0.5)
	box.Position = UDim2.new(1, 0, 0.5, 0)
	box.Size = UDim2.new(0, size, 0, size)
	box.Parent = parent
	local fill = create("Frame", {
		Name = "Fill", BorderSizePixel = 0, BackgroundColor3 = Theme.Off, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 1, -8),
	}, box)
	local function render(on)
		on = on and true or false
		TweenService:Create(fill, TweenInfo.new(0.16), { BackgroundColor3 = on and Theme.On or Theme.Off, BackgroundTransparency = on and 0 or 0.35 }):Play()
	end
	return box, render
end

--------------------------------------------------------------------------------------------------
-- Tab (controls)
--------------------------------------------------------------------------------------------------
local Tab = {}
Tab.__index = Tab

function Tab:_attach(obj)
	self._order += 1
	obj.LayoutOrder = self._order
	obj.Parent = self.Page
	return obj
end

local function requireKey(def, what)
	if def.key == nil then
		if def.label ~= nil then
			def.key = def.label
			warn("[UiLib] " .. what .. " without 'key' - using label '" .. tostring(def.label) .. "' as key")
		else
			error("[UiLib] " .. what .. " needs a 'key'", 3)
		end
	end
end

function Tab:AddSection(text)
	local row = newRow(30)
	row.Name = "Section"
	local l = textLabel(string.upper(tostring(text)), 24, Enum.TextXAlignment.Left)
	l.TextColor3 = Theme.Muted
	l.Size = UDim2.new(1, 0, 0, 24)
	l.Parent = row
	local rule = makeRule(self._order + 2)
	rule.Position = UDim2.new(0, 0, 1, -6)
	rule.Parent = row
	self:_attach(row)
	return self
end

function Tab:AddLabel(text)
	local row = newRow(0)
	row.Name = "Label"
	row.AutomaticSize = Enum.AutomaticSize.Y
	local l = textLabel(text, 25, Enum.TextXAlignment.Left)
	l.TextColor3 = Theme.Muted
	l.TextWrapped = true
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Parent = row
	self:_attach(row)
	return self
end

function Tab:AddDivider()
	local row = newRow(6)
	row.Name = "Divider"
	makeRule(self._order + 11).Parent = row
	self:_attach(row)
	return self
end

function Tab:AddButton(def)
	local row = newRow(32)
	row.Name = "Button"
	local btn = create("TextButton", {
		AutoButtonColor = false, Text = "", BackgroundColor3 = def.colour or def.color or Theme.Header,
		BackgroundTransparency = 0.1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1),
	}, row)
	addEdge(btn, Theme.Ink, nil, 0.5)
	hoverGlow(btn, btn, Theme.Flash)
	hoverScale(btn, btn, 1.03)
	local l = textLabel(def.label or "Button", 26, Enum.TextXAlignment.Center)
	l.Size = UDim2.fromScale(1, 1)
	l.Parent = btn
	btn.MouseButton1Click:Connect(function()
		l.TextColor3 = Theme.Flash
		TweenService:Create(l, TweenInfo.new(0.35), { TextColor3 = Theme.Label }):Play()
		if type(def.callback) == "function" then
			local ok, err = pcall(def.callback)
			if not ok then warn("[UiLib] button '" .. tostring(def.label) .. "' errored: " .. tostring(err)) end
		end
	end)
	self:_attach(row)
	return self
end

function Tab:AddToggle(def)
	requireKey(def, "toggle")
	local window = self._window
	local row = newRow(26)
	row.Name = "Toggle_" .. tostring(def.key)
	local hit = create("TextButton", { Name = "Hit", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, row)
	local l = textLabel(def.label or def.key, 13)
	l.Size = UDim2.new(1, -34, 1, 0)
	l.Parent = hit
	local box, render = newCheckBox(hit, 22)
	hoverScale(box, hit, 1.15)
	hoverGlow(box, hit, Theme.Accent)
	hit.MouseButton1Click:Connect(function() window:Set(def.key, not window:Get(def.key)) end)
	window:_register(def, "toggle", render, false)
	self:_attach(row)
	return self
end

function Tab:AddSlider(def)
	requireKey(def, "slider")
	local window = self._window
	local lo, hi = tonumber(def.min) or 0, tonumber(def.max) or 1
	if hi < lo then lo, hi = hi, lo end
	local step = tonumber(def.step) or 0
	local suffix = def.suffix and tostring(def.suffix) or ""

	local row = newRow(48)
	row.Name = "Slider_" .. tostring(def.key)
	local l = textLabel(def.label or def.key, 26)
	l.Size = UDim2.new(1, -90, 0, 22)
	l.Parent = row
	local readout = textLabel("", 13, Enum.TextXAlignment.Right)
	readout.TextColor3 = Theme.Accent
	readout.Size = UDim2.new(0, 90, 0, 22)
	readout.Position = UDim2.new(1, -90, 0, 0)
	readout.Parent = row

	local track = create("TextButton", {
		Name = "Track", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Well, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 0, 28),
	}, row)
	addEdge(track, Theme.Ink, nil, 0.5)
	hoverGlow(track, track, Theme.Accent)
	local fill = create("Frame", { Name = "Fill", BorderSizePixel = 0, BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.1, Size = UDim2.new(0, 0, 1, 0) }, track)

	local function render(v)
		v = clamp(tonumber(v) or lo, lo, hi)
		fill.Size = UDim2.new(hi > lo and (v - lo) / (hi - lo) or 0, 0, 1, 0)
		readout.Text = formatNumber(v, step) .. suffix
	end
	local function fromX(x)
		local w = track.AbsoluteSize.X
		if w <= 0 then return lo end
		return clamp(snap(lo + clamp((x - track.AbsolutePosition.X) / w, 0, 1) * (hi - lo), lo, step), lo, hi)
	end
	track.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		window._activeSlider = function(x) window:Set(def.key, fromX(x)) end
		window._activeSlider(input.Position.X)
	end)

	local ctrl = window:_register(def, "slider", render, lo)
	ctrl.low, ctrl.high, ctrl.step = lo, hi, step
	window:Set(def.key, window:Get(def.key), true) -- clamp the initial value
	self:_attach(row)
	return self
end

-- popup list used by both dropdowns ---------------------------------------------------------------
local function makePopup(window, row, baseHeight, px, pw)
	px, pw = px or 0.42, pw or 0.58
	local list = create("ScrollingFrame", {
		Name = "Options", Visible = false, Active = true, BackgroundColor3 = Theme.List, BackgroundTransparency = 0.04,
		BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = Theme.Ink, ScrollBarImageTransparency = 0.5,
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, Size = UDim2.new(pw, 0, 0, 0),
		Position = UDim2.new(px, 0, 0, baseHeight), ZIndex = 3,
	}, row)
	plainStroke(list)
	create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder }, list)

	local popup = { List = list, Open = false, Count = 0, Arrow = nil }
	local function h() return math.min(popup.Count, 8) * 24 end
	function popup.resize()
		row.Size = UDim2.new(1, 0, 0, baseHeight + (popup.Open and h() + 4 or 0))
		list.Size = UDim2.new(pw, 0, 0, popup.Open and h() or 0)
	end
	function popup.set(state)
		state = state and popup.Count > 0
		if popup.Open == state then return end
		popup.Open = state
		list.Visible = state
		if popup.Arrow then popup.Arrow.Text = state and "^" or "v" end
		popup.resize()
		if state then
			if window._openDropdown and window._openDropdown ~= popup.set then window._openDropdown(false) end
			window._openDropdown = popup.set
		elseif window._openDropdown == popup.set then
			window._openDropdown = nil
		end
	end
	return popup
end

local function newSelectedButton(row, text)
	local btn = create("TextButton", {
		Name = "Selected", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Well, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, Size = UDim2.new(0.58, 0, 0, 28), Position = UDim2.new(0.42, 0, 0, 2),
	}, row)
	addEdge(btn, Theme.Ink, nil, 0.5)
	hoverGlow(btn, btn, Theme.Accent)
	local l = textLabel(text or "", 26)
	l.Size = UDim2.new(1, -22, 1, 0)
	l.Position = UDim2.new(0, 8, 0, 0)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = btn
	local arrow = textLabel("v", 24, Enum.TextXAlignment.Center)
	arrow.TextColor3 = Theme.Muted
	arrow.Size = UDim2.new(0, 22, 1, 0)
	arrow.Position = UDim2.new(1, -24, 0, 0)
	arrow.Parent = btn
	return btn, l, arrow
end

local function hoverRow(btn)
	btn.MouseEnter:Connect(function()
		btn.BackgroundColor3 = Theme.Ink
		TweenService:Create(btn, TweenInfo.new(0.14), { BackgroundTransparency = 0.85 }):Play()
	end)
	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
	end)
end

function Tab:AddDropdown(def)
	requireKey(def, "dropdown")
	local window = self._window
	local options = {}
	for _, o in ipairs(def.options or {}) do options[#options + 1] = tostring(o) end

	local row = newRow(32)
	row.Name = "Dropdown_" .. tostring(def.key)
	local l = textLabel(def.label or def.key, 13)
	l.Size = UDim2.new(0.42, -6, 0, 32)
	l.Parent = row
	local selBtn, selLabel, arrow = newSelectedButton(row, "")
	local popup = makePopup(window, row, 32)
	popup.Arrow = arrow
	popup.Count = #options
	local buttons = {}

	local function highlight(v)
		for name, lab in pairs(buttons) do lab.TextColor3 = name == tostring(v) and Theme.Accent or Theme.Label end
	end
	local function rebuild()
		for _, c in ipairs(popup.List:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		buttons = {}
		popup.Count = #options
		for i, name in ipairs(options) do
			local b = create("TextButton", { Name = "Option_" .. name, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i }, popup.List)
			local t = textLabel(name, 25)
			t.Size = UDim2.new(1, -16, 1, 0)
			t.Position = UDim2.new(0, 8, 0, 0)
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.Parent = b
			buttons[name] = t
			hoverRow(b)
			b.MouseButton1Click:Connect(function()
				popup.set(false)
				window:Set(def.key, name)
			end)
		end
		highlight(window:Get(def.key))
		popup.resize()
	end
	local function render(v)
		selLabel.Text = (v == nil or v == "") and "--" or tostring(v)
		selLabel.TextColor3 = (v == nil or v == "") and Theme.Muted or Theme.Label
		highlight(v)
	end
	selBtn.MouseButton1Click:Connect(function() popup.set(not popup.Open) end)
	rebuild()
	local ctrl = window:_register(def, "dropdown", render, options[1])
	ctrl.setOptions = function(list)
		options = {}
		for _, o in ipairs(list or {}) do options[#options + 1] = tostring(o) end
		rebuild()
		render(window:Get(def.key))
	end
	ctrl.getOptions = function() return table.clone(options) end
	self:_attach(row)
	return self
end

function Tab:AddMultiDropdown(def)
	local window = self._window
	local options = def.options or {}
	local row = newRow(32)
	row.Name = "MultiDropdown_" .. tostring(def.label or "")
	local l = textLabel(def.label or "Select", 26)
	l.Size = UDim2.new(0.42, -6, 0, 32)
	l.Parent = row
	local selBtn, selLabel, arrow = newSelectedButton(row, "")
	local popup = makePopup(window, row, 32)
	popup.Arrow = arrow
	popup.Count = #options

	local function summary()
		local n = 0
		for _, o in ipairs(options) do
			if window:Get(o.key) then n += 1 end
		end
		selLabel.Text = n .. "/" .. #options .. " selected"
		selLabel.TextColor3 = n == 0 and Theme.Muted or Theme.Label
	end
	selBtn.MouseButton1Click:Connect(function() popup.set(not popup.Open) end)

	for i, option in ipairs(options) do
		local b = create("TextButton", { Name = "Option_" .. tostring(option.key), Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i }, popup.List)
		local t = textLabel(option.label or option.key, 14)
		t.Size = UDim2.new(1, -30, 1, 0)
		t.Position = UDim2.new(0, 8, 0, 0)
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.Parent = b
		local box, render = newCheckBox(b, 16)
		box.Position = UDim2.new(1, -8, 0.5, 0)
		hoverScale(box, b, 1.15)
		hoverRow(b)
		b.MouseButton1Click:Connect(function() window:Set(option.key, not window:Get(option.key)) end)
		window:_register(option, "toggle", function(v) render(v) summary() end, false)
	end
	summary()
	self:_attach(row)
	return self
end

function Tab:AddInput(def)
	requireKey(def, "input")
	local window = self._window
	local row = newRow(32)
	row.Name = "Input_" .. tostring(def.key)
	local l = textLabel(def.label or def.key, 26)
	l.Size = UDim2.new(0.42, -8, 1, 0)
	l.Parent = row
	local well = newWell(24)
	well.Size = UDim2.new(0.58, 0, 0, 24)
	well.Position = UDim2.new(0.42, 0, 0, 2)
	well.Parent = row
	hoverGlow(well, well, Theme.Accent)
	local box = create("TextBox", {
		Name = "Field", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -14, 1, 0), Position = UDim2.new(0, 7, 0, 0), AutoLocalize = false,
		FontFace = Library.FontFace, TextSize = math.floor(25 * (Library.TextScale or 1) + 0.5), TextColor3 = Theme.Value, PlaceholderText = tostring(def.placeholder or ""),
		PlaceholderColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ClipsDescendants = true, Text = "",
	}, well)
	local function render(v)
		if box:IsFocused() then return end
		box.Text = v == nil and "" or tostring(v)
	end
	box.FocusLost:Connect(function()
		if def.numeric then
			local n = tonumber(box.Text)
			if n == nil then render(window:Get(def.key)) return end
			window:Set(def.key, n)
		else
			window:Set(def.key, box.Text)
		end
	end)
	window:_register(def, "input", render, def.numeric and 0 or "")
	self:_attach(row)
	return self
end

-- original Wyvern controls: account-name box + dropdown on one row -------------------------------
function Tab:AddColumnHeader(def)
	def = def or {}
	local row = newRow(24)
	row.Name = "ColumnHeader"
	local function col(text, x, w)
		local l = textLabel(string.upper(tostring(text or "")), 23, Enum.TextXAlignment.Left)
		l.TextColor3 = Theme.Muted
		l.Size = UDim2.new(w, -4, 1, 0)
		l.Position = UDim2.new(x, 0, 0, 0)
		l.Parent = row
	end
	col(def.left, 0, 0.3)
	col(def.middle, 0.3, 0.4)
	col(def.right, 0.7, def.right2 and 0.15 or 0.3)
	if def.right2 then col(def.right2, 0.85, 0.15) end
	self:_attach(row)
	return self
end

local function newFieldBox(row, def, xScale, wScale)
	local well = newWell(30)
	well.Size = UDim2.new(wScale, -4, 0, 30)
	well.Position = UDim2.new(xScale, 0, 0, 2)
	well.Parent = row
	hoverGlow(well, well, Theme.Accent)
	local box = create("TextBox", {
		Name = "Field", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -14, 1, 0), Position = UDim2.new(0, 7, 0, 0), AutoLocalize = false,
		FontFace = Library.FontFace, TextSize = math.floor(25 * (Library.TextScale or 1) + 0.5), TextColor3 = Theme.Value, PlaceholderText = tostring(def.placeholder or ""),
		PlaceholderColor3 = Theme.Muted, TextXAlignment = Enum.TextXAlignment.Left, ClearTextOnFocus = false, ClipsDescendants = true, Text = "",
	}, well)
	return box
end

local function wireFieldBox(window, box, def)
	local function render(v)
		if box:IsFocused() then return end
		box.Text = v == nil and "" or tostring(v)
	end
	box.FocusLost:Connect(function()
		if def.numeric then
			local n = tonumber(box.Text)
			if n == nil then render(window:Get(def.key)) return end
			window:Set(def.key, n)
		else
			window:Set(def.key, box.Text)
		end
	end)
	window:_register(def, "input", render, def.numeric and 0 or "")
end

local function newSmallSelected(row, textSize)
	local btn = create("TextButton", {
		Name = "Selected", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Well, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, Size = UDim2.new(0.3, 0, 0, 30), Position = UDim2.new(0.7, 0, 0, 2),
	}, row)
	addEdge(btn, Theme.Ink, nil, 0.5)
	hoverGlow(btn, btn, Theme.Accent)
	local l = textLabel("", textSize or 24)
	l.Size = UDim2.new(1, -24, 1, 0)
	l.Position = UDim2.new(0, 6, 0, 0)
	l.TextTruncate = Enum.TextTruncate.AtEnd
	l.Parent = btn
	local arrow = textLabel("v", 23, Enum.TextXAlignment.Center)
	arrow.TextColor3 = Theme.Muted
	arrow.Size = UDim2.new(0, 16, 1, 0)
	arrow.Position = UDim2.new(1, -18, 0, 0)
	arrow.Parent = btn
	return btn, l, arrow
end

-- def: key/label/placeholder/numeric (the text box) + dropdownKey/dropdownOptions/dropdownDefault/dropdownCallback/dropdownPath (the dropdown)
function Tab:AddInputDropdown(def)
	requireKey(def, "inputdropdown")
	local window = self._window
	local options = {}
	for _, o in ipairs(def.dropdownOptions or {}) do options[#options + 1] = tostring(o) end
	local row = newRow(34)
	row.Name = "InputDropdown_" .. tostring(def.key)
	local l = textLabel(def.label or def.key, 13)
	l.Size = UDim2.new(0.3, -6, 0, 34)
	l.Parent = row
	wireFieldBox(window, newFieldBox(row, def, 0.3, 0.4), def)

	local ddef = { key = def.dropdownKey, label = def.dropdownLabel, default = def.dropdownDefault, path = def.dropdownPath, callback = def.dropdownCallback }
	local selBtn, selLabel, arrow = newSmallSelected(row, 24)
	local popup = makePopup(window, row, 34, 0.7, 0.3)
	popup.Arrow = arrow
	popup.Count = #options
	local buttons = {}
	local function highlight(v)
		for name, lab in pairs(buttons) do lab.TextColor3 = name == tostring(v) and Theme.Accent or Theme.Label end
	end
	local function rebuild()
		for _, c in ipairs(popup.List:GetChildren()) do
			if c:IsA("TextButton") then c:Destroy() end
		end
		buttons = {}
		popup.Count = #options
		for i, name in ipairs(options) do
			local b = create("TextButton", { Name = "Option_" .. name, Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i }, popup.List)
			local t = textLabel(name, 24)
			t.Size = UDim2.new(1, -12, 1, 0)
			t.Position = UDim2.new(0, 6, 0, 0)
			t.TextTruncate = Enum.TextTruncate.AtEnd
			t.Parent = b
			buttons[name] = t
			hoverRow(b)
			b.MouseButton1Click:Connect(function()
				popup.set(false)
				window:Set(ddef.key, name)
			end)
		end
		if ddef.key ~= nil then highlight(window:Get(ddef.key)) end
		popup.resize()
	end
	local function render(v)
		selLabel.Text = (v == nil or v == "") and "--" or tostring(v)
		selLabel.TextColor3 = (v == nil or v == "") and Theme.Muted or Theme.Label
		highlight(v)
	end
	selBtn.MouseButton1Click:Connect(function() popup.set(not popup.Open) end)
	rebuild()
	if ddef.key ~= nil then
		local ctrl = window:_register(ddef, "dropdown", render, options[1])
		ctrl.setOptions = function(list)
			options = {}
			for _, o in ipairs(list or {}) do options[#options + 1] = tostring(o) end
			rebuild()
			render(window:Get(ddef.key))
		end
		ctrl.getOptions = function() return table.clone(options) end
	end
	self:_attach(row)
	return self
end

-- def: key/label/placeholder (the text box) + dropdownOptions = { {key,label,default}, ... } (each is its own boolean key)
function Tab:AddInputMultiDropdown(def)
	requireKey(def, "inputmultidropdown")
	local window = self._window
	local options = def.dropdownOptions or {}
	local row = newRow(34)
	row.Name = "InputMultiDropdown_" .. tostring(def.key)
	local l = textLabel(def.label or def.key, 26)
	l.Size = UDim2.new(0.3, -6, 0, 34)
	l.Parent = row
	wireFieldBox(window, newFieldBox(row, def, 0.3, 0.4), def)

	local selBtn, selLabel, arrow = newSmallSelected(row, 24)
	local popup = makePopup(window, row, 34, 0.7, 0.3)
	popup.Arrow = arrow
	popup.Count = #options
	local function summary()
		local n = 0
		for _, o in ipairs(options) do
			if window:Get(o.key) then n += 1 end
		end
		selLabel.Text = n .. "/" .. #options
		selLabel.TextColor3 = n == 0 and Theme.Muted or Theme.Label
	end
	selBtn.MouseButton1Click:Connect(function() popup.set(not popup.Open) end)
	for i, option in ipairs(options) do
		local b = create("TextButton", { Name = "Option_" .. tostring(option.key), Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = i }, popup.List)
		local t = textLabel(option.label or option.key, 14)
		t.Size = UDim2.new(1, -30, 1, 0)
		t.Position = UDim2.new(0, 6, 0, 0)
		t.TextTruncate = Enum.TextTruncate.AtEnd
		t.Parent = b
		local box, render = newCheckBox(b, 16)
		box.Position = UDim2.new(1, -8, 0.5, 0)
		hoverScale(box, b, 1.15)
		hoverRow(b)
		b.MouseButton1Click:Connect(function() window:Set(option.key, not window:Get(option.key)) end)
		window:_register(option, "toggle", function(v) render(v) summary() end, false)
	end
	summary()
	self:_attach(row)
	return self
end


function Tab:AddColorPicker(def)
	requireKey(def, "colorpicker")
	local window = self._window
	local channels = { "R", "G", "B" }
	local row = newRow(32)
	row.Name = "ColorPicker_" .. tostring(def.key)
	local l = textLabel(def.label or def.key, 26)
	l.Size = UDim2.new(1, -40, 1, 0)
	l.Parent = row
	local swatch = create("TextButton", {
		Name = "Swatch", Text = "", AutoButtonColor = false, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 22, 0, 22), BackgroundColor3 = Color3.new(1, 1, 1),
	}, row)
	addEdge(swatch, Theme.Ink, nil, 0.5)
	hoverScale(swatch, swatch, 1.15)
	hoverGlow(swatch, swatch, Theme.Accent)

	local panelHeight = 86
	local panel = create("Frame", {
		Name = "Panel", Visible = false, BackgroundColor3 = Theme.List, BackgroundTransparency = 0.04, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, 32), ZIndex = 3,
	}, row)
	addEdge(panel, Theme.Ink, nil, 0.5)

	local parts = {}
	for i, ch in ipairs(channels) do
		local r = create("Frame", { Name = "Channel_" .. ch, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -16, 0, 22), Position = UDim2.new(0, 8, 0, 8 + (i - 1) * 26), ZIndex = 3 }, panel)
		local t = textLabel(ch, 14)
		t.Size = UDim2.new(0, 16, 1, 0)
		t.ZIndex = 3
		t.Parent = r
		local track = create("TextButton", {
			Name = "Track", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Well, BackgroundTransparency = 0.15,
			BorderSizePixel = 0, Size = UDim2.new(1, -52, 1, 0), Position = UDim2.new(0, 20, 0, 0), ZIndex = 3,
		}, r)
		addEdge(track, Theme.Ink, nil, 0.5)
		local fill = create("Frame", { Name = "Fill", BorderSizePixel = 0, BackgroundColor3 = Theme.Accent, BackgroundTransparency = 0.1, Size = UDim2.new(0, 0, 1, 0), ZIndex = 4 }, track)
		local read = textLabel("", 13, Enum.TextXAlignment.Right)
		read.TextColor3 = Theme.Accent
		read.Size = UDim2.new(0, 28, 1, 0)
		read.Position = UDim2.new(1, -28, 0, 0)
		read.ZIndex = 3
		read.Parent = r
		parts[ch] = { track = track, fill = fill, read = read }
	end

	local function channelOf(c, ch) return ch == "R" and c.R or ch == "G" and c.G or c.B end
	local function withChannel(c, ch, v)
		return Color3.new(ch == "R" and v or c.R, ch == "G" and v or c.G, ch == "B" and v or c.B)
	end
	local function render(c)
		c = typeof(c) == "Color3" and c or Color3.new(1, 1, 1)
		swatch.BackgroundColor3 = c
		for ch, p in pairs(parts) do
			local v = channelOf(c, ch)
			p.fill.Size = UDim2.new(v, 0, 1, 0)
			p.read.Text = tostring(math.floor(v * 255 + 0.5))
		end
	end

	local open = false
	local function setOpen(state)
		if open == state then return end
		open = state
		panel.Visible = open
		row.Size = UDim2.new(1, 0, 0, 32 + (open and panelHeight + 4 or 0))
		panel.Size = UDim2.new(1, 0, 0, open and panelHeight or 0)
		if open then
			if window._openDropdown and window._openDropdown ~= setOpen then window._openDropdown(false) end
			window._openDropdown = setOpen
		elseif window._openDropdown == setOpen then
			window._openDropdown = nil
		end
	end
	swatch.MouseButton1Click:Connect(function() setOpen(not open) end)

	for ch, p in pairs(parts) do
		p.track.InputBegan:Connect(function(input)
			if not isPointer(input) then return end
			window._activeSlider = function(x)
				local cur = window:Get(def.key)
				if typeof(cur) ~= "Color3" then cur = Color3.new(1, 1, 1) end
				local w = p.track.AbsoluteSize.X
				if w <= 0 then return end
				window:Set(def.key, withChannel(cur, ch, clamp((x - p.track.AbsolutePosition.X) / w, 0, 1)))
			end
			window._activeSlider(input.Position.X)
		end)
	end

	window:_register(def, "colorpicker", render, Color3.fromRGB(255, 255, 220))
	self:_attach(row)
	return self
end

function Tab:AddKeybind(def)
	requireKey(def, "keybind")
	local window = self._window
	local row = newRow(26)
	row.Name = "Keybind_" .. tostring(def.key)
	local l = textLabel(def.label or def.key, 26)
	l.Size = UDim2.new(1, -100, 1, 0)
	l.Parent = row
	local btn = create("TextButton", {
		Name = "Bind", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Well, BackgroundTransparency = 0.15,
		BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.new(0, 92, 0, 22),
	}, row)
	addEdge(btn, Theme.Ink, nil, 0.5)
	hoverGlow(btn, btn, Theme.Accent)
	local t = textLabel("None", 13, Enum.TextXAlignment.Center)
	t.Size = UDim2.fromScale(1, 1)
	t.Parent = btn

	local listening = false
	local function render(v)
		t.Text = listening and "..." or ((v and v ~= "") and tostring(v) or "None")
		t.TextColor3 = listening and Theme.Flash or Theme.Label
	end
	btn.MouseButton1Click:Connect(function()
		listening = true
		render(window:Get(def.key))
	end)
	window:_track(UserInputService.InputBegan:Connect(function(input, gp)
		if window._destroyed then return end
		if listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				listening = false
				window:Set(def.key, input.KeyCode == Enum.KeyCode.Escape and "None" or input.KeyCode.Name)
				render(window:Get(def.key))
			end
			return
		end
		if gp then return end
		local v = window:Get(def.key)
		if v and v ~= "None" and input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == v and type(def.onPress) == "function" then
			task.spawn(def.onPress)
		end
	end))
	window:_register(def, "keybind", render, def.default or "None")
	self:_attach(row)
	return self
end

--------------------------------------------------------------------------------------------------
-- Window
--------------------------------------------------------------------------------------------------
local Window = {}
Window.__index = Window

function Window:_track(conn)
	table.insert(self._connections, conn)
	return conn
end

function Window:_makeDraggable(handle, target, onFinish)
	handle.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		local startMouse = input.Position
		local parent = target.Parent
		local origin = parent and parent.AbsolutePosition or Vector2.zero
		local startPos = target.AbsolutePosition - origin -- relative to the parent, so the GUI inset can't shift it
		local moved = false
		self._activeDrag = function(pos)
			local d = pos - startMouse
			if d.Magnitude > 3 then moved = true end
			target.AnchorPoint = Vector2.new(0, 0)
			target.Position = UDim2.fromOffset(math.floor(startPos.X + d.X), math.floor(startPos.Y + d.Y))
		end
		self._dragFinish = function()
			if onFinish then onFinish(moved) end
		end
	end)
end

function Window:_buildInput()
	self:_track(UserInputService.InputChanged:Connect(function(input)
		if self._destroyed then return end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if self._activeSlider then self._activeSlider(input.Position.X) end
		if self._activeDrag then self._activeDrag(input.Position) end
		if self._activeResize then self._activeResize(input.Position) end
	end))
	self:_track(UserInputService.InputEnded:Connect(function(input)
		if not isPointer(input) then return end
		self._activeSlider = nil
		self._activeResize = nil
		if self._activeDrag then
			local finish = self._dragFinish
			self._activeDrag, self._dragFinish = nil, nil
			if finish then finish() end
		end
	end))
	self:_track(UserInputService.InputBegan:Connect(function(input, gp)
		if self._destroyed or gp then return end
		if self._opt.ToggleKeyCode and input.KeyCode == self._opt.ToggleKeyCode then
			self:Toggle()
		end
	end))
end

function Window:_buildToggleButton()
	local size = self._opt.ToggleSize
	local btn = create("TextButton", {
		Name = "Launcher", Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Header, BackgroundTransparency = 1,
		BorderSizePixel = 0, Size = UDim2.fromOffset(size, size), Position = self._opt.TogglePosition, AnchorPoint = Vector2.new(0, 0.5),
	}, self.Gui)
	self.Launcher = btn
	addEdge(btn, Theme.Ink, 1)
	hoverGlow(btn, btn, Theme.Flash, 0.6)
	hoverScale(btn, btn, 1.1)
	if self._opt.ToggleIcon then
		btn.BackgroundColor3 = Color3.new(0, 0, 0)
		btn.BackgroundTransparency = 0.35
		create("ImageLabel", { Name = "Icon", BackgroundTransparency = 1, Image = self._opt.ToggleIcon, ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromScale(1, 1), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5), ZIndex = 2 }, btn)
	else
		local text = self._opt.ToggleText
		if type(text) ~= "string" or text == "" then
			text = string.upper(string.sub(tostring(self._opt.Title), 1, 1))
		end
		btn.BackgroundTransparency = 0.1
		local t = textLabel(text, math.floor(size * 0.52), Enum.TextXAlignment.Center)
		t.Size = UDim2.fromScale(1, 1)
		t.ZIndex = 2
		t.Parent = btn
	end
	self:_makeDraggable(btn, btn, function(moved)
		if not moved then self:Toggle() end
	end)
end

function Window:_layoutDivider()
	if not self.Divider then return end
	self.Divider.Size = UDim2.new(0, self._opt.Height - 58, 0, 6)
	self.Divider.Position = UDim2.new(0, self._opt.SidebarWidth, 0.5, 19)
end

function Window:_makeResizable(root)
	local grip = create("TextButton", { Name = "Grip", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, 0, 1, 0), Size = UDim2.fromOffset(26, 18), ZIndex = 4 }, root)
	hoverScale(grip, grip, 1.2)
	local arrow = textLabel("v", 20, Enum.TextXAlignment.Center) -- same font as the rest; rotated to point down-right
	arrow.Name = "Arrow"
	arrow.AnchorPoint = Vector2.new(0.5, 0.5)
	arrow.Position = UDim2.new(0.5, 0, 0.5, 0)
	arrow.Size = UDim2.fromOffset(20, 20)
	arrow.Rotation = -45
	arrow.TextColor3 = Theme.Muted
	arrow.ZIndex = 4
	arrow.Parent = grip
	grip.MouseEnter:Connect(function() TweenService:Create(arrow, TweenInfo.new(0.16), { TextColor3 = Theme.Flash }):Play() end)
	grip.MouseLeave:Connect(function() TweenService:Create(arrow, TweenInfo.new(0.22), { TextColor3 = Theme.Muted }):Play() end)
	grip.InputBegan:Connect(function(input)
		if not isPointer(input) then return end
		local startMouse = input.Position
		local w, h = self._opt.Width, self._opt.Height
		self._activeResize = function(pos)
			local d = pos - startMouse
			self._opt.Width = clamp(math.floor(w + d.X), self._opt.MinWidth, self._opt.MaxWidth)
			self._opt.Height = clamp(math.floor(h + d.Y), self._opt.MinHeight, self._opt.MaxHeight)
			root.Size = UDim2.fromOffset(self._opt.Width, self._opt.Height)
			self:_layoutDivider()
		end
	end)
	self.ResizeGrip = grip
end

function Window:_buildWindow()
	local opt = self._opt
	local root = create("Frame", {
		Name = "Window", Visible = false, BackgroundColor3 = Theme.Background, BackgroundTransparency = Theme.BackgroundTransparency,
		BorderSizePixel = 0, Size = UDim2.fromOffset(opt.Width, opt.Height), Position = opt.Position, AnchorPoint = opt.AnchorPoint,
	}, self.Gui)
	self.Root = root
	self.RootScale = create("UIScale", { Scale = 1 }, root)
	addEdge(root, Theme.Ink, 0)

	-- header
	local header = create("TextButton", { Name = "Header", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.05, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 38) }, root)
	self.Header = header
	local grad = create("UIGradient", {
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Theme.Header), ColorSequenceKeypoint.new(0.55, Theme.Header), ColorSequenceKeypoint.new(1, Theme.Flash) }),
		Rotation = -12, Offset = Vector2.new(-0.8, 0),
	}, header)
	self._headerRotate = TweenService:Create(grad, TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Rotation = 12 })
	self._headerSweep = TweenService:Create(grad, TweenInfo.new(2.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Offset = Vector2.new(0.35, 0) })
	self._headerRotate:Play()
	self._headerSweep:Play()
	addEdge(header, Theme.Ink, 1)

	local title = textLabel(opt.Title, 26, Enum.TextXAlignment.Left)
	title.Name = "Title"
	title.Size = UDim2.new(1, -80, 1, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.ZIndex = 2
	title.Parent = header
	self.Title = title

	local close = create("TextButton", { Name = "Close", Text = "", AutoButtonColor = false, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromOffset(40, 28), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), ZIndex = 2 }, header)
	local x = textLabel("x", 24, Enum.TextXAlignment.Center)
	x.Name = "X"
	x.Size = UDim2.fromScale(1, 1)
	x.ZIndex = 3
	x.Parent = close
	hoverGlow(close, close, Theme.Danger, 0.55)
	hoverScale(close, close, 1.2)
	close.MouseEnter:Connect(function() TweenService:Create(x, TweenInfo.new(0.16), { TextColor3 = Theme.Flash }):Play() end)
	close.MouseLeave:Connect(function() TweenService:Create(x, TweenInfo.new(0.22), { TextColor3 = Theme.Label }):Play() end)
	close.MouseButton1Click:Connect(function() self:Close() end)

	-- sidebar
	local sidebar = create("ScrollingFrame", {
		Name = "Tabs", Active = true, BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 2, ScrollBarImageColor3 = Theme.Ink,
		ScrollBarImageTransparency = 0.6, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(0, opt.SidebarWidth, 1, -38), Position = UDim2.new(0, 0, 0, 38),
	}, root)
	self.Sidebar = sidebar
	local tabList = create("Frame", { Name = "TabList", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }, sidebar)
	self.TabList = tabList
	create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, tabList)
	create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 6) }, sidebar)
	local marker = textLabel("I", 24, Enum.TextXAlignment.Center)
	marker.Name = "Marker"
	marker.TextColor3 = Theme.Accent
	marker.TextTransparency = 1
	marker.Size = UDim2.fromOffset(10, 28)
	marker.ZIndex = 2
	marker.Parent = sidebar
	self.Marker = marker

	-- divider
	local divider = makeRule(10)
	divider.Rotation = 90
	divider.AnchorPoint = Vector2.new(0.5, 0.5)
	divider.Parent = root
	self.Divider = divider
	self:_layoutDivider()

	self.Pages = create("Frame", { Name = "Pages", BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -opt.SidebarWidth, 1, -38), Position = UDim2.new(0, opt.SidebarWidth, 0, 38) }, root)

	if opt.Draggable then self:_makeDraggable(header, root, nil) end
	if opt.Resizable then self:_makeResizable(root) end

	-- notifications
	local holder = create("Frame", { Name = "Notifications", BackgroundTransparency = 1, BorderSizePixel = 0, AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -16), Size = UDim2.new(0, 260, 1, -32), ZIndex = 20 }, self.Gui)
	create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 6) }, holder)
	self._notifyHolder = holder
end

function Window:_build()
	local parent, protected = getGuiParent()
	local gui = create("ScreenGui", { Name = randomName(), ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = self._opt.DisplayOrder })
	if protected then protect(gui) end

	-- keep the UI in English: stop Roblox from auto-translating any text in it
	if self._opt.ForceEnglish ~= false then
		local function lock(o)
			if o:IsA("GuiBase2d") then
				pcall(function() o.AutoLocalize = false end)
			end
		end
		lock(gui)
		self._lockEnglish = lock
		self:_track(gui.DescendantAdded:Connect(lock))
	end

	gui.Parent = parent
	self.Gui = gui
	self:_buildToggleButton()
	self:_buildWindow()
	self:_buildInput()
	if self._opt.StartOpen then self:Open() end
end

-- tabs -------------------------------------------------------------------------------------------
function Window:AddTab(name)
	assert(not self._destroyed, "Window is destroyed")
	name = tostring(name)
	self._tabCount += 1
	local order = self._tabCount
	local tab = setmetatable({ _window = self, Name = name, _order = 0, SidebarOrder = order }, Tab)

	local btn = create("TextButton", { Name = "Tab_" .. name, Text = "", AutoButtonColor = false, BackgroundColor3 = Theme.Ink, BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = order }, self.TabList)
	tab.Button = btn
	local label = textLabel(name, Library.TabTextSize or 26)
	label.Size = UDim2.new(1, -16, 1, 0)
	label.Position = UDim2.new(0, 14, 0, 0)
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Parent = btn
	tab.Label = label

	local page = create("ScrollingFrame", {
		Name = "Page_" .. name, Visible = false, Active = true, BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4,
		ScrollBarImageColor3 = Theme.Ink, ScrollBarImageTransparency = 0.5, CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		Size = UDim2.fromScale(1, 1),
	}, self.Pages)
	tab.Page = page
	create("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, page)
	create("UIPadding", { PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 16), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14) }, page)

	hoverGlow(btn, btn, Theme.Accent)
	btn.MouseEnter:Connect(function()
		if self._active ~= tab then TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundTransparency = 0.9 }):Play() end
	end)
	btn.MouseLeave:Connect(function()
		if self._active ~= tab then TweenService:Create(btn, TweenInfo.new(0.2), { BackgroundTransparency = 1 }):Play() end
	end)
	btn.MouseButton1Click:Connect(function() self:SelectTab(name) end)

	self._tabs[#self._tabs + 1] = tab
	if not self._active then self:SelectTab(name) end
	return tab
end

function Window:GetTab(name)
	for _, t in ipairs(self._tabs) do
		if t.Name == name then return t end
	end
	return nil
end

function Window:SelectTab(name)
	local found
	for _, t in ipairs(self._tabs) do
		local vis = t.Name == name
		t.Page.Visible = vis
		t.Button.BackgroundTransparency = vis and 0.86 or 1
		t.Label.TextColor3 = vis and Theme.Value or Theme.Label
		if vis then
			self._active = t
			found = t
		end
	end
	if found then self:_moveMarker(found) end
	return self
end

function Window:_moveMarker(tab)
	local marker = self.Marker
	local first = self._markerTab == nil
	self._markerTab = tab
	if self._markerShimmer then
		self._markerShimmer:Cancel()
		self._markerShimmer = nil
	end
	local pos = UDim2.new(0, 0, 0, (tab.SidebarOrder - 1) * 34 + 1)
	marker.TextColor3 = Theme.Flash
	if first then
		marker.Position = pos
		TweenService:Create(marker, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextTransparency = 0 }):Play()
	else
		TweenService:Create(marker, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = pos }):Play()
	end
	TweenService:Create(marker, TweenInfo.new(0.3), { TextColor3 = Theme.Accent }):Play()
	task.delay(0.35, function()
		if self._destroyed or self._markerTab ~= tab then return end
		local tw = TweenService:Create(marker, TweenInfo.new(1.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { TextColor3 = Theme.Accent:Lerp(Color3.new(1, 1, 1), 0.4) })
		self._markerShimmer = tw
		tw:Play()
	end)
end

-- values -----------------------------------------------------------------------------------------
function Window:_writeThrough(ctrl, value)
	if ctrl.path and self._opt.Target then
		setPath(self._opt.Target, ctrl.path, value)
	end
end

function Window:_register(def, kind, render, fallback)
	local key = tostring(def.key)
	if self._controls[key] then
		warn("[UiLib] duplicate control key '" .. key .. "' -- the second one won't be saved")
	end
	local path = def.path
	if path == nil then path = key end
	local ctrl = { def = def, kind = kind, key = key, path = path, render = render }
	self._controls[key] = ctrl
	local value = nil
	if path and self._opt.Target then value = getPath(self._opt.Target, path) end
	if value == nil then value = def.default end
	if value == nil then value = fallback end
	self._values[key] = value
	pcall(render, value)
	self:_writeThrough(ctrl, value)
	return ctrl
end

function Window:Set(key, value, silent)
	if self._destroyed then return self end
	key = tostring(key)
	local ctrl = self._controls[key]
	if not ctrl then
		warn("[UiLib] Set: no control named '" .. key .. "'")
		return self
	end
	if ctrl.kind == "slider" then
		local n = tonumber(value)
		if n == nil then return self end
		value = clamp(snap(n, ctrl.low, ctrl.step), ctrl.low, ctrl.high)
	elseif ctrl.kind == "toggle" then
		value = value and true or false
	elseif ctrl.kind == "colorpicker" then
		if typeof(value) ~= "Color3" then return self end
	end
	local old = self._values[key]
	self._values[key] = value
	self:_writeThrough(ctrl, value)
	pcall(ctrl.render, value)
	if silent or old == value then return self end
	if type(ctrl.def.callback) == "function" then
		local ok, err = pcall(ctrl.def.callback, value)
		if not ok then warn("[UiLib] callback for '" .. key .. "' errored: " .. tostring(err)) end
	end
	for _, fn in ipairs(self._listeners) do
		pcall(fn, key, value, old)
	end
	return self
end

function Window:Get(key)
	return self._values[tostring(key)]
end

function Window:SetMany(tbl, silent)
	for k, v in pairs(tbl) do self:Set(k, v, silent) end
	return self
end

function Window:Values(onlySaved)
	local out = {}
	for k, v in pairs(self._values) do
		local ctrl = self._controls[k]
		if not (onlySaved and ctrl and ctrl.def.save == false) then out[k] = v end
	end
	return out
end

function Window:ApplyTo(tbl)
	for _, ctrl in pairs(self._controls) do
		if ctrl.path then setPath(tbl, ctrl.path, self._values[ctrl.key]) end
	end
	return tbl
end

function Window:OnChange(fn)
	assert(type(fn) == "function", "OnChange needs a function")
	table.insert(self._listeners, fn)
	return function()
		for i, f in ipairs(self._listeners) do
			if f == fn then table.remove(self._listeners, i) return end
		end
	end
end

-- fires every control's callback with its current value (handy right after loading a config / on startup)
-- kept for compatibility with scripts that call it (does nothing by itself)
function Window:Preload() return self end

function Window:RunCallbacks()
	for key, ctrl in pairs(self._controls) do
		if type(ctrl.def.callback) == "function" then
			task.spawn(function() pcall(ctrl.def.callback, self._values[key]) end)
		end
	end
end

function Window:SetOptions(key, list)
	local ctrl = self._controls[tostring(key)]
	if ctrl and ctrl.setOptions then ctrl.setOptions(list) end
	return self
end

function Window:GetOptions(key)
	local ctrl = self._controls[tostring(key)]
	return ctrl and ctrl.getOptions and ctrl.getOptions() or {}
end

-- open / close -----------------------------------------------------------------------------------
local TWEEN_OPEN = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local TWEEN_CLOSE = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

function Window:Open()
	if self._destroyed then return self end
	self._open = true
	if self._popTween then self._popTween:Cancel() end
	self.Root.Visible = true
	self.Launcher.Visible = self._opt.AlwaysShowLauncher ~= false
	self.RootScale.Scale = 0.85
	self._popTween = TweenService:Create(self.RootScale, TWEEN_OPEN, { Scale = 1 })
	self._popTween:Play()
	return self
end

function Window:Close()
	if self._destroyed then return self end
	self._open = false
	self.Launcher.Visible = true
	if self._openDropdown then self._openDropdown(false) end
	if self._popTween then self._popTween:Cancel() end
	local tw = TweenService:Create(self.RootScale, TWEEN_CLOSE, { Scale = 0.85 })
	self._popTween = tw
	tw:Play()
	tw.Completed:Connect(function()
		if not self._destroyed and not self._open then self.Root.Visible = false end
	end)
	return self
end

function Window:Toggle()
	if self._open then return self:Close() end
	return self:Open()
end

function Window:IsOpen() return self._open end

function Window:SetToggleKey(keyCode) self._opt.ToggleKeyCode = keyCode return self end

function Window:SetTitle(text)
	if self.Title then self.Title.Text = tostring(text) end
	return self
end

function Window:SetVisible(state)
	state = state and true or false
	if self.Launcher then self.Launcher.Visible = state and (self._opt.AlwaysShowLauncher ~= false or not self._open) end
	if self.Root then self.Root.Visible = state and self._open end
	return self
end

local function measureText(text, size, width)
	local ok, res = pcall(function()
		local params = Instance.new("GetTextBoundsParams")
		params.Text = text
		params.Font = Library.FontFace
		params.Size = size
		params.Width = width
		return TextService:GetTextBoundsAsync(params).Y
	end)
	if ok and type(res) == "number" and res > 0 then return math.ceil(res) end
	local lines = math.max(1, math.ceil(#text * size * 0.55 / width))
	return lines * (size + 2)
end

function Window:Notify(title, text, duration)
	if self._destroyed then return end
	duration = tonumber(duration) or 4
	title, text = tostring(title or ""), tostring(text or "")
	-- fixed, measured height (no AutomaticSize) so a toast can never grow past its text
	local innerWidth = 240
	local bodyH = measureText(text, 14, innerWidth)
	local toast = create("Frame", {
		BackgroundColor3 = Theme.Background, BackgroundTransparency = Theme.BackgroundTransparency, BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 8 + 18 + 2 + bodyH + 8), ClipsDescendants = true, ZIndex = 20,
	}, self._notifyHolder)
	plainStroke(toast, Theme.Ink, 0.35)
	local t = textLabel(title, 15)
	t.TextColor3 = Theme.Header
	t.Size = UDim2.new(1, -20, 0, 18)
	t.Position = UDim2.new(0, 10, 0, 8)
	t.ZIndex = 21
	t.Parent = toast
	local b = textLabel(text, 14)
	b.TextWrapped = true
	b.TextYAlignment = Enum.TextYAlignment.Top
	b.Size = UDim2.new(1, -20, 0, bodyH)
	b.Position = UDim2.new(0, 10, 0, 28)
	b.ZIndex = 21
	b.Parent = toast
	task.delay(duration, function()
		if toast.Parent then toast:Destroy() end
	end)
end

function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
	self._connections, self._listeners = {}, {}
	for _, tw in ipairs({ "_markerShimmer", "_headerRotate", "_headerSweep", "_popTween" }) do
		if self[tw] then pcall(function() self[tw]:Cancel() end) self[tw] = nil end
	end
	if self.Gui then pcall(function() self.Gui:Destroy() end) end
	self.Gui, self.Root, self.Header, self.Sidebar, self.Pages, self.Launcher = nil, nil, nil, nil, nil, nil
	if self._registry and self._registry[self.Folder] == self then self._registry[self.Folder] = nil end
end

--------------------------------------------------------------------------------------------------
-- Library:CreateWindow
--------------------------------------------------------------------------------------------------
function Library:CreateWindow(opts)
	opts = opts or {}
	if opts.Theme then
		for k, v in pairs(opts.Theme) do Theme[k] = v end
	end
	local self = setmetatable({}, Window)
	self._opt = {}
	for k, v in pairs(Library.Defaults) do self._opt[k] = v end
	for k, v in pairs(opts) do
		if v ~= nil and k ~= "Theme" then self._opt[k] = v end
	end
	self._tabs, self._tabCount, self._controls, self._values = {}, 0, {}, {}
	self._listeners, self._connections = {}, {}
	self._open, self._destroyed = false, false
	self.Folder = tostring(self._opt.Folder):gsub("[^%w%-_ ]", "")
	if self.Folder == "" then self.Folder = "UiLib" end
	self.User = LocalPlayer and LocalPlayer.Name:gsub("[^%w%-_ ]", "") or "Player"

	genv.__UiLibWindows = genv.__UiLibWindows or {}
	local reg = genv.__UiLibWindows
	if reg[self.Folder] and reg[self.Folder] ~= self then pcall(function() reg[self.Folder]:Destroy() end) end
	reg[self.Folder] = self
	self._registry = reg

	self:_build()
	return self
end

Library.FormatNumber = formatNumber
return Library
