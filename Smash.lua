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
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
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
		cd_ttd = 8,
		pot = false,
		trinket = true,
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
local events = {}

local timer = {
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
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	health = {
		current = 0,
		max = 100,
		pct = 0,
	},
	rage = {
		current = 0,
		deficit = 0,
		max = 100,
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
		t29 = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
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
		{4, '4'},
		{5, '5+'},
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

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
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

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
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

function autoAoe:Purge()
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

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

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
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
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

function Ability:Remains()
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
			return max(0, expires - Player.ctime - Player.execute_remains)
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
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
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
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.aura_target, i, self.aura_filter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
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
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
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
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return 0
	end
	return castTime / 1000
end

function Ability:WontCapRage(reduction)
	return (Player.rage.current + self:Gain()) < (Player.rage.max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
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
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
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
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.aura_target == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		autoAoe:Add(dstGUID, true)
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
			if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, Player.time - oldest.start)))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(max(5, min(self.max_range, self.velocity * (Player.time - self.range_est_start))))
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
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration))
	return aura
end

function Ability:RefreshAuraAll()
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

-- Warrior Abilities
---- Multiple Specializations
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
local Avatar = Ability:Add(107574, true, true)
Avatar.buff_duration = 20
Avatar.cooldown_duration = 90
local DragonRoar = Ability:Add(118000, false, true)
DragonRoar.buff_duration = 6
DragonRoar.cooldown_duration = 35
DragonRoar:AutoAoe(true)
local ImpendingVictory = Ability:Add(202168, false, true)
ImpendingVictory.cooldown_duration = 30
ImpendingVictory.rage_cost = 10
local Massacre = Ability:Add(206315, false, true, 281001)
local Ravager = Ability:Add(152277, false, true)
Ravager.buff_duration = 7
Ravager.cooldown_duration = 60
local RecklessAbandon = Ability:Add(202751, false, true)
local StormBolt = Ability:Add(107570, false, false, 132169)
StormBolt.buff_duration = 4
StormBolt.cooldown_duration = 30
---- Arms
local Bladestorm = Ability:Add(227847, true, true)
Bladestorm.buff_duration = 4
Bladestorm.cooldown_duration = 60
Bladestorm.damage = Ability:Add(50622, false, true)
Bladestorm.damage:AutoAoe(true)
local ColossusSmash = Ability:Add(167105, false, true)
ColossusSmash.cooldown_duration = 45
ColossusSmash.debuff = Ability:Add(208086, false, true)
ColossusSmash.debuff.buff_duration = 10
local DeepWounds = Ability:Add(262111, false, true, 262115)
DeepWounds.buff_duration = 6
DeepWounds.tick_interval = 2
DeepWounds.hasted_ticks = true
local DieByTheSword = Ability:Add(118038, true, true)
DieByTheSword.buff_duration = 8
DieByTheSword.cooldown_duration = 180
local Execute = Ability:Add(163201, false, true)
Execute.rage_cost = 20
local MortalStrike = Ability:Add(12294, false, true)
MortalStrike.rage_cost = 30
MortalStrike.cooldown_duration = 6
MortalStrike.hasted_cooldown = true
local Overpower = Ability:Add(7384, true, true, 60503)
Overpower.buff_duration = 12
Overpower.cooldown_duration = 12
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
local Cleave = Ability:Add(845, false, true)
Cleave.rage_cost = 20
Cleave.cooldown_duration = 9
Cleave.hasted_cooldown = true
Cleave:AutoAoe()
local DeadlyCalm = Ability:Add(262228, true, true)
DeadlyCalm.buff_duration = 6
DeadlyCalm.cooldown_duration = 60
DeadlyCalm.triggers_gcd = false
local Dreadnaught = Ability:Add(262150, false, true)
local FervorOfBattle = Ability:Add(202316, false, true)
local Rend = Ability:Add(772, false, true)
Rend.rage_cost = 30
Rend.buff_duration = 12
Rend.tick_interval = 3
Rend.hasted_ticks = true
local Skullsplitter = Ability:Add(260643, false, true)
Skullsplitter.cooldown_duration = 21
Skullsplitter.hasted_cooldown = true
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
local DemoralizingShout = Ability:Add(1160, false, true)
DemoralizingShout.buff_duration = 8
DemoralizingShout.cooldown_duration = 45
local Devastate = Ability:Add(20243, false, true)
local IgnorePain = Ability:Add(190456, true, true)
IgnorePain.buff_duration = 12
IgnorePain.cooldown_duration = 1
IgnorePain.rage_cost = 40
IgnorePain.triggers_gcd = false
local Intercept = Ability:Add(198304, false, true)
Intercept.cooldown_duration = 15
Intercept.requires_charge = true
Intercept.triggers_gcd = false
local LastStand = Ability:Add(12975, true, true)
LastStand.buff_duration = 15
LastStand.cooldown_duration = 120
LastStand.triggers_gcd = false
local Revenge = Ability:Add(6572, false, true)
Revenge.cooldown_duration = 3
Revenge.rage_cost = 30
Revenge.hasted_cooldown = true
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
local ShieldSlam = Ability:Add(23922, false, true)
ShieldSlam.cooldown_duration = 9
ShieldSlam.hasted_cooldown = true
local ShieldWall = Ability:Add(871, true, true)
ShieldWall.buff_duration = 8
ShieldWall.cooldown_duration = 240
ShieldWall.triggers_gcd = false
local Shockwave = Ability:Add(46968, false, true, 132168)
Shockwave.buff_duration = 2
Shockwave.cooldown_duration = 40
Shockwave:AutoAoe()
local ThunderClap = Ability:Add(6343, false, true)
ThunderClap.buff_duration = 10
ThunderClap.cooldown_duration = 6
ThunderClap.hasted_cooldown = true
ThunderClap:AutoAoe(true)
------ Talents
local BoomingVoice = Ability:Add(202743, false, true)
local Devastator = Ability:Add(236279, false, true)
local UnstoppableForce = Ability:Add(275336, false, true)
------ Procs

