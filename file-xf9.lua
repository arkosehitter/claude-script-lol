--[[
	MoveLogger v2.5  ·  general move recorder for battlegrounds-style games (executor build)

	Every recording becomes its own MOVE BLOCK in the Moves tab — one block per move, each with
	its own copy buttons for table / replay / summary / timeline / JSON.

	ADVANCED MODE (Record page or Settings): records in two phases — STARTUP first (no victims,
	pure wind-up), then "Record hit" (F9) at the moment it lands, then "Done". One block, boundary
	marked, startup and hit kept separate.

	  ANIM · MARKER · VELOCITY · SOUND · VFX · HITBOX · MOVE · HIT · STATE · CAMERA · SCREEN ·
	  REMOTE · REPLICATION

	VFX capture is exhaustive: every readable property of every emitter / beam / trail / mesh,
	with texture + mesh asset ids (raw and extracted), colour keypoints as hex + rgb, host part
	size and offsets, attachments, flipbooks, and rebuildable Instance code.

	Keys: F6 start/stop · F7 arm · F8 show/hide · F9 hit phase.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local KeyframeSequenceProvider = game:GetService("KeyframeSequenceProvider")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
if GENV.__MoveLogger then pcall(GENV.__MoveLogger.destroy) end
local Self = {}
GENV.__MoveLogger = Self

local Bag = {}
local function cn(c) table.insert(Bag, c) return c end
local ownGui
local LoggedRoot

function Self.destroy()
	for _, c in Bag do pcall(function() c:Disconnect() end) end
	table.clear(Bag)
	pcall(function() RunService:UnbindFromRenderStep("MoveLoggerCam2") end)
	if ownGui then pcall(function() ownGui:Destroy() end) end
	GENV.__MoveLogger = nil
end

local function section(name, fn)
	local ok, err = pcall(fn)
	if not ok then warn("[MoveLogger] " .. name .. " failed: " .. tostring(err)) end
	return ok
end

---------------------------------------------------------------------------------------------------
-- settings
---------------------------------------------------------------------------------------------------
local CONFIG = {
	Radius = 150, VictimRadius = 45, Preroll = 0.4, IdleStop = 2.0, MaxLength = 30, MinLength = 0.3,
	AutoArm = true, StartOnAnim = true, StartOnRemote = false, IgnoreCoreAnims = true, TrackOthers = true,
	TrackVelocity = true, TrackHitboxTouches = true, CloneEffects = true, TrackTerrain = true, TrackMotion = true,
	TrackTags = true, TrackAttributes = true, TrackDummies = true, ReplicationSpy = true, LogRemotes = true,
	LogCamera = true, LogScreen = true, Advanced = false, Debug = false, MaxClones = 200,
	RemoteIgnore = "Chat,Message,Mute,Channel,Ping,Leaderboard,Cosmetic,Title,Notif,Mouse,Aim,Position,Cframe",
	SoundIgnore = "Running,Jumping,FreeFall,Landing,Swimming,Climbing,GettingUp,Died,Splash,Music,Theme,Ambience,Ambient",
	VelocitySpike = 12, SpeedPhase = 4, ShakeThreshold = 0.35, MaxEvents = 8000,
}

local CATS = { "ANIM", "MARKER", "VELOCITY", "SOUND", "VFX", "HITBOX", "MOVE", "HIT", "STATE", "CAMERA", "SCREEN", "REMOTE", "REPLICATION" }
local CAT_COLOR = {
	ANIM = Color3.fromRGB(120, 160, 255), MARKER = Color3.fromRGB(170, 140, 255), VELOCITY = Color3.fromRGB(90, 230, 220),
	SOUND = Color3.fromRGB(90, 210, 160), VFX = Color3.fromRGB(255, 170, 70), HITBOX = Color3.fromRGB(255, 80, 90),
	MOVE = Color3.fromRGB(80, 200, 255), HIT = Color3.fromRGB(255, 110, 140), STATE = Color3.fromRGB(220, 220, 120),
	CAMERA = Color3.fromRGB(150, 220, 255), SCREEN = Color3.fromRGB(240, 140, 220), REMOTE = Color3.fromRGB(170, 175, 190),
	REPLICATION = Color3.fromRGB(130, 200, 200),
}
local CAT_SHOW = {}
for _, c in CATS do CAT_SHOW[c] = true end

local THEME = {
	Bg = Color3.fromRGB(14, 15, 20), Panel = Color3.fromRGB(22, 24, 31), Panel2 = Color3.fromRGB(30, 33, 42),
	Stroke = Color3.fromRGB(48, 52, 66), Text = Color3.fromRGB(232, 235, 242), Sub = Color3.fromRGB(140, 146, 165),
	Accent = Color3.fromRGB(118, 136, 255), Rec = Color3.fromRGB(255, 72, 88), Armed = Color3.fromRGB(255, 190, 70),
	Good = Color3.fromRGB(110, 220, 150), Hit = Color3.fromRGB(255, 140, 70),
}

---------------------------------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------------------------------
local function now() return os.clock() end
local function r(n, d)
	local m = 10 ^ (d or 2)
	return math.round((tonumber(n) or 0) * m) / m
end
local function fmtNum(n, d)
	local s = string.format("%." .. tostring(d or 2) .. "f", n)
	s = string.gsub(s, "%.?0+$", "")
	if s == "-0" or s == "" then s = "0" end
	return s
end
local function v3s(v) return string.format("(%s, %s, %s)", fmtNum(v.X), fmtNum(v.Y), fmtNum(v.Z)) end
local function v3lua(v) return string.format("Vector3.new(%s, %s, %s)", fmtNum(v.X), fmtNum(v.Y), fmtNum(v.Z)) end
local function cflua(cf)
	local x, y, z = cf.Position.X, cf.Position.Y, cf.Position.Z
	local rx, ry, rz = cf:ToOrientation()
	if math.abs(rx) + math.abs(ry) + math.abs(rz) < 1e-3 then
		return string.format("CFrame.new(%s, %s, %s)", fmtNum(x), fmtNum(y), fmtNum(z))
	end
	return string.format("CFrame.new(%s, %s, %s) * CFrame.fromOrientation(math.rad(%s), math.rad(%s), math.rad(%s))",
		fmtNum(x), fmtNum(y), fmtNum(z), fmtNum(math.deg(rx), 1), fmtNum(math.deg(ry), 1), fmtNum(math.deg(rz), 1))
end
local function c3hex(c) return string.format("#%02X%02X%02X", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)) end
local function c3rgb(c) return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) } end
local function assetNum(s) return s and string.match(tostring(s), "%d%d%d%d+") or nil end
local function splitList(s)
	local t = {}
	for part in string.gmatch(s or "", "[^,]+") do
		local p = string.lower((string.gsub(part, "^%s+", ""):gsub("%s+$", "")))
		if p ~= "" then table.insert(t, p) end
	end
	return t
