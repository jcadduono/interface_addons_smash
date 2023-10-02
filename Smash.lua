local ADDON = 'Smash'
if select(2, UnitClass('player')) ~= 'WARRIOR' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

Smash = {}
local Opt -- use this as a local table reference to Smash

SLASH_Smash1, SLASH_Smash2 = '/smash', '/sm'
BINDING_HEADER_SMASH = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(Smash, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			animation = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			arms = false,
			fury = false,
			protection = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		cd_ttd = 10,
		pot = false,
		trinket = true,
		heal_threshold = 60,
		defensives = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- specialization constants
local SPEC = {
	NONE = 0,
	ARMS = 1,
	FURY = 2,
	PROTECTION = 3,
}

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.ARMS] = {},
	[SPEC.FURY] = {},
	[SPEC.PROTECTION] = {},
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	rage = {
		current = 0,
		deficit = 0,
		max = 100,
		pct = 0,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	set_bonus = {
		t29 = 0, -- Stones of the Walking Mountain
		t30 = 0, -- Irons of the Onyx Crucible
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

local smashPanel = CreateFrame('Frame', 'smashPanel', UIParent)
smashPanel:SetPoint('CENTER', 0, -169)
smashPanel:SetFrameStrata('BACKGROUND')
smashPanel:SetSize(64, 64)
smashPanel:SetMovable(true)
smashPanel:SetUserPlaced(true)
smashPanel:RegisterForDrag('LeftButton')
smashPanel:SetScript('OnDragStart', smashPanel.StartMoving)
smashPanel:SetScript('OnDragStop', smashPanel.StopMovingOrSizing)
smashPanel:Hide()
smashPanel.icon = smashPanel:CreateTexture(nil, 'BACKGROUND')
smashPanel.icon:SetAllPoints(smashPanel)
smashPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashPanel.border = smashPanel:CreateTexture(nil, 'ARTWORK')
smashPanel.border:SetAllPoints(smashPanel)
smashPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
smashPanel.border:Hide()
smashPanel.dimmer = smashPanel:CreateTexture(nil, 'BORDER')
smashPanel.dimmer:SetAllPoints(smashPanel)
smashPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
smashPanel.dimmer:Hide()
smashPanel.swipe = CreateFrame('Cooldown', nil, smashPanel, 'CooldownFrameTemplate')
smashPanel.swipe:SetAllPoints(smashPanel)
smashPanel.swipe:SetDrawBling(false)
smashPanel.swipe:SetDrawEdge(false)
smashPanel.text = CreateFrame('Frame', nil, smashPanel)
smashPanel.text:SetAllPoints(smashPanel)
smashPanel.text.tl = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.tl:SetPoint('TOPLEFT', smashPanel, 'TOPLEFT', 2.5, -3)
smashPanel.text.tl:SetJustifyH('LEFT')
smashPanel.text.tr = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.tr:SetPoint('TOPRIGHT', smashPanel, 'TOPRIGHT', -2.5, -3)
smashPanel.text.tr:SetJustifyH('RIGHT')
smashPanel.text.bl = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.bl:SetPoint('BOTTOMLEFT', smashPanel, 'BOTTOMLEFT', 2.5, 3)
smashPanel.text.bl:SetJustifyH('LEFT')
smashPanel.text.br = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.br:SetPoint('BOTTOMRIGHT', smashPanel, 'BOTTOMRIGHT', -2.5, 3)
smashPanel.text.br:SetJustifyH('RIGHT')
smashPanel.text.center = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.center:SetAllPoints(smashPanel.text)
smashPanel.text.center:SetJustifyH('CENTER')
smashPanel.text.center:SetJustifyV('CENTER')
smashPanel.button = CreateFrame('Button', nil, smashPanel)
smashPanel.button:SetAllPoints(smashPanel)
smashPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local smashPreviousPanel = CreateFrame('Frame', 'smashPreviousPanel', UIParent)
smashPreviousPanel:SetFrameStrata('BACKGROUND')
smashPreviousPanel:SetSize(64, 64)
smashPreviousPanel:SetMovable(true)
smashPreviousPanel:SetUserPlaced(true)
smashPreviousPanel:RegisterForDrag('LeftButton')
smashPreviousPanel:SetScript('OnDragStart', smashPreviousPanel.StartMoving)
smashPreviousPanel:SetScript('OnDragStop', smashPreviousPanel.StopMovingOrSizing)
smashPreviousPanel:Hide()
smashPreviousPanel.icon = smashPreviousPanel:CreateTexture(nil, 'BACKGROUND')
smashPreviousPanel.icon:SetAllPoints(smashPreviousPanel)
smashPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashPreviousPanel.border = smashPreviousPanel:CreateTexture(nil, 'ARTWORK')
smashPreviousPanel.border:SetAllPoints(smashPreviousPanel)
smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
local smashCooldownPanel = CreateFrame('Frame', 'smashCooldownPanel', UIParent)
smashCooldownPanel:SetFrameStrata('BACKGROUND')
smashCooldownPanel:SetSize(64, 64)
smashCooldownPanel:SetMovable(true)
smashCooldownPanel:SetUserPlaced(true)
smashCooldownPanel:RegisterForDrag('LeftButton')
smashCooldownPanel:SetScript('OnDragStart', smashCooldownPanel.StartMoving)
smashCooldownPanel:SetScript('OnDragStop', smashCooldownPanel.StopMovingOrSizing)
smashCooldownPanel:Hide()
smashCooldownPanel.icon = smashCooldownPanel:CreateTexture(nil, 'BACKGROUND')
smashCooldownPanel.icon:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashCooldownPanel.border = smashCooldownPanel:CreateTexture(nil, 'ARTWORK')
smashCooldownPanel.border:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
smashCooldownPanel.dimmer = smashCooldownPanel:CreateTexture(nil, 'BORDER')
smashCooldownPanel.dimmer:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
smashCooldownPanel.dimmer:Hide()
smashCooldownPanel.swipe = CreateFrame('Cooldown', nil, smashCooldownPanel, 'CooldownFrameTemplate')
smashCooldownPanel.swipe:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.swipe:SetDrawBling(false)
smashCooldownPanel.swipe:SetDrawEdge(false)
smashCooldownPanel.text = smashCooldownPanel:CreateFontString(nil, 'OVERLAY')
smashCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashCooldownPanel.text:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.text:SetJustifyH('CENTER')
smashCooldownPanel.text:SetJustifyV('CENTER')
local smashInterruptPanel = CreateFrame('Frame', 'smashInterruptPanel', UIParent)
smashInterruptPanel:SetFrameStrata('BACKGROUND')
smashInterruptPanel:SetSize(64, 64)
smashInterruptPanel:SetMovable(true)
smashInterruptPanel:SetUserPlaced(true)
smashInterruptPanel:RegisterForDrag('LeftButton')
smashInterruptPanel:SetScript('OnDragStart', smashInterruptPanel.StartMoving)
smashInterruptPanel:SetScript('OnDragStop', smashInterruptPanel.StopMovingOrSizing)
smashInterruptPanel:Hide()
smashInterruptPanel.icon = smashInterruptPanel:CreateTexture(nil, 'BACKGROUND')
smashInterruptPanel.icon:SetAllPoints(smashInterruptPanel)
smashInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashInterruptPanel.border = smashInterruptPanel:CreateTexture(nil, 'ARTWORK')
smashInterruptPanel.border:SetAllPoints(smashInterruptPanel)
smashInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
smashInterruptPanel.swipe = CreateFrame('Cooldown', nil, smashInterruptPanel, 'CooldownFrameTemplate')
smashInterruptPanel.swipe:SetAllPoints(smashInterruptPanel)
smashInterruptPanel.swipe:SetDrawBling(false)
smashInterruptPanel.swipe:SetDrawEdge(false)
local smashExtraPanel = CreateFrame('Frame', 'smashExtraPanel', UIParent)
smashExtraPanel:SetFrameStrata('BACKGROUND')
smashExtraPanel:SetSize(64, 64)
smashExtraPanel:SetMovable(true)
smashExtraPanel:SetUserPlaced(true)
smashExtraPanel:RegisterForDrag('LeftButton')
smashExtraPanel:SetScript('OnDragStart', smashExtraPanel.StartMoving)
smashExtraPanel:SetScript('OnDragStop', smashExtraPanel.StopMovingOrSizing)
smashExtraPanel:Hide()
smashExtraPanel.icon = smashExtraPanel:CreateTexture(nil, 'BACKGROUND')
smashExtraPanel.icon:SetAllPoints(smashExtraPanel)
smashExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashExtraPanel.border = smashExtraPanel:CreateTexture(nil, 'ARTWORK')
smashExtraPanel.border:SetAllPoints(smashExtraPanel)
smashExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
-- Fury Whirlwind stacks and duration remaining on extra icon
smashExtraPanel.whirlwind = CreateFrame('Cooldown', nil, smashExtraPanel, 'CooldownFrameTemplate')
smashExtraPanel.whirlwind:SetAllPoints(smashExtraPanel)
smashExtraPanel.whirlwind:SetDrawBling(false)
smashExtraPanel.whirlwind:SetDrawEdge(false)
smashExtraPanel.whirlwind.stack = smashExtraPanel.whirlwind:CreateFontString(nil, 'OVERLAY')
smashExtraPanel.whirlwind.stack:SetFont('Fonts\\FRIZQT__.TTF', 18, 'OUTLINE')
smashExtraPanel.whirlwind.stack:SetTextColor(1, 1, 1, 1)
smashExtraPanel.whirlwind.stack:SetAllPoints(smashExtraPanel.whirlwind)
smashExtraPanel.whirlwind.stack:SetJustifyH('CENTER')
smashExtraPanel.whirlwind.stack:SetJustifyV('CENTER')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.ARMS] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.FURY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.PROTECTION] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
		{6, '6+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	smashPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function Smash_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function Smash_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function Smash_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
	local count = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function AutoAoe:Purge()
	local update
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rank = 0,
		rage_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if not pool and self:Cost() > Player.rage.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains(offGCD)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - (offGCD and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	local remains = duration - (Player.ctime - start)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.rage_cost
end

function Ability:Gain()
	return self.rage_gain
end

function Ability:WontCapRage(reduction)
	return (Player.rage.current + self:Gain()) < (Player.rage.max - (reduction or 5))
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + (self.off_gcd and 0 or Player.execute_remains))) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if self.consumes_whirlwind and WhirlwindFury.known then
		WhirlwindFury.buff.pending_stack_use = true
	end
	if Opt.previous then
		smashPreviousPanel.ability = self
		smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		smashPreviousPanel.icon:SetTexture(self.icon)
		smashPreviousPanel:SetShown(smashPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and smashPreviousPanel.ability == self then
		smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, Abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, Abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFocus():GetNodeID()
]]

