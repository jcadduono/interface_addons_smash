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
BINDING_HEADER_AUTOMAGICALLY = 'Smash'

local function InitializeOpts()
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

-- specialization constants
local SPEC = {
	NONE = 0,
	ARMS = 1,
	FURY = 2,
	PROTECTION = 3,
}

local events, glows = {}, {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	rage = 0,
	rage_max = 100,
	equipped_mh = false,
	equipped_oh = false,
	next_swing_mh = 0,
	next_swing_oh = 0
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[165581] = true, -- Crest of Pa'ku (Horde)
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
smashPanel.text.tl:SetPoint('TOPLEFT', smashPanel, 'TOPLEFT', 3, -3)
smashPanel.text.tr = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.tr:SetPoint('TOPRIGHT', smashPanel, 'TOPRIGHT', -1.5, -3)
smashPanel.text.br = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.br:SetPoint('BOTTOMRIGHT', smashPanel, 'BOTTOMRIGHT', -1.5, 3)
smashPanel.text.bl = smashPanel.text:CreateFontString(nil, 'OVERLAY')
smashPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashPanel.text.bl:SetPoint('BOTTOMLEFT', smashPanel, 'BOTTOMLEFT', -3, 3)
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

-- Start Auto AoE

local targetModes = {
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

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[Player.spec])
	Player.enemies = targetModes[Player.spec][targetMode][1]
	smashPanel.text.br:SetText(targetModes[Player.spec][targetMode][2])
end
Smash_SetTargetMode = SetTargetMode

local function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[Player.spec] and 1 or mode)
end
Smash_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[Player.spec] or mode)
end
Smash_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:add(guid, update)
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
		self:update()
	end
end

function autoAoe:remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #targetModes[Player.spec], 1, -1 do
		if count >= targetModes[Player.spec][i][1] then
			SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:purge()
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
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
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
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable()
	if not self.known then
		return false
	end
	if self:cost() > Player.rage then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	return self:remains() > 0
end

function Ability:down()
	return not self:up()
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:tickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.rage_cost
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return Player.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe(removeUnaffected, trigger)
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

function Ability:recordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:updateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local duration = self:duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Warrior Abilities
---- Multiple Specializations
local BerserkerRage = Ability.add(18499, true, true)
BerserkerRage.buff_duration = 6
BerserkerRage.cooldown_duration = 60
local Charge = Ability.add(100, false, true)
Charge.cooldown_duration = 20
Charge.rage_cost = -20
Charge.requires_charge = true
local HeroicLeap = Ability.add(6544, false, true)
HeroicLeap.cooldown_duration = 45
HeroicLeap.requires_charge = true
local HeroicThrow = Ability.add(57755, false, true)
HeroicThrow.cooldown_duration = 6
local Pummel = Ability.add(6552, false, true)
Pummel.buff_duration = 4
Pummel.cooldown_duration = 15
Pummel.triggers_gcd = false
local BattleShout = Ability.add(6673, true, false)
BattleShout.buff_duration = 3600
BattleShout.cooldown_duration = 15
local Taunt = Ability.add(355, false, true)
Taunt.buff_duration = 3
Taunt.cooldown_duration = 8
Taunt.triggers_gcd = false
------ Procs

------ Talents