end
local function matchesAny(name, list)
	local n = string.lower(tostring(name))
	for _, p in list do if string.find(n, p, 1, true) then return true end end
	return false
end
local function shortPath(inst, depth)
	if not inst then return "nil" end
	local parts, node, d = {}, inst, depth or 4
	while node and node ~= game and d > 0 do
		table.insert(parts, 1, node.Name)
		node = node.Parent
		d -= 1
	end
	if node and node ~= game then table.insert(parts, 1, "…") end
	return table.concat(parts, ".")
end
local function luaStr(s) return string.format("%q", tostring(s)) end
local function safe(f, ...)
	local ok, a = pcall(f, ...)
	if ok then return a end
	return nil
end
local function get(inst, prop)
	local ok, v = pcall(function() return inst[prop] end)
	if ok then return v end
	return nil
end
local function guard(f)
	return function(...)
		local ok, err = pcall(f, ...)
		if not ok and CONFIG.Debug then warn("[MoveLogger] " .. tostring(err)) end
	end
end
local function characterOf(inst)
	local node = inst
	while node and node ~= workspace and node ~= game do
		if node:IsA("Model") and node:FindFirstChildOfClass("Humanoid") then return node end
		node = node.Parent
	end
	return nil
end
local function rootOf(model)
	if not model then return nil end
	return model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart or model:FindFirstChild("Torso")
end
local function myChar() return LocalPlayer.Character end
local function myRoot() return rootOf(LocalPlayer.Character) end
local function positionOf(inst)
	if not inst then return nil end
	if inst:IsA("BasePart") then return inst.Position end
	if inst:IsA("Attachment") then return inst.WorldPosition end
	if inst:IsA("Model") then
		local cf = safe(inst.GetPivot, inst)
		if cf then return cf.Position end
	end
	local p = inst.Parent
	if p and p ~= workspace and p ~= game then return positionOf(p) end
	return nil
end
local function cframeOf(inst)
	if inst:IsA("BasePart") then return inst.CFrame end
	if inst:IsA("Attachment") then return inst.WorldCFrame end
	if inst:IsA("Model") then return safe(inst.GetPivot, inst) end
	return nil
end
local function localTo(cf)
	local root = myRoot()
	if not root or not cf then return nil end
	return root.CFrame:ToObjectSpace(cf)
end
local function localDir(v)
	local root = myRoot()
	if not root then return v end
	return root.CFrame:VectorToObjectSpace(v)
end
local function dirWords(v)
	local parts = {}
	if math.abs(v.Z) >= 0.5 then table.insert(parts, (v.Z < 0 and "fwd " or "back ") .. fmtNum(math.abs(v.Z), 1)) end
	if math.abs(v.Y) >= 0.5 then table.insert(parts, (v.Y > 0 and "up " or "down ") .. fmtNum(math.abs(v.Y), 1)) end
	if math.abs(v.X) >= 0.5 then table.insert(parts, (v.X > 0 and "right " or "left ") .. fmtNum(math.abs(v.X), 1)) end
	return #parts > 0 and table.concat(parts, ", ") or "0"