-- Warrior Abilities
---- Class
------ Baseline
local BattleStance = Ability:Add(386164, true, true)
BattleStance.cooldown_duration = 3
local BerserkerRage = Ability:Add(18499, true, true)
BerserkerRage.buff_duration = 6
BerserkerRage.cooldown_duration = 60
local Charge = Ability:Add(100, false, true, 105771)
Charge.buff_duration = 1
Charge.cooldown_duration = 20
Charge.requires_charge = true
Charge.triggers_gcd = false
local HeroicLeap = Ability:Add(6544, false, true, 52174)
HeroicLeap.cooldown_duration = 45
HeroicLeap.requires_charge = true
HeroicLeap:AutoAoe()
local HeroicThrow = Ability:Add(57755, false, true)
HeroicThrow.cooldown_duration = 6
local Pummel = Ability:Add(6552, false, true)
Pummel.buff_duration = 4
Pummel.cooldown_duration = 15
Pummel.triggers_gcd = false
local BattleShout = Ability:Add(6673, true, false)
BattleShout.buff_duration = 3600
BattleShout.cooldown_duration = 15
local Taunt = Ability:Add(355, false, true)
Taunt.buff_duration = 3
Taunt.cooldown_duration = 8
Taunt.triggers_gcd = false
local VictoryRush = Ability:Add(34428, false, true)
------ Procs
local Victorious = Ability:Add(32216, true, true)
Victorious.buff_duration = 20
------ Talents
local AngerManagement = Ability:Add(152278, false, true)
local Avatar = Ability:Add({107574, 401150}, true, true)
Avatar.buff_duration = 20
Avatar.cooldown_duration = 90
local BlademastersTorment = Ability:Add(390138, false, true)
local BloodAndThunder = Ability:Add(384277, false, true)
local UnstoppableForce = Ability:Add(275336, false, true)
local DefensiveStance = Ability:Add(386208, true, true)
DefensiveStance.cooldown_duration = 3
local DragonRoar = Ability:Add(118000, false, true)
DragonRoar.buff_duration = 6
DragonRoar.cooldown_duration = 35
DragonRoar:AutoAoe(true)
local ElysianMight = Ability:Add(386285, true, true, 386286)
local ImpendingVictory = Ability:Add(202168, false, true)
ImpendingVictory.cooldown_duration = 30
ImpendingVictory.rage_cost = 10
local Intercept = Ability:Add(198304, false, true)
Intercept.cooldown_duration = 15
Intercept.requires_charge = true
Intercept.triggers_gcd = false
local Massacre = Ability:Add(206315, false, true, 281001)
local Ravager = Ability:Add({152277, 228920}, false, true)
Ravager.buff_duration = 12
Ravager.cooldown_duration = 60
Ravager.hasted_duration = true
Ravager.hasted_ticks = true
local RecklessAbandon = Ability:Add(202751, false, true)
local SeismicReverbation = Ability:Add(382956, true, true)
local Shockwave = Ability:Add(46968, false, true, 132168)
Shockwave.buff_duration = 2
Shockwave.cooldown_duration = 40
Shockwave:AutoAoe()
local Sidearm = Ability:Add(384404, false, true, 384391)
Sidearm:AutoAoe()
local SonicBoom = Ability:Add(390725, true, true)
local StormBolt = Ability:Add(107570, false, false, 132169)
StormBolt.buff_duration = 4
StormBolt.cooldown_duration = 30
local SpearOfBastion = Ability:Add(376079, false, true)
SpearOfBastion.cooldown_duration = 90
SpearOfBastion.buff_duration = 4
SpearOfBastion.rage_gain = 20
SpearOfBastion:AutoAoe()
local ThunderClap = Ability:Add(396719, false, true)
ThunderClap.buff_duration = 10
ThunderClap.cooldown_duration = 6
ThunderClap.rage_cost = 30
ThunderClap.hasted_cooldown = true
ThunderClap:AutoAoe(true)
local ThunderousWords = Ability:Add(384969, false, true)
local ThunderousRoar = Ability:Add(384318, false, true, 397364)
ThunderousRoar.buff_duration = 8
ThunderousRoar.cooldown_duration = 90
ThunderousRoar.rage_gain = 10
ThunderousRoar.tick_interval = 2
ThunderousRoar.hasted_ticks = true
ThunderousRoar:AutoAoe(true, 'apply')
local WarlordsTorment = Ability:Add(390140, false, true)
local WildStrikes = Ability:Add(382946, false, true, 392778)
WildStrikes.buff_duration = 10
local WreckingThrow = Ability:Add(384110, false, true)
WreckingThrow.cooldown_duration = 45
---- Arms
local Bladestorm = Ability:Add(389774, true, true)
Bladestorm.learn_spellId = 227847
Bladestorm.buff_duration = 6
Bladestorm.cooldown_duration = 60
Bladestorm.damage = Ability:Add(50622, false, true)
Bladestorm.damage:AutoAoe(true)
local ColossusSmash = Ability:Add(167105, false, true)
ColossusSmash.cooldown_duration = 45
ColossusSmash.debuff = Ability:Add(208086, false, true)
ColossusSmash.debuff.buff_duration = 10
local DeepWounds = Ability:Add(262111, false, true, 262115)
DeepWounds.buff_duration = 12
DeepWounds.tick_interval = 3
DeepWounds.hasted_ticks = true
DeepWounds:TrackAuras()
local DieByTheSword = Ability:Add(118038, true, true)
DieByTheSword.buff_duration = 8
DieByTheSword.cooldown_duration = 180
local Execute = Ability:Add(163201, false, true)
Execute.rage_cost = 20
local MortalStrike = Ability:Add(12294, false, true)
MortalStrike.rage_cost = 30
MortalStrike.cooldown_duration = 6
MortalStrike.hasted_cooldown = true
local Overpower = Ability:Add(7384, true, true)
Overpower.buff_duration = 15
Overpower.cooldown_duration = 12
Overpower.requires_charge = true
local Slam = Ability:Add(1464, false, true)
Slam.rage_cost = 20
local SweepingStrikes = Ability:Add(260708, true, true)
SweepingStrikes.buff_duration = 12
SweepingStrikes.cooldown_duration = 30
local Whirlwind = Ability:Add(1680, false, true, 199658)
Whirlwind.rage_cost = 30
Whirlwind:AutoAoe(true)
local Hamstring = Ability:Add(1715, false, true)
Hamstring.rage_cost = 10
Hamstring.buff_duration = 15
------ Talents
local BarbaricTraining = Ability:Add(383082, false, true)
local Battlelord = Ability:Add(386630, true, true, 386631)
Battlelord.buff_duration = 10
local Bloodletting = Ability:Add(383154, false, true)
local Cleave = Ability:Add(845, false, true)
Cleave.rage_cost = 20
Cleave.cooldown_duration = 9
Cleave.hasted_cooldown = true
Cleave:AutoAoe()
local CrushingForce = Ability:Add(382764, false, true)
local Dreadnaught = Ability:Add(262150, false, true, 315961)
Dreadnaught:AutoAoe()
local ExecutionersPrecision = Ability:Add(386634, false, true, 386633)
ExecutionersPrecision.buff_duration = 30
local FervorOfBattle = Ability:Add(202316, false, true)
local Hurricane = Ability:Add(390563, true, true, 390581)
Hurricane.buff_duration = 6
local Juggernaut = Ability:Add(383292, true, true, 383290)
Juggernaut.buff_duration = 12
local MartialProwess = Ability:Add(316440, true, true)
local MercilessBonegrinder = Ability:Add(383317, true, true, 383316)
MercilessBonegrinder.buff_duration = 9
local Rend = Ability:Add(772, false, true, 388539)
Rend.rage_cost = 30
Rend.buff_duration = 15
Rend.tick_interval = 3
Rend.hasted_ticks = true
Rend:TrackAuras()
local Skullsplitter = Ability:Add(260643, false, true)
Skullsplitter.cooldown_duration = 21
Skullsplitter.hasted_cooldown = true
local StormOfSwords = Ability:Add(385512, true, true)
local TestOfMight = Ability:Add(385008, true, true, 385013)
TestOfMight.buff_duration = 12
local TideOfBlood = Ability:Add(386357, false, true)
local Unhinged = Ability:Add(386628, false, true)
local Warbreaker = Ability:Add(262161, true, true)
Warbreaker.cooldown_duration = 45
Warbreaker:AutoAoe(true)
------ Procs
local SuddenDeath = Ability:Add(29725, true, true, 52437)
SuddenDeath.buff_duration = 10
---- Fury
local Bloodthirst = Ability:Add(23881, false, true)
Bloodthirst.cooldown_duration = 4.5
Bloodthirst.rage_gain = 8
Bloodthirst.hasted_cooldown = true
local ExecuteFury = Ability:Add(5308, false, true)
ExecuteFury.cooldown_duration = 6
ExecuteFury.rage_gain = 20
ExecuteFury.hasted_cooldown = true
local RagingBlow = Ability:Add(85288, false, true)
RagingBlow.cooldown_duration = 8
RagingBlow.rage_gain = 12
RagingBlow.hasted_cooldown = true
RagingBlow.requires_charge = true
local Rampage = Ability:Add(184367, false, true)
Rampage.rage_cost = 80
local Recklessness = Ability:Add(1719, true, true)
Recklessness.buff_duration = 12
Recklessness.cooldown_duration = 90
local WhirlwindFury = Ability:Add(190411, false, true, 199667)
WhirlwindFury:AutoAoe(true)
WhirlwindFury.buff = Ability:Add(85739, true, true)
WhirlwindFury.buff.buff_duration = 20
------ Talents
local BladestormFury = Ability:Add(46924, true, true)
BladestormFury.buff_duration = 4
BladestormFury.cooldown_duration = 60
local FrothingBerserker = Ability:Add(215571, false, true)
local Siegebreaker = Ability:Add(280772, false, true, 280773)
Siegebreaker.buff_duration = 10
Siegebreaker.cooldown_duration = 30
local SuddenDeathFury = Ability:Add(280721, true, true, 280776)
SuddenDeathFury.buff_duration = 10
------ Procs
local Enrage = Ability:Add(184361, true, true, 184362)
Enrage.buff_duration = 4
local Frenzy = Ability:Add(335077, true, true, 335082)
Frenzy.buff_duration = 12
---- Protection
------ Talents
local Bolster = Ability:Add(280001, true, true)
local BoomingVoice = Ability:Add(202743, false, true)
local DemoralizingShout = Ability:Add(1160, false, true)
DemoralizingShout.buff_duration = 8
DemoralizingShout.cooldown_duration = 45
local Devastate = Ability:Add(20243, false, true)
local Devastator = Ability:Add(236279, false, true)
local EnduringDefenses = Ability:Add(386027, true, true)
local IgnorePain = Ability:Add(190456, true, true)
IgnorePain.buff_duration = 12
IgnorePain.cooldown_duration = 1
IgnorePain.rage_cost = 35
IgnorePain.triggers_gcd = false
local ImmovableObject = Ability:Add(394307, true, true)
local LastStand = Ability:Add(12975, true, true)
LastStand.buff_duration = 15
LastStand.cooldown_duration = 180
LastStand.triggers_gcd = false
local Revenge = Ability:Add(6572, false, true)
Revenge.rage_cost = 20
Revenge:AutoAoe()
Revenge.free = Ability:Add(5302, true, true)
Revenge.free.buff_duration = 6
local ShieldBlock = Ability:Add(2565, true, true, 132404)
ShieldBlock.buff_duration = 6
ShieldBlock.cooldown_duration = 16
ShieldBlock.rage_cost = 30
ShieldBlock.hasted_cooldown = true
ShieldBlock.requires_charge = true
ShieldBlock.triggers_gcd = false
local ShieldCharge = Ability:Add(385952, false, true)
ShieldCharge.cooldown_duration = 45
local ShieldSlam = Ability:Add(23922, false, true)
ShieldSlam.cooldown_duration = 9
ShieldSlam.hasted_cooldown = true
local ShieldWall = Ability:Add(871, true, true)
ShieldWall.buff_duration = 8
ShieldWall.cooldown_duration = 180
ShieldWall.requires_charge = true
ShieldWall.triggers_gcd = false
local ThunderClapProt = Ability:Add(6343, false, true)
ThunderClapProt.buff_duration = 10
ThunderClapProt.cooldown_duration = 6
ThunderClapProt.hasted_cooldown = true
ThunderClapProt:AutoAoe(true)
local UnnervingFocus = Ability:Add(337154, true, true)
------ Procs
local SeeingRed = Ability:Add(386486, true, true)
SeeingRed.buff_duration = 30
local VanguardsDetermination = Ability:Add(394056, true, true)
VanguardsDetermination.buff_duration = 5
local ViolentOutburst = Ability:Add(386477, true, true, 386478)
ViolentOutburst.buff_duration = 30
-- Racials