---- Arms
local Avatar = Ability.add(107574, true, true)
Avatar.rage_cost = -20
Avatar.buff_duration = 20
Avatar.cooldown_duration = 90
local Bladestorm = Ability.add(46924, true, true)
Bladestorm.buff_duration = 4
Bladestorm.cooldown_duration = 60
Bladestorm:setAutoAoe(true)
local ColossusSmash = Ability.add(167105, false, true, 208086)
ColossusSmash.cooldown_duration = 45
ColossusSmash.buff_duration = 10
local DeepWounds = Ability.add(115767, false, true)
DeepWounds.buff_duration = 15
local DieByTheSword = Ability.add(118038, true, true)
DieByTheSword.buff_duration = 8
DieByTheSword.cooldown_duration = 180
local Execute = Ability.add(163201, false, true)
Execute.rage_cost = 20
local MortalStrike = Ability.add(12294, false, true)
MortalStrike.rage_cost = 30
MortalStrike.cooldown_duration = 6
MortalStrike.hasted_cooldown = true
local Overpower = Ability.add(7384, true, true, 60503)
Overpower.buff_duration = 12
Overpower.cooldown_duration = 12
local Rend = Ability.add(772, false, true)
Rend.rage_cost = 30
Rend.buff_duration = 12
Rend.hasted_ticks = true
local Slam = Ability.add(1464, false, true)
Slam.rage_cost = 20
local SweepingStrikes = Ability.add(260708, true, true)
SweepingStrikes.buff_duration = 12
SweepingStrikes.cooldown_duration = 30
local Whirlwind = Ability.add(1680, false, true)
Whirlwind.rage_cost = 30
Whirlwind:setAutoAoe(true)
local Hamstring = Ability.add(1715, false, true)
Hamstring.rage_cost = 10
Hamstring.buff_duration = 15
local Recklessness = Ability.add(1719, true, true)
Recklessness.buff_duration = 10
Recklessness.cooldown_duration = 90
local VictoryRush = Ability.add(34428, false, true)
------ Talents
local Cleave = Ability.add(845, false, true)
Cleave.rage_cost = 20
Cleave.cooldown_duration = 9
Cleave.hasted_cooldown = true
Cleave:setAutoAoe(true)
local DeadlyCalm = Ability.add(262228, true, true)
DeadlyCalm.buff_duration = 6
DeadlyCalm.cooldown_duration = 60
DeadlyCalm.triggers_gcd = false
local Dreadnaught = Ability.add(262150, false, true)
local FervorOfBattle = Ability.add(202316, false, true)
local Massacre = Ability.add(206315, false, true)
local Ravager = Ability.add(152277, false, true)
Ravager.buff_duration = 7
Ravager.cooldown_duration = 60
local Skullsplitter = Ability.add(260643, false, true)
Skullsplitter.cooldown_duration = 21
Skullsplitter.hasted_cooldown = true
local Warbreaker = Ability.add(262161, true, true)
Warbreaker.cooldown_duration = 45
Warbreaker:setAutoAoe(true)
------ Procs
local SuddenDeath = Ability.add(29725, true, true, 52437)
SuddenDeath.buff_duration = 10
local Victorious = Ability.add(32216, true, true)
Victorious.buff_duration = 20

---- Fury

------ Talents

------ Procs

---- Protection

------ Talents

------ Procs