end
local function seqDump(seq)
	if seq == nil then return nil end
	local t = typeof(seq)
	if t == "NumberSequence" then
		local out = {}
		for _, kp in seq.Keypoints do table.insert(out, { time = r(kp.Time, 4), value = r(kp.Value, 4), envelope = r(kp.Envelope, 4) }) end
		return { kind = "number", keypoints = out }
	elseif t == "ColorSequence" then
		local out = {}
		for _, kp in seq.Keypoints do
			table.insert(out, { time = r(kp.Time, 4), color = c3hex(kp.Value), rgb = c3rgb(kp.Value), envelope = r(kp.Envelope, 4) })
		end
		return { kind = "color", keypoints = out }
	elseif t == "NumberRange" then
		return { kind = "range", min = r(seq.Min, 4), max = r(seq.Max, 4) }
	end
	return tostring(seq)
end
local function seqShort(seq)
	if seq == nil then return "?" end
	local t = typeof(seq)
	if t == "NumberSequence" then
		local parts = {}
		for _, kp in seq.Keypoints do
			table.insert(parts, fmtNum(kp.Time, 2) .. ":" .. fmtNum(kp.Value, 3) .. (kp.Envelope ~= 0 and ("±" .. fmtNum(kp.Envelope, 2)) or ""))
		end
		return table.concat(parts, " → ")
	elseif t == "ColorSequence" then
		local parts = {}
		for _, kp in seq.Keypoints do table.insert(parts, fmtNum(kp.Time, 2) .. ":" .. c3hex(kp.Value)) end
		return table.concat(parts, " → ")
	elseif t == "NumberRange" then
		return fmtNum(seq.Min, 3) .. "–" .. fmtNum(seq.Max, 3)
	end
	return tostring(seq)
end
local function ser(v, depth, seen)
	depth = depth or 0
	local t = typeof(v)
	if t == "nil" then return "nil"
	elseif t == "boolean" then return tostring(v)
	elseif t == "number" then return fmtNum(v, 3)
	elseif t == "string" then
		if #v > 90 then return string.format("%q", string.sub(v, 1, 90)) .. "…" end
		return string.format("%q", v)
	elseif t == "Vector3" then return "V3" .. v3s(v)
	elseif t == "Vector2" then return string.format("V2(%s, %s)", fmtNum(v.X), fmtNum(v.Y))
	elseif t == "CFrame" then
		local rel = localTo(v)
		return "CF" .. v3s(v.Position) .. (rel and (" [you→" .. v3s(rel.Position) .. "]") or "")
	elseif t == "Color3" then return c3hex(v)
	elseif t == "NumberSequence" or t == "ColorSequence" or t == "NumberRange" then return "[" .. seqShort(v) .. "]"
	elseif t == "EnumItem" then return tostring(v)
	elseif t == "Instance" then
		local c = characterOf(v)
		if c == myChar() then return "<YOU" .. (v ~= c and ("." .. v.Name) or "") .. ">" end
		return "<" .. v.ClassName .. " " .. shortPath(v, 3) .. ">"
	elseif t == "table" then
		seen = seen or {}
		if seen[v] then return "<cycle>" end
		if depth >= 3 then return "{…}" end
		seen[v] = true
		local out, n = {}, 0
		local isArray = #v > 0
		for k, val in v do
			n += 1
			if n > 14 then table.insert(out, "…") break end
			if isArray and type(k) == "number" then
				table.insert(out, ser(val, depth + 1, seen))
			else
				local key = type(k) == "string" and (string.match(k, "^[%a_][%w_]*$") and k or string.format("[%q]", k)) or ("[" .. ser(k, depth + 1, seen) .. "]")
				table.insert(out, key .. "=" .. ser(val, depth + 1, seen))
			end
		end
		seen[v] = nil
		return "{" .. table.concat(out, ", ") .. "}"
	end
	return "<" .. t .. ">"
end
local function plain(v, depth)
	depth = depth or 0
	local t = typeof(v)
	if t == "number" then return r(v, 4)
	elseif t == "string" or t == "boolean" or t == "nil" then return v
	elseif t == "Vector3" then return { r(v.X, 3), r(v.Y, 3), r(v.Z, 3) }
	elseif t == "CFrame" then
		local rx, ry, rz = v:ToOrientation()
		return { pos = { r(v.X, 3), r(v.Y, 3), r(v.Z, 3) }, rotDeg = { r(math.deg(rx), 2), r(math.deg(ry), 2), r(math.deg(rz), 2) } }
	elseif t == "Color3" then return c3hex(v)
	elseif t == "table" then
		if depth > 7 then return "{…}" end
		local o = {}
		for k, val in v do o[type(k) == "number" and k or tostring(k)] = plain(val, depth + 1) end
		return o
	end
	return ser(v)
end

local MOVER_CLASSES = {
	BodyVelocity = true, BodyPosition = true, BodyGyro = true, BodyForce = true, BodyAngularVelocity = true, BodyThrust = true,
	LinearVelocity = true, AlignPosition = true, AlignOrientation = true, VectorForce = true, AngularVelocity = true, Torque = true,
}
local VISUAL_CLASSES = {
	ParticleEmitter = true, Beam = true, Trail = true, Highlight = true, PointLight = true, SpotLight = true, SurfaceLight = true,
	Explosion = true, Fire = true, Smoke = true, Sparkles = true, BillboardGui = true, SurfaceGui = true,
}
local HITBOX_NAMES = { "hitbox", "hit box", "hurtbox", "hit_box", "hbox", "damagebox", "damagearea", "aoe", "hb" }

