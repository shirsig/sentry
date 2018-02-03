local _G, _M = getfenv(0), {}
setfenv(1, setmetatable(_M, {__index=_G}))

local ANCHOR = CreateFrame('Frame', nil, UIParent)
ANCHOR:SetWidth(160)
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
ANCHOR:RegisterEvent'UPDATE_MOUSEOVER_UNIT'
ANCHOR:RegisterEvent'PLAYER_TARGET_CHANGED'

local FRAMES = {}
local ACTIVE_ENEMIES = {}
local RECENT_ENEMIES = {}
local DATA = {}

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

function SetEffectiveScale(frame, scale, parentframe)
    local parent = getglobal(parentframe)
    if parent then
        scale = scale / GetEffectiveScale(parent)
    end
    frame:SetScale(scale)
end

function Setup()
	_G.sentry_settings = sentry_settings or {}
	if sentry_settings.x then
		ANCHOR:SetPoint('CENTER', 'UIParent', 'BOTTOMLEFT', sentry_settings.x, sentry_settings.y)
	else
		ANCHOR:SetPoint('TOP', 0, -3)
	end
	sentry_settings.scale = sentry_settings.scale or 1
	SetEffectiveScale(ANCHOR, sentry_settings.scale, UIParent)
	sentry_settings.size = sentry_settings.size or 7
	sentry_settings.enemies = sentry_settings.enemies or {}

	CreateBars()

	DEFAULT_CHAT_FRAME:AddMessage'<sentry> loaded - /sentry'
end

function CreateBars()
	ANCHOR:SetHeight(18 * sentry_settings.size)
	for i = getn(FRAMES) + 1, sentry_settings.size do
		local f = CreateFrame('Frame', nil, ANCHOR)
		f:EnableMouse(true)
		f:SetScript('OnMouseDown', function()
			if IsControlKeyDown() then
				ANCHOR:StartMoving()
			else
				OnClick()
			end
		end)
		f:SetScript('OnMouseUp', function()
			ANCHOR:StopMovingOrSizing()
			sentry_settings.x, sentry_settings.y = ANCHOR:GetCenter()
		end)
		f:SetWidth(160)
		f:SetHeight(18)
		f:SetID(i)
		f:Hide()
		f.rank = f:CreateTexture()
		f.rank:SetWidth(15)
		f.rank:SetHeight(15)
		f.rank:SetPoint('RIGHT', f, 'LEFT', -4.5, 0)
		local portrait = f:CreateTexture()
		portrait:SetWidth(18)
		portrait:SetHeight(18)
		portrait:SetPoint('LEFT', 0, 0)
		portrait:SetTexture[[Interface\InventoryItems\WoWUnknownItem01]]
		portrait:SetTexCoord(.17, .83, .17, .83)
		f.health = CreateFrame('StatusBar', nil, f)
		f.health:EnableMouse(false)
		f.health:SetPoint('TOPLEFT', portrait, 'TOPRIGHT', 0, 0)
		f.health:SetPoint('BOTTOMRIGHT', 0, 0)
		f.health:SetStatusBarTexture[[Interface\Addons\sentry\Minimalist]]
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

	PlaceBars()
end

function Event()
	if event == 'PLAYER_LOGIN' then
		Setup()
	elseif event == 'UPDATE_MOUSEOVER_UNIT' or event == 'PLAYER_TARGET_CHANGED' then
		local unit = event == 'UPDATE_MOUSEOVER_UNIT' and 'mouseover' or 'target'
		if UnitIsEnemy('player', unit) and UnitPlayerControlled(unit) then
			CaptureEvent(UnitName(unit))
			ScanUnit(unit)
		end
	elseif event == 'CHAT_MSG_COMBAT_HOSTILEPLAYER_HITS' or event == 'CHAT_MSG_COMBAT_HOSTILEPLAYER_MISSES' or event == 'CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE' then
		for _, pattern in sentry_HARM_PATTERNS do
			for unitName, spell in string.gfind(arg1, pattern) do
				CaptureEvent(unitName, spell)
				return
			end
		end
	elseif event == 'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE' then
	elseif event == 'CHAT_MSG_SPELL_HOSTILEPLAYER_BUFF' or event == 'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS' then
		for _, pattern in {SPLL_HEALCRIT, SPLL_HEAL, SPLL_CAST, SPLL_CASTS} do
			for unitName, spell, targetName in string.gfind(arg1, pattern) do
				if strupper(targetName) ~= strupper(YOU) then
					CaptureEvent(unitName, spell)
					CaptureEvent(targetName)
				end
				return
			end
		end
		for unitName, spell in string.gfind(arg1, SPLL_CASTS2) do
			CaptureEvent(unitName, spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_GAINS) do
			CaptureEvent(unitName, sentry_SELFBUFFS[spell] and spell)
		end
		for unitName in string.gfind(arg1, SPLL_GAINS2) do
			CaptureEvent(unitName, sentry_SELFBUFFS[spell] and spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_BPERFORM) do
			CaptureEvent(unitName, spell)
		end
		for unitName, spell in string.gfind(arg1, SPLL_BCAST) do
			CaptureEvent(unitName, spell)
		end
	end