-- Azerite Traits
local CrushingAssault = Ability.add(278824, true, true, 278826)
CrushingAssault.buff_duration = 10
local ExecutionersPrecision = Ability.add(272866, false, true, 272870)
ExecutionersPrecision.buff_duration = 30
local TestOfMight = Ability.add(275529, true, true, 275532)
TestOfMight.buff_duration = 12
-- Heart of Azeroth
---- Major Essences
local ConcentratedFlame = Ability.add(295373, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame.dot = Ability.add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability.add(295840, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability.add(295258, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
local MemoryOfLucidDreams = Ability.add(298357, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability.add(295337, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:autoAoe(true)
local RippleInSpace = Ability.add(302731, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability.add(298452, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability.add(299370, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability.add(295186, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability.add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability.add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability.add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability.add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability.add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability.add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:autoAoe()
local RealityShift = Ability.add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability.add(302917, true, true)
RecklessForce.essence_id = 28
local StriveForPerfection = Ability.add(299369, true, true)
StriveForPerfection.essence_id = 22
-- PvP talents

-- Racials
local LightsJudgment = Ability.add(255647, false, true)
LightsJudgment.cooldown_duration = 150
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:equipped()
	return self.equip_slot and true
end

function InventoryItem:usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:equipped() and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local GreaterFlaskOfTheUndertow = InventoryItem.add(168654)
GreaterFlaskOfTheUndertow.buff = Ability.add(298841, true, true)
local SuperiorBattlePotionOfStrength = InventoryItem.add(168500)
SuperiorBattlePotionOfStrength.buff = Ability.add(298154, true, true)
SuperiorBattlePotionOfStrength.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem.add(0)
local Trinket2 = InventoryItem.add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
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
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() do
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

-- Start Helpful Functions

local function HealthPct()
	return Player.health / Player.health_max * 100
end

local function RageDeficit()
	return Player.rage_max - Player.rage
end

local function TimeInCombat()
	if Player.combat_start > 0 then
		return Player.time - Player.combat_start
	end
	return 0
end

local function BloodlustActive()
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

-- End Helpful Functions

-- Start Ability Modifications

function Ability:cost()
	if DeadlyCalm:up() then
		return 0
	end
	return self.rage_cost
end

function Execute:cost()
	if SuddenDeath:up() then
		return 0
	end
	return max(min(40, Player.rage), self.rage_cost)
end

function Execute:usable()
	if not SuddenDeath:up() and Target.healthPercentage >= (Massacre.known and 35 or 20) then
		return false
	end
	return Ability.usable(self)
end

function VictoryRush:usable()
	if Victorious:down() then
		return false
	end
	return Ability.usable(self)
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
	if TimeInCombat() == 0 then
		if BattleShout:usable() and BattleShout:remains() < 300 then
			return BattleShout
		end
		if Opt.pot and Target.boss then
			if GreaterFlaskOfTheUndertow:usable() and GreaterFlaskOfTheUndertow.buff:remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if SuperiorBattlePotionOfStrength:usable() then
				UseCooldown(SuperiorBattlePotionOfStrength)
			end
		end
		if Charge:usable() then
			UseExtra(Charge)
		end
	else
		if BattleShout:usable() and BattleShout:remains() < 30 then
			UseCooldown(BattleShout)
		end
	end
--[[
actions=charge
actions+=/auto_attack
actions+=/potion
actions+=/blood_fury,if=debuff.colossus_smash.up
actions+=/berserking,if=debuff.colossus_smash.up
actions+=/arcane_torrent,if=debuff.colossus_smash.down&cooldown.mortal_strike.remains>1.5&rage<50
actions+=/lights_judgment,if=debuff.colossus_smash.down
actions+=/fireblood,if=debuff.colossus_smash.up
actions+=/ancestral_call,if=debuff.colossus_smash.up
actions+=/avatar,if=cooldown.colossus_smash.remains<8|(talent.warbreaker.enabled&cooldown.warbreaker.remains<8)
actions+=/sweeping_strikes,if=spell_targets.whirlwind>1&(cooldown.bladestorm.remains>10|cooldown.colossus_smash.remains>8|azerite.test_of_might.enabled)
actions+=/run_action_list,name=hac,if=raid_event.adds.exists
actions+=/run_action_list,name=five_target,if=spell_targets.whirlwind>4
actions+=/run_action_list,name=execute,if=(talent.massacre.enabled&target.health.pct<35)|target.health.pct<20
actions+=/run_action_list,name=single_target
]]
	if LightsJudgment:usable() and ColossusSmash:down() and Target.timeToDie > 4 then
		UseExtra(LightsJudgment)
	end
	if Avatar:usable() and (ColossusSmash:remains() < 8 or (Warbreaker.known and Warbreaker:ready(8))) then
		UseCooldown(Avatar)
	end
	if SweepingStrikes:ready() and Enemies() > 1 and (not Bladestorm:ready(10) or not ColossusSmash:ready(8) or TestOfMight.known) then
		UseCooldown(SweepingStrikes)
	end
	if Enemies() >= 5 then
		return self:five_target()
	end
--	if Enemies() >= 3 then
--		return self:hac()
--	end
	if Target.healthPercentage < (Massacre.known and 35 or 20) then
		return self:execute()
	end
	return self:single_target()
end

APL[SPEC.ARMS].execute = function(self)
--[[
actions.execute=skullsplitter,if=rage<60&(!talent.deadly_calm.enabled|buff.deadly_calm.down)
actions.execute+=/ravager,if=!buff.deadly_calm.up&(cooldown.colossus_smash.remains<2|(talent.warbreaker.enabled&cooldown.warbreaker.remains<2))
actions.execute+=/colossus_smash,if=debuff.colossus_smash.down
actions.execute+=/warbreaker,if=debuff.colossus_smash.down
actions.execute+=/deadly_calm
actions.execute+=/bladestorm,if=rage<30&!buff.deadly_calm.up
actions.execute+=/cleave,if=spell_targets.whirlwind>2
actions.execute+=/slam,if=buff.crushing_assault.up
actions.execute+=/mortal_strike,if=buff.overpower.stack=2&talent.dreadnaught.enabled|buff.executioners_precision.stack=2
actions.execute+=/execute,if=buff.deadly_calm.up
actions.execute+=/overpower
actions.execute+=/execute
]]
	if Skullsplitter:usable() and Player.rage < 60 and (not DeadlyCalm.known or DeadlyCalm:down()) then
		return Skullsplitter
	end
	if Ravager:usable() and not DeadlyCalm:up() and (ColossusSmash:ready(2) or (Warbreaker.known and Warbreaker:ready(2))) then
		UseCooldown(Ravager)
	end
	if ColossusSmash:usable() and ColossusSmash:down() then
		return ColossusSmash
	end
	if Warbreaker:usable() and ColossusSmash:down() then
		return Warbreaker
	end
	if DeadlyCalm:usable() then
		UseCooldown(DeadlyCalm)
	end
	if Bladestorm:usable() and Player.rage < 30 and not DeadlyCalm:up() then
		UseCooldown(Bladestorm)
	end
	if Cleave:usable() and Enemies() > 2 then
		return Cleave
	end
	if CrushingAssault.known and Slam:usable() and CrushingAssault:up() then
		return Slam
	end
	if MortalStrike:usable() and (Dreadnaught.known and Overpower:stack() == 2 or ExecutionersPrecision.known and ExecutionersPrecision:stack() == 2) then
		return MortalStrike
	end
	if Execute:usable() and DeadlyCalm:up() then
		return Execute
	end
	if Overpower:usable() then
		return Overpower
	end
	if Execute:usable() then
		return Execute
	end
	if VictoryRush:usable() then
		return VictoryRush
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
	if Skullsplitter:usable() and Player.rage < 60 and (not DeadlyCalm.known or DeadlyCalm:down()) then
		return Skullsplitter
	end
	if Ravager:usable() and (not Warbreaker.known or Warbreaker:ready(2)) then
		UseCooldown(Ravager)
	end
	if ColossusSmash:usable() and ColossusSmash:down() then
		return ColossusSmash
	end
	if Warbreaker:usable() and ColossusSmash:down() then
		return Warbreaker
	end
	if Bladestorm:usable() and SweepingStrikes:down() and (not DeadlyCalm.known or DeadlyCalm:down()) and ((not TestOfMight.known and ColossusSmash:remains() > 4.5) or TestOfMight:up()) then
		UseCooldown(Bladestorm)
	end
	if DeadlyCalm:usable() then
		UseCooldown(DeadlyCalm)
	end
	if Cleave:usable() then
		return Cleave
	end
	if Execute:usable() and ((not Cleave.known and DeepWounds:remains() < 2) or SuddenDeath:up() and (SweepingStrikes:up() or not SweepingStrikes:ready(8))) then
		return Execute
	end
	if MortalStrike:usable() and ((not Cleave.known and DeepWounds:remains() < 2) or SweepingStrikes:up() and Overpower:stack() == 2 and (Dreadnaught.known or ExecutionersPrecision:stack() == 2)) then
		return MortalStrike
	end
	if Whirlwind:usable() then
		if ColossusSmash:up() or (CrushingAssault.known and FervorOfBattle.known and CrushingAssault:up()) then
			return Whirlwind
		end
		if DeadlyCalm:up() or Player.rage > 60 then
			return Whirlwind
		end
	end
	if Overpower:usable() then
		return Overpower
	end
	if Whirlwind:usable() then
		return Whirlwind
	end
	if VictoryRush:usable() then
		return VictoryRush
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
actions.single_target+=/skullsplitter,if=rage<60&(!talent.deadly_calm.enabled|buff.deadly_calm.down)
actions.single_target+=/ravager,if=!buff.deadly_calm.up&(cooldown.colossus_smash.remains<2|(talent.warbreaker.enabled&cooldown.warbreaker.remains<2))
actions.single_target+=/colossus_smash,if=debuff.colossus_smash.down
actions.single_target+=/warbreaker,if=debuff.colossus_smash.down
actions.single_target+=/deadly_calm
actions.single_target+=/execute,if=buff.sudden_death.react
actions.single_target+=/rend,if=refreshable&cooldown.colossus_smash.remains<5
actions.single_target+=/bladestorm,if=cooldown.mortal_strike.remains&(!talent.deadly_calm.enabled|buff.deadly_calm.down)&((debuff.colossus_smash.up&!azerite.test_of_might.enabled)|buff.test_of_might.up)
actions.single_target+=/cleave,if=spell_targets.whirlwind>2
actions.single_target+=/overpower,if=azerite.seismic_wave.rank=3
actions.single_target+=/mortal_strike
actions.single_target+=/whirlwind,if=talent.fervor_of_battle.enabled&(buff.deadly_calm.up|rage>=60)
actions.single_target+=/overpower
actions.single_target+=/rend,target_if=min:remains,if=refreshable&debuff.colossus_smash.down
actions.single_target+=/whirlwind,if=talent.fervor_of_battle.enabled&cooldown.mortal_strike.remains>0.5&(!azerite.test_of_might.enabled|debuff.colossus_smash.up)
actions.single_target+=/slam,if=!talent.fervor_of_battle.enabled&cooldown.mortal_strike.remains>0.5
]]
	if Rend:usable() and Rend:down() and ColossusSmash:down() then
		return Rend
	end
	if Skullsplitter:usable() and Player.rage < 60 and (not DeadlyCalm.known or DeadlyCalm:down()) then
		return Skullsplitter
	end
	if Ravager:usable() and not DeadlyCalm:up() and (ColossusSmash:ready(2) or (Warbreaker.known and Warbreaker:ready(2))) then
		UseCooldown(Ravager)
	end
	if ColossusSmash:usable() and ColossusSmash:down() then
		return ColossusSmash
	end
	if Warbreaker:usable() and ColossusSmash:down() then
		return Warbreaker
	end
	if DeadlyCalm:usable() then
		UseCooldown(DeadlyCalm)
	end
	if SuddenDeath.known and Execute:usable() and SuddenDeath:up() then
		return Execute
	end
	if Rend:usable() and Rend:refreshable() and ColossusSmash:cooldown() < 5 then
		return Rend
	end
	if Bladestorm:usable() and not MortalStrike:ready() and (not DeadlyCalm.known or DeadlyCalm:down()) and ((not TestOfMight.known and ColossusSmash:up()) or TestOfMight:up()) then
		UseCooldown(Bladestorm)
	end
	if Cleave:usable() and Enemies() > 2 then
		return Cleave
	end
	if MortalStrike:usable() then
		return MortalStrike
	end
	if FervorOfBattle.known and Whirlwind:usable() and (DeadlyCalm:up() or Player.rage >= 60) then
		return Whirlwind
	end
	if Overpower:usable() then
		return Overpower
	end
	if Rend:usable() and Rend:refreshable() and ColossusSmash:down() then
		return Rend
	end
	if MortalStrike:ready(0.5) then
		return MortalStrike
	end
	if FervorOfBattle.known then
		if Whirlwind:usable() and (not TestOfMight.known or ColossusSmash:up()) then
			return Whirlwind
		end
	else
		if Slam:usable() then
			return Slam
		end
	end
	if VictoryRush:usable() then
		return VictoryRush
	end
end

APL[SPEC.FURY].main = function(self)
	if TimeInCombat() == 0 then
		if BattleShout:usable() and BattleShout:remains() < 300 then
			return BattleShout
		end
		if Opt.pot and Target.boss then
			if GreaterFlaskOfTheUndertow:usable() and GreaterFlaskOfTheUndertow.buff:remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if SuperiorBattlePotionOfStrength:usable() then
				UseCooldown(SuperiorBattlePotionOfStrength)
			end
		end
	else
		if BattleShout:usable() and BattleShout:remains() < 30 then
			UseCooldown(BattleShout)
		end
	end
end

APL[SPEC.PROTECTION].main = function(self)
	if TimeInCombat() == 0 then
		if BattleShout:usable() and BattleShout:remains() < 300 then
			return BattleShout
		end
		if Opt.pot and Target.boss then
			if GreaterFlaskOfTheUndertow:usable() and GreaterFlaskOfTheUndertow.buff:remains() < 300 then
				UseCooldown(GreaterFlaskOfTheUndertow)
			end
			if SuperiorBattlePotionOfStrength:usable() then
				UseCooldown(SuperiorBattlePotionOfStrength)
			end
		end
	else
		if BattleShout:usable() and BattleShout:remains() < 30 then
			UseCooldown(BattleShout)
		end
	end
end

APL.Interrupt = function(self)
	if Pummel:usable() then
		return Pummel
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		Player.interrupt = nil
		smashInterruptPanel:Hide()
		return
	end
	Player.interrupt = APL.Interrupt()
	if Player.interrupt then
		smashInterruptPanel.icon:SetTexture(Player.interrupt.icon)
	end
	smashInterruptPanel.icon:SetShown(Player.interrupt)
	smashInterruptPanel.border:SetShown(Player.interrupt)
	smashInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
	smashInterruptPanel:Show()
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
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

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
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

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.ARMS and Opt.hide.arms) or
		   (Player.spec == SPEC.FURY and Opt.hide.fury) or
		   (Player.spec == SPEC.PROTECTION and Opt.hide.protection))
end

local function Disappear()
	smashPanel:Hide()
	smashPanel.icon:Hide()
	smashPanel.border:Hide()
	smashCooldownPanel:Hide()
	smashInterruptPanel:Hide()
	smashExtraPanel:Hide()
	Player.main, Player.last_main = nil
	Player.cd, Player.last_cd = nil
	Player.interrupt = nil
	Player.extra, Player.last_extra = nil
	UpdateGlows()
end

local function Equipped(itemID, slot)
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

local function UpdateDraggable()
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

local function UpdateScale()
	smashPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	smashPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	smashCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	smashInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	smashExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

local function UpdateAlpha()
	smashPanel:SetAlpha(Opt.alpha)
	smashPreviousPanel:SetAlpha(Opt.alpha)
	smashCooldownPanel:SetAlpha(Opt.alpha)
	smashInterruptPanel:SetAlpha(Opt.alpha)
	smashExtraPanel:SetAlpha(Opt.alpha)
end

local function SnapAllPanels()
	smashPreviousPanel:ClearAllPoints()
	smashPreviousPanel:SetPoint('TOPRIGHT', smashPanel, 'BOTTOMLEFT', -3, 40)
	smashCooldownPanel:ClearAllPoints()
	smashCooldownPanel:SetPoint('TOPLEFT', smashPanel, 'BOTTOMRIGHT', 3, 40)
	smashInterruptPanel:ClearAllPoints()
	smashInterruptPanel:SetPoint('BOTTOMLEFT', smashPanel, 'TOPRIGHT', 3, -21)
	smashExtraPanel:ClearAllPoints()
	smashExtraPanel:SetPoint('BOTTOMRIGHT', smashPanel, 'TOPLEFT', -3, -21)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.ARMS] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 49 },
			['below'] = { 'TOP', 'BOTTOM', 0, -12 }
		}
	},
	['kui'] = {
		[SPEC.ARMS] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		},
		[SPEC.FURY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		},
		[SPEC.PROTECTION] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 6 }
		}
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		smashPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		smashPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][Player.spec][Opt.snap]
		smashPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if resourceAnchor.frame then
		resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
		resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
	end
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 15
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
	timer.display = 0
	local dim, text_tl, text_tr
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Opt.swing_timer then
		if Player.main and Player.main:cost() <= Player.rage then
			smashPanel.text:Hide()
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
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.last_main = Player.main
	Player.last_cd = Player.cd
	Player.last_extra = Player.extra
	Player.main =  nil
	Player.cd = nil
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

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main ~= Player.last_main then
		if Player.main then
			smashPanel.icon:SetTexture(Player.main.icon)
		end
		smashPanel.icon:SetShown(Player.main)
		smashPanel.border:SetShown(Player.main)
	end
	if Player.cd ~= Player.last_cd then
		if Player.cd then
			smashCooldownPanel.icon:SetTexture(Player.cd.icon)
		end
		smashCooldownPanel:SetShown(Player.cd)
	end
	if Player.extra ~= Player.last_extra then
		if Player.extra then
			smashExtraPanel.icon:SetTexture(Player.extra.icon)
		end
		smashExtraPanel:SetShown(Player.extra)
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
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
	if srcName == 'player' and powerType == 'RAGE' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(srcName, castId, spellId)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:ADDON_LOADED(name)
	if name ~= 'Smash' then
		return
	end
	Opt = Smash
	if not Opt.frequency then
		print('It looks like this is your first time running Smash, why don\'t you take some time to familiarize yourself with the commands?')
		print('Type |cFFFFD000' .. SLASH_Smash1 .. '|r for a list of commands.')
	end
	if UnitLevel('player') < 110 then
		print('[|cFFFFD000Warning|r] Smash is not designed for players under level 110, and almost certainly will not operate properly!')
	end
	InitializeOpts()
	Azerite:initialize()
	UpdateDraggable()
	UpdateAlpha()
	UpdateScale()
	SnapAllPanels()
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
		if Opt.auto_aoe then
			if dstGUID == Player.guid then
				autoAoe:add(srcGUID, true)
			elseif srcGUID == Player.guid and not (missType == 'EVADE' or missType == 'IMMUNE') then
				autoAoe:add(dstGUID, true)
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
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if Opt.previous and smashPanel:IsVisible() then
				smashPreviousPanel.ability = ability
				smashPreviousPanel.border:SetTexture('Interface\\AddOns\\Smash\\border.blp')
				smashPreviousPanel.icon:SetTexture(ability.icon)
				smashPreviousPanel:Show()
			end
		end
		return
	end
	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:refreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:removeAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:remove(dstGUID)
		elseif ability.auto_aoe and eventType == ability.auto_aoe.trigger then
			ability:recordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and smashPanel:IsVisible() and ability == smashPreviousPanel.ability then
			smashPreviousPanel.border:SetTexture('Interface\\AddOns\\Smash\\misseffect.blp')
		end
	end
