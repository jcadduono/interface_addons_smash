local ADDON = 'Smash'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_SMASH = ADDON
BINDING_NAME_SMASH_TARGETMORE = "Toggle Targets +"
BINDING_NAME_SMASH_TARGETLESS = "Toggle Targets -"
BINDING_NAME_SMASH_TARGET1 = "Set Targets to 1"
BINDING_NAME_SMASH_TARGET2 = "Set Targets to 2"
BINDING_NAME_SMASH_TARGET3 = "Set Targets to 3"
BINDING_NAME_SMASH_TARGET4 = "Set Targets to 4"
BINDING_NAME_SMASH_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'WARRIOR' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetActionInfo = _G.GetActionInfo
local GetBindingKey = _G.GetBindingKey
local GetCombatRatingBonus = _G.GetCombatRatingBonus
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetMacroItem = _G.GetMacroItem
local GetMacroSpell = _G.GetMacroSpell
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsCurrentSpell = _G.IsCurrentSpell
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
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

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if uid then
		return tonumber(uid)
	end
	uid = guid:match('^%w+-%d+-(%w+)$')
	if uid then
		return tonumber(uid, 16)
	end
	return 0
end
-- end useful functions

SmashConfig = {}
local Opt -- use this as a local table reference to SmashConfig

SLASH_Smash1, SLASH_Smash2 = '/sm', '/smash'
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
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		keybinds = true,
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
		slam_min_speed = 1.9,
		slam_cutoff = 1,
	})
end

-- UI related functions container
local UI = {}

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
	tracked = {},
	swingQueue = {},
}

-- inventory item template
local InventoryItem, Trinket = {}, {}
InventoryItem.__index = InventoryItem

-- classified inventory items
local InventoryItems = {
	all = {},
	byItemId = {},
}

-- action button template
local Button = {}
Button.__index = Button

-- classified action buttons
local Buttons = {
	all = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

-- timers for updating combat/display/hp info
local Timer = {
	combat = 0,
	display = 0,
	health = 0,
}

-- stance constants
local STANCE = {
	NONE = 0,
	BATTLE = 1,
	DEFENSIVE = 2,
	BERSERKER = 3,
}

-- action priority list container
local APL = {
	[STANCE.NONE] = {},
	[STANCE.BATTLE] = {},
	[STANCE.DEFENSIVE] = {},
	[STANCE.BERSERKER] = {},
}

-- current player information
local Player = {
	initialized = false,
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	stance = STANCE.NONE,
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
		max = 100,
		deficit = 100,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		interruptible = false,
	},
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
		paused = false,
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
	main_freecast = false,
}

-- current target information
local Target = {
	boss = false,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
	npc_swing_types = { -- [uid] = type
	},
}

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

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid > 0 and self.ignored_units[uid] then
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
	for i = #Player.target_modes, 1, -1 do
		if count >= Player.target_modes[i][1] then
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

function Ability:Add(spellId, buff, player)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
		triggers_combat = false,
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
		max_range = 30,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
		keybinds = {},
	}
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if self.Available and not self:Available(seconds) then
		return false
	end
	if not pool then
		if self:Cost() > Player.rage.current then
			return false
		end
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	if self.requires_react and self:React() <= (seconds or 0) then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Active()
	return IsCurrentSpell(self.spellId) or self.last_used > (Player.time - Player.gcd)
end

function Ability:React()
	if self.aura_targets then
		local aura = self.aura_targets[self.aura_target == 'player' and Player.guid or Target.guid]
		if aura then
			return max(0, aura.expires - Player.time - Player.execute_remains)
		end
	end
	return 0
end

