if select(2, UnitClass('player')) ~= 'WARRIOR' then
	DisableAddOn('Smash')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

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
BINDING_HEADER_SMASH = 'Smash'

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
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
		pot = false,
		trinket = true,
		swing_timer = true,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
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
	spec = 0,
	target_mode = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	rage = 0,
	rage_max = 100,
	equipped_mh = false,
	equipped_oh = false,
	next_swing_mh = 0,
	next_swing_oh = 0,
	last_swing_taken = 0,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[174044] = true, -- Humming Black Dragonscale (parachute)
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

local smashPanel = CreateFrame('Frame', 'smashPanel', UIParent)
smashPanel:SetPoint('CENTER', 0, -169)
smashPanel:SetFrameStrata('BACKGROUND')
smashPanel:SetSize(64, 64)
smashPanel:SetMovable(true)
smashPanel:Hide()
smashPanel.icon = smashPanel:CreateTexture(nil, 'BACKGROUND')
smashPanel.icon:SetAllPoints(smashPanel)
smashPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashPanel.border = smashPanel:CreateTexture(nil, 'ARTWORK')
smashPanel.border:SetAllPoints(smashPanel)
smashPanel.border:SetTexture('Interface\\AddOns\\Smash\\border.blp')
smashPanel.border:Hide()
smashPanel.dimmer = smashPanel:CreateTexture(nil, 'BORDER')
smashPanel.dimmer:SetAllPoints(smashPanel)
smashPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
smashPanel.dimmer:Hide()
smashPanel.swipe = CreateFrame('Cooldown', nil, smashPanel, 'CooldownFrameTemplate')
smashPanel.swipe:SetAllPoints(smashPanel)
smashPanel.swipe:SetDrawBling(false)
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
smashPanel.button = CreateFrame('Button', nil, smashPanel)
smashPanel.button:SetAllPoints(smashPanel)
smashPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local smashPreviousPanel = CreateFrame('Frame', 'smashPreviousPanel', UIParent)
smashPreviousPanel:SetFrameStrata('BACKGROUND')
smashPreviousPanel:SetSize(64, 64)
smashPreviousPanel:Hide()
smashPreviousPanel:RegisterForDrag('LeftButton')
smashPreviousPanel:SetScript('OnDragStart', smashPreviousPanel.StartMoving)
smashPreviousPanel:SetScript('OnDragStop', smashPreviousPanel.StopMovingOrSizing)
smashPreviousPanel:SetMovable(true)
smashPreviousPanel.icon = smashPreviousPanel:CreateTexture(nil, 'BACKGROUND')
smashPreviousPanel.icon:SetAllPoints(smashPreviousPanel)
smashPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashPreviousPanel.border = smashPreviousPanel:CreateTexture(nil, 'ARTWORK')
smashPreviousPanel.border:SetAllPoints(smashPreviousPanel)
smashPreviousPanel.border:SetTexture('Interface\\AddOns\\Smash\\border.blp')
local smashCooldownPanel = CreateFrame('Frame', 'smashCooldownPanel', UIParent)
smashCooldownPanel:SetSize(64, 64)
smashCooldownPanel:SetFrameStrata('BACKGROUND')
smashCooldownPanel:Hide()
smashCooldownPanel:RegisterForDrag('LeftButton')
smashCooldownPanel:SetScript('OnDragStart', smashCooldownPanel.StartMoving)
smashCooldownPanel:SetScript('OnDragStop', smashCooldownPanel.StopMovingOrSizing)
smashCooldownPanel:SetMovable(true)
smashCooldownPanel.icon = smashCooldownPanel:CreateTexture(nil, 'BACKGROUND')
smashCooldownPanel.icon:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashCooldownPanel.border = smashCooldownPanel:CreateTexture(nil, 'ARTWORK')
smashCooldownPanel.border:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.border:SetTexture('Interface\\AddOns\\Smash\\border.blp')
smashCooldownPanel.cd = CreateFrame('Cooldown', nil, smashCooldownPanel, 'CooldownFrameTemplate')
smashCooldownPanel.cd:SetAllPoints(smashCooldownPanel)
local smashInterruptPanel = CreateFrame('Frame', 'smashInterruptPanel', UIParent)
smashInterruptPanel:SetFrameStrata('BACKGROUND')
smashInterruptPanel:SetSize(64, 64)
smashInterruptPanel:Hide()
smashInterruptPanel:RegisterForDrag('LeftButton')
smashInterruptPanel:SetScript('OnDragStart', smashInterruptPanel.StartMoving)
smashInterruptPanel:SetScript('OnDragStop', smashInterruptPanel.StopMovingOrSizing)
smashInterruptPanel:SetMovable(true)
smashInterruptPanel.icon = smashInterruptPanel:CreateTexture(nil, 'BACKGROUND')
smashInterruptPanel.icon:SetAllPoints(smashInterruptPanel)
smashInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashInterruptPanel.border = smashInterruptPanel:CreateTexture(nil, 'ARTWORK')
smashInterruptPanel.border:SetAllPoints(smashInterruptPanel)
smashInterruptPanel.border:SetTexture('Interface\\AddOns\\Smash\\border.blp')
smashInterruptPanel.cast = CreateFrame('Cooldown', nil, smashInterruptPanel, 'CooldownFrameTemplate')
smashInterruptPanel.cast:SetAllPoints(smashInterruptPanel)
local smashExtraPanel = CreateFrame('Frame', 'smashExtraPanel', UIParent)
smashExtraPanel:SetFrameStrata('BACKGROUND')
smashExtraPanel:SetSize(64, 64)
smashExtraPanel:Hide()
smashExtraPanel:RegisterForDrag('LeftButton')
smashExtraPanel:SetScript('OnDragStart', smashExtraPanel.StartMoving)
smashExtraPanel:SetScript('OnDragStop', smashExtraPanel.StopMovingOrSizing)
smashExtraPanel:SetMovable(true)
smashExtraPanel.icon = smashExtraPanel:CreateTexture(nil, 'BACKGROUND')
smashExtraPanel.icon:SetAllPoints(smashExtraPanel)
smashExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
smashExtraPanel.border = smashExtraPanel:CreateTexture(nil, 'ARTWORK')
smashExtraPanel.border:SetAllPoints(smashExtraPanel)
smashExtraPanel.border:SetTexture('Interface\\AddOns\\Smash\\border.blp')
-- Fury Whirlwind stacks and duration remaining on extra icon
smashExtraPanel.whirlwind = CreateFrame('Cooldown', nil, smashExtraPanel, 'CooldownFrameTemplate')
smashExtraPanel.whirlwind:SetAllPoints(smashExtraPanel)
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
	}
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
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
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
	local update, guid, t
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
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rage_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
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
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(pool)
	if not self.known then
		return false
	end
	if self:Cost() > Player.rage then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready()
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
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

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
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
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.rage_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
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
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastEnergyRegen()
	return Player.energy_regen * self:CastTime() - self:EnergyCost()
end

