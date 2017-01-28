local _G, _M = getfenv(0), {}
setfenv(1, setmetatable(_M, {__index=_G}))

local MAXATTACKFRAMES = 7

local ANCHOR = CreateFrame('Frame', nil, UIParent)
ANCHOR:SetWidth(160)
ANCHOR:SetHeight(18 * MAXATTACKFRAMES)
ANCHOR:SetPoint('TOP', 0, -3)
ANCHOR:SetMovable(true)
ANCHOR:SetClampedToScreen(true)
ANCHOR:SetScript('OnEvent', function () Event() end)
ANCHOR:RegisterEvent'PLAYER_LOGIN'

local ROOT
local BOTTOM
local FRAMES = {}
local DATA = setmetatable({}, {__index=function(self, key) self[key] = {}; return self[key] end})

local PATTERNS = {
	"(.+)'s (.+) hits .+ for %d+%.",
	"(.+)'s (.+) crits .+ for %d+%.",
	"(.+)'s (.+) hits %s for %d+ .+ damage%.",
	"(.+)'s (.+) crits %s for %d+ .+ damage%.",
	"(.+) begins to cast (.+)%.",
	"(.+) casts (.+)%.",
	"(.+) casts (.+) on .+%.",
	"(.+) begins to perform (.+)%.",
	"(.+) performs (.+)%.",
	"(.+) performs (.+) on .+%.",
	"(.+)'s (.+) drains %d+ .+ from .+%.",
	"(.+)'s (.+) is absorbed by .+%.",
	"You absorb (.+)'s (.+)%.",
	"You parry (.+)'s (.+)",
	"(.+)'s (.+) was parried%.",
	"(.+)'s (.+) was parried by .+%.",
	"(.+)'s (.+) was blocked%.",
	"(.+)'s (.+) was blocked by .+%.",
	"(.+)'s (.+) was deflected%.",
	"(.+)'s (.+) was deflected by .+%.",
	"(.+)'s (.+) was dodged%.",
	"(.+)'s (.+) was dodged by .+%.",
	"(.+)'s (.+) was evaded%.",
	"(.+)'s (.+) was evaded by .+%.",
	"(.+)'s (.+) fails%. .+ is immune%.",
	"(.+)'s (.+) failed%. You are immune%.",
	"(.+)'s (.+) missed .+%.",
	"(.+)'s (.+) misses you%.",
	"(.+)'s (.+) was resisted%.",
	"(.+)'s (.+) was resisted by .+%.",	
	"(.+)'s (.+) causes .+ %d+ damage%.",
	"(.+) gains %d+ extra attacks? through (.+)%.",

	"(.+) falls and loses %d+ health%.",
	"(.+) hits .+ for %d+%.",
	"(.+) crits .+ for %d+%.",
	"(.+) suffers %d+ points of fire damage%.",
	"(.+) loses %d+ health for swimming in lava%.",
	"(.+) misses .+%.",
	"(.+) attacks.+",
	"(.+) interrupts your .+%.",
	"(.+) interrupts .+'s .+%.",
	"(.+) fails to dispel your .+%.",
	"(.+) fails to dispel .+'s .+%.",
	--"%s is killed by %s.",
}

local DEATH_PATTERNS = {
	"(.+) dies%.",
	"(.+) is slain by .+!",
	"You have slain (.+)!",
	"(.+) is destroyed%.",
}

