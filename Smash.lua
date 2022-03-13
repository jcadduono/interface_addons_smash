local ADDON = 'Smash'
if select(2, UnitClass('player')) ~= 'WARRIOR' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- copy heavily accessed global functions into local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsCurrentSpell = _G.IsCurrentSpell
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = _G.UnitAura
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
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

SmashConfig = {}
local Opt -- use this as a local table reference to SmashConfig

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
	SetDefaults(SmashConfig, { -- defaults
		locked = false,
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
		swing_timer = true,
		cshout = true,
		last_shout = 'battle',
		slam_min_speed = 1.9,
		slam_cutoff = 1,
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
	health = 0
}

-- stance constants
local STANCE = {
	NONE = 0,
	BATTLE = 1,
	DEFENSIVE = 2,
	BERSERKER = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	stance = STANCE.NONE,
	target_mode = 0,
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	gcd = 1.5,
	gcd_remains = 0,
	health = 0,
	health_max = 0,
	rage = {
		current = 0,
		max = 0,
	},
	group_size = 1,
	moving = false,
	movement_speed = 100,
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			next = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			next = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
		last_taken_physical = 0,
	},
	equipped = {
		twohand = false,
		offhand = false,
		shield = false,
	},
	set_bonus = {
		t4_dps = 0,
		t5_dps = 0,
		t6_dps = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
	hostile = false,
	estimated_range = 30,
	npc_swing_types = { -- [npcId] = type
	},
}

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
smashPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
smashPanel.border:Hide()
smashPanel.dimmer = smashPanel:CreateTexture(nil, 'BORDER')
smashPanel.dimmer:SetAllPoints(smashPanel)
smashPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
smashPanel.dimmer:Hide()
smashPanel.swipe = CreateFrame('Cooldown', nil, smashPanel, 'CooldownFrameTemplate')
smashPanel.swipe:SetAllPoints(smashPanel)
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
smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
smashCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
smashCooldownPanel.dimmer = smashCooldownPanel:CreateTexture(nil, 'BORDER')
smashCooldownPanel.dimmer:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
smashCooldownPanel.dimmer:Hide()
smashCooldownPanel.swipe = CreateFrame('Cooldown', nil, smashCooldownPanel, 'CooldownFrameTemplate')
smashCooldownPanel.swipe:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.text = smashCooldownPanel:CreateFontString(nil, 'OVERLAY')
smashCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
smashCooldownPanel.text:SetAllPoints(smashCooldownPanel)
smashCooldownPanel.text:SetJustifyH('CENTER')
smashCooldownPanel.text:SetJustifyV('CENTER')
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
smashInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
smashInterruptPanel.swipe = CreateFrame('Cooldown', nil, smashInterruptPanel, 'CooldownFrameTemplate')
smashInterruptPanel.swipe:SetAllPoints(smashInterruptPanel)
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
smashExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')

-- Start AoE

Player.target_modes = {
	{1, ''},
	{2, '2'},
	{3, '3'},
	{4, '4'},
	{5, '5+'},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes)
	self.enemies = self.target_modes[self.target_mode][1]
	smashPanel.text.br:SetText(self.target_modes[self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes or mode)
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
	for i = #Player.target_modes, 1, -1 do
		if count >= Player.target_modes[i][1] then
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
	all = {}
}

function Ability:Add(spellId, buff, player)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		name = false,
		rank = 0,
		icon = false,
		requires_charge = false,
		requires_react = false,
		requires_shield = false,
		triggers_combat = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		rage_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 30,
		velocity = 0,
		last_used = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		if spell == self.spellId then
			return true
		end
		for _, id in next, self.spellIds do
			if spell == id then
				return true
			end
		end
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
	if not pool then
		if self:RageCost() > Player.rage.current then
			return false
		end
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	if self.requires_shield and not Player.equipped.shield then
		return false
	end
	return self:Ready(seconds)
end

function Ability:React()
	if self.aura_targets then
		local aura = self.aura_targets[self.auraTarget == 'player' and Player.guid or Target.guid]
		if aura then
			return max(0, aura.expires - Player.time - Player.execute_remains)
		end
	end
	return 0
end

function Ability:Remains(mine)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter .. (mine and '|PLAYER' or ''))
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

function Ability:Up(condition)
	return self:Remains(condition) > 0
end

function Ability:Down(condition)
	return self:Remains(condition) <= 0
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
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:RageCost()
	return self.rage_cost
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

function Ability:CastStart(dstGUID)
	return
end

function Ability:CastFailed(dstGUID)
	return
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		if self.activated then
			self.activated = false
		end
		self:RemoveAura(self.auraTarget == 'player' and Player.guid or dstGUID)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		smashPreviousPanel.ability = self
		smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		smashPreviousPanel.icon:SetTexture(self.icon)
		smashPreviousPanel:SetShown(smashPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event)
	if self.swing_queue then
		Player:ResetSwing(true, false, event == 'SPELL_MISSED')
	end
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
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and smashPreviousPanel.ability == self then
		smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT Tracking

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
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	return self:ApplyAura(guid)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT Tracking

