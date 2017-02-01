local _G, _M = getfenv(0), {}
setfenv(1, setmetatable(_M, {__index=_G}))

local SIZE = 7

local ANCHOR = CreateFrame('Frame', nil, UIParent)
ANCHOR:SetWidth(160)
ANCHOR:SetHeight(18 * SIZE)
ANCHOR:SetMovable(true)
ANCHOR:SetClampedToScreen(true)

ANCHOR:SetScript('OnEvent', function () Event() end)
ANCHOR:RegisterEvent'PLAYER_LOGIN'
ANCHOR:RegisterEvent'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE'
ANCHOR:RegisterEvent'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS'
ANCHOR:RegisterEvent'CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE'
ANCHOR:RegisterEvent'CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF'
ANCHOR:RegisterEvent'CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS'
ANCHOR:RegisterEvent'CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES'
ANCHOR:RegisterEvent'CHAT_MSG_COMBAT_HOSTILE_DEATH'
ANCHOR:RegisterEvent'UPDATE_MOUSEOVER_UNIT'
ANCHOR:RegisterEvent'PLAYER_TARGET_CHANGED'

local FRAMES = {}
local ENEMIES = {}
local DATA = setmetatable({}, {__index=function(self, key) self[key] = {}; return self[key] end})

local SPLL_HEALCRIT = "(.+)%'s (.+) critically heals (.+) for (%d+)%a%."
local SPLL_HEAL = "(.+)%'s (.+) heals (.+) for (%d+)%."
local SPLL_CAST = "(.+) casts (.+) on (.+)%."
local SPLL_CASTS = "(.+) casts (.+) on (.+)%'s .+%."
local SPLL_CASTS2 = "(.+) casts (.+)%."
local SPLL_GAINS = "(.+) gains ([^%d].*)%."
local SPLL_GAINS2 = "(.+) gains ([^%d].*)% %(%d+%)%."
-- TODO other gains patterns somehow also for friendly units?
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
	for i = 1, SIZE do
		local f = CreateFrame('Frame', nil, ANCHOR)
		f:EnableMouse(true)
		f:SetScript('OnMouseDown', function()
			ANCHOR:StartMoving()
		end)
		f:SetScript('OnMouseUp', function()
			OnClick()
			ANCHOR:StopMovingOrSizing()
			enemybars_settings.x, enemybars_settings.y = ANCHOR:GetCenter()
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
		f.flash = CreateFrame('Frame', 'enemybarflash' .. i, f)
		f.flash:SetWidth(180)
		f.flash:SetHeight(65)
		f.flash:SetPoint('CENTER', 0, -7)
		f.flash:Hide()
		local flash = f.flash:CreateTexture(nil, 'OVERLAY')
		flash:SetTexture[[Interface\Buttons\UI-DialogBox-Button-Highlight]]
		flash:SetBlendMode'ADD'
		flash:SetAllPoints()
		portrait:SetTexCoord(.17, .83, .17, .83)
		tinsert(FRAMES, f)
	end

	_G.SLASH_ENEMYBARS1 = '/enemybars'
	SlashCmdList.ENEMYBARS = SlashCommand
	
	_G.enemybars_settings = enemybars_settings or {}
	if enemybars_settings.x then
		ANCHOR:SetPoint('CENTER', 'UIParent', 'BOTTOMLEFT', enemybars_settings.x, enemybars_settings.y)
	else
		ANCHOR:SetPoint('TOP', 0, -3)
	end
	enemybars_settings.scale = enemybars_settings.scale or 1
	SetEffectiveScale(ANCHOR, enemybars_settings.scale, UIParent)

	PlaceFrames()

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
		for _, pattern in enemybars_PATTERNS do
			for unitName, spell in string.gfind(arg1, pattern) do
				CaptureEvent(unitName, spell)
				return
			end
		end
	elseif event == 'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE' then
	elseif event == 'CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF' or event == 'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS' then
		for _, pattern in {SPLL_HEALCRIT, SPLL_HEAL, SPLL_CAST, SPLL_CASTS} do
			for unitName, spell, targetName in string.gfind(arg1, pattern) do
				CaptureEvent(unitName, spell)
				CaptureEvent(targetName)
				return
			end
		end
		for unitName, spell in string.gfind(arg1, SPLL_CASTS2) do
			CaptureEvent(unitName, spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_GAINS) do
			CaptureEvent(unitName, enemybars_SELFBUFFS[spell] and spell)
		end
		for unitName in string.gfind(arg1, SPLL_GAINS2) do
			CaptureEvent(unitName, enemybars_SELFBUFFS[spell] and spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_BPERFORM) do
			CaptureEvent(unitName, spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_BCAST) do
			CaptureEvent(unitName, spell)
		end
	elseif event == 'CHAT_MSG_COMBAT_HOSTILE_DEATH' then
		for _, pattern in enemybars_DEATH_PATTERNS do
			for unitName in string.gfind(arg1, pattern) do 
				UnitDeath(unitName)
			end
		end
	end
end

function PlaceFrames()
	for _, frame in FRAMES do
		local i = frame:GetID()
		frame:ClearAllPoints()
		if i == 1 then
			frame:SetPoint(enemybars_settings.invert and 'BOTTOM' or 'TOP', 0, 0)
		else
			frame:SetPoint(enemybars_settings.invert and 'BOTTOM' or 'TOP', FRAMES[i - 1], enemybars_settings.invert and 'TOP' or 'BOTTOM', 0, 0)
		end
	end
end

function SlashCommand(msg)
	if msg == 'sound' then
		enemybars_settings.sound = not enemybars_settings.sound
	elseif msg == 'invert' then
		enemybars_settings.invert = not enemybars_settings.invert
		PlaceFrames()
	elseif strfind(msg, '^scale%s') then
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
	if strupper(unitName) == strupper(YOU) or unitName == UnitName'pet' or unitName == UNKNOWNOBJECT then
		return
	end
	for i = 1, GetNumPartyMembers() do
		if unitName == UnitName('party' .. i) or unitName == UnitName('partypet' .. i) then
			return
		end
	end

	DATA[unitName].failed = nil
	if not DATA[unitName].class then
		DATA[unitName].class = spell and enemybars_ABILITIES[spell] or enemybars_SELFBUFFS[spell]
		DATA[unitName].scanned = 0
	end
	
	for _, enemy in ENEMIES do
		if unitName == enemy then
			return
		end
	end
	if getn(ENEMIES) < SIZE then
		PlaySoundFile(getn(ENEMIES) == 0 and [[Sound\Interface\TalentScreenOpen.wav]] or [[Sound\Interface\MouseOverTarget.wav]])
		tinsert(ENEMIES, unitName)
	end
end

-- function CaptureHealer() -- TODO when healer is placed
-- 	if enemybars_settings.sound_all == 1 then
-- 		PlaySoundFile[[Sound\Interface\MapPing.wav]]
-- 	end
-- end

function OnClick()
	local name = ENEMIES[this:GetID()]
	TargetByName(name, true)
	if UnitName'target' == name then
		PlaySound'igCreatureAggroSelect'
	else
		PlaySoundFile[[Sound\Interface\Error.wav]]
	end
end

ANCHOR:SetScript('OnUpdate', function()
	for _, frame in FRAMES do
		local name = ENEMIES[frame:GetID()]
		if name then
			ScanEnemy(name)
			local data = DATA[name]

			if data.failed and GetTime() > data.failed + 10 then
				PlaySound'INTERFACESOUND_LOSTTARGETUNIT'
				tremove(ENEMIES, frame:GetID())
				return
			end

			if not frame:IsShown() then
				frame:Show()
				UIFrameFlash(frame.flash, .2, .5, .7, nil, .1, 0)
			end

			-- if frame.scan == data.scanned then
			-- 	return
			-- end
			frame.scan = data.scanned

			frame.name:SetText(name)

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
				frame.health:SetBackdropColor(.77 * .6, .12 * .6, .23 * .6, .6)		
			elseif data.class then
				local color = RAID_CLASS_COLORS[data.class]
				frame.health:SetStatusBarColor(color.r, color.g, color.b, .8)
				frame.health:SetBackdropColor(color.r * .6, color.g * .6, color.b * .6, .6)
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
				frame.level:SetTextColor(color.r, color.g, color.b)
			else
				frame.level:SetText''
			end

			if data.rank and data.rank > 0 then
				frame.rank:SetTexture(format('%s%02d', [[Interface\PvPRankBadges\PvPRank]], data.rank))
				frame.rank:Show()
			else
				frame.rank:Hide()
			end
			
			frame.health:SetMinMaxValues(0, data.maxHealth or 100)
			frame.health:SetValue(data.health or 100)
		elseif frame:IsShown() then
			UIFrameFlashRemoveFrame(frame)
			frame:Hide()
		end
	end
end)

do
	local attacking, shooting, looting
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
	do
		local f = CreateFrame'Frame'
		f:RegisterEvent'LOOT_OPENED'
		f:RegisterEvent'LOOT_CLOSED'
		f:SetScript('OnEvent', function()
			shooting = event == 'LOOT_OPENED'
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
		elseif (not data.scanned or GetTime() > data.scanned + 1) and not attacking and not shooting and not looting and GetComboPoints() == 0 and UnitName'target' ~= name then
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

function UnitDeath(name)
	for i, enemy in ENEMIES do
		if enemy == name then
			PlaySound'INTERFACESOUND_LOSTTARGETUNIT'
			tremove(ENEMIES, i)
			return
		end
	end
end