-- PvP talents

-- Trinket Effects

-- Class cooldowns
local PowerInfusion = Ability:Add(10060, true)
PowerInfusion.buff_duration = 20
-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.trackAuras)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.trackAuras[#self.trackAuras + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
	end
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 381301 or -- Feral Hide Drums (Leatherworking)
			id == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateKnown()
	self.rage.max = UnitPowerMax('player', 1)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.rank = 0
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
				ability.known = true
				break
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.talent_node and configId then
			node = C_Traits.GetNodeInfo(configId, ability.talent_node)
			if node then
				ability.rank = node.activeRank
				ability.known = ability.rank > 0
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsUsableSpell(ability.spellId)) then
			ability.known = false -- spell is locked, do not mark as known
		end
	end

	if Ravager.known then
		Bladestorm.known = false
	end
	if ImpendingVictory.known then
		VictoryRush.known = false
	end
	if Devastator.known then
		Devastate.known = false
	end
	if Warbreaker.known then
		ColossusSmash.known = false
	end
	Bladestorm.damage.known = Bladestorm.known or BladestormFury.known
	ColossusSmash.debuff.known = ColossusSmash.known or Warbreaker.known
	Revenge.free.known = Revenge.known
	Victorious.known = VictoryRush.known or ImpendingVictory.known
	WhirlwindFury.buff.known = WhirlwindFury.known
	VanguardsDetermination.known = self.spec == SPEC.PROTECTION and self.set_bonus.t29 >= 2
	if IgnorePain.known then
		IgnorePain.rage_cost = (self.spec == SPEC.ARMS and 40) or (self.spec == SPEC.FURY and 60) or 35
	end

	Abilities:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability and ability == channel.ability then
		channel.chained = true
	else
		channel.ability = ability
	end
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, ends, duration, spellId, speed_mh, speed_oh, speed, max_speed
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self.pool_rage = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.rage.current = UnitPower('player', 1)
	self.rage.deficit = self.rage.max - self.rage.current
	self.rage.pct = self.rage.current / self.rage.max * 100
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	smashPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
		if Opt.always_on then
			UI:UpdateCombat()
			smashPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			smashPreviousPanel:Hide()
		end
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		smashPanel:Show()
		return true
	end
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	if StormBolt:Up() or Shockwave:Up() then
		return true
	end
	return false
end

-- End Target Functions

-- Start Ability Modifications

function Execute:Cost()
	if SuddenDeath.known and SuddenDeath:Up() then
		return 0
	end
	return Ability.Cost(self)
end

function Execute:Usable()
	if (not SuddenDeath.known or not SuddenDeath:Up()) and Target.health.pct >= (Massacre.known and 35 or 20) then
		return false
	end
	return Ability.Usable(self)
end

function ExecuteFury:Usable()
	if (not SuddenDeathFury.known or not SuddenDeathFury:Up()) and Target.health.pct >= (Massacre.known and 35 or 20) then
		return false
	end
	return Ability.Usable(self)
end

function ThunderClap:Cost()
	local cost = Ability.Cost(self)
	if BloodAndThunder.known then
		cost = cost + 10
	end
	return cost
end
ThunderClapProt.Cost = ThunderClap.Cost

function Whirlwind:Cost()
	local cost = Ability.Cost(self)
	if BarbaricTraining.known then
		cost = cost + 10
	end
	if StormOfSwords.known then
		cost = cost + 20
	end
	return cost
end

function WhirlwindFury.buff:Stack()
	local stack = Ability.Stack(self)
	if self.pending_stack_use then
		stack = stack - 1
	end
	return max(0, stack)
end

function WhirlwindFury.buff:Remains()
	local remains = Ability.Remains(self)
	if remains == 0 or self:Stack() == 0 then
		return 0
	end
	return remains
end

function WhirlwindFury.buff:StartDurationStack()
	local _, i, id, duration, expires, stack
	for i = 1, 40 do
		_, _, stack, _, duration, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0, 0, 0
		end
		if self:Match(id) then
			if self.pending_stack_use then
				stack = stack - 1
			end
			return expires - duration, duration, stack
		end
	end
	return 0, 0, 0
end

function Cleave:Cost()
	local cost = Ability.Cost(self)
	if Battlelord.known and Battlelord:Up() then
		cost = cost - 10
	end
	return max(0, cost)
end

function MortalStrike:Cost()
	local cost = Ability.Cost(self)
	if Battlelord.known and Battlelord:Up() then
		cost = cost - 10
	end
	return max(0, cost)
end

function Revenge:Cost()
	if Revenge.free:Up() then
		return 0
	end
	return Ability.Cost(self)
end

function VictoryRush:Usable()
	if Victorious:Down() then
		return false
	end
	return Ability.Usable(self)
end

function StormBolt:Usable()
	if not Target.stunnable then
		return false
	end
	return Ability.Usable(self)
end

function DeepWounds:Duration()
	local duration = Ability.Duration(self)
	if Bloodletting.known then
		duration = duration + 6
	end
	return duration
end

function Rend:Duration()
	local duration = Ability.Duration(self)
	if Bloodletting.known then
		duration = duration + 6
	end
	return duration
end

function ThunderousRoar:Duration()
	local duration = Ability.Duration(self)
	if ThunderousWords.known then
		duration = duration + 2
	end
	if Bloodletting.known then
		duration = duration + 6
	end
	return duration
end

function WhirlwindFury:CastSuccess(...)
	Ability.CastSuccess(self)
	self.buff.pending_stack_use = false
end

function SweepingStrikes:CastSuccess(...)
	Ability.CastSuccess(self)
	if Opt.auto_aoe and Player.target_mode < 2 then
		Player:SetTargetMode(2)
	end
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function WaitFor(ability, wait_time)
	Player.wait_time = wait_time and (Player.ctime + wait_time) or (Player.ctime + ability:Cooldown())
	return ability
end

local function Pool(ability, extra)
	Player.pool_rage = ability:Cost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.ARMS].Main = function(self)
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
actions.precombat+=/battle_stance,toggle=on
actions.precombat+=/snapshot_stats
actions.precombat+=/use_item,name=algethar_puzzle_box
]]
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then

		end
		if BattleShout:Usable() and BattleShout:Remains() < 300 then
			return BattleShout
		end
		if BattleStance:Down() then
			UseExtra(BattleStance)
		end
		if Charge:Usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
		end
		if BattleStance:Down() then
			UseExtra(BattleStance)
		end
	end