---------------------------------------------------------------------------------------------------
-- recorder state
---------------------------------------------------------------------------------------------------
local Rec = {
	state = "idle", t0 = 0, events = {}, preroll = {}, victims = {}, lastActivity = 0,
	startCF = nil, path = {}, victimPaths = {}, saveFolder = nil, count = 0,
	advanced = false, phase = "hit", noVictims = false, hitStart = nil,
}
local History = {}
local Selected = 0
local UI = {}
local Hooks = {}

local log, markVictim, isHitboxName, hookHitboxPart, describeEffect, emitterDump, meshDump, emitterText
local trackCharacter, hookSound, hookRemote, arm, setState, startRecording, stopRecording, startHitPhase
local toast, copyText

local function isMine(inst)
	if not inst then return false end
	if ownGui and (inst == ownGui or inst:IsDescendantOf(ownGui)) then return true end
	if LoggedRoot and inst:IsDescendantOf(LoggedRoot) then return true end
	return false
end
local function inRange(pos)
	local root = myRoot()
	if not root or not pos then return false end
	return (pos - root.Position).Magnitude <= CONFIG.Radius
end
local function whoName(model)
	if not model then return "WORLD" end
	if model == myChar() then return "YOU" end
	return model.Name
end
local function inScope(model)
	if not model then return false end
	if model == myChar() then return true end
	if Rec.victims[model] then return true end
	if not CONFIG.TrackOthers then return false end
	local root = rootOf(model)
	return root ~= nil and inRange(root.Position)
end

function log(cat, who, text, data)
	if Rec.state == "idle" then return nil end
	local ev = { t = now(), cat = cat, who = whoName(who), model = who, text = text, data = data or {} }
	if who and who ~= myChar() and Rec.victims[who] then ev.victim = true end
	if Rec.state == "armed" then
		table.insert(Rec.preroll, ev)
		local cut = now() - CONFIG.Preroll
		while #Rec.preroll > 0 and Rec.preroll[1].t < cut do table.remove(Rec.preroll, 1) end
		while #Rec.preroll > 500 do table.remove(Rec.preroll, 1) end
	else
		if #Rec.events >= CONFIG.MaxEvents then return ev end
		table.insert(Rec.events, ev)
		if who == nil or who == myChar() or ev.victim then Rec.lastActivity = now() end
		if Hooks.onEvent then task.spawn(guard(Hooks.onEvent), ev) end
	end
	return ev
end

function markVictim(model, reason)
	if not model or model == myChar() or Rec.noVictims then return nil end
	local existing = Rec.victims[model]
	if existing then
		if reason and not existing[reason] then existing[reason] = true end
		return existing
	end
	local root = rootOf(model)
	if root and not inRange(root.Position) then return nil end
	local entry = { name = model.Name, firstAt = now(), reason = reason }
	if reason then entry[reason] = true end
	Rec.victims[model] = entry
	for _, ev in Rec.events do
		if ev.model == model then ev.victim = true end
	end
	log("STATE", model, string.format("victim tracked (%s)", reason or "?"), { kind = "victimStart", reason = reason })
	return entry
end

---------------------------------------------------------------------------------------------------
-- animations
---------------------------------------------------------------------------------------------------
local kfsCache = {}
local function fetchKeyframes(id)
	if kfsCache[id] ~= nil then return end
	kfsCache[id] = false
	task.spawn(guard(function()
		local ok, kfs = pcall(function()
			return KeyframeSequenceProvider:GetKeyframeSequenceAsync("rbxassetid://" .. tostring(id))
		end)
		if not ok or not kfs then return end
		local info = { markers = {}, keyframes = {}, length = 0 }
		pcall(function()
			for _, kf in kfs:GetKeyframes() do
				info.length = math.max(info.length, kf.Time)
				if kf.Name ~= "Keyframe" and kf.Name ~= "" then
					table.insert(info.keyframes, { name = kf.Name, time = kf.Time })
				end
				for _, m in kf:GetMarkers() do
					table.insert(info.markers, { name = m.Name, time = kf.Time, value = m.Value })
				end
			end
		end)
		table.sort(info.markers, function(a, b) return a.time < b.time end)
		kfsCache[id] = info
		pcall(function() kfs:Destroy() end)
	end))
end

local activeTracks = {}
local function isCoreAnim(track, model)
	if track.Priority == Enum.AnimationPriority.Core then return true end
	local anim = track.Animation
	if anim then
		local node = anim.Parent
		while node and node ~= model do
			if node.Name == "Animate" then return true end
			node = node.Parent
		end
	end
	return false
end