local BUFF_PATTERNS = {
	"(.+) gains %d+ .+ from (.+)'s (.+)%.",
	"(.+) gains (.+) %(%d+%)%.",
	"(.+) gains (.+)%.",

	"(.+)'s (.+) heals (.+) for %d+%.",
	"(.+)'s (.+) critically heals (.+) for %d+%.",
	"(.+) gains %d+ extra attacks? through (.+)%.",
	"(.+)'s (.+) failed%. You are immune%.",
	"(.+)'s (.+) fails%. (.+) is immune%.",
	"(.+)'s (.+) was resisted by (.+)%.",
	"(.+)'s (.+) was resisted%.",
	"(.+) begins to cast (.+)%.",
	"(.+) casts (.+)%.",
	"(.+) casts (.+) on (.+)%.",
	"(.+) casts (.+) on (.+)'s .+%.",
	"(.+) begins to perform (.+)%.",
	"(.+) performs (.+)%.",
	"(.+) performs (.+) on (.+)%.",
	"(.+) fails to dispel (.+)'s .+%.",
	"(.+)'s (.+) missed (.+)%.",
	"(.+)'s (.+) drains %d+ .+ from .+%. .+ gains %d+ .+%.",
}
local SPLL_HEALCRIT = "(.+)%'s (.+) critically heals (.+) for (%d+)%a%."
local SPLL_HEAL = "(.+)%'s (.+) heals (.+) for (%d+)%."
local SPLL_CAST = "(.+) casts (.+) on (.+)%."
local SPLL_CASTS = "(.+) casts (.+) on (.+)%'s .+%."
local SPLL_CASTS2 = "(.+) casts (.+)%."
local SPLL_GAINS = "(.+) gains (.+)%."
local SPLL_GAINS2 = "(.+) gains.+"
local SPLL_BPERFORM = "(.+) begins to perform (.+)%."
local SPLL_BCAST = "(.+) begins to cast (.+)%."

_G.TargetFrame_OnShow = function() end
_G.TargetFrame_OnHide = CloseDropDownMenus
do
	local orig = UIErrorsFrame_OnEvent
	function _G.UIErrorsFrame_OnEvent(event, msg)
	    if msg == ERR_UNIT_NOT_FOUND then
	        return
	    end
	    orig(event, msg)
	end
end

function SetEffectiveScale(frame, scale, parentframe)
    local parent = getglobal(parentframe)
    if parent then
        scale = scale / GetEffectiveScale(parent)
    end
    frame:SetScale(scale)
end

function Setup()
	ROOT = CreateFrame('Frame', nil, ANCHOR)
	ROOT:SetWidth(1)
	ROOT:SetHeight(1)
	ROOT:SetPoint('TOP', 0, 1)
	BOTTOM = ROOT
	for i = 1, MAXATTACKFRAMES do
		local f = CreateFrame('Frame', nil, ANCHOR)
		f:EnableMouse(true)
		f:SetScript('OnUpdate', OnUpdate)
		f:SetScript('OnMouseDown', function()
			ANCHOR:StartMoving()
		end)
		f:SetScript('OnMouseUp', function()
			OnClick()
			ANCHOR:StopMovingOrSizing()
			enemybars_settings.framePos_L = ANCHOR:GetLeft()
			enemybars_settings.framePos_T = ANCHOR:GetTop()
		end)
		f:SetWidth(160)
		f:SetHeight(18)
		f:RegisterForDrag'LeftButton'
		f:SetID(i)
		f:Hide()
		f.rank = f:CreateTexture(nil, 'BACKGROUND')
		f.rank:SetWidth(15)
		f.rank:SetHeight(15)
		f.rank:SetPoint('RIGHT', f, 'LEFT', -4.5, 0)
		local portrait = f:CreateTexture(nil, 'BACKGROUND')
		portrait:SetWidth(18)
		portrait:SetHeight(18)
		portrait:SetPoint('LEFT', 0, 0)
		portrait:SetTexture[[Interface\InventoryItems\WoWUnknownItem01]]
		portrait:SetTexCoord(.17, .83, .17, .83)
		f.health = CreateFrame('StatusBar', nil, f)
		f.health:EnableMouse(false)
		f.health:SetPoint('TOPLEFT', portrait, 'TOPRIGHT', 0, 0)
		f.health:SetPoint('BOTTOMRIGHT', 0, 0)
		f.health:SetStatusBarTexture[[Interface\Addons\enemybars\Minimalist]]
		f.health:SetBackdrop{bgFile=[[Interface\Tooltips\UI-Tooltip-Background]]}
		f.name = f.health:CreateFontString()
		f.name:SetWidth(154)
		f.name:SetPoint('LEFT', 3, .5)
		f.name:SetJustifyH'LEFT'
		f.name:SetFont([[Fonts\FRIZQT__.TTF]], 11)
		f.name:SetShadowOffset(1, -1)
		f.level = f.health:CreateFontString()
		f.level:SetWidth(154)
		f.level:SetPoint('RIGHT', -3, .5)
		f.level:SetJustifyH'RIGHT'
		f.level:SetFont([[Fonts\FRIZQT__.TTF]], 12)
		f.level:SetShadowOffset(1, -1)
		f.flash = CreateFrame('Frame', nil, f)
		f.flash:SetWidth(180)
		f.flash:SetHeight(70)
		f.flash:SetPoint('CENTER', 0, -7)
		f.flash:Hide()
		local flash = f.flash:CreateTexture(nil, 'OVERLAY')
		flash:SetTexture[[Interface\Buttons\UI-DialogBox-Button-Highlight]]
		flash:SetBlendMode'ADD'
		flash:SetAllPoints()
		portrait:SetTexCoord(.17, .83, .17, .83)
		FRAMES[f] = true
	end

	this:RegisterEvent'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE'
	this:RegisterEvent'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS'
	this:RegisterEvent'CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE'
	this:RegisterEvent'CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF'
	this:RegisterEvent'CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS'
	this:RegisterEvent'CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES'
	this:RegisterEvent'CHAT_MSG_COMBAT_HOSTILE_DEATH'

	this:RegisterEvent'UPDATE_MOUSEOVER_UNIT'
	this:RegisterEvent'PLAYER_TARGET_CHANGED'

	SLASH_ENEMYBARS1 = '/enemybars'
	SlashCmdList.ENEMYBARS = SlashCommand
	
	enemybars_settings = enemybars_settings or {}
	if enemybars_settings.framepos_L or enemybars_settings.framepos_T then
		ANCHOR:SetPoint('TOPLEFT', 'UIParent', 'BOTTOMLEFT', enemybars_settings.framepos_L, enemybars_settings.framepos_T)
	end
	enemybars_settings.scale = enemybars_settings.scale or 1
	SetEffectiveScale(ANCHOR, enemybars_settings.scale, UIParent)

	DEFAULT_CHAT_FRAME:AddMessage'enemybars Loaded (/enemybars for options)'