--[[
actions=charge,if=time<=0.5|movement.distance>5
actions+=/auto_attack
actions+=/potion,if=gcd.remains=0&debuff.colossus_smash.remains>8|target.time_to_die<25
actions+=/pummel,if=target.debuff.casting.react
actions+=/use_item,name=manic_grieftorch,if=!buff.avatar.up&!debuff.colossus_smash.up
actions+=/blood_fury,if=debuff.colossus_smash.up
actions+=/berserking,if=debuff.colossus_smash.remains>6
actions+=/arcane_torrent,if=cooldown.mortal_strike.remains>1.5&rage<50
actions+=/lights_judgment,if=debuff.colossus_smash.down&cooldown.mortal_strike.remains
actions+=/fireblood,if=debuff.colossus_smash.up
actions+=/ancestral_call,if=debuff.colossus_smash.up
actions+=/bag_of_tricks,if=debuff.colossus_smash.down&cooldown.mortal_strike.remains
actions+=/run_action_list,name=hac,if=raid_event.adds.exists|active_enemies>2
actions+=/call_action_list,name=execute,target_if=min:target.health.pct,if=(talent.massacre.enabled&target.health.pct<35)|target.health.pct<20
actions+=/run_action_list,name=single_target,if=!raid_event.adds.exists
]]
	self.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or (Avatar.known and Avatar:Up())
	if Player.health.pct < Opt.heal_threshold then
		if VictoryRush:Usable() then
			UseExtra(VictoryRush)
		elseif ImpendingVictory:Usable() then
			UseExtra(ImpendingVictory)
		end
	end
	if Player.enemies > 2 then
		return self:hac()
	end
	if Target.health.pct < (Massacre.known and 35 or 20) then
		local apl = self:execute()
		if apl then return apl end
	end
	return self:single_target()
end

APL[SPEC.ARMS].execute = function(self)
--[[
actions.execute=sweeping_strikes,if=spell_targets.whirlwind>1
actions.execute+=/rend,if=remains<=gcd&(!talent.warbreaker&cooldown.colossus_smash.remains<4|talent.warbreaker&cooldown.warbreaker.remains<4)&target.time_to_die>12
actions.execute+=/avatar,if=cooldown.colossus_smash.ready|debuff.colossus_smash.up|target.time_to_die<20
actions.execute+=/warbreaker
actions.execute+=/colossus_smash
actions.execute+=/thunderous_roar,if=buff.test_of_might.up|!talent.test_of_might&debuff.colossus_smash.up
actions.execute+=/spear_of_bastion,if=debuff.colossus_smash.up|buff.test_of_might.up
actions.execute+=/skullsplitter,if=rage<40
actions.execute+=/cleave,if=spell_targets.whirlwind>2&dot.deep_wounds.remains<gcd
actions.execute+=/overpower,if=rage<40&buff.martial_prowess.stack<2
actions.execute+=/mortal_strike,if=debuff.executioners_precision.stack=2|dot.deep_wounds.remains<=gcd
actions.execute+=/execute
actions.execute+=/shockwave,if=talent.sonic_boom
actions.execute+=/overpower
actions.execute+=/bladestorm
]]
	if Player.enemies > 1 and SweepingStrikes:Usable() and SweepingStrikes:Down() then
		UseCooldown(SweepingStrikes)
	end
	if Rend:Usable() and Rend:Remains() < Player.gcd and Target.timeToDie > 12 and (
		(not Warbreaker.known and ColossusSmash:Ready(4)) or
		(Warbreaker.known and Warbreaker:Ready(4))
	) then
		return Rend
	end
	if self.use_cds and Avatar:Usable() and (ColossusSmash:Ready() or ColossusSmash.debuff:Up() or (Target.boss and Target.timeToDie < 20)) then
		UseCooldown(Avatar)
	end
	if Warbreaker:Usable() then
		UseCooldown(Warbreaker)
	end
	if ColossusSmash:Usable() then
		UseCooldown(ColossusSmash)
	end
	if ThunderousRoar:Usable() and (
		(TestOfMight.known and TestOfMight:Up()) or
		(not TestOfMight.known and ColossusSmash.debuff:Up())
	) then
		UseCooldown(ThunderousRoar)
	end
	if self.use_cds and SpearOfBastion:Usable() and (ColossusSmash.debuff:Up() or (TestOfMight.known and TestOfMight:Up())) then
		UseCooldown(SpearOfBastion)
	end
	if Skullsplitter:Usable() and Player.rage.current < 40 then
		return Skullsplitter
	end
	if Cleave:Usable() and Player.enemies > 2 and DeepWounds:Remains() < Player.gcd then
		return Cleave
	end
	if Overpower:Usable() and Player.rage.current < 40 and Overpower:Stack() < 2 then
		return Overpower
	end
	if MortalStrike:Usable() and (ExecutionersPrecision:Stack() >= 2 or DeepWounds:Remains() < Player.gcd) then
		return MortalStrike
	end
	if Execute:Usable() then
		return Execute
	end
	if SonicBoom.known and Shockwave:Usable() then
		return Shockwave
	end
	if Overpower:Usable() then
		return Overpower
	end
	if self.use_cds and Bladestorm:Usable() then
		UseCooldown(Bladestorm)
	end
end

APL[SPEC.ARMS].single_target = function(self)
--[[
actions.single_target=sweeping_strikes,if=spell_targets.whirlwind>1
actions.single_target+=/mortal_strike
actions.single_target+=/rend,if=remains<=gcd|talent.tide_of_blood&cooldown.skullsplitter.remains<=gcd&(cooldown.colossus_smash.remains<=gcd|debuff.colossus_smash.up)&dot.rend.remains<dot.rend.duration*0.85
actions.single_target+=/avatar,if=talent.warlords_torment&rage.pct<33&(cooldown.colossus_smash.ready|debuff.colossus_smash.up|buff.test_of_might.up)|!talent.warlords_torment&(cooldown.colossus_smash.ready|debuff.colossus_smash.up)
actions.single_target+=/spear_of_bastion,if=cooldown.colossus_smash.remains<=gcd|cooldown.warbreaker.remains<=gcd
actions.single_target+=/warbreaker
actions.single_target+=/colossus_smash
actions.single_target+=/thunderous_roar,if=buff.test_of_might.up|talent.test_of_might&debuff.colossus_smash.up&rage.pct<33|!talent.test_of_might&debuff.colossus_smash.up
actions.single_target+=/bladestorm,if=talent.hurricane&(buff.test_of_might.up|!talent.test_of_might&debuff.colossus_smash.up)|talent.unhinged&(buff.test_of_might.up|!talent.test_of_might&debuff.colossus_smash.up)
actions.single_target+=/skullsplitter,if=talent.tide_of_blood&dot.rend.remains&(debuff.colossus_smash.up|cooldown.colossus_smash.remains>gcd*4&buff.test_of_might.up|!talent.test_of_might&cooldown.colossus_smash.remains>gcd*4)|rage<30
actions.single_target+=/execute,if=buff.sudden_death.react
actions.single_target+=/shockwave,if=talent.sonic_boom.enabled
actions.single_target+=/ignore_pain,if=talent.anger_management|talent.test_of_might&debuff.colossus_smash.up
actions.single_target+=/whirlwind,if=talent.storm_of_swords&talent.battlelord&rage.pct>80&debuff.colossus_smash.up
actions.single_target+=/overpower,if=charges=2&!talent.battlelord&(debuff.colossus_smash.down|rage.pct<25)|talent.battlelord
actions.single_target+=/whirlwind,if=talent.storm_of_swords|talent.fervor_of_battle&active_enemies>1
actions.single_target+=/thunder_clap,if=talent.battlelord&talent.blood_and_thunder
actions.single_target+=/overpower,if=debuff.colossus_smash.down&rage.pct<50&!talent.battlelord|rage.pct<25
actions.single_target+=/whirlwind,if=buff.merciless_bonegrinder.up
actions.single_target+=/cleave,if=set_bonus.tier29_2pc&!talent.crushing_force
actions.single_target+=/slam,if=rage>30&(!talent.fervor_of_battle|talent.fervor_of_battle&active_enemies=1)
actions.single_target+=/bladestorm
actions.single_target+=/cleave
actions.single_target+=/wrecking_throw
actions.single_target+=/rend,if=remains<duration*0.3
]]
	if Player.enemies > 1 and SweepingStrikes:Usable() and SweepingStrikes:Down() then
		UseCooldown(SweepingStrikes)
	end
	if MortalStrike:Usable() then
		return MortalStrike
	end
	if Rend:Usable() and (
		(Rend:Remains() < Player.gcd) or
		(TideOfBlood.known and Skullsplitter:Ready(Player.gcd) and (ColossusSmash:Ready(Player.gcd) or ColossusSmash.debuff:Up()) and Rend:Remains() < (Rend:Duration() * 0.85))
	) then
		return Rend
	end
	if self.use_cds and Avatar:Usable() and (
		(WarlordsTorment.known and Player.rage.pct < 33 and (ColossusSmash:Ready() or ColossusSmash.debuff:Up() or TestOfMight:Up())) or
		(not WarlordsTorment.known and (ColossusSmash:Ready() or ColossusSmash.debuff:Up()))
	) then
		UseCooldown(Avatar)
	end
	if self.use_cds and SpearOfBastion:Usable() and ((ColossusSmash.known and ColossusSmash:Ready(Player.gcd)) or (Warbreaker.known and Warbreaker:Ready(Player.gcd))) then
		UseCooldown(SpearOfBastion)
	end
	if Warbreaker:Usable() then
		UseCooldown(Warbreaker)
	end
	if ColossusSmash:Usable() then
		UseCooldown(ColossusSmash)
	end
	if ThunderousRoar:Usable() and (
		(TestOfMight.known and (TestOfMight:Up() or (ColossusSmash.debuff:Up() and Player.rage.pct < 33))) or
		(not TestOfMight.known and ColossusSmash.debuff:Up())
	) then
		UseCooldown(ThunderousRoar)
	end
	if self.use_cds and Bladestorm:Usable() and (Hurricane.known or Unhinged.known) and ((TestOfMight.known and TestOfMight:Up()) or (not TestOfMight.known and ColossusSmash.debuff:Up())) then
		UseCooldown(Bladestorm)
	end
	if Skullsplitter:Usable() and (
		Player.rage.current < 30 or
		(TideOfBlood.known and Rend:Up() and (ColossusSmash.debuff:Up() or (TestOfMight.known and not ColossusSmash:Ready(Player.gcd * 4) and TestOfMight:Up()) or (not TestOfMight.known and not ColossusSmash:Ready(Player.gcd * 4))))
	) then
		return Skullsplitter
	end
	if SuddenDeath.known and Execute:Usable() and SuddenDeath:Up() then
		return Execute
	end
	if WreckingThrow:Usable() and UnitGetTotalAbsorbs('target') > Player.health.max then
		return WreckingThrow
	end
	if SonicBoom.known and Shockwave:Usable() then
		return Shockwave
	end
	if IgnorePain:Usable() and (AngerManagement.known or (TestOfMight.known and ColossusSmash.debuff:Up())) then
		UseCooldown(IgnorePain)
	end
	if StormOfSwords.known and Battlelord.known and Whirlwind:Usable() and Player.rage.pct > 80 and ColossusSmash.debuff:Up() then
		return Whirlwind
	end
	if Overpower:Usable() and (Battlelord.known or (Overpower:Charges() == 2 and (Player.rage.pct < 25 or ColossusSmash.debuff:Down()))) then
		return Overpower
	end
	if Whirlwind:Usable() and (StormOfSwords.known or (FervorOfBattle.known and Player.enemies > 1)) then
		return Whirlwind
	end
	if Cleave:Usable() and Player.set_bonus.t29 >= 2 and not CrushingForce.known then
		return Cleave
	end
	if Slam:Usable() and Player.rage.current > 30 and (not FervorOfBattle.known or Player.enemies == 1) then
		return Slam
	end
	if self.use_cds and Bladestorm:Usable() then
		UseCooldown(Bladestorm)
	end
	if Cleave:Usable() then
		return Cleave
	end
	if WreckingThrow:Usable() then
		UseCooldown(WreckingThrow)
	end
	if Rend:Usable() and Rend:Refreshable() then
		return Rend
	end