local function onAnimationPlayed(model, track)
	if Rec.state == "idle" or not inScope(model) then return end
	if CONFIG.IgnoreCoreAnims and isCoreAnim(track, model) then return end
	local anim = track.Animation
	local id = anim and assetNum(anim.AnimationId) or "?"
	if model == myChar() and Rec.state == "armed" and CONFIG.StartOnAnim
		and track.Priority.Value >= Enum.AnimationPriority.Action.Value then
		startRecording("animation " .. (anim and anim.Name or id), "startup")
	end
	if model ~= myChar() then markVictim(model, "animation") end
	fetchKeyframes(id)
	local data = {
		id = id, name = anim and anim.Name or "?", priority = track.Priority.Name, looped = track.Looped,
		speed = r(track.Speed, 3), length = r(track.Length, 3), weight = r(track.WeightTarget, 3),
	}
	local ev = log("ANIM", model, string.format("▶ %s  rbxassetid://%s  (%s%s, speed %s)", data.name, id, data.priority,
		data.looped and ", looped" or "", fmtNum(data.speed, 2)), data)
	if not ev then return end

	local started = now()
	activeTracks[track] = { ev = ev, model = model, speed = track.Speed, started = started, lastTp = 0 }
	local conns = {}
	local function addConn(c) table.insert(conns, c) end

	addConn(track.KeyframeReached:Connect(guard(function(name)
		log("MARKER", model, string.format("◆ keyframe '%s' @%ss  (%s)", name, fmtNum(track.TimePosition, 3), data.name),
			{ anim = id, name = name, kind = "keyframe", at = r(track.TimePosition, 3) })
	end)))
	addConn(track.DidLoop:Connect(guard(function(count)
		log("ANIM", model, string.format("↻ %s looped x%d @%ss", data.name, count, fmtNum(track.TimePosition, 2)),
			{ anim = id, kind = "loop", count = count, at = r(track.TimePosition, 3) })
	end)))

	local function hookMarkers()
		local info = kfsCache[id]
		if not info or data.markers then return end
		data.markers = {}
		local seen = {}
		for _, m in info.markers do
			table.insert(data.markers, { name = m.name, time = r(m.time, 3), value = m.value })
			if not seen[m.name] then
				seen[m.name] = true
				addConn(track:GetMarkerReachedSignal(m.name):Connect(guard(function(param)
					log("MARKER", model, string.format("◆ marker '%s' @%ss%s  (%s)", m.name, fmtNum(track.TimePosition, 3),
						(param and param ~= "") and (" = " .. tostring(param)) or "", data.name),
						{ anim = id, name = m.name, param = param, kind = "marker", at = r(track.TimePosition, 3) })
				end)))
			end
		end
		data.keyframes = info.keyframes
	end
	hookMarkers()
	if not kfsCache[id] then
		task.spawn(guard(function()
			for _ = 1, 40 do
				task.wait(0.05)
				if kfsCache[id] then hookMarkers() break end
			end
		end))
	end

	track.Stopped:Once(guard(function()
		for _, c in conns do c:Disconnect() end
		activeTracks[track] = nil
		local played = now() - started
		data.played = r(played, 3)
		log("ANIM", model, string.format("■ %s stopped after %ss", data.name, fmtNum(played, 3)),
			{ id = id, name = data.name, kind = "stop", played = data.played })
	end))
end

local function snapshotTracks(model)
	local hum = model:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in safe(function() return animator:GetPlayingAnimationTracks() end) or {} do
		local anim = track.Animation
		log("ANIM", model, string.format("≡ already playing %s (rbxassetid://%s) at %ss", anim and anim.Name or "?",
			anim and assetNum(anim.AnimationId) or "?", fmtNum(track.TimePosition, 2)),
			{ id = anim and assetNum(anim.AnimationId) or "?", name = anim and anim.Name or "?", kind = "alreadyPlaying" })
	end
end

---------------------------------------------------------------------------------------------------
-- effect detail dump — every readable property, every asset id, every colour
---------------------------------------------------------------------------------------------------
local EMITTER_PROPS = {
	"Enabled", "Texture", "Color", "Size", "Transparency", "Lifetime", "Rate", "Speed", "SpreadAngle", "Rotation", "RotSpeed",
	"Acceleration", "Drag", "VelocityInheritence", "LightEmission", "LightInfluence", "ZOffset", "EmissionDirection",
	"Shape", "ShapeStyle", "ShapeInOut", "ShapePartial", "Squash", "Orientation", "LockedToPart", "TimeScale", "WindAffectsDrag",
	"FlipbookLayout", "FlipbookFramerate", "FlipbookStartRandom", "FlipbookStartFrame", "FlipbookParticleCount",
	"LocalTransparencyModifier",
}
local BEAM_PROPS = {
	"Enabled", "Texture", "TextureLength", "TextureMode", "TextureSpeed", "Color", "Transparency", "Width0", "Width1",
	"CurveSize0", "CurveSize1", "Segments", "LightEmission", "LightInfluence", "FaceCamera", "ZOffset",
	"Attachment0", "Attachment1",
}
local TRAIL_PROPS = {
	"Enabled", "Texture", "TextureLength", "TextureMode", "Color", "Transparency", "Lifetime", "WidthScale", "MinLength",
	"LightEmission", "FaceCamera", "Attachment0", "Attachment1",
}
local MESH_PROPS = {
	"MeshId", "TextureId", "TextureID", "MeshType", "Scale", "Offset", "VertexColor", "RenderFidelity", "ColorMap",
	"NormalMap", "RoughnessMap", "MetalnessMap", "AlphaMode", "Texture", "Transparency", "Color", "Material",
}
local SOUND_PROPS = { "SoundId", "Volume", "PlaybackSpeed", "Looped", "Playing", "TimePosition", "RollOffMode",
	"RollOffMinDistance", "RollOffMaxDistance", "EmitterSize", "PlayOnRemove", "SoundGroup", "TimeLength" }