function Ability:WontCapEnergy(reduction)
	return (Player.energy + self:CastEnergyRegen()) < (Player.energy_max - (reduction or 5))
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

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
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
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
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
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

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
Bloodthirst.hasted_cooldown = true
local ExecuteFury = Ability:Add(5308, false, true)
local RagingBlow = Ability:Add(85288, false, true)
RagingBlow.cooldown_duration = 8
RagingBlow.hasted_cooldown = true
RagingBlow.requires_charge = true
local Rampage = Ability:Add(184367, false, true)
Rampage.rage_cost = 85
local Recklessness = Ability:Add(1719, true, true)
Recklessness.buff_duration = 10
Recklessness.cooldown_duration = 90
local WhirlwindFury = Ability:Add(190411, false, true, 199667)
WhirlwindFury:AutoAoe(true)
WhirlwindFury.buff = Ability:Add(85739, true, true)
WhirlwindFury.buff.buff_duration = 20
------ Talents
local BladestormFury = Ability:Add(46924, true, true)
BladestormFury.buff_duration = 4
BladestormFury.cooldown_duration = 60
local Carnage = Ability:Add(202922, false, true)
local FrothingBerserker = Ability:Add(215571, false, true)
local FuriousSlash = Ability:Add(100130, true, true, 202539)
FuriousSlash.buff_duration = 15
local Siegebreaker = Ability:Add(280772, false, true, 280773)
Siegebreaker.buff_duration = 10
Siegebreaker.cooldown_duration = 30
local SuddenDeathFury = Ability:Add(280721, true, true, 280776)
SuddenDeathFury.buff_duration = 10
------ Procs
local Enrage = Ability:Add(184361, true, true, 184362)
Enrage.buff_duration = 4
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