end

APL[SPEC.ARMS].hac = function(self)
--[[
actions.hac=execute,if=buff.juggernaut.up&buff.juggernaut.remains<gcd
actions.hac+=/thunder_clap,if=active_enemies>2&talent.thunder_clap&talent.blood_and_thunder&talent.rend&dot.rend.remains<=dot.rend.duration*0.3
actions.hac+=/sweeping_strikes,if=active_enemies>=2&(cooldown.bladestorm.remains>15|!talent.bladestorm)
actions.hac+=/rend,if=active_enemies=1&remains<=gcd&(target.health.pct>20|talent.massacre&target.health.pct>35)|talent.tide_of_blood&cooldown.skullsplitter.remains<=gcd&(cooldown.colossus_smash.remains<=gcd|debuff.colossus_smash.up)&dot.rend.remains<dot.rend.duration*0.85
actions.hac+=/avatar,if=raid_event.adds.in>15|talent.blademasters_torment&active_enemies>1|target.time_to_die<20
actions.hac+=/warbreaker,if=raid_event.adds.in>22|active_enemies>1
actions.hac+=/colossus_smash,cycle_targets=1,if=(target.health.pct<20|talent.massacre&target.health.pct<35)
actions.hac+=/colossus_smash
actions.hac+=/thunderous_roar,if=(buff.test_of_might.up|!talent.test_of_might&debuff.colossus_smash.up)&raid_event.adds.in>15|active_enemies>1&dot.deep_wounds.remains
actions.hac+=/spear_of_bastion,if=(buff.test_of_might.up|!talent.test_of_might&debuff.colossus_smash.up)&raid_event.adds.in>15
actions.hac+=/bladestorm,if=talent.unhinged&(buff.test_of_might.up|!talent.test_of_might&debuff.colossus_smash.up)
actions.hac+=/bladestorm,if=active_enemies>1&(buff.test_of_might.up|!talent.test_of_might&debuff.colossus_smash.up)&raid_event.adds.in>30|active_enemies>1&dot.deep_wounds.remains
actions.hac+=/cleave,if=active_enemies>2|!talent.battlelord&buff.merciless_bonegrinder.up&cooldown.mortal_strike.remains>gcd
actions.hac+=/whirlwind,if=active_enemies>2|talent.storm_of_swords&(buff.merciless_bonegrinder.up|buff.hurricane.up)
actions.hac+=/skullsplitter,if=rage<40|talent.tide_of_blood&dot.rend.remains&(buff.sweeping_strikes.up&active_enemies>=2|debuff.colossus_smash.up|buff.test_of_might.up)
actions.hac+=/overpower,if=buff.sweeping_strikes.up&talent.dreadnaught
actions.hac+=/mortal_strike,cycle_targets=1,if=debuff.executioners_precision.stack=2|dot.deep_wounds.remains<=gcd|talent.dreadnaught&talent.battlelord&active_enemies<=2
actions.hac+=/execute,cycle_targets=1,if=buff.sudden_death.react|active_enemies<=2&(target.health.pct<20|talent.massacre&target.health.pct<35)|buff.sweeping_strikes.up
actions.hac+=/thunderous_roar,if=raid_event.adds.in>15
actions.hac+=/shockwave,if=active_enemies>2&talent.sonic_boom
actions.hac+=/overpower,if=active_enemies=1&(charges=2&!talent.battlelord&(debuff.colossus_smash.down|rage.pct<25)|talent.battlelord)
actions.hac+=/slam,if=active_enemies=1&!talent.battlelord&rage.pct>70
actions.hac+=/overpower,if=charges=2&(!talent.test_of_might|talent.test_of_might&debuff.colossus_smash.down|talent.battlelord)|rage<70
actions.hac+=/thunder_clap,if=active_enemies>2
actions.hac+=/mortal_strike
actions.hac+=/rend,if=active_enemies=1&dot.rend.remains<duration*0.3
actions.hac+=/whirlwind,if=talent.storm_of_swords|talent.fervor_of_battle&active_enemies>1
actions.hac+=/cleave,if=!talent.crushing_force
actions.hac+=/ignore_pain,if=talent.battlelord&talent.anger_management&rage>30&(target.health.pct>20|talent.massacre&target.health.pct>35)
actions.hac+=/slam,if=talent.crushing_force&rage>30&(talent.fervor_of_battle&active_enemies=1|!talent.fervor_of_battle)
actions.hac+=/shockwave,if=talent.sonic_boom
actions.hac+=/bladestorm,if=raid_event.adds.in>30
actions.hac+=/wrecking_throw
]]
	if Execute:Usable() and Juggernaut:Up() and Juggernaut:Remains() < Player.gcd then
		return Execute
	end
	if BloodAndThunder.known and Rend.known and ThunderClap:Usable() and (Rend:Refreshable() or Rend:Ticking() < Player.enemies) then
		return ThunderClap
	end
	if SweepingStrikes:Usable() and SweepingStrikes:Down() and (not Bladestorm.known or not Bladestorm:Ready(15)) then
		UseCooldown(SweepingStrikes)
	end
	if TideOfBlood.known and Rend:Usable() and Skullsplitter:Ready(Player.gcd) and (ColossusSmash:Ready(Player.gcd) or ColossusSmash.debuff:Up()) and Rend:Remains() < Rend:Duration() * 0.85 then
		return Rend
	end
	if self.use_cds and Avatar:Usable() and (BlademastersTorment.known or (Target.boss and Target.timeToDie < 20)) then
		UseCooldown(Avatar)
	end
	if Warbreaker:Usable() then
		UseCooldown(Warbreaker)
	end
	if ColossusSmash:Usable() then
		UseCooldown(ColossusSmash)
	end
	if Cleave:Usable() and DeepWounds:Ticking() < Player.enemies then
		return Cleave
	end
	if ThunderousRoar:Usable() and (
		(TestOfMight.known and TestOfMight:Up()) or
		(not TestOfMight.known and ColossusSmash.debuff:Up()) or
		DeepWounds:Up()
	) then
		UseCooldown(ThunderousRoar)
	end
	if self.use_cds and SpearOfBastion:Usable() and (
		(TestOfMight.known and TestOfMight:Up()) or
		(not TestOfMight.known and ColossusSmash.debuff:Up())
	) then
		UseCooldown(SpearOfBastion)
	end
	if self.use_cds and Bladestorm:Usable() and (
		(TestOfMight.known and TestOfMight:Up()) or
		(not TestOfMight.known and ColossusSmash.debuff:Up()) or
		DeepWounds:Up()
	) then
		UseCooldown(Bladestorm)
	end
	if Cleave:Usable() then
		return Cleave
	end
	if Whirlwind:Usable() then
		return Whirlwind
	end
	if Skullsplitter:Usable() and (
		Player.rage.current < 40 or
		(TideOfBlood.known and Rend:Up() and (SweepingStrikes:Up() or ColossusSmash.debuff:Up() or (TestOfMight.known and TestOfMight:Up())))
	) then
		return Skullsplitter
	end
	if Dreadnaught.known and Overpower:Usable() and SweepingStrikes:Up() then
		return Overpower
	end
	if MortalStrike:Usable() and (ExecutionersPrecision:Stack() >= 2 or DeepWounds:Remains() < Player.gcd) then
		return MortalStrike
	end
	if Execute:Usable() and (SuddenDeath:Up() or SweepingStrikes:Up()) then
		return Execute
	end
	if ThunderousRoar:Usable() then
		UseCooldown(ThunderousRoar)
	end
	if SonicBoom.known and Shockwave:Usable() then
		return Shockwave
	end
	if Overpower:Usable() and (Player.rage.current < 70 or (Overpower:Charges() == 2 and (Battlelord.known or not TestOfMight.known or ColossusSmash.debuff:Down()))) then
		return Overpower
	end
	if ThunderClap:Usable() then
		return ThunderClap
	end
	if MortalStrike:Usable() then
		return MortalStrike
	end
	if not CrushingForce.known and Cleave:Usable() then
		return Cleave
	end
	if Battlelord.known and AngerManagement.known and IgnorePain:Usable() and Player.rage.current > 30 and Target.health.pct > (Massacre.known and 35 or 20) then
		UseCooldown(IgnorePain)
	end
	if CrushingForce.known and not FervorOfBattle.known and Slam:Usable() and Player.rage.current > 30 then
		return Slam
	end
	if self.use_cds and Bladestorm:Usable() then
		UseCooldown(Bladestorm)
	end
	if WreckingThrow:Usable() then
		return WreckingThrow
	end
