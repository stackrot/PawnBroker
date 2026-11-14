-- The PawnBroker window: budget and level controls, the plan as rows you
-- can hover for the item tooltip, click to search the AH or shift-click
-- to link, and the suffix scan button with its progress.

local _, ns = ...

local ROW = 22
local PAD = 14
local COLUMNS = {	-- key, title, width, justify
	{ "slot", "Slot", 64, "LEFT" },
	{ "item", "Item", 236, "LEFT" },
	{ "price", "Price", 92, "RIGHT" },
	{ "net", "Net", 84, "RIGHT" },
	{ "gain", "Pawn gain", 104, "RIGHT" },
	{ "req", "Req", 34, "RIGHT" },
	{ "listed", "Listed", 46, "RIGHT" },
}
local GAP = 6	-- between columns
local SCROLLBAR = 30
-- Wide enough for every column beside the row icon.
local WIDTH = (function()
	local w = ROW + 2
	for _, c in ipairs(COLUMNS) do
		w = w + c[3] + GAP
	end
	return w + 2 * PAD + SCROLLBAR
end)()
local HEIGHT = 480
local ICON = 133784	-- a gold coin, for the portrait
local BUDGET_HELP = "Budget: blank for the gold you carry, 1g50s, 50s, "
	.. "or all."
local NEAR_HELP = "Near vendor price: /pb near 10s, or /pb near off."
local NET_HELP = "Plan by net cost: what each item costs once you sell it "
	.. "to a vendor. The budget then caps the net total, not what you pay "
	.. "up front."

local f	-- the window

local function settings()
	local db = ns.db()
	db.ui = db.ui or {}
	return db.ui
end

local function text(parent, font, justify)
	local s = parent:CreateFontString(nil, "OVERLAY", font)
	s:SetJustifyH(justify or "LEFT")
	s:SetWordWrap(false)
	return s
end

local function button(parent, label, width, onClick)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 22)
	b:SetText(label)
	b:SetScript("OnClick", onClick)
	return b
end

local function input(parent, width, onEnter)
	local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	e:SetSize(width, 20)
	e:SetAutoFocus(false)
	e:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		onEnter()
	end)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	return e
end

-- Searches the AH through Auctionator: exact name for ordinary items, the
-- base name for random-suffix ones so every version shows.
local function search(o)
	if not ns.ahOpen() then
		return f:SetStatus("Open the AH to search for items.")
	end
	local api = Auctionator.API.v1
	local exact = o.search:sub(1, 1) == '"'
	local ok = pcall(exact and api.MultiSearchExact or api.MultiSearch,
		ns.ADDON, { exact and o.name or o.search })
	if not ok then
		f:SetStatus("Auctionator couldn't start that search.")
	end
end

local function insertLink(link)
	local insert = ChatFrameUtil and ChatFrameUtil.InsertLink
		or ChatEdit_InsertLink
	if insert then
		insert(link)
	end
end

local function rowEnter(row)
	if not row.option then
		return
	end
	GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
	local o = row.option
	GameTooltip:SetHyperlink(o.link)
	GameTooltip:AddLine(" ")
	if o.vendor > 0 then
		GameTooltip:AddLine(string.format("Vendors for %s, so it costs %s "
			.. "once you sell it on.", ns.coins(o.vendor),
			ns.netText(o, ns.coins)), 1, 1, 1, true)
	end
	GameTooltip:AddLine("Click to search the AH, shift-click to link.",
		0.6, 0.6, 0.6)
	GameTooltip:Show()
end

local function rowClick(row)
	local o = row.option
	if not o then
		return
	end
	if IsModifiedClick("CHATLINK") then
		return insertLink(o.link)
	end
	search(o)
end