-- Warrior Abilities
---- General
local BerserkerRage = Ability:Add({18499}, true, true)
BerserkerRage.buff_duration = 10
BerserkerRage.cooldown_duration = 30
local Bloodrage = Ability:Add({2687}, true, false)
Bloodrage.cooldown_duration = 60
Bloodrage.buff = Ability:Add({29131}, true, true)
Bloodrage.buff.buff_duration = 10
local Pummel = Ability:Add({6552, 6554}, false, true)
Pummel.buff_duration = 4
Pummel.cooldown_duration = 10
Pummel.rage_cost = 10
---- Arms
local BattleStance = Ability:Add({2457}, false, true)
BattleStance.cooldown_duration = 1
local Charge = Ability:Add({100, 6178, 11578}, false, true)
Charge.cooldown_duration = 15
Charge.stun = Ability:Add({7922})
Charge.stun.buff_duration = 1
local HeroicStrike = Ability:Add({78, 284, 285, 1608, 11564, 11565, 11566, 11567, 25286, 29707, 30324}, false, true)
HeroicStrike.rage_cost = 15
HeroicStrike.swing_queue = true
local MockingBlow = Ability:Add({694, 7400, 7402, 20559, 20560, 25266}, false, true)
MockingBlow.buff_duration = 6
MockingBlow.cooldown_duration = 120
MockingBlow.rage_cost = 10
local Overpower = Ability:Add({7384, 7887, 11584, 11585}, false, true)
Overpower.buff_duration = 5 -- use 5 second imaginary debuff triggered by dodge
Overpower.cooldown_duration = 5
Overpower.rage_cost = 5
Overpower.requires_react = true
Overpower:TrackAuras()
local Rend = Ability:Add({772, 6546, 6547, 6548, 11572, 11573, 11574, 25208}, false, true)
Rend.rage_cost = 10
Rend.buff_duration = 15
Rend:TrackAuras()
local Hamstring = Ability:Add({1715, 7372, 7373, 25212}, false, false)
Hamstring.rage_cost = 10
Hamstring.buff_duration = 15
local Retaliation = Ability:Add({20230}, true, true)
Retaliation.buff_duration = 15
Retaliation.cooldown_duration = 1800
local ThunderClap = Ability:Add({6343, 8198, 8204, 8205, 11580, 11581, 25264}, false, true)
ThunderClap.cooldown_duration = 4
ThunderClap.rage_cost = 20
ThunderClap:AutoAoe(false)
------ Talents
local DeathWish = Ability:Add({12292}, true, true)
DeathWish.buff_duration = 30
DeathWish.cooldown_duration = 180
DeathWish.rage_cost = 10
local DeepWounds = Ability:Add({12834, 12849, 12867}, false, true)
DeepWounds.buff_duration = 12
local ImprovedHeroicStrike = Ability:Add({12282, 12663, 12664}, false, true)
local ImprovedThunderClap = Ability:Add({12287, 12665, 12666}, false, true)
local MortalStrike = Ability:Add({12294, 21551, 21552, 21553, 25248, 30330}, false, true)
MortalStrike.rage_cost = 30
MortalStrike.cooldown_duration = 6
------ Procs

---- Fury
local BattleShout = Ability:Add({6673, 5242, 6192, 11549, 11550, 11551, 25289, 2048}, true, false)
BattleShout.buff_duration = 120
BattleShout.rage_cost = 10
local BerserkerStance = Ability:Add({2458}, false, true)
BerserkerStance.cooldown_duration = 1
local Cleave = Ability:Add({845, 7369, 11608, 11609, 20569, 25231}, false, true)
Cleave.rage_cost = 20
Cleave.swing_queue = true
Cleave:AutoAoe(false)
local CommandingShout = Ability:Add({469}, true, false)
CommandingShout.buff_duration = 120
CommandingShout.rage_cost = 10
local Execute = Ability:Add({5308, 20658, 20660, 20661, 20662, 25234, 25236}, false, true)
Execute.rage_cost = 15
local Intercept = Ability:Add({20252, 20616, 20617, 25272, 25275}, false, true)
Intercept.cooldown_duration = 30
Intercept.rage_cost = 10
Intercept.stun = Ability:Add({20253, 20614, 20615, 25273, 25274})
Intercept.stun.buff_duration = 3
local IntimidatingShout = Ability:Add({5246}, false, false)
IntimidatingShout.buff_duration = 8
IntimidatingShout.cooldown_duration = 180
IntimidatingShout.rage_cost = 25
local Recklessness = Ability:Add({1719}, true, true)
Recklessness.buff_duration = 15
Recklessness.cooldown_duration = 1800
local Slam = Ability:Add({1464, 8820, 11604, 11605, 25241, 25242}, false, true)
Slam.rage_cost = 15
local VictoryRush = Ability:Add({34428}, true, true)
VictoryRush.buff_duration = 20
VictoryRush.activated = false
VictoryRush.requires_react = true
VictoryRush:TrackAuras()
local Whirlwind = Ability:Add({1680}, false, true)
Whirlwind.cooldown_duration = 10
Whirlwind.rage_cost = 25
Whirlwind:AutoAoe(false)
------ Talents
local Bloodthirst = Ability:Add({23881, 23892, 23893, 23894, 25251, 30335}, false, true)
Bloodthirst.rage_cost = 30
Bloodthirst.cooldown_duration = 6
local ImprovedExecute = Ability:Add({20502, 20503}, false, true)
local ImprovedSlam = Ability:Add({12862, 12330}, false, true)
local Rampage = Ability:Add({29801, 30030, 30033}, true, true)
Rampage.buff_duration = 5
Rampage.rage_cost = 20
Rampage.requires_react = true
Rampage.buff = Ability:Add({30029, 30031, 30032}, true, true)
Rampage.buff.buff_duration = 30
local SweepingStrikes = Ability:Add({12328}, true, true)
SweepingStrikes.rage_cost = 30
SweepingStrikes.buff_duration = 10
SweepingStrikes.cooldown_duration = 30
------ Procs