end

APL[SPEC.FURY].Main = function(self)
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/recklessness,if=!runeforge.signet_of_tormented_kings.equipped
actions.precombat+=/fleshcraft
]]
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then

		end
		if BattleShout:Usable() and BattleShout:Remains() < 300 then
			return BattleShout
		end
		if BattleStance:Down() then
			UseExtra(BattleStance)
		end
		if Charge:Usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
		end
		if BattleStance:Down() then
			UseExtra(BattleStance)
		end
	end
--[[
actions=auto_attack
actions+=/charge
actions+=/variable,name=execute_phase,value=talent.massacre&target.health.pct<35|target.health.pct<20|target.health.pct>80&covenant.venthyr
actions+=/variable,name=unique_legendaries,value=runeforge.signet_of_tormented_kings|runeforge.sinful_surge|runeforge.elysian_might
actions+=/variable,name=bladestorm_condition,value=(prev_gcd.1.rampage|buff.enrage.remains>gcd*2.5)&(!conduit.merciless_bonegrinder.enabled|spell_targets.whirlwind<=3|buff.merciless_bonegrinder.down)
# This is mostly to prevent cooldowns from being accidentally used during movement.
actions+=/run_action_list,name=movement,if=movement.distance>5
actions+=/heroic_leap,if=(raid_event.movement.distance>25&raid_event.movement.in>45)
actions+=/potion
actions+=/pummel,if=target.debuff.casting.react
actions+=/use_item,name=enforcers_stun_grenade,if=buff.enrage.up&(!cooldown.recklessness.remains|buff.recklessness.remains>10)&(!cooldown.spear_of_bastion.remains|cooldown.spear_of_bastion.remains>50|buff.elysian_might.up)|fight_remains<25
actions+=/spear_of_bastion,if=buff.enrage.up&rage<70
actions+=/rampage,if=cooldown.recklessness.remains<3&talent.reckless_abandon.enabled
actions+=/recklessness,if=runeforge.sinful_surge&gcd.remains=0&(variable.execute_phase|(target.time_to_pct_35>40&talent.anger_management|target.time_to_pct_35>70&!talent.anger_management))&(spell_targets.whirlwind=1|buff.meat_cleaver.up)
actions+=/recklessness,if=runeforge.elysian_might&gcd.remains=0&(!runeforge.signet_of_tormented_kings.equipped|variable.bladestorm_condition|buff.elysian_might.up&rage<70)&(cooldown.spear_of_bastion.remains<5|cooldown.spear_of_bastion.remains>20)&((buff.bloodlust.up|talent.anger_management.enabled|raid_event.adds.in>10)|target.time_to_die>100|variable.execute_phase|target.time_to_die<15&raid_event.adds.in>10)&(spell_targets.whirlwind=1|buff.meat_cleaver.up)
actions+=/recklessness,if=!variable.unique_legendaries&gcd.remains=0&((buff.bloodlust.up|talent.anger_management.enabled|raid_event.adds.in>10)|target.time_to_die>100|variable.execute_phase|target.time_to_die<15&raid_event.adds.in>10)&(spell_targets.whirlwind=1|buff.meat_cleaver.up)&(!covenant.necrolord|cooldown.conquerors_banner.remains>20)
actions+=/recklessness,use_off_gcd=1,if=runeforge.signet_of_tormented_kings.equipped&gcd.remains&prev_gcd.1.rampage&((buff.bloodlust.up|talent.anger_management.enabled|raid_event.adds.in>10)|target.time_to_die>100|variable.execute_phase|target.time_to_die<15&raid_event.adds.in>10)&(spell_targets.whirlwind=1|buff.meat_cleaver.up)
actions+=/whirlwind,if=spell_targets.whirlwind>1&!buff.meat_cleaver.up|raid_event.adds.in<gcd&!buff.meat_cleaver.up
actions+=/bloodthirst,if=buff.enrage.down&rage<50&(covenant.kyrian&cooldown.spear_of_bastion.remains<gcd|runeforge.signet_of_tormented_kings.equipped&cooldown.recklessness.remains<gcd)
actions+=/blood_fury
actions+=/berserking,if=buff.recklessness.up
actions+=/lights_judgment,if=buff.recklessness.down&debuff.siegebreaker.down
actions+=/fireblood
actions+=/ancestral_call
actions+=/bag_of_tricks,if=buff.recklessness.down&debuff.siegebreaker.down&buff.enrage.up
actions+=/call_action_list,name=aoe
actions+=/call_action_list,name=single_target
]]
	self.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or (Avatar.known and Avatar:Up())
	self.execute_phase = Target.health.pct < (Massacre.known and 35 or 20) or (Condemn.known and Target.health.pct > 80)
	--self.unique_legendaries = SignetOfTormentedKings.known or SinfulSurge.known  or ElysianMight.known
	self.bladestorm_condition = self.use_cds and (Rampage:Previous() or Enrage:Remains() > (Player.gcd * 2.5))
	if self.use_cds and SpearOfBastion:Usable() and Enrage:Up() and Player.rage.current < 70 then
		UseCooldown(SpearOfBastion)
	end
	if RecklessAbandon.known and Rampage:Usable() and Recklessness:Ready(3) then
		return Rampage
	end
	if self.use_cds and Recklessness:Usable() and (Player.enemies == 1 or WhirlwindFury.buff:Up()) and (
		(SinfulSurge.known and (self.execute_phase or ((AngerManagement.known and Target:TimeToPct(35) > 40) or (not AngerManagement.known and Target:TimeToPct(35) > 70)))) or
		(ElysianMight.known and (not SignetOfTormentedKings.known or self.bladestorm_condition or (ElysianMight:Up() and Player.rage.current < 70)) and (SpearOfBastion:Ready(5) or not SpearOfBastion:Ready(20))) or
		(SignetOfTormentedKings.known and Rampage:Previous() and (Target.timeToDie > 100 or self.execute_phase or Target.timeToDie < 15))
	) then
		UseCooldown(Recklessness)
	end
	if Player.enemies > 1 and WhirlwindFury:Usable() and WhirlwindFury.buff:Down() then
		return WhirlwindFury
	end
	if Bloodthirst:Usable() and Enrage:Down() and Player.rage.current < 50 and ((SpearOfBastion.known and SpearOfBastion:Ready(Player.gcd)) or (SignetOfTormentedKings.known and Recklessness:Ready(Player.gcd))) then
		return Bloodthirst
	end
	if Player.health.pct < Opt.heal_threshold then
		if VictoryRush:Usable() then
			UseExtra(VictoryRush)
		elseif ImpendingVictory:Usable() then
			UseExtra(ImpendingVictory)
		end
	end
	if Player.enemies > 1 then
		local apl = self:aoe()
		if apl then return apl end
	end
	return self:single_target()
end

APL[SPEC.FURY].aoe = function(self)
--[[
actions.aoe=cancel_buff,name=bladestorm,if=spell_targets.whirlwind>1&gcd.remains=0&soulbind.first_strike&buff.first_strike.remains&buff.enrage.remains<gcd
actions.aoe+=/spear_of_bastion,if=buff.enrage.up&rage<40&spell_targets.whirlwind>1
actions.aoe+=/bladestorm,if=buff.enrage.up&spell_targets.whirlwind>2
actions.aoe+=/siegebreaker,if=spell_targets.whirlwind>1
actions.aoe+=/rampage,if=spell_targets.whirlwind>1
actions.aoe+=/spear_of_bastion,if=buff.enrage.up&cooldown.recklessness.remains>5&spell_targets.whirlwind>1
actions.aoe+=/bladestorm,if=buff.enrage.remains>gcd*2.5&spell_targets.whirlwind>1
]]
	if self.use_cds and SpearOfBastion:Usable() and Enrage:Up() and Player.rage.current < 40 then
		UseCooldown(SpearOfBastion)
	end
	if self.use_cds and BladestormFury:Usable() and self.bladestorm_condition and Player.enemies > 2 then
		UseCooldown(BladestormFury)
	end
	if Siegebreaker:Usable() then
		return Siegebreaker
	end
	if Rampage:Usable() then
		return Rampage
	end
	if self.use_cds and SpearOfBastion:Usable() and Enrage:Up() and not Recklessness:Ready(5) then
		UseCooldown(SpearOfBastion)
	end
	if self.use_cds and BladestormFury:Usable() and self.bladestorm_condition then
		UseCooldown(BladestormFury)
	end
end