-- Racials

-- PvP talents

-- Trinket effects

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

-- Start Player API

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
	if self.ability_casting and self.ability_casting.triggers_combat then
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

function Player:UpdateAbilities()
	self.rage.max = UnitPowerMax('player', 1)

	local node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, abilities.all do
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
	Bladestorm.damage.known = Bladestorm.known or BladestormFury.known
	ColossusSmash.debuff.known = ColossusSmash.known or Warbreaker.known
	Revenge.free.known = Revenge.known
	Victorious.known = VictoryRush.known or ImpendingVictory.known
	WhirlwindFury.buff.known = WhirlwindFury.known

	wipe(abilities.bySpellId)
	wipe(abilities.velocity)
	wipe(abilities.autoAoe)
	wipe(abilities.trackAuras)
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == Player.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, start, duration, remains, spellId, speed_mh, speed_oh
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.pool_rage = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self.moving = GetUnitSpeed('player') ~= 0
	self:UpdateThreat()
	self.gcd = 1.5 * self.haste_factor
	self.rage.current = UnitPower('player', 1)
	self.rage.deficit = self.rage.max - self.rage.current

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
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
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
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
	UI:Disappear()
	if UI:ShouldHide() then
		return
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
		return
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

function Target:Stunned()
	if StormBolt:Up() or Shockwave:Up() then
		return true
	end
	return false
end

-- End Target API

-- Start Ability Modifications

function Ability:Cost()
	if DeadlyCalm.known and DeadlyCalm:Up() then
		return 0
	end
	return self.rage_cost
end

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

local function Pool(ability, extra)
	Player.pool_rage = ability:Cost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.ARMS] = {},
	[SPEC.FURY] = {},
	[SPEC.PROTECTION] = {},
}