---- Protection
local DefensiveStance = Ability:Add({71}, false, true)
DefensiveStance.cooldown_duration = 1
local Disarm = Ability:Add({676}, false, false)
Disarm.buff_duration = 10
Disarm.cooldown_duration = 60
Disarm.rage_cost = 20
local Revenge = Ability:Add({6572, 6574, 7379, 11600, 11601, 25288, 25269, 30357}, true, true)
Revenge.buff_duration = 5 -- use 5 second imaginary buff triggered by block/dodge/parry
Revenge.cooldown_duration = 5
Revenge.rage_cost = 5
Revenge.requires_react = true
Revenge:TrackAuras()
Revenge.stun = Ability:Add({12798})
Revenge.stun.buff_duration = 3
local ShieldBash = Ability:Add({72, 1671, 1672, 29704}, false, true)
ShieldBash.cooldown_duration = 12
ShieldBash.rage_cost = 10
ShieldBash.requires_shield = true
local ShieldBlock = Ability:Add({2565}, true, true)
ShieldBlock.cooldown_duration = 5
ShieldBlock.rage_cost = 10
ShieldBlock.requires_shield = true
local Taunt = Ability:Add({355}, false, true)
Taunt.cooldown_duration = 10
Taunt.triggers_gcd = false
------ Talents
local ConcussionBlow = Ability:Add({12809}, false, false)
ConcussionBlow.buff_duration = 5
ConcussionBlow.cooldown_duration = 45
ConcussionBlow.rage_cost = 15
local Devastate = Ability:Add({20243, 30016, 30022}, false, true)
Devastate.rage_cost = 15
local ShieldSlam = Ability:Add({23922, 23923, 23924, 23925, 25258, 30356}, false, true)
ShieldSlam.rage_cost = 20
ShieldSlam.cooldown_duration = 6
ShieldSlam.requires_shield = true
local FocusedRage = Ability:Add({29787, 29790, 29792}, false, true)
local ImprovedSunderArmor = Ability:Add({12308, 12810, 12811}, false, true)
------ Procs

-- Racials
local BloodFury = Ability:Add({20572}, true, true)
BloodFury.buff_duration = 15
BloodFury.cooldown_duration = 180
-- Class Debuffs
local CurseOfWeakness = Ability:Add({702, 1108, 6205, 7646, 11707, 11708, 27224, 30909}) -- Applied by Warlocks, AP reduction
local DemoralizingRoar = Ability:Add({99, 1735, 9490, 9747, 9898, 26998}) -- Applied by Druids, AP reduction
local DemoralizingShout = Ability:Add({1160, 6190, 11554, 11555, 11556, 25202, 25203}) -- Applied by Warriors, AP reduction, doesn't stack with Demoralizing Roar/Curse of Weakness
DemoralizingShout.rage_cost = 10
local ExposeArmor = Ability:Add({8647, 8649, 8650, 11197, 11198, 26866}) -- Applied by Rogues, armor reduction
local SunderArmor = Ability:Add({7386, 7405, 8380, 11596, 11597, 25225}) -- Applied by Warriors, armor reduction, doesn't stack with Expose Armor
SunderArmor.buff_duration = 30
SunderArmor.rage_cost = 15
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

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:RageDeficit()
	return self.rage.max - self.rage.current
end

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
		self.swing.mh.next = self.time + self.swing.mh.speed
		if Opt.swing_timer then
			smashPanel.text.tl:SetTextColor(1, missed and 0 or 1, missed and 0 or 1, 1)
		end
		if Slam.known then
			Slam.used_this_swing = false
		end
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
		self.swing.oh.next = self.time + self.swing.oh.speed
		if Opt.swing_timer then
			smashPanel.text.tr:SetTextColor(1, missed and 0 or 1, missed and 0 or 1, 1)
		end
	end
end