APL[SPEC.FURY].single_target = function(self)
--[[
actions.single_target=raging_blow,if=runeforge.will_of_the_berserker.equipped&buff.will_of_the_berserker.remains<gcd
actions.single_target+=/crushing_blow,if=runeforge.will_of_the_berserker.equipped&buff.will_of_the_berserker.remains<gcd
actions.single_target+=/cancel_buff,name=bladestorm,if=spell_targets.whirlwind=1&gcd.remains=0&(talent.massacre.enabled|covenant.venthyr.enabled)&variable.execute_phase&(rage>90|!cooldown.condemn.remains)
actions.single_target+=/siegebreaker,if=spell_targets.whirlwind>1|raid_event.adds.in>15
actions.single_target+=/rampage,if=buff.recklessness.up|(buff.enrage.remains<gcd|rage>80)|buff.frenzy.remains<1.5
actions.single_target+=/crushing_blow,if=set_bonus.tier28_2pc|charges=2|(buff.recklessness.up&variable.execute_phase&talent.massacre.enabled)
actions.single_target+=/execute
actions.single_target+=/spear_of_bastion,if=runeforge.elysian_might&buff.enrage.up&cooldown.recklessness.remains>5&(buff.recklessness.up|target.time_to_die<20|debuff.siegebreaker.up|!talent.siegebreaker&target.time_to_die>68)&raid_event.adds.in>55
actions.single_target+=/bladestorm,if=variable.bladestorm_condition&(!buff.recklessness.remains|rage<50)&(spell_targets.whirlwind=1&raid_event.adds.in>45|spell_targets.whirlwind=2)
actions.single_target+=/spear_of_bastion,if=buff.enrage.up&cooldown.recklessness.remains>5&(buff.recklessness.up|target.time_to_die<20|debuff.siegebreaker.up|!talent.siegebreaker&target.time_to_die>68)&raid_event.adds.in>55
actions.single_target+=/raging_blow,if=set_bonus.tier28_2pc|charges=2|(buff.recklessness.up&variable.execute_phase&talent.massacre.enabled)
actions.single_target+=/bloodthirst,if=buff.enrage.down|conduit.vicious_contempt.rank>5&target.health.pct<35
actions.single_target+=/bloodbath,if=buff.enrage.down|conduit.vicious_contempt.rank>5&target.health.pct<35&!talent.cruelty.enabled
actions.single_target+=/dragon_roar,if=buff.enrage.up&(spell_targets.whirlwind>1|raid_event.adds.in>15)
actions.single_target+=/whirlwind,if=buff.merciless_bonegrinder.up&spell_targets.whirlwind>3
actions.single_target+=/onslaught,if=buff.enrage.up
actions.single_target+=/bloodthirst
actions.single_target+=/bloodbath
actions.single_target+=/raging_blow
actions.single_target+=/crushing_blow
actions.single_target+=/whirlwind
]]
	if Siegebreaker:Usable() then
		return Siegebreaker
	end
	if Rampage:Usable() and (Player.rage.current > 80 or Recklessness:Up() or Frenzy:Remains() < 1.5 or Enrage:Remains() < Player.gcd) then
		return Rampage
	end
	if ExecuteFury:Usable() then
		return ExecuteFury
	end
	if self.use_cds and SpearOfBastion:Usable() and Enrage:Up() and not Recklessness:Ready(5) and (Recklessness:Up() or (Target.boss and Target.timeToDie < 20) or (Siegebreaker.known and Siegebreaker:Up()) or (Target.boss and not Siegebreaker.known and Target.timeToDie > 68)) then
		UseCooldown(SpearOfBastion)
	end
	if self.use_cds and BladestormFury:Usable() and self.bladestorm_condition and (Recklessness:Down() or Player.rage.current < 50) and between(Player.enemies, 1, 2) then
		UseCooldown(BladestormFury)
	end
	if RagingBlow:Usable() then
		return RagingBlow
	end
	if Bloodthirst:Usable() and Enrage:Down() then
		return Bloodthirst
	end
	if DragonRoar:Usable() and Enrage:Up() then
		return DragonRoar
	end
	if Bloodthirst:Usable() then
		return Bloodthirst
	end
	if RagingBlow:Usable() then
		return RagingBlow
	end
	if WhirlwindFury:Usable() then
		return WhirlwindFury
	end
end

APL[SPEC.PROTECTION].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then

		end
		if BattleShout:Usable() and BattleShout:Remains() < 300 then
			return BattleShout
		end
		if BattleStance:Down() and DefensiveStance:Down() then
			UseExtra(BattleStance)
		end
		if Charge:Usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
		end
		if BattleStance:Down() and DefensiveStance:Down() then
			UseExtra(BattleStance)
		end
	end
--[[
actions=auto_attack
actions+=/charge,if=time=0
actions+=/use_items
actions+=/potion,if=buff.avatar.up|buff.avatar.up&target.health.pct<=20
actions+=/run_action_list,name=aoe,if=spell_targets.thunder_clap>=3
actions+=/call_action_list,name=generic
]]
	self.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(Player.enemies - 1, 6)) or (Avatar.known and Avatar:Up())
	if Player:UnderAttack() then
		self:defensives()
	end
	if Player.health.pct < Opt.heal_threshold then
		if VictoryRush:Usable() then
			UseExtra(VictoryRush)
		elseif ImpendingVictory:Usable() then
			UseExtra(ImpendingVictory)
		end
	end
	if self.use_cds then
		self:cds()
	end
	if Player.enemies >= 3 then
		local apl = self:aoe()
		if apl then return apl end
	end
	return self:generic()
end

APL[SPEC.PROTECTION].defensives = function(self)
--[[
actions+=/shield_wall,if=talent.immovable_object.enabled&buff.avatar.down
actions+=/ignore_pain,if=target.health.pct>=20&(rage.deficit<=15&cooldown.shield_slam.ready|rage.deficit<=40&cooldown.shield_charge.ready&talent.champions_bulwark.enabled|rage.deficit<=20&cooldown.shield_charge.ready|rage.deficit<=30&cooldown.demoralizing_shout.ready&talent.booming_voice.enabled|rage.deficit<=20&cooldown.avatar.ready|rage.deficit<=45&cooldown.demoralizing_shout.ready&talent.booming_voice.enabled&buff.last_stand.up&talent.unnerving_focus.enabled|rage.deficit<=30&cooldown.avatar.ready&buff.last_stand.up&talent.unnerving_focus.enabled|rage.deficit<=20|rage.deficit<=40&cooldown.shield_slam.ready&buff.violent_outburst.up&talent.heavy_repercussions.enabled&talent.impenetrable_wall.enabled|rage.deficit<=55&cooldown.shield_slam.ready&buff.violent_outburst.up&buff.last_stand.up&talent.unnerving_focus.enabled&talent.heavy_repercussions.enabled&talent.impenetrable_wall.enabled|rage.deficit<=17&cooldown.shield_slam.ready&talent.heavy_repercussions.enabled|rage.deficit<=18&cooldown.shield_slam.ready&talent.impenetrable_wall.enabled),use_off_gcd=1
actions+=/last_stand,if=(target.health.pct>=90&talent.unnerving_focus.enabled|target.health.pct<=20&talent.unnerving_focus.enabled)|talent.bolster.enabled
actions+=/shield_block,if=buff.shield_block.duration<=18&talent.enduring_defenses.enabled|buff.shield_block.duration<=12
]]
	if self.use_cds and ShieldWall:Usable() and ImmovableObject.known and Avatar:Down() then
		return UseExtra(ShieldWall)
	end
	if ShieldBlock:Usable() and ShieldBlock:Remains() < 2 then
		return UseExtra(ShieldBlock)
	end
	if IgnorePain:Usable() and (Player.rage.deficit <= 30 or (Player.rage.deficit <= 55 and IgnorePain:Remains() < 2)) then
		return UseExtra(IgnorePain)
	end
	if self.use_cds and LastStand:Usable() and (
		Player.health.pct < 20 or
		Bolster.known or
		(UnnervingFocus.known and (Target.health.pct >= 90 or Target.health.pct <= 20))
	) then
		return UseExtra(LastStand)
	end
	if ShieldBlock:Usable() and (Player.enemies > 1 or Target.timeToDie > ShieldBlock:Remains()) and (ShieldBlock:Remains() < 4 or (Player.rage.deficit <= 40 and ShieldBlock:Remains() < (EnduringDefenses.known and 18 or 12))) then
		return UseExtra(ShieldBlock)
	end
end

APL[SPEC.PROTECTION].cds = function(self)
--[[
actions+=/avatar
actions+=/ravager
actions+=/demoralizing_shout,if=talent.booming_voice.enabled
actions+=/spear_of_bastion
actions+=/thunderous_roar
actions+=/shockwave,if=talent.sonic_boom.enabled&buff.avatar.up&talent.unstoppable_force.enabled&!talent.rumbling_earth.enabled
actions+=/shield_charge
]]
	if Avatar:Usable() then
		return UseCooldown(Avatar)
	end
	if Ravager:Usable() then
		return UseCooldown(Ravager)
	end
	if BoomingVoice.known and DemoralizingShout:Usable() then
		return UseCooldown(DemoralizingShout)
	end
	if SpearOfBastion:Usable() then
		return UseCooldown(SpearOfBastion)
	end
	if ThunderousRoar:Usable() then
		return UseCooldown(ThunderousRoar)
	end
	if SonicBoom.known and Shockwave:Usable() and Avatar:Up() and UnstoppableForce.known and not RumblingEarth.known then
		return UseCooldown(Shockwave)
	end
	if ShieldCharge:Usable() then
		return UseCooldown(ShieldCharge)
	end
end

APL[SPEC.PROTECTION].aoe = function(self)
--[[
actions.aoe=thunder_clap,if=dot.rend.remains<=1
actions.aoe+=/thunder_clap,if=buff.violent_outburst.up&spell_targets.thunderclap>5&buff.avatar.up&talent.unstoppable_force.enabled
actions.aoe+=/revenge,if=rage>=70&talent.seismic_reverberation.enabled&spell_targets.revenge>=3
actions.aoe+=/shield_slam,if=rage<=60|buff.violent_outburst.up&spell_targets.thunderclap<=4
actions.aoe+=/thunder_clap
actions.aoe+=/revenge,if=rage>=30|rage>=40&talent.barbaric_training.enabled
]]
	if ThunderClapProt:Usable() and Rend:Remains() < 1 then
		return ThunderClapProt
	end
	if UnstoppableForce.known and ThunderClapProt:Usable() and ViolentOutburst:Up() and Player.enemies > 5 then
		return ThunderClapProt
	end
	if SeismicReverbation.known and Revenge:Usable() and Player.rage.current >= 70 and Player.enemies >= 3 then
		return Revenge
	end
	if ShieldSlam:Usable() and (Player.rage.current <= 60 or (ViolentOutburst:Up() and Player.enemies <= 4)) then
		return ShieldSlam
	end
	if ThunderClapProt:Usable() then
		return ThunderClapProt
	end
	if Revenge:Usable() and Player.rage.current >= 30 then
		return Revenge
	end
