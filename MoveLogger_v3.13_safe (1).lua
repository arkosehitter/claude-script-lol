--[[ MoveLogger v3.13 — move recorder for battlegrounds games. F6 start/stop, F7 arm, F8 hide, F9 hit phase. ]] local __ML_MAIN = function()
-- 3.13: a Combat tab - one button per thing to log (M1 chain hit / miss, downslam, uppercut, each dash direction,
-- block / parry, other): it starts on your next input, stops by itself when you're done, and is labelled; Guided runs
-- through all of them in turn; Copy breakdown (just the combat part) and Export .txt (the full logs). Attacks the game
-- keeps its animations for under its Animate script are no longer taken for walk / idle; and the real reason your
-- animations went missing (3.10-3.12): a check on effect rigs errored on every animation while recording - fixed;
-- any of yours seen playing but not caught are filled in from AllTracks; AllTracks' LastAt fixed.
-- 3.12: M1 / combo logging - every swing of a chain (its input / on-screen button, M1 number, downslam in the air, uppercut
-- with jump held, dash, hit or miss, damage, reactions, knockback, lunge, its sounds / effects / hitboxes, the gaps and the
-- reset after); Dashes (direction, distance, speed); Inputs (keys, clicks, taps, on-screen buttons); Weapons (tools / swords /
-- axes / gloves on you: the joint and its C0 / C1, where it sits, its meshes, a builder, its swing path from your root 30x a
-- second, anything switched on in it, drawn / put away / moved hand); EffectChanges / ScreenChanges (every property set on an
-- effect after it appeared, frame by frame - tweens, emitters on / off, colours, sizes, moves, things added inside it - and on
-- ColorCorrection / Bloom / Blur / Lighting / the camera); effect motion sampled for 3s with rotation.
-- 3.11: animations are seen on every Animator in a character (not only the Humanoid's), any track playing that the
-- game never announced is picked up within 0.1s, and every recording lists AllTracks - every animation seen playing on
-- you / them, polled straight from their Animators - and AnimSetup (how your character is animated there).
-- 3.10: a rig that isn't anyone's character is logged (with its builder) the first time it animates near you - Hero's
-- ANIMATEABLEBUILDING is brought in with the city long before you get there.
-- 3.9: a rig the game brings in far away (Hero's ANIMATEABLEBUILDING in the city) is logged when it comes in range;
-- a map used again is logged again in each recording.
-- 3.8: effects that only came into range a moment after they appeared (welded on / moved into place a frame later -
-- Hero's setuppart, part pools), or that were only ever :Emit()ted, are logged too (True Evil's startup dust, arms...)
-- 3.7: rigs the game brings in that aren't characters (Hero's ANIMATEABLEBUILDING) are logged as effects too (with
-- builders); a recording isn't named after the game's plumbing (PlaySound, MauioShake...) any more.
-- 3.6: World CFrames on effects / your path / victims; Teleports; Maps (Hero's city); Source = the template each
-- effect was cloned from; EffectAnimations (wings, hands, buildings); CharacterCopies; pooled parts (Pooled = true);
-- HeroCalls / HeroCutscenes (exact camera keyframes) / QTE (its sounds kept out of Sounds); effects that appeared
-- just before a teleport are no longer lost

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
	for _, c in pairs(Bag) do pcall(function() c:Disconnect() end) end
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
	Remotes = true, Cam = true, Screen = true, Adv = false, Debug = false, MaxClones = 200, StartOnFx = true, Hooks = true, Templates = true, Zip = false, ZipOver = 120000,
	RIgnore = "Chat,Message,Mute,Channel,Ping,Leaderboard,Cosmetic,Title,Notif,Mouse,Aim,Position,Cframe",
	SIgnore = "Running,Jumping,FreeFall,Landing,Swimming,Climbing,GettingUp,Died,Splash,Music,Theme,Ambience",
	Spike = 12, Phase = 4, Shake = 0.35, MaxEv = 8000, HitPreroll = 4,
	Combo = true, ComboGap = 1.3, Inputs = true, Weapons = true, Changes = true, ChangeLife = 8, MaxChanges = 12000,
}
local CATS = { "ANIM", "MARKER", "VELOCITY", "SOUND", "VFX", "EFFECT", "TWEEN", "HITBOX", "MOVE", "HIT", "STATE", "CAMERA", "SCREEN", "REMOTE", "REPLICATION", "WORLD", "INPUT", "WEAPON" }
local CC = {
	ANIM = Color3.fromRGB(120, 160, 255), MARKER = Color3.fromRGB(170, 140, 255), VELOCITY = Color3.fromRGB(90, 230, 220),
	SOUND = Color3.fromRGB(90, 210, 160), VFX = Color3.fromRGB(255, 170, 70), HITBOX = Color3.fromRGB(255, 80, 90),
	MOVE = Color3.fromRGB(80, 200, 255), HIT = Color3.fromRGB(255, 110, 140), STATE = Color3.fromRGB(220, 220, 120),
	CAMERA = Color3.fromRGB(150, 220, 255), SCREEN = Color3.fromRGB(240, 140, 220), REMOTE = Color3.fromRGB(170, 175, 190),
	REPLICATION = Color3.fromRGB(130, 200, 200), WORLD = Color3.fromRGB(255, 225, 120), EFFECT = Color3.fromRGB(255, 120, 200), TWEEN = Color3.fromRGB(200, 170, 110),
	INPUT = Color3.fromRGB(200, 200, 255), WEAPON = Color3.fromRGB(255, 200, 150),
}
local SHOW = {}
for _, c in pairs(CATS) do SHOW[c] = true end
local T = {
	Bg = Color3.fromRGB(14, 15, 20), Pan = Color3.fromRGB(22, 24, 31), Pan2 = Color3.fromRGB(30, 33, 42),
	Stroke = Color3.fromRGB(48, 52, 66), Text = Color3.fromRGB(232, 235, 242), Sub = Color3.fromRGB(140, 146, 165),
	Acc = Color3.fromRGB(118, 136, 255), Rec = Color3.fromRGB(255, 72, 88), Arm = Color3.fromRGB(255, 190, 70),
	Good = Color3.fromRGB(110, 220, 150), Hit = Color3.fromRGB(255, 140, 70),
}

---------------------------------------------------------------------------------------------------
local function now() return os.clock() end
local X = {}
function X.srv()
	local ok, v = pcall(workspace.GetServerTimeNow, workspace)
	return ok and v or 0
end
function X.ping()
	local ok, v = pcall(LP.GetNetworkPing, LP)
	return ok and tonumber(v) or nil
end
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
	for _, p in pairs(l) do if string.find(n, p, 1, true) then return true end end
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
-- (heavy logging work runs as jobs: coroutines that stop for the frame once ~3ms are used, and carry on next frame -
-- so dumping an effect with 100+ emitters spreads over a few frames instead of freezing one)
X.jobs, X.deadline, X.co = {}, math.huge, nil
function X.check()
	if X.co and os.clock() > X.deadline and coroutine.running() == X.co then coroutine.yield() end
end
-- (3.3) looping effects: each emitter / beam / trail in a new effect - when it's switched on and off, and how
-- often it's :Emit()ed again (an effect the game keeps going, not just bursts once)
X.loopOf = setmetatable({}, { __mode = "k" })
function X.watchLoops(root, d, born)
	local L = {}
	d.loops = L
	local cs = {}
	local function watch(e)
		if not (e:IsA("ParticleEmitter") or e:IsA("Beam") or e:IsA("Trail")) or X.loopOf[e] then return end
		local r = { name = e.Name, class = e.ClassName, on = e.Enabled and born or nil, off = nil, emits = {} }
		if #L < 60 then L[#L + 1] = r end
		X.loopOf[e] = r
		cs[#cs + 1] = e:GetPropertyChangedSignal("Enabled"):Connect(function()
			if e.Enabled then
				if not r.on or r.off then r.on = r.on or now() r.off = nil end
			elseif r.on and not r.off then
				r.off = now()
			end
		end)
	end
	watch(root)
	for _, e in pairs(root:GetDescendants()) do watch(e) end
	cs[#cs + 1] = root.DescendantAdded:Connect(watch)
	local c
	c = root.AncestryChanged:Connect(function(_, p)
		if p == nil then
			c:Disconnect()
			for _, x in pairs(cs) do x:Disconnect() end
			for _, r in pairs(L) do if r.on and not r.off then r.off = now() end end
		end
	end)
end
-- (what's looping in an effect: on for a while, or emitted again and again)
function X.loopList(d, t0)
	local o = {}
	for _, r in pairs(d.loops or {}) do
		local n = #r.emits
		local onFor = r.on and ((r.off or now()) - r.on) or 0
		if onFor > 0.15 or n >= 3 then
			local every = n >= 2 and (r.emits[n] - r.emits[1]) / (n - 1) or 0
			o[#o + 1] = string.format("{ Name = %q, Class = %q, On = %s, Off = %s, Emits = %d, Every = %s }", r.name, r.class,
				r.on and string.format("%.3f", math.max(0, r.on - t0)) or "nil", r.off and string.format("%.3f", math.max(0, r.off - t0)) or "nil", n,
				string.format("%.3f", every))
		end
	end
	return o
end
function X.job(fn, ...)
	X.jobs[#X.jobs + 1] = { coroutine.create(fn), table.pack(...) }
end
function X.pump(budget)
	X.deadline = os.clock() + budget
	while #X.jobs > 0 do
		local j = X.jobs[1]
		X.co = j[1]
		local ok, err = coroutine.resume(j[1], table.unpack(j[2], 1, j[2].n))
		X.co = nil
		if not ok and C.Debug then warn("[ML] job: " .. tostring(err)) end
		if coroutine.status(j[1]) == "dead" then
			table.remove(X.jobs, 1)
		else
			break -- (it paused: the frame's budget is used up)
		end
		if os.clock() > X.deadline then break end
	end
	X.deadline = math.huge
end
-- (finish everything now - when a recording ends)
function X.drain()
	local guard = 0
	while #X.jobs > 0 and guard < 100000 do
		guard = guard + 1
		X.pump(math.huge)
	end
end
local function idx(i, p) return i[p] end
local function gp(i, p)
	if X.co then X.check() end
	local ok, v = pcall(idx, i, p)
	if ok then return v end
	return nil
end
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
local function isMe(m)
	if not m then return false end
	local c = LP.Character
	if m == c then return true end
	if c and m:IsDescendantOf(c) then return true end
	if P:GetPlayerFromCharacter(m) == LP then return true end
	return m.Name == LP.Name or m.Name == LP.DisplayName
end
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
	if r and cf then
		-- (3.1: a world effect is measured from where your root was when it appeared, not when it got processed)
		local at = X and X.bornT and X.rootAt and X.rootAt(X.bornT)
		return (at or r.CFrame):ToObjectSpace(cf)
	end
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
		for _, k in pairs(s.Keypoints) do o[#o + 1] = { time = rd(k.Time, 4), value = rd(k.Value, 4), envelope = rd(k.Envelope, 4) } end
		return { kind = "number", keypoints = o }
	elseif t == "ColorSequence" then
		local o = {}
		for _, k in pairs(s.Keypoints) do o[#o + 1] = { time = rd(k.Time, 4), color = hex(k.Value), rgb = rgb(k.Value) } end
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
	for _, k in pairs(d.keypoints or {}) do
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
		for _, k in pairs(s.Keypoints) do o[#o + 1] = fn(k.Time, 2) .. ":" .. hex(k.Value) end
		return table.concat(o, " → ")
	end
	if t == "NumberSequence" then
		local o = {}
		for _, k in pairs(s.Keypoints) do o[#o + 1] = fn(k.Time, 2) .. ":" .. fn(k.Value, 3) end
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
		for k, x in pairs(v) do
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
	for k, x in pairs(v) do o[type(k) == "number" and k or tostring(k)] = plain(x, d + 1) end
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
	return isMe(m) and "YOU" or m.Name
end
local function inScope(m)
	if not m then return false end
	if isMe(m) or Rec.victims[m] then return true end
	if not C.Others then return false end
	local r = rootOf(m)
	return r ~= nil and inR(r.Position)
end

function log(cat, who, text, data)
	if Rec.state == "idle" then return nil end
	local ev = { t = now(), st = X.srv(), cat = cat, who = wname(who), model = who, text = text, data = data or {} }
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
	if not m or isMe(m) or Rec.noVic then return nil end
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
	for _, ev in pairs(Rec.events) do if ev.model == m then ev.victim = true end end
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
			for _, kf in pairs(s:GetKeyframes()) do
				info.len = math.max(info.len, kf.Time)
				for _, m in pairs(kf:GetMarkers()) do info.markers[#info.markers + 1] = { name = m.Name, time = kf.Time, value = m.Value } end
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
	-- (3.13: an attack - Action priority or above, not looped - is never walk / idle, wherever the game keeps its
	-- Animation (some keep their M1s under the character's Animate script))
	if not tr.Looped and tr.Priority.Value >= Enum.AnimationPriority.Action.Value then return false end
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
	if C.IgnoreCore and isCore(tr, m) then
		if m == me() and not already then X.skipped = (X.skipped or 0) + 1 end
		return
	end
	if live[tr] then return end
	local a = tr.Animation
	local id = a and aid(a.AnimationId) or "?"
	if not already and m == me() and Rec.state == "armed" and C.StartOnAnim and tr.Priority.Value >= Enum.AnimationPriority.Action.Value then
		startRec("animation " .. (a and a.Name or id), "startup")
	end
	if m ~= me() then markV(m, "animation") end
	-- (3.10: a rig that isn't anyone's character (Hero's ANIMATEABLEBUILDING) - logged as an effect, with its builder,
	-- the first time it animates near you: it may have been brought in long before, far away)
	-- (3.13: FXSET is declared further down - read through X, or every animation errored here while recording)
	if Rec.state == "recording" and X.rigFx and X.FXSET and not X.FXSET[m] and not X.rigDone[m] and P:GetPlayerFromCharacter(m) == nil
		and not P:FindFirstChild(m.Name) and not isMe(m) and not any(m.Name, { "dummy", "training", "target" }) then
		X.rigDone[m] = true
		X.rigFx[m] = true
		pcall(X.lateFx, m, now())
	end
	fetch(id)
	local d = { id = id, name = a and a.Name or "?", priority = tr.Priority.Name, looped = tr.Looped, speed = rd(tr.Speed, 3), length = rd(tr.Length, 3) }
	if m == me() then pcall(X.animState, d) end
	local since = 0
	do
		local spd, tp = tr.Speed, tr.TimePosition
		local ok = not (spd ~= spd or spd == math.huge or spd <= 0.01)
		if already then
			since = ok and tp / spd or 0
			d.already, d.timePosition = true, rd(tp, 3)
		elseif ok and tp > 0.01 and (tr.Length <= 0 or tp < tr.Length) then
			-- (it reached us already this far in: it started on the server / another screen that much earlier)
			since = tp / spd
			d.lagCompensated = rd(since, 3)
		end
	end
	-- (the same animation started twice on one character within a frame or two: one is a copy - keep one)
	for otr, a in pairs(live) do
		if otr ~= tr and a.model == m and a.ev.data.id == id and math.abs((now() - since) - (a.start or a.t0)) < 0.08 then
			return
		end
	end
	local ev = log("ANIM", m, (already and "≡ (already playing, from ~" .. fn(since, 2) .. "s before) " or "▶ ") .. d.name .. " rbxassetid://" .. id .. " (" .. d.priority .. (d.looped and ", looped" or "") .. ", speed " .. fn(d.speed, 2) .. ")", d)
	if not ev then return end
	if since > 0 then ev.t = ev.t - since end
	local t0, cons = now(), {}
	live[tr] = { ev = ev, model = m, speed = tr.Speed, t0 = t0, tp = 0, start = ev.t }
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
		for _, mk in pairs(info.markers) do
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
	local live_start = ev.t
	tr.Stopped:Once(g(function()
		for _, c in pairs(cons) do c:Disconnect() end
		live[tr] = nil
		d.played = rd(now() - (live_start or t0), 3)
		log("ANIM", m, "■ " .. d.name .. " stopped after " .. fn(d.played, 3) .. "s", { id = id, name = d.name, kind = "stop", played = d.played })
	end))
end

local function snapTracks(m)
	if not m then return end
	local h = m:FindFirstChildOfClass("Humanoid")
	local an = h and h:FindFirstChildOfClass("Animator")
	if not an then return end
	for _, tr in pairs(sf(function() return an:GetPlayingAnimationTracks() end) or {}) do
		pcall(onAnim, m, tr, true)
	end
end

---------------------------------------------------------------------------------------------------
-- exhaustive effect dump: every readable property, every asset id, every colour
---------------------------------------------------------------------------------------------------
local EPROPS = {
	"Enabled", "Texture", "Color", "Size", "Transparency", "Lifetime", "Rate", "Speed", "SpreadAngle", "Rotation", "RotSpeed",
	"Acceleration", "Drag", "VelocityInheritance", "VelocityInheritence", "Brightness", "FlipbookMode", "LightEmission", "LightInfluence", "ZOffset", "EmissionDirection",
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

---------------------------------------------------------------------------------------------------
-- rebuildable trees: an effect written out as the instances it's made of (every part / attachment / emitter /
-- beam / trail / mesh / light, where each sits, every property a script can set) - so the log alone rebuilds it
local TREEPROPS = {
	BasePart = { "Size", "Color", "Material", "Transparency", "Reflectance", "CastShadow", "Anchored", "CanCollide", "CanQuery", "CanTouch", "Massless", "Shape" },
	MeshPart = { "MeshId", "TextureID", "RenderFidelity", "DoubleSided" },
	SpecialMesh = { "MeshType", "MeshId", "TextureId", "Scale", "Offset", "VertexColor" },
	BlockMesh = { "Scale", "Offset", "VertexColor" }, CylinderMesh = { "Scale", "Offset", "VertexColor" },
	Decal = { "Texture", "Color3", "Transparency", "Face", "ZIndex" },
	Texture = { "Texture", "Color3", "Transparency", "Face", "ZIndex", "StudsPerTileU", "StudsPerTileV", "OffsetStudsU", "OffsetStudsV" },
	Attachment = { "CFrame", "Visible" },
	ParticleEmitter = EPROPS, Beam = BPROPS, Trail = TPROPS,
	PointLight = { "Brightness", "Color", "Range", "Shadows", "Enabled" },
	SpotLight = { "Brightness", "Color", "Range", "Shadows", "Enabled", "Angle", "Face" },
	SurfaceLight = { "Brightness", "Color", "Range", "Shadows", "Enabled", "Angle", "Face" },
	Highlight = { "FillColor", "OutlineColor", "FillTransparency", "OutlineTransparency", "DepthMode", "Enabled" },
	Fire = { "Color", "SecondaryColor", "Heat", "Size", "Enabled", "TimeScale" },
	Smoke = { "Color", "Opacity", "RiseVelocity", "Size", "Enabled", "TimeScale" },
	Sparkles = { "SparkleColor", "Enabled", "TimeScale" },
	Weld = { "C0", "C1", "Part0", "Part1" }, Motor6D = { "C0", "C1", "Part0", "Part1" }, WeldConstraint = { "Part0", "Part1" },
	Sound = { "SoundId", "Volume", "PlaybackSpeed", "Looped", "RollOffMode", "RollOffMinDistance", "RollOffMaxDistance" },
	BillboardGui = { "Size", "StudsOffset", "StudsOffsetWorldSpace", "AlwaysOnTop", "LightInfluence", "MaxDistance", "Brightness" },
	ImageLabel = { "Size", "Position", "AnchorPoint", "Image", "ImageColor3", "ImageTransparency", "BackgroundTransparency", "Rotation" },
}
local TREESKIP = { Script = true, LocalScript = true, ModuleScript = true, Humanoid = true, Animator = true }
function X.snap(root, budget)
	budget = budget or { n = 0 }
	local rootCF = (root:IsA("BasePart") and root.CFrame) or (root:IsA("Model") and sf(function() return root:GetPivot() end)) or nil
	local function path(i)
		if not i then return nil end
		if i == root then return "." end
		if i:IsDescendantOf(root) then
			local o, n = {}, i
			while n and n ~= root do table.insert(o, 1, n.Name) n = n.Parent end
			return table.concat(o, ".")
		end
		return "<outside> " .. sp(i, 3)
	end
	local function one(i, depth)
		if budget.n >= 1500 or TREESKIP[i.ClassName] then return nil end
		budget.n = budget.n + 1
		local node = { c = i.ClassName, n = i.Name, p = {}, k = {} }
		local seen = {}
		for cls, list in pairs(TREEPROPS) do
			if i:IsA(cls) then
				for _, k in pairs(list) do
					if not seen[k] then
						seen[k] = true
						local v = gp(i, k)
						if v ~= nil then
							if typeof(v) == "Instance" then
								node.p[k] = { ref = path(v) }
							elseif k == "CFrame" and i:IsA("BasePart") and rootCF then
								node.p[k] = rootCF:ToObjectSpace(v)
							else
								node.p[k] = v
							end
						end
					end
				end
			end
		end
		local at = i:GetAttributes()
		if next(at) then node.a = at end
		if depth < 8 then
			for _, c in pairs(i:GetChildren()) do
				local k2 = one(c, depth + 1)
				if k2 then node.k[#node.k + 1] = k2 end
			end
		end
		return node
	end
	return one(root, 0)
end
-- a value as Luau source
function X.lit(v)
	local t = typeof(v)
	if t == "number" then return fn(v, 4)
	elseif t == "boolean" then return tostring(v)
	elseif t == "string" then return string.format("%q", v)
	elseif t == "Vector3" then return "Vector3.new(" .. fn(v.X, 4) .. ", " .. fn(v.Y, 4) .. ", " .. fn(v.Z, 4) .. ")"
	elseif t == "Vector2" then return "Vector2.new(" .. fn(v.X, 4) .. ", " .. fn(v.Y, 4) .. ")"
	elseif t == "CFrame" then
		local c = { v:GetComponents() }
		for x = 1, 12 do c[x] = fn(c[x], 5) end
		return "CFrame.new(" .. table.concat(c, ", ") .. ")"
	elseif t == "Color3" then return string.format("Color3.fromRGB(%d, %d, %d)", math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255))
	elseif t == "NumberRange" then return "NumberRange.new(" .. fn(v.Min, 4) .. ", " .. fn(v.Max, 4) .. ")"
	elseif t == "NumberSequence" then
		local o = {}
		for _, k in pairs(v.Keypoints) do o[#o + 1] = "NumberSequenceKeypoint.new(" .. fn(k.Time, 4) .. ", " .. fn(k.Value, 4) .. ", " .. fn(k.Envelope, 4) .. ")" end
		return "NS({ " .. table.concat(o, ", ") .. " })"
	elseif t == "ColorSequence" then
		local o = {}
		for _, k in pairs(v.Keypoints) do
			o[#o + 1] = string.format("ColorSequenceKeypoint.new(%s, Color3.fromRGB(%d, %d, %d))", fn(k.Time, 4), math.round(k.Value.R * 255), math.round(k.Value.G * 255), math.round(k.Value.B * 255))
		end
		return "CS({ " .. table.concat(o, ", ") .. " })"
	elseif t == "EnumItem" then return tostring(v)
	elseif t == "UDim2" then return string.format("UDim2.new(%s, %s, %s, %s)", fn(v.X.Scale, 4), fn(v.X.Offset), fn(v.Y.Scale, 4), fn(v.Y.Offset))
	elseif t == "UDim" then return string.format("UDim.new(%s, %s)", fn(v.Scale, 4), fn(v.Offset))
	elseif t == "table" and v.ref then return "REF(" .. string.format("%q", v.ref) .. ")"
	end
	return nil
end
function X.treeLua(node, ind)
	ind = ind or ""
	local ps = {}
	local keys = {}
	for k in pairs(node.p) do keys[#keys + 1] = k end
	table.sort(keys)
	for _, k in pairs(keys) do
		local s2 = X.lit(node.p[k])
		if s2 then ps[#ps + 1] = k .. " = " .. s2 end
	end
	local at = {}
	for k, v in pairs(node.a or {}) do
		local s2 = X.lit(v)
		if s2 then at[#at + 1] = string.format("[%q] = %s", k, s2) end
	end
	local o = ind .. string.format("N(%q, %q, { %s }, { %s }", node.c, node.n, table.concat(ps, ", "), table.concat(at, ", "))
	if #node.k > 0 then
		local kids = {}
		for _, c in pairs(node.k) do kids[#kids + 1] = X.treeLua(c, ind .. "\t") end
		o = o .. ", {\n" .. table.concat(kids, ",\n") .. "\n" .. ind .. "})"
	else
		o = o .. ")"
	end
	return o
end
X.TREEHEADER = [==[
	-- paste-ready builders: Builders["name"]() returns a fresh copy (parts' CFrames are relative to the first part).
	-- (MeshPart MeshIds can't be set from a script: make those parts with AssetService:CreateMeshPartAsync(MeshId).)
	-- local function NS(k) return NumberSequence.new(k) end
	-- local function CS(k) return ColorSequence.new(k) end
	-- local function REF(path) return path end -- (Part0 / Attachment0 etc.: hook them up after building)
	-- local function N(class, name, props, attrs, kids)
	-- 	local i = Instance.new(class) i.Name = name
	-- 	for k, v in pairs(props) do if type(v) ~= "string" or k ~= "Part0" and k ~= "Part1" and k ~= "Attachment0" and k ~= "Attachment1" then pcall(function() i[k] = v end) end end
	-- 	for k, v in pairs(attrs) do i:SetAttribute(k, v) end
	-- 	for _, c in pairs(kids or {}) do c.Parent = i end
	-- 	return i
	-- end]==]

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
		for _, kp in pairs(d[k].keypoints) do d.colors[#d.colors + 1] = { property = k, hex = kp.color, rgb = kp.rgb } end
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
	for _, p in pairs(list) do take(p) end
	local ok, all = pcall(function() return i:GetProperties() end)
	if ok and type(all) == "table" then
		local ks = {}
		for k in pairs(all) do if type(k) == "string" then ks[#ks + 1] = k end end
		table.sort(ks)
		for _, k in pairs(ks) do take(k) end
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
	for _, p in pairs(HBNAMES) do if string.find(n, p, 1, true) then return true end end
	return false
end

local function hasVis(i)
	if VIS[i.ClassName] or i:IsA("Decal") or i:IsA("Texture") then return true end
	for _, d in pairs(i:GetDescendants()) do
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
		d.world = cf
		if Rec.startCF then d.startOffset = Rec.startCF:ToObjectSpace(cf).Position end
		-- (3.2: a world effect also measured from the camera - some sit in front of it)
		local cam = X.bornT and X.camAt(X.bornT)
		if cam then d.camCF = cam:ToObjectSpace(cf) end
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
	for _, n in pairs(i:GetDescendants()) do scan(n) end
	for _, grp in { d.emitters, d.beams, d.trails, d.meshes, d.sounds } do
		for _, e in pairs(grp) do
			for _, a in pairs(e.assets or {}) do d.assets[#d.assets + 1] = a end
			for _, c in pairs(e.colors or {}) do d.colors[#d.colors + 1] = c end
		end
	end
	for _, w in pairs(i:GetDescendants()) do
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
	for m in pairs(tracked) do
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

-- a weld / constraint that joins two different characters: a grab. Logs where it holds them relative to you.
X.WELDS = { Weld = true, WeldConstraint = true, Motor6D = true, ManualWeld = true, ManualGlue = true, Snap = true, RigidConstraint = true,
	AlignPosition = true, AlignOrientation = true, BallSocketConstraint = true, RopeConstraint = true, RodConstraint = true, HingeConstraint = true }
function X.ends(i)
	local a = gp(i, "Part0") or (gp(i, "Attachment0") and gp(i, "Attachment0").Parent)
	local b = gp(i, "Part1") or (gp(i, "Attachment1") and gp(i, "Attachment1").Parent)
	return a, b
end
function X.weld(i)
	if not i.Parent or Rec.state == "idle" then return end
	local a, b = X.ends(i)
	if not (a and b) then
		-- (Part0 / Part1 often get set right after the weld is made)
		X.retried = X.retried or setmetatable({}, { __mode = "k" })
		if not X.retried[i] then
			X.retried[i] = true
			task.delay(0.05, g(X.weld), i)
		end
		return
	end
	local ca, cb = chOf(a), chOf(b)
	if not ca or not cb or ca == cb then return end
	if not (inScope(ca) or inScope(cb)) then return end
	local mine2 = isMe(ca) and ca or (isMe(cb) and cb) or nil
	local other = (mine2 == ca) and cb or ca
	if mine2 then markV(other, "grabbed") end
	local r = myRoot()
	local orr = rootOf(other)
	local rel = (r and orr) and r.CFrame:ToObjectSpace(orr.CFrame) or nil
	local d = { kind = "weld", class = i.ClassName, part0 = sp(a, 3), part1 = sp(b, 3), c0 = gp(i, "C0"), c1 = gp(i, "C1"), holder = mine2 and "YOU" or ca.Name,
		held = other.Name, rel = rel }
	local txt = "🔗 " .. i.ClassName .. " joins " .. d.part0 .. " ↔ " .. d.part1
	if rel then
		local _, yw = rel:ToOrientation()
		txt = txt .. " - holds " .. other.Name .. " at " .. dw(rel.Position) .. " from you, facing " .. fn(math.deg(yw), 0) .. "°"
	end
	local ev = log("MOVE", other, txt, d)
	local t0 = now()
	i.Destroying:Once(g(function()
		if Rec.state == "idle" then return end
		log("MOVE", other, "⛓ " .. i.ClassName .. " released after " .. fn(now() - t0, 3) .. "s", { kind = "weldEnd", class = i.ClassName, held = other.Name, after = rd(now() - t0, 3) })
	end))
	return ev
end
-- spans where a victim stayed at one spot relative to you (held / carried / pinned), from their track
function X.holds(tr)
	local o = {}
	local cur = nil
	local function close()
		if cur and cur.last.t - cur.first.t >= 0.25 then
			local moved = (cur.last.wp - cur.first.wp).Magnitude
			o[#o + 1] = { from = cur.first.t, to = cur.last.t, rel = cur.first.rel, yaw = cur.first.yaw, dist = cur.first.dist, carried = rd(moved, 2) }
		end
		cur = nil
	end
	for _, p in pairs(tr) do
		if p.rel and p.wp then
			if cur and (p.rel - cur.first.rel).Magnitude <= 0.2 and math.abs(((p.yaw or 0) - (cur.first.yaw or 0) + 180) % 360 - 180) <= 6 then
				cur.last = p
			else
				close()
				cur = { first = p, last = p }
			end
		end
	end
	close()
	return o
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
	for _, t in pairs(m:GetTags()) do info.tags[t] = true end
	tracked[m] = info
	local cons = info.conns
	local function add(c) cons[#cons + 1] = c end
	-- (3.11: every Animator in the character - some games animate through an AnimationController or a rig inside the
	-- character, not the Humanoid's Animator - and, every 0.1s, any track playing there that wasn't announced)
	info.animators = {}
	local function anim(an)
		for _, x in pairs(info.animators) do if x == an then return end end
		table.insert(info.animators, an)
		add(an.AnimationPlayed:Connect(g(function(tr) onAnim(m, tr) end)))
	end
	for _, x in pairs(m:GetDescendants()) do if x:IsA("Animator") then anim(x) end end
	add(m.DescendantAdded:Connect(g(function(c) if c:IsA("Animator") then anim(c) end end)))
	task.spawn(function()
		while tracked[m] == info and m.Parent do
			task.wait(0.1)
			if Rec.state ~= "idle" then
				for _, an2 in pairs(info.animators) do
					if an2.Parent then
						for _, tr in pairs(sf(function() return an2:GetPlayingAnimationTracks() end) or {}) do
							if not live[tr] then pcall(onAnim, m, tr, true) end
						end
					end
				end
			end
		end
	end)

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
	for _, d in pairs(m:GetDescendants()) do
		if VIS[d.ClassName] then logToggle(d, m) end
		if d:IsA("BasePart") and isHB(d.Name) then task.defer(g(hookHB), d, m) end
	end
	add(m.Destroying:Connect(function()
		for _, c in pairs(cons) do pcall(function() c:Disconnect() end) end
		tracked[m] = nil
	end))
end

---------------------------------------------------------------------------------------------------
local hsounds = setmetatable({}, { __mode = "k" })
local sIgnore = lst(C.SIgnore)
local function logSnd(s, fresh)
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
	local pk = X.sndPeak[s]
	local vol = s.Volume
	if pk then
		vol = math.max(vol, pk.v)
		pk.until_ = now() + 0.15 -- (a few frames more: the game may still be setting it)
	end
	local d = { id = id, name = s.Name, volume = rd(vol, 3), playedVolume = rd(s.Volume, 3), flat = (p == nil), setting = X.volSetting(), speed = rd(s.PlaybackSpeed, 3), timePosition = rd(s.TimePosition, 3),
		looped = s.Looped, parent = sp(s.Parent, 4), rollOffMode = s.RollOffMode.Name, rollOffMin = rd(s.RollOffMinDistance, 1),
		rollOffMax = rd(s.RollOffMaxDistance, 1), emitterSize = rd(s.EmitterSize, 2), length = rd(s.TimeLength, 3), offset = rel and rel.Position }
	-- (3.6: the QTE prompt's own sounds (Hero's QTEHandler) - kept apart: they're the prompt, not the move)
	if string.find(sp(s.Parent, 6), "QTE", 1, true) or s.Name == "QTEHit" or s.Name == "QTEMiss" then d.qte = true end
	local sev = log("SOUND", own, "♪ " .. s.Name .. " rbxassetid://" .. tostring(id) .. " (vol " .. fn(d.volume, 2) .. ", pitch " .. fn(d.speed, 2) .. ") on " .. d.parent, d)
	if not sev then return end
	-- (3.5) where in the audio it starts: a sound that just started (Played) at TimePosition > 0 was started
	-- that far in on purpose; one we only found already playing started earlier (lag) - moved back instead.
	-- The game may also seek it just after :Play(), or play only a region of it - both are caught below.
	local spd = s.PlaybackSpeed > 0.01 and s.PlaybackSpeed or 1
	if fresh then
		d.startAt = rd(s.TimePosition, 3)
	else
		if s.TimePosition > 0.01 and s.TimePosition < 2 then sev.t = sev.t - s.TimePosition / spd end
		d.startAt = 0
		d.foundPlaying = true
	end
	pcall(function()
		if s.PlaybackRegionsEnabled and s.PlaybackRegion.Min > (d.startAt or 0) then
			d.startAt = rd(s.PlaybackRegion.Min, 3)
			d.region = { rd(s.PlaybackRegion.Min, 3), rd(s.PlaybackRegion.Max, 3) }
		end
	end)
	do
		local tp0, c0 = s.TimePosition, now()
		local seeks = {}
		local last, lastT = tp0, c0
		local sc
		sc = s:GetPropertyChangedSignal("TimePosition"):Connect(function()
			local t = now()
			if t - c0 > 3 then sc:Disconnect() return end
			local expect = last + (t - lastT) * spd
			local tp = s.TimePosition
			if math.abs(tp - expect) > 0.08 then
				-- (a jump: set by the game, not just playing on)
				if t - c0 < 0.3 and fresh then d.startAt = rd(tp - (t - c0) * spd, 3) else if #seeks < 8 then seeks[#seeks + 1] = { rd(t - c0, 3), rd(tp, 3) } end end
				d.seeks = seeks
			end
			last, lastT = tp, t
		end)
		s.Destroying:Once(function() sc:Disconnect() end)
		-- (and a check a moment in, for games that set it without the change being seen)
		task.delay(0.12, function()
			if not s.Parent or not s.IsPlaying then return end
			local est = s.TimePosition - (now() - c0) * spd
			if fresh and est > (d.startAt or 0) + 0.06 then d.startAt = rd(est, 3) end
		end)
	end
	d.timePosition = d.startAt or d.timePosition
	local t0, done = now(), false
	local function fin()
		if done then return end
		done = true
		d.played = rd(now() - t0, 3)
	end
	s.Stopped:Once(fin); s.Ended:Once(fin); s.Destroying:Once(fin)
	if pk then task.delay(0.2, function() d.volume = rd(math.max(d.volume, pk.v), 3) end) end
end
-- (3.4) a sound's real volume: games often set it after the sound appears, then scale it by the player's own
-- volume setting as it plays - so the loudest it was set to before (and just after) it started is kept
X.sndPeak = setmetatable({}, { __mode = "k" })
function X.volSetting()
	local best = nil
	for _, o in { P.LocalPlayer, P.LocalPlayer and P.LocalPlayer.Character } do
		if o then
			for k, v in pairs(o:GetAttributes()) do
				if type(v) == "number" and string.find(string.lower(k), "vol") then best = best or { k, v } end
			end
		end
	end
	return best
end
function hookSnd(s)
	if hsounds[s] then return end
	hsounds[s] = true
	local pk = { v = s.Volume, until_ = math.huge }
	X.sndPeak[s] = pk
	local vc
	vc = s:GetPropertyChangedSignal("Volume"):Connect(function()
		if now() > pk.until_ then vc:Disconnect() return end
		if s.Volume > pk.v then pk.v = s.Volume end
	end)
	s.Destroying:Once(function() vc:Disconnect() end)
	s.Played:Connect(g(function() logSnd(s, true) end))
	if s.Playing and Rec.state ~= "idle" then task.defer(g(logSnd), s, false) end
end

---------------------------------------------------------------------------------------------------
local pend, pFlush, logged, clones, sigs = {}, false, {}, 0, {}
local FXSET = setmetatable({}, { __mode = "k" })
X.FXSET = FXSET

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
	for _, d in pairs(c:GetDescendants()) do if d:IsA("BaseScript") then d.Enabled = false end end
	if c:IsA("BasePart") then c.Anchored = true end
	pcall(function() c.Parent = Rec.save end)
	return c
end

local function process(i, born)
	if not i.Parent or mine(i) then return end
	local own, p = chOf(i), posOf(i)
	if X.rigFx[i] then own = nil end
	-- (3.6: one looked at again after a teleport is measured from where you landed)
	X.bornT = (not own) and (X.measureAt[i] or born) or nil
	X.measureAt[i] = nil
	if own then
		if not inScope(own) then return end
	elseif not p or not inR(p) then
		-- (3.6: out of range now - but you may be teleported there in a moment)
		if p and Rec.state == "recording" then X.farAdd(i, born) end
		return
	end
	if i:IsA("Attachment") and not hasVis(i) then return end
	if X.mapPlain(i) then return end
	if i:IsA("Folder") and #i:GetChildren() == 0 then return end
	local hb = hbKind(i)
	local d = describe(i)
	pcall(X.tag36, i, d, own, born)
	X.bornT = nil
	local cat, txt
	if hb then
		cat = "HITBOX"
		d.hitboxKind = hb
		txt = "▣ " .. (hb == "named" and "hitbox" or "possible hitbox") .. " '" .. i.Name .. "' size " .. (d.size and v3s(d.size) or "?") .. (d.offset and (" at you " .. dw(d.offset)) or "") .. (d.weldedTo and (" welded to " .. d.weldedTo) or "")
	else
		cat = "VFX"
		local o = {}
		for _, e in pairs(d.emitters) do o[#o + 1] = "'" .. e.name .. "'{" .. eText(e) .. "}" end
		for _, e in pairs(d.beams) do o[#o + 1] = "beam '" .. e.name .. "'{" .. eText(e) .. "}" end
		for _, e in pairs(d.trails) do o[#o + 1] = "trail '" .. e.name .. "'{" .. eText(e) .. "}" end
		local ms = {}
		for _, m in pairs(d.meshes) do ms[#ms + 1] = mText(m) end
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
	if cat == "VFX" then pcall(X.fxAnim, i, ev, born) end
	if cat == "VFX" and Rec.state == "recording" then pcall(X.watchLoops, i, d, born) end
	if cat == "VFX" and Rec.state == "recording" and not d.duplicate then pcall(X.watchChanges, i, d, born) end
	if Rec.state == "recording" and not d.duplicate then
		-- (the rebuildable tree is written a little later, a few per frame)
		local budget = Rec.treeBudget
		X.job(function()
			if i.Parent and budget then
				local ok, tree = pcall(X.snap, i, budget)
				if ok then d.tree = tree end
			end
		end)
	end
	if (C.Motion or cat == "HITBOX") and #logged < 250 then logged[#logged + 1] = { inst = i, ev = ev, born = born, samples = {} } end
	local conn
	conn = i.AncestryChanged:Connect(function(_, p2)
		if p2 == nil then
			conn:Disconnect()
			d.lifetime = rd(now() - born, 3)
		end
	end)
	if i:IsA("BasePart") and isHB(i.Name) then task.defer(g(hookHB), i, own) end
end

-- (spread over frames: at most ~4ms of work per frame, so logging a big effect can't freeze the game -
-- a freeze would push every time after it late. Each thing keeps the time it appeared, however late it's read.)
local function flush()
	pFlush = false
	local b = pend
	pend = {}
	for i, born in pairs(b) do
		local n, skip = i.Parent, false
		while n and n ~= workspace and n ~= game do
			if b[n] then skip = true break end
			n = n.Parent
		end
		if not skip then X.job(function() pcall(process, i, born) end) end
	end
	X.pump(0.003)
end

local CAND = { BasePart = true, Model = true, Attachment = true, Folder = true }
local function onDesc(i)
	local cls = i.ClassName
	if cls == "Sound" then hookSnd(i) return end
	if cls == "Humanoid" then
		if i.Parent and i.Parent:IsA("Model") then
			task.defer(g(trackChar), i.Parent)
			-- (3.7: a rig the game brings in that isn't anyone's character - Hero's ANIMATEABLEBUILDING, the furniture -
			-- logged as an effect too, so it has a builder)
			local m = i.Parent
			if Rec.state == "recording" and not FXSET[m] and P:GetPlayerFromCharacter(m) == nil and not P:FindFirstChild(m.Name) and not isMe(m) then
				X.rigFx[m] = true
				task.defer(g(function() if not FXSET[m] then process(m, now()) end end))
			end
		end
		return
	end
	if cls == "RemoteEvent" or cls == "UnreliableRemoteEvent" then
		if UI.hookRemote then UI.hookRemote(i) end
		return
	end
	if Rec.state == "idle" then return end
	if X.WELDS[cls] then task.defer(g(X.weld), i) end
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
	-- (3.6: a part parked far away is a pool's spare: logged when it's moved out to be used)
	if i:IsA("BasePart") and X.isParked(i.Position) then X.park(i) return end
	if X.mapOf(i) and X.mapPlain(i) then return end
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
		for _, k in pairs(c:GetChildren()) do
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
			for _, m in pairs(w:GetChildren()) do
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
		for _, c in pairs(x:GetChildren()) do
			if n >= 60 then return end
			local pth = path .. "." .. c.Name
			if c:IsA("BasePart") or c:IsA("Model") or c:IsA("Attachment") or VIS[c.ClassName] then
				local ok, d = pcall(describe, c)
				n = n + 1
				local ok2, tree = pcall(X.snap, c, { n = 0 })
				out[#out + 1] = { path = pth, class = c.ClassName, d = ok and d or nil, err = (not ok) and tostring(d) or nil, tree = ok2 and tree or nil }
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
	for _, o in pairs(others) do if who == me() and o ~= me() then markV(o, "effect") end end
	if Rec.state == "armed" and who == me() and C.StartOnFx then startRec("effect " .. mod .. "." .. fnm, "startup") end
	local o = {}
	for i = 3, n do o[#o + 1] = ser(l[i]) end
	local d = { module = mod, func = fnm, args = { table.unpack(l, 3, n) }, n = n - 2, assets = assets and sp(assets, 6) or nil }
	if assets then X.noteAssets(assets) end
	if assets and C.Templates then
		d.templates = tplCache[assets] or {}
		X.job(function()
			d.templates = dumpTpl(assets)
		end)
		if Rec.state == "recording" and Rec.save and not fxSaved[assets] then
			fxSaved[assets] = true
			task.defer(function()
				local c = saveClone(assets, "TEMPLATE " .. mod .. "." .. fnm)
				if c then d.saved = c.Name end
			end)
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
	for _, it in pairs(q) do
		local kind, inst = it[1], it[2]
		if inst.Parent or kind == "Emit" then
			local rel, who = fxRel(inst)
			if rel then
				if kind == "Create" then
					local info, goals = it[3], it[4]
					if typeof(info) == "TweenInfo" and type(goals) == "table" and HK.n < 600 then
						HK.n = HK.n + 1
						local gl, gt = {}, {}
						for k, v in pairs(goals) do
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
					local lr = X.loopOf[inst]
					if lr and #lr.emits < 400 then lr.emits[#lr.emits + 1] = it[5] end
					b.list[#b.list + 1] = { name = inst.Name, count = cnt, path = sp(inst, 3) }
					b.total = b.total + cnt
				end
			end
		end
	end
	for root, b in pairs(emits) do
		local names = {}
		for i2, x in pairs(b.list) do
			if i2 > 12 then names[#names + 1] = "…" break end
			names[#names + 1] = x.name .. "×" .. fn(x.count)
		end
		local ev = log("VFX", b.who, "✸ :Emit on " .. #b.list .. " emitter(s) in '" .. sp(root, 3) .. "' total " .. fn(b.total) .. "  " .. table.concat(names, " "),
			{ kind = "emit", root = sp(root, 5), emits = b.list, total = b.total })
		if ev then ev.t = b.t end
		-- (3.8: an effect that was only ever :Emit()ted - moved into place after it appeared, or reused - logged now,
		-- where it is)
		if Rec.state == "recording" and root.Parent and not FXSET[root] and not chOf(root) and (root:IsA("BasePart") or root:IsA("Model") or root:IsA("Attachment")) then
			pcall(X.lateFx, root, b.t)
		end
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
			for _, x in pairs(v) do
				local c = ck(x, d + 1)
				if c then return c end
			end
		end
	end
	for _, x in pairs(a) do
		local c = ck(x, 0)
		if c then return c end
	end
end
local function rLabel(a)
	for _, x in pairs(a) do
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
		pcall(X.heroCall, l, a.n, re)
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
local cam = { fov = 70, run = nil, stable = 0, look = nil, up = nil, ema = 0, shake = nil, cut = nil, ctype = nil }
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
	for _, k in pairs(p) do o[k] = e[k] end
	return o
end
local function snapPosts()
	for _, r in { LIGHT, workspace.CurrentCamera } do
		if r then for _, e in pairs(r:GetChildren()) do if PP[e.ClassName] then snapP[e] = sig(e) end end end
	end
end
local function checkPosts()
	if not C.Screen then return end
	for _, r in { LIGHT, workspace.CurrentCamera } do
		if r then
			for _, e in pairs(r:GetChildren()) do
				if PP[e.ClassName] then
					local o, n = snapP[e], sig(e)
					if o then
						local ch = {}
						for k, v in pairs(n) do if o[k] ~= v then ch[#ch + 1] = k .. " " .. ser(o[k]) .. "→" .. ser(v) end end
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
	if Rec.state == "recording" then pcall(X.watchChanges, e, d, t0) end
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
		for i in pairs(b) do
			local n, skip = i.Parent, false
			while n and n ~= PG do
				if b[n] then skip = true break end
				n = n.Parent
			end
			if not skip and i.Parent then
				local im = {}
				for _, d in pairs(i:GetDescendants()) do
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
-- a scripted camera (a cutscene): every frame of it, relative to your root part at that moment, until the camera
-- goes back to normal; written out as one "Cutscene" entry with its frames
function X.cutEnd(c)
	local k = cam.cut
	if not k then return end
	cam.cut = nil
	local dur = now() - k.t
	if #k.frames < 2 then return end
	local ev = log("CAMERA", nil, "cutscene camera " .. fn(dur, 2) .. "s (" .. #k.frames .. " frames, " .. k.ctype .. ")",
		{ kind = "cutscene", duration = rd(dur, 3), ctype = k.ctype, subject = k.subject, frames = k.frames, fovFrom = k.fov0, fovTo = rd(c and c.FieldOfView or 0, 2) })
	if ev then ev.t = k.t end
	cam.look, cam.fov, cam.rel = nil, c and c.FieldOfView or cam.fov, nil
end
function X.cutStep(c)
	local myHum = me() and me():FindFirstChildOfClass("Humanoid")
	local subj = c.CameraSubject
	local ct = c.CameraType
	if cam.ctype ~= ct then
		if cam.ctype then
			log("CAMERA", nil, "camera type " .. cam.ctype.Name .. " → " .. ct.Name, { kind = "type", from = cam.ctype.Name, to = ct.Name })
		end
		cam.ctype = ct
	end
	local scripted = ct == Enum.CameraType.Scriptable or ct == Enum.CameraType.Fixed or ct == Enum.CameraType.Attach
		or ct == Enum.CameraType.Watch or (subj ~= nil and myHum ~= nil and subj ~= myHum and not (subj:IsA("BasePart") and subj:IsDescendantOf(me())))
	if not scripted then
		if cam.cut then X.cutEnd(c) end
		return false
	end
	local r = myRoot()
	if not cam.cut then
		local sn = subj and (subj:IsDescendantOf(me() or game) and ("yours: " .. subj.Name) or wname(subj:FindFirstAncestorOfClass("Model")) .. "." .. subj.Name) or "none"
		cam.cut = { t = now(), frames = {}, ctype = ct.Name, subject = sn, fov0 = rd(cam.fov, 2) }
		cam.run, cam.shake = nil, nil
	end
	local k = cam.cut
	Rec.lastAct = now()
	if #k.frames >= 4000 then return true end
	local rel = r and r.CFrame:ToObjectSpace(c.CFrame) or c.CFrame
	local rx, ry, rz = rel:ToEulerAnglesYXZ()
	local p = rel.Position
	local f = { rd(now() - k.t, 3), rd(p.X, 2), rd(p.Y, 2), rd(p.Z, 2), rd(math.deg(rx), 2), rd(math.deg(ry), 2), rd(math.deg(rz), 2), rd(c.FieldOfView, 2) }
	local l = k.frames[#k.frames]
	if l and l[2] == f[2] and l[3] == f[3] and l[4] == f[4] and l[5] == f[5] and l[6] == f[6] and l[7] == f[7] and l[8] == f[8] then return true end
	k.frames[#k.frames + 1] = f
	return true
end
local function camStep(dt)
	if Rec.state == "idle" or not C.Cam then return end
	local c = workspace.CurrentCamera
	if not c then return end
	if Rec.state == "recording" and X.cutStep(c) then return end
	X.offsetShake(dt)
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
		-- (3.2: position shakes too - the camera jittering against what it looks at, not just turning)
		local rel = cf.Position - c.Focus.Position
		if cam.rel then
			local pj = (rel - cam.rel).Magnitude
			local pjit = math.abs(pj - (cam.pema or 0))
			cam.pema = (cam.pema or 0) + (pj - (cam.pema or 0)) * 0.15
			if pjit > 0.12 then
				jit = math.max(jit, C.Shake + 0.01)
				mag = math.max(mag, pjit * 4)
			end
		end
		cam.rel = rel
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
	if #e.samples >= 150 then return end
	local ins = e.inst
	local cf = cfOf(ins)
	local s = { t = rd(t - e.born, 3) }
	if cf and Rec.startCF then
		local rc = Rec.startCF:ToObjectSpace(cf)
		s.pos = rc.Position
		-- (3.12: which way it faces too, from where you started - degrees)
		local rx, ry, rz = rc:ToOrientation()
		s.rot = Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
	end
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
	if not last or (s.pos and last.pos and (s.pos - last.pos).Magnitude > 0.05) or (s.rot and last.rot and (s.rot - last.rot).Magnitude > 1) or (s.size and last.size and (s.size - last.size).Magnitude > 0.05) or s.transparency ~= last.transparency
		or (s.scale and last.scale and (s.scale - last.scale).Magnitude > 0.05) or s.decal ~= last.decal then
		e.samples[#e.samples + 1] = s
		e.ev.data.motion = e.samples
	end
end
local function tick()
	local t = now()
	local r = myRoot()
	if Rec.state == "recording" then
		local pg2 = X.ping()
		if pg2 and #Rec.pings < 900 then Rec.pings[#Rec.pings + 1] = pg2 end
		for m, info in pairs(Rec.victims) do
			local h = m.Parent and m:FindFirstChildOfClass("Humanoid")
			if h then info.hp, info.maxhp = rd(h.Health, 2), rd(h.MaxHealth, 2) end
		end
	end
	if C.Others and Rec.state == "recording" and r and not Rec.noVic then
		for _, p in pairs(P:GetPlayers()) do
			local c = p.Character
			if c and c ~= me() then
				local cr = rootOf(c)
				if cr and (cr.Position - r.Position).Magnitude <= C.VRadius then markV(c, "proximity") end
			end
		end
		for m in pairs(dummies) do
			local dr = rootOf(m)
			if dr and (dr.Position - r.Position).Magnitude <= C.VRadius then markV(m, "proximity") end
		end
	end
	if C.Tags then
		for m, info in pairs(tracked) do
			if m.Parent and inScope(m) then
				local cur = {}
				for _, tg in pairs(m:GetTags()) do
					cur[tg] = true
					if not info.tags[tg] then log("STATE", m, "+ tag '" .. tg .. "'", { kind = "tagAdded", tag = tg }) end
				end
				for tg in pairs(info.tags) do
					if not cur[tg] then log("STATE", m, "- tag '" .. tg .. "'", { kind = "tagRemoved", tag = tg }) end
				end
				info.tags = cur
			end
		end
	end
	for tr, a in pairs(live) do
		local tp = gp(tr, "TimePosition") or 0
		if a.tp and tp < a.tp - 0.15 then
			log("ANIM", a.model, "⤺ " .. (a.ev.data.name or "?") .. " time jump " .. fn(a.tp, 2) .. "s → " .. fn(tp, 2) .. "s", { kind = "timejump", id = a.ev.data.id, from = rd(a.tp, 3), to = rd(tp, 3) })
		end
		a.tp = tp
		if math.abs(tr.Speed - a.speed) > 0.01 then
			log("ANIM", a.model, "⏩ " .. (a.ev.data.name or "?") .. " speed " .. fn(a.speed, 2) .. " → " .. fn(tr.Speed, 2), { kind = "speed", id = a.ev.data.id, from = rd(a.speed, 3), to = rd(tr.Speed, 3), at = rd(tp, 3) })
			a.speed = tr.Speed
		end
	end
	for i = #logged, 1, -1 do
		local e = logged[i]
		if not e.inst.Parent or t - e.born > 8 then
			table.remove(logged, i)
		elseif t - e.born > 3 then
			sampleFx(e, t)
		end
	end
	checkPosts()
	if Rec.state == "recording" then
		local el = t - Rec.t0
		local busy = false
		for tr, a in pairs(live) do
			if a.model == me() and not tr.Looped and tr.Priority.Value >= Enum.AnimationPriority.Action.Value then busy = true break end
		end
		local lim = (Rec.adv and Rec.phase == "startup") and math.max(C.IdleStop, 4) or C.IdleStop
		if Rec.focus then
			-- (3.13: a Combat-tab recording stops when you're done: no attack of yours playing, no input, not moving fast)
			local f = Rec.focus
			local last = math.max(X.swingAt or Rec.t0, X.inAt or Rec.t0, X.fastAt or Rec.t0, Rec.t0)
			local wait = (f.kind == "dash" and 1) or (f.kind == "block" and 1.5) or (C.ComboGap + 0.6)
			if el > 20 or (el > 0.5 and not busy and t - last > wait) then stopRec(el > 20 and "max length" or "done") end
		elseif el > C.MaxLen or (el > C.MinLen and not busy and t - Rec.lastAct > lim) then
			stopRec(el > C.MaxLen and "max length" or "idle")
		end
	end
end

-- (3.2) shakes done through your Humanoid's CameraOffset (many games shake the camera that way)
function X.offsetShake(dt)
	local ch = me()
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local o = hum.CameraOffset
	local m = o.Magnitude
	local k = X.osh
	if m > 0.03 then
		if not k then k = { t = now(), peak = 0, quiet = 0 } X.osh = k end
		k.peak = math.max(k.peak, m)
		k.quiet = 0
	elseif k then
		k.quiet = k.quiet + dt
		if k.quiet > 0.1 then
			X.osh = nil
			local dur = now() - k.t - k.quiet
			if dur > 0.02 then
				local ev = log("CAMERA", nil, "shake (CameraOffset) ~" .. fn(dur, 2) .. "s, up to " .. fn(k.peak, 2) .. " studs",
					{ kind = "shake", duration = rd(dur, 3), strength = rd(k.peak, 3), source = "CameraOffset (studs)" })
				if ev then ev.t = k.t end
			end
		end
	end
end

-- (3.1) your root's recent CFrames, so things can be measured from where you were at a given moment
X.rh = {}
function X.rootPush()
	local r = myRoot()
	if not r then return end
	local t = now()
	local h = X.rh
	local cam = workspace.CurrentCamera
	h[#h + 1] = { t, r.CFrame, cam and cam.CFrame }
	if #h > 240 then table.remove(h, 1) end
end
function X.camAt(t)
	local h = X.rh
	for k = #h, 1, -1 do
		if h[k][1] <= t then return h[k][3] end
	end
	return h[1] and h[1][3] or nil
end
function X.rootAt(t)
	local h = X.rh
	for k = #h, 1, -1 do
		if h[k][1] <= t then return h[k][2] end
	end
	return h[1] and h[1][2] or nil
end

-- one point of a path: kept when it's been 0.1s, or the velocity changed, or it left the straight line
function X.keep(l, t, pos, vel)
	local last = l[#l]
	if not last then return true end
	local dt = t - last.t
	if dt >= 0.1 then return true end
	if (pos - last.wp).Magnitude > 30 then return true end
	if (vel - last.vw).Magnitude > 1.5 then return true end
	return ((last.wp + last.vw * dt) - pos).Magnitude > 0.2
end
function X.paths()
	if Rec.state ~= "recording" or not Rec.startCF then return end
	local r = myRoot()
	if not r then return end
	local t = now() - Rec.t0
	local v = r.AssemblyLinearVelocity
	if #Rec.path < 2500 and X.keep(Rec.path, t, r.Position, v) then
		Rec.path[#Rec.path + 1] = { t = rd(t, 3), pos = Rec.startCF:ToObjectSpace(r.CFrame).Position, vel = ldir(v), speed = rd(v.Magnitude, 2), wp = r.Position, vw = v, cf = r.CFrame }
	end
	Rec.peak = math.max(Rec.peak or 0, v.Magnitude)
	for m, info in pairs(Rec.victims) do
		local vr = m.Parent and rootOf(m)
		-- (another character with the same name closer to you is the one on screen: follow that one)
		for c in pairs(tracked) do
			if c ~= m and c.Name == m.Name and c.Parent then
				local cr = rootOf(c)
				if cr and vr and (cr.Position - r.Position).Magnitude + 1 < (vr.Position - r.Position).Magnitude then vr = cr end
			end
		end
		if vr then
			local l = Rec.vpaths[m]
			if not l then l = {} Rec.vpaths[m] = l end
			local vv = vr.AssemblyLinearVelocity
			if #l < 2500 and X.keep(l, t, vr.Position, vv) then
				local rel = r.CFrame:ToObjectSpace(vr.CFrame)
				local lx, ly, lz = rel:ToOrientation()
				local dist = rd((vr.Position - r.Position).Magnitude, 2)
				l[#l + 1] = { t = rd(t, 3), pos = Rec.startCF:ToObjectSpace(vr.CFrame).Position, rel = rel.Position, yaw = rd(math.deg(ly), 1),
					vel = ldir(vv), speed = rd(vv.Magnitude, 2), dist = dist, wp = vr.Position, vw = vv, cf = vr.CFrame }
				info.minDist = math.min(info.minDist or 1e9, dist)
				info.peak = math.max(info.peak or 0, vv.Magnitude)
			end
		end
	end
end

---------------------------------------------------------------------------------------------------
-- (3.6) whole-world logging: where things really are (world CFrames), teleports, maps brought in (Hero's
-- ExtraMapCloneIn city), the template each effect was cloned from, animated effect rigs (wings, hands,
-- buildings), copies of characters (a body left behind), pooled parts (moved out of a part cache instead of
-- being created), Hero's own calls (cutscene cameras with their keyframes, QTEs, map clones, tproot)
X.far = {}            -- effects that were out of range when they appeared: looked at again after a teleport
X.maps = setmetatable({}, { __mode = "k" })
X.copies = setmetatable({}, { __mode = "k" })
X.parked = setmetatable({}, { __mode = "k" })
X.pooled = setmetatable({}, { __mode = "k" })
X.fxRigs = setmetatable({}, { __mode = "k" })
X.recentAssets = {}
X.nParked = 0
X.measureAt = setmetatable({}, { __mode = "k" })
X.rigFx = setmetatable({}, { __mode = "k" })
X.rigDone = setmetatable({}, { __mode = "k" })     -- (3.9: rigs logged as effects - kept, for when they come in range later)
X.mapsLogged = setmetatable({}, { __mode = "k" })

-- a value written out in full (CFrames to the 1/1000th, instances by path) - for Hero's calls
function X.full(v, d)
	d = d or 0
	local t = typeof(v)
	if t == "CFrame" then
		local p, rx, ry, rz = v.Position, v:ToOrientation()
		return string.format("CFrame.new(%s, %s, %s) * CFrame.fromOrientation(%s, %s, %s)", fn(p.X, 3), fn(p.Y, 3), fn(p.Z, 3), fn(rx, 5), fn(ry, 5), fn(rz, 5))
	elseif t == "Vector3" then return string.format("Vector3.new(%s, %s, %s)", fn(v.X, 3), fn(v.Y, 3), fn(v.Z, 3))
	elseif t == "number" then return fn(v, 4)
	elseif t == "string" then return qs(#v > 200 and string.sub(v, 1, 200) or v)
	elseif t == "boolean" or t == "nil" or t == "EnumItem" then return tostring(v)
	elseif t == "Instance" then
		local c = chOf(v)
		local who = c and (isMe(c) and (c == LP.Character and "YOU" or "COPY OF YOU") or c.Name)
		return qs("<" .. v.ClassName .. " " .. (who and (who .. (v ~= c and ("." .. v.Name) or "")) or v:GetFullName()) .. ">")
	elseif t == "table" then
		if d >= 3 then return "{…}" end
		local o, n = {}, 0
		for k, x in pairs(v) do
			n = n + 1
			if n > 30 then o[#o + 1] = "--[[…]]" break end
			o[#o + 1] = (type(k) == "number" and "" or ("[" .. qs(tostring(k)) .. "] = ")) .. X.full(x, d + 1)
		end
		return "{ " .. table.concat(o, ", ") .. " }"
	end
	return qs("<" .. t .. ">")
end

-- where an effect came from: the template in ReplicatedStorage with its name and class whose insides match best
-- (a template folder the game just used counts for a lot - e.g. ScatterNormal's Hand vs ScatterFinisher's Hand)
function X.srcIndex()
	if X.srcIdx or X.srcBuilding then return end
	X.srcBuilding = true
	X.job(function()
		local idx, n = {}, 0
		for _, d in pairs(REP:GetDescendants()) do
			n = n + 1
			if n % 400 == 0 then X.check() end
			if (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Attachment")) and not (LoggedRoot and d:IsDescendantOf(LoggedRoot)) then
				local k = d.Name .. "|" .. d.ClassName
				local l = idx[k]
				if not l then l = {} idx[k] = l end
				if #l < 60 then l[#l + 1] = d end
			end
		end
		X.srcIdx = idx
		X.srcBuilding = nil
	end)
end
function X.kids(i)
	local s = {}
	for _, c in pairs(i:GetChildren()) do
		local k = c.Name .. "|" .. c.ClassName
		s[k] = (s[k] or 0) + 1
	end
	return s
end
function X.noteAssets(f)
	if typeof(f) ~= "Instance" then return end
	table.insert(X.recentAssets, 1, { f, now() })
	while #X.recentAssets > 12 do table.remove(X.recentAssets) end
end
function X.srcOf(i, d)
	local idx = X.srcIdx
	if not idx then return end
	local l = idx[i.Name .. "|" .. i.ClassName]
	if not l or #l == 0 then return end
	local mine2 = X.kids(i)
	local mesh = d.hostMeshId and aid(d.hostMeshId)
	local scored = {}
	for _, c in pairs(l) do
		if c.Parent then
			local theirs, inter, uni = X.kids(c), 0, 0
			for k, n in pairs(mine2) do inter = inter + math.min(n, theirs[k] or 0) uni = uni + math.max(n, theirs[k] or 0) end
			for k, n in pairs(theirs) do if not mine2[k] then uni = uni + n end end
			local s = uni > 0 and inter / uni or 1
			if mesh and c:IsA("MeshPart") and aid(c.MeshId) == mesh then s = s + 0.5 end
			if d.size and c:IsA("BasePart") and (c.Size - d.size).Magnitude < 0.01 then s = s + 0.25 end
			for k, ra in pairs(X.recentAssets) do
				if now() - ra[2] < 4 and ra[1].Parent and c:IsDescendantOf(ra[1]) then s = s + (k == 1 and 2 or 1) break end
			end
			scored[#scored + 1] = { c, s }
		end
	end
	table.sort(scored, function(a, b) return a[2] > b[2] end)
	if not scored[1] then return end
	d.source = scored[1][1]:GetFullName()
	d.sourceScore = rd(scored[1][2], 2)
	local alt = {}
	for k = 2, math.min(#scored, 4) do
		if scored[1][2] - scored[k][2] < 0.05 then alt[#alt + 1] = scored[k][1]:GetFullName() end
	end
	if #alt > 0 then d.sourceAlt = alt end
end

-- the extra facts about one effect (called from process)
function X.tag36(i, d, own, born)
	if own and own ~= LP.Character and P:GetPlayerFromCharacter(own) == nil then
		local pl = P:FindFirstChild(own.Name)
		if isMe(own) or (pl and pl:IsA("Player")) then
			-- (a copy of a character: a body left behind, an after-image - not the character itself)
			d.copyOf = isMe(own) and "YOU" or own.Name
			if not X.copies[own] then
				X.copies[own] = true
				local pv = sf(function() return own:GetPivot() end)
				local l = pv and l2(pv)
				log("WORLD", nil, "☍ copy of " .. d.copyOf .. " '" .. own:GetFullName() .. "'" .. (l and (" at you " .. dw(l.Position)) or ""),
					{ kind = "copy", of = d.copyOf, path = own:GetFullName(), world = pv, offsetCF = l })
			end
		end
	end
	if X.pooled[i] then d.pooled = true X.pooled[i] = nil end
	local m = X.mapOf(i)
	if m then d.inMap = m.Name end
	if X.srcIdx then pcall(X.srcOf, i, d) else X.srcIndex() end
end

-- animated effect rigs (Hero's wings, Scatter's hand, True Evil's building / furniture): their animations
function X.fxAnim(i, ev, born)
	if X.fxRigs[i] or not (i:IsA("Model") or i:IsA("BasePart")) then return end
	if i:FindFirstChildOfClass("Humanoid") then return end
	local function hookA(an)
		if X.fxRigs[an] then return end
		X.fxRigs[an] = true
		local function one(tr, already)
			local a = tr.Animation
			local id = a and aid(a.AnimationId) or "?"
			local since = already and (tr.TimePosition / math.max(tr.Speed, 1e-3)) or 0
			ev.data.anims = ev.data.anims or {}
			table.insert(ev.data.anims, id)
			local pv = cfOf(i)
			local e2 = log("WORLD", ev.model, "▶ effect '" .. i.Name .. "' animation rbxassetid://" .. id,
				{ kind = "fxanim", effect = i.Name, effectAt = rd(born - (Rec.t0 or 0), 3), id = id, speed = rd(tr.Speed, 3), length = rd(tr.Length, 3), looped = tr.Looped,
					world = pv, offsetCF = pv and l2(pv), source = ev.data.source })
			if e2 and since > 0 then e2.t = e2.t - since end
			tr.Stopped:Once(function() if e2 then e2.data.played = rd(now() - e2.t, 3) end end)
		end
		cn(an.AnimationPlayed:Connect(g(function(tr) one(tr, false) end)))
		for _, tr in pairs(sf(function() return an:GetPlayingAnimationTracks() end) or {}) do pcall(one, tr, true) end
	end
	local found = false
	for _, x in pairs(i:GetDescendants()) do
		if x:IsA("Animator") then hookA(x) found = true end
	end
	X.fxRigs[i] = true
	-- (the Animator / controller is often added a moment later)
	local c
	c = i.DescendantAdded:Connect(g(function(x) if x:IsA("Animator") then hookA(x) end end))
	task.delay(found and 0.5 or 3, function() if c then c:Disconnect() end end)
end

-- maps: a model the game brings in (Hero's city: Workspace.ExtraMapCloneIn, filled from
-- ReplicatedStorage.Effects.Parts.ExtraMapCloneInSlow) - logged once, its plain parts not logged as effects
function X.mapOf(i)
	local n = i
	while n and n ~= workspace and n ~= game do
		if X.maps[n] then return n end
		n = n.Parent
	end
end
function X.addMap(m, why, src)
	if not m:IsDescendantOf(workspace) then return end
	X.maps[m] = true
	-- (3.9: once per recording - the same map can be used again in the next one)
	if X.mapsLogged[m] == Rec.count then return end
	X.mapsLogged[m] = Rec.count
	local pv = sf(function() return m:GetPivot() end)
	local ev = log("WORLD", nil, "▦ map '" .. m:GetFullName() .. "' (" .. why .. ")", { kind = "map", name = m.Name, path = m:GetFullName(), world = pv, why = why, source = src })
	if not ev then return end
	-- (how big it ends up: Hero fills it a few parts per frame)
	task.delay(5, function()
		if not m.Parent then return end
		local n, mn, mx = 0, nil, nil
		for _, x in pairs(m:GetDescendants()) do
			if x:IsA("BasePart") then
				n = n + 1
				local p = x.Position
				mn = mn and Vector3.new(math.min(mn.X, p.X), math.min(mn.Y, p.Y), math.min(mn.Z, p.Z)) or p
				mx = mx and Vector3.new(math.max(mx.X, p.X), math.max(mx.Y, p.Y), math.max(mx.Z, p.Z)) or p
			end
		end
		ev.data.parts, ev.data.min, ev.data.max = n, mn, mx
		ev.data.world = sf(function() return m:GetPivot() end) or ev.data.world
	end)
end
function X.mapPlain(i)
	if not X.mapOf(i) then return false end
	if i:IsA("Model") and (i:FindFirstChildWhichIsA("AnimationController", true) or i:FindFirstChildWhichIsA("Humanoid", true)) then return false end
	for _, x in pairs(i:GetDescendants()) do
		if VIS[x.ClassName] then return false end
	end
	return true
end
function X.onTop(c)
	if Rec.state == "idle" or not (c:IsA("Model") or c:IsA("Folder")) or c:FindFirstChildOfClass("Humanoid") then return end
	task.delay(0.6, function()
		if not c.Parent or X.maps[c] then return end
		local n = 0
		for _, x in pairs(c:GetDescendants()) do if x:IsA("BasePart") then n = n + 1 end end
		if n >= 40 then X.addMap(c, n .. " parts appeared at once") end
	end)
end

-- effects out of range when they appeared (you were teleported a moment later) - looked at again after a teleport
function X.farAdd(i, born)
	if #X.far < 300 then X.far[#X.far + 1] = { i, born } end
	-- (3.8: it may only be out of range until it's moved into place (welded on, positioned a frame later -
	-- Hero's setuppart, pools): looked at again a moment later)
	if X.lateTry[i] then return end
	X.lateTry[i] = true
	for _, dt in { 0.03, 0.1, 0.25, 0.5 } do
		task.delay(dt, function()
			if Rec.state ~= "recording" or FXSET[i] or not i.Parent then return end
			local p = posOf(i)
			if p and inR(p) then pcall(X.lateFx, i, born) end
		end)
	end
end
X.lateTry = setmetatable({}, { __mode = "k" })
function X.lateFx(i, born)
	if FXSET[i] or pend[i] then return end
	pend[i] = born
	X.measureAt[i] = now()
	if not pFlush then pFlush = true task.defer(g(flush)) end
end
function X.tele()
	local r = myRoot()
	if not r then X.lastRoot = nil return end
	local cf, t = r.CFrame, now()
	local last = X.lastRoot
	X.lastRoot = { cf, t }
	if Rec.state ~= "recording" or not last then return end
	local jump = (cf.Position - last[1].Position).Magnitude
	if jump > 60 and t - last[2] < 0.25 then
		log("WORLD", me(), "⇥ teleport " .. fn(jump, 0) .. " studs", { kind = "teleport", from = last[1], to = cf, distance = rd(jump, 2) })
		-- (what appeared just before, out of range of where you were: probably where you were going)
		local again = X.far
		X.far = {}
		for _, f in pairs(again) do
			if f[1].Parent and t - f[2] < 1.5 and not FXSET[f[1]] then
				pend[f[1]] = f[2]
				X.measureAt[f[1]] = t
			end
		end
		if next(pend) and not pFlush then pFlush = true task.defer(g(flush)) end
	end
	-- (old ones go)
	if #X.far > 0 and t - X.far[1][2] > 2 then
		local keep = {}
		for _, f in pairs(X.far) do if t - f[2] <= 2 then keep[#keep + 1] = f end end
		X.far = keep
	end
end

-- pooled parts: parked far away (Hero's PartCache keeps them at 1e9) and moved in when used - logged when they
-- come out of the pool, as a new effect
function X.isParked(p) return p.Magnitude > 1e5 end
function X.park(i)
	if X.parked[i] or X.nParked > 5000 then return end
	X.parked[i] = true
	X.nParked = X.nParked + 1
	local far = true
	cn(i:GetPropertyChangedSignal("CFrame"):Connect(function()
		if Rec.state == "idle" then far = X.isParked(i.Position) return end
		local f2 = X.isParked(i.Position)
		if far and not f2 and inR(i.Position) then
			X.pooled[i] = true
			FXSET[i] = nil
			pend[i] = now()
			if not pFlush then pFlush = true task.defer(g(flush)) end
		end
		far = f2
	end))
end
function X.scanParked()
	if X.parkScanned then return end
	X.parkScanned = true
	X.job(function()
		local n = 0
		for _, d in pairs(workspace:GetDescendants()) do
			n = n + 1
			if n % 500 == 0 then X.check() end
			if d:IsA("BasePart") and X.isParked(d.Position) then X.park(d) end
		end
	end)
end

-- Hero's own calls (Remotes.RemoteEvent tables with a TBL, and "tproot"): written out in full; a cutscene
-- camera's keyframes are read from ReplicatedStorage.CustomCameraFolders, so it can be played back exactly
function X.camKeys(path)
	local f = REP:FindFirstChild("CustomCameraFolders")
	f = f and f:FindFirstChild(tostring(path))
	if not f then return nil end
	local o = {}
	for _, k in pairs(f:GetChildren()) do
		local v = k:FindFirstChild("Values")
		v = v and v:FindFirstChild("0")
		local n = tonumber(k.Name)
		if n and v and typeof(v.Value) == "CFrame" then o[#o + 1] = { n, v.Value } end
	end
	table.sort(o, function(a, b) return a[1] < b[1] end)
	return o
end
function X.heroCall(l, n, re)
	if Rec.state == "idle" then return end
	for k = 1, n do
		local v = l[k]
		local tbl = type(v) == "table" and v.TBL
		if type(v) == "string" and k == 1 and v == "tproot" then tbl = "tproot" end
		if type(tbl) == "string" then
			local args = type(v) == "table" and v or { table.unpack(l, 1, n) }
			local d = { kind = "herocall", tbl = tbl, remote = sp(re, 3), full = X.full(args) }
			if tbl == "ExtraMapCloneInSlow" and typeof(args.map) == "Instance" then
				X.addMap(args.map, "Hero ExtraMapCloneInSlow", "ReplicatedStorage.Effects.Parts." .. tostring(args.mapname or "ExtraMapCloneInSlow"))
			elseif tbl == "QTEEvent" or tbl == "RuptureQTE" then
				d.qte = { lastsFor = args.lastsfor or args.Duration or 5 }
			elseif tbl == "tproot" then
				d.tp = l[2]
			elseif type(args.Path) == "string" and (args.StartAt or args.Target) then
				-- (a cutscene camera: camera = (StartAt or Target.CFrame) * (CamOffset or CFrame.new(0, -3, 0)) * keyframe [* C1], FPS frames a second)
				local keys = X.camKeys(args.Path)
				d.cam = { path = args.Path, startAt = typeof(args.StartAt) == "CFrame" and args.StartAt or nil,
					target = typeof(args.Target) == "Instance" and args.Target:GetFullName() or nil,
					targetCF = typeof(args.Target) == "Instance" and args.Target:IsA("BasePart") and args.Target.CFrame or nil,
					camOffset = typeof(args.CamOffset) == "CFrame" and args.CamOffset or nil, c1 = typeof(args.C1) == "CFrame" and args.C1 or nil,
					fps = args.FPS or 60, pause = args.PauseDur, keys = keys }
			end
			local parts = REP:FindFirstChild("Effects")
			parts = parts and parts:FindFirstChild("Parts")
			local af = parts and parts:FindFirstChild(tbl)
			if af then X.noteAssets(af) d.assets = af:GetFullName() end
			log("WORLD", nil, "◈ Hero " .. tbl .. " " .. string.sub(d.full, 1, 200), d)
		end
	end
end

-- (3.6) the extra fields on an Effects line
function X.effExtra(d)
	local o = {}
	if d.world then o[#o + 1] = "World = " .. X.full(d.world) end
	if d.source then o[#o + 1] = "Source = " .. qs(d.source) .. ", SourceMatch = " .. fn(d.sourceScore or 0, 2) end
	if d.sourceAlt then
		local x = {}
		for _, s2 in pairs(d.sourceAlt) do x[#x + 1] = qs(s2) end
		o[#o + 1] = "SourceAlso = { " .. table.concat(x, ", ") .. " }"
	end
	if d.copyOf then o[#o + 1] = "CopyOf = " .. qs(d.copyOf) end
	if d.pooled then o[#o + 1] = "Pooled = true" end
	if d.inMap then o[#o + 1] = "InMap = " .. qs(d.inMap) end
	if d.anims and #d.anims > 0 then
		local x = {}
		for _, id in pairs(d.anims) do x[#x + 1] = qs("rbxassetid://" .. id) end
		o[#o + 1] = "Animations = { " .. table.concat(x, ", ") .. " }"
	end
	return #o > 0 and (", " .. table.concat(o, ", ")) or ""
end

-- (3.6) the world sections of a move table
function X.worldOut(rec, a, tm)
	local function each(kind, f)
		for _, e in pairs(rec.events) do
			if e.cat == "WORLD" and e.data.kind == kind then
				local ok, line = pcall(f, e, e.data)
				if ok and line then a("\t\t" .. line .. ",") end
			end
		end
	end
	a("\tTeleports = { -- your root jumped (From / To: world CFrames)")
	each("teleport", function(e, d)
		return string.format("{ At = %s, Distance = %s, From = %s, To = %s }", tm(e.rt), fn(d.distance, 2), X.full(d.from), X.full(d.to))
	end)
	a("\t},")
	a("\tMaps = { -- a map the game brought in: World = its pivot then; Min / Max: where its parts ended up (world); Source: what it was filled from")
	each("map", function(e, d)
		return string.format("{ At = %s, Name = %s, Path = %s, Why = %s, World = %s%s%s%s }", tm(e.rt), qs(d.name), qs(d.path), qs(d.why), d.world and X.full(d.world) or "nil",
			d.parts and (", Parts = " .. d.parts) or "", d.min and (", Min = " .. X.full(d.min) .. ", Max = " .. X.full(d.max)) or "", d.source and (", Source = " .. qs(d.source)) or "")
	end)
	a("\t},")
	a("\tEffectAnimations = { -- animations played on effect rigs (wings, hands, buildings): EffectAt = when that effect appeared; World / Offset = where the rig was")
	each("fxanim", function(e, d)
		return string.format("{ At = %s, Effect = %s, EffectAt = %s, Id = \"rbxassetid://%s\", Speed = %s, Length = %s, Looped = %s, Played = %s%s%s%s }", tm(e.rt), qs(d.effect),
			tm(d.effectAt or 0), tostring(d.id), fn(d.speed, 3), fn(d.length, 3), tostring(d.looped), fn(d.played or 0, 3),
			d.offsetCF and (", Offset = " .. X.full(d.offsetCF)) or "", d.world and (", World = " .. X.full(d.world)) or "", d.source and (", Source = " .. qs(d.source)) or "")
	end)
	a("\t},")
	a("\tCharacterCopies = { -- copies of a character (a body left behind, an after-image) - their parts in Effects say CopyOf")
	each("copy", function(e, d)
		return string.format("{ At = %s, Of = %s, Path = %s%s%s }", tm(e.rt), qs(d.of), qs(d.path), d.offsetCF and (", Offset = " .. X.full(d.offsetCF)) or "", d.world and (", World = " .. X.full(d.world)) or "")
	end)
	a("\t},")
	a("\tHeroCalls = { -- Hero's own calls to this screen (Remotes.RemoteEvent {TBL = ...} / \"tproot\"), every value in full")
	each("herocall", function(e, d)
		return string.format("{ At = %s, TBL = %s, Remote = %s%s, Args = %s }", tm(e.rt), qs(d.tbl), qs(d.remote), d.assets and (", Assets = " .. qs(d.assets)) or "", d.full)
	end)
	a("\t},")
	a("\tHeroCutscenes = { -- camera = (StartAt or TargetCFrame) * (CamOffset or CFrame.new(0, -3, 0)) * keyframe:Lerp(next, ...) [* C1]; keyframe numbers are frames at FPS (ReplicatedStorage.CustomCameraFolders[Path])")
	each("herocall", function(e, d)
		local c = d.cam
		if not c then return nil end
		local ks = {}
		for k, x in pairs(c.keys or {}) do
			if k > 3000 then break end
			local p, rx, ry, rz = x[2].Position, x[2]:ToOrientation()
			ks[#ks + 1] = string.format("{ %s, %s, %s, %s, %s, %s, %s }", fn(x[1], 2), fn(p.X, 3), fn(p.Y, 3), fn(p.Z, 3), fn(rx, 5), fn(ry, 5), fn(rz, 5))
		end
		return string.format("{ At = %s, Path = %s, StartAt = %s, Target = %s, TargetCFrame = %s, CamOffset = %s, C1 = %s, FPS = %s, PauseDur = %s, -- Keys: { frame, x, y, z, rx, ry, rz (radians, CFrame.fromOrientation) }\n\t\t\tKeys = { %s } }",
			tm(e.rt), qs(c.path), c.startAt and X.full(c.startAt) or "nil", c.target and qs(c.target) or "nil", c.targetCF and X.full(c.targetCF) or "nil",
			c.camOffset and X.full(c.camOffset) or "nil", c.c1 and X.full(c.c1) or "nil", fn(c.fps, 2), c.pause and fn(c.pause, 3) or "nil", table.concat(ks, ", "))
	end)
	a("\t},")
	a("\tQTE = { -- the QTE prompts (Hero's QTEEvent / RuptureQTE) and how they went (its QTEHit / QTEMiss sounds - not in Sounds)")
	each("herocall", function(e, d)
		if not d.qte then return nil end
		return string.format("{ At = %s, Kind = %s, LastsFor = %s }", tm(e.rt), qs(d.tbl), fn(tonumber(d.qte.lastsFor) or 0, 3))
	end)
	for _, e in pairs(rec.events) do
		if e.cat == "SOUND" and e.data.qte then
			a(string.format("\t\t{ At = %s, Kind = \"Result\", Sound = %s, Id = \"rbxassetid://%s\" },", tm(e.rt), qs(e.data.name), tostring(e.data.id)))
		end
	end
	a("\t},")
end

local function hb(dt)
	X.dt = (X.dt or dt) * 0.9 + dt * 0.1
	X.rootPush()
	pcall(X.tele)
	if Rec.state == "recording" then Rec.frames = (Rec.frames or 0) + 1 end
	if #X.jobs > 0 then pcall(X.pump, 0.003) end
	if Rec.state == "idle" then return end
	if Rec.state == "recording" then
		if dt > 0.05 and #(Rec.hitches or {}) < 60 then
			Rec.hitches = Rec.hitches or {}
			table.insert(Rec.hitches, { rd(now() - Rec.t0 - dt, 3), rd(dt, 3) })
		end
	end
	X.paths()
	if Rec.state == "recording" then
		pcall(X.wpnSample)
		local r0 = myRoot()
		if Rec.focus and r0 and r0.AssemblyLinearVelocity.Magnitude > 20 then X.fastAt = now() end
	end
	-- (young effects every frame: their tweens are usually 0.1-1.5s long)
	local tnow = now()
	for _, e in pairs(logged) do
		if e.inst.Parent and tnow - e.born <= 3 then sampleFx(e, tnow) end
	end
	local m0 = me()
	for m in pairs(tracked) do
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
		g(X.sweepTracks)()
	end
end


-- (3.11) how your character is animated: its Animators (and what's playing on each), its Motor6Ds
function X.animSetup()
	local ok, str = pcall(function()
		local c = me()
		local list = {}
		for _, x in pairs(c and c:GetDescendants() or {}) do
			if x:IsA("Animator") then
				local n = #(sf(function() return x:GetPlayingAnimationTracks() end) or {})
				table.insert(list, x.Parent.ClassName .. " " .. x.Parent.Name .. " (" .. n .. " playing)")
			end
		end
		local motors = 0
		for _, x in pairs(c and c:GetDescendants() or {}) do if x:IsA("Motor6D") then motors += 1 end end
		local seen = 0
		for _ in pairs(X.seenList or {}) do seen += 1 end
		return "Animators: " .. (#list > 0 and table.concat(list, ", ") or "none") .. "; Motor6Ds: " .. motors .. "; tracks seen: " .. seen .. "; Character: " .. (c and c:GetFullName() or "?")
	end)
	return ok and str or ("?" .. tostring(str))
end
---------------------------------------------------------------------------------------------------
-- (3.11) every animation playing on you and anyone in scope, straight from their Animators (any Animator in the
-- character), whatever the rest of the logger made of it - written out as AllTracks
X.seen = {}
function X.sweepTracks()
	if Rec.state ~= "recording" then return end
	local list = { me() }
	for m in pairs(Rec.victims) do table.insert(list, m) end
	for _, m in pairs(list) do
		if m and m.Parent then
			for _, an in pairs(m:GetDescendants()) do
				if an:IsA("Animator") then
					for _, tr in pairs(sf(function() return an:GetPlayingAnimationTracks() end) or {}) do
						local a = tr.Animation
						local id = a and aid(a.AnimationId) or "?"
						local key = tostring(m) .. "|" .. id
						local rec = X.seen[key]
						if not rec or (now() - rec.last) > 0.25 then
							-- (a new play: first time, or after a gap)
							rec = { who = isMe(m) and "YOU" or m.Name, id = id, first = now() - (Rec.t0 or now()), last = now(), prio = tr.Priority.Name,
								len = tr.Length, looped = tr.Looped, speed = tr.Speed, tp = tr.TimePosition, host = an.Parent and an.Parent.ClassName or "?" }
							X.seenList = X.seenList or {}
							table.insert(X.seenList, rec)
							X.seen[key] = rec
						end
						rec.last = now()
						if rec.who == "YOU" and not tr.Looped and tr.Priority.Value >= Enum.AnimationPriority.Action.Value then X.swingAt = now() end
					end
				end
			end
		end
	end
end

local function scanChars()
	for _, p in pairs(P:GetPlayers()) do if p.Character then trackChar(p.Character) end end
	local function scan(c, d)
		for _, k in pairs(c:GetChildren()) do
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
		for _, k in pairs(c:GetChildren()) do
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
				for _, d in pairs(r:GetDescendants()) do if d:IsA("Sound") then hookSnd(d) end end
			end
		end))
	end
	scanChars()
	scanDummies()
	scanHB()
	pcall(X.srcIndex)
	pcall(X.scanParked)
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
	X.seen, X.seenList = {}, {}
	Rec.events, Rec.victims, Rec.path, Rec.vpaths = {}, {}, {}, {}
	Rec.st0, Rec.pings, Rec.lastPath, Rec.treeBudget = X.srv(), {}, nil, { n = 0 }
	Rec.frames, Rec.hitches = 0, {}
	Rec.reason = reason or "manual"
	Rec.focus = X.focus
	X.swingAt, X.fastAt = nil, nil
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
	X.far = {}
	Rec.save = saveFolder("Rec" .. Rec.count)
	cam.fov = workspace.CurrentCamera and workspace.CurrentCamera.FieldOfView or 70
	cam.run, cam.shake, cam.cut = nil, nil, nil
	cam.ctype = workspace.CurrentCamera and workspace.CurrentCamera.CameraType or nil
	snapPosts()
	local cut = Rec.t0 - ((phase == "hit" and reason == "hit") and math.max(C.Preroll, C.HitPreroll or 0) or C.Preroll)
	for _, ev in pairs(Rec.pre) do if ev.t >= cut then Rec.events[#Rec.events + 1] = ev end end
	Rec.pre = {}
	Rec.lastAct = now()
	setState("recording")
	snapAll()
	pcall(X.recStart)
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
	for _, p in pairs(path) do
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
	X.drain()
	local evs = Rec.events
	table.sort(evs, function(a, b) return a.t < b.t end)
	local sd = (Rec.hitAt and Rec.hitAt > Rec.t0) and (Rec.hitAt - Rec.t0) or nil
	for _, ev in pairs(evs) do
		ev.rt = ev.t - Rec.t0
		if sd then ev.phase = ev.rt < sd and "startup" or "hit" end
		if ev.model and Rec.victims[ev.model] then ev.victim = true end
	end
	local dur = 0
	for _, ev in pairs(evs) do dur = math.max(dur, ev.rt) end
	for _, ph in pairs(phases(Rec.path)) do
		local ev = log("VELOCITY", me(), "▶ motion " .. fn(ph.to - ph.from, 2) .. "s, peak " .. fn(ph.peak, 1) .. " studs/s " .. dw(ph.dir),
			{ kind = "velocityPhase", localVelocity = ph.dir, peakSpeed = rd(ph.peak, 2), duration = rd(ph.to - ph.from, 3) })
		if ev then
			ev.rt = ph.from
			if sd then ev.phase = ev.rt < sd and "startup" or "hit" end
			evs[#evs + 1] = ev
		end
	end
	table.sort(evs, function(a, b) return a.rt < b.rt end)
	-- (3.13: attacks of yours seen playing (AllTracks) that weren't caught as they started: filled in)
	if pcall(X.fillAnims, evs) then table.sort(evs, function(a, b) return a.rt < b.rt end) end
	local name = UI.nameBox and UI.nameBox.Text ~= "" and UI.nameBox.Text or nil
	if not name then
		for _, ev in pairs(evs) do
			-- (3.7: not the game's plumbing - sounds, shakes, preloads)
			if ev.cat == "REMOTE" and ev.data.label and (ev.model == me() or ev.model == nil) and not any(ev.data.label, { "sound", "shake", "preload", "prep", "bvpeak", "tween", "emit", "trainer", "cutscene", "tproot" }) then name = ev.data.label break end
		end
	end
	if not name then
		for _, ev in pairs(evs) do
			if ev.cat == "ANIM" and ev.who == "YOU" and ev.data.id and not ev.data.kind then
				name = ev.data.name ~= "Animation" and ev.data.name or ("anim " .. ev.data.id)
				break
			end
		end
	end
	name = name or ("Recording " .. Rec.count)
	local vics, vinfo = {}, {}
	for m, v in pairs(Rec.victims) do
		if not isMe(m) and not vinfo[v.name] then
			vics[#vics + 1] = v.name
			local why = {}
			for k, x in pairs(v) do if type(k) == "string" and x == true then why[#why + 1] = k end end
			vinfo[v.name] = { reasons = why, minDist = v.minDist, peak = v.peak, hp = v.hp, maxhp = v.maxhp, firstAt = rd(v.firstAt - Rec.t0, 3), track = Rec.vpaths[m] }
		end
	end
	local net = nil
	if #Rec.pings > 0 then
		local sum, mn, mx = 0, math.huge, 0
		for _, x in pairs(Rec.pings) do sum = sum + x mn = math.min(mn, x) mx = math.max(mx, x) end
		local avg = sum / #Rec.pings
		local dev = 0
		for _, x in pairs(Rec.pings) do dev = dev + (x - avg) ^ 2 end
		net = { ping = rd(avg * 1000, 1), min = rd(mn * 1000, 1), max = rd(mx * 1000, 1), jitter = rd(math.sqrt(dev / #Rec.pings) * 1000, 1), fps = rd(1 / math.max(1e-3, X.dt or 1 / 60), 0) }
		net.avgFps = rd((Rec.frames or 0) / math.max(0.05, dur or 1), 0)
		net.hitches = Rec.hitches
	end
	local rec = { index = Rec.count, name = name, duration = dur, events = evs, victims = vics, vinfo = vinfo, reason = reason, net = net, allTracks = X.seenList, animSetup = X.animSetup(),
		startReason = Rec.reason, path = Rec.path, startVel = Rec.startVel, startSpd = Rec.startSpd, peak = Rec.peak,
		startup = sd, advanced = Rec.adv and sd ~= nil, save = Rec.save and Rec.save:GetFullName() or nil,
		character = me() and me().Name or "?", placeId = game.PlaceId, when = os.date("%Y-%m-%d %H:%M:%S") }
	pcall(X.recFinish, rec)
	rec.t0 = Rec.t0
	rec.focus = Rec.focus
	if Rec.focus then rec.label = Rec.focus.label end
	Rec.focus = nil
	if Rec.save then Rec.save.Name = "Rec" .. Rec.count .. " " .. string.gsub(name, "[^%w _%-]", "") end
	Hist[#Hist + 1] = rec
	while #Hist > 40 do table.remove(Hist, 1) end
	Sel = #Hist
	Rec.adv, Rec.noVic, Rec.hitAt = false, false, nil
	if Hooks.onFinish then task.spawn(g(Hooks.onFinish), rec) end
end

function stopRec(reason)
	if Rec.state ~= "recording" then setState("idle") return end
	X.cutEnd(workspace.CurrentCamera)
	flush()
	Rec.state = "idle"
	finish(reason or "manual")
	if C.AutoArm and reason ~= "manual" then arm() else setState("idle") end
end

---------------------------------------------------------------------------------------------------
-- (3.12) M1s / combos, your inputs, weapons, and every change made to an effect after it appeared
---------------------------------------------------------------------------------------------------
X.BODY = {}
for _, n in pairs({ "Head", "Torso", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "UpperTorso", "LowerTorso",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
	"RightUpperLeg", "RightLowerLeg", "RightFoot" }) do X.BODY[n] = true end
X.ARMS = { ["Right Arm"] = "Right", ["Left Arm"] = "Left", RightHand = "Right", LeftHand = "Left", RightLowerArm = "Right", LeftLowerArm = "Left",
	RightUpperArm = "Right", LeftUpperArm = "Left" }
X.WPNWORDS = { "sword", "katana", "blade", "axe", "weapon", "handle", "gun", "bat", "staff", "spear", "scythe", "hammer", "knife", "dagger",
	"glove", "gauntlet", "sheath", "saber", "sabre", "club", "mace", "lance", "rapier", "cleaver", "pipe", "crowbar", "shield", "bow", "claw", "hilt", "scabbard" }
X.ACT = { Action = true, Action2 = true, Action3 = true, Action4 = true }
X.chgN = 0

-- the state you were in as an animation of yours started (in the air, holding jump, moving which way, last input)
function X.animState(d)
	local c = me()
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h then return end
	d.air = h.FloorMaterial == Enum.Material.Air
	d.hstate = h:GetState().Name
	d.jump = h.Jump or UIS:IsKeyDown(Enum.KeyCode.Space)
	local r = rootOf(c)
	if r and h.MoveDirection.Magnitude > 0.1 then d.moveDir = r.CFrame:VectorToObjectSpace(h.MoveDirection) end
	if X.lastIn and now() - X.lastIn.t < 0.6 then d.input = { key = X.lastIn.key, ago = rd(now() - X.lastIn.t, 3), button = X.lastIn.button } end
end

---------------------------------------------------------------------------------------------------
-- your inputs: keys, clicks, taps (and which on-screen button a tap was on - mobile M1 / dash buttons)
function X.guiAt(pos)
	local GS = game:GetService("GuiService")
	local inset = sf(function() return GS:GetGuiInset() end) or Vector2.zero
	for _, p in pairs({ Vector2.new(pos.X, pos.Y), Vector2.new(pos.X, pos.Y) + inset }) do
		local list = sf(function() return PG:GetGuiObjectsAtPosition(p.X, p.Y) end)
		if list then
			for _, o in pairs(list) do
				if o.Visible and mine(o) then return nil, true end
			end
			for _, o in pairs(list) do
				if o:IsA("GuiButton") and o.Visible and not mine(o) then return sp(o, 3) end
			end
		end
	end
	return nil
end
function X.onInput(inp, proc, began)
	if Rec.state == "idle" or not C.Inputs then return end
	local ut = inp.UserInputType
	local key
	if ut == Enum.UserInputType.Keyboard then key = inp.KeyCode.Name
	elseif ut == Enum.UserInputType.MouseButton1 then key = "M1"
	elseif ut == Enum.UserInputType.MouseButton2 then key = "M2"
	elseif ut == Enum.UserInputType.Touch then key = "Touch"
	elseif string.find(ut.Name, "Gamepad", 1, true) then key = inp.KeyCode.Name
	end
	if not key or key == "F6" or key == "F7" or key == "F8" or key == "F9" or key == "Unknown" then return end
	local button = nil
	if began and (key == "Touch" or key == "M1") then
		local onMine
		button, onMine = X.guiAt(inp.Position)
		if onMine then return end
	end
	-- (a finger dragging the camera: no button under it - not an input worth logging)
	if key == "Touch" and not button then return end
	if not began and key == "Touch" then return end
	local c = me()
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local d = { kind = began and "down" or "up", key = key, proc = proc, button = button, air = h and h.FloorMaterial == Enum.Material.Air or false }
	if began then
		X.inAt = now()
		-- (3.13: a Combat-tab mode is armed: your first input starts it)
		if Rec.state == "armed" and X.focus then startRec("input " .. key) end
		X.lastIn = { key = key, t = now(), button = button }
		X.downAt = X.downAt or {}
		X.downAt[key] = now()
	elseif X.downAt and X.downAt[key] then
		d.held = rd(now() - X.downAt[key], 3)
	end
	log("INPUT", c, (began and "⌨ " or "⌨ release ") .. key .. (button and (" on '" .. button .. "'") or "") .. (d.held and (" (held " .. fn(d.held, 2) .. "s)") or "") ..
		(d.air and began and " (in the air)" or ""), d)
end
X.btnDone = setmetatable({}, { __mode = "k" })
function X.hookBtn(b)
	if X.btnDone[b] or not b:IsA("GuiButton") or mine(b) then return end
	X.btnDone[b] = true
	cn(b.Activated:Connect(g(function()
		if Rec.state == "idle" or not C.Inputs then return end
		local nm = sp(b, 3)
		X.inAt = now()
		if Rec.state == "armed" and X.focus then startRec("button " .. nm) end
		X.lastIn = { key = "Button", t = now(), button = nm }
		log("INPUT", me(), "⌨ button '" .. nm .. "'", { kind = "button", key = "Button", button = nm })
	end)))
end
function X.wireInputs()
	cn(UIS.InputBegan:Connect(g(function(i, p) X.onInput(i, p, true) end)))
	cn(UIS.InputEnded:Connect(g(function(i, p) X.onInput(i, p, false) end)))
	task.spawn(g(function()
		for _, d in pairs(PG:GetDescendants()) do X.hookBtn(d) end
	end))
	cn(PG.DescendantAdded:Connect(g(function(d) if d:IsA("GuiButton") then X.hookBtn(d) end end)))
end

---------------------------------------------------------------------------------------------------
-- every change made to something after it appeared: each property set on it or anything in it (tweens step by step,
-- emitters switched on / off, sizes, colours, CFrames - from where you started), attributes, things added / removed
X.CHGSKIP = { Parent = true, Name = true, Archivable = true, AssemblyLinearVelocity = true, AssemblyAngularVelocity = true,
	AssemblyCenterOfMass = true, AssemblyMass = true, AssemblyRootPart = true, ReceiveAge = true, ResizeIncrement = true, ResizeableFaces = true,
	Position = true, Orientation = true, Rotation = true, WorldPosition = true, WorldOrientation = true, WorldCFrame = true, WorldAxis = true,
	WorldSecondaryAxis = true, Axis = true, SecondaryAxis = true, ExtentsCFrame = true, ExtentsSize = true, LocalTransparencyModifier = true,
	TimePosition = true, PlaybackLoudness = true, IsPlaying = true, IsLoaded = true, TimeLength = true, CurrentPhysicalProperties = true, Mass = true,
	BrickColor = true, AbsolutePosition = true, AbsoluteSize = true, AbsoluteRotation = true, Transform = true, CurrentAngle = true }
function X.watchChanges(root, d, born, life)
	if not C.Changes or not root or not root.Parent then return end
	if d.changesOn then return end
	d.changesOn = true
	local L = d.changes or {}
	d.changes = L
	local cs, lastT, pend, n = {}, {}, {}, 0
	local stopped = false
	local function rel(i)
		if i == root then return "." end
		if not i:IsDescendantOf(root) then return "<outside> " .. sp(i, 3) end
		local o, x = {}, i
		while x and x ~= root do table.insert(o, 1, x.Name) x = x.Parent end
		return table.concat(o, ".")
	end
	local function val(i, k)
		local v = gp(i, k)
		local t = typeof(v)
		if t == "Instance" then return { ref = rel(v) } end
		if t == "CFrame" and k == "CFrame" and i:IsA("BasePart") and Rec.startCF then return Rec.startCF:ToObjectSpace(v) end
		if t == "function" or t == "table" or t == "thread" or t == "RBXScriptSignal" then return nil end
		return v
	end
	local function put1(i, k, v)
		if stopped or X.chgN >= C.MaxChanges or #L >= 2500 then return end
		X.chgN = X.chgN + 1
		L[#L + 1] = { rd(now() - born, 3), rel(i), k, v }
	end
	local function one(i, k)
		if stopped or X.CHGSKIP[k] then return end
		-- (the camera itself moves every frame - that's in Camera already)
		if i:IsA("Camera") and (k == "CFrame" or k == "Focus" or k == "ViewportSize" or k == "NearPlaneZ") then return end
		local ik = lastT[i]
		if not ik then ik = {} lastT[i] = ik end
		local t = now()
		-- (a tween sets its property every frame: kept 30 times a second, and its last value always)
		if ik[k] and t - ik[k] < 1 / 30 then
			pend[i] = pend[i] or {}
			if not pend[i][k] then
				pend[i][k] = true
				task.delay(1 / 30, g(function()
					if pend[i] then pend[i][k] = nil end
					ik[k] = now()
					local v = val(i, k)
					if v ~= nil then put1(i, k, v) end
				end))
			end
			return
		end
		ik[k] = t
		local v = val(i, k)
		if v ~= nil then put1(i, k, v) end
	end
	local function watch(i)
		if n >= 300 or i:IsA("LuaSourceContainer") then return end
		n = n + 1
		if i:IsA("ValueBase") then
			cs[#cs + 1] = i.Changed:Connect(g(function(v)
				if typeof(v) == "Instance" then v = { ref = rel(v) } end
				put1(i, "Value", v)
			end))
		else
			cs[#cs + 1] = i.Changed:Connect(g(function(k) if type(k) == "string" then one(i, k) end end))
		end
		cs[#cs + 1] = i.AttributeChanged:Connect(g(function(k) put1(i, "@" .. k, i:GetAttribute(k)) end))
	end
	watch(root)
	for _, x in pairs(root:GetDescendants()) do watch(x) end
	cs[#cs + 1] = root.DescendantAdded:Connect(g(function(x)
		if stopped then return end
		local tree = sf(X.snap, x, { n = 1450 })
		put1(x, "+", { added = x.ClassName, tree = tree })
		watch(x)
	end))
	cs[#cs + 1] = root.DescendantRemoving:Connect(g(function(x) put1(x, "-", { removed = x.ClassName }) end))
	local function stop()
		if stopped then return end
		stopped = true
		for _, c in pairs(cs) do c:Disconnect() end
	end
	cs[#cs + 1] = root.AncestryChanged:Connect(g(function(_, p) if p == nil then stop() end end))
	task.delay(life or C.ChangeLife, stop)
	X.chgStops = X.chgStops or {}
	X.chgStops[#X.chgStops + 1] = stop
end
-- one change, as Luau
function X.chgLua(c)
	local v = c[4]
	local vs
	if type(v) == "table" and v.added then
		vs = string.format("%q", v.added) .. (v.tree and (", " .. string.gsub(string.gsub(X.treeLua(v.tree, ""), "\n%s*", " "), "%s+", " ")) or "")
	elseif type(v) == "table" and v.removed then
		vs = string.format("%q", v.removed)
	else
		vs = X.lit(v) or qs(tostring(v))
	end
	return string.format("{ %s, %q, %q, %s }", fn(c[1], 3), c[2], c[3], vs)
end

---------------------------------------------------------------------------------------------------
-- weapons: whatever your character holds or wears that isn't its body - tools, swords / axes / gloves welded or
-- jointed to an arm, a sheath on the back - how it's attached (the joint, C0 / C1), where it sits, what it's made of
-- (a builder), how it moves as you swing (from your root, 30 times a second), and anything switched on in it
function X.jointOf(c, parts)
	local set = {}
	for _, p in pairs(parts) do set[p] = true end
	for _, j in pairs(c:GetDescendants()) do
		if j:IsA("JointInstance") or j:IsA("WeldConstraint") or j:IsA("RigidConstraint") then
			local p0, p1 = gp(j, "Part0"), gp(j, "Part1")
			if j:IsA("RigidConstraint") then
				local a0, a1 = gp(j, "Attachment0"), gp(j, "Attachment1")
				p0, p1 = a0 and a0.Parent, a1 and a1.Parent
			end
			if p0 and p1 then
				if set[p1] and X.BODY[p0.Name] and p0:IsDescendantOf(c) then return j, p0, p1 end
				if set[p0] and X.BODY[p1.Name] and p1:IsDescendantOf(c) then return j, p1, p0 end
			end
		end
	end
	return nil
end
function X.wpnScan(c)
	local out = {}
	if not c then return out end
	local function word(n) return any(n, X.WPNWORDS) end
	for _, ch in pairs(c:GetChildren()) do
		local skip = X.BODY[ch.Name] or ch:IsA("Humanoid") or ch:IsA("LuaSourceContainer") or ch:IsA("ValueBase") or ch:IsA("Clothing")
			or ch:IsA("BodyColors") or ch:IsA("CharacterMesh") or ch:IsA("ShirtGraphic") or mine(ch)
		local parts = {}
		if not skip then
			if ch:IsA("BasePart") then parts[1] = ch end
			for _, x in pairs(ch:GetDescendants()) do if x:IsA("BasePart") then parts[#parts + 1] = x end end
		end
		if #parts > 0 then
			local j, limb, held = X.jointOf(c, parts)
			local named = word(ch.Name)
			if not named then
				for _, x in pairs(ch:GetDescendants()) do if (x:IsA("BasePart") or x:IsA("DataModelMesh")) and word(x.Name) then named = true break end end
			end
			local ext = sf(function() return ch:IsA("BasePart") and ch.Size or (ch:IsA("Model") and ch:GetExtentsSize()) or nil end)
			if not ext and held then ext = held.Size end
			local big = ext and math.max(ext.X, ext.Y, ext.Z) >= 2.5
			local acc = ch:IsA("Accessory") and sf(function() return ch.AccessoryType.Name end) or nil
			local hatlike = acc and any(acc, { "hat", "hair", "face", "neck", "eyebrow", "eyelash" })
			local isW = ch:IsA("Tool") or named or (limb and X.ARMS[limb.Name] ~= nil and not hatlike)
				or (limb and big and not hatlike and not ch:IsA("Accessory")) or (j and j:IsA("Motor6D") and not hatlike)
			if isW then
				local main = (ch:IsA("Tool") and ch:FindFirstChild("Handle")) or held or parts[1]
				local w = { root = ch, name = ch.Name, class = ch.ClassName, path = sp(ch, 3), main = main, mainName = main.Name, joint = j, limb = limb,
					hand = limb and X.ARMS[limb.Name] or nil, size = ext, accType = acc, parts = #parts }
				if limb then w.fromLimb = limb.CFrame:ToObjectSpace(main.CFrame) end
				local r = rootOf(c)
				if r then w.fromRoot = r.CFrame:ToObjectSpace(main.CFrame) end
				if j then
					w.jinfo = { class = j.ClassName, name = j.Name, parent = sp(j.Parent, 2), part0 = gp(j, "Part0") and gp(j, "Part0").Name or "?",
						part1 = gp(j, "Part1") and gp(j, "Part1").Name or "?", c0 = gp(j, "C0"), c1 = gp(j, "C1") }
				end
				w.meshes = {}
				for _, x in pairs(ch:GetDescendants()) do
					if (x:IsA("MeshPart") or x:IsA("SpecialMesh") or x:IsA("SurfaceAppearance") or x:IsA("Decal") or x:IsA("Texture")) and #w.meshes < 12 then
						w.meshes[#w.meshes + 1] = dumpMesh(x)
					end
				end
				if ch:IsA("MeshPart") then table.insert(w.meshes, 1, dumpMesh(ch)) end
				w.fx = {}
				for _, x in pairs(ch:GetDescendants()) do
					if (x:IsA("ParticleEmitter") or x:IsA("Trail") or x:IsA("Beam") or x:IsA("Light")) and #w.fx < 40 then
						w.fx[#w.fx + 1] = x.ClassName .. " '" .. x.Name .. "' " .. (gp(x, "Enabled") and "on" or "off")
					end
				end
				out[#out + 1] = w
			end
		end
	end
	return out
end
function X.wpnText(w)
	return "🗡 " .. w.class .. " '" .. w.name .. "'" .. (w.hand and (" in your " .. string.lower(w.hand) .. " hand") or (w.limb and (" on " .. w.limb.Name) or "")) ..
		(w.jinfo and (" (" .. w.jinfo.class .. " " .. w.jinfo.part0 .. "→" .. w.jinfo.part1 .. ")") or "") .. (w.size and (" size " .. v3s(w.size)) or "")
end
-- at the start of a recording: what you hold, and watch it
function X.wpnStart()
	X.W = { list = {}, motion = {}, lastS = 0 }
	if not C.Weapons then return end
	local c = me()
	if not c then return end
	for _, w in pairs(X.wpnScan(c)) do X.wpnAdd(w, "held") end
	X.W.conns = {}
	local pendScan = false
	local function rescan()
		if pendScan then return end
		pendScan = true
		task.delay(0.1, g(function()
			pendScan = false
			if Rec.state ~= "recording" or not X.W then return end
			local now2 = X.wpnScan(c)
			local seen = {}
			for _, w in pairs(now2) do
				seen[w.root] = true
				local old = nil
				for _, o in pairs(X.W.list) do if o.root == w.root then old = o break end end
				if not old then
					X.wpnAdd(w, "drawn")
				elseif (old.limb ~= w.limb) or (old.jinfo and w.jinfo and (old.jinfo.c0 ~= w.jinfo.c0 or old.jinfo.part0 ~= w.jinfo.part0)) then
					local ev = log("WEAPON", c, "🗡 '" .. w.name .. "' moved: " .. (w.limb and w.limb.Name or "?") .. (w.jinfo and (" C0 " .. cfl(w.jinfo.c0)) or ""),
						{ kind = "moved", name = w.name, limb = w.limb and w.limb.Name, c0 = w.jinfo and w.jinfo.c0, c1 = w.jinfo and w.jinfo.c1, fromLimb = w.fromLimb })
					old.limb, old.jinfo, old.hand, old.main = w.limb, w.jinfo, w.hand, w.main
					if ev then old.moves = old.moves or {} table.insert(old.moves, ev) end
				end
			end
			for _, o in pairs(X.W.list) do
				if not seen[o.root] and not o.gone then
					o.gone = now()
					log("WEAPON", c, "🗡 '" .. o.name .. "' put away / removed", { kind = "removed", name = o.name })
				end
			end
		end))
	end
	table.insert(X.W.conns, c.DescendantAdded:Connect(g(function(x)
		if x:IsA("BasePart") or x:IsA("Tool") or x:IsA("Accessory") or x:IsA("Model") or x:IsA("JointInstance") or x:IsA("WeldConstraint") then rescan() end
	end)))
	table.insert(X.W.conns, c.DescendantRemoving:Connect(g(function(x)
		if x:IsA("BasePart") or x:IsA("Tool") or x:IsA("Accessory") or x:IsA("Model") or x:IsA("JointInstance") or x:IsA("WeldConstraint") then rescan() end
	end)))
end
function X.wpnAdd(w, why)
	w.d = { name = w.name }
	w.since = now()
	w.ev = log("WEAPON", me(), X.wpnText(w) .. (why == "drawn" and "  (drawn)" or ""), { kind = why, name = w.name, class = w.class })
	w.d.tree = sf(X.snap, w.root, { n = 1200 })
	pcall(X.watchChanges, w.root, w.d, Rec.t0 or now(), C.MaxLen + 5)
	if w.joint then
		w.jd = {}
		pcall(X.watchChanges, w.joint, w.jd, Rec.t0 or now(), C.MaxLen + 5)
	end
	w.samples = {}
	X.W.list[#X.W.list + 1] = w
end
-- (every frame while recording: each weapon's main part from your root, 30 times a second)
function X.wpnSample()
	local W = X.W
	if not W or #W.list == 0 then return end
	local t = now()
	if t - W.lastS < 1 / 30 then return end
	W.lastS = t
	local r = myRoot()
	if not r then return end
	for _, w in pairs(W.list) do
		if w.main and w.main.Parent and not w.gone and #w.samples < 1200 then
			local cf = r.CFrame:ToObjectSpace(w.main.CFrame)
			local last = w.samples[#w.samples]
			if not last or (last[2].Position - cf.Position).Magnitude > 0.03 or (t - Rec.t0) - last[1] > 0.5 then
				w.samples[#w.samples + 1] = { t - Rec.t0, cf }
			end
		end
	end
end
function X.recStart()
	X.chgN = 0
	X.chgStops = {}
	pcall(X.wpnStart)
	-- (the screen effects already there: a move often tweens the game's own ColorCorrection / Bloom / Blur)
	if C.Changes and C.Screen then
		X.screenD = {}
		for _, r in pairs({ LIGHT, workspace.CurrentCamera }) do
			if r then
				for _, e in pairs(r:GetChildren()) do
					if e:IsA("PostEffect") or e:IsA("Atmosphere") then
						local d = { name = e.Name, class = e.ClassName }
						X.screenD[#X.screenD + 1] = d
						pcall(X.watchChanges, e, d, Rec.t0, C.MaxLen + 5)
					end
				end
			end
		end
		local ld = { name = "Lighting", class = "Lighting", self = true }
		X.screenD[#X.screenD + 1] = ld
		pcall(X.watchChanges, LIGHT, ld, Rec.t0, C.MaxLen + 5)
		local cam = workspace.CurrentCamera
		if cam then
			local cd = { name = "Camera", class = "Camera", self = true }
			X.screenD[#X.screenD + 1] = cd
			pcall(X.watchChanges, cam, cd, Rec.t0, C.MaxLen + 5)
		end
	end
end
function X.recFinish(rec)
	for _, s in pairs(X.chgStops or {}) do pcall(s) end
	X.chgStops = {}
	if X.W then
		for _, c in pairs(X.W.conns or {}) do pcall(function() c:Disconnect() end) end
		rec.weapons = X.W.list
	end
	rec.screenChanges = X.screenD
	X.W, X.screenD = nil, nil
end

---------------------------------------------------------------------------------------------------
-- output: Combo (each swing: its input, kind, hit / miss, what it did), Dashes, Inputs, Weapons, Changes
function X.fillAnims(evs)
	local t0 = Rec.t0 or 0
	local n = 0
	for _, r in pairs(X.seenList or {}) do
		if r.who == "YOU" and not r.looped and X.ACT[r.prio] then
			local start = r.first - (r.tp or 0) / math.max(r.speed or 1, 0.05)
			local found = false
			for _, e in pairs(evs) do
				if e.cat == "ANIM" and e.who == "YOU" and not e.data.kind and e.data.id == r.id and math.abs((e.rt or 0) - start) < 0.35 then found = true break end
			end
			if not found then
				n = n + 1
				local d = { id = r.id, name = "anim " .. r.id, priority = r.prio, looped = false, speed = rd(r.speed or 1, 3), length = rd(r.len or 0, 3),
					played = rd(math.max(0, (r.last - t0) - start), 3), filled = true }
				evs[#evs + 1] = { t = t0 + start, rt = start, st = 0, cat = "ANIM", who = "YOU", model = me(), text = "▶ (seen playing) rbxassetid://" .. r.id .. " (" .. r.prio .. ")", data = d }
			end
		end
	end
	return n
end
function X.inWin(rec, from, to, pred)
	local o = {}
	for _, e in pairs(rec.events) do
		if e.rt >= from - 0.01 and e.rt < to and pred(e) then o[#o + 1] = e end
	end
	return o
end
function X.pathAt(rec, t)
	local best = nil
	for _, p in pairs(rec.path or {}) do
		if p.t <= t then best = p else break end
	end
	return best or (rec.path and rec.path[1])
end
function X.dirName(v)
	if not v or v.Magnitude < 0.5 then return "none" end
	if math.abs(v.Z) >= math.abs(v.X) then return v.Z < 0 and "front" or "back" end
	return v.X > 0 and "right" or "left"
end
function X.comboOut(rec, a, tm)
	if not C.Combo then return end
	local sw = {}
	for _, e in pairs(rec.events) do
		if e.cat == "ANIM" and e.who == "YOU" and not e.data.kind and not e.data.looped and X.ACT[e.data.priority or ""] then sw[#sw + 1] = e end
	end
	local ins = {}
	for _, e in pairs(rec.events) do if e.cat == "INPUT" and e.data.kind ~= "up" then ins[#ins + 1] = e end end
	a("\tCombo = { -- (3.12) each attack animation of yours is a swing. Kind: m1 / downslam (in the air) / uppercut (jump held) / dash / block / other;")
	a("\t\t-- ChainIndex: which M1 of the chain; Gap: since the swing before; Hit = true if anyone took damage or reacted; T in lists: seconds after the swing started;")
	a("\t\t-- Lunge: how far you moved during it (from where you stood, fwd = -Z)")
	local chain, lastM1, maxChain, chains = 0, nil, 0, {}
	local m1Gaps = {}
	for k, s in ipairs(sw) do
		local d = s.data
		local nx = sw[k + 1]
		local stop = nx and nx.rt or (s.rt + math.max(d.played or d.length or 0.6, 0.4) + 0.4)
		local inp = d.input
		if not inp then
			for _, e in pairs(ins) do
				if e.rt <= s.rt + 0.05 and e.rt >= s.rt - 0.45 then inp = { key = e.data.key, button = e.data.button, ago = rd(s.rt - e.rt, 3), air = e.data.air } end
			end
		end
		if d.air == nil and inp and inp.air ~= nil then d.air = inp.air end
		local nm = string.lower(tostring(d.name)) .. " " .. string.lower(tostring(inp and inp.button or ""))
		local key = inp and inp.key or ""
		local kind
		if any(nm, { "dash", "dodge", "roll", "evade", "sidestep" }) or key == "Q" then kind = "dash"
		elseif any(nm, { "block", "parry", "guard" }) or key == "F" then kind = "block"
		elseif any(nm, { "downslam", "down slam", "slam", "stomp", "ground" }) or d.air then kind = "downslam"
		elseif any(nm, { "uppercut", "upper", "launch" }) or d.jump then kind = "uppercut"
		elseif key == "M1" or key == "Touch" or key == "Button" or key == "ButtonR2" or key == "ButtonX" or key == "" or any(nm, { "m1", "punch", "swing", "combo", "attack", "light", "hit", "slash" }) then kind = "m1"
		else kind = "other" end
		local gap = (k > 1) and (s.rt - sw[k - 1].rt) or nil
		if kind == "m1" or kind == "downslam" or kind == "uppercut" then
			if lastM1 and s.rt - lastM1 <= C.ComboGap then
				chain = chain + 1
				m1Gaps[#m1Gaps + 1] = rd(s.rt - lastM1, 3)
			else
				if chain > 0 then chains[#chains + 1] = chain end
				chain = 1
			end
			lastM1 = s.rt
			maxChain = math.max(maxChain, chain)
		end
		local hits = X.inWin(rec, s.rt, stop, function(e) return e.cat == "HIT" and e.who ~= "YOU" and (e.data.amount or 0) > 0 end)
		local reacts = X.inWin(rec, s.rt, stop, function(e) return e.cat == "ANIM" and e.victim and not e.data.kind end)
		local kb = X.inWin(rec, s.rt, stop, function(e) return e.victim and ((e.cat == "VELOCITY" and e.data.localVelocity) or (e.cat == "MOVE" and e.data.kind ~= "end")) end)
		local snds = X.inWin(rec, s.rt, stop, function(e) return e.cat == "SOUND" and not e.victim end)
		local fxs = X.inWin(rec, s.rt, stop, function(e) return e.cat == "VFX" and (not e.data.kind or e.data.kind == "emit") end)
		local hbs = X.inWin(rec, s.rt, stop, function(e) return e.cat == "HITBOX" end)
		local mks = X.inWin(rec, s.rt, stop, function(e) return e.cat == "MARKER" and e.who == "YOU" end)
		local wps = X.inWin(rec, s.rt, stop, function(e) return e.cat == "WEAPON" end)
		local p0, p1 = X.pathAt(rec, s.rt), X.pathAt(rec, stop)
		local lunge = (p0 and p1 and p0.cf and p1.cf) and p0.cf:ToObjectSpace(p1.cf).Position or Vector3.zero
		local hit = #hits > 0 or #reacts > 0
		a(string.format("\t\t{ N = %d, Kind = %q, ChainIndex = %s, At = %s, Gap = %s, Until = %s, Input = %s, Button = %s, InputBefore = %s, Air = %s, JumpHeld = %s, State = %q, MoveDir = %s,",
			k, kind, (kind == "m1" or kind == "downslam" or kind == "uppercut") and tostring(chain) or "nil", tm(s.rt), gap and fn(gap, 3) or "nil", tm(stop),
			qs(key), qs(inp and inp.button or ""), inp and fn(inp.ago or 0, 3) or "nil", tostring(d.air or false), tostring(d.jump or false), d.hstate or "?",
			d.moveDir and v3l(d.moveDir) or "nil"))
		a(string.format("\t\t\tAnim = \"rbxassetid://%s\", Name = %s, Priority = %q, Length = %s, Speed = %s, Played = %s, Hit = %s, Lunge = %s,",
			tostring(d.id), qs(d.name), d.priority or "?", fn(d.length or 0, 3), fn(d.speed or 1, 3), fn(d.played or 0, 3), tostring(hit), v3l(lunge)))
		local function L2(title, list, f)
			local o = {}
			for _, e in pairs(list) do if #o < 40 then o[#o + 1] = f(e) end end
			a("\t\t\t" .. title .. " = { " .. table.concat(o, ", ") .. " },")
		end
		L2("Hits", hits, function(e) return string.format("{ T = %s, Target = %s, Amount = %s }", fn(e.rt - s.rt, 3), qs(e.data.target or e.who), fn(e.data.amount or 0, 2)) end)
		L2("Reactions", reacts, function(e) return string.format("{ T = %s, Who = %s, Anim = \"rbxassetid://%s\", Name = %s }", fn(e.rt - s.rt, 3), qs(e.who), tostring(e.data.id), qs(e.data.name)) end)
		L2("Knockback", kb, function(e) return string.format("{ T = %s, Who = %s, LocalVelocity = %s }", fn(e.rt - s.rt, 3), qs(e.who), e.data.localVelocity and v3l(e.data.localVelocity) or "nil") end)
		L2("Sounds", snds, function(e) return string.format("{ T = %s, Id = \"rbxassetid://%s\", Name = %s, Volume = %s }", fn(e.rt - s.rt, 3), tostring(e.data.id), qs(e.data.name), fn(e.data.volume or 0, 2)) end)
		L2("Effects", fxs, function(e)
			if e.data.kind == "emit" then return string.format("{ T = %s, Emit = %s, Total = %s }", fn(e.rt - s.rt, 3), qs(e.data.root), fn(e.data.total or 0)) end
			return string.format("{ T = %s, Name = %s, Folder = %s, Offset = %s }", fn(e.rt - s.rt, 3), qs(e.data.name), qs(e.data.folder or "?"), e.data.offsetCF and cfl(e.data.offsetCF) or "nil")
		end)
		L2("Hitboxes", hbs, function(e) return string.format("{ T = %s, Name = %s, Size = %s, Offset = %s }", fn(e.rt - s.rt, 3), qs(e.data.name), e.data.size and v3l(e.data.size) or "nil", e.data.offsetCF and cfl(e.data.offsetCF) or "nil") end)
		L2("Markers", mks, function(e) return string.format("{ T = %s, Name = %s }", fn(e.rt - s.rt, 3), qs(e.data.name or "?")) end)
		L2("Weapon", wps, function(e) return string.format("{ T = %s, Text = %s }", fn(e.rt - s.rt, 3), qs(e.text)) end)
		a("\t\t},")
	end
	if chain > 0 then chains[#chains + 1] = chain end
	local cl = {}
	for _, x in pairs(chains) do cl[#cl + 1] = tostring(x) end
	local gl = {}
	for _, x in pairs(m1Gaps) do gl[#gl + 1] = fn(x, 3) end
	local lastEnd = 0
	if #sw > 0 then local s = sw[#sw] lastEnd = s.rt + (s.data.played or s.data.length or 0) end
	a(string.format("\t\tChainLength = %d, Chains = { %s }, M1Gaps = { %s }, AfterLast = %s, -- (Chains: swings per chain - its M1s and the downslam / uppercut ending it; AfterLast: from the last swing's end to the end of the recording - the reset / endlag)",
		maxChain, table.concat(cl, ", "), table.concat(gl, ", "), fn(math.max(0, rec.duration - lastEnd), 3)))
	a("\t},")
	-- dashes: a dash input, or a dash animation, and the burst of speed that came with it
	a("\tDashes = { -- (3.12) Direction: front / back / left / right of where you faced; Distance: studs covered; from the speed burst after the input")
	local ph = phases(rec.path or {})
	local used = {}
	local function dash1(at, why, anim)
		for _, p in pairs(ph) do
			if not used[p] and p.from >= at - 0.15 and p.from <= at + 0.4 then
				used[p] = true
				local p0, p1 = X.pathAt(rec, p.from), X.pathAt(rec, p.to)
				local disp = (p0 and p1 and p0.cf and p1.cf) and p0.cf:ToObjectSpace(p1.cf).Position or Vector3.zero
				local snds = X.inWin(rec, at - 0.05, p.to + 0.2, function(e) return e.cat == "SOUND" and not e.victim end)
				local fxs = X.inWin(rec, at - 0.05, p.to + 0.2, function(e) return e.cat == "VFX" and not e.data.kind end)
				local so, fo = {}, {}
				for _, e in pairs(snds) do so[#so + 1] = string.format("{ T = %s, Id = \"rbxassetid://%s\" }", fn(e.rt - at, 3), tostring(e.data.id)) end
				for _, e in pairs(fxs) do fo[#fo + 1] = string.format("{ T = %s, Name = %s }", fn(e.rt - at, 3), qs(e.data.name)) end
				a(string.format("\t\t{ At = %s, Trigger = %s, Direction = %q, LocalVelocity = %s, PeakSpeed = %s, Starts = %s, Duration = %s, Distance = %s, Displacement = %s, Anim = %s, Sounds = { %s }, Effects = { %s } },",
					tm(at), qs(why), X.dirName(p.dir), v3l(p.dir or Vector3.zero), fn(p.peak, 2), fn(p.from - at, 3), fn(p.to - p.from, 3), fn(Vector3.new(disp.X, 0, disp.Z).Magnitude, 2),
					v3l(disp), anim and ("\"rbxassetid://" .. tostring(anim.data.id) .. "\"") or "nil", table.concat(so, ", "), table.concat(fo, ", ")))
				return true
			end
		end
	end
	for _, e in pairs(rec.events) do
		if e.cat == "INPUT" and e.data.kind ~= "up" and (e.data.key == "Q" or e.data.key == "ButtonB" or any(e.data.button or "", { "dash", "dodge", "roll" })) then
			local an = nil
			for _, s in pairs(sw) do if s.rt >= e.rt - 0.05 and s.rt <= e.rt + 0.4 then an = s break end end
			dash1(e.rt, "input " .. tostring(e.data.button or e.data.key), an)
		end
	end
	for _, s in pairs(sw) do
		if any(s.data.name or "", { "dash", "dodge", "roll", "evade" }) then dash1(s.rt, "animation " .. tostring(s.data.name), s) end
	end
	a("\t},")
	a("\tInputs = { -- (3.12) your keys / clicks / taps (Button: the on-screen button it was on), Held: how long it was held")
	for _, e in pairs(rec.events) do
		if e.cat == "INPUT" then
			a(string.format("\t\t{ At = %s, Kind = %q, Key = %s, Button = %s, Air = %s%s%s },", tm(e.rt), e.data.kind or "?", qs(e.data.key or ""), qs(e.data.button or ""),
				tostring(e.data.air or false), e.data.held and (", Held = " .. fn(e.data.held, 3)) or "", e.data.proc and ", GameProcessed = true" or ""))
		end
	end
	a("\t},")
end
function X.chgList(a, ind, L, t0)
	a(ind .. "Changes = { -- { T (s after it appeared), Path in it, Property, Value } - CFrames of parts: from where you started; \"+\" / \"-\": added / removed")
	for _, c in pairs(L or {}) do a(ind .. "\t" .. X.chgLua(c) .. ",") end
	a(ind .. "},")
end
function X.wpnOut(rec, a, tm)
	a("\tWeapons = { -- (3.12) what you held. Joint: how it's attached (C0 / C1); FromLimb / FromRoot: where its main part sits; Swing: its main part from your root over time { T, CFrame }")
	for _, w in pairs(rec.weapons or {}) do
		a(string.format("\t\t{ Name = %s, Class = %q, Path = %s, Main = %s, Limb = %s, Hand = %s, Size = %s, Parts = %d, AccessoryType = %s, Since = %s%s,",
			qs(w.name), w.class, qs(w.path), qs(w.mainName or "?"), qs(w.limb and w.limb.Name or ""), qs(w.hand or ""), w.size and v3l(w.size) or "nil", w.parts or 0,
			qs(w.accType or ""), fn(math.max(0, (w.since or Rec.t0) - (Rec.t0 or 0)), 3), w.gone and (", Removed = " .. fn(w.gone - (Rec.t0 or 0), 3)) or ""))
		if w.jinfo then
			a(string.format("\t\t\tJoint = { Class = %q, Name = %s, Parent = %s, Part0 = %s, Part1 = %s, C0 = %s, C1 = %s },", w.jinfo.class, qs(w.jinfo.name), qs(w.jinfo.parent),
				qs(w.jinfo.part0), qs(w.jinfo.part1), w.jinfo.c0 and X.lit(w.jinfo.c0) or "nil", w.jinfo.c1 and X.lit(w.jinfo.c1) or "nil"))
		end
		a(string.format("\t\t\tFromLimb = %s, FromRoot = %s,", w.fromLimb and X.lit(w.fromLimb) or "nil", w.fromRoot and X.lit(w.fromRoot) or "nil"))
		local ms = {}
		for _, x in pairs(w.meshes or {}) do ms[#ms + 1] = mLua(x) end
		a("\t\t\tMeshes = { " .. table.concat(ms, ", ") .. " },")
		local fx = {}
		for _, x in pairs(w.fx or {}) do fx[#fx + 1] = qs(x) end
		a("\t\t\tEffectsInIt = { " .. table.concat(fx, ", ") .. " },")
		local sl = {}
		for _, s in pairs(w.samples or {}) do sl[#sl + 1] = "{ " .. fn(s[1], 3) .. ", " .. X.lit(s[2]) .. " }" end
		a("\t\t\tSwing = { " .. table.concat(sl, ", ") .. " },")
		if w.d then X.chgList(a, "\t\t\t", w.d.changes, 0) end
		if w.jd and w.jd.changes and #w.jd.changes > 0 then
			a("\t\t\tJointChanges = {")
			for _, c in pairs(w.jd.changes) do a("\t\t\t\t" .. X.chgLua(c) .. ",") end
			a("\t\t\t},")
		end
		if w.d and w.d.tree then
			a("\t\t\tBuilder = function() -- (needs the N / NS / CS / REF helpers from Builders)")
			a("\t\t\t\treturn " .. string.gsub(X.treeLua(w.d.tree, "\t\t\t\t"), "^%s+", ""))
			a("\t\t\tend,")
		end
		a("\t\t},")
	end
	a("\t},")
	a("\tWeaponEvents = {")
	for _, e in pairs(rec.events) do
		if e.cat == "WEAPON" then a(string.format("\t\t{ At = %s, Kind = %q, Text = %s },", tm(e.rt), e.data.kind or "?", qs(e.text))) end
	end
	a("\t},")
end
function X.changesOut(rec, a, tm)
	a("\tEffectChanges = { -- (3.12) everything done to each effect after it appeared, frame by frame (30/s at most per property): tweens, emitters on / off, colours, sizes, moves")
	for _, e in pairs(rec.events) do
		if e.cat == "VFX" and not e.data.kind and e.data.changes and #e.data.changes > 0 then
			a(string.format("\t\t{ At = %s, Effect = %s, Folder = %s,", tm(e.rt), qs(e.data.name), qs(e.data.folder or "?")))
			X.chgList(a, "\t\t\t", e.data.changes)
			a("\t\t},")
		end
	end
	a("\t},")
	a("\tScreenChanges = { -- (3.12) the screen effects (ColorCorrection, Bloom, Blur ...), Lighting and the camera, changed during the move")
	for _, e in pairs(rec.events) do
		if e.cat == "SCREEN" and e.data.kind == "added" and e.data.changes and #e.data.changes > 0 then
			a(string.format("\t\t{ At = %s, Added = %s, Class = %q,", tm(e.rt), qs(e.data.name), e.data.class or "?"))
			X.chgList(a, "\t\t\t", e.data.changes)
			a("\t\t},")
		end
	end
	for _, d in pairs(rec.screenChanges or {}) do
		if d.changes and #d.changes > 0 then
			a(string.format("\t\t{ Existing = %s, Class = %q, -- (T: from the start of the recording)", qs(d.name), d.class))
			X.chgList(a, "\t\t\t", d.changes)
			a("\t\t},")
		end
	end
	a("\t},")
end

---------------------------------------------------------------------------------------------------
local Out = {}
-- consecutive copies of one remote (same remote + label) within 0.75s of each other -> one line with a count
function Out.remotes(rec)
	local o, last = {}, nil
	for _, e in pairs(rec.events) do
		if e.cat == "REMOTE" or e.cat == "REPLICATION" then
			local key = tostring(e.data.remote) .. "|" .. tostring(e.data.label)
			if last and last.key == key and e.rt - last.lastT <= 0.75 then
				last.n = last.n + 1
				last.lastT = e.rt
			else
				last = { ev = e, key = key, n = 1, lastT = e.rt }
				o[#o + 1] = last
			end
		end
	end
	return o
end
-- the same damage to the same target within 0.03s is one hit seen twice (a copy of their character)
function Out.hits(rec, pred)
	local o, last = {}, {}
	for _, e in pairs(rec.events) do
		if e.cat == "HIT" and (not pred or pred(e)) then
			local k = tostring(e.data.target) .. "|" .. tostring(e.data.amount)
			if not (last[k] and e.rt - last[k] <= 0.03) then o[#o + 1] = e end
			last[k] = e.rt
		end
	end
	return o
end
-- everything that happens while each of your animations plays, timed from that animation's start
-- (lag moves an animation and the effects the server sent with it together - these gaps are what to copy)
local RELCATS = { SOUND = true, VFX = true, EFFECT = true, HIT = true, MOVE = true, CAMERA = true, MARKER = true, HITBOX = true, TWEEN = true }
function Out.relative(rec)
	local o = {}
	for _, a in pairs(rec.events) do
		if a.cat == "ANIM" and a.who == "YOU" and not a.data.kind and (a.data.played or 0) >= 0.3 then
			local lst = {}
			local stop = a.rt + (a.data.played or 0) + 0.05
			for _, e in pairs(rec.events) do
				if e ~= a and e.rt >= a.rt - 0.01 and e.rt <= stop and #lst < 160 then
					local ok = RELCATS[e.cat] and (e.cat ~= "MARKER" or e.who == "YOU")
					if e.cat == "ANIM" and e.who ~= "YOU" and not e.data.kind then ok = true end
					if e.cat == "VFX" and e.data.kind and e.data.kind ~= "emit" then ok = false end
					if ok then lst[#lst + 1] = e end
				end
			end
			o[#o + 1] = { anim = a, events = lst }
		end
	end
	return o
end
local function evFilter(rec, o)
	local l = {}
	for _, ev in pairs(rec.events) do
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
	for _, ev in pairs(rec.events) do
		if (ev.cat == "HIT" and ev.data.offset and (ev.data.amount or 0) > 0) or (ev.cat == "HITBOX" and ev.data.kind == "touch" and ev.data.victim and ev.data.offset) then
			hits[#hits + 1] = ev
		end
	end
	local cl = {}
	for _, h in pairs(hits) do
		local c = cl[#cl]
		if c and h.rt - c.last <= 0.08 then
			c.hits[#c.hits + 1] = h
			c.last = h.rt
		else
			cl[#cl + 1] = { first = h.rt, last = h.rt, hits = { h } }
		end
	end
	local o = {}
	for _, c in pairs(cl) do
		local sum = Vector3.new()
		for _, h in pairs(c.hits) do sum = sum + h.data.offset end
		local cen = sum / #c.hits
		local ext = Vector3.new()
		for _, h in pairs(c.hits) do
			local d = h.data.offset - cen
			local half = (h.data.size or h.data.victimExtents or Vector3.new(4, 5, 2)) / 2
			ext = Vector3.new(math.max(ext.X, math.abs(d.X) + half.X), math.max(ext.Y, math.abs(d.Y) + half.Y), math.max(ext.Z, math.abs(d.Z) + half.Z))
		end
		local size = Vector3.new(math.max(ext.X * 2, 4), math.max(ext.Y * 2, 5), math.max(ext.Z * 2, 4))
		local dmg, names, srcs = 0, {}, {}
		for _, h in pairs(c.hits) do
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
		for _, k in pairs(s.keypoints) do o[#o + 1] = string.format("NumberSequenceKeypoint.new(%s, %s, %s)", fn(k.time, 4), fn(k.value, 4), fn(k.envelope, 4)) end
		return "NumberSequence.new({ " .. table.concat(o, ", ") .. " })"
	end
	if s.kind == "color" then
		local o = {}
		for _, k in pairs(s.keypoints) do
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
	for k, x in pairs(e) do
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
	for k, x in pairs(e.attributes or {}) do
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
	if rec.net then
		a(string.format("net: ping %sms (%s-%s, jitter %s) · %s fps · things the server sent reach you ~%sms late: the times are as your screen saw them; the \"timed against your animations\" section cancels that lag out",
			fn(rec.net.ping, 0), fn(rec.net.min, 0), fn(rec.net.max, 0), fn(rec.net.jitter, 0), fn(rec.net.fps, 0), fn(rec.net.ping / 2, 0)))
		if rec.net.hitches and #rec.net.hitches > 0 then
			local hs = {}
			for _, h in pairs(rec.net.hitches) do hs[#hs + 1] = fn(h[1], 2) .. "s(" .. math.floor(h[2] * 1000) .. "ms)" end
			a("  ⚠ frame hitches while recording (" .. fn(rec.net.avgFps or 0, 0) .. " fps avg) - times near these are less exact: " .. table.concat(hs, " "))
		end
		a(string.format("  other characters' MOVEMENT (knockback, pulls) shows ~%sms later still (Roblox smooths their physics): subtract that from victim velocity / track times",
			fn(rec.net.ping / 2 + 100, 0)))
	end
	local function sect(title, pred, f)
		local it = {}
		for _, ev in pairs(rec.events) do if pred(ev) then it[#it + 1] = f(ev) end end
		if #it > 0 then
			a("")
			a("■ " .. title .. " (" .. #it .. ")")
			for _, s in pairs(it) do a("  " .. s) end
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
		for _, m in pairs(e.data.markers or {}) do mk[#mk + 1] = m.name .. "@" .. fn(m.time, 3) end
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
		for _, x in pairs(d.emitters or {}) do em[#em + 1] = x.name .. "{" .. eText(x) .. "}" end
		local ms, as, co = {}, {}, {}
		for _, x in pairs(d.meshes or {}) do ms[#ms + 1] = mText(x) end
		for _, x in pairs(d.assets or {}) do as[#as + 1] = x.property .. "=" .. tostring(x.id or x.raw) end
		for _, x in pairs(d.colors or {}) do co[#co + 1] = tostring(x.hex) end
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
		for _, ev in pairs(rec.events) do
			if ev.cat == "EFFECT" and ev.data.templates and not seen[ev.data.assets] then
				seen[ev.data.assets] = true
				if not any2 then a("") a("■ Effect templates (asset folders the server handed the effect module)") any2 = true end
				a("  " .. ev.data.module .. "." .. ev.data.func .. " ← " .. tostring(ev.data.assets) .. (ev.data.saved and ("  [cloned: " .. ev.data.saved .. "]") or ""))
				for _, t in pairs(ev.data.templates) do
					local d = t.d
					if t.sound then
						a(string.format("    %s  Sound rbxassetid://%s vol %s pitch %s", t.path, tostring(t.sound.id), fn(t.sound.volume), fn(t.sound.speed)))
					elseif t.anim then
						a(string.format("    %s  Animation rbxassetid://%s", t.path, tostring(t.anim)))
					elseif d then
						local em = {}
						for _, x in pairs(d.emitters or {}) do em[#em + 1] = x.name .. "{" .. eText(x) .. "}" end
						for _, x in pairs(d.beams or {}) do em[#em + 1] = "beam " .. x.name .. "{" .. eText(x) .. "}" end
						for _, x in pairs(d.trails or {}) do em[#em + 1] = "trail " .. x.name .. "{" .. eText(x) .. "}" end
						local ms = {}
						for _, x in pairs(d.meshes or {}) do ms[#ms + 1] = mText(x) end
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
		for _, h in pairs(inf) do a(string.format("  %6.3f offset %s size ≥ %s %d contact(s) %s dmg on %s", h.at, v3s(h.offset), v3s(h.size), h.hits, fn(h.damage, 1), table.concat(h.targets, ", "))) end
	end
	sect("Movement", function(e) return ht(e) and e.cat == "MOVE" end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	if #rec.path > 1 then
		a("")
		a("■ Your displacement: " .. dw(rec.path[#rec.path].pos) .. "  (fwd = -Z)")
	end
	do
		local hs = Out.hits(rec)
		if #hs > 0 then
			a("")
			a("■ Damage (" .. #hs .. ")")
			for _, e in pairs(hs) do a("  " .. at(e) .. "  " .. e.text) end
		end
	end
	if #rec.victims > 0 then
		a("")
		a("■ Victims")
		for n, i in pairs(rec.vinfo or {}) do
			a(string.format("  %s — first %ss, closest %s, peak speed %s, hp %s/%s, by %s", n, fn(i.firstAt or 0, 2), fn(i.minDist or 0, 1),
				fn(i.peak or 0, 1), fn(i.hp or 0, 1), fn(i.maxhp or 0, 1), table.concat(i.reasons or {}, "+")))
			for _, h in pairs(X.holds(i.track or {})) do
				a(string.format("    held %s–%ss at %s from you (%s studs), facing %s°%s", fn(h.from, 2), fn(h.to, 2), dw(h.rel), fn(h.dist or 0, 1), fn(h.yaw or 0, 0),
					h.carried > 0.5 and (" - carried " .. fn(h.carried, 1) .. " studs with you") or ""))
			end
		end
	end
	sect("Victim reactions", function(e) return e.victim and (e.cat == "ANIM" or e.cat == "STATE" or e.cat == "VELOCITY") end, function(e) return at(e) .. "  " .. e.who .. "  " .. e.text end)
	sect("Grabs (welds / constraints between characters)", function(e) return e.cat == "MOVE" and (e.data.kind == "weld" or e.data.kind == "weldEnd") end, function(e) return at(e) .. "  " .. e.text end)
	sect("Your states", function(e) return e.who == "YOU" and e.cat == "STATE" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Camera", function(e) return e.cat == "CAMERA" end, function(e) return at(e) .. "  " .. e.text end)
	sect("Screen", function(e) return e.cat == "SCREEN" end, function(e) return at(e) .. "  " .. e.text end)
	do
		local gs = Out.remotes(rec)
		if #gs > 0 then
			a("")
			a("■ Remotes (" .. #gs .. ")")
			for _, g2 in pairs(gs) do
				a("  " .. at(g2.ev) .. "  " .. g2.ev.text .. (g2.n > 1 and ("  ×" .. g2.n .. " until " .. fn(g2.lastT, 3)) or ""))
			end
		end
	end
	for _, R in pairs(Out.relative(rec)) do
		if #R.events > 0 then
			a("")
			a(string.format("■ Timed against your animation %s rbxassetid://%s (starts %ss, plays %ss)", R.anim.data.name, R.anim.data.id, fn(R.anim.rt, 3), fn(R.anim.data.played or 0, 3)))
			for _, e in pairs(R.events) do
				a(string.format("  +%6.3f  %-7s %-10s %s", e.rt - R.anim.rt, e.cat, string.sub(e.who, 1, 10), string.sub(e.text, 1, 140)))
			end
		end
	end
	return table.concat(L, "\n")
end

function Out.moveTable(rec)
	local L = {}
	local function a(s) L[#L + 1] = s end
	local function tm(t) return fn(math.max(t, 0), 3) end
	a("-- Move #" .. rec.index .. " · " .. rec.name .. " · " .. rec.when)
	a("-- times from start · offsets/velocities local to you (fwd = -Z) · game adapter: " .. GAME.name)
	a("-- victims: FromYou = where they are from you right now; FromStart = from where you stood when the move began")
	if rec.net then
		a(string.format("-- net: ping %sms (jitter %s) - server-sent things reached this screen ~%sms late; use AnimRelative for exact gaps",
			fn(rec.net.ping, 0), fn(rec.net.jitter, 0), fn(rec.net.ping / 2, 0)))
	end
	if rec.startup then a("-- ADVANCED: startup ends at " .. tm(rec.startup) .. "s, Phase = \"hit\" from there") end
	a("return {")
	a("\tIndex = " .. rec.index .. ",")
	if rec.net then
		local hs = {}
		for _, h in pairs(rec.net.hitches or {}) do hs[#hs + 1] = "{ " .. fn(h[1], 3) .. ", " .. fn(h[2], 3) .. " }" end
		a(string.format("\tNet = { PingMs = %s, MinMs = %s, MaxMs = %s, JitterMs = %s, OneWayMs = %s, AvgFps = %s, Hitches = { %s } }, -- (hitch: at, frame length)", fn(rec.net.ping, 1), fn(rec.net.min, 1),
			fn(rec.net.max, 1), fn(rec.net.jitter, 1), fn(rec.net.ping / 2, 1), fn(rec.net.avgFps or rec.net.fps, 0), table.concat(hs, ", ")))
	end
	a("\tName = " .. qs(rec.name) .. ",")
	a("\tDuration = " .. tm(rec.duration) .. ",")
	if rec.startup then a("\tStartupDuration = " .. tm(rec.startup) .. ",") end
	a("\tStartLocalVelocity = " .. v3l(rec.startVel or Vector3.zero) .. ",")
	-- (3.11) how your character is animated here - if Animations stays empty, this says why
	a("\tAnimSetup = " .. string.format("%q", rec.animSetup or X.animSetup()) .. ",")
	if rec.focus then a(string.format("\tCombatMode = { Kind = %q, Label = %q, Hit = %s },", rec.focus.kind, rec.focus.label, tostring(rec.focus.hit or false))) end
	-- (3.11) every animation seen playing, straight from the Animators (FirstAt / LastAt: seconds from the start)
	a("\tAllTracks = { -- every animation seen playing on you / them (polled from their Animators every 0.1s)")
	for _, r in pairs(rec.allTracks or {}) do
		a(string.format("\t\t{ Who = %q, Id = \"rbxassetid://%s\", FirstAt = %s, LastAt = %s, Priority = %q, Length = %s, Looped = %s, Speed = %s, TimePosition = %s, On = %q },",
			r.who, tostring(r.id), fn(r.first, 3), fn(r.last - (rec.t0 or Rec.t0 or 0), 3), r.prio, fn(r.len, 3), tostring(r.looped), fn(r.speed, 2), fn(r.tp, 3), r.host))
	end
	a("\t},")
	a("\tPeakSpeed = " .. fn(rec.peak or 0, 3) .. ",")
	do
		local ok, err = pcall(X.comboOut, rec, a, tm)
		if not ok then a("\t-- (Combo couldn't be written: " .. tostring(err) .. ")") end
	end
	local function tag(ev, s)
		return rec.startup and (string.gsub(s, "^{ ", "{ Phase = " .. qs(ev.phase or "hit") .. ", ", 1)) or s
	end
	local function list(title, pred, f)
		a("\t" .. title .. " = {")
		for _, ev in pairs(rec.events) do if pred(ev) then a("\t\t" .. tag(ev, f(ev)) .. ",") end end
		a("\t},")
	end
	list("Animations", function(e) return e.cat == "ANIM" and e.who == "YOU" and not e.data.kind end, function(e)
		local mk = {}
		for _, m in pairs(e.data.markers or {}) do mk[#mk + 1] = string.format("{ Name = %s, Time = %s }", qs(m.name), fn(m.time, 3)) end
		return string.format("{ At = %s, Id = \"rbxassetid://%s\", Name = %s, Priority = %q, Speed = %s, Length = %s, Played = %s%s }", tm(e.rt), e.data.id, qs(e.data.name),
			e.data.priority, fn(e.data.speed, 3), fn(e.data.length or 0, 3), fn(e.data.played or 0, 3), #mk > 0 and (", Markers = { " .. table.concat(mk, ", ") .. " }") or "")
	end)
	list("AnimationEvents", function(e) return (e.cat == "MARKER" or (e.cat == "ANIM" and e.data.kind)) and (e.who == "YOU" or e.data.kind == "speed" or e.data.kind == "timejump") end, function(e)
		local extra = ""
		if e.data.kind == "speed" or e.data.kind == "timejump" then
			-- (3.2: the speed it went from / to, and whose animation)
			extra = string.format(", From = %s, To = %s, Who = %s", fn(e.data.from or 0, 3), fn(e.data.to or 0, 3), qs(e.who or "?"))
		end
		return string.format("{ At = %s, Kind = %q, Name = %s, AnimTime = %s, Param = %s%s }", tm(e.rt), e.data.kind or "marker", qs(e.data.name or e.data.id or "?"), fn(e.data.at or 0, 3), qs(e.data.param or ""), extra)
	end)
	a("\tVelocity = {")
	local stp = math.max(1, math.floor(math.max(#rec.path, 1) / 250))
	for i = 1, #rec.path, stp do
		local p = rec.path[i]
		if p.vel then a(string.format("\t\t{ At = %s, LocalVelocity = %s, Speed = %s },", tm(p.t), v3l(p.vel), fn(p.speed or 0, 2))) end
	end
	a("\t},")
	a("\tVelocityPhases = {")
	for _, ph in pairs(phases(rec.path)) do
		a(string.format("\t\t{ From = %s, To = %s, LocalVelocity = %s, PeakSpeed = %s },", tm(ph.from), tm(ph.to), v3l(ph.dir), fn(ph.peak, 2)))
	end
	a("\t},")
	list("Sounds", function(e) return e.cat == "SOUND" and not e.victim and not e.data.qte end, function(e)
		local dd = e.data
		return string.format("{ At = %s, Id = \"rbxassetid://%s\", Name = %s, Volume = %s, PlaybackSpeed = %s, TimePosition = %s, Parent = %s, Duration = %s, RollOffMode = %q%s }",
			tm(e.rt), dd.id, qs(dd.name), fn(dd.volume, 3), fn(dd.speed, 3), fn(dd.startAt or dd.timePosition, 3), qs(dd.parent), fn(dd.played or dd.length or 0, 3), dd.rollOffMode or "Inverse",
			-- (3.4: the volume heard (after the player's own setting), whether it had no position (flat - heard at full
			-- volume anywhere), and how far it carries)
			(dd.playedVolume and dd.playedVolume ~= dd.volume and (", PlayedVolume = " .. fn(dd.playedVolume, 3)) or "") ..
			(dd.flat and ", Flat = true" or "") ..
			(dd.region and (", PlaybackRegion = { " .. fn(dd.region[1], 3) .. ", " .. fn(dd.region[2], 3) .. " }") or "") ..
			(dd.foundPlaying and ", FoundPlaying = true" or "") ..
			(dd.seeks and #dd.seeks > 0 and (", Seeks = { " .. (function()
				local o = {}
				for _, x in pairs(dd.seeks) do o[#o + 1] = "{ " .. fn(x[1], 3) .. ", " .. fn(x[2], 3) .. " }" end
				return table.concat(o, ", ")
			end)() .. " }") or "") ..
			(dd.rollOffMin and (", RollOffMin = " .. fn(dd.rollOffMin, 1) .. ", RollOffMax = " .. fn(dd.rollOffMax or 0, 1)) or "") ..
			(dd.setting and (", VolumeSetting = { " .. qs(dd.setting[1]) .. ", " .. fn(dd.setting[2], 3) .. " }") or ""))
	end)
	list("Effects", function(e) return e.cat == "VFX" and not e.data.kind end, function(e)
		local d = e.data
		local as, co = {}, {}
		for _, x in pairs(d.assets or {}) do as[#as + 1] = string.format("{ Property = %s, Id = %s, Raw = %s }", qs(x.property), qs(x.id or ""), qs(x.raw)) end
		for _, x in pairs(d.colors or {}) do co[#co + 1] = string.format("{ Property = %s, Hex = %s }", qs(x.property), qs(x.hex)) end
		local mo = {}
		local ms = d.motion or {}
		local step = math.max(1, math.floor(#ms / 40))
		for k = 1, #ms, step do
			local x = ms[k]
			mo[#mo + 1] = string.format("{ T = %s%s%s%s%s%s%s }", fn(x.t, 3), x.pos and (", Offset = " .. v3l(x.pos)) or "", x.rot and (", Rot = " .. v3l(x.rot)) or "", x.size and (", Size = " .. v3l(x.size)) or "",
				x.transparency and (", Transparency = " .. fn(x.transparency, 3)) or "", x.scale and (", MeshScale = " .. v3l(x.scale)) or "", x.decal and (", DecalTransparency = " .. fn(x.decal, 3)) or "")
		end
		if #ms > 1 and (#ms - 1) % step ~= 0 then
			local x = ms[#ms]
			mo[#mo + 1] = string.format("{ T = %s%s%s%s%s%s%s }", fn(x.t, 3), x.pos and (", Offset = " .. v3l(x.pos)) or "", x.rot and (", Rot = " .. v3l(x.rot)) or "", x.size and (", Size = " .. v3l(x.size)) or "",
				x.transparency and (", Transparency = " .. fn(x.transparency, 3)) or "", x.scale and (", MeshScale = " .. v3l(x.scale)) or "", x.decal and (", DecalTransparency = " .. fn(x.decal, 3)) or "")
		end
		local at = {}
		for k, x in pairs(d.attributes or {}) do at[#at + 1] = string.format("[%s] = %s", qs(k), type(x) == "string" and qs(x) or tostring(x)) end
		local mm = {}
		for _, x in pairs(d.meshes or {}) do mm[#mm + 1] = mLua(x) end
		return string.format("{ At = %s, Name = %s, Class = %q, Folder = %s, Offset = %s, HostSize = %s, HostTexture = %s, HostMeshId = %s, Lifetime = %s, EmitterCount = %d, BeamCount = %d, TrailCount = %d, Assets = { %s }, Colors = { %s }%s%s%s%s%s }",
			tm(e.rt), qs(d.name), d.class, qs(d.folder or "?"), d.offsetCF and cfl(d.offsetCF) or "CFrame.new()", d.size and v3l(d.size) or "Vector3.one",
			qs(d.hostTexture or ""), qs(d.hostMeshId or ""), fn(d.lifetime or 0, 3), #(d.emitters or {}), #(d.beams or {}), #(d.trails or {}), table.concat(as, ", "), table.concat(co, ", "),
			d.saved and (", Saved = " .. qs(d.saved)) or "", d.weldedTo and (", WeldedTo = " .. qs(d.weldedTo)) or "",
			#at > 0 and (", Attributes = { " .. table.concat(at, ", ") .. " }") or "", #mo > 0 and (", Motion = { " .. table.concat(mo, ", ") .. " }") or "", #mm > 0 and (", Meshes = { " .. table.concat(mm, ", ") .. " }") or "")
			:sub(1, -3) .. (d.camCF and (", FromCamera = " .. cfl(d.camCF)) or "") .. (function()
				local lp = X.loopList(d, Rec.t0)
				return #lp > 0 and (", Loops = { " .. table.concat(lp, ", ") .. " }") or ""
			end)() .. X.effExtra(d) .. " }"
	end)
	-- (3.3) what kept going: effects whose emitters stayed on, or were emitted again and again (Off = nil: still on at the end)
	a("\tLoops = {")
	for _, e in pairs(rec.events) do
		if e.cat == "VFX" and not e.data.kind and e.data.loops then
			local lp = X.loopList(e.data, Rec.t0)
			if #lp > 0 then a(string.format("\t\t{ At = %s, Name = %s, Folder = %s, Emitters = { %s } },", fn(math.max(e.rt or 0, 0), 3), qs(e.data.name), qs(e.data.folder or "?"), table.concat(lp, ", "))) end
		end
	end
	a("\t},")
	-- (3.2) projectiles: effects that travelled (from their own motion samples, measured from where you started)
	a("\tProjectiles = { -- From / To: from where you stood at the start (fwd = -Z); Speed studs/s; Drop: how far it fell below a straight line")
	for _, e in pairs(rec.events) do
		local ms = e.cat == "VFX" and not e.data.kind and e.data.motion
		if ms and #ms >= 2 then
			local f, l = nil, nil
			for _, x in pairs(ms) do if x.pos then f = f or x l = x end end
			if f and l and l ~= f and (l.pos - f.pos).Magnitude > 8 and l.t > f.t then
				local dt = l.t - f.t
				local mid = nil
				for _, x in pairs(ms) do if x.pos and x.t >= f.t + dt * 0.4 and x.t <= f.t + dt * 0.6 then mid = x break end end
				local drop = 0
				if mid then drop = ((f.pos + l.pos) / 2).Y - mid.pos.Y end
				a(string.format("\t\t{ At = %s, Name = %s, Class = %q, From = %s, To = %s, Direction = %s, Speed = %s, Flight = %s, Drop = %s, Lifetime = %s },",
					tm(e.rt + f.t), qs(e.data.name), e.data.class or "?", v3l(f.pos), v3l(l.pos), v3l((l.pos - f.pos).Unit), fn((l.pos - f.pos).Magnitude / dt, 2),
					fn(dt, 3), fn(-drop, 2), fn(e.data.lifetime or 0, 3)))
			end
		end
	end
	a("\t},")
	a("\tEmitterDumps = { -- identical emitters are written once (later copies say which one)")
	local ei = 0
	local dumped = {}
	local function dump1(em, v, label)
		local code = emitLua(em, v)
		local prev = dumped[code]
		if prev then a("\t\t\t-- " .. label .. " " .. tostring(em.name) .. ": same as " .. prev) return end
		dumped[code] = "#" .. ei .. " " .. tostring(em.name)
		a("\t\t\t{ -- " .. label)
		a(code)
		a("\t\t\t},")
	end
	Out.dump1 = dump1
	for _, ev in pairs(rec.events) do
		if ev.cat == "VFX" and not ev.data.kind and not ev.data.duplicate then
			ei = ei + 1
			a(string.format("\t\t[%d] = { -- %s '%s' at %ss", ei, ev.data.class, ev.data.name, tm(ev.rt)))
			for _, em in pairs(ev.data.emitters or {}) do
				dump1(em, "em", "EMITTER on part of size " .. (em.hostSize and v3l(Vector3.new(em.hostSize[1], em.hostSize[2], em.hostSize[3])) or "?"))
			end
			for _, em in pairs(ev.data.beams or {}) do dump1(em, "bm", "BEAM") end
			for _, em in pairs(ev.data.trails or {}) do dump1(em, "tr", "TRAIL") end
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
		for _, x in pairs(e.data.emits or {}) do l2[#l2 + 1] = string.format("{ %s, %s }", qs(x.path), fn(x.count)) end
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
		for _, ev in pairs(rec.events) do
			if ev.cat == "EFFECT" and ev.data.templates and not seen[ev.data.assets] then
				seen[ev.data.assets] = true
				a("\t\t[" .. qs(ev.data.assets) .. "] = { -- " .. ev.data.module .. "." .. ev.data.func)
				for _, t in pairs(ev.data.templates) do
					local d = t.d
					if t.sound then
						a(string.format("\t\t\t{ Path = %s, Class = \"Sound\", Id = \"rbxassetid://%s\", Volume = %s, PlaybackSpeed = %s },", qs(t.path), tostring(t.sound.id), fn(t.sound.volume, 3), fn(t.sound.speed, 3)))
					elseif t.anim then
						a(string.format("\t\t\t{ Path = %s, Class = \"Animation\", Id = \"rbxassetid://%s\" },", qs(t.path), tostring(t.anim)))
					elseif d then
						a(string.format("\t\t\t{ Path = %s, Class = %q, Size = %s, HostTexture = %s, HostMeshId = %s, EmitterCount = %d, BeamCount = %d, TrailCount = %d,",
							qs(t.path), t.class, d.size and v3l(d.size) or "nil", qs(d.hostTexture or ""), qs(d.hostMeshId or ""), #(d.emitters or {}), #(d.beams or {}), #(d.trails or {})))
						for _, x in pairs(d.meshes or {}) do a("\t\t\t\t" .. mLua(x) .. ", -- MESH") end
						for _, em in pairs(d.emitters or {}) do Out.dump1(em, "em", "EMITTER") end
						for _, em in pairs(d.beams or {}) do Out.dump1(em, "bm", "BEAM") end
						for _, em in pairs(d.trails or {}) do Out.dump1(em, "tr", "TRAIL") end
						a("\t\t\t},")
					end
				end
				a("\t\t},")
			end
		end
	end
	a("\t},")
	a("\tBuilders = {")
	a(X.TREEHEADER)
	do
		local done = {}
		local function emit(key, tree)
			if not tree then return end
			local code = X.treeLua(tree, "\t\t\t")
			if done[code] then a("\t\t-- " .. key .. ": same as " .. done[code]) return end
			done[code] = key
			a(string.format("\t\t[%q] = function()\n\t\t\treturn %s\n\t\tend,", key, string.gsub(code, "^%s+", "")))
		end
		for _, e in pairs(rec.events) do
			if e.cat == "VFX" and not e.data.kind and e.data.tree then emit(string.format("%s @%s", e.data.name, tm(e.rt)), e.data.tree) end
		end
		for _, e in pairs(rec.events) do
			if e.cat == "EFFECT" and e.data.templates then
				for _, t in pairs(e.data.templates) do emit("TEMPLATE " .. t.path, t.tree) end
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
	for _, h in pairs(infer(rec)) do
		a(string.format("\t\t{ At = %s, Offset = CFrame.new(%s, %s, %s), Size = %s, Hits = %d, Damage = %s },", tm(h.at), fn(h.offset.X), fn(h.offset.Y), fn(h.offset.Z), v3l(h.size), h.hits, fn(h.damage, 2)))
	end
	a("\t},")
	list("Movement", function(e) return e.cat == "MOVE" and e.who == "YOU" and e.data.kind ~= "end" end, function(e)
		return string.format("{ At = %s, Class = %q%s%s }", tm(e.rt), e.data.class or "?", e.data.localVelocity and (", LocalVelocity = " .. v3l(e.data.localVelocity)) or "",
			e.data.duration and (", Duration = " .. fn(e.data.duration, 3)) or "")
	end)
	a("\tDamage = {")
	for _, e in Out.hits(rec, function(e) return e.who ~= "YOU" end) do
		a(string.format("\t\t{ At = %s, Target = %s, Amount = %s },", tm(e.rt), qs(e.data.target), fn(e.data.amount, 2)))
	end
	a("\t},")
	a("\tVictim = {")
	for n, i in pairs(rec.vinfo or {}) do
		a("\t\t[" .. qs(n) .. "] = {")
		a(string.format("\t\t\tFirstAt = %s, MinDistance = %s, PeakSpeed = %s, Health = %s, MaxHealth = %s, TrackedBy = %s,", fn(i.firstAt or 0, 3), fn(i.minDist or 0, 2),
			fn(i.peak or 0, 2), fn(i.hp or 0, 1), fn(i.maxhp or 0, 1), qs(table.concat(i.reasons or {}, "+"))))
		a("\t\t\tTrack = {")
		local tr = i.track or {}
		-- (another character's movement reaches this screen late: one-way ping + Roblox's ~0.1s smoothing buffer)
		local plag = rec.net and (rec.net.ping / 2000 + 0.1) or 0.15
		a(string.format("\t\t\tPhysicsLag = %s, -- their movement below is seen ~this late: real time ≈ At - PhysicsLag (ServerAt)", fn(plag, 3)))
		local ts = math.max(1, math.floor(math.max(#tr, 1) / 250))
		for x = 1, #tr, ts do
			local p = tr[x]
			a(string.format("\t\t\t\t{ At = %s, ServerAt = %s, FromYou = %s, Yaw = %s, Distance = %s, FromStart = %s, LocalVelocity = %s, Speed = %s%s },", tm(p.t), tm(math.max(0, p.t - plag)),
				p.rel and v3l(p.rel) or "nil", fn(p.yaw or 0, 1), fn(p.dist or 0, 2), v3l(p.pos), p.vel and v3l(p.vel) or "Vector3.zero", fn(p.speed or 0, 2),
				p.cf and (", World = " .. X.full(p.cf)) or ""))
		end
		a("\t\t\t},")
		a("\t\t\tHolds = { -- spans they stayed put relative to you: Hold = CFrame from your root (grab offset), Carried = studs moved together")
		for _, h in pairs(X.holds(tr)) do
			a(string.format("\t\t\t\t{ From = %s, To = %s, Hold = CFrame.new(%s, %s, %s) * CFrame.Angles(0, math.rad(%s), 0), Distance = %s, Carried = %s },", tm(h.from), tm(h.to),
				fn(h.rel.X, 2), fn(h.rel.Y, 2), fn(h.rel.Z, 2), fn(h.yaw or 0, 0), fn(h.dist or 0, 2), fn(h.carried, 2)))
		end
		a("\t\t\t},")
		a("\t\t},")
	end
	local function vlist(title, pred, f)
		a("\t\t" .. title .. " = {")
		for _, ev in pairs(rec.events) do if ev.victim and pred(ev) then a("\t\t\t" .. tag(ev, f(ev)) .. ",") end end
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
		if e.data.kind == "type" then
			return string.format("{ At = %s, Kind = \"CameraType\", From = %q, To = %q }", tm(e.rt), e.data.from, e.data.to)
		end
		if e.data.kind == "cutscene" then
			local fr = {}
			for i, f in pairs(e.data.frames) do
				fr[i] = "{ " .. fn(f[1], 3) .. ", " .. fn(f[2], 2) .. ", " .. fn(f[3], 2) .. ", " .. fn(f[4], 2) .. ", " .. fn(f[5], 2) .. ", " .. fn(f[6], 2) .. ", " .. fn(f[7], 2) .. ", " .. fn(f[8], 2) .. " }"
			end
			return string.format("{ At = %s, Kind = \"Cutscene\", Duration = %s, CameraType = %q, Subject = %s, FovBefore = %s, FovAfter = %s, -- Frames: { time, x, y, z (studs from your root, local), rx, ry, rz (deg, YXZ), fov } - camera = root.CFrame * CFrame.new(x, y, z) * CFrame.fromEulerAnglesYXZ(rad(rx), rad(ry), rad(rz))\n\t\t\tFrames = { %s } }",
				tm(e.rt), fn(e.data.duration, 3), e.data.ctype or "?", qs(e.data.subject or "?"), fn(e.data.fovFrom or 0, 2), fn(e.data.fovTo or 0, 2), table.concat(fr, ", "))
		end
		return string.format("{ At = %s, Kind = \"Shake\", Duration = %s, Strength = %s, Source = %q }", tm(e.rt), fn(e.data.duration or 0, 3), fn(e.data.strength or 0, 3), e.data.source or "camera (degrees)")
	end)
	list("Screen", function(e) return e.cat == "SCREEN" end, function(e)
		return string.format("{ At = %s, Kind = %q, Class = %q, Name = %s, Detail = %s%s }", tm(e.rt), e.data.kind or "?", e.data.class or "?", qs(e.data.name or "?"),
			qs(e.text or ""), e.data.images and #e.data.images > 0 and (", Images = { " .. table.concat((function() local o = {} for _, x in pairs(e.data.images) do o[#o + 1] = qs(x) end return o end)(), ", ") .. " }") or "")
	end)
	a("\tRemotes = {")
	for _, g2 in pairs(Out.remotes(rec)) do
		local e = g2.ev
		a(string.format("\t\t{ At = %s, Remote = %s, Label = %s, Args = %s%s },", tm(e.rt), qs(e.data.remote), qs(e.data.label or ""), qs(ser(e.data.args)),
			g2.n > 1 and string.format(", Count = %d, Until = %s", g2.n, tm(g2.lastT)) or ""))
	end
	a("\t},")
	a("\tAnimRelative = { -- per animation of yours: what happened, in seconds after it started (lag-free gaps)")
	for _, R in pairs(Out.relative(rec)) do
		if #R.events > 0 then
			a(string.format("\t\t{ Anim = \"rbxassetid://%s\", Name = %s, Start = %s, Played = %s, Events = {", R.anim.data.id, qs(R.anim.data.name), tm(R.anim.rt), fn(R.anim.data.played or 0, 3)))
			for _, e in pairs(R.events) do
				a(string.format("\t\t\t{ %s, %q, %s, %s },", fn(e.rt - R.anim.rt, 3), e.cat, qs(e.who), qs(string.sub(e.text, 1, 160))))
			end
			a("\t\t} },")
		end
	end
	a("\t},")
	X.worldOut(rec, a, tm)
	do
		local ok, err = pcall(X.wpnOut, rec, a, tm)
		if not ok then a("\t-- (Weapons couldn't be written: " .. tostring(err) .. ")") end
		ok, err = pcall(X.changesOut, rec, a, tm)
		if not ok then a("\t-- (Changes couldn't be written: " .. tostring(err) .. ")") end
	end
	a("\tPath = { -- Offset: from where you stood at the start (fwd = -Z); World: your root's own CFrame (3.6)")
	local ps = math.max(1, math.floor(#rec.path / 250))
	for i = 1, #rec.path, ps do
		local p = rec.path[i]
		-- (3.6: around a teleport every point is kept)
		a(string.format("\t\t{ At = %s, Offset = %s, Speed = %s%s },", tm(p.t), v3l(p.pos), fn(p.speed or 0, 2), p.cf and (", World = " .. X.full(p.cf)) or ""))
		if ps > 1 then
			for k = i + 1, math.min(i + ps - 1, #rec.path) do
				local q, q0 = rec.path[k], rec.path[k - 1]
				if q.wp and q0.wp and (q.wp - q0.wp).Magnitude > 30 then
					a(string.format("\t\t{ At = %s, Offset = %s, Speed = %s%s }, -- (a jump)", tm(q0.t), v3l(q0.pos), fn(q0.speed or 0, 2), q0.cf and (", World = " .. X.full(q0.cf)) or ""))
					a(string.format("\t\t{ At = %s, Offset = %s, Speed = %s%s },", tm(q.t), v3l(q.pos), fn(q.speed or 0, 2), q.cf and (", World = " .. X.full(q.cf)) or ""))
				end
			end
		end
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
	for _, d in pairs(fx:GetDescendants()) do
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
	for _, ev in pairs(rec.events) do
		if ev.cat == "HIT" and ev.who ~= "YOU" and (ev.data.amount or 0) > 0 then firstHit = ev.rt break end
	end
	a("local function react(aroot, vic, h, dmg)")
	a("\th:TakeDamage(dmg)")
	a("\tlocal vr = vic:FindFirstChild(\"HumanoidRootPart\")")
	if firstHit then
		local vn
		for _, ev in pairs(rec.events) do if ev.cat == "HIT" and ev.who ~= "YOU" and ev.rt == firstHit then vn = ev.who break end end
		for _, ev in pairs(rec.events) do
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
	for _, ev in pairs(rec.events) do
		if ev.cat == "HITBOX" and ev.data.kind ~= "touch" then hbs[#hbs + 1] = { at = ev.rt, off = ev.data.offsetCF, size = ev.data.size, dur = ev.data.lifetime or 0.1 } end
	end
	local inf = infer(rec)
	if #hbs == 0 then
		for _, x in pairs(inf) do hbs[#hbs + 1] = { at = x.at - 0.03, off = CFrame.new(x.offset), size = x.size, dur = 0.1, dmg = x.damage / math.max(x.hits, 1) } end
	end
	local dd = #inf > 0 and (inf[1].damage / math.max(inf[1].hits, 1)) or 10
	local lines = {}
	for _, ev in pairs(rec.events) do
		local t = ev.rt
		if ev.who == "YOU" and ev.cat == "ANIM" and not ev.data.kind then
			lines[#lines + 1] = { t, string.format("task.delay(%s, playAnim, h, \"rbxassetid://%s\", %s) -- %s%s", tm(t), ev.data.id, fn(ev.data.speed, 3), ev.data.name,
				ev.phase == "startup" and " [startup]" or "") }
		elseif ev.cat == "SOUND" and not ev.victim then
			lines[#lines + 1] = { t, string.format("task.delay(%s, playSound, root, \"rbxassetid://%s\", %s, %s, %s, %s, %s) -- %s", tm(t), ev.data.id,
				fn(ev.data.volume, 3), fn(ev.data.speed, 3), fn(ev.data.startAt or ev.data.timePosition, 3), fn(ev.data.played or ev.data.length or 1, 3), qs(ev.data.rollOffMode or "Inverse"), ev.data.name) }
		elseif ev.cat == "VFX" and not ev.data.kind then
			lines[#lines + 1] = { t, string.format("task.delay(%s, spawnFX, root, %s, %s, %s) -- %s", tm(t), qs(ev.data.saved or ev.data.name),
				ev.data.offsetCF and cfl(ev.data.offsetCF) or "CFrame.new()", fn(ev.data.lifetime or 1, 3), ev.data.class) }
		elseif ev.who == "YOU" and ev.cat == "MOVE" and ev.data.localVelocity and ev.data.kind ~= "end" then
			lines[#lines + 1] = { t, string.format("task.delay(%s, addVel, root, %s, %s) -- %s", tm(t), v3l(ev.data.localVelocity), fn(ev.data.duration or 0.15, 3), ev.data.class or "impulse") }
		elseif ev.who == "YOU" and ev.cat == "VELOCITY" and ev.data.kind == "velocityPhase" and ev.data.localVelocity then
			lines[#lines + 1] = { t, string.format("task.delay(%s, addVel, root, %s, %s) -- motion phase", tm(t), v3l(ev.data.localVelocity), fn(ev.data.duration or 0.2, 3)) }
		end
	end
	for _, x in pairs(hbs) do
		lines[#lines + 1] = { x.at, string.format("task.delay(%s, function() hitbox(character, root, %s, %s, %s, function(v, hh) react(root, v, hh, %s) end) end) -- hitbox", tm(x.at),
			x.off and cfl(x.off) or "CFrame.new(0, 0, -4)", x.size and v3l(x.size) or "Vector3.new(5, 5, 5)", fn(math.max(x.dur, 0.05), 3), fn(x.dmg or dd, 2)) }
	end
	table.sort(lines, function(p, q) return p[1] < q[1] end)
	for _, l in pairs(lines) do a("\t" .. l[2]) end
	a("end")
	a("")
	a("return Move")
	return table.concat(L, "\n")
end

-- (3.13) just the combat part of a recording: your tracks, Combo / Dashes / Inputs, Weapons, your sounds
function Out.combat(rec)
	local L = {}
	local function a(s) L[#L + 1] = s end
	local function tm(t) return fn(math.max(t, 0), 3) end
	a("-- Combat log · " .. tostring(rec.label or rec.name) .. " · " .. tostring(rec.when) .. " · times from the start (fwd = -Z)")
	a("return {")
	a(string.format("\tLabel = %s, Mode = %q, Hit = %s, Duration = %s%s,", qs(rec.label or rec.name), rec.focus and rec.focus.kind or "", tostring(rec.focus and rec.focus.hit or false),
		tm(rec.duration), rec.net and (", PingMs = " .. fn(rec.net.ping, 1)) or ""))
	a("\tYourTracks = {")
	for _, r in pairs(rec.allTracks or {}) do
		if r.who == "YOU" then
			a(string.format("\t\t{ Id = \"rbxassetid://%s\", FirstAt = %s, LastAt = %s, Priority = %q, Length = %s, Looped = %s, Speed = %s },", tostring(r.id), fn(r.first, 3),
				fn(r.last - (rec.t0 or Rec.t0 or 0), 3), r.prio, fn(r.len, 3), tostring(r.looped), fn(r.speed, 2)))
		end
	end
	a("\t},")
	local ok, err = pcall(X.comboOut, rec, a, tm)
	if not ok then a("\t-- (Combo: " .. tostring(err) .. ")") end
	a("\tSounds = {")
	for _, e in pairs(rec.events) do
		if e.cat == "SOUND" and not e.victim then
			a(string.format("\t\t{ At = %s, Id = \"rbxassetid://%s\", Name = %s, Volume = %s, Parent = %s },", tm(e.rt), tostring(e.data.id), qs(e.data.name), fn(e.data.volume or 0, 2), qs(e.data.parent or "")))
		end
	end
	a("\t},")
	a("\tDamage = {")
	for _, e in pairs(rec.events) do
		if e.cat == "HIT" then a(string.format("\t\t{ At = %s, Target = %s, Amount = %s },", tm(e.rt), qs(e.data.target or e.who), fn(e.data.amount or 0, 2))) end
	end
	a("\t},")
	ok, err = pcall(X.wpnOut, rec, a, tm)
	if not ok then a("\t-- (Weapons: " .. tostring(err) .. ")") end
	a("}")
	return table.concat(L, "\n")
end

function Out.json(rec)
	local evs = {}
	for _, ev in pairs(rec.events) do
		evs[#evs + 1] = { t = rd(ev.rt, 4), cat = ev.cat, who = ev.who, victim = ev.victim or nil, phase = ev.phase, text = ev.text, data = plain(ev.data) }
	end
	local ok, s = pcall(HS.JSONEncode, HS, { index = rec.index, name = rec.name, duration = rd(rec.duration, 4), startupDuration = rec.startup,
		when = rec.when, placeId = rec.placeId, character = rec.character, victims = rec.victims, victimInfo = plain(rec.vinfo),
		events = evs, inferredHitboxes = plain(infer(rec)), path = plain(rec.path) })
	return ok and s or ("JSON failed: " .. tostring(s))
end

---------------------------------------------------------------------------------------------------
-- (UI + startup live in their own function: keeps the main chunk under the 200-register limit of unoptimized compilers like loadstring)
local function __MLUI()
local function mk(cl, p, kids)
	local i = Instance.new(cl)
	for k, v in pairs(p or {}) do if k ~= "Parent" then i[k] = v end end
	for _, c in pairs(kids or {}) do c.Parent = i end
	if p and p.Parent then i.Parent = p.Parent end
	return i
end
local function cor(rad) return mk("UICorner", { CornerRadius = UDim.new(0, rad or 8) }) end
local function strk(c, t) return mk("UIStroke", { Color = c or T.Stroke, Thickness = t or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function pd(p) return mk("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }) end
local F, FB, FM = Enum.Font.GothamMedium, Enum.Font.GothamBold, Enum.Font.Code
local function lbl(txt, p)
	local d = { BackgroundTransparency = 1, Text = txt, TextColor3 = T.Text, Font = F, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }
	for k, v in pairs(p or {}) do d[k] = v end
	return mk("TextLabel", d)
end
local function btn(txt, p, fn2)
	local d = { BackgroundColor3 = T.Pan2, Text = txt, TextColor3 = T.Text, Font = F, TextSize = 13, AutoButtonColor = false, Size = UDim2.fromOffset(80, 28) }
	for k, v in pairs(p or {}) do d[k] = v end
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
lbl("Move Logger 3.13", { Position = UDim2.fromOffset(28, 0), Size = UDim2.new(0, 130, 1, 0), Font = FB, TextSize = 13, Parent = bar })
local stat = lbl("idle", { Position = UDim2.fromOffset(150, 0), Size = UDim2.new(1, -230, 1, 0), TextColor3 = T.Sub, TextSize = 11, Parent = bar })
local minB = btn("–", { Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -62, 0.5, -11), Parent = bar })
local clsB = btn("×", { Size = UDim2.fromOffset(26, 22), Position = UDim2.new(1, -32, 0.5, -11), Parent = bar })
local tabs = mk("Frame", { Size = UDim2.new(1, -20, 0, 28), Position = UDim2.fromOffset(10, 40), BackgroundTransparency = 1, Parent = win }, { hl(6) })
local body = mk("Frame", { Size = UDim2.new(1, -20, 1, -78), Position = UDim2.fromOffset(10, 74), BackgroundTransparency = 1, ClipsDescendants = true, Parent = win })
local pages, tbtns = {}, {}
local function showTab(n)
	for k, p in pairs(pages) do p.Visible = k == n end
	for k, b in pairs(tbtns) do
		b.BackgroundColor3 = k == n and T.Acc or T.Pan2
		b.TextColor3 = k == n and Color3.new(1, 1, 1) or T.Sub
	end
	if UI.onTab then UI.onTab(n) end
end
for i, n in { "Record", "Combat", "Moves", "Settings" } do
	local b = btn(n, { Size = UDim2.fromOffset(math.floor((W - 20 - 18) / 4), 26), LayoutOrder = i, TextSize = 12, Parent = tabs })
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
local function zip(txt)
	local ok, z = pcall(function()
		local ES = game:GetService("EncodingService")
		local c = ES:CompressBuffer(buffer.fromstring(txt), Enum.CompressionAlgorithm.Zstd, 9)
		return buffer.tostring(ES:Base64Encode(c))
	end)
	if ok and type(z) == "string" then return "MLZ1:" .. z end
	return nil
end
Self.zip = zip
function copyText(txt, what, box)
	if C.Zip or #txt > C.ZipOver then
		local z = zip(txt)
		if z then
			what = what .. string.format(" compressed %dKB → %dKB (paste into the decoder)", math.ceil(#txt / 1024), math.ceil(#z / 1024))
			txt = z
			if box and #txt <= 120000 then box.Text = txt end
		elseif #txt > C.ZipOver then
			toast("too big to copy safely (" .. math.ceil(#txt / 1024) .. "KB) and this game has no EncodingService — use Summary or turn off Templates")
			return
		end
	end
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
	for i, c in pairs(CATS) do
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
		for _, ev in pairs(src) do cnt[ev.cat] = (cnt[ev.cat] or 0) + 1 end
		for _, c in pairs(CATS) do
			cLabels[c].Text = c .. " " .. (cnt[c] or 0)
			cLabels[c].TextColor3 = (cnt[c] or 0) > 0 and T.Text or T.Sub
		end
		local vn = {}
		if s == "recording" and not Rec.noVic then
			for _, v in pairs(Rec.victims) do vn[#vn + 1] = v.name end
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
		for i, l in pairs(fLines) do l.Text = fBuf[i] and line(fBuf[i]) or "" end
	end
	function UI.feedFromRec(r)
		table.clear(fBuf)
		local n = r and #r.events or 0
		for i = math.max(1, n - #fLines + 1), n do fBuf[#fBuf + 1] = r.events[i] end
		for i, l in pairs(fLines) do l.Text = fBuf[i] and line(fBuf[i]) or "" end
	end
end)

---------------------------------------------------------------------------------------------------
-- (3.13) Combat tab: one button per thing to log. Pick one, then do it: it starts on your next input / attack, stops
-- by itself when you're done, and the recording is labelled with what it was. Guided goes through all of them.
sec("combat page", function()
	local pg = pages.Combat
	local MODES = {
		{ "M1 chain · miss", "m1", false, "Away from anyone: hold M1 until the whole chain is done. Stops by itself." },
		{ "M1 chain · hit", "m1", true, "Next to a dummy: hold M1 until the whole chain is done. Stops by itself." },
		{ "Downslam · miss", "downslam", false, "M1s, then jump and do the last M1 in the air (the downslam)." },
		{ "Downslam · hit", "downslam", true, "Next to a dummy: M1s, then jump and do the last M1 in the air." },
		{ "Uppercut · miss", "uppercut", false, "M1s with jump held on the last one (the uppercut)." },
		{ "Uppercut · hit", "uppercut", true, "Next to a dummy: M1s with jump held on the last one." },
		{ "Dash · front", "dash", false, "Dash forward (Q / the dash button). Stops 1s after." },
		{ "Dash · back", "dash", false, "Hold back and dash. Stops 1s after." },
		{ "Dash · left", "dash", false, "Hold left and dash. Stops 1s after." },
		{ "Dash · right", "dash", false, "Hold right and dash. Stops 1s after." },
		{ "Block / parry", "block", false, "Hold block while the dummy hits you (or parry). Stops 1.5s after." },
		{ "Other", "other", false, "Anything else (running M1, air combo...). Stops when you're done." },
	}
	local cw = math.floor((W - 20 - 15) / 4)
	local status = lbl("COMBAT", { Size = UDim2.new(1, 0, 0, 22), Font = FB, TextSize = 16, Parent = pg })
	local hint = lbl("Pick what to log. It starts on your next input and stops by itself.", { Position = UDim2.fromOffset(0, 22), Size = UDim2.new(1, 0, 0, 28),
		TextSize = 10, TextColor3 = T.Sub, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Parent = pg })
	local grid = mk("Frame", { Position = UDim2.fromOffset(0, 52), Size = UDim2.new(1, 0, 0, 3 * 26 + 2 * 5), BackgroundTransparency = 1, Parent = pg },
		{ mk("UIGridLayout", { CellSize = UDim2.fromOffset(cw, 26), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder }) })
	local mbtns = {}
	local function paint()
		for i, b in pairs(mbtns) do
			local on = X.focus and X.focus.idx == i
			b.BackgroundColor3 = on and T.Acc or T.Pan2
			b.TextColor3 = on and Color3.new(1, 1, 1) or (MODES[i][3] and T.Hit or T.Text)
		end
	end
	local function pick(i)
		local m = MODES[i]
		if Rec.state == "recording" then stopRec("manual") end
		X.focus = { kind = m[2], label = m[1], hit = m[3], idx = i }
		if UI.nameBox then UI.nameBox.Text = m[1] end
		arm()
		hint.Text = (X.queue and ("Guided " .. X.queue.at .. "/" .. #MODES .. " · ") or "") .. m[1] .. ": " .. m[4]
		paint()
		if UI.refreshCombat then pcall(UI.refreshCombat) end
	end
	for i, m in ipairs(MODES) do
		mbtns[i] = btn(m[1], { LayoutOrder = i, TextSize = 10, Parent = grid }, function()
			X.queue = nil
			pick(i)
		end)
	end
	local row = mk("Frame", { Position = UDim2.fromOffset(0, 52 + 88 + 6), Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Parent = pg }, { hl(5) })
	local function stopAll()
		X.queue = nil
		X.focus = nil
		if UI.nameBox then UI.nameBox.Text = "" end
		if Rec.state == "recording" then stopRec("manual") else setState("idle") end
		hint.Text = "Stopped. Pick what to log next."
		paint()
		if UI.refreshCombat then pcall(UI.refreshCombat) end
	end
	btn("Guided ▶ all", { Size = UDim2.fromOffset(cw, 26), LayoutOrder = 1, TextSize = 10, BackgroundColor3 = Color3.fromRGB(28, 48, 32), Parent = row }, function()
		X.queue = { at = 1 }
		pick(1)
	end)
	btn("■ Stop", { Size = UDim2.fromOffset(cw, 26), LayoutOrder = 2, TextSize = 10, Parent = row }, stopAll)
	btn("Copy breakdown", { Size = UDim2.fromOffset(cw, 26), LayoutOrder = 3, TextSize = 10, BackgroundColor3 = T.Acc, Parent = row }, function()
		local r = nil
		for k = #Hist, 1, -1 do if Hist[k].focus then r = Hist[k] break end end
		r = r or Hist[Sel]
		if not r then return toast("nothing logged yet") end
		local ok, s = pcall(Out.combat, r)
		if not ok then return toast("failed: " .. tostring(s)) end
		copyText(s, "combat breakdown of #" .. r.index, nil)
	end)
	-- (every Combat-tab recording, in full, as one .txt - what to send)
	btn("Export .txt", { Size = UDim2.fromOffset(cw, 26), LayoutOrder = 4, TextSize = 10, BackgroundColor3 = T.Acc, Parent = row }, function()
		local o, n = {}, 0
		for _, r in pairs(Hist) do
			if r.focus then
				n = n + 1
				local ok, s = pcall(Out.moveTable, r)
				s = ok and s or "-- failed"
				o[#o + 1] = (r.label or r.name) .. ":"
				o[#o + 1] = ""
				o[#o + 1] = Self.zip(s) or s
				o[#o + 1] = ""
			end
		end
		if n == 0 then return toast("no Combat-tab recordings yet") end
		local txt = table.concat(o, "\n")
		local saved = typeof(writefile) == "function" and pcall(writefile, "MoveLogger_combat.txt", txt)
		if typeof(setclipboard) == "function" and pcall(setclipboard, txt) then
			toast(string.format("copied %d combat log(s) (%dKB)%s", n, math.ceil(#txt / 1024), saved and " · saved MoveLogger_combat.txt" or ""))
		elseif saved then
			toast("saved MoveLogger_combat.txt (" .. n .. ")")
		else
			toast("no clipboard")
		end
	end)
	local list = mk("ScrollingFrame", { Position = UDim2.fromOffset(0, 52 + 88 + 6 + 30), Size = UDim2.new(1, 0, 1, -(52 + 88 + 6 + 30)), BackgroundColor3 = T.Pan,
		ScrollBarThickness = 4, ScrollBarImageColor3 = T.Stroke, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), BorderSizePixel = 0, Parent = pg },
		{ cor(8), pd(6), vl(2) })
	local lines = {}
	local function setLines(t)
		for i, s in ipairs(t) do
			local l = lines[i]
			if not l then
				l = lbl("", { Size = UDim2.new(1, 0, 0, 13), TextSize = 10, Font = FM, TextTruncate = Enum.TextTruncate.AtEnd, LayoutOrder = i, Parent = list })
				lines[i] = l
			end
			l.Text = s
			l.Visible = true
		end
		for i = #t + 1, #lines do lines[i].Visible = false end
	end
	-- the swings in a recording, one short line each
	local function swingLines(evs, t0, live)
		local o = {}
		local sw = {}
		for _, e in pairs(evs) do
			if e.cat == "ANIM" and e.who == "YOU" and not e.data.kind and not e.data.looped and X.ACT[e.data.priority or ""] then sw[#sw + 1] = e end
		end
		if live then
			-- (live: also what's been seen playing)
			for _, r in pairs(X.seenList or {}) do
				if r.who == "YOU" and not r.looped and X.ACT[r.prio] then
					local st = r.first - (r.tp or 0) / math.max(r.speed or 1, 0.05)
					local dup = false
					for _, e in pairs(sw) do if e.data.id == r.id and math.abs((e.t - t0) - st) < 0.35 then dup = true break end end
					if not dup then sw[#sw + 1] = { t = t0 + st, data = { id = r.id, length = r.len } } end
				end
			end
		end
		table.sort(sw, function(a, b) return a.t < b.t end)
		for k, s in ipairs(sw) do
			local st = s.t - t0
			local nx = sw[k + 1]
			local stop = nx and (nx.t - t0) or (st + 0.8)
			local dmg, n = 0, 0
			for _, e in pairs(evs) do
				local et = e.t - t0
				if e.cat == "HIT" and e.who ~= "YOU" and (e.data.amount or 0) > 0 and et >= st and et < stop then dmg = dmg + e.data.amount n = n + 1 end
			end
			o[#o + 1] = string.format("swing %d  @%5.2fs  %s  %s%s", k, st, nx and string.format("next +%.2fs", (nx.t - s.t)) or "last      ",
				n > 0 and string.format("HIT %s", fn(dmg, 1)) or "miss", s.data.air and "  (air)" or (s.data.jump and "  (jump)" or ""))
			o[#o + 1] = "   rbxassetid://" .. tostring(s.data.id)
		end
		local inputs = 0
		for _, e in pairs(evs) do if e.cat == "INPUT" and e.data.kind ~= "up" then inputs = inputs + 1 end end
		table.insert(o, 1, string.format("%d swing(s) · %d input(s)", #sw, inputs))
		return o
	end
	function UI.refreshCombat()
		if Rec.state == "recording" and Rec.focus then
			status.Text = string.format("● %s  %.1fs", Rec.focus.label, now() - Rec.t0)
			status.TextColor3 = T.Rec
			setLines(swingLines(Rec.events, Rec.t0, true))
		elseif Rec.state == "armed" and X.focus then
			status.Text = "ARMED · " .. X.focus.label
			status.TextColor3 = T.Arm
		else
			status.Text = "COMBAT"
			status.TextColor3 = T.Text
		end
		if Rec.state ~= "recording" then
			local r = nil
			for k = #Hist, 1, -1 do if Hist[k].focus then r = Hist[k] break end end
			if r then
				local t = swingLines(r.events, r.t0 or 0, false)
				table.insert(t, 1, string.format("last: #%d %s · %.2fs", r.index, r.label or r.name, r.duration or 0))
				setLines(t)
			else
				setLines({ "nothing logged here yet" })
			end
		end
		paint()
	end
	-- after a Combat-tab recording: Guided moves on to the next
	function UI.afterCombat(rec)
		if X.queue then
			X.queue.at = X.queue.at + 1
			if X.queue.at > #MODES then
				X.queue = nil
				X.focus = nil
				if UI.nameBox then UI.nameBox.Text = "" end
				setState("idle")
				hint.Text = "Guided done - Export .txt to send them all."
				toast("guided: all done")
			else
				pick(X.queue.at)
			end
		else
			-- (the same again until you pick another or Stop)
			if X.focus and Rec.state ~= "recording" then
				if UI.nameBox then UI.nameBox.Text = X.focus.label end
				arm()
			end
		end
		pcall(UI.refreshCombat)
	end
	UI.refreshCombat()
end)

---------------------------------------------------------------------------------------------------
local fmtKey, prevBox, prevHead, rows = "moveTable", nil, nil, {}
local PAGE, pIdx, full = 16000, 1, ""
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
	local search = mk("TextBox", { Size = UDim2.new(1, -90, 0, 24), BackgroundColor3 = T.Pan, PlaceholderText = "filter",
		PlaceholderColor3 = T.Sub, Text = "", TextColor3 = T.Text, Font = F, TextSize = 11, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = head },
		{ cor(7), strk(), mk("UIPadding", { PaddingLeft = UDim.new(0, 8) }) })
	-- (3.2) the ticked moves (or all of them) as one .txt: "name:" then its compressed block, for each
	local function export()
		if #Hist == 0 then return toast("nothing to copy") end
		local pick = {}
		for _, r in pairs(Hist) do if r.sel then pick[#pick + 1] = r end end
		if #pick == 0 then pick = Hist end
		local o = {}
		for _, r in pairs(pick) do
			local ok, s = pcall(Out.moveTable, r)
			s = ok and s or "-- failed"
			o[#o + 1] = (r.label or r.name) .. ":"
			o[#o + 1] = ""
			o[#o + 1] = Self.zip(s) or s
			o[#o + 1] = ""
		end
		local txt = table.concat(o, "\n")
		local saved = false
		if typeof(writefile) == "function" then
			saved = pcall(writefile, "MoveLogger_export.txt", txt)
		end
		if typeof(setclipboard) == "function" and pcall(setclipboard, txt) then
			toast(string.format("copied %d move(s) as .txt (%dKB)%s", #pick, math.ceil(#txt / 1024), saved and " · also saved MoveLogger_export.txt" or ""))
		elseif saved then
			toast("saved MoveLogger_export.txt (" .. #pick .. " moves)")
		else
			toast("no clipboard")
		end
	end
	btn("All", { Size = UDim2.fromOffset(32, 24), TextSize = 10, Parent = head }, function()
		local any = false
		for _, r in pairs(Hist) do if not r.sel then any = true break end end
		for _, r in pairs(Hist) do r.sel = any end
		if UI.refreshMoves then UI.refreshMoves() end
	end)
	btn(".txt", { Size = UDim2.fromOffset(38, 24), TextSize = 10, BackgroundColor3 = T.Acc, Parent = head }, export)
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
		for _, r in pairs(rows) do r:Destroy() end
		table.clear(rows)
		tbtns.Moves.Text = "Moves (" .. #Hist .. ")"
		local q = string.lower(search.Text)
		local n = 0
		for i = #Hist, 1, -1 do
			local r = Hist[i]
			if q == "" or string.find(string.lower(r.label or r.name), q, 1, true) or table.find(r.victims, q) then
				n = n + 1
				local card = mk("Frame", { Size = UDim2.new(1, 0, 0, 48), BackgroundColor3 = i == Sel and T.Pan2 or T.Pan, LayoutOrder = n, Parent = list },
					{ cor(7), strk(i == Sel and T.Acc or T.Stroke) })
				-- (3.2: tick it for the .txt; tap the name to rename it)
				btn(r.sel and "☑" or "☐", { Position = UDim2.fromOffset(4, 2), Size = UDim2.fromOffset(18, 18), TextSize = 12, Parent = card }, function()
					r.sel = not r.sel
					refresh()
				end)
				lbl("#" .. r.index, { Position = UDim2.fromOffset(25, 3), Size = UDim2.fromOffset(26, 16), TextSize = 10, TextColor3 = T.Sub, Parent = card })
				local nameBox = mk("TextBox", { Position = UDim2.fromOffset(52, 2), Size = UDim2.new(1, -58, 0, 18), BackgroundColor3 = T.Pan2,
					Text = r.label or r.name, TextColor3 = T.Text, Font = FB, TextSize = 11, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
					TextTruncate = Enum.TextTruncate.AtEnd, Parent = card }, { cor(4), mk("UIPadding", { PaddingLeft = UDim.new(0, 4) }) })
				nameBox.FocusLost:Connect(g(function()
					local t = string.gsub(nameBox.Text, "^%s+", "")
					t = string.gsub(t, "%s+$", "")
					r.label = t ~= "" and t or nil
					nameBox.Text = r.label or r.name
				end))
				lbl(string.format("%ss · %d events · %d victim(s)", fn(r.duration, 2), #r.events, #r.victims), { Position = UDim2.fromOffset(7, 19),
					Size = UDim2.new(1, -14, 0, 12), TextSize = 9, TextColor3 = T.Sub, Parent = card })
				local br = mk("Frame", { Position = UDim2.fromOffset(7, 32), Size = UDim2.new(1, -14, 0, 14), BackgroundTransparency = 1, Parent = card }, { hl(3) })
				local o = 0
				for _, f in { { "Table", "moveTable" }, { "Combat", "combat" }, { "Replay", "replay" }, { "Summ", "summary" }, { "Time", "timeline" } } do
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
	tg("Combo", "M1 / combo breakdown (each swing, dashes)")
	tg("Inputs", "Log your keys / clicks / taps / buttons")
	tg("Weapons", "Detect + log weapons (joint, swing path, builder)")
	tg("Changes", "Log every change to effects (tweens frame by frame)")
	tg("StartOnAnim", "Start on your next action animation")
	tg("StartOnRemote", "Start on a server event about you")
	tg("StartOnFx", "Start on an effect-module call for you (Hero)")
	tg("Hooks", "Hook Tween/Emit calls (executor only, reload to apply)")
	tg("Templates", "Dump + clone effect asset folders")
	tg("Zip", "Always compress copies (zstd + base64); big ones always are")
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
	num("ComboGap", "M1 chain: max gap between swings (s)", 0.3, 5)
	num("ChangeLife", "Effect changes: watch each for (s)", 1, 60)
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
	elseif n == "Record" and UI.refreshRecord then UI.refreshRecord()
	elseif n == "Combat" and UI.refreshCombat then pcall(UI.refreshCombat) end
end
Hooks.onEvent = function(ev) if UI.feed then UI.feed(ev) end end
Hooks.onState = function()
	if UI.refreshRecord then UI.refreshRecord() end
	if UI.refreshCombat then pcall(UI.refreshCombat) end
end
Hooks.onFinish = function(rec)
	UI.refreshAll()
	if rec and rec.focus then
		-- (3.13: a Combat-tab recording: stay on that tab; Guided goes on to the next one)
		toast((rec.label or "combat") .. " saved (#" .. Sel .. ")")
		if UI.afterCombat then pcall(UI.afterCombat, rec) end
		return
	end
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
	pcall(X.wireInputs)
	cn(workspace.ChildAdded:Connect(g(function(c) pcall(X.onTop, c) end)))
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
		for _, d in pairs(r:GetDescendants()) do
			if d:IsA("RemoteEvent") or d.ClassName == "UnreliableRemoteEvent" then hookRem(d) end
		end
		cn(r.DescendantAdded:Connect(g(function(d)
			if d:IsA("RemoteEvent") or d.ClassName == "UnreliableRemoteEvent" then hookRem(d) end
		end)))
	end
	task.spawn(g(function() pcall(tree, REP) end))
	cn(LP.CharacterAdded:Connect(g(function(c) task.defer(g(trackChar), c) end)))
	if LP.Character then task.defer(g(trackChar), LP.Character) end
	for _, p in pairs(P:GetPlayers()) do
		if p ~= LP then cn(p.CharacterAdded:Connect(g(function(c) task.defer(g(trackChar), c) end))) end
	end
	cn(P.PlayerAdded:Connect(g(function(p) cn(p.CharacterAdded:Connect(g(function(c) task.defer(g(trackChar), c) end))) end)))
	cn(RS.Heartbeat:Connect(g(hb)))
	pcall(function() RS:UnbindFromRenderStep("MLCam2") end)
	RS:BindToRenderStep("MLCam2", Enum.RenderPriority.Last.Value, g(camStep))
	task.spawn(g(function()
		while GENV.__MoveLogger == Self do
			task.wait(0.25)
			if Rec.state == "recording" then
				UI.refreshRecord()
				if UI.refreshCombat then pcall(UI.refreshCombat) end
			end
		end
	end))
end)

print("[MoveLogger] v3.13 loaded")
end
__MLUI()

end
print("[MoveLogger] loading…")
local __ok, __err = xpcall(function()  local __pf = function(t, k, f) if t[k] == nil then pcall(function() t[k] = f end) end end __pf(math, "round", function(x) return x >= 0 and math.floor(x + 0.5) or math.ceil(x - 0.5) end) __pf(math, "clamp", function(x, a, b) return math.max(a, math.min(b, x)) end) __pf(table, "unpack", unpack) __pf(table, "pack", function(...) return { n = select("#", ...), ... } end) __pf(table, "clear", function(t) for k in pairs(t) do t[k] = nil end end) __pf(table, "find", function(t, v) for i = 1, #t do if t[i] == v then return i end end return nil end)  return __ML_MAIN() end, function(e)
	return tostring(e) .. "\n" .. ((debug and debug.traceback) and debug.traceback() or "")
end)
if __ok then
	print("[MoveLogger] ready (F8 shows / hides)")
else
	warn("[MoveLogger] failed to start: " .. tostring(__err))
	pcall(function()
		local lp = game:GetService("Players").LocalPlayer
		if not lp then warn("[MoveLogger] needs to run on the client: there is no LocalPlayer here") return end
		local gui = Instance.new("ScreenGui")
		gui.Name = "MoveLoggerError"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 10001
		local box = Instance.new("TextBox")
		box.Size = UDim2.new(0.9, 0, 0, 180)
		box.Position = UDim2.new(0.05, 0, 0, 60)
		box.BackgroundColor3 = Color3.fromRGB(40, 12, 16)
		box.TextColor3 = Color3.fromRGB(255, 200, 200)
		box.TextSize = 13
		box.TextWrapped = true
		box.MultiLine = true
		box.ClearTextOnFocus = false
		box.TextXAlignment = Enum.TextXAlignment.Left
		box.TextYAlignment = Enum.TextYAlignment.Top
		box.Text = "MoveLogger failed to start (screenshot / copy this):\n" .. tostring(__err)
		box.Parent = gui
		gui.Parent = lp:WaitForChild("PlayerGui")
	end)
end
