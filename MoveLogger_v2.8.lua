--[[ MoveLogger v2.8 — move recorder for battlegrounds games. F6 start/stop, F7 arm, F8 hide, F9 hit phase. ]]

local P = game:GetService("Players")
local RS = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local TS = game:GetService("TweenService")
local HS = game:GetService("HttpService")
local LIGHT = game:GetService("Lighting")
local SND = game:GetService("SoundService")
local REP = game:GetService("ReplicatedStorage")
local KSP = game:GetService("KeyframeSequenceProvider")
local LP = P.LocalPlayer
local PG = LP:WaitForChild("PlayerGui")

local GENV = (typeof(getgenv) == "function" and getgenv()) or _G
if GENV.__MoveLogger then pcall(GENV.__MoveLogger.destroy) end
local Self = {}
GENV.__MoveLogger = Self
local Bag, ownGui, LoggedRoot = {}
local function cn(c) Bag[#Bag + 1] = c return c end
function Self.destroy()
	for _, c in Bag do pcall(function() c:Disconnect() end) end
	table.clear(Bag)
	local hk = Self.hk
	if hk then hk.on = false if hk.restore then hk.restore() end end
	pcall(function() RS:UnbindFromRenderStep("MLCam2") end)
	if ownGui then pcall(function() ownGui:Destroy() end) end
	GENV.__MoveLogger = nil
end
local function sec(n, f)
	local ok, e = pcall(f)
	if not ok then warn("[ML] " .. n .. ": " .. tostring(e)) end
end

local C = {
	Radius = 150, VRadius = 45, Preroll = 0.4, IdleStop = 2, MaxLen = 30, MinLen = 0.3, AutoArm = true,
	StartOnAnim = true, StartOnRemote = false, IgnoreCore = true, Others = true, Vel = true, Touches = true,
	Clone = true, Terrain = true, Motion = true, Tags = true, Attrs = true, Dummies = true, RepSpy = true,
	Remotes = true, Cam = true, Screen = true, Adv = false, Debug = false, MaxClones = 200, StartOnFx = true, Hooks = true, Templates = true,
	RIgnore = "Chat,Message,Mute,Channel,Ping,Leaderboard,Cosmetic,Title,Notif,Mouse,Aim,Position,Cframe",
	SIgnore = "Running,Jumping,FreeFall,Landing,Swimming,Climbing,GettingUp,Died,Splash,Music,Theme,Ambience",
	Spike = 12, Phase = 4, Shake = 0.35, MaxEv = 8000, HitPreroll = 4,
}
local CATS = { "ANIM", "MARKER", "VELOCITY", "SOUND", "VFX", "EFFECT", "TWEEN", "HITBOX", "MOVE", "HIT", "STATE", "CAMERA", "SCREEN", "REMOTE", "REPLICATION" }
local CC = {
	ANIM = Color3.fromRGB(120, 160, 255), MARKER = Color3.fromRGB(170, 140, 255), VELOCITY = Color3.fromRGB(90, 230, 220),
	SOUND = Color3.fromRGB(90, 210, 160), VFX = Color3.fromRGB(255, 170, 70), HITBOX = Color3.fromRGB(255, 80, 90),
	MOVE = Color3.fromRGB(80, 200, 255), HIT = Color3.fromRGB(255, 110, 140), STATE = Color3.fromRGB(220, 220, 120),
	CAMERA = Color3.fromRGB(150, 220, 255), SCREEN = Color3.fromRGB(240, 140, 220), REMOTE = Color3.fromRGB(170, 175, 190),
	REPLICATION = Color3.fromRGB(130, 200, 200), EFFECT = Color3.fromRGB(255, 120, 200), TWEEN = Color3.fromRGB(200, 170, 110),
}
local SHOW = {}
for _, c in CATS do SHOW[c] = true end
local T = {
	Bg = Color3.fromRGB(14, 15, 20), Pan = Color3.fromRGB(22, 24, 31), Pan2 = Color3.fromRGB(30, 33, 42),
	Stroke = Color3.fromRGB(48, 52, 66), Text = Color3.fromRGB(232, 235, 242), Sub = Color3.fromRGB(140, 146, 165),
	Acc = Color3.fromRGB(118, 136, 255), Rec = Color3.fromRGB(255, 72, 88), Arm = Color3.fromRGB(255, 190, 70),
	Good = Color3.fromRGB(110, 220, 150), Hit = Color3.fromRGB(255, 140, 70),
}

---------------------------------------------------------------------------------------------------
local function now() return os.clock() end
local function rd(n, d)
	n = tonumber(n) or 0
	if n ~= n or n == math.huge or n == -math.huge then return n == n and n or 0 end
	local m = 10 ^ (d or 2)
	return math.round(n * m) / m
end
local function fn(n, d)
	n = tonumber(n) or 0
	if n ~= n then return "0" end
	if n == math.huge then return "math.huge" end
	if n == -math.huge then return "-math.huge" end
	local s = string.format("%." .. tostring(d or 2) .. "f", n)
	s = string.gsub(s, "%.?0+$", "")
	if s == "-0" or s == "" then s = "0" end
	return s
end
local function v3s(v) return "(" .. fn(v.X) .. ", " .. fn(v.Y) .. ", " .. fn(v.Z) .. ")" end
local function v3l(v) return "Vector3.new(" .. fn(v.X) .. ", " .. fn(v.Y) .. ", " .. fn(v.Z) .. ")" end
local function cfl(cf)
	local p, rx, ry, rz = cf.Position, cf:ToOrientation()
	local b = "CFrame.new(" .. fn(p.X) .. ", " .. fn(p.Y) .. ", " .. fn(p.Z) .. ")"
	if math.abs(rx) + math.abs(ry) + math.abs(rz) < 1e-3 then return b end
	return b .. " * CFrame.fromOrientation(math.rad(" .. fn(math.deg(rx), 1) .. "), math.rad(" .. fn(math.deg(ry), 1) .. "), math.rad(" .. fn(math.deg(rz), 1) .. "))"
end
local function hex(c) return string.format("#%02X%02X%02X", math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255)) end
local function rgb(c) return { math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255) } end
local function aid(s) return s and string.match(tostring(s), "%d%d%d%d+") or nil end
local function lst(s)
	local t = {}
	for p in string.gmatch(s or "", "[^,]+") do
		p = string.lower((string.gsub(p, "^%s+", ""):gsub("%s+$", "")))
		if p ~= "" then t[#t + 1] = p end
	end
	return t
end
local function any(n, l)
	n = string.lower(tostring(n))
	for _, p in l do if string.find(n, p, 1, true) then return true end end
	return false
end
local function sp(i, d)
	if not i then return "nil" end
	local o, n, k = {}, i, d or 4
	while n and n ~= game and k > 0 do
		table.insert(o, 1, n.Name)
		n, k = n.Parent, k - 1
	end
	if n and n ~= game then table.insert(o, 1, "…") end
	return table.concat(o, ".")
end
local function qs(s) return string.format("%q", tostring(s)) end
local function sf(f, ...)
	local ok, a = pcall(f, ...)
	if ok then return a end
end
local function gp(i, p) return sf(function() return i[p] end) end
local function g(f)
	return function(...)
		local ok, e = pcall(f, ...)
		if not ok and C.Debug then warn("[ML] " .. tostring(e)) end
	end
end
local function chOf(i)
	local n = i
	while n and n ~= workspace and n ~= game do
		if n:IsA("Model") and n:FindFirstChildOfClass("Humanoid") then return n end
		n = n.Parent
	end
end
local function rootOf(m)
	if not m then return nil end
	return m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChild("Torso")
end
local function me() return LP.Character end
local function myRoot() return rootOf(LP.Character) end
local function posOf(i)
	if not i then return nil end
	if i:IsA("BasePart") then return i.Position end
	if i:IsA("Attachment") then return gp(i, "WorldPosition") end
	if i:IsA("Model") then
		local cf = sf(function() return i:GetPivot() end)
		return cf and cf.Position
	end
	local p = i.Parent
	if p and p ~= workspace and p ~= game then return posOf(p) end
end
local function cfOf(i)
	if i:IsA("BasePart") then return i.CFrame end
	if i:IsA("Attachment") then return gp(i, "WorldCFrame") end
	if i:IsA("Model") then return sf(function() return i:GetPivot() end) end
end
local function l2(cf)
	local r = myRoot()
	if r and cf then return r.CFrame:ToObjectSpace(cf) end
end
local function ldir(v)
	local r = myRoot()
	return r and r.CFrame:VectorToObjectSpace(v) or v
end
local function dw(v)
	local o = {}
	if math.abs(v.Z) >= 0.5 then o[#o + 1] = (v.Z < 0 and "fwd " or "back ") .. fn(math.abs(v.Z), 1) end
	if math.abs(v.Y) >= 0.5 then o[#o + 1] = (v.Y > 0 and "up " or "down ") .. fn(math.abs(v.Y), 1) end
	if math.abs(v.X) >= 0.5 then o[#o + 1] = (v.X > 0 and "right " or "left ") .. fn(math.abs(v.X), 1) end
	return #o > 0 and table.concat(o, ", ") or "0"
end
local function seqD(s)
	if s == nil then return nil end
	local t = typeof(s)
	if t == "NumberSequence" then
		local o = {}
		for _, k in s.Keypoints do o[#o + 1] = { time = rd(k.Time, 4), value = rd(k.Value, 4), envelope = rd(k.Envelope, 4) } end
		return { kind = "number", keypoints = o }
	elseif t == "ColorSequence" then
		local o = {}
		for _, k in s.Keypoints do o[#o + 1] = { time = rd(k.Time, 4), color = hex(k.Value), rgb = rgb(k.Value) } end
		return { kind = "color", keypoints = o }
	elseif t == "NumberRange" then
		return { kind = "range", min = rd(s.Min, 4), max = rd(s.Max, 4) }
	end
	return tostring(s)
end
local function seqT(d)
	if type(d) ~= "table" then return tostring(d) end
	if d.kind == "range" then return fn(d.min, 3) .. "–" .. fn(d.max, 3) end
	if d.kind == "color3" then return tostring(d.hex) end
	if d.kind == "enum" then return tostring(d.value) end
	local o = {}
	for _, k in d.keypoints or {} do
		o[#o + 1] = fn(k.time, 2) .. ":" .. tostring(k.value or k.color)
	end
	return table.concat(o, " → ")
end
local function seqS(s)
	if s == nil then return "?" end
	local t = typeof(s)
	if t == "NumberRange" then return fn(s.Min, 3) .. "–" .. fn(s.Max, 3) end
	if t == "ColorSequence" then
		local o = {}
		for _, k in s.Keypoints do o[#o + 1] = fn(k.Time, 2) .. ":" .. hex(k.Value) end
		return table.concat(o, " → ")
	end
	if t == "NumberSequence" then
		local o = {}
		for _, k in s.Keypoints do o[#o + 1] = fn(k.Time, 2) .. ":" .. fn(k.Value, 3) end
		return table.concat(o, " → ")
	end
	return tostring(s)
end
local function ser(v, d, seen)
	d = d or 0
	local t = typeof(v)
	if t == "nil" then return "nil"
	elseif t == "boolean" then return tostring(v)
	elseif t == "number" then return fn(v, 3)
	elseif t == "string" then
		return #v > 90 and (string.format("%q", string.sub(v, 1, 90)) .. "…") or string.format("%q", v)
	elseif t == "Vector3" then return "V3" .. v3s(v)
	elseif t == "CFrame" then
		local l = l2(v)
		return "CF" .. v3s(v.Position) .. (l and (" [you→" .. v3s(l.Position) .. "]") or "")
	elseif t == "Color3" then return hex(v)
	elseif t == "NumberSequence" or t == "ColorSequence" or t == "NumberRange" then return "[" .. seqS(v) .. "]"
	elseif t == "EnumItem" then return tostring(v)
	elseif t == "buffer" then
		local n = buffer.len(v)
		return "buffer[" .. n .. "]" .. (n >= 4 and ("<u32 " .. buffer.readu32(v, 0) .. ">") or "")
	elseif t == "UDim2" then return string.format("UDim2(%s,%s,%s,%s)", fn(v.X.Scale, 3), fn(v.X.Offset), fn(v.Y.Scale, 3), fn(v.Y.Offset))
	elseif t == "Instance" then
		return chOf(v) == me() and ("<YOU" .. (v ~= chOf(v) and ("." .. v.Name) or "") .. ">") or ("<" .. v.ClassName .. " " .. sp(v, 3) .. ">")
	elseif t == "table" then
		seen = seen or {}
		if seen[v] then return "<cycle>" end
		if d >= 3 then return "{…}" end
		seen[v] = true
		local o, n = {}, 0
		for k, x in v do
			n = n + 1
			if n > 14 then o[#o + 1] = "…" break end
			o[#o + 1] = (type(k) == "number" and ser(x, d + 1, seen)) or (tostring(k) .. "=" .. ser(x, d + 1, seen))
		end
		seen[v] = nil
		return "{" .. table.concat(o, ", ") .. "}"
	end
	return "<" .. t .. ">"
end
local function plain(v, d)
	d = d or 0
	local t = typeof(v)
	if t == "number" then return rd(v, 4)
	elseif t ~= "table" then
		if t == "Vector3" then return { rd(v.X, 3), rd(v.Y, 3), rd(v.Z, 3) } end
		if t == "CFrame" then
			local x, y, z = v:ToOrientation()
			return { pos = { rd(v.X, 3), rd(v.Y, 3), rd(v.Z, 3) }, rot = { rd(math.deg(x), 2), rd(math.deg(y), 2), rd(math.deg(z), 2) } }
		end
		if t == "Color3" then return hex(v) end
		return v
	end
	if d > 7 then return "{…}" end
	local o = {}
	for k, x in v do o[type(k) == "number" and k or tostring(k)] = plain(x, d + 1) end
	return o
end

local MOVERS = {
	BodyVelocity = true, BodyPosition = true, BodyGyro = true, BodyForce = true, BodyAngularVelocity = true, BodyThrust = true,
	LinearVelocity = true, AlignPosition = true, AlignOrientation = true, VectorForce = true, AngularVelocity = true, Torque = true,
}
local VIS = {
	ParticleEmitter = true, Beam = true, Trail = true, Highlight = true, PointLight = true, SpotLight = true, SurfaceLight = true,
	Explosion = true, Fire = true, Smoke = true, Sparkles = true, BillboardGui = true, SurfaceGui = true,
}
local HBNAMES = { "hitbox", "hit box", "hurtbox", "hit_box", "hbox", "damagebox", "damagearea", "aoe", "hb" }

---------------------------------------------------------------------------------------------------
local Rec = { state = "idle", t0 = 0, events = {}, pre = {}, victims = {}, lastAct = 0, path = {}, vpaths = {}, count = 0,
	adv = false, phase = "hit", noVic = false, hitAt = nil }
local Hist, Sel = {}, 0
local UI, Hooks = {}, {}

local log, markV, isHB, hookHB, describe, dumpE, dumpMesh, dumpSnd, eText
local trackChar, hookSnd, hookRem, arm, setState, startRec, stopRec, hitPhase
local toast, copyText

local function mine(i)
	if not i then return false end
	if ownGui and (i == ownGui or i:IsDescendantOf(ownGui)) then return true end
	return LoggedRoot ~= nil and i:IsDescendantOf(LoggedRoot)
end
local function inR(p)
	local r = myRoot()
	return r ~= nil and p ~= nil and (p - r.Position).Magnitude <= C.Radius
end
local function wname(m)
	if not m then return "WORLD" end
	return m == me() and "YOU" or m.Name
end
local function inScope(m)
	if not m then return false end
	if m == me() or Rec.victims[m] then return true end
	if not C.Others then return false end
	local r = rootOf(m)
	return r ~= nil and inR(r.Position)
end

function log(cat, who, text, data)
	if Rec.state == "idle" then return nil end
	local ev = { t = now(), cat = cat, who = wname(who), model = who, text = text, data = data or {} }
	if who and who ~= me() and Rec.victims[who] then ev.victim = true end
	if Rec.state == "armed" then
		Rec.pre[#Rec.pre + 1] = ev
		local cut = now() - math.max(C.Preroll, C.HitPreroll or 0)
		while #Rec.pre > 0 and Rec.pre[1].t < cut do table.remove(Rec.pre, 1) end
		while #Rec.pre > 500 do table.remove(Rec.pre, 1) end
	else
		if #Rec.events >= C.MaxEv then return ev end
		Rec.events[#Rec.events + 1] = ev
		if who == nil or who == me() or ev.victim then Rec.lastAct = now() end
		if Hooks.onEvent then task.spawn(g(Hooks.onEvent), ev) end
	end
	return ev
end

function markV(m, why)
	if not m or m == me() or Rec.noVic then return nil end
	local ex = Rec.victims[m]
	if ex then
		if why then ex[why] = true end
		return ex
	end
	local r = rootOf(m)
	if r and not inR(r.Position) then return nil end
	local e = { name = m.Name, firstAt = now() }
	if why then e[why] = true end
	Rec.victims[m] = e
	for _, ev in Rec.events do if ev.model == m then ev.victim = true end end
	log("STATE", m, "victim tracked (" .. tostring(why) .. ")", { kind = "victimStart", reason = why })
	return e
end

---------------------------------------------------------------------------------------------------
local kfs = {}
local function fetch(id)
	if kfs[id] ~= nil then return end
	kfs[id] = false
	task.spawn(g(function()
		local ok, s = pcall(function() return KSP:GetKeyframeSequenceAsync("rbxassetid://" .. tostring(id)) end)
		if not ok or not s then return end
		local info = { markers = {}, len = 0 }
		pcall(function()
			for _, kf in s:GetKeyframes() do
				info.len = math.max(info.len, kf.Time)
				for _, m in kf:GetMarkers() do info.markers[#info.markers + 1] = { name = m.Name, time = kf.Time, value = m.Value } end
			end
		end)
		table.sort(info.markers, function(a, b) return a.time < b.time end)
		kfs[id] = info
		pcall(function() s:Destroy() end)
	end))
end
local live = {}
local function isCore(tr, m)
	if tr.Priority == Enum.AnimationPriority.Core then return true end
	if tr.Looped and (tr.Priority == Enum.AnimationPriority.Idle or tr.Priority == Enum.AnimationPriority.Movement) then return true end
	local a = tr.Animation
	if not a then return false end
	local n = a.Parent
	while n and n ~= m do
		if n.Name == "Animate" then return true end
		n = n.Parent
	end
	return false
end

local function onAnim(m, tr, already)
	if Rec.state == "idle" or not inScope(m) then return end
	if C.IgnoreCore and isCore(tr, m) then return end
	if live[tr] then return end
	local a = tr.Animation
	local id = a and aid(a.AnimationId) or "?"
	if not already and m == me() and Rec.state == "armed" and C.StartOnAnim and tr.Priority.Value >= Enum.AnimationPriority.Action.Value then
		startRec("animation " .. (a and a.Name or id), "startup")
	end
	if m ~= me() then markV(m, "animation") end
	fetch(id)
	local d = { id = id, name = a and a.Name or "?", priority = tr.Priority.Name, looped = tr.Looped, speed = rd(tr.Speed, 3), length = rd(tr.Length, 3) }
	local since = 0
	if already then
		local spd = tr.Speed
		since = (spd ~= spd or spd == math.huge or spd <= 0.01) and 0 or tr.TimePosition / spd
		d.already, d.timePosition = true, rd(tr.TimePosition, 3)
	end
	local ev = log("ANIM", m, (already and "≡ (already playing, from ~" .. fn(since, 2) .. "s before) " or "▶ ") .. d.name .. " rbxassetid://" .. id .. " (" .. d.priority .. (d.looped and ", looped" or "") .. ", speed " .. fn(d.speed, 2) .. ")", d)
	if not ev then return end
	if already then ev.t = ev.t - since end
	local t0, cons = now(), {}
	live[tr] = { ev = ev, model = m, speed = tr.Speed, t0 = t0, tp = 0 }
	local function add(c) cons[#cons + 1] = c end
	add(tr.KeyframeReached:Connect(g(function(n)
		log("MARKER", m, "◆ keyframe '" .. n .. "' @" .. fn(tr.TimePosition, 3) .. "s (" .. d.name .. ")", { anim = id, name = n, kind = "keyframe", at = rd(tr.TimePosition, 3) })
	end)))
	add(tr.DidLoop:Connect(g(function(c)
		log("ANIM", m, "↻ " .. d.name .. " looped x" .. c .. " @" .. fn(tr.TimePosition, 2) .. "s", { anim = id, kind = "loop", count = c })
	end)))
	local function markers()
		local info = kfs[id]
		if not info or d.markers then return end
		d.markers = {}
		local seen = {}
		for _, mk in info.markers do
			d.markers[#d.markers + 1] = { name = mk.name, time = rd(mk.time, 3) }
			if not seen[mk.name] then
				seen[mk.name] = true
				add(tr:GetMarkerReachedSignal(mk.name):Connect(g(function(p)
					log("MARKER", m, "◆ marker '" .. mk.name .. "' @" .. fn(tr.TimePosition, 3) .. "s" .. (p and p ~= "" and (" = " .. tostring(p)) or "") .. " (" .. d.name .. ")",
						{ anim = id, name = mk.name, param = p, kind = "marker", at = rd(tr.TimePosition, 3) })
				end)))
			end
		end
	end
	markers()
	if not kfs[id] then
		task.spawn(g(function()
			for _ = 1, 40 do
				task.wait(0.05)
				if kfs[id] then markers() break end
			end
		end))
	end
	tr.Stopped:Once(g(function()
		for _, c in cons do c:Disconnect() end
		live[tr] = nil
		d.played = rd(now() - t0, 3)
		log("ANIM", m, "■ " .. d.name .. " stopped after " .. fn(d.played, 3) .. "s", { id = id, name = d.name, kind = "stop", played = d.played })
	end))
end

local function snapTracks(m)
	if not m then return end
	local h = m:FindFirstChildOfClass("Humanoid")
	local an = h and h:FindFirstChildOfClass("Animator")
	if not an then return end
	for _, tr in sf(function() return an:GetPlayingAnimationTracks() end) or {} do
		pcall(onAnim, m, tr, true)
	end
end

---------------------------------------------------------------------------------------------------
-- exhaustive effect dump: every readable property, every asset id, every colour
---------------------------------------------------------------------------------------------------
local EPROPS = {
	"Enabled", "Texture", "Color", "Size", "Transparency", "Lifetime", "Rate", "Speed", "SpreadAngle", "Rotation", "RotSpeed",
	"Acceleration", "Drag", "VelocityInheritence", "LightEmission", "LightInfluence", "ZOffset", "EmissionDirection",
	"Shape", "ShapeStyle", "ShapeInOut", "ShapePartial", "Squash", "Orientation", "LockedToPart", "TimeScale", "WindAffectsDrag",
	"FlipbookLayout", "FlipbookFramerate", "FlipbookStartRandom", "FlipbookStartFrame", "FlipbookParticleCount",
}
local BPROPS = { "Enabled", "Texture", "TextureLength", "TextureMode", "TextureSpeed", "Color", "Transparency", "Width0", "Width1",
	"CurveSize0", "CurveSize1", "Segments", "LightEmission", "LightInfluence", "FaceCamera", "ZOffset", "Attachment0", "Attachment1" }
local TPROPS = { "Enabled", "Texture", "TextureLength", "TextureMode", "Color", "Transparency", "Lifetime", "WidthScale",
	"MinLength", "LightEmission", "FaceCamera", "Attachment0", "Attachment1" }
local MPROPS = { "MeshId", "TextureId", "TextureID", "MeshType", "Scale", "Offset", "VertexColor", "RenderFidelity",
	"ColorMap", "NormalMap", "RoughnessMap", "MetalnessMap", "AlphaMode", "Texture", "Transparency", "Color", "Material" }
local SPROPS = { "SoundId", "Volume", "PlaybackSpeed", "Looped", "Playing", "TimePosition", "RollOffMode",
	"RollOffMinDistance", "RollOffMaxDistance", "EmitterSize", "PlayOnRemove", "TimeLength" }
local NOISE = {
	Name = true, Parent = true, ClassName = true, Archivable = true, RobloxLocked = true, Sandboxed = true,
	SecurityCapabilities = true, UniqueId = true, Attributes = true, AttributesSerialize = true, Tags = true,
	HistoryId = true, SourceAssetId = true, InternalSize = true,
}

local function isAsset(k, v)
	if type(v) ~= "string" or v == "" or #v > 300 then return false end
	if string.find(k, "Texture") or string.find(k, "MeshId") or string.find(k, "SoundId") or string.find(k, "Image")
		or string.find(k, "Map") or string.find(k, "Mesh") then return true end
	return aid(v) ~= nil and (string.find(v, "rbxasset", 1, true) ~= nil or string.find(v, "http", 1, true) ~= nil)
end

local function put(d, k, v, t)
	if t == "EnumItem" then
		local et, ev = string.match(tostring(v), "^Enum%.([%w_]+)%.([%w_]+)$")
		d[k] = { kind = "enum", enumType = et, value = ev }
	elseif t == "ColorSequence" then
		d[k] = seqD(v)
		for _, kp in d[k].keypoints do d.colors[#d.colors + 1] = { property = k, hex = kp.color, rgb = kp.rgb } end
	elseif t == "NumberSequence" or t == "NumberRange" then
		d[k] = seqD(v)
	elseif t == "Color3" then
		d[k] = { kind = "color3", hex = hex(v), rgb = rgb(v) }
		d.colors[#d.colors + 1] = { property = k, hex = hex(v), rgb = rgb(v) }
	elseif t == "BrickColor" then
		d[k] = v.Name
	elseif t == "Vector3" then
		d[k] = { rd(v.X, 3), rd(v.Y, 3), rd(v.Z, 3) }
	elseif t == "Vector2" then
		d[k] = { rd(v.X, 3), rd(v.Y, 3) }
	elseif t == "CFrame" then
		local l = l2(v)
		d[k] = { pos = { rd(v.X, 3), rd(v.Y, 3), rd(v.Z, 3) }, rel = l and { rd(l.Position.X, 3), rd(l.Position.Y, 3), rd(l.Position.Z, 3) } }
	elseif t == "number" then
		d[k] = rd(v, 4)
	elseif t == "boolean" then
		d[k] = v
	elseif t == "string" then
		d[k] = v
		if isAsset(k, v) then d.assets[#d.assets + 1] = { property = k, raw = v, id = aid(v) } end
	elseif t == "Rect" then
		d[k] = { min = { rd(v.Min.X, 2), rd(v.Min.Y, 2) }, max = { rd(v.Max.X, 2), rd(v.Max.Y, 2) } }
	elseif t == "Instance" then
		local cf = v:IsA("Attachment") and gp(v, "WorldCFrame")
		local l = cf and l2(cf)
		d[k] = { path = sp(v, 4), class = v.ClassName, rel = l and { rd(l.Position.X, 2), rd(l.Position.Y, 2), rd(l.Position.Z, 2) } }
	end
end

local function dumpProps(i, list)
	local d = { assets = {}, colors = {} }
	local seen = {}
	local function take(k)
		if seen[k] or NOISE[k] then return end
		seen[k] = true
		local v, t = gp(i, k), nil
		if v == nil then return end
		t = typeof(v)
		if t == "function" or t == "table" or t == "thread" then return end
		put(d, k, v, t)
	end
	for _, p in list do take(p) end
	local ok, all = pcall(function() return i:GetProperties() end)
	if ok and type(all) == "table" then
		local ks = {}
		for k in all do if type(k) == "string" then ks[#ks + 1] = k end end
		table.sort(ks)
		for _, k in ks do take(k) end
	end
	return d
end

function dumpE(e)
	if not e then return nil end
	local d = dumpProps(e, e:IsA("Beam") and BPROPS or (e:IsA("Trail") and TPROPS or EPROPS))
	d.class, d.name = e.ClassName, e.Name
	local at = e:GetAttributes()
	if next(at) then d.attributes = at end
	local h = e.Parent
	if h then
		d.hostName, d.hostClass, d.hostPath = h.Name, h.ClassName, sp(h, 4)
		if h:IsA("BasePart") then
			d.hostSize = { rd(h.Size.X, 3), rd(h.Size.Y, 3), rd(h.Size.Z, 3) }
			d.hostMaterial, d.hostTransparency = h.Material.Name, rd(h.Transparency, 3)
			d.hostColor, d.hostColorRgb = hex(h.Color), rgb(h.Color)
			d.hostShape = h:IsA("Part") and h.Shape.Name or nil
			local l = l2(h.CFrame)
			if l then d.hostOffset = { rd(l.Position.X, 3), rd(l.Position.Y, 3), rd(l.Position.Z, 3) } end
			local tx = h:IsA("MeshPart") and gp(h, "TextureID") or gp(h, "Texture")
			if type(tx) == "string" and tx ~= "" then
				d.hostTexture = { raw = tx, id = aid(tx) }
				d.assets[#d.assets + 1] = { property = "HostTexture", raw = tx, id = aid(tx) }
			end
			local mi = h:IsA("MeshPart") and gp(h, "MeshId") or nil
			if type(mi) == "string" and mi ~= "" then
				d.hostMeshId = { raw = mi, id = aid(mi) }
				d.assets[#d.assets + 1] = { property = "HostMeshId", raw = mi, id = aid(mi) }
			end
			d.colors[#d.colors + 1] = { property = "HostColor", hex = hex(h.Color), rgb = rgb(h.Color) }
		elseif h:IsA("Attachment") then
			local wc = gp(h, "WorldCFrame")
			local l = wc and l2(wc)
			if l then d.hostOffset = { rd(l.Position.X, 3), rd(l.Position.Y, 3), rd(l.Position.Z, 3) } end
			d.hostParent = h.Parent and h.Parent.Name
			if h.Parent and h.Parent:IsA("BasePart") then
				d.hostSize = { rd(h.Parent.Size.X, 3), rd(h.Parent.Size.Y, 3), rd(h.Parent.Size.Z, 3) }
			end
		end
	end
	return d
end

function dumpMesh(i)
	local d = dumpProps(i, MPROPS)
	d.class, d.name = i.ClassName, i.Name
	if i:IsA("BasePart") then
		d.size = { rd(i.Size.X, 3), rd(i.Size.Y, 3), rd(i.Size.Z, 3) }
		d.colorHex, d.colorRgb = hex(i.Color), rgb(i.Color)
	end
	return d
end

function dumpSnd(s)
	local d = dumpProps(s, SPROPS)
	d.class, d.name = s.ClassName, s.Name
	d.parent = s.Parent and sp(s.Parent, 4) or nil
	return d
end

local function mText(x)
	local id = x.MeshId and aid(x.MeshId)
	local tx = (x.TextureId and aid(x.TextureId)) or (x.TextureID and aid(x.TextureID)) or (x.Texture and aid(x.Texture))
	local mt = type(x.MeshType) == "table" and x.MeshType.value or nil
	local o = (id and ("mesh " .. id)) or (mt and mt ~= "FileMesh" and mt) or x.class or "?"
	if tx then o = o .. " tex " .. tx end
	if type(x.Scale) == "table" then o = o .. " scale (" .. fn(x.Scale[1], 3) .. ", " .. fn(x.Scale[2], 3) .. ", " .. fn(x.Scale[3], 3) .. ")" end
	if type(x.Offset) == "table" and (x.Offset[1] ~= 0 or x.Offset[2] ~= 0 or x.Offset[3] ~= 0) then o = o .. " offset (" .. fn(x.Offset[1], 3) .. ", " .. fn(x.Offset[2], 3) .. ", " .. fn(x.Offset[3], 3) .. ")" end
	if type(x.VertexColor) == "table" and (x.VertexColor[1] ~= 1 or x.VertexColor[2] ~= 1 or x.VertexColor[3] ~= 1) then o = o .. " vcolor (" .. fn(x.VertexColor[1], 3) .. ", " .. fn(x.VertexColor[2], 3) .. ", " .. fn(x.VertexColor[3], 3) .. ")" end
	if type(x.Transparency) == "number" and x.Transparency ~= 0 then o = o .. " transp " .. fn(x.Transparency, 3) end
	return o
end
local function mLua(x)
	local f = {}
	local function v3(k) local v = x[k] if type(v) == "table" and #v == 3 then f[#f + 1] = k .. " = Vector3.new(" .. fn(v[1], 4) .. ", " .. fn(v[2], 4) .. ", " .. fn(v[3], 4) .. ")" end end
	f[#f + 1] = "Class = " .. qs(x.class or "?")
	f[#f + 1] = "Name = " .. qs(x.name or "?")
	for _, k in { "MeshId", "TextureId", "TextureID", "Texture" } do if type(x[k]) == "string" and x[k] ~= "" then f[#f + 1] = k .. " = " .. qs(x[k]) end end
	if type(x.MeshType) == "table" and x.MeshType.value then f[#f + 1] = "MeshType = Enum.MeshType." .. x.MeshType.value end
	v3("Scale") v3("Offset") v3("VertexColor")
	if type(x.Transparency) == "number" then f[#f + 1] = "Transparency = " .. fn(x.Transparency, 4) end
	if type(x.Color3) == "table" and x.Color3.rgb then f[#f + 1] = string.format("Color3 = Color3.fromRGB(%d, %d, %d)", x.Color3.rgb[1], x.Color3.rgb[2], x.Color3.rgb[3]) end
	if type(x.Face) == "table" and x.Face.value then f[#f + 1] = "Face = Enum.NormalId." .. x.Face.value end
	return "{ " .. table.concat(f, ", ") .. " }"
end

function isHB(n)
	n = string.lower(tostring(n))
	for _, p in HBNAMES do if string.find(n, p, 1, true) then return true end end
	return false
end

local function hasVis(i)
	if VIS[i.ClassName] or i:IsA("Decal") or i:IsA("Texture") then return true end
	for _, d in i:GetDescendants() do
		if VIS[d.ClassName] or d:IsA("Decal") or d:IsA("Texture") or d:IsA("SpecialMesh") then return true end
		if d:IsA("BasePart") and d.Transparency < 0.98 then return true end
	end
	return i:IsA("BasePart") and i.Transparency < 0.98
end

local function hbKind(i)
	if not i:IsA("BasePart") then return nil end
	if isHB(i.Name) then return "named" end
	if i.Transparency >= 0.98 and not i.CanCollide and i.Size.Magnitude > 2.5 and not hasVis(i) then return "invisible" end
end

function describe(i)
	local d = { name = i.Name, class = i.ClassName, path = sp(i.Parent, 3), folder = i.Parent and i.Parent.Name, assets = {}, colors = {} }
	if i:IsA("BasePart") then
		d.size, d.material, d.transparency, d.color = i.Size, i.Material.Name, rd(i.Transparency, 3), hex(i.Color)
		d.colorRgb = rgb(i.Color)
		d.anchored, d.canCollide, d.canTouch, d.canQuery, d.massless = i.Anchored, i.CanCollide, i.CanTouch, i.CanQuery, i.Massless
		d.shape = i:IsA("Part") and i.Shape.Name or nil
		local av = gp(i, "AssemblyLinearVelocity") or Vector3.zero
		d.velocity, d.localVelocity = av, ldir(av)
		d.colors[#d.colors + 1] = { property = "Color", hex = hex(i.Color), rgb = rgb(i.Color) }
		local tx = i:IsA("MeshPart") and gp(i, "TextureID") or gp(i, "Texture")
		if type(tx) == "string" and tx ~= "" then
			d.hostTexture = tx
			d.assets[#d.assets + 1] = { property = "HostTexture", raw = tx, id = aid(tx) }
		end
		local mi = i:IsA("MeshPart") and gp(i, "MeshId") or nil
		if type(mi) == "string" and mi ~= "" then
			d.hostMeshId = mi
			d.assets[#d.assets + 1] = { property = "HostMeshId", raw = mi, id = aid(mi) }
		end
	elseif i:IsA("Model") then
		d.size = sf(function() return i:GetExtentsSize() end)
	end
	local at = i:GetAttributes()
	if next(at) then d.attributes = at end
	local cf = cfOf(i)
	if cf then
		local l = l2(cf)
		if l then d.offset, d.offsetCF = l.Position, l end
		if Rec.startCF then d.startOffset = Rec.startCF:ToObjectSpace(cf).Position end
	end
	d.emitters, d.beams, d.trails, d.meshes, d.sounds, d.contents = {}, {}, {}, {}, {}, {}
	local function scan(n)
		d.contents[n.ClassName] = (d.contents[n.ClassName] or 0) + 1
		if n:IsA("ParticleEmitter") then d.emitters[#d.emitters + 1] = dumpE(n)
		elseif n:IsA("Beam") then d.beams[#d.beams + 1] = dumpE(n)
		elseif n:IsA("Trail") then d.trails[#d.trails + 1] = dumpE(n)
		elseif n:IsA("SpecialMesh") or n:IsA("MeshPart") or n:IsA("SurfaceAppearance") or n:IsA("Decal") or n:IsA("Texture") then
			d.meshes[#d.meshes + 1] = dumpMesh(n)
		elseif n:IsA("Sound") then d.sounds[#d.sounds + 1] = dumpSnd(n)
		end
	end
	scan(i)
	for _, n in i:GetDescendants() do scan(n) end
	for _, grp in { d.emitters, d.beams, d.trails, d.meshes, d.sounds } do
		for _, e in grp do
			for _, a in e.assets or {} do d.assets[#d.assets + 1] = a end
			for _, c in e.colors or {} do d.colors[#d.colors + 1] = c end
		end
	end
	for _, w in i:GetDescendants() do
		if w:IsA("WeldConstraint") or w:IsA("Weld") or w:IsA("Motor6D") then
			local o = (w.Part0 and not w.Part0:IsDescendantOf(i)) and w.Part0 or ((w.Part1 and not w.Part1:IsDescendantOf(i)) and w.Part1 or nil)
			if o then
				local c = chOf(o)
				d.weldedTo = (c and (wname(c) .. ".") or "") .. o.Name
				break
			end
		end
	end
	return d
end

function eText(e)
	local o = {}
	if e.attributes then
		for _, k in { "EmitCount", "EmitDelay", "EmitDuration" } do
			if e.attributes[k] ~= nil then o[#o + 1] = k .. " " .. tostring(e.attributes[k]) end
		end
	end
	if e.Texture then
		local t = type(e.Texture) == "table" and e.Texture.raw or e.Texture
		if t and t ~= "" then o[#o + 1] = "tex " .. tostring(aid(t) or t) end
	end
	if e.Rate then o[#o + 1] = "rate " .. fn(e.Rate, 2) end
	if e.Lifetime then o[#o + 1] = "life " .. seqT(e.Lifetime) end
	if e.Speed then o[#o + 1] = "speed " .. seqT(e.Speed) end
	if e.Size then o[#o + 1] = "size " .. seqT(e.Size) end
	if e.Color then o[#o + 1] = "color " .. seqT(e.Color) end
	if e.SpreadAngle then o[#o + 1] = "spread " .. seqT(e.SpreadAngle) end
	if e.Shape then o[#o + 1] = "shape " .. seqT(e.Shape) end
	return table.concat(o, " ")
end

---------------------------------------------------------------------------------------------------
local tracked = setmetatable({}, { __mode = "k" })
-- (you and everyone in scope: a victim's reaction animation is usually already going when a hit phase starts)
local function snapAll()
	snapTracks(me())
	for m in tracked do
		if m ~= me() and m.Parent and inScope(m) then snapTracks(m) end
	end
end

local function moverInfo(m, who)
	local d, txt = { class = m.ClassName, name = m.Name }, m.ClassName
	if m:IsA("BodyVelocity") then
		local l = ldir(m.Velocity)
		d.localVelocity, d.maxForce = l, m.MaxForce
		txt = "BodyVelocity " .. dw(l) .. " (|v| " .. fn(m.Velocity.Magnitude, 1) .. ")"
	elseif m:IsA("LinearVelocity") then
		local v = m.VectorVelocity
		if m.RelativeTo == Enum.ActuatorRelativeTo.World then v = ldir(v) end
		d.localVelocity, d.relativeTo, d.mode = v, m.RelativeTo.Name, m.VelocityConstraintMode.Name
		txt = "LinearVelocity " .. dw(v) .. " (" .. m.RelativeTo.Name .. ", " .. m.VelocityConstraintMode.Name .. ")"
	elseif m:IsA("BodyPosition") or m:IsA("AlignPosition") then
		local l = l2(CFrame.new(m.Position))
		d.localPosition = l and l.Position
		txt = m.ClassName .. " → " .. (l and dw(l.Position) or v3s(m.Position))
	elseif m:IsA("BodyGyro") or m:IsA("AlignOrientation") then
		txt = m.ClassName
	elseif m:IsA("VectorForce") or m:IsA("BodyForce") then
		d.localForce = ldir(m.Force)
		txt = m.ClassName .. " " .. dw(d.localForce)
	end
	return txt, d
end

local function logMover(m, who)
	if not m.Parent then return end
	if who and who ~= me() then markV(who, "mover") end
	local txt, d = moverInfo(m, who)
	local ev = log("MOVE", who, "+ " .. txt, d)
	if not ev then return end
	local t0 = now()
	local conn
	conn = m.AncestryChanged:Connect(function(_, p)
		if p == nil then
			conn:Disconnect()
			d.duration = rd(now() - t0, 3)
			log("MOVE", who, "- " .. m.ClassName .. " removed after " .. fn(d.duration, 3) .. "s", { class = m.ClassName, kind = "end", duration = d.duration })
		end
	end)
end

local function logToggle(i, who)
	if not (i:IsA("ParticleEmitter") or i:IsA("Beam") or i:IsA("Trail") or i:IsA("Highlight")) then return end
	local info = tracked[who]
	if not info then return end
	info.conns[#info.conns + 1] = i:GetPropertyChangedSignal("Enabled"):Connect(g(function()
		if Rec.state == "idle" or not inScope(who) then return end
		log("VFX", who, (i.Enabled and "◉ enabled " or "○ disabled ") .. i.ClassName .. " '" .. i.Name .. "' on " .. sp(i.Parent, 2),
			{ class = i.ClassName, name = i.Name, enabled = i.Enabled, path = sp(i, 5), kind = "toggle", dump = dumpE(i) })
	end))
end

function trackChar(m)
	if tracked[m] or not m:IsA("Model") then return end
	local h = m:FindFirstChildOfClass("Humanoid")
	if not h then return end
	local info = { conns = {}, attrs = m:GetAttributes(), hattrs = h:GetAttributes(), tags = {}, hp = h.Health, kids = {} }
	for _, t in m:GetTags() do info.tags[t] = true end
	tracked[m] = info
	local cons = info.conns
	local function add(c) cons[#cons + 1] = c end
	local function anim(an) add(an.AnimationPlayed:Connect(g(function(tr) onAnim(m, tr) end))) end
	local an = h:FindFirstChildOfClass("Animator")
	if an then anim(an) end
	add(h.ChildAdded:Connect(g(function(c) if c:IsA("Animator") then anim(c) end end)))

	add(h.HealthChanged:Connect(g(function(hp)
		local last = info.hp
		info.hp = hp
		if Rec.state == "idle" then return end
		local diff = last - hp
		if math.abs(diff) < 0.01 then return end
		if m == me() then
			log("HIT", m, (diff > 0 and "took " or "healed ") .. fn(math.abs(diff), 1) .. " HP (now " .. fn(hp, 1) .. ")", { amount = rd(-diff, 2), health = rd(hp, 2), target = "YOU" })
			return
		end
		if diff > 0 then markV(m, "damage") end
		local r, mr = rootOf(m), myRoot()
		if not r or not mr or not inR(r.Position) then return end
		local rel = mr.CFrame:ToObjectSpace(r.CFrame)
		log("HIT", m, (diff > 0 and "−" or "+") .. fn(math.abs(diff), 1) .. " HP → " .. m.Name .. " (at you " .. dw(rel.Position) .. ", " .. fn(rel.Position.Magnitude, 1) .. " studs)",
			{ amount = rd(diff, 2), health = rd(hp, 2), target = m.Name, offset = rel.Position, offsetCF = rel,
				distance = rd(rel.Position.Magnitude, 2), size = m:GetExtentsSize(), localVelocity = ldir(r.AssemblyLinearVelocity) })
	end)))

	add(h.StateChanged:Connect(g(function(o, n)
		if Rec.state == "idle" or not inScope(m) then return end
		if n == Enum.HumanoidStateType.Running or n == Enum.HumanoidStateType.RunningNoPhysics or n == Enum.HumanoidStateType.Landed then return end
		log("STATE", m, "state " .. o.Name .. " → " .. n.Name, { kind = "humanoidState", from = o.Name, to = n.Name })
	end)))

	for _, p in { "WalkSpeed", "JumpPower", "JumpHeight", "AutoRotate", "PlatformStand", "Sit", "FloorMaterial" } do
		local last = gp(h, p)
		add(h:GetPropertyChangedSignal(p):Connect(g(function()
			local v = h[p]
			local was = last
			last = v
			if Rec.state == "idle" or not inScope(m) then return end
			log("STATE", m, p .. " " .. ser(was) .. " → " .. ser(v), { kind = "property", property = p, from = was, to = v })
		end)))
	end

	add(m.ChildAdded:Connect(g(function(c)
		if Rec.state == "idle" or not inScope(m) then return end
		if c:IsA("BasePart") or c:IsA("Humanoid") or c:IsA("Script") or c:IsA("LocalScript") then return end
		if VIS[c.ClassName] then return end
		if c:IsA("Model") and c:FindFirstChildWhichIsA("BasePart", true) then return end
		local at = c:GetAttributes()
		local val = c:IsA("ValueBase") and gp(c, "Value") or nil
		info.kids[c] = now()
		if m ~= me() and any(c.Name, { "stun", "ragdoll", "hit", "freeze", "slow" }) then markV(m, "marker") end
		log("STATE", m, "+ " .. c.ClassName .. " '" .. c.Name .. "'" .. (val ~= nil and (" = " .. ser(val)) or "") .. (next(at) and ("  " .. ser(at)) or ""),
			{ kind = "childAdded", class = c.ClassName, name = c.Name, value = val, attributes = at })
		local store = c:GetAttributes()
		add(c.AttributeChanged:Connect(g(function(n)
			local v = c:GetAttribute(n)
			local was = store[n]
			store[n] = v
			if Rec.state == "idle" or not inScope(m) then return end
			log("STATE", m, "child attr " .. c.Name .. "." .. n .. ": " .. ser(was) .. " → " .. ser(v), { kind = "childAttribute", child = c.Name, name = n, from = was, to = v })
		end)))
	end)))

	add(m.ChildRemoved:Connect(g(function(c)
		local b = info.kids[c]
		info.kids[c] = nil
		if Rec.state == "idle" or not b then return end
		log("STATE", m, "- " .. c.ClassName .. " '" .. c.Name .. "' removed after " .. fn(now() - b, 3) .. "s", { kind = "childRemoved", class = c.ClassName, name = c.Name })
	end)))

	local function attrH(i, store, lbl)
		add(i.AttributeChanged:Connect(g(function(n)
			local v = i:GetAttribute(n)
			local was = store[n]
			store[n] = v
			if Rec.state == "idle" or not inScope(m) then return end
			log("STATE", m, lbl .. "attr " .. n .. ": " .. ser(was) .. " → " .. ser(v), { kind = "attribute", on = lbl == "" and "Character" or "Humanoid", name = n, from = was, to = v })
		end)))
	end
	attrH(m, info.attrs, "")
	attrH(h, info.hattrs, "Humanoid.")

	add(m.DescendantAdded:Connect(g(function(d)
		if Rec.state == "idle" or not inScope(m) then return end
		if MOVERS[d.ClassName] then task.defer(g(logMover), d, m) end
		if VIS[d.ClassName] then logToggle(d, m) end
		if d:IsA("BasePart") and isHB(d.Name) then task.defer(g(hookHB), d, m) end
	end)))
	for _, d in m:GetDescendants() do
		if VIS[d.ClassName] then logToggle(d, m) end
		if d:IsA("BasePart") and isHB(d.Name) then task.defer(g(hookHB), d, m) end
	end
	add(m.Destroying:Connect(function()
		for _, c in cons do pcall(function() c:Disconnect() end) end
		tracked[m] = nil
	end))
end

---------------------------------------------------------------------------------------------------
local hsounds = setmetatable({}, { __mode = "k" })
local sIgnore = lst(C.SIgnore)
local function logSnd(s)
	if Rec.state == "idle" or mine(s) or any(s.Name, sIgnore) then return end
	local own = chOf(s)
	local p = posOf(s.Parent)
	if own then
		if not inScope(own) then return end
	elseif p and not inR(p) then
		return
	end
	local id = aid(s.SoundId) or s.SoundId
	local rel = p and l2(CFrame.new(p))
	local d = { id = id, name = s.Name, volume = rd(s.Volume, 3), speed = rd(s.PlaybackSpeed, 3), timePosition = rd(s.TimePosition, 3),
		looped = s.Looped, parent = sp(s.Parent, 4), rollOffMode = s.RollOffMode.Name, rollOffMin = rd(s.RollOffMinDistance, 1),
		rollOffMax = rd(s.RollOffMaxDistance, 1), emitterSize = rd(s.EmitterSize, 2), length = rd(s.TimeLength, 3), offset = rel and rel.Position }
	if not log("SOUND", own, "♪ " .. s.Name .. " rbxassetid://" .. tostring(id) .. " (vol " .. fn(d.volume, 2) .. ", pitch " .. fn(d.speed, 2) .. ") on " .. d.parent, d) then return end
	local t0, done = now(), false
	local function fin()
		if done then return end
		done = true
		d.played = rd(now() - t0, 3)
	end
	s.Stopped:Once(fin); s.Ended:Once(fin); s.Destroying:Once(fin)
end
function hookSnd(s)
	if hsounds[s] then return end
	hsounds[s] = true
	s.Played:Connect(g(function() logSnd(s) end))
	if s.Playing and Rec.state ~= "idle" then task.defer(g(logSnd), s) end
end

---------------------------------------------------------------------------------------------------
local pend, pFlush, logged, clones, sigs = {}, false, {}, 0, {}
local FXSET = setmetatable({}, { __mode = "k" })

local function saveClone(i, lbl)
	if not C.Clone or Rec.state ~= "recording" or not Rec.save then return nil end
	if clones > C.MaxClones then return nil end
	local a = i.Archivable
	i.Archivable = true
	local ok, c = pcall(i.Clone, i)
	i.Archivable = a
	if not ok or not c then return nil end
	clones = clones + 1
	c.Name = lbl
	for _, d in c:GetDescendants() do if d:IsA("BaseScript") then d.Enabled = false end end
	if c:IsA("BasePart") then c.Anchored = true end
	pcall(function() c.Parent = Rec.save end)
	return c
end

local function process(i, born)
	if not i.Parent or mine(i) then return end
	local own, p = chOf(i), posOf(i)
	if own then
		if not inScope(own) then return end
	elseif not p or not inR(p) then
		return
	end
	if i:IsA("Attachment") and not hasVis(i) then return end
	if i:IsA("Folder") and #i:GetChildren() == 0 then return end
	local hb = hbKind(i)
	local d = describe(i)
	local cat, txt
	if hb then
		cat = "HITBOX"
		d.hitboxKind = hb
		txt = "▣ " .. (hb == "named" and "hitbox" or "possible hitbox") .. " '" .. i.Name .. "' size " .. (d.size and v3s(d.size) or "?") .. (d.offset and (" at you " .. dw(d.offset)) or "") .. (d.weldedTo and (" welded to " .. d.weldedTo) or "")
	else
		cat = "VFX"
		local o = {}
		for _, e in d.emitters do o[#o + 1] = "'" .. e.name .. "'{" .. eText(e) .. "}" end
		for _, e in d.beams do o[#o + 1] = "beam '" .. e.name .. "'{" .. eText(e) .. "}" end
		for _, e in d.trails do o[#o + 1] = "trail '" .. e.name .. "'{" .. eText(e) .. "}" end
		local ms = {}
		for _, m in d.meshes do ms[#ms + 1] = mText(m) end
		txt = "✦ " .. i.ClassName .. " '" .. i.Name .. "' in " .. d.path .. " host " .. (d.size and ("size " .. v3s(d.size)) or "?") ..
			(#o > 0 and ("  " .. table.concat(o, " ")) or "") .. (#ms > 0 and ("  meshes " .. table.concat(ms, ", ")) or "") .. (d.offset and ("  at you " .. dw(d.offset)) or "")
	end
	local ev = log(cat, own, txt, d)
	if not ev then return end
	ev.t = math.min(ev.t, born)
	if Rec.state == "recording" then
		local sig = i.Name .. "|" .. i.ClassName .. "|" .. tostring(d.folder)
		if not sigs[sig] or cat == "HITBOX" then
			sigs[sig] = true
			local lbl = string.format("%06.3f %s", math.max(0, born - Rec.t0), i.Name)
			if saveClone(i, lbl) then d.saved = lbl end
		else
			d.duplicate = true
		end
	end
	FXSET[i] = ev
	if (C.Motion or cat == "HITBOX") and #logged < 100 then logged[#logged + 1] = { inst = i, ev = ev, born = born, samples = {} } end
	local conn
	conn = i.AncestryChanged:Connect(function(_, p2)
		if p2 == nil then
			conn:Disconnect()
			d.lifetime = rd(now() - born, 3)
		end
	end)
	if i:IsA("BasePart") and isHB(i.Name) then task.defer(g(hookHB), i, own) end
end

local function flush()
	pFlush = false
	local b = pend
	pend = {}
	for i, born in b do
		local n, skip = i.Parent, false
		while n and n ~= workspace and n ~= game do
			if b[n] then skip = true break end
			n = n.Parent
		end
		if not skip then pcall(process, i, born) end
	end
end

local CAND = { BasePart = true, Model = true, Attachment = true, Folder = true }
local function onDesc(i)
	local cls = i.ClassName
	if cls == "Sound" then hookSnd(i) return end
	if cls == "Humanoid" then
		if i.Parent and i.Parent:IsA("Model") then task.defer(g(trackChar), i.Parent) end
		return
	end
	if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" then
		if UI.hookRemote then UI.hookRemote(i) end
		return
	end
	if Rec.state == "idle" then return end
	if MOVERS[cls] then
		local a0 = gp(i, "Attachment0")
		local c = a0 and chOf(a0)
		if c and not chOf(i) and inScope(c) then task.defer(g(logMover), i, c) end
		return
	end
	if i:IsA("BasePart") and isHB(i.Name) then
		local o = chOf(i)
		if not o or inScope(o) then task.defer(g(hookHB), i, o) end
	end
	if not (VIS[cls] or i:IsA("BasePart") or CAND[cls]) then return end
	local own = chOf(i)
	if own then
		if own == i or cls == "Folder" then return end
		if i.Parent and i.Parent:IsA("Accessory") then return end
		if i.Parent == own and i:IsA("BasePart") and own ~= me() and not hbKind(i) then return end
	end
	if i:FindFirstChildOfClass("Humanoid") then return end
	pend[i] = now()
	if not pFlush then
		pFlush = true
		task.defer(g(flush))
	end
end

---------------------------------------------------------------------------------------------------
local hookedHB, throttle = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
function hookHB(p, own)
	if hookedHB[p] then return end
	hookedHB[p] = true
	local snap = { size = p.Size, transp = p.Transparency, touch = p.CanTouch, collide = p.CanCollide, anch = p.Anchored }
	local function alive() return p.Parent ~= nil and Rec.state ~= "idle" and (not own or inScope(own)) end
	local function base(k)
		local d = describe(p)
		d.kind = k
		d.hitboxKind = hbKind(p) or "tracked"
		return d
	end
	p:GetPropertyChangedSignal("Size"):Connect(g(function()
		if not alive() then return end
		local was = snap.size
		snap.size = p.Size
		if (p.Size - was).Magnitude < 0.01 then return end
		local d = base("resized")
		d.from, d.to = was, p.Size
		log("HITBOX", own, "▣ '" .. p.Name .. "' size " .. v3s(was) .. " → " .. v3s(p.Size) .. (d.offset and (" at you " .. dw(d.offset)) or ""), d)
	end))
	p:GetPropertyChangedSignal("Transparency"):Connect(g(function()
		if not alive() then return end
		local was = snap.transp
		snap.transp = p.Transparency
		if math.abs(p.Transparency - was) < 0.01 then return end
		local d = base("visibility")
		d.from, d.to = rd(was, 3), rd(p.Transparency, 3)
		log("HITBOX", own, "▣ '" .. p.Name .. "' transparency " .. fn(was, 2) .. " → " .. fn(p.Transparency, 2), d)
	end))
	p:GetPropertyChangedSignal("CanTouch"):Connect(g(function()
		if not alive() then return end
		local was = snap.touch
		snap.touch = p.CanTouch
		local d = base("canTouch")
		d.from, d.to = was, p.CanTouch
		log("HITBOX", own, "▣ '" .. p.Name .. "' CanTouch " .. tostring(was) .. " → " .. tostring(p.CanTouch) .. (p.CanTouch and " (armed)" or ""), d)
	end))
	p:GetPropertyChangedSignal("Anchored"):Connect(g(function()
		if not alive() then return end
		local was = snap.anch
		snap.anch = p.Anchored
		local d = base("anchored")
		d.from, d.to = was, p.Anchored
		log("HITBOX", own, "▣ '" .. p.Name .. "' Anchored " .. tostring(was) .. " → " .. tostring(p.Anchored), d)
	end))
	if C.Touches then
		p.Touched:Connect(g(function(hit)
			if not alive() then return end
			local vic = chOf(hit)
			if not vic and not C.Debug then return end
			local mr = myRoot()
			local key = vic or hit
			local t = now()
			if throttle[key] and t - throttle[key] < 0.08 then return end
			throttle[key] = t
			if vic and vic ~= me() then markV(vic, "hitboxTouch") end
			local rel = mr and mr.CFrame:ToObjectSpace(hit.CFrame)
			local d = base("touch")
			d.touched, d.victim = hit.Name, vic and vic.Name or nil
			if vic then d.victimExtents = sf(vic.GetExtentsSize, vic) end
			d.offset, d.offsetCF, d.distance = rel and rel.Position, rel, rel and rd(rel.Position.Magnitude, 2)
			log("HITBOX", own, "▣ '" .. p.Name .. "' touched " .. hit.Name .. (vic and (" [VICTIM " .. vic.Name .. "]") or "") .. (rel and (" at you " .. dw(rel.Position) .. ", " .. fn(rel.Position.Magnitude, 1) .. " studs") or ""), d)
		end))
	end
end

---------------------------------------------------------------------------------------------------
local dummies = setmetatable({}, { __mode = "k" })
local function attachDummy(m)
	if dummies[m] then return end
	local h = m:FindFirstChildOfClass("Humanoid")
	if not h then return end
	dummies[m] = true
	local last = h.Health
	local c = h:GetPropertyChangedSignal("Health"):Connect(g(function()
		local hp = h.Health
		local diff = last - hp
		if diff ~= 0 then
			if diff > 0 then markV(m, "damage") end
			log("HIT", m, "dummy " .. m.Name .. " " .. fn(last, 1) .. " → " .. fn(hp, 1), { amount = rd(diff, 2), health = rd(hp, 2), target = m.Name, dummy = true })
		end
		last = hp
	end))
	cn(m.Destroying:Connect(function() c:Disconnect() end))
end
local function scanDummies()
	if not C.Dummies then return end
	local function scan(c, d)
		for _, k in c:GetChildren() do
			if k:IsA("Model") and k:FindFirstChildOfClass("Humanoid") and any(k.Name, { "dummy", "training", "target" }) then
				attachDummy(k)
			elseif d > 0 and (k:IsA("Folder") or k:IsA("Model")) then
				scan(k, d - 1)
			end
		end
	end
	scan(workspace, 3)
end

---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- game adapters: Hero (Remotes.RunEffectMod → EffectMods.EffectsHandler.<Move>.<Func>(ctrl, assets, char, ...),
-- buffer-encoded Remotes.RemoteEvent via RemoteWrapper), plus generic effect-folder detection
local GAME = { name = "generic", dec = {} }
local HK = { on = false, q = {}, n = 0 }
Self.hk = HK
local fxCall
do
task.spawn(function()
	sec("adapter", function()
		local rm = REP:FindFirstChild("Remotes")
		local fxr = rm and rm:FindFirstChild("RunEffectMod")
		if fxr and REP:FindFirstChild("EffectMods") then
			GAME.name = "Hero"
			GAME.fxRemote = fxr
		end
		for _, n in { "Effects", "Visuals", "VFX", "FX", "Debris", "Fx" } do
			local f = workspace:FindFirstChild(n)
			if f and not f:FindFirstChildOfClass("Humanoid") then GAME.fxFolder = f break end
		end
		local w = REP:FindFirstChild("RemoteWrapper")
		if w then
			for _, m in w:GetChildren() do
				local sh = m:IsA("ModuleScript") and m:FindFirstChild("Shared")
				if sh and sh:IsA("ModuleScript") then
					local ok, mod = pcall(require, m)
					local ok2, sm = pcall(require, sh)
					if ok and ok2 and type(mod) == "table" and typeof(mod.Object) == "Instance" and type(sm) == "table" and type(sm.DecodeData) == "function" then
						GAME.dec[mod.Object] = sm.DecodeData
					end
				end
			end
		end
	end)
end)

local tplCache = setmetatable({}, { __mode = "k" })
local function dumpTpl(f)
	if tplCache[f] then return tplCache[f] end
	local out, n = {}, 0
	local function walk(x, depth, path)
		for _, c in x:GetChildren() do
			if n >= 60 then return end
			local pth = path .. "." .. c.Name
			if c:IsA("BasePart") or c:IsA("Model") or c:IsA("Attachment") or VIS[c.ClassName] then
				local ok, d = pcall(describe, c)
				n = n + 1
				out[#out + 1] = { path = pth, class = c.ClassName, d = ok and d or nil, err = (not ok) and tostring(d) or nil }
			elseif c:IsA("Sound") then
				n = n + 1
				out[#out + 1] = { path = pth, class = "Sound", sound = { id = aid(c.SoundId), volume = rd(c.Volume, 3), speed = rd(c.PlaybackSpeed, 3) } }
			elseif c:IsA("Animation") then
				n = n + 1
				out[#out + 1] = { path = pth, class = "Animation", anim = aid(c.AnimationId) }
			elseif depth < 4 then
				walk(c, depth + 1, pth)
			end
		end
	end
	walk(f, 0, f.Name)
	tplCache[f] = out
	return out
end
local fxSaved = setmetatable({}, { __mode = "k" })
function fxCall(l, n)
	local mod, fnm = tostring(l[1]), tostring(l[2])
	local who, assets, others = nil, nil, {}
	for i = 3, n do
		local v = l[i]
		if typeof(v) == "Instance" then
			local c = chOf(v)
			if c then
				if not who then who = c elseif c ~= who then others[#others + 1] = c end
			elseif not v:IsDescendantOf(workspace) then
				local nd = #v:GetDescendants()
				if nd > 0 and nd > (assets and #assets:GetDescendants() or 0) then assets = v end
			end
		end
	end
	if who and who ~= me() and not inScope(who) then return end
	for _, o in others do if who == me() and o ~= me() then markV(o, "effect") end end
	if Rec.state == "armed" and who == me() and C.StartOnFx then startRec("effect " .. mod .. "." .. fnm, "startup") end
	local o = {}
	for i = 3, n do o[#o + 1] = ser(l[i]) end
	local d = { module = mod, func = fnm, args = { table.unpack(l, 3, n) }, n = n - 2, assets = assets and sp(assets, 6) or nil }
	if assets and C.Templates then
		d.templates = dumpTpl(assets)
		if Rec.state == "recording" and Rec.save and not fxSaved[assets] then
			fxSaved[assets] = true
			local c = saveClone(assets, "TEMPLATE " .. mod .. "." .. fnm)
			if c then d.saved = c.Name end
		end
	end
	log("EFFECT", who, "▶ " .. mod .. "." .. fnm .. (assets and ("  assets " .. sp(assets, 6) .. " (" .. #(d.templates or {}) .. " templates)") or "") ..
		(#o > 0 and ("  (" .. table.concat(o, ", ") .. ")") or ""), d)
end

-- optional executor hooks: TweenService:Create goals and ParticleEmitter:Emit counts (only while armed/recording)
local function fxRel(i)
	if typeof(i) ~= "Instance" or mine(i) then return nil end
	local x, k = i, 0
	while x and k < 8 do
		local ev = FXSET[x]
		if ev then return "fx", ev.model end
		x, k = x.Parent, k + 1
	end
	if GAME.fxFolder and i:IsDescendantOf(GAME.fxFolder) then return "fx" end
	local cam = workspace.CurrentCamera
	if cam and i:IsDescendantOf(cam) then return "fx" end
	if i == LIGHT or i.Parent == LIGHT then return "screen" end
	if i:IsA("GuiObject") and i:IsDescendantOf(PG) then
		local sz = i.Size
		if sz.X.Scale >= 0.9 and sz.Y.Scale >= 0.9 then return "screen" end
		return nil
	end
	local c = chOf(i)
	if c and inScope(c) then return "char", c end
	if i:IsDescendantOf(workspace) then
		local pp = posOf(i)
		if pp and inR(pp) and not i:IsDescendantOf(workspace.Terrain) and (i:IsA("BasePart") or i:IsA("JointInstance") or VIS[i.ClassName] or i:IsA("DataModelMesh") or i:IsA("Decal")) then return "fx" end
	end
	return nil
end
local function lit(v)
	local t = typeof(v)
	if t == "number" then return fn(v, 4)
	elseif t == "boolean" then return tostring(v)
	elseif t == "string" then return qs(v)
	elseif t == "Vector3" then return v3l(v)
	elseif t == "CFrame" then return cfl(v)
	elseif t == "Color3" then return string.format("Color3.fromRGB(%d, %d, %d)", math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255))
	elseif t == "UDim2" then return string.format("UDim2.new(%s, %s, %s, %s)", fn(v.X.Scale, 4), fn(v.X.Offset), fn(v.Y.Scale, 4), fn(v.Y.Offset))
	elseif t == "Vector2" then return string.format("Vector2.new(%s, %s)", fn(v.X), fn(v.Y))
	elseif t == "NumberRange" then return string.format("NumberRange.new(%s, %s)", fn(v.Min, 4), fn(v.Max, 4))
	elseif t == "EnumItem" then return tostring(v)
	end
	return qs(ser(v))
end
local function hkFlush()
	HK.pending = false
	local q = HK.q
	HK.q = {}
	local emits = {}
	for _, it in q do
		local kind, inst = it[1], it[2]
		if inst.Parent or kind == "Emit" then
			local rel, who = fxRel(inst)
			if rel then
				if kind == "Create" then
					local info, goals = it[3], it[4]
					if typeof(info) == "TweenInfo" and type(goals) == "table" and HK.n < 600 then
						HK.n = HK.n + 1
						local gl, gt = {}, {}
						for k, v in goals do
							gl[#gl + 1] = tostring(k) .. " = " .. lit(v)
							gt[#gt + 1] = tostring(k) .. "→" .. ser(v)
						end
						table.sort(gl)
						local d = { kind = "tween", target = sp(inst, 5), class = inst.ClassName, name = inst.Name, time = rd(info.Time, 4), style = info.EasingStyle.Name,
							dir = info.EasingDirection.Name, delay = rd(info.DelayTime, 4), rep = info.RepeatCount, rev = info.Reverses, goals = gl, rel = rel }
						local ev = log(rel == "screen" and "SCREEN" or "TWEEN", who, "⤳ " .. inst.ClassName .. " '" .. sp(inst, 3) .. "' " .. table.concat(gt, ", ") ..
							"  " .. fn(d.time, 3) .. "s " .. d.style .. " " .. d.dir .. (d.delay > 0 and (" delay " .. fn(d.delay, 3)) or "") .. (d.rep ~= 0 and (" ×" .. d.rep) or "") .. (d.rev and " reverses" or ""), d)
						if ev then ev.t = it[5] end
					end
				elseif kind == "Emit" then
					local root = inst
					local x, k = inst.Parent, 0
					while x and x ~= workspace and k < 6 do
						if FXSET[x] or (GAME.fxFolder and x.Parent == GAME.fxFolder) then root = x end
						x, k = x.Parent, k + 1
					end
					local b = emits[root]
					if not b then b = { t = it[5], who = who, list = {}, total = 0 } emits[root] = b end
					local cnt = tonumber(it[3]) or 0
					b.list[#b.list + 1] = { name = inst.Name, count = cnt, path = sp(inst, 3) }
					b.total = b.total + cnt
				end
			end
		end
	end
	for root, b in emits do
		local names = {}
		for i2, x in b.list do
			if i2 > 12 then names[#names + 1] = "…" break end
			names[#names + 1] = x.name .. "×" .. fn(x.count)
		end
		local ev = log("VFX", b.who, "✸ :Emit on " .. #b.list .. " emitter(s) in '" .. sp(root, 3) .. "' total " .. fn(b.total) .. "  " .. table.concat(names, " "),
			{ kind = "emit", root = sp(root, 5), emits = b.list, total = b.total })
		if ev then ev.t = b.t end
	end
end
local function hkPush(kind, inst, a, b2)
	local q = HK.q
	q[#q + 1] = { kind, inst, a, b2, os.clock() }
	if not HK.pending then
		HK.pending = true
		task.defer(g(hkFlush))
	end
end
task.spawn(function()
	sec("hooks", function()
		if not C.Hooks or typeof(hookmetamethod) ~= "function" or typeof(getnamecallmethod) ~= "function" then return end
		local cc = typeof(checkcaller) == "function" and checkcaller or function() return false end
		local wrap = typeof(newcclosure) == "function" and newcclosure or function(f) return f end
		local old
		old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
			if HK.on and not cc() then
				local m = getnamecallmethod()
				if m == "Create" and self == TS then
					local i, info, goals = ...
					if typeof(i) == "Instance" then hkPush("Create", i, info, goals) end
				elseif m == "Emit" and typeof(self) == "Instance" and self.ClassName == "ParticleEmitter" then
					hkPush("Emit", self, (...))
				end
			end
			return old(self, ...)
		end))
		HK.installed = true
		HK.restore = function() pcall(hookmetamethod, game, "__namecall", old) end
	end)
end)
end
local hrems = setmetatable({}, { __mode = "k" })
local rIgnore = lst(C.RIgnore)
local RHINT = { "replication", "replicate", "replicator", "state", "sync", "update", "gameevent", "action" }
local function rSubj(a)
	local function ck(v, d)
		if typeof(v) == "Instance" then return chOf(v) end
		if type(v) == "table" and d < 2 then
			for _, x in v do
				local c = ck(x, d + 1)
				if c then return c end
			end
		end
	end
	for _, x in a do
		local c = ck(x, 0)
		if c then return c end
	end
end
local function rLabel(a)
	for _, x in a do
		if type(x) == "table" then
			for _, k in { "Effect", "effect", "Move", "move", "Name", "name", "Skill", "skill", "Request", "Ability", "Action", "Type" } do
				if type(x[k]) == "string" then return x[k] end
			end
		elseif type(x) == "string" and #x < 40 then
			return x
		end
	end
end
function hookRem(re)
	if hrems[re] then return end
	hrems[re] = true
	re.OnClientEvent:Connect(g(function(...)
		if Rec.state == "idle" then return end
		local a = table.pack(...)
		local l = {}
		for i = 1, a.n do l[i] = a[i] end
		local dec = GAME.dec[re]
		if dec then
			local hb2 = false
			for i = 1, a.n do if typeof(l[i]) == "buffer" then hb2 = true end end
			if hb2 then
				local r = table.pack(pcall(dec, table.unpack(l, 1, a.n)))
				if r[1] then
					l = {}
					for i = 2, r.n do l[i - 1] = r[i] end
					a = { n = r.n - 1 }
				end
			end
		end
		if re == GAME.fxRemote then return fxCall(l, a.n) end
		local rep = C.RepSpy and any(re.Name, RHINT)
		if not rep and (not C.Remotes or any(re.Name, rIgnore)) then return end
		local s = rSubj(l)
		if s and s ~= me() and not inScope(s) then return end
		if s and s ~= me() then markV(s, "remote") end
		if Rec.state == "armed" and C.StartOnRemote and s == me() then startRec("remote " .. re.Name, "startup") end
		local o = {}
		for i = 1, a.n do o[i] = ser(l[i]) end
		local lbl = rLabel(l)
		log(rep and "REPLICATION" or "REMOTE", s, (rep and "⇄ " or "⇠ ") .. re.Name .. (lbl and (" [" .. lbl .. "]") or "") .. " " .. table.concat(o, ", "),
			{ remote = sp(re, 4), class = re.ClassName, label = lbl, args = l, n = a.n, replication = rep or nil })
	end))
end
UI.hookRemote = hookRem

---------------------------------------------------------------------------------------------------
local cam = { fov = 70, run = nil, stable = 0, look = nil, up = nil, ema = 0, shake = nil }
local snapP = setmetatable({}, { __mode = "k" })
local PP = {
	ColorCorrectionEffect = { "Enabled", "Brightness", "Contrast", "Saturation", "TintColor" },
	BlurEffect = { "Enabled", "Size" }, BloomEffect = { "Enabled", "Intensity", "Size", "Threshold" },
	DepthOfFieldEffect = { "Enabled", "FarIntensity", "FocusDistance", "InFocusRadius", "NearIntensity" },
	SunRaysEffect = { "Enabled", "Intensity", "Spread" },
}
local function sig(e)
	local p = PP[e.ClassName]
	if not p then return nil end
	local o = {}
	for _, k in p do o[k] = e[k] end
	return o
end
local function snapPosts()
	for _, r in { LIGHT, workspace.CurrentCamera } do
		if r then for _, e in r:GetChildren() do if PP[e.ClassName] then snapP[e] = sig(e) end end end
	end
end
local function checkPosts()
	if not C.Screen then return end
	for _, r in { LIGHT, workspace.CurrentCamera } do
		if r then
			for _, e in r:GetChildren() do
				if PP[e.ClassName] then
					local o, n = snapP[e], sig(e)
					if o then
						local ch = {}
						for k, v in n do if o[k] ~= v then ch[#ch + 1] = k .. " " .. ser(o[k]) .. "→" .. ser(v) end end
						if #ch > 0 then log("SCREEN", nil, "~ " .. e.ClassName .. " '" .. e.Name .. "': " .. table.concat(ch, ", "), { kind = "change", class = e.ClassName, name = e.Name }) end
					end
					snapP[e] = n
				end
			end
		end
	end
end
local function onScreen(e)
	if Rec.state == "idle" or not C.Screen or mine(e) then return end
	if not (e:IsA("PostEffect") or e:IsA("Atmosphere") or e:IsA("Sky")) then return end
	snapP[e] = sig(e)
	local d = { kind = "added", class = e.ClassName, name = e.Name }
	log("SCREEN", nil, "+ " .. e.ClassName .. " '" .. e.Name .. "'", d)
	local t0 = now()
	local c
	c = e.AncestryChanged:Connect(function(_, p)
		if p == nil then
			c:Disconnect()
			d.lifetime = rd(now() - t0, 3)
			log("SCREEN", nil, "- " .. e.ClassName .. " '" .. e.Name .. "' removed after " .. fn(d.lifetime, 3) .. "s", { kind = "removed", class = e.ClassName, name = e.Name })
		end
	end)
end
local gBatch, gFlush = {}, false
local function onGui(gui)
	if Rec.state == "idle" or not C.Screen or mine(gui) then return end
	if not (gui:IsA("ScreenGui") or gui:IsA("GuiObject")) then return end
	gBatch[gui] = true
	if gFlush then return end
	gFlush = true
	task.defer(g(function()
		gFlush = false
		local b = gBatch
		gBatch = {}
		for i in b do
			local n, skip = i.Parent, false
			while n and n ~= PG do
				if b[n] then skip = true break end
				n = n.Parent
			end
			if not skip and i.Parent then
				local im = {}
				for _, d in i:GetDescendants() do
					if (d:IsA("ImageLabel") or d:IsA("ImageButton")) and #im < 4 then
						local id = aid(d.Image)
						if id then im[#im + 1] = id end
					end
				end
				log("SCREEN", nil, "▢ overlay " .. i.ClassName .. " '" .. i.Name .. "'" .. (#im > 0 and (" images " .. table.concat(im, ", ")) or ""), { kind = "overlay", class = i.ClassName, name = i.Name, images = im })
			end
		end
	end))
end
local function camStep(dt)
	if Rec.state == "idle" or not C.Cam then return end
	local c = workspace.CurrentCamera
	if not c then return end
	local fov = c.FieldOfView
	if math.abs(fov - cam.fov) > 0.15 then
		if not cam.run then cam.run = { t = now(), from = cam.fov, peak = fov } end
		local r = cam.run
		if math.abs(fov - r.from) > math.abs(r.peak - r.from) then r.peak = fov r.peakT = now() end
		cam.stable = 0
	elseif cam.run then
		cam.stable = cam.stable + dt
		if cam.stable > 0.12 then
			local r = cam.run
			cam.run = nil
			local ev = log("CAMERA", nil, "FOV " .. fn(r.from, 1) .. " → " .. fn(r.peak, 1) .. " → " .. fn(fov, 1) .. " over " .. fn(now() - r.t, 2) .. "s",
				{ kind = "fov", from = rd(r.from, 2), peak = rd(r.peak, 2), to = rd(fov, 2), duration = rd(now() - r.t, 3), peakAt = r.peakT and rd(r.peakT - r.t, 3) or 0 })
			if ev then ev.t = r.t end
		end
	end
	cam.fov = fov
	local cf = c.CFrame
	local look, up = cf.LookVector, cf.UpVector
	if cam.look then
		local a = math.deg(math.acos(math.clamp(look:Dot(cam.look), -1, 1)))
		local b = math.deg(math.acos(math.clamp(up:Dot(cam.up), -1, 1)))
		local mag = a + b * 0.5
		local jit = math.abs(mag - cam.ema)
		cam.ema = cam.ema + (mag - cam.ema) * 0.15
		if jit > C.Shake then
			if not cam.shake then cam.shake = { t = now(), peak = 0, n = 0, quiet = 0 } end
			cam.shake.peak = math.max(cam.shake.peak, mag)
			cam.shake.n = cam.shake.n + 1
			cam.shake.quiet = 0
		elseif cam.shake then
			cam.shake.quiet = cam.shake.quiet + dt
			if cam.shake.quiet > 0.12 then
				local s = cam.shake
				cam.shake = nil
				if s.n >= 3 then
					local ev = log("CAMERA", nil, "shake ~" .. fn(now() - s.t - s.quiet, 2) .. "s, strength ~" .. fn(s.peak, 2) .. "°",
						{ kind = "shake", duration = rd(now() - s.t - s.quiet, 3), strength = rd(s.peak, 3) })
					if ev then ev.t = s.t end
				end
			end
		end
	end
	cam.look, cam.up = look, up
end

---------------------------------------------------------------------------------------------------
local lastVel = setmetatable({}, { __mode = "k" })
local acc = 0
local function vsample(r)
	if not r then return nil, 0 end
	local v = r.AssemblyLinearVelocity
	return ldir(v), rd(v.Magnitude, 2)
end
-- one motion sample of a spawned effect (only when something changed)
local function sampleFx(e, t)
	if #e.samples >= 60 then return end
	local ins = e.inst
	local cf = cfOf(ins)
	local s = { t = rd(t - e.born, 3) }
	if cf and Rec.startCF then s.pos = Rec.startCF:ToObjectSpace(cf).Position end
	if ins:IsA("BasePart") then
		s.size = ins.Size
		s.transparency = rd(ins.Transparency, 3)
		s.vel = ldir(gp(ins, "AssemblyLinearVelocity") or Vector3.zero)
		local sm = ins:FindFirstChildOfClass("SpecialMesh")
		if sm then s.scale = sm.Scale end
		local dc = ins:FindFirstChildWhichIsA("Decal")
		if dc then s.decal = rd(dc.Transparency, 3) end
	end
	local last = e.samples[#e.samples]
	if not last or (s.pos and last.pos and (s.pos - last.pos).Magnitude > 0.05) or (s.size and last.size and (s.size - last.size).Magnitude > 0.05) or s.transparency ~= last.transparency
		or (s.scale and last.scale and (s.scale - last.scale).Magnitude > 0.05) or s.decal ~= last.decal then
		e.samples[#e.samples + 1] = s
		e.ev.data.motion = e.samples
	end
end
local function tick()
	local t = now()
	local r = myRoot()
	if r and Rec.startCF and Rec.state == "recording" then
		local lv, sp2 = vsample(r)
		Rec.path[#Rec.path + 1] = { t = rd(t - Rec.t0, 3), pos = Rec.startCF:ToObjectSpace(r.CFrame).Position, vel = lv, speed = sp2 }
		Rec.peak = math.max(Rec.peak or 0, sp2)
		for m, info in Rec.victims do
			local vr = rootOf(m)
			if vr then
				local l = Rec.vpaths[info.name]
				if not l then l = {} Rec.vpaths[info.name] = l end
				if #l < 500 then
					local vlv, vsp = vsample(vr)
					local rel = Rec.startCF:ToObjectSpace(vr.CFrame)
					local dist = rd((vr.Position - r.Position).Magnitude, 2)
					l[#l + 1] = { t = rd(t - Rec.t0, 3), pos = rel.Position, vel = vlv, speed = vsp, dist = dist }
					info.minDist = math.min(info.minDist or 1e9, dist)
					info.peak = math.max(info.peak or 0, vsp)
					local h = m:FindFirstChildOfClass("Humanoid")
					if h then info.hp, info.maxhp = rd(h.Health, 2), rd(h.MaxHealth, 2) end
				end
			end
		end
	end
	if C.Others and Rec.state == "recording" and r and not Rec.noVic then
		for _, p in P:GetPlayers() do
			local c = p.Character
			if c and c ~= me() then
				local cr = rootOf(c)
				if cr and (cr.Position - r.Position).Magnitude <= C.VRadius then markV(c, "proximity") end
			end
		end
		for m in dummies do
			local dr = rootOf(m)
			if dr and (dr.Position - r.Position).Magnitude <= C.VRadius then markV(m, "proximity") end
		end
	end
	if C.Tags then
		for m, info in tracked do
			if m.Parent and inScope(m) then
				local cur = {}
				for _, tg in m:GetTags() do
					cur[tg] = true
					if not info.tags[tg] then log("STATE", m, "+ tag '" .. tg .. "'", { kind = "tagAdded", tag = tg }) end
				end
				for tg in info.tags do
					if not cur[tg] then log("STATE", m, "- tag '" .. tg .. "'", { kind = "tagRemoved", tag = tg }) end
				end
				info.tags = cur
			end
		end
	end
	for tr, a in live do
		local tp = gp(tr, "TimePosition") or 0
		if a.tp and tp < a.tp - 0.15 then
			log("ANIM", a.model, "⤺ " .. (a.ev.data.name or "?") .. " time jump " .. fn(a.tp, 2) .. "s → " .. fn(tp, 2) .. "s", { kind = "timejump", id = a.ev.data.id, from = rd(a.tp, 3), to = rd(tp, 3) })
		end
		a.tp = tp
		if math.abs(tr.Speed - a.speed) > 0.01 then
			log("ANIM", a.model, "⏩ " .. (a.ev.data.name or "?") .. " speed " .. fn(a.speed, 2) .. " → " .. fn(tr.Speed, 2), { kind = "speed", id = a.ev.data.id, from = rd(a.speed, 3), to = rd(tr.Speed, 3) })
			a.speed = tr.Speed
		end
	end
	for i = #logged, 1, -1 do
		local e = logged[i]
		if not e.inst.Parent or t - e.born > 8 then
			table.remove(logged, i)
		elseif t - e.born > 2 then
			sampleFx(e, t)
		end
	end
	checkPosts()
	if Rec.state == "recording" then
		local el = t - Rec.t0
		local busy = false
		for tr, a in live do
			if a.model == me() and not tr.Looped and tr.Priority.Value >= Enum.AnimationPriority.Action.Value then busy = true break end
		end
		local lim = (Rec.adv and Rec.phase == "startup") and math.max(C.IdleStop, 4) or C.IdleStop
		if el > C.MaxLen or (el > C.MinLen and not busy and t - Rec.lastAct > lim) then
			stopRec(el > C.MaxLen and "max length" or "idle")
		end
	end
end

local function hb(dt)
	if Rec.state == "idle" then return end
	-- (young effects every frame: their tweens are usually 0.1-1.5s long)
	local tnow = now()
	for _, e in logged do
		if e.inst.Parent and tnow - e.born <= 2 then sampleFx(e, tnow) end
	end
	local m0 = me()
	for m in tracked do
		if m.Parent and (m == m0 or Rec.victims[m] or (C.Others and inScope(m))) then
			local r = rootOf(m)
			if r and C.Vel then
				local v = r.AssemblyLinearVelocity
				local last = lastVel[m]
				lastVel[m] = v
				if last then
					local sp2 = v.Magnitude
					local prev = last.Magnitude
					local delta = (v - last).Magnitude
					local cross = (prev < C.Phase and sp2 >= C.Phase) or (prev >= C.Phase and sp2 < C.Phase)
					if delta > C.Spike or cross then
						local l = ldir(v)
						local k = cross and (sp2 >= C.Phase and "speedPhaseStart" or "speedPhaseEnd") or "impulse"
						log("VELOCITY", m, (k == "impulse" and "⚡ jump " or (k == "speedPhaseStart" and "▶ moving " or "◼ stopped ")) .. dw(l) .. " (|v| " .. fn(sp2, 1) .. ", Δ" .. fn(delta, 1) .. ")",
							{ kind = k, localVelocity = l, speed = rd(sp2, 2), delta = rd(delta, 2) })
					end
				end
			end
		end
	end
	acc = acc + dt
	if acc >= 0.1 then
		acc = 0
		g(tick)()
	end
end

---------------------------------------------------------------------------------------------------
local function scanChars()
	for _, p in P:GetPlayers() do if p.Character then trackChar(p.Character) end end
	local function scan(c, d)
		for _, k in c:GetChildren() do
			if k:IsA("Model") and k:FindFirstChildOfClass("Humanoid") then
				trackChar(k)
			elseif d > 0 and (k:IsA("Folder") or k:IsA("Model")) then
				scan(k, d - 1)
			end
		end
	end
	scan(workspace, 2)
end
local function scanHB()
	if not myRoot() then return end
	local function scan(c, d)
		for _, k in c:GetChildren() do
			if k:IsA("BasePart") and isHB(k.Name) and inR(k.Position) then
				hookHB(k, chOf(k))
			elseif d > 0 and (k:IsA("Folder") or k:IsA("Model")) then
				scan(k, d - 1)
			end
		end
	end
	scan(workspace, 4)
end
function setState(s)
	Rec.state = s
	HK.on = s ~= "idle"
	if s == "armed" or s == "recording" then HK.n = 0 end
	if Hooks.onState then task.spawn(g(Hooks.onState)) end
end
local scanned = false
function arm()
	if Rec.state == "recording" then return end
	if not scanned then
		scanned = true
		task.spawn(g(function()
			for _, r in { workspace, SND, PG } do
				for _, d in r:GetDescendants() do if d:IsA("Sound") then hookSnd(d) end end
			end
		end))
	end
	scanChars()
	scanDummies()
	scanHB()
	Rec.pre = {}
	setState("armed")
end
local function saveFolder(n)
	if not C.Clone then return nil end
	if not LoggedRoot or not LoggedRoot.Parent then
		LoggedRoot = REP:FindFirstChild("MoveLogger_Logged") or Instance.new("Folder")
		LoggedRoot.Name = "MoveLogger_Logged"
		LoggedRoot.Parent = REP
	end
	local f = Instance.new("Folder")
	f.Name = n
	f.Parent = LoggedRoot
	return f
end

function startRec(reason, phase)
	if Rec.state == "recording" then return end
	if Rec.state == "idle" then arm() end
	scanChars()
	scanDummies()
	scanHB()
	Rec.count = Rec.count + 1
	Rec.t0 = now()
	Rec.events, Rec.victims, Rec.path, Rec.vpaths = {}, {}, {}, {}
	Rec.reason = reason or "manual"
	Rec.adv = C.Adv or phase == "startup"
	Rec.phase = (Rec.adv and phase ~= "hit") and "startup" or "hit"
	Rec.noVic = Rec.adv and Rec.phase == "startup"
	Rec.hitAt = Rec.phase == "hit" and Rec.t0 or nil
	local r = myRoot()
	Rec.startCF = r and r.CFrame or nil
	Rec.startVel = r and ldir(r.AssemblyLinearVelocity) or Vector3.zero
	Rec.startSpd = r and rd(r.AssemblyLinearVelocity.Magnitude, 2) or 0
	Rec.peak = Rec.startSpd
	logged, clones, sigs = {}, 0, {}
	Rec.save = saveFolder("Rec" .. Rec.count)
	cam.fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
	cam.run, cam.shake = nil, nil
	snapPosts()
	local cut = Rec.t0 - ((phase == "hit" and reason == "hit") and math.max(C.Preroll, C.HitPreroll or 0) or C.Preroll)
	for _, ev in Rec.pre do if ev.t >= cut then Rec.events[#Rec.events + 1] = ev end end
	Rec.pre = {}
	Rec.lastAct = now()
	setState("recording")
	snapAll()
	if Rec.phase == "startup" then log("MARKER", me(), "══ STARTUP PHASE ══ (no victims)", { kind = "startupPhase" }) end
end

function hitPhase()
	if Rec.state ~= "recording" then startRec("hit", "hit") return end
	if not Rec.adv or Rec.phase ~= "startup" then toast("already in the hit phase") return end
	Rec.hitAt = now()
	Rec.phase = "hit"
	Rec.noVic = false
	Rec.lastAct = now()
	Rec.victims = {}
	log("MARKER", me(), "══ HIT PHASE ══", { kind = "hitPhase" })
	scanChars()
	scanDummies()
	scanHB()
	snapAll()
	toast("hit phase recording")
	if Hooks.onState then task.spawn(g(Hooks.onState)) end
end

local function phases(path)
	local o, cur = {}, nil
	for _, p in path do
		local s = p.speed or 0
		if s >= C.Phase then
			if not cur then cur = { from = p.t, peak = s, peakAt = p.t, dir = p.vel } end
			if s > cur.peak then cur.peak = s cur.peakAt = p.t cur.dir = p.vel end
			cur.to = p.t
		elseif cur then
			if cur.to - cur.from >= 0.1 then o[#o + 1] = cur end
			cur = nil
		end
	end
	if cur and (cur.to or cur.from) - cur.from >= 0.1 then o[#o + 1] = cur end
	return o
end

local function finish(reason)
	local evs = Rec.events
	table.sort(evs, function(a, b) return a.t < b.t end)
	local sd = (Rec.hitAt and Rec.hitAt > Rec.t0) and (Rec.hitAt - Rec.t0) or nil
	for _, ev in evs do
		ev.rt = ev.t - Rec.t0
		if sd then ev.phase = ev.rt < sd and "startup" or "hit" end
		if ev.model and Rec.victims[ev.model] then ev.victim = true end
	end
	local dur = 0
	for _, ev in evs do dur = math.max(dur, ev.rt) end
	for _, ph in phases(Rec.path) do
		local ev = log("VELOCITY", me(), "▶ motion " .. fn(ph.to - ph.from, 2) .. "s, peak " .. fn(ph.peak, 1) .. " studs/s " .. dw(ph.dir),
			{ kind = "velocityPhase", localVelocity = ph.dir, peakSpeed = rd(ph.peak, 2), duration = rd(ph.to - ph.from, 3) })
		if ev then
			ev.rt = ph.from
			if sd then ev.phase = ev.rt < sd and "startup" or "hit" end
			evs[#evs + 1] = ev
		end
	end
	table.sort(evs, function(a, b) return a.rt < b.rt end)
	local name = UI.nameBox and UI.nameBox.Text ~= "" and UI.nameBox.Text or nil
	if not name then
		for _, ev in evs do
			if ev.cat == "REMOTE" and ev.data.label and (ev.model == me() or ev.model == nil) then name = ev.data.label break end
		end
	end
	if not name then
		for _, ev in evs do
			if ev.cat == "ANIM" and ev.who == "YOU" and ev.data.id and not ev.data.kind then
				name = ev.data.name ~= "Animation" and ev.data.name or ("anim " .. ev.data.id)
				break
			end
		end
	end
	name = name or ("Recording " .. Rec.count)
	local vics, vinfo = {}, {}
	for m, v in Rec.victims do
		vics[#vics + 1] = v.name
		local why = {}
		for k in v do if type(k) == "string" and k ~= "name" then why[#why + 1] = k end end
		vinfo[v.name] = { reasons = why, minDist = v.minDist, peak = v.peak, hp = v.hp, maxhp = v.maxhp, firstAt = rd(v.firstAt - Rec.t0, 3), track = Rec.vpaths[v.name] }
	end
	local rec = { index = Rec.count, name = name, duration = dur, events = evs, victims = vics, vinfo = vinfo, reason = reason,
		startReason = Rec.reason, path = Rec.path, startVel = Rec.startVel, startSpd = Rec.startSpd, peak = Rec.peak,
		startup = sd, advanced = Rec.adv and sd ~= nil, save = Rec.save and Rec.save:GetFullName() or nil,
		character = me() and me().Name or "?", placeId = game.PlaceId, when = os.date("%Y-%m-%d %H:%M:%S") }
	if Rec.save then Rec.save.Name = "Rec" .. Rec.count .. " " .. string.gsub(name, "[^%w _%-]", "") end
	Hist[#Hist + 1] = rec
	while #Hist > 40 do table.remove(Hist, 1) end
	Sel = #Hist
	Rec.adv, Rec.noVic, Rec.hitAt = false, false, nil
	if Hooks.onFinish then task.spawn(g(Hooks.onFinish), rec) end
end

function stopRec(reason)
	if Rec.state ~= "recording" then setState("idle") return end
	flush()
	Rec.state = "idle"
	finish(reason or "manual")
	if C.AutoArm and reason ~= "manual" then arm() else setState("idle") end
end

---------------------------------------------------------------------------------------------------
local Out = {}
local function evFilter(rec, o)
	local l = {}
	for _, ev in rec.events do
		if SHOW[ev.cat] and (not o or not o.vicOnly or ev.victim) and (not o or not o.youOnly or ev.who == "YOU" or ev.who == "WORLD") then
			if not o or not o.search or o.search == "" or string.find(string.lower(ev.text .. " " .. ev.who), string.lower(o.search), 1, true) then
				l[#l + 1] = ev
			end
		end
	end
	return l
end
local function infer(rec)
	local hits = {}
	for _, ev in rec.events do
		if (ev.cat == "HIT" and ev.data.offset and (ev.data.amount or 0) > 0) or (ev.cat == "HITBOX" and ev.data.kind == "touch" and ev.data.victim and ev.data.offset) then
			hits[#hits + 1] = ev
		end
	end
	local cl = {}
	for _, h in hits do
		local c = cl[#cl]
		if c and h.rt - c.last <= 0.08 then
			c.hits[#c.hits + 1] = h
			c.last = h.rt
		else
			cl[#cl + 1] = { first = h.rt, last = h.rt, hits = { h } }
		end
	end
	local o = {}
	for _, c in cl do
		local sum = Vector3.new()
		for _, h in c.hits do sum = sum + h.data.offset end
		local cen = sum / #c.hits
		local ext = Vector3.new()
		for _, h in c.hits do
			local d = h.data.offset - cen
			local half = (h.data.size or h.data.victimExtents or Vector3.new(4, 5, 2)) / 2
			ext = Vector3.new(math.max(ext.X, math.abs(d.X) + half.X), math.max(ext.Y, math.abs(d.Y) + half.Y), math.max(ext.Z, math.abs(d.Z) + half.Z))
		end
		local size = Vector3.new(math.max(ext.X * 2, 4), math.max(ext.Y * 2, 5), math.max(ext.Z * 2, 4))
		local dmg, names, srcs = 0, {}, {}
		for _, h in c.hits do
			dmg = dmg + (h.data.amount or 0)
			local tg = h.data.target or h.data.victim
			if tg and not table.find(names, tg) then names[#names + 1] = tg end
			if h.cat == "HITBOX" and not table.find(srcs, h.data.name) then srcs[#srcs + 1] = h.data.name end
		end
		o[#o + 1] = { at = c.first, offset = cen, size = size, hits = #c.hits, damage = dmg, targets = names, sources = srcs }
	end
	return o
end
local function seqLua(s)
	if not s then return "nil" end
	if s.kind == "color3" then return string.format("Color3.fromRGB(%d, %d, %d)", s.rgb[1], s.rgb[2], s.rgb[3]) end
	if s.kind == "enum" then return "Enum." .. tostring(s.enumType) .. "." .. tostring(s.value) end
	if s.kind == "number" then
		local o = {}
		for _, k in s.keypoints do o[#o + 1] = string.format("NumberSequenceKeypoint.new(%s, %s, %s)", fn(k.time, 4), fn(k.value, 4), fn(k.envelope, 4)) end
		return "NumberSequence.new({ " .. table.concat(o, ", ") .. " })"
	end
	if s.kind == "color" then
		local o = {}
		for _, k in s.keypoints do
			local c = k.rgb or { 255, 255, 255 }
			o[#o + 1] = string.format("ColorSequenceKeypoint.new(%s, Color3.fromRGB(%d, %d, %d))", fn(k.time, 4), c[1], c[2], c[3])
		end
		return "ColorSequence.new({ " .. table.concat(o, ", ") .. " })"
	end
	if s.kind == "range" then return string.format("NumberRange.new(%s, %s)", fn(s.min, 4), fn(s.max, 4)) end
	return "nil"
end
local function emitLua(e, v)
	local o = {}
	local function a(s) o[#o + 1] = s end
	a(string.format("\t\tlocal %s = Instance.new(%q)", v, e.class))
	a(string.format("\t\t%s.Name = %s", v, qs(e.name)))
	local skip = { class = true, name = true, assets = true, colors = true, hostName = true, hostClass = true, hostPath = true,
		hostSize = true, hostMaterial = true, hostTransparency = true, hostColor = true, hostColorRgb = true, hostShape = true,
		hostOffset = true, hostParent = true, hostTexture = true, hostMeshId = true, attributes = true }
	for k, x in e do
		if not skip[k] then
			if type(x) == "table" and x.kind then
				a(string.format("\t\t%s.%s = %s", v, k, seqLua(x)))
			elseif type(x) == "table" and #x == 3 and type(x[1]) == "number" then
				a(string.format("\t\t%s.%s = Vector3.new(%s, %s, %s)", v, k, fn(x[1], 3), fn(x[2], 3), fn(x[3], 3)))
			elseif type(x) == "table" and x.path then
				a(string.format("\t\t-- %s.%s = %s (%s)", v, k, x.path, x.class or "?"))
			elseif type(x) == "number" then
				a(string.format("\t\t%s.%s = %s", v, k, fn(x, 4)))
			elseif type(x) == "string" then
				if isAsset(k, x) then a(string.format("\t\t%s.%s = %s", v, k, qs(x))) else a(string.format("\t\t-- %s.%s = %s", v, k, qs(x))) end
			elseif type(x) == "boolean" then
				a(string.format("\t\t%s.%s = %s", v, k, tostring(x)))
			end
		end
	end
	for k, x in e.attributes or {} do
		if type(x) == "number" or type(x) == "boolean" or type(x) == "string" then
			a(string.format("\t\t%s:SetAttribute(%s, %s)", v, qs(k), type(x) == "string" and qs(x) or tostring(x)))
		end
	end
	return table.concat(o, "\n")
end
local function div() return string.rep("─", 24) .. " HIT " .. string.rep("─", 24) end

function Out.timeline(rec, o)
	local L = { string.format("MOVE #%d · %s · %ss · %d events · %s", rec.index, rec.name, fn(rec.duration, 3), #rec.events, rec.when),
		string.format("you: %s · victims: %s · started by %s · start speed %s, peak %s", rec.character, #rec.victims > 0 and table.concat(rec.victims, ", ") or "none",
			rec.startReason or "?", fn(rec.startSpd or 0, 1), fn(rec.peak or 0, 1)) }
	if rec.startup then L[#L + 1] = string.format("startup %ss, hit at %ss", fn(rec.startup, 3), fn(rec.startup, 3)) end
	L[#L + 1] = string.rep("─", 72)
	local shown = false
	for _, ev in evFilter(rec, o) do
		if rec.startup and not shown and ev.rt >= rec.startup then
			L[#L + 1] = div()
			shown = true
		end
		L[#L + 1] = string.format("%+8.3f  %-10s %-10s %s", ev.rt, ev.cat, string.sub(ev.who, 1, 10), ev.text)
	end
	return table.concat(L, "\n")
end

function Out.summary(rec)
	local L = {}
	local function a(s) L[#L + 1] = s end
	a(string.format("MOVE #%d · %s · %ss · you: %s · victims: %s", rec.index, rec.name, fn(rec.duration, 3), rec.character, #rec.victims > 0 and table.concat(rec.victims, ", ") or "none"))
	a("game adapter: " .. GAME.name .. " · tween/emit hooks: " .. (HK.installed and "on" or "off (executor has no hookmetamethod)"))
	local function sect(title, pred, f)
		local it = {}
		for _, ev in rec.events do if pred(ev) then it[#it + 1] = f(ev) end end
		if #it > 0 then
			a("")
			a("■ " .. title .. " (" .. #it .. ")")
			for _, s in it do a("  " .. s) end
		end
	end
	local function at(e) return string.format("%6.3f", e.rt) end
	local function st(e) return rec.startup ~= nil and e.phase == "startup" end
	local function ht(e) return rec.startup == nil or e.phase == "hit" end
	if rec.startup then
		sect("Startup · animations", function(e) return st(e) and e.cat == "ANIM" and e.who == "YOU" and not e.data.kind end, function(e)
			return at(e) .. "  rbxassetid://" .. e.data.id .. " " .. e.data.name
		end)
		sect("Startup · other", function(e) return st(e) and (e.cat == "VFX" or e.cat == "SOUND" or e.cat == "HITBOX" or e.cat == "VELOCITY" or e.cat == "MOVE") end, function(e)
			return at(e) .. "  " .. e.cat .. "  " .. e.text
		end)
		a("")
		a(div())
	end
	sect("Your animations", function(e) return ht(e) and e.cat == "ANIM" and e.who == "YOU" and not e.data.kind end, function(e)
		local mk = {}
		for _, m in e.data.markers or {} do mk[#mk + 1] = m.name .. "@" .. fn(m.time, 3) end
		return string.format("%s  rbxassetid://%s  %s  speed %s  length %ss  played %ss%s", at(e), e.data.id, e.data.name, fn(e.data.speed),
			fn(e.data.length or 0, 3), fn(e.data.played or 0, 3), #mk > 0 and ("  markers: " .. table.concat(mk, ", ")) or "")
	end)
	sect("Animation events", function(e) return ht(e) and (e.cat == "MARKER" or (e.cat == "ANIM" and e.data.kind)) end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect("Velocity", function(e) return ht(e) and e.cat == "VELOCITY" end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect("Sounds", function(e) return ht(e) and e.cat == "SOUND" end, function(e)
		return string.format("%s  rbxassetid://%s  %s  vol %s pitch %s  on %s%s", at(e), e.data.id, e.data.name, fn(e.data.volume), fn(e.data.speed), e.data.parent,
			e.data.played and ("  (" .. fn(e.data.played, 2) .. "s)") or "")
	end)
	sect("Effects", function(e) return ht(e) and e.cat == "VFX" and not e.data.kind end, function(e)
		local d = e.data
		local em = {}
		for _, x in d.emitters or {} do em[#em + 1] = x.name .. "{" .. eText(x) .. "}" end
		local ms, as, co = {}, {}, {}
		for _, x in d.meshes or {} do ms[#ms + 1] = mText(x) end
		for _, x in d.assets or {} do as[#as + 1] = x.property .. "=" .. tostring(x.id or x.raw) end
		for _, x in d.colors or {} do co[#co + 1] = tostring(x.hex) end
		return string.format("%s  %s '%s' in %s host %s%s%s%s%s%s%s", at(e), d.class, d.name, d.path, d.size and v3s(d.size) or "?",
			#em > 0 and ("  emitters " .. table.concat(em, " ")) or "", #ms > 0 and ("  meshes " .. table.concat(ms, ", ")) or "",
			#as > 0 and ("  assets " .. table.concat(as, ", ")) or "", #co > 0 and ("  colors " .. table.concat(co, " ")) or "",
			d.offset and ("  at " .. v3s(d.offset)) or "", d.lifetime and ("  lived " .. fn(d.lifetime, 2) .. "s") or "")
	end)
	sect("Effect calls", function(e) return e.cat == "EFFECT" end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect(":Emit calls", function(e) return e.cat == "VFX" and e.data.kind == "emit" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Tweens", function(e) return e.cat == "TWEEN" or (e.cat == "SCREEN" and e.data.kind == "tween") end, function(e) return at(e) .. "  " .. e.text end)
	do
		local seen, any2 = {}, false
		for _, ev in rec.events do
			if ev.cat == "EFFECT" and ev.data.templates and not seen[ev.data.assets] then
				seen[ev.data.assets] = true
				if not any2 then a("") a("■ Effect templates (asset folders the server handed the effect module)") any2 = true end
				a("  " .. ev.data.module .. "." .. ev.data.func .. " ← " .. tostring(ev.data.assets) .. (ev.data.saved and ("  [cloned: " .. ev.data.saved .. "]") or ""))
				for _, t in ev.data.templates do
					local d = t.d
					if t.sound then
						a(string.format("    %s  Sound rbxassetid://%s vol %s pitch %s", t.path, tostring(t.sound.id), fn(t.sound.volume), fn(t.sound.speed)))
					elseif t.anim then
						a(string.format("    %s  Animation rbxassetid://%s", t.path, tostring(t.anim)))
					elseif d then
						local em = {}
						for _, x in d.emitters or {} do em[#em + 1] = x.name .. "{" .. eText(x) .. "}" end
						for _, x in d.beams or {} do em[#em + 1] = "beam " .. x.name .. "{" .. eText(x) .. "}" end
						for _, x in d.trails or {} do em[#em + 1] = "trail " .. x.name .. "{" .. eText(x) .. "}" end
						local ms = {}
						for _, x in d.meshes or {} do ms[#ms + 1] = mText(x) end
						a(string.format("    %s  %s size %s%s%s", t.path, t.class, d.size and v3s(d.size) or "?", #ms > 0 and ("  meshes " .. table.concat(ms, ", ")) or "",
							#em > 0 and ("  " .. table.concat(em, " ")) or ""))
					else
						a("    " .. t.path .. "  " .. t.class .. "  (describe failed: " .. tostring(t.err) .. ")")
					end
				end
			end
		end
	end
	sect("Hitbox parts", function(e) return ht(e) and e.cat == "HITBOX" and e.data.kind ~= "touch" end, function(e)
		return string.format("%s  '%s' (%s/%s) size %s offset %s%s", at(e), e.data.name, e.data.hitboxKind, e.data.kind or "add", e.data.size and v3s(e.data.size) or "?",
			e.data.offset and v3s(e.data.offset) or "?", e.data.lifetime and ("  lived " .. fn(e.data.lifetime, 3) .. "s") or "")
	end)
	sect("Hitbox touches", function(e) return e.cat == "HITBOX" and e.data.kind == "touch" end, function(e)
		return at(e) .. "  '" .. e.data.name .. "' touched " .. e.data.touched .. (e.data.victim and (" [VICTIM " .. e.data.victim .. "]") or "") ..
			" offset " .. (e.data.offset and v3s(e.data.offset) or "?") .. " " .. fn(e.data.distance or 0, 1) .. " studs"
	end)
	local inf = infer(rec)
	if #inf > 0 then
		a("")
		a("■ Inferred hitboxes (" .. #inf .. ")")
		for _, h in inf do a(string.format("  %6.3f offset %s size ≥ %s %d contact(s) %s dmg on %s", h.at, v3s(h.offset), v3s(h.size), h.hits, fn(h.damage, 1), table.concat(h.targets, ", "))) end
	end
	sect("Movement", function(e) return ht(e) and e.cat == "MOVE" end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	if #rec.path > 1 then
		a("")
		a("■ Your displacement: " .. dw(rec.path[#rec.path].pos) .. "  (fwd = -Z)")
	end
	sect("Damage", function(e) return e.cat == "HIT" end, function(e) return at(e) .. "  " .. e.text end)
	if #rec.victims > 0 then
		a("")
		a("■ Victims")
		for n, i in rec.vinfo or {} do
			a(string.format("  %s — first %ss, closest %s, peak speed %s, hp %s/%s, by %s", n, fn(i.firstAt or 0, 2), fn(i.minDist or 0, 1),
				fn(i.peak or 0, 1), fn(i.hp or 0, 1), fn(i.maxhp or 0, 1), table.concat(i.reasons or {}, "+")))
		end
	end
	sect("Victim reactions", function(e) return e.victim and (e.cat == "ANIM" or e.cat == "STATE" or e.cat == "VELOCITY") end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect("Your states", function(e) return e.who == "YOU" and e.cat == "STATE" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Camera", function(e) return e.cat == "CAMERA" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Screen", function(e) return e.cat == "SCREEN" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Remotes", function(e) return e.cat == "REMOTE" or e.cat == "REPLICATION" end, function(e) return at(e) .. "  " .. e.text end)
	return table.concat(L, "\n")
end

function Out.moveTable(rec)
	local L = {}
	local function a(s) L[#L + 1] = s end
	local function tm(t) return fn(math.max(t, 0), 3) end
	a("-- Move #" .. rec.index .. " · " .. rec.name .. " · " .. rec.when)
	a("-- times from start · offsets/velocities local to you (fwd = -Z) · game adapter: " .. GAME.name)
	if rec.startup then a("-- ADVANCED: startup ends at " .. tm(rec.startup) .. "s, Phase = \"hit\" from there") end
	a("return {")
	a("\tIndex = " .. rec.index .. ",")
	a("\tName = " .. qs(rec.name) .. ",")
	a("\tDuration = " .. tm(rec.duration) .. ",")
	if rec.startup then a("\tStartupDuration = " .. tm(rec.startup) .. ",") end
	a("\tStartLocalVelocity = " .. v3l(rec.startVel or Vector3.zero) .. ",")
	a("\tPeakSpeed = " .. fn(rec.peak or 0, 3) .. ",")
	local function tag(ev, s)
		return rec.startup and (string.gsub(s, "^{ ", "{ Phase = " .. qs(ev.phase or "hit") .. ", ", 1)) or s
	end
	local function list(title, pred, f)
		a("\t" .. title .. " = {")
		for _, ev in rec.events do if pred(ev) then a("\t\t" .. tag(ev, f(ev)) .. ",") end end
		a("\t},")
	end
	list("Animations", function(e) return e.cat == "ANIM" and e.who == "YOU" and not e.data.kind end, function(e)
		local mk = {}
		for _, m in e.data.markers or {} do mk[#mk + 1] = string.format("{ Name = %s, Time = %s }", qs(m.name), fn(m.time, 3)) end
		return string.format("{ At = %s, Id = \"rbxassetid://%s\", Name = %s, Priority = %q, Speed = %s, Length = %s, Played = %s%s }", tm(e.rt), e.data.id, qs(e.data.name),
			e.data.priority, fn(e.data.speed, 3), fn(e.data.length or 0, 3), fn(e.data.played or 0, 3), #mk > 0 and (", Markers = { " .. table.concat(mk, ", ") .. " }") or "")
	end)
	list("AnimationEvents", function(e) return (e.cat == "MARKER" or (e.cat == "ANIM" and e.data.kind)) and e.who == "YOU" end, function(e)
		return string.format("{ At = %s, Kind = %q, Name = %s, AnimTime = %s, Param = %s }", tm(e.rt), e.data.kind or "marker", qs(e.data.name or e.data.id or "?"), fn(e.data.at or 0, 3), qs(e.data.param or ""))
	end)
	a("\tVelocity = {")
	local stp = math.max(1, math.floor(math.max(#rec.path, 1) / 80))
	for i = 1, #rec.path, stp do
		local p = rec.path[i]
		if p.vel then a(string.format("\t\t{ At = %s, LocalVelocity = %s, Speed = %s },", tm(p.t), v3l(p.vel), fn(p.speed or 0, 2))) end
	end
	a("\t},")
	a("\tVelocityPhases = {")
	for _, ph in phases(rec.path) do
		a(string.format("\t\t{ From = %s, To = %s, LocalVelocity = %s, PeakSpeed = %s },", tm(ph.from), tm(ph.to), v3l(ph.dir), fn(ph.peak, 2)))
	end
	a("\t},")
	list("Sounds", function(e) return e.cat == "SOUND" and not e.victim end, function(e)
		return string.format("{ At = %s, Id = \"rbxassetid://%s\", Name = %s, Volume = %s, PlaybackSpeed = %s, TimePosition = %s, Parent = %s, Duration = %s, RollOffMode = %q }",
			tm(e.rt), e.data.id, qs(e.data.name), fn(e.data.volume, 3), fn(e.data.speed, 3), fn(e.data.timePosition, 3), qs(e.data.parent), fn(e.data.played or e.data.length or 0, 3), e.data.rollOffMode or "Inverse")
	end)
	list("Effects", function(e) return e.cat == "VFX" and not e.data.kind end, function(e)
		local d = e.data
		local as, co = {}, {}
		for _, x in d.assets or {} do as[#as + 1] = string.format("{ Property = %s, Id = %s, Raw = %s }", qs(x.property), qs(x.id or ""), qs(x.raw)) end
		for _, x in d.colors or {} do co[#co + 1] = string.format("{ Property = %s, Hex = %s }", qs(x.property), qs(x.hex)) end
		local mo = {}
		local ms = d.motion or {}
		local step = math.max(1, math.floor(#ms / 10))
		for k = 1, #ms, step do
			local x = ms[k]
			mo[#mo + 1] = string.format("{ T = %s%s%s%s%s%s }", fn(x.t, 3), x.pos and (", Offset = " .. v3l(x.pos)) or "", x.size and (", Size = " .. v3l(x.size)) or "",
				x.transparency and (", Transparency = " .. fn(x.transparency, 3)) or "", x.scale and (", MeshScale = " .. v3l(x.scale)) or "", x.decal and (", DecalTransparency = " .. fn(x.decal, 3)) or "")
		end
		if #ms > 1 and (#ms - 1) % step ~= 0 then
			local x = ms[#ms]
			mo[#mo + 1] = string.format("{ T = %s%s%s%s%s%s }", fn(x.t, 3), x.pos and (", Offset = " .. v3l(x.pos)) or "", x.size and (", Size = " .. v3l(x.size)) or "",
				x.transparency and (", Transparency = " .. fn(x.transparency, 3)) or "", x.scale and (", MeshScale = " .. v3l(x.scale)) or "", x.decal and (", DecalTransparency = " .. fn(x.decal, 3)) or "")
		end
		local at = {}
		for k, x in d.attributes or {} do at[#at + 1] = string.format("[%s] = %s", qs(k), type(x) == "string" and qs(x) or tostring(x)) end
		local mm = {}
		for _, x in d.meshes or {} do mm[#mm + 1] = mLua(x) end
		return string.format("{ At = %s, Name = %s, Class = %q, Folder = %s, Offset = %s, HostSize = %s, HostTexture = %s, HostMeshId = %s, Lifetime = %s, EmitterCount = %d, BeamCount = %d, TrailCount = %d, Assets = { %s }, Colors = { %s }%s%s%s%s%s }",
			tm(e.rt), qs(d.name), d.class, qs(d.folder or "?"), d.offsetCF and cfl(d.offsetCF) or "CFrame.new()", d.size and v3l(d.size) or "Vector3.one",
			qs(d.hostTexture or ""), qs(d.hostMeshId or ""), fn(d.lifetime or 0, 3), #(d.emitters or {}), #(d.beams or {}), #(d.trails or {}), table.concat(as, ", "), table.concat(co, ", "),
			d.saved and (", Saved = " .. qs(d.saved)) or "", d.weldedTo and (", WeldedTo = " .. qs(d.weldedTo)) or "",
			#at > 0 and (", Attributes = { " .. table.concat(at, ", ") .. " }") or "", #mo > 0 and (", Motion = { " .. table.concat(mo, ", ") .. " }") or "", #mm > 0 and (", Meshes = { " .. table.concat(mm, ", ") .. " }") or "")
	end)
	a("\tEmitterDumps = {")
	local ei = 0
	for _, ev in rec.events do
		if ev.cat == "VFX" and not ev.data.kind then
			ei = ei + 1
			a(string.format("\t\t[%d] = { -- %s '%s' at %ss", ei, ev.data.class, ev.data.name, tm(ev.rt)))
			for _, em in ev.data.emitters or {} do
				a("\t\t\t{ -- EMITTER on part of size " .. (em.hostSize and v3l(Vector3.new(em.hostSize[1], em.hostSize[2], em.hostSize[3])) or "?"))
				a(emitLua(em, "em"))
				a("\t\t\t},")
			end
			for _, em in ev.data.beams or {} do a("\t\t\t{ -- BEAM") a(emitLua(em, "bm")) a("\t\t\t},") end
			for _, em in ev.data.trails or {} do a("\t\t\t{ -- TRAIL") a(emitLua(em, "tr")) a("\t\t\t},") end
			a("\t\t},")
		end
	end
	a("\t},")
	list("EffectCalls", function(e) return e.cat == "EFFECT" end, function(e)
		return string.format("{ At = %s, Who = %s, Module = %s, Func = %s, Assets = %s, Args = %s%s }", tm(e.rt), qs(e.who), qs(e.data.module), qs(e.data.func),
			qs(e.data.assets or ""), qs(ser(e.data.args)), e.data.saved and (", Saved = " .. qs(e.data.saved)) or "")
	end)
	list("Emits", function(e) return e.cat == "VFX" and e.data.kind == "emit" end, function(e)
		local l2 = {}
		for _, x in e.data.emits or {} do l2[#l2 + 1] = string.format("{ %s, %s }", qs(x.path), fn(x.count)) end
		return string.format("{ At = %s, Root = %s, Total = %s, Emitters = { %s } }", tm(e.rt), qs(e.data.root), fn(e.data.total), table.concat(l2, ", "))
	end)
	list("Tweens", function(e) return e.cat == "TWEEN" or (e.cat == "SCREEN" and e.data.kind == "tween") end, function(e)
		local d = e.data
		return string.format("{ At = %s, Target = %s, Class = %q, Info = TweenInfo.new(%s, Enum.EasingStyle.%s, Enum.EasingDirection.%s, %d, %s, %s), Goals = { %s } }",
			tm(e.rt), qs(d.target), d.class, fn(d.time, 4), d.style, d.dir, d.rep or 0, tostring(d.rev or false), fn(d.delay or 0, 4), table.concat(d.goals or {}, ", "))
	end)
	a("\tTemplates = {")
	do
		local seen = {}
		for _, ev in rec.events do
			if ev.cat == "EFFECT" and ev.data.templates and not seen[ev.data.assets] then
				seen[ev.data.assets] = true
				a("\t\t[" .. qs(ev.data.assets) .. "] = { -- " .. ev.data.module .. "." .. ev.data.func)
				for _, t in ev.data.templates do
					local d = t.d
					if t.sound then
						a(string.format("\t\t\t{ Path = %s, Class = \"Sound\", Id = \"rbxassetid://%s\", Volume = %s, PlaybackSpeed = %s },", qs(t.path), tostring(t.sound.id), fn(t.sound.volume, 3), fn(t.sound.speed, 3)))
					elseif t.anim then
						a(string.format("\t\t\t{ Path = %s, Class = \"Animation\", Id = \"rbxassetid://%s\" },", qs(t.path), tostring(t.anim)))
					elseif d then
						a(string.format("\t\t\t{ Path = %s, Class = %q, Size = %s, HostTexture = %s, HostMeshId = %s, EmitterCount = %d, BeamCount = %d, TrailCount = %d,",
							qs(t.path), t.class, d.size and v3l(d.size) or "nil", qs(d.hostTexture or ""), qs(d.hostMeshId or ""), #(d.emitters or {}), #(d.beams or {}), #(d.trails or {})))
						for _, x in d.meshes or {} do a("\t\t\t\t" .. mLua(x) .. ", -- MESH") end
						for _, em in d.emitters or {} do a("\t\t\t\t{ -- EMITTER") a(emitLua(em, "em")) a("\t\t\t\t},") end
						for _, em in d.beams or {} do a("\t\t\t\t{ -- BEAM") a(emitLua(em, "bm")) a("\t\t\t\t},") end
						for _, em in d.trails or {} do a("\t\t\t\t{ -- TRAIL") a(emitLua(em, "tr")) a("\t\t\t\t},") end
						a("\t\t\t},")
					end
				end
				a("\t\t},")
			end
		end
	end
	a("\t},")
	list("Hitboxes", function(e) return e.cat == "HITBOX" and e.data.kind ~= "touch" end, function(e)
		return string.format("{ At = %s, Name = %s, Kind = %q, Size = %s, Offset = %s, Duration = %s }", tm(e.rt), qs(e.data.name), e.data.kind or "add",
			e.data.size and v3l(e.data.size) or "Vector3.one", e.data.offsetCF and cfl(e.data.offsetCF) or "CFrame.new()", fn(e.data.lifetime or 0.1, 3))
	end)
	list("HitboxTouches", function(e) return e.cat == "HITBOX" and e.data.kind == "touch" end, function(e)
		return string.format("{ At = %s, Hitbox = %s, Touched = %s, Victim = %s, Offset = %s, Distance = %s }", tm(e.rt), qs(e.data.name), qs(e.data.touched),
			qs(e.data.victim or ""), e.data.offsetCF and cfl(e.data.offsetCF) or "CFrame.new()", fn(e.data.distance or 0, 2))
	end)
	a("\tInferredHitboxes = {")
	for _, h in infer(rec) do
		a(string.format("\t\t{ At = %s, Offset = CFrame.new(%s, %s, %s), Size = %s, Hits = %d, Damage = %s },", tm(h.at), fn(h.offset.X), fn(h.offset.Y), fn(h.offset.Z), v3l(h.size), h.hits, fn(h.damage, 2)))
	end
	a("\t},")
	list("Movement", function(e) return e.cat == "MOVE" and e.who == "YOU" and e.data.kind ~= "end" end, function(e)
		return string.format("{ At = %s, Class = %q%s%s }", tm(e.rt), e.data.class or "?", e.data.localVelocity and (", LocalVelocity = " .. v3l(e.data.localVelocity)) or "",
			e.data.duration and (", Duration = " .. fn(e.data.duration, 3)) or "")
	end)
	list("Damage", function(e) return e.cat == "HIT" and e.who ~= "YOU" end, function(e)
		return string.format("{ At = %s, Target = %s, Amount = %s }", tm(e.rt), qs(e.data.target), fn(e.data.amount, 2))
	end)
	a("\tVictim = {")
	for n, i in rec.vinfo or {} do
		a("\t\t[" .. qs(n) .. "] = {")
		a(string.format("\t\t\tFirstAt = %s, MinDistance = %s, PeakSpeed = %s, Health = %s, MaxHealth = %s, TrackedBy = %s,", fn(i.firstAt or 0, 3), fn(i.minDist or 0, 2),
			fn(i.peak or 0, 2), fn(i.hp or 0, 1), fn(i.maxhp or 0, 1), qs(table.concat(i.reasons or {}, "+"))))
		a("\t\t\tTrack = {")
		local tr = i.track or {}
		local ts = math.max(1, math.floor(math.max(#tr, 1) / 60))
		for x = 1, #tr, ts do
			local p = tr[x]
			a(string.format("\t\t\t\t{ At = %s, Offset = %s, LocalVelocity = %s, Speed = %s, Distance = %s },", tm(p.t), v3l(p.pos),
				p.vel and v3l(p.vel) or "Vector3.zero", fn(p.speed or 0, 2), fn(p.dist or 0, 2)))
		end
		a("\t\t\t},")
		a("\t\t},")
	end
	local function vlist(title, pred, f)
		a("\t\t" .. title .. " = {")
		for _, ev in rec.events do if ev.victim and pred(ev) then a("\t\t\t" .. tag(ev, f(ev)) .. ",") end end
		a("\t\t},")
	end
	vlist("Animations", function(e) return e.cat == "ANIM" and not e.data.kind end, function(e)
		return string.format("{ At = %s, Who = %s, Id = \"rbxassetid://%s\", Name = %s, Speed = %s, Played = %s }", tm(e.rt), qs(e.who), e.data.id, qs(e.data.name), fn(e.data.speed, 3), fn(e.data.played or 0, 3))
	end)
	vlist("Knockback", function(e) return (e.cat == "MOVE" and e.data.kind ~= "end") or (e.cat == "VELOCITY" and e.data.localVelocity) end, function(e)
		return string.format("{ At = %s, Who = %s, LocalVelocity = %s, Speed = %s }", tm(e.rt), qs(e.who),
			e.data.localVelocity and v3l(e.data.localVelocity) or "Vector3.zero", fn(e.data.speed or 0, 2))
	end)
	vlist("Markers", function(e) return e.cat == "STATE" and e.data.kind == "childAdded" end, function(e)
		return string.format("{ At = %s, Who = %s, Class = %q, Name = %s }", tm(e.rt), qs(e.who), e.data.class, qs(e.data.name))
	end)
	a("\t},")
	list("Camera", function(e) return e.cat == "CAMERA" end, function(e)
		if e.data.kind == "fov" then
			return string.format("{ At = %s, Kind = \"FOV\", From = %s, Peak = %s, To = %s, Duration = %s }", tm(e.rt), fn(e.data.from, 2), fn(e.data.peak, 2), fn(e.data.to, 2), fn(e.data.duration, 3))
		end
		return string.format("{ At = %s, Kind = \"Shake\", Duration = %s, Strength = %s }", tm(e.rt), fn(e.data.duration or 0, 3), fn(e.data.strength or 0, 3))
	end)
	list("Screen", function(e) return e.cat == "SCREEN" end, function(e)
		return string.format("{ At = %s, Kind = %q, Class = %q, Name = %s }", tm(e.rt), e.data.kind or "?", e.data.class or "?", qs(e.data.name or "?"))
	end)
	list("Remotes", function(e) return e.cat == "REMOTE" or e.cat == "REPLICATION" end, function(e)
		return string.format("{ At = %s, Remote = %s, Label = %s, Args = %s }", tm(e.rt), qs(e.data.remote), qs(e.data.label or ""), qs(ser(e.data.args)))
	end)
	a("\tPath = {")
	local ps = math.max(1, math.floor(#rec.path / 40))
	for i = 1, #rec.path, ps do
		local p = rec.path[i]
		a(string.format("\t\t{ At = %s, Offset = %s, Speed = %s },", tm(p.t), v3l(p.pos), fn(p.speed or 0, 2)))
	end
	a("\t},")
	a("}")
	return table.concat(L, "\n")
end

local PRELUDE = [==[
local Debris = game:GetService("Debris")
local REP = game:GetService("ReplicatedStorage")
local FX = REP:FindFirstChild("MoveEffects")
local Move = {}

local function playAnim(h, id, sp)
	local an = h:FindFirstChildOfClass("Animator") or h
	local a = Instance.new("Animation")
	a.AnimationId = id
	local tr = an:LoadAnimation(a)
	tr:Play()
	if sp and sp ~= 1 then tr:AdjustSpeed(sp) end
	return tr
end

local function playSound(p, id, vol, sp, tp, life, mode)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = vol or 1
	s.PlaybackSpeed = sp or 1
	s.TimePosition = tp or 0
	if mode then pcall(function() s.RollOffMode = Enum.RollOffMode[mode] end) end
	s.Parent = p
	s:Play()
	Debris:AddItem(s, math.max(life or 0, 0.1) + 1)
end

local function spawnFX(root, name, off, life)
	local src = FX and FX:FindFirstChild(name, true)
	if not src then return end
	local fx = src:Clone()
	local cf = root.CFrame * off
	if fx:IsA("BasePart") then
		fx.CFrame, fx.Anchored, fx.CanCollide = cf, true, false
	elseif fx:IsA("Model") then
		fx:PivotTo(cf)
	elseif fx:IsA("Attachment") then
		fx.Parent = workspace.Terrain
		fx.WorldCFrame = cf
	end
	if not fx.Parent then fx.Parent = workspace:FindFirstChild("Thrown") or workspace end
	for _, d in fx:GetDescendants() do
		if d:IsA("ParticleEmitter") then
			local n, dl = d:GetAttribute("EmitCount"), d:GetAttribute("EmitDelay") or 0
			if n then task.delay(dl, function() d:Emit(n) end) end
		end
	end
	Debris:AddItem(fx, math.max(life or 1, 0.2) + 1)
end

local function addVel(root, lv, dur, force, space)
	local at = Instance.new("Attachment")
	at.Parent = root
	local x = Instance.new("LinearVelocity")
	x.Attachment0 = at
	x.RelativeTo = Enum.ActuatorRelativeTo.World
	x.VectorVelocity = (space or root.CFrame):VectorToWorldSpace(lv)
	x.MaxForce = force or 1e6
	x.Parent = root
	Debris:AddItem(x, dur)
	Debris:AddItem(at, dur)
end

local function hitbox(char, root, off, size, dur, onHit)
	local par = OverlapParams.new()
	par.FilterType = Enum.RaycastFilterType.Exclude
	par.FilterDescendantsInstances = { char }
	local hit, stop = {}, os.clock() + dur
	repeat
		for _, p in workspace:GetPartBoundsInBox(root.CFrame * off, size, par) do
			local m = p:FindFirstAncestorOfClass("Model")
			local h = m and m:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 and not hit[m] then
				hit[m] = true
				task.spawn(onHit, m, h)
			end
		end
		task.wait()
	until os.clock() >= stop
end
]==]

function Out.replay(rec)
	local L = {}
	local function a(s) L[#L + 1] = s end
	local function tm(t) return fn(math.max(t, 0), 3) end
	a("--[[")
	a("\tMove #" .. rec.index .. " · " .. rec.name .. " · " .. rec.when)
	if rec.startup then a("\tADVANCED: startup 0–" .. tm(rec.startup) .. "s, hit at " .. tm(rec.startup) .. "s") end
	a("\tClones: copy " .. (rec.save or "ReplicatedStorage.MoveLogger_Logged.<rec>") .. " into ReplicatedStorage.MoveEffects")
	a("\tUse: require(this).Play(character) — server")
	a("--]]")
	a(PRELUDE)
	a("")
	local firstHit
	for _, ev in rec.events do
		if ev.cat == "HIT" and ev.who ~= "YOU" and (ev.data.amount or 0) > 0 then firstHit = ev.rt break end
	end
	a("local function react(aroot, vic, h, dmg)")
	a("\th:TakeDamage(dmg)")
	a("\tlocal vr = vic:FindFirstChild(\"HumanoidRootPart\")")
	if firstHit then
		local vn
		for _, ev in rec.events do if ev.cat == "HIT" and ev.who ~= "YOU" and ev.rt == firstHit then vn = ev.who break end end
		for _, ev in rec.events do
			if ev.victim and ev.who == vn and ev.rt >= firstHit - 0.05 then
				local dt = tm(ev.rt - firstHit)
				if ev.cat == "ANIM" and not ev.data.kind then
					a(string.format("\ttask.delay(%s, playAnim, h, \"rbxassetid://%s\", %s) -- %s", dt, ev.data.id, fn(ev.data.speed, 3), ev.data.name))
				elseif (ev.cat == "MOVE" and ev.data.localVelocity and ev.data.kind ~= "end") or (ev.cat == "VELOCITY" and ev.data.localVelocity) then
					a(string.format("\ttask.delay(%s, function() if vr then addVel(vr, %s, %s, nil, aroot.CFrame) end end) -- knockback", dt, v3l(ev.data.localVelocity), fn(ev.data.duration or 0.2, 3)))
				end
			end
		end
	else
		a("\t-- no hits recorded")
	end
	a("end")
	a("")
	a("function Move.Play(character)")
	a("\tlocal h = character:FindFirstChildOfClass(\"Humanoid\")")
	a("\tlocal root = character:FindFirstChild(\"HumanoidRootPart\")")
	a("\tif not h or not root then return end")
	if rec.startSpd and rec.startSpd > 1 then a("\taddVel(root, " .. v3l(rec.startVel) .. ", 0.05, nil, root.CFrame) -- launch") end
	local hbs = {}
	for _, ev in rec.events do
		if ev.cat == "HITBOX" and ev.data.kind ~= "touch" then hbs[#hbs + 1] = { at = ev.rt, off = ev.data.offsetCF, size = ev.data.size, dur = ev.data.lifetime or 0.1 } end
	end
	local inf = infer(rec)
	if #hbs == 0 then
		for _, x in inf do hbs[#hbs + 1] = { at = x.at - 0.03, off = CFrame.new(x.offset), size = x.size, dur = 0.1, dmg = x.damage / math.max(x.hits, 1) } end
	end
	local dd = #inf > 0 and (inf[1].damage / math.max(inf[1].hits, 1)) or 10
	local lines = {}
	for _, ev in rec.events do
		local t = ev.rt
		if ev.who == "YOU" and ev.cat == "ANIM" and not ev.data.kind then
			lines[#lines + 1] = { t, string.format("task.delay(%s, playAnim, h, \"rbxassetid://%s\", %s) -- %s%s", tm(t), ev.data.id, fn(ev.data.speed, 3), ev.data.name,
				ev.phase == "startup" and " [startup]" or "") }
		elseif ev.cat == "SOUND" and not ev.victim then
			lines[#lines + 1] = { t, string.format("task.delay(%s, playSound, root, \"rbxassetid://%s\", %s, %s, %s, %s, %s) -- %s", tm(t), ev.data.id,
				fn(ev.data.volume, 3), fn(ev.data.speed, 3), fn(ev.data.timePosition, 3), fn(ev.data.played or ev.data.length or 1, 3), qs(ev.data.rollOffMode or "Inverse"), ev.data.name) }
		elseif ev.cat == "VFX" and not ev.data.kind then
			lines[#lines + 1] = { t, string.format("task.delay(%s, spawnFX, root, %s, %s, %s) -- %s", tm(t), qs(ev.data.saved or ev.data.name),
				ev.data.offsetCF and cfl(ev.data.offsetCF) or "CFrame.new()", fn(ev.data.lifetime or 1, 3), ev.data.class) }
		elseif ev.who == "YOU" and ev.cat == "MOVE" and ev.data.localVelocity and ev.data.kind ~= "end" then
			lines[#lines + 1] = { t, string.format("task.delay(%s, addVel, root, %s, %s) -- %s", tm(t), v3l(ev.data.localVelocity), fn(ev.data.duration or 0.15, 3), ev.data.class or "impulse") }
		elseif ev.who == "YOU" and ev.cat == "VELOCITY" and ev.data.kind == "velocityPhase" and ev.data.localVelocity then
			lines[#lines + 1] = { t, string.format("task.delay(%s, addVel, root, %s, %s) -- motion phase", tm(t), v3l(ev.data.localVelocity), fn(ev.data.duration or 0.2, 3)) }
		end
	end
	for _, x in hbs do
		lines[#lines + 1] = { x.at, string.format("task.delay(%s, function() hitbox(character, root, %s, %s, %s, function(v, hh) react(root, v, hh, %s) end) end) -- hitbox", tm(x.at),
			x.off and cfl(x.off) or "CFrame.new(0, 0, -4)", x.size and v3l(x.size) or "Vector3.new(5, 5, 5)", fn(math.max(x.dur, 0.05), 3), fn(x.dmg or dd, 2)) }
	end
	table.sort(lines, function(p, q) return p[1] < q[1] end)
	for _, l in lines do a("\t" .. l[2]) end
	a("end")
	a("")
	a("return Move")
	return table.concat(L, "\n")
end

function Out.json(rec)
	local evs = {}
	for _, ev in rec.events do
		evs[#evs + 1] = { t = rd(ev.rt, 4), cat = ev.cat, who = ev.who, victim = ev.victim or nil, phase = ev.phase, text = ev.text, data = plain(ev.data) }
	end
	local ok, s = pcall(HS.JSONEncode, HS, { index = rec.index, name = rec.name, duration = rd(rec.duration, 4), startupDuration = rec.startup,
		when = rec.when, placeId = rec.placeId, character = rec.character, victims = rec.victims, victimInfo = plain(rec.vinfo),
		events = evs, inferredHitboxes = plain(infer(rec)), path = plain(rec.path) })
	return ok and s or ("JSON failed: " .. tostring(s))
end

---------------------------------------------------------------------------------------------------
local function mk(cl, p, kids)
	local i = Instance.new(cl)
	for k, v in p or {} do if k ~= "Parent" then i[k] = v end end
	for _, c in kids or {} do c.Parent = i end
	if p and p.Parent then i.Parent = p.Parent end
	return i
end
local function cor(rad) return mk("UICorner", { CornerRadius = UDim.new(0, rad or 8) }) end
local function strk(c, t) return mk("UIStroke", { Color = c or T.Stroke, Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pd(p) return mk("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }) end
local F, FB, FM = Enum.Font.GothamMedium, Enum.Font.GothamBold, Enum.Font.Code
local function lbl(txt, p)
	local d = { BackgroundTransparency = 1, Text = txt, TextColor3 = T.Text, Font = F, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in p or {} do d[k] = v end
	return mk("TextLabel", d)
end
local function btn(txt, p, fn2)
	local d = { BackgroundColor3 = T.Pan2, Text = txt, TextColor3 = T.Text, Font = F, TextSize = 13, AutoButtonColor = false, Size = UDim2.fromOffset(80, 28) }
	for k, v in p or {} do d[k] = v end
	local st = strk()
	local b = mk("TextButton", d, { cor(7), st })
	b.MouseEnter:Connect(function() TS:Create(st, TweenInfo.new(0.12), { Color = T.Acc }):Play() end)
	b.MouseLeave:Connect(function() TS:Create(st, TweenInfo.new(0.12), { Color = T.Stroke }):Play() end)
	if fn2 then b.Activated:Connect(g(fn2)) end
	return b
end
local function hl(gap) return mk("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }) end
local function vl(gap) return mk("UIListLayout", { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, gap or 6), SortOrder = Enum.SortOrder.LayoutOrder }) end

ownGui = mk("ScreenGui", { Name = "MoveLogger", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 10000, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local vp = (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1280, 720)
local W = math.clamp(vp.X - 24, 360, 660)
local H = math.clamp(vp.Y - 90, 360, 540)
local win = mk("Frame", { Size = UDim2.fromOffset(W, H), Position = UDim2.new(1, -W - 12, 0, 60), BackgroundColor3 = T.Bg, Parent = ownGui }, { cor(12), strk(T.Stroke, 1) })
local bar = mk("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundColor3 = T.Pan, Parent = win }, { cor(12) })
mk("Frame", { Size = UDim2.new(1, 0, 0, 10), Position = UDim2.new(0, 0, 1, -10), BackgroundColor3 = T.Pan, BorderSizePixel = 0, Parent = bar })
local dot = mk("Frame", { Size = UDim2.fromOffset(9, 9), Position = UDim2.new(0, 12, 0.5, -4), BackgroundColor3 = T.Sub, Parent = bar }, { cor(5) })
lbl("Move Logger 2.6", { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(0, 130, 1, 0), Font = FB, TextSize = 13, Parent = bar })
local stat = lbl("idle", { Position = UDim2.fromOffset(150, 0), Size = UDim2.new(1, -230, 1, 0), TextColor3 = T.Sub, TextSize = 11, Parent = bar })
local minB = btn("–", { Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -62, 0.5, -11), Parent = bar })
local clsB = btn("×", { Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -32, 0.5, -11), Parent = bar })
local tabs = mk("Frame", { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 40), BackgroundTransparency = 1, Parent = win }, { hl(6) })
local body = mk("Frame", { Size = UDim2.new(1, -20, 1, -78), Position = UDim2.fromOffset(10, 74), BackgroundTransparency = 1, ClipsDescendants = true, Parent = win })
local pages, tbtns = {}, {}
local function showTab(n)
	for k, p in pages do p.Visible = k == n end
	for k, b in tbtns do
		b.BackgroundColor3 = k == n and T.Acc or T.Pan2
		b.TextColor3 = k == n and Color3.new(1, 1, 1) or T.Sub
	end
	if UI.onTab then UI.onTab(n) end
end
for i, n in { "Record", "Moves", "Settings" } do
	local b = btn(n, { Size = UDim2.fromOffset(math.floor((W - 20 - 14) / 3), 26), LayoutOrder = i, TextSize = 12, Parent = tabs })
	tbtns[n] = b
	pages[n] = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, Parent = body })
	b.Activated:Connect(function() showTab(n) end)
end
do
	local drag, sp0, ip
	bar.InputBegan:Connect(function(inp)
		if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
			drag, sp0, ip = true, win.Position, inp.Position
			inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then drag = false end end)
		end
	end)
	cn(UIS.InputChanged:Connect(function(inp)
		if drag and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
			local d = inp.Position - ip
			win.Position = UDim2.new(sp0.X.Scale, sp0.X.Offset + d.X, sp0.Y.Scale, sp0.Y.Offset + d.Y)
		end
	end))
end
local pill = btn("ML", { Size = UDim2.fromOffset(44, 44), Position = UDim2.new(0, 12, 0.5, -22), BackgroundColor3 = T.Pan, Font = FB, TextSize = 14, Parent = ownGui })
local pc = pill:FindFirstChildOfClass("UICorner")
if pc then pc.CornerRadius = UDim.new(1, 0) end
local ps = pill:FindFirstChildOfClass("UIStroke")
if ps then ps.Thickness = 2 end
local function toggleWin() win.Visible = not win.Visible end
pill.Activated:Connect(toggleWin)
clsB.Activated:Connect(function() win.Visible = false end)
local mini = false
minB.Activated:Connect(function()
	mini = not mini
	tabs.Visible, body.Visible = not mini, not mini
	win.Size = mini and UDim2.fromOffset(W, 34) or UDim2.fromOffset(W, H)
end)
local tTok = 0
local tLbl = lbl("", { Size = UDim2.new(1, 0, 0, 16), Position = UDim2.new(0, 0, 1, -18), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, TextColor3 = T.Good, TextTransparency = 1, ZIndex = 20, Parent = win })
function toast(m)
	tTok = tTok + 1
	local tok = tTok
	tLbl.Text, tLbl.TextTransparency = m, 0
	task.delay(2, function()
		if tTok ~= tok then return end
		TS:Create(tLbl, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
	end)
end
function copyText(txt, what, box)
	if typeof(setclipboard) == "function" and pcall(setclipboard, txt) then
		toast("copied " .. what)
		return
	end
	if box then
		box:CaptureFocus()
		task.defer(function() box.SelectionStart, box.CursorPosition = 1, #box.Text + 1 end)
		toast("selected " .. what .. " — Ctrl+C")
	else
		toast("no clipboard")
	end
end

---------------------------------------------------------------------------------------------------
sec("record page", function()
	local pg = pages.Record
	local big = lbl("IDLE", { Size = UDim2.new(1, 0, 0, 30), Font = FB, TextSize = 22, Parent = pg })
	local sub = lbl("Arm, then do a move — or Start / F6.", { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 16), TextColor3 = T.Sub, TextSize = 11, Parent = pg })
	local row = mk("Frame", { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 30), BackgroundTransparency = 1, Parent = pg }, { hl(5) })
	local bw = math.floor((W - 20 - 15) / 4)
	local armB = btn("Arm", { Size = UDim2.fromOffset(bw, 30), LayoutOrder = 1, Parent = row }, function() arm() end)
	local stB = btn("● Start", { Size = UDim2.fromOffset(bw, 30), LayoutOrder = 2, BackgroundColor3 = Color3.fromRGB(60, 28, 34), Parent = row }, function() startRec("manual") end)
	btn("■ Stop", { Size = UDim2.fromOffset(bw, 30), LayoutOrder = 3, Parent = row }, function()
		if Rec.state == "recording" then stopRec("manual") else setState("idle") end
	end)
	btn("Clear", { Size = UDim2.fromOffset(bw, 30), LayoutOrder = 4, Parent = row }, function()
		table.clear(Hist)
		Sel = 0
		if UI.refreshAll then UI.refreshAll() end
	end)
	armB.TextColor3, stB.TextColor3 = T.Arm, T.Rec
	local arow = mk("Frame", { Position = UDim2.fromOffset(0, 86), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = pg }, { hl(5) })
	local advB = btn("Advanced: off", { Size = UDim2.fromOffset(bw, 26), LayoutOrder = 1, TextSize = 10, Parent = arow })
	local hitB = btn("Hit ▶ F9", { Size = UDim2.fromOffset(bw, 26), LayoutOrder = 2, TextSize = 10, BackgroundColor3 = Color3.fromRGB(60, 40, 24), Parent = arow })
	local doneB = btn("✓ Done", { Size = UDim2.fromOffset(bw, 26), LayoutOrder = 3, TextSize = 10, BackgroundColor3 = Color3.fromRGB(28, 48, 32), Parent = arow })
	local hint = lbl("split startup / hit", { Size = UDim2.new(1, -bw * 3 - 15, 1, 0), LayoutOrder = 4, TextSize = 10, TextColor3 = T.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Parent = arow })
	local function paintAdv()
		advB.Text = "Advanced: " .. (C.Adv and "on" or "off")
		advB.TextColor3 = C.Adv and T.Good or T.Sub
		local rec = Rec.state == "recording"
		hitB.TextColor3 = (rec and Rec.phase == "startup") and T.Hit or T.Sub
		doneB.TextColor3 = (rec and Rec.phase == "hit") and T.Good or T.Sub
		hint.Text = not C.Adv and "split startup / hit" or (rec and (Rec.phase == "startup" and "wind-up — Hit when it connects" or "hit phase — Done") or "Start = startup · Hit = hit · Done = save")
	end
	advB.Activated:Connect(g(function()
		C.Adv = not C.Adv
		paintAdv()
	end))
	hitB.Activated:Connect(g(function() hitPhase() end))
	doneB.Activated:Connect(g(function()
		if Rec.state == "recording" then stopRec("manual") else toast("nothing recording") end
	end))
	paintAdv()
	UI.nameBox = mk("TextBox", { Position = UDim2.fromOffset(0, 116), Size = UDim2.new(1, 0, 0, 26), BackgroundColor3 = T.Pan, PlaceholderText = "move name",
		PlaceholderColor3 = T.Sub, Text = "", TextColor3 = T.Text, Font = F, TextSize = 11, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = pg },
		{ cor(7), strk(), mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
	local chips = mk("Frame", { Position = UDim2.fromOffset(0, 146), Size = UDim2.new(1, 0, 0, 72), BackgroundTransparency = 1, Parent = pg },
		{ mk("UIGridLayout", { CellSize = UDim2.fromOffset(math.floor((W - 20 - 25) / 6), 20), CellPadding = UDim2.fromOffset(5, 6), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local cLabels = {}
	for i, c in CATS do
		local ch = mk("Frame", { BackgroundColor3 = T.Pan, LayoutOrder = i, Parent = chips }, { cor(6) })
		mk("Frame", { Size = UDim2.fromOffset(3, 12), Position = UDim2.new(0, 5, 0.5, -6), BackgroundColor3 = CC[c], BorderSizePixel = 0, Parent = ch }, { cor(2) })
		cLabels[c] = lbl(c .. " 0", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(1, -14, 1, 0), TextSize = 9, TextColor3 = T.Sub, Parent = ch })
	end
	local vicL = lbl("victims: —", { Position = UDim2.fromOffset(0, 222), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = T.Sub, TextTruncate = Enum.TextTruncate.AtEnd, Parent = pg })
	local feed = mk("Frame", { Position = UDim2.fromOffset(0, 240), Size = UDim2.new(1, 0, 1, -266), BackgroundColor3 = T.Pan, ClipsDescendants = true, Parent = pg }, { cor(8), strk(), pd(7), vl(2) })
	local fLines = {}
	for i = 1, 9 do
		fLines[i] = lbl("", { Size = UDim2.new(1, 0, 0, 13), TextSize = 10, Font = FM, RichText = true, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = i, Parent = feed })
	end
	local fBuf = {}
	local hist = mk("Frame", { Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = pg })
	local hLbl = lbl("no moves yet", { Position = UDim2.fromOffset(32, 0), Size = UDim2.new(1, -64, 1, 0), TextXAlignment = Enum.TextXAlignment.Center, TextSize = 11, Parent = hist })
	btn("‹", { Size = UDim2.fromOffset(26, 22), Parent = hist }, function() if Sel > 1 then Sel = Sel - 1 if UI.refreshAll then UI.refreshAll() end end end)
	btn("›", { Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -26, 0, 0), Parent = hist }, function() if Sel < #Hist then Sel = Sel + 1 if UI.refreshAll then UI.refreshAll() end end end)
	local function line(ev)
		local t = Rec.state == "recording" and (ev.t - Rec.t0) or ev.rt or 0
		local x = string.gsub(string.gsub(string.gsub(ev.text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;")
		return string.format('<font color="#8a90a5">%+6.2f</font> <font color="%s">%-6s</font> %s', t, hex(CC[ev.cat] or T.Text), ev.cat, x)
	end
	local cnt = {}
	function UI.refreshRecord()
		local s = Rec.state
		if s == "recording" then
			local su = Rec.phase == "startup"
			big.Text = string.format("%s %.2fs", su and "● STARTUP" or "● REC", now() - Rec.t0)
			big.TextColor3, dot.BackgroundColor3 = su and T.Arm or T.Rec, su and T.Arm or T.Rec
			if ps then ps.Color = su and T.Arm or T.Rec end
			sub.Text = su and "wind-up only, no victims — Hit (F9) when it connects" or string.format("%d events · F6 / Stop to end", #Rec.events)
		elseif s == "armed" then
			big.Text, big.TextColor3, dot.BackgroundColor3 = "ARMED", T.Arm, T.Arm
			if ps then ps.Color = T.Arm end
			sub.Text = C.Adv and "will start the STARTUP phase on your next action animation" or "do your move — starts on your next action animation"
		else
			big.Text, big.TextColor3, dot.BackgroundColor3 = "IDLE", T.Text, T.Sub
			if ps then ps.Color = T.Stroke end
			sub.Text = "Arm, then do a move — or Start / F6."
		end
		stat.Text = s == "recording" and string.format("%s %.1fs", Rec.phase == "startup" and "startup" or "rec", now() - Rec.t0) or s
		paintAdv()
		table.clear(cnt)
		local src = s == "recording" and Rec.events or (Hist[Sel] and Hist[Sel].events) or {}
		for _, ev in src do cnt[ev.cat] = (cnt[ev.cat] or 0) + 1 end
		for _, c in CATS do
			cLabels[c].Text = c .. " " .. (cnt[c] or 0)
			cLabels[c].TextColor3 = (cnt[c] or 0) > 0 and T.Text or T.Sub
		end
		local vn = {}
		if s == "recording" and not Rec.noVic then
			for _, v in Rec.victims do vn[#vn + 1] = v.name end
		elseif Hist[Sel] then
			vn = Hist[Sel].victims
		end
		vicL.Text = "victims: " .. (#vn > 0 and table.concat(vn, ", ") or "—")
		local r = Hist[Sel]
		hLbl.Text = r and string.format("#%d/%d · %s · %ss", Sel, #Hist, r.name, fn(r.duration, 2)) or "no moves yet"
	end
	function UI.feed(ev)
		fBuf[#fBuf + 1] = ev
		while #fBuf > #fLines do table.remove(fBuf, 1) end
		for i, l in fLines do l.Text = fBuf[i] and line(fBuf[i]) or "" end
	end
	function UI.feedFromRec(r)
		table.clear(fBuf)
		local n = r and #r.events or 0
		for i = math.max(1, n - #fLines + 1), n do fBuf[#fBuf + 1] = r.events[i] end
		for i, l in fLines do l.Text = fBuf[i] and line(fBuf[i]) or "" end
	end
end)

---------------------------------------------------------------------------------------------------
local fmtKey, prevBox, prevHead, rows = "moveTable", nil, nil, {}
local PAGE, pIdx, full = 60000, 1, ""
local function page()
	local tot = math.max(1, math.ceil(#full / PAGE))
	pIdx = math.clamp(pIdx, 1, tot)
	local a = (pIdx - 1) * PAGE + 1
	if prevBox then prevBox.Text = string.sub(full, a, a + PAGE - 1) end
	if prevHead then prevHead.Text = string.format("%s · %d/%d", fmtKey, pIdx, tot) end
end
local function render(r, f)
	local ok, s = pcall(Out[f] or Out.moveTable, r)
	full = ok and s or ("failed: " .. tostring(s))
	pIdx = 1
	page()
end
local function copyMove(r, f, quiet)
	local ok, s = pcall(Out[f] or Out.moveTable, r)
	if not ok then return toast("failed: " .. tostring(s)) end
	copyText(s, f .. " of #" .. r.index, (not quiet) and prevBox or nil)
end

sec("moves page", function()
	local pg = pages.Moves
	local head = mk("Frame", { Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Parent = pg }, { hl(5) })
	local search = mk("TextBox", { Size = UDim2.new(1, -110, 0, 24), BackgroundColor3 = T.Pan, PlaceholderText = "filter",
		PlaceholderColor3 = T.Sub, Text = "", TextColor3 = T.Text, Font = F, TextSize = 11, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = head },
		{ cor(7), strk(), mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
	btn("Copy all", { Size = UDim2.fromOffset(70, 24), TextSize = 10, Parent = head }, function()
		if #Hist == 0 then return toast("nothing to copy") end
		local o = {}
		for _, r in Hist do
			o[#o + 1] = "-- ===== MOVE #" .. r.index .. " · " .. r.name .. " ====="
			local ok, s = pcall(Out.moveTable, r)
			o[#o + 1] = ok and s or "-- failed"
			o[#o + 1] = ""
		end
		copyText(table.concat(o, "\n"), "all blocks", prevBox)
	end)
	local list = mk("ScrollingFrame", { Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -232), BackgroundColor3 = T.Pan, ScrollBarThickness = 4,
		ScrollBarImageColor3 = T.Stroke, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = pg }, { cor(8), pd(5), vl(4) })
	local wrap = mk("Frame", { Position = UDim2.new(0, 0, 1, -160), Size = UDim2.new(1, 0, 0, 160), BackgroundTransparency = 1, Parent = pg })
	local pbar = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, Parent = wrap }, { hl(4) })
	prevHead = lbl("pick a block", { Size = UDim2.new(1, -120, 0, 22), TextSize = 10, TextColor3 = T.Sub, Parent = pbar })
	btn("‹", { Size = UDim2.fromOffset(24, 22), Parent = pbar }, function() pIdx = pIdx - 1 page() end)
	btn("›", { Size = UDim2.fromOffset(24, 22), Parent = pbar }, function() pIdx = pIdx + 1 page() end)
	btn("Copy", { Size = UDim2.fromOffset(46, 22), BackgroundColor3 = T.Acc, Parent = pbar }, function()
		if Hist[Sel] then copyMove(Hist[Sel], fmtKey) end
	end)
	local scroller = mk("ScrollingFrame", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 1, -26), BackgroundColor3 = T.Pan, ScrollBarThickness = 5,
		ScrollBarImageColor3 = T.Stroke, AutomaticCanvasSize = Enum.AutomaticSize.XY, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = wrap }, { cor(8), strk() })
	prevBox = mk("TextBox", { Size = UDim2.new(1, -10, 0, 0), Position = UDim2.fromOffset(5, 5), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1,
		Text = "", TextColor3 = T.Text, Font = FM, TextSize = 11, MultiLine = true, ClearTextOnFocus = false, TextEditable = true, TextWrapped = false,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = scroller })
	local function refresh()
		for _, r in rows do r:Destroy() end
		table.clear(rows)
		tbtns.Moves.Text = "Moves (" .. #Hist .. ")"
		local q = string.lower(search.Text)
		local n = 0
		for i = #Hist, 1, -1 do
			local r = Hist[i]
			if q == "" or string.find(string.lower(r.name), q, 1, true) or table.find(r.victims, q) then
				n = n + 1
				local card = mk("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = i == Sel and T.Pan2 or T.Pan, LayoutOrder = n, Parent = list },
					{ cor(7), strk(i == Sel and T.Acc or T.Stroke) })
				lbl(string.format("#%d %s%s", r.index, r.name, r.startup and "  [startup+hit]" or ""), { Position = UDim2.fromOffset(7, 3), Size = UDim2.new(1, -14, 0, 16),
					TextSize = 11, Font = FB, TextTruncate = Enum.TextTruncate.AtEnd, Parent = card })
				lbl(string.format("%ss · %d events · %d victim(s)", fn(r.duration, 2), #r.events, #r.victims), { Position = UDim2.fromOffset(7, 19),
					Size = UDim2.new(1, -14, 0, 12), TextSize = 9, TextColor3 = T.Sub, Parent = card })
				local br = mk("Frame", { Position = UDim2.fromOffset(7, 32), Size = UDim2.new(1, -14, 0, 14), BackgroundTransparency = 1, Parent = card }, { hl(3) })
				local o = 0
				for _, f in { { "Table", "moveTable" }, { "Replay", "replay" }, { "Summ", "summary" }, { "Time", "timeline" }, { "JSON", "json" } } do
					o = o + 1
					btn(f[1], { Size = UDim2.fromOffset(44, 14), TextSize = 8, LayoutOrder = o, Parent = br }, function()
						Sel = i
						render(r, f[2])
						refresh()
					end)
				end
				btn("copy", { Size = UDim2.fromOffset(44, 14), TextSize = 8, BackgroundColor3 = T.Acc, LayoutOrder = 6, Parent = br }, function() copyMove(r, fmtKey) end)
				rows[#rows + 1] = card
			end
		end
		if n == 0 then
			rows[#rows + 1] = lbl(#Hist == 0 and "no moves yet — record one on the Record tab" or "nothing matches", { Size = UDim2.new(1, 0, 0, 36),
				TextSize = 11, TextColor3 = T.Sub, TextXAlignment = Enum.TextXAlignment.Center, Parent = list })
		end
		local r = Hist[Sel]
		if r then
			prevHead.Text = "#" .. r.index .. " " .. r.name .. " · " .. fmtKey
			render(r, fmtKey)
		else
			prevHead.Text = "pick a block"
			full = "No move blocks yet.\n\nRecord tab → Arm, then do a move."
			pIdx = 1
			page()
		end
	end
	search:GetPropertyChangedSignal("Text"):Connect(g(refresh))
	UI.refreshMoves = refresh
end)

---------------------------------------------------------------------------------------------------
sec("settings page", function()
	local pg = pages.Settings
	local list = mk("ScrollingFrame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ScrollBarThickness = 4, ScrollBarImageColor3 = T.Stroke,
		AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = pg }, { vl(4) })
	local o = 0
	local function row(txt)
		o = o + 1
		local f = mk("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundColor3 = T.Pan, LayoutOrder = o, Parent = list }, { cor(6) })
		lbl(txt, { Position = UDim2.fromOffset(8, 0), Size = UDim2.new(1, -100, 1, 0), TextSize = 11, Parent = f })
		return f
	end
	local function tg(key, txt, onChange)
		local f = row(txt)
		local sw = mk("TextButton", { Size = UDim2.fromOffset(36, 18), Position = UDim2.new(1, -44, 0.5, -9), BackgroundColor3 = T.Pan2, Text = "", AutoButtonColor = false, Parent = f }, { cor(9) })
		local kn = mk("Frame", { Size = UDim2.fromOffset(14, 14), BackgroundColor3 = Color3.new(1, 1, 1), Parent = sw }, { cor(7) })
		local function paint()
			kn.Position = C[key] and UDim2.fromOffset(20, 2) or UDim2.fromOffset(2, 2)
			sw.BackgroundColor3 = C[key] and T.Acc or T.Pan2
		end
		paint()
		sw.Activated:Connect(g(function()
			C[key] = not C[key]
			paint()
			if onChange then onChange() end
		end))
	end
	local function num(key, txt, minv, maxv)
		local f = row(txt)
		local box = mk("TextBox", { Size = UDim2.fromOffset(56, 18), Position = UDim2.new(1, -64, 0.5, -9), BackgroundColor3 = T.Pan2, Text = tostring(C[key]),
			TextColor3 = T.Text, Font = F, TextSize = 10, ClearTextOnFocus = false, Parent = f }, { cor(5) })
		box.FocusLost:Connect(function()
			C[key] = math.clamp(tonumber(box.Text) or C[key], minv, maxv)
			box.Text = tostring(C[key])
		end)
	end
	local function txt(key, title, onSet)
		o = o + 1
		local f = mk("Frame", { Size = UDim2.new(1, 0, 0, 44), BackgroundColor3 = T.Pan, LayoutOrder = o, Parent = list }, { cor(6) })
		lbl(title, { Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -16, 0, 14), TextSize = 10, TextColor3 = T.Sub, Parent = f })
		local box = mk("TextBox", { Position = UDim2.fromOffset(6, 18), Size = UDim2.new(1, -12, 0, 20), BackgroundColor3 = T.Pan2, Text = C[key],
			TextColor3 = T.Text, Font = F, TextSize = 10, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = f }, { cor(5) })
		box.FocusLost:Connect(function()
			C[key] = box.Text
			if onSet then onSet(box.Text) end
		end)
	end
	tg("Adv", "Advanced recording (startup → hit → Done)", function() if UI.refreshRecord then UI.refreshRecord() end end)
	tg("StartOnAnim", "Start on your next action animation")
	tg("StartOnRemote", "Start on a server event about you")
	tg("StartOnFx", "Start on an effect-module call for you (Hero)")
	tg("Hooks", "Hook Tween/Emit calls (executor only, reload to apply)")
	tg("Templates", "Dump + clone effect asset folders")
	tg("AutoArm", "Re-arm after each recording")
	tg("Others", "Log everyone in the radius")
	tg("IgnoreCore", "Ignore walk / idle / run / jump")
	tg("Clone", "Clone effects to ReplicatedStorage")
	tg("Terrain", "Track Terrain effect children")
	tg("Motion", "Track effect motion")
	tg("Tags", "Track tags")
	tg("Attrs", "Track attributes")
	tg("Dummies", "Track dummies")
	tg("Vel", "Track velocity")
	tg("Touches", "Log hitbox Touched events")
	tg("RepSpy", "Spy replication remotes")
	tg("Remotes", "Log server → you remotes")
	tg("Cam", "Log camera")
	tg("Screen", "Log screen effects")
	tg("Debug", "Print handler errors")
	num("Radius", "Radius (studs)", 10, 2000)
	num("VRadius", "Victim proximity", 5, 300)
	num("Preroll", "Pre-roll (s)", 0, 3)
	num("IdleStop", "Auto-stop after idle (s)", 0.25, 15)
	num("MaxLen", "Max length (s)", 2, 300)
	num("Spike", "Velocity jump threshold", 5, 500)
	num("Shake", "Shake threshold (°)", 0.05, 5)
	num("MaxClones", "Max effect clones", 10, 600)
	txt("RIgnore", "Ignore remotes containing", function(s) rIgnore = lst(s) end)
	txt("SIgnore", "Ignore sounds containing", function(s) sIgnore = lst(s) end)
end)

---------------------------------------------------------------------------------------------------
function UI.refreshAll()
	UI.refreshRecord()
	UI.feedFromRec(Hist[Sel])
	if pages.Moves.Visible and UI.refreshMoves then UI.refreshMoves() end
end
UI.onTab = function(n)
	if n == "Moves" and UI.refreshMoves then UI.refreshMoves()
	elseif n == "Record" and UI.refreshRecord then UI.refreshRecord() end
end
Hooks.onEvent = function(ev) if UI.feed then UI.feed(ev) end end
Hooks.onState = function() if UI.refreshRecord then UI.refreshRecord() end end
Hooks.onFinish = function()
	UI.refreshAll()
	if win.Visible and not mini then showTab("Moves") end
	toast("move #" .. Sel .. " saved")
end

ownGui.Parent = PG
showTab("Record")

sec("wiring", function()
	cn(UIS.InputBegan:Connect(g(function(inp, proc)
		if proc then return end
		if inp.KeyCode == Enum.KeyCode.F6 then
			if Rec.state == "recording" then stopRec("manual") else startRec("manual") end
		elseif inp.KeyCode == Enum.KeyCode.F7 then
			if Rec.state == "armed" then setState("idle") else arm() end
		elseif inp.KeyCode == Enum.KeyCode.F8 then
			toggleWin()
		elseif inp.KeyCode == Enum.KeyCode.F9 then
			hitPhase()
		end
	end)))
	cn(workspace.DescendantAdded:Connect(g(onDesc)))
	cn(SND.DescendantAdded:Connect(g(function(d) if d:IsA("Sound") then hookSnd(d) end end)))
	cn(PG.DescendantAdded:Connect(g(function(d)
		if d:IsA("Sound") then hookSnd(d) return end
		onGui(d)
	end)))
	cn(LIGHT.ChildAdded:Connect(g(onScreen)))
	cn(workspace.Terrain.ChildAdded:Connect(g(function(c)
		if Rec.state == "idle" or not C.Terrain then return end
		if c:IsA("Attachment") or c:IsA("ParticleEmitter") or c:IsA("Trail") or c:IsA("Beam") or hasVis(c) then task.defer(g(process), c, now()) end
	end)))
	local function hookCam(c)
		if not c then return end
		cn(c.ChildAdded:Connect(g(onScreen)))
	end
	hookCam(workspace.CurrentCamera)
	cn(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(g(function() hookCam(workspace.CurrentCamera) end)))
	local function tree(r)
		for _, d in r:GetDescendants() do
			if d:IsA("RemoteEvent") or d.ClassName == "UnreliableRemoteEvent" then hookRem(d) end
		end
		cn(r.DescendantAdded:Connect(g(function(d)
			if d:IsA("RemoteEvent") or d.ClassName == "UnreliableRemoteEvent" then hookRem(d) end
		end)))
	end
	task.spawn(g(function() pcall(tree, REP) end))
	cn(LP.CharacterAdded:Connect(g(function(c) task.defer(g(trackChar), c) end)))
	if LP.Character then task.defer(g(trackChar), LP.Character) end
	for _, p in P:GetPlayers() do
		if p ~= LP then cn(p.CharacterAdded:Connect(g(function(c) task.defer(g(trackChar), c) end))) end
	end
	cn(P.PlayerAdded:Connect(g(function(p) cn(p.CharacterAdded:Connect(g(function(c) task.defer(g(trackChar), c) end))) end)))
	cn(RS.Heartbeat:Connect(g(hb)))
	pcall(function() RS:UnbindFromRenderStep("MLCam2") end)
	RS:BindToRenderStep("MLCam2", Enum.RenderPriority.Camera.Value + 1, g(camStep))
	task.spawn(g(function()
		while GENV.__MoveLogger == Self do
			task.wait(0.25)
			if Rec.state == "recording" then UI.refreshRecord() end
		end
	end))
end)

print("[MoveLogger] v2.6 loaded")