APL[SPEC.ARMS].Main = function(self)
	if Player:TimeInCombat() == 0 then
		if not Player:InArenaOrBattleground() then

		end
		if BattleShout:Usable() and BattleShout:Remains() < 300 then
			return BattleShout
		end
		if Charge:Usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
		end
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
		if Charge:Usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
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
	self.execute_phase = Target.health.pct < (Massacre.known and 35 or 20) or (Condemn.known and Target.health.pct > 80)
	--self.unique_legendaries = SignetOfTormentedKings.known or SinfulSurge.known  or ElysianMight.known
	self.bladestorm_condition = (Rampage:Previous() or Enrage:Remains() > (Player.gcd * 2.5)) and (not MercilessBonegrinder.known or Player.enemies <= 3 or MercilessBonegrinder:Down())
	if SpearOfBastion:Usable() and Enrage:Up() and Player.rage.current < 70 then
		UseCooldown(SpearOfBastion)
	end
	if RecklessAbandon.known and Rampage:Usable() and Recklessness:Ready(3) then
		return Rampage
	end
	if Recklessness:Usable() and (Player.enemies == 1 or WhirlwindFury.buff:Up()) and (
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
	if VictoryRush:Usable() and Player.health.pct < 85 then
		UseExtra(VictoryRush)
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
	if SpearOfBastion:Usable() and Enrage:Up() and Player.rage.current < 40 then
		UseCooldown(SpearOfBastion)
	end
	if BladestormFury:Usable() and self.bladestorm_condition and Player.enemies > 2 then
		UseCooldown(BladestormFury)
	end
	if Siegebreaker:Usable() then
		return Siegebreaker
	end
	if Rampage:Usable() then
		return Rampage
	end
	if SpearOfBastion:Usable() and Enrage:Up() and not Recklessness:Ready(5) then
		UseCooldown(SpearOfBastion)
	end
	if BladestormFury:Usable() and self.bladestorm_condition then
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
	if SpearOfBastion:Usable() and Enrage:Up() and not Recklessness:Ready(5) and (Recklessness:Up() or (Target.boss and Target.timeToDie < 20) or (Siegebreaker.known and Siegebreaker:Up()) or (Target.boss and not Siegebreaker.known and Target.timeToDie > 68)) then
		UseCooldown(SpearOfBastion)
	end
	if BladestormFury:Usable() and self.bladestorm_condition and (Recklessness:Down() or Player.rage.current < 50) and between(Player.enemies, 1, 2) then
		UseCooldown(BladestormFury)
	end
	if MercilessBonegrinder.known and WhirlwindFury:Usable() and MercilessBonegrinder:Up() and Player.enemies > 3 then
		return WhirlwindFury
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
		if Charge:Usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
		end
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

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard and actionButton.overlay then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
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
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
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
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ARMS] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, -2 }
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
	timer.display = 0
	local dim, dim_cd, text_center, text_cd

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.main and Player.main.requires_react then
		local react = Player.main:React()
		if react > 0 then
			text_center = format('%.1f', react)
		end
	end
	if Player.cd and Player.cd.requires_react then
		local react = Player.cd:React()
		if react > 0 then
			text_cd = format('%.1f', react)
		end
	end
	if Player.pool_rage then
		local deficit = Player.pool_rage - UnitPower('player', 1)
		if deficit > 0 then
			text_center = format('POOL %d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.main and Player.main_freecast then
		if not smashPanel.freeCastOverlayOn then
			smashPanel.freeCastOverlayOn = true
			smashPanel.border:SetTexture(ADDON_PATH .. 'freecast.blp')
		end
	elseif smashPanel.freeCastOverlayOn then
		smashPanel.freeCastOverlayOn = false
		smashPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end

	smashPanel.dimmer:SetShown(dim)
	smashPanel.text.center:SetText(text_center)
	--smashPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	smashCooldownPanel.text:SetText(text_cd)
	smashCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.spec]:Main()
	if Player.main then
		smashPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = (Player.main.rage_cost > 0 and Player.main:Cost() == 0)
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
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
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
		autoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID ~= Player.guid then
		return
	end
	local ability = spellId and abilities.bySpellId[spellId]
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
		if ability == WhirlwindFury.buff and (event == 'SPELL_AURA_REMOVED' or event == 'SPELL_AURA_REMOVED_DOSE') then
			ability.pending_stack_use = false
		end
		return -- ignore buffs beyond here
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth('player')
		Player.health.max = UnitHealthMax('player')
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

--[[
function events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
end
]]

function events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		smashPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
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

	Player:ResetSwing(true, true)
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	smashPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	events:UNIT_HEALTH('player')
	UI.OnResourceFrameShow()
	Player:Update()
end

function events:TRAIT_CONFIG_UPDATED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function events:SPELL_UPDATE_COOLDOWN()
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

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
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
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

smashPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
for event in next, events do
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
				lasikPanel:ClearAllPoints()
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
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
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
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Arms specialization', not Opt.hide.arms)
			end
			if startsWith(msg[2], 'f') then
				Opt.hide.fury = not Opt.hide.fury
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Fury specialization', not Opt.hide.fury)
			end
			if startsWith(msg[2], 'p') then
				Opt.hide.protection = not Opt.hide.protection
				events:PLAYER_SPECIALIZATION_CHANGED('player')
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
			Opt.cd_ttd = tonumber(msg[2]) or 8
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
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
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
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Smash1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