-- properties that are noise or already captured elsewhere
local NOISE_PROPS = {
	Name = true, Parent = true, ClassName = true, Archivable = true, RobloxLocked = true, Sandboxed = true,
	SecurityCapabilities = true, UniqueId = true, Attributes = true, AttributesSerialize = true, Tags = true,
	HistoryId = true, SourceAssetId = true, InternalSize = true,
}

-- anything that is an asset reference
local function isAssetKey(key, value)
	if type(value) ~= "string" or value == "" or #value > 300 then return false end
	if string.find(key, "Texture") or string.find(key, "MeshId") or string.find(key, "SoundId")
		or string.find(key, "Image") or string.find(key, "Map") or string.find(key, "Mesh") then
		return true
	end
	return assetNum(value) ~= nil and (string.find(value, "rbxasset", 1, true) ~= nil or string.find(value, "http", 1, true) ~= nil)
end

local function propValue(inst, key)
	local ok, v = pcall(function() return inst[key] end)
	if not ok then return nil, nil end
	return v, typeof(v)
end

local function storeProp(d, key, v, t)
	if t == "EnumItem" then
		local full = tostring(v)
		local etype, eval = string.match(full, "^Enum%.([%w_]+)%.([%w_]+)$")
		d[key] = { kind = "enum", enumType = etype, value = eval, full = full }
	elseif t == "ColorSequence" then
		local dumped = seqDump(v)
		d[key] = dumped
		for _, kp in dumped.keypoints do table.insert(d.colors, { property = key, hex = kp.color, rgb = kp.rgb }) end
	elseif t == "NumberSequence" or t == "NumberRange" then
		d[key] = seqDump(v)
	elseif t == "Color3" then
		d[key] = { kind = "color3", hex = c3hex(v), rgb = c3rgb(v) }
		table.insert(d.colors, { property = key, hex = c3hex(v), rgb = c3rgb(v) })
	elseif t == "BrickColor" then
		d[key] = v.Name
	elseif t == "Vector3" then
		d[key] = { r(v.X, 3), r(v.Y, 3), r(v.Z, 3) }
	elseif t == "Vector2" then
		d[key] = { r(v.X, 3), r(v.Y, 3) }
	elseif t == "CFrame" then
		local rel = localTo(v)
		d[key] = { pos = { r(v.X, 3), r(v.Y, 3), r(v.Z, 3) },
			local = rel and { r(rel.Position.X, 3), r(rel.Position.Y, 3), r(rel.Position.Z, 3) } or nil }
	elseif t == "number" then
		d[key] = r(v, 4)
	elseif t == "boolean" then
		d[key] = v
	elseif t == "string" then
		d[key] = v
		if isAssetKey(key, v) then table.insert(d.assets, { property = key, raw = v, id = assetNum(v) }) end
	elseif t == "Rect" then
		d[key] = { min = { r(v.Min.X, 2), r(v.Min.Y, 2) }, max = { r(v.Max.X, 2), r(v.Max.Y, 2) } }
	elseif t == "UDim2" then
		d[key] = { x = { r(v.X.Scale, 3), v.X.Offset }, y = { r(v.Y.Scale, 3), v.Y.Offset } }
	elseif t == "UDim" then
		d[key] = { scale = r(v.Scale, 3), offset = v.Offset }
	elseif t == "Instance" then
		local cf = v:IsA("Attachment") and v.WorldCFrame or nil
		local rel = cf and localTo(cf)
		d[key] = { path = shortPath(v, 4), class = v.ClassName,
			world = cf and { r(cf.Position.X, 2), r(cf.Position.Y, 2), r(cf.Position.Z, 2) } or nil,
			local = rel and { r(rel.Position.X, 2), r(rel.Position.Y, 2), r(rel.Position.Z, 2) } or nil }
	end
end

local function dumpProps(inst, props)
	local d = { assets = {}, colors = {} }
	local seen = {}
	local function take(key)
		if seen[key] or NOISE_PROPS[key] then return end
		seen[key] = true
		local v, t = propValue(inst, key)
		if v == nil or t == "function" or t == "table" or t == "thread" then return end
		storeProp(d, key, v, t)
	end
	for _, p in props do take(p) end
	-- then every other readable property, so nothing is missed
	local ok, all = pcall(function() return inst:GetProperties() end)
	if ok and type(all) == "table" then
		local keys = {}
		for k in all do if type(k) == "string" then table.insert(keys, k) end end
		table.sort(keys)
		for _, k in keys do take(k) end
	end
	if next(d.assets) == nil then d.assets = nil end
	if next(d.colors) == nil then d.colors = nil end
	return d
end

