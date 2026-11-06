--[[
	MoveLogger v2.4  ·  general move recorder for battlegrounds-style games (executor build)

	Every recording becomes its own MOVE BLOCK in the Moves tab — one block per move, each with
	its own copy buttons for table / replay / summary / timeline / JSON.

	ADVANCED MODE (Record page or Settings): records in two phases — STARTUP first (no victims,
	pure wind-up), then "Record hit" (F9) at the moment it lands, then "Done". One block, boundary
	marked, startup and hit kept separate.

	  ANIM · MARKER · VELOCITY · SOUND · VFX · HITBOX · MOVE · HIT · STATE · CAMERA · SCREEN ·
	  REMOTE · REPLICATION

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
		for _, kp in seq.Keypoints do table.insert(out, { time = r(kp.Time, 4), color = c3hex(kp.Value), envelope = r(kp.Envelope, 4) }) end
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

-- class tables (declared before anything that reads them)
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

-- forward declarations
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
-- effect detail dump
---------------------------------------------------------------------------------------------------
local EMITTER_PROPS = {
	"Enabled", "Texture", "Color", "Size", "Transparency", "Lifetime", "Rate", "Speed", "SpreadAngle", "Rotation", "RotSpeed",
	"Acceleration", "Drag", "VelocityInheritence", "LightEmission", "LightInfluence", "ZOffset", "EmissionDirection",
	"Shape", "ShapeStyle", "ShapeInOut", "ShapePartial", "Squash", "Orientation", "LockedToPart", "TimeScale", "WindAffectsDrag",
	"FlipbookLayout", "FlipbookFramerate", "FlipbookStartRandom", "FlipbookStartFrame", "FlipbookParticleCount",
}
local BEAM_PROPS = {
	"Enabled", "Texture", "TextureLength", "TextureMode", "TextureSpeed", "Color", "Transparency", "Width0", "Width1",
	"CurveSize0", "CurveSize1", "Segments", "LightEmission", "LightInfluence", "FaceCamera", "ZOffset",
}
local TRAIL_PROPS = {
	"Enabled", "Texture", "TextureLength", "TextureMode", "Color", "Transparency", "Lifetime", "WidthScale", "MinLength",
	"LightEmission", "FaceCamera",
}
local SEQ_PROPS = {
	Color = true, Size = true, Transparency = true, SpreadAngle = true, Rotation = true, RotSpeed = true,
	Speed = true, Acceleration = true, Drag = true, Lifetime = true, Width0 = true, Width1 = true, WidthScale = true,
}

local function dumpProps(inst, props)
	local d = {}
	for _, p in props do
		local v = get(inst, p)
		if v ~= nil then
			if typeof(v) == "EnumItem" then
				d[p] = tostring(v)
			elseif typeof(v) == "NumberSequence" or typeof(v) == "ColorSequence" or typeof(v) == "NumberRange" then
				d[p] = seqDump(v)
			elseif typeof(v) == "Vector3" then
				d[p] = { r(v.X, 3), r(v.Y, 3), r(v.Z, 3) }
			elseif typeof(v) == "number" then
				d[p] = r(v, 4)
			elseif typeof(v) == "string" then
				d[p] = v
			elseif typeof(v) == "boolean" then
				d[p] = v
			end
		end
	end
	local attrs = inst:GetAttributes()
	if next(attrs) then d.attributes = plain(attrs) end
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
			d.hostShape = host:IsA("Part") and host.Shape.Name or nil
			d.hostCanCollide = host.CanCollide
			local rel = localTo(host.CFrame)
			if rel then d.hostOffset = { r(rel.Position.X, 3), r(rel.Position.Y, 3), r(rel.Position.Z, 3) } end
		elseif host:IsA("Attachment") then
			local rel = localTo(host.WorldCFrame)
			if rel then d.hostOffset = { r(rel.Position.X, 3), r(rel.Position.Y, 3), r(rel.Position.Z, 3) } end
			d.hostParent = host.Parent and host.Parent.Name
			if host.Parent and host.Parent:IsA("BasePart") then
				d.hostSize = { r(host.Parent.Size.X, 3), r(host.Parent.Size.Y, 3), r(host.Parent.Size.Z, 3) }
			end
		end
	end
	return d
end

function meshDump(inst)
	local d = { class = inst.ClassName, name = inst.Name }
	if inst:IsA("SpecialMesh") then
		d.meshId, d.textureId, d.meshType = inst.MeshId, inst.TextureId, inst.MeshType.Name
		d.scale = { r(inst.Scale.X, 3), r(inst.Scale.Y, 3), r(inst.Scale.Z, 3) }
		d.offset = { r(inst.Offset.X, 3), r(inst.Offset.Y, 3), r(inst.Offset.Z, 3) }
	elseif inst:IsA("MeshPart") then
		d.meshId, d.textureId, d.renderFidelity = inst.MeshId, inst.TextureID, inst.RenderFidelity.Name
		d.size = { r(inst.Size.X, 3), r(inst.Size.Y, 3), r(inst.Size.Z, 3) }
	elseif inst:IsA("SurfaceAppearance") then
		d.colorMap, d.normalMap, d.roughnessMap, d.metalnessMap, d.alphaMode =
			inst.ColorMap, inst.NormalMap, inst.RoughnessMap, inst.MetalnessMap, inst.AlphaMode.Name
	elseif inst:IsA("Decal") or inst:IsA("Texture") then
		d.texture = inst.Texture
	end
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
	local d = { name = inst.Name, class = inst.ClassName, path = shortPath(inst.Parent, 3), folder = inst.Parent and inst.Parent.Name }
	if inst:IsA("BasePart") then
		d.size, d.material, d.transparency, d.color = inst.Size, inst.Material.Name, r(inst.Transparency, 3), c3hex(inst.Color)
		d.anchored, d.canCollide, d.canTouch, d.canQuery, d.massless = inst.Anchored, inst.CanCollide, inst.CanTouch, inst.CanQuery, inst.Massless
		d.shape = inst:IsA("Part") and inst.Shape.Name or nil
		d.velocity, d.localVelocity = inst.AssemblyLinearVelocity, localDir(inst.AssemblyLinearVelocity)
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
			table.insert(d.sounds, { name = node.Name, id = assetNum(node.SoundId), volume = r(node.Volume, 2), speed = r(node.PlaybackSpeed, 2),
				looped = node.Looped, playing = node.Playing, rollOffMode = node.RollOffMode.Name })
		end
	end
	scan(inst)
	for _, node in inst:GetDescendants() do scan(node) end
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
	if e.Texture and e.Texture ~= "" then table.insert(bits, "tex " .. (assetNum(e.Texture) or e.Texture)) end
	if e.Rate then table.insert(bits, "rate " .. fmtNum(e.Rate, 2)) end
	if e.Lifetime then table.insert(bits, "life " .. seqShort(e.Lifetime)) end
	if e.Speed then table.insert(bits, "speed " .. seqShort(e.Speed)) end
	if e.Size then table.insert(bits, "size " .. seqShort(e.Size)) end
	if e.Color then table.insert(bits, "color " .. seqShort(e.Color)) end
	if e.SpreadAngle then table.insert(bits, "spread " .. seqShort(e.SpreadAngle)) end
	if e.Shape then table.insert(bits, "shape " .. e.Shape.Name) end
	if e.LightEmission and e.LightEmission > 0 then table.insert(bits, "light " .. fmtNum(e.LightEmission, 2)) end
	return table.concat(bits, " ")
end

---------------------------------------------------------------------------------------------------
-- characters
---------------------------------------------------------------------------------------------------
local tracked = setmetatable({}, { __mode = "k" })

local function moverVelocity(m)
	if m:IsA("BodyVelocity") then return m.Velocity, "Velocity" end
	if m:IsA("LinearVelocity") then return m.VectorVelocity, "VectorVelocity" end
	if m:IsA("BodyForce") or m:IsA("VectorForce") then return m.Force, "Force" end
	return nil
end

local function moverInfo(m, who)
	local d = { class = m.ClassName, name = m.Name }
	local txt, cls = m.ClassName, m.ClassName
	if cls == "BodyVelocity" then
		local lv = localDir(m.Velocity)
		d.velocity, d.localVelocity, d.maxForce, d.p = m.Velocity, lv, m.MaxForce, m.P
		txt = "BodyVelocity " .. dirWords(lv) .. "  (|v| " .. fmtNum(m.Velocity.Magnitude, 1) .. ")"
	elseif cls == "LinearVelocity" then
		local v = m.VectorVelocity
		if m.RelativeTo == Enum.ActuatorRelativeTo.World then v = localDir(v) end
		d.vectorVelocity, d.localVelocity, d.relativeTo, d.maxForce, d.mode = m.VectorVelocity, v, m.RelativeTo.Name, m.MaxForce, m.VelocityConstraintMode.Name
		txt = "LinearVelocity " .. dirWords(v) .. "  (" .. m.RelativeTo.Name .. ", " .. m.VelocityConstraintMode.Name .. ")"
	elseif cls == "BodyPosition" or cls == "AlignPosition" then
		local rel = localTo(CFrame.new(m.Position))
		d.position, d.localPosition, d.maxForce = m.Position, rel and rel.Position, m.MaxForce
		txt = cls .. " → " .. (rel and dirWords(rel.Position) or v3s(m.Position))
	elseif cls == "BodyGyro" or cls == "AlignOrientation" then
		d.cframe = m.CFrame
		txt = cls .. " (turns " .. (who == myChar() and "you" or "them") .. ")"
	elseif cls == "VectorForce" or cls == "BodyForce" then
		d.force, d.localForce = m.Force, localDir(m.Force)
		txt = cls .. " " .. dirWords(d.localForce)
	elseif cls == "BodyAngularVelocity" or cls == "AngularVelocity" then
		d.angularVelocity = m.AngularVelocity
		txt = cls .. " " .. v3s(m.AngularVelocity)
	end
	return txt, d
end

local function logMover(m, who)
	if not m.Parent then return end
	if who and who ~= myChar() then markVictim(who, "mover") end
	local txt, d = moverInfo(m, who)
	local ev = log("MOVE", who, "+ " .. txt, d)
	if not ev then return end
	local born = now()
	local samples = {}
	d.velocityTrack = samples
	local velProp = select(2, moverVelocity(m))
	local velConn
	if velProp then
		velConn = m:GetPropertyChangedSignal(velProp):Connect(guard(function()
			local v = moverVelocity(m)
			if not v or #samples > 60 then return end
			local lv = localDir(v)
			table.insert(samples, { t = r(now() - born, 3), value = lv, speed = r(v.Magnitude, 2) })
			log("VELOCITY", who, string.format("mover %s → %s  (|v| %s)", m.ClassName, dirWords(lv), fmtNum(v.Magnitude, 1)),
				{ kind = "moverChange", class = m.ClassName, localVelocity = lv, speed = r(v.Magnitude, 2) })
		end))
	end
	local conn
	conn = m.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			conn:Disconnect()
			if velConn then velConn:Disconnect() end
			d.duration = r(now() - born, 3)
			log("MOVE", who, string.format("- %s removed after %ss", m.ClassName, fmtNum(d.duration, 3)), { class = m.ClassName, kind = "end", duration = d.duration })
		end
	end)
end

local function logVisualToggle(inst, who)
	if not (inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Highlight")) then return end
	local info = tracked[who]
	if not info then return end
	table.insert(info.conns, inst:GetPropertyChangedSignal("Enabled"):Connect(guard(function()
		if Rec.state == "idle" or not inScope(who) then return end
		log("VFX", who, string.format("%s %s '%s' on %s", inst.Enabled and "◉ enabled" or "○ disabled", inst.ClassName, inst.Name, shortPath(inst.Parent, 2)),
			{ class = inst.ClassName, name = inst.Name, enabled = inst.Enabled, path = shortPath(inst, 5), kind = "toggle", dump = emitterDump(inst) })
	end)))
end

local function untrack(model)
	local info = tracked[model]
	if not info then return end
	for _, c in info.conns do pcall(function() c:Disconnect() end) end
	tracked[model] = nil
end

function trackCharacter(model)
	if tracked[model] or not model:IsA("Model") then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local info = { conns = {}, attrs = model:GetAttributes(), hattrs = hum:GetAttributes(), tags = {}, lastHealth = hum.Health, children = {} }
	for _, tag in model:GetTags() do info.tags[tag] = true end
	tracked[model] = info
	local conns = info.conns
	local function add(c) table.insert(conns, c) end

	local function hookAnimator(animator)
		add(animator.AnimationPlayed:Connect(guard(function(track) onAnimationPlayed(model, track) end)))
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then hookAnimator(animator) end
	add(hum.ChildAdded:Connect(guard(function(c) if c:IsA("Animator") then hookAnimator(c) end end)))

	add(hum.HealthChanged:Connect(guard(function(hp)
		local last = info.lastHealth
		info.lastHealth = hp
		if Rec.state == "idle" then return end
		local diff = last - hp
		if math.abs(diff) < 0.01 then return end
		if model == myChar() then
			log("HIT", model, string.format("%s %s HP  (now %s)", diff > 0 and "took" or "healed", fmtNum(math.abs(diff), 1), fmtNum(hp, 1)),
				{ amount = r(-diff, 2), health = r(hp, 2), target = "YOU" })
			return
		end
		if diff > 0 then markVictim(model, "damage") end
		local root, mine = rootOf(model), myRoot()
		if not root or not mine or not inRange(root.Position) then return end
		local rel = mine.CFrame:ToObjectSpace(root.CFrame)
		log("HIT", model, string.format("%s %s HP → %s  (at you %s, %s studs)", diff > 0 and "−" or "+", fmtNum(math.abs(diff), 1), model.Name,
			dirWords(rel.Position), fmtNum(rel.Position.Magnitude, 1)), {
			amount = r(diff, 2), health = r(hp, 2), target = model.Name, offset = rel.Position, offsetCF = rel,
			distance = r(rel.Position.Magnitude, 2), size = model:GetExtentsSize(), localVelocity = localDir(root.AssemblyLinearVelocity),
		})
	end)))

	add(hum.StateChanged:Connect(guard(function(old, new)
		if Rec.state == "idle" or not inScope(model) then return end
		if new == Enum.HumanoidStateType.Running or new == Enum.HumanoidStateType.RunningNoPhysics or new == Enum.HumanoidStateType.Landed then return end
		log("STATE", model, string.format("state %s → %s", old.Name, new.Name), { kind = "humanoidState", from = old.Name, to = new.Name })
	end)))

	for _, prop in { "WalkSpeed", "JumpPower", "JumpHeight", "AutoRotate", "PlatformStand", "Sit", "FloorMaterial" } do
		local last = safe(function() return hum[prop] end)
		add(hum:GetPropertyChangedSignal(prop):Connect(guard(function()
			local v = hum[prop]
			local was = last
			last = v
			if Rec.state == "idle" or not inScope(model) then return end
			log("STATE", model, string.format("%s %s → %s", prop, ser(was), ser(v)), { kind = "property", property = prop, from = was, to = v })
		end)))
	end

	add(model.ChildAdded:Connect(guard(function(c)
		if Rec.state == "idle" or not inScope(model) then return end
		if c:IsA("BasePart") or c:IsA("Humanoid") or c:IsA("Script") or c:IsA("LocalScript") then return end
		if VISUAL_CLASSES[c.ClassName] then return end
		if c:IsA("Model") and c:FindFirstChildWhichIsA("BasePart", true) and #c:GetDescendants() > 0 then return end
		local attrs = c:GetAttributes()
		local val = c:IsA("ValueBase") and safe(function() return c.Value end) or nil
		info.children[c] = now()
		if model ~= myChar() and matchesAny(c.Name, { "stun", "ragdoll", "hit", "freeze", "slow" }) then markVictim(model, "marker") end
		log("STATE", model, string.format("+ %s '%s'%s%s", c.ClassName, c.Name, val ~= nil and (" = " .. ser(val)) or "", next(attrs) and ("  " .. ser(attrs)) or ""),
			{ kind = "childAdded", class = c.ClassName, name = c.Name, value = val, attributes = attrs })
		local cstore = c:GetAttributes()
		add(c.AttributeChanged:Connect(guard(function(name)
			local v = c:GetAttribute(name)
			local was = cstore[name]
			cstore[name] = v
			if Rec.state == "idle" or not inScope(model) then return end
			log("STATE", model, string.format("child attr %s.%s: %s → %s", c.Name, name, ser(was), ser(v)),
				{ kind = "childAttribute", child = c.Name, name = name, from = was, to = v })
		end)))
		local ctags = {}
		for _, t in c:GetTags() do ctags[t] = true end
		table.insert(info.childTagTicks or {}, function()
			if not c.Parent or Rec.state == "idle" then return end
			local cur = {}
			for _, t in c:GetTags() do
				cur[t] = true
				if not ctags[t] then log("STATE", model, string.format("child tag + '%s' on %s", t, c.Name), { kind = "childTagAdded", child = c.Name, tag = t }) end
			end
			for t in ctags do
				if not cur[t] then log("STATE", model, string.format("child tag - '%s' on %s", t, c.Name), { kind = "childTagRemoved", child = c.Name, tag = t }) end
			end
			ctags = cur
		end)
	end)))

	add(model.ChildRemoved:Connect(guard(function(c)
		local born = info.children[c]
		info.children[c] = nil
		if Rec.state == "idle" or not born then return end
		log("STATE", model, string.format("- %s '%s' removed after %ss", c.ClassName, c.Name, fmtNum(now() - born, 3)),
			{ kind = "childRemoved", class = c.ClassName, name = c.Name, duration = r(now() - born, 3) })
	end)))

	local function attrHook(inst, store, label)
		add(inst.AttributeChanged:Connect(guard(function(name)
			local v = inst:GetAttribute(name)
			local was = store[name]
			store[name] = v
			if Rec.state == "idle" or not inScope(model) then return end
			log("STATE", model, string.format("%sattr %s: %s → %s", label, name, ser(was), ser(v)),
				{ kind = "attribute", on = label == "" and "Character" or "Humanoid", name = name, from = was, to = v })
		end)))
	end
	attrHook(model, info.attrs, "")
	attrHook(hum, info.hattrs, "Humanoid.")

	add(model.DescendantAdded:Connect(guard(function(d)
		if Rec.state == "idle" or not inScope(model) then return end
		if MOVER_CLASSES[d.ClassName] then task.defer(guard(logMover), d, model) end
		if VISUAL_CLASSES[d.ClassName] then logVisualToggle(d, model) end
		if d:IsA("BasePart") and isHitboxName(d.Name) then task.defer(guard(hookHitboxPart), d, model) end
	end)))
	for _, d in model:GetDescendants() do
		if VISUAL_CLASSES[d.ClassName] then logVisualToggle(d, model) end
		if d:IsA("BasePart") and isHitboxName(d.Name) then task.defer(guard(hookHitboxPart), d, model) end
	end

	local root = rootOf(model)
	if root then
		local lastAnch = root.Anchored
		add(root:GetPropertyChangedSignal("Anchored"):Connect(guard(function()
			local was = lastAnch
			lastAnch = root.Anchored
			if Rec.state == "idle" or not inScope(model) then return end
			log("STATE", model, string.format("root Anchored %s → %s", tostring(was), tostring(root.Anchored)),
				{ kind = "property", property = "Anchored", from = was, to = root.Anchored })
		end)))
	end
	add(model.Destroying:Connect(function() untrack(model) end))
end

---------------------------------------------------------------------------------------------------
-- sounds
---------------------------------------------------------------------------------------------------
local hookedSounds = setmetatable({}, { __mode = "k" })
local soundIgnore = splitList(CONFIG.SoundIgnore)

local function logSound(s)
	if Rec.state == "idle" or isMine(s) then return end
	if matchesAny(s.Name, soundIgnore) then return end
	local owner = characterOf(s)
	local pos = positionOf(s.Parent)
	if owner then
		if not inScope(owner) then return end
	elseif pos and not inRange(pos) then
		return
	end
	local id = assetNum(s.SoundId) or (s.SoundId ~= "" and s.SoundId) or "?"
	local rel = pos and localTo(CFrame.new(pos))
	local d = {
		id = id, name = s.Name, volume = r(s.Volume, 3), speed = r(s.PlaybackSpeed, 3), timePosition = r(s.TimePosition, 3),
		looped = s.Looped, parent = shortPath(s.Parent, 4), rollOffMode = s.RollOffMode.Name,
		rollOffMin = r(s.RollOffMinDistance, 1), rollOffMax = r(s.RollOffMaxDistance, 1), emitterSize = r(s.EmitterSize, 2),
		length = r(s.TimeLength, 3), offset = rel and rel.Position,
	}
	if not log("SOUND", owner, string.format("♪ %s  rbxassetid://%s  (vol %s, pitch %s%s) on %s", s.Name, id, fmtNum(d.volume, 2), fmtNum(d.speed, 2),
		d.timePosition > 0 and (", from " .. fmtNum(d.timePosition, 2) .. "s") or "", d.parent), d) then return end
	local born = now()
	local done = false
	local function finish()
		if done then return end
		done = true
		d.played = r(now() - born, 3)
	end
	s.Stopped:Once(finish)
	s.Ended:Once(finish)
	s.Destroying:Once(finish)
end

function hookSound(s)
	if hookedSounds[s] then return end
	hookedSounds[s] = true
	s.Played:Connect(guard(function() logSound(s) end))
	if s.Playing and Rec.state ~= "idle" then task.defer(guard(logSound), s) end
end

---------------------------------------------------------------------------------------------------
-- spawned effects
---------------------------------------------------------------------------------------------------
local pendingRoots, pendingFlush = {}, false
local loggedEffects = {}
local saveCounter, cloneSigs = 0, {}

local function saveClone(inst, label)
	if not CONFIG.CloneEffects or Rec.state ~= "recording" or not Rec.saveFolder then return nil end
	if saveCounter > CONFIG.MaxClones then return nil end
	local wasArch = inst.Archivable
	inst.Archivable = true
	local ok, c = pcall(inst.Clone, inst)
	inst.Archivable = wasArch
	if not ok or not c then return nil end
	saveCounter += 1
	c.Name = label
	for _, d in c:GetDescendants() do
		if d:IsA("BaseScript") then d.Enabled = false end
	end
	if c:IsA("BasePart") then c.Anchored = true end
	pcall(function() c.Parent = Rec.saveFolder end)
	return c
end

local function processRoot(inst, born)
	if not inst.Parent or isMine(inst) then return end
	local owner = characterOf(inst)
	local pos = positionOf(inst)
	if owner then
		if not inScope(owner) then return end
	elseif not pos or not inRange(pos) then
		return
	end
	if inst:IsA("Attachment") and not hasVisualDescendant(inst) then return end
	if inst:IsA("Folder") and #inst:GetChildren() == 0 then return end
	local hb = hitboxKind(inst)
	local d = describeEffect(inst)
	local cat, text
	if hb then
		cat = "HITBOX"
		d.hitboxKind = hb
		text = string.format("▣ %s '%s'  size %s  at you %s%s%s", hb == "named" and "hitbox" or "possible hitbox (invisible part)", inst.Name,
			d.size and v3s(d.size) or "?", d.offset and dirWords(d.offset) or "?", d.weldedTo and ("  welded to " .. d.weldedTo) or "",
			inst:IsA("BasePart") and inst.CanTouch and " (CanTouch)" or "")
	else
		cat = "VFX"
		local em = {}
		for _, e in d.emitters do table.insert(em, string.format("'%s'{%s}", e.name, emitterText(e))) end
		for _, e in d.beams do table.insert(em, string.format("beam '%s'{%s}", e.name, emitterText(e))) end
		for _, e in d.trails do table.insert(em, string.format("trail '%s'{%s}", e.name, emitterText(e))) end
		local meshes = {}
		for _, m in d.meshes do table.insert(meshes, m.meshId or m.texture or "?") end
		text = string.format("✦ %s '%s' in %s  host %s%s  %s%s%s", inst.ClassName, inst.Name, d.path,
			d.size and ("size " .. v3s(d.size)) or "?", d.shape and (" (" .. d.shape .. ")") or "",
			#em > 0 and (table.concat(em, " ") .. "  ") or "", #meshes > 0 and ("meshes " .. table.concat(meshes, ", ") .. "  ") or "",
			d.offset and ("at you " .. dirWords(d.offset)) or "")
	end
	local ev = log(cat, owner, text, d)
	if not ev then return end
	ev.t = math.min(ev.t, born)
	if Rec.state == "recording" then
		local sig = table.concat({ inst.Name, inst.ClassName, tostring(d.folder) }, "|")
		if not cloneSigs[sig] or cat == "HITBOX" then
			cloneSigs[sig] = true
			local label = string.format("%06.3f %s", math.max(0, born - Rec.t0), inst.Name)
			if saveClone(inst, label) then d.saved = label end
		else
			d.duplicate = true
		end
	end
	if (CONFIG.TrackMotion or cat == "HITBOX") and #loggedEffects < 100 then
		table.insert(loggedEffects, { inst = inst, ev = ev, born = born, samples = {} })
	end
	local conn
	conn = inst.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			conn:Disconnect()
			d.lifetime = r(now() - born, 3)
		end
	end)
	if inst:IsA("BasePart") and isHitboxName(inst.Name) then task.defer(guard(hookHitboxPart), inst, owner) end
end

local function flushPending()
	pendingFlush = false
	local batch = pendingRoots
	pendingRoots = {}
	for inst, born in batch do
		local node, skip = inst.Parent, false
		while node and node ~= workspace and node ~= game do
			if batch[node] then skip = true break end
			node = node.Parent
		end
		if not skip then pcall(processRoot, inst, born) end
	end
end

local EFFECT_CANDIDATE = { BasePart = true, Model = true, Attachment = true, Folder = true }

local function onWorkspaceDescendant(inst)
	local cls = inst.ClassName
	if cls == "Sound" then hookSound(inst) return end
	if cls == "Humanoid" then
		local m = inst.Parent
		if m and m:IsA("Model") then task.defer(guard(trackCharacter), m) end
		return
	end
	if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" then
		if UI.hookRemote then UI.hookRemote(inst) end
		return
	end
	if Rec.state == "idle" then return end
	if MOVER_CLASSES[cls] then
		local a0 = safe(function() return inst.Attachment0 end)
		local c = a0 and characterOf(a0)
		if c and not characterOf(inst) and inScope(c) then task.defer(guard(logMover), inst, c) end
		return
	end
	if inst:IsA("BasePart") and isHitboxName(inst.Name) then
		local o = characterOf(inst)
		if not o or inScope(o) then task.defer(guard(hookHitboxPart), inst, o) end
	end
	if not (VISUAL_CLASSES[cls] or inst:IsA("BasePart") or EFFECT_CANDIDATE[cls]) then return end
	local owner = characterOf(inst)
	if owner then
		if owner == inst or cls == "Folder" then return end
		if inst.Parent and inst.Parent:IsA("Accessory") then return end
		if inst.Parent == owner and inst:IsA("BasePart") and owner ~= myChar() and not hitboxKind(inst) then return end
	end
	if inst:FindFirstChildOfClass("Humanoid") then return end
	pendingRoots[inst] = now()
	if not pendingFlush then
		pendingFlush = true
		task.defer(guard(flushPending))
	end
end

---------------------------------------------------------------------------------------------------
-- hitbox parts
---------------------------------------------------------------------------------------------------
local hookedHitboxes = setmetatable({}, { __mode = "k" })
local touchThrottle = setmetatable({}, { __mode = "k" })

function hookHitboxPart(part, owner)
	if hookedHitboxes[part] then return end
	hookedHitboxes[part] = true
	local snap = { size = part.Size, transp = part.Transparency, canTouch = part.CanTouch, canCollide = part.CanCollide, anchored = part.Anchored }
	local function alive() return part.Parent ~= nil and Rec.state ~= "idle" and (not owner or inScope(owner)) end
	local function base(kind)
		local d = describeEffect(part)
		d.kind = kind
		d.hitboxKind = hitboxKind(part) or "tracked"
		return d
	end
	part:GetPropertyChangedSignal("Size"):Connect(guard(function()
		if not alive() then return end
		local was = snap.size
		snap.size = part.Size
		if (part.Size - was).Magnitude < 0.01 then return end
		local d = base("resized")
		d.from, d.to = was, part.Size
		log("HITBOX", owner, string.format("▣ '%s' size %s → %s  at you %s", part.Name, v3s(was), v3s(part.Size), d.offset and dirWords(d.offset) or "?"), d)
	end))
	part:GetPropertyChangedSignal("Transparency"):Connect(guard(function()
		if not alive() then return end
		local was = snap.transp
		snap.transp = part.Transparency
		if math.abs(part.Transparency - was) < 0.01 then return end
		local d = base("visibility")
		d.from, d.to = r(was, 3), r(part.Transparency, 3)
		log("HITBOX", owner, string.format("▣ '%s' transparency %s → %s", part.Name, fmtNum(was, 2), fmtNum(part.Transparency, 2)), d)
	end))
	part:GetPropertyChangedSignal("CanTouch"):Connect(guard(function()
		if not alive() then return end
		local was = snap.canTouch
		snap.canTouch = part.CanTouch
		local d = base("canTouch")
		d.from, d.to = was, part.CanTouch
		log("HITBOX", owner, string.format("▣ '%s' CanTouch %s → %s%s", part.Name, tostring(was), tostring(part.CanTouch), part.CanTouch and "  (armed)" or ""), d)
	end))
	part:GetPropertyChangedSignal("Anchored"):Connect(guard(function()
		if not alive() then return end
		local was = snap.anchored
		snap.anchored = part.Anchored
		local d = base("anchored")
		d.from, d.to = was, part.Anchored
		log("HITBOX", owner, string.format("▣ '%s' Anchored %s → %s", part.Name, tostring(was), tostring(part.Anchored)), d)
	end))
	if CONFIG.TrackHitboxTouches then
		part.Touched:Connect(guard(function(hit)
			if not alive() then return end
			local victim = characterOf(hit)
			local mine = myRoot()
			local key = victim or hit
			local t = now()
			local last = touchThrottle[key]
			if last and t - last < 0.08 then return end
			touchThrottle[key] = t
			if victim and victim ~= myChar() then markVictim(victim, "hitboxTouch") end
			local rel = mine and mine.CFrame:ToObjectSpace(hit.CFrame)
			local d = base("touch")
			d.touched, d.touchedClass, d.victim = hit.Name, hit.ClassName, victim and victim.Name or nil
			if victim then d.victimExtents = safe(victim.GetExtentsSize, victim) end
			d.offset, d.offsetCF, d.distance = rel and rel.Position, rel, rel and r(rel.Position.Magnitude, 2)
			log("HITBOX", owner, string.format("▣ '%s' touched %s%s  (at you %s, %s studs)", part.Name, hit.Name,
				victim and (" [VICTIM " .. victim.Name .. "]") or "", rel and dirWords(rel.Position) or "?", rel and fmtNum(rel.Position.Magnitude, 1) or "?"), d)
		end))
	end
end

---------------------------------------------------------------------------------------------------
-- dummies
---------------------------------------------------------------------------------------------------
local dummies = setmetatable({}, { __mode = "k" })
local function attachDummy(model)
	if dummies[model] then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	dummies[model] = true
	local last = hum.Health
	log("STATE", model, string.format("dummy tracked  hp %s/%s", fmtNum(last, 1), fmtNum(hum.MaxHealth, 1)), { kind = "dummy" })
	local c = hum:GetPropertyChangedSignal("Health"):Connect(guard(function()
		local hp = hum.Health
		local diff = last - hp
		if diff ~= 0 then
			if diff > 0 then markVictim(model, "damage") end
			log("HIT", model, string.format("dummy %s | %s → %s (%+.1f)", model.Name, fmtNum(last, 1), fmtNum(hp, 1), -diff),
				{ amount = r(diff, 2), health = r(hp, 2), target = model.Name, dummy = true })
		end
		last = hp
	end))
	cn(model.Destroying:Connect(function() c:Disconnect() end))
end

local function scanDummies()
	if not CONFIG.TrackDummies then return end
	local function scan(container, depth)
		for _, c in container:GetChildren() do
			if c:IsA("Model") and c:FindFirstChildOfClass("Humanoid") and matchesAny(c.Name, { "dummy", "training", "target" }) then
				attachDummy(c)
			elseif depth > 0 and (c:IsA("Folder") or c:IsA("Model")) then
				scan(c, depth - 1)
			end
		end
	end
	scan(workspace, 3)
end

---------------------------------------------------------------------------------------------------
-- remotes
---------------------------------------------------------------------------------------------------
local hookedRemotes = setmetatable({}, { __mode = "k" })
local remoteIgnore = splitList(CONFIG.RemoteIgnore)
local REPLICATION_HINTS = { "replication", "replicate", "replicator", "state", "sync", "update", "gameevent", "action" }

local function remoteSubject(args)
	local function check(v, depth)
		if typeof(v) == "Instance" then return characterOf(v) end
		if type(v) == "table" and depth < 2 then
			for _, x in v do
				local c = check(x, depth + 1)
				if c then return c end
			end
		end
		return nil
	end
	for _, a in args do
		local c = check(a, 0)
		if c then return c end
	end
	return nil
end
local function remoteLabel(args)
	for _, a in args do
		if type(a) == "table" then
			for _, key in { "Effect", "effect", "Move", "move", "Name", "name", "Skill", "skill", "Request", "request", "Ability", "Action", "Type" } do
				if type(a[key]) == "string" then return a[key] end
			end
		elseif type(a) == "string" and #a < 40 then
			return a
		end
	end
	return nil
end

function hookRemote(re)
	if hookedRemotes[re] then return end
	hookedRemotes[re] = true
	re.OnClientEvent:Connect(guard(function(...)
		if Rec.state == "idle" then return end
		local args = table.pack(...)
		local list = {}
		for i = 1, args.n do list[i] = args[i] end
		local isReplication = CONFIG.ReplicationSpy and matchesAny(re.Name, REPLICATION_HINTS)
		if not isReplication and (not CONFIG.LogRemotes or matchesAny(re.Name, remoteIgnore)) then return end
		local subject = remoteSubject(list)
		if subject and subject ~= myChar() and not inScope(subject) then return end
		if subject and subject ~= myChar() then markVictim(subject, "remote") end
		if Rec.state == "armed" and CONFIG.StartOnRemote and subject == myChar() then startRecording("remote " .. re.Name, "startup") end
		local parts = {}
		for i = 1, args.n do table.insert(parts, ser(list[i])) end
		local label = remoteLabel(list)
		log(isReplication and "REPLICATION" or "REMOTE", subject, string.format("%s %s%s  %s", isReplication and "⇄" or "⇠", re.Name,
			label and ("  [" .. label .. "]") or "", table.concat(parts, ", ")),
			{ remote = shortPath(re, 4), class = re.ClassName, label = label, args = list, n = args.n, replication = isReplication or nil })
	end))
end
UI.hookRemote = hookRemote

---------------------------------------------------------------------------------------------------
-- camera / screen
---------------------------------------------------------------------------------------------------
local Camera = workspace.CurrentCamera
local cam = { fov = Camera and Camera.FieldOfView or 70, fovRun = nil, stableFor = 0, lastLook = nil, lastUp = nil, ema = 0, shake = nil }
local postSnap = setmetatable({}, { __mode = "k" })
local POST_PROPS = {
	ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
	BlurEffect = { "Enabled", "Size" }, BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
	DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	SunRaysEffect = { "Enabled", "Intensity", "Spread" },
}
local function postSig(e)
	local props = POST_PROPS[e.ClassName]
	if not props then return nil end
	local t = {}
	for _, p in props do t[p] = e[p] end
	return t
end
local function snapPosts()
	for _, root in { Lighting, Camera } do
		if root then
			for _, e in root:GetChildren() do
				if POST_PROPS[e.ClassName] then postSnap[e] = postSig(e) end
			end
		end
	end
end
local function checkPosts()
	if not CONFIG.LogScreen then return end
	for _, root in { Lighting, Camera } do
		if root then
			for _, e in root:GetChildren() do
				if POST_PROPS[e.ClassName] then
					local old, new = postSnap[e], postSig(e)
					if old then
						local changes = {}
						for k, v in new do
							if old[k] ~= v then table.insert(changes, string.format("%s %s→%s", k, ser(old[k]), ser(v))) end
						end
						if #changes > 0 then
							log("SCREEN", nil, string.format("~ %s '%s': %s", e.ClassName, e.Name, table.concat(changes, ", ")),
								{ kind = "change", class = e.ClassName, name = e.Name, from = old, to = new })
						end
					end
					postSnap[e] = new
				end
			end
		end
	end
end
local function onScreenEffect(e)
	if Rec.state == "idle" or not CONFIG.LogScreen or isMine(e) then return end
	if not (e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Sky")) then return end
	local sig = postSig(e)
	postSnap[e] = sig
	local d = { kind = "added", class = e.ClassName, name = e.Name, props = sig, parent = e.Parent and e.Parent.Name }
	log("SCREEN", nil, string.format("+ %s '%s' in %s %s", e.ClassName, e.Name, d.parent or "?", sig and ser(sig) or ""), d)
	local born = now()
	local conn
	conn = e.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			conn:Disconnect()
			d.lifetime = r(now() - born, 3)
			log("SCREEN", nil, string.format("- %s '%s' removed after %ss", e.ClassName, e.Name, fmtNum(d.lifetime, 3)),
				{ kind = "removed", class = e.ClassName, name = e.Name, lifetime = d.lifetime })
		end
	end)
end
local guiBatch, guiFlush = {}, false
local function onGuiDescendant(g)
	if Rec.state == "idle" or not CONFIG.LogScreen or isMine(g) then return end
	if not (g:IsA("ScreenGui") or g:IsA("GuiObject")) then return end
	guiBatch[g] = true
	if guiFlush then return end
	guiFlush = true
	task.defer(guard(function()
		guiFlush = false
		local batch = guiBatch
		guiBatch = {}
		for inst in batch do
			local node, skip = inst.Parent, false
			while node and node ~= PlayerGui do
				if batch[node] then skip = true break end
				node = node.Parent
			end
			if not skip and inst.Parent then
				local imgs = {}
				for _, d in inst:GetDescendants() do
					if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and #imgs < 4 then
						local id = assetNum(d.Image)
						if id then table.insert(imgs, id) end
					end
				end
				log("SCREEN", nil, string.format("▢ overlay %s '%s' in %s%s", inst.ClassName, inst.Name, shortPath(inst.Parent, 2),
					#imgs > 0 and ("  images " .. table.concat(imgs, ", ")) or ""),
					{ kind = "overlay", class = inst.ClassName, name = inst.Name, path = shortPath(inst, 4), images = imgs })
			end
		end
	end))
end

local function cameraStep(dt)
	if Rec.state == "idle" or not CONFIG.LogCamera then return end
	Camera = workspace.CurrentCamera
	if not Camera then return end
	local fov = Camera.FieldOfView
	if math.abs(fov - cam.fov) > 0.15 then
		if not cam.fovRun then cam.fovRun = { t = now(), from = cam.fov, peak = fov } end
		local run = cam.fovRun
		if math.abs(fov - run.from) > math.abs(run.peak - run.from) then run.peak = fov run.peakT = now() end
		cam.stableFor = 0
	elseif cam.fovRun then
		cam.stableFor += dt
		if cam.stableFor > 0.12 then
			local run = cam.fovRun
			cam.fovRun = nil
			local ev = log("CAMERA", nil, string.format("FOV %s → %s → %s over %ss", fmtNum(run.from, 1), fmtNum(run.peak, 1), fmtNum(fov, 1), fmtNum(now() - run.t, 2)),
				{ kind = "fov", from = r(run.from, 2), peak = r(run.peak, 2), to = r(fov, 2), duration = r(now() - run.t, 3), peakAt = run.peakT and r(run.peakT - run.t, 3) or 0 })
			if ev then ev.t = run.t end
		end
	end
	cam.fov = fov
	local cf = Camera.CFrame
	local look, up = cf.LookVector, cf.UpVector
	if cam.lastLook then
		local a = math.deg(math.acos(math.clamp(look:Dot(cam.lastLook), -1, 1)))
		local rl = math.deg(math.acos(math.clamp(up:Dot(cam.lastUp), -1, 1)))
		local mag = a + rl * 0.5
		local jitter = math.abs(mag - cam.ema)
		cam.ema = cam.ema + (mag - cam.ema) * 0.15
		if jitter > CONFIG.ShakeThreshold then
			if not cam.shake then cam.shake = { t = now(), peak = 0, frames = 0, quiet = 0 } end
			cam.shake.peak = math.max(cam.shake.peak, mag)
			cam.shake.frames += 1
			cam.shake.quiet = 0
		elseif cam.shake then
			cam.shake.quiet += dt
			if cam.shake.quiet > 0.12 then
				local s = cam.shake
				cam.shake = nil
				if s.frames >= 3 then
					local ev = log("CAMERA", nil, string.format("shake ~%ss, strength ~%s° (approx.)", fmtNum(now() - s.t - s.quiet, 2), fmtNum(s.peak, 2)),
						{ kind = "shake", duration = r(now() - s.t - s.quiet, 3), strength = r(s.peak, 3), frames = s.frames })
					if ev then ev.t = s.t end
				end
			end
		end
	end
	cam.lastLook, cam.lastUp = look, up
end

---------------------------------------------------------------------------------------------------
-- sampling
---------------------------------------------------------------------------------------------------
local lastVel = setmetatable({}, { __mode = "k" })
local sampleAcc = 0
local function velSample(root)
	if not root then return nil, 0 end
	local v = root.AssemblyLinearVelocity
	return localDir(v), r(v.Magnitude, 2)
end

local function sampleTick()
	local t = now()
	local root = myRoot()
	if root and Rec.startCF and Rec.state == "recording" then
		local lv, speed = velSample(root)
		table.insert(Rec.path, { t = r(t - Rec.t0, 3), pos = Rec.startCF:ToObjectSpace(root.CFrame).Position,
			look = Rec.startCF:VectorToObjectSpace(root.CFrame.LookVector), vel = lv, speed = speed })
		Rec.peakSpeed = math.max(Rec.peakSpeed or 0, speed)
		for model, info in Rec.victims do
			local vr = rootOf(model)
			if vr then
				local list = Rec.victimPaths[info.name]
				if not list then list = {} Rec.victimPaths[info.name] = list end
				if #list < 500 then
					local vlv, vspeed = velSample(vr)
					local rel = Rec.startCF:ToObjectSpace(vr.CFrame)
					local dist = r((vr.Position - root.Position).Magnitude, 2)
					table.insert(list, { t = r(t - Rec.t0, 3), pos = rel.Position, vel = vlv, speed = vspeed, dist = dist })
					info.minDistance = math.min(info.minDistance or 1e9, dist)
					info.peakSpeed = math.max(info.peakSpeed or 0, vspeed)
					local hum = model:FindFirstChildOfClass("Humanoid")
					if hum then info.health = r(hum.Health, 2) info.maxHealth = r(hum.MaxHealth, 2) end
				end
			end
		end
	end
	if CONFIG.TrackOthers and Rec.state == "recording" and root and not Rec.noVictims then
		for _, p in Players:GetPlayers() do
			local c = p.Character
			if c and c ~= myChar() then
				local cr = rootOf(c)
				if cr and (cr.Position - root.Position).Magnitude <= CONFIG.VictimRadius then markVictim(c, "proximity") end
			end
		end
		for model in dummies do
			local dr = rootOf(model)
			if dr and (dr.Position - root.Position).Magnitude <= CONFIG.VictimRadius then markVictim(model, "proximity") end
		end
	end
	if CONFIG.TrackTags then
		for model, info in tracked do
			if model.Parent and inScope(model) then
				local cur = {}
				for _, tag in model:GetTags() do
					cur[tag] = true
					if not info.tags[tag] then log("STATE", model, "+ tag '" .. tag .. "'", { kind = "tagAdded", tag = tag }) end
				end
				for tag in info.tags do
					if not cur[tag] then log("STATE", model, "- tag '" .. tag .. "'", { kind = "tagRemoved", tag = tag }) end
				end
				info.tags = cur
			end
		end
	end
	for track, a in activeTracks do
		local tp = safe(function() return track.TimePosition end) or 0
		if a.lastTp and tp < a.lastTp - 0.15 then
			log("ANIM", a.model, string.format("⤺ %s time jump %ss → %ss", a.ev.data.name or "?", fmtNum(a.lastTp, 2), fmtNum(tp, 2)),
				{ kind = "timejump", id = a.ev.data.id, from = r(a.lastTp, 3), to = r(tp, 3) })
		end
		a.lastTp = tp
		if math.abs(track.Speed - a.speed) > 0.01 then
			log("ANIM", a.model, string.format("⏩ %s speed %s → %s at %ss into it", a.ev.data.name or "?", fmtNum(a.speed, 2), fmtNum(track.Speed, 2), fmtNum(tp, 2)),
				{ kind = "speed", id = a.ev.data.id, from = r(a.speed, 3), to = r(track.Speed, 3), timePosition = r(tp, 3) })
			a.speed = track.Speed
		end
	end
	for i = #loggedEffects, 1, -1 do
		local e = loggedEffects[i]
		local inst = e.inst
		if not inst.Parent or t - e.born > 8 then
			table.remove(loggedEffects, i)
		elseif #e.samples < 50 then
			local cf = cframeOf(inst)
			local s = { t = r(t - e.born, 3) }
			if cf and Rec.startCF then s.pos = Rec.startCF:ToObjectSpace(cf).Position end
			if inst:IsA("BasePart") then
				s.size = inst.Size
				s.transparency = r(inst.Transparency, 3)
				s.vel = localDir(inst.AssemblyLinearVelocity)
				s.speed = r(inst.AssemblyLinearVelocity.Magnitude, 2)
			end
			local last = e.samples[#e.samples]
			local changed = not last or (s.pos and last.pos and (s.pos - last.pos).Magnitude > 0.05)
				or (s.size and last.size and (s.size - last.size).Magnitude > 0.05)
				or (s.transparency ~= last.transparency) or (s.speed and s.speed > 1 and (not last.speed or math.abs(s.speed - last.speed) > 0.5))
			if changed then
				table.insert(e.samples, s)
				e.ev.data.motion = e.samples
			end
		end
	end
	checkPosts()
	if Rec.state == "recording" then
		local elapsed = t - Rec.t0
		local busy = false
		for track, a in activeTracks do
			if a.model == myChar() and not track.Looped and track.Priority.Value >= Enum.AnimationPriority.Action.Value then busy = true break end
		end
		local idleLimit = (Rec.advanced and Rec.phase == "startup") and math.max(CONFIG.IdleStop, 4) or CONFIG.IdleStop
		if elapsed > CONFIG.MaxLength or (elapsed > CONFIG.MinLength and not busy and t - Rec.lastActivity > idleLimit) then
			stopRecording(elapsed > CONFIG.MaxLength and "max length" or "idle")
		end
	end
end

local function heartbeat(dt)
	if Rec.state == "idle" then return end
	local mine = myChar()
	for model in tracked do
		if model.Parent and (model == mine or Rec.victims[model] or (CONFIG.TrackOthers and inScope(model))) then
			local root = rootOf(model)
			if root and CONFIG.TrackVelocity then
				local v = root.AssemblyLinearVelocity
				local last = lastVel[model]
				lastVel[model] = v
				local speed = v.Magnitude
				local prevSpeed = last and last.Magnitude or 0
				if last then
					local delta = (v - last).Magnitude
					local crossed = (prevSpeed < CONFIG.SpeedPhase and speed >= CONFIG.SpeedPhase)
						or (prevSpeed >= CONFIG.SpeedPhase and speed < CONFIG.SpeedPhase)
					if delta > CONFIG.VelocitySpike or crossed then
						local lv = localDir(v)
						local kind = crossed and (speed >= CONFIG.SpeedPhase and "speedPhaseStart" or "speedPhaseEnd") or "impulse"
						log("VELOCITY", model, string.format("%s  → %s  (|v| %s, Δ%s)",
							kind == "impulse" and "⚡ jump" or (kind == "speedPhaseStart" and "▶ moving" or "◼ stopped"),
							dirWords(lv), fmtNum(speed, 1), fmtNum(delta, 1)),
							{ kind = kind, localVelocity = lv, speed = r(speed, 2), delta = r(delta, 2) })
					end
				end
			end
		end
	end
	sampleAcc += dt
	if sampleAcc >= 0.1 then
		sampleAcc = 0
		guard(sampleTick)()
	end
end

---------------------------------------------------------------------------------------------------
-- start / stop
---------------------------------------------------------------------------------------------------
local function scanCharacters()
	for _, p in Players:GetPlayers() do
		if p.Character then trackCharacter(p.Character) end
	end
	local function scan(container, depth)
		for _, c in container:GetChildren() do
			if c:IsA("Model") and c:FindFirstChildOfClass("Humanoid") then
				trackCharacter(c)
			elseif depth > 0 and (c:IsA("Folder") or c:IsA("Model")) then
				scan(c, depth - 1)
			end
		end
	end
	scan(workspace, 2)
end

local function scanHitboxes()
	local root = myRoot()
	if not root then return end
	local function scan(container, depth)
		for _, c in container:GetChildren() do
			if c:IsA("BasePart") and isHitboxName(c.Name) and inRange(c.Position) then
				hookHitboxPart(c, characterOf(c))
			elseif depth > 0 and (c:IsA("Folder") or c:IsA("Model")) then
				scan(c, depth - 1)
			end
		end
	end
	scan(workspace, 4)
end

function setState(s)
	Rec.state = s
	if Hooks.onState then task.spawn(guard(Hooks.onState)) end
end

local soundsScanned = false
function arm()
	if Rec.state == "recording" then return end
	if not soundsScanned then
		soundsScanned = true
		task.spawn(guard(function()
			for _, root in { workspace, SoundService, PlayerGui } do
				for _, d in root:GetDescendants() do
					if d:IsA("Sound") then hookSound(d) end
				end
			end
		end))
	end
	scanCharacters()
	scanDummies()
	scanHitboxes()
	Rec.preroll = {}
	setState("armed")
end

local function newSaveFolder(name)
	if not CONFIG.CloneEffects then return nil end
	if not LoggedRoot or not LoggedRoot.Parent then
		LoggedRoot = ReplicatedStorage:FindFirstChild("MoveLogger_Logged") or Instance.new("Folder")
		LoggedRoot.Name = "MoveLogger_Logged"
		LoggedRoot.Parent = ReplicatedStorage
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = LoggedRoot
	return f
end

function startRecording(reason, phase)
	if Rec.state == "recording" then return end
	if Rec.state == "idle" then arm() end
	scanCharacters()
	scanDummies()
	scanHitboxes()
	Rec.count += 1
	Rec.t0 = now()
	Rec.events, Rec.victims, Rec.path, Rec.victimPaths = {}, {}, {}, {}
	Rec.reason = reason or "manual"
	Rec.advanced = CONFIG.Advanced or phase == "startup"
	Rec.phase = (Rec.advanced and phase ~= "hit") and "startup" or "hit"
	Rec.noVictims = Rec.advanced and Rec.phase == "startup"
	Rec.hitStart = Rec.phase == "hit" and Rec.t0 or nil
	local root = myRoot()
	Rec.startCF = root and root.CFrame or nil
	Rec.startVelocity = root and localDir(root.AssemblyLinearVelocity) or Vector3.zero
	Rec.startSpeed = root and r(root.AssemblyLinearVelocity.Magnitude, 2) or 0
	Rec.peakSpeed = Rec.startSpeed
	loggedEffects = {}
	saveCounter, cloneSigs = 0, {}
	Rec.saveFolder = newSaveFolder(string.format("Rec%d", Rec.count))
	cam.fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
	cam.fovRun, cam.shake = nil, nil
	snapPosts()
	local cut = Rec.t0 - CONFIG.Preroll
	for _, ev in Rec.preroll do
		if ev.t >= cut then table.insert(Rec.events, ev) end
	end
	Rec.preroll = {}
	Rec.lastActivity = now()
	setState("recording")
	snapshotTracks(myChar())
	if Rec.phase == "startup" then log("MARKER", myChar(), "══ STARTUP PHASE ══  (no victims)", { kind = "startupPhase" }) end
end

function startHitPhase()
	if Rec.state ~= "recording" then
		startRecording("hit", "hit")
		return
	end
	if not Rec.advanced or Rec.phase ~= "startup" then
		toast("already in the hit phase")
		return
	end
	Rec.hitStart = now()
	Rec.phase = "hit"
	Rec.noVictims = false
	Rec.lastActivity = now()
	Rec.victims = {}
	log("MARKER", myChar(), "══ HIT PHASE ══", { kind = "hitPhase" })
	scanCharacters()
	scanDummies()
	scanHitboxes()
	snapshotTracks(myChar())
	toast("hit phase recording")
	if Hooks.onState then task.spawn(guard(Hooks.onState)) end
end

local function velocityPhases(path)
	local phases, cur = {}, nil
	for _, p in path do
		local s = p.speed or 0
		if s >= CONFIG.SpeedPhase then
			if not cur then cur = { from = p.t, peak = s, peakAt = p.t, dir = p.vel } end
			if s > cur.peak then cur.peak = s cur.peakAt = p.t cur.dir = p.vel end
			cur.to = p.t
		elseif cur then
			if cur.to - cur.from >= 0.1 then table.insert(phases, cur) end
			cur = nil
		end
	end
	if cur and (cur.to or cur.from) - cur.from >= 0.1 then table.insert(phases, cur) end
	return phases
end

local function finishRecording(reason)
	local events = Rec.events
	table.sort(events, function(a, b) return a.t < b.t end)
	local startupDuration = (Rec.hitStart and Rec.hitStart > Rec.t0) and (Rec.hitStart - Rec.t0) or nil
	for _, ev in events do
		ev.rt = ev.t - Rec.t0
		if startupDuration then ev.phase = ev.rt < startupDuration and "startup" or "hit" end
		if ev.model and Rec.victims[ev.model] then ev.victim = true end
	end
	local duration = 0
	for _, ev in events do duration = math.max(duration, ev.rt) end
	for _, ph in velocityPhases(Rec.path) do
		local ev = log("VELOCITY", myChar(), string.format("▶ motion %ss, peak %s studs/s %s", fmtNum(ph.to - ph.from, 2), fmtNum(ph.peak, 1), dirWords(ph.dir)),
			{ kind = "velocityPhase", localVelocity = ph.dir, peakSpeed = r(ph.peak, 2), duration = r(ph.to - ph.from, 3), peakAt = r(ph.peakAt - ph.from, 3) })
		if ev then
			ev.rt = ph.from
			if startupDuration then ev.phase = ev.rt < startupDuration and "startup" or "hit" end
			table.insert(events, ev)
		end
	end
	table.sort(events, function(a, b) return a.rt < b.rt end)
	local name = UI.nameBox and UI.nameBox.Text ~= "" and UI.nameBox.Text or nil
	if not name then
		for _, ev in events do
			if ev.cat == "REMOTE" and ev.data.label and (ev.model == myChar() or ev.model == nil) then name = ev.data.label break end
		end
	end
	if not name then
		for _, ev in events do
			if ev.cat == "ANIM" and ev.who == "YOU" and ev.data.id and not ev.data.kind then
				name = ev.data.name ~= "Animation" and ev.data.name or ("anim " .. ev.data.id)
				break
			end
		end
	end
	if not name then name = "Recording " .. Rec.count end
	local victims, victimInfo = {}, {}
	for model, v in Rec.victims do
		table.insert(victims, v.name)
		local reasons = {}
		for k in v do if type(k) == "string" and k ~= "name" then table.insert(reasons, k) end end
		victimInfo[v.name] = { reasons = reasons, minDistance = v.minDistance, peakSpeed = v.peakSpeed, health = v.health,
			maxHealth = v.maxHealth, firstAt = r(v.firstAt - Rec.t0, 3), track = Rec.victimPaths[v.name] }
	end
	local rec = {
		index = Rec.count, name = name, duration = duration, events = events, victims = victims, victimInfo = victimInfo,
		reason = reason, startReason = Rec.reason, path = Rec.path, victimPaths = Rec.victimPaths,
		startVelocity = Rec.startVelocity, startSpeed = Rec.startSpeed, peakSpeed = Rec.peakSpeed,
		startupDuration = startupDuration, advanced = Rec.advanced and startupDuration ~= nil,
		saveFolder = Rec.saveFolder and Rec.saveFolder:GetFullName() or nil,
		character = myChar() and myChar().Name or "?", placeId = game.PlaceId, when = os.date("%Y-%m-%d %H:%M:%S"),
	}
	if Rec.saveFolder then Rec.saveFolder.Name = string.format("Rec%d %s", Rec.count, (string.gsub(name, "[^%w _%-]", ""))) end
	table.insert(History, rec)
	while #History > 40 do table.remove(History, 1) end
	Selected = #History
	Rec.advanced, Rec.noVictims, Rec.hitStart = false, false, nil
	if Hooks.onFinish then task.spawn(guard(Hooks.onFinish), rec) end
end

function stopRecording(reason)
	if Rec.state ~= "recording" then
		setState("idle")
		return
	end
	flushPending()
	Rec.state = "idle"
	finishRecording(reason or "manual")
	if CONFIG.AutoArm and reason ~= "manual" then arm() else setState("idle") end
end

---------------------------------------------------------------------------------------------------
-- outputs
---------------------------------------------------------------------------------------------------
local Out = {}

local function evFilter(rec, opts)
	local list = {}
	for _, ev in rec.events do
		if CAT_SHOW[ev.cat] and (not opts or not opts.victimOnly or ev.victim) and (not opts or not opts.youOnly or ev.who == "YOU" or ev.who == "WORLD") then
			if not opts or not opts.search or opts.search == "" or string.find(string.lower(ev.text .. " " .. ev.who), string.lower(opts.search), 1, true) then
				table.insert(list, ev)
			end
		end
	end
	return list
end

local function inferHitboxes(rec)
	local hits = {}
	for _, ev in rec.events do
		if (ev.cat == "HIT" and ev.data.offset and ev.data.amount and ev.data.amount > 0)
			or (ev.cat == "HITBOX" and ev.data.kind == "touch" and ev.data.victim and ev.data.offset) then
			table.insert(hits, ev)
		end
	end
	local clusters = {}
	for _, h in hits do
		local c = clusters[#clusters]
		if c and h.rt - c.last <= 0.08 then
			table.insert(c.hits, h)
			c.last = h.rt
		else
			table.insert(clusters, { first = h.rt, last = h.rt, hits = { h } })
		end
	end
	local out = {}
	for _, c in clusters do
		local sum = Vector3.new()
		for _, h in c.hits do sum += h.data.offset end
		local center = sum / #c.hits
		local ext = Vector3.new()
		for _, h in c.hits do
			local d = h.data.offset - center
			local half = (h.data.size or (h.data.victimExtents or Vector3.new(4, 5, 2))) / 2
			ext = Vector3.new(math.max(ext.X, math.abs(d.X) + half.X), math.max(ext.Y, math.abs(d.Y) + half.Y), math.max(ext.Z, math.abs(d.Z) + half.Z))
		end
		local size = Vector3.new(math.max(ext.X * 2, 4), math.max(ext.Y * 2, 5), math.max(ext.Z * 2, 4))
		local dmg, names, sources = 0, {}, {}
		for _, h in c.hits do
			dmg += h.data.amount or 0
			local tgt = h.data.target or h.data.victim
			if tgt and not table.find(names, tgt) then table.insert(names, tgt) end
			local src = h.cat == "HITBOX" and h.data.name or nil
			if src and not table.find(sources, src) then table.insert(sources, src) end
		end
		table.insert(out, { at = c.first, offset = center, size = size, hits = #c.hits, damage = dmg, targets = names, sources = sources })
	end
	return out
end

local function seqLua(seq)
	if not seq then return "nil" end
	if seq.kind == "number" then
		local kp = {}
		for _, k in seq.keypoints do table.insert(kp, string.format("NumberSequenceKeypoint.new(%s, %s, %s)", fmtNum(k.time, 4), fmtNum(k.value, 4), fmtNum(k.envelope, 4))) end
		return "NumberSequence.new({ " .. table.concat(kp, ", ") .. " })"
	elseif seq.kind == "color" then
		local kp = {}
		for _, k in seq.keypoints do
			local h = string.gsub(k.color, "#", "")
			table.insert(kp, string.format("ColorSequenceKeypoint.new(%s, Color3.fromRGB(%d, %d, %d))", fmtNum(k.time, 4),
				tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16)))
		end
		return "ColorSequence.new({ " .. table.concat(kp, ", ") .. " })"
	elseif seq.kind == "range" then
		return string.format("NumberRange.new(%s, %s)", fmtNum(seq.min, 4), fmtNum(seq.max, 4))
	end
	return "nil"
end

local function emitterLua(e, var)
	local L = {}
	local function add(s) table.insert(L, s) end
	add(string.format("\t\tlocal %s = Instance.new(%q)", var, e.class))
	add(string.format("\t\t%s.Name = %s", var, luaStr(e.name)))
	local skip = { class = true, name = true, hostName = true, hostClass = true, hostPath = true, hostSize = true,
		hostMaterial = true, hostTransparency = true, hostColor = true, hostShape = true, hostCanCollide = true,
		hostOffset = true, hostParent = true, attributes = true }
	for k, v in e do
		if not skip[k] then
			if type(v) == "table" and v.kind then
				add(string.format("\t\t%s.%s = %s", var, k, seqLua(v)))
			elseif type(v) == "table" and #v == 3 and type(v[1]) == "number" then
				add(string.format("\t\t%s.%s = Vector3.new(%s, %s, %s)", var, k, fmtNum(v[1], 3), fmtNum(v[2], 3), fmtNum(v[3], 3)))
			elseif type(v) == "number" then
				add(string.format("\t\t%s.%s = %s", var, k, fmtNum(v, 4)))
			elseif type(v) == "string" then
				if k == "Texture" then
					add(string.format("\t\t%s.Texture = %s", var, luaStr(v)))
				else
					add(string.format("\t\t%s.%s = Enum.%s.%s", var, k, (e.class == "Beam" or e.class == "Trail") and "TextureMode" or "", v))
				end
			elseif type(v) == "boolean" then
				add(string.format("\t\t%s.%s = %s", var, k, tostring(v)))
			end
		end
	end
	return table.concat(L, "\n")
end

local function phaseDivider()
	return string.rep("─", 26) .. " HIT " .. string.rep("─", 26)
end

function Out.timeline(rec, opts)
	local lines = {}
	table.insert(lines, string.format("MOVE #%d · %s · %ss · %d events · %s · place %s", rec.index, rec.name, fmtNum(rec.duration, 3), #rec.events, rec.when, tostring(rec.placeId)))
	table.insert(lines, string.format("you: %s · victims: %s · started by %s, stopped by %s · start speed %s, peak %s%s", rec.character,
		#rec.victims > 0 and table.concat(rec.victims, ", ") or "none", rec.startReason or "?", rec.reason or "?",
		fmtNum(rec.startSpeed or 0, 1), fmtNum(rec.peakSpeed or 0, 1), rec.saveFolder and (" · clones in " .. rec.saveFolder) or ""))
	if rec.startupDuration then
		table.insert(lines, string.format("startup %ss, hit at %ss — startup is wind-up only", fmtNum(rec.startupDuration, 3), fmtNum(rec.startupDuration, 3)))
	end
	table.insert(lines, string.rep("─", 72))
	local shown = false
	for _, ev in evFilter(rec, opts) do
		if rec.startupDuration and not shown and ev.rt >= rec.startupDuration then
			table.insert(lines, phaseDivider())
			shown = true
		end
		table.insert(lines, string.format("%+8.3f  %-10s %-10s %s", ev.rt, ev.cat, string.sub(ev.who, 1, 10), ev.text))
	end
	return table.concat(lines, "\n")
end

function Out.summary(rec)
	local L = {}
	local function add(s) table.insert(L, s) end
	add(string.format("MOVE #%d · %s · %ss · you: %s · victims: %s", rec.index, rec.name, fmtNum(rec.duration, 3), rec.character, #rec.victims > 0 and table.concat(rec.victims, ", ") or "none"))
	if rec.startupDuration then
		add(string.format("startup %ss → hit at %ss. Startup holds no victim data by design.", fmtNum(rec.startupDuration, 3), fmtNum(rec.startupDuration, 3)))
	end
	local function sect(title, pred, fmt)
		local items = {}
		for _, ev in rec.events do if pred(ev) then table.insert(items, fmt(ev)) end end
		if #items > 0 then
			add("")
			add("■ " .. title .. " (" .. #items .. ")")
			for _, s in items do add("  " .. s) end
		end
	end
	local function at(ev) return string.format("%6.3f", ev.rt) end
	local function isStartup(ev) return rec.startupDuration ~= nil and ev.phase == "startup" end
	local function isHit(ev) return rec.startupDuration == nil or ev.phase == "hit" end

	if rec.startupDuration then
		sect("Startup · animations", function(e) return isStartup(e) and e.cat == "ANIM" and e.who == "YOU" and not e.data.kind end, function(e)
			return string.format("%s  rbxassetid://%s  %s  speed %s", at(e), e.data.id, e.data.name, fmtNum(e.data.speed))
		end)
		sect("Startup · effects / sounds / hitboxes", function(e) return isStartup(e) and (e.cat == "VFX" or e.cat == "SOUND" or e.cat == "HITBOX") end, function(e)
			return at(e) .. "  " .. e.cat .. "  " .. e.text
		end)
		sect("Startup · velocity / states", function(e) return isStartup(e) and (e.cat == "VELOCITY" or e.cat == "STATE" or e.cat == "MOVE") end, function(e)
			return at(e) .. "  " .. e.who .. "  " .. e.text
		end)
		add("")
		add(phaseDivider())
	end

	sect("Your animations", function(e) return isHit(e) and e.cat == "ANIM" and e.who == "YOU" and not e.data.kind end, function(e)
		local d = e.data
		local m = {}
		for _, mk in d.markers or {} do table.insert(m, mk.name .. "@" .. fmtNum(mk.time, 3)) end
		return string.format("%s  rbxassetid://%s  %s  speed %s  length %ss  played %ss%s", at(e), d.id, d.name, fmtNum(d.speed), fmtNum(d.length or 0, 3), fmtNum(d.played or 0, 3),
			#m > 0 and ("  markers: " .. table.concat(m, ", ")) or "")
	end)
	sect("Animation events", function(e) return isHit(e) and (e.cat == "MARKER" or (e.cat == "ANIM" and e.data.kind)) end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect("Velocity", function(e) return isHit(e) and e.cat == "VELOCITY" end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect("Sounds", function(e) return isHit(e) and e.cat == "SOUND" end, function(e)
		local d = e.data
		return string.format("%s  rbxassetid://%s  %s  vol %s pitch %s  on %s%s", at(e), d.id, d.name, fmtNum(d.volume), fmtNum(d.speed), d.parent, d.played and ("  (" .. fmtNum(d.played, 2) .. "s)") or "")
	end)
	sect("Effects", function(e) return isHit(e) and e.cat == "VFX" and not e.data.kind end, function(e)
		local d = e.data
		local em = {}
		for _, em2 in d.emitters or {} do table.insert(em, string.format("%s{%s}", em2.name, emitterText(em2))) end
		local meshes = {}
		for _, m in d.meshes or {} do table.insert(meshes, m.meshId or m.texture or "?") end
		return string.format("%s  %s '%s' in %s  host size %s%s%s%s%s%s", at(e), d.class, d.name, d.path,
			d.size and v3s(d.size) or "?", #em > 0 and ("  emitters: " .. table.concat(em, " ")) or "",
			#meshes > 0 and ("  meshes: " .. table.concat(meshes, ", ")) or "",
			#(d.sounds or {}) > 0 and ("  sounds: " .. tostring(#d.sounds)) or "",
			d.offset and ("  at " .. v3s(d.offset)) or "", d.lifetime and ("  lived " .. fmtNum(d.lifetime, 2) .. "s") or "")
	end)
	sect("Hitbox parts", function(e) return isHit(e) and e.cat == "HITBOX" and e.data.kind ~= "touch" end, function(e)
		local d = e.data
		return string.format("%s  '%s' (%s/%s)  size %s  offset %s%s%s", at(e), d.name, d.hitboxKind, d.kind or "add", d.size and v3s(d.size) or "?",
			d.offset and v3s(d.offset) or "?", d.lifetime and ("  lived " .. fmtNum(d.lifetime, 3) .. "s") or "", d.weldedTo and ("  welded " .. d.weldedTo) or "")
	end)
	sect("Hitbox touches", function(e) return e.cat == "HITBOX" and e.data.kind == "touch" end, function(e)
		return string.format("%s  '%s' touched %s%s  offset %s  %s studs", at(e), e.data.name, e.data.touched, e.data.victim and (" [VICTIM " .. e.data.victim .. "]") or "",
			e.data.offset and v3s(e.data.offset) or "?", fmtNum(e.data.distance or 0, 1))
	end)
	local inf = inferHitboxes(rec)
	if #inf > 0 then
		add("")
		add("■ Hitboxes inferred from hits/touches (" .. #inf .. ")  — box in YOUR local space")
		for _, h in inf do
			add(string.format("  %6.3f  offset %s  size ≥ %s  %d contact(s) %s dmg on %s%s", h.at, v3s(h.offset), v3s(h.size), h.hits, fmtNum(h.damage, 1),
				table.concat(h.targets, ", "), #h.sources > 0 and ("  via " .. table.concat(h.sources, ", ")) or ""))
		end
	end
	sect("Movement", function(e) return isHit(e) and e.cat == "MOVE" end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	if #rec.path > 1 then
		local last = rec.path[#rec.path]
		add("")
		add(string.format("■ Your displacement over the move: %s  (start-relative: fwd = -Z)", dirWords(last.pos)))
	end
	sect("Damage", function(e) return e.cat == "HIT" end, function(e) return at(e) .. "  " .. e.text end)
	if #rec.victims > 0 then
		add("")
		add("■ Victims")
		for name, info in rec.victimInfo or {} do
			add(string.format("  %s — first seen %ss, closest %s studs, peak speed %s, hp %s/%s, tracked by %s", name, fmtNum(info.firstAt or 0, 2),
				fmtNum(info.minDistance or 0, 1), fmtNum(info.peakSpeed or 0, 1), fmtNum(info.health or 0, 1), fmtNum(info.maxHealth or 0, 1),
				#info.reasons > 0 and table.concat(info.reasons, "+") or "?"))
		end
	end
	sect("Victim reactions", function(e) return e.victim and (e.cat == "ANIM" or e.cat == "STATE" or e.cat == "VELOCITY") end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect("Your states / markers", function(e) return e.who == "YOU" and e.cat == "STATE" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Camera", function(e) return e.cat == "CAMERA" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Screen", function(e) return e.cat == "SCREEN" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Remotes", function(e) return e.cat == "REMOTE" or e.cat == "REPLICATION" end, function(e) return at(e) .. "  " .. e.text end)
	return table.concat(L, "\n")
end

function Out.moveTable(rec)
	local L = {}
	local function add(s) table.insert(L, s) end
	local function T(t) return fmtNum(math.max(t, 0), 3) end
	add(string.format("-- Move #%d · %s · recorded %s by MoveLogger", rec.index, rec.name, rec.when))
	add("-- times in seconds from the start · offsets/velocities are local to you at that moment (forward = -Z)")
	if rec.startupDuration then
		add(string.format("-- ADVANCED: Startup ends at %ss, everything with Phase = \"hit\" happens from there.", T(rec.startupDuration)))
	end
	add("return {")
	add(string.format("\tIndex = %d,", rec.index))
	add(string.format("\tName = %s,", luaStr(rec.name)))
	add(string.format("\tDuration = %s,", T(rec.duration)))
	if rec.startupDuration then add(string.format("\tStartupDuration = %s,", T(rec.startupDuration))) end
	add(string.format("\tStartLocalVelocity = %s,", v3lua(rec.startVelocity or Vector3.zero)))
	add(string.format("\tStartSpeed = %s,", fmtNum(rec.startSpeed or 0, 3)))
	add(string.format("\tPeakSpeed = %s,", fmtNum(rec.peakSpeed or 0, 3)))
	local function tag(ev, s)
		if rec.startupDuration then
			return (string.gsub(s, "^{ ", "{ Phase = " .. luaStr(ev.phase or "hit") .. ", ", 1))
		end
		return s
	end
	local function list(title, pred, fmt)
		add("\t" .. title .. " = {")
		for _, ev in rec.events do
			if pred(ev) then add("\t\t" .. tag(ev, fmt(ev)) .. ",") end
		end
		add("\t},")
	end
	list("Animations", function(e) return e.cat == "ANIM" and e.who == "YOU" and not e.data.kind end, function(e)
		local d = e.data
		local m = {}
		for _, mk in d.markers or {} do table.insert(m, string.format("{ Name = %s, Time = %s }", luaStr(mk.name), fmtNum(mk.time, 3))) end
		return string.format("{ At = %s, Id = \"rbxassetid://%s\", Name = %s, Priority = %q, Speed = %s, Length = %s, Played = %s%s }", T(e.rt), d.id, luaStr(d.name), d.priority,
			fmtNum(d.speed, 3), fmtNum(d.length or 0, 3), fmtNum(d.played or 0, 3), #m > 0 and (", Markers = { " .. table.concat(m, ", ") .. " }") or "")
	end)
	list("AnimationEvents", function(e) return (e.cat == "MARKER" or (e.cat == "ANIM" and e.data.kind)) and e.who == "YOU" end, function(e)
		return string.format("{ At = %s, Kind = %q, Name = %s, AnimTime = %s, Param = %s }", T(e.rt), e.data.kind or "marker",
			luaStr(e.data.name or e.data.id or "?"), fmtNum(e.data.at or 0, 3), luaStr(e.data.param or ""))
	end)
	add("\tVelocity = {")
	local vstep = math.max(1, math.floor(math.max(#rec.path, 1) / 80))
	for i = 1, #rec.path, vstep do
		local p = rec.path[i]
		if p.vel then add(string.format("\t\t{ At = %s, LocalVelocity = %s, Speed = %s },", T(p.t), v3lua(p.vel), fmtNum(p.speed or 0, 2))) end
	end
	add("\t},")
	add("\tVelocityPhases = {")
	for _, ph in velocityPhases(rec.path) do
		add(string.format("\t\t{ From = %s, To = %s, LocalVelocity = %s, PeakSpeed = %s, PeakAt = %s },", T(ph.from), T(ph.to), v3lua(ph.dir),
			fmtNum(ph.peak, 2), T(ph.peakAt)))
	end
	add("\t},")
	list("VelocityEvents", function(e) return e.cat == "VELOCITY" and e.who == "YOU" end, function(e)
		local d = e.data
		if d.localVelocity then return string.format("{ At = %s, Kind = %q, LocalVelocity = %s, Speed = %s }", T(e.rt), d.kind or "?", v3lua(d.localVelocity), fmtNum(d.speed or 0, 2)) end
		return string.format("{ At = %s, Kind = %q }", T(e.rt), d.kind or "?")
	end)
	list("Sounds", function(e) return e.cat == "SOUND" and not e.victim end, function(e)
		local d = e.data
		return string.format("{ At = %s, Id = \"rbxassetid://%s\", Name = %s, Volume = %s, PlaybackSpeed = %s, TimePosition = %s, Parent = %s, Duration = %s, RollOffMode = %q, EmitterSize = %s }",
			T(e.rt), d.id, luaStr(d.name), fmtNum(d.volume, 3), fmtNum(d.speed, 3), fmtNum(d.timePosition, 3), luaStr(d.parent), fmtNum(d.played or d.length or 0, 3),
			d.rollOffMode or "Inverse", fmtNum(d.emitterSize or 10, 2))
	end)
	list("Effects", function(e) return e.cat == "VFX" and not e.data.kind end, function(e)
		local d = e.data
		return string.format("{ At = %s, Name = %s, Class = %q, Folder = %s, Offset = %s, HostSize = %s, Lifetime = %s, EmitterCount = %d%s%s }",
			T(e.rt), luaStr(d.name), d.class, luaStr(d.folder or "?"), d.offsetCF and cflua(d.offsetCF) or "CFrame.new()",
			d.size and v3lua(d.size) or "Vector3.one", fmtNum(d.lifetime or 0, 3), #(d.emitters or {}),
			d.saved and (", Saved = " .. luaStr(d.saved)) or "", d.weldedTo and (", WeldedTo = " .. luaStr(d.weldedTo)) or "")
	end)
	add("\tEmitterDumps = {")
	local ei = 0
	for _, ev in rec.events do
		if ev.cat == "VFX" and not ev.data.kind then
			ei += 1
			add(string.format("\t\t[%d] = { -- effect %s '%s' at %ss", ei, ev.data.class, ev.data.name, T(ev.rt)))
			for _, em in ev.data.emitters or {} do
				add("\t\t\t{ -- EMITTER on part of size " .. (em.hostSize and v3lua(Vector3.new(em.hostSize[1], em.hostSize[2], em.hostSize[3])) or "?"))
				add(emitterLua(em, "em"))
				add("\t\t\t},")
			end
			for _, em in ev.data.beams or {} do
				add("\t\t\t{ -- BEAM")
				add(emitterLua(em, "bm"))
				add("\t\t\t},")
			end
			for _, em in ev.data.trails or {} do
				add("\t\t\t{ -- TRAIL")
				add(emitterLua(em, "tr"))
				add("\t\t\t},")
			end
			add("\t\t},")
		end
	end
	add("\t},")
	list("EffectToggles", function(e) return e.cat == "VFX" and e.data.kind == "toggle" and e.who == "YOU" end, function(e)
		return string.format("{ At = %s, Path = %s, Enabled = %s }", T(e.rt), luaStr(e.data.path), tostring(e.data.enabled))
	end)
	list("Hitboxes", function(e) return e.cat == "HITBOX" and e.data.kind ~= "touch" end, function(e)
		local d = e.data
		return string.format("{ At = %s, Name = %s, Kind = %q, Size = %s, Offset = %s, Duration = %s, Welded = %s, Source = \"part\" }", T(e.rt), luaStr(d.name), d.kind or "add",
			d.size and v3lua(d.size) or "Vector3.one", d.offsetCF and cflua(d.offsetCF) or "CFrame.new()", fmtNum(d.lifetime or 0.1, 3), tostring(d.weldedTo ~= nil))
	end)
	list("HitboxTouches", function(e) return e.cat == "HITBOX" and e.data.kind == "touch" end, function(e)
		local d = e.data
		return string.format("{ At = %s, Hitbox = %s, Touched = %s, Victim = %s, Offset = %s, Distance = %s }", T(e.rt), luaStr(d.name), luaStr(d.touched),
			luaStr(d.victim or ""), d.offsetCF and cflua(d.offsetCF) or "CFrame.new()", fmtNum(d.distance or 0, 2))
	end)
	add("\tInferredHitboxes = {")
	for _, h in inferHitboxes(rec) do
		add(string.format("\t\t{ At = %s, Offset = CFrame.new(%s, %s, %s), Size = %s, Hits = %d, Damage = %s },", T(h.at), fmtNum(h.offset.X), fmtNum(h.offset.Y), fmtNum(h.offset.Z),
			v3lua(h.size), h.hits, fmtNum(h.damage, 2)))
	end
	add("\t},")
	list("Movement", function(e) return e.cat == "MOVE" and e.who == "YOU" and e.data.kind ~= "end" end, function(e)
		local d = e.data
		if d.kind == "impulse" then return string.format("{ At = %s, Kind = \"Impulse\", LocalVelocity = %s }", T(e.rt), v3lua(d.localVelocity)) end
		return string.format("{ At = %s, Class = %q%s%s%s }", T(e.rt), d.class or "?", d.localVelocity and (", LocalVelocity = " .. v3lua(d.localVelocity)) or "",
			d.localPosition and (", LocalPosition = " .. v3lua(d.localPosition)) or "", d.duration and (", Duration = " .. fmtNum(d.duration, 3)) or "")
	end)
	list("Damage", function(e) return e.cat == "HIT" and e.who ~= "YOU" end, function(e)
		return string.format("{ At = %s, Target = %s, Amount = %s }", T(e.rt), luaStr(e.data.target), fmtNum(e.data.amount, 2))
	end)
	add("\tVictim = {")
	for name, info in rec.victimInfo or {} do
		add(string.format("\t\t[%s] = {", luaStr(name)))
		add(string.format("\t\t\tFirstAt = %s, MinDistance = %s, PeakSpeed = %s, Health = %s, MaxHealth = %s, TrackedBy = %s,",
			fmtNum(info.firstAt or 0, 3), fmtNum(info.minDistance or 0, 2), fmtNum(info.peakSpeed or 0, 2),
			fmtNum(info.health or 0, 1), fmtNum(info.maxHealth or 0, 1), luaStr(table.concat(info.reasons or {}, "+"))))
		add("\t\t\tTrack = {")
		local tr = info.track or {}
		local tstep = math.max(1, math.floor(math.max(#tr, 1) / 60))
		for i = 1, #tr, tstep do
			local p = tr[i]
			add(string.format("\t\t\t\t{ At = %s, Offset = %s, LocalVelocity = %s, Speed = %s, Distance = %s },", T(p.t), v3lua(p.pos),
				p.vel and v3lua(p.vel) or "Vector3.zero", fmtNum(p.speed or 0, 2), fmtNum(p.dist or 0, 2)))
		end
		add("\t\t\t},")
		add("\t\t},")
	end
	local function vlist(title, pred, fmt)
		add("\t\t" .. title .. " = {")
		for _, ev in rec.events do
			if ev.victim and pred(ev) then add("\t\t\t" .. tag(ev, fmt(ev)) .. ",") end
		end
		add("\t\t},")
	end
	vlist("Animations", function(e) return e.cat == "ANIM" and not e.data.kind end, function(e)
		return string.format("{ At = %s, Who = %s, Id = \"rbxassetid://%s\", Name = %s, Speed = %s, Played = %s }", T(e.rt), luaStr(e.who), e.data.id, luaStr(e.data.name),
			fmtNum(e.data.speed, 3), fmtNum(e.data.played or 0, 3))
	end)
	vlist("Knockback", function(e) return (e.cat == "MOVE" and e.data.kind ~= "end") or (e.cat == "VELOCITY" and e.data.localVelocity) end, function(e)
		local d = e.data
		return string.format("{ At = %s, Who = %s, Class = %q%s%s%s }", T(e.rt), luaStr(e.who), d.class or d.kind or "Impulse",
			d.localVelocity and (", LocalVelocity = " .. v3lua(d.localVelocity)) or "", d.speed and (", Speed = " .. fmtNum(d.speed, 2)) or "",
			d.duration and (", Duration = " .. fmtNum(d.duration, 3)) or "")
	end)
	vlist("Markers", function(e) return e.cat == "STATE" and e.data.kind == "childAdded" end, function(e)
		local dur
		for _, x in rec.events do
			if x.model == e.model and x.cat == "STATE" and x.data.kind == "childRemoved" and x.data.name == e.data.name and x.rt >= e.rt then dur = x.data.duration break end
		end
		return string.format("{ At = %s, Who = %s, Class = %q, Name = %s, Duration = %s%s }", T(e.rt), luaStr(e.who), e.data.class, luaStr(e.data.name), fmtNum(dur or 0, 3),
			e.data.attributes and next(e.data.attributes) and (", Attributes = " .. ser(e.data.attributes)) or "")
	end)
	vlist("States", function(e) return e.cat == "STATE" and (e.data.kind == "humanoidState" or e.data.kind == "property" or e.data.kind == "attribute") end, function(e)
		local d = e.data
		return string.format("{ At = %s, Who = %s, Kind = %q, Name = %s, To = %s }", T(e.rt), luaStr(e.who), d.kind, luaStr(d.property or d.name or d.to), ser(d.to))
	end)
	add("\t},")
	list("Camera", function(e) return e.cat == "CAMERA" end, function(e)
		local d = e.data
		if d.kind == "fov" then
			return string.format("{ At = %s, Kind = \"FOV\", From = %s, Peak = %s, To = %s, PeakAt = %s, Duration = %s }", T(e.rt), fmtNum(d.from, 2), fmtNum(d.peak, 2),
				fmtNum(d.to, 2), fmtNum(d.peakAt, 3), fmtNum(d.duration, 3))
		end
		return string.format("{ At = %s, Kind = \"Shake\", Duration = %s, Strength = %s }", T(e.rt), fmtNum(d.duration or 0, 3), fmtNum(d.strength or 0, 3))
	end)
	list("Screen", function(e) return e.cat == "SCREEN" end, function(e)
		return string.format("{ At = %s, Kind = %q, Class = %q, Name = %s }", T(e.rt), e.data.kind or "?", e.data.class or "?", luaStr(e.data.name or "?"))
	end)
	list("Remotes", function(e) return e.cat == "REMOTE" or e.cat == "REPLICATION" end, function(e)
		return string.format("{ At = %s, Remote = %s, Label = %s, Args = %s }", T(e.rt), luaStr(e.data.remote), luaStr(e.data.label or ""), luaStr(ser(e.data.args)))
	end)
	add("\tPath = {")
	local step = math.max(1, math.floor(#rec.path / 40))
	for i = 1, #rec.path, step do
		local p = rec.path[i]
		add(string.format("\t\t{ At = %s, Offset = %s, Speed = %s },", T(p.t), v3lua(p.pos), fmtNum(p.speed or 0, 2)))
	end
	add("\t},")
	add("}")
	return table.concat(L, "\n")
end

local REPLAY_PRELUDE = [==[
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EffectsFolder = ReplicatedStorage:FindFirstChild("MoveEffects")

local Move = {}

local function playAnim(humanoid, id, speed)
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid
	local a = Instance.new("Animation")
	a.AnimationId = id
	local track = animator:LoadAnimation(a)
	track:Play()
	if speed and speed ~= 1 then track:AdjustSpeed(speed) end
	return track
end

local function playSound(parent, id, volume, speed, timePosition, life, rollOffMode, emitterSize)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume or 1
	s.PlaybackSpeed = speed or 1
	s.TimePosition = timePosition or 0
	if rollOffMode then pcall(function() s.RollOffMode = Enum.RollOffMode[rollOffMode] end) end
	if emitterSize then s.EmitterSize = emitterSize end
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, math.max(life or 0, 0.1) + 1)
	return s
end

local function spawnEffect(root, savedName, offset, life)
	local src = EffectsFolder and EffectsFolder:FindFirstChild(savedName, true)
	if not src then return nil end
	local fx = src:Clone()
	local cf = root.CFrame * offset
	if fx:IsA("BasePart") then
		fx.CFrame = cf
		fx.Anchored = true
		fx.CanCollide = false
	elseif fx:IsA("Model") then
		fx:PivotTo(cf)
	elseif fx:IsA("Attachment") then
		fx.Parent = workspace.Terrain
		fx.WorldCFrame = cf
	end
	if not fx.Parent then fx.Parent = workspace:FindFirstChild("Thrown") or workspace end
	for _, d in fx:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local n = d:GetAttribute("EmitCount")
			local delay = d:GetAttribute("EmitDelay") or 0
			if n then task.delay(delay, function() d:Emit(n) end) end
		end
	end
	Debris:AddItem(fx, math.max(life or 1, 0.2) + 1)
	return fx
end

local function addVelocity(root, localVelocity, duration, maxForce, space)
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VectorVelocity = (space or root.CFrame):VectorToWorldSpace(localVelocity)
	lv.MaxForce = maxForce or 1e6
	lv.Parent = root
	Debris:AddItem(lv, duration)
	Debris:AddItem(att, duration)
end

local function hitbox(character, root, offset, size, duration, onHit)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = {}
	local stop = os.clock() + duration
	repeat
		for _, part in workspace:GetPartBoundsInBox(root.CFrame * offset, size, params) do
			local model = part:FindFirstAncestorOfClass("Model")
			local hum = model and model:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 and not hit[model] then
				hit[model] = true
				task.spawn(onHit, model, hum)
			end
		end
		task.wait()
	until os.clock() >= stop
end
]==]

function Out.replay(rec)
	local L = {}
	local function add(s) table.insert(L, s) end
	local function T(t) return fmtNum(math.max(t, 0), 3) end
	add("--[[")
	add(string.format("\tMove #%d · %s  ·  generated by MoveLogger from a %ss recording (%s)", rec.index, rec.name, fmtNum(rec.duration, 3), rec.when))
	if rec.startupDuration then
		add(string.format("\tADVANCED: startup runs 0–%ss, the hit lands at %ss. Startup is wind-up only.", T(rec.startupDuration), T(rec.startupDuration)))
	end
	add("\tA starting point, not a finished move: check hitboxes / damage / parents against your framework.")
	add("\tClones: copy " .. (rec.saveFolder or "ReplicatedStorage.MoveLogger_Logged.<rec>") .. " into ReplicatedStorage.MoveEffects in Studio.")
	add("\tUse: local Move = require(this) ; Move.Play(character)  -- server")
	add("--]]")
	add(REPLAY_PRELUDE)
	add("")
	local firstHit
	for _, ev in rec.events do
		if ev.cat == "HIT" and ev.who ~= "YOU" and (ev.data.amount or 0) > 0 then firstHit = ev.rt break end
	end
	add("local function victimReaction(attackerRoot, victim, humanoid, damage)")
	add("\thumanoid:TakeDamage(damage)")
	add("\tlocal vroot = victim:FindFirstChild(\"HumanoidRootPart\")")
	if firstHit then
		local victimName
		for _, ev in rec.events do
			if ev.cat == "HIT" and ev.who ~= "YOU" and ev.rt == firstHit then victimName = ev.who break end
		end
		for _, ev in rec.events do
			if ev.victim and ev.who == victimName and ev.rt >= firstHit - 0.05 then
				local dt = T(ev.rt - firstHit)
				if ev.cat == "ANIM" and not ev.data.kind then
					add(string.format("\ttask.delay(%s, playAnim, humanoid, \"rbxassetid://%s\", %s) -- %s", dt, ev.data.id, fmtNum(ev.data.speed, 3), ev.data.name))
				elseif (ev.cat == "MOVE" and ev.data.localVelocity and ev.data.kind ~= "end") or (ev.cat == "VELOCITY" and ev.data.localVelocity) then
					add(string.format("\ttask.delay(%s, function() if vroot then addVelocity(vroot, %s, %s, nil, attackerRoot.CFrame) end end) -- knockback",
						dt, v3lua(ev.data.localVelocity), fmtNum(ev.data.duration or 0.2, 3)))
				elseif ev.cat == "STATE" and ev.data.kind == "childAdded" then
					local dur
					for _, x in rec.events do
						if x.model == ev.model and x.cat == "STATE" and x.data.kind == "childRemoved" and x.data.name == ev.data.name and x.rt >= ev.rt then dur = x.data.duration break end
					end
					local attrs = ""
					for k, v in ev.data.attributes or {} do
						if type(v) == "number" or type(v) == "boolean" or type(v) == "string" then
							attrs ..= string.format(" m:SetAttribute(%s, %s)", luaStr(k), type(v) == "string" and luaStr(v) or tostring(v))
						end
					end
					add(string.format("\ttask.delay(%s, function() local m = Instance.new(%q) m.Name = %s%s m.Parent = victim Debris:AddItem(m, %s) end) -- marker",
						dt, ev.data.class == "Accessory" and "Folder" or ev.data.class, luaStr(ev.data.name), attrs, fmtNum(dur or 1, 3)))
				end
			end
		end
	else
		add("\t-- (no hits were recorded)")
	end
	add("end")
	add("")
	add("function Move.Play(character)")
	add("\tlocal humanoid = character:FindFirstChildOfClass(\"Humanoid\")")
	add("\tlocal root = character:FindFirstChild(\"HumanoidRootPart\")")
	add("\tif not humanoid or not root then return end")
	if rec.startSpeed and rec.startSpeed > 1 then
		add(string.format("\taddVelocity(root, %s, 0.05, nil, root.CFrame) -- launch velocity", v3lua(rec.startVelocity)))
	end
	local hb = {}
	for _, ev in rec.events do
		if ev.cat == "HITBOX" and ev.data.kind ~= "touch" then
			table.insert(hb, { at = ev.rt, offset = ev.data.offsetCF, size = ev.data.size, dur = ev.data.lifetime or 0.1, part = true })
		end
	end
	local inferred = inferHitboxes(rec)
	if #hb == 0 then
		for _, h in inferred do table.insert(hb, { at = h.at - 0.03, offset = CFrame.new(h.offset), size = h.size, dur = 0.1, damage = h.damage / math.max(h.hits, 1) }) end
	end
	local defaultDamage = 10
	if #inferred > 0 then defaultDamage = inferred[1].damage / math.max(inferred[1].hits, 1) end
	local lines = {}
	for _, ev in rec.events do
		local t = ev.rt
		if ev.who == "YOU" and ev.cat == "ANIM" and not ev.data.kind then
			table.insert(lines, { t, string.format("task.delay(%s, playAnim, humanoid, \"rbxassetid://%s\", %s) -- %s%s", T(t), ev.data.id, fmtNum(ev.data.speed, 3), ev.data.name,
				ev.phase == "startup" and "  [startup]" or "") })
		elseif ev.cat == "SOUND" and not ev.victim then
			table.insert(lines, { t, string.format("task.delay(%s, playSound, root, \"rbxassetid://%s\", %s, %s, %s, %s, %s, %s) -- %s", T(t), ev.data.id, fmtNum(ev.data.volume, 3),
				fmtNum(ev.data.speed, 3), fmtNum(ev.data.timePosition, 3), fmtNum(ev.data.played or ev.data.length or 1, 3), luaStr(ev.data.rollOffMode or "Inverse"),
				fmtNum(ev.data.emitterSize or 10, 2), ev.data.name) })
		elseif ev.cat == "VFX" and not ev.data.kind then
			local contents = {}
			for k, v in ev.data.contents or {} do table.insert(contents, k .. "x" .. v) end
			table.insert(lines, { t, string.format("task.delay(%s, spawnEffect, root, %s, %s, %s) -- %s [%s]", T(t), luaStr(ev.data.saved or ev.data.name),
				ev.data.offsetCF and cflua(ev.data.offsetCF) or "CFrame.new()", fmtNum(ev.data.lifetime or 1, 3), ev.data.class, table.concat(contents, " ")) })
		elseif ev.who == "YOU" and ev.cat == "MOVE" and ev.data.localVelocity and ev.data.kind ~= "end" then
			table.insert(lines, { t, string.format("task.delay(%s, addVelocity, root, %s, %s) -- %s", T(t), v3lua(ev.data.localVelocity), fmtNum(ev.data.duration or 0.15, 3), ev.data.class or "impulse") })
		elseif ev.who == "YOU" and ev.cat == "VELOCITY" and ev.data.kind == "velocityPhase" and ev.data.localVelocity then
			table.insert(lines, { t, string.format("task.delay(%s, addVelocity, root, %s, %s) -- motion phase, peak %s", T(t), v3lua(ev.data.localVelocity),
				fmtNum(ev.data.duration or 0.2, 3), fmtNum(ev.data.peakSpeed or 0, 1)) })
		elseif ev.who == "YOU" and ev.cat == "STATE" and ev.data.kind == "property" then
			table.insert(lines, { t, string.format("task.delay(%s, function() pcall(function() %s = %s end) end)", T(t),
				ev.data.property == "Anchored" and "root.Anchored" or ("humanoid." .. ev.data.property), ser(ev.data.to)) })
		end
	end
	for _, h in hb do
		table.insert(lines, { h.at, string.format("task.delay(%s, function() hitbox(character, root, %s, %s, %s, function(victim, hum) victimReaction(root, victim, hum, %s) end) end) -- hitbox%s",
			T(h.at), h.offset and cflua(h.offset) or "CFrame.new(0, 0, -4)", h.size and v3lua(h.size) or "Vector3.new(5, 5, 5)", fmtNum(math.max(h.dur, 0.05), 3),
			fmtNum(h.damage or defaultDamage, 2), h.part and " (server hitbox part)" or " (inferred)") })
	end
	table.sort(lines, function(a, b) return a[1] < b[1] end)
	for _, l in lines do add("\t" .. l[2]) end
	add("end")
	add("")
	add("return Move")
	return table.concat(L, "\n")
end

function Out.json(rec)
	local evs = {}
	for _, ev in rec.events do
		table.insert(evs, { t = r(ev.rt, 4), cat = ev.cat, who = ev.who, victim = ev.victim or nil, phase = ev.phase, text = ev.text, data = plain(ev.data) })
	end
	local ok, s = pcall(HttpService.JSONEncode, HttpService, {
		index = rec.index, name = rec.name, duration = r(rec.duration, 4), startupDuration = rec.startupDuration,
		when = rec.when, placeId = rec.placeId, character = rec.character, victims = rec.victims, victimInfo = plain(rec.victimInfo),
		startSpeed = rec.startSpeed, peakSpeed = rec.peakSpeed,
		events = evs, inferredHitboxes = plain(inferHitboxes(rec)), path = plain(rec.path), victimPaths = plain(rec.victimPaths),
	})
	return ok and s or ("JSON failed: " .. tostring(s))
end

---------------------------------------------------------------------------------------------------
-- UI core
---------------------------------------------------------------------------------------------------
local function make(class, props, children)
	local i = Instance.new(class)
	for k, v in props or {} do if k ~= "Parent" then i[k] = v end end
	for _, c in children or {} do c.Parent = i end
	if props and props.Parent then i.Parent = props.Parent end
	return i
end
local function corner(rad) return make("UICorner", { CornerRadius = UDim.new(0, rad or 8) }) end
local function stroke(col, th) return make("UIStroke", { Color = col or THEME.Stroke, Thickness = th or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pad(p)
	return make("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) })
end
local FONT = Enum.Font.GothamMedium
local FONT_B = Enum.Font.GothamBold
local FONT_MONO = Enum.Font.Code

local function label(text, props)
	local p = { BackgroundTransparency = 1, Text = text, TextColor3 = THEME.Text, Font = FONT, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in props or {} do p[k] = v end
	return make("TextLabel", p)
end
local function button(text, props, onClick)
	local p = { BackgroundColor3 = THEME.Panel2, Text = text, TextColor3 = THEME.Text, Font = FONT, TextSize = 13, AutoButtonColor = false, Size = UDim2.fromOffset(80, 28) }
	for k, v in props or {} do p[k] = v end
	local st = stroke()
	local b = make("TextButton", p, { corner(7), st })
	b.MouseEnter:Connect(function() TweenService:Create(st, TweenInfo.new(0.12), { Color = THEME.Accent }):Play() end)
	b.MouseLeave:Connect(function() TweenService:Create(st, TweenInfo.new(0.12), { Color = THEME.Stroke }):Play() end)
	if onClick then b.Activated:Connect(guard(onClick)) end
	return b
end
local function hlist(gap, props)
	local p = { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }
	for k, v in props or {} do p[k] = v end
	return make("UIListLayout", p)
end
local function vlist(gap)
	return make("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder })
end

ownGui = make("ScreenGui", { Name = "MoveLogger", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })

local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
local W = math.clamp(vp.X - 24, 360, 660)
local H = math.clamp(vp.Y - 90, 360, 540)

local window = make("Frame", { Name = "Window", Size = UDim2.fromOffset(W, H), Position = UDim2.new(1, -W - 12, 0, 60), BackgroundColor3 = THEME.Bg, Parent = ownGui },
	{ corner(12), stroke(THEME.Stroke, 1) })
local titleBar = make("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundColor3 = THEME.Panel, Parent = window }, { corner(12) })
make("Frame", { Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -12), BackgroundColor3 = THEME.Panel, BorderSizePixel = 0, Parent = titleBar })
local statusDot = make("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.new(0, 14, 0.5, -5), BackgroundColor3 = THEME.Sub, Parent = titleBar }, { corner(5) })
label("Move Logger v2.4", { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(0, 140, 1, 0), Font = FONT_B, TextSize = 14, Parent = titleBar })
local statusText = label("idle", { Position = UDim2.fromOffset(160, 0), Size = UDim2.new(1, -250, 1, 0), TextColor3 = THEME.Sub, TextSize = 12, Parent = titleBar })
local minBtn = button("–", { Size = UDim2.fromOffset(28, 24), Position = UDim2.new(1, -66, 0.5, -12), Parent = titleBar })
local closeBtn = button("×", { Size = UDim2.fromOffset(28, 24), Position = UDim2.new(1, -34, 0.5, -12), Parent = titleBar })

local tabBar = make("Frame", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 44), BackgroundTransparency = 1, Parent = window }, { hlist(6) })
local content = make("Frame", { Size = UDim2.new(1, -20, 1, -86), Position = UDim2.fromOffset(10, 80), BackgroundTransparency = 1, ClipsDescendants = true, Parent = window })
local pages, tabButtons = {}, {}
local function showTab(name)
	for n, p in pages do p.Visible = n == name end
	for n, b in tabButtons do
		b.BackgroundColor3 = n == name and THEME.Accent or THEME.Panel2
		b.TextColor3 = n == name and Color3.new(1, 1, 1) or THEME.Sub
	end
	if UI.onTab then UI.onTab(name) end
end
for i, name in { "Record", "Moves", "Timeline", "Settings" } do
	local b = button(name, { Size = UDim2.fromOffset(math.floor((W - 20 - 18) / 4), 28), LayoutOrder = i, Parent = tabBar })
	tabButtons[name] = b
	pages[name] = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = content })
	b.Activated:Connect(function() showTab(name) end)
end

do
	local dragging, startPos, startInput
	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging, startPos, startInput = true, window.Position, input.Position
			input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	cn(UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - startInput
			window.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end))
end

local pill = button("ML", { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0, 12, 0.5, -22), BackgroundColor3 = THEME.Panel, Font = FONT_B, TextSize = 14, Parent = ownGui })
local pillCorner = pill:FindFirstChildOfClass("UICorner")
if pillCorner then pillCorner.CornerRadius = UDim.new(1, 0) end
local pillStroke = pill:FindFirstChildOfClass("UIStroke")
if pillStroke then pillStroke.Thickness = 2 end
local function toggleWindow() window.Visible = not window.Visible end
pill.Activated:Connect(toggleWindow)
closeBtn.Activated:Connect(function() window.Visible = false end)
local minimized = false
minBtn.Activated:Connect(function()
	minimized = not minimized
	tabBar.Visible = not minimized
	content.Visible = not minimized
	window.Size = minimized and UDim2.fromOffset(W, 38) or UDim2.fromOffset(W, H)
end)

local toastToken = 0
local toastLabel = label("", { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -20), TextXAlignment = Enum.TextXAlignment.Center,
	TextSize = 11, TextColor3 = THEME.Good, TextTransparency = 1, ZIndex = 20, Parent = window })
function toast(msg)
	toastToken += 1
	local token = toastToken
	toastLabel.Text = msg
	toastLabel.TextTransparency = 0
	task.delay(2, function()
		if toastToken ~= token then return end
		TweenService:Create(toastLabel, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	end)
end

function copyText(text, what, box)
	if typeof(setclipboard) == "function" and pcall(setclipboard, text) then
		toast("copied " .. what)
		return true
	end
	if box then
		box:CaptureFocus()
		task.defer(function()
			box.SelectionStart = 1
			box.CursorPosition = #box.Text + 1
		end)
		toast("selected " .. what .. " — press Ctrl+C")
	else
		toast("no clipboard available")
	end
	return false
end

---------------------------------------------------------------------------------------------------
-- Record page
---------------------------------------------------------------------------------------------------
section("record page", function()
	local page = pages.Record
	local big = label("IDLE", { Size = UDim2.new(1, 0, 0, 34), Font = FONT_B, TextSize = 24, Parent = page })
	local sub = label("Arm, then do a move — or Start / F6.", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 0, 18), TextColor3 = THEME.Sub, TextSize = 12, Parent = page })
	local row = make("Frame", { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, Parent = page }, { hlist(6) })
	local bw = math.floor((W - 20 - 18) / 4)
	local armB = button("Arm", { Size = UDim2.fromOffset(bw, 32), LayoutOrder = 1, Parent = row }, function() arm() end)
	local startB = button("● Start", { Size = UDim2.fromOffset(bw, 32), LayoutOrder = 2, BackgroundColor3 = Color3.fromRGB(60, 28, 34), Parent = row }, function() startRecording("manual") end)
	local stopB = button("■ Stop", { Size = UDim2.fromOffset(bw, 32), LayoutOrder = 3, Parent = row }, function()
		if Rec.state == "recording" then stopRecording("manual") else setState("idle") end
	end)
	button("Clear", { Size = UDim2.fromOffset(bw, 32), LayoutOrder = 4, Parent = row }, function()
		table.clear(History)
		Selected = 0
		if UI.refreshAll then UI.refreshAll() end
		toast("all moves cleared")
	end)
	armB.TextColor3 = THEME.Armed
	startB.TextColor3 = THEME.Rec

	local advRow = make("Frame", { Position = UDim2.fromOffset(0, 94), Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, Parent = page }, { hlist(6) })
	local advToggle = button("Advanced: off", { Size = UDim2.fromOffset(bw, 28), LayoutOrder = 1, TextSize = 11, Parent = advRow })
	local hitB = button("Hit ▶ F9", { Size = UDim2.fromOffset(bw, 28), LayoutOrder = 2, TextSize = 11, BackgroundColor3 = Color3.fromRGB(60, 40, 24), Parent = advRow })
	local doneB = button("✓ Done", { Size = UDim2.fromOffset(bw, 28), LayoutOrder = 3, TextSize = 11, BackgroundColor3 = Color3.fromRGB(28, 48, 32), Parent = advRow })
	local advHint = label("split startup / hit", { Size = UDim2.new(1, -bw * 3 - 18, 1, 0), LayoutOrder = 4, TextSize = 10, TextColor3 = THEME.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Parent = advRow })
	local function paintAdv()
		advToggle.Text = "Advanced: " .. (CONFIG.Advanced and "on" or "off")
		advToggle.TextColor3 = CONFIG.Advanced and THEME.Good or THEME.Sub
		local rec = Rec.state == "recording"
		hitB.TextColor3 = (rec and Rec.phase == "startup") and THEME.Hit or THEME.Sub
		doneB.TextColor3 = (rec and Rec.phase == "hit") and THEME.Good or THEME.Sub
		advHint.Text = not CONFIG.Advanced and "split startup / hit"
			or (rec and (Rec.phase == "startup" and "wind-up — press Hit when it connects" or "hit phase — press Done") or "Start = startup · Hit = hit · Done = save")
	end
	advToggle.Activated:Connect(guard(function()
		CONFIG.Advanced = not CONFIG.Advanced
		paintAdv()
		toast(CONFIG.Advanced and "advanced on — Start records startup, Hit switches to hit" or "advanced off")
	end))
	hitB.Activated:Connect(guard(function() startHitPhase() end))
	doneB.Activated:Connect(guard(function()
		if Rec.state == "recording" then stopRecording("manual") else toast("nothing recording") end
	end))
	paintAdv()

	UI.nameBox = make("TextBox", { Position = UDim2.fromOffset(0, 126), Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = THEME.Panel,
		PlaceholderText = "move name (optional)", PlaceholderColor3 = THEME.Sub, Text = "", TextColor3 = THEME.Text, Font = FONT, TextSize = 12,
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = page },
		{ corner(7), stroke(), make("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
	local chips = make("Frame", { Position = UDim2.fromOffset(0, 158), Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, Parent = page },
		{ make("UIGridLayout", { CellSize = UDim2.fromOffset(math.floor((W - 20 - 5 * 5) / 6), 22), CellPadding = UDim2.fromOffset(5, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local chipLabels = {}
	for i, c in CATS do
		local chip = make("Frame", { BackgroundColor3 = THEME.Panel, LayoutOrder = i, Parent = chips }, { corner(6) })
		make("Frame", { Size = UDim2.fromOffset(3, 14), Position = UDim2.new(0, 6, 0.5, -7), BackgroundColor3 = CAT_COLOR[c], BorderSizePixel = 0, Parent = chip }, { corner(2) })
		chipLabels[c] = label(c .. " 0", { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -16, 1, 0), TextSize = 10, TextColor3 = THEME.Sub, Parent = chip })
	end
	local victimsL = label("victims: —", { Position = UDim2.fromOffset(0, 238), Size = UDim2.new(1, 0, 0, 16), TextSize = 12, TextColor3 = THEME.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Parent = page })
	local feed = make("Frame", { Position = UDim2.fromOffset(0, 258), Size = UDim2.new(1, 0, 1, -292), BackgroundColor3 = THEME.Panel, ClipsDescendants = true, Parent = page },
		{ corner(8), stroke(), pad(8), vlist(2) })
	local feedLines = {}
	for i = 1, 10 do
		feedLines[i] = label("", { Size = UDim2.new(1, 0, 0, 14), TextSize = 11, Font = FONT_MONO, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = i, Parent = feed })
	end
	local feedBuf = {}
	local hist = make("Frame", { Position = UDim2.new(0, 0, 1, -28), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = page })
	local histL = label("no moves yet", { Position = UDim2.fromOffset(36, 0), Size = UDim2.new(1, -72, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 12, Parent = hist })
	button("‹", { Size = UDim2.fromOffset(30, 26), Parent = hist }, function() if Selected > 1 then Selected -= 1 if UI.refreshAll then UI.refreshAll() end end end)
	button("›", { Size = UDim2.fromOffset(30, 26), Position = UDim2.new(1, -30, 0, 0), Parent = hist }, function() if Selected < #History then Selected += 1 if UI.refreshAll then UI.refreshAll() end end end)

	local function richLine(ev)
		local c = CAT_COLOR[ev.cat] or THEME.Text
		local t = Rec.state == "recording" and (ev.t - Rec.t0) or ev.rt or 0
		local txt = string.gsub(string.gsub(string.gsub(ev.text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		return string.format('<font color="#8a90a5">%+6.2f</font> <font color="%s">%-6s</font> <font color="#c8ccd8">%s</font> %s', t, c3hex(c), ev.cat, ev.who, txt)
	end
	local counts = {}
	function UI.refreshRecord()
		local s = Rec.state
		if s == "recording" then
			local startup = Rec.phase == "startup"
			big.Text = string.format("%s %.2fs", startup and "● STARTUP" or "● REC", now() - Rec.t0)
			big.TextColor3 = startup and THEME.Armed or THEME.Rec
			statusDot.BackgroundColor3 = startup and THEME.Armed or THEME.Rec
			if pillStroke then pillStroke.Color = startup and THEME.Armed or THEME.Rec end
			sub.Text = startup and "wind-up only, no victims — press Hit (F9) when it connects"
				or string.format("%d events · stops after %ss idle · F6 / Stop to end", #Rec.events, fmtNum(CONFIG.IdleStop, 1))
		elseif s == "armed" then
			big.Text = "ARMED"
			big.TextColor3 = THEME.Armed
			statusDot.BackgroundColor3 = THEME.Armed
			if pillStroke then pillStroke.Color = THEME.Armed end
			sub.Text = CONFIG.Advanced and "will start the STARTUP phase on your next action animation"
				or (CONFIG.StartOnAnim and "do your move — recording starts on your next action animation" or "press Start / F6 to record")
		else
			big.Text = "IDLE"
			big.TextColor3 = THEME.Text
			statusDot.BackgroundColor3 = THEME.Sub
			if pillStroke then pillStroke.Color = THEME.Stroke end
			sub.Text = "Arm, then do a move — or Start / F6."
		end
		statusText.Text = s == "recording" and string.format("%s %.1fs", Rec.phase == "startup" and "startup" or "recording", now() - Rec.t0) or s
		paintAdv()
		table.clear(counts)
		local src = s == "recording" and Rec.events or (History[Selected] and History[Selected].events) or {}
		for _, ev in src do counts[ev.cat] = (counts[ev.cat] or 0) + 1 end
		for _, c in CATS do
			chipLabels[c].Text = string.format("%s %d", c, counts[c] or 0)
			chipLabels[c].TextColor3 = (counts[c] or 0) > 0 and THEME.Text or THEME.Sub
		end
		local vnames = {}
		if s == "recording" and not Rec.noVictims then
			for _, v in Rec.victims do table.insert(vnames, v.name) end
		elseif History[Selected] then
			vnames = History[Selected].victims
		end
		victimsL.Text = "victims: " .. (#vnames > 0 and table.concat(vnames, ", ") or "—")
		local rec = History[Selected]
		histL.Text = rec and string.format("#%d of %d · %s · %ss · %d events", Selected, #History, rec.name, fmtNum(rec.duration, 2), #rec.events) or "no moves yet"
	end
	function UI.feed(ev)
		table.insert(feedBuf, ev)
		while #feedBuf > #feedLines do table.remove(feedBuf, 1) end
		for i, l in feedLines do
			local e = feedBuf[i]
			l.Text = e and richLine(e) or ""
		end
	end
	function UI.feedFromRec(rec)
		table.clear(feedBuf)
		local n = rec and #rec.events or 0
		for i = math.max(1, n - #feedLines + 1), n do table.insert(feedBuf, rec.events[i]) end
		for i, l in feedLines do
			local e = feedBuf[i]
			l.Text = e and richLine(e) or ""
		end
	end
end)

---------------------------------------------------------------------------------------------------
-- Moves page
---------------------------------------------------------------------------------------------------
local fmtKey = "moveTable"
local previewBox, previewHead
local moveRows = {}
local PAGE = 60000
local pageIndex, fullText = 1, ""

local function showPreviewPage()
	local total = math.max(1, math.ceil(#fullText / PAGE))
	pageIndex = math.clamp(pageIndex, 1, total)
	local a = (pageIndex - 1) * PAGE + 1
	if previewBox then previewBox.Text = string.sub(fullText, a, a + PAGE - 1) end
	if previewHead then previewHead.Text = string.format("%s · page %d/%d · %d chars", fmtKey, pageIndex, total, #fullText) end
end
local function renderMove(rec, fmt)
	local ok, s = pcall(Out[fmt] or Out.moveTable, rec)
	fullText = ok and s or ("Output failed: " .. tostring(s))
	pageIndex = 1
	showPreviewPage()
end
local function copyMove(rec, fmt, quiet)
	local ok, s = pcall(Out[fmt] or Out.moveTable, rec)
	if not ok then
		toast("failed: " .. tostring(s))
		return
	end
	copyText(s, string.format("%s of move #%d", fmt, rec.index), quiet and nil or previewBox)
end

section("moves page", function()
	local page = pages.Moves
	local head = make("Frame", { Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = page }, { hlist(5) })
	label("moves", { Size = UDim2.fromOffset(44, 26), TextSize = 12, TextColor3 = THEME.Sub, LayoutOrder = 1, Parent = head })
	local search = make("TextBox", { Size = UDim2.new(1, -160, 0, 26), BackgroundColor3 = THEME.Panel, PlaceholderText = "filter by name / victim",
		PlaceholderColor3 = THEME.Sub, Text = "", TextColor3 = THEME.Text, Font = FONT, TextSize = 12, ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = 2, Parent = head }, { corner(7), stroke(), make("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
	button("Copy all blocks", { Size = UDim2.fromOffset(105, 26), TextSize = 11, LayoutOrder = 3, Parent = head }, function()
		if #History == 0 then return toast("nothing to copy") end
		local parts = {}
		for _, rec in History do
			table.insert(parts, string.format("-- ==================== MOVE #%d · %s ====================", rec.index, rec.name))
			local ok, s = pcall(Out.moveTable, rec)
			table.insert(parts, ok and s or ("-- failed: " .. tostring(s)))
			table.insert(parts, "")
		end
		copyText(table.concat(parts, "\n"), "all move blocks", previewBox)
	end)

	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -242), BackgroundColor3 = THEME.Panel,
		ScrollBarThickness = 4, ScrollBarImageColor3 = THEME.Stroke, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		BorderSizePixel = 0, Parent = page }, { corner(8), pad(6), vlist(5) })

	local prevWrap = make("Frame", { Position = UDim2.new(0, 0, 1, -172), Size = UDim2.new(1, 0, 0, 172), BackgroundTransparency = 1, Parent = page })
	local prevBar = make("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = prevWrap }, { hlist(4) })
	previewHead = label("pick a block", { Size = UDim2.new(1, -140, 0, 24), TextSize = 11, TextColor3 = THEME.Sub, LayoutOrder = 1, Parent = prevBar })
	button("‹", { Size = UDim2.fromOffset(26, 24), LayoutOrder = 2, Parent = prevBar }, function() pageIndex -= 1 showPreviewPage() end)
	button("›", { Size = UDim2.fromOffset(26, 24), LayoutOrder = 3, Parent = prevBar }, function() pageIndex += 1 showPreviewPage() end)
	button("Copy", { Size = UDim2.fromOffset(50, 24), BackgroundColor3 = THEME.Accent, LayoutOrder = 4, Parent = prevBar }, function()
		local rec = History[Selected]
		if rec then copyMove(rec, fmtKey) end
	end)
	local previewScroller = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28), BackgroundColor3 = THEME.Panel,
		ScrollBarThickness = 5, ScrollBarImageColor3 = THEME.Stroke, AutomaticCanvasSize = Enum.AutomaticSize.XY, CanvasSize = UDim2.new(),
		BorderSizePixel = 0, Parent = prevWrap }, { corner(8), stroke() })
	previewBox = make("TextBox", { Size = UDim2.new(1, -12, 0, 0), Position = UDim2.fromOffset(6, 6), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, Text = "", TextColor3 = THEME.Text, Font = FONT_MONO, TextSize = 12, MultiLine = true, ClearTextOnFocus = false,
		TextEditable = true, TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = previewScroller })

	local function matchesFilter(rec, q)
		if q == "" then return true end
		q = string.lower(q)
		if string.find(string.lower(rec.name), q, 1, true) then return true end
		for _, v in rec.victims do if string.find(string.lower(v), q, 1, true) then return true end end
		return false
	end
	local function refreshMoves()
		for _, row in moveRows do row:Destroy() end
		table.clear(moveRows)
		tabButtons.Moves.Text = string.format("Moves (%d)", #History)
		local q = search.Text
		local shown = 0
		for i = #History, 1, -1 do
			local rec = History[i]
			if matchesFilter(rec, q) then
				shown += 1
				local isSel = i == Selected
				local card = make("Frame", { Size = UDim2.new(1, 0, 0, 54), BackgroundColor3 = isSel and THEME.Panel2 or THEME.Panel,
					LayoutOrder = shown, Parent = list }, { corner(7), stroke(isSel and THEME.Accent or THEME.Stroke) })
				label(string.format("#%d  %s%s", rec.index, rec.name, rec.startupDuration and "  [startup+hit]" or ""),
					{ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 18), TextSize = 12, Font = FONT_B, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
				label(string.format("%ss%s · %d events · %d victim(s) · %s", fmtNum(rec.duration, 2),
					rec.startupDuration and string.format(" (startup %ss)", fmtNum(rec.startupDuration, 2)) or "", #rec.events, #rec.victims, rec.when),
					{ Position = UDim2.fromOffset(8, 22), Size = UDim2.new(1, -16, 0, 14), TextSize = 10, TextColor3 = THEME.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
				local btns = make("Frame", { Position = UDim2.fromOffset(8, 36), Size = UDim2.new(1, -16, 0, 15), BackgroundTransparency = 1, Parent = card }, { hlist(4) })
				local order = 0
				for _, f in { { "Table", "moveTable" }, { "Replay", "replay" }, { "Summary", "summary" }, { "Timeline", "timeline" }, { "JSON", "json" } } do
					order += 1
					button(f[1], { Size = UDim2.fromOffset(52, 15), TextSize = 9, LayoutOrder = order, Parent = btns }, function()
						Selected = i
						renderMove(rec, f[2])
						refreshMoves()
					end)
				end
				order += 1
				button("copy ▸", { Size = UDim2.fromOffset(56, 15), TextSize = 9, BackgroundColor3 = THEME.Accent, LayoutOrder = order, Parent = btns }, function()
					copyMove(rec, fmtKey)
				end)
				table.insert(moveRows, card)
			end
		end
		if shown == 0 then
			table.insert(moveRows, label(#History == 0 and "no moves yet — record one on the Record tab" or "nothing matches that filter", {
				Size = UDim2.new(1, 0, 0, 40), TextSize = 12, TextColor3 = THEME.Sub, TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center, LayoutOrder = 1, Parent = list }))
		end
		local rec = History[Selected]
		if rec then
			previewHead.Text = string.format("#%d %s · %s", rec.index, rec.name, fmtKey)
			renderMove(rec, fmtKey)
		else
			previewHead.Text = "pick a block"
			fullText = "No move blocks yet.\n\nRecord tab → Arm, then do a move. Every recording lands here as its own copyable block."
			pageIndex = 1
			showPreviewPage()
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(guard(refreshMoves))
	UI.refreshMoves = refreshMoves
end)

---------------------------------------------------------------------------------------------------
-- Timeline page
---------------------------------------------------------------------------------------------------
section("timeline page", function()
	local page = pages.Timeline
	local filters = make("Frame", { Size = UDim2.new(1, 0, 0, 76), BackgroundTransparency = 1, Parent = page },
		{ make("UIGridLayout", { CellSize = UDim2.fromOffset(math.floor((W - 20 - 5 * 6) / 7), 20), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local opts = { victimOnly = false, youOnly = false, search = "" }
	local rebuild
	for i, c in CATS do
		local b = button(c, { LayoutOrder = i, TextSize = 9, Parent = filters })
		local function paint()
			b.BackgroundColor3 = CAT_SHOW[c] and CAT_COLOR[c]:Lerp(THEME.Panel2, 0.55) or THEME.Panel
			b.TextColor3 = CAT_SHOW[c] and THEME.Text or THEME.Sub
		end
		paint()
		b.Activated:Connect(function() CAT_SHOW[c] = not CAT_SHOW[c] paint() rebuild() end)
	end
	local vb = button("victim only", { LayoutOrder = 30, TextSize = 9, Parent = filters })
	vb.Activated:Connect(function()
		opts.victimOnly = not opts.victimOnly
		opts.youOnly = false
		vb.BackgroundColor3 = opts.victimOnly and THEME.Accent or THEME.Panel2
		rebuild()
	end)
	local yb = button("you only", { LayoutOrder = 31, TextSize = 9, Parent = filters })
	yb.Activated:Connect(function()
		opts.youOnly = not opts.youOnly
		opts.victimOnly = false
		yb.BackgroundColor3 = opts.youOnly and THEME.Accent or THEME.Panel2
		vb.BackgroundColor3 = THEME.Panel2
		rebuild()
	end)
	local search = make("TextBox", { Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = THEME.Panel,
		PlaceholderText = "search (id, name, remote …)", PlaceholderColor3 = THEME.Sub, Text = "", TextColor3 = THEME.Text, Font = FONT, TextSize = 12,
		ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = page }, { corner(7), stroke(), make("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
	local list = make("ScrollingFrame", { Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 1, -196), BackgroundColor3 = THEME.Panel,
		ScrollBarThickness = 4, ScrollBarImageColor3 = THEME.Stroke, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		BorderSizePixel = 0, Parent = page }, { corner(8), pad(6), vlist(1) })
	local detail = make("TextBox", { Position = UDim2.new(0, 0, 1, -78), Size = UDim2.new(1, 0, 0, 78), BackgroundColor3 = THEME.Panel,
		Text = "tap an event for its details", TextColor3 = THEME.Sub, Font = FONT_MONO, TextSize = 11, TextWrapped = true, MultiLine = true,
		ClearTextOnFocus = false, TextEditable = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = page },
		{ corner(8), stroke(), pad(6) })
	local rows = {}
	rebuild = function()
		for _, rw in rows do rw:Destroy() end
		table.clear(rows)
		local rec = History[Selected]
		if not rec then return end
		opts.search = search.Text
		local evs = evFilter(rec, opts)
		local cap = math.min(#evs, 600)
		local dividerShown = not rec.startupDuration
		local n = 0
		for i = 1, cap do
			local ev = evs[i]
			if not dividerShown and ev.rt >= rec.startupDuration then
				dividerShown = true
				n += 1
				table.insert(rows, label("──────── HIT ────────", { Size = UDim2.new(1, 0, 0, 16), TextSize = 10, TextColor3 = THEME.Hit,
					TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = n, Parent = list }))
			end
			n += 1
			local rw = make("TextButton", { Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, AutoButtonColor = false, Text = "", LayoutOrder = n, Parent = list })
			make("Frame", { Size = UDim2.fromOffset(3, 12), Position = UDim2.new(0, 0, 0.5, -6), BackgroundColor3 = CAT_COLOR[ev.cat], BorderSizePixel = 0, Parent = rw }, { corner(2) })
			local txt = string.gsub(string.gsub(string.gsub(ev.text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
			label(string.format('<font color="#8a90a5">%+7.3f</font>  <font color="%s">%s</font>  <font color="%s">%s</font>  %s%s', ev.rt, c3hex(CAT_COLOR[ev.cat]), ev.cat,
				ev.victim and "#ff8fa3" or "#c8ccd8", ev.who, txt, ev.phase == "startup" and '  <font color="#ffbe46">[startup]</font>' or ""),
				{ Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -8, 1, 0), Font = FONT_MONO, TextSize = 11, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, Parent = rw })
			rw.Activated:Connect(guard(function()
				detail.TextColor3 = THEME.Text
				detail.Text = string.format("%+.3fs  %s  %s%s%s\n%s\n\n%s", ev.rt, ev.cat, ev.who, ev.victim and " (victim)" or "",
					ev.phase and (" [" .. ev.phase .. "]") or "", ev.text, ser(ev.data))
			end))
			table.insert(rows, rw)
		end
		if #evs > cap then
			table.insert(rows, label(string.format("… %d more (narrow the filters)", #evs - cap), { Size = UDim2.new(1, 0, 0, 18),
				TextSize = 11, TextColor3 = THEME.Sub, LayoutOrder = n + 1, Parent = list }))
		end
	end
	search.FocusLost:Connect(guard(rebuild))
	UI.refreshTimeline = rebuild
end)

---------------------------------------------------------------------------------------------------
-- Settings page
---------------------------------------------------------------------------------------------------
section("settings page", function()
	local page = pages.Settings
	local list = make("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScrollBarThickness = 4,
		ScrollBarImageColor3 = THEME.Stroke, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = page },
		{ vlist(6), make("UIPadding", { PaddingRight = UDim.new(0, 8) }) })
	local order = 0
	local function row(text, hint)
		order += 1
		local f = make("Frame", { Size = UDim2.new(1, 0, 0, hint and 40 or 30), BackgroundColor3 = THEME.Panel, LayoutOrder = order, Parent = list }, { corner(7) })
		label(text, { Position = UDim2.fromOffset(10, hint and 3 or 0), Size = UDim2.new(1, -150, 0, hint and 20 or 30), TextSize = 12, Parent = f })
		if hint then label(hint, { Position = UDim2.fromOffset(10, 21), Size = UDim2.new(1, -150, 0, 16), TextSize = 10, TextColor3 = THEME.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f }) end
		return f
	end
	local function toggle(key, text, hint, onChange)
		local f = row(text, hint)
		local sw = make("TextButton", { Size = UDim2.fromOffset(44, 22), Position = UDim2.new(1, -54, 0.5, -11), BackgroundColor3 = THEME.Panel2, Text = "", AutoButtonColor = false, Parent = f }, { corner(11) })
		local knob = make("Frame", { Size = UDim2.fromOffset(18, 18), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sw }, { corner(9) })
		local function paint(anim)
			local on = CONFIG[key]
			local goal = { Position = on and UDim2.fromOffset(24, 2) or UDim2.fromOffset(2, 2) }
			if anim then TweenService:Create(knob, TweenInfo.new(0.15), goal):Play() else knob.Position = goal.Position end
			sw.BackgroundColor3 = on and THEME.Accent or THEME.Panel2
		end
		paint(false)
		sw.Activated:Connect(guard(function()
			CONFIG[key] = not CONFIG[key]
			paint(true)
			if onChange then onChange() end
		end))
	end
	local function number(key, text, step, minv, maxv, hint)
		local f = row(text, hint)
		local val = label(fmtNum(CONFIG[key], 2), { Size = UDim2.fromOffset(50, 22), Position = UDim2.new(1, -92, 0.5, -11), TextXAlignment = Enum.TextXAlignment.Center, Parent = f })
		local function set(v)
			CONFIG[key] = math.clamp(r(v, 3), minv, maxv)
			val.Text = fmtNum(CONFIG[key], 2)
		end
		button("−", { Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -120, 0.5, -11), Parent = f }, function() set(CONFIG[key] - step) end)
		button("+", { Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -38, 0.5, -11), Parent = f }, function() set(CONFIG[key] + step) end)
	end
	local function textField(key, title, hint, onSet)
		order += 1
		local f = make("Frame", { Size = UDim2.new(1, 0, 0, 58), BackgroundColor3 = THEME.Panel, LayoutOrder = order, Parent = list }, { corner(7) })
		label(title, { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(1, -20, 0, 18), TextSize = 12, Parent = f })
		local tb = make("TextBox", { Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -16, 0, 26), BackgroundColor3 = THEME.Panel2, Text = CONFIG[key],
			PlaceholderText = hint, PlaceholderColor3 = THEME.Sub, TextColor3 = THEME.Text, Font = FONT, TextSize = 11, ClearTextOnFocus = false,
			TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = f }, { corner(6), make("UIPadding", { PaddingLeft = UDim.new(0, 6) }) })
		tb.FocusLost:Connect(function()
			CONFIG[key] = tb.Text
			if onSet then onSet(tb.Text) end
		end)
	end
	toggle("Advanced", "Advanced recording", "startup phase, then hit phase, then Done", function() if UI.refreshRecord then UI.refreshRecord() end end)
	toggle("StartOnAnim", "Start on your next action animation", "when armed")
	toggle("StartOnRemote", "Start on a server event about you", "when armed")
	toggle("AutoArm", "Re-arm after each recording")
	toggle("TrackOthers", "Log everyone within the radius", "off: only you + people you hit")
	toggle("IgnoreCoreAnims", "Ignore walk / idle / run / jump")
	toggle("CloneEffects", "Clone effects", "ReplicatedStorage.MoveLogger_Logged")
	toggle("TrackTerrain", "Track Terrain effect children", "terrain attachments / emitters")
	toggle("TrackMotion", "Track effect motion")
	toggle("TrackTags", "Track tags", "CollectionService tags on characters + children")
	toggle("TrackAttributes", "Track attributes", "character / humanoid / child attributes")
	toggle("TrackDummies", "Track dummies", "log HP on training targets")
	toggle("TrackVelocity", "Track velocity", "continuous track for you + victims")
	toggle("TrackHitboxTouches", "Log hitbox Touched events", "names who was touched and where")
	toggle("ReplicationSpy", "Spy replication remotes", "bypasses the ignore list")
	toggle("LogRemotes", "Log server → you remotes")
	toggle("LogCamera", "Log camera (FOV, shake)")
	toggle("LogScreen", "Log screen effects / overlays")
	toggle("Debug", "Print handler errors", "warn() on caught errors")
	number("Radius", "Radius (studs)", 10, 10, 2000)
	number("VictimRadius", "Victim proximity radius", 5, 5, 300)
	number("Preroll", "Pre-roll (s)", 0.1, 0, 3)
	number("IdleStop", "Auto-stop after idle (s)", 0.25, 0.25, 15)
	number("MaxLength", "Max length (s)", 5, 2, 300)
	number("VelocitySpike", "Velocity jump threshold", 5, 5, 500)
	number("ShakeThreshold", "Shake threshold (°)", 0.05, 0.05, 5)
	number("MaxClones", "Max effect clones per recording", 10, 10, 600)
	textField("RemoteIgnore", "Ignore remotes containing", "comma separated", function(s) remoteIgnore = splitList(s) end)
	textField("SoundIgnore", "Ignore sounds containing", "comma separated", function(s) soundIgnore = splitList(s) end)
	order += 1
	label("F6 start/stop · F7 arm · F8 show/hide · F9 hit phase.\nNot visible to a LocalScript: the server's own spatial queries (see inferred hitboxes), PlayLocalSound, :Emit() on emitters that already existed, FireServer calls.", {
		Size = UDim2.new(1, 0, 0, 52), TextWrapped = true, TextSize = 11, TextColor3 = THEME.Sub, TextYAlignment = Enum.TextYAlignment.Top, LayoutOrder = order, Parent = list })
end)

---------------------------------------------------------------------------------------------------
-- wiring
---------------------------------------------------------------------------------------------------
function UI.refreshAll()
	UI.refreshRecord()
	UI.feedFromRec(History[Selected])
	if pages.Moves.Visible and UI.refreshMoves then UI.refreshMoves() end
	if pages.Timeline.Visible and UI.refreshTimeline then UI.refreshTimeline() end
end
UI.onTab = function(name)
	if name == "Moves" and UI.refreshMoves then UI.refreshMoves()
	elseif name == "Timeline" and UI.refreshTimeline then UI.refreshTimeline()
	elseif name == "Record" and UI.refreshRecord then UI.refreshRecord() end
end
Hooks.onEvent = function(ev) if UI.feed then UI.feed(ev) end end
Hooks.onState = function() if UI.refreshRecord then UI.refreshRecord() end end
Hooks.onFinish = function()
	UI.refreshAll()
	if window.Visible and not minimized then showTab("Moves") end
	toast(string.format("move #%d saved as its own block", Selected))
end

ownGui.Parent = PlayerGui
showTab("Record")

section("wiring", function()
	cn(UserInputService.InputBegan:Connect(guard(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.F6 then
			if Rec.state == "recording" then stopRecording("manual") else startRecording("manual") end
		elseif input.KeyCode == Enum.KeyCode.F7 then
			if Rec.state == "armed" then setState("idle") else arm() end
		elseif input.KeyCode == Enum.KeyCode.F8 then
			toggleWindow()
		elseif input.KeyCode == Enum.KeyCode.F9 then
			startHitPhase()
		end
	end)))

	cn(workspace.DescendantAdded:Connect(guard(onWorkspaceDescendant)))
	cn(SoundService.DescendantAdded:Connect(guard(function(d) if d:IsA("Sound") then hookSound(d) end end)))
	cn(PlayerGui.DescendantAdded:Connect(guard(function(d)
		if d:IsA("Sound") then hookSound(d) return end
		onGuiDescendant(d)
	end)))
	cn(Lighting.ChildAdded:Connect(guard(onScreenEffect)))
	cn(workspace.Terrain.ChildAdded:Connect(guard(function(c)
		if Rec.state == "idle" or not CONFIG.TrackTerrain then return end
		if c:IsA("Attachment") or c:IsA("ParticleEmitter") or c:IsA("Trail") or c:IsA("Beam") or hasVisualDescendant(c) then
			task.defer(guard(processRoot), c, now())
		end
	end)))

	local function hookCamera(c)
		if not c then return end
		cn(c.ChildAdded:Connect(guard(onScreenEffect)))
		cn(c:GetPropertyChangedSignal("CameraType"):Connect(guard(function()
			if Rec.state ~= "idle" and CONFIG.LogCamera then log("CAMERA", nil, "camera type → " .. c.CameraType.Name, { kind = "type", to = c.CameraType.Name }) end
		end)))
	end
	hookCamera(workspace.CurrentCamera)
	cn(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(guard(function() hookCamera(workspace.CurrentCamera) end)))

	local function hookRemoteTree(root)
		for _, d in root:GetDescendants() do
			if d:IsA("RemoteEvent") or d.ClassName == "UnreliableRemoteEvent" then hookRemote(d) end
		end
		cn(root.DescendantAdded:Connect(guard(function(d)
			if d:IsA("RemoteEvent") or d.ClassName == "UnreliableRemoteEvent" then hookRemote(d) end
		end)))
	end
	task.spawn(guard(function() pcall(hookRemoteTree, ReplicatedStorage) end))
	task.spawn(guard(function() pcall(hookRemoteTree, workspace) end))

	cn(LocalPlayer.CharacterAdded:Connect(guard(function(c) task.defer(guard(trackCharacter), c) end)))
	if LocalPlayer.Character then task.defer(guard(trackCharacter), LocalPlayer.Character) end
	for _, p in Players:GetPlayers() do
		if p ~= LocalPlayer then cn(p.CharacterAdded:Connect(guard(function(c) task.defer(guard(trackCharacter), c) end))) end
	end
	cn(Players.PlayerAdded:Connect(guard(function(p) cn(p.CharacterAdded:Connect(guard(function(c) task.defer(guard(trackCharacter), c) end))) end)))

	cn(RunService.Heartbeat:Connect(guard(heartbeat)))
	pcall(function() RunService:UnbindFromRenderStep("MoveLoggerCam2") end)
	RunService:BindToRenderStep("MoveLoggerCam2", Enum.RenderPriority.Camera.Value + 1, guard(cameraStep))

	task.spawn(guard(function()
		while GENV.__MoveLogger == Self do
			task.wait(0.25)
			if Rec.state == "recording" then UI.refreshRecord() end
		end
	end))

	task.spawn(guard(function()
		pcall(function()
			for _, p in Players:GetPlayers() do
				if p.Character then trackCharacter(p.Character) end
			end
		end)
	end))
end)

print("[MoveLogger] loaded v2.4 — F8 to toggle, F7 to arm")