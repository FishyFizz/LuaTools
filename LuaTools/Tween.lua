local Deep = require "LuaTools.Deep"

local Tween = {} ---@class FishyLibs_Tween

function Tween.Lerp(a, b, ratio)
    ratio = math.clamp(ratio, 0, 1)
    return (ratio * b) + ((1-ratio) * a)
end

function Tween.Exp(a, b, exp, ratio)
    local r = (ratio ^ exp)
    return Tween.Lerp(a, b, r)
end

function Tween.EaseOut(a, b, ratio)
    local r = 1 - math.exp(-6 * ratio)
    return Tween.Lerp(a, b, r)
end

function Tween.EaseIn(a, b, ratio)
    local r = math.exp(6 * (ratio - 1))
    return Tween.Lerp(a, b, r)
end

---Takes an interpolateFunc that interpolate between numbers
---Returns an interpolateFunc that interpolate between tables that contain multiple numbers
---@param interpolateFunc fun(a:number, b:number, ratio:number):number
---@return fun(a:table, b:table, ratio:number):table
function Tween.ToMultiInterpolateFunc(interpolateFunc)
    return function(a, b, ratio)
        local result = Deep.DeepCopy(a, 1)
        for k in pairs(result) do
            if type(result[k]) == "number" and type(b[k]) == "number" then
                result[k] = interpolateFunc(result[k], b[k], ratio)
            end
        end
        return result
    end
end

---@param proceduralAnim ProceduralAnimObject
function Tween.StartProceduralAnim(proceduralAnim)

    ---@class ProceduralAnimTicker
    local obj = {
        animObj = proceduralAnim,
        t = 0,
        frames = 0,
        callbackCalled = false,
    }

    function obj:Update(dt)
        self.t = self.t + dt
        self.frames = self.frames + 1
        if self.frames % 3 == 0 then
            LogUtil.LogInfo("[ProcedualAnim]: t = ", self.t, " frames = ", self.frames)
        end
        self.animObj.updateFunc(self.t)
        if self.t >= self.animObj.length then
            LogUtil.LogInfo("[ProcedualAnim] STOPPED", self.t)
            LuaTickController:Get():RemoveTick(self)
            if self.animObj.callback and (not self.callbackCalled) then
                self.callbackCalled = true
                self.animObj.callback()
            end
        end
    end

    function obj:Terminate()
        LuaTickController:Get():RemoveTick(self)
        if self.animObj.callback and (not self.callbackCalled) then
            self.callbackCalled = true
            self.animObj.callback()
        end
    end

    LuaTickController:Get():RegisterTick(obj)
    return obj
end

function Tween.CreateProceduralAnim(startParam, endParam, lengthSec, interpolateFunc, paramUpdateFunc, callback)

    ---@class ProceduralAnimObject
    local obj = {
        length = lengthSec,
        updateFunc = function(t)
            local param
            if t <= 0 then param = startParam end
            if t >= lengthSec then param = endParam end
            pcall(paramUpdateFunc, interpolateFunc(startParam, endParam, t/lengthSec))
        end,

        callback = callback,

        Start = function(self)
            return Tween.StartProceduralAnim(self)
        end
    }

    return obj
end

--WORK IN PROGRESS, DO NO USE
----------------------------------------------------------------------------------------------------------
--#region Tween.Timeline

---@class ProceduralAnimTimeline
Tween.Timeline = {}

function Tween.Timeline.New()
    local obj = {}
    setmetatable(obj, {__index=Tween.Timeline})
    obj:Init()
    return obj
end

---@class TweenKeyFrame
---@field time              number
---@field paramValue        any
---@field interpolateFunc   nil|fun(a:any, b:any, ratio:number):any

---@class TweenAnimTrack
---@field setter    fun(value:any)
---@field keyFrames TweenKeyFrame[]

function Tween.Timeline:Init()
    ---@type table<string, TweenAnimTrack>
    self.tracks = {}

    ---@type TweenKeyFrame[]
    self.eventTrack = {}

    self.length = 0
end

---@param paramName         string
---@param paramSetter       fun(value:any)
function Tween.Timeline:AddParam(paramName, paramSetter)
    self.tracks[paramName] = {
        setter = paramSetter,
        keyFrames = {}
    }
end

---@param keyFrames TweenKeyFrame[]
function Tween.Timeline:FindInsertPos(keyFrames, t)
    local prevTime = -1

    for _idx, keyFrame in ipairs(keyFrames) do
        if keyFrame.time > t then
            return _idx
        end
    end

    -- keyFrames[] is empty
    return 1
end

---@param keyFrames TweenKeyFrame[]
function Tween.Timeline:FindFrameIndex(keyFrames, t)
    for idx, keyFrame in ipairs(keyFrames) do
        if keyFrame.time == t then
            return idx
        end
    end
end

function Tween.Timeline:AddEvent(t, callback)
    local insertPos = self:FindInsertPos(self.eventTrack, t)
    local frame = {
        time = t,
        paramValue = callback,
        interpolateFunc = nil,
    }
    table.insert(self.eventTrack, insertPos, frame)

    if self.length < t then self.length = t end
    return self
end

function Tween.Timeline:AddParamKey(paramName, t, value, interpolateFunc)
    if not self.tracks[paramName] then return end

    ---@type TweenKeyFrame
    local frame = {
        time = t,
        paramValue = value,
        interpolateFunc = interpolateFunc,
    }

    local replacePos = self:FindFrameIndex(self.tracks[paramName].keyFrames, t)
    if replacePos then
        self.tracks[paramName].keyFrames[replacePos] = frame
    else 
        local insertPos = self:FindInsertPos(self.tracks[paramName].keyFrames, t)
        table.insert(self.tracks[paramName].keyFrames, insertPos, frame)
    end

    if self.length < t then self.length = t end
    return self
end

function Tween.Timeline:Play()
    --TODO
end

--#endregion
----------------------------------------------------------------------------------------------------------


return Tween