function Player:UnderMeleeAttack(physical)
	return (self.time - (physical and self.swing.last_taken_physical or self.swing.last_taken)) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
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

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
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

	-- Update spell ranks first
	for _, ability in next, abilities.all do
		ability.known = false
		ability.spellId = ability.spellIds[1]
		ability.rank = 1
		for i, spellId in next, ability.spellIds do
			if IsPlayerSpell(spellId) then
				ability.known = true
				ability.spellId = spellId -- update spellId to current rank
				ability.rank = i
			end
		end
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
	end

	Intercept.stun.known = Intercept.known
	if Rampage.known then
		Rampage.buff.known = true
		Rampage.buff.spellId = Rampage.buff.spellIds[Rampage.rank]
		Rampage.buff.rank = Rampage.rank
	end
	Slam.use = Slam.known and ImprovedSlam.known and Player.equipped.twohand

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	abilities.swingQueue = {}
	for _, ability in next, abilities.all do
		if ability.known then
			for i, spellId in next, ability.spellIds do
				abilities.bySpellId[spellId] = ability
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
			if ability.swing_queue then
				abilities.swingQueue[#abilities.swingQueue + 1] = ability
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
	local _, start, duration, remains, spellId, speed, max_speed
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.pool_rage = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(47524)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.health = UnitHealth('player')
	self.health_max = UnitHealthMax('player')
	self.rage.current = UnitPower('player', 1)
	if self.ability_casting and self.ability_casting.rage_cost then
		self.rage.current = max(0, self.rage.current - self.ability_casting:RageCost())
	end
	self.swing.mh.remains = self.ability_casting == Slam and self.swing.mh.speed or max(0, self.swing.mh.next - self.time - self.execute_remains)
	self.swing.oh.remains = self.ability_casting == Slam and self.swing.oh.speed or max(0, self.swing.oh.next - self.time - self.execute_remains)
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()

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
		UI:CreateOverlayGlows()
	end
	smashPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	self:SetTargetMode(1)
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:UPDATE_SHAPESHIFT_FORM()
	events:PLAYER_REGEN_ENABLED()
	self:Update()
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	if self.health <= 0 then
		self.health = Player.health_max
		self.health_max = self.health
	end
	if reset then
		for i = 1, 25 do
			self.health_array[i] = self.health
		end
	else
		table.remove(self.health_array, 1)
		self.health_array[25] = self.health
	end
	self.timeToDieMax = self.health / Player.health_max * 10
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.npcid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.creature_type = 'Humanoid'
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
		self.npcid = tonumber(guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)') or 0)
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.creature_type = UnitCreatureType('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
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

function Target:Stunned()
	if Charge.stun:Up() or Intercept.stun:Up() or Revenge.stun:Up() or ConcussionBlow:Up() then
		return true
	end
	return false
end

function Target:DealsPhysicalDamage()
	if self.npcid and Target.npc_swing_types[self.npcid] then
		return bit.band(Target.npc_swing_types[self.npcid], 1) > 0
	end
	return true
end

-- End Target API

-- Start Ability Modifications

FocusedRage.modifies = {
	[Cleave] = true,
	[ConcussionBlow] = true,
	[DemoralizingShout] = true,
	[Devastate] = true,
	[Disarm] = true,
	[Execute] = true,
	[Hamstring] = true,
	[HeroicStrike] = true,
	[Intercept] = true,
	[IntimidatingShout] = true,
	[MockingBlow] = true,
	[Overpower] = true,
	[Pummel] = true,
	[Rend] = true,
	[Revenge] = true,
	[ShieldBash] = true,
	[ShieldSlam] = true,
	[Slam] = true,
	[SunderArmor] = true,
	[ThunderClap] = true,
	[Whirlwind] = true,
}

function Ability:RageCost()
	local cost = self.rage_cost
	if FocusedRage.known and FocusedRage.modifies[self] then
		cost = cost - FocusedRage.rank
	end
	return max(0, cost)
end

function HeroicStrike:RageCost()
	local cost = Ability.RageCost(self)
	if ImprovedHeroicStrike.known then
		cost = cost - ImprovedHeroicStrike.rank
	end
	return max(0, cost)
end

function SunderArmor:RageCost()
	local cost = Ability.RageCost(self)
	if ImprovedSunderArmor.known then
		cost = cost - ImprovedSunderArmor.rank
	end
	return max(0, cost)
end
Devastate.RageCost = SunderArmor.RageCost

function ThunderClap:RageCost()
	local cost = Ability.RageCost(self)
	if ImprovedThunderClap.known then
		cost = cost - floor(1.4 * ImprovedThunderClap.rank)
	end
	return max(0, cost)
end

function Execute:RageCost()
	local cost = Ability.RageCost(self)
	if ImprovedExecute.known then
		cost = cost - floor(2.6 * ImprovedExecute.rank)
	end
	if Player.set_bonus.t6_dps >= 2 then
		cost = cost - 3
	end
	return max(0, cost)
end

function Execute:Usable()
	if Target.healthPercentage > 20 then
		return false
	end
	return Ability.Usable(self)
end

function Bloodthirst:RageCost()
	local cost = Ability.RageCost(self)
	if Player.set_bonus.t5_dps >= 4 then
		cost = cost - 5
	end
	return max(0, cost)
end

function MortalStrike:RageCost()
	local cost = Ability.RageCost(self)
	if Player.set_bonus.t5_dps >= 4 then
		cost = cost - 5
	end
	return max(0, cost)
end

function Whirlwind:RageCost()
	local cost = Ability.RageCost(self)
	if Player.set_bonus.t4_dps >= 2 then
		cost = cost - 5
	end
	return max(0, cost)
end

function Charge:Usable()
	if InCombatLockdown() then
		return false
	end
	return Ability.Usable(self)
end

function Rend:Usable()
	if Target.creature_type == 'Mechanical' or Target.creature_type == 'Elemental' then
		return false
	end
	return Ability.Usable(self)
end

function VictoryRush:React()
	if not self.activated then
		return 0
	end
	return Ability.React(self)
end

function ConcussionBlow:Usable()
	if not Target.stunnable or Target:Stunned() then
		return false
	end
	return Ability.Usable(self)
end

function SweepingStrikes:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	if Opt.auto_aoe and Player.target_mode < 2 then
		Player:SetTargetMode(2)
	end
end

function Slam:CastLanded(dstGUID, event)
	Ability.CastLanded(self, dstGUID, event)
	Player:ResetSwing(true, true, event == 'SPELL_MISSED')
	self.used_this_swing = true
end

function Slam:FirstInSwing()
	return not (self.used_this_swing or self:Casting())
end

function BattleShout:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Opt.last_shout = 'battle'
end

function CommandingShout:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	Opt.last_shout = 'commanding'
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
	Player.pool_rage = min(Player.rage.max, ability:RageCost() + (extra or 0))
	return ability
end

-- Begin Action Priority Lists

local APL = {
	[STANCE.NONE] = {
		main = function() end
	},
	[STANCE.BATTLE] = {},
	[STANCE.DEFENSIVE] = {},
	[STANCE.BERSERKER] = {},
}

APL[STANCE.BATTLE].main = function(self)
	Slam.wait = Slam.use and Player.swing.mh.remains < Opt.slam_cutoff and Player.swing.mh.speed > Opt.slam_min_speed and Player.rage.current < 75 and Target.timeToDie > 2
	if Player:TimeInCombat() == 0 then
		local apl = APL:Buffs(Target.boss and 180 or 30)
		if apl then return apl end
		if Charge:Usable() then
			return Charge
		end
	else
		local apl = APL:Buffs(10)
		if apl then UseExtra(apl) end
	end
	if Overpower:Usable() then
		return Overpower
	end
	if DefensiveStance.known and Player.equipped.shield and (Player.enemies == 1 or not SweepingStrikes.known or not SweepingStrikes:Ready()) then
		UseExtra(DefensiveStance)
	end
	if BerserkerStance.known and not Player.equipped.shield and Player.rage.current < 30 then
		UseCooldown(BerserkerStance)
	end
	if Slam.use and Slam:Usable() and Slam:FirstInSwing() and Player.swing.mh.remains > Opt.slam_min_speed and (Player.enemies == 1 or not Whirlwind:Usable() or Player.rage.current > (Slam:RageCost() + Whirlwind:RageCost())) then
		return Slam
	end
	if Bloodrage:Usable() and Player.rage.current < 30 and not (Player:UnderAttack() or Player:HealthPct() < 60 or BerserkerRage:Up()) then
		UseCooldown(Bloodrage)
	end
	if DeathWish:Usable() and not Slam.wait and (not Target.boss or (Player:TimeInCombat() > 10 and (Target.healthPercentage < 20 or Target.timeToDie < 35 or Target.timeToDie > DeathWish:CooldownDuration() + 40))) then
		UseCooldown(DeathWish)
	end
	if BloodFury:Usable() and not (Player:UnderAttack() or Player:HealthPct() < 60) then
		UseCooldown(BloodFury)
	end
	if Rampage:Usable(0, true) and Rampage.buff:Remains() < 3 then
		return Pool(Rampage)
	end
	if SweepingStrikes:Usable(0.5, true) and Player.enemies > 1 then
		UseCooldown(SweepingStrikes)
	end
	if Player.enemies > 1 then
		if Cleave:Usable() and Player.rage.current >= (Player.equipped.twohand and 85 or 55) then
			UseCooldown(Cleave)
		end
	elseif Player.equipped.offhand then
		if HeroicStrike:Usable() and Player.rage.current >= 55 and not Execute:Usable() then
			UseCooldown(HeroicStrike)
		end
	end
	if VictoryRush:Usable() and VictoryRush:Remains() < Player.gcd then
		return VictoryRush
	end
	if not Slam.wait then
		if Bloodthirst:Usable() and (Player.equipped.twohand or not Execute:Usable()) then
			return Bloodthirst
		end
		if MortalStrike:Usable() and (Player.equipped.twohand or not Execute:Usable()) then
			return MortalStrike
		end
		if ShieldSlam:Usable() then
			return ShieldSlam
		end
		if Rampage:Usable() and Rampage.buff:Remains() < 5 then
			return Rampage
		end
		if Execute:Usable() then
			return Execute
		end
	end
	if Player.enemies > 1 then
		if Cleave:Usable() and Player.rage.current >= 55 then
			UseCooldown(Cleave)
		end
	else
		if HeroicStrike:Usable() and Player.rage.current >= (Player.equipped.twohand and 65 or 55) then
			UseCooldown(HeroicStrike)
		end
	end
	if VictoryRush:Usable() and not Slam.wait then
		return VictoryRush
	end
	if Slam.use and Slam:Usable() and Player.enemies == 1 and Player.swing.mh.remains > Opt.slam_min_speed and Player.rage.current >= 90 then
		return Slam
	end
end

APL[STANCE.DEFENSIVE].main = function(self)
	Slam.wait = false
	if Player:TimeInCombat() == 0 then
		local apl = APL:Buffs(Target.boss and 180 or 30)
		if apl then return apl end
		if Charge:Ready(2) and Player.rage.current < 30 then
			UseExtra(BattleStance)
		end
		if Bloodrage:Usable() then
			UseCooldown(Bloodrage)
		end
	else
		local apl = APL:Buffs(10)
		if apl then UseExtra(apl) end
	end
	if ShieldBlock:Usable() and Player.rage.current >= 27 and Player:UnderMeleeAttack(true) and ShieldBlock:Down() then
		UseCooldown(ShieldBlock)
	end
	if Taunt:Usable() and Player.threat.status < 3 and UnitAffectingCombat('target') then
		UseCooldown(Taunt)
	end
	if Bloodrage:Usable() and Player.rage.current < 20 and not (Player:HealthPct() < 60 or BerserkerRage:Up()) then
		UseCooldown(Bloodrage)
	end
	if Player.rage.current >= 44 then
		if Cleave:Usable() and Player.enemies > 1 then
			UseCooldown(Cleave)
		end
		if HeroicStrike:Usable() then
			UseCooldown(HeroicStrike)
		end
	end
	if SweepingStrikes.known and Player.enemies > 1 and SweepingStrikes:Ready(2) and Player.rage.current <= 30 then
		UseExtra(BattleStance)
	end
	if Rampage:Usable() and Rampage.buff:Remains() < 5 then
		return Rampage
	end
	if Revenge:Usable() and Revenge:React() < Player.gcd then
		return Revenge
	end
	if ShieldSlam:Usable() then
		return ShieldSlam
	end
	if ThunderClap:Usable() and Player.enemies >= (ImprovedThunderClap.known and 3 or 4) then
		return ThunderClap
	end
	if Revenge:Usable(0, true) then
		return Pool(Revenge)
	end
	if ShieldSlam:Usable(0.5, true) then
		return Pool(ShieldSlam)
	end
	if ThunderClap:Usable(0.5, true) and ((ImprovedThunderClap.known and Player.enemies >= 2) or ThunderClap:Down()) then
		return Pool(ThunderClap)
	end
	if Bloodthirst:Usable(0, true) then
		return Bloodthirst
	end
	if MortalStrike:Usable(0, true) then
		return MortalStrike
	end
	if Devastate.known then
		if Devastate:Usable() and (Player.rage.current >= 26 or (SunderArmor:Stack() >= 3 and SunderArmor:Remains() < 5)) then
			return Devastate
		end
	else
		if ThunderClap:Usable() and Player.enemies >= 2 and Player.rage.current >= 50 then
			return ThunderClap
		end
		if SunderArmor:Usable() and (Player.rage.current >= 60 or (SunderArmor:Stack() >= 3 and SunderArmor:Remains() < 5) or (Player.rage.current >= 26 and SunderArmor:Stack() < 5)) then
			return SunderArmor
		end
	end
end

APL[STANCE.BERSERKER].main = function(self)
	Slam.wait = Slam.use and Player.swing.mh.remains < Opt.slam_cutoff and Player.swing.mh.speed > Opt.slam_min_speed and Player.rage.current < 75 and Target.timeToDie > 2
	if Player:TimeInCombat() == 0 then
		local apl = APL:Buffs(Target.boss and 180 or 30)
		if apl then return apl end
		if Intercept:Usable() then
			return Intercept
		end
		if Charge:Ready(0.5) and Player.rage.current < 20 then
			UseExtra(BattleStance)
		end
	elseif not Slam.wait then
		local apl = APL:Buffs(10)
		if apl then UseExtra(apl) end
	end
	if Slam.use and Slam:Usable() and Slam:FirstInSwing() and Player.swing.mh.remains > Opt.slam_min_speed and (Player.enemies == 1 or not Whirlwind:Usable() or Player.rage.current > (Slam:RageCost() + Whirlwind:RageCost())) then
		return Slam
	end
	if Bloodrage:Usable() and Player.rage.current < 30 and not (Player:UnderAttack() or Player:HealthPct() < 60 or BerserkerRage:Up()) then
		UseCooldown(Bloodrage)
	end
	if DeathWish:Usable() and not Slam.wait and (not Target.boss or (Player:TimeInCombat() > 10 and (Target.healthPercentage < 20 or Target.timeToDie < 35 or Target.timeToDie > DeathWish:CooldownDuration() + 40))) then
		UseCooldown(DeathWish)
	end
	if BloodFury:Usable() and not (Player:UnderAttack() or Player:HealthPct() < 60) then
		UseCooldown(BloodFury)
	end
	if Recklessness:Usable() and Target.boss and (Target.healthPercentage < 20 or Target.timeToDie < 25) and (not Rampage.known or Rampage.buff:Remains() > 8) and (Player.enemies == 1 or not SweepingStrikes.known or SweepingStrikes:Ready(Player.gcd) or SweepingStrikes:Remains() > 8) and (not DeathWish.known or DeathWish:Up() or Target.timeToDie < DeathWish:Cooldown() + 20) then
		UseExtra(Recklessness)
	end
	if Rampage:Usable(0, true) and Rampage.buff:Remains() < 3 then
		return Pool(Rampage)
	end
	if SweepingStrikes:Usable(0.5, true) and Player.enemies > 1 then
		UseCooldown(SweepingStrikes)
	end
	if Player.enemies > 1 then
		if Cleave:Usable() and Player.rage.current >= (Player.equipped.twohand and 85 or 55) then
			UseCooldown(Cleave)
		end
	elseif Player.equipped.offhand then
		if HeroicStrike:Usable() and Player.rage.current >= 55 and not Execute:Usable() then
			UseCooldown(HeroicStrike)
		end
	end
	if VictoryRush:Usable() and VictoryRush:React() < Player.gcd then
		return VictoryRush
	end
	if Player.enemies > 1 and not Slam.wait then
		if Whirlwind:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:RageCost() + Whirlwind:RageCost())) then
			return Whirlwind
		end
		if Bloodthirst:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:RageCost() + Bloodthirst:RageCost())) then
			return Bloodthirst
		end
		if MortalStrike:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:RageCost() + MortalStrike:RageCost())) then
			return MortalStrike
		end
		if ShieldSlam:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:RageCost() + ShieldSlam:RageCost())) then
			return ShieldSlam
		end
		if Rampage:Usable() and Rampage.buff:Remains() < 5 then
			return Rampage
		end
		if Execute:Usable() and (Player.equipped.offhand or Recklessness:Up() or (SweepingStrikes:Up() and (not Whirlwind.known or not Whirlwind:Ready(3)))) then
			return Execute
		end
	elseif not Slam.wait then
		if Execute:Usable() and Player.rage.current >= 55 and Player.swing.mh.remains < (Player.gcd * 3 - Opt.slam_cutoff) then
			return Execute
		end
		if Bloodthirst:Usable() and (Player.equipped.twohand or not Execute:Usable()) then
			return Bloodthirst
		end
		if MortalStrike:Usable() and (Player.equipped.twohand or not Execute:Usable()) then
			return MortalStrike
		end
		if ShieldSlam:Usable() then
			return ShieldSlam
		end
		if Whirlwind:Usable() and (Player.equipped.twohand or not Execute:Usable()) then
			return Whirlwind
		end
		if Rampage:Usable() and Rampage.buff:Remains() < 5 then
			return Rampage
		end
		if Execute:Usable() then
			return Execute
		end
	end
	if BerserkerRage:Usable() and Player.rage.current < 45 and Player:UnderAttack() and not Slam.wait then
		UseCooldown(BerserkerRage)
	end
	if Player.enemies > 1 then
		if Cleave:Usable() and Player.rage.current >= 55 then
			UseCooldown(Cleave)
		end
	else
		if HeroicStrike:Usable() and Player.rage.current >= (Player.equipped.twohand and 65 or 55) and not Execute:Usable() then
			UseCooldown(HeroicStrike)
		end
	end
	if VictoryRush:Usable() and not Slam.wait then
		return VictoryRush
	end
	if Slam.use and Slam:Usable() and Player.enemies == 1 and Player.swing.mh.remains > Opt.slam_min_speed and Player.rage.current >= 90 then
		return Slam
	end