end

function Event()
	if event == 'PLAYER_LOGIN' then
		Setup()
	elseif event == 'UPDATE_MOUSEOVER_UNIT' then
		if UnitIsEnemy('player', 'mouseover') and UnitPlayerControlled'mouseover' and not UnitIsDead'mouseover' then
			CaptureEvent(UnitName'mouseover')
		end
	elseif event == 'PLAYER_TARGET_CHANGED' then
		if UnitIsEnemy('player', 'target') and UnitPlayerControlled'target' and not UnitIsDead'target' then
			CaptureEvent(UnitName'target')
		end
	elseif event == 'CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS' or event == 'CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES' or event == 'CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE' then
		for _, pattern in PATTERNS do
			for unitName, spell in string.gfind(arg1, pattern) do
				CaptureEvent(unitName, spell)
			end
		end
	elseif event == 'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE' then
	elseif event == 'CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF' or event == 'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS' then
		for unitName, spell, targetName, damage in string.gfind(arg1, SPLL_HEALCRIT) do
			CaptureEvent(unitName, spell)
			CaptureEvent(targetName)	
		end
		for unitName, spell, targetName, damage in string.gfind(arg1, SPLL_HEAL) do
			CaptureEvent(unitName, spell)
			CaptureEvent(targetName)
		end
		for unitName, spell, targetName in string.gfind(arg1, SPLL_CAST) do
			CaptureEvent(unitName, spell)
			CaptureEvent(targetName)
		end
		for unitName, spell, targetName in string.gfind(arg1, SPLL_CASTS) do
			CaptureEvent(unitName, spell)
			CaptureEvent(targetName)
		end
		for unitName, spell in string.gfind(arg1, SPLL_CASTS2) do
			CaptureEvent(unitName, spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_GAINS) do
			--GAINS IS NOT WORKING
			CaptureEvent(unitName, enemybars_SelfBuffs[spell] and spell)
		end
		for unitName in string.gfind(arg1, SPLL_GAINS2) do
			--GAINS IS NOT WORKING
			CaptureEvent(unitName)
		end
		for unitName, spell in string.gfind(arg1, SPLL_BPERFORM) do
			CaptureEvent(unitName, spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_BCAST) do
			CaptureEvent(unitName, spell)
		end
	elseif event == 'CHAT_MSG_COMBAT_HOSTILE_DEATH' then
		for _, pattern in DEATH_PATTERNS do
			for unitName in string.gfind(arg1, pattern) do 
				UnitDeath(unitName)
			end
		end
	end