end

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.stunnable = true
		Target.classification = 'normal'
		Target.player = false
		Target.level = UnitLevel('player')
		Target.healthMax = 0
		Target.hostile = true
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			smashPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			smashPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.boss = false
	Target.stunnable = true
	Target.classification = UnitClassification('target')
	Target.player = UnitIsPlayer('target')
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not Target.player and Target.classification ~= 'minus' and Target.classification ~= 'normal' then
		if Target.level == -1 or (Player.instance == 'party' and Target.level >= UnitLevel('player') + 2) then
			Target.boss = true
			Target.stunnable = false
		elseif Player.instance == 'raid' or (Target.healthMax > Player.health_max * 10) then
			Target.stunnable = false
		end
	end
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		smashPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		smashPreviousPanel:Hide()
	end
	local _, ability, guid
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:clear()
		autoAoe:update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Player.equipped_mh = GetInventoryItemID('player', 16) and true
	Player.equipped_oh = GetInventoryItemID('player', 17) and true
end

local function UpdateAbilityData()
	Player.rage_max = UnitPowerMax('player', 1)

	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = false
		if IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) then
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

	if Warbreaker.known then
		ColosussSmash.known = false
	end
	if Ravager.known then
		Bladestorm.known = false
	end

	abilities.bySpellId = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
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
			_, inventoryItems[i].equip_slot = Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Azerite:update()
	UpdateAbilityData()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	smashPreviousPanel.ability = nil
	SetTargetMode(1)
	UpdateTargetInfo()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	InnerDemons.next_imp = nil
end

function events:PLAYER_PVP_TALENT_UPDATE()
	UpdateAbilityData()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:update()
	UpdateAbilityData()
end

function events:PLAYER_ENTERING_WORLD()
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

smashPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			ToggleTargetMode()
		elseif button == 'RightButton' then
			ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			SetTargetMode(1)
		end
	end
end)

smashPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

smashPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	smashPanel:RegisterEvent(event)
end

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
			UpdateDraggable()
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
			OnResourceFrameShow()
		end
		return Status('Snap to Blizzard combat resources frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UpdateScale()
			end
			return Status('Extra ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
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
				UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (extra icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
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
		return Status('Dim main ability icon when you don\'t have enough mana to use it', Opt.dimmer)
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
			Smash_SetTargetMode(1)
			UpdateDraggable()
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
		SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Smash (version: |cFFFFD000' .. GetAddOnMetadata('Smash', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Smash UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Smash UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Smash UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Smash UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Smash UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Smash for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough rage to use it',
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