end

APL.Buffs = function(self, remains)
	self.bs_mine = BattleShout:Remains(true)
	self.bs_remains = self.bs_mine > 0 and self.bs_mine or BattleShout:Remains()
	self.bs_mine = self.bs_mine > 0
	self.cs_mine = CommandingShout:Remains(true)
	self.cs_remains = self.cs_mine > 0 and self.cs_mine or CommandingShout:Remains()
	self.cs_mine = self.cs_mine > 0
	if Opt.last_shout == 'battle' and BattleShout:Usable() and (self.bs_remains == 0 or (self.bs_mine and self.bs_remains < min(30, remains))) then
		return BattleShout
	end
	if Opt.last_shout == 'commanding' and CommandingShout:Usable() and (self.cs_remains == 0 or (self.cs_mine and self.cs_remains < min(30, remains))) then
		return CommandingShout
	end
	if BattleShout:Usable() and not self.cs_mine and (self.bs_remains == 0 or (self.bs_mine and self.bs_remains < min(30, remains))) then
		return BattleShout
	end
	if Opt.cshout and CommandingShout:Usable() and not self.bs_mine and (self.cs_remains == 0 or (self.cs_mine and self.cs_remains < min(30, remains))) then
		return CommandingShout
	end
	if DemoralizingShout.known and Player:TimeInCombat() > 0 then
		self.ds_mine = DemoralizingShout:Remains(true)
		self.ds_remains = self.ds_mine > 0 and self.ds_mine or max(DemoralizingShout:Remains(), DemoralizingRoar:Remains(), CurseOfWeakness:Remains())
		self.ds_mine = self.ds_mine > 0
		if DemoralizingShout:Usable() and (self.ds_remains == 0 or (self.ds_mine and self.ds_remains < 5)) then
			if Player.stance ~= STANCE.BERSERKER then
				return DemoralizingShout
			elseif Player.rage.current >= 60 or ((not Whirlwind.known or not Whirlwind:Ready(Player.gcd)) and (not Bloodthirst.known or not Bloodthirst:Ready(Player.gcd)) and (not MortalStrike.known or not MortalStrike:Ready(Player.gcd))) then
				return DemoralizingShout
			end
		end
	end