--- Azerite Traits
local ColdSteelHotBlood = Ability:Add(288080, false, true)
local CrushingAssault = Ability:Add(278751, true, true, 278826)
CrushingAssault.buff_duration = 10
local ExecutionersPrecision = Ability:Add(272866, false, true, 272870)
ExecutionersPrecision.buff_duration = 30
local SeismicWave = Ability:Add(277639, false, true, 278497)
SeismicWave:AutoAoe()
local TestOfMight = Ability:Add(275529, true, true, 275540)
TestOfMight.buff_duration = 12
-- Heart of Azeroth
---- Major Essences
local AnimaOfDeath = Ability:Add(300003, false, true)
AnimaOfDeath.cooldown_duration = 120
AnimaOfDeath.essence_id = 24
AnimaOfDeath.essence_major = true
local BloodOfTheEnemy = Ability:Add(298277, false, true)
BloodOfTheEnemy.buff_duration = 10
BloodOfTheEnemy.cooldown_duration = 120
BloodOfTheEnemy.essence_id = 23
BloodOfTheEnemy.essence_major = true
local ConcentratedFlame = Ability:Add(295373, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add(295840, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add(295258, false, true, 295261)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
FocusedAzeriteBeam:AutoAoe()
local MemoryOfLucidDreams = Ability:Add(298357, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add(295337, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local ReapingFlames = Ability:Add(310690, false, true)
ReapingFlames.cooldown_duration = 45
ReapingFlames.essence_id = 35
ReapingFlames.essence_major = true
local RippleInSpace = Ability:Add(302731, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add(298452, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability:Add(299370, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add(295186, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302932, true, true)
RecklessForce.buff_duration = 3
RecklessForce.essence_id = 28
RecklessForce.counter = Ability:Add(302917, true, true)
RecklessForce.counter.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- Racials

-- PvP talents

-- Trinket Effects

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
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
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
local GreaterFlaskOfTheUndertow = InventoryItem:Add(168654)
GreaterFlaskOfTheUndertow.buff = Ability:Add(298841, true, true)
local SuperiorBattlePotionOfStrength = InventoryItem:Add(168500)
SuperiorBattlePotionOfStrength.buff = Ability:Add(298154, true, true)
SuperiorBattlePotionOfStrength.buff.triggers_gcd = false
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
Trinket.MerekthasFang = InventoryItem:Add(158367)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	if UnitEffectiveLevel('player') < 110 then
		print('disabling azerite, player is effectively level', UnitEffectiveLevel('player'))
		return -- disable all Azerite/Essences for players scaled under 110
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								--print('Azerite found:', pinfo.azeritePowerID, GetSpellInfo(pinfo.spellID))
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Rage()
	return self.rage
end

function Player:RageDeficit()
	return self.rage_max - self.rage
end

function Player:UnderAttack()
	return (Player.time - self.last_swing_taken) < 3
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	self.rage_max = UnitPowerMax('player', 1)

	local _, ability

	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = false
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.spellId2 and C_LevelLink.IsSpellLocked(ability.spellId2)) then
			-- spell is locked, do not mark as known
		elseif IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) then
			ability.known = true
		elseif Azerite.traits[ability.spellId] then
			ability.known = true
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
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

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
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

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.healthArray, 1)
	self.healthArray[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
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
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.healthArray[i] = 0
		end
		self:UpdateHealth()
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
		local i
		for i = 1, 25 do
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		smashPanel:Show()
		return true
	end
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

function Rampage:Cost()
	local cost = Ability.Cost(self)
	if Carnage.known then
		cost = cost - 10
	end
	if FrothingBerserker.known then
		cost = cost + 10
	end
	return max(0, cost)
end

function Slam:Cost()
	local cost = Ability.Cost(self)
	if CrushingAssault.known and CrushingAssault:Up() then
		cost = cost - 20
	end
	return max(0, cost)
end

function Execute:Usable()
	if (not SuddenDeath.known or not SuddenDeath:Up()) and Target.healthPercentage >= (Massacre.known and 35 or 20) then
		return false
	end
	return Ability.Usable(self)
end

function ExecuteFury:Usable()
	if (not SuddenDeathFury.known or not SuddenDeathFury:Up()) and Target.healthPercentage >= (Massacre.known and 35 or 20) then
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
		_, _, stack, _, duration, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
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

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
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

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.ARMS] = {},
	[SPEC.FURY] = {},
	[SPEC.PROTECTION] = {},
}

APL[SPEC.ARMS].main = function(self)
	if Player:TimeInCombat() == 0 then
		if BattleShout:Usable() and BattleShout:Remains() < 300 then
			return BattleShout
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if Charge:Usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
		end
	end
	Player.lucid_active = MemoryOfLucidDreams.known and MemoryOfLucidDreams:Up()
--[[
actions=charge
actions+=/auto_attack
actions+=/potion,if=target.health.pct<21&buff.memory_of_lucid_dreams.up|!essence.memory_of_lucid_dreams.major
actions+=/blood_fury,if=buff.memory_of_lucid_dreams.remains<5|(!essence.memory_of_lucid_dreams.major&debuff.colossus_smash.up)
actions+=/berserking,if=buff.memory_of_lucid_dreams.up|(!essence.memory_of_lucid_dreams.major&debuff.colossus_smash.up)
actions+=/arcane_torrent,if=cooldown.mortal_strike.remains>1.5&buff.memory_of_lucid_dreams.down&rage<50
actions+=/lights_judgment,if=debuff.colossus_smash.down
actions+=/fireblood,if=buff.memory_of_lucid_dreams.remains<5|(!essence.memory_of_lucid_dreams.major&debuff.colossus_smash.up)
actions+=/ancestral_call,if=buff.memory_of_lucid_dreams.remains<5|(!essence.memory_of_lucid_dreams.major&debuff.colossus_smash.up)
actions+=/bag_of_tricks,if=buff.memory_of_lucid_dreams.remains<5|(!essence.memory_of_lucid_dreams.major&debuff.colossus_smash.up)
actions+=/use_item,name=ashvanes_razor_coral,if=!debuff.razor_coral_debuff.up|(target.health.pct<20.1&buff.memory_of_lucid_dreams.up&cooldown.memory_of_lucid_dreams.remains<117)|(target.health.pct<30.1&debuff.conductive_ink_debuff.up&!essence.memory_of_lucid_dreams.major)|(!debuff.conductive_ink_debuff.up&!essence.memory_of_lucid_dreams.major&debuff.colossus_smash.up)|target.time_to_die<30
actions+=/avatar,if=cooldown.colossus_smash.remains<8|(talent.warbreaker.enabled&cooldown.warbreaker.remains<8)
actions+=/sweeping_strikes,if=spell_targets.whirlwind>1&(cooldown.bladestorm.remains>10|cooldown.colossus_smash.remains>8|azerite.test_of_might.enabled)
actions+=/blood_of_the_enemy,if=buff.test_of_might.up|(debuff.colossus_smash.up&!azerite.test_of_might.enabled)
actions+=/purifying_blast,if=!debuff.colossus_smash.up&!buff.test_of_might.up
actions+=/ripple_in_space,if=!debuff.colossus_smash.up&!buff.test_of_might.up
actions+=/worldvein_resonance,if=!debuff.colossus_smash.up&!buff.test_of_might.up
actions+=/focused_azerite_beam,if=!debuff.colossus_smash.up&!buff.test_of_might.up
actions+=/reaping_flames,if=!debuff.colossus_smash.up&!buff.test_of_might.up
actions+=/concentrated_flame,if=!debuff.colossus_smash.up&!buff.test_of_might.up&dot.concentrated_flame_burn.remains=0
actions+=/the_unbound_force,if=buff.reckless_force.up
actions+=/guardian_of_azeroth,if=cooldown.colossus_smash.remains<10
actions+=/memory_of_lucid_dreams,if=!talent.warbreaker.enabled&cooldown.colossus_smash.remains<gcd&(target.time_to_die>150|target.health.pct<20)
actions+=/memory_of_lucid_dreams,if=talent.warbreaker.enabled&cooldown.warbreaker.remains<gcd&(target.time_to_die>150|target.health.pct<20)
actions+=/run_action_list,name=hac,if=raid_event.adds.exists
actions+=/run_action_list,name=five_target,if=spell_targets.whirlwind>4
actions+=/run_action_list,name=execute,if=(talent.massacre.enabled&target.health.pct<35)|target.health.pct<20
actions+=/run_action_list,name=single_target
]]
	if Trinket.MerekthasFang:Usable() and not Player.lucid_active and Player.enemies > 1 and SweepingStrikes:Down() and ColossusSmash:Down() and (not TestOfMight.known or TestOfMight:Down()) then
		UseCooldown(Trinket.MerekthasFang)
	end
	if Avatar:Usable() and (ColossusSmash.known and ColossusSmash:Ready(8) or Warbreaker.known and Warbreaker:Ready(8)) then
		UseCooldown(Avatar)
	end
	if SweepingStrikes:Ready() and Player.enemies > 1 and (not Bladestorm:Ready(10) or not ColossusSmash:Ready(8) or TestOfMight.known) then
		UseCooldown(SweepingStrikes)
	end
	if MemoryOfLucidDreams.known then
		if MemoryOfLucidDreams:Usable() and Target.timeToDie > 8 and (Target.timeToDie > 150 or Target.healthPercentage < 20 or (Massacre.known and Target.healthPercentage < 35 and Target.timeToDie < (TestOfMight.known and 24 or 12))) and (ColossusSmash.known and ColossusSmash:Ready(Player.gcd) or Warbreaker.known and Warbreaker:Ready(Player.gcd)) then
			UseCooldown(MemoryOfLucidDreams)
		end
	elseif BloodOfTheEnemy.known then
		if BloodOfTheEnemy:Usable() and ((not TestOfMight.known and ColossusSmash.debuff:Up()) or TestOfMight:Up()) then
			UseCooldown(BloodOfTheEnemy)
		end
	elseif TheUnboundForce.known then
		if TheUnboundForce:Usable() and RecklessForce:Up() then
			UseCooldown(TheUnboundForce)
		end
	elseif GuardianOfAzeroth.known then
		if GuardianOfAzeroth:Usable() and (ColossusSmash.known and ColossusSmash:Ready(10) or Warbreaker.known and Warbreaker:Ready(10)) then
			UseCooldown(GuardianOfAzeroth)
		end
	elseif ColossusSmash.debuff:Down() and TestOfMight:Down() then
		if PurifyingBlast:Usable() then
			UseCooldown(PurifyingBlast)
		elseif RippleInSpace:Usable() then
			UseCooldown(RippleInSpace)
		elseif WorldveinResonance:Usable() and Lifeblood:Stack() < 4 then
			UseCooldown(WorldveinResonance)
		elseif FocusedAzeriteBeam:Usable() then
			UseCooldown(FocusedAzeriteBeam)
		elseif ReapingFlames:Usable() then
			UseCooldown(ReapingFlames)
		elseif ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
			UseCooldown(ConcentratedFlame)
		end
	end
	if Player.enemies >= 5 then
		return self:five_target()
	end
--	if Player.enemies >= 3 then
--		return self:hac()
--	end
	if Target.healthPercentage < (Massacre.known and 35 or 20) then
		return self:execute()
	end
	return self:single_target()
end

APL[SPEC.ARMS].execute = function(self)
--[[
actions.execute=skullsplitter,if=rage<60&buff.deadly_calm.down&buff.memory_of_lucid_dreams.down
actions.execute+=/ravager,if=!buff.deadly_calm.up&(cooldown.colossus_smash.remains<2|(talent.warbreaker.enabled&cooldown.warbreaker.remains<2))
actions.execute+=/colossus_smash,if=!essence.memory_of_lucid_dreams.major|(buff.memory_of_lucid_dreams.up|cooldown.memory_of_lucid_dreams.remains>10)
actions.execute+=/warbreaker,if=!essence.memory_of_lucid_dreams.major|(buff.memory_of_lucid_dreams.up|cooldown.memory_of_lucid_dreams.remains>10)
actions.execute+=/deadly_calm
actions.execute+=/bladestorm,if=!buff.memory_of_lucid_dreams.up&buff.test_of_might.up&rage<30&!buff.deadly_calm.up
actions.execute+=/cleave,if=spell_targets.whirlwind>2
actions.execute+=/slam,if=buff.crushing_assault.up&buff.memory_of_lucid_dreams.down
actions.execute+=/mortal_strike,if=buff.overpower.stack=2&talent.dreadnaught.enabled|buff.executioners_precision.stack=2
actions.execute+=/execute,if=buff.memory_of_lucid_dreams.up|buff.deadly_calm.up|(buff.test_of_might.up&cooldown.memory_of_lucid_dreams.remains>94)
actions.execute+=/overpower
actions.execute+=/execute
]]
	if Skullsplitter:Usable() and Player.rage < 60 and DeadlyCalm:Down() and not Player.lucid_active then
		return Skullsplitter
	end
	if Ravager:Usable() and DeadlyCalm:Down() and (ColossusSmash.known and ColossusSmash:Ready(2) or Warbreaker.known and Warbreaker:Ready(2)) then
		UseCooldown(Ravager)
	end
	if ColossusSmash.debuff:Down() and (not MemoryOfLucidDreams.known or Player.lucid_active or MemoryOfLucidDreams:Cooldown() > 10) then
		if ColossusSmash:Usable() then
			return ColossusSmash
		end
		if Warbreaker:Usable() then
			return Warbreaker
		end
	end
	if DeadlyCalm:Usable() then
		UseCooldown(DeadlyCalm)
	end
	if Bladestorm:Usable() and Player.rage < 30 and not Player.lucid_active and TestOfMight:Up() and ColossusSmash:Down() and DeadlyCalm:Down() then
		UseCooldown(Bladestorm)
	end
	if Cleave:Usable() and Player.enemies > 2 then
		return Cleave
	end
	if CrushingAssault.known and Slam:Usable() and CrushingAssault:Up() and not Player.lucid_active then
		return Slam
	end
	if MortalStrike:Usable() and (Dreadnaught.known and Overpower:Stack() == 2 or ExecutionersPrecision.known and ExecutionersPrecision:Stack() == 2) then
		return MortalStrike
	end
	if Execute:Usable() and (Player.lucid_active or DeadlyCalm:Up() or (TestOfMight:Up() and MemoryOfLucidDreams:Cooldown() > 94)) then
		return Execute
	end
	if Overpower:Usable() then
		return Overpower
	end
	if Execute:Usable() then
		return Execute
	end
end

APL[SPEC.ARMS].five_target = function(self)
--[[
actions.five_target=skullsplitter,if=rage<60&(!talent.deadly_calm.enabled|buff.deadly_calm.down)
actions.five_target+=/ravager,if=(!talent.warbreaker.enabled|cooldown.warbreaker.remains<2)
actions.five_target+=/colossus_smash,if=debuff.colossus_smash.down
actions.five_target+=/warbreaker,if=debuff.colossus_smash.down
actions.five_target+=/bladestorm,if=buff.sweeping_strikes.down&(!talent.deadly_calm.enabled|buff.deadly_calm.down)&((debuff.colossus_smash.remains>4.5&!azerite.test_of_might.enabled)|buff.test_of_might.up)
actions.five_target+=/deadly_calm
actions.five_target+=/cleave
actions.five_target+=/execute,if=(!talent.cleave.enabled&dot.deep_wounds.remains<2)|(buff.sudden_death.react|buff.stone_heart.react)&(buff.sweeping_strikes.up|cooldown.sweeping_strikes.remains>8)
actions.five_target+=/mortal_strike,if=(!talent.cleave.enabled&dot.deep_wounds.remains<2)|buff.sweeping_strikes.up&buff.overpower.stack=2&(talent.dreadnaught.enabled|buff.executioners_precision.stack=2)
actions.five_target+=/whirlwind,if=debuff.colossus_smash.up|(buff.crushing_assault.up&talent.fervor_of_battle.enabled)
actions.five_target+=/whirlwind,if=buff.deadly_calm.up|rage>60
actions.five_target+=/overpower
actions.five_target+=/whirlwind
]]
	if Skullsplitter:Usable() and Player.rage < 60 and (not DeadlyCalm.known or DeadlyCalm:Down()) then
		return Skullsplitter
	end
	if Ravager:Usable() and (not Warbreaker.known or Warbreaker:Ready(2)) then
		UseCooldown(Ravager)
	end
	if ColossusSmash:Usable() and ColossusSmash.debuff:Down() then
		return ColossusSmash
	end
	if Warbreaker:Usable() and ColossusSmash.debuff:Down() then
		return Warbreaker
	end
	if Bladestorm:Usable() and SweepingStrikes:Down() and (not DeadlyCalm.known or DeadlyCalm:Down()) and ((not TestOfMight.known and ColossusSmash.debuff:Remains() > 4.5) or TestOfMight:Up()) then
		UseCooldown(Bladestorm)
	end
	if DeadlyCalm:Usable() then
		UseCooldown(DeadlyCalm)
	end
	if Cleave:Usable() then
		return Cleave
	end
	if Execute:Usable() and ((not Cleave.known and DeepWounds:Remains() < 2) or SuddenDeath:Up() and (SweepingStrikes:Up() or not SweepingStrikes:Ready(8))) then
		return Execute
	end
	if MortalStrike:Usable() and ((not Cleave.known and DeepWounds:Remains() < 2) or SweepingStrikes:Up() and Overpower:Stack() == 2 and (Dreadnaught.known or ExecutionersPrecision:Stack() == 2)) then
		return MortalStrike
	end
	if Whirlwind:Usable() then
		if ColossusSmash.debuff:Up() or (CrushingAssault.known and FervorOfBattle.known and CrushingAssault:Up()) then
			return Whirlwind
		end
		if DeadlyCalm:Up() or Player.rage > 60 then
			return Whirlwind
		end
	end
	if Overpower:Usable() then
		return Overpower
	end
	if Whirlwind:Usable() then
		return Whirlwind
	end
end

APL[SPEC.ARMS].hac = function(self)
--[[
actions.hac=rend,if=remains<=duration*0.3&(!raid_event.adds.up|buff.sweeping_strikes.up)
actions.hac+=/skullsplitter,if=rage<60&(cooldown.deadly_calm.remains>3|!talent.deadly_calm.enabled)
actions.hac+=/deadly_calm,if=(cooldown.bladestorm.remains>6|talent.ravager.enabled&cooldown.ravager.remains>6)&(cooldown.colossus_smash.remains<2|(talent.warbreaker.enabled&cooldown.warbreaker.remains<2))
actions.hac+=/ravager,if=(raid_event.adds.up|raid_event.adds.in>target.time_to_die)&(cooldown.colossus_smash.remains<2|(talent.warbreaker.enabled&cooldown.warbreaker.remains<2))
actions.hac+=/colossus_smash,if=raid_event.adds.up|raid_event.adds.in>40|(raid_event.adds.in>20&talent.anger_management.enabled)
actions.hac+=/warbreaker,if=raid_event.adds.up|raid_event.adds.in>40|(raid_event.adds.in>20&talent.anger_management.enabled)
actions.hac+=/bladestorm,if=(debuff.colossus_smash.up&raid_event.adds.in>target.time_to_die)|raid_event.adds.up&((debuff.colossus_smash.remains>4.5&!azerite.test_of_might.enabled)|buff.test_of_might.up)
actions.hac+=/overpower,if=!raid_event.adds.up|(raid_event.adds.up&azerite.seismic_wave.enabled)
actions.hac+=/cleave,if=spell_targets.whirlwind>2
actions.hac+=/execute,if=!raid_event.adds.up|(!talent.cleave.enabled&dot.deep_wounds.remains<2)|buff.sudden_death.react
actions.hac+=/mortal_strike,if=!raid_event.adds.up|(!talent.cleave.enabled&dot.deep_wounds.remains<2)
actions.hac+=/whirlwind,if=raid_event.adds.up
actions.hac+=/overpower
actions.hac+=/whirlwind,if=talent.fervor_of_battle.enabled
actions.hac+=/slam,if=!talent.fervor_of_battle.enabled&!raid_event.adds.up
]]

end

APL[SPEC.ARMS].single_target = function(self)
--[[
actions.single_target=rend,if=!remains&debuff.colossus_smash.down
actions.single_target+=/skullsplitter,if=rage<60&buff.deadly_calm.down&buff.memory_of_lucid_dreams.down
actions.single_target+=/ravager,if=!buff.deadly_calm.up&(cooldown.colossus_smash.remains<2|(talent.warbreaker.enabled&cooldown.warbreaker.remains<2))
actions.single_target+=/colossus_smash
actions.single_target+=/warbreaker
actions.single_target+=/deadly_calm
actions.single_target+=/execute,if=buff.sudden_death.react
actions.single_target+=/rend,if=refreshable&cooldown.colossus_smash.remains<5
actions.single_target+=/bladestorm,if=cooldown.mortal_strike.remains&(!talent.deadly_calm.enabled|buff.deadly_calm.down)&((debuff.colossus_smash.up&!azerite.test_of_might.enabled)|buff.test_of_might.up)&buff.memory_of_lucid_dreams.down&rage<40
actions.single_target+=/cleave,if=spell_targets.whirlwind>2
actions.single_target+=/overpower,if=(rage<30&buff.memory_of_lucid_dreams.up&debuff.colossus_smash.up)|(rage<70&buff.memory_of_lucid_dreams.down)
actions.single_target+=/mortal_strike
actions.single_target+=/whirlwind,if=talent.fervor_of_battle.enabled&(buff.memory_of_lucid_dreams.up|debuff.colossus_smash.up|buff.deadly_calm.up)
actions.single_target+=/overpower
actions.single_target+=/rend,target_if=min:remains,if=refreshable&debuff.colossus_smash.down
actions.single_target+=/whirlwind,if=talent.fervor_of_battle.enabled&(buff.test_of_might.up|debuff.colossus_smash.down&buff.test_of_might.down&rage>60)
actions.single_target+=/slam,if=!talent.fervor_of_battle.enabled
]]
	if Rend:Usable() and Rend:Down() and ColossusSmash.debuff:Down() then
		return Rend
	end
	if Skullsplitter:Usable() and Player.rage < 60 and DeadlyCalm:Down() and not Player.lucid_active then
		return Skullsplitter
	end
	if Ravager:Usable() and not DeadlyCalm:Up() and (ColossusSmash.known and ColossusSmash:Ready(2) or Warbreaker.known and Warbreaker:Ready(2)) then
		UseCooldown(Ravager)
	end
	if ColossusSmash:Usable() then
		return ColossusSmash
	end
	if Warbreaker:Usable() then
		return Warbreaker
	end
	if DeadlyCalm:Usable() then
		UseCooldown(DeadlyCalm)
	end
	if SuddenDeath.known and Execute:Usable() and SuddenDeath:Up() then
		return Execute
	end
	if Rend:Usable() and Rend:Refreshable() and ColossusSmash:Cooldown() < 5 then
		return Rend
	end
	if Bladestorm:Usable() and Player.rage < 40 and not MortalStrike:Ready() and (not DeadlyCalm.known or DeadlyCalm:Down()) and ((not TestOfMight.known and ColossusSmash.debuff:Up()) or TestOfMight:Up()) and not Player.lucid_active then
		UseCooldown(Bladestorm)
	end
	if Cleave:Usable() and Player.enemies > 2 then
		return Cleave
	end
	if Overpower:Usable() and ((Player.rage < 30 and Player.lucid_active and ColossusSmash.debuff:Up()) or (Player.rage < 70 and not Player.lucid_active)) then
		return Overpower
	end
	if MortalStrike:Usable() then
		return MortalStrike
	end
	if FervorOfBattle.known and Whirlwind:Usable() and (Player.lucid_active or ColossusSmash.debuff:Up() or DeadlyCalm:Up()) then
		return Whirlwind
	end
	if Overpower:Usable() then
		return Overpower
	end
	if Rend:Usable() and Rend:Refreshable() and ColossusSmash.debuff:Down() then
		return Rend
	end
	if MortalStrike:Ready(0.5) then
		return MortalStrike
	end
	if FervorOfBattle.known then
		if Whirlwind:Usable() and (TestOfMight:Up() or Player.rage > 60 and ColossusSmash.debuff:Down()) then
			return Whirlwind
		end
	else
		if Slam:Usable() and (Player.rage >= 50 or not MortalStrike:Ready(0.5)) then
			return Slam
		end
	end
	if Victorious:Up() and (Player.rage < 20 or not MortalStrike:Ready(1)) then
		if VictoryRush:Usable() then
			return VictoryRush
		end
		if ImpendingVictory:Usable() then
			return ImpendingVictory
		end
	end
end

APL[SPEC.FURY].main = function(self)
	if Player:TimeInCombat() == 0 then
		if BattleShout:Usable() and BattleShout:Remains() < 300 then
			return BattleShout
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
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
actions+=/charge
actions+=/heroic_leap,if=(raid_event.movement.distance>25&raid_event.movement.in>45)
actions+=/potion,if=buff.guardian_of_azeroth.up|(!essence.condensed_lifeforce.major&target.time_to_die=60)
actions+=/rampage,if=cooldown.recklessness.remains<3&(spell_targets.whirlwind<2|buff.meat_cleaver.up)
actions+=/blood_of_the_enemy,if=buff.recklessness.up
actions+=/purifying_blast,if=!buff.recklessness.up&!buff.siegebreaker.up
actions+=/ripple_in_space,if=!buff.recklessness.up&!buff.siegebreaker.up
actions+=/worldvein_resonance,if=!buff.recklessness.up&!buff.siegebreaker.up
actions+=/focused_azerite_beam,if=!buff.recklessness.up&!buff.siegebreaker.up
actions+=/reaping_flames,if=!buff.recklessness.up&!buff.siegebreaker.up
actions+=/concentrated_flame,if=!buff.recklessness.up&!buff.siegebreaker.up&dot.concentrated_flame_burn.remains=0
actions+=/the_unbound_force,if=buff.reckless_force.up
actions+=/guardian_of_azeroth,if=!buff.recklessness.up&(target.time_to_die>195|target.health.pct<20)
actions+=/memory_of_lucid_dreams,if=!buff.recklessness.up
actions+=/recklessness,if=!essence.condensed_lifeforce.major&!essence.blood_of_the_enemy.major|cooldown.guardian_of_azeroth.remains>1|buff.guardian_of_azeroth.up|cooldown.blood_of_the_enemy.remains<gcd
actions+=/whirlwind,if=spell_targets.whirlwind>1&!buff.meat_cleaver.up
actions+=/use_item,name=ashvanes_razor_coral,if=target.time_to_die<20|!debuff.razor_coral_debuff.up|(target.health.pct<30.1&debuff.conductive_ink_debuff.up)|(!debuff.conductive_ink_debuff.up&buff.memory_of_lucid_dreams.up|prev_gcd.2.guardian_of_azeroth|prev_gcd.2.recklessness&(!essence.memory_of_lucid_dreams.major&!essence.condensed_lifeforce.major))
actions+=/blood_fury,if=buff.recklessness.up
actions+=/berserking,if=buff.recklessness.up
actions+=/lights_judgment,if=buff.recklessness.down&debuff.siegebreaker.down
actions+=/fireblood,if=buff.recklessness.up
actions+=/ancestral_call,if=buff.recklessness.up
actions+=/bag_of_tricks,if=buff.recklessness.down&debuff.siegebreaker.down&buff.enrage.up
actions+=/run_action_list,name=single_target
]]
	if Rampage:Usable() and Recklessness:Ready(3) and (Player.enemies == 1 or WhirlwindFury.buff:Up()) then
		return Rampage
	end
	if BloodOfTheEnemy.known then
		if BloodOfTheEnemy:Usable() and Recklessness:Up() then
			UseCooldown(BloodOfTheEnemy)
		end
	elseif TheUnboundForce.known then
		if TheUnboundForce:Usable() and RecklessForce:Up() then
			UseCooldown(TheUnboundForce)
		end
	elseif GuardianOfAzeroth.known then
		if GuardianOfAzeroth:Usable() and Recklessness:Down() and (Target.timeToDie > 195 or Target.healthPercentage < 20) then
			UseCooldown(GuardianOfAzeroth)
		end
	elseif MemoryOfLucidDreams.known then
		if MemoryOfLucidDreams:Usable() and Recklessness:Down() then
			UseCooldown(MemoryOfLucidDreams)
		end
	elseif Recklessness:Down() and Siegebreaker:Down() then
		if PurifyingBlast:Usable() then
			UseCooldown(PurifyingBlast)
		elseif RippleInSpace:Usable() then
			UseCooldown(RippleInSpace)
		elseif WorldveinResonance:Usable() and Lifeblood:Stack() < 4 then
			UseCooldown(WorldveinResonance)
		elseif FocusedAzeriteBeam:Usable() then
			UseCooldown(FocusedAzeriteBeam)
		elseif ReapingFlames:Usable() then
			UseCooldown(ReapingFlames)
		elseif ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
			UseCooldown(ConcentratedFlame)
		end
	end
	if Recklessness:Usable() and (not GuardianOfAzeroth.known and not BloodOfTheEnemy.known or (GuardianOfAzeroth.known and (GuardianOfAzeroth:Cooldown() > 1 or GuardianOfAzeroth:Up()) or (BloodOfTheEnemy.known and BloodOfTheEnemy:Ready(Player.gcd)))) then
		UseCooldown(Recklessness)
	end
	if Player.enemies > 1 and WhirlwindFury:Usable() and WhirlwindFury.buff:Down() then
		return WhirlwindFury
	end
	return self:single_target()
end

APL[SPEC.FURY].single_target = function(self)
--[[
actions.single_target=siegebreaker
actions.single_target+=/rampage,if=(buff.recklessness.up|buff.memory_of_lucid_dreams.up)|(talent.frothing_berserker.enabled|talent.carnage.enabled&(buff.enrage.remains<gcd|rage>90)|talent.massacre.enabled&(buff.enrage.remains<gcd|rage>90))
actions.single_target+=/execute
actions.single_target+=/furious_slash,if=!buff.bloodlust.up&buff.furious_slash.remains<3
actions.single_target+=/bladestorm,if=prev_gcd.1.rampage
actions.single_target+=/bloodthirst,if=buff.enrage.down|azerite.cold_steel_hot_blood.rank>1
actions.single_target+=/dragon_roar,if=buff.enrage.up
actions.single_target+=/raging_blow,if=charges=2
actions.single_target+=/bloodthirst
actions.single_target+=/raging_blow,if=talent.carnage.enabled|(talent.massacre.enabled&rage<80)|(talent.frothing_berserker.enabled&rage<90)
actions.single_target+=/furious_slash,if=talent.furious_slash.enabled
actions.single_target+=/whirlwind
]]
	if Siegebreaker:Usable() then
		return Siegebreaker
	end
	if Rampage:Usable() and ((Recklessness:Up() or MemoryOfLucidDreams:Up()) or (FrothingBerserker.known or (Carnage.known or Massacre.known) and (Enrage:Remains() < Player.gcd or Player:Rage() > 90))) then
		return Rampage
	end
	if ExecuteFury:Usable() then
		return ExecuteFury
	end
	if FuriousSlash:Usable() and not Player:BloodlustActive() and FuriousSlash:Remains() < 3 then
		return FuriousSlash
	end
	if BladestormFury:Usable() and Rampage:Previous() then
		UseCooldown(BladestormFury)
	end
	if Bloodthirst:Usable() and (ColdSteelHotBlood:AzeriteRank() > 1 or Enrage:Down()) then
		return Bloodthirst
	end
	if DragonRoar:Usable() and Enrage:Up() then
		return DragonRoar
	end
	if RagingBlow:Usable() and RagingBlow:Charges() >= 2 then
		return RagingBlow
	end
	if Bloodthirst:Usable() then
		return Bloodthirst
	end
	if RagingBlow:Usable() and (Carnage.known or (Massacre.known and Player:Rage() < 80) or (FrothingBerserker.known and Player:Rage() < 90)) then
		return RagingBlow
	end
	if FuriousSlash:Usable() then
		return FuriousSlash
	end
	if WhirlwindFury:Usable() then
		return WhirlwindFury
	end
end

APL[SPEC.PROTECTION].main = function(self)
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/food
actions.precombat+=/augmentation
# Snapshot raid buffed stats before combat begins and pre-potting is done.
actions.precombat+=/snapshot_stats
actions.precombat+=/use_item,name=azsharas_font_of_power
actions.precombat+=/worldvein_resonance
actions.precombat+=/memory_of_lucid_dreams
actions.precombat+=/guardian_of_azeroth
actions.precombat+=/potion
]]
		if BattleShout:Usable() and BattleShout:Remains() < 300 then
			return BattleShout
		end
		if WorldveinResonance:Usable() then
			UseCooldown(WorldveinResonance)
		elseif MemoryOfLucidDreams:Usable() then
			UseCooldown(MemoryOfLucidDreams)
		elseif GuardianOfAzeroth:Usable() then
			UseCooldown(GuardianOfAzeroth)
		elseif Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheUndertow:Usable() and GreaterFlaskOfTheUndertow.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if Target.boss and SuperiorBattlePotionOfStrength:Usable() then
				UseCooldown(SuperiorBattlePotionOfStrength)
			end
		end
		if Intercept:Usable() then
			UseExtra(Intercept)
		end
	else
		if BattleShout:Usable() and BattleShout:Remains() < 30 then
			UseCooldown(BattleShout)
		end
	end