end

function PlaceBars()
	for _, frame in FRAMES do
		local i = frame:GetID()
		frame:ClearAllPoints()
		if i == 1 then
			frame:SetPoint(sentry_settings.invert and 'BOTTOM' or 'TOP', 0, 0)
		else
			frame:SetPoint(sentry_settings.invert and 'BOTTOM' or 'TOP', FRAMES[i - 1], sentry_settings.invert and 'TOP' or 'BOTTOM', 0, 0)
		end
	end
end

function CaptureEvent(name, spell)
	for i = 1, 3 do
		if GetBattlefieldStatus(i) == 'active' then
			return
		end
	end
	if strupper(name) == strupper(YOU) or name == UnitName'pet' or name == UNKNOWNOBJECT then
		return
	end
	for i = 1, GetNumPartyMembers() do
		if name == UnitName('party' .. i) or name == UnitName('partypet' .. i) then
			return
		end
	end

	DATA[name] = DATA[name] or {}
	local data = DATA[name]
	data.seen = GetTime()
	if not data.class then
		data.class = spell and sentry_ABILITIES[spell] or sentry_SELFBUFFS[spell]
	end
	
	for _, enemy in ACTIVE_ENEMIES do
		if name == enemy then
			return
		end
	end
	if getn(ACTIVE_ENEMIES) < sentry_settings.size then
		PlaySoundFile(getn(ACTIVE_ENEMIES) == 0 and [[Sound\Interface\TalentScreenOpen.wav]] or [[Sound\Interface\MouseOverTarget.wav]])
		tinsert(ACTIVE_ENEMIES, name)
		for i = getn(RECENT_ENEMIES), 1, -1 do
			if RECENT_ENEMIES[i] == name then
				tremove(RECENT_ENEMIES, i)
			end
		end
	end
end

function OnClick()
	local name = ACTIVE_ENEMIES[this:GetID()]
	if arg1 == 'LeftButton' then
		TargetByName(name, true)
		if UnitName'target' == name then
			PlaySound'igCreatureAggroSelect'
		else
			PlaySoundFile[[Sound\Interface\Error.wav]]
		end
	end
end