end

APL.Interrupt = function(self)
	if Pummel:Usable() and Player.stance == STANCE.BERSERKER then
		return Pummel
	end
	if ShieldBash:Usable() and (Player.stance == STANCE.BATTLE or Player.stance == STANCE.DEFENSIVE) then
		return ShieldBash
	end
	if Pummel:Usable() then
		return Pummel
	end
	if ShieldBash:Usable() then
		return ShieldBash
	end
	if ConcussionBlow:Usable() then
		return ConcussionBlow
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
		GenerateGlow(_G['StanceButton' .. i])
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
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon and not Player.cd.queued) or
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

function UI:UpdateSwingTimers()
	local text_center, text_tl, text_tr
	local now = GetTime()

	if Opt.swing_timer then
		local mh = Player.swing.mh.next - (now - Player.time_diff)
		local oh = Player.swing.oh.next - (now - Player.time_diff)
		if mh > 0 then
			if Slam.wait then
				text_center = format('SLAM\n%.1fs', mh)
				smashPanel.text.center:SetText(text_center)
			else
				text_tl = format('%.1f', mh)
			end
		end
		if oh > 0 then
			text_tr = format('%.1f', oh)
		end
	end

	smashPanel.text.tl:SetText(text_tl)
	smashPanel.text.tr:SetText(text_tr)
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
	if Player.pool_rage then
		local deficit = Player.pool_rage - UnitPower('player', 1)
		if deficit > 0 then
			text_center = format('POOL\n%d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.cd and Player.cd.queued then
		if not smashCooldownPanel.swingQueueOverlayOn then
			smashCooldownPanel.swingQueueOverlayOn = true
			smashCooldownPanel.border:SetTexture(ADDON_PATH .. 'swingqueue.blp')
		end
	elseif smashCooldownPanel.swingQueueOverlayOn then
		smashCooldownPanel.swingQueueOverlayOn = false
		smashCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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

	smashPanel.dimmer:SetShown(dim)
	smashPanel.text.center:SetText(text_center)
	smashCooldownPanel.text:SetText(text_cd)
	smashCooldownPanel.dimmer:SetShown(dim_cd)
	--smashPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))

	self:UpdateSwingTimers()
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL[Player.stance]:main()
	if Player.main then
		smashPanel.icon:SetTexture(Player.main.icon)
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
		local _, _, _, start, ends = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends = UnitChannelInfo('target')
		end
		if start then
			Player.interrupt = APL.Interrupt()
			smashInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			smashInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		smashInterruptPanel.icon:SetShown(Player.interrupt)
		smashInterruptPanel.border:SetShown(Player.interrupt)
		smashInterruptPanel:SetShown(start)
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
		Opt = SmashConfig
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_Smash1 .. '|r for a list of commands.')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
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
	   e == 'RANGE_DAMAGE' or
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_AURA_REMOVED' or
	   e == 'SPELL_DAMAGE' or
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
	if event == 'PARTY_KILL' and srcGUID == Player.guid then
		VictoryRush:ApplyAura(srcGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			autoAoe:Add(dstGUID, true)
		end
		if Rampage.known and critical then
			Rampage:ApplyAura(srcGUID)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		local npcId = tonumber(srcGUID:match('^%w+-%d+-%d+-%d+-%d+-(%d+)') or 0)
		if npcId > 0 then
			if spellSchool then
				if spellSchool > 1 and Target.npc_swing_types[npcId] ~= spellSchool then
					Target.npc_swing_types[npcId] = spellSchool
				end
			elseif Target.npc_swing_types[npcId] then
				spellSchool = Target.npc_swing_types[npcId]
			end
		end
		if not spellSchool or bit.band(spellSchool, 1) > 0 then
			Player.swing.last_taken_physical = Player.time
		end
		if blocked then
			Revenge:ApplyAura(dstGUID)
		end
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Overpower.known and missType == 'DODGE' then
			Overpower:ApplyAura(dstGUID)
		end
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Revenge.known and (missType == 'BLOCK' or missType == 'DODGE' or missType == 'PARRY') then
			Revenge:ApplyAura(dstGUID)
		end
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, _, _, resisted, blocked, absorbed, critical)
	if event == 'SPELL_MISSED' then
		if srcGUID == Player.guid then
			if Overpower.known and missType == 'DODGE' then
				Overpower:ApplyAura(dstGUID)
			end
		elseif dstGUID == Player.guid then
			if Revenge.known and (missType == 'BLOCK' or missType == 'DODGE' or missType == 'PARRY') then
				Revenge:ApplyAura(dstGUID)
			end
		end
	end

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
		ability:CastSuccess(dstGUID)
		return
	elseif event == 'SPELL_CAST_START' then
		ability:CastStart(dstGUID)
		return
	elseif event == 'SPELL_CAST_FAILED' then
		ability:CastFailed(dstGUID)
		return
	end

	if dstGUID == Player.guid then
		return -- ignore buffs beyond here
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
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'RANGE_DAMAGE' or event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event)
		if Rampage.known and event == 'SPELL_DAMAGE' and critical then
			Rampage:ApplyAura(srcGUID)
		end
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
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