end

function SlashCommand(msg)
	if strfind(msg, 'scale') then
		for scale in string.gfind(msg, "scale%s*(%S*)") do
			if tonumber(scale) then
				SetEffectiveScale(ANCHOR, scale, UIParent)
				enemybars_settings.scale = scale			
			end
		end
	end
end

function CaptureEvent(unitName, spell)
	for i = 1, 3 do
		if GetBattlefieldStatus(i) == 'active' then
			return
		end
	end

	if unitName == UnitName'player' or unitName == UnitName'pet' or unitName == UNKNOWNOBJECT then
		return
	end

	for i = 1, GetNumPartyMembers() do
		if unitName == UnitName('party' .. i) or unitName == UnitName('partypet' .. i) then
			return
		end
	end

	DATA[unitName].failed = nil
	if not DATA[unitName].class then
		DATA[unitName].class = spell and enemybars_Abilities[spell] or enemybars_SelfBuffs[spell]
		DATA[unitName].scanned = 0
	end
	
	for frame in FRAMES do
		if frame.unit == unitName then
			return
		end
	end
	for frame in FRAMES do
		if not frame.pred then
			ShowFrame(unitName, frame)
			return
		end
	end
end

-- function CaptureHealer() -- TODO when healer is placed
-- 	if enemybars_settings.sound_all == 1 then
-- 		PlaySoundFile[[Sound\Interface\MapPing.wav]]
-- 	end
-- end

function ShowFrame(unitName, frame)
	PlaySoundFile(BOTTOM == ROOT and [[Sound\Interface\TalentScreenOpen.wav]] or [[Sound\Interface\MouseOverTarget.wav]])

	frame.unit = unitName

	frame.pred = BOTTOM
	BOTTOM = frame

	frame.name:SetText(unitName)
	-- UIFrameFlash(frame.flash, .2, .5, .7, nil, .1, 0)

	frame:ClearAllPoints()
	frame:SetPoint('TOP', frame.pred, 'BOTTOM', 0, 0)
	frame:Show()
end

do
	local f = CreateFrame'Frame'
	function ScanUnit(id)
		if UnitExists(id) then
			if not DATA[UnitName(id)].portrait then
				local texture = f:CreateTexture(nil, 'ARTWORK')
				texture:SetWidth(18)
				texture:SetHeight(18)
				texture:SetTexCoord(.15, .85, .15, .85)
				DATA[UnitName(id)].portrait = texture
			end
			SetPortraitTexture(DATA[UnitName(id)].portrait, id)
			local rankName, rankNumber = GetPVPRankInfo(UnitPVPRank(id))
			DATA[UnitName(id)].class = UnitIsPlayer(id) and strupper(UnitClass(id)) or 'PET'
			DATA[UnitName(id)].level = UnitLevel(id) == -1 and 100 or UnitLevel(id)
			DATA[UnitName(id)].rank = rankNumber
			DATA[UnitName(id)].maxHealth = UnitHealthMax(id)
			DATA[UnitName(id)].health = UnitHealth(id)
		end
	end
end

function HideFrame(frame)
	PlaySound'INTERFACESOUND_LOSTTARGETUNIT'
	frame.unit = nil
	frame.moving = nil
	if frame == BOTTOM then
		BOTTOM = frame.pred
	end
	for cFrame in FRAMES do
		if cFrame.pred == frame then
			cFrame.pred = frame.pred
			local startPos = cFrame:GetTop() / cFrame:GetScale() - cFrame.pred:GetBottom() / cFrame.pred:GetScale()
			AnimateFrame(cFrame, .5)
			break
		end
	end
	frame.pred = nil
	frame:Hide()
end

function OnClick()
	TargetByName(this.unit, true)
	if UnitName'target' == this.unit then
		PlaySound'igCreatureAggroSelect'
	else
		PlaySoundFile[[Sound\Interface\Error.wav]]
	end
end