--[[
actions=auto_attack
actions+=/intercept,if=time=0
actions+=/use_items,if=cooldown.avatar.remains<=gcd|buff.avatar.up
actions+=/blood_fury
actions+=/berserking
actions+=/arcane_torrent
actions+=/lights_judgment
actions+=/fireblood
actions+=/ancestral_call
actions+=/bag_of_tricks
actions+=/potion,if=buff.avatar.up|target.time_to_die<25
# use Ignore Pain to avoid rage capping
actions+=/ignore_pain,if=rage.deficit<25+20*talent.booming_voice.enabled*cooldown.demoralizing_shout.ready
actions+=/worldvein_resonance,if=cooldown.avatar.remains<=2
actions+=/ripple_in_space
actions+=/memory_of_lucid_dreams
actions+=/concentrated_flame,if=buff.avatar.down&!dot.concentrated_flame_burn.remains>0|essence.the_crucible_of_flame.rank<3
actions+=/last_stand,if=cooldown.anima_of_death.remains<=2
actions+=/avatar
actions+=/run_action_list,name=aoe,if=spell_targets.thunder_clap>=3
actions+=/call_action_list,name=st
]]
	if Opt.trinket and (Avatar:Ready(Player.gcd) or Avatar:Up()) then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
	if Opt.pot and Opt.boss and not Player:InArenaOrBattleground() and SuperiorBattlePotionOfStrength:Usable() and (Avatar:Up() or Target.timeToDie < 25) then
		UseCooldown(SuperiorBattlePotionOfStrength)
	end
	if IgnorePain:Usable() and Player:RageDeficit() < (25 + (BoomingVoice.known and DemoralizingShout:Ready() and 20 or 0)) and (IgnorePain:Down() or ShieldBlock:Up()) then
		UseExtra(IgnorePain)
	end
	if WorldveinResonance:Usable() and Avatar:Ready(2) then
		UseCooldown(WorldveinResonance)
	elseif RippleInSpace:Usable() then
		UseCooldown(RippleInSpace)
	elseif MemoryOfLucidDreams:Usable() then
		UseCooldown(MemoryOfLucidDreams)
	elseif ConcentratedFlame:Usable() and Avatar:Down() and ConcentratedFlame.dot:Down() then
		UseCooldown(ConcentratedFlame)
	elseif AnimaOfDeath.known and AnimaOfDeath:Ready(2) and LastStand:Usable() then
		UseCooldown(LastStand)
	elseif Avatar:Usable() then
		UseCooldown(Avatar)
	end
	if Player.enemies >= 3 then
		return self:aoe()
	end
	return self:st()