function emitterDump(e)
	if not e then return nil end
	local props = e:IsA("Beam") and BEAM_PROPS or (e:IsA("Trail") and TRAIL_PROPS or EMITTER_PROPS)
	local d = dumpProps(e, props)
	d.class = e.ClassName
	d.name = e.Name
	local host = e.Parent
	if host then
		d.hostName = host.Name
		d.hostClass = host.ClassName
		d.hostPath = shortPath(host, 4)
		if host:IsA("BasePart") then
			d.hostSize = { r(host.Size.X, 3), r(host.Size.Y, 3), r(host.Size.Z, 3) }
			d.hostMaterial = host.Material.Name
			d.hostTransparency = r(host.Transparency, 3)
			d.hostColor = c3hex(host.Color)
			d.hostColorRgb = c3rgb(host.Color)
			d.hostShape = host:IsA("Part") and host.Shape.Name or nil
			d.hostCanCollide = host.CanCollide
			local rel = localTo(host.CFrame)
			if rel then d.hostOffset = { r(rel.Position.X, 3), r(rel.Position.Y, 3), r(rel.Position.Z, 3) } end
			local htex = host:IsA("MeshPart") and host.TextureID or get(host, "Texture")
			if type(htex) == "string" and htex ~= "" then
				d.hostTexture = { raw = htex, id = assetNum(htex) }
				table.insert(d.assets, { property = "HostTexture", raw = htex, id = assetNum(htex) })
			end
			local hmesh = host:IsA("MeshPart") and host.MeshId or nil
			if type(hmesh) == "string" and hmesh ~= "" then
				d.hostMeshId = { raw = hmesh, id = assetNum(hmesh) }
				table.insert(d.assets, { property = "HostMeshId", raw = hmesh, id = assetNum(hmesh) })
			end
			if not d.colors then d.colors = {} end
			table.insert(d.colors, { property = "HostColor", hex = c3hex(host.Color), rgb = c3rgb(host.Color) })
		elseif host:IsA("Attachment") then
			local rel = localTo(host.WorldCFrame)
			if rel then d.hostOffset = { r(rel.Position.X, 3), r(rel.Position.Y, 3), r(rel.Position.Z, 3) } end
			d.hostParent = host.Parent and host.Parent.Name
			d.hostParentClass = host.Parent and host.Parent.ClassName
			if host.Parent and host.Parent:IsA("BasePart") then
				d.hostSize = { r(host.Parent.Size.X, 3), r(host.Parent.Size.Y, 3), r(host.Parent.Size.Z, 3) }
			end
		end
	end
	if not d.assets then d.assets = nil end
	if not d.colors then d.colors = nil end
	return d
end

function meshDump(inst)
	local d = dumpProps(inst, MESH_PROPS)
	d.class = inst.ClassName
	d.name = inst.Name
	if inst:IsA("BasePart") then
		d.size = { r(inst.Size.X, 3), r(inst.Size.Y, 3), r(inst.Size.Z, 3) }
		d.colorHex = c3hex(inst.Color)
		d.colorRgb = c3rgb(inst.Color)
	end
	if not d.assets then d.assets = nil end
	if not d.colors then d.colors = nil end
	return d
end

function soundDump(s)
	local d = dumpProps(s, SOUND_PROPS)
	d.class = s.ClassName
	d.name = s.Name
	d.parent = s.Parent and shortPath(s.Parent, 4) or nil
	if not d.assets then d.assets = nil end
	if not d.colors then d.colors = nil end
	return d
end

function isHitboxName(name)
	local n = string.lower(tostring(name))
	for _, p in HITBOX_NAMES do if string.find(n, p, 1, true) then return true end end
	return false
end

local function hasVisualDescendant(inst)
	if VISUAL_CLASSES[inst.ClassName] or inst:IsA("Decal") or inst:IsA("Texture") then return true end
	for _, d in inst:GetDescendants() do
		if VISUAL_CLASSES[d.ClassName] or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SpecialMesh") then return true end
		if d:IsA("BasePart") and d.Transparency < 0.98 then return true end
	end
	if inst:IsA("BasePart") and inst.Transparency < 0.98 then return true end
	return false
end

local function hitboxKind(inst)
	if not inst:IsA("BasePart") then return nil end
	if isHitboxName(inst.Name) then return "named" end
	if inst.Transparency >= 0.98 and not inst.CanCollide and inst.Size.Magnitude > 2.5 and not hasVisualDescendant(inst) then return "invisible" end
	return nil
end