function Ability:Remains(mine, offGCD)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter .. (mine and '|PLAYER' or ''))
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (offGCD and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
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

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
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
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:MaxStack()
	return self.max_stack
end

function Ability:Capped(deficit)
	return self:Stack() >= (self:MaxStack() - (deficit or 0))
end

function Ability:Cost()
	return self.rage_cost
end

function Ability:Free()
	return self.rage_cost > 0 and self:Cost() == 0
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
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
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
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
		if self.activated then
			self.activated = false
		end
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
	if Opt.previous then
		smashPreviousPanel.ability = self
		smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		smashPreviousPanel.icon:SetTexture(self.icon)
		smashPreviousPanel:SetShown(smashPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.swing_queue then
		Player:ResetSwing(true, false, event == 'SPELL_MISSED', false)
	end
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
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and smashPreviousPanel.ability == self then
		smashPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT Tracking

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
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
local Attack = Ability:Add({6603}, false, true)
local BerserkerRage = Ability:Add({18499}, true, true)
BerserkerRage.buff_duration = 10
BerserkerRage.cooldown_duration = 30
local Bloodrage = Ability:Add({2687}, true, false)
Bloodrage.cooldown_duration = 60
Bloodrage.buff = Ability:Add({29131}, true, true)
Bloodrage.buff.buff_duration = 10
Bloodrage.buff.tick_interval = 1
local Pummel = Ability:Add({6552, 6554}, false, true)
Pummel.buff_duration = 4
Pummel.cooldown_duration = 10
Pummel.rage_cost = 10
---- Arms
local BattleStance = Ability:Add({2457}, false, true)
BattleStance.cooldown_duration = 1
BattleStance.is_stance = true
local Charge = Ability:Add({100, 6178, 11578}, false, true)
Charge.cooldown_duration = 15
Charge.triggers_combat = true
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
Overpower:Track()
local Rend = Ability:Add({772, 6546, 6547, 6548, 11572, 11573, 11574, 25208}, false, true)
Rend.buff_duration = 9
Rend.rage_cost = 10
Rend.tick_interval = 3
Rend:Track()
local Hamstring = Ability:Add({1715, 7372, 7373, 25212}, false, false)
Hamstring.rage_cost = 10
Hamstring.buff_duration = 15
local Retaliation = Ability:Add({20230}, true, true)
Retaliation.buff_duration = 15
Retaliation.cooldown_duration = 1800
local ThunderClap = Ability:Add({6343, 8198, 8204, 8205, 11580, 11581, 25264}, false, true)
ThunderClap.buff_duration = 10
ThunderClap.cooldown_duration = 4
ThunderClap.rage_cost = 20
ThunderClap:AutoAoe(false)
------ Talents
local AngerManagement = Ability:Add({12296}, true, true)
AngerManagement.tick_interval = 3
local DeathWish = Ability:Add({12292}, true, true)
DeathWish.buff_duration = 30
DeathWish.cooldown_duration = 180
DeathWish.rage_cost = 10
local DeepWounds = Ability:Add({12834, 12849, 12867}, false, true)
DeepWounds.buff_duration = 12
local ImprovedHeroicStrike = Ability:Add({12282, 12663, 12664}, false, true)
local ImprovedRend = Ability:Add({12286, 12658, 12659}, false, true)
local ImprovedThunderClap = Ability:Add({12287, 12665, 12666}, false, true)
local MortalStrike = Ability:Add({12294, 21551, 21552, 21553, 25248, 30330}, false, true)
MortalStrike.rage_cost = 30
MortalStrike.cooldown_duration = 6
local SecondWind = Ability:Add({29834, 29838}, true, true)
SecondWind.buff = Ability:Add({29841, 29842}, true, true)
SecondWind.buff.buff_duration = 10
SecondWind.buff.tick_interval = 2
------ Procs

---- Fury
local BattleShout = Ability:Add({6673, 5242, 6192, 11549, 11550, 11551, 25289, 2048}, true, false)
BattleShout.buff_duration = 120
BattleShout.rage_cost = 10
BattleShout.is_shout = true
local BerserkerStance = Ability:Add({2458}, false, true)
BerserkerStance.cooldown_duration = 1
BerserkerStance.is_stance = true
local Cleave = Ability:Add({845, 7369, 11608, 11609, 20569, 25231}, false, true)
Cleave.rage_cost = 20
Cleave.swing_queue = true
Cleave:AutoAoe(false)
local CommandingShout = Ability:Add({469}, true, false)
CommandingShout.buff_duration = 120
CommandingShout.rage_cost = 10
CommandingShout.is_shout = true
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
VictoryRush:Track()
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
DefensiveStance.is_stance = true
local Disarm = Ability:Add({676}, false, false)
Disarm.buff_duration = 10
Disarm.cooldown_duration = 60
Disarm.rage_cost = 20
local Revenge = Ability:Add({6572, 6574, 7379, 11600, 11601, 25288, 25269, 30357}, true, true)
Revenge.buff_duration = 5 -- use 5 second imaginary buff triggered by block/dodge/parry
Revenge.cooldown_duration = 5
Revenge.rage_cost = 5
Revenge.requires_react = true
Revenge:Track()
Revenge.stun = Ability:Add({12798})
Revenge.stun.buff_duration = 3
local ShieldBash = Ability:Add({72, 1671, 1672, 29704}, false, true)
ShieldBash.cooldown_duration = 12
ShieldBash.rage_cost = 10
local ShieldBlock = Ability:Add({2565}, true, true)
ShieldBlock.cooldown_duration = 5
ShieldBlock.rage_cost = 10
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
SunderArmor.max_stack = 5
-- Trinket Effects
local FieryWeapon = Ability:Add({13897}, false, true)
FieryWeapon.bonus_id = 803
-- End Abilities

-- Start Inventory Items

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
		off_gcd = true,
		keybinds = {},
	}
	setmetatable(item, self)
	InventoryItems.all[#InventoryItems.all + 1] = item
	InventoryItems.byItemId[itemId] = item
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
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
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
Trinket.FigurineOfTheColossus = InventoryItem:Add(27529)
-- End Inventory Items

-- Start Buttons

Buttons.KeybindPatterns = {
	['ALT%-'] = 'a-',
	['CTRL%-'] = 'c-',
	['SHIFT%-'] = 's-',
	['META%-'] = 'm-',
	['NUMPAD'] = 'NP',
	['PLUS'] = '%+',
	['MINUS'] = '%-',
	['MULTIPLY'] = '%*',
	['DIVIDE'] = '%/',
	['BACKSPACE'] = 'BS',
	['BUTTON'] = 'MB',
	['CLEAR'] = 'Clr',
	['DELETE'] = 'Del',
	['END'] = 'End',
	['HOME'] = 'Home',
	['INSERT'] = 'Ins',
	['MOUSEWHEELDOWN'] = 'MwD',
	['MOUSEWHEELUP'] = 'MwU',
	['PAGEDOWN'] = 'PgDn',
	['PAGEUP'] = 'PgUp',
	['CAPSLOCK'] = 'Caps',
	['NUMLOCK'] = 'NumL',
	['SCROLLLOCK'] = 'ScrL',
	['SPACEBAR'] = 'Space',
	['SPACE'] = 'Space',
	['TAB'] = 'Tab',
	['DOWNARROW'] = 'Down',
	['LEFTARROW'] = 'Left',
	['RIGHTARROW'] = 'Right',
	['UPARROW'] = 'Up',
}

function Buttons:Scan()
	if Bartender4 then
		for i = 1, 120 do
			Button:Add(_G['BT4Button' .. i])
		end
		for i = 1, 10 do
			Button:Add(_G['BT4PetButton' .. i])
		end
		return
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				Button:Add(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
		return
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				Button:Add(_G['LUIBarBottom' .. b .. 'Button' .. i])
				Button:Add(_G['LUIBarLeft' .. b .. 'Button' .. i])
				Button:Add(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
		return
	end
	if Dominos then
		for i = 1, 60 do
			Button:Add(_G['DominosActionButton' .. i])
		end
		-- fallthrough because Dominos re-uses Blizzard action buttons
	end
	for i = 1, 12 do
		Button:Add(_G['ActionButton' .. i])
		Button:Add(_G['MultiBarLeftButton' .. i])
		Button:Add(_G['MultiBarRightButton' .. i])
		Button:Add(_G['MultiBarBottomLeftButton' .. i])
		Button:Add(_G['MultiBarBottomRightButton' .. i])
		Button:Add(_G['MultiBar5Button' .. i])
		Button:Add(_G['MultiBar6Button' .. i])
		Button:Add(_G['MultiBar7Button' .. i])
	end
	for i = 1, 10 do
		Button:Add(_G['PetActionButton' .. i])
	end
end

function Button:UpdateGlowDisplay()
	local w, h = self.frame:GetSize()
	self.glow:SetSize(w * 1.4, h * 1.4)
	self.glow:SetPoint('TOPLEFT', self.frame, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
	self.glow:SetPoint('BOTTOMRIGHT', self.frame, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
	self.glow.ProcStartFlipbook:SetVertexColor(Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b)
	self.glow.ProcLoopFlipbook:SetVertexColor(Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b)
	self.glow.ProcStartAnim:Play()
	self.glow:Hide()
end

function Button:UpdateActionID()
	self.action_id = (
		(self.frame._state_type == 'action' and self.frame._state_action) or
		(self.frame.CalculateAction and self.frame:CalculateAction()) or
		(self.frame:GetAttribute('action'))
	) or 0
end

function Button:UpdateAction()
	self.action = nil
	if self.action_id <= 0 then
		return
	end
	local actionType, id, subType = GetActionInfo(self.action_id)
	if id and type(id) == 'number' and id > 0 then
		if actionType == 'item' or (actionType == 'macro' and subType == 'item') then
			self.action = InventoryItems.byItemId[id]
		elseif actionType == 'spell' or (actionType == 'macro' and subType == 'spell') then
			self.action = Abilities.bySpellId[id]
		elseif actionType == 'macro' then
			local spellId = GetMacroSpell(id)
			if type(spellId) == 'number' then
				self.action = Abilities.bySpellId[spellId]
				return
			end
			local itemId, itemLink = GetMacroItem(id)
			if type(itemLink) == 'string' then
				self.action = InventoryItems.byItemId[tonumber(itemLink:match('|Hitem:(%d+)'))]
			end
		end
	end
end

function Button:UpdateKeybind()
	self.keybind = nil
	local bind = self.frame.bindingAction or (self.frame.config and self.frame.config.keyBoundTarget)
	if bind then
		local key = GetBindingKey(bind)
		if key then
			key = key:gsub(' ', ''):upper()
			for pattern, short in next, Buttons.KeybindPatterns do
				key = key:gsub(pattern, short)
			end
			self.keybind = key
			return
		end
	end
end

function Button:Add(actionButton)
	if not actionButton then
		return
	end
	local button = {
		frame = actionButton,
		name = actionButton:GetName(),
		action_id = 0,
		glow = CreateFrame('Frame', nil, actionButton, 'ActionButtonSpellAlertTemplate')
	}
	setmetatable(button, self)
	Buttons.all[#Buttons.all + 1] = button
	button:UpdateActionID()
	button:UpdateAction()
	button:UpdateKeybind()
	button:UpdateGlowDisplay()
	return button
end

-- End Buttons

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.tracked)
	wipe(self.swingQueue)
	for _, ability in next, self.all do
		if ability.known then
			for i, spellId in next, ability.spellIds do
				self.bySpellId[spellId] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.tracked[#self.tracked + 1] = ability
			end
			if ability.swing_queue then
				self.swingQueue[#self.swingQueue + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

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
	if (
		(self.cast.ability and self.cast.ability.triggers_combat) or
		(self.previous_gcd[1] and self.previous_gcd[1].triggers_combat and self.previous_gcd[1]:UsedWithin(Player.gcd))
	) then
		return 0.1
	end
	return 0
end

function Player:ResetSwing(mainHand, offHand, missed, pause)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
		self.swing.mh.next = self.time + self.swing.mh.speed
		if Opt.swing_timer then
			smashPanel.text.tl:SetTextColor(1, missed and 0 or 1, missed and 0 or 1, 1)
		end
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
		self.swing.oh.next = self.time + self.swing.oh.speed
	end
	Player.swing.paused = not not pause
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
	local info
	-- Update spell ranks first
	for _, ability in next, Abilities.all do
		ability.known = false
		ability.spellId = ability.spellIds[1]
		ability.rank = 1
		for i, spellId in next, ability.spellIds do
			if IsPlayerSpell(spellId) then
				ability.known = true
				ability.spellId = spellId -- update spellId to current rank
				ability.rank = i
			end
			if Opt.last_shout == spellId then
				self.last_shout = ability
			elseif Opt.last_stance == spellId then
				self.last_stance = ability
			end
		end
		if ability.bonus_id then -- used for checking enchants and crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		info = GetSpellInfo(ability.spellId)
		if info then
			ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
		end
	end

	Bloodrage.buff.known = Bloodrage.known
	Intercept.stun.known = Intercept.known
	if Rampage.known then
		Rampage.buff.known = true
		Rampage.buff.spellId = Rampage.buff.spellIds[Rampage.rank]
		Rampage.buff.rank = Rampage.rank
	end
	if SecondWind.known then
		SecondWind.buff.known = true
		SecondWind.buff.spellId = SecondWind.buff.spellIds[SecondWind.rank]
		SecondWind.buff.rank = SecondWind.rank
	end
	Slam.use = Slam.known and ImprovedSlam.known and Player.equipped.twohand

	-- Mark specific spells as known if they can be triggered by others
	self.last_shout = self.last_shout or BattleShout
	Opt.last_shout = self.last_shout.spellId
	self.last_stance = self.last_stance or BattleStance
	Opt.last_stance = self.last_stance.spellId

	Abilities:Update()
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		self:ResetSwing(true, true, false, false)
		return
	end
	local ability = Abilities.bySpellId[spellId]
	channel.interrupt_if = ability and ability.interrupt_if
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	channel.ticks_remain = channel.tick_count
	self:ResetSwing(true, true, false, true)
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
	local _, cooldown, start, ends, spellId, speed, max_speed
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.pool_rage = nil
	self:UpdateTime()
	cooldown = GetSpellCooldown(47524)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0

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
		self.channel.ticks = (self.ctime - self.channel.start) / self.channel.tick_interval
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end

	self.rage.current = UnitPower('player', 1)
	if self.cast.ability and self.cast.ability.rage_cost then
		self.rage.current = max(0, self.rage.current - self.cast.ability:Cost())
	end
	self.rage.deficit = max(0, self.rage.max - self.rage.current)

	self.swing.mh.remains = self.swing.paused and self.swing.mh.speed or max(0, self.swing.mh.next - self.time - self.execute_remains)
	self.swing.oh.remains = self.swing.paused and self.swing.oh.speed or max(0, self.swing.oh.next - self.time - self.execute_remains)

	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100

	self:UpdateThreat()

	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.main = APL[self.stance]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
end

function Player:Init()
	local _
	if not self.initialized then
		Buttons:Scan()
		UI:DisableOverlayGlows()
		self.guid = UnitGUID('player')
		self.name = UnitName('player')
		self.initialized = true
	end
	smashPreviousPanel.ability = nil
	_, self.instance = IsInInstance()
	self:SetTargetMode(1)
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:UPDATE_SHAPESHIFT_FORM()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	Events:ACTIONBAR_PAGE_CHANGED()
	Target:Update()
	Player:Update()
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
	self.timeToDieMax = self.health.current / Player.health.max * (
		15 + (Player.equipped.shield and 5 or 0)
	)
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
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
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid)
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.creature_type = UnitCreatureType('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2) and (not Player.instance == 'raid' or (self.health.max > Player.health.max * 10))
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		smashPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:Health()
	local health = self.health.current
	if Player.cast.ability then
		health = health - Player.cast.ability:MinDamage()
	end
	return max(0, health)
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self:Health() - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	return Charge.stun:Up() or Intercept.stun:Up() or Revenge.stun:Up() or ConcussionBlow:Up()
end

function Target:DealsPhysicalDamage()
	if self.uid and Target.npc_swing_types[self.uid] then
		return bit.band(Target.npc_swing_types[self.uid], 1) > 0
	end
	return true
end

-- End Target Functions

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

function Ability:Cost()
	local cost = self.rage_cost
	if FocusedRage.known and FocusedRage.modifies[self] then
		cost = cost - FocusedRage.rank
	end
	return max(0, cost)
end

function HeroicStrike:Cost()
	local cost = Ability.Cost(self)
	if ImprovedHeroicStrike.known then
		cost = cost - ImprovedHeroicStrike.rank
	end
	return max(0, cost)
end

function SunderArmor:Cost()
	local cost = Ability.Cost(self)
	if ImprovedSunderArmor.known then
		cost = cost - ImprovedSunderArmor.rank
	end
	return max(0, cost)
end
Devastate.Cost = SunderArmor.Cost

function ThunderClap:Cost()
	local cost = Ability.Cost(self)
	if ImprovedThunderClap.known then
		cost = cost - floor(1.4 * ImprovedThunderClap.rank)
	end
	return max(0, cost)
end

function ThunderClap:Available()
	return Player.stance == STANCE.BATTLE or Player.stance == STANCE.DEFENSIVE
end

function Execute:Cost()
	local cost = Ability.Cost(self)
	if ImprovedExecute.known then
		cost = cost - floor(2.6 * ImprovedExecute.rank)
	end
	if Player.set_bonus.t6_dps >= 2 then
		cost = cost - 3
	end
	return max(0, cost)
end

function Execute:Available()
	return (
		(Player.stance == STANCE.BATTLE or Player.stance == STANCE.BERSERKER) and
		Target.health.pct < 20
	)
end

function Bloodthirst:Cost()
	local cost = Ability.Cost(self)
	if Player.set_bonus.t5_dps >= 4 then
		cost = cost - 5
	end
	return max(0, cost)
end

function MortalStrike:Cost()
	local cost = Ability.Cost(self)
	if Player.set_bonus.t5_dps >= 4 then
		cost = cost - 5
	end
	return max(0, cost)
end

function Whirlwind:Cost()
	local cost = Ability.Cost(self)
	if Player.set_bonus.t4_dps >= 2 then
		cost = cost - 5
	end
	return max(0, cost)
end

function Charge:Available()
	return Player.stance == STANCE.BATTLE and Player:TimeInCombat() == 0
end

function Rend:Available()
	return (
		(Player.stance == STANCE.BATTLE or Player.stance == STANCE.DEFENSIVE) and
		not (Target.creature_type == 'Mechanical' or Target.creature_type == 'Elemental')
	)
end

function Revenge:Available()
	return Player.stance == STANCE.DEFENSIVE
end

function Overpower:Available()
	return Player.stance == STANCE.BATTLE
end

function VictoryRush:React()
	if not self.activated then
		return 0
	end
	return Ability.React(self)
end

function ConcussionBlow:Available()
	return Target.stunnable and not Target:Stunned()
end

function SweepingStrikes:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	if Opt.auto_aoe and Player.target_mode < 2 then
		Player:SetTargetMode(2)
	end
end

function SweepingStrikes:Available()
	return Player.stance == STANCE.BATTLE or Player.stance == STANCE.BERSERKER
end

function Slam:CastLanded(dstGUID, event)
	Ability.CastLanded(self, dstGUID, event)
	Player:ResetSwing(true, true, event == 'SPELL_MISSED', false)
	self.used_this_swing = true
end

function Slam:FirstInSwing()
	return not (self.used_this_swing or self:Casting())
end

function ShieldBlock:Available()
	return Player.stance == STANCE.DEFENSIVE and Player.equipped.shield
end

function ShieldBash:Available()
	return (
		(Player.stance == STANCE.BATTLE or Player.stance == STANCE.DEFENSIVE) and
		Player.equipped.shield
	)
end

function ShieldSlam:Available()
	return Player.equipped.shield
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
	Player.pool_rage = min(Player.rage.max, ability:Cost() + (extra or 0))
	return ability
end

-- Begin Action Priority Lists

APL[STANCE.NONE].Main = function(self)
	if Player.last_stance:Usable() then
		return Player.last_stance
	end
	return APL:Struggle(0)
end

APL[STANCE.BATTLE].Main = function(self)
	self.rage_pool_amount = max(10,
		(MortalStrike.known and MortalStrike:Ready(Player.gcd * 2) and MortalStrike:Cost() or 0) +
		(Bloodthirst.known and Bloodthirst:Ready(Player.gcd * 2) and Bloodthirst:Cost() or 0) +
		(ShieldSlam.known and ShieldSlam:Ready(Player.gcd * 2) and ShieldSlam:Cost() or 0) +
		(Overpower.known and Player:UnderMeleeAttack() and Overpower:Ready(Player.gcd * 2) and Overpower:Cost() or 0) +
		(SweepingStrikes.known and Player.enemies > 1 and SweepingStrikes:Ready(Player.gcd * 2) and SweepingStrikes:Cost() or 0) +
		(AngerManagement.known and -1 or 0) +
		(Bloodrage.known and Bloodrage.buff:Up() and -1 or 0) +
		(SecondWind.known and SecondWind.buff:Up() and (-2 * SecondWind.rank) or 0)
	)
	Slam.wait = Slam.use and Player.swing.mh.remains < Opt.slam_cutoff and Player.swing.mh.speed > Opt.slam_min_speed and Player.rage.current < 75 and Target.timeToDie > 2
	if Player:TimeInCombat() == 0 then
		local apl = APL:Buffs(self.rage_pool_amount, Target.boss and 180 or 30)
		if apl then return apl end
		if Charge:Usable() then
			return Charge
		end
	else
		local apl = APL:Buffs(self.rage_pool_amount, 10)
		if apl then UseExtra(apl) end
	end
	if Overpower:Usable() then
		return Overpower
	end
	if DefensiveStance.known and Player.equipped.shield and (Player.enemies == 1 or not SweepingStrikes.known or not SweepingStrikes:Ready()) then
		UseExtra(DefensiveStance)
	end
	if Slam.use and Slam:Usable() and Slam:FirstInSwing() and Player.swing.mh.remains > Opt.slam_min_speed and (Player.enemies == 1 or not Whirlwind:Usable() or Player.rage.current > (Slam:Cost() + Whirlwind:Cost())) then
		return Slam
	end
	APL:Cooldowns(self.rage_pool_amount)
	if Rampage:Usable(0, true) and Rampage.buff:Remains() < 3 then
		return Pool(Rampage)
	end
	if SweepingStrikes:Usable(0.5, true) and Player.enemies > 1 then
		UseCooldown(SweepingStrikes)
	end
	if Player.enemies > 1 and Cleave:Usable() and Player.rage.current >= (30 + self.rage_pool_amount + Cleave:Cost()) then
		UseCooldown(Cleave)
	elseif HeroicStrike:Usable() and (not Cleave.known or Player.enemies < 2) and Player.rage.current >= (30 + self.rage_pool_amount + HeroicStrike:Cost()) and not Execute:Usable() then
		UseCooldown(HeroicStrike)
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
		if VictoryRush:Usable() then
			return VictoryRush
		end
	end
	if Slam.use and Slam:Usable() and Player.enemies == 1 and Player.swing.mh.remains > Opt.slam_min_speed and Player.rage.current >= 90 then
		return Slam
	end
	if BerserkerStance:Usable() and Whirlwind.known and not Player.equipped.shield and Player.rage.current < (self.rage_pool_amount + 10) and Whirlwind:Ready(2) and Overpower:React() == 0 then
		UseCooldown(BerserkerStance)
	end
	if not Slam.wait then
		return APL:Struggle(self.rage_pool_amount)
	end
end

APL[STANCE.DEFENSIVE].Main = function(self)
	self.rage_pool_amount = max(10,
		(MortalStrike.known and MortalStrike:Ready(Player.gcd * 2) and MortalStrike:Cost() or 0) +
		(Bloodthirst.known and Bloodthirst:Ready(Player.gcd * 2) and Bloodthirst:Cost() or 0) +
		(ShieldSlam.known and ShieldSlam:Ready(Player.gcd * 2) and ShieldSlam:Cost() or 0) +
		(Revenge.known and Player:UnderMeleeAttack() and Revenge:Ready(Player.gcd * 2) and Revenge:Cost() or 0) +
		(AngerManagement.known and -1 or 0) +
		(Bloodrage.known and Bloodrage.buff:Up() and -1 or 0) +
		(SecondWind.known and SecondWind.buff:Up() and (-2 * SecondWind.rank) or 0)
	)
	Slam.wait = false
	if Player:TimeInCombat() == 0 then
		local apl = APL:Buffs(self.rage_pool_amount, Target.boss and 180 or 30)
		if apl then return apl end
		if Charge:Ready(2) and Player.rage.current < 30 then
			UseExtra(BattleStance)
		end
		if Bloodrage:Usable() then
			UseCooldown(Bloodrage)
		end
	else
		local apl = APL:Buffs(self.rage_pool_amount, 10)
		if apl then UseExtra(apl) end
	end
	if ShieldBlock:Usable() and Player.rage.current >= (self.rage_pool_amount + ShieldBlock:Cost()) and Player:UnderMeleeAttack(true) and ShieldBlock:Down() then
		UseCooldown(ShieldBlock)
	end
	if Taunt:Usable() and Player.threat.status < 3 and UnitAffectingCombat('target') then
		UseCooldown(Taunt)
	end
	APL:Cooldowns(self.rage_pool_amount)
	if Player.enemies > 1 and Cleave:Usable() and Player.rage.current >= (20 + self.rage_pool_amount + Cleave:Cost()) then
		UseCooldown(Cleave)
	elseif HeroicStrike:Usable() and (not Cleave.known or Player.enemies < 2) and Player.rage.current >= (20 + self.rage_pool_amount + HeroicStrike:Cost()) then
		UseCooldown(HeroicStrike)
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
	if ThunderClap:Usable() and Player.enemies >= (4 - (ImprovedThunderClap.rank >= 3 and 1 or 0)) then
		return ThunderClap
	end
	if Revenge:Usable(0, true) then
		return Pool(Revenge)
	end
	if ShieldSlam:Usable(0.5, true) then
		return Pool(ShieldSlam)
	end
	if ThunderClap:Usable(0.5, true) and (
		(ImprovedThunderClap.rank >= 3 and Player.enemies > (1 + (Cleave.known and 1 or 0))) or
		ThunderClap:Remains() < 2
	) then
		return Pool(ThunderClap)
	end
	if Bloodthirst:Usable(0, true) then
		return Bloodthirst
	end
	if MortalStrike:Usable(0, true) then
		return MortalStrike
	end
	if Devastate:Usable() and (
		Player.rage.current >= (self.rage_pool_amount + Devastate:Cost()) or
		(SunderArmor:Stack() >= 3 and SunderArmor:Remains() < 5)
	) then
		return Devastate
	end
	return APL:Struggle(self.rage_pool_amount)
end

APL[STANCE.BERSERKER].Main = function(self)
	self.rage_pool_amount = max(10,
		(MortalStrike.known and MortalStrike:Ready(Player.gcd * 2) and MortalStrike:Cost() or 0) +
		(Bloodthirst.known and Bloodthirst:Ready(Player.gcd * 2) and Bloodthirst:Cost() or 0) +
		(ShieldSlam.known and ShieldSlam:Ready(Player.gcd * 2) and ShieldSlam:Cost() or 0) +
		(Whirlwind.known and Whirlwind:Ready(Player.gcd * 2) and Whirlwind:Cost() or 0) +
		(SweepingStrikes.known and Player.enemies > 1 and SweepingStrikes:Ready(Player.gcd * 2) and SweepingStrikes:Cost() or 0) +
		(AngerManagement.known and -1 or 0) +
		(Bloodrage.known and Bloodrage.buff:Up() and -1 or 0) +
		(SecondWind.known and SecondWind.buff:Up() and (-2 * SecondWind.rank) or 0)
	)
	Slam.wait = Slam.use and Player.swing.mh.remains < Opt.slam_cutoff and Player.swing.mh.speed > Opt.slam_min_speed and Player.rage.current < 75 and Target.timeToDie > 2
	if Player:TimeInCombat() == 0 then
		local apl = APL:Buffs(self.rage_pool_amount, Target.boss and 180 or 30)
		if apl then return apl end
		if Intercept:Usable() then
			return Intercept
		end
		if Charge:Ready(0.5) and Player.rage.current < 20 then
			UseExtra(BattleStance)
		end
	elseif not Slam.wait then
		local apl = APL:Buffs(self.rage_pool_amount, 10)
		if apl then UseExtra(apl) end
	end
	if Slam.use and Slam:Usable() and Slam:FirstInSwing() and Player.swing.mh.remains > Opt.slam_min_speed and (Player.enemies == 1 or not Whirlwind:Usable() or Player.rage.current > (Slam:Cost() + Whirlwind:Cost())) then
		return Slam
	end
	APL:Cooldowns(self.rage_pool_amount)
	if Rampage:Usable(0, true) and Rampage.buff:Remains() < 3 then
		return Pool(Rampage)
	end
	if SweepingStrikes:Usable(0.5, true) and Player.enemies > 1 then
		UseCooldown(SweepingStrikes)
	end
	if Player.enemies > 1 and Cleave:Usable() and Player.rage.current >= (30 + self.rage_pool_amount + Cleave:Cost()) then
		UseCooldown(Cleave)
	elseif HeroicStrike:Usable() and (not Cleave.known or Player.enemies < 2) and Player.rage.current >= (30 + self.rage_pool_amount + HeroicStrike:Cost()) and not Execute:Usable() then
		UseCooldown(HeroicStrike)
	end
	if VictoryRush:Usable() and VictoryRush:React() < Player.gcd then
		return VictoryRush
	end
	if Player.enemies > 1 and not Slam.wait then
		if Whirlwind:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:Cost() + Whirlwind:Cost())) then
			return Whirlwind
		end
		if Bloodthirst:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:Cost() + Bloodthirst:Cost())) then
			return Bloodthirst
		end
		if MortalStrike:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:Cost() + MortalStrike:Cost())) then
			return MortalStrike
		end
		if ShieldSlam:Usable() and (not SweepingStrikes.known or not SweepingStrikes:Ready(2) or Player.rage.current >= (SweepingStrikes:Cost() + ShieldSlam:Cost())) then
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
	if VictoryRush:Usable() and not Slam.wait then
		return VictoryRush
	end
	if Slam.use and Slam:Usable() and Player.enemies == 1 and Player.swing.mh.remains > Opt.slam_min_speed and Player.rage.current >= 90 then
		return Slam
	end
	if BattleStance:Usable() and Player.rage.current < self.rage_pool_amount and Overpower:React() > 2 then
		UseCooldown(BattleStance)
	end
	return APL:Struggle(self.rage_pool_amount)
end

APL.Cooldowns = function(self, pool)
	if Bloodrage:Usable() and Player.rage.current < pool and Player.health.pct >= (50 + (Player:UnderAttack() and 25 or 0)) and not (Player:UnderAttack() and BerserkerRage:Up()) then
		UseCooldown(Bloodrage)
	end
	if DeathWish:Usable() and not Slam.wait and (
		(Recklessness.known and Recklessness:Up()) or (
			Player.rage.current >= (pool + DeathWish:Cost()) and (
				not Target.boss or
				(Player:TimeInCombat() > 10 and (Target.health.pct < 20 or Target.timeToDie < 35 or Target.timeToDie > DeathWish:CooldownDuration() + 40))
			)
		)
	) then
		UseCooldown(DeathWish)
	end
	if BloodFury:Usable() and Player.health.pct >= (50 + (Player:UnderAttack() and 25 or 0)) then
		UseCooldown(BloodFury)
	end
	if Recklessness:Usable() and Target.boss and (Target.health.pct < 20 or Target.timeToDie < 25) and (not Rampage.known or Rampage.buff:Remains() > 8) and (Player.enemies == 1 or not SweepingStrikes.known or SweepingStrikes:Ready(Player.gcd) or SweepingStrikes:Remains() > 8) and (not DeathWish.known or DeathWish:Up() or Target.timeToDie < DeathWish:Cooldown() + 20) then
		UseExtra(Recklessness)
	end
end

APL.Buffs = function(self, pool, remains)
	self.bs_mine = BattleShout:Remains(true)
	self.bs_remains = self.bs_mine > 0 and self.bs_mine or BattleShout:Remains()
	self.bs_mine = self.bs_mine > 0
	self.cs_mine = CommandingShout:Remains(true)
	self.cs_remains = self.cs_mine > 0 and self.cs_mine or CommandingShout:Remains()
	self.cs_mine = self.cs_mine > 0
	if Player.last_shout == BattleShout and BattleShout:Usable() and (self.bs_remains == 0 or (self.bs_mine and self.bs_remains < min(30, remains))) then
		return BattleShout
	end
	if Player.last_shout == CommandingShout and CommandingShout:Usable() and (self.cs_remains == 0 or (self.cs_mine and self.cs_remains < min(30, remains))) then
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
		if DemoralizingShout:Usable() and Player.rage.current >= (pool + DemoralizingShout:Cost()) and (
			(self.ds_remains == 0 and (Player.equipped.shield or Player.stance == STANCE.DEFENSIVE or Player:UnderMeleeAttack())) or
			(self.ds_mine and self.ds_remains < 5)
		) then
			return DemoralizingShout
		end
	end
	if Bloodrage:Usable() and Player.rage.current < 10 and Player:TimeInCombat() == 0 and Player.last_shout:Remains() < min(30, remains) then
		return Bloodrage
	end
end

APL.Struggle = function(self, pool)
	if ThunderClap:Usable() and Player.rage.current >= (pool + ThunderClap:Cost()) and (
		(ImprovedThunderClap.rank >= 3 and (Player.enemies >= (2 + (Cleave.known and 1 or 0)) or (Player:UnderMeleeAttack() and ThunderClap:Remains() < 2))) or
		(Player.enemies >= (4 - (ImprovedThunderClap.rank >= 3 and 2 or 0)) and Player.rage.current >= (pool + ThunderClap:Cost() + (Cleave.known and Cleave:Cost() or 0)))
	) then
		return ThunderClap
	end
	if not Devastate.known and SunderArmor:Usable() and ((SunderArmor:Stack() >= 3 and SunderArmor:Remains() < min(5, Target.timeToDie)) or (Target.timeToDie > 18 and Player.rage.current >= (pool + SunderArmor:Cost()) and not SunderArmor:Capped())) then
		return SunderArmor
	end
	if FieryWeapon.known and Hamstring:Usable() and Player.rage.current >= (pool + Hamstring:Cost()) then
		return Hamstring
	end
	if ImprovedRend.known and Rend:Usable() and (not Cleave.known or Player.enemies < 2) and Rend:Down() and Player.rage.current >= (pool + Rend:Cost()) and Target.timeToDie > (Rend:TickTime() * 3) then
		return Rend
	end
	if Player.enemies > 1 and Cleave:Usable() and Player.rage.current >= (pool + Cleave:Cost()) then
		UseCooldown(Cleave)
	elseif HeroicStrike:Usable() and (not Cleave.known or Player.enemies < 2) and Player.rage.current >= (pool + HeroicStrike:Cost()) and not Execute:Usable() then
		UseCooldown(HeroicStrike)
	end
	if Attack:Usable() and not Attack:Active() then
		return Attack
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

-- Start UI Functions

function UI:DisableOverlayGlows()
	if not Opt.glow.blizzard then
		SetCVar('assistedCombatHighlight', 0)
	end
	if Opt.glow.blizzard or not LibStub then
		return
	end
	local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
	if lib then
		lib.ShowOverlayGlow = function(...)
			return lib.HideOverlayGlow(...)
		end
	end
end

function UI:UpdateGlows()
	for _, button in next, Buttons.all do
		if button.action and button.frame:IsVisible() and (
			(Opt.glow.main and button.action == Player.main) or
			(Opt.glow.cooldown and button.action == Player.cd) or
			(Opt.glow.interrupt and button.action == Player.interrupt) or
			(Opt.glow.extra and button.action == Player.extra)
		) then
			if not button.glow:IsVisible() then
				button.glow:Show()
				if Opt.glow.animation then
					button.glow.ProcStartAnim:Play()
				else
					button.glow.ProcLoop:Play()
				end
			end
		elseif button.glow:IsVisible() then
			if button.glow.ProcStartAnim:IsPlaying() then
				button.glow.ProcStartAnim:Stop()
			end
			if button.glow.ProcLoop:IsPlaying() then
				button.glow.ProcLoop:Stop()
			end
			button.glow:Hide()
		end
	end
end

function UI:UpdateBindings()
	for _, item in next, InventoryItems.all do
		wipe(item.keybinds)
	end
	for _, ability in next, Abilities.all do
		wipe(ability.keybinds)
	end
	for _, button in next, Buttons.all do
		if button.action and button.keybind then
			button.action.keybinds[#button.action.keybinds + 1] = button.keybind
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	smashPanel:SetMovable(not Opt.snap)
	smashPreviousPanel:SetMovable(not Opt.snap)
	smashCooldownPanel:SetMovable(not Opt.snap)
	smashInterruptPanel:SetMovable(not Opt.snap)
	smashExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		smashPanel:SetUserPlaced(true)
		smashPreviousPanel:SetUserPlaced(true)
		smashCooldownPanel:SetUserPlaced(true)
		smashInterruptPanel:SetUserPlaced(true)
		smashExtraPanel:SetUserPlaced(true)
	end
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
	smashPanel.text:SetScale(Opt.scale.main)
	smashPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	smashCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	smashCooldownPanel.text:SetScale(Opt.scale.cooldown)
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
	self:UpdateGlows()
end

function UI:Reset()
	smashPanel:ClearAllPoints()
	smashPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, border_cd, dim, dim_cd, text_center, text_tl, text_tr, text_cd_center, text_cd_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main_freecast then
			border = 'freecast'
		end
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Opt.keybinds then
			for _, bind in next, Player.main.keybinds do
				text_tr = bind
				break
			end
		end
	end
	if Player.cd then
		if Player.cd.queued then
			border_cd = 'swingqueue'
		end
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
		if Opt.keybinds then
			for _, bind in next, Player.cd.keybinds do
				text_cd_tr = bind
				break
			end
		end
	end
	if Player.pool_rage then
		local deficit = Player.pool_rage - UnitPower('player', 1)
		if deficit > 0 then
			text_center = format('POOL\n%d', deficit)
			dim = Opt.dimmer
		end
	end
	if Opt.swing_timer then
		local mh = Player.swing.paused and 0 or Player.swing.mh.next - (GetTime() - Player.time_diff)
		if mh > 0 or Player.ability_queued then
			text_tl = format('%.1f', max(0, mh))
		end
	end
	if border ~= smashPanel.border.overlay then
		smashPanel.border.overlay = border
		smashPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end
	if border_cd ~= smashCooldownPanel.border.overlay then
		smashCooldownPanel.border.overlay = border_cd
		smashCooldownPanel.border:SetTexture(ADDON_PATH .. (border_cd or 'border') .. '.blp')
	end

	smashPanel.dimmer:SetShown(dim)
	smashPanel.text.center:SetText(text_center)
	smashPanel.text.tl:SetText(text_tl)
	smashPanel.text.tr:SetText(text_tr)
	--smashPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	smashCooldownPanel.dimmer:SetShown(dim_cd)
	smashCooldownPanel.text.center:SetText(text_cd_center)
	smashCooldownPanel.text.tr:SetText(text_cd_tr)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		smashPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = Player.main:Free()
	end
	if Player.cd then
		smashCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			smashCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
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
		Opt = SmashConfig
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_Smash1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
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
	   e == 'RANGE_DAMAGE' or
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
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
	local uid = ToUID(dstGUID)
	if uid <= 0 then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
	if event == 'PARTY_KILL' and srcGUID == Player.guid then
		VictoryRush:ApplyAura(srcGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, false, false)
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
		if Rampage.known and critical then
			Rampage:ApplyAura(srcGUID)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		local uid = ToUID(srcGUID)
		if uid > 0 then
			if spellSchool then
				if spellSchool > 1 and Target.npc_swing_types[uid] ~= spellSchool then
					Target.npc_swing_types[uid] = spellSchool
				end
			elseif Target.npc_swing_types[uid] then
				spellSchool = Target.npc_swing_types[uid]
			end
		end
		if not spellSchool or bit.band(spellSchool, 1) > 0 then
			Player.swing.last_taken_physical = Player.time
		end
		if blocked then
			Revenge:ApplyAura(dstGUID)
		end
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true, false)
		if Overpower.known and missType == 'DODGE' then
			Overpower:ApplyAura(dstGUID)
		end
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Revenge.known and (missType == 'BLOCK' or missType == 'DODGE' or missType == 'PARRY') then
			Revenge:ApplyAura(dstGUID)
		end
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType, resisted, blocked, absorbed, critical)
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

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
--[[
		if not UnknownSpell[event] then
			UnknownSpell[event] = {}
		end
		if not UnknownSpell[event][spellId] then
			UnknownSpell[event][spellId] = true
			log(format('%.3f EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d FROM %s ON %s', Player.time, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0, srcGUID, dstGUID))
		end
]]
		return
	end
	--log(format('%.3f EVENT %s TRACK CHECK %s ID %d FROM %s ON %s', Player.time, event, ability.name, spellId, srcGUID, dstGUID))

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED' then
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
			if ability.is_shout then
				Player.last_shout = ability
				Opt.last_shout = ability.spellId
			elseif ability.is_stance then
				Player.last_stance = ability
				Opt.last_stance = ability.spellId
			end
		end
		return -- ignore buffs beyond here
	end
	if event == 'RANGE_DAMAGE' or event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
		if Rampage.known and event == 'SPELL_DAMAGE' and critical then
			Rampage:ApplyAura(srcGUID)
		end
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
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitEffectiveLevel(unitId)
		Player.rage.max = UnitPowerMax('player', 1)
	end
end

function Events:UNIT_POWER_UPDATE(unitId, powerType)
	if unitId == 'player' and powerType == 'RAGE' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:ResetSwing(true, true, false, true)
	end
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:ResetSwing(true, true, true, false)
	end
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_FAILED(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

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

function Events:CURRENT_SPELL_CAST_CHANGED()
	Player.ability_queued = false
	for _, ability in next, Abilities.swingQueue do
		ability.queued = false
		for _, spellId in next, ability.spellIds do
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

function Events:SPELL_UPDATE_USABLE()
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

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Player.swing.last_taken_physical = 0
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
	for _, i in next, InventoryItems.all do
		i.name, _, _, _, _, _, _, _, equipType, i.icon = GetItemInfo(i.itemId or 0)
		i.can_use = i.name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, i.equip_slot = Player:Equipped(i.itemId)
			if i.equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', i.equip_slot)
			end
			i.can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[i.itemId] then
			i.can_use = false
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

	Player:UpdateKnown()
end

function Events:SPELLS_CHANGED()
	Player:UpdateKnown()
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(47524)
		end
		smashPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:UPDATE_SHAPESHIFT_FORM()
	local stance = GetShapeshiftFormID() or 0
	Player.stance = (
		(stance == 17 and STANCE.BATTLE) or
		(stance == 18 and STANCE.DEFENSIVE) or
		(stance == 19 and STANCE.BERSERKER)
	)
end

function Events:ACTIONBAR_SLOT_CHANGED(slot)
	for _, button in next, Buttons.all do
		if not slot or button.action_id == slot then
			button:UpdateAction()
		end
	end
	UI:UpdateBindings()
	UI:UpdateGlows()
end

function Events:ACTIONBAR_PAGE_CHANGED()
	C_Timer.After(0, function()
		Events:ACTIONBAR_SLOT_CHANGED()
	end)
end
Events.UPDATE_BONUS_ACTIONBAR = Events.ACTIONBAR_PAGE_CHANGED

function Events:UPDATE_BINDINGS()
	UI:UpdateBindings()
end
Events.GAME_PAD_ACTIVE_CHANGED = Events.UPDATE_BINDINGS

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
	log(desc .. ':', opt_view, ...)
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
				for _, button in next, Buttons.all do
					button:UpdateGlowDisplay()
				end
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
				for _, button in next, Buttons.all do
					button:UpdateGlowDisplay()
				end
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
	if startsWith(msg[1], 'key') or startsWith(msg[1], 'bind') then
		if msg[2] then
			Opt.keybinds = msg[2] == 'on'
		end
		return Status('Show keybinding text on main ability icon (topright)', Opt.keybinds)
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
		return Status('Show time remaining until next melee swing (top-left)', Opt.swing_timer)
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
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
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
		'keybind |cFF00C000on|r/|cFFC00000off|r - show keybinding text on main ability icon (topright)',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'swing |cFF00C000on|r/|cFFC00000off|r - show time remaining until next melee swing (top-left)',
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