end

APL[SPEC.PROTECTION].aoe = function(self)
--[[
actions.aoe=thunder_clap
actions.aoe+=/memory_of_lucid_dreams,if=buff.avatar.down
actions.aoe+=/demoralizing_shout,if=talent.booming_voice.enabled
actions.aoe+=/anima_of_death,if=buff.last_stand.up
actions.aoe+=/dragon_roar
actions.aoe+=/revenge
actions.aoe+=/use_item,name=grongs_primal_rage,if=buff.avatar.down|cooldown.thunder_clap.remains>=4
actions.aoe+=/ravager
actions.aoe+=/shield_block,if=cooldown.shield_slam.ready&buff.shield_block.down
actions.aoe+=/shield_slam
]]
	if ThunderClap:Usable() then
		return ThunderClap
	end
	if MemoryOfLucidDreams:Usable() and Avatar:Down() then
		UseCooldown(MemoryOfLucidDreams)
	elseif BoomingVoice.known and DemoralizingShout:Usable() then
		UseCooldown(DemoralizingShout)
	elseif AnimaOfDeath:Usable() and LastStand:Up() then
		UseCooldown(AnimaOfDeath)
	end
	if DragonRoar:Usable() then
		return DragonRoar
	end
	if Revenge:Usable() and (Revenge.free:Up() or Player:Rage() >= 60 or (IgnorePain:Up() and (ShieldBlock:Up() or not ShieldBlock:Ready()))) then
		return Revenge
	end
	if Ravager:Usable() then
		UseCooldown(Ravager)
	end
	if ShieldBlock:Usable() and ShieldSlam:Ready(0.5) and ShieldBlock:Down() then
		UseExtra(ShieldBlock)
	end
	if ShieldSlam:Usable() then
		return ShieldSlam
	end
	if Victorious:Up() then
		if VictoryRush:Usable() then
			return VictoryRush
		end
		if ImpendingVictory:Usable() then
			return ImpendingVictory
		end
	end
	if ImpendingVictory:Usable() and Player:Rage() >= 40 and Player:HealthPct() < 80 then
		return ImpendingVictory
	end