end

APL[SPEC.PROTECTION].generic = function(self)
--[[
actions.generic=shield_slam
actions.generic+=/thunder_clap,if=dot.rend.remains<=1&buff.violent_outburst.down
actions.generic+=/execute,if=buff.sudden_death.up&talent.sudden_death.enabled
actions.generic+=/execute,if=spell_targets.revenge=1&(talent.massacre.enabled|talent.juggernaut.enabled)&rage>=50
actions.generic+=/revenge,if=buff.vanguards_determination.down&rage>=40
actions.generic+=/execute,if=spell_targets.revenge=1&rage>=50
actions.generic+=/thunder_clap,if=(spell_targets.thunder_clap>1|cooldown.shield_slam.remains&!buff.violent_outburst.up)
actions.generic+=/revenge,if=(rage>=60&target.health.pct>20|buff.revenge.up&target.health.pct<=20&rage<=18&cooldown.shield_slam.remains|buff.revenge.up&target.health.pct>20)|(rage>=60&target.health.pct>35|buff.revenge.up&target.health.pct<=35&rage<=18&cooldown.shield_slam.remains|buff.revenge.up&target.health.pct>35)&talent.massacre.enabled
actions.generic+=/execute,if=spell_targets.revenge=1
actions.generic+=/revenge
actions.generic+=/thunder_clap
actions.generic+=/devastate
]]
	if ShieldSlam:Usable() then
		return ShieldSlam
	end
	if ThunderClapProt:Usable() and Rend:Remains() < 1 and ViolentOutburst:Down() then
		return ThunderClapProt
	end
	if SuddenDeath.known and Execute:Usable() and SuddenDeath:Up() then
		return Execute
	end
	if Execute:Usable() and Player.enemies == 1 and (Massacre.known or Juggernaut.known) and Player.rage.current >= 50 then
		return Execute
	end
	if Revenge:Usable() and VanguardsDetermination:Down() and Player.rage.current >= 40 then
		return Revenge
	end
	if Execute:Usable() and Player.enemies == 1 and Player.rage.current >= 50 then
		return Execute
	end
	if ThunderClapProt:Usable() and (Player.enemies > 1 or (not ShieldSlam:Ready() and ViolentOutburst:Down())) then
		return ThunderClapProt
	end
	self.execute_pct = Massacre.known and 35 or 20
	if Revenge:Usable() and (
		(Target.health.pct > self.execute_pct and (Player.rage.current >= 60 or Revenge.free:Up())) or
		(Target.health.pct <= self.execute_pct and Revenge.free:Up() and Player.rage.current <= 18 and not ShieldSlam:Ready())
	) then
		return Revenge
	end
	if Execute:Usable() and Player.enemies == 1 then
		return Execute
	end
	if Revenge:Usable() then
		return Revenge
	end
	if ThunderClapProt:Usable() then
		return ThunderClapProt
	end
	if Devastate:Usable() then
		return Devastate
	end
end

APL.Interrupt = function(self)
	if Pummel:Usable() then
		return Pummel
	end
	if Target.stunnable then
		if Shockwave:Usable() and Player.enemies >= 3 then
			return Shockwave
		end
		if StormBolt:Usable() then
			return StormBolt
		end
		if Shockwave:Usable() then
			return Shockwave
		end
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	smashPanel:EnableMouse(draggable or Opt.aoe)
	smashPanel.button:SetShown(Opt.aoe)
	smashPreviousPanel:EnableMouse(draggable)
	smashCooldownPanel:EnableMouse(draggable)
	smashInterruptPanel:EnableMouse(draggable)
	smashExtraPanel:EnableMouse(draggable)
end

function UI:UpdateAlpha()
	smashPanel:SetAlpha(Opt.alpha)
	smashPreviousPanel:SetAlpha(Opt.alpha)
	smashCooldownPanel:SetAlpha(Opt.alpha)
	smashInterruptPanel:SetAlpha(Opt.alpha)
	smashExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	smashPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	smashPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	smashCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	smashInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	smashExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	smashPreviousPanel:ClearAllPoints()
	smashPreviousPanel:SetPoint('TOPRIGHT', smashPanel, 'BOTTOMLEFT', -3, 40)
	smashCooldownPanel:ClearAllPoints()
	smashCooldownPanel:SetPoint('TOPLEFT', smashPanel, 'BOTTOMRIGHT', 3, 40)
	smashInterruptPanel:ClearAllPoints()
	smashInterruptPanel:SetPoint('BOTTOMLEFT', smashPanel, 'TOPRIGHT', 3, -21)
	smashExtraPanel:ClearAllPoints()
	smashExtraPanel:SetPoint('BOTTOMRIGHT', smashPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.ARMS] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ARMS] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -1 },
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		smashPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		smashPanel:ClearAllPoints()
		smashPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		(Player.spec == SPEC.ARMS and Opt.hide.arms) or
		(Player.spec == SPEC.FURY and Opt.hide.fury) or
		(Player.spec == SPEC.PROTECTION and Opt.hide.protection))
end

function UI:Disappear()
	smashPanel:Hide()
	smashPanel.icon:Hide()
	smashPanel.border:Hide()
	smashCooldownPanel:Hide()
	smashInterruptPanel:Hide()
	smashExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, border, text_center, text_cd, color_center

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.pool_rage then
		local deficit = Player.pool_rage - UnitPower('player', 1)
		if deficit > 0 then
			text_center = format('POOL %d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.channel.tick_count > 0 then
		dim = Opt.dimmer
		if Player.channel.tick_count > 1 then
			local ctime = GetTime()
			local channel = Player.channel
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = 'CHAIN'
					color_center = 'green'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if color_center ~= smashPanel.text.center.color then
		smashPanel.text.center.color = color_center
		if color_center == 'green' then
			smashPanel.text.center:SetTextColor(0, 1, 0, 1)
		elseif color_center == 'red' then
			smashPanel.text.center:SetTextColor(1, 0, 0, 1)
		else
			smashPanel.text.center:SetTextColor(1, 1, 1, 1)
		end
	end
	if border ~= smashPanel.border.overlay then
		smashPanel.border.overlay = border
		smashPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	smashPanel.dimmer:SetShown(dim)
	smashPanel.text.center:SetText(text_center)
	--smashPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	smashCooldownPanel.text:SetText(text_cd)
	smashCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		smashPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.rage_cost > 0 and Player.main:Cost() == 0) or (Player.main.Free and Player.main:Free())
	end
	if Player.cd then
		smashCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			smashCooldownPanel.swipe:SetCooldown(start, duration)
		end
	end
	if Player.extra then
		smashExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			smashInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			smashInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		smashInterruptPanel.icon:SetShown(Player.interrupt)
		smashInterruptPanel.border:SetShown(Player.interrupt)
		smashInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and smashPreviousPanel.ability then
		if (Player.time - smashPreviousPanel.ability.last_used) > 10 then
			smashPreviousPanel.ability = nil
			smashPreviousPanel:Hide()
		end
	end

	smashPanel.icon:SetShown(Player.main)
	smashPanel.border:SetShown(Player.main)
	smashCooldownPanel:SetShown(Player.cd)
	smashExtraPanel:SetShown(Player.extra)

	if Player.spec == SPEC.FURY then
		local start, duration, stack = WhirlwindFury.buff:StartDurationStack()
		if stack > 0 then
			smashExtraPanel.whirlwind.stack:SetText(stack)
			smashExtraPanel.whirlwind:SetCooldown(start, duration)
			if not Player.extra then
				smashExtraPanel.icon:SetTexture(WhirlwindFury.buff.icon)
				smashExtraPanel:SetShown(true)
			end
		end
		smashExtraPanel.whirlwind:SetShown(stack > 0)
	end

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = Smash
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Smash1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ENERGIZE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if dstGUID == Player.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		if ability == WhirlwindFury.buff and (event == 'SPELL_AURA_REMOVED' or event == 'SPELL_AURA_REMOVED_DOSE') then
			ability.pending_stack_use = false
		end
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not ability.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		smashPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
	local _, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end

	Player.set_bonus.t29 = (Player:Equipped(200423) and 1 or 0) + (Player:Equipped(200425) and 1 or 0) + (Player:Equipped(200426) and 1 or 0) + (Player:Equipped(200427) and 1 or 0) + (Player:Equipped(200428) and 1 or 0)
	Player.set_bonus.t30 = (Player:Equipped(202441) and 1 or 0) + (Player:Equipped(202442) and 1 or 0) + (Player:Equipped(202443) and 1 or 0) + (Player:Equipped(202444) and 1 or 0) + (Player:Equipped(202446) and 1 or 0)

	Player:ResetSwing(true, true)
	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	smashPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end

function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		smashPanel.swipe:SetCooldown(start, duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

smashPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

smashPanel:SetScript('OnUpdate', function(self, elapsed)
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

smashPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	smashPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				smashPanel:ClearAllPoints()
			end
			UI:UpdateDraggable()
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'a') then
				Opt.hide.arms = not Opt.hide.arms
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Arms specialization', not Opt.hide.arms)
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.fury = not Opt.hide.fury
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Fury specialization', not Opt.hide.fury)
			end
			if startsWith(msg[2], 'p') then
				Opt.hide.protection = not Opt.hide.protection
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Protection specialization', not Opt.hide.protection)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000arms|r/|cFFFFD000fury|r/|cFFFFD000protection|r')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 10
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal_threshold = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal_threshold .. '%')
	end
	if startsWith(msg[1], 'de') then
		if msg[2] then
			Opt.defensives = msg[2] == 'on'
		end
		return Status('Show defensives/emergency heals in extra UI', Opt.defensives)
	end
	if msg[1] == 'reset' then
		smashPanel:ClearAllPoints()
		smashPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000arms|r/|cFFFFD000fury|r/|cFFFFD000protection|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'defensives |cFF00C000on|r/|cFFC00000off|r - show defensives/emergency heals in extra UI',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Smash1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