local function newRow(parent)
	local row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW)
	row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight",
		"ADD")
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(ROW - 4, ROW - 4)
	row.icon:SetPoint("LEFT", 2, 0)
	row.cells = {}
	local x = ROW + 2
	for _, c in ipairs(COLUMNS) do
		local cell = text(row, "GameFontHighlightSmall", c[4])
		cell:SetPoint("LEFT", x, 0)
		cell:SetWidth(c[3])
		row.cells[c[1]] = cell
		x = x + c[3] + GAP
	end
	row.title = text(row, "GameFontNormal")
	row.title:SetPoint("LEFT", 4, 0)
	row:SetScript("OnEnter", rowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnClick", rowClick)
	return row
end

local function row(i)
	local rows = f.rows
	if not rows[i] then
		rows[i] = newRow(f.list)
		rows[i]:SetPoint("TOPLEFT", 0, -(i - 1) * ROW)
		rows[i]:SetPoint("RIGHT", f.list, "RIGHT")
	end
	rows[i]:Show()
	return rows[i]
end

local function fillTitle(r, label, color)
	r.option = nil
	r.icon:Hide()
	for _, cell in pairs(r.cells) do
		cell:SetText("")
	end
	r.title:SetText(label)
	r.title:SetTextColor(color[1], color[2], color[3])
	r:EnableMouse(false)
end

local GREEN, WHITE = { 0.25, 1, 0.25 }, { 1, 1, 1 }

-- Net cost turns green at or under the near-vendor limit.
local function fillOption(r, o, nearLimit)
	r.option = o
	r.title:SetText("")
	r.icon:SetTexture(select(5, C_Item.GetItemInfoInstant(o.link)))
	r.icon:Show()
	local pct = o.beat > 0 and ns.percent(o) or "new"
	r.cells.slot:SetText(o.group)
	r.cells.item:SetText(o.link)
	r.cells.price:SetText(ns.coins(o.price))
	r.cells.net:SetText(ns.netText(o, ns.coins))
	local near = nearLimit and o.net <= nearLimit
	r.cells.net:SetTextColor(unpack(near and GREEN or WHITE))
	r.cells.gain:SetText(string.format("+%.1f (%s)", o.gain, pct))
	r.cells.req:SetText(o.level)
	r.cells.listed:SetText(o.listed or "")
	r:EnableMouse(true)
end

local GOLD, GREY = { 1, 0.82, 0 }, { 0.6, 0.6, 0.6 }

local function render(plan)
	local n = 0
	local function add(fill, ...)
		n = n + 1
		fill(row(n), ...)
	end
	if #plan.chosen == 0 then
		add(fillTitle, "Nothing in the scan beats your gear within "
			.. "budget.", GREY)
	else
		add(fillTitle, ns.buyLine(plan, ns.coins), GOLD)
	end
	for _, o in ipairs(plan.chosen) do
		add(fillOption, o, plan.nearLimit)
	end
	if #plan.over > 0 then
		add(fillTitle, "Better, but over budget", GREY)
	end
	for _, o in ipairs(plan.over) do
		add(fillOption, o, plan.nearLimit)
	end
	if #plan.near > 0 then
		add(fillTitle, string.format("Near vendor price (net %s or less)",
			ns.coins(plan.nearLimit)), GREEN)
	end
	for _, o in ipairs(plan.near) do
		add(fillOption, o, plan.nearLimit)
	end
	for i = n + 1, #f.rows do
		f.rows[i]:Hide()
	end
	f.list:SetHeight(math.max(1, n * ROW))
end

local function controls()
	local ui = settings()
	local label = text(f, "GameFontNormalSmall")
	label:SetPoint("TOPLEFT", PAD + 4, -62)
	label:SetText("Budget")
	f.budget = input(f, 80, function() f:Plan() end)
	f.budget:SetPoint("LEFT", label, "RIGHT", 10, 0)
	f.budget:SetText(ui.budget or "")
	f.budget:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(BUDGET_HELP, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.budget:SetScript("OnLeave", GameTooltip_Hide)
	local ahead = text(f, "GameFontNormalSmall")
	ahead:SetPoint("LEFT", f.budget, "RIGHT", 14, 0)
	ahead:SetText("Levels above")
	f.ahead = input(f, 28, function() f:Plan() end)
	f.ahead:SetPoint("LEFT", ahead, "RIGHT", 10, 0)
	f.ahead:SetNumeric(true)
	f.ahead:SetMaxLetters(2)
	f.ahead:SetText(ui.ahead or "")
	f.net = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	f.net:SetSize(24, 24)
	f.net:SetPoint("LEFT", f.ahead, "RIGHT", 10, 0)
	f.net:SetChecked(ui.net == true)
	f.net:SetScript("OnClick", function() f:Plan() end)
	f.net:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(NET_HELP, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	f.net:SetScript("OnLeave", GameTooltip_Hide)
	local net = text(f, "GameFontNormalSmall")
	net:SetPoint("LEFT", f.net, "RIGHT", 2, 0)
	net:SetText("Net cost")
	f.planButton = button(f, "Plan", 80, function() f:Plan() end)
	f.planButton:SetPoint("LEFT", net, "RIGHT", 14, 0)
	f.scanButton = button(f, "Scan suffixes", 120, function()
		if ns.scanning() then
			ns.stopScan()
		else
			ns.scan()
		end
	end)
	f.scanButton:SetPoint("TOPRIGHT", -PAD - 4, -58)
end

local function columns(top)
	local x = PAD + 6 + ROW + 2
	for _, c in ipairs(COLUMNS) do
		local head = text(f, "GameFontNormalSmall", c[4])
		head:SetPoint("TOPLEFT", x, top)
		head:SetWidth(c[3])
		head:SetText(c[2])
		x = x + c[3] + GAP
	end
end

local function listArea(top, bottom)
	local ok, inset = pcall(CreateFrame, "Frame", nil, f,
		"InsetFrameTemplate")
	if not ok then
		inset = CreateFrame("Frame", nil, f)
	end
	inset:SetPoint("TOPLEFT", PAD, top)
	inset:SetPoint("BOTTOMRIGHT", -PAD, bottom)
	local scroll = CreateFrame("ScrollFrame", nil, inset,
		"ScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -4)
	scroll:SetPoint("BOTTOMRIGHT", -24, 4)
	f.list = CreateFrame("Frame", nil, scroll)
	f.list:SetSize(WIDTH - 2 * PAD - SCROLLBAR, 1)
	scroll:SetScrollChild(f.list)
	f.rows = {}
end

local function footer()
	f.notes = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	f.notes:SetPoint("BOTTOMLEFT", PAD + 4, 34)
	f.notes:SetPoint("RIGHT", -PAD - 4, 0)
	f.notes:SetJustifyH("LEFT")
	f.notes:SetJustifyV("BOTTOM")
	f.notes:SetSpacing(2)
	f.status = text(f, "GameFontHighlightSmall")
	f.status:SetPoint("BOTTOMLEFT", PAD + 4, 14)
	f.status:SetPoint("RIGHT", -PAD - 4, 0)
end

local function window()
	f = CreateFrame("Frame", "PawnBrokerFrame", UIParent,
		"PortraitFrameTemplate")
	f:SetSize(WIDTH, HEIGHT)
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	f:SetScript("OnHide", GameTooltip_Hide)
	if f.SetTitle then
		f:SetTitle("PawnBroker")
	end
	local portrait = f.GetPortrait and f:GetPortrait()
	if portrait then
		portrait:SetTexture(ICON)
	end
	table.insert(UISpecialFrames, "PawnBrokerFrame")
	f.header = text(f, "GameFontHighlight")
	f.header:SetPoint("TOPLEFT", 64, -34)
	f.header:SetPoint("RIGHT", -PAD, 0)
	controls()
	columns(-92)
	listArea(-108, 96)
	footer()
	f:Hide()
end

local methods = {}

function methods:SetStatus(msg)
	self.status:SetText((msg:gsub("^%l", string.upper)))
end

-- Scan button: "Stop scan" while one runs, usable only with the AH open.
function methods:Refresh()
	local scanning = ns.scanning()
	self.scanButton:SetText(scanning and "Stop scan" or "Scan suffixes")
	self.scanButton:SetEnabled(scanning or ns.ahOpen())
end

-- Plans from the controls; note, if given, replaces the status line
-- once the plan is shown.
function methods:Plan(note)
	local budget = strtrim(self.budget:GetText())
	local ahead = tonumber(self.ahead:GetText()) or 0
	local net = self.net:GetChecked() and true or false
	local opts = ns.parse(budget .. (ahead > 0 and (" +" .. ahead) or "")
		.. (net and " net" or ""))
	if not opts then
		self:Show()
		return self:SetStatus(BUDGET_HELP)
	end
	local ui = settings()
	ui.budget, ui.ahead = budget, ahead > 0 and tostring(ahead) or ""
	ui.net = net
	-- false turns the near-vendor list off; unset means the default.
	if ui.near ~= false then
		opts.near = ui.near or ns.NEAR
	end
	self.note = note
	self:Show()
	ns.plan(opts)
end

-- "near 10s" or "near off" from a /pb line: copper, false for off, or
-- nil when the word after "near" isn't either.
local function nearLimit(word)
	word = (word or ""):lower()
	if word == "off" then
		return false
	end
	if word:find("^[%dgsc]+$") and word:find("%d[gsc]") then
		return ns.copper(word)
	end
end

-- Fills the controls from a /pb command line, then plans.
function methods:PlanFrom(msg)
	local budget, ahead, net = {}, "", false
	local words = {}
	for word in msg:gmatch("%S+") do
		words[#words + 1] = word
	end
	local i = 1
	while i <= #words do
		local word = words[i]
		local n = word:match("^%+(%d+)$")
		if n then
			ahead = n
		elseif word:lower() == "net" then
			net = true
		elseif word:lower() == "near" then
			local limit = nearLimit(words[i + 1])
			if limit == nil then
				self:Show()
				return self:SetStatus(NEAR_HELP)
			end
			settings().near = limit
			i = i + 1
		else
			budget[#budget + 1] = word
		end
		i = i + 1
	end
	self.budget:SetText(table.concat(budget, " "))
	self.ahead:SetText(ahead)
	self.net:SetChecked(net)
	self:Plan()
end

function methods:ShowPlan(plan)
	self.header:SetText(plan.header)
	render(plan)
	self.notes:SetText(table.concat(plan.notes, "\n"))
	self:SetStatus(self.note or "Plan ready.")
	self.note = nil
	self:Refresh()
	self:Show()
end

window()
for name, fn in pairs(methods) do
	f[name] = fn
end
ns.ui = f