end

APL[SPEC.PROTECTION].st = function(self)
--[[
actions.st=thunder_clap,if=spell_targets.thunder_clap=2&talent.unstoppable_force.enabled&buff.avatar.up
actions.st+=/shield_block,if=cooldown.shield_slam.ready&buff.shield_block.down
actions.st+=/shield_slam,if=buff.shield_block.up
actions.st+=/thunder_clap,if=(talent.unstoppable_force.enabled&buff.avatar.up)
actions.st+=/demoralizing_shout,if=talent.booming_voice.enabled
actions.st+=/anima_of_death,if=buff.last_stand.up
actions.st+=/shield_slam
actions.st+=/use_item,name=ashvanes_razor_coral,target_if=debuff.razor_coral_debuff.stack=0
actions.st+=/use_item,name=ashvanes_razor_coral,if=debuff.razor_coral_debuff.stack>7&(cooldown.avatar.remains<5|buff.avatar.up)
actions.st+=/dragon_roar
actions.st+=/thunder_clap
actions.st+=/revenge
actions.st+=/use_item,name=grongs_primal_rage,if=buff.avatar.down|cooldown.shield_slam.remains>=4
actions.st+=/ravager
actions.st+=/devastate
]]
	if UnstoppableForce.known and Player.enemies == 2 and ThunderClap:Usable() and Avatar:Up() then
		return ThunderClap
	end
	if ShieldBlock:Usable() and ShieldSlam:Ready(0.5) and ShieldBlock:Down() then
		UseExtra(ShieldBlock)
	end
	if ShieldSlam:Usable() and ShieldBlock:Up() then
		return ShieldSlam
	end
	if UnstoppableForce.known and ThunderClap:Usable() and Avatar:Up() then
		return ThunderClap
	end
	if BoomingVoice.known and DemoralizingShout:Usable() then
		UseCooldown(DemoralizingShout)
	elseif AnimaOfDeath:Usable() and LastStand:Up() then
		UseCooldown(AnimaOfDeath)
	end
	if ShieldSlam:Usable() then
		return ShieldSlam
	end
	if DragonRoar:Usable() then
		return DragonRoar
	end
	if ThunderClap:Usable() then
		return ThunderClap
	end
	if Revenge:Usable() and (Revenge.free:Up() or Player:Rage() >= 60 or (IgnorePain:Up() and (ShieldBlock:Up() or not ShieldBlock:Ready()))) then
		return Revenge
	end
	if Ravager:Usable() then
		UseCooldown(Ravager)
	end
	if Victorious:Up() then
		if VictoryRush:Usable() then
			return VictoryRush
		end
		if ImpendingVictory:Usable() then
			return ImpendingVictory
		end
	end
	if ImpendingVictory:Usable() and Player:Rage() >= 40 and Player:HealthPct() < 80 then
		return ImpendingVictory
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

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
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