function describeEffect(inst)
	local d = { name = inst.Name, class = inst.ClassName, path = shortPath(inst.Parent, 3), folder = inst.Parent and inst.Parent.Name,
		assets = {}, colors = {} }
	if inst:IsA("BasePart") then
		d.size, d.material, d.transparency, d.color = inst.Size, inst.Material.Name, r(inst.Transparency, 3), c3hex(inst.Color)
		d.colorRgb = c3rgb(inst.Color)
		d.anchored, d.canCollide, d.canTouch, d.canQuery, d.massless = inst.Anchored, inst.CanCollide, inst.CanTouch, inst.CanQuery, inst.Massless
		d.shape = inst:IsA("Part") and inst.Shape.Name or nil
		d.velocity, d.localVelocity = inst.AssemblyLinearVelocity, localDir(inst.AssemblyLinearVelocity)
		table.insert(d.colors, { property = "Color", hex = c3hex(inst.Color), rgb = c3rgb(inst.Color) })
		local htex = inst:IsA("MeshPart") and inst.TextureID or get(inst, "Texture")
		if type(htex) == "string" and htex ~= "" then
			d.hostTexture = htex
			table.insert(d.assets, { property = "HostTexture", raw = htex, id = assetNum(htex) })
		end
		local hmesh = inst:IsA("MeshPart") and inst.MeshId or nil
		if type(hmesh) == "string" and hmesh ~= "" then
			d.hostMeshId = hmesh
			table.insert(d.assets, { property = "HostMeshId", raw = hmesh, id = assetNum(hmesh) })
		end
	elseif inst:IsA("Model") then
		d.size = safe(inst.GetExtentsSize, inst)
	end
	local attrs = inst:GetAttributes()
	if next(attrs) then d.attributes = attrs end
	local cf = cframeOf(inst)
	if cf then
		local rel = localTo(cf)
		if rel then d.offset = rel.Position d.offsetCF = rel end
		if Rec.startCF then d.startOffset = Rec.startCF:ToObjectSpace(cf).Position end
	end
	d.emitters, d.beams, d.trails, d.meshes, d.sounds, d.contents = {}, {}, {}, {}, {}, {}
	local function scan(node)
		local cls = node.ClassName
		d.contents[cls] = (d.contents[cls] or 0) + 1
		if node:IsA("ParticleEmitter") then
			table.insert(d.emitters, emitterDump(node))
		elseif node:IsA("Beam") then
			table.insert(d.beams, emitterDump(node))
		elseif node:IsA("Trail") then
			table.insert(d.trails, emitterDump(node))
		elseif node:IsA("SpecialMesh") or node:IsA("MeshPart") or node:IsA("SurfaceAppearance") or node:IsA("Decal") or node:IsA("Texture") then
			table.insert(d.meshes, meshDump(node))
		elseif node:IsA("Sound") then
			table.insert(d.sounds, soundDump(node))
		end
	end
	scan(inst)
	for _, node in inst:GetDescendants() do scan(node) end
	-- roll every asset and colour up to the effect so nothing hides in a child
	for _, group in { d.emitters, d.beams, d.trails, d.meshes } do
		for _, e in group do
			for _, a in e.assets or {} do table.insert(d.assets, a) end
			for _, c in e.colors or {} do table.insert(d.colors, c) end
		end
	end
	for _, s in d.sounds do
		for _, a in s.assets or {} do table.insert(d.assets, a) end
	end
	if #d.assets == 0 then d.assets = nil end
	if #d.colors == 0 then d.colors = nil end
	for _, w in inst:GetDescendants() do
		if w:IsA("WeldConstraint") or w:IsA("Weld") or w:IsA("Motor6D") then
			local other = (w.Part0 and not w.Part0:IsDescendantOf(inst)) and w.Part0 or ((w.Part1 and not w.Part1:IsDescendantOf(inst)) and w.Part1 or nil)
			if other then
				local c = characterOf(other)
				d.weldedTo = (c and (whoName(c) .. ".") or "") .. other.Name
				break
			end
		end
	end
	return d
end

function emitterText(e)
	local bits = {}
	if e.Texture then
		local t = type(e.Texture) == "table" and e.Texture.raw or e.Texture
		if t and t ~= "" then table.insert(bits, "tex " .. tostring(assetNum(t) or t)) end
	end
	if e.Rate then table.insert(bits, "rate " .. fmtNum(e.Rate, 2)) end
	if e.Lifetime and type(e.Lifetime) == "table" then table.insert(bits, "life " .. seqShort(seqFromDump(e.Lifetime))) end
	if e.Speed and type(e.Speed) == "table" then table.insert(bits, "speed " .. seqShort(seqFromDump(e.Speed))) end
	if e.Size and type(e.Size) == "table" then table.insert(bits, "size " .. seqShort(seqFromDump(e.Size))) end
	if e.Color and type(e.Color) == "table" and e.Color.keypoints then
		local hexes = {}
		for _, kp in e.Color.keypoints do table.insert(hexes, kp.color) end
		table.insert(bits, "color " .. table.concat(hexes, "→"))
	end
	if e.SpreadAngle and type(e.SpreadAngle) == "table" then table.insert(bits, "spread " .. seqShort(seqFromDump(e.SpreadAngle))) end
	if e.Shape and type(e.Shape) == "table" then table.insert(bits, "shape " .. tostring(e.Shape.value)) end
	if e.LightEmission and e.LightEmission > 0 then table.insert(bits, "light " .. fmtNum(e.LightEmission, 2)) end
	return table.concat(bits, " ")
end

-- render a dumped sequence back to a short display string
function seqFromDump(dumped)
	if type(dumped) ~= "table" then return dumped end
	if dumped.kind == "number" then
		local parts = {}
		for _, kp in dumped.keypoints or {} do table.insert(parts, fmtNum(kp.time, 2) .. ":" .. fmtNum(kp.value, 3)) end
		return table.concat(parts, " → ")
	elseif dumped.kind == "color" then
		local parts = {}
		for _, kp in dumped.keypoints or {} do table.insert(parts, fmtNum(kp.time, 2) .. ":" .. tostring(kp.color)) end
		return table.concat(parts, " → ")
	elseif dumped.kind == "range" then
		return fmtNum(dumped.min, 3) .. "–" .. fmtNum(dumped.max, 3)
	end
	return tostring(dumped)
end