function OnUpdate()
	if this.moving then
		this:ClearAllPoints()
		local fraction = (GetTime() - this.animStartTime) / (this.animEndTime - this.animStartTime)
		if fraction >= 1 then
			AnimateFrameEnd(this)
		else
			this:SetPoint('TOP', this.pred, 'BOTTOM', 0, (fraction - 1) * this:GetHeight())
		end
	end
	if this.unit then
		ScanEnemy(this.unit)
		UpdateFrame(this)
		if DATA[this.unit].failed and GetTime() > DATA[this.unit].failed + 10 then
			HideFrame(this)
		end
	end
end

do
	local attacking, shooting
	do
		local f = CreateFrame'Frame'
		f:RegisterEvent'PLAYER_ENTER_COMBAT'
		f:RegisterEvent'PLAYER_LEAVE_COMBAT'
		f:SetScript('OnEvent', function()
			attacking = event == 'PLAYER_ENTER_COMBAT'
		end)
	end
	do
		local f = CreateFrame'Frame'
		f:RegisterEvent'START_AUTOREPEAT_SPELL'
		f:RegisterEvent'STOP_AUTOREPEAT_SPELL'
		f:SetScript('OnEvent', function()
			shooting = event == 'START_AUTOREPEAT_SPELL'
		end)
	end
	function ScanEnemy(name)
		local data = DATA[name]
		if name == UnitName'mouseover' then
			ScanUnit'mouseover'
			data.failed = nil
			data.scanned = GetTime()
		elseif name == UnitName'target' then
			ScanUnit'target'
			data.failed = nil
			data.scanned = GetTime()
		elseif (not data.scanned or GetTime() > data.scanned + 1) and not attacking and not shooting and GetComboPoints() == 0 and UnitName'target' ~= name then
			local backup = UnitName'target'
			TargetByName(name, true)
			if UnitName'target' == name then
				ScanUnit'target'
				data.failed = nil
			else
				data.failed = data.failed or GetTime()
			end
			if UnitName'target' ~= backup then
				(backup and TargetLastTarget or ClearTarget)()
			end
			data.scanned = GetTime()
		end
	end
end

function UpdateFrame(frame)
	local data = DATA[frame.unit]
	if frame.scan == data.scanned then
		return
	end
	frame.scan = data.scanned

	local slot = frame:GetID()

	if frame.portrait then
		frame.portrait:Hide()
	end
	if data.portrait then
		frame.portrait = data.portrait
		frame.portrait:SetParent(frame)
		frame.portrait:SetPoint('LEFT', 0, 0)
		frame.portrait:Show()
	end

	if data.class == 'PET' then
		frame.health:SetStatusBarColor(.77, .12, .23, .8)
		frame.health:SetBackdropColor(.77 * .7, .12 * .7, .23 * .7, .5)		
	elseif data.class then
		local color = RAID_CLASS_COLORS[data.class]
		frame.health:SetStatusBarColor(color.r, color.g, color.b, .8)
		frame.health:SetBackdropColor(color.r * .7, color.g * .7, color.b * .7, .5)
	else	
		frame.health:SetStatusBarColor(0, 0, 0, .8)
		frame.health:SetBackdropColor(0, 0, 0, .5)
	end	

	if data.level then
		if data.level == 100 then
			frame.level:SetText'??'
		else
			frame.level:SetText(data.level)
		end
		local color = GetDifficultyColor(data.level)
		-- frame.name:SetTextColor(color.r, color.g, color.b)
		frame.level:SetTextColor(color.r, color.g, color.b)
	else
		frame.level:SetText''
		-- frame.level:SetVertexColor(.75, .75, .75)
	end

	if data.rank and data.rank > 0 then
		frame.rank:SetTexture(format('%s%02d', [[Interface\PvPRankBadges\PvPRank]], data.rank))
		frame.rank:Show()
	else
		frame.rank:Hide()
	end
	
	frame.health:SetMinMaxValues(0, data.maxHealth or 100)
	frame.health:SetValue(data.health or 100)
end

function AnimateFrame(frame, duration)
	frame.animStartTime = GetTime()
	frame.animEndTime = frame.animStartTime + duration
	frame.moving = true
end

function AnimateFrameEnd(frame)
	frame.moving = false
	frame:ClearAllPoints()
	frame:SetPoint('TOP', frame.pred, 'BOTTOM', 0, 0)
end

function UnitDeath(unitName)
	for frame in FRAMES do
		if unitName == frame.unit then
			HideFrame(frame)
		end
	end
end