function UI:CreateOverlayGlows()
	local b, i
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
	local glow, icon, i
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
	smashPanel:EnableMouse(Opt.aoe or not Opt.locked)
	smashPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		smashPanel:SetScript('OnDragStart', nil)
		smashPanel:SetScript('OnDragStop', nil)
		smashPanel:RegisterForDrag(nil)
		smashPreviousPanel:EnableMouse(false)
		smashCooldownPanel:EnableMouse(false)
		smashInterruptPanel:EnableMouse(false)
		smashExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			smashPanel:SetScript('OnDragStart', smashPanel.StartMoving)
			smashPanel:SetScript('OnDragStop', smashPanel.StopMovingOrSizing)
			smashPanel:RegisterForDrag('LeftButton')
		end
		smashPreviousPanel:EnableMouse(true)
		smashCooldownPanel:EnableMouse(true)
		smashInterruptPanel:EnableMouse(true)
		smashExtraPanel:EnableMouse(true)
	end
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
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.ARMS] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 30 },
			['below'] = { 'TOP', 'BOTTOM', 0, -4 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		smashPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap then
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
	local dim, text_tl, text_tr
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Opt.swing_timer then
		if Player.main and Player.main:Cost() <= Player.rage then
		else
			local next_swing
			if Player.equipped_oh then
				next_swing = min(Player.next_swing_mh, Player.next_swing_oh)
			else
				next_swing = Player.next_swing_mh
			end
			text_tr = format('%.1f', max(0, next_swing - Player.time))
		end
	end
	smashPanel.dimmer:SetShown(dim)
	smashPanel.text.tl:SetText(text_tl)
	smashPanel.text.tr:SetText(text_tr)
	--smashPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.rage = UnitPower('player', 1)
	Player.moving = GetUnitSpeed('player') ~= 0

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		smashPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		smashCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		smashExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			smashInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			smashInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		smashInterruptPanel.icon:SetShown(Player.interrupt)
		smashInterruptPanel.border:SetShown(Player.interrupt)
		smashInterruptPanel:SetShown(start and not notInterruptible)
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
	if name == 'Smash' then
		Opt = Smash
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Smash1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if dstGUID == Player.guid then
			Player.last_swing_taken = Player.time
		end
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:Add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:Add(dstGUID, true)
			end
		end
		if Opt.swing_timer and srcGUID == Player.guid then
			local mh, oh = UnitAttackSpeed('player')
			if offHand and oh then
				Player.next_swing_oh = timeStamp + oh
			else
				Player.next_swing_mh = timeStamp + mh
			end
			if eventType == 'SWING_MISSED' then
				smashPanel.text.tr:SetTextColor(1, 0, 0, 1)
			else
				smashPanel.text.tr:SetTextColor(1, 1, 1, 1)
			end
		end
	end

	if srcGUID ~= Player.guid then
		return
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_APPLIED_DOSE' or
	   eventType == 'SPELL_AURA_REMOVED_DOSE' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
			end
			if Opt.previous and smashPanel:IsVisible() then
				smashPreviousPanel.ability = ability
				smashPreviousPanel.border:SetTexture('Interface\\AddOns\\Smash\\border.blp')
				smashPreviousPanel.icon:SetTexture(ability.icon)
				smashPreviousPanel:Show()
			end
			if Opt.auto_aoe then
				if ability == SweepingStrikes and Player.target_mode < 2 then
					Player:SetTargetMode(2)
				end
			end
			if Player.spec == SPEC.FURY then
				if ability == WhirlwindFury then
					WhirlwindFury.buff.pending_stack_use = false
				elseif (
					ability == Bloodthirst or ability == ExecuteFury or
					ability == VictoryRush or ability == ImpendingVictory or
					ability == RagingBlow or ability == FuriousSlash or
					ability == Siegebreaker
				) then
					WhirlwindFury.buff.pending_stack_use = true
				end
			end
		end
		return
	end

	if dstGUID == Player.guid then
		if ability == WhirlwindFury.buff and (eventType == 'SPELL_AURA_REMOVED' or eventType == 'SPELL_AURA_REMOVED_DOSE') then
			ability.pending_stack_use = false
		end
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and smashPanel:IsVisible() and ability == smashPreviousPanel.ability then
			smashPreviousPanel.border:SetTexture('Interface\\AddOns\\Smash\\misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.last_swing_taken = 0
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		smashPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
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
	local _, i, equipType, hasCooldown
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
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	smashPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
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

function events:UNIT_POWER_UPDATE(srcName, powerType)
	if srcName == 'player' and powerType == 'COMBO_POINTS' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
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
local event
for event in next, events do
	smashPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
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
	print('Smash -', desc .. ':', opt_view, ...)
end

function SlashCmdList.Smash(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				smashPanel:ClearAllPoints()
			end
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
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
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
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
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
		return Status('Show the Smash UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Smash for cooldown management', Opt.cooldown)
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
	if startsWith(msg[1], 'sw') then
		if msg[2] then
			Opt.swing = msg[2] == 'on'
		end
		return Status('Show time remaining until next swing when rage starved (topright)', Opt.swing)
	end
	if msg[1] == 'reset' then
		smashPanel:ClearAllPoints()
		smashPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Smash (version: |cFFFFD000' .. GetAddOnMetadata('Smash', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Smash UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Smash UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Smash UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Smash UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Smash UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Smash for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000arms|r/|cFFFFD000fury|r/|cFFFFD000protection|r - toggle disabling Smash for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'swing |cFF00C000on|r/|cFFC00000off|r - show time remaining until next swing when rage starved',
		'|cFFFFD000reset|r - reset the location of the Smash UI to default',
	} do
		print('  ' .. SLASH_Smash1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