function events:UNIT_POWER_UPDATE(unitID, powerType)
	if unitID == 'player' and powerType == 'RAGE' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_START(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

function events:UNIT_SPELLCAST_SUCCEEDED(unitID, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
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

function events:CURRENT_SPELL_CAST_CHANGED()
	Player.ability_queued = false
	for _, ability in next, abilities.swingQueue do
		ability.queued = false
		for i, spellId in next, ability.spellIds do
			if IsCurrentSpell(spellId) then
				ability.queued = true
				Player.ability_queued = ability
				if Opt.swing_timer then
					smashPanel.text.tl:SetTextColor(0.2, 0.8, 1, 1)
				end
				break
			end
		end
	end
end

function events:SPELL_UPDATE_USABLE()
	if VictoryRush.known and VictoryRush.aura_targets[Player.guid] then
		if IsUsableSpell(VictoryRush.spellId) then
			if not VictoryRush.activated then
				VictoryRush.activated = true
			end
		else
			if VictoryRush.activated then
				VictoryRush.activated = false
				VictoryRush:RemoveAura(Player.guid)
			end
		end
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.previous_gcd = {}
	Player.swing.last_taken = 0
	Player.swing.last_taken_physical = 0
	Target.estimated_range = 30
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
	_, _, _, _, _, _, _, _, equipType = GetItemInfo(GetInventoryItemID('player', 16) or 0)
	Player.equipped.twohand = equipType == 'INVTYPE_2HWEAPON'
	_, _, _, _, _, _, _, _, equipType = GetItemInfo(GetInventoryItemID('player', 17) or 0)
	Player.equipped.offhand = equipType == 'INVTYPE_WEAPON'
	Player.equipped.shield = equipType == 'INVTYPE_SHIELD'

	Player.set_bonus.t4_dps = (Player:Equipped(29019) and 1 or 0) + (Player:Equipped(29020) and 1 or 0) + (Player:Equipped(29021) and 1 or 0) + (Player:Equipped(29022) and 1 or 0) + (Player:Equipped(29023) and 1 or 0)
	Player.set_bonus.t5_dps = (Player:Equipped(30118) and 1 or 0) + (Player:Equipped(30119) and 1 or 0) + (Player:Equipped(30120) and 1 or 0) + (Player:Equipped(30121) and 1 or 0) + (Player:Equipped(30122) and 1 or 0)
	Player.set_bonus.t6_dps = (Player:Equipped(30969) and 1 or 0) + (Player:Equipped(30972) and 1 or 0) + (Player:Equipped(30975) and 1 or 0) + (Player:Equipped(30977) and 1 or 0) + (Player:Equipped(30979) and 1 or 0) + (Player:Equipped(34441) and 1 or 0) + (Player:Equipped(34546) and 1 or 0) + (Player:Equipped(34569) and 1 or 0)

	Player:UpdateAbilities()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(47524)
		end
		smashPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UPDATE_SHAPESHIFT_FORM()
	Player.stance = GetShapeshiftForm()
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
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
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
	if startsWith(msg[1], 'sw') then
		if msg[2] then
			Opt.swing_timer = msg[2] == 'on'
		end
		return Status('Show time remaining until next melee swing (main-hand top-left, off-hand top-right)', Opt.swing_timer)
	end
	if startsWith(msg[1], 'cs') then
		if msg[2] then
			Opt.cshout = msg[2] == 'on'
		end
		return Status('Use Commanding Shout if another warrior uses Battle Shout', Opt.cshout)
	end
	if startsWith(msg[1], 'sl') then
		if msg[2] then
			Opt.slam_min_speed = tonumber(msg[2]) or 1.9
		end
		return Status('Minimum swing speed for using Slam', Opt.slam_min_speed, 'seconds')
	end
	if startsWith(msg[1], 'cu') then
		if msg[2] then
			Opt.slam_cutoff = tonumber(msg[2]) or 1
		end
		return Status('Minimum remaining swing time to use abilities before Slam', Opt.slam_cutoff, 'seconds')
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
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'swing |cFF00C000on|r/|cFFC00000off|r - show time remaining until next melee swing',
		'cshout |cFF00C000on|r/|cFFC00000off|r - use Commanding Shout if another warrior uses Battle Shout',
		'slam |cFFFFD000[seconds]|r  - minimum swing speed for using Slam (default is 1.9 seconds)',
		'cutoff |cFFFFD000[seconds]|r  - minimum remaining swing time to use abilities before Slam (default is 1.0 seconds)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_Smash1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