ANCHOR:SetScript('OnUpdate', function()
	ScanUnit'target'
	ScanUnit'mouseover'
	for name, _ in sentry_settings.enemies do
		if getn(ACTIVE_ENEMIES) == sentry_settings.size then
			break
		end
		local active = false
		for _, active_name in ACTIVE_ENEMIES do
			active = active or name == active_name
		end
		if not active then
			TargetEnemy(name)
		end
	end
	for _, name in RECENT_ENEMIES do
		if getn(ACTIVE_ENEMIES) == sentry_settings.size then
			break
		end
		if not sentry_settings.enemies[name] then
			TargetEnemy(name)
		end
	end
	for _, frame in FRAMES do
		local name = ACTIVE_ENEMIES[frame:GetID()]
		if name then
			local data = DATA[name]

			TargetEnemy(name)

			if data.untargetable and GetTime() > data.seen + 30 then
				PlaySound'INTERFACESOUND_LOSTTARGETUNIT'
				tremove(ACTIVE_ENEMIES, frame:GetID())
				tinsert(RECENT_ENEMIES, 1, name)
				if getn(RECENT_ENEMIES) > sentry_settings.size then
					tremove(RECENT_ENEMIES)
				end
				return
			end

			if not frame:IsShown() then
				frame:Show()
				UIFrameFlash(frame.flash, .2, .5, .7, nil, .1, 0)
			end

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
				frame.health:SetStatusBarColor(.77, .12, .23)
				frame.health:SetBackdropColor(.77 * .5, .12 * .5, .23 * .5)		
			elseif data.class then
				local color = RAID_CLASS_COLORS[data.class]
				frame.health:SetStatusBarColor(color.r, color.g, color.b)
				frame.health:SetBackdropColor(color.r * .5, color.g * .5, color.b * .5)
			else	
				frame.health:SetStatusBarColor(0, 0, 0)
				frame.health:SetBackdropColor(0, 0, 0)
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
			
			frame.health:SetMinMaxValues(0, 1)
			frame.health:SetValue(data.health or 1)
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

	do
		local lastTargetTime = 0
		local pass = function() end
		function TargetEnemy(name)
			local now = GetTime()
			local ready = now - lastTargetTime > 3 and now - (DATA[name] and DATA[name].scanned or 0) > getn(ACTIVE_ENEMIES) * 3
			if ready and not attacking and not shooting and not looting and GetComboPoints() == 0 and UnitName'target' ~= name then
				local target = UnitName'target'
				local _PlaySound, _UIErrorsFrame_OnEvent = PlaySound, UIErrorsFrame_OnEvent
				_G.PlaySound, _G.UIErrorsFrame_OnEvent = pass, pass
				TargetByName(name, true)
				if UnitName'target' ~= target then
					(target and TargetLastTarget or ClearTarget)()
					lastTargetTime = now
				elseif DATA[name] then
					DATA[name].untargetable = true
				end
				_G.PlaySound, _G.UIErrorsFrame_OnEvent = _PlaySound, _UIErrorsFrame_OnEvent
			end
		end
	end
end

do
	local f = CreateFrame'Frame'
	function ScanUnit(id)
		local data = DATA[UnitName(id)]
		if data and UnitIsEnemy('player', id) and UnitPlayerControlled(id) then
			data.untargetable = false
			data.scanned = GetTime()
			data.seen = data.scanned
			if not data.portrait then
				local texture = f:CreateTexture(nil, 'OVERLAY')
				texture:SetWidth(18)
				texture:SetHeight(18)
				texture:SetTexCoord(.15, .85, .15, .85)
				data.portrait = texture
			end
			SetPortraitTexture(data.portrait, id)
			local rankName, rankNumber = GetPVPRankInfo(UnitPVPRank(id))
			data.class = UnitIsPlayer(id) and strupper(UnitClass(id)) or 'PET'
			data.level = UnitLevel(id) == -1 and 100 or UnitLevel(id)
			data.rank = rankNumber
			data.health = UnitHealth(id) / UnitHealthMax(id)
		end
	end
end

_G.SLASH_SENTRY1 = '/sentry'
do
	local function sortedNames()
		local t = {}
		for key in pairs(sentry_settings.enemies) do
			tinsert(t, key)
		end
		sort(t, function(key1, key2) return key1 < key2 end)
		return t
	end

	local function toggleName(name)
		local key = gsub(strlower(name), "^%l", string.upper)
		if sentry_settings.enemies[key] then
			sentry_settings.enemies[key] = nil
			DEFAULT_CHAT_FRAME:AddMessage('<sentry> - ' .. key)
		elseif key ~= '' then
			sentry_settings.enemies[key] = true
			DEFAULT_CHAT_FRAME:AddMessage('<sentry> + ' .. key)
		end
	end

	function SlashCmdList.SENTRY(msg)
		if msg == 'invert' then
			sentry_settings.invert = not sentry_settings.invert
			PlaceBars()
			return
		elseif strfind(msg, '^scale%s') then
			for scale in string.gfind(msg, "scale%s*(%S*)") do
				if tonumber(scale) then
					SetEffectiveScale(ANCHOR, scale, UIParent)
					sentry_settings.scale = tonumber(scale)
					return
				end
			end
		elseif strfind(msg, '^size%s') then
			for size in string.gfind(msg, "size%s*(%S*)") do
				if tonumber(size) then
					sentry_settings.size = tonumber(size)
					CreateBars()
					return
				end
			end
		elseif strfind(msg, '^toggle%s') then
			for name in string.gfind(msg, "toggle%s*(%S*)") do
				toggleName(name)
			end
		elseif msg == 'list' then
			for _, key in ipairs(sortedNames()) do
				DEFAULT_CHAT_FRAME:AddMessage('<sentry> ' .. key)
			end	
		else
			DEFAULT_CHAT_FRAME:AddMessage'<sentry> Usage:'
			DEFAULT_CHAT_FRAME:AddMessage'<sentry>   invert'
			DEFAULT_CHAT_FRAME:AddMessage'<sentry>   scale {number}'
			DEFAULT_CHAT_FRAME:AddMessage'<sentry>   size {number}'
			DEFAULT_CHAT_FRAME:AddMessage'<sentry>   toggle {name}'
			DEFAULT_CHAT_FRAME:AddMessage'<sentry>   list'
		end
	end
end