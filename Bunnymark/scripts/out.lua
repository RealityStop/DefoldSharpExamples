CSharpLuaSingleFile = true

-- CoreSystemLib: Core.lua
do
--[[
Copyright 2017 YANG Huan (sy.yanghuan@gmail.com).

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
--]]

local setmetatable = setmetatable
local getmetatable = getmetatable
local type = type
local pairs  = pairs
local assert = assert
local table = table
local tremove = table.remove
local tconcat = table.concat
local floor = math.floor
local ceil = math.ceil
local error = error
local select = select
local xpcall = xpcall
local rawget = rawget
local rawset = rawset
local rawequal = rawequal
local tostring = tostring
local string = string
local sfind = string.find
local ssub = string.sub
local debug = debug
local next = next
local global = _G
local prevSystem = rawget(global, "System")

local emptyFn = function() end
local nilFn = function() return nil end
local falseFn = function() return false end
local trueFn = function() return true end
local identityFn = function(x) return x end
local lengthFn = function (t) return #t end
local zeroFn = function() return 0 end
local oneFn = function() return 1 end
local equals = function(x, y) return x == y end
local getCurrent = function(t) return t.current end
local assembly, metadatas
local System, Object, ValueType

local function new(cls, ...)
  local this = setmetatable({}, cls)
  return this, cls.__ctor__(this, ...)
end

local function throw(e, lv)
  if e == nil then e = System.NullReferenceException() end
  e:traceback(lv)
  error(e)
end

local function xpcallErr(e)
  if e == nil then
    e = System.Exception("script error")
    e:traceback()
  elseif type(e) == "string" then
    if sfind(e, "attempt to index") then
      e = System.NullReferenceException(e)
    elseif sfind(e, "attempt to divide by zero") then  
      e = System.DivideByZeroException(e)
    else
      e = System.Exception(e)
    end
    e:traceback()
  end
  return e
end

local function try(try, catch, finally)
  local ok, status, result = xpcall(try, xpcallErr)
  if not ok then
    if catch then
      if finally then
        ok, status, result = xpcall(catch, xpcallErr, status)
      else
        ok, status, result = true, catch(status)
      end
      if ok then
        if status == 1 then
          ok = false
          status = result
        end
      end
    end
  end
  if finally then
    finally()
  end
  if not ok then
    error(status)
  end
  return status, result
end

local function set(className, cls)
  local scope = global
  local starIndex = 1
  while true do
    local pos = sfind(className, "[%.+]", starIndex) or 0
    local name = ssub(className, starIndex, pos -1)
    if pos ~= 0 then
      local t = rawget(scope, name)
      if t == nil then
        if cls then
          t = {}
          rawset(scope, name, t)
        else
          return nil
        end
      end
      scope = t
      starIndex = pos + 1
    else
      if cls then
        assert(rawget(scope, name) == nil, className)
        rawset(scope, name, cls)
        return cls
      else
        return rawget(scope, name)
      end
    end
  end
end

local function multiKey(t, f, ...)
  local n, i, k = select("#", ...), 1
  while true do
    local arg = assert(select(i, ...))
    if f then
      k = f(arg)
    else
      k = arg
    end
    if i == n then
      break
    end
    local tk = t[k]
    if tk == nil then
      tk = {}
      t[k] = tk
    end
    t = tk
    i = i + 1
  end
  return t, k
end

local function genericName(name, ...)
  local n = select("#", ...)
  local t = { name, "`", n, "[" }
  local count = 5
  local hascomma
  for i = 1, n do
    local cls = select(i, ...)
    if hascomma then
      t[count] = ","
      count = count + 1
    else
      hascomma = true
    end
    t[count] = cls.__name__
    count = count + 1
  end
  t[count] = "]"
  return tconcat(t)
end

local enumMetatable = { class = "E", default = zeroFn, __index = false, interface = false, __call = function (_, v) return v or 0 end }
enumMetatable.__index = enumMetatable

local interfaceMetatable = { class = "I", default = nilFn, __index = false }
interfaceMetatable.__index = interfaceMetatable

local ctorMetatable = { __call = function (ctor, ...) return ctor[1](...) end }

local function applyExtends(cls)
  local extends = cls.base
  if extends then
    if type(extends) == "function" then
      extends = extends(global, cls)
    end
    cls.base = nil
  end
  return extends
end

local function applyMetadata(cls)
  local metadata = cls.__metadata__
  if metadata then
    if metadatas then
      metadatas[#metadatas + 1] = function (global)
        cls.__metadata__ = metadata(global)
      end
    else
      cls.__metadata__ = metadata(global)
    end
  end
end

local function setBase(cls, kind)
  local ctor = cls.__ctor__
  if ctor and type(ctor) == "table" then
    setmetatable(ctor, ctorMetatable)
  end
  local extends = applyExtends(cls)
  applyMetadata(cls)

  cls.__index = cls 
  cls.__call = new
  
  local object = kind ~= "S" and Object or ValueType
  if extends then
    local base = extends[1]
    if not base then error(cls.__name__ .. "'s base is nil") end
    if base.class == "I" then
      cls.interface = extends
      setmetatable(cls, object)
    else
      setmetatable(cls, base)
      if #extends > 1 then
        tremove(extends, 1)
        cls.interface = extends
      end
    end
  else
    setmetatable(cls, object)
  end
end

local function staticCtorSetBase(cls)
  setmetatable(cls, nil)
  local t = cls[cls]
  for k, v in pairs(t) do
    cls[k] = v
  end
  cls[cls] = nil
  local kind = cls.class
  cls.class = nil
  setBase(cls, kind)
  cls:static()
  cls.static = nil
end

local staticCtorMetatable = {
  __index = function(cls, key)
    staticCtorSetBase(cls)
    return cls[key]
  end,
  __newindex = function(cls, key, value)
    staticCtorSetBase(cls)
    cls[key] = value
  end,
  __call = function(cls, ...)
    staticCtorSetBase(cls)
    return new(cls, ...)
  end
}

local function setHasStaticCtor(cls, kind)
  local name = cls.__name__
  cls.__name__ = nil
  local t = {}
  for k, v in pairs(cls) do
    t[k] = v
    cls[k] = nil
  end
  cls[cls] = t
  cls.__name__ = name
  cls.class = kind
  cls.__call = new
  cls.__index = cls
  setmetatable(cls, staticCtorMetatable)
end

local function defCore(name, kind, cls, generic)
  cls = cls or {}
  cls.__name__ = name
  cls.__assembly__ = assembly
  if not generic then
    set(name, cls)
  end
  if kind == "C" or kind == "S" then
    if cls.static == nil then
      setBase(cls, kind)
    else
      setHasStaticCtor(cls, kind)
    end
  elseif kind == "I" then
    local extends = applyExtends(cls)
    if extends then 
      cls.interface = extends 
    end
    applyMetadata(cls)
    setmetatable(cls, interfaceMetatable)
  elseif kind == "E" then
    applyMetadata(cls)
    setmetatable(cls, enumMetatable)
  else
    assert(false, kind)
  end
  return cls
end

local genericClassKey = {}
local function getGenericClass(cls)
  return cls[genericClassKey]
end

local function getDefGenericClass(name, kind, generic, genericArgumentCount)
  local genericClass, genericBaseName
  if generic then
    generic.__index = generic
    generic.__call = new
    genericClass = generic
  else
    genericClass = {}
  end
  genericClass[genericClassKey] = genericClass
  if kind == 'I' then
    genericClass.class = 'I'
  end
  local _, i = name:find('.*_')
  if i then
    genericBaseName = name:sub(1, i - 1)
    genericArgumentCount = name:sub(i + 1, i + 1)
  else
    genericBaseName = name
    if not genericArgumentCount then error(name .. ' has not pass genericArgumentCount') end
  end
  genericClass.__name__ = genericBaseName .. '`' .. genericArgumentCount
  return genericClass, genericBaseName
end

local function defGeneric(name, kind, cls, generic, ...)
  local genericClass, genericBaseName = getDefGenericClass(name, kind, generic, ...)
  local mt = {}
  local fn = function(_, ...)
    local gt, gk = multiKey(mt, nil, ...)
    local t = gt[gk]
    if t == nil then
      local class, super  = cls(...)
      t = class or {}
      t[genericClassKey] = genericClass
      defCore(genericName(genericBaseName, ...), kind, t, true)
      if generic then
        setmetatable(t, super or generic)
      end
      gt[gk] = t
    end
    return t
  end

  local base = kind ~= "S" and Object or ValueType
  local caller = setmetatable({ __call = fn, __index = base }, base)
  return set(name, setmetatable(genericClass, caller))
end

local function def(name, kind, cls, ...)
  if type(cls) == "function" then
    return defGeneric(name, kind, cls, ...)
  else
    return defCore(name, kind, cls, ...)
  end
end

local function defCls(name, cls, ...)
  return def(name, "C", cls, ...)
end

local function defInf(name, cls, ...)
  return def(name, "I", cls, ...)
end

local function defStc(name, cls, ...)
  return def(name, "S", cls, ...)
end

local function defEnum(name, cls)
  return def(name, "E", cls)
end

local function defArray(name, cls, Array, MultiArray)
  Array.__index = Array
  MultiArray.__index =  MultiArray
  setmetatable(MultiArray, Array)

  local mt = {}
  local function create(Array, T)
    local ArrayT = mt[T]
    if ArrayT == nil then
      ArrayT = defCore(T.__name__ .. "[]", "C", cls(T), true)
      setmetatable(ArrayT, Array)
      mt[T] = ArrayT
    end
    return ArrayT
  end

  local mtMulti = {}
  local function createMulti(MultiArray, T, dimension)
    local gt, gk = multiKey(mtMulti, nil, T, dimension)
    local ArrayT = gt[gk]
    if ArrayT == nil then
      local name = T.__name__ .. "[" .. (","):rep(dimension - 1) .. "]"
      ArrayT = defCore(name, "C", cls(T), true)
      setmetatable(ArrayT, MultiArray)
      gt[gk] = ArrayT
    end
    return ArrayT
  end

  return set(name, setmetatable(Array, {
    __index = Object,
    __call = function (Array, T, dimension)
      if not dimension then
        return create(Array, T)
      else
        return createMulti(MultiArray, T, dimension)
      end
    end
  }))
end

local function trunc(num)
  return num > 0 and floor(num) or ceil(num)
end

local function when(f, ...)
  local ok, r = pcall(f, ...)
  return ok and r
end

System = {
  emptyFn = emptyFn,
  falseFn = falseFn,
  trueFn = trueFn,
  identityFn = identityFn,
  lengthFn = lengthFn,
  zeroFn = zeroFn,
  oneFn = oneFn,
  equals = equals,
  getCurrent = getCurrent,
  try = try,
  when = when,
  throw = throw,
  getClass = set,
  multiKey = multiKey,
  getGenericClass = getGenericClass,
  define = defCls,
  defInf = defInf,
  defStc = defStc,
  defEnum = defEnum,
  defArray = defArray,
  enumMetatable = enumMetatable,
  trunc = trunc,
  global = global
}
if prevSystem then
  setmetatable(System, { __index = prevSystem })
end
global.System = System

local debugsetmetatable = debug and debug.setmetatable
System.debugsetmetatable = debugsetmetatable

local _, _, version = sfind(_VERSION, "^Lua (.*)$")
version = tonumber(version)
System.luaVersion = version

if version < 5.3 then
  local bnot, band, bor, xor, sl, sr
  local bit = rawget(global, "bit")
  if not bit then
    local ok, b = pcall(require, "bit")
    if ok then
      bit = b
    end
  end
  if bit then
    bnot, band, bor, xor, sl, sr = bit.bnot, bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
  else
    local function disable()
      throw(System.NotSupportedException("bit operation is not enabled."))
    end
    bnot, band, bor, xor, sl, sr  = disable, disable, disable, disable, disable, disable
  end

  System.bnot = bnot
  System.band = band
  System.bor = bor
  System.xor = xor
  System.sl = sl
  System.sr = sr

  function System.div(x, y) 
    if y == 0 then throw(System.DivideByZeroException(), 1) end
    return trunc(x / y)
  end

  function System.mod(x, y)
    if y == 0 then throw(System.DivideByZeroException(), 1) end
    local v = x % y
    if v ~= 0 and x * y < 0 then
      return v - y
    end
    return v
  end
  
  function System.modf(x, y)
    local v = x % y
    if v ~= 0 and x * y < 0 then
      return v - y
    end
    return v
  end

  function System.toUInt(v, max, mask, checked)
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return band(v, mask)
  end

  function System.ToUInt(v, max, mask, checked)
    v = trunc(v)
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return band(v, mask)
  end

  local function toInt(v, mask, umask)
    v = band(v, mask)
    local uv = band(v, umask)
    if uv ~= v then
      v = xor(uv - 1, umask)
      if uv ~= 0 then
        v = -v
      end
    end
    return v
  end

  function System.toInt(v, min, max, mask, umask, checked)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return toInt(v, mask, umask)
  end

  function System.ToInt(v, min, max, mask, umask, checked)
    v = trunc(v)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return toInt(v, mask, umask)
  end

  local function toUInt32(v)
    if v <= -2251799813685248 or v >= 2251799813685248 then  -- 2 ^ 51, Lua BitOp used 51 and 52
      throw(System.InvalidCastException()) 
    end
    v = band(v, 0xffffffff)
    local uv = band(v, 0x7fffffff)
    if uv ~= v then
      return uv + 0x80000000
    end
    return v
  end

  function System.toUInt32(v, checked)
    if v >= 0 and v <= 4294967295 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return toUInt32(v)
  end

  function System.ToUInt32(v, checked)
    v = trunc(v)
    if v >= 0 and v <= 4294967295 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return toUInt32(v)
  end

  function System.toInt32(v, checked)
    if v >= -2147483648 and v <= 2147483647 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v <= -2251799813685248 or v >= 2251799813685248 then  -- 2 ^ 51, Lua BitOp used 51 and 52
      throw(System.InvalidCastException()) 
    end
    return band(v, 0xffffffff)
  end

  function System.toInt64(v, checked) 
    if v >= (-9223372036854775807 - 1) and v <= 9223372036854775807 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    throw(System.InvalidCastException()) -- 2 ^ 51, Lua BitOp used 51 and 52
  end

  function System.toUInt64(v, checked)
    if v >= 0 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v >= -2147483648 then
      return band(v, 0x7fffffff) + 0xffffffff80000000
    end
    throw(System.InvalidCastException()) 
  end

  function System.ToUInt64(v, checked)
    v = trunc(v)
    if v >= 0 and v <= 18446744073709551615 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    if v >= -2147483648 and v <= 2147483647 then
      v = band(v, 0xffffffff)
      local uv = band(v, 0x7fffffff)
      if uv ~= v then
        return uv + 0xffffffff80000000
      end
      return v
    end
    throw(System.InvalidCastException()) 
  end

  if table.pack == nil then
    table.pack = function(...)
      return { n = select("#", ...), ... }
    end
  end

  if table.unpack == nil then
    table.unpack = assert(unpack)
  end

  if table.move == nil then
    table.move = function(a1, f, e, t, a2)
      if a2 == nil then a2 = a1 end
      if t > f then
        t = e - f + t
        while e >= f do
          a2[t] = a1[e]
          t = t - 1
          e = e - 1
        end
      else
        while f <= e do
          a2[t] = a1[f]
          t = t + 1
          f = f + 1
        end
      end
    end
  end
else
  load[[
  local System = System
  local throw = System.throw
  local trunc = System.trunc
  
  function System.bnot(x) return ~x end 
  function System.band(x, y) return x & y end
  function System.bor(x, y) return x | y end
  function System.xor(x, y) return x ~ y end
  function System.sl(x, y) return x << y end
  function System.sr(x, y) return x >> y end
  function System.div(x, y) if x ~ y < 0 then return -(-x // y) end return x // y end

  function System.mod(x, y)
    local v = x % y
    if v ~= 0 and 1.0 * x * y < 0 then
      return v - y
    end
    return v
  end

  local function toUInt(v, max, mask, checked)  
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 2) 
    end
    return v & mask
  end
  System.toUInt = toUInt

  function System.ToUInt(v, max, mask, checked)
    v = trunc(v)
    if v >= 0 and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 2) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return v & mask
  end
  
  local function toSingedInt(v, mask, umask)
    v = v & mask
    local uv = v & umask
    if uv ~= v then
      v = (uv - 1) ~ umask
      if uv ~= 0 then
        v = -v
      end
    end
    return v
  end
  
  local function toInt(v, min, max, mask, umask, checked)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 2) 
    end
    return toSingedInt(v, mask, umask)
  end
  System.toInt = toInt
  
  function System.ToInt(v, min, max, mask, umask, checked)
    v = trunc(v)
    if v >= min and v <= max then
      return v
    end
    if checked then
      throw(System.OverflowException(), 2) 
    end
    if v < -2147483648 or v > 2147483647 then
      return 0
    end
    return toSingedInt(v, mask, umask)
  end

  function System.toUInt32(v, checked)
    return toUInt(v, 4294967295, 0xffffffff, checked)
  end
  
  function System.ToUInt32(v, checked)
    v = trunc(v)
    if v >= 0 and v <= 4294967295 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return v & 0xffffffff
  end
  
  function System.toInt32(v, checked)
    return toInt(v, -2147483648, 2147483647, 0xffffffff, 0x7fffffff, checked)
  end

  function System.toInt64(v, checked)
    return toInt(v, (-9223372036854775807 - 1), 9223372036854775807, 0xffffffffffffffff, 0x7fffffffffffffff, checked)
  end

  function System.toUInt64(v, checked)
    if v >= 0 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    return (v & 0x7fffffffffffffff) + 0x8000000000000000
  end

  function System.ToUInt64(v, checked)
    v = trunc(v)
    if v >= 0 and v <= 18446744073709551615 then
      return v
    end
    if checked then
      throw(System.OverflowException(), 1) 
    end
    v = v & 0xffffffffffffffff
    local uv = v & 0x7fffffffffffffff
    if uv ~= v then
      return uv + 0x8000000000000000
    end
    return v
  end

  ]]()
end

local toUInt = System.toUInt
local toInt = System.toInt
local ToUInt = System.ToUInt
local ToInt = System.ToInt

function System.toByte(v, checked)
  return toUInt(v, 255, 0xff, checked)
end

function System.toSByte(v, checked)
  return toInt(v, -128, 127, 0xff, 0x7f, checked)
end

function System.toInt16(v, checked)
  return toInt(v, -32768, 32767, 0xffff, 0x7fff, checked)
end

function System.toUInt16(v, checked)
  return toUInt(v, 65535, 0xffff, checked)
end

function System.ToByte(v, checked)
  return ToUInt(v, 255, 0xff, checked)
end

function System.ToSByte(v, checked)
  return ToInt(v, -128, 127, 0xff, 0x7f, checked)
end

function System.ToInt16(v, checked)
  return ToInt(v, -32768, 32767, 0xffff, 0x7fff, checked)
end

function System.ToUInt16(v, checked)
  return ToUInt(v, 65535, 0xffff, checked)
end

function System.ToInt32(v, checked)
  v = trunc(v)
  if v >= -2147483648 and v <= 2147483647 then
    return v
  end
  if checked then
    throw(System.OverflowException(), 1) 
  end
  return -2147483648
end

function System.ToInt64(v, checked)
  v = trunc(v)
  if v >= (-9223372036854775807 - 1) and v <= 9223372036854775807 then
    return v
  end
  if checked then
    throw(System.OverflowException(), 1) 
  end
  return (-9223372036854775807 - 1)
end

function System.ToSingle(v, checked)
  if v >= -3.40282347E+38 and v <= 3.40282347E+38 then
    return v
  end
  if checked then
    throw(System.OverflowException(), 1) 
  end
  if v > 0 then
    return 1 / 0 
  else
    return -1 / 0
  end
end

function System.using(t, f)
  local dispose = t and t.Dispose
  if dispose ~= nil then
    local ok, status, ret = xpcall(f, xpcallErr, t)   
    dispose(t)
    if not ok then
      error(status)
    end
    return status, ret
  else
    return f(t)    
  end
end

function System.usingX(f, ...)
  local ok, status, ret = xpcall(f, xpcallErr, ...)
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    if t ~= nil then
      local dispose = t.Dispose
      if dispose ~= nil then
        dispose(t)
      end
    end
  end
  if not ok then
    error(status)
  end
  return status, ret
end

function System.apply(t, f)
  f(t)
  return t
end

function System.default(T)
  return T:default()
end

function System.property(name, onlyget)
  local function g(this)
    return this[name]
  end
  if onlyget then
    return g
  end
  local function s(this, v)
    this[name] = v
  end
  return g, s
end

function System.new(cls, index, ...)
  local this = setmetatable({}, cls)
  return this, cls.__ctor__[index](this, ...)
end

function System.base(this)
  return getmetatable(getmetatable(this))
end

local equalsObj, compareObj, toString
if debugsetmetatable then
  equalsObj = function (x, y)
    if x == y then
      return true
    end
    if x == nil or y == nil then
      return false
    end
    local ix = x.EqualsObj
    if ix ~= nil then
      return ix(x, y)
    end
    local iy = y.EqualsObj
    if iy ~= nil then
      return iy(y, x)
    end
    return false
  end

  compareObj = function (a, b)
    if a == b then return 0 end
    if a == nil then return -1 end
    if b == nil then return 1 end
    local ia = a.CompareToObj
    if ia ~= nil then
      return ia(a, b)
    end
    local ib = b.CompareToObj
    if ib ~= nil then
      return -ib(b, a)
    end
    throw(System.ArgumentException("Argument_ImplementIComparable"))
  end

  toString = function (t, f, a)
    local s = t ~= nil and t:ToString(f) or ""
    if a then
      return ("%" .. a .. "s"):format(s)
    end
    return s
  end

  debugsetmetatable(nil, {
    __concat = function(a, b)
      if a == nil then
        if b == nil then
          return ""
        else
          return b
        end
      else
        return a
      end
    end,
    __add = function (a, b)
      if a == nil then
        if b == nil or type(b) == "number" then
          return nil
        end
        return b
      end
      return nil
    end,
    __sub = nilFn,
    __mul = nilFn,
    __div = nilFn,
    __mod = nilFn,
    __unm = nilFn,
    __lt = falseFn,
    __le = falseFn,

    -- lua 5.3
    __idiv = nilFn,
    __band = nilFn,
    __bor = nilFn,
    __bxor = nilFn,
    __bnot = nilFn,
    __shl = nilFn,
    __shr = nilFn,
  })
else
  equalsObj = function (x, y)
    if x == y then
      return true
    end
    if x == nil or y == nil then
      return false
    end
    local t = type(x)
    if t == "table" then
      local ix = x.EqualsObj
      if ix ~= nil then
        return ix(x, y)
      end
    elseif t == "number" then
      return System.Number.EqualsObj(x, y)
    end
    t = type(y)
    if t == "table" then
      local iy = y.EqualsObj
      if iy ~= nil then
        return iy(y, x)
      end
    end
    return false
  end

  compareObj = function (a, b)
    if a == b then return 0 end
    if a == nil then return -1 end
    if b == nil then return 1 end
    local t = type(a)
    if t == "number" then
      return System.Number.CompareToObj(a, b)
    elseif t == "boolean" then
      return System.Boolean.CompareToObj(a, b)
    else
      local ia = a.CompareToObj
      if ia ~= nil then
        return ia(a, b)
      end
    end
    t = type(b)
    if t == "number" then
      return -System.Number.CompareToObj(b, a)
    elseif t == "boolean" then
      return -System.Boolean.CompareToObj(a, b)
    else
      local ib = b.CompareToObj
      if ib ~= nil then
        return -ib(b, a)
      end
    end
    throw(System.ArgumentException("Argument_ImplementIComparable"))
  end

  toString = function (obj, f, a)
    local s
    if obj ~= nil then
      local t = type(obj) 
      if t == "number" then
        if f then
          s = System.Number.ToString(obj, f)
        else
          s = tostring(obj)
        end
      elseif t == "table" then
        s = obj:ToString(f)
      elseif t == "boolean" then
        s = obj and "True" or "False"
      elseif t == "function" then
        s = "System.Delegate"
      else
        s = tostring(obj)
      end
    else
      s = ""
    end
    if a then
      return ("%" .. a .. "s"):format(s)
    end
    return s
  end
end

System.equalsObj = equalsObj
System.compareObj = compareObj
System.toString = toString

Object = defCls("System.Object", {
  __call = new,
  __ctor__ = emptyFn,
  default = nilFn,
  class = "C",
  EqualsObj = equals,
  ReferenceEquals = rawequal,
  GetHashCode = identityFn,
  EqualsStatic = equalsObj,
  GetType = false,
  ToString = function(this) return this.__name__ end
})
setmetatable(Object, { __call = new })

ValueType = defCls("System.ValueType", {
  class = "S",
  default = function(T) 
    return T()
  end,
  __clone__ = function(this)
    if type(this) == "table" then
      local cls = getmetatable(this)
      local t = {}
      for k, v in pairs(this) do
        if type(v) == "table" and v.class == "S" then
          t[k] = v:__clone__()
        else
          t[k] = v
        end
      end
      return setmetatable(t, cls)
    end
    return this
  end,
  __copy__ = function (this, obj)
    for k, v in pairs(obj) do
      if type(v) == "table" and v.class == "S" then
        this[k] = v:__clone__()
      else
        this[k] = v
      end
    end
    for k, v in pairs(this) do
      if v ~= nil and rawget(obj, k) == nil then
        this[k] = nil
      end
    end
  end,
  EqualsObj = function (this, obj)
    if getmetatable(this) ~= getmetatable(obj) then return false end
    for k, v in pairs(this) do
      if not equalsObj(v, obj[k]) then
        return false
      end
    end
    return true
  end,
  GetHashCode = function (this)
    throw(System.NotSupportedException(this.__name__ .. " User-defined struct not support GetHashCode"), 1)
  end
})

local AnonymousType
AnonymousType = defCls("System.AnonymousType", {
  EqualsObj = function (this, obj)
    if getmetatable(obj) ~= AnonymousType then return false end
    for k, v in pairs(this) do
      if not equalsObj(v, obj[k]) then
        return false
      end
    end
    return true
  end
})

local function anonymousTypeCreate(T, t)
  return setmetatable(t, T)
end

local anonymousTypeMetaTable = setmetatable({ __index = Object, __call = anonymousTypeCreate }, Object)
setmetatable(AnonymousType, anonymousTypeMetaTable)

local pack, unpack = table.pack, table.unpack

local function tupleDeconstruct(t) 
  return unpack(t, 1, t.n)
end

local function tupleEquals(t, other)
  for i = 1, t.n do
    if not equalsObj(t[i], other[i]) then
      return false
    end
  end
  return true
end

local function tupleEqualsObj(t, obj)
  if getmetatable(obj) ~= getmetatable(t) or t.n ~= obj.n then
    return false
  end
  return tupleEquals(t, obj)
end

local function tupleCompareTo(t, other)
  for i = 1, t.n do
    local v = compareObj(t[i], other[i])
    if v ~= 0 then
      return v
    end
  end
  return 0
end

local function tupleCompareToObj(t, obj)
  if obj == nil then return 1 end
  if getmetatable(obj) ~= getmetatable(t) or t.n ~= obj.n then
    throw(System.ArgumentException())
  end
  return tupleCompareTo(t, obj)
end

local function tupleToString(t)
  local a = { "(" }
  local count = 2
  for i = 1, t.n do
    if i ~= 1 then
      a[count] = ", "
      count = count + 1
    end
    local v = t[i]
    if v ~= nil then
      a[count] = v:ToString()
      count = count + 1
    end
  end
  a[count] = ")"
  return tconcat(a)
end

local function tupleLength(t)
  return t.n
end

local function tupleGet(t, index)
  if index < 0 or index >= t.n then
    throw(System.IndexOutOfRangeException())
  end
  return t[index + 1]
end

local function tupleGetRest(t)
  return t[8]
end

local function tupleCreate(T, ...)
  return setmetatable(pack(...), T)
end

local Tuple = defCls("System.Tuple", {
  Deconstruct = tupleDeconstruct,
  ToString = tupleToString,
  EqualsObj = tupleEqualsObj,
  CompareToObj = tupleCompareToObj,
  getLength = tupleLength,
  get = tupleGet,
  getRest = tupleGetRest
})
local tupleMetaTable = setmetatable({ __index  = Object, __call = tupleCreate }, Object)
setmetatable(Tuple, tupleMetaTable)

local ValueTuple = defStc("System.ValueTuple", {
  Deconstruct = tupleDeconstruct,
  ToString = tupleToString,
  __eq = tupleEquals,
  Equals = tupleEquals,
  EqualsObj = tupleEqualsObj,
  CompareTo = tupleCompareTo,
  CompareToObj = tupleCompareToObj,
  getLength = tupleLength,
  get = tupleGet,
  default = function ()
    throw(System.NotSupportedException("not support default(T) when T is ValueTuple"))
  end
})

local valueTupleMetaTable = setmetatable({ __index  = ValueType, __call = tupleCreate }, ValueType)
setmetatable(ValueTuple, valueTupleMetaTable)

local function recordEquals(t, other)
  if getmetatable(t) == getmetatable(other) then
    for k, v in pairs(t) do
      if not equalsObj(v, other[k]) then
        return false
      end
    end
    return true
  end
  return false
end

local function recordPrintMembers(this, builder)
  local p = pack(this.__members__())
  local n = p.n
  for i = 2, n do
    local k = p[i]
    local v = this[k]
    builder:Append(k)
    builder:Append(" = ")
    if v ~= nil then
    builder:Append(toString(v))
    end
    if i ~= n then
    builder:Append(", ")
    end
  end
  return true
end

local function recordToString(this)
  local p = pack(this.__members__())
  local n = p.n
  local t = { p[1], "{" }
  local count = 3
  for i = 2, n do
    local k = p[i]
    local v = this[k]
    t[count] = k
    t[count + 1] = "="
    if v ~= nil then
      if i ~= n then
        t[count + 2] = toString(v) .. ','
      else
        t[count + 2] = toString(v)
      end
    else
      if i ~= n then
        t[count + 2] = ','
      end
    end
    if v == nil and i == n then
      count = count + 2
    else
      count = count + 3
    end
  end
  t[count] = "}"
  return tconcat(t, ' ')
end

local function recordDeconstruct(this)
  local t = pack(this.__members__())
  for i = 2, t.n do
    t[i] = this[t[i]]
  end
  return unpack(t, 2)
end

defCls("System.RecordType", {
  __eq = recordEquals,
  __clone__ = ValueType.__clone__,
  Equals = recordEquals,
  PrintMembers = recordPrintMembers,
  ToString = recordToString,
  Deconstruct = recordDeconstruct
})

defStc("System.RecordValueType", {
  __eq = recordEquals,
  Equals = recordEquals,
  PrintMembers = recordPrintMembers,
  ToString = recordToString,
  Deconstruct = recordDeconstruct
})

local Attribute = defCls("System.Attribute")
defCls("System.FlagsAttribute", { base = { Attribute } })

local Nullable = { 
  default = nilFn,
  Value = function (this)
    if this == nil then
      throw(System.InvalidOperationException("Nullable object must have a value."))
    end
    return this
  end,
  EqualsObj = equalsObj,
  GetHashCode = function (this)
    if this == nil then
      return 0
    end
    if type(this) == "table" then
      return this:GetHashCode()
    end
    return this
  end,
  clone = function (t)
    if type(t) == "table" then
      return t:__clone__()
    end
    return t
  end
}

defStc("System.Nullable", function (T)
  return { 
    __genericT__ = T 
  }
end, Nullable, 1)

function System.isNullable(T)
  return getmetatable(T) == Nullable
end

local Index = defStc("System.Index", {
  End = -0.0,
  Start = 0,
  IsFromEnd = function (this)
    return 1 / this < 0 
  end,
  GetOffset = function (this, length)
    if 1 / this < 0 then
      return length + this
    end
    return this
  end,
  ToString = function (this)
    return ((1 / this < 0) and '^' or '') .. this
  end
})
setmetatable(Index, { 
  __call = function (value, fromEnd)
    if value < 0 then
      throw(System.ArgumentOutOfRangeException("Non-negative number required."))
    end
    if fromEnd then
      if value == 0 then
        return -0.0
      end
      return -value
    end
    return value
  end
})

local function pointerAddress(p)
  local address = p[3]
  if address == nil then
    address = ssub(tostring(p), 7)
    p[3] = address
  end
  return address + p[2]
end

local Pointer
local function newPointer(t, i)
  return setmetatable({ t, i }, Pointer)
end

Pointer = {
  __index = false,
  get = function(this)
    local t, i = this[1], this[2]
    return t[i]
  end,
  set = function(this, value)
    local t, i = this[1], this[2]
    t[i] = value
  end,
  __add = function(this, count)
    return newPointer(this[1], this[2] + count)
  end,
  __sub = function(this, count)
    return newPointer(this[1], this[2] - count)
  end,
  __lt = function(t1, t2)
    return pointerAddress(t1) < pointerAddress(t2)
  end,
  __le = function(t1, t2)
    return pointerAddress(t1) <= pointerAddress(t2)
  end
}
Pointer.__index = Pointer

function System.stackalloc(t)
  return newPointer(t, 1)
end

local modules, imports = {}, {}
function System.import(f)
  imports[#imports + 1] = f
end

local namespace
local function defIn(kind, name, f)
  local namespaceName, isClass = namespace[1], namespace[2]
  if #namespaceName > 0 then
    name = namespaceName .. (isClass and "+" or ".") .. name
  end
  assert(modules[name] == nil, name)
  namespace[1], namespace[2] = name, kind == "C" or kind == "S"
  local t = f(assembly, global)
  namespace[1], namespace[2] = namespaceName, isClass
  modules[isClass and name:gsub("+", ".") or name] = function()
    return def(name, kind, t)
  end
end

namespace = {
  "",
  false,
  __index = false,
  class = function(name, f) defIn("C", name, f) end,
  struct = function(name, f) defIn("S", name, f) end,
  interface = function(name, f) defIn("I", name, f) end,
  enum = function(name, f) defIn("E", name, f) end,
  namespace = function(name, f)
    local namespaceName = namespace[1]
    name = namespaceName .. "." .. name
    namespace[1] = name
    f(namespace)
    namespace[1] = namespaceName
  end
}
namespace.__index = namespace

function System.namespace(name, f)
  if not assembly then assembly = setmetatable({}, namespace) end
  namespace[1] = name
  f(namespace)
  namespace[1], namespace[2] = "", false
end

function System.init(t)
  local path, files = t.path, t.files
  if files then
    path = (path and #path > 0) and (path .. '.') or ""
    for i = 1, #files do
      require(path .. files[i])
    end
  end

  metadatas = {}
  local types = t.types
  if types then
    local classes = {}
    for i = 1, #types do
      local name = types[i]
      local cls = assert(modules[name], name)()
      classes[i] = cls
    end
    assembly.classes = classes
  end

  for i = 1, #imports do
    imports[i](global)
  end

  local b, e = 1, #metadatas
  while true do
    for i = b, e do
      metadatas[i](global)
    end
    local len = #metadatas
    if len == e then
      break
    end
    b, e = e + 1, len
  end

  local main = t.Main
  if main then
    assembly.entryPoint = main
    System.entryAssembly = assembly
  end

  local attributes = t.assembly
  if attributes then
    if type(attributes) == "function" then
      attributes = attributes(global)
    end
    for k, v in pairs(attributes) do
      assembly[k] = v
    end
  end

  local current = assembly
  modules, imports, assembly, metadatas = {}, {}, nil, nil
  return current
end

System.config = rawget(global, "CSharpLuaSystemConfig") or {}
local isSingleFile = rawget(global, "CSharpLuaSingleFile")
if not isSingleFile then
  return function (config)
    if config then
      System.config = config 
    end
  end
end

end

-- CoreSystemLib: Interfaces.lua
do
local System = System
local defInf = System.defInf
local emptyFn = System.emptyFn

local IComparable = defInf("System.IComparable")
local IFormattable = defInf("System.IFormattable")
local IConvertible = defInf("System.IConvertible")
defInf("System.IFormatProvider")
defInf("System.ICloneable")

defInf("System.IComparable_1", emptyFn)
defInf("System.IEquatable_1", emptyFn)

defInf("System.IPromise")
defInf("System.IDisposable")

defInf("System.IStructuralComparable")
defInf("System.IStructuralEquatable")

local IEnumerable = defInf("System.IEnumerable")
local IEnumerator = defInf("System.IEnumerator")

local ICollection = defInf("System.ICollection", {
  base = { IEnumerable }
})

defInf("System.IList", {
  base = { ICollection }
})

defInf("System.IDictionary", {
  base = { ICollection }
})

defInf("System.IEnumerator_1", function(T) 
  return {
    base = { IEnumerator }
  }
end)

local IEnumerable_1 = defInf("System.IEnumerable_1", function(T) 
  return {
    base = { IEnumerable }
  }
end)

local ICollection_1 = defInf("System.ICollection_1", function(T) 
  return { 
    base = { IEnumerable_1(T) } 
  }
end)

local IReadOnlyCollection_1 = defInf("System.IReadOnlyCollection_1", function (T)
  return { 
    base = { IEnumerable_1(T) } 
  }
end)

defInf("System.IReadOnlyList_1", function (T)
  return { 
    base = { IReadOnlyCollection_1(T) } 
  }
end)

defInf('System.IDictionary_2', function(TKey, TValue) 
  return {
    base = { ICollection_1(System.KeyValuePair(TKey, TValue)) }
  }
end)

defInf("System.IReadOnlyDictionary_2", function(TKey, TValue) 
  return {
    base = { IReadOnlyCollection_1(System.KeyValuePair(TKey, TValue)) }
  }
end)

defInf("System.IList_1", function(T) 
  return {
    base = { ICollection_1(T) }
  }
end)

defInf("System.ISet_1", function(T) 
  return {
    base = { ICollection_1(T) }
  }
end)

defInf("System.IComparer")
defInf("System.IComparer_1", emptyFn)
defInf("System.IEqualityComparer")
defInf("System.IEqualityComparer_1", emptyFn)

System.enumMetatable.interface = { IComparable, IFormattable, IConvertible }
end

-- CoreSystemLib: Exception.lua
do
local System = System
local define = System.define
local Object = System.Object
local toString = System.toString

local tconcat = table.concat
local type = type
local debug = debug
local assert = assert
local select = select

local traceback = (debug and debug.traceback) or System.config.traceback or function () return "" end
System.traceback = traceback

local resource = {
  Arg_KeyNotFound = "The given key was not present in the dictionary.",
  Arg_KeyNotFoundWithKey = "The given key '%s' was not present in the dictionary.",
  Arg_WrongType = "The value '%s' is not of type '%s' and cannot be used in this generic collection.",
  Arg_ParamName_Name = "(Parameter '%s')",
  Argument_AddingDuplicate = "An item with the same key has already been added. Key: %s",
  ArgumentOutOfRange_SmallCapacity = "capacity was less than the current size.",
  InvalidOperation_EmptyQueue = "Queue empty.",
  ArgumentOutOfRange_NeedNonNegNum = "Non-negative number required.",
}

local function getResource(t, k)
  local s = resource[k]
  assert(s, k)
  return function (...)
	local n = select("#", ...)
    local f
    if n == 0 then
      f = function () return s end
    elseif n == 1 then
      f = function (x1) return s:format(toString(x1)) end
    elseif n == 2 then
      f = function (x1, x2) return s:format(toString(x1), toString(x2)) end
    elseif n == 3 then
      f = function (x1, x2, x3) return s:format(toString(x1), toString(x2), toString(x3)) end
    else
      assert(false)
    end
    t[k] = f
    return f(...)
  end
end

System.er = setmetatable({}, { __index = getResource })

local function getMessage(this)
  return this.message or ("Exception of type '%s' was thrown."):format(this.__name__)
end

local function toString(this)
  local t = { this.__name__ }
  local count = 2
  local message, innerException, stackTrace = getMessage(this), this.innerException, this.errorStack
  t[count] = ": "
  t[count + 1] = message
  count = count + 2
  if innerException then
    t[count] = "---> "
    t[count + 1] = innerException:ToString()
    count = count + 2
  end
  if stackTrace then
    t[count] = stackTrace
  end
  return tconcat(t)
end

local function ctorOfException(this, message, innerException)
  this.message = message
  this.innerException = innerException
end

local Exception = define("System.Exception", {
  __tostring = toString,
  __ctor__ = ctorOfException,
  ToString = toString,
  getMessage = getMessage,
  getInnerException = function(this) 
    return this.innerException
  end,
  getStackTrace = function(this) 
    return this.errorStack
  end,
  getData = function (this)
    local data = this.data
    if not data then
      data = System.Dictionary(Object, Object)()
      this.data = data
    end
    return data
  end,
  traceback = function(this, lv)
    this.errorStack = traceback("", lv and lv + 3 or 3)
  end
})

local SystemException = define("System.SystemException", {
  __tostring = toString,
  base = { Exception },
  __ctor__ = function (this, message, innerException)
    ctorOfException(this, message or "System error.", innerException)
  end
})

local ArgumentException = define("System.ArgumentException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, paramName, innerException)
    if type(paramName) == "table" then
      paramName, innerException = nil, paramName
    end
    ctorOfException(this, message or "Value does not fall within the expected range.", innerException)
    this.paramName = paramName
    if paramName and #paramName > 0 then
      this.message = this.message .. " " .. resource.Arg_ParamName_Name:format(paramName)
    end
  end,
  getParamName = function(this) 
    return this.paramName
  end
})

define("System.ArgumentNullException", {
  __tostring = toString,
  base = { ArgumentException },
  __ctor__ = function(this, paramName, message, innerException) 
    ArgumentException.__ctor__(this, message or "Value cannot be null.", paramName, innerException)
  end
})

define("System.ArgumentOutOfRangeException", {
  __tostring = toString,
  base = { ArgumentException },
  __ctor__ = function(this, paramName, message, innerException, actualValue) 
    ArgumentException.__ctor__(this, message or "Specified argument was out of the range of valid values.", paramName, innerException)
    this.actualValue = actualValue
  end,
  getActualValue = function(this) 
    return this.actualValue
  end
})

define("System.IndexOutOfRangeException", {
   __tostring = toString,
   base = { SystemException },
   __ctor__ = function (this, message, innerException)
    ctorOfException(this, message or "Index was outside the bounds of the array.", innerException)
  end
})

define("System.CultureNotFoundException", {
  __tostring = toString,
  base = { ArgumentException },
  __ctor__ = function(this, paramName, invalidCultureName, message, innerException, invalidCultureId) 
    if not message then 
      message = "Culture is not supported."
      if paramName then
        message = message .. "\nParameter name = " .. paramName
      end
      if invalidCultureName then
        message = message .. "\n" .. invalidCultureName .. " is an invalid culture identifier."
      end
    end
    ArgumentException.__ctor__(this, message, paramName, innerException)
    this.invalidCultureName = invalidCultureName
    this.invalidCultureId = invalidCultureId
  end,
  getInvalidCultureName = function(this)
    return this.invalidCultureName
  end,
  getInvalidCultureId = function(this) 
    return this.invalidCultureId
  end
})

local KeyNotFoundException = define("System.Collections.Generic.KeyNotFoundException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or resource.Arg_KeyNotFound, innerException)
  end
})
System.KeyNotFoundException = KeyNotFoundException

local ArithmeticException = define("System.ArithmeticException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Overflow or underflow in the arithmetic operation.", innerException)
  end
})

define("System.DivideByZeroException", {
  __tostring = toString,
  base = { ArithmeticException },
  __ctor__ = function(this, message, innerException) 
    ArithmeticException.__ctor__(this, message or "Attempted to divide by zero.", innerException)
  end
})

define("System.OverflowException", {
  __tostring = toString,
  base = { ArithmeticException },
  __ctor__ = function(this, message, innerException) 
    ArithmeticException.__ctor__(this, message or "Arithmetic operation resulted in an overflow.", innerException)
  end
})

define("System.FormatException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Invalid format.", innerException)
  end
})

define("System.InvalidCastException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Specified cast is not valid.", innerException)
  end
})

local InvalidOperationException = define("System.InvalidOperationException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Operation is not valid due to the current state of the object.", innerException)
  end
})

define("System.NotImplementedException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "The method or operation is not implemented.", innerException)
  end
})

define("System.NotSupportedException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Specified method is not supported.", innerException)
  end
})

define("System.NullReferenceException", {
  __tostring = toString,
  base = { SystemException },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Object reference not set to an instance of an object.", innerException)
  end
})

define("System.RankException", {
  __tostring = toString,
  base = { Exception },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Attempted to operate on an array with the incorrect number of dimensions.", innerException)
  end
})

define("System.TypeLoadException", {
  __tostring = toString,
  base = { Exception },
  __ctor__ = function(this, message, innerException) 
    ctorOfException(this, message or "Failed when load type.", innerException)
  end
})

define("System.ObjectDisposedException", {
  __tostring = toString,
  base = { InvalidOperationException },
  __ctor__ = function(this, objectName, message, innerException)
    ctorOfException(this, message or "Cannot access a disposed object.", innerException)
    this.objectName = objectName
    if objectName and #objectName > 0 then
      this.message = this.message .. "\nObject name: '" .. objectName .. "'."
    end
  end
})

local function toStringOfAggregateException(this)
  local t = { toString(this) }
  local count = 2
  for i = 0, this.innerExceptions:getCount() - 1 do
    t[count] = "\n---> (Inner Exception #"
    t[count + 1] = i
    t[count + 2] = ") "
    t[count + 3] = this.innerExceptions:get(i):ToString()
    t[count + 4] = "<---\n"
    count = count + 5
  end
  return tconcat(t)
end

define("System.AggregateException", {
  ToString = toStringOfAggregateException,
  __tostring = toStringOfAggregateException,
  base = { Exception },
  __ctor__ = function (this, message, innerExceptions)
    if type(message) == "table" then
      message, innerExceptions = nil, message
    end
    Exception.__ctor__(this, message or "One or more errors occurred.")
    local ReadOnlyCollection = System.ReadOnlyCollection(Exception)
    if innerExceptions then
      if System.is(innerExceptions, Exception) then
        local list = System.List(Exception)()
        list:Add(innerExceptions)
        this.innerExceptions = ReadOnlyCollection(list)
      else
        if not System.isArrayLike(innerExceptions) then
          innerExceptions = System.Array.toArray(innerExceptions)
        end
        this.innerExceptions = ReadOnlyCollection(innerExceptions)
      end
    else
      this.innerExceptions = ReadOnlyCollection(System.Array.Empty(Exception))
    end
  end,
  getInnerExceptions = function (this)
    return this.innerExceptions
  end
})

System.SwitchExpressionException = define("System.Runtime.CompilerServices", {
  __tostring = toString,
  base = { InvalidOperationException },
  __ctor__ = function(this, message, innerException)
    ctorOfException(this, message or "Non-exhaustive switch expression failed to match its input.", innerException)
  end
})
end

-- CoreSystemLib: Math.lua
do
local System = System
local trunc = System.trunc

local math = math
local floor = math.floor
local min = math.min
local max = math.max
local abs = math.abs
local log = math.log

local function bigMul(a, b)
  return a * b
end

local function divRem(a, b)
  local remainder = a % b
  return (a - remainder) / b, remainder
end

local function round(value, digits, mode)
  local mult = 10 ^ (digits or 0)
  local i = value * mult
  if mode == 1 then
    value = trunc(i + (value >= 0 and 0.5 or -0.5))
  else
    value = trunc(i)
    if value ~= i then
      local dif = i - value
      if value >= 0 then
        if dif > 0.5 or (dif == 0.5 and value % 2 ~= 0) then
          value = value + 1  
        end
      else
        if dif < -0.5 or (dif == -0.5 and value % 2 ~= 0) then
          value = value - 1  
        end
      end
    end
  end
  return value / mult
end

local function sign(v)
  return v == 0 and 0 or (v > 0 and 1 or -1) 
end

local function IEEERemainder(x, y)
  if x ~= x then
    return x
  end
  if y ~= y then
    return y
  end
  local regularMod = System.mod(x, y)
  if regularMod ~= regularMod then
    return regularMod
  end
  if regularMod == 0 and x < 0 then
    return -0.0
  end
  local alternativeResult = regularMod - abs(y) * sign(x)
  local i, j = abs(alternativeResult), abs(regularMod)
  if i == j then
    local divisionResult = x / y
    local roundedResult = round(divisionResult)
    if abs(roundedResult) > abs(divisionResult) then
      return alternativeResult
    else
      return regularMod
    end
  end
  if i < j then
    return alternativeResult
  else
    return regularMod
  end
end

local function clamp(a, b, c)
  return min(max(a, b), c)
end

local function truncate(d)
  return trunc(d) * 1.0
end

local log10 = math.log10
if not log10 then
  log10 = function (x) return log(x, 10) end
  math.log10 = log10
end

local exp = math.exp
local cosh = math.cosh or function (x) return (exp(x) + exp(-x)) / 2.0 end
local pow = math.pow or function (x, y) return x ^ y end
local sinh = math.sinh or function (x) return (exp(x) - exp(-x)) / 2.0 end
local tanh = math.tanh or function (x) return sinh(x) / cosh(x) end

local Math = math
Math.Abs = abs
Math.Acos = math.acos
Math.Asin = math.asin
Math.Atan = math.atan
Math.Atan2 = math.atan2 or math.atan
Math.BigMul = bigMul
Math.Ceiling = math.ceil
Math.Clamp = clamp
Math.Cos = math.cos
Math.Cosh = cosh
Math.DivRem = divRem
Math.Exp = exp
Math.Floor = math.floor
Math.IEEERemainder = IEEERemainder
Math.Log = log
Math.Log10 = log10
Math.Max = math.max
Math.Min = math.min
Math.Pow = pow
Math.Round = round
Math.Sign = sign
Math.Sin = math.sin
Math.Sinh = sinh
Math.Sqrt = math.sqrt
Math.Tan = math.tan
Math.Tanh = tanh
Math.Truncate = truncate

System.define("System.Math", Math)
end

-- CoreSystemLib: Number.lua
do
local System = System
local throw = System.throw
local define = System.defStc
local equals = System.equals
local zeroFn = System.zeroFn
local identityFn = System.identityFn
local debugsetmetatable = System.debugsetmetatable

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1
local IConvertible = System.IConvertible
local IFormattable = System.IFormattable

local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException
local FormatException = System.FormatException
local OverflowException = System.OverflowException

local type = type
local tonumber = tonumber
local floor = math.floor
local setmetatable = setmetatable
local tostring = tostring

local function hexForamt(x, n)
  return n == "" and "%" .. x or "%0" .. n .. x
end

local function floatForamt(x, n)
  return n == "" and "%.f" or "%." .. n .. 'f'
end

local function integerFormat(x, n)
  return n == "" and "%d" or "%0" .. n .. 'd'
end

local function exponentialFormat(x, n)
  return n == "" and "%" .. x or "%." .. n .. x
end

local formats = {
  ['x'] = hexForamt,
  ['X'] = hexForamt,
  ['f'] = floatForamt,
  ['F'] = floatForamt,
  ['d'] = integerFormat,
  ['D'] = integerFormat,
  ['e'] = exponentialFormat,
  ['E'] = exponentialFormat
}

local function toStringWithFormat(this, format)
  if #format ~= 0 then
    local i, j, x, n = format:find("^%s*([xXdDfFeE])(%d?)%s*$")
    if i then
      local f = formats[x]
      if f then
        format = f(x, n)
      end
      return format:format(this)
    end
  end
  return tostring(this)
end

local function toString(this, format)
  if format then
    return toStringWithFormat(this, format)
  end
  return tostring(this)
end

local function compareInt(this, v)
  if this < v then return -1 end
  if this > v then return 1 end
  return 0
end

local function inherits(_, T)
  return { IComparable, IComparable_1(T), IEquatable_1(T), IConvertible, IFormattable }
end

local Int = define("System.Int", {
  base = inherits,
  default = zeroFn,
  CompareTo = compareInt,
  Equals = equals,
  ToString = toString,
  GetHashCode = identityFn,
  CompareToObj = function (this, v)
    if v == nil then return 1 end
    if type(v) ~= "number" then
      throw(ArgumentException("Arg_MustBeInt"))
    end
    return compareInt(this, v)
  end,
  EqualsObj = function (this, v)
    if type(v) ~= "number" then
      return false
    end
    return this == v
  end
})
Int.__call = zeroFn

local function parseInt(s, min, max)
  if s == nil then
    return nil, 1        
  end
  local v = tonumber(s)
  if v == nil or v ~= floor(v) then
    return nil, 2
  end
  if v < min or v > max then
    return nil, 3
  end
  return v
end

local function tryParseInt(s, min, max)
  local v = parseInt(s, min, max)
  if v then
    return true, v
  end
  return false, 0
end

local function parseIntWithException(s, min, max)
  local v, err = parseInt(s, min, max)
  if v then
    return v    
  end
  if err == 1 then
    throw(ArgumentNullException())
  elseif err == 2 then
    throw(FormatException())
  else
    throw(OverflowException())
  end
end

local SByte = define("System.SByte", {
  Parse = function (s)
    return parseIntWithException(s, -128, 127)
  end,
  TryParse = function (s)
    return tryParseInt(s, -128, 127)
  end
})
setmetatable(SByte, Int)

local Byte = define("System.Byte", {
  Parse = function (s)
    return parseIntWithException(s, 0, 255)
  end,
  TryParse = function (s)
    return tryParseInt(s, 0, 255)
  end
})
setmetatable(Byte, Int)

local Int16 = define("System.Int16", {
  Parse = function (s)
    return parseIntWithException(s, -32768, 32767)
  end,
  TryParse = function (s)
    return tryParseInt(s, -32768, 32767)
  end
})
setmetatable(Int16, Int)

local UInt16 = define("System.UInt16", {
  Parse = function (s)
    return parseIntWithException(s, 0, 65535)
  end,
  TryParse = function (s)
    return tryParseInt(s, 0, 65535)
  end
})
setmetatable(UInt16, Int)

local Int32 = define("System.Int32", {
  Parse = function (s)
    return parseIntWithException(s, -2147483648, 2147483647)
  end,
  TryParse = function (s)
    return tryParseInt(s, -2147483648, 2147483647)
  end
})
setmetatable(Int32, Int)

local UInt32 = define("System.UInt32", {
  Parse = function (s)
    return parseIntWithException(s, 0, 4294967295)
  end,
  TryParse = function (s)
    return tryParseInt(s, 0, 4294967295)
  end
})
setmetatable(UInt32, Int)

local Int64 = define("System.Int64", {
  Parse = function (s)
    return parseIntWithException(s, (-9223372036854775807 - 1), 9223372036854775807)
  end,
  TryParse = function (s)
    return tryParseInt(s, (-9223372036854775807 - 1), 9223372036854775807)
  end
})
setmetatable(Int64, Int)

local UInt64 = define("System.UInt64", {
  Parse = function (s)
    return parseIntWithException(s, 0, 18446744073709551615.0)
  end,
  TryParse = function (s)
    return tryParseInt(s, 0, 18446744073709551615.0)
  end
})
setmetatable(UInt64, Int)

local nan = 0 / 0
local posInf = 1 / 0
local negInf = - 1 / 0
local nanHashCode = {}

--http://lua-users.org/wiki/InfAndNanComparisons
local function isNaN(v)
  return v ~= v
end

local function compareDouble(this, v)
  if this < v then return -1 end
  if this > v then return 1 end
  if this == v then return 0 end
  if isNaN(this) then
    return isNaN(v) and 0 or -1
  else 
    return 1
  end
end

local function equalsDouble(this, v)
  if this == v then return true end
  return isNaN(this) and isNaN(v)
end

local function equalsObj(this, v)
  if type(v) ~= "number" then
    return false
  end
  return equalsDouble(this, v)
end

local function getHashCode(this)
  return isNaN(this) and nanHashCode or this
end

local Number = define("System.Number", {
  base = inherits,
  default = zeroFn,
  CompareTo = compareDouble,
  Equals = equalsDouble,
  ToString = toString,
  NaN = nan,
  IsNaN = isNaN,
  NegativeInfinity = negInf,
  PositiveInfinity = posInf,
  EqualsObj = equalsObj,
  GetHashCode = getHashCode,
  CompareToObj = function (this, v)
    if v == nil then return 1 end
    if type(v) ~= "number" then
      throw(ArgumentException("Arg_MustBeNumber"))
    end
    return compareDouble(this, v)
  end,
  IsFinite = function (v)
    return v ~= posInf and v ~= negInf and not isNaN(v)
  end,
  IsInfinity = function (v)
    return v == posInf or v == negInf
  end,
  IsNegativeInfinity = function (v)
    return v == negInf
  end,
  IsPositiveInfinity = function (v)
    return v == posInf
  end
})
Number.__call = zeroFn
if debugsetmetatable then
  debugsetmetatable(0, Number)
end

local function parseDouble(s)
  if s == nil then
    return nil, 1
  end
  local v = tonumber(s)
  if v == nil then
    return nil, 2
  end
  return v
end

local function parseDoubleWithException(s)
  local v, err = parseDouble(s)
  if v then
    return v    
  end
  if err == 1 then
    throw(ArgumentNullException())
  else
    throw(FormatException())
  end
end

local Single = define("System.Single", {
  Parse = function (s)
    local v = parseDoubleWithException(s)
    if v < -3.40282347E+38 or v > 3.40282347E+38 then
      throw(OverflowException())
    end
    return v
  end,
  TryParse = function (s)
    local v = parseDouble(s)
    if v and v >= -3.40282347E+38 and v < 3.40282347E+38 then
      return true, v
    end
    return false, 0
  end
})
setmetatable(Single, Number)

local Double = define("System.Double", {
  Parse = parseDoubleWithException,
  TryParse = function (s)
    local v = parseDouble(s)
    if v then
      return true, v
    end
    return false, 0
  end
})
setmetatable(Double, Number)

if not debugsetmetatable then
  local NullReferenceException = System.NullReferenceException
  local systemToString = System.toString

  function System.ObjectEqualsObj(this, obj)
    if this == nil then throw(NullReferenceException()) end
    local t = type(this)
    if t == "number" then
      return equalsObj(this, obj)
    elseif t == "table" then
      return this:EqualsObj(obj)
    end
    return this == obj
  end

  function System.ObjectGetHashCode(this)
    if this == nil then throw(NullReferenceException()) end
    local t = type(this)
    if t == "number" then
      return getHashCode(this)
    elseif t == "table" then
      return this:GetHashCode()
    end
    return this
  end

  function System.ObjectToString(this)
    if this == nil then throw(NullReferenceException()) end
    return systemToString(this)
  end

  function System.IComparableCompareTo(this, other)
    if this == nil then throw(NullReferenceException()) end
    local t = type(this)
    if t == "number" then
      return compareDouble(this, other)
    elseif t == "boolean" then
      return System.Boolean.CompareTo(this, other)
    end
    return this:CompareTo(other)
  end

  function System.IEquatableEquals(this, other)
    if this == nil then throw(NullReferenceException()) end
    local t = type(this)
    if t == "number" then
      return equalsDouble(this, other)
    elseif t == "boolean" then
      return System.Boolean.Equals(this, other)
    end
    return this:Equals(other)
  end

  function System.IFormattableToString(this, format, formatProvider)
    if this == nil then throw(NullReferenceException()) end
    local t = type(this)
    if t == "number" then
      return toString(this, format, formatProvider)
    end
    return this:ToString(format, formatProvider)
  end
end
end

-- CoreSystemLib: Char.lua
do
local System = System
local throw = System.throw
local Int = System.Int
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException

local setmetatable = setmetatable
local byte = string.byte

local isSeparatorTable = {
  [32] = true,
  [160] = true,
  [0x2028] = true,
  [0x2029] = true,
  [0x0020] = true,
  [0x00A0] = true,
  [0x1680] = true,
  [0x180E] = true,
  [0x202F] = true,
  [0x205F] = true,
  [0x3000] = true,
}

local isSymbolTable = {
  [36] = true,
  [43] = true,
  [60] = true, 
  [61] = true, 
  [62] = true, 
  [94] = true, 
  [96] = true,
  [124] = true,
  [126] = true,
  [172] = true, 
  [180] = true,
  [182] = true,
  [184] = true,
  [215] = true,
  [247] = true,
}

--https://msdn.microsoft.com/zh-cn/library/t809ektx(v=vs.110).aspx
local isWhiteSpace = {
  [0x0020] = true,
  [0x00A0] = true,
  [0x1680] = true,
  [0x202F] = true,
  [0x205F] = true,
  [0x3000] = true,
  [0x2028] = true,
  [0x2029] = true,
  [0x0085] = true,
}

local function get(s, index)
  if s == nil then throw(ArgumentNullException("s")) end
  local c = byte(s, index + 1)
  if not c then throw(ArgumentOutOfRangeException("index")) end
  return c
end

local function isDigit(c, index)
  if index then
    c = get(c, index)
  end
  return (c >= 48 and c <= 57)
end

-- https://msdn.microsoft.com/zh-cn/library/yyxz6h5w(v=vs.110).aspx
local function isLetter(c, index)    
  if index then
    c = get(c, index) 
  end
  if c < 128 then
    return (c >= 65 and c <= 90) or (c >= 97 and c <= 122)
  else  
    return (c >= 0x0400 and c <= 0x042F) 
      or (c >= 0x03AC and c <= 0x03CE) 
      or (c == 0x01C5 or c == 0x1FFC) 
      or (c >= 0x02B0 and c <= 0x02C1) 
      or (c >= 0x1D2C and c <= 0x1D61) 
      or (c >= 0x05D0 and c <= 0x05EA)
      or (c >= 0x0621 and c <= 0x063A)
      or (c >= 0x4E00 and c <= 0x9FC3) 
  end
end

local Char = System.defStc("System.Char", {
  ToString = string.char,
  CompareTo = Int.CompareTo,
  CompareToObj = Int.CompareToObj,
  Equals = Int.Equals,
  EqualsObj = Int.EqualsObj,
  GetHashCode = Int.GetHashCode,
  default = Int.default,
  IsControl = function (c, index)
    if index then
      c = get(c, index)
    end
    return (c >=0 and c <= 31) or (c >= 127 and c <= 159)
  end,
  IsDigit = isDigit,
  IsLetter = isLetter,
  IsLetterOrDigit = function (c, index)
    if index then
      c = get(c, index)
    end
    return isDigit(c) or isLetter(c)
  end,
  IsLower = function (c, index)
    if index then
      c = get(c, index)
    end
    return (c >= 97 and c <= 122) or (c >= 945 and c <= 969)
  end,
  IsNumber = function (c, index)
    if index then
      c = get(c, index)
    end
    return (c >= 48 and c <= 57) or c == 178 or c == 179 or c == 185 or c == 188 or c == 189 or c == 190
  end,
  IsPunctuation = function (c, index)
    if index then
      c = get(c, index)
    end
    if c < 256 then
      return (c >= 0x0021 and c <= 0x0023) 
        or (c >= 0x0025 and c <= 0x002A) 
        or (c >= 0x002C and c <= 0x002F) 
        or (c >= 0x003A and c <= 0x003B) 
        or (c >= 0x003F and c <= 0x0040)  
        or (c >= 0x005B and c <= 0x005D)
        or c == 0x5F or c == 0x7B or c == 0x007D or c == 0x00A1 or c == 0x00AB or c == 0x00AD or c == 0x00B7 or c == 0x00BB or c == 0x00BF
    end
    return false
  end,
  IsSeparator = function (c, index)
    if index then
      c = get(c, index)
    end
    return (c >= 0x2000 and c <= 0x200A) or isSeparatorTable[c] == true
  end,
  IsSymbol = function (c, index)
    if index then
      c = get(c, index)
    end
    if c < 256 then
      return (c >= 162 and c <= 169) or (c >= 174 and c <= 177) or isSymbolTable(c) == true
    end
    return false
  end,
  IsUpper = function (c, index)
    if index then
      c = get(c, index)
    end
    return (c >= 65 and c <= 90) or (c >= 913 and c <= 937)
  end,
  IsWhiteSpace = function (c, index)
    if index then
      c = get(c, index)
    end
    return (c >= 0x2000 and c <= 0x200A) or (c >= 0x0009 and c <= 0x000d) or isWhiteSpace[c] == true
  end,
  Parse = function (s)
    if s == nil then
      throw(System.ArgumentNullException())
    end
    if #s ~= 1 then
      throw(System.FormatException())
    end
    return s:byte()
  end,
  TryParse = function (s)
    if s == nil or #s ~= 1 then
      return false, 0
    end 
    return true, s:byte()
  end,
  ToLower = function (c)
    if (c >= 65 and c <= 90) or (c >= 913 and c <= 937) then
      return c + 32
    end
    return c
  end,
  ToUpper = function (c)
    if (c >= 97 and c <= 122) or (c >= 945 and c <= 969) then
      return c - 32
    end
    return c
  end,
  IsHighSurrogate = function (c, index) 
    if index then
      c = get(c, index)
    end
    return c >= 0xD800 and c <= 0xDBFF
  end,
  IsLowSurrogate = function (c, index) 
    if index then
      c = get(c, index)
    end
    return c >= 0xDC00 and c <= 0xDFFF
  end,
  IsSurrogate = function (c, index) 
    if index then
      c = get(c, index)
    end
    return c >= 0xD800 and c <= 0xDFFF
  end,
  base = function (_, T)
    return { System.IComparable, System.IComparable_1(T), System.IEquatable_1(T) }
  end
})

local ValueType = System.ValueType
local charMetaTable = setmetatable({ __index = ValueType, __call = Char.default }, ValueType)
setmetatable(Char, charMetaTable)
end

-- CoreSystemLib: String.lua
do
local System = System
local Char = System.Char
local throw = System.throw
local emptyFn = System.emptyFn
local lengthFn = System.lengthFn
local systemToString = System.toString
local debugsetmetatable = System.debugsetmetatable
local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local FormatException = System.FormatException
local IndexOutOfRangeException = System.IndexOutOfRangeException

local string = string
local char = string.char
local rep = string.rep
local lower = string.lower
local upper = string.upper
local byte = string.byte
local sub = string.sub
local find = string.find
local gsub = string.gsub

local table = table
local tconcat = table.concat
local unpack = table.unpack
local getmetatable = getmetatable
local setmetatable = setmetatable
local select = select
local type = type
local tonumber = tonumber
local String

local function toString(t, isch, format)
  if isch then return char(t) end
  return systemToString(t, format)
end

local function checkIndex(value, startIndex, count)
  if value == nil then throw(ArgumentNullException("value")) end
  local len = #value
  if not startIndex then
    startIndex, count = 0, len
  elseif not count then
    if startIndex < 0 or startIndex > len then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    count = len - startIndex
  else
    if startIndex < 0 or startIndex > len then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    if count < 0 or count > len - startIndex then
      throw(ArgumentOutOfRangeException("count"))
    end
  end
  return startIndex, count, len
end

local function ctor(String, value, startIndex, count)
  if type(value) == "number" then
    if startIndex <= 0 then throw(ArgumentOutOfRangeException("count")) end
    return rep(char(value), startIndex)
  end
  startIndex, count = checkIndex(value, startIndex, count)
  return char(unpack(value, startIndex + 1, startIndex + count))
end

local function get(this, index)
  local c = byte(this, index + 1)
  if not c then
    throw(IndexOutOfRangeException())
  end
  return c
end

local function compare(strA, strB, ignoreCase)
  if strA == nil then
    if strB == nil then
      return 0
    end
    return -1
  elseif strB == nil then
    return 1
  end

  if ignoreCase then
    strA, strB = lower(strA), lower(strB)
  end

  if strA < strB then return -1 end
  if strA > strB then return 1 end
  return 0
end

local function compareFull(...)
  local n = select("#", ...)
  if n == 2 then
    return compare(...)
  elseif n == 3 then
    local strA, strB, ignoreCase = ...
    if type(ignoreCase) == "number" then
      ignoreCase = ignoreCase % 2 ~= 0
    end
    return compare(strA, strB, ignoreCase)
  elseif n == 4 then
    local strA, strB, ignoreCase, options = ...
    if type(options) == "number" then
      ignoreCase = options == 1 or options == 268435456
    end
    return compare(strA, strB, ignoreCase)
  else
    local strA, indexA, strB, indexB, length, ignoreCase, options = ...
    if type(ignoreCase) == "number" then
      ignoreCase = ignoreCase % 2 ~= 0
    elseif type(options) == "number" then
      ignoreCase = options == 1 or options == 268435456
    end
    checkIndex(strA, indexA, length)
    checkIndex(strB, indexB, length)
    strA, strB = sub(strA, indexA + 1, indexA +  length), sub(strB, indexB + 1, indexB + length)
    return compare(strA, strB, ignoreCase) 
  end
end

local function concat(...)
  local t = {}
  local count = 1
  local len = select("#", ...)
  if len == 1 then
    local v = ...
    if System.isEnumerableLike(v) then
      local isch = v.__genericT__ == Char
      for _, v in System.each(v) do
        t[count] = toString(v, isch)
        count = count + 1
      end
    else
      return toString(v)
    end
  else
    for i = 1, len do
      local v = select(i, ...)
      t[count] = toString(v)
      count = count + 1
    end
  end
  return tconcat(t)
end

local function equals(this, value, comparisonType)
  if not comparisonType then
    return this == value
  end
  return compare(this, value, comparisonType % 2 ~= 0) == 0
end

local function throwFormatError()
  throw(FormatException("Input string was not in a correct format."))
end

local function formatBuild(format, len, select, ...)
  local t, count = {}, 1
  local i, j, s = 1
  while true do
    local startPos  = i
    while true do
      i, j, s = find(format, "([{}])", i)
      if not i then
        if count == 1 then
          return format
        end
        t[count] = sub(format, startPos)
        return table.concat(t)
      end
      local pos = i - 1
      i = i + 1
      local c = byte(format, i)
      if not c then throwFormatError() end
      if s == '{' then
        if c == 123 then
          i = i + 1
        else
          pos = i - 2
          if pos >= startPos then
            t[count] = sub(format, startPos, pos)
            count = count + 1
          end
          break
        end
      else
        if c == 125 then
          i = i + 1
        else
          throwFormatError()
        end
      end
      if pos >= startPos then
        t[count] = sub(format, startPos, pos)
        count = count + 1
      end
      t[count] = s
      count = count + 1
      startPos = i
    end
    local r, alignment, formatString
    i, j, s, r = find(format, "^(%d+)(.-)}", i)
    if not i then throwFormatError() end
    s = tonumber(s) + 1
    if s > len then throwFormatError() end
    if r ~= "" then
      local i, j, c, d = find(r, "^,([-]?)(%d+)")
      if i then
        alignment = tonumber(d)
        if c == '-' then alignment = -alignment end
        i = j + 1
      end
      i, j, c = find(r, "^:(.*)$", i)
      if i then
        formatString = c
      elseif not alignment then
        throwFormatError()
      end
    end
    s = select(s, ...)
    if s ~= nil and s ~= System.null then
      s = toString(s, false, formatString)
      if alignment then
        s = ("%" .. alignment .. "s"):format(s)
      end
      t[count] = s
      count = count + 1
    end
    i = j + 1
  end
end

local function selectTable(i, t)
  return t[i]
end

local function format(format, ...)
  if format == nil then throw(ArgumentNullException()) end
  local len = select("#", ...)
  if len == 1 then
    local args = ...
    if System.isArrayLike(args) then
      return formatBuild(format, #args, selectTable, args)
    end
  end
  return formatBuild(format, len, select, ...)
end

local function isNullOrEmpty(value)
  return value == nil or #value == 0
end

local function isNullOrWhiteSpace(value)
  return value == nil or find(value, "^%s*$") ~= nil
end

local function joinEnumerable(separator, values)
  if values == nil then throw(ArgumentNullException("values")) end
  if type(separator) == "number" then
    separator = char(separator)
  end
  local isch = values.__genericT__ == Char
  local t = {}
  local len = 1
  for _, v in System.each(values) do
    if v ~= nil then
      t[len] = toString(v, isch)
      len = len + 1
    end
  end
  return tconcat(t, separator)
end

local function joinParams(separator, ...)
  if type(separator) == "number" then
    separator = char(separator)
  end
  local t = {}
  local len = 1
  local n = select("#", ...)
  if n == 1 then
    local values = ...
    if System.isArrayLike(values) then
      for i = 0, #values - 1 do
        local v = values:get(i)
        if v ~= nil then
          t[len] = toString(v)
          len = len + 1
        end
      end
      return tconcat(t, separator) 
    end
  end
  for i = 1, n do
    local v = select(i, ...)
    if v ~= nil then
      t[len] = toString(v)
      len = len + 1
    end
  end
  return tconcat(t, separator) 
end

local function join(separator, value, startIndex, count)
  if type(separator) == "number" then
    separator = char(separator)
  end
  local t = {}
  local len = 1
  if startIndex then  
    checkIndex(value, startIndex, count)
    for i = startIndex + 1, startIndex + count do
      local v = value[i]
      if v ~= System.null then
        t[len] = v
        len = len + 1
      end
    end
  else
    for _, v in System.each(value) do
      if v ~= nil then
        t[len] = v
        len = len + 1
      end
    end
  end
  return tconcat(t, separator)
end

local function compareToObj(this, v)
  if v == nil then return 1 end
  if type(v) ~= "string" then
    throw(ArgumentException("Arg_MustBeString"))
  end
  return compare(this, v)
end

local function escape(s)
  return gsub(s, "([%%%^%.])", "%%%1")
end

local function contains(this, value, comparisonType)
  if value == nil then throw(ArgumentNullException("value")) end
  if type(value) == "number" then
    value = char(value)
  end
  if comparisonType then
    local ignoreCase = comparisonType % 2 ~= 0
    if ignoreCase then
      this, value = lower(this), lower(value)
    end
  end 
  return find(this, escape(value)) ~= nil
end

local function copyTo(this, sourceIndex, destination, destinationIndex, count)
  if destination == nil then throw(ArgumentNullException("destination")) end
  if count < 0 then throw(ArgumentOutOfRangeException("count")) end
  local len = #this
  if sourceIndex < 0 or count > len - sourceIndex then throw(ArgumentOutOfRangeException("sourceIndex")) end
  if destinationIndex > #destination - count or destinationIndex < 0 then throw(ArgumentOutOfRangeException("destinationIndex")) end
  if count > 0 then
    destinationIndex = destinationIndex + 1
    for i = sourceIndex + 1, sourceIndex + count do
      destination[destinationIndex] = byte(this, i)
      destinationIndex = destinationIndex + 1
    end
  end
end

local function endsWith(this, suffix)
  return suffix == "" or sub(this, -#suffix) == suffix
end

local function equalsObj(this, v)
  if type(v) == "string" then
    return this == v
  end
  return false
end

local CharEnumerator = System.define("System.CharEnumerator", {
  base = { System.IEnumerator_1(System.Char), System.IDisposable, System.ICloneable },
  getCurrent = System.getCurrent,
  Dispose = emptyFn,
  MoveNext = function (this)
    local index, s = this.index, this.s
    if index <= #s then
      this.current = byte(s, index)
      this.index = index + 1
      return true
    end
    return false
  end
})

local function getEnumerator(this)
  return setmetatable({ s = this, index = 1 }, CharEnumerator)
end

local function getTypeCode()
  return 18
end

local function indexOf(this, value, startIndex, count, comparisonType)
  if value == nil then throw(ArgumentNullException("value")) end
  startIndex, count = checkIndex(this, startIndex, count)
  if type(value) == "number" then value = char(value) end
  local ignoreCase = comparisonType and comparisonType % 2 ~= 0
  if ignoreCase then
    this, value = lower(this), lower(value)
  end
  local i, j = find(this, escape(value), startIndex + 1)
  if i then
    local e = startIndex + count
    if j <= e then
      return i - 1
    end
    return - 1
  end
  return -1
end

local function indexOfAny(this, anyOf, startIndex, count)
  if anyOf == nil then throw(ArgumentNullException("chars")) end
  startIndex, count = checkIndex(this, startIndex, count)
  anyOf = "[" .. escape(char(unpack(anyOf))) .. "]"
  local i, j = find(this, anyOf, startIndex + 1)
  if i then
    local e = startIndex + count
    if j <= e then
      return i - 1
    end
    return - 1
  end
  return -1
end

local function insert(this, startIndex, value) 
  if value == nil then throw(ArgumentNullException("value")) end
  if startIndex < 0 or startIndex > #this then throw(ArgumentOutOfRangeException("startIndex")) end
  return sub(this, 1, startIndex) .. value .. sub(this, startIndex + 1)
end

local function chechLastIndexOf(value, startIndex, count)
  if value == nil then throw(ArgumentNullException("value")) end
  local len = #value
  if not startIndex then
    startIndex, count = len - 1, len
  elseif not count then
    count = len == 0 and 0 or (startIndex + 1)
  end
  if len == 0 then
    if startIndex ~= -1 and startIndex ~= 0 then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    if count ~= 0 then
      throw(ArgumentOutOfRangeException("count"))
    end
  end
  if startIndex < 0 or startIndex >= len then
    throw(ArgumentOutOfRangeException("startIndex"))
  end
  if count < 0 or startIndex - count + 1 < 0 then
    throw(ArgumentOutOfRangeException("count"))
  end
  return startIndex, count, len
end

local function lastIndexOf(this, value, startIndex, count, comparisonType)
  if value == nil then throw(ArgumentNullException("value")) end
  startIndex, count = chechLastIndexOf(this, startIndex, count)
  if type(value) == "number" then value = char(value) end
  local ignoreCase = comparisonType and comparisonType % 2 ~= 0
  if ignoreCase then
    this, value = lower(this), lower(value)
  end
  value = escape(value)
  local e = startIndex + 1
  local f = e - count + 1
  local index = -1  
  while true do
    local i, j = find(this, value, f)
    if not i or j > e then
      break
    end
    index = i - 1
    f = j + 1
  end
  return index
end

local function lastIndexOfAny(this, anyOf, startIndex, count)
  if anyOf == nil then throw(ArgumentNullException("chars")) end
  startIndex, count = chechLastIndexOf(this, startIndex, count)
  anyOf = "[" .. escape(char(unpack(anyOf))) .. "]"
  local f, e = startIndex - count + 1, startIndex + 1
  local index = -1
  while true do
    local i, j = find(this, anyOf, f)
    if not i or j > e then
      break
    end
    index = i - 1
    f = j + 1
  end
  return index
end

local function padLeft(this, totalWidth, paddingChar) 
  local len = #this;
  if len >= totalWidth then
    return this
  else
    paddingChar = paddingChar or 0x20
    return rep(char(paddingChar), totalWidth - len) .. this
  end
end

local function padRight(this, totalWidth, paddingChar) 
  local len = #this
  if len >= totalWidth then
    return this
  else
    paddingChar = paddingChar or 0x20
    return this .. rep(char(paddingChar), totalWidth - len)
  end
end

local function remove(this, startIndex, count) 
  startIndex, count = checkIndex(this, startIndex, count)
  return sub(this, 1, startIndex) .. sub(this, startIndex + 1 + count)
end

local function replace(this, a, b)
  if type(a) == "number" then
    a, b = char(a), char(b)
  end
  return gsub(this, escape(a), b)
end

local function findAny(s, strings, startIndex)
  local findBegin, findEnd
  for i = 1, #strings do
    local posBegin, posEnd = find(s, escape(strings[i]), startIndex)
    if posBegin then
      if not findBegin or posBegin < findBegin then
        findBegin, findEnd = posBegin, posEnd
      else
        break
      end
    end
  end
  return findBegin, findEnd
end

local function split(this, strings, count, options) 
  local t = {}
  local find = find
  if type(strings) == "table" then
    if #strings == 0 then
      return t
    end

    if type(strings[1]) == "string" then
      find = findAny
    else
      strings = char(unpack(strings))
      strings = escape(strings)
      strings = "[" .. strings .. "]"
    end
  elseif type(strings) == "string" then       
    strings = escape(strings)         
  else
    strings = char(strings)
    strings = escape(strings)
  end

  local len = 1
  local startIndex = 1
  while true do
    local posBegin, posEnd = find(this, strings, startIndex)
    posBegin = posBegin or 0
    local subStr = sub(this, startIndex, posBegin -1)
    if options ~= 1 or #subStr > 0 then
      t[len] = subStr
      len = len + 1
      if count then
        count = count -1
        if count == 0 then
          if posBegin ~= 0 then
            t[len - 1] = sub(this, startIndex)
          end
          break
        end
      end
    end
    if posBegin == 0 then
      break
    end 
    startIndex = posEnd + 1
  end   
  return System.arrayFromTable(t, String) 
end

local function startsWith(this, prefix)
  return sub(this, 1, #prefix) == prefix
end

local function substring(this, startIndex, count)
  startIndex, count = checkIndex(this, startIndex, count)
  return sub(this, startIndex + 1, startIndex + count)
end

local function toCharArray(str, startIndex, count)
  startIndex, count = checkIndex(str, startIndex, count)
  local t = {}
  local len = 1
  for i = startIndex + 1, startIndex + count do
    t[len] = byte(str, i)
    len = len + 1
  end
  return System.arrayFromTable(t, System.Char)
end

local function trim(this, chars, ...)
  if not chars then
    chars = "^%s*(.-)%s*$"
  else
    if type(chars) == "table" then
      chars = char(unpack(chars))
    else
      chars = char(chars, ...)
    end
    chars = escape(chars)
    chars = "^[" .. chars .. "]*(.-)[" .. chars .. "]*$"
  end
  return (gsub(this, chars, "%1"))
end

local function trimEnd(this, chars, ...)
  if not chars then
    chars = "(.-)%s*$"
  else
    if type(chars) == "table" then
      chars = char(unpack(chars))
    else
      chars = char(chars, ...)
    end
    chars = escape(chars)
    chars = "(.-)[" .. chars .. "]*$"
  end
  return (gsub(this, chars, "%1"))
end

local function trimStart(this, chars, ...)
  if not chars then
    chars = "^%s*(.-)"
  else
    if type(chars) == "table" then
      chars = char(unpack(chars))
    else
      chars = char(chars, ...)
    end
    chars = escape(chars)
    chars = "^[" .. chars .. "]*(.-)"
  end
  return (gsub(this, chars, "%1"))
end

local function inherits(_, T)
  return { System.IEnumerable_1(System.Char), System.IComparable, System.IComparable_1(T), System.IConvertible, System.IEquatable_1(T), System.ICloneable }
end

string.traceback = emptyFn  -- make throw(str) not fail
string.getLength = lengthFn
string.getCount = lengthFn
string.get = get
string.Compare = compareFull
string.CompareOrdinal = compareFull
string.Concat = concat
string.Copy = System.identityFn
string.Equals = equals
string.Format = format
string.IsNullOrEmpty = isNullOrEmpty
string.IsNullOrWhiteSpace = isNullOrWhiteSpace
string.JoinEnumerable = joinEnumerable
string.JoinParams = joinParams
string.Join = join
string.CompareTo = compare
string.CompareToObj = compareToObj
string.Contains = contains
string.CopyTo = copyTo
string.EndsWith = endsWith
string.EqualsObj = equalsObj
string.GetEnumerator = getEnumerator
string.GetTypeCode = getTypeCode
string.IndexOf = indexOf
string.IndexOfAny = indexOfAny
string.Insert = insert
string.LastIndexOf = lastIndexOf
string.LastIndexOfAny = lastIndexOfAny
string.PadLeft = padLeft
string.PadRight = padRight
string.Remove = remove
string.Replace = replace
string.Split = split
string.StartsWith = startsWith
string.Substring = substring
string.ToCharArray = toCharArray
string.ToLower = lower
string.ToLowerInvariant = lower
string.ToString = System.identityFn
string.ToUpper = upper
string.ToUpperInvariant = upper
string.Trim = trim
string.TrimEnd = trimEnd
string.TrimStart = trimStart

if debugsetmetatable then
  String = string
  String.__genericT__ = System.Char
  String.base = inherits
  System.define("System.String", String)

  debugsetmetatable("", String)
  local Object = System.Object
  local StringMetaTable = setmetatable({ __index = Object, __call = ctor }, Object)
  setmetatable(String, StringMetaTable)
else
  string.__call = ctor
  string.__index = string
  
  String = getmetatable("")
  String.__genericT__ = System.Char
  String.base = inherits
  System.define("System.String", String)
  String.__index = string
  setmetatable(String, string)
  setmetatable(string, System.Object)  
end
end

-- CoreSystemLib: Boolean.lua
do
local System = System
local throw = System.throw
local debugsetmetatable = System.debugsetmetatable
local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException
local FormatException = System.FormatException

local type = type
local setmetatable = setmetatable

local function compareTo(this, v)
  if this == v then
    return 0
  elseif this == false then
    return -1     
  end
  return 1
end

local falseString = "False"
local trueString = "True"

local function parse(s)
  if s == nil then
    return nil, 1
  end
  local i, j, value = s:find("^[%s%c%z]*(%a+)[%s%c%z]*$")
  if value then
    s = value:lower()
    if s == "true" then
      return true
    elseif s == "false" then
      return false
    end
  end
  return nil, 2
end

local function toString(this)
  return this and trueString or falseString
end

local Boolean = System.defStc("System.Boolean", {
  default = System.falseFn,
  GetHashCode = System.identityFn,
  Equals = System.equals,
  CompareTo = compareTo,
  ToString = toString,
  FalseString = falseString,
  TrueString = trueString,
  CompareToObj = function (this, v)
    if v == nil then return 1 end
    if type(v) ~= "boolean" then
      throw(ArgumentException("Arg_MustBeBoolean"))
    end
    return compareTo(this, v)
  end,
  EqualsObj = function (this, v)
    if type(v) ~= "boolean" then
      return false
    end
    return this == v
  end,
  __concat = function (a, b)
    if type(a) == "boolean" then
      return toString(a) .. b
    else 
      return a .. toString(b)
    end
  end,
  __tostring = toString,
  Parse = function (s)
    local v, err = parse(s)
    if v == nil then
      if err == 1 then
        throw(ArgumentNullException()) 
      else
        throw(FormatException())
      end
    end
    return v
  end,
  TryParse = function (s)
    local v = parse(s)
    if v ~= nil then
      return true, v
    end
    return false, false
  end,
  base = function (_, T)
    return { System.IComparable, System.IConvertible, System.IComparable_1(T), System.IEquatable_1(T) }
  end
})
if debugsetmetatable then
  debugsetmetatable(false, Boolean)
end

local ValueType = System.ValueType
local boolMetaTable = setmetatable({ __index = ValueType, __call = Boolean.default }, ValueType)
setmetatable(Boolean, boolMetaTable)
end

-- CoreSystemLib: Delegate.lua
do
local System = System
local throw = System.throw
local Object = System.Object
local debugsetmetatable = System.debugsetmetatable
local ArgumentNullException = System.ArgumentNullException

local setmetatable = setmetatable
local assert = assert
local select = select
local type = type
local unpack = table.unpack
local tmove = table.move

local Delegate
local multicast

local function appendFn(t, count, f)
  if type(f) == "table" then
    for i = 1, #f do
      t[count] = f[i]
      count = count + 1
    end
  else
    t[count] = f
    count = count + 1
  end
  return count
end

local function combineImpl(fn1, fn2)    
  local t = setmetatable({}, multicast)
  local count = 1
  count = appendFn(t, count, fn1)
  appendFn(t, count, fn2)
  return t
end

local function combine(fn1, fn2)
  if fn1 ~= nil then
    if fn2 ~= nil then 
      return combineImpl(fn1, fn2) 
    end
    return fn1 
  end
  if fn2 ~= nil then return fn2 end
  return nil
end

local function equalsMulticast(fn1, fn2, start, count)
  for i = 1, count do
    if fn1[start + i] ~= fn2[i] then
      return false
    end
  end
  return true
end

local function delete(fn, count, deleteIndex, deleteCount)
  local t =  setmetatable({}, multicast)
  local len = 1
  for i = 1, deleteIndex - 1 do
    t[len] = fn[i]
    len = len + 1
  end
  for i = deleteIndex + deleteCount, count do
    t[len] = fn[i]
    len = len + 1
  end
  return t
end

local function removeImpl(fn1, fn2) 
  if type(fn2) ~= "table" then
    if type(fn1) ~= "table" then
      if fn1 == fn2 then
        return nil
      end
    else
      local count = #fn1
      for i = count, 1, -1 do
        if fn1[i] == fn2 then
          if count == 2 then
            return fn1[3 - i]
          else
            return delete(fn1, count, i, 1)
          end
        end
      end
    end
  elseif type(fn1) == "table" then
    local count1, count2 = #fn1, # fn2
    local diff = count1 - count2
    for i = diff + 1, 1, -1 do
      if equalsMulticast(fn1, fn2, i - 1, count2) then
        if diff == 0 then 
          return nil
        elseif diff == 1 then 
          return fn1[i ~= 1 and 1 or count1] 
        else
          return delete(fn1, count1, i, count2)
        end
      end
    end
  end
  return fn1
end

local function remove(fn1, fn2)
  if fn1 ~= nil then
    if fn2 ~= nil then
      return removeImpl(fn1, fn2)
    end
    return fn1
  end
  return nil
end

local multiKey = System.multiKey

local mt = {}
local function makeGenericTypes(...)
  local gt, gk = multiKey(mt, nil, ...)
  local t = gt[gk]
  if t == nil then
    t = setmetatable({ ... }, Delegate)
    gt[gk] = t
  end
  return t
end

Delegate = System.define("System.Delegate", {
  __add = combine,
  __sub = remove,
  EqualsObj = System.equals,
  Combine = combine,
  Remove = remove,
  RemoveAll = function (source, value)
    local newDelegate
    repeat
      newDelegate = source
      source = remove(source, value)
    until newDelegate == source
    return newDelegate
  end,
  DynamicInvoke = function (this, ...)
    return this(...)
  end,
  GetType = function (this)
    return System.typeof(Delegate)
  end,
  GetInvocationList = function (this)
    local t
    if type(this) == "table" then
      t = {}
      tmove(this, 1, #this, 1, t)
    else
      t = { this }
    end
    return System.arrayFromTable(t, Delegate)
  end
})

local delegateMetaTable = setmetatable({ __index = Object, __call = makeGenericTypes }, Object)
setmetatable(Delegate, delegateMetaTable)
if debugsetmetatable then
  debugsetmetatable(System.emptyFn, Delegate)

  function System.event(name)
    local function a(this, v)
      this[name] = this[name] + v
    end
    local function r(this, v)
      this[name] = this[name] - v
    end
    return a, r
  end
else
  System.DelegateCombine = combine
  System.DelegateRemove = remove

  function System.event(name)
    local function a(this, v)
      this[name] = combine(this[name], v)
    end
    local function r(this, v)
      this[name] = remove(this[name], v)
    end
    return a, r
  end
end

multicast = setmetatable({
  __index = Delegate,
  __add = combine,
  __sub = remove,
  __call = function (t, ...)
    local result
    for i = 1, #t do
      result = t[i](...)
    end
    return result
  end,
  __eq = function (fn1, fn2)
    local len1, len2 = #fn1, #fn2
    if len1 ~= len2 then
      return false
    end
    for i = 1, len1 do
      if fn1[i] ~= fn2[i] then
        return false
      end
    end
    return true
  end
}, Delegate)

function System.fn(target, method)
  assert(method)
  if target == nil then throw(ArgumentNullException()) end
  local f = target[method]
  if f == nil then
    f = function (...)
      return method(target, ...)
    end
    target[method] = f
  end
  return f
end

local binds = setmetatable({}, { __mode = "k" })

function System.bind(f, n, ...)
  assert(f)
  local gt, gk = multiKey(binds, nil, f, ...)
  local fn = gt[gk]
  if fn == nil then
    local args = { ... }
    fn = function (...)
      local len = select("#", ...)
      if len == n then
        return f(..., unpack(args))
      else
        assert(len > n)
        local t = { ... }
        for i = 1, #args do
          local j = args[i]
          if type(j) == "number" then
            j = select(n + j, ...)
            assert(j)
          end
          t[n + i] = j
        end
        return f(unpack(t, 1, n + #args))
      end
    end
    gt[gk] = fn
  end
  return fn
end

local function bind(f, create, ...)
  assert(f)
  local gt, gk = multiKey(binds, nil, f, create)
  local fn = gt[gk]
  if fn == nil then
    fn = create(f, ...)
    gt[gk] = fn
  end
  return fn
end

local function create1(f, a)
  return function (...)
    return f(..., a)
  end
end

function System.bind1(f, a)
  return bind(f, create1, a)
end

local function create2(f, a, b)
  return function (...)
    return f(..., a, b)
  end
end

function System.bind2(f, a, b)
  return bind(f, create2, a, b)
end

local function create3(f, a, b, c)
  return function (...)
    return f(..., a, b, c)
  end
end

function System.bind3(f, a, b, c)
 return bind(f, create3, a, b, c)
end

local function create2_1(f)
  return function(x1, x2, T1, T2)
    return f(x1, x2, T2, T1)
  end
end

function System.bind2_1(f)
  return bind(f, create2_1) 
end

local function create0_2(f)
  return function(x1, x2, T1, T2)
    return f(x1, x2, T2)
  end
end

function System.bind0_2(f)
  return bind(f, create0_2) 
end

local EventArgs = System.define("System.EventArgs")
EventArgs.Empty = setmetatable({}, EventArgs)
end

-- CoreSystemLib: Enum.lua
do
local System = System
local throw = System.throw
local Int = System.Int
local Number = System.Number
local band = System.band
local bor = System.bor
local ArgumentNullException = System.ArgumentNullException
local ArgumentException = System.ArgumentException

local assert = assert
local pairs = pairs
local tostring = tostring
local type = type

local function toString(this, cls)
  if this == nil then return "" end
  if cls then
    for k, v in pairs(cls) do
      if v == this then
        return k
      end
    end
  end
  return tostring(this)
end

local function hasFlag(this, flag)
  if this == flag then
    return true
  end
  return band(this, flag) ~= 0
end

Number.EnumToString = toString
Number.HasFlag = hasFlag
System.EnumToString = toString
System.EnumHasFlag = hasFlag

local function tryParseEnum(enumType, value, ignoreCase)
  if enumType == nil then throw(ArgumentNullException("enumType")) end
  local cls = enumType[1] or enumType
  if cls.class ~= "E" then throw(ArgumentException("Arg_MustBeEnum")) end
  if value == nil then
    return
  end
  if ignoreCase then
    value = value:lower()
  end
  local i, j, s, r = 1
  while true do
    i, j, s = value:find("%s*(%a+)%s*", i)
    if not i then
      return
    end
    for k, v in pairs(cls) do
      if ignoreCase then
        k = k:lower()
      end
      if k == s then
        if not r then
          r = v
        else
          r = bor(r, v)
        end
        break
      end
    end
    i = value:find(',', j + 1)
    if not i then
      break
    end
    i = i + 1
  end
  return r
end

System.define("System.Enum", {
  CompareToObj = Int.CompareToObj,
  EqualsObj = Int.EqualsObj,
  default = Int.default,
  ToString = toString,
  HasFlag = hasFlag,
  GetName = function (enumType, value)
    if enumType == nil then throw(ArgumentNullException("enumType")) end
    if value == nil then throw(ArgumentNullException("value")) end
    if not enumType:getIsEnum() then throw(ArgumentException("Arg_MustBeEnum")) end
    for k, v in pairs(enumType[1]) do
      if v == value then
        return k
      end
    end
  end,
  GetNames = function (enumType)
    if enumType == nil then throw(ArgumentNullException("enumType")) end
    if not enumType:getIsEnum() then throw(ArgumentException("Arg_MustBeEnum")) end
    local t = {}
    local count = 1
    for k, v in pairs(enumType[1]) do
      if type(v) == "number" then
        t[count] = k
        count = count + 1
      end
    end
    return System.arrayFromTable(t, System.String)
  end,
  GetValues = function (enumType)
    if enumType == nil then throw(ArgumentNullException("enumType")) end
    if not enumType:getIsEnum() then throw(ArgumentException("Arg_MustBeEnum")) end
    local t = {}
    local count = 1
    for k, v in pairs(enumType[1]) do
      if type(v) == "number" then
        t[count] = v
        count = count + 1
      end
    end
    return System.arrayFromTable(t, System.Int32)
  end,
  IsDefined = function (enumType, value)
    if enumType == nil then throw(ArgumentNullException("enumType")) end
    if value == nil then throw(ArgumentNullException("value")) end
    if not enumType:getIsEnum() then throw(ArgumentException("Arg_MustBeEnum")) end
    local cls = enumType[1]
    local t = type(value)
    if t == "string" then
      return cls[value] ~= nil
    elseif t == "number" then
      for k, v in pairs(cls) do
        if v == value then
          return true
        end
      end
      return false
    end
    throw(System.InvalidOperationException())
  end,
  Parse = function (enumType, value, ignoreCase)
    local result = tryParseEnum(enumType, value, ignoreCase)
    if result == nil then
      throw(ArgumentException("Requested value '" .. value .. "' was not found."))
    end
    return result
  end,
  TryParse = function (type, value, ignoreCase)
    local result = tryParseEnum(type, value, ignoreCase)
    if result == nil then
      return false, 0
    end
    return true, result
  end
})
end

-- CoreSystemLib: TimeSpan.lua
do
local System = System
local throw = System.throw
local div = System.div
local trunc = System.trunc
local ArgumentException = System.ArgumentException
local OverflowException = System.OverflowException
local ArgumentNullException = System.ArgumentNullException
local FormatException = System.FormatException

local assert = assert
local getmetatable = getmetatable
local select = select
local sformat = string.format
local sfind = string.find
local tostring = tostring
local tonumber = tonumber
local floor = math.floor
local log10 = math.log10

local TimeSpan
local zero

local function compare(t1, t2)
  if t1.ticks > t2.ticks then return 1 end
  if t1.ticks < t2.ticks then return -1 end
  return 0
end

local function add(this, ts) 
  return TimeSpan(this.ticks + ts.ticks)
end

local function subtract(this, ts) 
  return TimeSpan(this.ticks - ts.ticks)
end

local function negate(this) 
  local ticks = this.ticks
  if ticks == (-9223372036854775807 - 1) then
    throw(OverflowException("Overflow_NegateTwosCompNum"))
  end
  return TimeSpan(-ticks)
end

local function interval(value, scale)
  if value ~= value then 
    throw(ArgumentException("Arg_CannotBeNaN"))
  end
  local tmp = value * scale
  local millis = tmp + (value >=0 and 0.5 or -0.5)
  if millis > 922337203685477 or millis < -922337203685477 then
    throw(OverflowException("Overflow_TimeSpanTooLong"))
  end
  return TimeSpan(trunc(millis) * 10000)
end

local function getPart(this, i, j)
  local t = this.ticks
  local v = div(t, i) % j
  if v ~= 0 and t < 0 then
    return v - j
  end
  return v
end

local function parse(s)
  if s == nil then return nil, 1 end
  local i, j, k, sign, ch
  local day, hour, minute, second, milliseconds = 0, 0, 0, 0, 0
  i, j, sign, day = sfind(s, "^%s*([-]?)(%d+)")
  if not i then return end
  k = j + 1
  i, j, ch = sfind(s, "^([%.:])", k)
  if not i then 
    i, j = sfind(s, "^%s*$", k)
    if not i then return end
    k = -1
  else
    k = j + 1
    if ch == '.' then
      i, j, hour, minute = sfind(s, "^(%d+):(%d+)", k)
      if not i then return end
      k = j + 1
      i, j, second = sfind(s, "^:(%d+)", k)
      if not i then return end
    else
      i, j, hour = sfind(s, "^(%d+)", k)
      if not i then return end
      k = j + 1
      i, j, minute = sfind(s, "^:(%d+)", k)
      if not i then
        i, j = sfind(s, "^%s*$", k)
        if not i then
          return
        end
        day, hour, minute = 0, day, hour
        k = -1
      else
        k = j
        i, j, second = sfind(s, "^:(%d+)", k + 1)
        if not i then
          day, hour, minute, second = 0, day, hour, minute
          j = k
        end
      end
    end
  end
  if k ~= -1 then
    k = j + 1
    i, j, milliseconds = sfind(s, "^%.(%d+)%s*$", k)
    if not i then
      i, j = sfind(s, "^%s*$", k)
      if not i then return end
      milliseconds = 0
    else
      milliseconds = tonumber(milliseconds)
      local n = floor(log10(milliseconds) + 1)
      if n > 3 then
        if n > 7 then return end
        milliseconds = milliseconds / (10 ^ (n - 3))
      end
    end
  end
  if sign == '-' then
    day, hour, minute, second, milliseconds = -tonumber(day), -tonumber(hour), -tonumber(minute), -tonumber(second), -tonumber(milliseconds)
  else
    day, hour, minute, second, milliseconds = tonumber(day), tonumber(hour), tonumber(minute), tonumber(second), tonumber(milliseconds)
  end
  return TimeSpan(day, hour, minute, second, milliseconds)
end

TimeSpan = System.defStc("System.TimeSpan", {
  ticks = 0,
  __ctor__ = function (this, ...)
    local ticks
    local length = select("#", ...)
    if length == 0 then
    elseif length == 1 then
      ticks = ...
    elseif length == 3 then
      local hours, minutes, seconds = ...
      ticks = (((hours * 60 + minutes) * 60) + seconds) * 10000000
    elseif length == 4 then
      local days, hours, minutes, seconds = ...
      ticks = ((((days * 24 + hours) * 60 + minutes) * 60) + seconds) * 10000000
    elseif length == 5 then
      local days, hours, minutes, seconds, milliseconds = ...
      ticks = (((((days * 24 + hours) * 60 + minutes) * 60) + seconds) * 1000 + milliseconds) * 10000
    else 
      assert(ticks)
    end
    this.ticks = ticks
  end,
  Compare = compare,
  CompareTo = compare,
  CompareToObj = function (this, t)
    if t == nil then return 1 end
    if getmetatable(t) ~= TimeSpan then
      throw(ArgumentException("Arg_MustBeTimeSpan"))
    end
    compare(this, t)
  end,
  Equals = function (t1, t2)
    return t1.ticks == t2.ticks
  end,
  EqualsObj = function(this, t)
    if getmetatable(t) == TimeSpan then
      return this.ticks == t.ticks
    end
    return false
  end,
  GetHashCode = function (this)
    return this.ticks
  end,
  getTicks = function (this) 
    return this.ticks
  end,
  getDays = function (this) 
    return div(this.ticks, 864000000000)
  end,
  getHours = function(this)
    return getPart(this, 36000000000, 24)
  end,
  getMinutes = function (this)
    return getPart(this, 600000000, 60)
  end,
  getSeconds = function (this)
    return getPart(this, 10000000, 60)
  end,
  getMilliseconds = function (this)
    return getPart(this, 10000, 1000)
  end,
  getTotalDays = function (this) 
    return this.ticks / 864000000000
  end,
  getTotalHours = function (this) 
    return this.ticks / 36000000000
  end,
  getTotalMilliseconds = function (this) 
    return this.ticks / 10000
  end,
  getTotalMinutes = function (this) 
    return this.ticks / 600000000
  end,
  getTotalSeconds = function (this) 
    return this.ticks / 10000000
  end,
  Add = add,
  Subtract = subtract,
  Duration = function (this) 
    local ticks = this.ticks
    if ticks == (-9223372036854775807 - 1) then
      throw(OverflowException("Overflow_Duration"))
    end
    return TimeSpan(ticks >= 0 and ticks or - ticks)
  end,
  Negate = negate,
  ToString = function (this) 
    local day, milliseconds = this:getDays(), this.ticks % 10000000
    local daysStr = day == 0 and "" or (day .. ".")
    local millisecondsStr = milliseconds == 0 and "" or (".%07d"):format(milliseconds)
    return sformat("%s%02d:%02d:%02d%s", daysStr, this:getHours(), this:getMinutes(), this:getSeconds(), millisecondsStr)
  end,
  Parse = function (s)
    local v, err = parse(s)
    if v then
      return v
    end
    if err == 1 then
      throw(ArgumentNullException())
    else
      throw(FormatException())
    end
  end,
  TryParse = function (s)
    local v = parse(s)
    if v then
      return true, v
    end
    return false, zero
  end,
  __add = add,
  __sub = subtract,
  __unm = negate,
  __eq = function (t1, t2)
    return t1.ticks == t2.ticks
  end,
  __lt = function (t1, t2)
    return t1.ticks < t2.ticks
  end,
  __le = function (t1, t2)
    return t1.ticks <= t2.ticks
  end,
  FromDays = function (value) 
    return interval(value, 864e5)
  end,
  FromHours = function (value) 
    return interval(value, 36e5)
  end,
  FromMilliseconds = function (value) 
    return interval(value, 1)
  end,
  FromMinutes = function (value) 
    return interval(value, 6e4)
  end,
  FromSeconds = function (value) 
    return interval(value, 1000)
  end,
  FromTicks = function (value) 
    return TimeSpan(value)
  end,
  base = function (_, T)
    return { System.IComparable, System.IComparable_1(T), System.IEquatable_1(T) }
  end,
  default = function ()
    return zero
  end,
  Zero = false,
  MaxValue = false,
  MinValue = false
})

zero = TimeSpan(0)
TimeSpan.Zero = zero
TimeSpan.MaxValue = TimeSpan(9223372036854775807)
TimeSpan.MinValue = TimeSpan((-9223372036854775807 - 1))
end

-- CoreSystemLib: DateTime.lua
do
local System = System
local throw = System.throw
local div = System.div
local trunc = System.trunc

local TimeSpan = System.TimeSpan
local compare = TimeSpan.Compare
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException
local FormatException = System.FormatException

local assert = assert
local getmetatable = getmetatable
local select = select
local sformat = string.format
local sfind = string.find
local os = os
local ostime = os.time
local osdifftime = os.difftime
local osdate = os.date
local tonumber = tonumber
local math = math
local floor = math.floor
local log10 = math.log10
local modf = math.modf

--http://referencesource.microsoft.com/#mscorlib/system/datetime.cs
local DateTime
local minValue

local daysToMonth365 = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334, 365 }
local daysToMonth366 = { 0, 31, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366 }

local function isLeapYear(year) 
  if year < 1 or year > 9999 then 
    throw(ArgumentOutOfRangeException("year", "ArgumentOutOfRange_Year"))
  end
  return year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0)
end

local function dateToTicks(year, month, day) 
  if year >= 1 and year <= 9999 and month >= 1 and month <= 12 then
    local days = isLeapYear(year) and daysToMonth366 or daysToMonth365
    if day >= 1 and day <= days[month + 1] - days[month] then
      local y = year - 1
      local n = y * 365 + div(y, 4) - div(y, 100) + div(y, 400) + days[month] + day - 1
      return n * 864000000000
    end
  end
end

local function timeToTicks(hour, minute, second)
  if hour >= 0 and hour < 24 and minute >= 0 and minute < 60 and second >=0 and second < 60 then 
    return (((hour * 60 + minute) * 60) + second) * 10000000
  end
  throw(ArgumentOutOfRangeException("ArgumentOutOfRange_BadHourMinuteSecond"))
end

local function checkTicks(ticks)
  if ticks < 0 or ticks > 3155378975999999999 then
    throw(ArgumentOutOfRangeException("ticks", "ArgumentOutOfRange_DateTimeBadTicks"))
  end
end

local function checkKind(kind) 
  if kind and (kind < 0 or kind > 2) then
    throw(ArgumentOutOfRangeException("kind"))
  end
end

local function addTicks(this, value)
  return DateTime(this.ticks + value, this.kind)
end

local function addTimeSpan(this, ts)
  return addTicks(this, ts.ticks)
end

local function add(this, value, scale)
  local millis = trunc(value * scale + (value >= 0 and 0.5 or -0.5))
  return addTicks(this, millis * 10000)
end

local function subtract(this, v) 
  if getmetatable(v) == DateTime then
    return TimeSpan(this.ticks - v.ticks)
  end
  return DateTime(this.ticks - v.ticks, this.kind) 
end

local function getDataPart(ticks, part)
  local n = div(ticks, 864000000000)
  local y400 = div(n, 146097)
  n = n - y400 * 146097
  local y100 = div(n, 36524)
  if y100 == 4 then y100 = 3 end
  n = n - y100 * 36524
  local y4 = div(n, 1461)
  n = n - y4 * 1461;
  local y1 = div(n, 365)
  if y1 == 4 then y1 = 3 end
  if part == 0 then
    return y400 * 400 + y100 * 100 + y4 * 4 + y1 + 1
  end
  n = n - y1 * 365
  if part == 1 then return n + 1 end
  local leapYear = y1 == 3 and (y4 ~= 24 or y100 == 3)
  local days = leapYear and daysToMonth366 or daysToMonth365
  local m = div(n, 32) + 1
  while n >= days[m + 1] do m = m + 1 end
  if part == 2 then return m end
  return n - days[m] + 1
end

local function getDatePart(ticks)
  local year, month, day
  local n = div(ticks, 864000000000)
  local y400 = div(n, 146097)
  n = n - y400 * 146097
  local y100 = div(n, 36524)
  if y100 == 4 then y100 = 3 end
  n = n - y100 * 36524
  local y4 = div(n, 1461)
  n = n - y4 * 1461
  local y1 = div(n, 365)
  if y1 == 4 then y1 = 3 end
  year = y400 * 400 + y100 * 100 + y4 * 4 + y1 + 1
  n = n - y1 * 365
  local leapYear = y1 == 3 and (y4 ~= 24 or y100 == 3)
  local days = leapYear and daysToMonth366 or daysToMonth365
  local m = div(n, 32) + 1
  while n >= days[m + 1] do m = m + 1 end
  month = m
  day = n - days[m] + 1
  return year, month, day
end

local function daysInMonth(year, month)
  if month < 1 or month > 12 then
    throw(ArgumentOutOfRangeException("month"))
  end
  local days = isLeapYear(year) and daysToMonth366 or daysToMonth365
  return days[month + 1] - days[month]
end

local function addMonths(this, months)
  if months < -120000 or months > 12000 then
    throw(ArgumentOutOfRangeException("months"))
  end
  local ticks = this.ticks
  local y, m, d = getDatePart(ticks)
  local i = m - 1 + months
  if i >= 0 then
    m = i % 12 + 1
    y = y + div(i, 12)
  else
    m = 12 + (i + 1) % -12
    y = y + div(i - 11, 12)
  end
  if y < 1 or y > 9999 then
    throw(ArgumentOutOfRangeException("months")) 
  end
  local days = daysInMonth(y, m)
  if d > days then d = days end
  return DateTime(dateToTicks(y, m, d) + ticks % 864000000000, this.kind)
end

local function getTimeZone()
  local date = osdate("*t")
  local dst = date.isdst
  local now = ostime(date)
  return osdifftime(now, ostime(osdate("!*t", now))) * 10000000, dst and 3600 * 10000000 or 0 
end

local timeZoneTicks, dstTicks = getTimeZone()
local baseUtcOffset = TimeSpan(timeZoneTicks)

local time = System.config.time or ostime
System.time = time
System.currentTimeMillis = function () return trunc(time() * 1000) end

local function now()
  local seconds = time()
  local ticks = seconds * 10000000 + timeZoneTicks + dstTicks + 621355968000000000
  return DateTime(ticks, 2)
end

local function parse(s)
  if s == nil then
    return nil, 1
  end
  local i, j, year, month, day, hour, minute, second, milliseconds
  i, j, year, month, day = sfind(s, "^%s*(%d+)%s*/%s*(%d+)%s*/%s*(%d+)%s*")
  if i == nil then
    return nil, 2
  else
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
  end
  if j < #s then
    i, j, hour, minute = sfind(s, "^(%d+)%s*:%s*(%d+)", j + 1)
    if i == nil then
      return nil, 2
    else
      hour, minute = tonumber(hour), tonumber(minute)
    end
    local next = j + 1
    i, j, second = sfind(s, "^:%s*(%d+)", next)
    if i == nil then
      if sfind(s, "^%s*$", next) == nil then
        return nil, 2
      else
        second = 0
        milliseconds = 0
      end
    else
      second = tonumber(second)
      next = j + 1
      i, j, milliseconds = sfind(s, "^%.(%d+)%s*$", next)
      if i == nil then
        if sfind(s, "^%s*$", next) == nil then
          return nil, 2
        else
          milliseconds = 0
        end
      else
        milliseconds = tonumber(milliseconds)
        local n = floor(log10(milliseconds) + 1)
        if n > 3 then
          if n <= 7 then
            milliseconds = milliseconds / (10 ^ (n - 3))
          else
            local ticks = milliseconds / (10 ^ (n - 7))
            local _, decimal = modf(ticks)
            if decimal > 0.5 then
              ticks = ticks + 1
            end
            milliseconds = floor(ticks) / 10000
          end
        end
      end
    end
  end
  if hour == nil then
    return DateTime(year, month, day)
  end
  return DateTime(year, month, day, hour, minute, second, milliseconds)
end

local abbreviatedDayNames = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
local dayNames = { "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"	 }
local abbreviatedMonthNames = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
local monthNames = { "January",	"February",	"March", "April",	"May", "June", "July", "August", "September", "October", "November", "December" }

local realFormats = {
  ["d"] = "MM/dd/yyyy",
  ["D"] = "dddd, dd MMMM yyyy",
  ["f"] = "dddd, dd MMMM yyyy HH:mm",
  ["F"] = "dddd, dd MMMM yyyy HH:mm:ss",
  ["g"] = "MM/dd/yyyy HH:mm",
  ["G"] = "MM/dd/yyyy HH:mm:ss",
  ["m"] = "MMMM dd",
  ["M"] = "MMMM dd",
  ["o"] = "yyyy-MM-ddTHH:mm:ss.fffffffK",
  ["O"] = "yyyy-MM-ddTHH:mm:ss.fffffffK",
  ["r"] = "ddd, dd MMM yyyy HH:mm:ss GMT",
  ["R"] = "ddd, dd MMM yyyy HH:mm:ss GMT",
  ["s"] = "yyyy-MM-ddTHH:mm:ss",
  ["t"] = "HH:mm",
  ["T"] = "HH:mm:ss",
  ["u"] = "yyyy-MM-dd HH:mm:ssZ",
  ["U"] = "dddd, dd MMMM yyyy HH:mm:ss",
  ["y"] = "yyyy MMMM",
  ["Y"] = "yyyy MMMM"
}

local function parseRepeatPattern(format, n, pos, ch)
  local index = pos + 1
  while index <= n and format:byte(index) == ch do
    index = index + 1
  end
  return index - pos
end

local function throwFormatInvalidException()
  throw(FormatException("Input string was not in a correct format."))
end

local function formatCustomized(this, format, n)
  local t, i, tokenLen, hour12 = {}, 1
  while i <= n do
    local ch = format:byte(i)
    if ch == 104 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      hour12 = this:getHour() % 12
      if hour12 == 0 then hour12 = 12 end
      t[#t + 1] = sformat("%02d", hour12)
    elseif ch == 72 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      t[#t + 1] = sformat("%02d", this:getHour())
    elseif ch == 109 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      t[#t + 1] = sformat("%02d", this:getMinute())
    elseif ch == 115 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      t[#t + 1] = sformat("%02d", this:getSecond())
    elseif ch == 102 or ch == 70 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      if tokenLen <= 7 then
        local fraction = this.ticks % 10000000
        fraction = div(fraction, 10 ^ (7 - tokenLen))
        if ch == 102 then
          t[#t + 1] = sformat("%0" .. tokenLen .. 'd', fraction)
        else
          local effectiveDigits = tokenLen
          while effectiveDigits > 0 do
            if fraction % 10 == 0 then
              fraction = div(fraction, 10)
              effectiveDigits = effectiveDigits - 1
            else 
              break
            end
          end
          if effectiveDigits > 0 then
            t[#t + 1] = sformat("%0" .. effectiveDigits .. 'd', fraction)
          end
        end
      else
        throwFormatInvalidException()
      end
    elseif ch == 116 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      local hour = this:getHour()
      if tokenLen == 1 then
        t[#t + 1] = hour < 12 and "A" or "P"
      else
        t[#t + 1] = hour < 12 and "AM" or "PM"
      end
    elseif ch == 100 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      if tokenLen <= 2 then
        local day = this:getDay()
        t[#t + 1] = sformat("%0" .. tokenLen .. 'd', day)
      else
        local i = this:getDayOfWeek() + 1
        t[#t + 1] = (tokenLen == 3 and abbreviatedDayNames or dayNames)[i]
      end
    elseif ch == 77 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      local month = this:getMonth()
      if tokenLen <= 2 then
        t[#t + 1] = sformat("%0" .. tokenLen .. 'd', month)
      else
        t[#t + 1] = (tokenLen == 3 and abbreviatedMonthNames or monthNames)[month]
      end
    elseif ch == 121 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      local year = this:getYear()
      if tokenLen <= 2 then
        year = year % 100
        t[#t + 1] = tokenLen == 1 and year or sformat("%02d", year)
      else
        t[#t + 1] = sformat("%0" .. tokenLen .. 'd', year)
      end
    elseif ch == 122 then
      tokenLen = parseRepeatPattern(format, n, i, ch)
      local offset = this.kind == 1 and TimeSpan.Zero or baseUtcOffset
      local sign
      if offset.ticks >= 0 then
        sign = "+"
      else
        sign = "-"
        offset = offset:Negate()
      end
      local hour = offset:getHours()
      if tokenLen <= 1 then
        t[#t + 1] = sformat("%s%d", sign, hour)
      elseif tokenLen < 3 then
        t[#t + 1] = sformat("%s%02d", sign, hour)
      else
        t[#t + 1] = sformat("%s%02d:%02d", sign, hour, offset:getMinutes())
      end
    elseif ch == 75 then
      tokenLen = 1
      if this.kind == 2 then
        local offset = baseUtcOffset
        local sign
        if offset.ticks >= 0 then
          sign = "+"
        else
          sign = "-"
          offset = offset:Negate()
        end
        t[#t + 1] = sformat("%s%02d:%02d", sign, offset:getHours(), offset:getMinutes())
      elseif this.kind == 1 then
        t[#t + 1] = "Z"
      end
    elseif ch == 39 or ch == 34 then
      local a, b, c = sfind(format, "^(.*)" .. string.char(ch), i + 1)
      if not a then throwFormatInvalidException() end
      t[#t + 1] = c
      tokenLen = b - a + 2
    elseif ch == 37 then
      local nextChar = format:byte(i + 1)
      if nextChar and nextChar ~= 37 then
        t[#t + 1] = formatCustomized(this, string.char(nextChar), 1)
        tokenLen = 2
      else
        throwFormatInvalidException()
      end
    elseif ch == 92 then
      local nextChar = format:byte(i + 1)
      if nextChar then
        t[#t + 1] = string.char(nextChar)
        tokenLen = 2
      else
        throwFormatInvalidException()
      end
    else
      t[#t + 1] = string.char(ch)
      tokenLen = 1
    end
    i = i + tokenLen
  end
  return table.concat(t)
end

local function toStringWithFormat(this, format)
  local n = #format
  if n == 1 then
    format = realFormats[format]
    if not format then throwFormatInvalidException() end
    return formatCustomized(this, format, #format)
  end
  return formatCustomized(this, format, n)
end

DateTime = System.defStc("System.DateTime", {
  ticks = 0,
  kind = 0,
  Compare = compare,
  CompareTo = compare,
  CompareToObj = function (this, t)
    if t == nil then return 1 end
    if getmetatable(t) ~= DateTime then
      throw(ArgumentException("Arg_MustBeDateTime"))
    end
    return compare(this, t)
  end,
  Equals = function (t1, t2)
    return t1.ticks == t2.ticks
  end,
  EqualsObj = function (this, t)
    if getmetatable(t) == DateTime then
      return this.ticks == t.ticks
    end
    return false
  end,
  GetHashCode = function (this)
    return this.ticks
  end,
  IsLeapYear = isLeapYear,
  __ctor__ = function (this, ...)
    local len = select("#", ...)
    if len == 0 then
    elseif len == 1 then
      local ticks = ...
      checkTicks(ticks)
      this.ticks = ticks
    elseif len == 2 then
      local ticks, kind = ...
      checkTicks(ticks)
      checkKind(kind)
      this.ticks = ticks
      this.kind = kind
    elseif len == 3 then
      this.ticks = dateToTicks(...)
    elseif len == 6 then
      local year, month, day, hour, minute, second = ...
      this.ticks = dateToTicks(year, month, day) + timeToTicks(hour, minute, second)
    elseif len == 7 then
      local year, month, day, hour, minute, second, millisecond = ...
      this.ticks = dateToTicks(year, month, day) + timeToTicks(hour, minute, second) + millisecond * 10000
    elseif len == 8 then
      local year, month, day, hour, minute, second, millisecond, kind = ...
      checkKind(kind)
      this.ticks = dateToTicks(year, month, day) + timeToTicks(hour, minute, second) + millisecond * 10000
      this.kind = kind
    else
      assert(false)
    end
  end,
  AddTicks = addTicks,
  Add = addTimeSpan,
  AddDays = function (this, days)
    return add(this, days, 86400000)
  end,
  AddHours = function (this, hours)
    return add(this, hours, 3600000)
  end,
  AddMinutes = function (this, minutes) 
    return add(this, minutes, 60000);
  end,
  AddSeconds = function (this, seconds)
    return add(this, seconds, 1000)
  end,
  AddMilliseconds = function (this, milliseconds)
    return add(this, milliseconds, 1)
  end,
  DaysInMonth = daysInMonth,
  AddMonths = addMonths,
  AddYears = function (this, years)
    if years < - 10000 or years > 10000 then
      throw(ArgumentOutOfRangeException("years")) 
    end
    return addMonths(this, years * 12)
  end,
  SpecifyKind = function (this, kind)
    return DateTime(this.ticks, kind)
  end,
  Subtract = subtract,
  getDay = function (this)
    return getDataPart(this.ticks, 3)
  end,
  getDate = function (this)
    local ticks = this.ticks
    return DateTime(ticks - ticks % 864000000000, this.kind)
  end,
  getDayOfWeek = function (this)
    return (div(this.ticks, 864000000000) + 1) % 7
  end,
  getDayOfYear = function (this)
    return getDataPart(this.ticks, 1)
  end,
  getKind = function (this)
    return this.kind
  end,
  getHour = TimeSpan.getHours,
  getMinute = TimeSpan.getMinutes,
  getSecond = TimeSpan.getSeconds,
  getMillisecond = TimeSpan.getMilliseconds,
  getMonth = function (this)
    return getDataPart(this.ticks, 2)
  end,
  getYear = function (this)
    return getDataPart(this.ticks, 0)
  end,
  getTimeOfDay = function (this)
    return TimeSpan(this.ticks % 864000000000)
  end,
  getTicks = function (this)
    return this.ticks
  end,
  BaseUtcOffset = baseUtcOffset,
  getUtcNow = function ()
    local seconds = time()
    local ticks = seconds * 10000000 + 621355968000000000
    return DateTime(ticks, 1)
  end,
  getNow = now,
  getToday = function ()
    return now():getDate()
  end,
  ToLocalTime = function (this)
    if this.kind == 2 then 
      return this
    end
    local ticks = this.ticks + timeZoneTicks + dstTicks
    return DateTime(ticks, 2)
  end,
  ToUniversalTime = function (this)
    if this.kind == 1 then
      return this
    end
    local ticks = this.ticks - timeZoneTicks - dstTicks
    return DateTime(ticks, 1)
  end,
  IsDaylightSavingTime = function(this)
    return this.kind == 2 and dstTicks > 0
  end,
  ToString = function (this, format)
    if format then 
      return toStringWithFormat(this, format) 
    end
    local year, month, day = getDatePart(this.ticks)
    return sformat("%d/%d/%d %02d:%02d:%02d", year, month, day, this:getHour(), this:getMinute(), this:getSecond())
  end,
  Parse = function (s)
    local v, err = parse(s)
    if v then
      return v
    end
    if err == 1 then
      throw(ArgumentNullException())
    else
      throw(FormatException())
    end
  end,
  TryParse = function(s)
    local v = parse(s)
    if v then
      return true, v
    end
    return false, minValue
  end,
  __add = addTimeSpan,
  __sub = subtract,
  __eq = TimeSpan.__eq,
  __lt = TimeSpan.__lt,
  __le = TimeSpan.__le,
  base =  function(_, T)
    return { System.IComparable, System.IComparable_1(T), System.IConvertible, System.IEquatable_1(T), System.IFormattable }
  end,
  default = function ()
    return minValue
  end,
  MinValue = false,
  MaxValue = false
})

minValue = DateTime(0)
DateTime.MinValue = minValue
DateTime.MaxValue = DateTime(3155378975999999999)
end

-- CoreSystemLib: Collections/EqualityComparer.lua
do
local System = System
local define = System.define
local throw = System.throw
local equalsObj = System.equalsObj
local compareObj = System.compareObj
local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException

local type = type

local EqualityComparer
EqualityComparer = define("System.EqualityComparer", function (T)
  local equals
  local Equals = T.Equals
  if Equals then
    if T.class == 'S' then
      equals = Equals 
    else
      equals = function (x, y) 
        return x:Equals(y) 
      end 
    end
  else
    equals = equalsObj
  end
  local function getHashCode(x)
    if type(x) == "table" then
      return x:GetHashCode()
    end
    return x
  end
  local defaultComparer
  return {
    __genericT__ = T,
    base = { System.IEqualityComparer_1(T), System.IEqualityComparer }, 
    getDefault = function ()
      local comparer = defaultComparer 
      if comparer == nil then
        comparer = EqualityComparer(T)()
        defaultComparer = comparer
      end
      return comparer
    end,
    EqualsOf = function (this, x, y)
      if x ~= nil then
        if y ~= nil then return equals(x, y) end
        return false
      end                 
      if y ~= nil then return false end
      return true
    end,
    GetHashCodeOf = function (this, obj)
      if obj == nil then return 0 end
      return getHashCode(obj)
    end,
    GetHashCodeObjOf = function (this, obj)
      if obj == nil then return 0 end
      if System.is(obj, T) then return getHashCode(obj) end
      throw(ArgumentException("Type of argument is not compatible with the generic comparer."))
    end,
    EqualsObjOf = function (this, x, y)
      if x == y then return true end
      if x == nil or y == nil then return false end
      local is = System.is
      if is(x, T) and is(y, T) then return equals(x, y) end
      throw(ArgumentException("Type of argument is not compatible with the generic comparer."))
    end
  }
end, nil, 1)

local function compare(this, a, b)
  return compareObj(a, b)
end

define("System.Comparer", (function ()
  local Comparer
  Comparer = {
    base = { System.IComparer },
    static = function (this)
      local default = Comparer()
      this.Default = default
      this.DefaultInvariant = default
    end,
    Compare = compare
  }
  return Comparer
end)())

local Comparer, ComparisonComparer

ComparisonComparer = define("System.ComparisonComparer", function (T)
  return {
    base = { Comparer(T) },
    __ctor__ = function (this, comparison)
      this.comparison = comparison
    end,
    Compare = function (this, x, y)
      return this.comparison(x, y)
    end
  }
end, nil, 1)

Comparer = define("System.Comparer_1", function (T)
  local Compare
  local compareTo = T.CompareTo
  if compareTo then
    if T.class ~= 'S' then
      compareTo = function (x, y)
        return x:CompareTo(y)
      end
    end
    Compare = function (this, x, y)
      if x ~= nil then
        if y ~= nil then 
          return compareTo(x, y) 
        end
        return 1
      end                 
      if y ~= nil then return -1 end
      return 0
    end
  else
    Compare = compare
  end

  local defaultComparer
  local function getDefault()
    local comparer = defaultComparer 
    if comparer == nil then
      comparer = Comparer(T)()
      defaultComparer = comparer
    end
    return comparer
  end

  local function Create(comparison)
    if comparison == nil then throw(ArgumentNullException("comparison")) end
    return ComparisonComparer(T)(comparison)
  end

  return {
    __genericT__ = T,
    base = { System.IComparer_1(T), System.IComparer }, 
    getDefault = getDefault,
    getDefaultInvariant = getDefault,
    Compare = Compare,
    Create = Create
  }
end)
end

-- CoreSystemLib: Array.lua
do
local System = System
local define = System.define
local throw = System.throw
local div = System.div
local bnot = System.bnot
local trueFn = System.trueFn
local falseFn = System.falseFn
local lengthFn = System.lengthFn
local er = System.er

local InvalidOperationException = System.InvalidOperationException
local NullReferenceException = System.NullReferenceException
local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local IndexOutOfRangeException = System.IndexOutOfRangeException
local NotSupportedException = System.NotSupportedException
local EqualityComparer = System.EqualityComparer
local Comparer_1 = System.Comparer_1
local IEnumerable_1 = System.IEnumerable_1
local IEnumerator_1 = System.IEnumerator_1

local assert = assert
local select = select
local getmetatable = getmetatable
local setmetatable = setmetatable
local type = type
local table = table
local tinsert = table.insert
local tremove = table.remove
local tmove = table.move
local tsort = table.sort
local pack = table.pack
local unpack = table.unpack
local error = error
local coroutine = coroutine
local ccreate = coroutine.create
local cresume = coroutine.resume
local cyield = coroutine.yield

local null = {}
local arrayEnumerator
local arrayFromTable

local versions = setmetatable({}, { __mode = "k" })
System.versions = versions

local function throwFailedVersion()
  throw(InvalidOperationException("Collection was modified; enumeration operation may not execute."))
end

local function checkIndex(t, index) 
  if index < 0 or index >= #t then
    throw(ArgumentOutOfRangeException("index"))
  end
end

local function checkIndexAndCount(t, index, count)
  if t == nil then throw(ArgumentNullException("array")) end
  if index < 0 or count < 0 or index + count > #t then
    throw(ArgumentOutOfRangeException("index or count"))
  end
end

local function wrap(v)
  if v == nil then 
    return null 
  end
  return v
end

local function unWrap(v)
  if v == null then 
    return nil 
  end
  return v
end

local function ipairs(t)
  local version = versions[t]
  return function (t, i)
    if version ~= versions[t] then
      throwFailedVersion()
    end
    local v = t[i]
    if v ~= nil then
      if v == null then
        v = nil
      end
      return i + 1, v
    end
  end, t, 1
end

local function eachFn(en)
  if en:MoveNext() then
    return true, en:getCurrent()
  end
  return nil
end

local function each(t)
  if t == nil then throw(NullReferenceException(), 1) end
  local getEnumerator = t.GetEnumerator
  if getEnumerator == arrayEnumerator then
    return ipairs(t)
  end
  local en = getEnumerator(t)
  return eachFn, en
end

function System.isArrayLike(t)
  return type(t) == "table" and t.GetEnumerator == arrayEnumerator
end

function System.isEnumerableLike(t)
  return type(t) == "table" and t.GetEnumerator ~= nil
end

function System.toLuaTable(array)
  local t = {}
  for i = 1, #array do
    local item = array[i]
    if item ~= null then
      t[i] = item
    end
  end   
  return t
end

System.null = null
System.Void = null
System.each = each
System.ipairs = ipairs
System.throwFailedVersion = throwFailedVersion

System.wrap = wrap
System.unWrap = unWrap
System.checkIndex = checkIndex
System.checkIndexAndCount = checkIndexAndCount

local Array
local emptys = {}

local function get(t, index)
  local v = t[index + 1]
  if v == nil then
    throw(ArgumentOutOfRangeException("index"))
  end
  if v ~= null then 
    return v
  end
  return nil
end

local function set(t, index, v)
  index = index + 1
  if t[index] == nil then
    throw(ArgumentOutOfRangeException("index"))
  end
  t[index] = v == nil and null or v
  versions[t] = (versions[t] or 0) + 1
end

local function add(t, v)
  local n = #t
  t[n + 1] = v == nil and null or v
  versions[t] = (versions[t] or 0) + 1
  return n
end

local function addRange(t, collection)
  if collection == nil then throw(ArgumentNullException("collection")) end
  local count = #t + 1
  if collection.GetEnumerator == arrayEnumerator then
    tmove(collection, 1, #collection, count, t)
  else
    for _, v in each(collection) do
      t[count] = v == nil and null or v
      count = count + 1
    end
  end
  versions[t] = (versions[t] or 0) + 1
end

local function clear(t)
  local size = #t
  if size > 0 then
    for i = 1, size do
      t[i] = nil
    end
    versions[t] = (versions[t] or 0) + 1
  end
end

local function first(t)
  local v = t[1]
  if v == nil then throw(InvalidOperationException())  end
  if v ~= null then
    return v
  end
  return nil
end

local function last(t)
  local n = #t
  if n == 0 then throw(InvalidOperationException()) end
  local v = t[n]
  if v ~= null then
    return v
  end
  return nil
end

local function unset()
  throw(NotSupportedException("Collection is read-only."))
end

local function fill(t, f, e, v)
  while f <= e do
    t[f] = v
    f = f + 1
  end
end

local function buildArray(T, len, t)
  if t == nil then 
    t = {}
    if len > 0 then
      local genericT = T.__genericT__
      local default = genericT:default()
      if default == nil then
        fill(t, 1, len, null)
      elseif type(default) ~= "table" then
        fill(t, 1, len, default)
      else
        for i = 1, len do
          t[i] = genericT:default()
        end
      end
    end
  else
    if len > 0 then
      local default = T.__genericT__:default()
      if default == nil then
        for i = 1, len do
          if t[i] == nil then
            t[i] = null
          end
        end
      end
    end
  end
  return setmetatable(t, T)
end

local function indexOf(t, v, startIndex, count)
  if t == nil then throw(ArgumentNullException("array")) end
  local len = #t
  if not startIndex then
    startIndex, count = 0, len
  elseif not count then
    if startIndex < 0 or startIndex > len then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    count = len - startIndex
  else
    if startIndex < 0 or startIndex > len then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    if count < 0 or count > len - startIndex then
      throw(ArgumentOutOfRangeException("count"))
    end
  end
  local comparer = EqualityComparer(t.__genericT__).getDefault()
  local equals = comparer.EqualsOf
  for i = startIndex + 1, startIndex + count do
    local item = t[i]
    if item == null then item = nil end
    if equals(comparer, item, v) then
      return i - 1
    end
  end
  return -1
end

local function findIndex(t, startIndex, count, match)
  if t == nil then throw(ArgumentNullException("array")) end
  local len = #t
  if not count then
    startIndex, count, match = 0, len, startIndex
  elseif not match then
    if startIndex < 0 or startIndex > len then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    count, match = len - startIndex, count
  else
    if startIndex < 0 or startIndex > len then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    if count < 0 or count > len - startIndex then
      throw(ArgumentOutOfRangeException("count"))
    end
  end
  if match == nil then throw(ArgumentNullException("match")) end
  local endIndex = startIndex + count
  for i = startIndex + 1, endIndex  do
    local item = t[i]
    if item == null then item = nil end
    if match(item) then
      return i - 1
    end
  end
  return -1
end

local function copy(sourceArray, sourceIndex, destinationArray, destinationIndex, length, reliable)
  if not reliable then
    checkIndexAndCount(sourceArray, sourceIndex, length)
    checkIndexAndCount(destinationArray, destinationIndex, length)
  end
  tmove(sourceArray, sourceIndex + 1, sourceIndex + length, destinationIndex + 1, destinationArray)
end

local function removeRange(t, index, count)
  local n = #t
  if count < 0 or index > n - count then
    throw(ArgumentOutOfRangeException("index or count"))
  end
  if count > 0 then
    if index + count < n then
      tmove(t, index + count + 1, n, index + 1)
    end
    fill(t, n - count + 1, n, nil)
    versions[t] = (versions[t] or 0) + 1
  end
end

local function findAll(t, match)
  if t == nil then throw(ArgumentNullException("array")) end
  if match == nil then throw(ArgumentNullException("match")) end
  local list = {}
  local count = 1
  for i = 1, #t do
    local item = t[i]
    if (item == null and match(nil)) or match(item) then
      list[count] = item
      count = count + 1
    end
  end
  return list
end

local function binarySearch(t, ...)
  if t == nil then throw(ArgumentNullException("array")) end
  local len = #t
  local index, count, v, comparer
  local n = select("#", ...)
  if n == 1 or n == 2 then
    index, count, v, comparer = 0, len, ...
  else
    index, count, v, comparer = ...
  end
  checkIndexAndCount(t, index, count)
  local compare
  if type(comparer) == "function" then
    compare = comparer
  elseif comparer == nil then
    comparer = Comparer_1(t.__genericT__).getDefault()
    compare = comparer.Compare 
  else
    compare = comparer.Compare
  end
  local lo = index
  local hi = index + count - 1
  while lo <= hi do
    local i = lo + div(hi - lo, 2)
    local item = t[i + 1]
    if item == null then item = nil end
    local order = compare(comparer, item, v);
    if order == 0 then return i end
    if order < 0 then
      lo = i + 1
    else
      hi = i - 1
    end
  end
  return bnot(lo)
end

local function getSortComp(t, comparer)
  local compare
  if comparer then
    if type(comparer) == "function" then
      compare = comparer
    else
      local Compare = comparer.Compare
      if Compare then
        compare = function (x, y) return Compare(comparer, x, y) end
      else
        compare = comparer
      end
    end
  else
    comparer = Comparer_1(t.__genericT__).getDefault()
    local Compare = comparer.Compare
    compare = function (x, y) return Compare(comparer, x, y) end
  end
  return function(x, y) 
    if x == null then x = nil end
    if y == null then y = nil end
    return compare(x, y) < 0
  end
end

local function sort(t, comparer)
  if #t > 1 then
    tsort(t, getSortComp(t, comparer))
    versions[t] = (versions[t] or 0) + 1
  end
end

local function addOrder(t, v, comparer)
  local i = binarySearch(t, v, comparer)
  if i >= 0 then return false end
  tinsert(t, bnot(i) + 1, v == nil and null or v)
  return true
end

local function addOrderRange(t, collection)
  if collection == nil then throw(ArgumentNullException("collection")) end
  local comparer, n = t.comparer, #t
  if collection.GetEnumerator == arrayEnumerator then
    for i = 1, #collection do
      local v = collection[i]
      if v == null then v = nil end
      addOrder(t, v, comparer)
    end
  else
    for _, v in each(collection) do
      addOrder(t, v, comparer)
    end
  end
  if #t ~= n then
    versions[t] = (versions[t] or 0) + 1
  end
end

local function exceptWithOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  if #t == 0 then return end
  if t == other then
    clear(t)
    return
  end
  local comparer, n = t.comparer, #t
  if other.GetEnumerator == arrayEnumerator then
    for i = 1, n do
      local v = t[i]
      if v == null then v = nil end
      local i = binarySearch(t, v, comparer)
      if i >= 0 then
        tremove(t, i + 1)
      end
    end
  else
    for _, v in each(other) do
      local i = binarySearch(t, v, comparer)
      if i >= 0 then
        tremove(t, i + 1)
      end
    end
  end
  if #t ~= n then
    versions[t] = (versions[t] or 0) + 1
  end
end

local function intersectWithOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  if #t == 0 then return end
  if t == other then return end
  local comparer = t.comparer
  local array = arrayFromTable({}, t.__genericT__)
  for _, v in each(other) do
    local i = binarySearch(t, v, comparer)
    if i >= 0 then
      array[#array + 1] = v == nil and null or v
    end
  end
  clear(t)
  addOrderRange(t, array)
end

local function isSubsetOfOrderWithSameEC(t, n, comparer, set)
  for i = 1, n do
    local v = t[i]
    if v == null then v = nil end
    local j = binarySearch(set, v, comparer)
    if j < 0 then
      return false
    end
  end
  return true
end

local function checkOrderUniqueAndUnfoundElements(t, n, comparer, other, returnIfUnfound)
  if n == 0 then
    local numElementsInOther = 0
    for _, v in each(other) do
      numElementsInOther = numElementsInOther + 1
      break
    end
    return 0, numElementsInOther
  end
  local uniqueFoundCount, unfoundCount, mark = 0, 0, {}
  for _, v in each(other) do
    local i = binarySearch(t, v, comparer)
    if i >= 0 then
      if not mark[i] then
        mark[i] = true
        uniqueFoundCount = uniqueFoundCount + 1
      end
    else
      unfoundCount = unfoundCount + 1
      if returnIfUnfound then
        break
      end
    end
  end
  return uniqueFoundCount, unfoundCount
end

local function isProperSubsetOfOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  if t == other then return false end
  local comparer, n = t.comparer, #t
  if System.is(other, System.SortedSet(t.__genericT__)) then
    if comparer == other.comparer then
      if n >= #other then return false end
      return isSubsetOfOrderWithSameEC(t, n, comparer, set)
    end
  end
  local uniqueCount, unfoundCount = checkOrderUniqueAndUnfoundElements(t, n, comparer, other)
  return uniqueCount == n and unfoundCount > 0
end

local function isProperSupersetOfOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  local n = #t
  if n == 0 then return false end
  if System.is(other, System.ICollection) then
    if other:getCount() == 0 then
      return true
    end
  end
  local comparer = t.comparer
  if System.is(other, System.SortedSet(t.__genericT__)) then
    if comparer == other.comparer then
      local n1 = #other
      if n1 >= n then return false end
      return isSubsetOfOrderWithSameEC(other, n1, comparer, t)
    end
  end
  local uniqueCount, unfoundCount = checkOrderUniqueAndUnfoundElements(t, n, comparer, other, true)
  return uniqueCount < n and unfoundCount == 0
end

local function isSubsetOfOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  local n = #t
  if n == 0 then return true end
  local comparer = t.comparer
  if System.is(other, System.SortedSet(t.__genericT__)) then
    if comparer == other.comparer then
      if n > #other then return false end
      return isSubsetOfOrderWithSameEC(t, n, comparer, set)
    end
  end
  local uniqueCount, unfoundCount = checkOrderUniqueAndUnfoundElements(t, n, comparer, other)
  return uniqueCount == n and unfoundCount >= 0
end

local function isSupersetOfOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  if System.is(other, System.ICollection) then
    if other:getCount() == 0 then
      return true
    end
  end
  local comparer, n = t.comparer, #t
  if System.is(other, System.SortedSet(t.__genericT__)) then
    if comparer == other.comparer then
      local n1 = #other
      if n < n1 then return false end
      return isSubsetOfOrderWithSameEC(other, n1, comparer, t)
    end
  end
  for _, v in each(other) do
    local i = binarySearch(t, v, comparer)
    if i < 0 then
      return false
    end
  end
  return true
end

local function isOverlapsOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  local n = #t
  if n == 0 then return false end
  if System.is(other, System.ICollection) and other:getCount() == 0 then return false end
  local comparer = t.comparer
  if System.is(other, System.SortedSet(t.__genericT__)) and comparer == other.comparer then
    local c = comparer.Compare
    if c(comparer, first(t), last(other)) > 0 or c(comparer, last(t), first(other)) < 0 then
      return false
    end
  end
  for _, v in each(other) do
    local i = binarySearch(t, v, comparer)
    if i >= 0 then
      return true
    end
  end
  return false
end

local function equalsOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  local comparer, n = t.comparer, #t
  if System.is(other, System.SortedSet(t.__genericT__)) and comparer == other.comparer then
    local n1 = #other
    if n ~= n1 then return false end
    local c = comparer.Compare
    for i = 1, n do
      local v, v1 = t[i], other[i]
      if v == null then v = nil end
      if v1 == null then v1 = nil end
      if c(comparer, v, v1) ~= 0 then
        return false
      end
    end
    return true
  end
  local uniqueCount, unfoundCount = checkOrderUniqueAndUnfoundElements(t, n, comparer, other, true)
  return uniqueCount == n and unfoundCount == 0
end

local function symmetricExceptWithOrder(t, other)
  if other == nil then throw(ArgumentNullException("other")) end
  local n = #t
  if n == 0 then
    addOrderRange(other)
    return
  end
  if t == other then
    clear(t)
    return
  end
  for _, v in each(other) do
    local i = binarySearch(t, v, comparer)
    if i >= 0 then
      tremove(t, i + 1)
    else
      addOrder(t, v, comparer)
    end
  end
end

local function tryGetValueOrder(t, equalValue)
  local i = binarySearch(t, equalValue, t.comparer)
  if i >= 0 then
    local v = t[i + 1]
    if v == null then v = nil end
    return true, v
  end
  return false, t.__genericT__:default()
end

local function checkOrderDictKeyValueObj(t, k, v)
  if k == nil then throw(ArgumentNullException("key")) end
  local TValue = t.__genericTValue__
  if v == nil and TValue:default() ~= nil then throw(ArgumentNullException("value")) end
  local TKey = t.__genericTKey__
  if not System.is(k, TKey) then 
    throw(ArgumentException(er.Arg_WrongType(k, TKey.__name__), "key")) 
  end
  if not System.is(v, TValue) then
    throw(ArgumentException(er.Arg_WrongType(v, TValue.__name__), "value")) 
  end
end

local function getOrderDictIndex(t, k, isObj)
  if k == nil then throw(ArgumentNullException("key")) end
  if isObj and not System.is(k, t.__genericTKey__) then
    return -1
  end
  return binarySearch(t, k, t.keyComparer)
end

local function addOrderDict(t, k, v, keyComparer, T, version)
  local i = binarySearch(t, k, keyComparer)
  if i >= 0 then
    throw(ArgumentException(er.Argument_AddingDuplicate(k)))
  end
  tinsert(t, bnot(i) + 1, setmetatable({ k, v }, T))
  if version then
    versions[t] = (versions[t] or 0) + 1
  end
end

local function getOrderDict(t, k, isObj)
  local i = getOrderDictIndex(t, k)
  if i >= 0 then
    return t[i + 1][2]
  end
  if isObj then
    return nil
  end
  throw(System.KeyNotFoundException(er.Arg_KeyNotFoundWithKey(k)))
end

local function setOrderDict(t, k, v)
  local i = getOrderDictIndex(t, k)
  if i >= 0 then
    t[i + 1][2] = v
  else
    tinsert(t, bnot(i) + 1, setmetatable({ k, v }, t.__genericT__))
    versions[t] = (versions[t] or 0) + 1
  end
end

local function getViewBetweenOrder(t, lowerValue, upperValue)
  local comparer = t.comparer
  if comparer:Compare(lowerValue, upperValue) > 0 then
    throw(ArgumentException("lowerBound is greater than upperBound"))
  end
  local n = #t
  local i = binarySearch(t, lowerValue, comparer)
  if i < 0 then i = bnot(i) end
  local set = { comparer = comparer }
  if i < n then
    local j = binarySearch(t, upperValue, comparer)
    if j < 0 then j = bnot(j) - 1 end
    if i <= j then
      tmove(t, i + 1, j + 1, 1, set)
    end
  end
  return setmetatable(set, System.SortedSet(t.__genericT__))
end

local function heapDown(t, k, n, c)
  local j
  while true do
    j = k * 2
    if j <= n and j > 0 then
      if j < n and c(t[j], t[j + 1]) > 0 then
        j = j + 1
      end
      if c(t[k], t[j]) <= 0 then
        break
      end
      t[j], t[k] = t[k], t[j]
      k = j
    else
      break
    end
  end
end

local function heapUp(t, k, n, c)
  while k > 1 do
    local j = div(k, 2)
    if c(t[j], t[k]) <= 0 then
      break
    end
    t[j], t[k] = t[k], t[j]
    k = j
  end
end

local function heapify(t, c)
  local n = #t
  for i = div(n, 2), 1, -1 do
    heapDown(t, i, n, c)  
  end
end

local function heapAdd(t, v, c)
  local n = #t + 1
  t[n] = v
  heapUp(t, n, n, c)
end

local function heapPop(t, c)
  local n = #t
  if n == 0 then return end
  local v = t[1]
  t[1] = t[n]
  t[n] = nil
  heapDown(t, 1, n - 1, c)
  return v
end

local SortedSetEqualityComparerFn
local SortedSetEqualityComparer = {
  __ctor__ = function (this, equalityComparer, comparer)
    local T = this.__genericT__
    this.comparer = comparer or Comparer_1(T).getDefault()
    this.equalityComparer = equalityComparer or EqualityComparer(T).getDefault()
  end,
  EqualsOf = function (this, x, y)
    if x == nil then return y == nil end
    if y == nil then return false end
    return equalsOrder(x, y)
  end,
  GetHashCodeOf = function (this, set)
    local hashCode = 0
    if set ~= nil then
      for i = 1, #set do
        local v = set[i]
        if v == null then v = nil end
        hashCode = System.xor(hashCode, System.band(this.equalityComparer:GetHashCodeOf(v), 0x7FFFFFFF))
      end
    end
    return hashCode
  end,
  EqualsObj = function (this, obj)
    if System.is(obj, SortedSetEqualityComparerFn(this.__genericT__)) then
      return this.comparer == obj.comparer
    end
    return false
  end,
  GetHashCode = function (this)
    return System.xor(this.comparer:GetHashCode(), this.equalityComparer:GetHashCode())
  end
}

SortedSetEqualityComparerFn = define("System.SortedSetEqualityComparer", function (T)
  return {
    base = { System.IEqualityComparer_1(T) },
    __genericT__ = T
  }
end, SortedSetEqualityComparer, 1)

local ArrayEnumerator = define("System.ArrayEnumerator", function (T)
  return {
    base = { IEnumerator_1(T) }
  }
end, {
  getCurrent = System.getCurrent, 
  Dispose = System.emptyFn,
  Reset = function (this)
    this.index = 1
    this.current = nil
  end,
  MoveNext = function (this)
    local t = this.list
    if this.version ~= versions[t] then
      throwFailedVersion()
    end
    local index = this.index
    local v = t[index]
    if v ~= nil then
      if v == null then
        this.current = nil
      else
        this.current = v
      end
      this.index = index + 1
      return true
    end
    this.current = nil
    return false
  end
}, 1)

arrayEnumerator = function (t, T)
  if not T then T = t.__genericT__ end
  return setmetatable({ list = t, index = 1, version = versions[t], currnet = T:default() }, ArrayEnumerator(T))
end

local ArrayReverseEnumerable 

local function reverseEnumerator(t)
  local T = t.__genericT__
  return setmetatable({ list = t, index = #t, version = versions[t], currnet = T:default() }, ArrayReverseEnumerable(T))
end

ArrayReverseEnumerable = define("System.ArrayReverseEnumerable", function (T)
  return {
    base = { IEnumerable_1(T), IEnumerator_1(T) }
  }
end, {
  getCurrent = System.getCurrent, 
  Dispose = System.emptyFn,
  GetEnumerator = function (this)
    return reverseEnumerator(this.list)
  end,
  Reset = function (this)
    this.index = #this.list
    this.current = nil
  end,
  MoveNext = function (this)
    local t = this.list
    if this.version ~= versions[t] then
      throwFailedVersion()
    end
    local index = this.index
    local v = t[index]
    if v ~= nil then
      if v == null then
        this.current = nil
      else
        this.current = v
      end
      this.index = index - 1
      return true
    end
    this.current = nil
    return false
  end
}, 1)

local function reverseEnumerable(t)
  return setmetatable({ list = t }, ArrayReverseEnumerable(t.__genericT__))
end

local function checkArrayIndex(index1, index2)
  if index2 then
    throw(ArgumentException("Indices length does not match the array rank."))
  elseif type(index1) == "table" then
    if #index1 ~= 1 then
      throw(ArgumentException("Indices length does not match the array rank."))
    else
      index1 = index1[1]
    end
  end
  return index1
end

Array = {
  version = 0,
  new = buildArray,
  set = set,
  get = get,
  setCapacity = function (t, len)
    if len < #t then throw(ArgumentOutOfRangeException("Value", er.ArgumentOutOfRange_SmallCapacity())) end
  end,
  ctorList = function (t, ...)
    local n = select("#", ...)
    if n == 0 then return end
    local collection = ...
    if type(collection) == "number" then return end
    addRange(t, collection)
  end,
  ctorOrderSet = function(t, ...)
    local n = select("#", ...)
    if n == 0 then
      t.comparer = Comparer_1(t.__genericT__).getDefault()
    else
      local collection, comparer = ...
      if collection == nil then throw(ArgumentNullException("collection")) end
      t.comparer = comparer or Comparer_1(t.__genericT__).getDefault()
      if collection then
        addOrderRange(t, collection)
      end
    end
  end,
  ctorOrderDict = function (t, ...)
    local n = select("#", ...)
    local dictionary, comparer
    if n ~= 0 then
      dictionary, comparer = ...
      if dictionary == nil then throw(ArgumentNullException("dictionary")) end
    end
    if comparer == nil then comparer = Comparer_1(t.__genericT__).getDefault() end
    local c = comparer.Compare
    local keyComparer = function (_, p, v)
      return c(comparer, p[1], v)
    end
    t.comparer, t.keyComparer = comparer, keyComparer
    if type(dictionary) == "table" then
      local T = t.__genericT__
      for _, p in each(dictionary) do
        local k, v = p[1], p[2]
        addOrderDict(t, k, v, keyComparer, T)
      end
    end
  end,
  add = add,
  addObj = function (this, item)
    if not System.is(item, this.__genericT__) then
      throw(ArgumentException())
    end
    return add(this, item)
  end,
  addRange = addRange,
  addOrder = function (t, v)
    local success = addOrder(t, v, t.comparer)
    if success then
      versions[t] = (versions[t] or 0) + 1
    end
    return success
  end,
  addOrderRange = addOrderRange,
  addOrderDict = function (t, k, v)
    if k == nil then throw(ArgumentNullException("key")) end
    addOrderDict(t, k, v, t.keyComparer, t.__genericT__, true)
  end,
  addPairOrderDict = function (t, ...)
    local k, v
    if select("#", ...) == 1 then
      local pair = ... 
      k, v = pair[1], pair[2]
    else
      k, v = ...
    end
    if k == nil then throw(ArgumentNullException("key")) end
    addOrderDict(t, k ,v, t.keyComparer, t.__genericT__, true)
  end,
  addOrderDictObj = function (t, k, v)
    checkOrderDictKeyValueObj(t, k, v)
    addOrderDict(t, k ,v, t.keyComparer, t.__genericT__, true)
  end,
  AsReadOnly = function (t)
    return System.ReadOnlyCollection(t.__genericT__)(t)
  end,
  clear = clear,
  containsOrder = function (t, v)
    return binarySearch(t, v, t.comparer) >= 0
  end,
  containsOrderDict = function (t, k)
    return getOrderDictIndex(t, k) >= 0
  end,
  containsOrderDictObj = function (t, k)
    return getOrderDictIndex(t, k, true) >= 0
  end,
  createSetComparer = function (T, equalityComparer)
    return SortedSetEqualityComparerFn(T)(equalityComparer)
  end,
  exceptWithOrder = exceptWithOrder,
  findAll = function (t, match)
    return setmetatable(findAll(t, match), System.List(t.__genericT__))
  end,
  first = first,
  firstOrDefault = function (t)
    local v = t[1]
    if v == nil then
      return t.__genericT__:default()
    elseif v == null then
      return nil
    else
      return v
    end
  end,
  insert = function (t, index, v)
    if index < 0 or index > #t then
      throw(ArgumentOutOfRangeException("index"))
    end
    tinsert(t, index + 1, v == nil and null or v)
    versions[t] = (versions[t] or 0) + 1
  end,
  insertRange = function (t, index, collection) 
    if collection == nil then throw(ArgumentNullException("collection")) end
    local len = #t
    if index < 0 or index > len then
      throw(ArgumentOutOfRangeException("index"))
    end
    if t.GetEnumerator == arrayEnumerator then
      local count = #collection
      if count > 0 then
        if index < len then
          tmove(t, index + 1, len, index + 1 + count, t)
        end
        if t == collection then
          tmove(t, 1, index, index + 1, t)
          tmove(t, index + 1 + count, count * 2, index * 2 + 1, t)
        else
          tmove(collection, 1, count, index + 1, t)
        end
      end
    else
      for _, v in each(collection) do
        index = index + 1
        tinsert(t, index, v == nil and null or v)
      end
    end
    versions[t] = (versions[t] or 0) + 1
  end,
  getViewBetweenOrder = getViewBetweenOrder,
  getOrderComparer = function (t) return t.comparer end,
  intersectWithOrder = intersectWithOrder,
  isProperSubsetOfOrder = isProperSubsetOfOrder,
  isProperSupersetOfOrder = isProperSupersetOfOrder,
  isSubsetOfOrder = isSubsetOfOrder,
  isSupersetOfOrder = isSupersetOfOrder,
  isOverlapsOrder = isOverlapsOrder,
  equalsOrder = equalsOrder,
  symmetricExceptWithOrder = symmetricExceptWithOrder,
  heapDown = heapDown,
  heapUp = heapUp,
  heapify = heapify,
  heapAdd = heapAdd,
  heapPop = heapPop,
  last = last,
  lastOrDefault = function (t)
    local n = #t
    local v = t[n]
    if v == nil then
      return t.__genericT__:default()
    elseif v == null then
      return nil
    else
      return v
    end
  end,
  popFirst = function (t)
    if #t == 0 then throw(InvalidOperationException()) end
    local v = t[1]
    tremove(t, 1)
    versions[t] = (versions[t] or 0) + 1
    if v ~= null then
      return v
    end
    return nil
  end,
  popLast = function (t)
    local n = #t
    if n == 0 then throw(InvalidOperationException()) end
    local v = t[n]
    t[n] = nil
    if v ~= null then
      return v
    end
    return nil
  end,
  removeRange = removeRange,
  remove = function (t, v)
    local index = indexOf(t, v)
    if index >= 0 then
      tremove(t, index + 1)
      versions[t] = (versions[t] or 0) + 1
      return true
    end
    return false
  end,
  removeAll = function (t, match)
    if match == nil then throw(ArgumentNullException("match")) end
    local size = #t
    local freeIndex = 1
    while freeIndex <= size do
      local item = t[freeIndex]
      if item == null then  item = nil end
      if match(item) then
        break
      end
      freeIndex = freeIndex + 1 
    end
    if freeIndex > size then return 0 end
  
    local current = freeIndex + 1
    while current <= size do 
      while current <= size do
        local item = t[current]
        if item == null then item = nil end
        if not match(item) then
          break
        end
        current = current + 1 
      end
      if current <= size then
        t[freeIndex] = t[current]
        freeIndex = freeIndex + 1
        current = current + 1
      end
    end
    freeIndex = freeIndex -1
    local count = size - freeIndex
    removeRange(t, freeIndex, count)
    return count
  end,
  removeAt = function (t, index)
    index = index + 1
    if t[index] == nil then throw(ArgumentOutOfRangeException("index"))  end
    tremove(t, index)
    versions[t] = (versions[t] or 0) + 1
  end,
  removeOrder = function (t, v)
    local i = binarySearch(t, v, t.comparer)
    if i >= 0 then
      tremove(t, i + 1)
      versions[t] = (versions[t] or 0) + 1
      return true
    end
    return false
  end,
  removeOrderDict = function (t, k)
    local i = getOrderDictIndex(t, k)
    if i >= 0 then
      tremove(t, i + 1)
      versions[t] = (versions[t] or 0) + 1
      return true
    end
    return false
  end,
  removePairOrderDict = function (t, p)
    local i = getOrderDictIndex(t, p[1])
    if i >= 0 then
      local v = t[i + 1][2]
      local comparer = EqualityComparer(this.__genericTValue__).getDefault()
      if comparer:EqualsOf(p[2], v) then
        tremove(this, i)
        return true
      end
    end
    return false
  end,
  tryGetValueOrder = tryGetValueOrder,
  tryGetValueOrderDict = function (t, k)
    local i = getOrderDictIndex(t, k)
    if i >= 0 then
      local p = t[i + 1]
      return true, p[2]
    end
    return false, t.__genericTValue__:default()
  end,
  getRange = function (t, index, count)
    if count < 0 or index > #t - count then
      throw(ArgumentOutOfRangeException("index or count"))
    end
    local list = {}
    tmove(t, index + 1, index + count, 1, list)
    return setmetatable(list, System.List(t.__genericT__))
  end,
  getOrderDict = getOrderDict,
  getOrderDictObj = function (t, k)
    return getOrderDict(t, k, true)
  end,
  setOrderDict = setOrderDict,
  setOrderDictObj = function (t, k, v)
    checkOrderDictKeyValueObj(t, k, v)
    setOrderDict(t, k, v)
  end,
  indexKeyOrderDict = function (t, k)
    local i = getOrderDictIndex(t, k)
    if i < 0 then i = -1 end
    return i
  end, 
  indexOfValue = function (t, v)
    local len = #t
    if len > 0 then
      local comparer = EqualityComparer(t.__genericTValue__).getDefault()
      local equals = comparer.EqualsOf
      for i = 1, len do
        if equals(comparer, v, t[i][2]) then
          return i - 1
        end
      end
    end
    return -1
  end,
  reverseEnumerator = reverseEnumerator,
  reverseEnumerable = reverseEnumerable,
  getCount = lengthFn,
  getSyncRoot = System.identityFn,
  getLongLength = lengthFn,
  getLength = lengthFn,
  getIsSynchronized = falseFn,
  getIsReadOnly = falseFn,
  getIsFixedSize = trueFn,
  getRank = System.oneFn,
  Add = unset,
  Clear = unset,
  Insert = unset,
  Remove = unset,
  RemoveAt = unset,
  BinarySearch = binarySearch,
  ClearArray = function (t, index, length)
    if t == nil then throw(ArgumentNullException("array")) end
    if index < 0 or length < 0 or index + length > #t then
      throw(IndexOutOfRangeException())
    end
    local default = t.__genericT__:default()
    if default == nil then default = null end
    fill(t, index + 1, index + length, default)
  end,
  Contains = function (t, v)
    return indexOf(t, v) ~= -1
  end,
  Copy = function (t, ...)
    local len = select("#", ...)     
    if len == 2 then
      local array, length = ...
      copy(t, 0, array, 0, length)
    else 
      copy(t, ...)
    end
  end,
  CreateInstance = function (elementType, length)
    return buildArray(Array(elementType[1]), length)
  end,
  Empty = function (T)
    local t = emptys[T]
    if t == nil then
      t = Array(T){}
      emptys[T] = t
    end
    return t
  end,
  Exists = function (t, match)
    return findIndex(t, match) ~= -1
  end,
  Fill = function (t, value, startIndex, count)
    if t == nil then throw(ArgumentNullException("array")) end
    local len = #t
    if not startIndex then
      startIndex, count = 0, len
    else
      if startIndex < 0 or startIndex > len then
        throw(ArgumentOutOfRangeException("startIndex"))
      end
      if count < 0 or count > len - startIndex then
        throw(ArgumentOutOfRangeException("count"))
      end
    end
    fill(t, startIndex + 1, startIndex + count, value)
  end,
  Find = function (t, match)
    if t == nil then throw(ArgumentNullException("array")) end
    if match == nil then throw(ArgumentNullException("match")) end
    for i = 1, #t do
      local item = t[i]
      if item == null then item = nil end
      if match(item) then
        return item
      end
    end
    return t.__genericT__:default()
  end,
  FindAll = function (t, match)
    return setmetatable(findAll(t, match), Array(t.__genericT__))
  end,
  FindIndex = findIndex,
  FindLast = function (t, match)
    if t == nil then throw(ArgumentNullException("array")) end
    if match == nil then throw(ArgumentNullException("match")) end
    for i = #t, 1, -1 do
      local item = t[i]
      if item == null then item = nil end
      if match(item) then
        return item
      end
    end
    return t.__genericT__:default()
  end,
  FindLastIndex = function (t, startIndex, count, match)
    if t == nil then throw(ArgumentNullException("array")) end
    local len = #t
    if not count then
      startIndex, count, match = len - 1, len, startIndex
    elseif not match then
      count, match = startIndex + 1, count
    end
    if match == nil then throw(ArgumentNullException("match")) end
    if count < 0 or startIndex - count + 1 < 0 then
      throw(ArgumentOutOfRangeException("count"))
    end
    local endIndex = startIndex - count + 1
    for i = startIndex + 1, endIndex + 1, -1 do
      local item = t[i]
      if item == null then
        item = nil
      end
      if match(item) then
        return i - 1
      end
    end
    return -1
  end,
  ForEach = function (t, action)
    if action == nil then throw(ArgumentNullException("action")) end
    for i = 1, #t do
      local item = t[i]
      if item == null then item = nil end
      action(item)
    end
  end,
  IndexOf = indexOf,
  LastIndexOf = function (t, value, startIndex, count)
    if t == nil then throw(ArgumentNullException("array")) end
    local len = #t
    if not startIndex then
      startIndex, count = len - 1, len
    elseif not count then
      count = len == 0 and 0 or (startIndex + 1)
    end
    if len == 0 then
      if startIndex ~= -1 and startIndex ~= 0 then
        throw(ArgumentOutOfRangeException("startIndex"))
      end
      if count ~= 0 then
        throw(ArgumentOutOfRangeException("count"))
      end
    end
    if startIndex < 0 or startIndex >= len then
      throw(ArgumentOutOfRangeException("startIndex"))
    end
    if count < 0 or startIndex - count + 1 < 0 then
      throw(ArgumentOutOfRangeException("count"))
    end
    local comparer = EqualityComparer(t.__genericT__).getDefault()
    local equals = comparer.EqualsOf
    local endIndex = startIndex - count + 1
    for i = startIndex + 1, endIndex + 1, -1 do
      local item = t[i]
      if item == null then item = nil end
      if equals(comparer, item, value) then
        return i - 1
      end
    end
    return -1
  end,
  Resize = function (t, newSize, T)
    if newSize < 0 then throw(ArgumentOutOfRangeException("newSize")) end
    if t == nil then
      return buildArray(Array(T), newSize)
    end
    local len = #t
    if len > newSize then
      fill(t, newSize + 1, len, nil)
    elseif len < newSize then
      local default = t.__genericT__:default()
      if default == nil then default = null end
      fill(t, len + 1, newSize, default)
    end
    return t
  end,
  Reverse = function (t, index, count)
    if not index then
      index = 0
      count = #t
    else
      if count < 0 or index > #t - count then
        throw(ArgumentOutOfRangeException("index or count"))
      end
    end
    local i, j = index + 1, index + count
    while i < j do
      t[i], t[j] = t[j], t[i]
      i = i + 1
      j = j - 1
    end
    versions[t] = (versions[t] or 0) + 1
  end,
  Sort = function (t, ...)
    if t == nil then throw(ArgumentNullException("array")) end
    local len = select("#", ...)
    if len == 0 then
      sort(t)
    elseif len == 1 then
      local comparer = ...
      sort(t, comparer)
    else
      local index, count, comparer = ...
      if count > 1 then
        local comp = getSortComp(t, comparer)
        if index == 0 and count == #t then
          tsort(t, comp)
        else
          checkIndexAndCount(t, index, count)
          local arr = {}
          tmove(t, index + 1, index + count, 1, arr)
          tsort(arr, comp)
          tmove(arr, 1, count, index + 1, t)
        end
        versions[t] = (versions[t] or 0) + 1
      end
    end
  end,
  toArray = function (t)
    local array = {}    
    if t.GetEnumerator == arrayEnumerator then
      tmove(t, 1, #t, 1, array)
    else
      local count = 1
      for _, v in each(t) do
        array[count] = v == nil and null or v
        count = count + 1
      end
    end
    return arrayFromTable(array, t.__genericT__)
  end,
  TrueForAll = function (t, match)
    if t == nil then throw(ArgumentNullException("array")) end
    if match == nil then throw(ArgumentNullException("match")) end
    for i = 1, #t do
      local item = t[i]
      if item == null then item = nil end
      if not match(item) then
        return false
      end
    end
    return true
  end,
  Clone = function (this)
    local t = setmetatable({}, getmetatable(this))
    tmove(this, 1, #this, 1, t)
    return t
  end,
  CopyTo = function (t, ...)
    local n = select("#", ...)
    local sourceIndex, array, arrayIndex, len
    if n == 1 then
      sourceIndex, arrayIndex, len, array = 0, 0, #t, ...
      checkIndexAndCount(array, 0, len)
    elseif n == 2 then
      sourceIndex, len, array, arrayIndex = 0, #t, ...
      checkIndexAndCount(array, arrayIndex, len)
    elseif n == 3 then
      sourceIndex, array, arrayIndex, len = 0, ...
      checkIndexAndCount(t, sourceIndex, len)
      checkIndexAndCount(array, arrayIndex, len)
    else
      sourceIndex, array, arrayIndex, len = ...
      checkIndexAndCount(t, sourceIndex, len)
      checkIndexAndCount(array, arrayIndex, len)
    end

    local T = t.__genericT__
    if T.class == "S" then
      local default = T:default()
      if type(default) == "table" then
        for i = 1, len do
          array[arrayIndex + i] = t[sourceIndex + i]:__clone__()
        end
        return
      end
    end

    tmove(t, sourceIndex + 1, sourceIndex + len, arrayIndex + 1, array)
  end,
  GetEnumerator = arrayEnumerator,
  GetLength = function (this, dimension)
    if dimension ~= 0 then throw(IndexOutOfRangeException()) end
    return #this
  end,
  GetLowerBound = function (this, dimension)
    if dimension ~= 0 then throw(IndexOutOfRangeException()) end
    return 0
  end,
  GetUpperBound = function (this, dimension)
    if dimension ~= 0 then throw(IndexOutOfRangeException()) end
    return #this - 1
  end,
  GetValue = function (this, index1, index2)
    if index1 == nil then throw(ArgumentNullException("indices")) end
    return get(this, checkArrayIndex(index1, index2))
  end,
  SetValue = function (this, value, index1, index2)
    if index1 == nil then throw(ArgumentNullException("indices")) end
    set(this, checkArrayIndex(index1, index2), System.castWithNullable(this.__genericT__, value))
  end,
  Clone = function (this)
    local array = {}
    tmove(this, 1, #this, 1, array)
    return arrayFromTable(array, this.__genericT__)
  end
}

function Array.__call(ArrayT, n, t)
  if type(n) == "table" then
    t = n
  elseif t ~= nil then
    for i = 1, n  do
      if t[i] == nil then
        t[i] = null
      end
    end
  else
    t = {}
    if n > 0 then
      local T = ArrayT.__genericT__
      local default = T:default()
      if default == nil then
        fill(t, 1, n, null)
      elseif type(default) ~= "table" then
        fill(t, 1, n, default)
      else
        for i = 1, n do
          t[i] = T:default()
        end
      end
    end
  end
  return setmetatable(t, ArrayT)
end

function System.arrayFromList(t)
  return setmetatable(t, Array(t.__genericT__))
end

arrayFromTable = function (t, T, readOnly)
  assert(T)
  local array = setmetatable(t, Array(T))
  if readOnly then
    array.set = unset
  end
  return array
end

System.arrayFromTable = arrayFromTable

local function getIndex(t, ...)
  local rank = t.__rank__
  local id = 0
  local len = #rank
  for i = 1, len do
    id = id * rank[i] + select(i, ...)
  end
  return id, len
end

local function checkMultiArrayIndex(t, index1, ...)
  if index1 == nil then throw(ArgumentNullException("indices")) end
  local rank = t.__rank__
  local len = #rank
  if type(index1) == "table" then
    if #index1 ~= len then
      throw(ArgumentException("Indices length does not match the array rank."))
    end
    local id = 0
    for i = 1, len do
      id = id * rank[i] + index1[i]
    end
    return id
  elseif len ~= select("#", ...) + 1 then
    throw(ArgumentException("Indices length does not match the array rank."))
  end
  return getIndex(t, index1, ...)
end

local MultiArray = { 
  set = function (this, ...)
    local index, len = getIndex(this, ...)
    set(this, index, select(len + 1, ...))
  end,
  get = function (this, ...)
    local index = getIndex(this, ...)
    return get(this, index)
  end,
  getRank = function (this)
    return #this.__rank__
  end,
  GetLength = function (this, dimension)
    local rank = this.__rank__
    if dimension < 0 or dimension >= #rank then throw(IndexOutOfRangeException()) end
    return rank[dimension + 1]
  end,
  GetLowerBound = function (this, dimension)
    local rank = this.__rank__
    if dimension < 0 or dimension >= #rank then throw(IndexOutOfRangeException()) end
    return 0
  end,
  GetUpperBound = function (this, dimension)
    local rank = this.__rank__
    if dimension < 0 or dimension >= #rank then throw(IndexOutOfRangeException()) end
    return rank[dimension + 1] - 1
  end,
  GetValue = function (this, ...)
    return get(this, checkMultiArrayIndex(this, ...))
  end,
  SetValue = function (this, value, ...)
    set(this, checkMultiArrayIndex(this, ...), System.castWithNullable(this.__genericT__, value))
  end,
  Clone = function (this)
    local array = { __rank__ = this.__rank__ }
    tmove(this, 1, #this, 1, array)
    return arrayFromTable(array, this.__genericT__)
  end
}

function MultiArray.__call(T, rank, t)
  local len = 1
  for i = 1, #rank do
    len = len * rank[i]
  end
  t = buildArray(T, len, t)
  t.__rank__ = rank
  return t
end

System.defArray("System.Array", function(T) 
  return { 
    base = { System.ICloneable, System.IList_1(T), System.IReadOnlyList_1(T), System.IList }, 
    __genericT__ = T
  }
end, Array, MultiArray)

local cpool = {}
local function createCoroutine(f)
  local c = tremove(cpool)
  if c == nil then
    c = ccreate(function (...)
      f(...)
      while true do
        f = nil
        cpool[#cpool + 1] = c
        f = cyield(cpool)
        f(cyield())
      end
    end)
  else
    cresume(c, f)
  end
  return c
end

System.ccreate = createCoroutine
System.cpool = cpool
System.cresume = cresume
System.yield = cyield

local YieldEnumerable
YieldEnumerable = define("System.YieldEnumerable", function (T)
  return {
    base = { IEnumerable_1(T), IEnumerator_1(T), System.IDisposable },
    __genericT__ = T
  }
end, {
  getCurrent = System.getCurrent, 
  Dispose = System.emptyFn,
  GetEnumerator = function (this)
    return setmetatable({ f = this.f, args = this.args }, YieldEnumerable(this.__genericT__))
  end,
  MoveNext = function (this)
    local c = this.c
    if c == false then
      return false
    end
  
    local ok, v
    if c == nil then
      c = createCoroutine(this.f)
      this.c = c
      local args = this.args
      ok, v = cresume(c, unpack(args, 1, args.n))
      this.args = nil
    else
      ok, v = cresume(c)
    end
  
    if ok then
      if v == cpool then
        this.c = false
        this.current = nil
        return false
      else
        this.current = v
        return true
      end
    else
      error(v)
    end
  end
}, 1)

local function yieldIEnumerable(f, T, ...)
  return setmetatable({ f = f, args = pack(...) }, YieldEnumerable(T))
end

System.yieldIEnumerable = yieldIEnumerable
System.yieldIEnumerator = yieldIEnumerable

local ReadOnlyCollection = {
  __ctor__ = function (this, list)
    if not list then throw(ArgumentNullException("list")) end
    this.list = list
  end,
  getCount = function (this)
    return #this.list
  end,
  get = function (this, index)
    return this.list:get(index)
  end,
  Contains = function (this, value)
    return this.list:Contains(value)
  end,
  GetEnumerator = function (this)
    return this.list:GetEnumerator()
  end,
  CopyTo = function (this, array, index)
    this.list:CopyTo(array, index)
  end,
  IndexOf = function (this, value)
    return this.list:IndexOf(value)
  end,
  getIsSynchronized = falseFn,
  getIsReadOnly = trueFn,
  getIsFixedSize = trueFn,
}

define("System.ReadOnlyCollection", function (T)
  return { 
    base = { System.IList_1(T), System.IList, System.IReadOnlyList_1(T) }, 
    __genericT__ = T
  }
end, ReadOnlyCollection, 1)
end

-- CoreSystemLib: Type.lua
do
local System = System
local throw = System.throw
local Object = System.Object
local Boolean = System.Boolean
local Delegate = System.Delegate
local getClass = System.getClass
local getGenericClass = System.getGenericClass
local arrayFromTable = System.arrayFromTable

local InvalidCastException = System.InvalidCastException
local ArgumentNullException = System.ArgumentNullException
local MissingMethodException = System.MissingMethodException
local TypeLoadException = System.TypeLoadException
local NullReferenceException = System.NullReferenceException

local Char = System.Char
local SByte = System.SByte
local Byte = System.Byte
local Int16 = System.Int16
local UInt16 = System.UInt16
local Int32 = System.Int32
local UInt32 = System.UInt32
local Int64 = System.Int64
local UInt64 = System.UInt64
local Single = System.Single
local Double = System.Double
local Int = System.Int
local Number = System.Number
local ValueType = System.ValueType

local assert = assert
local type = type
local setmetatable = setmetatable
local getmetatable = getmetatable
local select = select
local unpack = table.unpack
local floor = math.floor

local Type, typeof

local function isGenericName(name)
  return name:find('`') ~= nil
end

local function getBaseType(this)
  local baseType = this.baseType
  if baseType == nil then
    local baseCls = getmetatable(this[1])
    if baseCls ~= nil then
      baseType = typeof(baseCls)
      this.baseType = baseType
    end
  end
  return baseType
end

local function isSubclassOf(this, c)
  local p = this
  if p == c then
    return false
  end
  while p ~= nil do
    if p == c then
      return true
    end
    p = getmetatable(p)
  end
  return false
end

local function getIsInterface(this)
  return this[1].class == "I"
end

local function fillInterfaces(t, cls, set)
  local base = getmetatable(cls)
  if base then
    fillInterfaces(t, base, set)
  end
  local interface = cls.interface
  if interface then
    for i = 1, #interface do
      local it = interface[i]
      if not set[it] then
        t[#t + 1] = typeof(it)
        set[it] = true
      end
      fillInterfaces(t, it, set)
    end
  end
end

local function getInterfaces(this)
  local t = this.interfaces
  if t == nil then
    t = arrayFromTable({}, Type, true)
    fillInterfaces(t, this[1], {})
    this.interfaces = t
  end
  return t
end

local function implementInterface(this, ifaceType)
  local t = this
  while t ~= nil do
    local interfaces = getInterfaces(this)
    if interfaces ~= nil then
      for i = 1, #interfaces do
        local it = interfaces[i]
        if it == ifaceType or implementInterface(it, ifaceType) then
          return true
        end
      end
    end
    t = getBaseType(t)
  end
  return false
end

local function isAssignableFrom(this, c)
  if c == nil then 
    return false 
  end
  if this == c then 
    return true
  end
  local left, right = this[1], c[1]
  if left == Object then
    return true
  end

  if isSubclassOf(right, left) then
    return true
  end

  if left.class == "I" then
    return implementInterface(c, this)
  end

  return false
end

local function isGenericTypeDefinition(this)
  local cls = this[1]
  return getGenericClass(cls) == cls
end

local function getIsArray(this)
  return this[1].__name__:byte(-2) == 91
end

Type = System.define("System.Type", {
  Equals = System.equals,
  getIsGenericType = function (this)
    return isGenericName(this[1].__name__)
  end,
  getContainsGenericParameters = function (this)
    return isGenericName(this[1].__name__)
  end,
  getIsGenericTypeDefinition = isGenericTypeDefinition,
  GetGenericTypeDefinition = function (this)
    local genericClass = getGenericClass(this[1])
    if genericClass then
      return typeof(genericClass)
    end
    throw(System.InvalidOperationException())
  end,
  MakeGenericType = function (this, ...)
    local args = { ... }
    for i = 1, #args do
      args[i] = args[i][1]
    end
    return typeof(this[1](unpack(args)))
  end,
  getIsEnum = function (this)
    return this[1].class == "E"
  end,
  getIsClass = function (this)
    return this[1].class == "C"
  end,
  getIsValueType = function (this)
    return this[1].class == "S" 
  end,
  getName = function (this)
    local name = this.name
    if name == nil then
      local clsName = this[1].__name__
      local pattern = isGenericName(clsName) and "^.*()%.(.*)%[.+%]$" or "^.*()%.(.*)$"
      name = clsName:gsub(pattern, "%2")
      this.name = name
    end
    return name
  end,
  getFullName = function (this)
    return this[1].__name__
  end,
  getNamespace = function (this)
    local namespace = this.namespace
    if namespace == nil then
      local clsName = this[1].__name__
      local pattern = isGenericName(clsName) and "^(.*)()%..*%[.+%]$" or "^(.*)()%..*$"
      namespace = clsName:gsub(pattern, "%1")
      this.namespace = namespace
    end
    return namespace
  end,
  getBaseType = function (this)
    local cls = this[1]
    if cls.class ~= "I" and cls ~= Object then
      while true do
        local base = getmetatable(cls)
        if not base then
          break
        end
        if base.__index == base then
          return typeof(base)
        end
        cls = base
      end
    end
    return nil
  end,
  IsSubclassOf = function (this, c)
    return isSubclassOf(this[1], c[1])
  end,
  getIsInterface = getIsInterface,
  GetInterfaces = getInterfaces,
  IsAssignableFrom = isAssignableFrom,
  IsInstanceOfType = function (this, obj)
    if obj == nil then
      return false 
    end
    return isAssignableFrom(this, obj:GetType())
  end,
  getIsArray = getIsArray,
  GetElementType = function (this)
    if getIsArray(this) then
      return typeof(this[1].__genericT__)
    end
    return nil
  end,
  ToString = function (this)
    return this[1].__name__
  end,
  GetTypeFrom = function (typeName, throwOnError, ignoreCase)
    if typeName == nil then
      throw(ArgumentNullException("typeName"))
    end
    if #typeName == 0 then
      if throwOnError then
        throw(TypeLoadException("Arg_TypeLoadNullStr"))
      end
      return nil
    end
    assert(not ignoreCase, "ignoreCase is not support")
    local cls = getClass(typeName)
    if cls ~= nil then
      return typeof(cls)
    end
    if throwOnError then
      throw(TypeLoadException(typeName .. ": failed to load."))
    end
    return nil
  end
})

local NumberType = {
  __index = Type,
  __eq = function (a, b)
    local c1, c2 = a[1], b[1]
    if c1 == c2 then
      return true
    end
    if c1 == Number or c2 == Number then
      return true
    end
    return false
  end
}

local function newNumberType(c)
  return setmetatable({ c }, NumberType)
end

local types = {
  [Char] = newNumberType(Char),
  [SByte] = newNumberType(SByte),
  [Byte] = newNumberType(Byte),
  [Int16] = newNumberType(Int16),
  [UInt16] = newNumberType(UInt16),
  [Int32] = newNumberType(Int32),
  [UInt32] = newNumberType(UInt32),
  [Int64] = newNumberType(Int64),
  [UInt64] = newNumberType(UInt64),
  [Single] = newNumberType(Single),
  [Double] = newNumberType(Double),
  [Int] = newNumberType(Int),
  [Number] = newNumberType(Number),
}

local customTypeof = System.config.customTypeof

function typeof(cls)
  assert(cls)
  local t = types[cls]
  if t == nil then
    if customTypeof then
      t = customTypeof(cls)
      if t then
        types[cls] = t
        return t
      end
    end
    t = setmetatable({ cls }, Type)
    types[cls] = t
  end
  return t
end

local function getType(obj)
  return typeof(getmetatable(obj))
end

System.typeof = typeof
System.Object.GetType = getType

local function addCheckInterface(set, cls)
  local interface = cls.interface
  if interface then
    for i = 1, #interface do
      local it = interface[i]
      set[it] = true
      addCheckInterface(set, it)
    end
  end
end

local function getCheckSet(cls)
  local set = {}
  local p = cls
  repeat
    set[p] = true
    addCheckInterface(set, p)
    p = getmetatable(p)
  until not p
  return set
end

local customTypeCheck = System.config.customTypeCheck

local checks = setmetatable({}, {
  __index = function (checks, cls)
    if customTypeCheck then
      local f, add = customTypeCheck(cls)
      if f then
        if add then
          checks[cls] = f
        end
        return f
      end
    end

    local set = getCheckSet(cls)
    local function check(obj, T)
      return set[T] == true
    end
    checks[cls] = check
    return check
  end
})

checks[Number] = function (obj, T)
  local set = getCheckSet(Number)
  local numbers = {
    [Char] = function (obj) return type(obj) == "number" and obj >= 0 and obj <= 65535 and floor(obj) == obj end,
    [SByte] = function (obj) return type(obj) == "number" and obj >= -128 and obj <= 127 and floor(obj) == obj end,
    [Byte] = function (obj) return type(obj) == "number" and obj >= 0 and obj <= 255 and floor(obj) == obj end,
    [Int16] = function (obj) return type(obj) == "number" and obj >= -32768 and obj <= 32767 and floor(obj) == obj end,
    [UInt16] = function (obj) return type(obj) == "number" and obj >= 0 and obj <= 32767 and floor(obj) == obj end,
    [Int32] = function (obj) return type(obj) == "number" and obj >= -2147483648 and obj <= 2147483647 and floor(obj) == obj end,
    [UInt32] = function (obj) return type(obj) == "number" and obj >= 0 and obj <= 4294967295 and floor(obj) == obj end,
    [Int64] = function (obj) return type(obj) == "number" and obj >= (-9223372036854775807 - 1) and obj <= 9223372036854775807 and floor(obj) == obj end,
    [UInt64] = function (obj) return type(obj) == "number" and obj >= 0 and obj <= 18446744073709551615 and floor(obj) == obj end,
    [Single] = function (obj) return type(obj) == "number" and obj >= -3.40282347E+38 and obj <= 3.40282347E+38 end,
    [Double] = function (obj) return type(obj) == "number" end
  }
  local function check(obj, T)
    local number = numbers[T]
    if number then
      return number(obj)
    end
    return set[T] == true
  end
  checks[Number] = check
  return check(obj, T)
end

local is, getName

if System.debugsetmetatable then
  is = function (obj, T)
    return checks[getmetatable(obj)](obj, T)
  end

  getName = function (obj)
    return obj.__name__
  end

  System.getClassFromObj = getmetatable
else
  local function getClassFromObj(obj)
    local t = type(obj)
    if t == "number" then
      return Number
    elseif t == "boolean" then
      return Boolean
    elseif t == "function" then
      return Delegate
    end
    return getmetatable(obj)
  end

  function System.ObjectGetType(this)
    if this == nil then throw(NullReferenceException()) end
    return typeof(getClassFromObj(this))
  end

  is = function (obj, T)
    local base = getClassFromObj(obj)
    if base then
      return checks[base](obj, T)
    end
    return false
  end

  getName = function (obj)
    return getClassFromObj(obj).__name__
  end

  System.getClassFromObj = getClassFromObj
end

System.is = is

function System.as(obj, cls)
  if obj ~= nil and is(obj, cls) then
    return obj
  end
  return nil
end

local function cast(cls, obj, nullable)
  if obj ~= nil then
    if is(obj, cls) then
      return obj
    end
    throw(InvalidCastException(("Unable to cast object of type '%s' to type '%s'."):format(getName(obj), cls.__name__)), 1)
  else
    if cls.class ~= "S" or nullable then
      return nil
    end
    throw(NullReferenceException(), 1)
  end
end

System.cast = cast

function System.castWithNullable(cls, obj)
  if System.isNullable(cls) then
    return cast(cls.__genericT__, obj, true)
  end
  return cast(cls, obj)
end
end

-- CoreSystemLib: Collections/List.lua
do
local System = System
local falseFn = System.falseFn
local lengthFn = System.lengthFn
local Array = System.Array

local List = {
  __ctor__ = Array.ctorList,
  getCapacity = lengthFn,
  setCapacity = Array.setCapacity,
  getCount = lengthFn,
  getIsFixedSize = falseFn,
  getIsReadOnly = falseFn,
  get = Array.get,
  set = Array.set,
  Add = Array.add,
  AddObj = Array.addObj,
  AddRange = Array.addRange,
  AsReadOnly = Array.AsReadOnly,
  BinarySearch = Array.BinarySearch,
  Clear = Array.clear,
  Contains = Array.Contains,
  CopyTo = Array.CopyTo,
  Exists = Array.Exists,
  Find = Array.Find,
  FindAll = Array.findAll,
  FindIndex = Array.FindIndex,
  FindLast = Array.FindLast,
  FindLastIndex = Array.FindLastIndex,
  ForEach = Array.ForEach,
  GetEnumerator = Array.GetEnumerator,
  GetRange = Array.getRange,
  IndexOf = Array.IndexOf,
  Insert = Array.insert,
  InsertRange = Array.insertRange,
  LastIndexOf = Array.LastIndexOf,
  Remove = Array.remove,
  RemoveAll = Array.removeAll,
  RemoveAt = Array.removeAt,
  RemoveRange = Array.removeRange,
  Reverse = Array.Reverse,
  Sort = Array.Sort,
  TrimExcess = System.emptyFn,
  ToArray = Array.toArray,
  TrueForAll = Array.TrueForAll
}

function System.listFromTable(t, T)
  return setmetatable(t, List(T))
end

local ListFn = System.define("System.Collections.Generic.List", function(T) 
  return { 
    base = { System.IList_1(T), System.IReadOnlyList_1(T), System.IList }, 
    __genericT__ = T,
  }
end, List, 1)

System.List = ListFn
System.ArrayList = ListFn(System.Object)
end

-- CoreSystemLib: Collections/Dictionary.lua
do
local System = System
local define = System.define
local throw = System.throw
local null = System.null
local falseFn = System.falseFn
local each = System.each
local lengthFn = System.lengthFn
local versions = System.versions
local Array = System.Array
local toString = System.toString

local checkIndexAndCount = System.checkIndexAndCount
local throwFailedVersion = System.throwFailedVersion
local ArgumentNullException = System.ArgumentNullException
local ArgumentException = System.ArgumentException
local KeyNotFoundException = System.KeyNotFoundException
local EqualityComparer = System.EqualityComparer
local NotSupportedException = System.NotSupportedException

local assert = assert
local pairs = pairs
local next = next
local select = select
local getmetatable = getmetatable
local setmetatable = setmetatable
local tconcat = table.concat
local tremove = table.remove
local type = type

local counts = setmetatable({}, { __mode = "k" })
System.counts = counts

local function getCount(this)
  local t = counts[this]
  if t then
    return t[1]
  end
  return 0
end

local function pairsFn(t, i)
  local count =  counts[t]
  if count then
    if count[2] ~= count[3] then
      throwFailedVersion()
    end
  end
  local k, v = next(t, i)
  if v == null then
    return k
  end
  return k, v
end

function System.pairs(t)
  local count = counts[t]
  if count then
    count[3] = count[2]
  end
  return pairsFn, t
end

local KeyValuePairFn
local KeyValuePair = {
  __ctor__ = function (this, ...)
    if select("#", ...) == 0 then
      this[1], this[2] = this.__genericTKey__:default(), this.__genericTValue__:default()
    else
      this[1], this[2] = ...
    end
  end,
  Create = function (key, value, TKey, TValue)
    return setmetatable({ key, value }, KeyValuePairFn(TKey, TValue))
  end,
  Deconstruct = function (this)
    return this[1], this[2]
  end,
  ToString = function (this)
    local t = { "[" }
    local count = 2
    local k, v = this[1], this[2]
    if k ~= nil then
      t[count] = toString(k)
      count = count + 1
    end
    t[count] = ", "
    count = count + 1
    if v ~= nil then
      t[count] = toString(v)
      count = count + 1
    end
    t[count] = "]"
    return tconcat(t)
  end
}

KeyValuePairFn = System.defStc("System.Collections.Generic.KeyValuePair", function(TKey, TValue)
  local cls = {
    __genericTKey__ = TKey,
    __genericTValue__ = TValue,
  }
  return cls
end, KeyValuePair, 2)
System.KeyValuePair = KeyValuePairFn

local function isKeyValuePair(t)
  return getmetatable(getmetatable(t)) == KeyValuePair
end

local DictionaryEnumerator = define("System.Collections.Generic.DictionaryEnumerator", {
  getCurrent = System.getCurrent, 
  Dispose = System.emptyFn,
  MoveNext = function (this)
    local t, kind = this.dict, this.kind
    local count = counts[t]
    if this.version ~= (count and count[2] or 0) then
      throwFailedVersion()
    end
    local k, v = next(t, this.index)
    if k ~= nil then
      if kind then
        kind[1] = k
        if v == null then v = nil end
        kind[2] = v
      elseif kind == false then
        if v == null then v = nil end
        this.current = v
      else
        this.current = k
      end
      this.index = k
      return true
    else
      if kind then
        kind[1], kind[2] = kind.__genericTKey__:default(), kind.__genericTValue__:default()
      elseif kind == false then
        this.current = t.__genericTValue__:default()
      else
        this.current = t.__genericTKey__:default()
      end
      return false
    end
  end
})

local function dictionaryEnumerator(t, kind)
  local current
  if not kind then
    local TKey, TValue = t.__genericTKey__, t.__genericTValue__
    kind = setmetatable({ TKey:default(), TValue:default() }, t.__genericT__)
    current = kind
  elseif kind == 1 then
    local TKey = t.__genericTKey__
    current = TKey:default()
    kind = nil
  else
    local TValue = t.__genericTValue__
    current = TValue:default()
    kind = false
  end
  local count = counts[t]
  local en = {
    dict = t,
    version = count and count[2] or 0,
    kind = kind,
    current = current
  }
  return setmetatable(en, DictionaryEnumerator)
end

local DictionaryCollection = define("System.Collections.Generic.DictionaryCollection", function (T)
    return {
      base = { System.ICollection_1(T), System.IReadOnlyCollection_1(T), System.ICollection },
      __genericT__ = T
    }
  end, {
  __ctor__ = function (this, dict, kind)
    this.dict = dict
    this.kind = kind
  end,
  getCount = function (this)
    return getCount(this.dict)
  end,
  GetEnumerator = function (this)
    return dictionaryEnumerator(this.dict, this.kind)
  end
}, 1)

local function add(this, key, value)
  if key == nil then throw(ArgumentNullException("key")) end
  if this[key] ~= nil then throw(ArgumentException("key already exists")) end
  this[key] = value == nil and null or value
  local t = counts[this]
  if t then
    t[1] = t[1] + 1
    t[2] = t[2] + 1
  else
    counts[this] = { 1, 1 }
  end
end

local function remove(this, key)
  if key == nil then throw(ArgumentNullException("key")) end
  if this[key] ~= nil then
    this[key] = nil
    local t = counts[this]
    t[1] = t[1] - 1
    t[2] = t[2] + 1
    return true
  end
  return false
end

local function buildFromDictionary(this, dictionary)
  if dictionary == nil then throw(ArgumentNullException("dictionary")) end
  local count = 0
  for k, v in pairs(dictionary) do
    this[k] = v
    count = count + 1
  end
  counts[this] = { count, 0 }
end

local ArrayDictionaryFn
local function buildHasComparer(this, ...)
   local Dictionary = ArrayDictionaryFn(this.__genericTKey__, this.__genericTValue__)
   Dictionary.__ctor__(this, ...)
   return setmetatable(this, Dictionary)
end

local Dictionary = {
  getIsFixedSize = falseFn,
  getIsReadOnly = falseFn,
  __ctor__ = function (this, ...) 
    local n = select("#", ...)
    if n == 0 then
    elseif n == 1 then
      local comparer = ...
      if comparer == nil or type(comparer) == "number" then  
      else
        local equals = comparer.EqualsOf
        if equals == nil then
          buildFromDictionary(this, comparer)
        else
          buildHasComparer(this, ...)
        end
      end
    else
      local dictionary, comparer = ...
      if comparer ~= nil then 
        buildHasComparer(this, ...)
      end
      if type(dictionary) ~= "number" then 
        buildFromDictionary(this, dictionary)
      end
    end
  end,
  AddKeyValue = add,
  Add = function (this, ...)
    local k, v
    if select("#", ...) == 1 then
      local pair = ... 
      k, v = pair[1], pair[2]
    else
      k, v = ...
    end
    add(this, k ,v)
  end,
  Clear = function (this)
    for k, v in pairs(this) do
      this[k] = nil
    end
    counts[this] = nil
  end,
  ContainsKey = function (this, key)
    if key == nil then throw(ArgumentNullException("key")) end
    return this[key] ~= nil 
  end,
  ContainsValue = function (this, value)
    if value == nil then
      for _, v in pairs(this) do
        if v == null then
          return true
        end
      end
    else
      local comparer = EqualityComparer(this.__genericTValue__).getDefault()
      local equals = comparer.EqualsOf
        for _, v in pairs(this) do
          if v ~= null then
            if equals(comparer, value, v ) then
              return true
            end
          end
      end
    end
    return false
  end,
  Contains = function (this, pair)
    local key = pair[1]
    if key == nil then throw(ArgumentNullException("key")) end
    local value = this[key]
    if value ~= nil then
      if value == null then value = nil end
      local comparer = EqualityComparer(this.__genericTValue__).getDefault()
      if comparer:EqualsOf(value, pair[2]) then
        return true
      end
    end
    return false
  end,
  CopyTo = function (this, array, index)
    local count = getCount(this)
    checkIndexAndCount(array, index, count)
    if count > 0 then
      local KeyValuePair = this.__genericT__
      index = index + 1
      for k, v in pairs(this) do
        if v == null then v = nil end
        array[index] = setmetatable({ k, v }, KeyValuePair)
        index = index + 1
      end
    end
  end,
  RemoveKey = remove,
  Remove = function (this, key)
    if isKeyValuePair(key) then
      local k, v = key[1], key[2]
      if k == nil then throw(ArgumentNullException("key")) end
      local value = this[k]
      if value ~= nil then
        if value == null then value = nil end
        local comparer = EqualityComparer(this.__genericTValue__).getDefault()
        if comparer:EqualsOf(value, v) then
          remove(this, k)
          return true
        end
      end
      return false
    end
    return remove(this, key)
  end,
  TryGetValue = function (this, key)
    if key == nil then throw(ArgumentNullException("key")) end
    local value = this[key]
    if value == nil then
      return false, this.__genericTValue__:default()
    end
    if value == null then return true end
    return true, value
  end,
  getComparer = function (this)
    return EqualityComparer(this.__genericTKey__).getDefault()
  end,
  getCount = getCount,
  get = function (this, key)
    if key == nil then throw(ArgumentNullException("key")) end
    local value = this[key]
    if value == nil then throw(KeyNotFoundException()) end
    if value ~= null then
      return value
    end
    return nil
  end,
  set = function (this, key, value)
    if key == nil then throw(ArgumentNullException("key")) end
    local t = counts[this]
    if t then
      if this[key] == nil then
        t[1] = t[1] + 1
      end
      t[2] = t[2] + 1
    else
      counts[this] = { 1, 1 }
    end
    this[key] = value == nil and null or value
  end,
  GetEnumerator = dictionaryEnumerator,
  getKeys = function (this)
    return DictionaryCollection(this.__genericTKey__)(this, 1)
  end,
  getValues = function (this)
    return DictionaryCollection(this.__genericTValue__)(this, 2)
  end
}

local ArrayDictionaryEnumerator = define("System.Collections.Generic.ArrayDictionaryEnumerator", function (T)
  return {
    base = { System.IEnumerator_1(T) }
  }
end, {
  getCurrent = System.getCurrent, 
  Dispose = System.emptyFn,
  MoveNext = function (this)
    local t = this.list
    if this.version ~= versions[t] then
      throwFailedVersion()
    end
    local index = this.index
    local pair = t[index]
    if pair ~= nil then
      if this.kind then
        this.current = pair[2]
      else
        this.current = pair[1]
      end
      this.index = index + 1
      return true
    end
    this.current = nil
    return false
  end
}, 1)

local arrayDictionaryEnumerator = function (t, kind, T)
  return setmetatable({ list = t, kind = kind, index = 1, version = versions[t], currnet = T:default() }, ArrayDictionaryEnumerator(T))
end

local ArrayDictionaryCollection = define("System.Collections.Generic.ArrayDictionaryCollection", function (T)
  return {
    base = { System.ICollection_1(T), System.IReadOnlyCollection_1(T), System.ICollection },
    __genericT__ = T
  }
  end, {
  __ctor__ = function (this, dict, kind)
    this.dict = dict
    this.kind = kind
  end,
  getCount = function (this)
    return #this.dict
  end,
  get = function (this, index)
    local p = this.dict[index + 1]
    if p == nil then throw(System.ArgumentOutOfRangeException()) end
    if this.kind then
      return p[2]
    end
    return p[1]
  end,
  Contains = function (this, v)
    if this.kind then
      return this.dict:ContainsValue(v)
    end 
    return this.dict:ContainsKey(v)
  end,
  GetEnumerator = function (this)
    return arrayDictionaryEnumerator(this.dict, this.kind, this.__genericT__)
  end
}, 1)

local ArrayDictionary = (function ()
  local function buildFromDictionary(this, dictionary)
    if dictionary == nil then throw(ArgumentNullException("dictionary")) end
    local count = 1
    local KeyValuePair = this.__genericT__
    for _, pair in each(dictionary) do
      local k, v = pair[1], pair[2]
      if type(k) == "table" and k.class == 'S' then
        k = k:__clone__()
      end
      this[count] = setmetatable({ k, v }, KeyValuePair)
      count = count + 1
    end
  end 
  
  local function add(this, key, value, set)
    if key == nil then throw(ArgumentNullException("key")) end
    local len = #this
    if len > 0 then
      local comparer = this.comparer
      local equals = comparer.EqualsOf
      for i = 1, len do
        if equals(comparer, this[i][1], key) then
          if set then
            this[i][2] = value
            return
          else
            throw(ArgumentException("key already exists"))
          end
        end
      end
    end
    this[len + 1] = setmetatable({ key, value }, this.__genericT__)
    versions[this] = (versions[this] or 0) + 1
  end
  
  local function remove(this, key)
    if key == nil then throw(ArgumentNullException("key")) end
    local len = #this
    if len > 0 then
      local comparer = this.comparer
      local equals = comparer.EqualsOf
      for i = 1, len do
        if equals(comparer, this[i][1], key) then
          tremove(this, i)
          versions[this] = (versions[this] or 0) + 1
          return true
        end
      end
    end
    return false
  end
 
  return {
    getIsFixedSize = falseFn,
    getIsReadOnly = falseFn,
    __ctor__ = function (this, ...)
      local Comparer
      local n = select("#", ...)
      if n == 0 then
      elseif n == 1 then
        local comparer = ...
        if comparer == nil or type(comparer) == "number" then  
        else
          local equals = comparer.EqualsOf
          if equals == nil then
            buildFromDictionary(this, comparer)
          else
            Comparer = comparer
          end
        end
      else
        local dictionary, comparer = ...
        if type(dictionary) ~= "number" then 
           buildFromDictionary(this, dictionary)
        end
        Comparer = comparer
      end
      this.comparer = Comparer or EqualityComparer(this.__genericTKey__).getDefault()
    end,
    AddKeyValue = add,
    Add = function (this, ...)
      local k, v
      if select("#", ...) == 1 then
        local pair = ... 
        k, v = pair[1], pair[2]
      else
        k, v = ...
      end
      add(this, k ,v)
    end,
    Clear = Array.clear,
    ContainsKey = function (this, key)
      if key == nil then throw(ArgumentNullException("key")) end
      local len = #this
      if len > 0 then
        local comparer = this.comparer
        local equals = comparer.EqualsOf
        for i = 1, len do
          if equals(comparer, this[i][1], key) then
            return true
          end
        end
      end
      return false
    end,
    ContainsValue = function (this, value)
      local len = #this
      if len > 0 then
        local comparer = EqualityComparer(this.__genericTValue__).getDefault()
        local equals = comparer.EqualsOf
        for i = 1, len do
          if equals(comparer, value, this[i][2]) then
            return true
          end
        end
      end
      return false
    end,
    Contains = function (this, pair)
      local key = pair[1]
      if key == nil then throw(ArgumentNullException("key")) end
      local len = #this
      if len > 0 then
        local comparer = this.comparer
        local equals = comparer.EqualsOf
        for i = 1, len do
          local t = this[i]
          if equals(comparer, t[1], key) then
            local comparer = EqualityComparer(this.__genericTValue__).getDefault()
            if comparer:EqualsOf(t[2], pair[2]) then
              return true
            end 
          end
        end
      end
      return false
    end,
    CopyTo = function (this, array, index)
      local count = #this
      checkIndexAndCount(array, index, count)
      if count > 0 then
        local KeyValuePair = this.__genericT__
        index = index + 1
        for i = 1, count do
          local t = this[i]
          array[index] = setmetatable({ t[1]:__clone__(), t[2] }, KeyValuePair)
          index = index + 1
        end
      end
    end,
    RemoveKey = remove,
    Remove = function (this, key)
      if isKeyValuePair(key) then
        local len = #this
        local k, v = key[1], key[2]
        for i = 1, #this do
          local pair = this[i]
          if pair[1]:EqualsObj(k) then
            local comparer = EqualityComparer(this.__genericTValue__).getDefault()
            if comparer:EqualsOf(pair[2], v) then
              tremove(this, i)
              return true
            end
          end
        end
      end
      return false
    end,
    TryGetValue = function (this, key)
      if key == nil then throw(ArgumentNullException("key")) end
      local len = #this
      if len > 0 then
        local comparer = this.comparer
        local equals = comparer.EqualsOf
        for i = 1, len do
          local pair = this[i]
          if equals(comparer, pair[1], key) then
            return true, pair[2]
          end
        end
      end
      return false, this.__genericTValue__:default()
    end,
    getComparer = function (this)
      return this.comparer
    end,
    getCount = lengthFn,
    get = function (this, key)
      if key == nil then throw(ArgumentNullException("key")) end
      local len = #this
      if len > 0 then
        local comparer = this.comparer
        local equals = comparer.EqualsOf
        for i = 1, len do
          local pair = this[i]
          if equals(comparer, pair[1], key) then
            return pair[2]
          end
        end
      end
      throw(KeyNotFoundException())
    end,
    set = function (this, key, value)
      add(this, key, value, true)
    end,
    GetEnumerator = Array.GetEnumerator,
    getKeys = function (this)
      return ArrayDictionaryCollection(this.__genericTKey__)(this)
    end,
    getValues = function (this)
      return ArrayDictionaryCollection(this.__genericTValue__)(this, true)
    end
  }
end)()

ArrayDictionaryFn = define("System.Collections.Generic.ArrayDictionary", function(TKey, TValue) 
  return { 
    base = { System.IDictionary_2(TKey, TValue), System.IDictionary, System.IReadOnlyDictionary_2(TKey, TValue) },
    __genericT__ = KeyValuePairFn(TKey, TValue),
    __genericTKey__ = TKey,
    __genericTValue__ = TValue,
  }
end, ArrayDictionary, 2)

function System.dictionaryFromTable(t, TKey, TValue)
  return setmetatable(t, Dictionary(TKey, TValue))
end

function System.isDictLike(t)
  return type(t) == "table" and t.GetEnumerator == dictionaryEnumerator
end

local DictionaryFn = define("System.Collections.Generic.Dictionary", function(TKey, TValue)
  local array, len
  if TKey.class == 'S' and type(TKey:default()) == "table" then
    array = ArrayDictionary
  else
    len = getCount
  end
  return { 
    base = { System.IDictionary_2(TKey, TValue), System.IDictionary, System.IReadOnlyDictionary_2(TKey, TValue) },
    __genericT__ = KeyValuePairFn(TKey, TValue),
    __genericTKey__ = TKey,
    __genericTValue__ = TValue,
    __len = len
  }, array
end, Dictionary, 2)

System.Dictionary = DictionaryFn
System.ArrayDictionary = ArrayDictionaryFn

local Object = System.Object
System.Hashtable = DictionaryFn(Object, Object)
end

-- CoreSystemLib: Collections/Queue.lua
do
local System = System
local Array = System.Array

local function tryDequeue(this)
  if #this == 0 then
    return false
  end
  return true, this:Dequeue()
end

local Queue = {
  __ctor__ = Array.ctorList,
  getCount = Array.getLength,
  Clear = Array.clear,
  Contains = Array.Contains,
  CopyTo = Array.CopyTo,
  Dequeue = Array.popFirst,
  Enqueue = Array.add,
  GetEnumerator = Array.GetEnumerator,
  Peek = Array.first,
  ToArray = Array.toArray,
  TrimExcess = System.emptyFn,
  TryDequeue = tryDequeue
}

function System.queueFromTable(t, T)
  return setmetatable(t, Queue(T))
end

local QueueFn = System.define("System.Collections.Generic.Queue", function(T) 
  return {
    base = { System.IEnumerable_1(T), System.ICollection },
    __genericT__ = T,
  }
end, Queue, 1)

System.Queue = QueueFn
System.queue = QueueFn(System.Object)
end

-- CoreSystemLib: Collections/Stack.lua
do
local System = System
local Array = System.Array

local Stack = {
  __ctor__ = Array.ctorList,
  getCount = Array.getLength,
  Clear = Array.clear,
  Contains = Array.Contains,
  GetEnumerator = Array.reverseEnumerator,
  Push = Array.add,
  Peek = Array.last,
  Pop = Array.popLast,
  ToArray = Array.toArray,
  TrimExcess = System.emptyFn
}

function System.stackFromTable(t, T)
  return setmetatable(t, Stack(T))
end

local StackFn = System.define("System.Collections.Generic.Stack", function(T) 
  return {
    base = { System.IEnumerable_1(T), System.ICollection },
    __genericT__ = T,
  }
end, Stack, 1)

System.Stack = StackFn
System.stack = StackFn(System.Object)
end

-- CoreSystemLib: Collections/HashSet.lua
do
local System = System
local throw = System.throw
local each = System.each
local Dictionary = System.Dictionary
local wrap = System.wrap
local unWrap = System.unWrap
local getEnumerator = Dictionary.GetEnumerator 
local ArgumentNullException = System.ArgumentNullException

local assert = assert
local pairs = pairs
local select = select

local counts = System.counts

local function build(this, collection, comparer)
  if comparer ~= nil then
    assert(false)
  end
  if collection == nil then
    throw(ArgumentNullException("collection"))
  end
  this:UnionWith(collection)
end

local function checkUniqueAndUnfoundElements(this, other, returnIfUnfound)
  if #this == 0 then
    local numElementsInOther = 0
    for _, item in each(other) do
      numElementsInOther = numElementsInOther + 1
      break
    end
    return 0, numElementsInOther
  end
  local set, uniqueCount, unfoundCount = {}, 0, 0
  for _, item in each(other) do
    item = wrap(item)
    if this[item] ~= nil then
      if set[item] == nil then
        set[item] = true
        uniqueCount = uniqueCount + 1
      end
    else
      unfoundCount = unfoundCount + 1
      if returnIfUnfound then
        break
      end
    end
  end
  return uniqueCount, unfoundCount
end

local HashSet = {
  __ctor__ = function (this, ...)
    local len = select("#", ...)
    if len == 0 then
    elseif len == 1 then
      local collection = ...
      if collection == nil then return end
      if collection.getEnumerator ~= nil then
        build(this, collection, nil)
      else
        assert(true)
      end
    else 
      build(this, ...)
    end
  end,
  Clear = Dictionary.Clear,
  getCount = Dictionary.getCount,
  getIsReadOnly = System.falseFn,
  Contains = function (this, item)
    item = wrap(item)
    return this[item] ~= nil
  end,
  Remove = function (this, item)
    item = wrap(item)
    if this[item] then
      this[item] = nil
      local t = counts[this]
      t[1] = t[1] - 1
      t[2] = t[2] + 1
      return true
    end
    return false
  end,
  GetEnumerator = function (this)
    return getEnumerator(this, 1)
  end,
  Add = function (this, v)
    v = wrap(v)
    if this[v] == nil then
      this[v] = true
      local t = counts[this]
      if t then
        t[1] = t[1] + 1
        t[2] = t[2] + 1
      else
        counts[this] = { 1, 1 }
      end
      return true
    end
    return false
  end,
  UnionWith = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    local count = 0
    for _, v in each(collection) do
      v = wrap(v)
      if this[v] == nil then
        this[v] = true
        count = count + 1
      end
    end
    if count > 0 then
      local t = counts[this]
      if t then
        t[1] = t[1] + count
        t[2] = t[2] + 1
      else
        counts[this] = { count, 1 }  
      end
    end
  end,
  IntersectWith = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    local set = {}
    for _, v in each(other) do
      v = wrap(v)
      if this[v] ~= nil then
        set[v] = true
      end
    end
    local count = 0
    for v, _ in pairs(this) do
      if set[v] == nil then
        this[v] = nil
        count = count + 1
      end
    end
    if count > 0 then
      local t = counts[this]
      t[1] = t[1] - count
      t[2] = t[2] + 1
    end
  end,
  ExceptWith = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    if other == this then
      this:Clear()
      return
    end
    local count = 0
    for _, v in each(other) do
      v = wrap(v)
      if this[v] ~= nil then
        this[v] = nil
        count = count + 1
      end
    end
    if count > 0 then
      local t = counts[this]
      t[1] = t[1] - count
      t[2] = t[2] + 1
    end
  end,
  SymmetricExceptWith = function (this, other)
    if other == nil then throw(ArgumentNullException("other")) end
    if other == this then
      this:Clear()
      return
    end
    local set = {}
    local count = 0
    local changed = false
    for _, v in each(other) do
      v = wrap(v)
      if this[v] == nil then
        this[v] = true
        count = count + 1
        changed = true
        set[v] = true
      elseif set[v] == nil then 
        this[v] = nil
        count = count - 1
        changed = true
      end
    end
    if changed then
      local t = counts[this]
      if t then
        t[1] = t[1] + count
        t[2] = t[2] + 1
      else
        counts[this] = { count, 1 }
      end
    end
  end,
  IsSubsetOf = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    local count = #this
    if count == 0 then
      return true
    end
    local uniqueCount, unfoundCount = checkUniqueAndUnfoundElements(this, other, false)
    return uniqueCount == count and unfoundCount >= 0
  end,
  IsProperSubsetOf = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    local uniqueCount, unfoundCount = checkUniqueAndUnfoundElements(this, other, false)
    return uniqueCount == #this and unfoundCount > 0
  end,
  IsSupersetOf = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    for _, element in each(other) do
      element = wrap(element)
      if this[element] == nil then
        return false
      end
    end
    return true
  end,
  IsProperSupersetOf = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    local count = #this
    if count == 0 then
      return false
    end
    local uniqueCount, unfoundCount = checkUniqueAndUnfoundElements(this, other, true)
    return uniqueCount < count and unfoundCount == 0
  end,
  Overlaps = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    if #this == 0 then
      return false
    end
    for _, element in each(other) do
      element = wrap(element)
      if this[element] ~= nil then
        return true
      end
    end
    return false
  end,
  SetEquals = function (this, other)
    if other == nil then
      throw(ArgumentNullException("other"))
    end
    local uniqueCount, unfoundCount = checkUniqueAndUnfoundElements(this, other, true)
    return uniqueCount == #this and unfoundCount == 0
  end,
  RemoveWhere = function (this, match)
    if match == nil then
      throw(ArgumentNullException("match"))
    end
    local numRemoved = 0
    for v, _ in pairs(this) do
      if match(unWrap(v)) then
        this[v] = nil
        numRemoved = numRemoved + 1
      end
    end
    if numRemoved > 0 then
      local t = counts[this]
      t[1] = t[1] - numRemoved
      t[2] = t[2] + 1
    end
    return numRemoved
  end,
  TrimExcess = System.emptyFn
}

function System.hashSetFromTable(t, T)
  return setmetatable(t, HashSet(T))
end

System.HashSet = System.define("System.Collections.Generic.HashSet", function(T) 
  return { 
    base = { System.ICollection_1(T), System.ISet_1(T) }, 
    __genericT__ = T,
    __genericTKey__ = T,
    __len = HashSet.getCount
  }
end, HashSet, 1)
end

-- CoreSystemLib: Collections/LinkedList.lua
do
local System = System
local define = System.define
local throw = System.throw
local each = System.each
local checkIndexAndCount = System.checkIndexAndCount
local ArgumentNullException = System.ArgumentNullException
local InvalidOperationException = System.InvalidOperationException
local EqualityComparer = System.EqualityComparer

local setmetatable = setmetatable
local select = select

local LinkedListNode = define("System.Collections.Generic.LinkedListNode", {
  __ctor__ = function (this, value)
    this.Value = value
  end,
  getNext = function (this)
    local next = this.next
    if next == nil or next == this.List.head then
      return nil
    end
    return next
  end,
  getPrevious = function (this)
    local prev = this.prev
    if prev == nil or this == this.List.head then
      return nil
    end
    return prev
  end
})
System.LinkedListNode = LinkedListNode

local function newLinkedListNode(list, value)
  return setmetatable({ List = assert(list), Value = value }, LinkedListNode)
end

local function vaildateNewNode(this, node)
  if node == nil then
    throw(ArgumentNullException("node"))
  end
  if node.List ~= nil then
    throw(InvalidOperationException("ExternalLinkedListNode"))
  end
end

local function vaildateNode(this, node)
  if node == nil then
    throw(ArgumentNullException("node"))
  end
  if node.List ~= this then
    throw(InvalidOperationException("ExternalLinkedListNode"))
  end
end

local function insertNodeBefore(this, node, newNode)
  newNode.next = node
  newNode.prev = node.prev
  node.prev.next = newNode
  node.prev = newNode
  this.Count = this.Count + 1
  this.version = this.version + 1
end

local function insertNodeToEmptyList(this, newNode)
  newNode.next = newNode
  newNode.prev = newNode
  this.head = newNode
  this.Count = this.Count + 1
  this.version = this.version + 1
end

local function invalidate(this)
  this.List = nil
  this.next = nil
  this.prev = nil
end

local function remvoeNode(this, node)
  if node.next == node then
    this.head = nil
  else
    node.next.prev = node.prev
    node.prev.next = node.next
    if this.head == node then
      this.head = node.next
    end
  end
  invalidate(node)
  this.Count = this.Count - 1
  this.version = this.version + 1
end

local LinkedListEnumerator = { 
  __index = false,
  getCurrent = System.getCurrent, 
  Dispose = System.emptyFn,
  MoveNext = function (this)
    local list = this.list
    local node = this.node
    if this.version ~= list.version then
      System.throwFailedVersion()
    end
    if node == nil then
      return false
    end
    this.current = node.Value
    node = node.next
    if node == list.head then
      node = nil
    end
    this.node = node
    return true
  end
}
LinkedListEnumerator.__index = LinkedListEnumerator

local LinkedList = { 
  Count = 0, 
  version = 0,
  __ctor__ = function (this, ...)
    local len = select("#", ...)
    if len == 1 then
      local collection = ...
      if collection == nil then
        throw(ArgumentNullException("collection"))
      end
      for _, item in each(collection) do
        this:AddLast(item)
      end
    end
  end,
  getCount = function (this)
    return this.Count
  end,
  getFirst = function(this)    
    return this.head
  end,
  getLast = function (this)
    local head = this.head
    return head ~= nil and head.prev or nil
  end,
  AddAfterNode = function (this, node, newNode)
    vaildateNode(this, node)
    vaildateNewNode(this, newNode)
    insertNodeBefore(this, node.next, newNode)
    newNode.List = this
  end,
  AddAfter = function (this, node, value)    
    vaildateNode(this, node)
    local result = newLinkedListNode(node.List, value)
    insertNodeBefore(this, node.next, result)
    return result
  end,
  AddBeforeNode = function (this, node, newNode)
    vaildateNode(this, node)
    vaildateNewNode(this, newNode)
    insertNodeBefore(this, node, newNode)
    newNode.List = this
    if node == this.head then
      this.head = newNode
    end
  end,
  AddBefore = function (this, node, value)
    vaildateNode(this, node)
    local result = newLinkedListNode(node.List, value)
    insertNodeBefore(this, node, result)
    if node == this.head then
      this.head = result
    end
    return result
  end,
  AddFirstNode = function (this, node)
	  vaildateNewNode(this, node)
    if this.head == nil then
      insertNodeToEmptyList(this, node)
    else
      insertNodeBefore(this, this.head, node)
      this.head = node
    end
    node.List = this
  end,
  AddFirst = function (this, value)
    local result = newLinkedListNode(this, value)
    if this.head == nil then
      insertNodeToEmptyList(this, result)
    else
      insertNodeBefore(this, this.head, result)
      this.head = result
    end
    return result
  end,
  AddLastNode = function (this, node)
    vaildateNewNode(this, node)
    if this.head == nil then
      insertNodeToEmptyList(this, node)
    else
      insertNodeBefore(this, this.head, node)
    end
    node.List = this
  end,
  AddLast = function (this, value)
    local result = newLinkedListNode(this, value)
    if this.head == nil then
      insertNodeToEmptyList(this, result)
    else
      insertNodeBefore(this, this.head, result)
    end
    return result
  end,
  Clear = function (this)
    local current = this.head
    while current ~= nil do
      local temp = current
      current = current.next
      invalidate(temp)
    end
    this.head = nil
    this.Count = 0
    this.version = this.version + 1
  end,
  Contains = function (this, value)
    return this:Find(value) ~= nil
  end,
  CopyTo = function (this, array, index)
    checkIndexAndCount(array, index, this.Count)
    local head = this.head
    local node = head
    if node then
      index = index + 1
      repeat
        local value = node.Value
        if value == nil then value = System.null end
        array[index] = value
        index = index + 1
        node = node.next
      until node == head
    end
  end,
  Find = function (this, value)     
    local head = this.head
    local node = head
    local comparer = EqualityComparer(this.__genericT__).getDefault()
    local equals = comparer.EqualsOf
    if node ~= nil then
      if value ~= nil then
        repeat
          if equals(comparer, node.Value, value) then
            return node
          end
          node = node.next
        until node == head
      else
        repeat 
          if node.Value == nil then
            return node
          end
          node = node.next
        until node == head
      end
    end
    return nil
  end,
  FindLast = function (this, value)
    local head = this.head
    if head == nil then return nil end
    local last = head.prev
    local node = last
    local comparer = EqualityComparer(this.__genericT__).getDefault()
    local equals = comparer.EqualsOf
    if node ~= nil then
      if value ~= nil then
        repeat
          if equals(comparer, node.Value, value) then
            return node
          end
          node = node.prev
        until node == last
      else
        repeat 
          if node.Value == nil then
            return node
          end
          node = node.prev
         until node == last
      end
    end
    return nil
  end,
  RemoveNode = function (this, node)
    vaildateNode(this, node)
    remvoeNode(this, node)
  end,
  Remove = function (this, node)
    node = this:Find(node)
    if node ~= nil then
      remvoeNode(this, node)
    end
    return false
  end,
  RemoveFirst = function (this)
    local head = this.head
    if head == nil then
      throw(InvalidOperationException("LinkedListEmpty"))
    end
    remvoeNode(this, head)
  end,
  RemoveLast = function (this)
    local head = this.head
    if head == nil then
      throw(InvalidOperationException("LinkedListEmpty"))
    end
    remvoeNode(this, head.prev)
  end,
  GetEnumerator = function (this)
    return setmetatable({ list = this, version = this.version, node = this.head }, LinkedListEnumerator)
  end
}

function System.linkedListFromTable(t, T)
  return setmetatable(t, LinkedList(T))
end

System.LinkedList = define("System.Collections.Generic.LinkedList", function(T) 
  return { 
  base = { System.ICollection_1(T), System.ICollection }, 
  __genericT__ = T,
  __len = LinkedList.getCount
  }
end, LinkedList, 1)
end

-- CoreSystemLib: Collections/SortedSet.lua
do
local System = System
local Array = System.Array

local SortedSet = {
  __ctor__ = Array.ctorOrderSet,
  getMin = Array.firstOrDefault,
  getMax = Array.lastOrDefault,
  getCount = System.lengthFn,
  getComparer = Array.getOrderComparer,
  CreateSetComparer = Array.createSetComparer,
  Add = Array.addOrder,
  Clear = Array.clear,
  Contains = Array.containsOrder,
  CopyTo = Array.CopyTo,
  ExceptWith = Array.exceptWithOrder,
  GetEnumerator = Array.GetEnumerator,
  GetViewBetween = Array.getViewBetweenOrder,
  IntersectWith = Array.intersectWithOrder,
  IsProperSubsetOf = Array.isProperSubsetOfOrder,
  IsProperSupersetOf = Array.isProperSupersetOfOrder,
  IsSubsetOf = Array.isSubsetOfOrder,
  IsSupersetOf = Array.isSupersetOfOrder,
  Overlaps = Array.isOverlapsOrder,
  Remove = Array.removeOrder,
  RemoveWhere = Array.removeAll,
  Reverse = Array.reverseEnumerable,
  SetEquals = Array.equalsOrder,
  SymmetricExceptWith = Array.symmetricExceptWithOrder,
  TryGetValue = Array.tryGetValueOrder,
  UnionWith = Array.addOrderRange,
}

local SortedSetFn = System.define("System.Collections.Generic.SortedSet", function(T) 
  return { 
    base = { System.ICollection_1(T), System.IReadOnlyCollection_1(T), System.ISet_1(T) }, 
    __genericT__ = T,
  }
end, SortedSet, 1)

System.SortedSet = SortedSetFn
end

-- CoreSystemLib: Collections/SortedList.lua
do
local System = System
local lengthFn = System.lengthFn
local Array = System.Array
local ArrayDictionary = System.ArrayDictionary

local SortedList = {
  __ctor__ = Array.ctorOrderDict,
  getComparer = Array.getOrderComparer,
  getCount = lengthFn,
  getCapacity = lengthFn,
  setCapacity = Array.setCapacity,
  AddKeyValue = Array.addOrderDict,
  AddKeyValueObj = Array.addOrderDictObj,
  Add = Array.addPairOrderDict,
  Clear = Array.clear,
  ContainsKey = Array.containsOrderDict,
  ContainsValue = ArrayDictionary.ContainsValue,
  ContainsKeyObj = Array.containsOrderDictObj,
  GetEnumerator = Array.GetEnumerator,
  IndexOfKey = Array.indexKeyOrderDict,
  IndexOfValue =  Array.indexOfValue,
  RemoveKey = Array.removeOrderDict,
  Remove =  Array.removePairOrderDict,
  RemoveAt = Array.removeAt,
  TrimExcess = System.emptyFn,
  getKeys = ArrayDictionary.getKeys,
  getValues = ArrayDictionary.getValues,
  get = Array.getOrderDict,
  getObj = Array.getOrderDictObj,
  set = Array.setOrderDict,
  setObj = Array.setOrderDictObj,
}

local SortedListFn = System.define("System.Collections.Generic.SortedList", function(TKey, TValue) 
return { 
  base = { System.IDictionary_2(TKey, TValue), System.IDictionary, System.IReadOnlyDictionary_2(TKey, TValue) },
  __genericT__ = System.KeyValuePair(TKey, TValue),
  __genericTKey__ = TKey,
  __genericTValue__ = TValue,
}
end, SortedList, 2)

System.SortedList = SortedListFn
end

-- CoreSystemLib: Collections/SortedDictionary.lua
do
local System = System
local Array = System.Array
local ArrayDictionary = System.ArrayDictionary

local SortedDictionary = {
  __ctor__ = Array.ctorOrderDict,
  getComparer = Array.getOrderComparer,
  getCount = System.lengthFn,
  AddKeyValue = Array.addOrderDict,
  AddKeyValueObj = Array.addOrderDictObj,
  Add = Array.addPairOrderDict,
  Clear = Array.clear,
  ContainsKey = Array.containsOrderDict,
  ContainsValue = ArrayDictionary.ContainsValue,
  ContainsKeyObj = Array.containsOrderDictObj,
  CopyTo = Array.CopyTo,
  GetEnumerator = Array.GetEnumerator,
  RemoveKey = Array.removeOrderDict,
  Remove =  Array.removePairOrderDict,
  TryGetValue = Array.tryGetValueOrderDict,
  getKeys = ArrayDictionary.getKeys,
  getValues = ArrayDictionary.getValues,
  get = Array.getOrderDict,
  getObj = Array.getOrderDictObj,
  set = Array.setOrderDict,
  setObj = Array.setOrderDictObj,
}

local SortedDictionaryFn = System.define("System.Collections.Generic.SortedDictionary", function(TKey, TValue) 
  return { 
    base = { System.IDictionary_2(TKey, TValue), System.IDictionary, System.IReadOnlyDictionary_2(TKey, TValue) },
    __genericT__ = System.KeyValuePair(TKey, TValue),
    __genericTKey__ = TKey,
    __genericTValue__ = TValue,
  }
end, SortedDictionary, 2)

System.SortedDictionary = SortedDictionaryFn
end

-- CoreSystemLib: Collections/PriorityQueue.lua
do
local System = System
local throw = System.throw
local each = System.each
local er = System.er 
local Array = System.Array
local heapDown = Array.heapDown
local heapUp = Array.heapUp
local heapify = Array.heapify
local heapAdd = Array.heapAdd
local heapPop = Array.heapPop
local Comparer_1 = System.Comparer_1

local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local InvalidOperationException = System.InvalidOperationException

local select = select
local type = type

local function __ctor__(t, ...)
  local items, comparer
  local n = select("#", ...)
  if n == 0 then
  else
    items, comparer = ...
    if items == nil then throw(ArgumentNullException("items")) end
  end
  if comparer == nil then comparer = Comparer_1(t.__genericTPriority__).getDefault() end
  local compare = comparer.Compare
  local c = function (a, b) return compare(comparer, a[2], b[2]) end
  t.comparer, t.c = comparer, c
  if type(items) == "table" then
    local i = 1
    for _, tuple in each(items) do
      local element, priority = tuple[1], tuple[2]
      t[i] = { element, priority }
      i = i + 1
    end
    if i > 1 then
      heapify(t, c)
    end
  end
end

local function dequeue(t, n)
  local v = heapPop(t, t.c)
  if v == nil then throw(InvalidOperationException(er.InvalidOperation_EmptyQueue())) end
  return v[1]
end

local function enqueue(t, element, priority) 
  heapAdd(t, { element, priority }, t.c)
end

local function enqueueDequeue(t, element, priority)
  local n = #t
  if n ~= 0 then
    local c = t.c
    local v = { element, priority }
    local root = t[1]
    if c(v, root) > 0 then
      t[1] = v
      heapDown(t, 1, n, c)
      return root[1]
    end
  end
  return element
end

local function enqueueRange(t, ...)
  local len = select("#", ...)
  local n = #t
  if n == 0 then
    local i = 1
    if len == 1 then
      local items = ...
      for _, tuple in each(items) do
        local element, priority = tuple[1], tuple[2]
        t[i] = { element, priority }
        i = i + 1
      end
    else
      local elements, priority = ...
      for _, element in each(elements) do
        t[i] = { element, priority }
        i = i + 1
      end
    end
    if i > 1 then
      heapify(t, t.c)
    end
  else
    local c = t.c
    if len == 1 then
      local items = ...
      for _, tuple in each(items) do
        local element, priority = tuple[1], tuple[2]
        n = n + 1
        t[n] = { element, priority }
        heapUp(t, n, n, c)
      end
    else
      local elements, priority = ...
      for _, element in each(elements) do
        n = n + 1
        t[n] = { element, priority }
        heapUp(t, n, n, c)
      end
    end
  end
end

local function ensureCapacity(t, capacity)
  if capacity < 0 then
    throw(ArgumentOutOfRangeException("capacity", er.ArgumentOutOfRange_NeedNonNegNum()))
  end
  local n = #t
  local newcapacity = 2 * n
  newcapacity = math.max(newcapacity, n + 4)
  if newcapacity < 4 then newcapacity = 4 end
  return newcapacity
end

local function peek(t)
  local v = t[1]
  if v == nil then throw(InvalidOperationException(er.InvalidOperation_EmptyQueue())) end
  return v[1]
end

local function tryDequeue(t)
  local v = heapPop(t, t.c)
  if v then
    return true, v[1], v[2]
  end
  return false, t.__genericTElement__:default(), t.__genericTPriority__:default()
end

local function tryPeek(t)
  local v = t[1] 
  if v then
    return true, v[1], v[2]
  end
  return false, t.__genericTElement__:default(), t.__genericTPriority__:default()
end

local PriorityQueue = {
  __ctor__ = __ctor__,
  getCount = System.lengthFn,
  getComparer = Array.getOrderComparer,
  Clear = Array.clear,
  Dequeue = dequeue,
  Enqueue = enqueue,
  EnqueueDequeue = enqueueDequeue,
  EnqueueRange = enqueueRange,
  EnsureCapacity = ensureCapacity,
  Peek = peek,
  TrimExcess = System.emptyFn,
  TryDequeue = tryDequeue,
  TryPeek = tryPeek,
}

local PriorityQueueFn = System.define("System.Collections.Generic.PriorityQueue", function (TElement, TPriority)
  return { 
    __genericTElement__ = TElement,
    __genericTPriority__ = TPriority,
  }
end, PriorityQueue, 2)

System.PriorityQueue = PriorityQueueFn
end

-- CoreSystemLib: Collections/Linq.lua
do
local System = System
local define = System.define
local throw = System.throw
local each = System.each
local identityFn = System.identityFn
local wrap = System.wrap
local unWrap = System.unWrap
local is = System.is
local cast = System.cast
local Int32 = System.Int32
local isArrayLike = System.isArrayLike
local isDictLike = System.isDictLike
local Array = System.Array
local arrayEnumerator = Array.GetEnumerator

local NullReferenceException = System.NullReferenceException
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local InvalidOperationException = System.InvalidOperationException
local EqualityComparer = System.EqualityComparer
local Comparer_1 = System.Comparer_1
local Empty = System.Array.Empty

local IEnumerable_1 = System.IEnumerable_1
local IEnumerable = System.IEnumerable
local IEnumerator_1 = System.IEnumerator_1
local IEnumerator = System.IEnumerator

local assert = assert
local getmetatable = getmetatable
local setmetatable = setmetatable
local select = select
local pairs = pairs
local tsort = table.sort

local InternalEnumerable = define("System.Linq.InternalEnumerable", function(T) 
  return {
    base = { IEnumerable_1(T) }
  }
end, nil, 1)

local function createEnumerable(T, GetEnumerator)
  assert(T)
  return setmetatable({ __genericT__ = T, GetEnumerator = GetEnumerator }, InternalEnumerable(T))
end

local InternalEnumerator = define("System.Linq.InternalEnumerator", function(T) 
  return {
    base = { IEnumerator_1(T) }
  }
end, nil, 1)

local function createEnumerator(T, source, tryGetNext, init)
  assert(T)
  local state = 1
  local current
  local en
  return setmetatable({
    MoveNext = function()
      if state == 1 then
        state = 2
        if source then
          en = source:GetEnumerator() 
        end
        if init then
          init(en) 
        end
      end
      if state == 2 then
        local ok, v = tryGetNext(en)
        if ok then
          current = v
          return true
        elseif en then
          local dispose = en.Dispose
          if dispose then
            dispose(en)
          end    
        end
       end
       return false
    end,
    getCurrent = function()
      return current
    end
  }, InternalEnumerator(T))
end

local Enumerable = {}
define("System.Linq.Enumerable", Enumerable)

function Enumerable.Where(source, predicate)
  if source == nil then throw(ArgumentNullException("source")) end
  if predicate == nil then throw(ArgumentNullException("predicate")) end
  local T = source.__genericT__
  return createEnumerable(T, function() 
    local index = -1
    return createEnumerator(T, source, function(en)
      while en:MoveNext() do
        local current = en:getCurrent()
        index = index + 1
        if predicate(current, index) then
          return true, current
        end
      end 
      return false
    end)
  end)
end

function Enumerable.Select(source, selector, T)
  if source == nil then throw(ArgumentNullException("source")) end
  if selector == nil then throw(ArgumentNullException("selector")) end
  return createEnumerable(T, function()
    local index = -1
    return createEnumerator(T, source, function(en) 
      if en:MoveNext() then
        index = index + 1
        return true, selector(en:getCurrent(), index)
      end
      return false
    end)
  end)
end

local function selectMany(source, collectionSelector, resultSelector, T)
  if source == nil then throw(ArgumentNullException("source")) end
  if collectionSelector == nil then throw(ArgumentNullException("collectionSelector")) end
  if resultSelector == nil then throw(ArgumentNullException("resultSelector")) end
  return createEnumerable(T, function() 
    local element, midEn
    local index = -1
    return createEnumerator(T, source, function(en) 
      while true do
        if midEn and midEn:MoveNext() then
          return true, resultSelector(element, midEn:getCurrent())
        else
          if not en:MoveNext() then return false end
          index = index + 1
          local current = en:getCurrent()
          midEn = collectionSelector(current, index):GetEnumerator()
          if midEn == nil then
            throw(NullReferenceException())
          end
          element = current
        end  
      end
    end)
  end)
end

local function identityFnOfSelectMany(s, x)
  return x
end

function Enumerable.SelectMany(source, ...)
  local len = select("#", ...)
  if len == 2 then
    local collectionSelector, T = ...
    return selectMany(source, collectionSelector, identityFnOfSelectMany, T)
  else
    return selectMany(source, ...)
  end
end

function Enumerable.Take(source, count)
  if source == nil then throw(ArgumentNullException("source")) end
  local T = source.__genericT__
  return createEnumerable(T, function()
    return createEnumerator(T, source, function(en)
      if count > 0 then
        if en:MoveNext() then
          count = count - 1
          return true, en:getCurrent()
        end
      end
      return false
    end)
  end)
end

function Enumerable.TakeWhile(source, predicate)
  if source == nil then throw(ArgumentNullException("source")) end
  if predicate == nil then throw(ArgumentNullException("predicate")) end
  local T = source.__genericT__
  return createEnumerable(T, function()
    local index = -1
    return createEnumerator(T, source, function(en)
      if en:MoveNext() then
        local current = en:getCurrent()
        index = index + 1
        if not predicate(current, index) then
          return false
        end
        return true, current
      end
      return false
    end)
  end)
end

function Enumerable.Skip(source, count)
  if source == nil then throw(ArgumentNullException("source")) end
  local T = source.__genericT__
  return createEnumerable(T, function()
    return createEnumerator(T, source, function(en)
      while count > 0 and en:MoveNext() do count = count - 1 end
      if count <= 0 then
        if en:MoveNext() then
          return true, en:getCurrent() 
        end
      end
      return false
    end)
  end)
end

function Enumerable.SkipWhile(source, predicate)
  if source == nil then throw(ArgumentNullException("source")) end
  if predicate == nil then throw(ArgumentNullException("predicate")) end
  local T = source.__genericT__
  return createEnumerable(T, function()
    local index = -1
    local isSkipEnd = false
    return createEnumerator(T, source, function(en)
      while not isSkipEnd do
        if en:MoveNext() then
          local current = en:getCurrent()
          index = index + 1
          if not predicate(current, index) then
            isSkipEnd = true
            return true, current
          end     
        else 
          return false
        end
      end
      if en:MoveNext() then
        return true, en:getCurrent()
      end
      return false
    end)
  end)
end

local IGrouping = System.defInf("System.Linq.IGrouping_2", function (TKey, TElement)
  return {
    base = { IEnumerable_1(TElement) } 
  }
end)

local Grouping = define("System.Linq.Grouping", function (TKey, TElement)
  return {
    __genericT__ = TElement,
    base = { IGrouping(TKey, TElement) },
    GetEnumerator = arrayEnumerator,
    getKey = function (this)
      return this.key
    end,
    getCount = function (this)
      return #this
    end
  }
end, nil, 2)

local function getGrouping(this, key)
  local hashCode = this.comparer:GetHashCodeOf(key)
  local groupIndex = this.indexs[hashCode]
  return this.groups[groupIndex]
end

local Lookup = {
  __ctor__ = function (this, comparer)
    this.comparer = comparer or EqualityComparer(this.__genericTKey__).getDefault()
    this.groups = {}
    this.indexs = {}
  end,
  get = function (this, key)
    local grouping = getGrouping(this, key)
    if grouping ~= nil then return grouping end 
    return Empty(this.__genericTElement__)
  end,
  GetCount = function (this)
    return #this.groups
  end,
  Contains = function (this, key)
    return getGrouping(this, key) ~= nil
  end,
  GetEnumerator = function (this)
    return arrayEnumerator(this.groups, IGrouping)
  end
}

local LookupFn = define("System.Linq.Lookup", function(TKey, TElement)
  local cls = {
    __genericTKey__ = TKey,
    __genericTElement__ = TElement,
  }
  return cls
end, Lookup, 2)

local function addToLookup(this, key, value)
  local hashCode = this.comparer:GetHashCodeOf(key)
  local groupIndex = this.indexs[hashCode]
  local group
  if groupIndex == nil then
	  groupIndex = #this.groups + 1
	  this.indexs[hashCode] = groupIndex
	  group = setmetatable({ key = key }, Grouping(this.__genericTKey__, this.__genericTElement__))
	  this.groups[groupIndex] = group
  else
	  group = this.groups[groupIndex]
	  assert(group)
  end
  group[#group + 1] = wrap(value)
end

local function createLookup(source, keySelector, elementSelector, comparer, TKey, TElement)
  local lookup = LookupFn(TKey, TElement)(comparer)
  for _, item in each(source) do
    addToLookup(lookup, keySelector(item), elementSelector(item))
  end
  return lookup
end

local function createLookupForJoin(source, keySelector, comparer, TKey, TElement)
  local lookup = LookupFn(TKey, TElement)(comparer)
  for _, item in each(source) do
    local key = keySelector(item)
    if key ~= nil then
      addToLookup(lookup, key, item)
    end
  end
  return lookup
end

function Enumerable.Join(outer, inner, outerKeySelector, innerKeySelector, resultSelector, comparer, TKey, TResult)
  if outer == nil then throw(ArgumentNullException("outer")) end
  if inner == nil then throw(ArgumentNullException("inner")) end
  if outerKeySelector == nil then throw(ArgumentNullException("outerKeySelector")) end
  if innerKeySelector == nil then throw(ArgumentNullException("innerKeySelector")) end
  if resultSelector == nil then throw(ArgumentNullException("resultSelector")) end
  local lookup = createLookupForJoin(inner, innerKeySelector, comparer, TKey, inner.__genericT__)
  return createEnumerable(TResult, function ()
    local item, grouping, index
    return createEnumerator(TResult, outer, function (en)
      while true do
        if grouping ~= nil then
          index = index + 1
          if index < #grouping then
            return true, resultSelector(item, unWrap(grouping[index + 1]))
          end
        end
        if not en:MoveNext() then return false end
        local current = en:getCurrent()
        item = current
        grouping = getGrouping(lookup, outerKeySelector(current))
        index = -1
      end
    end)
  end)
end

function Enumerable.GroupJoin(outer, inner, outerKeySelector, innerKeySelector, resultSelector, comparer, TKey, TResult)
  if outer == nil then throw(ArgumentNullException("outer")) end
  if inner == nil then throw(ArgumentNullException("inner")) end
  if outerKeySelector == nil then throw(ArgumentNullException("outerKeySelector")) end
  if innerKeySelector == nil then throw(ArgumentNullException("innerKeySelector")) end
  if resultSelector == nil then throw(ArgumentNullException("resultSelector")) end
  local lookup = createLookupForJoin(inner, innerKeySelector, comparer, TKey, inner.__genericT__)
  return createEnumerable(TResult, function ()
    return createEnumerator(TResult, outer, function (en)
      if en:MoveNext() then
        local item = en:getCurrent()
        return true, resultSelector(item, lookup:get(outerKeySelector(item)))
      end
      return false
    end)
  end)
end

local function ordered(source, compare)
  local T = source.__genericT__
  local orderedEnumerable = createEnumerable(T, function()
    local t = {}
    local index = 0
    return createEnumerator(T, source, function() 
      index = index + 1
      local v = t[index]
      if v ~= nil then
        return true, unWrap(v)
      end
      return false
    end, 
    function() 
      local count = 1
      if isDictLike(source) then
        for k, v in pairs(source) do
          t[count] = setmetatable({ Key = k, Value = v }, T)
          count = count + 1
        end
      else
        for _, v in each(source) do
          t[count] = wrap(v)
          count = count + 1
        end
      end
      if count > 1 then
        tsort(t, function(x, y)
          return compare(unWrap(x), unWrap(y)) < 0 
        end)
      end
    end)
  end)
  orderedEnumerable.source = source
  orderedEnumerable.compare = compare
  return orderedEnumerable
end

local function orderBy(source, keySelector, comparer, TKey, descending)
  if source == nil then throw(ArgumentNullException("source")) end
  if keySelector == nil then throw(ArgumentNullException("keySelector")) end
  if comparer == nil then comparer = Comparer_1(TKey).getDefault() end 
  local keys = {}
  local function getKey(t) 
    local k = keys[t]
    if k == nil then
      k = keySelector(t)
      keys[t] = k
    end
    return k
  end
  local c = comparer.Compare
  local compare
  if descending then
    compare = function(x, y)
      return -c(comparer, getKey(x), getKey(y))
    end
  else
    compare = function(x, y)
      return c(comparer, getKey(x), getKey(y))
    end
  end
  return ordered(source, compare)
end

function Enumerable.OrderBy(source, keySelector, comparer, TKey)
  return orderBy(source, keySelector, comparer, TKey, false)
end

function Enumerable.OrderByDescending(source, keySelector, comparer, TKey)
  return orderBy(source, keySelector, comparer, TKey, true)
end

local function thenBy(source, keySelector, comparer, TKey, descending)
  if source == nil then throw(ArgumentNullException("source")) end
  if keySelector == nil then throw(ArgumentNullException("keySelector")) end
  if comparer == nil then comparer = Comparer_1(TKey).getDefault() end
  local keys = {}
  local function getKey(t) 
    local k = keys[t]
    if k == nil then
      k = keySelector(t)
      keys[t] = k
    end
    return k
  end
  local c = comparer.Compare
  local compare
  local parentSource, parentCompare = source.source, source.compare
  if descending then
    compare = function(x, y)
      local v = parentCompare(x, y)
      if v ~= 0 then
        return v
      else
        return -c(comparer, getKey(x), getKey(y))
      end
    end
  else
    compare = function(x, y)
      local v = parentCompare(x, y)
      if v ~= 0 then
        return v
      else
        return c(comparer, getKey(x), getKey(y))
      end
    end
  end
  return ordered(parentSource, compare)
end

function Enumerable.ThenBy(source, keySelector, comparer, TKey)
  return thenBy(source, keySelector, comparer, TKey, false)
end

function Enumerable.ThenByDescending(source, keySelector, comparer, TKey)
  return thenBy(source, keySelector, comparer, TKey, true)
end

local function groupBy(source, keySelector, elementSelector, comparer, TKey, TElement)
  if source == nil then throw(ArgumentNullException("source")) end
  if keySelector == nil then throw(ArgumentNullException("keySelector")) end
  if elementSelector == nil then throw(ArgumentNullException("elementSelector")) end
  return createEnumerable(IGrouping, function()
    return createLookup(source, keySelector, elementSelector, comparer, TKey, TElement):GetEnumerator()
  end)
end

function Enumerable.GroupBy(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  if len == 2 then
    local keySelector, TKey = ...
    return groupBy(source, keySelector, identityFn, nil, TKey, source.__genericT__)
  elseif len == 3 then
    local keySelector, comparer, TKey = ...
    return groupBy(source, keySelector, identityFn, comparer, TKey, source.__genericT__)
  elseif len == 4 then
    local keySelector, elementSelector, TKey, TElement = ...
    return groupBy(source, keySelector, elementSelector, nil, TKey, TElement)
  else
    return groupBy(source, ...)
  end
end

local function groupBySelect(source, keySelector, elementSelector, resultSelector, comparer, TKey, TElement, TResult)
  if source == nil then throw(ArgumentNullException("source")) end
  if keySelector == nil then throw(ArgumentNullException("keySelector")) end
  if elementSelector == nil then throw(ArgumentNullException("elementSelector")) end
  if resultSelector == nil then throw(ArgumentNullException("resultSelector")) end
  return createEnumerable(TResult, function()
    local lookup = createLookup(source, keySelector, elementSelector, comparer, TKey, TElement)
    return createEnumerator(TResult, lookup, function(en)
      if en:MoveNext() then
        local current = en:getCurrent()
        return resultSelector(current.key, current)
      end
      return false
    end)
  end)
end

function Enumerable.GroupBySelect(source, ...)
  local len = select("#", ...)
  if len == 4 then
    local keySelector, resultSelector, TKey, TResult = ...
    return groupBySelect(source, keySelector, identityFn, resultSelector, nil, TKey, source.__genericT__, TResult)
  elseif len == 5 then
    local keySelector, resultSelector, comparer, TKey, TResult = ...
    return groupBySelect(source, keySelector, identityFn, resultSelector, comparer, TKey, source.__genericT__, TResult)
  elseif len == 6 then
    local keySelector, elementSelector, resultSelector, TKey, TElement, TResult = ...
    return groupBySelect(source, keySelector, elementSelector, resultSelector, nil, TKey, TElement, TResult)
  else
    return groupBySelect(source, ...)
  end
end

function Enumerable.Concat(first, second)
  if first == nil then throw(ArgumentNullException("first")) end
  if second == nil then throw(ArgumentNullException("second")) end
  local T = first.__genericT__
  return createEnumerable(T, function()
    local secondEn
    return createEnumerator(T, first, function(en)
      if secondEn == nil then
        if en:MoveNext() then
          return true, en:getCurrent()
        end
        secondEn = second:GetEnumerator()
      end
      if secondEn:MoveNext() then
        return true, secondEn:getCurrent()
      end
      return false
    end)
  end)
end

function Enumerable.Zip(first, second, resultSelector, TResult) 
  if first == nil then throw(ArgumentNullException("first")) end
  if second == nil then throw(ArgumentNullException("second")) end
  if resultSelector == nil then throw(ArgumentNullException("resultSelector")) end
  return createEnumerable(TResult, function()
    local e2
    return createEnumerator(TResult, first, function(e1)
      if e1:MoveNext() and e2:MoveNext() then
          return true, resultSelector(e1:getCurrent(), e2:getCurrent())
      end
    end, 
    function()
      e2 = second:GetEnumerator()
    end)
  end)
end

local function addToSet(set, v, getHashCode, comparer)
  local hashCode = getHashCode(comparer, v)
  if set[hashCode] == nil then
    set[hashCode] = true
    return true
  end
  return false
end

local function removeFromSet(set, v, getHashCode, comparer)
  local hashCode = getHashCode(comparer, v)
  if set[hashCode] ~= nil then
    set[hashCode] = nil
    return true
  end
  return false
end

local function getComparer(source, comparer)
  return comparer or EqualityComparer(source.__genericT__).getDefault()
end

function Enumerable.Distinct(source, comparer)
  if source == nil then throw(ArgumentNullException("source")) end
  local T = source.__genericT__
  return createEnumerable(T, function()
    local set = {}
    comparer = getComparer(source, comparer)
    local getHashCode = comparer.GetHashCodeOf
    return createEnumerator(T, source, function(en)
      while en:MoveNext() do
        local current = en:getCurrent()
        if addToSet(set, current, getHashCode, comparer) then
          return true, current  
        end
      end
      return false
    end)
  end)
end

function Enumerable.Union(first, second, comparer)
  if first == nil then throw(ArgumentNullException("first")) end
  if second == nil then throw(ArgumentNullException("second")) end
  local T = first.__genericT__
  return createEnumerable(T, function()
    local set = {}
    comparer = getComparer(first, comparer)
    local getHashCode = comparer.GetHashCodeOf
    local secondEn
    return createEnumerator(T, first, function(en)
      if secondEn == nil then
        while en:MoveNext() do
          local current = en:getCurrent()
          if addToSet(set, current, getHashCode, comparer) then
            return true, current  
          end
        end
        secondEn = second:GetEnumerator()
      end
      while secondEn:MoveNext() do
        local current = secondEn:getCurrent()
        if addToSet(set, current, getHashCode, comparer) then
          return true, current  
        end
      end
      return false
    end)
  end)
end

function Enumerable.Intersect(first, second, comparer)
  if first == nil then throw(ArgumentNullException("first")) end
  if second == nil then throw(ArgumentNullException("second")) end
  local T = first.__genericT__
  return createEnumerable(T, function()
    local set = {}
    comparer = getComparer(first, comparer)
    local getHashCode = comparer.GetHashCodeOf
    return createEnumerator(T, first, function(en)
      while en:MoveNext() do
        local current = en:getCurrent()
        if removeFromSet(set, current, getHashCode, comparer) then
          return true, current
        end
      end
      return false
    end,
    function()
      for _, v in each(second) do
        addToSet(set, v, getHashCode, comparer)
      end
    end)
  end) 
end

function Enumerable.Except(first, second, comparer)
  if first == nil then throw(ArgumentNullException("first")) end
  if second == nil then throw(ArgumentNullException("second")) end
  local T = first.__genericT__
  return createEnumerable(T, function()
    local set = {}
    comparer = getComparer(first, comparer)
    local getHashCode = comparer.GetHashCodeOf
    return createEnumerator(T, first, function(en) 
      while en:MoveNext() do
        local current = en:getCurrent()
        if addToSet(set, current, getHashCode, comparer) then
          return true, current  
        end
      end
      return false
    end,
    function()
      for _, v in each(second) do
        addToSet(set, v, getHashCode, comparer)
      end
    end)
  end)
end

function Enumerable.Reverse(source)
  if source == nil then throw(ArgumentNullException("source")) end
  local T = source.__genericT__
  return createEnumerable(T, function()
    local t = {}    
    local index
    return createEnumerator(T, nil, function() 
      if index > 1 then
        index = index - 1
        return true, t[index]
      end
      return false
    end,
    function()
      local count = 1
      for _, v in each(source) do
        t[count] = v
        count = count + 1
      end  
      index = count
    end)
  end)
end

function Enumerable.SequenceEqual(first, second, comparer)
  if first == nil then throw(ArgumentNullException("first")) end
  if second == nil then throw(ArgumentNullException("second")) end
  comparer = getComparer(first, comparer)
  local equals = comparer.EqualsOf
  local e1 = first:GetEnumerator()
  local e2 = second:GetEnumerator()
  while e1:MoveNext() do
    if not(e2:MoveNext() and equals(comparer, e1:getCurrent(), e2:getCurrent())) then
      return false
    end
  end
  if e2:MoveNext() then
    return false
  end
  return true
end

Enumerable.ToArray = Array.toArray

function Enumerable.ToList(source)
  return System.List(source.__genericT__)(source)
end

local function toDictionary(source, keySelector, elementSelector, comparer, TKey, TValue)
  if source == nil then throw(ArgumentNullException("source")) end
  if keySelector == nil then throw(ArgumentNullException("keySelector")) end
  if elementSelector == nil then throw(ArgumentNullException("elementSelector")) end
  local dict = System.Dictionary(TKey, TValue)(comparer)
  for _, v in each(source) do
    dict:Add(keySelector(v), elementSelector(v))
  end
  return dict
end

function Enumerable.ToDictionary(source, ...)
  local len = select("#", ...)
  if len == 2 then
    local keySelector, TKey = ...
    return toDictionary(source, keySelector, identityFn, nil, TKey, source.__genericT__)
  elseif len == 3 then
    local keySelector, comparer, TKey = ...
    return toDictionary(source, keySelector, identityFn, comparer, TKey, source.__genericT__)
  elseif len == 4 then
    local keySelector, elementSelector, TKey, TElement = ...
    return toDictionary(source, keySelector, elementSelector, nil, TKey, TElement)
  else
    return toDictionary(source, ...)
  end
end

local function toLookup(source, keySelector, elementSelector, comparer, TKey, TElement )
  if source == nil then throw(ArgumentNullException("source")) end
  if keySelector == nil then throw(ArgumentNullException("keySelector")) end
  if elementSelector == nil then throw(ArgumentNullException("elementSelector")) end
  return createLookup(source, keySelector, elementSelector, comparer, TKey, TElement)
end

function Enumerable.ToLookup(source, ...)
  local len = select("#", ...)
  if len == 2 then
    local keySelector, TKey = ...
    return toLookup(source, keySelector, identityFn, nil, TKey, source.__genericT__)
  elseif len == 3 then
    local keySelector, comparer, TKey = ...
    return toLookup(source, keySelector, identityFn, comparer, TKey, source.__genericT__)
  elseif len == 4 then
    local keySelector, elementSelector, TKey, TElement = ...
    return toLookup(source, keySelector, elementSelector, nil, TKey, TElement)
  else
    return toLookup(source, ...)
  end
end

function Enumerable.DefaultIfEmpty(source)
  if source == nil then throw(ArgumentNullException("source")) end
  local T = source.__genericT__
  local state 
  return createEnumerable(T, function()
    return createEnumerator(T, source, function(en)
      if not state then
        if en:MoveNext() then
          state = 1
          return true, en:getCurrent()
        end
        state = 2
        return true, T:default()
      elseif state == 1 then
        if en:MoveNext() then
          return true, en:getCurrent()
        end
      end
      return false
    end)
  end)
end

function Enumerable.OfType(source, T)
  if source == nil then throw(ArgumentNullException("source")) end
  return createEnumerable(T, function()
    return createEnumerator(T, source, function(en) 
      while en:MoveNext() do
        local current = en:getCurrent()
        if is(current, T) then
          return true, current
        end
      end
      return false
    end)
  end)
end

function Enumerable.Cast(source, T)
  if source == nil then throw(ArgumentNullException("source")) end
  if is(source, IEnumerable_1(T)) then return source end
  return createEnumerable(T, function()
    return createEnumerator(T, source, function(en) 
      if en:MoveNext() then
        return true, cast(T, en:getCurrent())
      end
      return false
    end)
  end)
end

local function first(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  if len == 0 then
    if isArrayLike(source) then
      local count = #source
      if count > 0 then
        return true, unWrap(source[1])
      end
    else
      local en = source:GetEnumerator()
      if en:MoveNext() then 
        return true, en:getCurrent()
      end
    end
    return false, 0
  else
    local predicate = ...
    if predicate == nil then throw(ArgumentNullException("predicate")) end
    for _, v in each(source) do
      if predicate(v) then 
        return true, v
      end
    end
    return false, 1
  end
end

function Enumerable.First(source, ...)
  local ok, result = first(source, ...)
  if ok then return result end
  if result == 0 then
    throw(InvalidOperationException("NoElements"))
  end
  throw(InvalidOperationException("NoMatch"))
end

function Enumerable.FirstOrDefault(source, ...)
  local ok, result = first(source, ...)
  return ok and result or source.__genericT__:default()
end

local function last(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  if len == 0 then
    if isArrayLike(source) then
      local count = #source
      if count > 0 then
        return true, unWrap(source[count])
      end
    else
      local en = source:GetEnumerator()
      if en:MoveNext() then 
        local result
        repeat
          result = en:getCurrent()
        until not en:MoveNext()
        return true, result
      end
    end
    return false, 0
  else
    local predicate = ...
    if predicate == nil then throw(ArgumentNullException("predicate")) end
    local result, found
    for _, v in each(source) do
      if predicate(v) then
        result = v
        found = true
      end
    end    
    if found then return true, result end
    return false, 1
  end
end

function Enumerable.Last(source, ...)
  local ok, result = last(source, ...)
  if ok then return result end
  if result == 0 then
    throw(InvalidOperationException("NoElements"))
  end
  throw(InvalidOperationException("NoMatch"))
end

function Enumerable.LastOrDefault(source, ...)
  local ok, result = last(source, ...)
  return ok and result or source.__genericT__:default()
end

local function single(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  if len == 0 then
    if isArrayLike(source) then
      local count = #source
      if count == 0 then
        return false, 0
      elseif count == 1 then
        return true, unWrap(source[1])
      end
    else
      local en = source:GetEnumerator()
      if not en:MoveNext() then return false, 0 end
      local result = en:getCurrent()
      if not en:MoveNext() then
        return true, result
      end
    end
    return false, 1
  else
    local predicate = ...
    if predicate == nil then throw(ArgumentNullException("predicate")) end
    local result, found
    for _, v in each(source) do
      if predicate(v) then
        result = v
        if found then
          return false, 1
        end
        found = true
      end
    end
    if foun then return true, result end    
    return false, 0    
  end
end

function Enumerable.Single(source, ...)
  local ok, result = single(source, ...)
  if ok then return result end
  if result == 0 then
    throw(InvalidOperationException("NoElements"))
  end
  throw(InvalidOperationException("MoreThanOneMatch"))
end

function Enumerable.SingleOrDefault(source, ...)
  local ok, result = single(source, ...)
  return ok and result or source.__genericT__:default()
end

local function elementAt(source, index)
  if source == nil then throw(ArgumentNullException("source")) end
  if index >= 0 then
    if isArrayLike(source) then
      local count = #source
      if index < count then
        return true, unWrap(source[index + 1])
      end
    else
      local en = source:GetEnumerator()
      while true do
        if not en:MoveNext() then break end
        if index == 0 then return true, en:getCurrent() end
        index = index - 1
      end
    end
  end
  return false
end

function Enumerable.ElementAt(source, index)
  local ok, result = elementAt(source, index)
  if ok then return result end
  throw(ArgumentOutOfRangeException("index"))
end

function Enumerable.ElementAtOrDefault(source, index)
  local ok, result = elementAt(source, index)
  return ok and result or source.__genericT__:default()
end

function Enumerable.Range(start, count)
  if count < 0 then throw(ArgumentOutOfRangeException("count")) end
  return createEnumerable(Int32, function()
    local index = -1
    return createEnumerator(Int32, nil, function()
      index = index + 1
      if index < count then
        return true, start + index  
      end
      return false
    end)
  end)
end

function Enumerable.Repeat(element, count, T)
  if count < 0 then throw(ArgumentOutOfRangeException("count")) end
  return createEnumerable(T, function()
    local index = -1
    return createEnumerator(T, nil, function()
      index = index + 1
      if index < count then
        return true, element  
      end
      return false
    end)
  end)
end

function Enumerable.Any(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  if len == 0 then
    local en = source:GetEnumerator()
    return en:MoveNext()
  else
    local predicate = ...
    if predicate == nil then throw(ArgumentNullException("predicate")) end
    for _, v in each(source) do
      if predicate(v) then
        return true
      end
    end
    return false
  end
end

function Enumerable.All(source, predicate)
  if source == nil then throw(ArgumentNullException("source")) end
  if predicate == nil then throw(ArgumentNullException("predicate")) end
  for _, v in each(source) do
    if not predicate(v) then
      return false
    end
  end
  return true
end

function Enumerable.Count(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  if len == 0 then
    if isArrayLike(source) then
      return #source
    end
    local count = 0
    local en = source:GetEnumerator()
    while en:MoveNext() do 
      count = count + 1 
    end
    return count
  else
    local predicate = ...
    if predicate == nil then throw(ArgumentNullException("predicate")) end
    local count = 0
    for _, v in each(source) do
      if predicate(v) then
        count = count + 1
      end
    end
    return count
  end
end

function Enumerable.Contains(source, value, comparer)
  if source == nil then throw(ArgumentNullException("source")) end
  comparer = getComparer(source, comparer)
  local equals = comparer.EqualsOf
  for _, v in each(source) do
    if equals(comparer, v, value) then
      return true
    end
  end
  return false
end

function Enumerable.Aggregate(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...);
  if len == 1 then
    local func = ...
    if func == nil then throw(ArgumentNullException("func")) end
    local e = source:GetEnumerator()
    if not e:MoveNext() then throw(InvalidOperationException("NoElements")) end
    local result = e:getCurrent()
    while e:MoveNext() do
      result = func(result, e:getCurrent())
    end
    return result
  elseif len == 2 then
    local seed, func = ...
    if func == nil then throw(ArgumentNullException("func")) end
    local result = seed
    for _, element in each(source) do
      result = func(result, element)
    end
    return result
  else 
    local seed, func, resultSelector = ...
    if func == nil then throw(ArgumentNullException("func")) end
    if resultSelector == nil then throw(ArgumentNullException("resultSelector")) end
    local result = seed
    for _, element in each(source) do
      result = func(result, element)
    end
    return resultSelector(result)
  end
end

function Enumerable.Sum(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  if len == 0 then
    local sum = 0
    for _, v in each(source) do
      sum = sum + v
    end
    return sum
  else
    local selector = ...
    if selector == nil then throw(ArgumentNullException("selector")) end
    local sum = 0
    for _, v in each(source) do
      sum = sum + selector(v)
    end
    return sum
  end
end

local function minOrMax(compareFn, source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local len = select("#", ...)
  local selector, T 
  if len == 0 then
    selector, T = identityFn, source.__genericT__
  else
    selector, T = ...
    if selector == nil then throw(ArgumentNullException("selector")) end
  end
  local comparer = Comparer_1(T).getDefault()
  local compare = comparer.Compare
  local value = T:default()
  if value == nil then
    for _, x in each(source) do
      x = selector(x)
      if x ~= nil and (value == nil or compareFn(compare, comparer, x, value)) then
        value = x
      end 
    end
    return value
  else
    local hasValue = false
    for _, x in each(source) do
      x = selector(x)
      if hasValue then
        if compareFn(compare, comparer, x, value) then
          value = x
        end
      else
        value = x
        hasValue = true
      end
    end
    if hasValue then return value end
    throw(InvalidOperationException("NoElements"))
  end
end

local function minFn(compare, comparer, x, y)
  return compare(comparer, x, y) < 0
end

function Enumerable.Min(source, ...)
  return minOrMax(minFn, source, ...)
end

local function maxFn(compare, comparer, x, y)
  return compare(comparer, x, y) > 0
end

function Enumerable.Max(source, ...)
  return minOrMax(maxFn, source, ...)
end

function Enumerable.Average(source, ...)
  if source == nil then throw(ArgumentNullException("source")) end
  local sum, count = 0, 0
  local len = select("#", ...)
  if len == 0 then
    for _, v in each(source) do
      sum = sum + v
      count = count + 1
    end
  else
    local selector = ...
    if selector == nil then throw(ArgumentNullException("selector")) end
    for _, v in each(source) do
      sum = sum + selector(v)
      count = count + 1
    end
  end
  if count > 0 then
    return sum / count
  end
  throw(InvalidOperationException("NoElements"))
end
end

-- CoreSystemLib: Convert.lua
do
local System = System
local throw = System.throw
local cast = System.cast
local as = System.as
local trunc = System.trunc
local define = System.define
local band = System.band
local bor = System.bor
local sl = System.sl
local sr = System.sr
local div = System.div
local identityFn = System.identityFn
local IConvertible = System.IConvertible
local systemToString = System.toString
local checkIndex = System.checkIndexAndCount

local OverflowException = System.OverflowException
local FormatException = System.FormatException
local ArgumentException = System.ArgumentException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local ArgumentNullException = System.ArgumentNullException
local InvalidCastException = System.InvalidCastException

local SByte = System.SByte
local Byte = System.Byte
local Int16 = System.Int16
local UInt16 = System.UInt16
local Int32 = System.Int32
local UInt32 = System.UInt32
local Int64 = System.Int64
local UInt64 = System.UInt64
local Single = System.Single
local Double = System.Double
local Boolean = System.Boolean
local Char = System.Char
local DateTime = System.DateTime
local String = System.String
local Object = System.Object

local ParseSByte = SByte.Parse
local ParseByte = Byte.Parse
local ParseInt16 = Int16.Parse
local ParseUInt16 = UInt16.Parse
local ParseInt32 = Int32.Parse
local ParseUInt32 = UInt32.Parse
local ParseInt64 = Int64.Parse
local ParseUInt64 = UInt64.Parse

local ParseSingle = Single.Parse
local ParseDouble = Double.Parse
local ParseBoolean = Boolean.Parse

local type = type
local string = string
local sbyte = string.byte
local math = math
local floor = math.floor
local tconcat = table.concat
local setmetatable = setmetatable
local getmetatable = getmetatable
local tonumber = tonumber
local select = select

local function toBoolean(value)
  if value == nil then return false end
  local typename = type(value)
  if typename == "number" then
    return value ~= 0
  elseif typename == "string" then
    return ParseBoolean(value)  
  elseif typename == "boolean" then
    return value
  else
    return cast(IConvertible, value):ToBoolean()   
  end
end

local function toChar(value)
  if value == nil then return 0 end
  local typename = type(value)
  if typename == "number" then
    if value ~= floor(value) or value > 9223372036854775807 or value < (-9223372036854775807 - 1) then
      throw(InvalidCastException("InvalidCast_FromTo_Char"))
    end
    if value < 0 or value > 65535 then 
      throw(OverflowException("Overflow_Char")) 
    end
    return value
  elseif typename == "string" then
    if #value ~= 1 then
      throw(FormatException("Format_NeedSingleChar"))
    end
    return sbyte(value)
  else
    return cast(IConvertible, value):ToChar()
  end
end

local function parseBits(s, p, n)
  local i, j, v = s:find(p)
  if not i then
    throw(FormatException())
  end
  v = tonumber(v)
  for i = j + 1, #s do
    local ch = sbyte(s, i)
    local b = ch - 48
    if b < 0 or b >= n then
      if not s:find("^%s*$", i) then
        throw(FormatException())
      end
      break
    end
    v = v * n + b
  end
  return v
end

local function parseNumberFromBase(value, fromBase, min, max)
  if fromBase == 2 then
    value = parseBits(value, "^%s*([01])", fromBase)
  elseif fromBase == 8 then
    value = parseBits(value, "^%s*([0-7])", fromBase)
  elseif fromBase == 16 then
    local _, _, v = value:find("^%s*(%w+)%s*$")
    if not v then
      throw(ArgumentException("String cannot contain a minus sign if the base is not 10."))
    end
    local ch = sbyte(v, 2)
    if ch == 120 or ch == 88 then
    else
      v = "0x" .. v
    end
    value = tonumber(v)
    if value == nil then
      throw(FormatException())
    end
  else
    throw(ArgumentException("fromBase")) 
  end
  if max == 127 and value <= 255 then
    return System.toSByte(value)
  end
  if max == 32767 and value <= 65535 then
    return System.toInt16(value)
  end
  if max == 2147483647 and value <= 4294967295 then
    return System.toInt32(value)
  end
  if value < min or value > max then
    throw(OverflowException())
  end
  return value
end

local function toNumber(value, min, max, parse, objectTo, sign)
  if value == nil then return 0 end
  local typename = type(value)
  if typename == "number" then
    if sign == false then
      value = System.ToSingle(value * 1.0)
    elseif sign == true then
      value = value * 1.0
    else
      local i = value
      value = trunc(value)
      if value ~= i then
        local dif = i - value
        if value >= 0 then
          if dif > 0.5 or (dif == 0.5 and value % 2 ~= 0) then
            value = value + 1  
          end
        else
          if dif < -0.5 or (dif == -0.5 and value % 2 ~= 0) then
            value = value - 1  
          end
        end
      end
      if value < min or value > max then
        throw(OverflowException())
      end
    end
    return value
  elseif typename == "string" then
    if sign and sign ~= 10 and type(sign) == "number" then
      return parseNumberFromBase(value, sign, min, max)
    end
    return parse(value) 
  elseif typename == "boolean" then
    return value and 1 or 0
  else
    return objectTo(value)
  end
end

local function objectToSByte(value)
  return cast(IConvertible, value):ToSByte()
end

local function toSByte(value, fromBase)
  return toNumber(value, -128, 127, ParseSByte, objectToSByte, fromBase)
end

local function objectToByte(value)
  return cast(IConvertible, value):ToByte()
end

local function toByte(value, fromBase)
  return toNumber(value, 0, 255, ParseByte, objectToByte, fromBase) 
end

local function objectToInt16(value)
  return cast(IConvertible, value):ToInt16()
end

local function toInt16(value, fromBase)
  return toNumber(value, -32768, 32767, ParseInt16, objectToInt16, fromBase) 
end

local function objectToUInt16(value)
  return cast(IConvertible, value):ToUInt16()
end

local function toUInt16(value, fromBase)
  return toNumber(value, 0, 65535, ParseUInt16, objectToUInt16, fromBase) 
end

local function objectToInt32(value)
  return cast(IConvertible, value):ToInt32()
end

local function toInt32(value, fromBase)
  return toNumber(value, -2147483648, 2147483647, ParseInt32, objectToInt32, fromBase) 
end

local function objectToUInt32(value)
  return cast(IConvertible, value):ToUInt32()
end

local function toUInt32(value, fromBase)
  return toNumber(value, 0, 4294967295, ParseUInt32, objectToUInt32, fromBase) 
end

local function objectToInt64(value)
  return cast(IConvertible, value):ToInt64()
end

local function toInt64(value, fromBase)
  return toNumber(value, (-9223372036854775807 - 1), 9223372036854775807, ParseInt64, objectToInt64, fromBase) 
end

local function objectToUInt64(value)
  return cast(IConvertible, value):ToUInt64()
end

local function toUInt64(value, fromBase)
  return toNumber(value, 0, 18446744073709551615.0, ParseUInt64, objectToUInt64, fromBase) 
end

local function objectToSingle(value)
  return cast(IConvertible, value):ToSingle()
end

local function toSingle(value)
  return toNumber(value, nil, nil, ParseSingle, objectToSingle, false) 
end

local function objectToDouble(value)
  return cast(IConvertible, value):ToDouble()
end

local function toDouble(value)
  return toNumber(value, nil, nil, ParseDouble, objectToDouble, true) 
end

local function toDateTime(value)
  if value == nil then return DateTime.MinValue end
  if getmetatable(value) == DateTime then return value end
  if type(value) == "string" then return DateTime.Parse(value) end
  return cast(IConvertible, value):ToDateTime()
end

local function toBaseType(ic, targetType)
  local cls = targetType[1]
  if cls == Boolean then return ic:ToBoolean() end
  if cls == Char then return ic:ToChar() end
  if cls == SByte then return ic:ToSByte() end
  if cls == Byte then return ic:ToByte() end
  if cls == Int16 then return ic:ToInt16() end
  if cls == UInt16 then return ic:ToUInt16() end
  if cls == Int32 then return ic:ToInt32() end
  if cls == UInt32 then return ic:ToUInt32() end
  if cls == Int64 then return ic:ToInt64() end
  if cls == UInt64 then return ic:ToUInt64() end
  if cls == Single then return ic:ToSingle() end
  if cls == Double then return ic:ToDouble() end
  if cls == DateTime then return ic:ToDateTime() end
  if cls == String then return ic:ToString() end
  if cls == Object then return value end
end

local function defaultToType(value, targetType)
  if targetType == nil then throw(ArgumentNullException("targetType")) end
  if value:GetType() == targetType then return value end
  local v = toBaseType(value, targetType)
  if v ~= nil then
    return v
  end
  throw(InvalidCastException())
end

local function changeType(value, conversionType)
  if conversionType == nil then
    throw(ArgumentNullException("conversionType"))
  end
  if value == nil then
    if conversionType:getIsValueType() then
      throw(InvalidCastException("InvalidCast_CannotCastNullToValueType"))
    end
    return nil
  end
  local ic = as(value, IConvertible)
  if ic == nil then
    if value:GetType() == conversionType then
      return value
    end
    throw(InvalidCastException("InvalidCast_IConvertible"))
  end
  local v = toBaseType(ic, conversionType)
  if v ~= nil then
    return v
  end
  return ic.ToType(conversionType)
end

local rexp
if math.frexp then
  rexp = function (x)
    local _, v = math.frexp(x)
    return v
  end
else
  local abs, log = math.abs, math.log
  local log2 = log(2)
  rexp = function (x)
    return floor(log(abs(x)) / log2) + 1
  end
end

local function toBits(num, bits)
  -- returns a table of bits, most significant first.
  bits = bits or math.max(1, rexp(num))
  local t = {} -- will contain the bits        
  for b = bits, 1, -1 do
    local i =  num % 2
    t[b] = i
    num = div(num - i, 2)
  end
  if bits == 64 and t[1] == 0 then
    return tconcat(t, nil, 2, bits)
  end
  return tconcat(t)
end

local function toString(value, toBaseOrProvider, cast)
  if value == nil then
    return ""
  end
  if toBaseOrProvider then
    if type(toBaseOrProvider) == "number" then
      if toBaseOrProvider ~= 10 then
        if cast and value < 0 then
          value = cast(value)
        end
      end
      if toBaseOrProvider == 2 then
        return toBits(value)
      elseif toBaseOrProvider == 8 then
        return ("%o"):format(value)
      elseif toBaseOrProvider == 10 then
        return value .. ""
      elseif toBaseOrProvider == 16 then
        return ("%x"):format(value)
      else
        throw(ArgumentException())
      end
    end
  end
  return systemToString(value)
end

local base64Table = {'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O',
                      'P','Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d',
                      'e','f','g','h','i','j','k','l','m','n','o','p','q','r','s',
                      't','u','v','w','x','y','z','0','1','2','3','4','5','6','7',
                      '8','9','+','/','=' };

local function toBase64String(t, ...)
  if t == nil then throw(ArgumentNullException("inArray")) end
  local n = select("#", ...)
  local offset, length, options
  if n == 0 then
    offset, length, options = 0, #t, 0
  elseif n == 1 then
    offset, length, options = 0, #t, ...
  elseif n == 2 then
    options, offset, length = 0, ...
    checkIndex(t, offset, length)
  else
    offset, length, options = ...
    checkIndex(t, offset, length)
  end
  local insertLineBreaks, lengthmod3, outChars  = options == 1, length % 3, {}
  local calcLength, j, charcount = offset + (length - lengthmod3), 1, 0
  local i = offset
  while i < calcLength do
    if insertLineBreaks then
      if charcount == 76 then
        outChars[j] = "\r\n"
        j = j + 1
        charcount = 0
      end
      charcount = charcount + 4
    end
    local a, b, c = t:get(i), t:get(i + 1), t:get(i + 2)
    outChars[j] =  base64Table[sr(band(a, 0xfc), 2) + 1]
    outChars[j + 1] = base64Table[bor(sl(band(a, 0x03), 4), sr(band(b, 0xf0), 4)) + 1]
    outChars[j + 2] = base64Table[bor(sl(band(b, 0x0f), 2), sr(band(c, 0xc0), 6)) + 1]
    outChars[j + 3] = base64Table[band(c, 0x3f) + 1]
    j = j + 4
    i = i + 3
  end

  i = calcLength
  if insertLineBreaks and lengthmod3 ~= 0 and charcount == 76 then
    outChars[j] = "\r\n"
    j = j + 1
  end
  
  if lengthmod3 == 2 then
    local a, b = t:get(i), t:get(i + 1)
    outChars[j] =  base64Table[sr(band(a, 0xfc), 2) + 1]
    outChars[j + 1] = base64Table[bor(sl(band(a, 0x03), 4), sr(band(b, 0xf0), 4)) + 1]
    outChars[j + 2] = base64Table[sl(band(b, 0x0f), 2) + 1]
    outChars[j + 3] = '='
  elseif lengthmod3 == 1 then
    local a = t:get(i)
    outChars[j] =  base64Table[sr(band(a, 0xfc), 2) + 1]
    outChars[j + 1] = base64Table[sl(band(a, 0x03), 4) + 1]
    outChars[j + 2] = '='
    outChars[j + 3] = '='
  end
  return tconcat(outChars)
end

local function fromBase64ComputeResultLength(s, len)
  local usefulInputLength, padding = len, 0
  for i = 1, len do
    local c = sbyte(s, i)
    if c <= 32 then
      usefulInputLength = usefulInputLength - 1
    elseif c == 61 then
      usefulInputLength = usefulInputLength - 1
      padding = padding + 1
    end
  end
  if padding ~= 0 then
    if padding == 1 then
      padding = 2
    elseif padding == 2 then
      padding = 1
    else
      throw(FormatException("Format_BadBase64Char"))
    end
  end
  return div(usefulInputLength, 4) * 3 + padding
end

local function FromBase64Decode(s, len, t, resultLength)
  local i, j, codes, c, gotoEqualityCharEncountered = 1, 0, 0x000000ff
  while true do
    if i > len then
      break
    end
    c = sbyte(s, i)
    i = i + 1
    if c >= 65 then
      if c <= 90 then
        c = c - 65
      elseif c <= 122 then
        c = c - 71 
      end
    else
      if c == 43 then
        c = 62
      elseif c == 47 then
        c = 63
      elseif c == 13 or c == 10 or c == 32 or c == 9 then
      elseif c == 61 then
        gotoEqualityCharEncountered = true
        break
      else
        throw(FormatException("Format_BadBase64Char"))
      end
    end
    codes = bor(sl(codes, 6), c)
    if (band(codes, 0x80000000)) ~= 0 then
      if resultLength - j < 3 then
        return - 1
      end
      t[j + 1] = band(sr(codes, 16), 0xff)
      t[j + 2] = band(sr(codes, 8), 0xff)
      t[j + 3] = band(codes, 0xff)
      j = j + 3
      codes = 0x000000ff
    end
  end

  if gotoEqualityCharEncountered then
    if i > len then
      codes = sl(codes, 6)
      if (band(codes, 0x80000000)) == 0 then
        throw(FormatException("Format_BadBase64CharArrayLength"))
      end

      if j < 2 then
        return - 1
      end

      t[j + 1] = band(sr(codes, 16), 0xff)
      t[j + 2] = band(sr(codes, 8), 0xff)
      j = j + 2
      codes = 0x000000ff
    else
      while i < len do
        c = sbyte(s, i)
        if c ~= 32 and c ~= 10 and c ~= 13 and c ~= 9 then
          break
        end
        i = i + 1
      end

      if i == len and sbyte(s, i) == 61 then
        codes = sl(codes, 12)
        if (band(codes, 0x80000000)) == 0 then
          throw(FormatException(("Format_BadBase64CharArrayLength")))
        end

        if resultLength - j < 1 then
          return - 1
        end

        t[j + 1] = band(sr(codes, 16), 0xff)
        j = j + 1
        codes = 0x000000ff
      else
        System.throw(System.FormatException(("Format_BadBase64Char")))
      end
    end
  end

  if codes ~= 0x000000ff then
    throw(FormatException(("Format_BadBase64CharArrayLength")))
  end
  return j
end

local function fromBase64String(s)
  if s == nil then throw(ArgumentNullException("s")) end
  local len = #s
  while len > 0 do
    local lastChar = sbyte(s, len)
    if lastChar ~= 32 and lastChar ~= 10 and lastChar ~= 13 and lastChar ~= 9 then
      break
    end
    len = len - 1
  end
  local resultLength = fromBase64ComputeResultLength(s, len)
  local t = {}
  FromBase64Decode(s, len, t, resultLength)
  return System.arrayFromTable(t, Byte)
end

define("System.Convert", {
  ToBoolean = toBoolean,
  ToChar = toChar,
  ToSByte = toSByte,
  ToByte = toByte,
  ToInt16 = toInt16,
  ToUInt16 = toUInt16,
  ToInt32 = toInt32,
  ToUInt32 = toUInt32,
  ToInt64 = toInt64,
  ToUInt64 = toUInt64,
  ToSingle = toSingle,
  ToDouble = toDouble,
  ToDateTime = toDateTime,
  ToBase64String = toBase64String,
  FromBase64String = fromBase64String,
  ChangeType = changeType,
  ToString = toString,
  ToStringFromChar = string.char
})

String.ToBoolean = toBoolean
String.ToChar = toChar
String.ToSByte = toSByte
String.ToByte = toByte
String.ToInt16 = toInt16
String.ToUInt16 = toUInt16
String.ToInt32 = toInt32
String.ToUInt32 = toUInt32
String.ToInt64 = toInt64
String.ToUInt64 = toUInt64
String.ToSingle = identityFn
String.ToDouble = toDouble
String.ToDateTime = toDateTime
String.ToType = defaultToType

local function throwInvalidCastException()
  throw(InvalidCastException())
end

local Number = System.Number
Number.ToBoolean = toBoolean
Number.ToChar = toChar
Number.ToSByte = toSByte
Number.ToByte = toByte
Number.ToInt16 = toInt16
Number.ToUInt16 = toUInt16
Number.ToInt32 = toInt32
Number.ToUInt32 = toUInt32
Number.ToInt64 = toInt64
Number.ToUInt64 = toUInt64
Number.ToSingle = toSingle
Number.ToDouble = toDouble
Number.ToDateTime = throwInvalidCastException
Number.ToType = defaultToType

Boolean.ToBoolean = identityFn
Boolean.ToChar = throwInvalidCastException
Boolean.ToSByte = toSByte
Boolean.ToByte = toByte
Boolean.ToInt16 = toInt16
Boolean.ToUInt16 = toUInt16
Boolean.ToInt32 = toInt32
Boolean.ToUInt32 = toUInt32
Boolean.ToInt64 = toInt64
Boolean.ToUInt64 = toUInt64
Boolean.ToSingle = toSingle
Boolean.ToDouble = toDouble
Boolean.ToDateTime = throwInvalidCastException
Boolean.ToType = defaultToType

DateTime.ToBoolean = throwInvalidCastException
DateTime.ToChar = throwInvalidCastException
DateTime.ToSByte = throwInvalidCastException
DateTime.ToByte = throwInvalidCastException
DateTime.ToInt16 = throwInvalidCastException
DateTime.ToUInt16 = throwInvalidCastException
DateTime.ToInt32 = throwInvalidCastException
DateTime.ToUInt32 = throwInvalidCastException
DateTime.ToInt64 = throwInvalidCastException
DateTime.ToUInt64 = throwInvalidCastException
DateTime.ToSingle = throwInvalidCastException
DateTime.ToDouble = throwInvalidCastException
DateTime.ToDateTime = identityFn
DateTime.ToType = defaultToType

-- BitConverter
local global = System.global
local systemToInt16 = System.toInt16
local systemToInt32 = System.toInt32
local systemToUInt64 = System.toUInt64
local arrayFromTable = System.arrayFromTable
local NotSupportedException = System.NotSupportedException

local assert = assert
local rawget = rawget
local unpack = table.unpack
local schar = string.char

-- https://github.com/ToxicFrog/vstruct/blob/master/io/endianness.lua#L30
local isLittleEndian = true
local dump = string.dump
if dump and sbyte(dump(System.emptyFn), 7) == 0x00 then
  isLittleEndian = false
end


local function bytes(t)
  return arrayFromTable(t, Byte)    
end

local function checkIndex(value, startIndex, count)
  if value == nil then throw(ArgumentNullException("value")) end
  local len = #value
  if startIndex < 0 or startIndex >= len then
    throw(ArgumentOutOfRangeException("startIndex"))
  end
  if startIndex > len - count then
    throw(ArgumentException())
  end
end

local spack, sunpack, getBytesFromInt64, toInt64
if System.luaVersion < 5.3 then
  local struct = rawget(global, "struct")
  if struct then
    spack, sunpack = struct.pack, struct.unpack
  end
  if not spack then
    spack = function ()
      throw(NotSupportedException("not found struct"), 1) 
    end
    sunpack = spack
  end

  getBytesFromInt64 = function (value)
    if value <= -2147483647 or value >= 2147483647 then
      local s = spack("i8", value)
      return bytes({
        sbyte(s, 1),
        sbyte(s, 2),
        sbyte(s, 3),
        sbyte(s, 4),
        sbyte(s, 5),
        sbyte(s, 6),
        sbyte(s, 7),
        sbyte(s, 8)
      })
    end
    return bytes({
      band(value, 0xff),
      band(sr(value, 8), 0xff),
      band(sr(value, 16), 0xff),
      band(sr(value, 24), 0xff),
      0,
      0,
      0,
      0
    })
  end

  toInt64 = function (value, startIndex)
    checkIndex(value, startIndex, 8)
    if value <= -2147483647 or value >= 2147483647 then
      throw(System.NotSupportedException()) 
    end
    if isLittleEndian then
      local i = value[startIndex + 1]
      i = bor(i, sl(value[startIndex + 2], 8))
      i = bor(i, sl(value[startIndex + 3], 16))
      i = bor(i, sl(value[startIndex + 4], 24))
      return i
    else
      local i = value[startIndex + 8]
      i = bor(i, sl(value[startIndex + 7], 8))
      i = bor(i, sl(value[startIndex + 6], 16))
      i = bor(i, sl(value[startIndex + 5], 24))
      return i
    end
  end
else
  spack, sunpack = string.pack, string.unpack
  getBytesFromInt64 = function (value)
    return bytes({
      band(value, 0xff),
      band(sr(value, 8), 0xff),
      band(sr(value, 16), 0xff),
      band(sr(value, 24), 0xff),
      band(sr(value, 32), 0xff),
      band(sr(value, 40), 0xff),
      band(sr(value, 48), 0xff),
      band(sr(value, 56), 0xff)
    })
  end

  toInt64 = function (value, startIndex)
    checkIndex(value, startIndex, 8)
    if isLittleEndian then
      local i = value[startIndex + 1]
      i = bor(i, sl(value[startIndex + 2], 8))
      i = bor(i, sl(value[startIndex + 3], 16))
      i = bor(i, sl(value[startIndex + 4], 24))
      i = bor(i, sl(value[startIndex + 5], 32))
      i = bor(i, sl(value[startIndex + 6], 40))
      i = bor(i, sl(value[startIndex + 7], 48))
      i = bor(i, sl(value[startIndex + 8], 56))
      return i
    else
      local i = value[startIndex + 8]
      i = bor(i, sl(value[startIndex + 7], 8))
      i = bor(i, sl(value[startIndex + 6], 16))
      i = bor(i, sl(value[startIndex + 5], 24))
      i = bor(i, sl(value[startIndex + 4], 32))
      i = bor(i, sl(value[startIndex + 3], 40))
      i = bor(i, sl(value[startIndex + 2], 48))
      i = bor(i, sl(value[startIndex + 1], 56))
      return i
    end
  end
end

local function getBytesFromBoolean(value)
  return bytes({ value and 1 or 0 })
end

local function getBytesFromInt16(value)
  return bytes({
    band(value, 0xff),
    band(sr(value, 8), 0xff),
  })
end

local function getBytesFromInt32(value)
  return bytes({
    band(value, 0xff),
    band(sr(value, 8), 0xff),
    band(sr(value, 16), 0xff),
    band(sr(value, 24), 0xff)
  })
end

local function getBytesFromFloat(value)
  local s = spack("f", value)
  return bytes({
    sbyte(s, 1),
    sbyte(s, 2),
    sbyte(s, 3),
    sbyte(s, 4)
  })
end

local function getBytesFromDouble(value)
  local s = spack("d", value)
  return bytes({
    sbyte(s, 1),
    sbyte(s, 2),
    sbyte(s, 3),
    sbyte(s, 4),
    sbyte(s, 5),
    sbyte(s, 6),
    sbyte(s, 7),
    sbyte(s, 8)
  })
end

local function toBoolean(value, startIndex)
  checkIndex(value, startIndex, 1)
  return value[startIndex + 1] ~= 0 and true or false
end

local function toUInt16(value, startIndex)
  checkIndex(value, startIndex, 2)
  if isLittleEndian then
    value = bor(value[startIndex + 1], sl(value[startIndex + 2], 8))
  else
    value = bor(sl(value[startIndex + 1], 8), value[startIndex + 2])
  end
  return value
end

local function toInt16(value, startIndex)
  value = toUInt16(value, startIndex)
  return systemToInt16(value)
end

local function toUInt32(value, startIndex)
  checkIndex(value, startIndex, 4)
  local i
  if isLittleEndian then
    i = value[startIndex + 1]
    i = bor(i, sl(value[startIndex + 2], 8))
    i = bor(i, sl(value[startIndex + 3], 16))
    i = bor(i, sl(value[startIndex + 4], 24))
  else
    local i = value[startIndex + 4]
    i = bor(i, sl(value[startIndex + 3], 8))
    i = bor(i, sl(value[startIndex + 2], 16))
    i = bor(i, sl(value[startIndex + 1], 24))
  end
  return i
end

local function toInt32(value, startIndex)
  value = toUInt32(value, startIndex)
  return systemToInt32(value)
end

local function toUInt64(value, startIndex)
  value = toInt64(value, startIndex)
  return systemToUInt64(value)
end

local function toSingle(value, startIndex)
  checkIndex(value, startIndex, 4)
  return sunpack("f", schar(unpack(value, startIndex + 1)))
end

local function toDouble(value, startIndex)
  checkIndex(value, startIndex, 8)
  return sunpack("d", schar(unpack(value, startIndex + 1)))
end

local function getHexValue(i)
  assert(i >= 0 and i < 16, "i is out of range.")
  if i < 10 then
    return i + 48
  end
  return i - 10 + 65
end

local function toString(value, startIndex, length)
  if value == nil then throw(ArgumentNullException("value")) end
  local len = #value
  if not startIndex then
    startIndex, length = 0, #value
  elseif not length then
    length = len - startIndex
  end
  if startIndex < 0 or (startIndex >= len and startIndex > 0) then
    throw(ArgumentOutOfRangeException("startIndex"))
  end
  if length < 0 then
    throw(ArgumentOutOfRangeException("length"))
  end
  if startIndex + length > len then
    throw(ArgumentException())
  end
  if length == 0 then
    return ""
  end
  local t = {}
  local len = 1
  for i = startIndex + 1, startIndex + length  do
    local b = value[i]
    t[len] = getHexValue(div(b, 16))
    t[len + 1] = getHexValue(b % 16)
    t[len + 2] = 45
    len = len + 3
  end
  return schar(unpack(t, 1, len - 2))
end

local function doubleToInt64Bits(value)
  local s = spack("d", value)
  return (sunpack("i8", s))
end

local function int64BitsToDouble(value)
  local s = spack("i8", value)
  return (sunpack("d", s))
end

define("System.BitConverter", {
  IsLittleEndian = isLittleEndian,
  GetBytesFromBoolean = getBytesFromBoolean,
  GetBytesFromInt16 = getBytesFromInt16,
  GetBytesFromInt32 = getBytesFromInt32,
  GetBytesFromInt64 = getBytesFromInt64,
  GetBytesFromFloat = getBytesFromFloat,
  GetBytesFromDouble = getBytesFromDouble,
  ToBoolean = toBoolean,
  ToChar = toUInt16,
  ToInt16 = toInt16,
  ToUInt16 = toUInt16,
  ToInt32 = toInt32,
  ToUInt32 = toUInt32,
  ToInt64 = toInt64,
  ToUInt64 = toUInt64,
  ToSingle = toSingle,
  ToDouble = toDouble,
  ToString = toString,
  DoubleToInt64Bits = doubleToInt64Bits,
  Int64BitsToDouble = int64BitsToDouble
})
end

-- CoreSystemLib: Random.lua
do
-- Compiled from https://github.com/dotnet/corefx/blob/master/src/Common/src/CoreLib/System/Random.cs
-- Generated by CSharp.lua Compiler
-- Licensed to the .NET Foundation under one or more agreements.
-- The .NET Foundation licenses this file to you under the MIT license.
-- See the LICENSE file in the project root for more information.
local System = System
local ArrayInt32 = System.Array(System.Int32)
System.define("System.Random", (function ()
  local Sample, InternalSample, GenerateSeed, Next, GetSampleForLargeRange, NextDouble, 
  NextBytes, internal, __ctor__, rnd
  internal = function (this)
    this._seedArray = ArrayInt32:new(56)
  end
  __ctor__ = function (this, Seed)
    if not Seed then Seed = GenerateSeed() end
    internal(this)
    local ii = 0
    local mj, mk

    --Initialize our Seed array.
    local subtraction = (Seed == -2147483648 --[[Int32.MinValue]]) and 2147483647 --[[Int32.MaxValue]] or math.Abs(Seed)
    mj = 161803398 --[[Random.MSEED]] - subtraction
    this._seedArray:set(55, mj)
    mk = 1
    for i = 1, 54 do
      --Apparently the range [1..55] is special (Knuth) and so we're wasting the 0'th position.
      ii = ii + 21
      if ii >= 55 then
        ii = ii - 55
      end
      this._seedArray:set(ii, mk)
      mk = mj - mk
      if mk < 0 then
        mk = mk + 2147483647 --[[Random.MBIG]]
      end
      mj = this._seedArray:get(ii)
    end
    for k = 1, 4 do
      for i = 1, 55 do
        local n = i + 30
        if n >= 55 then
          n = n - 55
        end
        local v =  this._seedArray:get(i) - this._seedArray:get(1 + n)
        this._seedArray:set(i, System.toInt32(v))
        if this._seedArray:get(i) < 0 then
          this._seedArray:set(i, this._seedArray:get(i) + 2147483647 --[[Random.MBIG]])
        end
      end
    end
    this._inext = 0
    this._inextp = 21
    Seed = 1
  end
  Sample = function (this)
    --Including this division at the end gives us significantly improved
    --random number distribution.
    return (InternalSample(this) * (4.6566128752457969E-10 --[[1.0 / MBIG]]))
  end
  InternalSample = function (this)
    local retVal
    local locINext = this._inext
    local locINextp = this._inextp

    locINext = locINext + 1
    if locINext >= 56 then
      locINext = 1
    end
    locINextp = locINextp + 1
    if locINextp >= 56 then
      locINextp = 1
    end

    retVal = this._seedArray:get(locINext) - this._seedArray:get(locINextp)

    if retVal == 2147483647 --[[Random.MBIG]] then
      retVal = retVal - 1
    end
    if retVal < 0 then
      retVal = retVal + 2147483647 --[[Random.MBIG]]
    end

    this._seedArray:set(locINext, retVal)

    this._inext = locINext
    this._inextp = locINextp

    return retVal
  end
  GenerateSeed = function ()
    if not rnd then
      math.randomseed(os.time())
      rnd = math.random
    end
    return rnd(0, 2147483647)
  end
  Next = function (this, minValue, maxValue)
    if not minValue then
      return InternalSample(this)
    end

    if not maxValue then
      maxValue = minValue
      if maxValue < 0 then
        System.throw(System.ArgumentOutOfRangeException("maxValue" --[[nameof(maxValue)]], "'maxValue' must be greater than zero."))
      end
      return System.ToInt32((Sample(this) * maxValue))
    end

    if minValue > maxValue then
      System.throw(System.ArgumentOutOfRangeException("minValue" --[[nameof(minValue)]], "'minValue' cannot be greater than maxValue."))
    end
    local range = maxValue - minValue
    if range <= 2147483647 --[[Int32.MaxValue]] then
      return (System.ToInt32((Sample(this) * range)) + minValue)
    else
      return System.toInt32((System.ToInt64((GetSampleForLargeRange(this) * range)) + minValue))
    end
  end
  GetSampleForLargeRange = function (this)
    -- The distribution of double value returned by Sample 
    -- is not distributed well enough for a large range.
    -- If we use Sample for a range [int.MinValue..int.MaxValue)
    -- We will end up getting even numbers only.

    local result = InternalSample(this)
    -- Note we can't use addition here. The distribution will be bad if we do that.
    local negative = (InternalSample(this) % 2 == 0) and true or false
    -- decide the sign based on second sample
    if negative then
      result = - result
    end
    local d = result
    d = d + (2147483646 --[[int.MaxValue - 1]])
    -- get a number in range [0 .. 2 * Int32MaxValue - 1)
    d = d / (4294967293 --[[2 * (uint)int.MaxValue - 1]])
    return d
  end
  NextDouble = function (this)
    return Sample(this)
  end
  NextBytes = function (this, buffer)
    if buffer == nil then
      System.throw(System.ArgumentNullException("buffer" --[[nameof(buffer)]]))
    end
    do
      local i = 0
      while i < #buffer do
        buffer:set(i, System.toByte(InternalSample(this)))
        i = i + 1
      end
    end
  end
  return {
    _inext = 0,
    _inextp = 0,
    Sample = Sample,
    Next = Next,
    NextDouble = NextDouble,
    NextBytes = NextBytes,
    __ctor__ = __ctor__
  }
end)())

end

-- CoreSystemLib: Text/StringBuilder.lua
do
local System = System
local throw = System.throw
local clear = System.Array.clear
local toString = System.toString
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local IndexOutOfRangeException = System.IndexOutOfRangeException

local table = table
local tconcat = table.concat
local schar = string.char
local ssub = string.sub
local sbyte = string.byte
local type = type
local select = select

local function build(this, value, startIndex, length)
  value = value:Substring(startIndex, length)
  local len = #value
  if len > 0 then
    this[#this + 1] = value
    this.Length = len
  end
end

local function getItemIndex(this, index)
  for i = 1, #this do
    local s = this[i]
    local len = #s
    local begin = index
    index = index - len
    if index < 0 then
      begin = begin + 1
      local ch = sbyte(s, begin)
      if not ch then
        break
      end
      return i, s, begin, ch
    end
  end
end

local function getLength(this)
  return this.Length
end

local StringBuilder = System.define("System.Text.StringBuilder", { 
  Length = 0,
  ToString = tconcat,
  __tostring = tconcat,
  __ctor__ = function (this, ...)
    local len = select("#", ...)
    if len == 0 then
    elseif len == 1 or len == 2 then
      local value = ...
      if type(value) == "string" then
        build(this, value, 0, #value)
      else
        build(this, "", 0, 0)
      end
    else 
      local value, startIndex, length = ...
      build(this, value, startIndex, length)
    end
  end,
  get = function (this, index)
    local _, _, _, ch = getItemIndex(this, index)
    if not _ then
      throw(IndexOutOfRangeException())
    end
    return ch
  end,
  set = function (this, index, value)
    local i, s, j = getItemIndex(this, index)
    if not i then
      throw(ArgumentOutOfRangeException("index"))
    end
    this[i] = ssub(s, 1, j - 1) .. schar(value) .. ssub(s, j + 1)
  end,
  setCapacity = function (this, value)
    if value < this.Length then
      throw(ArgumentOutOfRangeException())
    end
  end,
  getCapacity = getLength,
  getMaxCapacity = getLength,
  getLength = getLength,
  setLength = function (this, value) 
    if value < 0 then throw(ArgumentOutOfRangeException("value")) end
    if value == 0 then
      this:Clear()
      return
    end
    local delta = value - this.Length
    if delta > 0 then
      this:AppendCharRepeat(0, delta)
    else
      local length, remain = #this, value
      for i = 1, length do
        local s = this[i]
        local len = #s
        if len >= remain then
          if len ~= remain then
            s = ssub(s, 0, remain)
            this[i] = s
          end
          for j = i + 1, length do
            this[j] = nil
          end
          break
        end
        remain = remain - len
      end
      this.Length = this.Length + delta
    end  
  end,
  Append = function (this, value, startIndex, count)
    if not startIndex then
      if value ~= nil then
        value = toString(value)
        if value ~= nil then
          this[#this + 1] = value
          this.Length =  this.Length + #value
        end
      end
    else
      if value == nil then
        throw(ArgumentNullException("value"))
      end
      value = value:Substring(startIndex, count)
      this[#this + 1] = value
      this.Length =  this.Length + #value
    end
    return this
  end,
  AppendChar = function (this, v) 
    v = schar(v)
    this[#this + 1] = v
    this.Length = this.Length + 1
    return this
  end,
  AppendCharRepeat = function (this, v, repeatCount)
    if repeatCount < 0 then throw(ArgumentOutOfRangeException("repeatCount")) end
    if repeatCount == 0 then return this end
    v = schar(v)
    local count = #this + 1
    for i = 1, repeatCount do
      this[count] = v
      count = count + 1
    end
    this.Length = this.Length + repeatCount
    return this
  end,
  AppendFormat = function (this, format, ...)
    local value = format:Format(...)
    this[#this + 1] = value
    this.Length = this.Length + #value
    return this
  end,
  AppendLine = function (this, value)
    local count = 1
    local len = #this + 1
    if value ~= nil then
      this[len] = value
      len = len + 1
      count = count + #value
    end
    this[len] = "\n"
    this.Length = this.Length + count
    return this
  end,
  Clear = function (this)
    clear(this)
    this.Length = 0
    return this
  end,
  Insert = function (this, index, value)
    local length = this.Length
    if value ~= nil then
      if index == length then
        this:Append(value)
      else
        value = toString(value)
        if value ~= nil then
          local i, s, j = getItemIndex(this, index)
          if not i then
            throw(ArgumentOutOfRangeException("index"))
          end
          this[i] = ssub(s, 1, j - 1) .. value .. ssub(s, j)
          this.Length = length + #value
        end
      end
    end
  end
})
System.StringBuilder = StringBuilder
end

-- CoreSystemLib: Console.lua
do
local System = System
local toString = System.toString

local print = print
local select = select
local string = string
local byte = string.byte
local char = string.char
local Format = string.Format

local function getWriteValue(v, ...)
  if select("#", ...) ~= 0 then
    return Format(v, ...)
  end
  return toString(v)
end

local Console = System.define("System.Console", {
  WriteLine = function (v, ...)
    print(getWriteValue(v, ...))     
  end,
  WriteLineChar = function (v)
    print(char(v))     
  end
})

local io = io
if io then
  local stdin = io.stdin
  local stdout = io.stdout
  local read = stdin.read
  local write = stdout.write

  function Console.Read()
    local ch = read(stdin, 1)
    return byte(ch)
  end

  function Console.ReadLine()
     return read(stdin)
  end

  function Console.Write(v, ...)
    write(stdout, getWriteValue(v, ...))
  end

  function Console.WriteChar(v)
     write(stdout, char(v))
  end
end
end

-- CoreSystemLib: IO/File.lua
do
local io = io
if io then

local System = System
local define = System.define
local throw = System.throw
local each = System.each

local open = io.open
local remove = os.remove

local IOException = define("System.IO.IOException", {
  __tostring = System.Exception.ToString,
  base = { System.Exception },
  __ctor__ = function(this, message, innerException) 
    System.Exception.__ctor__(this, message or "I/O error occurred.", innerException)
  end,
})

local function openFile(path, mode)
  local f, err = open(path, mode)
  if f == nil then
    throw(IOException(err))
  end
  return f
end

local function readAll(path, mode)
  local f = openFile(path, mode)
  local bytes = f:read("*all")
  f:close()
  return bytes
end

local function writeAll(path, contents, mode)
  local f = openFile(path, mode)
  f:write(contents)
  f:close()
end

define("System.IO.File", {
  ReadAllBytes = function (path)
    return readAll(path, "rb")
  end,
  ReadAllText = function (path)
    return readAll(path, "r")
  end,
  ReadAllLines = function (path)
    local t = {}
    local count = 1
    for line in io.lines(path) do
      t[count] = line
      count = count + 1
    end
    return System.arrayFromTable(t, System.String)
  end,  
  WriteAllBytes = function (path, contents)
    writeAll(path, contents, "wb")
  end,
  WriteAllText = function (path, contents)
    writeAll(path, contents, "w")
  end,
  WriteAllLines = function (path, contents)
    local f = openFile(path, "w")
    for _, line in each(contents) do
      if line == nil then
        f:write("\n")
      else
        f:write(line, "\n")
      end
    end
    f:close()
  end,
  Exists = function (path)
    local file = io.open(path, "rb")
    if file then file:close() end
    return file ~= nil
  end,
  Delete = function (path)
    local ok, err = remove(path)
    if not ok then
      throw(IOException(err))
    end
  end
})

end
end

-- CoreSystemLib: Reflection/Assembly.lua
do
local System = System
local define = System.define
local throw = System.throw
local div = System.div
local Type = System.Type
local typeof = System.typeof
local getClass = System.getClass
local is = System.is
local band = System.band
local arrayFromTable = System.arrayFromTable
local toLuaTable = System.toLuaTable

local Exception = System.Exception
local NotSupportedException = System.NotSupportedException
local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException

local assert = assert
local pairs = pairs
local getmetatable = getmetatable
local setmetatable = setmetatable
local rawget = rawget
local type = type
local unpack = table.unpack
local select = select
local floor = math.floor

local TargetException = define("System.Reflection.TargetException", {
  __tostring = Exception.ToString,
  base = { Exception }
})

local TargetParameterCountException = define("System.Reflection.TargetParameterCountException", {
  __tostring = Exception.ToString,
  base = { Exception },
  __ctor__ = function(this, message, innerException) 
    Exception.__ctor__(this, message or "Parameter count mismatch.", innerException)
  end,
})

local AmbiguousMatchException = define("System.Reflection.AmbiguousMatchException", {
  __tostring = Exception.ToString,
  base = { System.SystemException },
  __ctor__ = function(this, message, innerException) 
    Exception.__ctor__(this, message or "Ambiguous match found.", innerException)
  end,
})

local MissingMethodException = define("System.MissingMethodException", {
  __tostring = Exception.ToString,
  base = { Exception },
  __ctor__ = function(this, message, innerException) 
    Exception.__ctor__(this, message or "Specified method could not be found.", innerException)
  end
})

local function throwNoMatadata(sign)
  throw(NotSupportedException("not found metadata for " .. sign), 1)
end

local function eq(left, right)
  return left[1] == right[1] and left.name == right.name
end

local function getName(this)
  return this.name
end

local function isAccessibility(memberInfo, kind)
  local metadata = memberInfo.metadata
  if not metadata then
    throwNoMatadata(memberInfo.c.__name__ .. "." .. memberInfo.name)
  end
  return band(metadata[2], 0x7) == kind
end

local MemberInfo = define("System.Reflection.MemberInfo", {
  getName = getName,
  EqualsObj = function (this, obj)
    if getmetatable(this) ~= getmetatable(obj) then
      return false
    end
    return eq(this, obj)
  end,
  getMemberType = function (this)
    return this.memberType
  end,
  getDeclaringType = function (this)
    return typeof(this.c)
  end,
  getIsStatic = function (this)
    local metadata = this.metadata
    if not metadata then
      throwNoMatadata(this.c.__name__ .. "." .. this.name)
    end
    return band(metadata[2], 0x8) == 1
  end,
  getIsPrivate = function (this)
    return isAccessibility(this, 1)
  end,
  getIsFamilyAndAssembly = function (this)
    return isAccessibility(this, 2)
  end,
  getIsFamily = function (this)
    return isAccessibility(this, 3)
  end,
  getIsAssembly = function (this)
    return isAccessibility(this, 4)
  end,
  getIsFamilyOrAssembly = function (this)
    return isAccessibility(this, 5)
  end,
  getIsPublic = function (this)
    return isAccessibility(this, 6)
  end
})

local function getFieldOrPropertyType(this)
  local metadata = this.metadata
  if not metadata then
    throwNoMatadata(this.c.__name__ .. "." .. this.name)
  end
  return typeof(metadata[3])
end

local function checkObj(obj, cls)
  if not is(obj, cls) then
    throw(ArgumentException("Object does not match target type.", "obj"), 1)
  end
end

local function checkTarget(cls, obj, metadata)
  if band(metadata[2], 0x8) == 0 then
    if obj == nil then
      throw(TargetException())
    end
    checkObj(obj, cls)
  else
    return true
  end
end

local function checkValue(value, valueClass)
  if value == nil then
    if valueClass.class == "S" then
      value = valueClass:default()
    end
  else
    checkObj(value, valueClass)
  end
  return value
end

local function getOrSetField(this, obj, isSet, value)
  local cls, metadata = this.c, this.metadata
  if metadata then
    if checkTarget(cls, obj, metadata) then
      obj = cls
    end
    local name = metadata[4]
    if type(name) ~= "string" then
      name = this.name
    end
    if isSet then
      obj[name] = checkValue(value, metadata[3])
    else
      return obj[name]
    end
  else
    if obj ~= nil then
      checkObj(obj, cls)
    else
      obj = cls
    end
    if isSet then
      obj[this.name] = value
    else
      return obj[this.name]
    end
  end
end

local function isMetadataDefined(metadata, index, attributeType)
  attributeType = attributeType[1]
  for i = index, #metadata do
    if is(metadata[i], attributeType) then
      return true
    end
  end
  return false
end

local function fillMetadataCustomAttributes(t, metadata, index, attributeType)
  local count = #t + 1
  if attributeType then
    attributeType = attributeType[1]
    for i = index, #metadata do
      if is(metadata[i], attributeType) then
        t[count] = metadata[i]
        count = count + 1
      end
    end
  else
    for i = index, #metadata do
      t[count] = metadata[i]
      count = count + 1
    end
  end
end

local FieldInfo = define("System.Reflection.FieldInfo", {
  __eq = eq,
  base = { MemberInfo },
  memberType = 4,
  getFieldType = getFieldOrPropertyType,
  GetValue = getOrSetField,
  SetValue = function (this, obj, value)
    getOrSetField(this, obj, true, value)
  end,
  IsDefined = function (this, attributeType)
    if attributeType == nil then throw(ArgumentNullException()) end
    local metadata = this.metadata
    if metadata then
      return isMetadataDefined(metadata, 4, attributeType)
    end
    return false
  end,
  GetCustomAttributes = function (this, attributeType, inherit)
    if type(attributeType) == "boolean" then
      attributeType, inherit = nil, attributeType
    else
      if attributeType == nil then throw(ArgumentNullException()) end
    end
    local t = {}
    local metadata = this.metadata
    if metadata then
      local index = 4
      if type(metadata[index]) == "string" then
        index = 5
      end
      fillMetadataCustomAttributes(t, metadata, index, attributeType)
    end
    return arrayFromTable(t, System.Attribute) 
  end
})

local function getOrSetProperty(this, obj, isSet, value)
  local cls, metadata = this.c, this.metadata
  if metadata then
    local isStatic
    if checkTarget(cls, obj, metadata) then
      obj = cls
      isStatic = true
    end
    if isSet then
      value = checkValue(value, metadata[3])
    end
    local kind = band(metadata[2], 0x300)
    if kind == 0 then
      local name = metadata[4]
      if type(name) ~= "string" then
        name = this.name
      end
      if isSet then
        obj[name] = value
      else
        return obj[name]
      end
    else
      local index
      if kind == 0x100 then
        index = isSet and 5 or 4      
      elseif kind == 0x200 then
        if isSet then
          throw(ArgumentException("Property Set method was not found."))
        end
        index = 4
      else
        if not isSet then
          throw(ArgumentException("Property Get method was not found."))
        end  
        index = 4
      end
      local fn = metadata[index]
      if type(fn) == "table" then
        fn = fn[1]
      end
      if isSet then
        if isStatic then
          fn(value)
        else
          fn(obj, value)
        end  
      else
        return fn(obj)
      end
    end
  else
    local isStatic
    if obj ~= nil then
      checkObj(obj, cls)
    else
      obj = cls
      isStatic = true
    end
    if this.isField then
      if isSet then
        obj[this.name] = value
      else
        return obj[this.name]
      end
    else
      if isSet then
        local fn = obj["set" .. this.name]
        if fn == nil then
          throw(ArgumentException("Property Set method not found."))
        end
        if isStatic then
          fn(value)
        else
          fn(obj, value)
        end
      else
        local fn = obj["get" .. this.name]
        if fn == nil then
          throw(ArgumentException("Property Get method not found."))
        end
        return fn(obj)
      end
    end
  end
end

local function getPropertyAttributesIndex(metadata)
  local kind = band(metadata[2], 0x300)
  local index
  if kind == 0 then
    index = 4
  elseif kind == 0x100 then
    index = 6
  else
    index = 5
  end
  return index
end

local PropertyInfo = define("System.Reflection.PropertyInfo", {
  __eq = eq,
  base = { MemberInfo },
  memberType = 16,
  getPropertyType = getFieldOrPropertyType,
  GetValue = getOrSetProperty,
  SetValue = function (this, obj, value)
    getOrSetProperty(this, obj, true, value)
  end,
  IsDefined = function (this, attributeType)
    if attributeType == nil then throw(ArgumentNullException()) end
    local metadata = this.metadata
    if metadata then
      local index = getPropertyAttributesIndex(metadata)
      return isMetadataDefined(metadata, index, attributeType)
    end
    return false
  end,
  GetCustomAttributes = function (this, attributeType, inherit)
    if type(attributeType) == "boolean" then
      attributeType, inherit = nil, attributeType
    else
      if attributeType == nil then throw(ArgumentNullException()) end
    end
    local t = {}
    local metadata = this.metadata
    if metadata then
      local index = getPropertyAttributesIndex(metadata)
      fillMetadataCustomAttributes(t, metadata, index, attributeType)
    end
    return arrayFromTable(t, System.Attribute) 
  end
})

local function hasPublicFlag(flags)
  return band(flags, 0x7) == 6
end

local function getMethodParameterCount(flags)
  local count = band(flags, 0xFF00)
  if count ~= 0 then
    count = count / 256
  end
  return floor(count)
end

local function getMethodAttributesIndex(metadata)
  local flags = metadata[2]
  local index
  local typeParametersCount = band(flags, 0xFF0000)
  if typeParametersCount == 0 then
    local parameterCount = getMethodParameterCount(flags)
    if band(flags, 0x80) == 0 then
      index = 4 + parameterCount
    else
      index = 5 + parameterCount
    end
  else
    index = 5
  end
  return index
end

local MethodInfo = define("System.Reflection.MethodInfo", {
  __eq = eq,
  base = { MemberInfo },
  memberType = 8,
  getReturnType = function (this)
    local metadata = this.metadata
    if not metadata then
      throwNoMatadata(this.c.__name__ .. "." .. this.name)
    end
    local flags = metadata[2]
    if band(flags, 0x80) == 0 then
      return Type.Void
    end
    if band(flags, 0xC00) > 0 then
      assert(false, "not implement for generic method")
    end
    local parameterCount = getMethodParameterCount(flags)
    return typeof(metadata[4 + parameterCount])
  end,
  Invoke = function (this, obj, parameters)
    local cls, metadata = this.c, this.metadata
    if metadata then
      local isStatic
      if checkTarget(cls, obj, metadata) then
        isStatic = true
      end
      local t = {}
      local parameterCount = getMethodParameterCount(metadata[2])
      if parameterCount == 0 then
        if parameters ~= nil and #parameters > 0 then
          throw(TargetParameterCountException())
        end
      else
        if parameters == nil and #parameters ~= parameterCount then
          throw(TargetParameterCountException())
        end
        for i = 4, 3 + parameterCount do
          local j = #t
          local paramValue, mtData = parameters:get(j), metadata[i]
          if mtData ~= nil then
            paramValue = checkValue(paramValue, mtData)
          end
          t[j + 1] = paramValue
        end
      end
      local f = metadata[3]
      if isStatic then
        if t then
          return f(unpack(t, 1, parameterCount))
        else
          return f()
        end
      else
        if t then
          return f(obj, unpack(t, 1, parameterCount))
        else
          return f(obj)
        end
      end
    else
      local f = assert(this.f)
      if obj ~= nil then
        checkObj(obj, cls)
        if parameters ~= nil then
          local t = toLuaTable(parameters)
          return f(obj, unpack(t, 1, #parameters))
        else
          return f(obj)
        end
      else
        if parameters ~= nil then
          local t = toLuaTable(parameters)
          return f(unpack(t, 1, #parameters))
        else
          return f()
        end
      end
    end
  end,
  IsDefined = function (this, attributeType, inherit)
    if attributeType == nil then throw(ArgumentNullException()) end
    local metadata = this.metadata
    if metadata then
      local index = getMethodAttributesIndex(metadata)
      return isMetadataDefined(metadata, index, attributeType)
    end
    return false
  end,
  GetCustomAttributes = function (this, attributeType, inherit)
    if type(attributeType) == "boolean" then
      attributeType, inherit = nil, attributeType
    else
      if attributeType == nil then throw(ArgumentNullException()) end
    end
    local t = {}
    local metadata = this.metadata
    if metadata then
      local index = getMethodAttributesIndex(metadata)
      fillMetadataCustomAttributes(t, metadata, index, attributeType)
    end
    return arrayFromTable(t, System.Attribute)
  end
})

local function buildFieldInfo(cls, name, metadata)
  return setmetatable({ c = cls, name = name, metadata = metadata }, FieldInfo)
end

local function buildPropertyInfo(cls, name, metadata, isField)
  return setmetatable({ c = cls, name = name, metadata = metadata, isField = isField }, PropertyInfo)
end

local function buildMethodInfo(cls, name, metadata, f)
  return setmetatable({ c = cls, name = name, metadata = metadata, f = f }, MethodInfo)
end

-- https://en.cppreference.com/w/cpp/algorithm/lower_bound
local function lowerBound(t, first, last, value, comp)
  local count = last - first
  local it, step
  while count > 0 do
    it = first
    step = div(count, 2)
    it = it + step
    if comp(t[it], value) then
      it = it + 1
      first = it
      count = count - (step + 1)
    else
      count = step
    end
  end
  return first
end

local function metadataItemCompByName(item, name)
  return item[1] < name
end

local function binarySearchByName(metadata, name)
  local last = #metadata + 1
  local index = lowerBound(metadata, 1, last, name, metadataItemCompByName)
  if index ~= last then
    local item = metadata[index]
    if item[1] == name then
      return metadata[index], index
    end
  end
  return nil
end

function Type.GetField(this, name)
  if name == nil then throw(ArgumentNullException()) end
  local cls = this[1]
  local metadata = cls.__metadata__
  if metadata then
    local fields = metadata.fields
    if fields then
      local field = binarySearchByName(fields, name)
      if field then
        return buildFieldInfo(cls, name, field)
      end
      return nil
    end
  end
  if type(cls[name]) ~= "function" then
    return buildFieldInfo(cls, name)
  end
end

function Type.GetFields(this)
  local t = {}
  local cls = this[1]
  local count = 1
  repeat
    local metadata = rawget(cls, "__metadata__")
    if metadata then
      local fields = metadata.fields
      if fields then
        for i = 1, #fields do
          local field = fields[i]
          if hasPublicFlag(field[2]) then
            t[count] = buildFieldInfo(cls, field[1], field)
            count = count + 1
          end
        end
      else
        metadata = nil
      end
    end
    if not metadata then
      for k, v in pairs(cls) do
        if type(v) ~= "function" then
          t[count] = buildFieldInfo(cls, k)
          count = count + 1
        end
      end
    end
    cls = getmetatable(cls)
  until cls == nil 
  return arrayFromTable(t, FieldInfo)
end

function Type.GetProperty(this, name)
  if name == nil then throw(ArgumentNullException()) end
  local cls = this[1]
  local metadata = cls.__metadata__
  if metadata then
    local properties = metadata.properties
    if properties then
      local property = binarySearchByName(properties, name)
      if property then
        return buildPropertyInfo(cls, name, property)
      end
      return nil
    end
  end
  if cls["get" .. name] or cls["set" .. name] then
    return buildPropertyInfo(cls, name)
  else
    return buildPropertyInfo(cls, name, nil, true)
  end
end

function Type.GetProperties(this)
  local t = {}
  local cls = this[1]
  local count = 1
  repeat
    local metadata = rawget(cls, "__metadata__")
    if metadata then
      local properties = metadata.properties
      if properties then
        for i = 1, #properties do
          local property = properties[i]
          if hasPublicFlag(property[2]) then
            t[count] = buildPropertyInfo(cls, property[1], property)
            count = count + 1
          end
        end
      end
    end
    cls = getmetatable(cls)
  until cls == nil 
  return arrayFromTable(t, PropertyInfo)
end

function Type.GetMethod(this, name)
  if name == nil then throw(ArgumentNullException()) end
  local cls = this[1]
  local metadata = cls.__metadata__
  if metadata then
    local methods = metadata.methods
    if methods then
      local item, index = binarySearchByName(methods, name)
      if item then
        local next = methods[index + 1]
        if next and next[1] == name then
          throw(AmbiguousMatchException())
        end
        return buildMethodInfo(cls, name, item)
      end
      return nil
    end
  end
  local f = cls[name]
  if type(f) == "function" then
    return buildMethodInfo(cls, name, nil, f)
  end
end

function Type.GetMethods(this)
  local t = {}
  local cls = this[1]
  local count = 1
  repeat
    local metadata = rawget(cls, "__metadata__")
    if metadata then
      local methods = metadata.methods
      if methods then
        for i = 1, #methods do
          local method = methods[i]
          if hasPublicFlag(method[2]) then
            t[count] = buildMethodInfo(cls, method[1], method)
            count = count + 1
          end
        end
      else
        metadata = nil
      end
    end
    if not metadata then
      for k, v in pairs(cls) do
        if type(v) == "function" then
          t[count] = buildMethodInfo(cls, k, nil, v)
          count = count + 1
        end
      end
    end
    cls = getmetatable(cls)
  until cls == nil 
  return arrayFromTable(t, MethodInfo)
end

function Type.GetMembers(this)
  local t = arrayFromTable({}, MemberInfo)
  t:addRange(this:GetFields())
  t:addRange(this:GetProperties())
  t:addRange(this:GetMethods())
  return t
end

function Type.IsDefined(this, attributeType, inherit)
  if attributeType == nil then throw(ArgumentNullException()) end
  local cls = this[1]
  if not inherit then
    local metadata = rawget(cls, "__metadata__")
    if metadata then
      local class  = metadata.class
      if class then
        return isMetadataDefined(class, 2, attributeType)
      end
    end
    return false
  else
    repeat
      local metadata = rawget(cls, "__metadata__")
      if metadata then
        local class  = metadata.class
        if class then
          if isMetadataDefined(class, 2, attributeType) then
            return true
          end
        end
      end
      cls = getmetatable(cls)
    until cls == nil
    return false
  end
end

function Type.GetCustomAttributes(this, attributeType, inherit)
  if type(attributeType) == "boolean" then
    attributeType, inherit = nil, attributeType
  else
    if attributeType == nil then throw(ArgumentNullException()) end
  end
  local cls = this[1]
  local t = {}
  if not inherit then
    local metadata = rawget(cls, "__metadata__")
    if metadata then
      local class  = metadata.class
      if class then
        fillMetadataCustomAttributes(t, class, 2, attributeType)
      end
    end
  else
    repeat
      local metadata = rawget(cls, "__metadata__")
      if metadata then
        local class  = metadata.class
        if class then
          fillMetadataCustomAttributes(t, class, 2, attributeType)
        end
      end
      cls = getmetatable(cls)
    until cls == nil
  end
  return arrayFromTable(t, System.Attribute)
end

local Assembly, coreSystemAssembly
local function getAssembly(t)
  local assembly = t[1].__assembly__
  if assembly then
    return setmetatable(assembly, Assembly)
  end
  return coreSystemAssembly
end

local function getAssemblyName(this)
  local name = this.name or "CSharpLua.CoreLib"
  return name .. ", Version=1.0.0.0, Culture=neutral, PublicKeyToken=null"
end

Assembly = define("System.Reflection.Assembly", {
  GetName = getAssemblyName,
  getFullName = getAssemblyName,
  GetAssembly = getAssembly,
  GetTypeFrom = Type.GetTypeFrom,
  GetEntryAssembly = function ()
    local entryAssembly = System.entryAssembly
    if entryAssembly then
      return setmetatable(entryAssembly, Assembly)
    end
    return nil
  end,
  getEntryPoint = function (this)
    local entryPoint = this.entryPoint
    if entryPoint ~= nil then
      local _, _, t, name = entryPoint:find("(.*)%.(.*)")
      local cls = getClass(t)
      local f = assert(cls[name])
      return buildMethodInfo(cls, name, nil, f)
    end
    return nil
  end,
  GetExportedTypes = function (this)
    if this.exportedTypes then
      return this.exportedTypes
    end
    local t = {}
    local classes = this.classes
    if classes then
      for i = 1, #classes do
        t[i] = typeof(classes[i])
      end
    end
    local array = arrayFromTable(t, Type, true)
    this.exportedTypes = array
    return array
  end
})
coreSystemAssembly = Assembly()

function System.GetExecutingAssembly(assembly)
	return setmetatable(assembly, Assembly)
end

Type.getAssembly = getAssembly

function Type.getAssemblyQualifiedName(this)
  return this:getName() .. ', ' .. getName(assembly)
end

function Type.getAttributes(this)
  local cls = this[1]
  local metadata = rawget(cls, "__metadata__")
  if metadata then
    metadata = metadata.class
    if metadata then
      return metadata[1]
    end
  end
  throwNoMatadata(cls.__name__)
end

function Type.GetGenericArguments(this)
  local t = {}
  local count = 1

  local cls = this[1]
  local metadata = rawget(cls, "__metadata__")
  if metadata then
    metadata = metadata.class
    if metadata then
      local flags = metadata[1]
      local typeParameterCount = band(flags, 0xFF00)
      if typeParameterCount ~= 0 then
        typeParameterCount = typeParameterCount / 256
        for i = 2, 1 + typeParameterCount do
          t[count] = typeof(metadata[i])
          count = count + 1
        end
      end
      return arrayFromTable(t, Type)
    end
  end

  local name = cls.__name__ 
  local i = name:find("%[")
  if i then
    i = i + 1
    while true do
      local j = name:find(",", i) or -1
      local clsName = name:sub(i, j - 1)
      t[count] = typeof(System.getClass(clsName))
      if j == -1 then
        break
      end
      count = count + 1
      i = j + 1
    end
  end
  return arrayFromTable(t, Type)
end

local Attribute = System.Attribute

function Attribute.GetCustomAttribute(element, attributeType, inherit)
  return element:GetCustomAttribute(attributeType, inherit)
end

function Attribute.GetCustomAttributes(element, attributeType, inherit)
  return element:GetCustomAttributes(attributeType, inherit)
end

function Attribute.IsDefined(element, attributeType, inherit)
	return element:IsDefined(attributeType, inherit)
end

local function createInstance(T, nonPublic)
  local metadata = rawget(T, "__metadata__")
  if metadata then
    local methods = metadata.methods
    if methods then
      local ctorMetadata = methods[1]
      if ctorMetadata[1] == ".ctor" then
        local flags = ctorMetadata[2]
        if nonPublic or hasPublicFlag(flags) then
          local parameterCount = getMethodParameterCount(flags)
          if parameterCount == 0 then
            return T()
          end
        end
        throw(MissingMethodException())
      end
    end
  end
  return T()
end

local function isCtorMatch(method, n, f, ...)
  local flags = method[2]
  if hasPublicFlag(flags) then
    local parameterCount = getMethodParameterCount(flags)
    if parameterCount == n then
      for j = 4, 3 + parameterCount do
        local p = f(j - 3, ...)
        if not is(p, method[j]) then
          return false
        end
      end
      return true
    end
  end
  return false
end

local function findMatchCtor(T, n, f, ...)
  local metadata = rawget(T, "__metadata__")
  if metadata then
    local hasCtor
    local methods = metadata.methods
    for i = 1, #methods do
      local method = methods[i]
      if method[1] == ".ctor" then
        if isCtorMatch(method, n, f, ...) then
          return i
        end
        hasCtor = true
      else
        break
      end
    end
    if hasCtor then
      throw(MissingMethodException())
    end
  end
end

define("System.Activator", {
  CreateInstance = function (type, ...)
    if type == nil then throw(ArgumentNullException("type")) end
    if getmetatable(type) ~= Type then
      return createInstance(type)
    end
    local T, n = type[1], select("#", ...)
    if n == 0 then
      return createInstance(T)
    elseif n == 1 then
      local args = ...
      if System.isArrayLike(args) then
        n = #args
        if n == 0 then
          return createInstance(T)
        end
        local i = findMatchCtor(T, n, function (i, args) return args:get(i - 1) end, args)
        if i and i ~= 1 then
          return System.new(T, i, unpack(args, 1, n))
        end
        return T(unpack(args, 1, n))
      end
    end
    local i = findMatchCtor(T, n, select, ...)
    if i and i ~= 1 then
      return System.new(T, i, ...)
    end
    return T(...)
  end,
  CreateInstance1 = function (type, nonPublic)
    if type == nil then throw(ArgumentNullException("type")) end
    return createInstance(type[1], nonPublic)
  end
})
end

-- CoreSystemLib: Threading/Timer.lua
do
local System = System
local define = System.define
local throw = System.throw
local Array = System.Array
local heapAdd = Array.heapAdd
local heapPop = Array.heapPop
local heapDown = Array.heapDown
local currentTimeMillis = System.currentTimeMillis
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException  = System.ArgumentOutOfRangeException
local NotImplementedException = System.NotImplementedException
local ObjectDisposedException = System.ObjectDisposedException

local type = type

local config = System.config
local setTimeout = config.setTimeout
local clearTimeout = config.clearTimeout

if setTimeout and clearTimeout then
  System.post = function (fn) 
    setTimeout(fn, 0) 
  end
else
  System.post = function (fn)
    fn()
  end
  local function notset()
    throw(NotImplementedException("System.config.setTimeout or clearTimeout is not registered."))
  end
  setTimeout = notset
  clearTimeout = notset
end

local TimeoutQueue = define("System.TimeoutQueue", (function ()
  local Add, AddRepeating, AddRepeating1, getNextExpiration, Erase, RunLoop, Contains, __ctor__
  __ctor__ = function (this)
	this.c = function (a, b) return a.Expiration - b.Expiration end
  end
  Add = function (this, now, delay, callback)
    return AddRepeating1(this, now, delay, 0, callback)
  end
  AddRepeating = function (this, now, interval, callback)
    return AddRepeating1(this, now, interval, interval, callback)
  end
  AddRepeating1 = function (this, now, delay, interval, callback)
    local id = {
      Expiration = now + delay,
      RepeatInterval = interval,
      Callback = callback
    }
    heapAdd(this, id, this.c)
    return id
  end
  getNextExpiration = function (this)
    if #this > 0 then return this[1].Expiration end
  end
  Erase = function (this, id)
    if not id.cancel then
      id.cancel = true
      return true
    end
    return false
  end
  RunLoop = function (this, now)
    while true do
      local e = this[1]
      if e == nil then break end
      if e.cancel then
        heapPop(this, this.c)
      else
        if e.Expiration <= now then
          if e.RepeatInterval <= 0 then
            heapPop(this, this.c)
            e.cancel = true
          else
            e.Expiration = now + e.RepeatInterval
            heapDown(this, 1, #this, this.c)
          end
          e.Callback(e, now)
        else
          return e.Expiration
        end
      end
    end
  end
  Contains = function (this, id)
    return not id.cancel
  end
  return {
    nextId_ = 1,
    Add = Add,
    AddRepeating = AddRepeating,
    AddRepeating1 = AddRepeating1,
    getNextExpiration = getNextExpiration,
    Erase = Erase,
    RunLoop = RunLoop,
    Contains = Contains,
    __ctor__ = __ctor__
  }
end)())

local timerQueue = TimeoutQueue()
local driverTimer

local function runTimerQueue()
  local now = currentTimeMillis()
  local nextExpiration = timerQueue:RunLoop(now)
  if nextExpiration then
    driverTimer = setTimeout(runTimerQueue, nextExpiration - now)
  else
    driverTimer = nil
  end
end

local function addTimer(fn, dueTime, period)
  local now = currentTimeMillis()
  local id = timerQueue:AddRepeating1(now, dueTime, period or 0, fn)
  if timerQueue[1] == id then
    if driverTimer then
      clearTimeout(driverTimer)
    end
    driverTimer = setTimeout(runTimerQueue, dueTime)
  end
  return id
end

local function removeTimer(id)
  return timerQueue:Erase(id)
end

System.addTimer = addTimer
System.removeTimer = removeTimer

local function close(this)
  local id = this.id
  if id then
    removeTimer(id)
  end
end

local function change(this, dueTime, period)
  if type(dueTime) == "table" then
    dueTime = dueTime:getTotalMilliseconds()
    period = period:getTotalMilliseconds()
  end
  if dueTime < -1 or dueTime > 0xfffffffe then
    throw(ArgumentOutOfRangeException("dueTime"))
  end
  if period < -1 or period > 0xfffffffe then
    throw(ArgumentOutOfRangeException("period"))
  end
  if this.id == false then throw(ObjectDisposedException()) end
  close(this)
  if dueTime ~= -1 then
    this.id = addTimer(this.callback, dueTime, period)
  end
  return true
end

System.Timer = define("System.Threading.Timer", {
  __ctor__ =  function (this, callback, state,  dueTime, period)
    if callback == nil then throw(ArgumentNullException("callback")) end
    this.callback = function () callback(state) end
    change(this, dueTime, period)
  end,
  Change = change,
  Dispose = function (this)
    close(this)
    this.id = false
  end,
  getActiveCount = function ()
    local count = 0
    for i = 1, #timerQueue do
      if not timerQueue[i].cancel then
        count = count + 1
      end
    end
    return count
  end,
  __gc = close
})
end

-- CoreSystemLib: Threading/Thread.lua
do
local System = System
local define = System.define
local throw = System.throw
local trunc = System.trunc
local post = System.post
local addTimer = System.addTimer
local Exception = System.Exception
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local NotSupportedException = System.NotSupportedException

local assert = assert
local type = type
local setmetatable = setmetatable
local coroutine = coroutine
local ccreate = coroutine.create
local cresume = coroutine.resume
local cstatus = coroutine.status
local cyield = coroutine.yield

local mainThread

local ThreadStateException = define("System.Threading.ThreadStateException", {
  __tostring = Exception.ToString,
  base = { Exception },

  __ctor__ = function(this, message, innerException)
     Exception.__ctor__(this, message or "Thread is running or terminated; it cannot restart.", innerException)
  end
})

local ThreadAbortException = define("System.Threading.ThreadAbortException", {
  __tostring = Exception.ToString,
  base = { Exception },
  __ctor__ = function(this, message, innerException)
    Exception.__ctor__(this, message or "Thread aborted.", innerException)
end
})

local nextThreadId = 1
local currentThread

local function getThreadId()
  local id = nextThreadId
  nextThreadId = nextThreadId + 1
  return id
end

local function checkTimeout(timeout)
  if type(timeout) == "table" then
    timeout = trunc(timeout:getTotalMilliseconds())
  end
  if timeout < -1 or timeout > 2147483647 then
    throw(ArgumentOutOfRangeException("timeout"))
  end
  return timeout
end

local function resume(t, obj)
  local prevThread = currentThread
  currentThread = t
  local co = assert(t.co)
  local ok, v = cresume(co, obj)
  currentThread = prevThread
  if ok then
    if type(v) == "function" then
      v()
    elseif cstatus(co) == "dead" then
      local joinThread = t.joinThread
      if joinThread then
        resume(joinThread, true)
      end
      t.co = false
    end
  else
    t.co = false
    print("Warning: Thread.run" , v)
  end
end

local function run(t, obj)
  post(function ()
    resume(t, obj)
  end)
end

local Thread =  define("System.Threading.Thread", {
  IsBackground = false,
  IsThreadPoolThread = false,
  Priority = 2,
  ApartmentState = 2,
  Abort = function ()
    throw(ThreadAbortException())
  end,
  getCurrentThread = function ()
    return currentThread
  end,
  __ctor__ = function (this, start)
	  if start == nil then throw(ArgumentNullException("start")) end
    this.start = start
  end,
  getIsAlive = function (this)
    local co = this.co
    return co and cstatus(co) ~= "dead"
  end,
  ManagedThreadId = function (this)
	  local id = this.id
    if not id then
      id = getThreadId()
      this.id = id
    end
    return id
  end,
  Sleep = function (timeout)
    local current = currentThread
    if current == mainThread then
      throw(NotSupportedException("mainThread not support"))
    end
    timeout = checkTimeout(timeout)
    local f
    if timeout ~= -1 then
      f = function ()
        addTimer(function () 
          resume(current) 
        end, timeout)
      end
    end
    cyield(f)
  end,
  Yield = function ()
    local current = currentThread
    if current == mainThread then
      return false
    end
    cyield(function ()
      run(current)
    end)
    return true
  end,
  Join = function (this, timeout)
    if currentThread == mainThread then
      throw(NotSupportedException("mainThread not support"))
    end
    if this.joinThread then
      throw(ThreadStateException())
    end
    this.joinThread = currentThread  
    if timeout == nil then
      cyield()
    else
      timeout = checkTimeout(timeout)
      local f
      if timeout ~= -1 then
        f = function ()
          addTimer(function ()
            resume(currentThread, false)
          end, timeout)
        end
      end
      return cyield(f)
    end
  end,
  Start = function (this, parameter)
    if this.co ~= nil then throw(ThreadStateException()) end
    local co = ccreate(this.start)
    this.co = co
    this.start = nil
    run(this, parameter)
  end,
  waitTask = function (taskContinueActions)
    if currentThread == mainThread then
      throw(NotSupportedException("mainThread not support"))
    end
    taskContinueActions[#taskContinueActions + 1] = function ()
      resume(currentThread)
    end
    cyield()
  end,
})

mainThread = setmetatable({ id = getThreadId() }, Thread)
currentThread = mainThread

System.ThreadStateException = ThreadStateException
System.ThreadAbortException = ThreadAbortException
System.Thread = Thread
end

-- CoreSystemLib: Threading/Task.lua
do
local System = System
local define = System.define
local defStc = System.defStc
local throw = System.throw
local try = System.try
local trunc = System.trunc
local Void = System.Void
local post = System.post
local addTimer = System.addTimer
local removeTimer = System.removeTimer
local waitTask = System.Thread.waitTask
local arrayFromTable = System.arrayFromTable
local Exception = System.Exception
local NullReferenceException = System.NullReferenceException
local NotImplementedException = System.NotImplementedException
local ArgumentException = System.ArgumentException
local ArgumentNullException = System.ArgumentNullException
local ArgumentOutOfRangeException = System.ArgumentOutOfRangeException
local InvalidOperationException = System.InvalidOperationException
local AggregateException = System.AggregateException
local ObjectDisposedException = System.ObjectDisposedException

local ccreate = System.ccreate
local cpool = System.cpool
local cresume = System.cresume
local cyield = System.yield

local type = type
local table = table
local select = select
local assert = assert
local getmetatable = getmetatable
local setmetatable = setmetatable
local tremove = table.remove
local pack = table.pack
local unpack = table.unpack
local error = error

local TaskCanceledException = define("System.Threading.Tasks.TaskCanceledException", {
  __tostring = Exception.ToString,
  base = { Exception },
  __ctor__ = function (this, task)
    this.task = task  
    Exception.__ctor__(this, "A task was canceled.")
  end,
  getTask = function(this) 
    return this.task
  end
})
System.TaskCanceledException = TaskCanceledException

local TaskStatusCreated = 0
local TaskStatusWaitingForActivation = 1
local TaskStatusWaitingToRun = 2
local TaskStatusRunning = 3
local TaskStatusWaitingForChildrenToComplete = 4
local TaskStatusRanToCompletion = 5
local TaskStatusCanceled = 6
local TaskStatusFaulted = 7

System.TaskStatus = System.defEnum("System.Threading.Tasks.TaskStatus", {
  Created = TaskStatusCreated,
  WaitingForActivation = TaskStatusWaitingForActivation,
  WaitingToRun = TaskStatusWaitingToRun,
  Running = TaskStatusRunning,
  WaitingForChildrenToComplete = TaskStatusWaitingForChildrenToComplete,
  RanToCompletion = TaskStatusRanToCompletion,
  Canceled = TaskStatusCanceled,
  Faulted = TaskStatusFaulted,
})

local UnobservedTaskExceptionEventArgs = define("System.Threading.Tasks.UnobservedTaskExceptionEventArgs", {
  __ctor__ = function (this, exception)
    this.exception = exception
  end,
  SetObserved = function (this)
    this.observed = true
  end,
  getObserved = function (this)
    if this.observed then
      return true
    end
    return false
  end,
  getException = function (this)
    return this.exception
  end
})
System.UnobservedTaskExceptionEventArgs = UnobservedTaskExceptionEventArgs

local unobservedTaskException
local function publishUnobservedTaskException(sender, ueea)
  local handler = unobservedTaskException
  if handler then
    handler(sender, ueea)
  end
end

local TaskScheduler = define("System.Threading.Tasks.TaskScheduler", {
  addUnobservedTaskException = function (value)
    unobservedTaskException = unobservedTaskException + value
  end,
  removeUnobservedTaskException = function (value)
    unobservedTaskException = unobservedTaskException - value
  end
})
System.TaskScheduler = TaskScheduler

local TaskExceptionHolder = {
  __index = false,
  __gc = function (this)
    if not this.isHandled then
      local e = this.exception
      if e then
        local ueea = UnobservedTaskExceptionEventArgs(e)
        publishUnobservedTaskException(this.task, ueea)
        if not ueea.observed then
          print("Warning: TaskExceptionHolder" , e)
        end
      end
    end
  end
}
TaskExceptionHolder.__index = TaskExceptionHolder

local function newTaskExceptionHolder(task, exception) 
  return setmetatable({ task = task, exception = exception }, TaskExceptionHolder)
end

local function getException(task, await)
  local holder = task.data
  if not holder.isHandled then
    holder.isHandled = true
  end
  local e = holder.exception
  if await then
    return e
  end
  return AggregateException(e)
end

local Task
local nextTaskId = 1
local currentTask
local completedTask

local function getNewId()
  local id = nextTaskId
  nextTaskId = nextTaskId + 1
  return id
end

local function getId(this)
  local id = this.id
  if id == nil then
    id = getNewId()
    this.id = id
  end
  return id 
end

local function isCompleted(this)
  local status = this.status
  return status == TaskStatusRanToCompletion or status == TaskStatusFaulted or status == TaskStatusCanceled
end

local function newTask(status, data)
  return setmetatable({ status = status, data = data }, Task)
end

local function fromResult(result)
  return newTask(TaskStatusRanToCompletion, result)
end

local function fromCanceled(cancellationToken)
  if cancellationToken and cancellationToken:getIsCancellationRequested() then 
    throw(ArgumentOutOfRangeException("cancellationToken"))
  end
  return newTask(TaskStatusCanceled, cancellationToken)
end

local function fromException(exception)
  local data = newTaskExceptionHolder(false, exception)
  local t = newTask(TaskStatusFaulted, data) 
  data.task = t
  return t
end

local function getCompletedTask()
  local t = completedTask
  if t == nil then
    t = fromResult()
    completedTask = t
  end
  return t
end

local function trySetComplete(this, status, data)
  if isCompleted(this) then
    return false
  end

  this.status = status
  this.data = data

  local continueActions = this.continueActions
  if continueActions then
    for i = 1, #continueActions do
      continueActions[i](this)
    end
    this.continueActions = nil
  end
  return true
end

local function trySetResult(this, result)
  return trySetComplete(this, TaskStatusRanToCompletion, result)
end

local function trySetException(this, exception)
  if this.data == Void then
    throw(exception)
  end
  return trySetComplete(this, TaskStatusFaulted, newTaskExceptionHolder(this, exception))
end

local function trySetCanceled(this, cancellationToken)
  return trySetComplete(this, TaskStatusCanceled, cancellationToken)
end

local function newWaitingTask(isVoid)
  return newTask(TaskStatusWaitingForActivation, isVoid and Void)
end

local function getContinueActions(task) 
  local continueActions = task.continueActions
  if continueActions == nil then
    continueActions = {}
    task.continueActions = continueActions
  end
  return continueActions
end

local function addContinueAction(task, f)
  local continueActions = getContinueActions(task)
  continueActions[#continueActions + 1] = assert(f)
end

local function checkTasks(...)
  local tasks
  local n = select("#", ...)
  if n == 1 then
    local args = ...
    if args == nil then throw(ArgumentNullException("tasks")) end
    if System.isArrayLike(args) then
      tasks = args
    elseif System.isEnumerableLike(args) then
      tasks = System.Array.toArray(args)
    end
    if tasks ~= nil then
      for i = 1, #tasks do
        if tasks[i] == System.null then
          throw(ArgumentNullException())
        end
      end
    end
  end
  if tasks == nil then
    tasks = { ... }
    for i = 1, n do
      if tasks[i] == nil then
        throw(ArgumentNullException())
      end
    end
  end
  return tasks
end

local function getDelay(delay)
  if type(delay) == "table" then
    delay = trunc(delay:getTotalMilliseconds())
    if delay < -1 or delay > 2147483647 then
      throw(ArgumentOutOfRangeException("delay"))
    end
  elseif delay < -1 then
    throw(ArgumentOutOfRangeException("millisecondsDelay"))  
  end
  return delay
end

local waitToken = {}
local function getResult(this, await)
  local status = this.status
  if status == TaskStatusRanToCompletion then
    return this.data
  elseif status == TaskStatusFaulted then
    throw(getException(this, await))
  elseif status == TaskStatusCanceled then
    local e = TaskCanceledException(this)
    if not await then e = AggregateException(e) end
    throw(e)
  end
  return waitToken
end

local function getAwaitResult(task)
  local status = task.status
  local ok, v
  if status == TaskStatusRanToCompletion then
    ok, v = true, task.data
  elseif status == TaskStatusFaulted then
    ok, v = false, getException(task, true)
  elseif status == TaskStatusCanceled then
    ok, v = false, TaskCanceledException(task)
  else
    assert(false)
  end
  return ok, v
end

local factory = {
  StartNew = function (_, f, state)
    local t = newWaitingTask()
    post(function ()
      try(function ()
        assert(trySetResult(t, f(state)))
      end, function (e)
        assert(trySetException(t, e))
      end)
    end)
    return t
  end
}

Task = define("System.Threading.Tasks.Task", {
  Dispose = System.emptyFn,
  __ctor__ = function (this, action, state)
    if action == nil then throw(ArgumentNullException("action")) end
    this.status = TaskStatusCreated
    this.data = function ()
      return action(state)
    end
  end,
  getId = getId,
  getCurrentId = function ()
    local t = currentTask
    if t then
      return getId(t)
    end
  end,
  getFactory = function ()
    return factory
  end,
  getStatus = function (this)
    return this.status
  end,
  getException = function (this)
    if this.status == TaskStatusFaulted then
      return getException(this)
    end
    return nil
  end,
  getResult = function (this)
    local result = getResult(this)
    if result == waitToken then
      waitTask(getContinueActions(this))
      result = getResult(this)
      assert(result ~= waitToken)
    end
    return result
  end,
  getIsCompleted = isCompleted,
  getIsCanceled = function (this)
    return this.status == TaskStatusCanceled
  end,
  getIsFaulted = function (this)
    return this.status == TaskStatusFaulted
  end,
  FromResult = fromResult,
  FromCanceled = fromCanceled,
  FromException = fromException,
  getCompletedTask = getCompletedTask,
  Delay = function (delay, cancellationToken)
    delay = getDelay(delay)

    if cancellationToken and cancellationToken:getIsCancellationRequested() then
      return fromCanceled(cancellationToken)
    elseif delay == 0 then
      return getCompletedTask()
    end

    local t = newWaitingTask()
    local timerId, registration  

    if cancellationToken and cancellationToken:getCanBeCanceled() then
      registration = cancellationToken:Register(function ()
        local success = trySetCanceled(t, cancellationToken)
        if success and timerId then
          removeTimer(timerId)
        end
      end)
    end

    if delay ~= -1 then
      timerId = addTimer(function ()
        local success = trySetResult(t)
        if success and registration then
          registration:Dispose()
        end
      end, delay)
    end

    return t
  end,
  Run = function (f, cancellationToken)
    local t = Task(f) 
    t:Start()
    return t
  end,
  WhenAll = function (T, ...)
    local tasks = checkTasks(...)
    local count = #tasks
    if count == 0 then
      return getCompletedTask()
    end
    local result, exceptions, cancelled = {}, {}
    local t = newWaitingTask()
    local function f(task)
      local status = task.status
      if status == TaskStatusRanToCompletion then
        result[#result + 1] = task.data
      elseif status == TaskStatusFaulted then
        local exception = getException(task, true)
        exceptions[#exceptions + 1] = exception
      elseif status == TaskStatusCanceled then
        cancelled = true
      end
      count = count - 1
      if count == 0 then
        if #exceptions > 0 then
          trySetException(t, arrayFromTable(exceptions, Exception))
        elseif cancelled then
          trySetCanceled(t)
        else
          if T then
            trySetResult(t, arrayFromTable(result, T))
          end
            trySetResult(t)
        end
      end
    end
    for i = 1, count do
      local task = tasks[i]
      if isCompleted(task) then
        post(function ()
          f(task)
        end)
      else
        addContinueAction(task, f)
      end
    end
    return t
  end,
  WhenAny = function (...)
    local tasks = checkTasks(...)
    local count = #tasks
    if count == 0 then
      throw(ArgumentException())
    end
    local t = newWaitingTask()
    local function f(task)
      local status = task.status
      if status == TaskStatusRanToCompletion then
        trySetResult(t, task)
      elseif status == TaskStatusFaulted then
        trySetException(t, getException(task))
      elseif status == TaskStatusCanceled then
        trySetCanceled(t)
      end
    end
    for i = 1, count do
      local task = tasks[i]
      if isCompleted(task) then
        post(function ()
          f(task)
        end)
      else
        addContinueAction(task, f)
      end
    end
    return t
  end,
  ContinueWith = function (this, continuationAction)
    if continuationAction == nil then throw(ArgumentNullException("continuationAction")) end
    local t = newWaitingTask()
    local function f(task)
      try(function ()
        t.status = TaskStatusRunning
        assert(trySetResult(t, continuationAction(task)))
      end, function (e)
        assert(trySetException(t, e))
      end)
    end
    if isCompleted(this) then
      post(function ()
        f(this)
      end)
    else
      addContinueAction(this, f)
    end
    return t
  end,
  Start = function (this)
    if this.status ~= TaskStatusCreated then throw(InvalidOperationException("Task was already started.")) end
    this.status = TaskStatusWaitingToRun
    post(function ()
      try(function ()
        this.status = TaskStatusRunning
        assert(trySetResult(this, this.data()))
      end, function (e)
        assert(trySetException(this, e))
      end)
    end)
  end,
  Wait = function (this)
    waitTask(getContinueActions(this))
  end,
  Await = function (this, t)
    local a = t:GetAwaiter()
    if a:getIsCompleted() then
      return a:GetResult()
    end
    a:OnCompleted(function ()
      local ok, v
      try(function ()
        ok, v = true, a:GetResult()
      end, function (e)
        ok, v = false, e
      end)
      ok, v = cresume(this.c, ok, v)
      if not ok then
        assert(trySetException(this, v))
      end
    end)
    local ok, v = cyield()
    if ok then
      return v
    else
      error(v)
    end
  end,
  await = function (this, task)
    if getmetatable(task) ~= Task then
      return this:Await(task)
    end

    local result = getResult(task, true)
    if result ~= waitToken then
      return result
    end
    addContinueAction(task, function (task)
      local ok, v = getAwaitResult(task)
      ok, v = cresume(this.c, ok, v)
      if not ok then
        assert(trySetException(this, v))
      end
    end)
    local ok, v = cyield()
    if ok then
      return v
    else
      error(v)
    end
  end
})
System.Task = Task

local TaskT_TransitionToFinal_AlreadyCompleted = "An attempt was made to transition a task to a final state when it had already completed."
local TaskCompletionSource = define("System.Threading.Tasks.TaskCompletionSource", {
  __ctor__ = function (this)
    this.task = newWaitingTask()
  end,
  getTask = function (this)
    return this.task
  end,
  SetCanceled = function (this)
    if not trySetCanceled(this.task) then
      throw(InvalidOperationException(TaskT_TransitionToFinal_AlreadyCompleted))
    end
  end,
  SetException = function (this, exception)
    if exception == nil then throw(ArgumentNullException("exception")) end
    if not trySetException(this.task, exception) then
      throw(InvalidOperationException(TaskT_TransitionToFinal_AlreadyCompleted))
    end
  end,
  SetResult = function (this, result)
    if not trySetResult(this.task, result) then
      throw(InvalidOperationException(TaskT_TransitionToFinal_AlreadyCompleted))
    end
  end,
  TrySetCanceled = trySetCanceled,
  TrySetException = trySetException,
  TrySetResult = trySetResult
})
System.TaskCompletionSource = TaskCompletionSource

local CancellationTokenRegistration = defStc("System.Threading.CancellationTokenRegistration", (function ()
  local function unregister(this)
    local token = this.token
    if token then
      local f = this.f
      if f then
        this.f = nil
        return token.source:unRegister(f)
      end
    end
    return false
  end
  return {
    base =  function(_, T)
      return { System.IDisposable, System.IEquatable_1(T) }
    end,
    __ctor__ = function (this, token, f)
      if not token then
        return
      end
      this.token = token
      this.f = f
    end,
    getToken = function (this)
      return this.token
    end,
    Equals = System.equals,
    Unregister = unregister,
    Dispose = unregister
  }
end)())
System.CancellationTokenRegistration = CancellationTokenRegistration

local OperationCanceledException = define("System.OperationCanceledException", {
  __tostring = Exception.ToString,
  base = { System.SystemException },
  __ctor__ = function (this, message, innerException, token)
    Exception.__ctor__(this, message or "The operation was canceled.", innerException)
    this.tokne = token
  end,
  getCancellationToken = function (this)
    return this.token
  end
})

local canceledSource
local CancellationToken 
CancellationToken = defStc("System.Threading.CancellationToken", {
  __ctor__ = function (this, canceled)
    if canceled == nil then
      return
    end
    if canceled == true then
      this.source = canceledSource
    elseif canceled then
      this.source = canceled
    end
  end,
  getCanBeCanceled = function (this)
    return this.source ~= nil
  end,
  getIsCancellationRequested = function (this)
    local source = this.source
    if source then
      return source:getIsCancellationRequested()
    end
    return false
  end,
  getNone = function ()
    return CancellationToken()
  end,
  Equals = System.equals,
  Register = function (this, callback, state)
    local source = this.source
    if source then
      if not source:getIsCancellationRequested() then
        local function f()
          callback(state)
        end
        this.source:register(f)
        return CancellationTokenRegistration(this, f)
      end
      callback(state)
    end
    return CancellationTokenRegistration()
  end,
  ThrowIfCancellationRequested = function (this)
    if this:getIsCancellationRequested() then
      throw(OperationCanceledException())
    end
  end
})
System.CancellationToken = CancellationToken

local CancellationTokenSource 
CancellationTokenSource = define("System.Threading.CancellationTokenSource", (function ()
  local function clean(this)
    local timerId = this.timerId
    if timerId then
      removeTimer(timerId)
    end
    local links = this.links
    if links then
      for i = 1, #links do
        links[i]:Dispose()
      end
    end
  end
  return  {
    state = 0,
    base = { System.IDisposable },
    __ctor__  = function (this, delay)
      if delay then
        delay = getDelay(delay)
        if delay == 0 then
          this.state = 1
        else
          this.timerId = addTimer(function ()
            this.Cancel()
          end, delay)
        end
      end
    end,
    Cancel = function (this, throwOnFirstException)
      if this.disposed then throw(ObjectDisposedException()) end
      if this.state == 1  then
        return
      end
      clean(this)
      this.state = 1
      local actions = this.continueActions
      if actions then
        local t = {}
        for i = 1, #actions do
          try(function ()
            actions[i]()          
          end, function (e)
            if throwOnFirstException then
              throw(e)
            end
            t[#t + 1] = e
          end)
        end
        if #t > 0 then
          throw(AggregateException(arrayFromTable(t, Exception)))
        end
      end
    end,
    CancelAfter = function (this, delay)
      if this.disposed then throw(ObjectDisposedException()) end
      delay = getDelay(delay)
      if this.state == 1  then
        return
      end
      local timerId = this.timerId
      if timerId then
        removeTimer(timerId)
      end
      this.timerId = addTimer(function ()
        this:Cancel()
      end, delay)
    end,
    Dispose = function (this)
      if this.disposed then
        return
      end
      clean(this)
      this.disposed = true
    end,
    getIsCancellationRequested = function (this)
      return this.state == 1
    end,
    getToken = function (this)
      local t = this.token
      if not t then
        t = CancellationToken(this)
        this.token = t
      end
      return t
    end,
    register = addContinueAction,
    unRegister = function (this, f)
      local actions = this.continueActions
      if actions then
        for i = 1, #actions do
          if actions[i] == f then
            tremove(actions, i)
            return true
          end
        end
      end
      return false
    end,
    CreateLinkedTokenSource = function (...)
      local cts, links, count = CancellationTokenSource(), {}, 1
      cts.links = links
      local n = select("#", ...)
      if n == 1 then
        local args = ...
        if System.isArrayLike(args) then
          for i = 1, #args do
            links[count] = args[i]:Register(cts.Cancel, cts)
            count = count + 1 
          end
          return cts
        end
      end
      for i = 1, n do
        local token = select(i, ...)
        links[count] = token:Register(cts.Cancel, cts)
        count = count + 1 
      end
      return cts
    end
  }
end)())
System.CancellationTokenSource = CancellationTokenSource
canceledSource = setmetatable({ state = 1 }, CancellationTokenSource)

local function taskCoroutineCreate(t, f)
  local c = ccreate(function (...)
    local r = f(t, ...)
    assert(trySetResult(t, r))
  end)
  t.c = c
  return c
end

function System.async(f, void, ...)
  local t = newWaitingTask(void)
  local c = taskCoroutineCreate(t, f)
  local ok, v = cresume(c, ...)
  if not ok then
    assert(trySetException(t, v))
  end
  return t
end

local IAsyncDisposable = System.defInf("System.IAsyncDisposable")
local IAsyncEnumerable = System.defInf("System.Collections.Generic.IAsyncEnumerable", System.emptyFn, nil, 1)
local IAsyncEnumerator = System.defInf("System.Collections.Generic.IAsyncEnumerator", System.emptyFn, nil, 1)

System.IAsyncEnumerable_1 =  IAsyncEnumerable
System.IAsyncEnumerator_1 = IAsyncEnumerator

local yieldAsync 
local function checkYieldAsync(this, ok, v, current)
  if ok then
    if v == yieldAsync then
      this.e.current = current
      assert(trySetResult(this.t, true))
    elseif v == cpool then
      this.c = nil
      this.e.current = nil
      assert(trySetResult(this.t, false))
    end
  else
    assert(trySetException(this.t, v))
  end
end
yieldAsync = {
  __index = false,
  await = function (this, task)
    local result = getResult(task, true)
    if result ~= waitToken then
      return result
    end
    addContinueAction(task, function (task)
      local current
      local ok, v = getAwaitResult(task)
      ok, v, current = cresume(this.c, ok, v)
      checkYieldAsync(this, ok, v, current)
    end)
    local ok, v = cyield()
    if ok then
      return v
    else
      error(v)
    end
  end,
  yield = function (this, v)
    cyield(yieldAsync, v)
  end
}
yieldAsync.__index = yieldAsync

local YieldAsyncEnumerable
YieldAsyncEnumerable = define("System.YieldAsyncEnumerable", function (T)
   return {
    base = { IAsyncEnumerable(T), IAsyncEnumerator(T), IAsyncDisposable },
    __genericT__ = T
  }
end, {
  getCurrent = System.getCurrent, 
  GetAsyncEnumerator = function (this)
    return setmetatable({ f = this.f, args = this.args }, YieldAsyncEnumerable(this.__genericT__))
  end,
  DisposeAsync = function (this)
    return getCompletedTask()
  end,
  MoveNextAsync = function (this)
    local a = this.a
    if a and a.c == nil then
      return fromResult(false)
    end

    local t = newWaitingTask()
    local ok, v, current
    if a == nil then
      local c = ccreate(this.f)
      a = setmetatable({ t = t, c = c, e = this }, yieldAsync)
      this.a = a
      local args = this.args
      ok, v, current = cresume(c, a, unpack(args, 1, args.n))
      this.args = nil
    else
      a.t = t
      ok, v, current = cresume(a.c)
    end
    checkYieldAsync(a, ok, v, current)
    return t
  end
}, 1)

local function yieldIAsyncEnumerable(f, T, ...)
  return setmetatable({ f = f, args = pack(...) }, YieldAsyncEnumerable(T))
end

System.yieldIAsyncEnumerable = yieldIAsyncEnumerable
System.yieldIAsyncEnumerator = yieldIAsyncEnumerable

local function eachFn(en, async)
  if async:await(en:MoveNextAsync()) then
    return async, en:getCurrent()
  end
  return nil
end

local function each(async, t)
  if t == nil then throw(NullReferenceException(), 1) end
  local en = t:GetAsyncEnumerator()
  return eachFn, en, async
end

System.asynceach = each
end

-- CoreSystemLib: Utilities.lua
do
local System = System
local throw = System.throw
local define = System.define
local trunc = System.trunc
local sl = System.sl
local bor = System.bor
local TimeSpan = System.TimeSpan
local ArgumentNullException = System.ArgumentNullException

local select = select
local type = type
local os = os
local clock = os.clock
local tostring = tostring
local collectgarbage = collectgarbage

define("System.Environment", {
  Exit = os.exit,
  getStackTrace = System.traceback,
  getTickCount = function ()
    return System.currentTimeMillis() % 2147483648
  end
})

define("System.GC", {
  Collect = function ()
    collectgarbage("collect")
  end,
  GetTotalMemory = function (forceFullCollection)
    if forceFullCollection then 
      collectgarbage("collect")
    end
    return collectgarbage("count") * 1024
  end
})

local Lazy = {
  created = false,
  __ctor__ = function (this, ...)
    local n = select("#", ...)
    if n == 0 then
    elseif n == 1 then
      local valueFactory = ...
      if valueFactory == nil then
        throw(ArgumentNullException("valueFactory"))
      elseif type(valueFactory) ~= "boolean" then
        this.valueFactory = valueFactory
      end
    elseif n == 2 then
      local valueFactory = ...
      if valueFactory == nil then
        throw(ArgumentNullException("valueFactory"))
      end
      this.valueFactory = valueFactory
    end
  end,
  getIsValueCreated = function (this)
    return this.created
  end,
  getValue = function (this)
    if not this.created then
      local valueFactory = this.valueFactory
      if valueFactory then
        this.value = valueFactory()
        this.valueFactory = nil
      else
        this.value = this.__genericT__()
      end
      this.created = true
    end
    return this.value
  end,
  ToString = function (this)
    if this.created then
      return this.value:ToString()
    end
    return "Value is not created."
  end
}

define("System.Lazy", function (T)
  return { 
    __genericT__ = T 
  }
end, Lazy, 1)

local ticker, frequency
local time = System.config.time
if time then
  ticker = time
  frequency = 10000
else
  ticker = clock
  frequency = 1000
end

local function getRawElapsedSeconds(this)
  local timeElapsed = this.elapsed
  if this.running then
    local currentTimeStamp = ticker()
    local elapsedUntilNow  = currentTimeStamp - this.startTimeStamp
    timeElapsed = timeElapsed + elapsedUntilNow
  end
  return timeElapsed
end

local Stopwatch
Stopwatch = define("System.Diagnostics.Stopwatch", {
  elapsed = 0,
  running = false,
  IsHighResolution = false,
  Frequency = frequency,
  StartNew = function ()
    local t = Stopwatch()
    t:Start()
    return t
  end,
  GetTimestamp = function ()
    return trunc(ticker() * frequency)
  end,
  Start = function (this)
    if not this.running then
      this.startTimeStamp = ticker()
      this.running = true
    end
  end,
  Stop = function (this)
    if this.running then
      local endTimeStamp = ticker()
      local elapsedThisPeriod = endTimeStamp - this.startTimeStamp
      local elapsed = this.elapsed + elapsedThisPeriod
      this.running = false
      if elapsed < 0 then
        -- os.clock may be return negative value
        elapsed = 0
      end
      this.elapsed = elapsed
    end
  end,
  Reset = function (this)
    this.elapsed = 0
    this.running = false
    this.startTimeStamp = 0
  end,
  Restart = function (this)
    this.elapsed = 0
    this.startTimeStamp = ticker()
    this.running = true
  end,
  getIsRunning = function (this)
    return this.running
  end,
  getElapsed = function (this)
    return TimeSpan(trunc(getRawElapsedSeconds(this) * 1e7))
  end,
  getElapsedMilliseconds = function (this)
    return trunc(getRawElapsedSeconds(this) * 1000)
  end,
  getElapsedTicks = function (this)
    return trunc(getRawElapsedSeconds(this) * frequency)
  end
})
System.Stopwatch = Stopwatch

local weaks = setmetatable({}, { __mode = "kv" })

local function setWeakTarget(this, target)
  weaks[this] = target
end

define("System.WeakReference", {
  trackResurrection = false,
  SetTarget = setWeakTarget,
  setTarget = setWeakTarget,
  __ctor__ = function (this, target, trackResurrection)
    if trackResurrection then
      this.trackResurrection = trackResurrection
    end
    weaks[this] = target
  end,
  TryGetTarget = function (this)
    local target = weaks[this]
    return target ~= nil, target
  end,
  getIsAlive = function (this)
    return weaks[this] ~= nil
  end,
  getTrackResurrection = function (this)
    return this.trackResurrection
  end,
  getTarget = function (this)
    return weaks[this]
  end
})

define("System.Guid", {})
define("System.ArraySegment", {})
end

-- CoreSystemLib: Globalization/Globalization.lua
do
local System = System
local emptyFn = System.emptyFn
local define = System.define

define("System.Globalization.NumberFormatInfo", {
  getInvariantInfo = emptyFn,
  getCurrentInfo = emptyFn,
})

define("System.Globalization.CultureInfo", {
  getInvariantCulture = emptyFn,
})

define("System.Globalization.DateTimeFormatInfo", {
  getInvariantInfo = emptyFn,
})
end

-- CoreSystemLib: Numerics/HashCodeHelper.lua
do
local System = System
local bitLShift = System.sl
local bitNot = System.bnot

local HashCodeHelper = {}

function HashCodeHelper.CombineHashCodes(h1, h2)
  return (bitLShift(h1, 5) + h1) * bitNot(h2)
end

System.define("System.Numerics.HashCodeHelper", HashCodeHelper)
end

-- CoreSystemLib: Numerics/Complex.lua
do
-- Compiled from https://github.com/dotnet/corefx/blob/master/src/System.Runtime.Numerics/src/System/Numerics/Complex.cs
-- Generated by CSharp.lua Compiler
-- Licensed to the .NET Foundation under one or more agreements.
-- The .NET Foundation licenses this file to you under the MIT license.
-- See the LICENSE file in the project root for more information.
local System = System

local assert = assert
local type = type
local math = math

-- <summary>
-- A complex number z is a number of the form z = x + yi, where x and y
-- are real numbers, and i is the imaginary unit, with the property i2= -1.
-- </summary>
System.define("System.Numerics.Complex", (function ()
  local Zero, One, ImaginaryOne, NaN, Infinity, s_sqrtRescaleThreshold, s_asinOverflowThreshold, s_log2, 
  getReal, getImaginary, getMagnitude, getPhase, FromPolarCoordinates, Negate, Add, Subtract, 
  Multiply, Divide, Abs, Hypot, Log1P, Conjugate, Reciprocal, op_Equality, EqualsObj, Equals, 
  GetHashCode, ToString, Sin, Sinh, Asin, Cos, Cosh, Acos, 
  Tan, Tanh, Atan, Asin_Internal, IsFinite, IsInfinity, IsNaN, Log, 
  Log10, Exp, Sqrt, Pow, Pow1, Scale, ToComplex, 
  class, static, __ctor__
  static = function (this)
    Zero = class(0.0, 0.0)
    this.Zero = Zero
    One = class(1.0, 0.0)
    this.One = One
    ImaginaryOne = class(0.0, 1.0)
    this.ImaginaryOne = ImaginaryOne
    NaN = class(System.Double.NaN, System.Double.NaN)
    this.NaN = NaN
    Infinity = class(System.Double.PositiveInfinity, System.Double.PositiveInfinity)
    this.Infinity = Infinity
    s_sqrtRescaleThreshold = 1.79769313486232E+308 --[[Double.MaxValue]] / (math.Sqrt(2.0) + 1.0)
    s_asinOverflowThreshold = math.Sqrt(1.79769313486232E+308 --[[Double.MaxValue]]) / 2.0
    s_log2 = math.Log(2.0)
  end
  __ctor__ = function (this, real, imaginary)
    if real == nil then
      return
    end
    this.m_real = real
    this.m_imaginary = imaginary
  end
  getReal = function (this)
    return this.m_real
  end
  getImaginary = function (this)
    return this.m_imaginary
  end
  getMagnitude = function (this)
    return Abs(this)
  end
  getPhase = function (this)
    return math.Atan2(this.m_imaginary, this.m_real)
  end
  FromPolarCoordinates = function (magnitude, phase)
    return class(magnitude * math.Cos(phase), magnitude * math.Sin(phase))
  end
  Negate = function (value)
    return class(- value.m_real, - value.m_imaginary)
  end
  Add = function (left, right)
    if type(left) == "number" then
      return class(left + right.m_real, right.m_imaginary)
    elseif type(right) == "number" then
      return class(left.m_real + right, left.m_imaginary)
    else
      return class(left.m_real + right.m_real, left.m_imaginary + right.m_imaginary)
    end
  end
  Subtract = function (left, right)
    if type(left) == "number" then
      return class(left - right.m_real, - right.m_imaginary)
    elseif type(right) == "number" then
      return class(left.m_real - right, left.m_imaginary)
    else
      return class(left.m_real - right.m_real, left.m_imaginary - right.m_imaginary)
    end
  end
  Multiply = function (left, right)
    if type(left) == "number" then
      if not System.Double.IsFinite(right.m_real) then
        if not System.Double.IsFinite(right.m_imaginary) then
          return class(System.Double.NaN, System.Double.NaN)
        end

        return class(left * right.m_real, System.Double.NaN)
      end

      if not System.Double.IsFinite(right.m_imaginary) then
        return class(System.Double.NaN, left * right.m_imaginary)
      end

      return class(left * right.m_real, left * right.m_imaginary)
    elseif type(right) == "number" then
      if not System.Double.IsFinite(left.m_real) then
        if not System.Double.IsFinite(left.m_imaginary) then
          return class(System.Double.NaN, System.Double.NaN)
        end

        return class(left.m_real * right, System.Double.NaN)
      end

      if not System.Double.IsFinite(left.m_imaginary) then
        return class(System.Double.NaN, left.m_imaginary * right)
      end

      return class(left.m_real * right, left.m_imaginary * right)
    else
      -- Multiplication:  (a + bi)(c + di) = (ac -bd) + (bc + ad)i
      local result_realpart = (left.m_real * right.m_real) - (left.m_imaginary * right.m_imaginary)
      local result_imaginarypart = (left.m_imaginary * right.m_real) + (left.m_real * right.m_imaginary)
      return class(result_realpart, result_imaginarypart)
    end
  end
  Divide = function (left, right)
    if type(left) == "number" then
      -- Division : Smith's formula.
      local a = left
      local c = right.m_real
      local d = right.m_imaginary

      -- Computing c * c + d * d will overflow even in cases where the actual result of the division does not overflow.
      if math.Abs(d) < math.Abs(c) then
        local doc = d / c
        return class(a / (c + d * doc), (- a * doc) / (c + d * doc))
      else
        local cod = c / d
        return class(a * cod / (d + c * cod), - a / (d + c * cod))
      end
    elseif type(right) == "number" then
      -- IEEE prohibit optimizations which are value changing
      -- so we make sure that behaviour for the simplified version exactly match
      -- full version.
      if right == 0 then
        return class(System.Double.NaN, System.Double.NaN)
      end

      if not System.Double.IsFinite(left.m_real) then
        if not System.Double.IsFinite(left.m_imaginary) then
          return class(System.Double.NaN, System.Double.NaN)
        end

        return class(left.m_real / right, System.Double.NaN)
      end

      if not System.Double.IsFinite(left.m_imaginary) then
        return class(System.Double.NaN, left.m_imaginary / right)
      end

      -- Here the actual optimized version of code.
      return class(left.m_real / right, left.m_imaginary / right)
    else
      -- Division : Smith's formula.
      local a = left.m_real
      local b = left.m_imaginary
      local c = right.m_real
      local d = right.m_imaginary

      -- Computing c * c + d * d will overflow even in cases where the actual result of the division does not overflow.
      if math.Abs(d) < math.Abs(c) then
        local doc = d / c
        return class((a + b * doc) / (c + d * doc), (b - a * doc) / (c + d * doc))
      else
        local cod = c / d
        return class((b + a * cod) / (d + c * cod), (- a + b * cod) / (d + c * cod))
      end
    end
  end
  Abs = function (value)
    return Hypot(value.m_real, value.m_imaginary)
  end
  Hypot = function (a, b)
    -- Using
    --   sqrt(a^2 + b^2) = |a| * sqrt(1 + (b/a)^2)
    -- we can factor out the larger component to dodge overflow even when a * a would overflow.

    a = math.Abs(a)
    b = math.Abs(b)

    local small, large
    if a < b then
      small = a
      large = b
    else
      small = b
      large = a
    end

    if small == 0.0 then
      return large
    elseif System.Double.IsPositiveInfinity(large) and not System.Double.IsNaN(small) then
      -- The NaN test is necessary so we don't return +inf when small=NaN and large=+inf.
      -- NaN in any other place returns NaN without any special handling.
      return (System.Double.PositiveInfinity)
    else
      local ratio = small / large
      return (large * math.Sqrt(1.0 + ratio * ratio))
    end
  end
  Log1P = function (x)
    -- Compute log(1 + x) without loss of accuracy when x is small.

    -- Our only use case so far is for positive values, so this isn't coded to handle negative values.
    assert((x >= 0.0) or System.Double.IsNaN(x))

    local xp1 = 1.0 + x
    if xp1 == 1.0 then
      return x
    elseif x < 0.75 then
      -- This is accurate to within 5 ulp with any floating-point system that uses a guard digit,
      -- as proven in Theorem 4 of "What Every Computer Scientist Should Know About Floating-Point
      -- Arithmetic" (https://docs.oracle.com/cd/E19957-01/806-3568/ncg_goldberg.html)
      return x * math.Log(xp1) / (xp1 - 1.0)
    else
      return math.Log(xp1)
    end
  end
  Conjugate = function (value)
    -- Conjugate of a Complex number: the conjugate of x+i*y is x-i*y
    return class(value.m_real, - value.m_imaginary)
  end
  Reciprocal = function (value)
    -- Reciprocal of a Complex number : the reciprocal of x+i*y is 1/(x+i*y)
    if value.m_real == 0 and value.m_imaginary == 0 then
      return Zero
    end
    return One / value
  end
  op_Equality = function (left, right)
    return left.m_real == right.m_real and left.m_imaginary == right.m_imaginary
  end
  EqualsObj = function (this, obj)
    if not (System.is(obj, class)) then
      return false
    end
    return Equals(this, System.cast(class, obj))
  end
  Equals = function (this, value)
    return this.m_real:Equals(value.m_real) and this.m_imaginary:Equals(value.m_imaginary)
  end
  GetHashCode = function (this)
    local n1 = 99999997
    local realHash = System.mod(this.m_real:GetHashCode(), n1)
    local imaginaryHash = this.m_imaginary:GetHashCode()
    local finalHash = System.xor(realHash, imaginaryHash)
    return finalHash
  end
  ToString = function (this)
    return ("(%s, %s)"):format(this.m_real, this.m_imaginary)
  end
  Sin = function (value)
    -- We need both sinh and cosh of imaginary part. To avoid multiple calls to Math.Exp with the same value,
    -- we compute them both here from a single call to Math.Exp.
    local p = math.Exp(value.m_imaginary)
    local q = 1.0 / p
    local sinh = (p - q) * 0.5
    local cosh = (p + q) * 0.5
    return class(math.Sin(value.m_real) * cosh, math.Cos(value.m_real) * sinh)
    -- There is a known limitation with this algorithm: inputs that cause sinh and cosh to overflow, but for
    -- which sin or cos are small enough that sin * cosh or cos * sinh are still representable, nonetheless
    -- produce overflow. For example, Sin((0.01, 711.0)) should produce (~3.0E306, PositiveInfinity), but
    -- instead produces (PositiveInfinity, PositiveInfinity). 
  end
  Sinh = function (value)
    -- Use sinh(z) = -i sin(iz) to compute via sin(z).
    local sin = Sin(class(- value.m_imaginary, value.m_real))
    return class(sin.m_imaginary, - sin.m_real)
  end
  Asin = function (value)
    local b, bPrime, v
    b, bPrime, v = Asin_Internal(math.Abs(getReal(value)), math.Abs(getImaginary(value)))

    local u
    if bPrime < 0.0 then
      u = math.Asin(b)
    else
      u = math.Atan(bPrime)
    end

    if getReal(value) < 0.0 then
      u = - u
    end
    if getImaginary(value) < 0.0 then
      v = - v
    end

    return class(u, v)
  end
  Cos = function (value)
    local p = math.Exp(value.m_imaginary)
    local q = 1.0 / p
    local sinh = (p - q) * 0.5
    local cosh = (p + q) * 0.5
    return class(math.Cos(value.m_real) * cosh, - math.Sin(value.m_real) * sinh)
  end
  Cosh = function (value)
    -- Use cosh(z) = cos(iz) to compute via cos(z).
    return Cos(class(- value.m_imaginary, value.m_real))
  end
  Acos = function (value)
    local b, bPrime, v
    b, bPrime, v = Asin_Internal(math.Abs(getReal(value)), math.Abs(getImaginary(value)))

    local u
    if bPrime < 0.0 then
      u = math.Acos(b)
    else
      u = math.Atan(1.0 / bPrime)
    end

    if getReal(value) < 0.0 then
      u = 3.14159265358979 --[[Math.PI]] - u
    end
    if getImaginary(value) > 0.0 then
      v = - v
    end

    return class(u, v)
  end
  Tan = function (value)
    -- tan z = sin z / cos z, but to avoid unnecessary repeated trig computations, use
    --   tan z = (sin(2x) + i sinh(2y)) / (cos(2x) + cosh(2y))
    -- (see Abramowitz & Stegun 4.3.57 or derive by hand), and compute trig functions here.

    -- This approach does not work for |y| > ~355, because sinh(2y) and cosh(2y) overflow,
    -- even though their ratio does not. In that case, divide through by cosh to get:
    --   tan z = (sin(2x) / cosh(2y) + i \tanh(2y)) / (1 + cos(2x) / cosh(2y))
    -- which correctly computes the (tiny) real part and the (normal-sized) imaginary part.

    local x2 = 2.0 * value.m_real
    local y2 = 2.0 * value.m_imaginary
    local p = math.Exp(y2)
    local q = 1.0 / p
    local cosh = (p + q) * 0.5
    if math.Abs(value.m_imaginary) <= 4.0 then
      local sinh = (p - q) * 0.5
      local D = math.Cos(x2) + cosh
      return class(math.Sin(x2) / D, sinh / D)
    else
      local D = 1.0 + math.Cos(x2) / cosh
      return class(math.Sin(x2) / cosh / D, math.Tanh(y2) / D)
    end
  end
  Tanh = function (value)
    -- Use tanh(z) = -i tan(iz) to compute via tan(z).
    local tan = Tan(class(- value.m_imaginary, value.m_real))
    return class(tan.m_imaginary, - tan.m_real)
  end
  Atan = function (value)
    local two = class(2.0, 0.0)
    return (ImaginaryOne / two) * (Log(One - (ImaginaryOne * value)) - Log(One + ImaginaryOne * value))
  end
  Asin_Internal = function (x, y, b, bPrime, v)
    -- This method for the inverse complex sine (and cosine) is described in Hull, Fairgrieve,
    -- and Tang, "Implementing the Complex Arcsine and Arccosine Functions Using Exception Handling",
    -- ACM Transactions on Mathematical Software (1997)
    -- (https://www.researchgate.net/profile/Ping_Tang3/publication/220493330_Implementing_the_Complex_Arcsine_and_Arccosine_Functions_Using_Exception_Handling/links/55b244b208ae9289a085245d.pdf)

    -- First, the basics: start with sin(w) = (e^{iw} - e^{-iw}) / (2i) = z. Here z is the input
    -- and w is the output. To solve for w, define t = e^{i w} and multiply through by t to
    -- get the quadratic equation t^2 - 2 i z t - 1 = 0. The solution is t = i z + sqrt(1 - z^2), so
    --   w = arcsin(z) = - i log( i z + sqrt(1 - z^2) )
    -- Decompose z = x + i y, multiply out i z + sqrt(1 - z^2), use log(s) = |s| + i arg(s), and do a
    -- bunch of algebra to get the components of w = arcsin(z) = u + i v
    --   u = arcsin(beta)  v = sign(y) log(alpha + sqrt(alpha^2 - 1))
    -- where
    --   alpha = (rho + sigma) / 2      beta = (rho - sigma) / 2
    --   rho = sqrt((x + 1)^2 + y^2)    sigma = sqrt((x - 1)^2 + y^2)
    -- These formulas appear in DLMF section 4.23. (http://dlmf.nist.gov/4.23), along with the analogous
    --   arccos(w) = arccos(beta) - i sign(y) log(alpha + sqrt(alpha^2 - 1))
    -- So alpha and beta together give us arcsin(w) and arccos(w).

    -- As written, alpha is not susceptible to cancelation errors, but beta is. To avoid cancelation, note
    --   beta = (rho^2 - sigma^2) / (rho + sigma) / 2 = (2 x) / (rho + sigma) = x / alpha
    -- which is not subject to cancelation. Note alpha >= 1 and |beta| <= 1.

    -- For alpha ~ 1, the argument of the log is near unity, so we compute (alpha - 1) instead,
    -- write the argument as 1 + (alpha - 1) + sqrt((alpha - 1)(alpha + 1)), and use the log1p function
    -- to compute the log without loss of accuracy.
    -- For beta ~ 1, arccos does not accurately resolve small angles, so we compute the tangent of the angle
    -- instead.
    -- Hull, Fairgrieve, and Tang derive formulas for (alpha - 1) and beta' = tan(u) that do not suffer
    -- from cancelation in these cases.

    -- For simplicity, we assume all positive inputs and return all positive outputs. The caller should
    -- assign signs appropriate to the desired cut conventions. We return v directly since its magnitude
    -- is the same for both arcsin and arccos. Instead of u, we usually return beta and sometimes beta'.
    -- If beta' is not computed, it is set to -1; if it is computed, it should be used instead of beta
    -- to determine u. Compute u = arcsin(beta) or u = arctan(beta') for arcsin, u = arccos(beta)
    -- or arctan(1/beta') for arccos.

    assert((x >= 0.0) or System.Double.IsNaN(x))
    assert((y >= 0.0) or System.Double.IsNaN(y))

    -- For x or y large enough to overflow alpha^2, we can simplify our formulas and avoid overflow.
    if (x > s_asinOverflowThreshold) or (y > s_asinOverflowThreshold) then
      b = - 1.0
      bPrime = x / y

      local small, big
      if x < y then
        small = x
        big = y
      else
        small = y
        big = x
      end
      local ratio = small / big
      v = s_log2 + math.Log(big) + 0.5 * Log1P(ratio * ratio)
    else
      local r = Hypot((x + 1.0), y)
      local s = Hypot((x - 1.0), y)

      local a = (r + s) * 0.5
      b = x / a

      if b > 0.75 then
        if x <= 1.0 then
          local amx = (y * y / (r + (x + 1.0)) + (s + (1.0 - x))) * 0.5
          bPrime = x / math.Sqrt((a + x) * amx)
        else
          -- In this case, amx ~ y^2. Since we take the square root of amx, we should
          -- pull y out from under the square root so we don't lose its contribution
          -- when y^2 underflows.
          local t = (1.0 / (r + (x + 1.0)) + 1.0 / (s + (x - 1.0))) * 0.5
          bPrime = x / y / math.Sqrt((a + x) * t)
        end
      else
        bPrime = - 1.0
      end

      if a < 1.5 then
        if x < 1.0 then
          -- This is another case where our expression is proportional to y^2 and
          -- we take its square root, so again we pull out a factor of y from
          -- under the square root.
          local t = (1.0 / (r + (x + 1.0)) + 1.0 / (s + (1.0 - x))) * 0.5
          local am1 = y * y * t
          v = Log1P(am1 + y * math.Sqrt(t * (a + 1.0)))
        else
          local am1 = (y * y / (r + (x + 1.0)) + (s + (x - 1.0))) * 0.5
          v = Log1P(am1 + math.Sqrt(am1 * (a + 1.0)))
        end
      else
        -- Because of the test above, we can be sure that a * a will not overflow.
        v = math.Log(a + math.Sqrt((a - 1.0) * (a + 1.0)))
      end
    end
    return b, bPrime, v
  end
  IsFinite = function (value)
    return System.Double.IsFinite(value.m_real) and System.Double.IsFinite(value.m_imaginary)
  end
  IsInfinity = function (value)
    return System.Double.IsInfinity(value.m_real) or System.Double.IsInfinity(value.m_imaginary)
  end
  IsNaN = function (value)
    return not IsInfinity(value) and not IsFinite(value)
  end
  Log = function (value, baseValue)
    if baseValue ~= nil then
      return (Log(value) / Log(ToComplex(baseValue))) 
    end
    return class(math.Log(Abs(value)), math.Atan2(value.m_imaginary, value.m_real))
  end
  Log10 = function (value)
    local tempLog = Log(value)
    return Scale(tempLog, 0.43429448190325 --[[Complex.InverseOfLog10]])
  end
  Exp = function (value)
    local expReal = math.Exp(value.m_real)
    local cosImaginary = expReal * math.Cos(value.m_imaginary)
    local sinImaginary = expReal * math.Sin(value.m_imaginary)
    return class(cosImaginary, sinImaginary)
  end
  Sqrt = function (value)
    local m_real = value.m_real
    local m_imaginary = value.m_imaginary
    if m_imaginary == 0.0 then
      -- Handle the trivial case quickly.
      if m_real < 0.0 then
        return class(0.0, math.Sqrt(- m_real))
      else
        return class(math.Sqrt(m_real), 0.0)
      end
    else
      -- One way to compute Sqrt(z) is just to call Pow(z, 0.5), which coverts to polar coordinates
      -- (sqrt + atan), halves the phase, and reconverts to cartesian coordinates (cos + sin).
      -- Not only is this more expensive than necessary, it also fails to preserve certain expected
      -- symmetries, such as that the square root of a pure negative is a pure imaginary, and that the
      -- square root of a pure imaginary has exactly equal real and imaginary parts. This all goes
      -- back to the fact that Math.PI is not stored with infinite precision, so taking half of Math.PI
      -- does not land us on an argument with cosine exactly equal to zero.

      -- To find a fast and symmetry-respecting formula for complex square root,
      -- note x + i y = \sqrt{a + i b} implies x^2 + 2 i x y - y^2 = a + i b,
      -- so x^2 - y^2 = a and 2 x y = b. Cross-substitute and use the quadratic formula to obtain
      --   x = \sqrt{\frac{\sqrt{a^2 + b^2} + a}{2}}  y = \pm \sqrt{\frac{\sqrt{a^2 + b^2} - a}{2}}
      -- There is just one complication: depending on the sign on a, either x or y suffers from
      -- cancelation when |b| << |a|. We can get aroud this by noting that our formulas imply
      -- x^2 y^2 = b^2 / 4, so |x| |y| = |b| / 2. So after computing the one that doesn't suffer
      -- from cancelation, we can compute the other with just a division. This is basically just
      -- the right way to evaluate the quadratic formula without cancelation.

      -- All this reduces our total cost to two sqrts and a few flops, and it respects the desired
      -- symmetries. Much better than atan + cos + sin!

      -- The signs are a matter of choice of branch cut, which is traditionally taken so x > 0 and sign(y) = sign(b).

      -- If the components are too large, Hypot will overflow, even though the subsequent sqrt would
      -- make the result representable. To avoid this, we re-scale (by exact powers of 2 for accuracy)
      -- when we encounter very large components to avoid intermediate infinities.
      local rescale = false
      if (math.Abs(m_real) >= s_sqrtRescaleThreshold) or (math.Abs(m_imaginary) >= s_sqrtRescaleThreshold) then
        if System.Double.IsInfinity(m_imaginary) and not System.Double.IsNaN(m_real) then
          -- We need to handle infinite imaginary parts specially because otherwise
          -- our formulas below produce inf/inf = NaN. The NaN test is necessary
          -- so that we return NaN rather than (+inf,inf) for (NaN,inf).
          return (class(System.Double.PositiveInfinity, m_imaginary))
        else
          m_real = m_real * 0.25
          m_imaginary = m_imaginary * 0.25
          rescale = true
        end
      end

      -- This is the core of the algorithm. Everything else is special case handling.
      local x, y
      if m_real >= 0.0 then
        x = math.Sqrt((Hypot(m_real, m_imaginary) + m_real) * 0.5)
        y = m_imaginary / (2.0 * x)
      else
        y = math.Sqrt((Hypot(m_real, m_imaginary) - m_real) * 0.5)
        if m_imaginary < 0.0 then
          y = - y
        end
        x = m_imaginary / (2.0 * y)
      end

      if rescale then
        x = x * 2.0
        y = y * 2.0
      end

      return class(x, y)
    end
  end
  Pow = function (value, power)
    if power == Zero then
      return One
    end

    if value == Zero then
      return Zero
    end

    local valueReal = value.m_real
    local valueImaginary = value.m_imaginary
    local powerReal = power.m_real
    local powerImaginary = power.m_imaginary

    local rho = Abs(value)
    local theta = math.Atan2(valueImaginary, valueReal)
    local newRho = powerReal * theta + powerImaginary * math.Log(rho)

    local t = math.Pow(rho, powerReal) * math.Pow(2.71828182845905 --[[Math.E]], - powerImaginary * theta)

    return class(t * math.Cos(newRho), t * math.Sin(newRho))
  end
  Pow1 = function (value, power)
    return Pow(value, class(power, 0))
  end
  Scale = function (value, factor)
    local realResult = factor * value.m_real
    local imaginaryResuilt = factor * value.m_imaginary
    return class(realResult, imaginaryResuilt)
  end
  ToComplex = function (value)
    return class(value, 0.0)
  end
  class = {
    base = function (out, T)
      return {
        System.IEquatable_1(T),
        System.IFormattable
      }
    end,
    m_real = 0,
    m_imaginary = 0,
    getReal = getReal,
    getImaginary = getImaginary,
    getMagnitude = getMagnitude,
    getPhase = getPhase,
    FromPolarCoordinates = FromPolarCoordinates,
    Negate = Negate,
    Add = Add,
    Subtract = Subtract,
    Multiply = Multiply,
    Divide = Divide,
    Abs = Abs,
    Conjugate = Conjugate,
    Reciprocal = Reciprocal,
    EqualsObj = EqualsObj,
    Equals = Equals,
    GetHashCode = GetHashCode,
    ToString = ToString,
    Sin = Sin,
    Sinh = Sinh,
    Asin = Asin,
    Cos = Cos,
    Cosh = Cosh,
    Acos = Acos,
    Tan = Tan,
    Tanh = Tanh,
    Atan = Atan,
    IsFinite = IsFinite,
    IsInfinity = IsInfinity,
    IsNaN = IsNaN,
    Log = Log,
    Log10 = Log10,
    Exp = Exp,
    Sqrt = Sqrt,
    Pow = Pow,
    Pow1 = Pow1,
    ToComplex = ToComplex,
    static = static,
    __ctor__ = __ctor__,
    __add = Add,
    __sub = Subtract,
    __mul = Multiply,
    __div = Divide,
    __unm = Negate,
    __eq = op_Equality
  }
  return class
end)())

end

-- CoreSystemLib: Numerics/Matrix3x2.lua
do
local System = System
local SystemNumerics = System.Numerics

local tan = math.tan
local cos = math.cos
local sin = math.sin
local abs = math.abs

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1

local new = function (cls, ...)
    local this = setmetatable({}, cls)
    return this, cls.__ctor__(this, ...)
end

local Matrix3x2 = {}

Matrix3x2.__ctor__ = function(this, m11, m12, m21, m22, m31, m32)
    this.M11 = m11 or 0
    this.M12 = m12 or 0
    this.M21 = m21 or 0
    this.M22 = m22 or 0
    this.M31 = m31 or 0
    this.M32 = m32 or 0
    local mt = getmetatable(this)
    mt.__unm = Matrix3x2.op_UnaryNegation
    setmetatable(this, mt)
end

Matrix3x2.base = function (_, T)
    return { IComparable, IComparable_1(T), IEquatable_1(T) }
end

Matrix3x2.getIdentity = function ()
    return new(Matrix3x2, 1, 0, 0, 1, 0, 0)
end

Matrix3x2.getIsIdentity = function (this)
    return this.M11 == 1 and this.M22 == 1 and this.M12 == 0 and this.M21 == 0 and this.M31 == 0 and this.M32 == 0
end

Matrix3x2.getTranslation = function (this)
    return SystemNumerics.Vector2(this.M31, this.M32)
end

Matrix3x2.setTranslation = function (this, value)
    this.M31 = value.X
    this.M32 = value.Y
end

Matrix3x2.CreateTranslation = function (position, yPosition)
    if yPosition == nil then
        -- Vector2
        local result = new(Matrix3x2)

        result.M11 = 1.0
        result.M12 = 0.0
        result.M21 = 0.0
        result.M22 = 1.0

        result.M31 = position.X
        result.M32 = position.Y

        return result:__clone__()
    else
        -- singles
        local result = new(Matrix3x2)

        result.M11 = 1.0
        result.M12 = 0.0
        result.M21 = 0.0
        result.M22 = 1.0
  
        result.M31 = position
        result.M32 = yPosition
  
        return result:__clone__()
    end
end

Matrix3x2.CreateScale = function(val1, val2, val3)
    if val3 == nil then
        if val2 == nil then
            if val1.X == nil then
                -- CreateScale(Single)
                local result = new(Matrix3x2)

                result.M11 = val1
                result.M12 = 0.0
                result.M21 = 0.0
                result.M22 = val1
                result.M31 = 0.0
                result.M32 = 0.0
          
                return result:__clone__()
            else
                -- CreateScale(Vector2)
                local result = new(Matrix3x2)

                result.M11 = val1.X
                result.M12 = 0.0
                result.M21 = 0.0
                result.M22 = val1.Y
                result.M31 = 0.0
                result.M32 = 0.0

                return result:__clone__()
            end
        else
            if val2.X == nil then
                -- CreateScale(Single, Single)
                local result = new(Matrix3x2)

                result.M11 = val1
                result.M12 = 0.0
                result.M21 = 0.0
                result.M22 = val2
                result.M31 = 0.0
                result.M32 = 0.0

                return result:__clone__()
            else
                if val1.X == nil then
                    -- CreateScale(Single, Vector2)
                    local result = new(Matrix3x2)

                    local tx = val2.X * (1 - val1)
                    local ty = val2.Y * (1 - val1)

                    result.M11 = val1
                    result.M12 = 0.0
                    result.M21 = 0.0
                    result.M22 = val1
                    result.M31 = tx
                    result.M32 = ty

                    return result:__clone__()
                else
                    -- CreateScale(Vector2, Vector2)
                    local result = new(Matrix3x2)

                    local tx = val2.X * (1 - val1.X)
                    local ty = val2.Y * (1 - val1.Y)

                    result.M11 = val1.X
                    result.M12 = 0.0
                    result.M21 = 0.0
                    result.M22 = val1.Y
                    result.M31 = tx
                    result.M32 = ty

                    return result:__clone__()
                end
            end
        end
    else
        -- CreateScale(Single, Single, Vector2)
        local result = new(Matrix3x2)

        local tx = val3.X * (1 - val1)
        local ty = val3.Y * (1 - val2)

        result.M11 = val1
        result.M12 = 0.0
        result.M21 = 0.0
        result.M22 = val2
        result.M31 = tx
        result.M32 = ty

        return result:__clone__()
    end
end

Matrix3x2.CreateSkew = function (radiansX, radiansY, centerPoint)
    if centerPoint == nil then

        local result = new(Matrix3x2)

        local xTan = System.ToSingle(tan(radiansX))
        local yTan = System.ToSingle(tan(radiansY))

        result.M11 = 1.0
        result.M12 = yTan
        result.M21 = xTan
        result.M22 = 1.0
        result.M31 = 0.0
        result.M32 = 0.0

        return result:__clone__()
    else
        local result = new(Matrix3x2)

        local xTan = System.ToSingle(tan(radiansX))
        local yTan = System.ToSingle(tan(radiansY))

        local tx = - centerPoint.Y * xTan
        local ty = - centerPoint.X * yTan

        result.M11 = 1.0
        result.M12 = yTan
        result.M21 = xTan
        result.M22 = 1.0
        result.M31 = tx
        result.M32 = ty

        return result:__clone__()
    end
end

Matrix3x2.CreateRotation = function (radians, centerPoint)
    if centerPoint == nil then

        local result = new(Matrix3x2)

        radians = System.ToSingle(math.IEEERemainder(radians, 6.28318530717959 --[[Math.PI * 2]]))

        local c, s

        -- 0.1% of a degree

        if radians > - 1.745329E-05 --[[epsilon]] and radians < 1.745329E-05 --[[epsilon]] then
            -- Exact case for zero rotation.
            c = 1
            s = 0
        elseif radians > 1.57077887350062 --[[Math.PI / 2 - epsilon]] and radians < 1.57081378008917 --[[Math.PI / 2 + epsilon]] then
            -- Exact case for 90 degree rotation.
            c = 0
            s = 1
        elseif radians < -3.14157520029552 --[[-Math.PI + epsilon]] or radians > 3.14157520029552 --[[Math.PI - epsilon]] then
            -- Exact case for 180 degree rotation.
            c = - 1
            s = 0
        elseif radians > -1.57081378008917 --[[-Math.PI / 2 - epsilon]] and radians < -1.57077887350062 --[[-Math.PI / 2 + epsilon]] then
            -- Exact case for 270 degree rotation.
            c = 0
            s = - 1
        else
            -- Arbitrary rotation.
            c = System.ToSingle(cos(radians))
            s = System.ToSingle(sin(radians))
        end

        -- [  c  s ]
        -- [ -s  c ]
        -- [  0  0 ]
        result.M11 = c
        result.M12 = s
        result.M21 = - s
        result.M22 = c
        result.M31 = 0.0
        result.M32 = 0.0

        return result:__clone__()
    else
        local result = new(Matrix3x2)

        radians = System.ToSingle(math.IEEERemainder(radians, 6.28318530717959 --[[Math.PI * 2]]))
  
        local c, s
  
        -- 0.1% of a degree
  
        if radians > - 1.745329E-05 --[[epsilon]] and radians < 1.745329E-05 --[[epsilon]] then
          -- Exact case for zero rotation.
          c = 1
          s = 0
        elseif radians > 1.57077887350062 --[[Math.PI / 2 - epsilon]] and radians < 1.57081378008917 --[[Math.PI / 2 + epsilon]] then
          -- Exact case for 90 degree rotation.
          c = 0
          s = 1
        elseif radians < -3.14157520029552 --[[-Math.PI + epsilon]] or radians > 3.14157520029552 --[[Math.PI - epsilon]] then
          -- Exact case for 180 degree rotation.
          c = - 1
          s = 0
        elseif radians > -1.57081378008917 --[[-Math.PI / 2 - epsilon]] and radians < -1.57077887350062 --[[-Math.PI / 2 + epsilon]] then
          -- Exact case for 270 degree rotation.
          c = 0
          s = - 1
        else
          -- Arbitrary rotation.
          c = System.ToSingle(cos(radians))
          s = System.ToSingle(sin(radians))
        end
  
        local x = centerPoint.X * (1 - c) + centerPoint.Y * s
        local y = centerPoint.Y * (1 - c) - centerPoint.X * s
  
        -- [  c  s ]
        -- [ -s  c ]
        -- [  x  y ]
        result.M11 = c
        result.M12 = s
        result.M21 = - s
        result.M22 = c
        result.M31 = x
        result.M32 = y
  
        return result:__clone__()
    end
end

Matrix3x2.GetDeterminant = function (this)
    -- There isn't actually any such thing as a determinant for a non-square matrix,
    -- but this 3x2 type is really just an optimization of a 3x3 where we happen to
    -- know the rightmost column is always (0, 0, 1). So we expand to 3x3 format:
    --
    --  [ M11, M12, 0 ]
    --  [ M21, M22, 0 ]
    --  [ M31, M32, 1 ]
    --
    -- Sum the diagonal products:
    --  (M11 * M22 * 1) + (M12 * 0 * M31) + (0 * M21 * M32)
    --
    -- Subtract the opposite diagonal products:
    --  (M31 * M22 * 0) + (M32 * 0 * M11) + (1 * M21 * M12)
    --
    -- Collapse out the constants and oh look, this is just a 2x2 determinant!

    return (this.M11 * this.M22) - (this.M21 * this.M12)
end

Matrix3x2.Invert = function (matrix, result)
    local det = (matrix.M11 * matrix.M22) - (matrix.M21 * matrix.M12)

    if result == nil then
        result = new(Matrix3x2)
    end

    if abs(det) < 1.401298E-45 --[[Single.Epsilon]] then
      result = new(Matrix3x2, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN)
      return false, result
    end

    local invDet = 1.0 / det

    result.M11 = matrix.M22 * invDet
    result.M12 = - matrix.M12 * invDet
    result.M21 = - matrix.M21 * invDet
    result.M22 = matrix.M11 * invDet
    result.M31 = (matrix.M21 * matrix.M32 - matrix.M31 * matrix.M22) * invDet
    result.M32 = (matrix.M31 * matrix.M12 - matrix.M11 * matrix.M32) * invDet

    return true, result
end

Matrix3x2.Lerp = function (matrix1, matrix2, amount)
    local result = new(Matrix3x2)

    -- First row
    result.M11 = matrix1.M11 + (matrix2.M11 - matrix1.M11) * amount
    result.M12 = matrix1.M12 + (matrix2.M12 - matrix1.M12) * amount

    -- Second row
    result.M21 = matrix1.M21 + (matrix2.M21 - matrix1.M21) * amount
    result.M22 = matrix1.M22 + (matrix2.M22 - matrix1.M22) * amount

    -- Third row
    result.M31 = matrix1.M31 + (matrix2.M31 - matrix1.M31) * amount
    result.M32 = matrix1.M32 + (matrix2.M32 - matrix1.M32) * amount

    return result:__clone__()
end

Matrix3x2.Negate = function (value)
    local result = new(Matrix3x2)

    result.M11 = - value.M11
    result.M12 = - value.M12
    result.M21 = - value.M21
    result.M22 = - value.M22
    result.M31 = - value.M31
    result.M32 = - value.M32

    return result:__clone__()
end

Matrix3x2.Add = function (value1, value2)
    local result = new(Matrix3x2)

    result.M11 = value1.M11 + value2.M11
    result.M12 = value1.M12 + value2.M12
    result.M21 = value1.M21 + value2.M21
    result.M22 = value1.M22 + value2.M22
    result.M31 = value1.M31 + value2.M31
    result.M32 = value1.M32 + value2.M32

    return result:__clone__()
end

Matrix3x2.Subtract = function (value1, value2)
    local result = new(Matrix3x2)

    result.M11 = value1.M11 - value2.M11
    result.M12 = value1.M12 - value2.M12
    result.M21 = value1.M21 - value2.M21
    result.M22 = value1.M22 - value2.M22
    result.M31 = value1.M31 - value2.M31
    result.M32 = value1.M32 - value2.M32

    return result:__clone__()
end

Matrix3x2.Multiply = function (value1, value2)
    if value2.M11 == nil then
        -- scalar
        local result = new(Matrix3x2)

        result.M11 = value1.M11 * value2
        result.M12 = value1.M12 * value2
        result.M21 = value1.M21 * value2
        result.M22 = value1.M22 * value2
        result.M31 = value1.M31 * value2
        result.M32 = value1.M32 * value2

        return result:__clone__()
    else
        -- matrix
        local result = new(Matrix3x2)

        -- First row
        result.M11 = value1.M11 * value2.M11 + value1.M12 * value2.M21
        result.M12 = value1.M11 * value2.M12 + value1.M12 * value2.M22

        -- Second row
        result.M21 = value1.M21 * value2.M11 + value1.M22 * value2.M21
        result.M22 = value1.M21 * value2.M12 + value1.M22 * value2.M22

        -- Third row
        result.M31 = value1.M31 * value2.M11 + value1.M32 * value2.M21 + value2.M31
        result.M32 = value1.M31 * value2.M12 + value1.M32 * value2.M22 + value2.M32

        return result:__clone__()
    end
end

Matrix3x2.op_UnaryNegation = function (value)
    local m = new(Matrix3x2)

    m.M11 = - value.M11
    m.M12 = - value.M12
    m.M21 = - value.M21
    m.M22 = - value.M22
    m.M31 = - value.M31
    m.M32 = - value.M32

    return m:__clone__()
end

Matrix3x2.op_Addition = function (value1, value2)
    local m = new(Matrix3x2)

    m.M11 = value1.M11 + value2.M11
    m.M12 = value1.M12 + value2.M12
    m.M21 = value1.M21 + value2.M21
    m.M22 = value1.M22 + value2.M22
    m.M31 = value1.M31 + value2.M31
    m.M32 = value1.M32 + value2.M32

    return m:__clone__()
end

Matrix3x2.op_Subtraction = function (value1, value2)
    local m = new(Matrix3x2)

    m.M11 = value1.M11 - value2.M11
    m.M12 = value1.M12 - value2.M12
    m.M21 = value1.M21 - value2.M21
    m.M22 = value1.M22 - value2.M22
    m.M31 = value1.M31 - value2.M31
    m.M32 = value1.M32 - value2.M32

    return m:__clone__()
end

Matrix3x2.op_Multiply = function (value1, value2)
    if value2.M11 == nil then
        -- scalar
        local result = new(Matrix3x2)

        result.M11 = value1.M11 * value2
        result.M12 = value1.M12 * value2
        result.M21 = value1.M21 * value2
        result.M22 = value1.M22 * value2
        result.M31 = value1.M31 * value2
        result.M32 = value1.M32 * value2

        return result:__clone__()
    else
        -- matrix
        local result = new(Matrix3x2)

        -- First row
        result.M11 = value1.M11 * value2.M11 + value1.M12 * value2.M21
        result.M12 = value1.M11 * value2.M12 + value1.M12 * value2.M22

        -- Second row
        result.M21 = value1.M21 * value2.M11 + value1.M22 * value2.M21
        result.M22 = value1.M21 * value2.M12 + value1.M22 * value2.M22

        -- Third row
        result.M31 = value1.M31 * value2.M11 + value1.M32 * value2.M21 + value2.M31
        result.M32 = value1.M31 * value2.M12 + value1.M32 * value2.M22 + value2.M32

        return result:__clone__()
    end
end

Matrix3x2.op_Equality = function (value1, value2)
    return (value1.M11 == value2.M11 and value1.M22 == value2.M22 and value1.M12 == value2.M12 and value1.M21 == value2.M21 and value1.M31 == value2.M31 and value1.M32 == value2.M32)
end

Matrix3x2.op_Inequality = function (value1, value2)
    return (value1.M11 ~= value2.M11 or value1.M12 ~= value2.M12 or value1.M21 ~= value2.M21 or value1.M22 ~= value2.M22 or value1.M31 ~= value2.M31 or value1.M32 ~= value2.M32)
end

Matrix3x2.Equals = function (this, other)
    if System.is(other, Matrix3x2) then
        return (this.M11 == other.M11 and this.M22 == other.M22 and this.M12 == other.M12 and this.M21 == other.M21 and this.M31 == other.M31 and this.M32 == other.M32)
    end
    return false
end

Matrix3x2.ToString = function (this)
    local sb = System.StringBuilder()
    sb:Append("{ ")
    sb:Append("{")
    sb:Append("M11: ")
    sb:Append(this.M11:ToString())
    sb:Append(" M12: ")
    sb:Append(this.M12:ToString())
    sb:Append("} ")
    sb:Append("{")
    sb:Append("M21: ")
    sb:Append(this.M21:ToString())
    sb:Append(" M22: ")
    sb:Append(this.M22:ToString())
    sb:Append("} ")
    sb:Append("{")
    sb:Append("M31: ")
    sb:Append(this.M31:ToString())
    sb:Append(" M32: ")
    sb:Append(this.M32:ToString())
    sb:Append("} ")
    sb:Append("}")
    return sb:ToString()
end

Matrix3x2.GetHashCode = function (this)
    return this.M11:GetHashCode() + this.M12:GetHashCode() + this.M21:GetHashCode() + this.M22:GetHashCode() + this.M31:GetHashCode() + this.M32:GetHashCode()
end

System.defStc("System.Numerics.Matrix3x2", Matrix3x2)
end

-- CoreSystemLib: Numerics/Matrix4x4.lua
do
local System = System
local SystemNumerics = System.Numerics

local sqrt = math.sqrt
local abs = math.abs
local tan = math.tan
local cos = math.cos
local sin = math.sin

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1

local new = function (cls, ...)
    local this = setmetatable({}, cls)
    return this, cls.__ctor__(this, ...)
end

local Matrix4x4 = {}

Matrix4x4.__ctor__ = function (this, m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44)
    if m11 == nil then
        this.M11 = 0
        this.M12 = 0
        this.M13 = 0
        this.M14 = 0

        this.M21 = 0
        this.M22 = 0
        this.M23 = 0
        this.M24 = 0

        this.M31 = 0
        this.M32 = 0
        this.M33 = 0
        this.M34 = 0

        this.M41 = 0
        this.M42 = 0
        this.M43 = 0
        this.M44 = 0
    elseif m11.M11 == nil then
        -- from singles
        this.M11 = m11 or 0
        this.M12 = m12 or 0
        this.M13 = m13 or 0
        this.M14 = m14 or 0

        this.M21 = m21 or 0
        this.M22 = m22 or 0
        this.M23 = m23 or 0
        this.M24 = m24 or 0

        this.M31 = m31 or 0
        this.M32 = m32 or 0
        this.M33 = m33 or 0
        this.M34 = m34 or 0

        this.M41 = m41 or 0
        this.M42 = m42 or 0
        this.M43 = m43 or 0
        this.M44 = m44 or 0
    else
        -- from matrix
        this.M11 = m11.M11
        this.M12 = m11.M12
        this.M13 = 0
        this.M14 = 0
        this.M21 = m11.M21
        this.M22 = m11.M22
        this.M23 = 0
        this.M24 = 0
        this.M31 = 0
        this.M32 = 0
        this.M33 = 1
        this.M34 = 0
        this.M41 = m11.M31
        this.M42 = m11.M32
        this.M43 = 0
        this.M44 = 1
    end 
    local mt = getmetatable(this)
    mt.__unm = Matrix4x4.op_UnaryNegation
    setmetatable(this, mt)   
  end

Matrix4x4.base = function (_, T)
    return { IComparable, IComparable_1(T), IEquatable_1(T) }
end

Matrix4x4.getIdentity = function ()
    return new(Matrix4x4, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
end

Matrix4x4.getIsIdentity = function (this)
    return this.M11 == 1 and this.M22 == 1 and this.M33 == 1 and this.M44 == 1 and this.M12 == 0 and this.M13 == 0 and this.M14 == 0 and this.M21 == 0 and this.M23 == 0 and this.M24 == 0 and this.M31 == 0 and this.M32 == 0 and this.M34 == 0 and this.M41 == 0 and this.M42 == 0 and this.M43 == 0
end

Matrix4x4.getTranslation = function (this)
    return SystemNumerics.Vector3(this.M41, this.M42, this.M43)
end
  
Matrix4x4.setTranslation = function (this, value)
    this.M41 = value.X
    this.M42 = value.Y
    this.M43 = value.Z
end

Matrix4x4.CreateBillboard = function (objectPosition, cameraPosition, cameraUpVector, cameraForwardVector)

    local zaxis = SystemNumerics.Vector3(objectPosition.X - cameraPosition.X, objectPosition.Y - cameraPosition.Y, objectPosition.Z - cameraPosition.Z)

    local norm = zaxis:LengthSquared()

    if norm < 0.0001 --[[epsilon]] then
      zaxis = - cameraForwardVector
    else
      zaxis = SystemNumerics.Vector3.Multiply(zaxis, 1.0 / System.ToSingle(sqrt(norm)))
    end

    local xaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.Cross(cameraUpVector, zaxis))

    local yaxis = SystemNumerics.Vector3.Cross(zaxis, xaxis)

    local result = new(Matrix4x4)

    result.M11 = xaxis.X
    result.M12 = xaxis.Y
    result.M13 = xaxis.Z
    result.M14 = 0.0
    result.M21 = yaxis.X
    result.M22 = yaxis.Y
    result.M23 = yaxis.Z
    result.M24 = 0.0
    result.M31 = zaxis.X
    result.M32 = zaxis.Y
    result.M33 = zaxis.Z
    result.M34 = 0.0

    result.M41 = objectPosition.X
    result.M42 = objectPosition.Y
    result.M43 = objectPosition.Z
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateConstrainedBillboard = function (objectPosition, cameraPosition, rotateAxis, cameraForwardVector, objectForwardVector)
    -- 0.1 degrees

    -- Treat the case when object and camera positions are too close.
    local faceDir = SystemNumerics.Vector3(objectPosition.X - cameraPosition.X, objectPosition.Y - cameraPosition.Y, objectPosition.Z - cameraPosition.Z)

    local norm = faceDir:LengthSquared()

    if norm < 0.0001 --[[epsilon]] then
      faceDir = - cameraForwardVector
    else
      faceDir = SystemNumerics.Vector3.Multiply(faceDir, (1.0 / System.ToSingle(sqrt(norm))))
    end

    local yaxis = rotateAxis:__clone__()
    local xaxis
    local zaxis

    -- Treat the case when angle between faceDir and rotateAxis is too close to 0.
    local dot = SystemNumerics.Vector3.Dot(rotateAxis, faceDir)

    if abs(dot) > 0.9982547 --[[minAngle]] then
      zaxis = objectForwardVector:__clone__()

      -- Make sure passed values are useful for compute.
      dot = SystemNumerics.Vector3.Dot(rotateAxis, zaxis)

      if abs(dot) > 0.9982547 --[[minAngle]] then
        zaxis = (abs(rotateAxis.Z) > 0.9982547 --[[minAngle]]) and SystemNumerics.Vector3(1, 0, 0) or SystemNumerics.Vector3(0, 0, - 1)
      end

      xaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.Cross(rotateAxis, zaxis))
      zaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.Cross(xaxis, rotateAxis))
    else
      xaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.Cross(rotateAxis, faceDir))
      zaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.Cross(xaxis, yaxis))
    end

    local result = new(Matrix4x4)

    result.M11 = xaxis.X
    result.M12 = xaxis.Y
    result.M13 = xaxis.Z
    result.M14 = 0.0
    result.M21 = yaxis.X
    result.M22 = yaxis.Y
    result.M23 = yaxis.Z
    result.M24 = 0.0
    result.M31 = zaxis.X
    result.M32 = zaxis.Y
    result.M33 = zaxis.Z
    result.M34 = 0.0

    result.M41 = objectPosition.X
    result.M42 = objectPosition.Y
    result.M43 = objectPosition.Z
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateTranslation = function (position, yPosition, zPosition)
    local result = new(Matrix4x4)

    result.M11 = 1.0
    result.M12 = 0.0
    result.M13 = 0.0
    result.M14 = 0.0
    result.M21 = 0.0
    result.M22 = 1.0
    result.M23 = 0.0
    result.M24 = 0.0
    result.M31 = 0.0
    result.M32 = 0.0
    result.M33 = 1.0
    result.M34 = 0.0

    if yPosition ~= nil then
        position = SystemNumerics.Vector3(position, yPosition, zPosition)
    end

    result.M41 = position.X
    result.M42 = position.Y
    result.M43 = position.Z
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateScale = function(val1, val2, val3, val4)
    if val4 == nil then
        if val3 == nil then
            if val2 == nil then
                if val1.X == nil then
                    -- CreateScale(Single)
                    local result = new(Matrix4x4)

                    result.M11 = val1
                    result.M12 = 0.0
                    result.M13 = 0.0
                    result.M14 = 0.0
                    result.M21 = 0.0
                    result.M22 = val1
                    result.M23 = 0.0
                    result.M24 = 0.0
                    result.M31 = 0.0
                    result.M32 = 0.0
                    result.M33 = val1
                    result.M34 = 0.0
                    result.M41 = 0.0
                    result.M42 = 0.0
                    result.M43 = 0.0
                    result.M44 = 1.0

                    return result:__clone__()
                else
                    -- CreateScale(Vector3)
                    local result = new(Matrix4x4)

                    result.M11 = val1.X
                    result.M12 = 0.0
                    result.M13 = 0.0
                    result.M14 = 0.0
                    result.M21 = 0.0
                    result.M22 = val1.Y
                    result.M23 = 0.0
                    result.M24 = 0.0
                    result.M31 = 0.0
                    result.M32 = 0.0
                    result.M33 = val1.Z
                    result.M34 = 0.0
                    result.M41 = 0.0
                    result.M42 = 0.0
                    result.M43 = 0.0
                    result.M44 = 1.0

                    return result:__clone__()
                end
            else
                if val1.X == nil then
                    -- CreateScale(Single, Vector3)
                    local result = new(Matrix4x4)

                    local tx = val2.X * (1 - val1)
                    local ty = val2.Y * (1 - val1)
                    local tz = val2.Z * (1 - val1)

                    result.M11 = val1
                    result.M12 = 0.0
                    result.M13 = 0.0
                    result.M14 = 0.0
                    result.M21 = 0.0
                    result.M22 = val1
                    result.M23 = 0.0
                    result.M24 = 0.0
                    result.M31 = 0.0
                    result.M32 = 0.0
                    result.M33 = val1
                    result.M34 = 0.0
                    result.M41 = tx
                    result.M42 = ty
                    result.M43 = tz
                    result.M44 = 1.0

                    return result:__clone__()
                else
                    -- CreateScale(Vector3, Vector3)
                    local result = new(Matrix4x4)

                    local tx = val2.X * (1 - val1.X)
                    local ty = val2.Y * (1 - val1.Y)
                    local tz = val2.Z * (1 - val1.Z)

                    result.M11 = val1.X
                    result.M12 = 0.0
                    result.M13 = 0.0
                    result.M14 = 0.0
                    result.M21 = 0.0
                    result.M22 = val1.Y
                    result.M23 = 0.0
                    result.M24 = 0.0
                    result.M31 = 0.0
                    result.M32 = 0.0
                    result.M33 = val1.Z
                    result.M34 = 0.0
                    result.M41 = tx
                    result.M42 = ty
                    result.M43 = tz
                    result.M44 = 1.0

                    return result:__clone__()
                end
            end
        else
            -- CreateScale(Single, Single, Single)
            local result = new(Matrix4x4)

            result.M11 = val1
            result.M12 = 0.0
            result.M13 = 0.0
            result.M14 = 0.0
            result.M21 = 0.0
            result.M22 = val2
            result.M23 = 0.0
            result.M24 = 0.0
            result.M31 = 0.0
            result.M32 = 0.0
            result.M33 = val3
            result.M34 = 0.0
            result.M41 = 0.0
            result.M42 = 0.0
            result.M43 = 0.0
            result.M44 = 1.0

            return result:__clone__()
        end
    else
        -- CreateScale(Single, Single, Single, Vector3)
        local result = new(Matrix4x4)

        local tx = val4.X * (1 - val1)
        local ty = val4.Y * (1 - val2)
        local tz = val4.Z * (1 - val3)

        result.M11 = val1
        result.M12 = 0.0
        result.M13 = 0.0
        result.M14 = 0.0
        result.M21 = 0.0
        result.M22 = val2
        result.M23 = 0.0
        result.M24 = 0.0
        result.M31 = 0.0
        result.M32 = 0.0
        result.M33 = val3
        result.M34 = 0.0
        result.M41 = tx
        result.M42 = ty
        result.M43 = tz
        result.M44 = 1.0

        return result:__clone__()
    end
end

Matrix4x4.CreateRotationX = function (radians, centerPoint)

    if centerPoint == nil then
        local result = new(Matrix4x4)

        local c = System.ToSingle(cos(radians))
        local s = System.ToSingle(sin(radians))
    
        -- [  1  0  0  0 ]
        -- [  0  c  s  0 ]
        -- [  0 -s  c  0 ]
        -- [  0  0  0  1 ]
        result.M11 = 1.0
        result.M12 = 0.0
        result.M13 = 0.0
        result.M14 = 0.0
        result.M21 = 0.0
        result.M22 = c
        result.M23 = s
        result.M24 = 0.0
        result.M31 = 0.0
        result.M32 = - s
        result.M33 = c
        result.M34 = 0.0
        result.M41 = 0.0
        result.M42 = 0.0
        result.M43 = 0.0
        result.M44 = 1.0
    
        return result:__clone__()
    else
        local result = new(Matrix4x4)

        local c = System.ToSingle(cos(radians))
        local s = System.ToSingle(sin(radians))
  
        local y = centerPoint.Y * (1 - c) + centerPoint.Z * s
        local z = centerPoint.Z * (1 - c) - centerPoint.Y * s
  
        -- [  1  0  0  0 ]
        -- [  0  c  s  0 ]
        -- [  0 -s  c  0 ]
        -- [  0  y  z  1 ]
        result.M11 = 1.0
        result.M12 = 0.0
        result.M13 = 0.0
        result.M14 = 0.0
        result.M21 = 0.0
        result.M22 = c
        result.M23 = s
        result.M24 = 0.0
        result.M31 = 0.0
        result.M32 = - s
        result.M33 = c
        result.M34 = 0.0
        result.M41 = 0.0
        result.M42 = y
        result.M43 = z
        result.M44 = 1.0
  
        return result:__clone__()
    end    
end

Matrix4x4.CreateRotationY = function(radians, centerPoint)
    if centerPoint == nil then
        local result = new(Matrix4x4)

        local c = System.ToSingle(cos(radians))
        local s = System.ToSingle(sin(radians))
  
        -- [  c  0 -s  0 ]
        -- [  0  1  0  0 ]
        -- [  s  0  c  0 ]
        -- [  0  0  0  1 ]
        result.M11 = c
        result.M12 = 0.0
        result.M13 = - s
        result.M14 = 0.0
        result.M21 = 0.0
        result.M22 = 1.0
        result.M23 = 0.0
        result.M24 = 0.0
        result.M31 = s
        result.M32 = 0.0
        result.M33 = c
        result.M34 = 0.0
        result.M41 = 0.0
        result.M42 = 0.0
        result.M43 = 0.0
        result.M44 = 1.0
  
        return result:__clone__()
    else
        local result = new(Matrix4x4)

        local c = System.ToSingle(cos(radians))
        local s = System.ToSingle(sin(radians))

        local x = centerPoint.X * (1 - c) - centerPoint.Z * s
        local z = centerPoint.Z * (1 - c) + centerPoint.X * s

         -- [  c  0 -s  0 ]
         -- [  0  1  0  0 ]
         -- [  s  0  c  0 ]
         -- [  x  0  z  1 ]
        result.M11 = c
        result.M12 = 0.0
        result.M13 = - s
        result.M14 = 0.0
        result.M21 = 0.0
        result.M22 = 1.0
        result.M23 = 0.0
        result.M24 = 0.0
        result.M31 = s
        result.M32 = 0.0
        result.M33 = c
        result.M34 = 0.0
        result.M41 = x
        result.M42 = 0.0
        result.M43 = z
        result.M44 = 1.0

        return result:__clone__()
    end
end

Matrix4x4.CreateRotationZ = function(radians, centerPoint)
    if centerPoint == nil then
        local result = new(Matrix4x4)

        local c = System.ToSingle(cos(radians))
        local s = System.ToSingle(sin(radians))
  
        -- [  c  s  0  0 ]
        -- [ -s  c  0  0 ]
        -- [  0  0  1  0 ]
        -- [  0  0  0  1 ]
        result.M11 = c
        result.M12 = s
        result.M13 = 0.0
        result.M14 = 0.0
        result.M21 = - s
        result.M22 = c
        result.M23 = 0.0
        result.M24 = 0.0
        result.M31 = 0.0
        result.M32 = 0.0
        result.M33 = 1.0
        result.M34 = 0.0
        result.M41 = 0.0
        result.M42 = 0.0
        result.M43 = 0.0
        result.M44 = 1.0
  
        return result:__clone__()
    else
        local result = new(Matrix4x4)

        local c = System.ToSingle(cos(radians))
        local s = System.ToSingle(sin(radians))
  
        local x = centerPoint.X * (1 - c) + centerPoint.Y * s
        local y = centerPoint.Y * (1 - c) - centerPoint.X * s
  
        -- [  c  s  0  0 ]
        -- [ -s  c  0  0 ]
        -- [  0  0  1  0 ]
        -- [  x  y  0  1 ]
        result.M11 = c
        result.M12 = s
        result.M13 = 0.0
        result.M14 = 0.0
        result.M21 = - s
        result.M22 = c
        result.M23 = 0.0
        result.M24 = 0.0
        result.M31 = 0.0
        result.M32 = 0.0
        result.M33 = 1.0
        result.M34 = 0.0
        result.M41 = x
        result.M42 = y
        result.M43 = 0.0
        result.M44 = 1.0
  
        return result:__clone__()
    end
end

Matrix4x4.CreateFromAxisAngle = function (axis, angle)
    -- a: angle
    -- x, y, z: unit vector for axis.
    --
    -- Rotation matrix M can compute by using below equation.
    --
    --        T               T
    --  M = uu + (cos a)( I-uu ) + (sin a)S
    --
    -- Where:
    --
    --  u = ( x, y, z )
    --
    --      [  0 -z  y ]
    --  S = [  z  0 -x ]
    --      [ -y  x  0 ]
    --
    --      [ 1 0 0 ]
    --  I = [ 0 1 0 ]
    --      [ 0 0 1 ]
    --
    --
    --     [  xx+cosa*(1-xx)   yx-cosa*yx-sina*z zx-cosa*xz+sina*y ]
    -- M = [ xy-cosa*yx+sina*z    yy+cosa(1-yy)  yz-cosa*yz-sina*x ]
    --     [ zx-cosa*zx-sina*y zy-cosa*zy+sina*x   zz+cosa*(1-zz)  ]
    --
    local x = axis.X local y = axis.Y local z = axis.Z
    local sa = System.ToSingle(sin(angle)) local ca = System.ToSingle(cos(angle))
    local xx = x * x local yy = y * y local zz = z * z
    local xy = x * y local xz = x * z local yz = y * z

    local result = new(Matrix4x4)

    result.M11 = xx + ca * (1.0 - xx)
    result.M12 = xy - ca * xy + sa * z
    result.M13 = xz - ca * xz - sa * y
    result.M14 = 0.0
    result.M21 = xy - ca * xy - sa * z
    result.M22 = yy + ca * (1.0 - yy)
    result.M23 = yz - ca * yz + sa * x
    result.M24 = 0.0
    result.M31 = xz - ca * xz + sa * y
    result.M32 = yz - ca * yz - sa * x
    result.M33 = zz + ca * (1.0 - zz)
    result.M34 = 0.0
    result.M41 = 0.0
    result.M42 = 0.0
    result.M43 = 0.0
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreatePerspectiveFieldOfView = function (fieldOfView, aspectRatio, nearPlaneDistance, farPlaneDistance)
    if fieldOfView <= 0.0 or fieldOfView >= 3.14159265358979 --[[Math.PI]] then
      System.throw(System.ArgumentOutOfRangeException("fieldOfView"))
    end

    if nearPlaneDistance <= 0.0 then
      System.throw(System.ArgumentOutOfRangeException("nearPlaneDistance"))
    end

    if farPlaneDistance <= 0.0 then
      System.throw(System.ArgumentOutOfRangeException("farPlaneDistance"))
    end

    if nearPlaneDistance >= farPlaneDistance then
      System.throw(System.ArgumentOutOfRangeException("nearPlaneDistance"))
    end

    local yScale = 1.0 / System.ToSingle(tan(fieldOfView * 0.5))
    local xScale = yScale / aspectRatio

    local result = new(Matrix4x4)

    result.M11 = xScale
    result.M14 = 0.0 result.M13 = result.M14 result.M12 = result.M13

    result.M22 = yScale
    result.M24 = 0.0 result.M23 = result.M24 result.M21 = result.M23

    result.M32 = 0.0 result.M31 = result.M32
    result.M33 = farPlaneDistance / (nearPlaneDistance - farPlaneDistance)
    result.M34 = - 1.0

    result.M44 = 0.0 result.M42 = result.M44 result.M41 = result.M42
    result.M43 = nearPlaneDistance * farPlaneDistance / (nearPlaneDistance - farPlaneDistance)

    return result:__clone__()
end

Matrix4x4.CreatePerspective = function (width, height, nearPlaneDistance, farPlaneDistance)
    if nearPlaneDistance <= 0.0 then
      System.throw(System.ArgumentOutOfRangeException("nearPlaneDistance"))
    end
    if farPlaneDistance <= 0.0 then
      System.throw(System.ArgumentOutOfRangeException("farPlaneDistance"))
    end
    if nearPlaneDistance >= farPlaneDistance then
      System.throw(System.ArgumentOutOfRangeException("nearPlaneDistance"))
    end
    local result = new(Matrix4x4)

    result.M11 = 2.0 * nearPlaneDistance / width
    result.M14 = 0.0 result.M13 = result.M14 result.M12 = result.M13

    result.M22 = 2.0 * nearPlaneDistance / height
    result.M24 = 0.0 result.M23 = result.M24 result.M21 = result.M23

    result.M33 = farPlaneDistance / (nearPlaneDistance - farPlaneDistance)
    result.M32 = 0.0 result.M31 = result.M32
    result.M34 = - 1.0

    result.M44 = 0.0 result.M42 = result.M44 result.M41 = result.M42
    result.M43 = nearPlaneDistance * farPlaneDistance / (nearPlaneDistance - farPlaneDistance)

    return result:__clone__()
end

Matrix4x4.CreatePerspectiveOffCenter = function (left, right, bottom, top, nearPlaneDistance, farPlaneDistance)
    if nearPlaneDistance <= 0.0 then
      System.throw(System.ArgumentOutOfRangeException("nearPlaneDistance"))
    end

    if farPlaneDistance <= 0.0 then
      System.throw(System.ArgumentOutOfRangeException("farPlaneDistance"))
    end

    if nearPlaneDistance >= farPlaneDistance then
      System.throw(System.ArgumentOutOfRangeException("nearPlaneDistance"))
    end

    local result = new(Matrix4x4)

    result.M11 = 2.0 * nearPlaneDistance / (right - left)
    result.M14 = 0.0 result.M13 = result.M14 result.M12 = result.M13

    result.M22 = 2.0 * nearPlaneDistance / (top - bottom)
    result.M24 = 0.0 result.M23 = result.M24 result.M21 = result.M23

    result.M31 = (left + right) / (right - left)
    result.M32 = (top + bottom) / (top - bottom)
    result.M33 = farPlaneDistance / (nearPlaneDistance - farPlaneDistance)
    result.M34 = - 1.0

    result.M43 = nearPlaneDistance * farPlaneDistance / (nearPlaneDistance - farPlaneDistance)
    result.M44 = 0.0 result.M42 = result.M44 result.M41 = result.M42

    return result:__clone__()
end

Matrix4x4.CreateOrthographic = function (width, height, zNearPlane, zFarPlane)
    local result = new(Matrix4x4)

    result.M11 = 2.0 / width
    result.M14 = 0.0 result.M13 = result.M14 result.M12 = result.M13

    result.M22 = 2.0 / height
    result.M24 = 0.0 result.M23 = result.M24 result.M21 = result.M23

    result.M33 = 1.0 / (zNearPlane - zFarPlane)
    result.M34 = 0.0 result.M32 = result.M34 result.M31 = result.M32

    result.M42 = 0.0 result.M41 = result.M42
    result.M43 = zNearPlane / (zNearPlane - zFarPlane)
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateOrthographicOffCenter = function (left, right, bottom, top, zNearPlane, zFarPlane)
    local result = new(Matrix4x4)

    result.M11 = 2.0 / (right - left)
    result.M14 = 0.0 result.M13 = result.M14 result.M12 = result.M13

    result.M22 = 2.0 / (top - bottom)
    result.M24 = 0.0 result.M23 = result.M24 result.M21 = result.M23

    result.M33 = 1.0 / (zNearPlane - zFarPlane)
    result.M34 = 0.0 result.M32 = result.M34 result.M31 = result.M32

    result.M41 = (left + right) / (left - right)
    result.M42 = (top + bottom) / (bottom - top)
    result.M43 = zNearPlane / (zNearPlane - zFarPlane)
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateLookAt = function (cameraPosition, cameraTarget, cameraUpVector)
    local zaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.op_Subtraction(cameraPosition, cameraTarget))
    local xaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.Cross(cameraUpVector, zaxis))
    local yaxis = SystemNumerics.Vector3.Cross(zaxis, xaxis)

    local result = new(Matrix4x4)

    result.M11 = xaxis.X
    result.M12 = yaxis.X
    result.M13 = zaxis.X
    result.M14 = 0.0
    result.M21 = xaxis.Y
    result.M22 = yaxis.Y
    result.M23 = zaxis.Y
    result.M24 = 0.0
    result.M31 = xaxis.Z
    result.M32 = yaxis.Z
    result.M33 = zaxis.Z
    result.M34 = 0.0
    result.M41 = - SystemNumerics.Vector3.Dot(xaxis, cameraPosition)
    result.M42 = - SystemNumerics.Vector3.Dot(yaxis, cameraPosition)
    result.M43 = - SystemNumerics.Vector3.Dot(zaxis, cameraPosition)
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateWorld = function (position, forward, up)
    local zaxis = SystemNumerics.Vector3.Normalize(- forward)
    local xaxis = SystemNumerics.Vector3.Normalize(SystemNumerics.Vector3.Cross(up, zaxis))
    local yaxis = SystemNumerics.Vector3.Cross(zaxis, xaxis)

    local result = new(Matrix4x4)

    result.M11 = xaxis.X
    result.M12 = xaxis.Y
    result.M13 = xaxis.Z
    result.M14 = 0.0
    result.M21 = yaxis.X
    result.M22 = yaxis.Y
    result.M23 = yaxis.Z
    result.M24 = 0.0
    result.M31 = zaxis.X
    result.M32 = zaxis.Y
    result.M33 = zaxis.Z
    result.M34 = 0.0
    result.M41 = position.X
    result.M42 = position.Y
    result.M43 = position.Z
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateFromQuaternion = function (quaternion)
    local result = new(Matrix4x4)

    local xx = quaternion.X * quaternion.X
    local yy = quaternion.Y * quaternion.Y
    local zz = quaternion.Z * quaternion.Z

    local xy = quaternion.X * quaternion.Y
    local wz = quaternion.Z * quaternion.W
    local xz = quaternion.Z * quaternion.X
    local wy = quaternion.Y * quaternion.W
    local yz = quaternion.Y * quaternion.Z
    local wx = quaternion.X * quaternion.W

    result.M11 = 1.0 - 2.0 * (yy + zz)
    result.M12 = 2.0 * (xy + wz)
    result.M13 = 2.0 * (xz - wy)
    result.M14 = 0.0
    result.M21 = 2.0 * (xy - wz)
    result.M22 = 1.0 - 2.0 * (zz + xx)
    result.M23 = 2.0 * (yz + wx)
    result.M24 = 0.0
    result.M31 = 2.0 * (xz + wy)
    result.M32 = 2.0 * (yz - wx)
    result.M33 = 1.0 - 2.0 * (yy + xx)
    result.M34 = 0.0
    result.M41 = 0.0
    result.M42 = 0.0
    result.M43 = 0.0
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.CreateFromYawPitchRoll = function (yaw, pitch, roll)
    local q = SystemNumerics.Quaternion.CreateFromYawPitchRoll(yaw, pitch, roll)

    return Matrix4x4.CreateFromQuaternion(q:__clone__())
end

Matrix4x4.CreateShadow = function (lightDirection, plane)
    local p = SystemNumerics.Plane.Normalize(plane)

    local dot = p.Normal.X * lightDirection.X + p.Normal.Y * lightDirection.Y + p.Normal.Z * lightDirection.Z
    local a = - p.Normal.X
    local b = - p.Normal.Y
    local c = - p.Normal.Z
    local d = - p.D

    local result = new(Matrix4x4)

    result.M11 = a * lightDirection.X + dot
    result.M21 = b * lightDirection.X
    result.M31 = c * lightDirection.X
    result.M41 = d * lightDirection.X

    result.M12 = a * lightDirection.Y
    result.M22 = b * lightDirection.Y + dot
    result.M32 = c * lightDirection.Y
    result.M42 = d * lightDirection.Y

    result.M13 = a * lightDirection.Z
    result.M23 = b * lightDirection.Z
    result.M33 = c * lightDirection.Z + dot
    result.M43 = d * lightDirection.Z

    result.M14 = 0.0
    result.M24 = 0.0
    result.M34 = 0.0
    result.M44 = dot

    return result:__clone__()
end

Matrix4x4.CreateReflection = function (value)
    value = SystemNumerics.Plane.Normalize(value)

    local a = value.Normal.X
    local b = value.Normal.Y
    local c = value.Normal.Z

    local fa = - 2.0 * a
    local fb = - 2.0 * b
    local fc = - 2.0 * c

    local result = new(Matrix4x4)

    result.M11 = fa * a + 1.0
    result.M12 = fb * a
    result.M13 = fc * a
    result.M14 = 0.0

    result.M21 = fa * b
    result.M22 = fb * b + 1.0
    result.M23 = fc * b
    result.M24 = 0.0

    result.M31 = fa * c
    result.M32 = fb * c
    result.M33 = fc * c + 1.0
    result.M34 = 0.0

    result.M41 = fa * value.D
    result.M42 = fb * value.D
    result.M43 = fc * value.D
    result.M44 = 1.0

    return result:__clone__()
end

Matrix4x4.GetDeterminant = function (this)
    -- | a b c d |     | f g h |     | e g h |     | e f h |     | e f g |
    -- | e f g h | = a | j k l | - b | i k l | + c | i j l | - d | i j k |
    -- | i j k l |     | n o p |     | m o p |     | m n p |     | m n o |
    -- | m n o p |
    --
    --   | f g h |
    -- a | j k l | = a ( f ( kp - lo ) - g ( jp - ln ) + h ( jo - kn ) )
    --   | n o p |
    --
    --   | e g h |     
    -- b | i k l | = b ( e ( kp - lo ) - g ( ip - lm ) + h ( io - km ) )
    --   | m o p |     
    --
    --   | e f h |
    -- c | i j l | = c ( e ( jp - ln ) - f ( ip - lm ) + h ( in - jm ) )
    --   | m n p |
    --
    --   | e f g |
    -- d | i j k | = d ( e ( jo - kn ) - f ( io - km ) + g ( in - jm ) )
    --   | m n o |
    --
    -- Cost of operation
    -- 17 adds and 28 muls.
    --
    -- add: 6 + 8 + 3 = 17
    -- mul: 12 + 16 = 28

    local a = this.M11 local b = this.M12 local c = this.M13 local d = this.M14
    local e = this.M21 local f = this.M22 local g = this.M23 local h = this.M24
    local i = this.M31 local j = this.M32 local k = this.M33 local l = this.M34
    local m = this.M41 local n = this.M42 local o = this.M43 local p = this.M44

    local kp_lo = k * p - l * o
    local jp_ln = j * p - l * n
    local jo_kn = j * o - k * n
    local ip_lm = i * p - l * m
    local io_km = i * o - k * m
    local in_jm = i * n - j * m

    return a * (f * kp_lo - g * jp_ln + h * jo_kn) - b * (e * kp_lo - g * ip_lm + h * io_km) + c * (e * jp_ln - f * ip_lm + h * in_jm) - d * (e * jo_kn - f * io_km + g * in_jm)
end

Matrix4x4.Invert = function (matrix, result)
    --                                       -1
    -- If you have matrix M, inverse Matrix M   can compute
    --
    --     -1       1      
    --    M   = --------- A
    --            det(M)
    --
    -- A is adjugate (adjoint) of M, where,
    --
    --      T
    -- A = C
    --
    -- C is Cofactor matrix of M, where,
    --           i + j
    -- C   = (-1)      * det(M  )
    --  ij                    ij
    --
    --     [ a b c d ]
    -- M = [ e f g h ]
    --     [ i j k l ]
    --     [ m n o p ]
    --
    -- First Row
    --           2 | f g h |
    -- C   = (-1)  | j k l | = + ( f ( kp - lo ) - g ( jp - ln ) + h ( jo - kn ) )
    --  11         | n o p |
    --
    --           3 | e g h |
    -- C   = (-1)  | i k l | = - ( e ( kp - lo ) - g ( ip - lm ) + h ( io - km ) )
    --  12         | m o p |
    --
    --           4 | e f h |
    -- C   = (-1)  | i j l | = + ( e ( jp - ln ) - f ( ip - lm ) + h ( in - jm ) )
    --  13         | m n p |
    --
    --           5 | e f g |
    -- C   = (-1)  | i j k | = - ( e ( jo - kn ) - f ( io - km ) + g ( in - jm ) )
    --  14         | m n o |
    --
    -- Second Row
    --           3 | b c d |
    -- C   = (-1)  | j k l | = - ( b ( kp - lo ) - c ( jp - ln ) + d ( jo - kn ) )
    --  21         | n o p |
    --
    --           4 | a c d |
    -- C   = (-1)  | i k l | = + ( a ( kp - lo ) - c ( ip - lm ) + d ( io - km ) )
    --  22         | m o p |
    --
    --           5 | a b d |
    -- C   = (-1)  | i j l | = - ( a ( jp - ln ) - b ( ip - lm ) + d ( in - jm ) )
    --  23         | m n p |
    --
    --           6 | a b c |
    -- C   = (-1)  | i j k | = + ( a ( jo - kn ) - b ( io - km ) + c ( in - jm ) )
    --  24         | m n o |
    --
    -- Third Row
    --           4 | b c d |
    -- C   = (-1)  | f g h | = + ( b ( gp - ho ) - c ( fp - hn ) + d ( fo - gn ) )
    --  31         | n o p |
    --
    --           5 | a c d |
    -- C   = (-1)  | e g h | = - ( a ( gp - ho ) - c ( ep - hm ) + d ( eo - gm ) )
    --  32         | m o p |
    --
    --           6 | a b d |
    -- C   = (-1)  | e f h | = + ( a ( fp - hn ) - b ( ep - hm ) + d ( en - fm ) )
    --  33         | m n p |
    --
    --           7 | a b c |
    -- C   = (-1)  | e f g | = - ( a ( fo - gn ) - b ( eo - gm ) + c ( en - fm ) )
    --  34         | m n o |
    --
    -- Fourth Row
    --           5 | b c d |
    -- C   = (-1)  | f g h | = - ( b ( gl - hk ) - c ( fl - hj ) + d ( fk - gj ) )
    --  41         | j k l |
    --
    --           6 | a c d |
    -- C   = (-1)  | e g h | = + ( a ( gl - hk ) - c ( el - hi ) + d ( ek - gi ) )
    --  42         | i k l |
    --
    --           7 | a b d |
    -- C   = (-1)  | e f h | = - ( a ( fl - hj ) - b ( el - hi ) + d ( ej - fi ) )
    --  43         | i j l |
    --
    --           8 | a b c |
    -- C   = (-1)  | e f g | = + ( a ( fk - gj ) - b ( ek - gi ) + c ( ej - fi ) )
    --  44         | i j k |
    --
    -- Cost of operation
    -- 53 adds, 104 muls, and 1 div.
    local a = matrix.M11 local b = matrix.M12 local c = matrix.M13 local d = matrix.M14
    local e = matrix.M21 local f = matrix.M22 local g = matrix.M23 local h = matrix.M24
    local i = matrix.M31 local j = matrix.M32 local k = matrix.M33 local l = matrix.M34
    local m = matrix.M41 local n = matrix.M42 local o = matrix.M43 local p = matrix.M44

    local kp_lo = k * p - l * o
    local jp_ln = j * p - l * n
    local jo_kn = j * o - k * n
    local ip_lm = i * p - l * m
    local io_km = i * o - k * m
    local in_jm = i * n - j * m

    local a11 = (f * kp_lo - g * jp_ln + h * jo_kn)
    local a12 = - (e * kp_lo - g * ip_lm + h * io_km)
    local a13 = (e * jp_ln - f * ip_lm + h * in_jm)
    local a14 = - (e * jo_kn - f * io_km + g * in_jm)

    local det = a * a11 + b * a12 + c * a13 + d * a14

    if abs(det) < 1.401298E-45 --[[Single.Epsilon]] then
      result = new(Matrix4x4, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN, System.Single.NaN)
      return false, result
    end

    local invDet = 1.0 / det

    if result == nil then
        result = new(Matrix4x4)
    end

    result.M11 = a11 * invDet
    result.M21 = a12 * invDet
    result.M31 = a13 * invDet
    result.M41 = a14 * invDet

    result.M12 = - (b * kp_lo - c * jp_ln + d * jo_kn) * invDet
    result.M22 = (a * kp_lo - c * ip_lm + d * io_km) * invDet
    result.M32 = - (a * jp_ln - b * ip_lm + d * in_jm) * invDet
    result.M42 = (a * jo_kn - b * io_km + c * in_jm) * invDet

    local gp_ho = g * p - h * o
    local fp_hn = f * p - h * n
    local fo_gn = f * o - g * n
    local ep_hm = e * p - h * m
    local eo_gm = e * o - g * m
    local en_fm = e * n - f * m

    result.M13 = (b * gp_ho - c * fp_hn + d * fo_gn) * invDet
    result.M23 = - (a * gp_ho - c * ep_hm + d * eo_gm) * invDet
    result.M33 = (a * fp_hn - b * ep_hm + d * en_fm) * invDet
    result.M43 = - (a * fo_gn - b * eo_gm + c * en_fm) * invDet

    local gl_hk = g * l - h * k
    local fl_hj = f * l - h * j
    local fk_gj = f * k - g * j
    local el_hi = e * l - h * i
    local ek_gi = e * k - g * i
    local ej_fi = e * j - f * i

    result.M14 = - (b * gl_hk - c * fl_hj + d * fk_gj) * invDet
    result.M24 = (a * gl_hk - c * el_hi + d * ek_gi) * invDet
    result.M34 = - (a * fl_hj - b * el_hi + d * ej_fi) * invDet
    result.M44 = (a * fk_gj - b * ek_gi + c * ej_fi) * invDet

    return true, result
end

Matrix4x4.Transform = function (value, rotation)
    -- Compute rotation matrix.
    local x2 = rotation.X + rotation.X
    local y2 = rotation.Y + rotation.Y
    local z2 = rotation.Z + rotation.Z

    local wx2 = rotation.W * x2
    local wy2 = rotation.W * y2
    local wz2 = rotation.W * z2
    local xx2 = rotation.X * x2
    local xy2 = rotation.X * y2
    local xz2 = rotation.X * z2
    local yy2 = rotation.Y * y2
    local yz2 = rotation.Y * z2
    local zz2 = rotation.Z * z2

    local q11 = 1.0 - yy2 - zz2
    local q21 = xy2 - wz2
    local q31 = xz2 + wy2

    local q12 = xy2 + wz2
    local q22 = 1.0 - xx2 - zz2
    local q32 = yz2 - wx2

    local q13 = xz2 - wy2
    local q23 = yz2 + wx2
    local q33 = 1.0 - xx2 - yy2

    local result = new(Matrix4x4)

    -- First row
    result.M11 = value.M11 * q11 + value.M12 * q21 + value.M13 * q31
    result.M12 = value.M11 * q12 + value.M12 * q22 + value.M13 * q32
    result.M13 = value.M11 * q13 + value.M12 * q23 + value.M13 * q33
    result.M14 = value.M14

    -- Second row
    result.M21 = value.M21 * q11 + value.M22 * q21 + value.M23 * q31
    result.M22 = value.M21 * q12 + value.M22 * q22 + value.M23 * q32
    result.M23 = value.M21 * q13 + value.M22 * q23 + value.M23 * q33
    result.M24 = value.M24

    -- Third row
    result.M31 = value.M31 * q11 + value.M32 * q21 + value.M33 * q31
    result.M32 = value.M31 * q12 + value.M32 * q22 + value.M33 * q32
    result.M33 = value.M31 * q13 + value.M32 * q23 + value.M33 * q33
    result.M34 = value.M34

    -- Fourth row
    result.M41 = value.M41 * q11 + value.M42 * q21 + value.M43 * q31
    result.M42 = value.M41 * q12 + value.M42 * q22 + value.M43 * q32
    result.M43 = value.M41 * q13 + value.M42 * q23 + value.M43 * q33
    result.M44 = value.M44

    return result:__clone__()
end

Matrix4x4.Transpose = function (matrix)
    local result = new(Matrix4x4)

    result.M11 = matrix.M11
    result.M12 = matrix.M21
    result.M13 = matrix.M31
    result.M14 = matrix.M41
    result.M21 = matrix.M12
    result.M22 = matrix.M22
    result.M23 = matrix.M32
    result.M24 = matrix.M42
    result.M31 = matrix.M13
    result.M32 = matrix.M23
    result.M33 = matrix.M33
    result.M34 = matrix.M43
    result.M41 = matrix.M14
    result.M42 = matrix.M24
    result.M43 = matrix.M34
    result.M44 = matrix.M44

    return result:__clone__()
end

Matrix4x4.Lerp = function (matrix1, matrix2, amount)
    local result = new(Matrix4x4)

    -- First row
    result.M11 = matrix1.M11 + (matrix2.M11 - matrix1.M11) * amount
    result.M12 = matrix1.M12 + (matrix2.M12 - matrix1.M12) * amount
    result.M13 = matrix1.M13 + (matrix2.M13 - matrix1.M13) * amount
    result.M14 = matrix1.M14 + (matrix2.M14 - matrix1.M14) * amount

    -- Second row
    result.M21 = matrix1.M21 + (matrix2.M21 - matrix1.M21) * amount
    result.M22 = matrix1.M22 + (matrix2.M22 - matrix1.M22) * amount
    result.M23 = matrix1.M23 + (matrix2.M23 - matrix1.M23) * amount
    result.M24 = matrix1.M24 + (matrix2.M24 - matrix1.M24) * amount

    -- Third row
    result.M31 = matrix1.M31 + (matrix2.M31 - matrix1.M31) * amount
    result.M32 = matrix1.M32 + (matrix2.M32 - matrix1.M32) * amount
    result.M33 = matrix1.M33 + (matrix2.M33 - matrix1.M33) * amount
    result.M34 = matrix1.M34 + (matrix2.M34 - matrix1.M34) * amount

    -- Fourth row
    result.M41 = matrix1.M41 + (matrix2.M41 - matrix1.M41) * amount
    result.M42 = matrix1.M42 + (matrix2.M42 - matrix1.M42) * amount
    result.M43 = matrix1.M43 + (matrix2.M43 - matrix1.M43) * amount
    result.M44 = matrix1.M44 + (matrix2.M44 - matrix1.M44) * amount

    return result:__clone__()
end

Matrix4x4.Negate = function (value)
    local result = new(Matrix4x4)

    result.M11 = - value.M11
    result.M12 = - value.M12
    result.M13 = - value.M13
    result.M14 = - value.M14
    result.M21 = - value.M21
    result.M22 = - value.M22
    result.M23 = - value.M23
    result.M24 = - value.M24
    result.M31 = - value.M31
    result.M32 = - value.M32
    result.M33 = - value.M33
    result.M34 = - value.M34
    result.M41 = - value.M41
    result.M42 = - value.M42
    result.M43 = - value.M43
    result.M44 = - value.M44

    return result:__clone__()
end

Matrix4x4.Add = function (value1, value2)
    local result = new(Matrix4x4)

    result.M11 = value1.M11 + value2.M11
    result.M12 = value1.M12 + value2.M12
    result.M13 = value1.M13 + value2.M13
    result.M14 = value1.M14 + value2.M14
    result.M21 = value1.M21 + value2.M21
    result.M22 = value1.M22 + value2.M22
    result.M23 = value1.M23 + value2.M23
    result.M24 = value1.M24 + value2.M24
    result.M31 = value1.M31 + value2.M31
    result.M32 = value1.M32 + value2.M32
    result.M33 = value1.M33 + value2.M33
    result.M34 = value1.M34 + value2.M34
    result.M41 = value1.M41 + value2.M41
    result.M42 = value1.M42 + value2.M42
    result.M43 = value1.M43 + value2.M43
    result.M44 = value1.M44 + value2.M44

    return result:__clone__()
end

Matrix4x4.Subtract = function (value1, value2)
    local result = new(Matrix4x4)

    result.M11 = value1.M11 - value2.M11
    result.M12 = value1.M12 - value2.M12
    result.M13 = value1.M13 - value2.M13
    result.M14 = value1.M14 - value2.M14
    result.M21 = value1.M21 - value2.M21
    result.M22 = value1.M22 - value2.M22
    result.M23 = value1.M23 - value2.M23
    result.M24 = value1.M24 - value2.M24
    result.M31 = value1.M31 - value2.M31
    result.M32 = value1.M32 - value2.M32
    result.M33 = value1.M33 - value2.M33
    result.M34 = value1.M34 - value2.M34
    result.M41 = value1.M41 - value2.M41
    result.M42 = value1.M42 - value2.M42
    result.M43 = value1.M43 - value2.M43
    result.M44 = value1.M44 - value2.M44

    return result:__clone__()
end

Matrix4x4.Multiply = function(value1, value2)
    if value2.M11 == nil then
        -- scalar
        local result = new(Matrix4x4)

        result.M11 = value1.M11 * value2
        result.M12 = value1.M12 * value2
        result.M13 = value1.M13 * value2
        result.M14 = value1.M14 * value2
        result.M21 = value1.M21 * value2
        result.M22 = value1.M22 * value2
        result.M23 = value1.M23 * value2
        result.M24 = value1.M24 * value2
        result.M31 = value1.M31 * value2
        result.M32 = value1.M32 * value2
        result.M33 = value1.M33 * value2
        result.M34 = value1.M34 * value2
        result.M41 = value1.M41 * value2
        result.M42 = value1.M42 * value2
        result.M43 = value1.M43 * value2
        result.M44 = value1.M44 * value2

        return result:__clone__()
    else
        -- matrix
        local result = new(Matrix4x4)

        -- First row
        result.M11 = value1.M11 * value2.M11 + value1.M12 * value2.M21 + value1.M13 * value2.M31 + value1.M14 * value2.M41
        result.M12 = value1.M11 * value2.M12 + value1.M12 * value2.M22 + value1.M13 * value2.M32 + value1.M14 * value2.M42
        result.M13 = value1.M11 * value2.M13 + value1.M12 * value2.M23 + value1.M13 * value2.M33 + value1.M14 * value2.M43
        result.M14 = value1.M11 * value2.M14 + value1.M12 * value2.M24 + value1.M13 * value2.M34 + value1.M14 * value2.M44

        -- Second row
        result.M21 = value1.M21 * value2.M11 + value1.M22 * value2.M21 + value1.M23 * value2.M31 + value1.M24 * value2.M41
        result.M22 = value1.M21 * value2.M12 + value1.M22 * value2.M22 + value1.M23 * value2.M32 + value1.M24 * value2.M42
        result.M23 = value1.M21 * value2.M13 + value1.M22 * value2.M23 + value1.M23 * value2.M33 + value1.M24 * value2.M43
        result.M24 = value1.M21 * value2.M14 + value1.M22 * value2.M24 + value1.M23 * value2.M34 + value1.M24 * value2.M44

        -- Third row
        result.M31 = value1.M31 * value2.M11 + value1.M32 * value2.M21 + value1.M33 * value2.M31 + value1.M34 * value2.M41
        result.M32 = value1.M31 * value2.M12 + value1.M32 * value2.M22 + value1.M33 * value2.M32 + value1.M34 * value2.M42
        result.M33 = value1.M31 * value2.M13 + value1.M32 * value2.M23 + value1.M33 * value2.M33 + value1.M34 * value2.M43
        result.M34 = value1.M31 * value2.M14 + value1.M32 * value2.M24 + value1.M33 * value2.M34 + value1.M34 * value2.M44

        -- Fourth row
        result.M41 = value1.M41 * value2.M11 + value1.M42 * value2.M21 + value1.M43 * value2.M31 + value1.M44 * value2.M41
        result.M42 = value1.M41 * value2.M12 + value1.M42 * value2.M22 + value1.M43 * value2.M32 + value1.M44 * value2.M42
        result.M43 = value1.M41 * value2.M13 + value1.M42 * value2.M23 + value1.M43 * value2.M33 + value1.M44 * value2.M43
        result.M44 = value1.M41 * value2.M14 + value1.M42 * value2.M24 + value1.M43 * value2.M34 + value1.M44 * value2.M44

        return result:__clone__()
    end
end

Matrix4x4.op_UnaryNegation = function (value)
    local m = new(Matrix4x4)

    m.M11 = - value.M11
    m.M12 = - value.M12
    m.M13 = - value.M13
    m.M14 = - value.M14
    m.M21 = - value.M21
    m.M22 = - value.M22
    m.M23 = - value.M23
    m.M24 = - value.M24
    m.M31 = - value.M31
    m.M32 = - value.M32
    m.M33 = - value.M33
    m.M34 = - value.M34
    m.M41 = - value.M41
    m.M42 = - value.M42
    m.M43 = - value.M43
    m.M44 = - value.M44

    return m:__clone__()
end

Matrix4x4.op_Addition = function (value1, value2)
    local m = new(Matrix4x4)

    m.M11 = value1.M11 + value2.M11
    m.M12 = value1.M12 + value2.M12
    m.M13 = value1.M13 + value2.M13
    m.M14 = value1.M14 + value2.M14
    m.M21 = value1.M21 + value2.M21
    m.M22 = value1.M22 + value2.M22
    m.M23 = value1.M23 + value2.M23
    m.M24 = value1.M24 + value2.M24
    m.M31 = value1.M31 + value2.M31
    m.M32 = value1.M32 + value2.M32
    m.M33 = value1.M33 + value2.M33
    m.M34 = value1.M34 + value2.M34
    m.M41 = value1.M41 + value2.M41
    m.M42 = value1.M42 + value2.M42
    m.M43 = value1.M43 + value2.M43
    m.M44 = value1.M44 + value2.M44

    return m:__clone__()
end

Matrix4x4.op_Subtraction = function (value1, value2)
    local m = new(Matrix4x4)

    m.M11 = value1.M11 - value2.M11
    m.M12 = value1.M12 - value2.M12
    m.M13 = value1.M13 - value2.M13
    m.M14 = value1.M14 - value2.M14
    m.M21 = value1.M21 - value2.M21
    m.M22 = value1.M22 - value2.M22
    m.M23 = value1.M23 - value2.M23
    m.M24 = value1.M24 - value2.M24
    m.M31 = value1.M31 - value2.M31
    m.M32 = value1.M32 - value2.M32
    m.M33 = value1.M33 - value2.M33
    m.M34 = value1.M34 - value2.M34
    m.M41 = value1.M41 - value2.M41
    m.M42 = value1.M42 - value2.M42
    m.M43 = value1.M43 - value2.M43
    m.M44 = value1.M44 - value2.M44

    return m:__clone__()
end

Matrix4x4.op_Multiply = function(value1, value2)
    if value2.M11 == nil then
        -- scalar
        local result = new(Matrix4x4)

        result.M11 = value1.M11 * value2
        result.M12 = value1.M12 * value2
        result.M13 = value1.M13 * value2
        result.M14 = value1.M14 * value2
        result.M21 = value1.M21 * value2
        result.M22 = value1.M22 * value2
        result.M23 = value1.M23 * value2
        result.M24 = value1.M24 * value2
        result.M31 = value1.M31 * value2
        result.M32 = value1.M32 * value2
        result.M33 = value1.M33 * value2
        result.M34 = value1.M34 * value2
        result.M41 = value1.M41 * value2
        result.M42 = value1.M42 * value2
        result.M43 = value1.M43 * value2
        result.M44 = value1.M44 * value2

        return result:__clone__()
    else
        -- matrix
        local result = new(Matrix4x4)

        -- First row
        result.M11 = value1.M11 * value2.M11 + value1.M12 * value2.M21 + value1.M13 * value2.M31 + value1.M14 * value2.M41
        result.M12 = value1.M11 * value2.M12 + value1.M12 * value2.M22 + value1.M13 * value2.M32 + value1.M14 * value2.M42
        result.M13 = value1.M11 * value2.M13 + value1.M12 * value2.M23 + value1.M13 * value2.M33 + value1.M14 * value2.M43
        result.M14 = value1.M11 * value2.M14 + value1.M12 * value2.M24 + value1.M13 * value2.M34 + value1.M14 * value2.M44

        -- Second row
        result.M21 = value1.M21 * value2.M11 + value1.M22 * value2.M21 + value1.M23 * value2.M31 + value1.M24 * value2.M41
        result.M22 = value1.M21 * value2.M12 + value1.M22 * value2.M22 + value1.M23 * value2.M32 + value1.M24 * value2.M42
        result.M23 = value1.M21 * value2.M13 + value1.M22 * value2.M23 + value1.M23 * value2.M33 + value1.M24 * value2.M43
        result.M24 = value1.M21 * value2.M14 + value1.M22 * value2.M24 + value1.M23 * value2.M34 + value1.M24 * value2.M44

        -- Third row
        result.M31 = value1.M31 * value2.M11 + value1.M32 * value2.M21 + value1.M33 * value2.M31 + value1.M34 * value2.M41
        result.M32 = value1.M31 * value2.M12 + value1.M32 * value2.M22 + value1.M33 * value2.M32 + value1.M34 * value2.M42
        result.M33 = value1.M31 * value2.M13 + value1.M32 * value2.M23 + value1.M33 * value2.M33 + value1.M34 * value2.M43
        result.M34 = value1.M31 * value2.M14 + value1.M32 * value2.M24 + value1.M33 * value2.M34 + value1.M34 * value2.M44

        -- Fourth row
        result.M41 = value1.M41 * value2.M11 + value1.M42 * value2.M21 + value1.M43 * value2.M31 + value1.M44 * value2.M41
        result.M42 = value1.M41 * value2.M12 + value1.M42 * value2.M22 + value1.M43 * value2.M32 + value1.M44 * value2.M42
        result.M43 = value1.M41 * value2.M13 + value1.M42 * value2.M23 + value1.M43 * value2.M33 + value1.M44 * value2.M43
        result.M44 = value1.M41 * value2.M14 + value1.M42 * value2.M24 + value1.M43 * value2.M34 + value1.M44 * value2.M44

        return result:__clone__()
    end
end

Matrix4x4.op_Equality = function (value1, value2)
    return (value1.M11 == value2.M11 and value1.M22 == value2.M22 and value1.M33 == value2.M33 and value1.M44 == value2.M44 and value1.M12 == value2.M12 and value1.M13 == value2.M13 and value1.M14 == value2.M14 and value1.M21 == value2.M21 and value1.M23 == value2.M23 and value1.M24 == value2.M24 and value1.M31 == value2.M31 and value1.M32 == value2.M32 and value1.M34 == value2.M34 and value1.M41 == value2.M41 and value1.M42 == value2.M42 and value1.M43 == value2.M43)
end

Matrix4x4.op_Inequality = function (value1, value2)
    return (value1.M11 ~= value2.M11 or value1.M12 ~= value2.M12 or value1.M13 ~= value2.M13 or value1.M14 ~= value2.M14 or value1.M21 ~= value2.M21 or value1.M22 ~= value2.M22 or value1.M23 ~= value2.M23 or value1.M24 ~= value2.M24 or value1.M31 ~= value2.M31 or value1.M32 ~= value2.M32 or value1.M33 ~= value2.M33 or value1.M34 ~= value2.M34 or value1.M41 ~= value2.M41 or value1.M42 ~= value2.M42 or value1.M43 ~= value2.M43 or value1.M44 ~= value2.M44)
end

Matrix4x4.Equals = function (this, other)
    if System.is(other, Matrix4x4) then
        return (this.M11 == other.M11 and this.M22 == other.M22 and this.M33 == other.M33 and this.M44 == other.M44 and this.M12 == other.M12 and this.M13 == other.M13 and this.M14 == other.M14 and this.M21 == other.M21 and this.M23 == other.M23 and this.M24 == other.M24 and this.M31 == other.M31 and this.M32 == other.M32 and this.M34 == other.M34 and this.M41 == other.M41 and this.M42 == other.M42 and this.M43 == other.M43)
    end
    return false
end

Matrix4x4.ToString = function (this)
    local sb = System.StringBuilder()
    sb:Append("{ ")
    sb:Append("{")
    sb:Append("M11: ")
    sb:Append(this.M11:ToString())
    sb:Append(" M12: ")
    sb:Append(this.M12:ToString())
    sb:Append(" M13: ")
    sb:Append(this.M13:ToString())
    sb:Append(" M14: ")
    sb:Append(this.M14:ToString())
    sb:Append("} ")
    sb:Append("{")
    sb:Append("M21: ")
    sb:Append(this.M21:ToString())
    sb:Append(" M22: ")
    sb:Append(this.M22:ToString())
    sb:Append(" M23: ")
    sb:Append(this.M23:ToString())
    sb:Append(" M24: ")
    sb:Append(this.M24:ToString())
    sb:Append("} ")
    sb:Append("{")
    sb:Append("M31: ")
    sb:Append(this.M31:ToString())
    sb:Append(" M32: ")
    sb:Append(this.M32:ToString())
    sb:Append(" M33: ")
    sb:Append(this.M33:ToString())
    sb:Append(" M34: ")
    sb:Append(this.M34:ToString())
    sb:Append("} ")
    sb:Append("{")
    sb:Append("M41: ")
    sb:Append(this.M41:ToString())
    sb:Append(" M42: ")
    sb:Append(this.M42:ToString())
    sb:Append(" M43: ")
    sb:Append(this.M43:ToString())
    sb:Append(" M44: ")
    sb:Append(this.M44:ToString())
    sb:Append("} ")
    sb:Append("}")
    return sb:ToString()
end

Matrix4x4.GetHashCode = function (this)
    return this.M11:GetHashCode() + this.M12:GetHashCode() + this.M13:GetHashCode() + this.M14:GetHashCode() + this.M21:GetHashCode() + this.M22:GetHashCode() + this.M23:GetHashCode() + this.M24:GetHashCode() + this.M31:GetHashCode() + this.M32:GetHashCode() + this.M33:GetHashCode() + this.M34:GetHashCode() + this.M41:GetHashCode() + this.M42:GetHashCode() + this.M43:GetHashCode() + this.M44:GetHashCode()
end

-- https://math.stackexchange.com/questions/237369/given-this-transformation-matrix-how-do-i-decompose-it-into-translation-rotati
-- It appears that this function is not complete, as it appears by the comments
-- Improvement is welcome
Matrix4x4.Decompose = function(matrix, scale, rotation, translation)
    -- throw(NotImplementedException("Matrix4x4.Decompose is not yet implemented"))

    -- Extract Translation
    translation = SystemNumerics.Vector3(matrix.M41, matrix.M42, matrix.M43)

    -- Zero Translation
    matrix.M41 = 0
    matrix.M42 = 0
    matrix.M43 = 0

    -- Extract scales

    local sx = SystemNumerics.Vector3(matrix.M11, matrix.M12, matrix.M13):Length()
    local sy = SystemNumerics.Vector3(matrix.M21, matrix.M22, matrix.M23):Length()
    local sz = SystemNumerics.Vector3(matrix.M31, matrix.M32, matrix.M33):Length()

    scale = SystemNumerics.Vector3(sx, sy, sz)

    -- divide by scale

    local matTemp = matrix:__clone__()

    matTemp.M11 = matTemp.M11 / sx
    matTemp.M12 = matTemp.M12 / sx
    matTemp.M13 = matTemp.M13 / sx

    matTemp.M21 = matTemp.M21 / sy
    matTemp.M22 = matTemp.M22 / sy
    matTemp.M23 = matTemp.M23 / sy

    matTemp.M31 = matTemp.M31 / sz
    matTemp.M32 = matTemp.M32 / sz
    matTemp.M33 = matTemp.M33/ sz

    rotation = SystemNumerics.Quaternion.CreateFromRotationMatrix(matTemp)

    return true, scale, rotation, translation
end

System.defStc("System.Numerics.Matrix4x4", Matrix4x4)
end

-- CoreSystemLib: Numerics/Plane.lua
do
local System = System
local SystemNumerics = System.Numerics

local sqrt = math.sqrt
local abs = math.abs

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1

local new = function (cls, ...)
    local this = setmetatable({}, cls)
    return this, cls.__ctor__(this, ...)
end

local Plane = {}

Plane.__ctor__ = function(this, val1, val2, val3, val4)
    if val4 == nil then
        if val2 == nil then
            -- Plane(Vector4)
            this.Normal = SystemNumerics.Vector3(val1.X, val1.Y, val1.Z)
            this.D = val1.W
        else
            -- Plane(Vector3, Single)
            this.Normal = val1:__clone__()
            this.D = val2
        end
    else
        -- Plane(Single, Single, Single, Single)
        this.Normal = SystemNumerics.Vector3(val1, val2, val3)
        this.D = val4
    end
end

Plane.base = function (_, T)
    return { IComparable, IComparable_1(T), IEquatable_1(T) }
end

Plane.CreateFromVertices = function (point1, point2, point3)
    local ax = point2.X - point1.X
    local ay = point2.Y - point1.Y
    local az = point2.Z - point1.Z

    local bx = point3.X - point1.X
    local by = point3.Y - point1.Y
    local bz = point3.Z - point1.Z

    -- N=Cross(a,b)
    local nx = ay * bz - az * by
    local ny = az * bx - ax * bz
    local nz = ax * by - ay * bx

    -- Normalize(N)
    local ls = nx * nx + ny * ny + nz * nz
    local invNorm = 1.0 / System.ToSingle(sqrt(ls))

    local normal = SystemNumerics.Vector3(nx * invNorm, ny * invNorm, nz * invNorm)

    return new(Plane, normal:__clone__(), - (normal.X * point1.X + normal.Y * point1.Y + normal.Z * point1.Z))
end

Plane.Normalize = function (value)
    -- smallest such that 1.0+FLT_EPSILON != 1.0
    local f = value.Normal.X * value.Normal.X + value.Normal.Y * value.Normal.Y + value.Normal.Z * value.Normal.Z

    if abs(f - 1.0) < 1.192093E-07 --[[FLT_EPSILON]] then
        return value:__clone__()
        -- It already normalized, so we don't need to further process.
    end

    local fInv = 1.0 / System.ToSingle(sqrt(f))

    return new(Plane, value.Normal.X * fInv, value.Normal.Y * fInv, value.Normal.Z * fInv, value.D * fInv)
  end

Plane.Transform = function (plane, matrix)
    if matrix.X == nil then
        -- matrix
        local m
        local default
        default, m = SystemNumerics.Matrix4x4.Invert(matrix)

        local x = plane.Normal.X local y = plane.Normal.Y local z = plane.Normal.Z local w = plane.D

        return new(Plane, x * m.M11 + y * m.M12 + z * m.M13 + w * m.M14, x * m.M21 + y * m.M22 + z * m.M23 + w * m.M24, x * m.M31 + y * m.M32 + z * m.M33 + w * m.M34, x * m.M41 + y * m.M42 + z * m.M43 + w * m.M44)
    else
        -- quaternion
        local x2 = matrix.X + matrix.X
        local y2 = matrix.Y + matrix.Y
        local z2 = matrix.Z + matrix.Z
  
        local wx2 = matrix.W * x2
        local wy2 = matrix.W * y2
        local wz2 = matrix.W * z2
        local xx2 = matrix.X * x2
        local xy2 = matrix.X * y2
        local xz2 = matrix.X * z2
        local yy2 = matrix.Y * y2
        local yz2 = matrix.Y * z2
        local zz2 = matrix.Z * z2
  
        local m11 = 1.0 - yy2 - zz2
        local m21 = xy2 - wz2
        local m31 = xz2 + wy2
  
        local m12 = xy2 + wz2
        local m22 = 1.0 - xx2 - zz2
        local m32 = yz2 - wx2
  
        local m13 = xz2 - wy2
        local m23 = yz2 + wx2
        local m33 = 1.0 - xx2 - yy2
  
        local x = plane.Normal.X local y = plane.Normal.Y local z = plane.Normal.Z
  
        return new(Plane, x * m11 + y * m21 + z * m31, x * m12 + y * m22 + z * m32, x * m13 + y * m23 + z * m33, plane.D)  
    end
end

Plane.Dot = function (plane, value)
    return plane.Normal.X * value.X + plane.Normal.Y * value.Y + plane.Normal.Z * value.Z + plane.D * value.W
end

Plane.DotCoordinate = function (plane, value)
    return plane.Normal.X * value.X + plane.Normal.Y * value.Y + plane.Normal.Z * value.Z + plane.D
end

Plane.DotNormal = function (plane, value)
    return plane.Normal.X * value.X + plane.Normal.Y * value.Y + plane.Normal.Z * value.Z
end

Plane.op_Equality = function (value1, value2)
    return (value1.Normal.X == value2.Normal.X and value1.Normal.Y == value2.Normal.Y and value1.Normal.Z == value2.Normal.Z and value1.D == value2.D)
end

Plane.op_Inequality = function (value1, value2)
    return (value1.Normal.X ~= value2.Normal.X or value1.Normal.Y ~= value2.Normal.Y or value1.Normal.Z ~= value2.Normal.Z or value1.D ~= value2.D)
end

Plane.Equals = function (this, obj)
    if System.is(obj, Plane) then
        return (this.Normal.X == obj.Normal.X and this.Normal.Y == obj.Normal.Y and this.Normal.Z == obj.Normal.Z and this.D == obj.D)
    end
    return false
end

Plane.ToString = function (this)
    local sb = System.StringBuilder()
    sb:Append("{")
    sb:Append("Normal: ")
    sb:Append(this.Normal:ToString())
    sb:Append(" D: ")
    sb:Append(this.D:ToString())
    sb:Append("}")
    return sb:ToString()
end

Plane.GetHashCode = function (this)
    return this.Normal:GetHashCode() + this.D:GetHashCode()
end

System.defStc("System.Numerics.Plane", Plane)
end

-- CoreSystemLib: Numerics/Quaternion.lua
do
local System = System
local SystemNumerics = System.Numerics

local sqrt = math.sqrt
local sin = math.sin
local cos = math.cos
local acos = math.acos

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1

local new = function (cls, ...)
    local this = setmetatable({}, cls)
    return this, cls.__ctor__(this, ...)
end

local Quaternion = {}

Quaternion.__ctor__ = function(this, x, y, z, w)
    if x == nil then
        this.X = 0
        this.Y = 0
        this.Z = 0
        this.W = 0
    elseif z == nil then
        -- Quaternion(Vector3, Single)
        this.X = x.X or 0
        this.Y = x.Y or 0
        this.Z = x.Z or 0
        this.W = z or 0
    else
        -- Quaternion(Single, Single, Single, Single)
        this.X = x or 0
        this.Y = y or 0
        this.Z = z or 0
        this.W = w or 0
    end
    local mt = getmetatable(this)
    mt.__unm = Quaternion.op_UnaryNegation
    setmetatable(this, mt)
end

Quaternion.base = function (_, T)
    return { IComparable, IComparable_1(T), IEquatable_1(T) }
end

Quaternion.getIdentity = function ()
    return new(Quaternion, 0, 0, 0, 1)
end

Quaternion.getIsIdentity = function (this)
    return this.X == 0 and this.Y == 0 and this.Z == 0 and this.W == 1
end

Quaternion.Length = function (this)
    local ls = this.X * this.X + this.Y * this.Y + this.Z * this.Z + this.W * this.W

    return System.ToSingle(sqrt(ls))
end

Quaternion.LengthSquared = function (this)
    return this.X * this.X + this.Y * this.Y + this.Z * this.Z + this.W * this.W
end

Quaternion.Normalize = function (value)
    local ls = value.X * value.X + value.Y * value.Y + value.Z * value.Z + value.W * value.W
    local invNorm = 1.0 / System.ToSingle(sqrt(ls))

    return new(Quaternion, value.X * invNorm, value.Y * invNorm, value.Z * invNorm, value.W * invNorm)
end

Quaternion.Conjugate = function (value)
    return new(Quaternion, - value.X, - value.Y, - value.Z, value.W)
end

Quaternion.Inverse = function (value)
    --  -1   (       a              -v       )
    -- q   = ( -------------   ------------- )
    --       (  a^2 + |v|^2  ,  a^2 + |v|^2  )

    local ls = value.X * value.X + value.Y * value.Y + value.Z * value.Z + value.W * value.W
    local invNorm = 1.0 / ls

    return new(Quaternion, - value.X * invNorm, - value.Y * invNorm, - value.Z * invNorm, value.W * invNorm)
end

Quaternion.CreateFromAxisAngle = function (axis, angle)
    local halfAngle = angle * 0.5
    local s = System.ToSingle(sin(halfAngle))
    local c = System.ToSingle(cos(halfAngle))

    return new(Quaternion, axis.X * s, axis.Y * s, axis.Z * s, c)
end

Quaternion.CreateFromYawPitchRoll = function (yaw, pitch, roll)
    --  Roll first, about axis the object is facing, then
    --  pitch upward, then yaw to face into the new heading
    local sr, cr, sp, cp, sy, cy

    local halfRoll = roll * 0.5
    sr = System.ToSingle(sin(halfRoll))
    cr = System.ToSingle(cos(halfRoll))

    local halfPitch = pitch * 0.5
    sp = System.ToSingle(sin(halfPitch))
    cp = System.ToSingle(cos(halfPitch))

    local halfYaw = yaw * 0.5
    sy = System.ToSingle(sin(halfYaw))
    cy = System.ToSingle(cos(halfYaw))

    return new(Quaternion, cy * sp * cr + sy * cp * sr, sy * cp * cr - cy * sp * sr, cy * cp * sr - sy * sp * cr, cy * cp * cr + sy * sp * sr)
end

Quaternion.CreateFromRotationMatrix = function (matrix)
    local trace = matrix.M11 + matrix.M22 + matrix.M33

    local q = new(Quaternion)

    if trace > 0.0 then
      local s = System.ToSingle(sqrt(trace + 1.0))
      q.W = s * 0.5
      s = 0.5 / s
      q.X = (matrix.M23 - matrix.M32) * s
      q.Y = (matrix.M31 - matrix.M13) * s
      q.Z = (matrix.M12 - matrix.M21) * s
    else
      if matrix.M11 >= matrix.M22 and matrix.M11 >= matrix.M33 then
        local s = System.ToSingle(sqrt(1.0 + matrix.M11 - matrix.M22 - matrix.M33))
        local invS = 0.5 / s
        q.X = 0.5 * s
        q.Y = (matrix.M12 + matrix.M21) * invS
        q.Z = (matrix.M13 + matrix.M31) * invS
        q.W = (matrix.M23 - matrix.M32) * invS
      elseif matrix.M22 > matrix.M33 then
        local s = System.ToSingle(sqrt(1.0 + matrix.M22 - matrix.M11 - matrix.M33))
        local invS = 0.5 / s
        q.X = (matrix.M21 + matrix.M12) * invS
        q.Y = 0.5 * s
        q.Z = (matrix.M32 + matrix.M23) * invS
        q.W = (matrix.M31 - matrix.M13) * invS
      else
        local s = System.ToSingle(sqrt(1.0 + matrix.M33 - matrix.M11 - matrix.M22))
        local invS = 0.5 / s
        q.X = (matrix.M31 + matrix.M13) * invS
        q.Y = (matrix.M32 + matrix.M23) * invS
        q.Z = 0.5 * s
        q.W = (matrix.M12 - matrix.M21) * invS
      end
    end

    return q:__clone__()
end

Quaternion.Dot = function (quaternion1, quaternion2)
    return quaternion1.X * quaternion2.X + quaternion1.Y * quaternion2.Y + quaternion1.Z * quaternion2.Z + quaternion1.W * quaternion2.W
end

Quaternion.Slerp = function (quaternion1, quaternion2, amount)
    local t = amount

    local cosOmega = quaternion1.X * quaternion2.X + quaternion1.Y * quaternion2.Y + quaternion1.Z * quaternion2.Z + quaternion1.W * quaternion2.W

    local flip = false

    if cosOmega < 0.0 then
      flip = true
      cosOmega = - cosOmega
    end

    local s1, s2

    if cosOmega > (0.999999 --[[1.0f - epsilon]]) then
      -- Too close, do straight linear interpolation.
      s1 = 1.0 - t
      s2 = (flip) and - t or t
    else
      local omega = System.ToSingle(acos(cosOmega))
      local invSinOmega = System.ToSingle((1 / sin(omega)))

      s1 = System.ToSingle(sin((1.0 - t) * omega)) * invSinOmega
      s2 = (flip) and System.ToSingle(- sin(t * omega)) * invSinOmega or System.ToSingle(sin(t * omega)) * invSinOmega
    end

    return new(Quaternion, s1 * quaternion1.X + s2 * quaternion2.X, s1 * quaternion1.Y + s2 * quaternion2.Y, s1 * quaternion1.Z + s2 * quaternion2.Z, s1 * quaternion1.W + s2 * quaternion2.W)
end

Quaternion.Lerp = function (quaternion1, quaternion2, amount)
    local t = amount
    local t1 = 1.0 - t

    local r = new(Quaternion)

    local dot = quaternion1.X * quaternion2.X + quaternion1.Y * quaternion2.Y + quaternion1.Z * quaternion2.Z + quaternion1.W * quaternion2.W

    if dot >= 0.0 then
      r.X = t1 * quaternion1.X + t * quaternion2.X
      r.Y = t1 * quaternion1.Y + t * quaternion2.Y
      r.Z = t1 * quaternion1.Z + t * quaternion2.Z
      r.W = t1 * quaternion1.W + t * quaternion2.W
    else
      r.X = t1 * quaternion1.X - t * quaternion2.X
      r.Y = t1 * quaternion1.Y - t * quaternion2.Y
      r.Z = t1 * quaternion1.Z - t * quaternion2.Z
      r.W = t1 * quaternion1.W - t * quaternion2.W
    end

    -- Normalize it.
    local ls = r.X * r.X + r.Y * r.Y + r.Z * r.Z + r.W * r.W
    local invNorm = 1.0 / System.ToSingle(sqrt(ls))

    r.X = r.X * invNorm
    r.Y = r.Y * invNorm
    r.Z = r.Z * invNorm
    r.W = r.W * invNorm

    return r:__clone__()
end

Quaternion.Concatenate = function (value1, value2)

    -- Concatenate rotation is actually q2 * q1 instead of q1 * q2.
    -- So that's why value2 goes q1 and value1 goes q2.
    local q1x = value2.X
    local q1y = value2.Y
    local q1z = value2.Z
    local q1w = value2.W

    local q2x = value1.X
    local q2y = value1.Y
    local q2z = value1.Z
    local q2w = value1.W

    -- cross(av, bv)
    local cx = q1y * q2z - q1z * q2y
    local cy = q1z * q2x - q1x * q2z
    local cz = q1x * q2y - q1y * q2x

    local dot = q1x * q2x + q1y * q2y + q1z * q2z

    return new(Quaternion, q1x * q2w + q2x * q1w + cx, q1y * q2w + q2y * q1w + cy, q1z * q2w + q2z * q1w + cz, q1w * q2w - dot)
end

Quaternion.Negate = function (value)
    return new(Quaternion, - value.X, - value.Y, - value.Z, - value.W)
end

Quaternion.Add = function (value1, value2)
    return new(Quaternion, value1.X + value2.X, value1.Y + value2.Y, value1.Z + value2.Z, value1.W + value2.W)
end

Quaternion.Subtract = function (value1, value2)
    return new(Quaternion, value1.X - value2.X, value1.Y - value2.Y, value1.Z - value2.Z, value1.W - value2.W)
end

Quaternion.Multiply = function (value1, value2)
    if value2.X == nil then
        -- scalar
        return new(Quaternion, value1.X * value2, value1.Y * value2, value1.Z * value2, value1.W * value2)
    else
        -- quaternion
        local q1x = value1.X
        local q1y = value1.Y
        local q1z = value1.Z
        local q1w = value1.W

        local q2x = value2.X
        local q2y = value2.Y
        local q2z = value2.Z
        local q2w = value2.W

        -- cross(av, bv)
        local cx = q1y * q2z - q1z * q2y
        local cy = q1z * q2x - q1x * q2z
        local cz = q1x * q2y - q1y * q2x

        local dot = q1x * q2x + q1y * q2y + q1z * q2z

        return new(Quaternion, q1x * q2w + q2x * q1w + cx, q1y * q2w + q2y * q1w + cy, q1z * q2w + q2z * q1w + cz, q1w * q2w - dot)
    end    
end

Quaternion.Divide = function (value1, value2)

    local q1x = value1.X
    local q1y = value1.Y
    local q1z = value1.Z
    local q1w = value1.W

    ---------------------------------------
    -- Inverse part.
    local ls = value2.X * value2.X + value2.Y * value2.Y + value2.Z * value2.Z + value2.W * value2.W
    local invNorm = 1.0 / ls

    local q2x = - value2.X * invNorm
    local q2y = - value2.Y * invNorm
    local q2z = - value2.Z * invNorm
    local q2w = value2.W * invNorm

    ---------------------------------------
    -- Multiply part.

    -- cross(av, bv)
    local cx = q1y * q2z - q1z * q2y
    local cy = q1z * q2x - q1x * q2z
    local cz = q1x * q2y - q1y * q2x

    local dot = q1x * q2x + q1y * q2y + q1z * q2z

    return new(Quaternion, q1x * q2w + q2x * q1w + cx, q1y * q2w + q2y * q1w + cy, q1z * q2w + q2z * q1w + cz, q1w * q2w - dot)
end

Quaternion.op_UnaryNegation = function (value)
    return new(Quaternion, - value.X, - value.Y, - value.Z, - value.W)
end

Quaternion.op_Addition = function (value1, value2)
    return new(Quaternion, value1.X + value2.X, value1.Y + value2.Y, value1.Z + value2.Z, value1.W + value2.W)
end

Quaternion.op_Subtraction = function (value1, value2)
    return new(Quaternion, value1.X - value2.X, value1.Y - value2.Y, value1.Z - value2.Z, value1.W - value2.W)
end

Quaternion.op_Multiply = function (value1, value2)
    if value2.X == nil then
        -- scalar
        return new(Quaternion, value1.X * value2, value1.Y * value2, value1.Z * value2, value1.W * value2)
    else
        -- quaternion
        local q1x = value1.X
        local q1y = value1.Y
        local q1z = value1.Z
        local q1w = value1.W

        local q2x = value2.X
        local q2y = value2.Y
        local q2z = value2.Z
        local q2w = value2.W

        -- cross(av, bv)
        local cx = q1y * q2z - q1z * q2y
        local cy = q1z * q2x - q1x * q2z
        local cz = q1x * q2y - q1y * q2x

        local dot = q1x * q2x + q1y * q2y + q1z * q2z

        return new(Quaternion, q1x * q2w + q2x * q1w + cx, q1y * q2w + q2y * q1w + cy, q1z * q2w + q2z * q1w + cz, q1w * q2w - dot)
    end    
end

Quaternion.op_Division = function (value1, value2)

    local q1x = value1.X
    local q1y = value1.Y
    local q1z = value1.Z
    local q1w = value1.W

    ---------------------------------------
    -- Inverse part.
    local ls = value2.X * value2.X + value2.Y * value2.Y + value2.Z * value2.Z + value2.W * value2.W
    local invNorm = 1.0 / ls

    local q2x = - value2.X * invNorm
    local q2y = - value2.Y * invNorm
    local q2z = - value2.Z * invNorm
    local q2w = value2.W * invNorm

    ---------------------------------------
    -- Multiply part.

    -- cross(av, bv)
    local cx = q1y * q2z - q1z * q2y
    local cy = q1z * q2x - q1x * q2z
    local cz = q1x * q2y - q1y * q2x

    local dot = q1x * q2x + q1y * q2y + q1z * q2z

    return new(Quaternion, q1x * q2w + q2x * q1w + cx, q1y * q2w + q2y * q1w + cy, q1z * q2w + q2z * q1w + cz, q1w * q2w - dot)
end

Quaternion.op_Equality = function (value1, value2)
    return (value1.X == value2.X and value1.Y == value2.Y and value1.Z == value2.Z and value1.W == value2.W)
end

Quaternion.op_Inequality = function (value1, value2)
    return (value1.X ~= value2.X or value1.Y ~= value2.Y or value1.Z ~= value2.Z or value1.W ~= value2.W)
end

Quaternion.Equals = function (this, obj)
    if System.is(obj, Quaternion) then
        return (this.X == obj.X and this.Y == obj.Y and this.Z == obj.Z and this.W == obj.W)
    end
    return false
end

Quaternion.ToString = function (this)
    local sb = System.StringBuilder()
    sb:Append("{")
    sb:Append("X: ")
    sb:Append(this.X:ToString())
    sb:Append(" Y: ")
    sb:Append(this.Y:ToString())
    sb:Append(" Z: ")
    sb:Append(this.Z:ToString())
    sb:Append(" W: ")
    sb:Append(this.W:ToString())
    sb:Append("}")
    return sb:ToString()
end

Quaternion.GetHashCode = function (this)
    return this.X:GetHashCode() + this.Y:GetHashCode() + this.Z:GetHashCode() + this.W:GetHashCode()
end

System.defStc("System.Numerics.Quaternion", Quaternion)
end

-- CoreSystemLib: Numerics/Vector2.lua
do
local System = System
local SystemNumerics = System.Numerics

local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1
local IFormattable = System.IFormattable

local new = function (cls, ...)
    local this = setmetatable({}, cls)
    return this, cls.__ctor__(this, ...)
end

local Vector2 = {}

Vector2.__ctor__ = function(this, X, Y)
    if Y == nil then
        this.X = X or 0
        this.Y = X or 0
    else
        this.X = X or 0
        this.Y = Y or 0
    end
    local mt = getmetatable(this)
    mt.__unm = Vector2.op_UnaryNegation
    setmetatable(this, mt)
end

Vector2.base = function (_, T)
    return { IComparable, IComparable_1(T), IEquatable_1(T), IFormattable }
end

Vector2.getZero = function ()
    return new(Vector2, 0, 0, 0)
end
Vector2.getOne = function ()
    return new(Vector2, 1.0, 1.0)
end
Vector2.getUnitX = function ()
    return new(Vector2, 1.0, 0.0)
end
Vector2.getUnitY = function ()
    return new(Vector2, 0.0, 1.0)
end

Vector2.CopyTo = function(this, array, index)
    if index == nil then
        index = 0
    end

    if array == nil then
        System.throw(System.NullReferenceException())
    end

    if index < 0 or index >= #array then
        System.throw(System.ArgumentOutOfRangeException())
    end
    if (#array - index) < 2 then
        System.throw(System.ArgumentException())
    end

    array:set(index, this.X)
    array:set(index + 1, this.Y)
end

Vector2.Equals = function (this, other)
    if not (System.is(other, Vector2)) then
        return false
    end
    other = System.cast(Vector2, other)
    return this.X == other.X and this.Y == other.Y
end

Vector2.Dot = function (value1, value2)
    return value1.X * value2.X + value1.Y * value2.Y
end

Vector2.Min = function (value1, value2)
    return new(Vector2, (value1.X < value2.X) and value1.X or value2.X, (value1.Y < value2.Y) and value1.Y or value2.Y)
end

Vector2.Max = function (value1, value2)
    return new(Vector2, (value1.X > value2.X) and value1.X or value2.X, (value1.Y > value2.Y) and value1.Y or value2.Y)
end

Vector2.Abs = function (value)
    return new(Vector2, abs(value.X), abs(value.Y))
end

Vector2.SquareRoot = function (value)
    return new(Vector2, System.ToSingle(sqrt(value.X)), System.ToSingle(sqrt(value.Y)))
end

Vector2.op_Addition = function (left, right)
    return new(Vector2, left.X + right.X, left.Y + right.Y)
end

Vector2.Add = function (left, right)
    return Vector2.op_Addition(left, right)
end

Vector2.op_Subtraction = function (left, right)
    return new(Vector2, left.X - right.X, left.Y - right.Y)
end

Vector2.Subtract = function (left, right)
    return Vector2.op_Subtraction(left, right)
end

Vector2.op_Multiply = function (left, right)
    if type(left) == "number" then
        left = new(Vector2, left)
    end

    if type(right) == "number" then
        right = new(Vector2, right)
    end

    return new(Vector2, left.X * right.X, left.Y * right.Y)
end

Vector2.Multiply = function (left, right)
    return Vector2.op_Multiply(left, right)
end

Vector2.op_Division = function (left, right)
    if type(right) == "number" then
        return Vector2.op_Multiply(left, 1.0 / right)
    end
    return new(Vector2, left.X / right.X, left.Y / right.Y)
end

Vector2.Divide = function (left, right)
    return Vector2.op_Division(left, right)
end

Vector2.op_UnaryNegation = function (value)
    return Vector2.op_Subtraction(Vector2.getZero(), value)
end

Vector2.Negate = function (value)
    return - value
end

Vector2.op_Equality = function (left, right)
    return (left.X == right.X and left.Y == right.Y )
end

Vector2.op_Inequality = function (left, right)
    return (left.X ~= right.X or left.Y ~= right.Y)
end

Vector2.GetHashCode = function (this)
    local hash = this.X:GetHashCode()
    hash = SystemNumerics.HashCodeHelper.CombineHashCodes(hash, this.Y:GetHashCode())
    return hash
end

Vector2.ToString = function (this)
    local sb = System.StringBuilder()
    local separator = 44 --[[',']]
    sb:AppendChar(60 --[['<']])
    sb:Append(this.X:ToString())
    sb:AppendChar(separator)
    sb:AppendChar(32 --[[' ']])
    sb:Append(this.Y:ToString())
    sb:AppendChar(62 --[['>']])
    return sb:ToString()
end

Vector2.Length = function (this)
    local ls = this.X * this.X + this.Y * this.Y
    return System.ToSingle(sqrt(ls))
end

Vector2.LengthSquared = function (this)
    return this.X * this.X + this.Y * this.Y
end

Vector2.Distance = function (value1, value2)
    local dx = value1.X - value2.X
    local dy = value1.Y - value2.Y

    local ls = dx * dx + dy * dy

    return System.ToSingle(sqrt(ls))
end

Vector2.DistanceSquared = function (value1, value2)
    local dx = value1.X - value2.X
    local dy = value1.Y - value2.Y

    return dx * dx + dy * dy
end

Vector2.Normalize = function (value)
    local ls = value.X * value.X + value.Y * value.Y
    local invNorm = 1.0 / System.ToSingle(sqrt(ls))

    return new(Vector2, value.X * invNorm, value.Y * invNorm)
end

Vector2.Reflect = function (vector, normal)
    local dot = vector.X * normal.X + vector.Y * normal.Y

    return new(Vector2, vector.X - 2.0 * dot * normal.X, vector.Y - 2.0 * dot * normal.Y)
end

Vector2.Clamp = function (value1, min, max)
    -- This compare order is very important!!!
    -- We must follow HLSL behavior in the case user specified min value is bigger than max value.
    local x = value1.X
    x = (x > max.X) and max.X or x
    x = (x < min.X) and min.X or x

    local y = value1.Y
    y = (y > max.Y) and max.Y or y
    y = (y < min.Y) and min.Y or y

    return new(Vector2, x, y)
end

Vector2.Lerp = function (value1, value2, amount)
    return new(Vector2, value1.X + (value2.X - value1.X) * amount, value1.Y + (value2.Y - value1.Y) * amount)
end

Vector2.Transform = function (position, matrix)
    if matrix.M41 == nil then
        -- 3x2 matrix
        return new(Vector2, position.X * matrix.M11 + position.Y * matrix.M21 + matrix.M31, 
                            position.X * matrix.M12 + position.Y * matrix.M22 + matrix.M32
                            )
    elseif matrix.X == nil then
        -- 4x4 matrix
        return new(Vector2, position.X * matrix.M11 + position.Y * matrix.M21 + matrix.M41, 
                            position.X * matrix.M12 + position.Y * matrix.M22 + matrix.M42
                            )
    else 
        -- Quaternion
        local x2 = matrix.X + matrix.X
        local y2 = matrix.Y + matrix.Y
        local z2 = matrix.Z + matrix.Z

        local wz2 = matrix.W * z2
        local xx2 = matrix.X * x2
        local xy2 = matrix.X * y2
        local yy2 = matrix.Y * y2
        local zz2 = matrix.Z * z2

        return new(Vector2, position.X * (1.0 - yy2 - zz2) + position.Y * (xy2 - wz2),
                            position.X * (xy2 + wz2) + position.Y * (1.0 - xx2 - zz2)
                                )    
    end
end

Vector2.TransformNormal = function (normal, matrix)
    if matrix.M41 == nil then
        -- 3.2 matirx
        return new(Vector2, normal.X * matrix.M11 + normal.Y * matrix.M21, 
                            normal.X * matrix.M12 + normal.Y * matrix.M22
                                )
    else
        -- 4x4 matrix
        return new(Vector2, normal.X * matrix.M11 + normal.Y * matrix.M21, 
                            normal.X * matrix.M12 + normal.Y * matrix.M22
                                )
    end
 end

System.defStc("System.Numerics.Vector2", Vector2)
end

-- CoreSystemLib: Numerics/Vector3.lua
do
local System = System
local SystemNumerics = System.Numerics

local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1
local IFormattable = System.IFormattable

local new = function (cls, ...)
    local this = setmetatable({}, cls)
    return this, cls.__ctor__(this, ...)
end

local Vector3 = {}

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3?view=netframework-4.7.2#constructors
Vector3.__ctor__ = function(this, X, Y, Z)
    if Z == nil then
        -- 1 var constructor
        if Y == nil then
            this.X = X or 0
            this.Y = X or 0
            this.Z = X or 0
        -- 2 var constructor
        else
            this.X = X.X
            this.Y = X.Y
            this.Z = Y or 0
        end
    -- 3 var constructor
    else
        this.X = X or 0
        this.Y = Y or 0
        this.Z = Z or 0
    end
    local mt = getmetatable(this)
    mt.__unm = Vector3.op_UnaryNegation
    setmetatable(this, mt)
end

Vector3.base = function (_, T)
    return { IComparable, IComparable_1(T), IEquatable_1(T), IFormattable }
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3?view=netframework-4.7.2#properties
Vector3.getOne = function() return new(Vector3, 1.0, 1.0, 1.0) end
Vector3.getZero = function() return new(Vector3, 0, 0, 0) end
Vector3.getUnitX = function() return new(Vector3, 1.0, 0.0, 0.0) end
Vector3.getUnitY = function() return new(Vector3, 0.0, 1.0, 0.0) end
Vector3.getUnitZ = function() return new(Vector3, 0.0, 0.0, 1.0) end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.copyto?view=netframework-4.7.2#System_Numerics_Vector3_CopyTo_System_Single___
Vector3.CopyTo = function(this, array, index)
    if index == nil then
        index = 0
    end

    if array == nil then
        System.throw(System.NullReferenceException())
    end

    if index < 0 or index >= #array then
        System.throw(System.ArgumentOutOfRangeException())
    end
    if (#array - index) < 3 then
        System.throw(System.ArgumentException())
    end

    array:set(index, this.X)
    array:set(index + 1, this.Y)
    array:set(index + 2, this.Z)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.equals?view=netframework-4.7.2#System_Numerics_Vector3_Equals_System_Object_
Vector3.Equals = function(this, other)
    if not (System.is(other, Vector3)) then
        return false
    end
    other = System.cast(Vector3, other)
    return this.X == other.X and this.Y == other.Y and this.Z == other.Z
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.dot?view=netframework-4.7.2#System_Numerics_Vector3_Dot_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.Dot = function(vector1, vector2)
    return vector1.X * vector2.X + vector1.Y * vector2.Y + vector1.Z * vector2.Z
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.min?view=netframework-4.7.2#System_Numerics_Vector3_Min_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.Min = function(value1, value2)
    return new(Vector3, (value1.X < value2.X) and value1.X or value2.X, (value1.Y < value2.Y) and value1.Y or value2.Y, (value1.Z < value2.Z) and value1.Z or value2.Z)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.max?view=netframework-4.7.2#System_Numerics_Vector3_Max_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.Max = function(value1, value2)
    return new(Vector3, (value1.X > value2.X) and value1.X or value2.X, (value1.Y > value2.Y) and value1.Y or value2.Y, (value1.Z > value2.Z) and value1.Z or value2.Z)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.abs?view=netframework-4.7.2#System_Numerics_Vector3_Abs_System_Numerics_Vector3_
Vector3.Abs = function(value)
    return new(Vector3, abs(value.X), abs(value.Y), abs(value.Z))
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.squareroot?view=netframework-4.7.2#System_Numerics_Vector3_SquareRoot_System_Numerics_Vector3_
Vector3.SquareRoot = function(value)
    return new(Vector3, System.ToSingle(sqrt(value.X)), System.ToSingle(sqrt(value.Y)), System.ToSingle(sqrt(value.Z)))
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.add?view=netframework-4.7.2#System_Numerics_Vector3_Add_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.op_Addition = function(left, right)
    return new(Vector3, left.X + right.X, left.Y + right.Y, left.Z + right.Z)
end

Vector3.Add = function(left, right)
    return Vector3.op_Addition(left, right)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.subtract?view=netframework-4.7.2#System_Numerics_Vector3_Subtract_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.op_Subtraction = function(left, right)
    return new(Vector3, left.X - right.X, left.Y - right.Y, left.Z - right.Z)
end

Vector3.Subtract = function(left, right)
    return Vector3.op_Subtraction(left, right)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.multiply?view=netframework-4.7.2#System_Numerics_Vector3_Multiply_System_Single_System_Numerics_Vector3_
Vector3.op_Multiply = function(left, right)
    if type(left) == "number" then
        left = new(Vector3, left)
    end

    if type(right) == "number" then
        right = new(Vector3, right)
    end
    return new(Vector3, left.X * right.X, left.Y * right.Y, left.Z * right.Z)
end

Vector3.Multiply = function(left, right)
    return Vector3.op_Multiply(left, right)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.divide?view=netframework-4.7.2#System_Numerics_Vector3_Divide_System_Numerics_Vector3_System_Single_
Vector3.op_Division = function(left, right)
    if type(right) == "number" then
        return Vector3.op_Multiply(left, 1.0 / right)
    end
    return new(Vector3, left.X / right.X, left.Y / right.Y, left.Z / right.Z)
end

Vector3.Divide = function(left, right)
    return Vector3.op_Division(left, right)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.negate?view=netframework-4.7.2#System_Numerics_Vector3_Negate_System_Numerics_Vector3_
Vector3.op_UnaryNegation = function(value)
    return Vector3.op_Subtraction(Vector3.getZero(), value)
end

Vector3.Negate = function(value)
    return - value
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.equals?view=netframework-4.7.2#System_Numerics_Vector3_Equals_System_Numerics_Vector3_
Vector3.op_Equality = function(left, right)
    return (left.X == right.X and left.Y == right.Y and left.Z == right.Z)
end

Vector3.op_Inequality = function(left, right)
    return (left.X ~= right.X or left.Y ~= right.Y or left.Z ~= right.Z)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.gethashcode?view=netframework-4.7.2#System_Numerics_Vector3_GetHashCode
Vector3.GetHashCode = function(this)
    local hash = this.X:GetHashCode()
    hash = SystemNumerics.HashCodeHelper.CombineHashCodes(hash, this.Y:GetHashCode())
    hash = SystemNumerics.HashCodeHelper.CombineHashCodes(hash, this.Z:GetHashCode())
    return hash
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.tostring?view=netframework-4.7.2#System_Numerics_Vector3_ToString
Vector3.ToString = function(this)
    local sb = System.StringBuilder()
    local separator = 44 --[[',']]
    sb:AppendChar(60 --[['<']])
    sb:Append((this.X):ToString())
    sb:AppendChar(separator)
    sb:AppendChar(32 --[[' ']])
    sb:Append((this.Y):ToString())
    sb:AppendChar(separator)
    sb:AppendChar(32 --[[' ']])
    sb:Append((this.Z):ToString())
    sb:AppendChar(62 --[['>']])
    return sb:ToString()
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.length?view=netframework-4.7.2#System_Numerics_Vector3_Length
Vector3.Length = function(this)
    local ls = this.X * this.X + this.Y * this.Y + this.Z * this.Z
    return System.ToSingle(sqrt(ls))
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.lengthsquared?view=netframework-4.7.2#System_Numerics_Vector3_LengthSquared
Vector3.LengthSquared = function(this)
    return this.X * this.X + this.Y * this.Y + this.Z * this.Z
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.distance?view=netframework-4.7.2#System_Numerics_Vector3_Distance_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.Distance = function(value1, value2)
    local dx = value1.X - value2.X
    local dy = value1.Y - value2.Y
    local dz = value1.Z - value2.Z

    local ls = dx * dx + dy * dy + dz * dz

    return System.ToSingle(sqrt(ls))
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.distancesquared?view=netframework-4.7.2#System_Numerics_Vector3_DistanceSquared_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.DistanceSquared = function(value1, value2)
    local dx = value1.X - value2.X
    local dy = value1.Y - value2.Y
    local dz = value1.Z - value2.Z

    return dx * dx + dy * dy + dz * dz
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.normalize?view=netframework-4.7.2#System_Numerics_Vector3_Normalize_System_Numerics_Vector3_
Vector3.Normalize = function(value)
    local ls = value.X * value.X + value.Y * value.Y + value.Z * value.Z
    local length = System.ToSingle(sqrt(ls))
    return new(Vector3, value.X / length, value.Y / length, value.Z / length)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.cross?view=netframework-4.7.2#System_Numerics_Vector3_Cross_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.Cross = function(vector1, vector2)
    return new(Vector3, vector1.Y * vector2.Z - vector1.Z * vector2.Y, vector1.Z * vector2.X - vector1.X * vector2.Z, vector1.X * vector2.Y - vector1.Y * vector2.X)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.reflect?view=netframework-4.7.2#System_Numerics_Vector3_Reflect_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.Reflect = function(vector, normal)
    local dot = vector.X * normal.X + vector.Y * normal.Y + vector.Z * normal.Z
    local tempX = normal.X * dot * 2
    local tempY = normal.Y * dot * 2
    local tempZ = normal.Z * dot * 2
    return new(Vector3, vector.X - tempX, vector.Y - tempY, vector.Z - tempZ)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.clamp?view=netframework-4.7.2#System_Numerics_Vector3_Clamp_System_Numerics_Vector3_System_Numerics_Vector3_System_Numerics_Vector3_
Vector3.Clamp = function(value1, min, max)
    local x = value1.X
    x = (x > max.X) and max.X or x
    x = (x < min.X) and min.X or x

    local y = value1.Y
    y = (y > max.Y) and max.Y or y
    y = (y < min.Y) and min.Y or y

    local z = value1.Z
    z = (z > max.Z) and max.Z or z
    z = (z < min.Z) and min.Z or z

    return new(Vector3, x, y, z)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.lerp?view=netframework-4.7.2#System_Numerics_Vector3_Lerp_System_Numerics_Vector3_System_Numerics_Vector3_System_Single_
Vector3.Lerp = function(value1, value2, amount)
    return new(Vector3, value1.X + (value2.X - value1.X) * amount, value1.Y + (value2.Y - value1.Y) * amount, value1.Z + (value2.Z - value1.Z) * amount)
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.transform?view=netframework-4.7.2#System_Numerics_Vector3_Transform_System_Numerics_Vector3_System_Numerics_Matrix4x4_
-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.transform?view=netframework-4.7.2#System_Numerics_Vector3_Transform_System_Numerics_Vector3_System_Numerics_Quaternion_
Vector3.Transform = function(position, matrix)
    if matrix.X then
        -- quaternion
        local x2 = matrix.X + matrix.X
        local y2 = matrix.Y + matrix.Y
        local z2 = matrix.Z + matrix.Z
  
        local wx2 = matrix.W * x2
        local wy2 = matrix.W * y2
        local wz2 = matrix.W * z2
        local xx2 = matrix.X * x2
        local xy2 = matrix.X * y2
        local xz2 = matrix.X * z2
        local yy2 = matrix.Y * y2
        local yz2 = matrix.Y * z2
        local zz2 = matrix.Z * z2
  
        return new(Vector3, position.X * (1.0 - yy2 - zz2) + position.Y * (xy2 - wz2) + position.Z * (xz2 + wy2), 
                            position.X * (xy2 + wz2) + position.Y * (1.0 - xx2 - zz2) + position.Z * (yz2 - wx2), 
                            position.X * (xz2 - wy2) + position.Y * (yz2 + wx2) + position.Z * (1.0 - xx2 - yy2)
                        )
    else
        -- 4x4 matrix
        return new(Vector3, position.X * matrix.M11 + position.Y * matrix.M21 + position.Z * matrix.M31 + matrix.M41, 
                            position.X * matrix.M12 + position.Y * matrix.M22 + position.Z * matrix.M32 + matrix.M42, 
                            position.X * matrix.M13 + position.Y * matrix.M23 + position.Z * matrix.M33 + matrix.M43
                        ) 
    end 
end

-- https://docs.microsoft.com/en-us/dotnet/api/system.numerics.vector3.transformnormal?view=netframework-4.7.2#System_Numerics_Vector3_TransformNormal_System_Numerics_Vector3_System_Numerics_Matrix4x4_
Vector3.TransformNormal = function(normal, matrix)
    return new(Vector3, normal.X * matrix.M11 + normal.Y * matrix.M21 + normal.Z * matrix.M31,
                        normal.X * matrix.M12 + normal.Y * matrix.M22 + normal.Z * matrix.M32, 
                        normal.X * matrix.M13 + normal.Y * matrix.M23 + normal.Z * matrix.M33
                    )
end

System.defStc("System.Numerics.Vector3", Vector3)

end

-- CoreSystemLib: Numerics/Vector4.lua
do
local System = System
local SystemNumerics = System.Numerics

local abs = math.abs
local min = math.min
local max = math.max
local sqrt = math.sqrt

local IComparable = System.IComparable
local IComparable_1 = System.IComparable_1
local IEquatable_1 = System.IEquatable_1
local IFormattable = System.IFormattable

local new = function (cls, ...)
    local this = setmetatable({}, cls)
    return this, cls.__ctor__(this, ...)
end

local Vector4 = {}

Vector4.__ctor__ = function(this, X, Y, Z, W)
    if W == nil then
        if Z == nil then
            -- 1 var constructor
            if Y == nil then
                this.X = X or 0
                this.Y = X or 0
                this.Z = X or 0
                this.W = X or 0
            else
            -- 2 var constructor
                this.X = X.X
                this.Y = X.Y
                this.Z = X.Z
                this.W = Y or 0
            end
        else
        -- 3 var constructor
        this.X = X.X
        this.Y = X.Y
        this.Z = Y or 0
        this.W = Z or 0
        end
    else
    -- 4 var constructor
        this.X = X or 0
        this.Y = Y or 0
        this.Z = Z or 0
        this.W = W or 0
    end
    local mt = getmetatable(this)
    mt.__unm = Vector4.op_UnaryNegation
    setmetatable(this, mt)
end

Vector4.base = function (_, T)
    return { IComparable, IComparable_1(T), IEquatable_1(T), IFormattable }
end

Vector4.getOne = function() return new(Vector4, 1.0, 1.0, 1.0, 1.0) end
Vector4.getZero = function() return new(Vector4, 0, 0, 0, 0) end
Vector4.getUnitX = function() return new(Vector4, 1.0, 0.0, 0.0, 0.0) end
Vector4.getUnitY = function() return new(Vector4, 0.0, 1.0, 0.0, 0.0) end
Vector4.getUnitZ = function() return new(Vector4, 0.0, 0.0, 1.0, 0.0) end
Vector4.getUnitW = function() return new(Vector4, 0.0, 0.0, 0.0, 1.0) end

Vector4.CopyTo = function(this, array, index)
    if index == nil then
        index = 0
    end

    if array == nil then
        System.throw(System.NullReferenceException())
    end

    if index < 0 or index >= #array then
        System.throw(System.ArgumentOutOfRangeException())
    end
    if (#array - index) < 4 then
        System.throw(System.ArgumentException())
    end

    array:set(index, this.X)
    array:set(index + 1, this.Y)
    array:set(index + 2, this.Z)
    array:set(index + 3, this.W)
end

Vector4.Equals = function(this, other)
    if not (System.is(other, Vector4)) then
        return false
    end
    other = System.cast(Vector4, other)
    return this.X == other.X and this.Y == other.Y and this.Z == other.Z and this.W == other.W
end

Vector4.Dot = function(vector1, vector2)
    return vector1.X * vector2.X + vector1.Y * vector2.Y + vector1.Z * vector2.Z + vector1.W * vector2.W
end

Vector4.Min = function(value1, value2)
    return new(Vector4, (value1.X < value2.X) and value1.X or value2.X, (value1.Y < value2.Y) and value1.Y or value2.Y, (value1.Z < value2.Z) and value1.Z or value2.Z, (value1.W < value2.W) and value1.W or value2.W)
end

Vector4.Max = function(value1, value2)
    return new(Vector4, (value1.X > value2.X) and value1.X or value2.X, (value1.Y > value2.Y) and value1.Y or value2.Y, (value1.Z > value2.Z) and value1.Z or value2.Z, (value1.W > value2.W) and value1.W or value2.W)
end

Vector4.Abs = function(value)
    return new(Vector4, abs(value.X), abs(value.Y), abs(value.Z), abs(value.W))
end

Vector4.SquareRoot = function(value)
    return new(Vector4, System.ToSingle(sqrt(value.X)), System.ToSingle(sqrt(value.Y)), System.ToSingle(sqrt(value.Z)), System.ToSingle(sqrt(value.W)))
end

Vector4.op_Addition = function(left, right)
    return new(Vector4, left.X + right.X, left.Y + right.Y, left.Z + right.Z, left.W + right.W)
end

Vector4.Add = function(left, right)
    return Vector4.op_Addition(left, right)
end

Vector4.op_Subtraction = function(left, right)
    return new(Vector4, left.X - right.X, left.Y - right.Y, left.Z - right.Z, left.W - right.W)
end

Vector4.Subtract = function(left, right)
    return Vector4.op_Subtraction(left, right)
end

Vector4.op_Multiply = function(left, right)
    if type(left) == "number" then
        left = new(Vector4, left)
    end

    if type(right) == "number" then
        right = new(Vector4, right)
    end
    return new(Vector4, left.X * right.X, left.Y * right.Y, left.Z * right.Z, left.W * right.W)
end

Vector4.Multiply = function(left, right)
    return Vector4.op_Multiply(left, right)
end

Vector4.op_Division = function(left, right)
    if type(right) == "number" then
        return Vector4.op_Multiply(left, 1.0 / right)
    end
    return new(Vector4, left.X / right.X, left.Y / right.Y, left.Z / right.Z, left.W / right.W)
end

Vector4.Divide = function(left, right)
    return Vector4.op_Division(left, right)
end

Vector4.op_UnaryNegation = function(value)
    return Vector4.op_Subtraction(Vector4.getZero(), value)
end

Vector4.Negate = function(value)
    return - value
end

Vector4.op_Equality = function(left, right)
    return left.X == right.X and left.Y == right.Y and left.Z == right.Z and left.W == right.W
end

Vector4.op_Inequality = function(left, right)
    return not (Vector4.op_Equality(left, right))
end

Vector4.GetHashCode = function(this)
    local hash = this.X:GetHashCode()
    hash = SystemNumerics.HashCodeHelper.CombineHashCodes(hash, this.Y:GetHashCode())
    hash = SystemNumerics.HashCodeHelper.CombineHashCodes(hash, this.Z:GetHashCode())
    hash = SystemNumerics.HashCodeHelper.CombineHashCodes(hash, this.W:GetHashCode())
      
    return hash
end

Vector4.ToString = function(this)
    local sb = System.StringBuilder()
    local separator = 44 --[[',']]
    sb:AppendChar(60 --[['<']])
    sb:Append((this.X):ToString())
    sb:AppendChar(separator)
    sb:AppendChar(32 --[[' ']])
    sb:Append((this.Y):ToString())
    sb:AppendChar(separator)
    sb:AppendChar(32 --[[' ']])
    sb:Append((this.Z):ToString())
    sb:AppendChar(separator)
    sb:AppendChar(32 --[[' ']])
    sb:Append((this.W):ToString())
    sb:AppendChar(62 --[['>']])
    return sb:ToString()
end

Vector4.Length = function(this)
    local ls = this.X * this.X + this.Y * this.Y + this.Z * this.Z + this.W * this.W
    return System.ToSingle(sqrt(ls))
end

Vector4.LengthSquared = function(this)
    return this.X * this.X + this.Y * this.Y + this.Z * this.Z + this.W * this.W
end

Vector4.Distance = function(value1, value2)
    local dx = value1.X - value2.X
    local dy = value1.Y - value2.Y
    local dz = value1.Z - value2.Z
    local dw = value1.W - value2.W

    local ls = dx * dx + dy * dy + dz * dz + dw * dw

    return System.ToSingle(sqrt(ls))
end

Vector4.DistanceSquared = function(value1, value2)
    local dx = value1.X - value2.X
    local dy = value1.Y - value2.Y
    local dz = value1.Z - value2.Z
    local dw = value1.W - value2.W

    return dx * dx + dy * dy + dz * dz + dw * dw
end

Vector4.Normalize = function(vector)
    local ls = vector.X * vector.X + vector.Y * vector.Y + vector.Z * vector.Z + vector.W * vector.W
    local invNorm = 1.0 / System.ToSingle(sqrt(ls))

    return new(Vector4, vector.X * invNorm, vector.Y * invNorm, vector.Z * invNorm, vector.W * invNorm)
end

Vector4.Clamp = function(value1, min, max)
    local x = value1.X
    x = (x > max.X) and max.X or x
    x = (x < min.X) and min.X or x

    local y = value1.Y
    y = (y > max.Y) and max.Y or y
    y = (y < min.Y) and min.Y or y

    local z = value1.Z
    z = (z > max.Z) and max.Z or z
    z = (z < min.Z) and min.Z or z

    local w = value1.W
    w = (w > max.W) and max.W or w
    w = (w < min.W) and min.W or w

    return new(Vector4, x, y, z, w)
end

Vector4.Lerp = function(value1, value2, amount)
    return new(Vector4, value1.X + (value2.X - value1.X) * amount, value1.Y + (value2.Y - value1.Y) * amount, value1.Z + (value2.Z - value1.Z) * amount, value1.W + (value2.W - value1.W) * amount)
end

Vector4.Transform = function(position, matrix)
    if matrix.X == nil then
        -- 4x4 matrix
        if matrix.W == nil then
            if matrix.Z == nil then
                -- vector2
                return new(Vector4, position.X * matrix.M11 + position.Y * matrix.M21 + matrix.M41, 
                                    position.X * matrix.M12 + position.Y * matrix.M22 + matrix.M42,
                                    position.X * matrix.M13 + position.Y * matrix.M23 + matrix.M43, 
                                    position.X * matrix.M14 + position.Y * matrix.M24 + matrix.M44
                                )
            else
                -- vector3
                return new(Vector4, position.X * matrix.M11 + position.Y * matrix.M21 + position.Z * matrix.M31 + matrix.M41, 
                                    position.X * matrix.M12 + position.Y * matrix.M22 + position.Z * matrix.M32 + matrix.M42, 
                                    position.X * matrix.M13 + position.Y * matrix.M23 + position.Z * matrix.M33 + matrix.M43, 
                                    position.X * matrix.M14 + position.Y * matrix.M24 + position.Z * matrix.M34 + matrix.M44
                                )
            end
        else
            -- vector4
            return new(Vector4, position.X * matrix.M11 + position.Y * matrix.M21 + position.Z * matrix.M31 + position.W * matrix.M41, 
                                position.X * matrix.M12 + position.Y * matrix.M22 + position.Z * matrix.M32 + position.W * matrix.M42,
                                position.X * matrix.M13 + position.Y * matrix.M23 + position.Z * matrix.M33 + position.W * matrix.M43, 
                                position.X * matrix.M14 + position.Y * matrix.M24 + position.Z * matrix.M34 + position.W * matrix.M44
                            )
        end
    else
        -- quaternion
        if matrix.W == nil then
            if matrix.Z == nil then
                -- vector2
                local x2 = matrix.X + matrix.X
                local y2 = matrix.Y + matrix.Y
                local z2 = matrix.Z + matrix.Z

                local wx2 = matrix.W * x2
                local wy2 = matrix.W * y2
                local wz2 = matrix.W * z2
                local xx2 = matrix.X * x2
                local xy2 = matrix.X * y2
                local xz2 = matrix.X * z2
                local yy2 = matrix.Y * y2
                local yz2 = matrix.Y * z2
                local zz2 = matrix.Z * z2

                return new(Vector4, position.X * (1.0 - yy2 - zz2) + position.Y * (xy2 - wz2), 
                                    position.X * (xy2 + wz2) + position.Y * (1.0 - xx2 - zz2), 
                                    position.X * (xz2 - wy2) + position.Y * (yz2 + wx2), 
                                    1.0
                                )
            else
                -- vector3
                local x2 = matrix.X + matrix.X
                local y2 = matrix.Y + matrix.Y
                local z2 = matrix.Z + matrix.Z

                local wx2 = matrix.W * x2
                local wy2 = matrix.W * y2
                local wz2 = matrix.W * z2
                local xx2 = matrix.X * x2
                local xy2 = matrix.X * y2
                local xz2 = matrix.X * z2
                local yy2 = matrix.Y * y2
                local yz2 = matrix.Y * z2
                local zz2 = matrix.Z * z2

                return new(Vector4, position.X * (1.0 - yy2 - zz2) + position.Y * (xy2 - wz2) + position.Z * (xz2 + wy2), 
                                    position.X * (xy2 + wz2) + position.Y * (1.0 - xx2 - zz2) + position.Z * (yz2 - wx2), 
                                    position.X * (xz2 - wy2) + position.Y * (yz2 + wx2) + position.Z * (1.0 - xx2 - yy2), 
                                    1.0
                                )
            end
        else
            -- vector4
            local x2 = matrix.X + matrix.X
            local y2 = matrix.Y + matrix.Y
            local z2 = matrix.Z + matrix.Z

            local wx2 = matrix.W * x2
            local wy2 = matrix.W * y2
            local wz2 = matrix.W * z2
            local xx2 = matrix.X * x2
            local xy2 = matrix.X * y2
            local xz2 = matrix.X * z2
            local yy2 = matrix.Y * y2
            local yz2 = matrix.Y * z2
            local zz2 = matrix.Z * z2

            return new(Vector4, position.X * (1.0 - yy2 - zz2) + position.Y * (xy2 - wz2) + position.Z * (xz2 + wy2), 
                                position.X * (xy2 + wz2) + position.Y * (1.0 - xx2 - zz2) + position.Z * (yz2 - wx2), 
                                position.X * (xz2 - wy2) + position.Y * (yz2 + wx2) + position.Z * (1.0 - xx2 - yy2), 
                                position.W
                            )
        end
    end
end

System.defStc("System.Numerics.Vector4", Vector4)

end

-- Generated by CSharp.lua Compiler
do
local System = System
local types
System.import(function (out)
  types = out.types
end)
System.namespace("", function (namespace)
  namespace.class("Bunnymark_GUI", function (namespace)
    local init, on_message, on_input, Load
    init = function (this)
      math.randomseed(os.clock())
      this:RequestInput()

      local dataTable = {}
      dataTable["color"] = vmath.vector4(0.4,0.5,0.8,1)
      msg.post("@render:","clear_color",dataTable)

      this._menuEnabled = true


      this.test_root_node = gui.get_node(hash("test_root"))
      this.toggle_profiler_node = gui.get_node(hash("toggle_profiler"))
      this.back_node = gui.get_node(hash("back"))
      gui.set_enabled(this.test_root_node, false)

      this.menu_root_node = gui.get_node(hash("menu_root"))
      this.go_animate_node = gui.get_node(hash("go_animate"))
      this.go_animate_multiple_node = gui.get_node(hash("go_animate_multiple"))
      this.update_single_node = gui.get_node(hash("update_single"))
      this.update_many_node = gui.get_node(hash("update_many"))
      this.particlefx_node = gui.get_node(hash("particlefx"))
      this.gui_animate_node = gui.get_node(hash("gui_animate"))



      local version = (sys.get_engine_info()).version
      this:GetNode1(hash("version"), types.TextNode):SetText(version)
    end
    on_message = function (this, message_id, message, sender)
      if message_id == hash("proxy_loaded") then
        msg.post(sender, "enable")
        this._menuEnabled = false
        gui.set_enabled(this.test_root_node, true)
        gui.set_enabled(this.menu_root_node, false)
      elseif message_id == hash("proxy_unloaded") then
        this._menuEnabled = true
        gui.set_enabled(this.test_root_node, false)
        gui.set_enabled(this.menu_root_node, true)
      end
    end
    on_input = function (this, action_id, action)
      if action_id == hash("touch") and action.released then
        if this._menuEnabled then
          if gui.pick_node(this.go_animate_node, action.x, action.y) then
            Load(this, "#go_animate_proxy")
          elseif gui.pick_node(this.update_single_node, action.x, action.y) then
            Load(this, "#update_single_proxy")
          elseif gui.pick_node(this.update_many_node, action.x, action.y) then
            Load(this, "#update_many_proxy")
          elseif gui.pick_node(this.particlefx_node, action.x, action.y) then
            Load(this, "#particlefx_proxy")
          elseif gui.pick_node(this.go_animate_multiple_node, action.x, action.y) then
            Load(this, "#go_animate_multiple_proxy")
          elseif gui.pick_node(this.gui_animate_node, action.x, action.y) then
            Load(this, "#gui_animate_proxy")
          end
        else
          if gui.pick_node(this.back_node, action.x, action.y) then
            msg.post(this._currentProxy, "unload")
          elseif gui.pick_node(this.toggle_profiler_node, action.x, action.y) then
            msg.post("@system:", "toggle_profile")
          end
        end
      end

      return false
    end
    Load = function (this, proxy_url)
      msg.post(proxy_url, "load")
      this._currentProxy = proxy_url
    end
    return {
      base = function (out)
        return {
          out.support.GUIScript
        }
      end,
      _menuEnabled = false,
      init = init,
      on_message = on_message,
      on_input = on_input,
      __metadata__ = function (out)
        return {
          fields = {
            { "FPS_node", 0x1, out.types.Node },
            { "_currentProxy", 0x1, System.String },
            { "_menuEnabled", 0x1, System.Boolean },
            { "back_node", 0x1, out.types.Node },
            { "go_animate_multiple_node", 0x1, out.types.Node },
            { "go_animate_node", 0x1, out.types.Node },
            { "gui_animate_node", 0x1, out.types.Node },
            { "menu_root_node", 0x1, out.types.Node },
            { "particlefx_node", 0x1, out.types.Node },
            { "test_root_node", 0x1, out.types.Node },
            { "toggle_profiler_node", 0x1, out.types.Node },
            { "update_many_node", 0x1, out.types.Node },
            { "update_single_node", 0x1, out.types.Node }
          },
          methods = {
            { "Load", 0x101, Load, System.String },
            { "init", 0x3, init },
            { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean },
            { "on_message", 0x303, on_message, out.types.Hash, System.Object, out.types.Hash }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("", function (namespace)
  namespace.class("Bunny_Update", function (namespace)
    local init, update, __ctor__
    __ctor__ = function (this)
      this.velocity = - math.random(100)
      System.base(this).__ctor__(this)
    end
    init = function (this)
      this:getGameobject():setPosition(vmath.vector3(math.random(640),math.random(1000, 1100),0))
    end
    update = function (this, dt)
      support.GameObjectReference.CurrentGameObject = this:getGameobject()
      this.velocity = this.velocity - (1200 * dt)

      local pos = this:getGameobject():getPosition()
      pos.y = pos.y + this.velocity * dt
      if pos.y < 60 then
        this.velocity = - this.velocity
        pos.y = 60
      end

      this:getGameobject():setPosition(pos)
      support.GameObjectReference.CurrentGameObject = nil
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript
        }
      end,
      init = init,
      update = update,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "velocity", 0x1, System.Double }
          },
          methods = {
            { "init", 0x3, init },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local ArrayDouble = System.Array(System.Double)
System.namespace("", function (namespace)
  namespace.class("FPSProperties", function (namespace)
    return {
      base = function (out)
        return {
          out.support.AnimatableProperties
        }
      end,
      sampleCount = 60,
      __metadata__ = function (out)
        return {
          fields = {
            { "sampleCount", 0x6, System.Int32 }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)
System.namespace("", function (namespace)
  namespace.class("FPS", function (namespace)
    local init, update, class
    namespace.class("SimpleMovingAverage", function (namespace)
      local Update, __ctor__
      __ctor__ = function (this, k)
        this._k = System.toInt32(k)
        this._values = ArrayDouble(k)
      end
      Update = function (this, nextInput)
        -- calculate the new sum
        this._sum = this._sum - this._values:get(this._index) + nextInput

        -- overwrite the old value with the new one
        this._values:set(this._index, nextInput)

        -- increment the index (wrapping back to 0)
        this._index = System.mod((this._index + 1), this._k)

        -- calculate the average
        return this._sum / this._k
      end
      return {
        _k = 0,
        _index = 0,
        _sum = 0,
        Update = Update,
        __ctor__ = __ctor__,
        __metadata__ = function (out)
          return {
            fields = {
              { "_index", 0x1, System.Int32 },
              { "_k", 0x1, System.Int32 },
              { "_sum", 0x1, System.Double },
              { "_values", 0x1, System.Array(System.Double) }
            },
            methods = {
              { ".ctor", 0x106, nil, System.UInt32 },
              { "Update", 0x186, Update, System.Double, System.Double }
            },
            class = { 0x6 }
          }
        end
      }
    end)
    init = function (this)
      this.sma = class.SimpleMovingAverage(60)
    end
    update = function (this, dt)
      class.Fps = 1 / this.sma:Update(dt)
      class.LowFPS = class.Fps < 60
    end
    class = {
      base = function (out)
        return {
          out.support.GameObjectScript_1(out.FPSProperties)
        }
      end,
      LowFPS = false,
      Fps = 0,
      init = init,
      update = update,
      __metadata__ = function (out)
        return {
          fields = {
            { "sma", 0x1, class.SimpleMovingAverage }
          },
          properties = {
            { "Fps", 0xE, System.Double },
            { "LowFPS", 0xE, System.Boolean }
          },
          methods = {
            { "init", 0x3, init },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("GoBunny", function (namespace)
    local __ctor__
    __ctor__ = function (this, url1)
      this.url = url1
    end
    return {
      Velocity = 0,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "Position", 0x6, out.types.Vector3 },
            { "Velocity", 0x6, System.Double },
            { "url", 0x6, out.types.Url }
          },
          methods = {
            { ".ctor", 0x106, nil, out.types.Url }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("GuiAnimateGui", function (namespace)
    local init
    init = function (this)
      Bunnymark.CurrentInstance:Spawn(500)
    end
    return {
      base = function (out)
        return {
          out.support.GUIScript
        }
      end,
      init = init,
      __metadata__ = function (out)
        return {
          methods = {
            { "init", 0x3, init }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("GuiBunny", function (namespace)
    local __ctor__
    __ctor__ = function (this, node)
      this.node = node
    end
    return {
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "node", 0x6, out.types.Node }
          },
          methods = {
            { ".ctor", 0x106, nil, out.types.Node }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Buffer API documentation
  -- 
  -- </summary>
  namespace.class("Buffer", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Built-ins API documentation
  -- 
  -- </summary>
  namespace.class("Builtins", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Camera API documentation
  -- 
  -- </summary>
  namespace.class("Camera", function (namespace)
    -- <summary>
    -- </summary>
    namespace.class("set_camera_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("set_camera")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        aspect_ratio = 0,
        fov = 0,
        near_z = 0,
        far_z = 0,
        orthographic_projection = false,
        orthographic_zoom = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "aspect_ratio", 0x6, System.Double },
              { "far_z", 0x6, System.Double },
              { "fov", 0x6, System.Double },
              { "near_z", 0x6, System.Double },
              { "orthographic_projection", 0x6, System.Boolean },
              { "orthographic_zoom", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("acquire_camera_focus_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("acquire_camera_focus")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("release_camera_focus_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("release_camera_focus")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("", function (namespace)
  -- <summary>
  -- Collection factory API documentation
  -- 
  -- </summary>
  namespace.class("CollectionFactory", function (namespace)
    local getStatus, Create, Create1, Create2, Create3
    namespace.struct("CollectionFactoryCreateResult", function (namespace)
      local __ctor1__, __ctor2__
      __ctor1__ = function (this)
      end
      __ctor2__ = function (this, relativeHash, uniqueHash)
        this.RelativeHash = relativeHash
        this.UniqueHash = uniqueHash
      end
      return {
        __ctor__ = {
          __ctor1__,
          __ctor2__
        },
        __metadata__ = function (out)
          return {
            fields = {
              { "RelativeHash", 0x6, out.types.Hash },
              { "UniqueHash", 0x6, out.types.Hash }
            },
            methods = {
              { ".ctor", 0x206, __ctor2__, out.types.Hash, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
    end)
    getStatus = function (this)
      return collectionfactory.get_status(support.BuiltInComponentBase.op_Implicit(this))
    end
    Create = function (this)
      return collectionfactory.create(support.BuiltInComponentBase.op_Implicit(this))
    end
    Create1 = function (this, position)
      return collectionfactory.create(support.BuiltInComponentBase.op_Implicit(this), position)
    end
    Create2 = function (this, position, rotation)
      return collectionfactory.create(support.BuiltInComponentBase.op_Implicit(this), position, rotation)
    end
    Create3 = function (this, position, rotation, properties)
      return collectionfactory.create(support.BuiltInComponentBase.op_Implicit(this), position, rotation, properties)
    end
    return {
      base = function (out)
        return {
          out.support.BuiltInComponentBase
        }
      end,
      getStatus = getStatus,
      Create = Create,
      Create1 = Create1,
      Create2 = Create2,
      Create3 = Create3,
      __metadata__ = function (out)
        return {
          properties = {
            { "Status", 0x206, System.Int32, getStatus }
          },
          methods = {
            { "Create", 0x86, Create, out.types.LuaTableOf_2(out.types.Hash, out.types.Hash) },
            { "Create", 0x186, Create1, out.types.Vector3, out.types.LuaTableOf_2(out.types.Hash, out.types.Hash) },
            { "Create", 0x286, Create2, out.types.Vector3, out.types.Quaternion, out.types.LuaTableOf_2(out.types.Hash, out.types.Hash) },
            { "Create", 0x386, Create3, out.types.Vector3, out.types.Quaternion, out.types.ILuaTable, out.types.LuaTableOf_2(out.types.Hash, out.types.Hash) }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("", function (namespace)
  -- <summary>
  -- Collection proxy API documentation
  -- 
  -- </summary>
  namespace.class("CollectionProxy", function (namespace)
    local Load, LoadAsync, Init, Enable, Disable, Final, Unload, SetTimeStep, 
    class
    -- <summary>
    -- </summary>
    namespace.class("set_time_step_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("set_time_step")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        factor = 0,
        mode = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "factor", 0x6, System.Double },
              { "mode", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("load_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("load")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("async_load_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("async_load")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("proxy_loaded_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("proxy_loaded")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("init_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("init")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("enable_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("enable")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("disable_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("disable")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("final_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("final")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("unload_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("unload")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("proxy_unloaded_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("proxy_unloaded")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- Posts a load message to the collection-proxy-component to start the loading of the referenced collection. When the loading has completed, the message proxy_loaded will be sent back to the script. A loaded collection must be initialized (message init) and enabled (message enable) in order to be simulated and drawn.
    -- </summary>
    Load = function (this)
      local message = class.load_message()
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    -- <summary>
    -- Posts a async_load message to a collection-proxy-component to start background loading of the referenced collection. When the loading has completed, the message proxy_loaded will be sent back to the script. A loaded collection must be initialized (message init) and enabled (message enable) in order to be simulated and drawn.
    -- </summary>
    LoadAsync = function (this)
      local message = class.async_load_message()
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    -- <summary>
    -- Post this message to a collection-proxy-component to initialize the game objects and components in the referenced collection. Sending enable to an uninitialized collection proxy automatically initializes it. The init message simply provides a higher level of control.
    -- </summary>
    Init = function (this)
      local message = class.init_message()
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    -- <summary>
    -- Post this message to a collection-proxy-component to enable the referenced collection, which in turn enables the contained game objects and components. If the referenced collection was not initialized prior to this call, it will automatically be initialized.
    -- </summary>
    Enable = function (this)
      local message = class.enable_message()
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    -- <summary>
    -- Post this message to a collection-proxy-component to disable the referenced collection, which in turn disables the contained game objects and components.
    -- </summary>
    Disable = function (this)
      local message = class.disable_message()
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    -- <summary>
    -- Post this message to a collection-proxy-component to finalize the referenced collection, which in turn finalizes the contained game objects and components.
    -- </summary>
    Final = function (this)
      local message = class.final_message()
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    -- <summary>
    -- Post this message to a collection-proxy-component to start the unloading of the referenced collection. When the unloading has completed, the message proxy_unloaded will be sent back to the script.
    -- </summary>
    Unload = function (this)
      local message = class.unload_message()
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    -- <summary>
    -- Post this message to a collection-proxy-component to modify the time-step used when updating the collection controlled by the proxy. The time-step is modified by a scaling factor and can be incremented either continuously or in discrete steps. The continuous mode can be used for slow-motion or fast-forward effects. The discrete mode is only useful when scaling the time-step to pass slower than real time (factor is below 1). The time-step will then be set to 0 for as many frames as the scaling demands and then take on the full real-time-step for one frame, to simulate pulses. E.g. if factor is set to 0.1 the time-step would be 0 for 9 frames, then be 1/60 for one frame, 0 for 9 frames, and so on. The result in practice is that the game looks like it's updated at a much lower frequency than 60 Hz, which can be useful for debugging when each frame needs to be inspected.
    -- </summary>
    -- <param name="factor"></param>
    -- <param name="mode"></param>
    SetTimeStep = function (this, factor, mode)
      local default = class.set_time_step_message()
      default.factor = factor
      default.mode = mode
      local message = default
      Message.postMessage5(support.BuiltInComponentBase.op_Implicit(this), message)
    end
    class = {
      base = function (out)
        return {
          out.support.BuiltInComponentBase
        }
      end,
      Load = Load,
      LoadAsync = LoadAsync,
      Init = Init,
      Enable = Enable,
      Disable = Disable,
      Final = Final,
      Unload = Unload,
      SetTimeStep = SetTimeStep,
      __metadata__ = function (out)
        return {
          methods = {
            { "Disable", 0x6, Disable },
            { "Enable", 0x6, Enable },
            { "Final", 0x6, Final },
            { "Init", 0x6, Init },
            { "Load", 0x6, Load },
            { "LoadAsync", 0x6, LoadAsync },
            { "SetTimeStep", 0x206, SetTimeStep, System.Double, System.Int32 },
            { "Unload", 0x6, Unload }
          },
          class = { 0x6 }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Crash API documentation
  -- 
  -- </summary>
  namespace.class("Crash", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("Debug", function (namespace)
    local _hook, _mask, _count, _debuggingEnabled, SetEditorDebug, ToggleEditorDebug, static
    static = function (this)
      if sys.get_engine_info().is_debug then
        _debuggingEnabled = true

        local default
        default, _mask, _count = debug.gethook()
        _hook = default
      end
    end
    _debuggingEnabled = true
    SetEditorDebug = function (shouldDebug)
      if not sys.get_engine_info().is_debug then
        return
      end

      if shouldDebug then
        debug.sethook(_hook,_mask,_count)
        _debuggingEnabled = true
      else
        debug.sethook()
        _debuggingEnabled = false
      end
    end
    ToggleEditorDebug = function ()
      if not sys.get_engine_info().is_debug then
        return false
      end

      SetEditorDebug(not _debuggingEnabled)
      return _debuggingEnabled
    end
    return {
      SetEditorDebug = SetEditorDebug,
      ToggleEditorDebug = ToggleEditorDebug,
      static = static,
      __metadata__ = function (out)
        return {
          fields = {
            { "_count", 0x9, System.Object },
            { "_debuggingEnabled", 0x9, System.Boolean },
            { "_hook", 0x9, System.Object },
            { "_mask", 0x9, System.Object }
          },
          methods = {
            { "SetEditorDebug", 0x10E, SetEditorDebug, System.Boolean },
            { "ToggleEditorDebug", 0x8E, ToggleEditorDebug, System.Boolean }
          },
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Facebook API documentation
  -- 
  -- </summary>
  namespace.class("Facebook", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("", function (namespace)
  -- <summary>
  -- Factory API documentation
  -- 
  -- </summary>
  namespace.class("Factory", function (namespace)
    local getStatus, Unload, Load, Load1, Create, Create1, Create2, Create3, 
    Create4, class
    getStatus = function (this)
      return factory.get_status(support.BuiltInComponentBase.op_Implicit(this))
    end
    -- <summary>
    -- This decreases the reference count for each resource loaded with factory.load. If reference is zero, the resource is destroyed.
    -- Calling this function when the factory is not marked as dynamic loading does nothing.
    -- </summary>
    Unload = function (this)
      factory.unload(support.BuiltInComponentBase.op_Implicit(this))
    end
    -- <summary>
    -- Resources are referenced by the factory component until the existing (parent) collection is destroyed or factory.unload is called.
    -- Calling this function when the factory is not marked as dynamic loading does nothing.
    -- </summary>
    Load = function (this)
      factory.load(support.BuiltInComponentBase.op_Implicit(this))
    end
    Load1 = function (this, callback)
      local function IntermediateCallback(obj, url, b) 
        callback(obj, this, b)
      end

      factory.load(support.BuiltInComponentBase.op_Implicit(this), IntermediateCallback)
    end
    Create = function (this)
      return factory.create(support.BuiltInComponentBase.op_Implicit(this))
    end
    Create1 = function (this, position)
      return factory.create(support.BuiltInComponentBase.op_Implicit(this), position)
    end
    Create2 = function (this, position, rotation)
      return factory.create(support.BuiltInComponentBase.op_Implicit(this), position, rotation)
    end
    Create3 = function (this, position, rotation, properties)
      return factory.create(support.BuiltInComponentBase.op_Implicit(this), position, rotation, properties)
    end
    Create4 = function (this, position, rotation, properties, scale)
      return factory.create(support.BuiltInComponentBase.op_Implicit(this), position, rotation, properties, scale)
    end
    class = {
      base = function (out)
        return {
          out.support.BuiltInComponentBase
        }
      end,
      getStatus = getStatus,
      Unload = Unload,
      Load = Load,
      Load1 = Load1,
      Create = Create,
      Create1 = Create1,
      Create2 = Create2,
      Create3 = Create3,
      Create4 = Create4,
      __metadata__ = function (out)
        return {
          properties = {
            { "Status", 0x206, System.Int32, getStatus }
          },
          methods = {
            { "Create", 0x86, Create, out.types.Hash },
            { "Create", 0x186, Create1, out.types.Vector3, out.types.Hash },
            { "Create", 0x286, Create2, out.types.Vector3, out.types.Quaternion, out.types.Hash },
            { "Create", 0x386, Create3, out.types.Vector3, out.types.Quaternion, out.types.ILuaTable, out.types.Hash },
            { "Create", 0x486, Create4, out.types.Vector3, out.types.Quaternion, out.types.ILuaTable, System.Double, out.types.Hash },
            { "Load", 0x6, Load },
            { "Load", 0x106, Load1, System.Delegate(System.Object, class, System.Boolean, System.Void) },
            { "Unload", 0x6, Unload }
          },
          class = { 0x6 }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Game object API documentation
  -- 
  -- </summary>
  namespace.class("Go", function (namespace)
    -- <summary>
    -- </summary>
    namespace.class("acquire_input_focus_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("acquire_input_focus")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("release_input_focus_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("release_input_focus")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("set_parent_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("set_parent")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        keep_world_transform = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "keep_world_transform", 0x6, System.Double },
              { "parent_id", 0x6, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("enable_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("enable")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("disable_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("disable")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- GUI API documentation
  -- 
  -- </summary>
  namespace.class("Gui", function (namespace)
    local GetNode1
    -- <summary>
    -- </summary>
    namespace.class("layout_changed_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("layout_changed")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "id", 0x6, out.types.Hash },
              { "previous_id", 0x6, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    GetNode1 = function (id, TNode)
      local node = TNode()
      node:__assignproxy__(gui.get_node(id))
      return node
    end
    return {
      GetNode1 = GetNode1,
      __metadata__ = function (out)
        return {
          methods = {
            { "GetNode", 0x1018E, GetNode1, function (TNode) return out.types.Hash, TNode end }
          },
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- HTML5 API documentation
  -- 
  -- </summary>
  namespace.class("Html5", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- HTTP API documentation
  -- 
  -- </summary>
  namespace.class("Http", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Inter-app communication API documentation
  -- 
  -- </summary>
  namespace.class("Iac", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- In-app purchases API documentation
  -- 
  -- </summary>
  namespace.class("Iap", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Image API documentation
  -- 
  -- </summary>
  namespace.class("Image", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- JSON API documentation
  -- 
  -- </summary>
  namespace.class("Json", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Label API documentation
  -- 
  -- </summary>
  namespace.class("Label", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Lua math standard library
  -- 
  -- </summary>
  namespace.class("Math", function (namespace)
    local Huge, PI, TAU, static
    static = function (this)
      Huge = math.huge
      this.Huge = Huge
      PI = math.pi
      this.PI = PI
      TAU = (2*math.pi)
      this.TAU = TAU
    end
    return {
      static = static,
      __metadata__ = function (out)
        return {
          fields = {
            { "Huge", 0xE, System.Double }
          },
          properties = {
            { "PI", 0xE, System.Double },
            { "TAU", 0xE, System.Double }
          },
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
local types
local DictTypeHash
System.import(function (out)
  support = out.support
  types = out.types
  DictTypeHash = System.Dictionary(System.Type, types.Hash)
end)
System.namespace("", function (namespace)
  namespace.class("Message", function (namespace)
    local typeToHashLookup, postMessage, postMessage1, postMessage2, postMessage3, postMessage4, postMessage5, IsMessage, 
    IsMessage1, static
    static = function (this)
      typeToHashLookup = DictTypeHash()
    end
    postMessage = function (id, code, data)
      msg.post(id,code,data:ToTable())
    end
    postMessage1 = function (id, code, data)
      msg.post(id,code,data:ToTable())
    end
    postMessage2 = function (id, code, data)
      msg.post(id,code,data:ToTable())
    end
    postMessage3 = function (id, message)
      msg.post(id,message:FetchCode(),message:ToTable())
    end
    postMessage4 = function (id, message)
      msg.post(id,message:FetchCode(),message:ToTable())
    end
    postMessage5 = function (id, message)
      msg.post(id,message:FetchCode(),message:ToTable())
    end
    IsMessage = function (message_id, message, expectedCode, messageImpl, T)
      if message_id == expectedCode then
        messageImpl = message
        return true, messageImpl
      end


      messageImpl = message
      return false, messageImpl
    end
    IsMessage1 = function (message_id, message, messageImpl, reconstructMetadata, T)
      local default, hash = typeToHashLookup:TryGetValue(System.typeof(T), nil)
      if not default then
        local dummy = T()
        hash = dummy:FetchCode()
        typeToHashLookup:AddKeyValue(System.typeof(T), hash)
      end

      if hash == message_id then
        if reconstructMetadata then
          messageImpl = support.LuaTableSerializableExt.DefaultTableDeserialization(message, T)
        else
          messageImpl = message
        end

        return true, messageImpl
      end


      messageImpl = message
      return false, messageImpl
    end
    return {
      postMessage = postMessage,
      postMessage1 = postMessage1,
      postMessage2 = postMessage2,
      postMessage3 = postMessage3,
      postMessage4 = postMessage4,
      postMessage5 = postMessage5,
      IsMessage = IsMessage,
      IsMessage1 = IsMessage1,
      static = static,
      __metadata__ = function (out)
        return {
          fields = {
            { "typeToHashLookup", 0x9, System.Dictionary(System.Type, out.types.Hash) }
          },
          methods = {
            { "IsMessage", 0x1048E, IsMessage, function (T) return out.types.Hash, System.Object, out.types.Hash, T, System.Boolean end },
            { "IsMessage", 0x1048E, IsMessage1, function (T) return out.types.Hash, System.Object, T, System.Boolean, System.Boolean end },
            { "postMessage", 0x30E, postMessage, System.String, System.String, out.types.ILuaTableSerializable },
            { "postMessage", 0x30E, postMessage1, out.types.Url, System.String, out.types.ILuaTableSerializable },
            { "postMessage", 0x30E, postMessage2, out.types.Hash, System.String, out.types.ILuaTableSerializable },
            { "postMessage", 0x20E, postMessage3, System.String, out.MessageImplementation },
            { "postMessage", 0x20E, postMessage4, out.types.Hash, out.MessageImplementation },
            { "postMessage", 0x20E, postMessage5, out.types.Url, out.MessageImplementation }
          },
          class = { 0xE }
        }
      end
    }
  end)
end)
System.namespace("", function (namespace)
  namespace.class("MessageImplementation", function (namespace)
    local ToTable
    ToTable = function (this)
      return support.LuaTableSerializableExt.DefaultTableSerialization(this)
    end
    return {
      base = function (out)
        return {
          out.types.ILuaTableSerializable
        }
      end,
      ToTable = ToTable,
      __metadata__ = function (out)
        return {
          methods = {
            { "ToTable", 0x86, ToTable, out.types.ILuaTable }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Model API documentation
  -- 
  -- </summary>
  namespace.class("Model", function (namespace)
    -- <summary>
    -- </summary>
    namespace.class("model_animation_done_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("model_animation_done")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "animation_id", 0x6, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Messaging API documentation
  -- 
  -- </summary>
  namespace.class("Msg", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("OS", function (namespace)
    local Shutdown
    -- <summary>
    -- Safely shuts the game down.  Use exit() if an immediate force exit is needed
    -- </summary>
    Shutdown = function ()
      msg.post("@system:", "exit", {code = 0})
    end
    return {
      Shutdown = Shutdown,
      __metadata__ = function (out)
        return {
          methods = {
            { "Shutdown", 0xE, Shutdown }
          },
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Particle effects API documentation
  -- 
  -- </summary>
  namespace.class("Particlefx", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Collision object physics API documentation
  -- 
  -- </summary>
  namespace.class("Physics", function (namespace)
    -- <summary>
    -- </summary>
    namespace.class("apply_force_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("apply_force")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "force", 0x6, out.types.Vector3 },
              { "position", 0x6, out.types.Vector3 }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("collision_response_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("collision_response")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "other_group", 0x6, out.types.Hash },
              { "other_id", 0x6, out.types.Hash },
              { "other_position", 0x6, out.types.Vector3 },
              { "own_group", 0x6, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("contact_point_response_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("contact_point_response")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        distance = 0,
        applied_impulse = 0,
        life_time = 0,
        mass = 0,
        other_mass = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "applied_impulse", 0x6, System.Double },
              { "distance", 0x6, System.Double },
              { "life_time", 0x6, System.Double },
              { "mass", 0x6, System.Double },
              { "normal", 0x6, out.types.Vector3 },
              { "other_group", 0x6, out.types.Hash },
              { "other_id", 0x6, out.types.Hash },
              { "other_mass", 0x6, System.Double },
              { "other_position", 0x6, out.types.Vector3 },
              { "own_group", 0x6, out.types.Hash },
              { "position", 0x6, out.types.Vector3 },
              { "relative_velocity", 0x6, out.types.Vector3 }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("trigger_response_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("trigger_response")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        enter = false,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "enter", 0x6, System.Boolean },
              { "other_group", 0x6, out.types.Hash },
              { "other_id", 0x6, out.types.Hash },
              { "own_group", 0x6, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("ray_cast_response_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("ray_cast_response")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        fraction = 0,
        request_id = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "fraction", 0x6, System.Double },
              { "group", 0x6, out.types.Hash },
              { "id", 0x6, out.types.Hash },
              { "normal", 0x6, out.types.Vector3 },
              { "position", 0x6, out.types.Vector3 },
              { "request_id", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("ray_cast_missed_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("ray_cast_missed")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        request_id = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "request_id", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Profiler API documentation
  -- 
  -- </summary>
  namespace.class("Profiler", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Push notifications API documentation
  -- 
  -- </summary>
  namespace.class("Push", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Rendering API documentation
  -- 
  -- </summary>
  namespace.class("Render", function (namespace)
    -- <summary>
    -- </summary>
    namespace.class("draw_debug_text_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("draw_debug_text")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "color", 0x6, out.types.Vector4 },
              { "position", 0x6, out.types.Vector3 },
              { "text", 0x6, System.String }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("draw_line_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("draw_line")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "color", 0x6, out.types.Vector4 },
              { "end_point", 0x6, out.types.Vector3 },
              { "start_point", 0x6, out.types.Vector3 }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("window_resized_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("window_resized")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        height = 0,
        width = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "height", 0x6, System.Double },
              { "width", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("resize_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("resize")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        height = 0,
        width = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "height", 0x6, System.Double },
              { "width", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("clear_color_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("clear_color")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "color", 0x6, out.types.Vector4 }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Resource API documentation
  -- 
  -- </summary>
  namespace.class("Resource", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("", function (namespace)
  -- <summary>
  -- Sound API documentation
  -- 
  -- </summary>
  namespace.class("Sound", function (namespace)
    local Play, Play1, Play2, Play3, Play4, Play5, Stop, Pause, 
    Unpause, SetGain, SetPan, class
    -- <summary>
    -- </summary>
    namespace.class("play_sound_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("play_sound")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        delay = 0,
        gain = 0,
        play_id = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "delay", 0x6, System.Double },
              { "gain", 0x6, System.Double },
              { "play_id", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("stop_sound_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("stop_sound")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("set_gain_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("set_gain")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        gain = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "gain", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("sound_done_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("sound_done")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        play_id = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "play_id", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    Play = function (this, sound)
      return System.ToInt32(sound.play(sound))
    end
    Play1 = function (this, sound)
      return System.ToInt32(sound.play(sound))
    end
    Play2 = function (this, sound)
      return System.ToInt32(sound.play(sound))
    end
    Play3 = function (this, sound, delay, gain, pan, speed, onCompleteCallback)
      local table = {}
      table["delay"] = delay
      table["gain"] = gain
      table["pan"] = pan
      table["speed"] = speed

      if onCompleteCallback ~= nil then
        local callback
        callback = function (o, hash, arg3, arg4)
          onCompleteCallback(this, hash, arg3:get("play_id"), arg4)
        end

        return System.ToInt32(sound.play(sound, table, callback))
      else
        return System.ToInt32(sound.play(sound, table))
      end
    end
    Play4 = function (this, sound, delay, gain, pan, speed, onCompleteCallback)
      local table = {}
      table["delay"] = delay
      table["gain"] = gain
      table["pan"] = pan
      table["speed"] = speed

      if onCompleteCallback ~= nil then
        local callback
        callback = function (o, hash, arg3, arg4)
          onCompleteCallback(this, hash, arg3:get("play_id"), arg4)
        end

        return System.ToInt32(sound.play(sound, table, callback))
      else
        return System.ToInt32(sound.play(sound, table))
      end
    end
    Play5 = function (this, sound, delay, gain, pan, speed, onCompleteCallback)
      local table = {}
      table["delay"] = delay
      table["gain"] = gain
      table["pan"] = pan
      table["speed"] = speed

      if onCompleteCallback ~= nil then
        local callback
        callback = function (o, hash, arg3, arg4)
          onCompleteCallback(this, hash, arg3:get("play_id"), arg4)
        end

        return System.ToInt32(sound.play(sound, table, callback))
      else
        return System.ToInt32(sound.play(sound, table))
      end
    end
    Stop = function (this)
      sound.stop(support.BuiltInComponentBase.op_Implicit(this))
    end
    Pause = function (this, shouldPause)
      sound.pause(support.BuiltInComponentBase.op_Implicit(this), shouldPause)
    end
    Unpause = function (this)
      sound.pause(support.BuiltInComponentBase.op_Implicit(this), false)
    end
    SetGain = function (this, gain)
      sound.set_gain(support.BuiltInComponentBase.op_Implicit(this), gain)
    end
    SetPan = function (this, pan)
      sound.set_pan(support.BuiltInComponentBase.op_Implicit(this), pan)
    end
    class = {
      base = function (out)
        return {
          out.support.BuiltInComponentBase
        }
      end,
      Play = Play,
      Play1 = Play1,
      Play2 = Play2,
      Play3 = Play3,
      Play4 = Play4,
      Play5 = Play5,
      Stop = Stop,
      Pause = Pause,
      Unpause = Unpause,
      SetGain = SetGain,
      SetPan = SetPan,
      __metadata__ = function (out)
        return {
          methods = {
            { "Pause", 0x106, Pause, System.Boolean },
            { "Play", 0x186, Play, System.String, System.Int32 },
            { "Play", 0x186, Play1, out.types.Hash, System.Int32 },
            { "Play", 0x186, Play2, out.types.Url, System.Int32 },
            { "Play", 0x686, Play3, System.String, System.Double, System.Double, System.Double, System.Double, System.Delegate(class, out.types.Hash, System.Int32, out.types.Url, System.Void), System.Int32 },
            { "Play", 0x686, Play4, out.types.Hash, System.Double, System.Double, System.Double, System.Double, System.Delegate(class, out.types.Hash, System.Int32, out.types.Url, System.Void), System.Int32 },
            { "Play", 0x686, Play5, out.types.Url, System.Double, System.Double, System.Double, System.Double, System.Delegate(class, out.types.Hash, System.Int32, out.types.Url, System.Void), System.Int32 },
            { "SetGain", 0x106, SetGain, System.Double },
            { "SetPan", 0x106, SetPan, System.Double },
            { "Stop", 0x6, Stop },
            { "Unpause", 0x6, Unpause }
          },
          class = { 0x6 }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("", function (namespace)
  -- <summary>
  -- Sprite API documentation
  -- 
  -- </summary>
  namespace.class("Sprite", function (namespace)
    local getFlipHorizontal, setFlipHorizontal, getFlipVertical, setFlipVertical, getSize, getScale, setScale, getImage, 
    setImage, getMaterial, setMaterial, getCursor, setCursor, getPlaybackRate, setPlaybackRate, getAnimation, 
    PlayFlipbook, PlayFlipbook1, PlayFlipbook2, class
    -- <summary>
    -- </summary>
    namespace.class("play_animation_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("play_animation")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "id", 0x6, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("animation_done_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("animation_done")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        current_tile = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "current_tile", 0x6, System.Double },
              { "id", 0x6, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    getFlipHorizontal = function (this)
      return this._cachedFlipHorizontal
    end
    setFlipHorizontal = function (this, value)
      this._cachedFlipHorizontal = value
      sprite.set_hflip(support.BuiltInComponentBase.op_Implicit(this), value)
    end
    getFlipVertical = function (this)
      return this._cachedFlipVertical
    end
    setFlipVertical = function (this, value)
      this._cachedFlipVertical = value

      sprite.set_vflip(support.BuiltInComponentBase.op_Implicit(this), value)
    end
    getSize = function (this)
      return go.get(support.BuiltInComponentBase.op_Implicit(this), "size")
    end
    getScale = function (this)
      return go.get(support.BuiltInComponentBase.op_Implicit(this), "scale")
    end
    setScale = function (this, value)
      go.set(support.BuiltInComponentBase.op_Implicit(this), "scale", value)
    end
    getImage = function (this)
      return go.get(support.BuiltInComponentBase.op_Implicit(this), "image")
    end
    setImage = function (this, value)
      go.set(support.BuiltInComponentBase.op_Implicit(this), "image", value)
    end
    getMaterial = function (this)
      return go.get(support.BuiltInComponentBase.op_Implicit(this), "material")
    end
    setMaterial = function (this, value)
      go.set(support.BuiltInComponentBase.op_Implicit(this), "material", value)
    end
    getCursor = function (this)
      return go.get(support.BuiltInComponentBase.op_Implicit(this), "cursor")
    end
    setCursor = function (this, value)
      go.set(support.BuiltInComponentBase.op_Implicit(this), "cursor", value)
    end
    getPlaybackRate = function (this)
      return go.get(support.BuiltInComponentBase.op_Implicit(this), "playback_rate")
    end
    setPlaybackRate = function (this, value)
      go.set(support.BuiltInComponentBase.op_Implicit(this), "playback_rate", value)
    end
    getAnimation = function (this)
      return go.get(support.BuiltInComponentBase.op_Implicit(this), "animation")
    end
    PlayFlipbook = function (this, animation)
      sprite.play_flipbook(support.BuiltInComponentBase.op_Implicit(this), animation)
    end
    PlayFlipbook1 = function (this, animation, onComplete)
      local function callback(target, hash, table, url) 
        onComplete(this, hash, table, url)
      end

      sprite.play_flipbook(support.BuiltInComponentBase.op_Implicit(this), animation, callback)
    end
    PlayFlipbook2 = function (this, animation, onComplete, playProperties)
      local function callback(target, hash, table, url) 
        onComplete(this, hash, table, url)
      end

      sprite.play_flipbook(support.BuiltInComponentBase.op_Implicit(this), animation, callback, playProperties)
    end
    class = {
      base = function (out)
        return {
          out.support.BuiltInComponentBase
        }
      end,
      _cachedFlipHorizontal = false,
      _cachedFlipVertical = false,
      getFlipHorizontal = getFlipHorizontal,
      setFlipHorizontal = setFlipHorizontal,
      getFlipVertical = getFlipVertical,
      setFlipVertical = setFlipVertical,
      getSize = getSize,
      getScale = getScale,
      setScale = setScale,
      getImage = getImage,
      setImage = setImage,
      getMaterial = getMaterial,
      setMaterial = setMaterial,
      getCursor = getCursor,
      setCursor = setCursor,
      getPlaybackRate = getPlaybackRate,
      setPlaybackRate = setPlaybackRate,
      getAnimation = getAnimation,
      PlayFlipbook = PlayFlipbook,
      PlayFlipbook1 = PlayFlipbook1,
      PlayFlipbook2 = PlayFlipbook2,
      __metadata__ = function (out)
        return {
          fields = {
            { "_cachedFlipHorizontal", 0x1, System.Boolean },
            { "_cachedFlipVertical", 0x1, System.Boolean }
          },
          properties = {
            { "Animation", 0x206, out.types.Hash, getAnimation },
            { "Cursor", 0x106, System.Double, getCursor, setCursor },
            { "FlipHorizontal", 0x106, System.Boolean, getFlipHorizontal, setFlipHorizontal },
            { "FlipVertical", 0x106, System.Boolean, getFlipVertical, setFlipVertical },
            { "Image", 0x106, out.types.Hash, getImage, setImage },
            { "Material", 0x106, out.types.Hash, getMaterial, setMaterial },
            { "PlaybackRate", 0x106, System.Double, getPlaybackRate, setPlaybackRate },
            { "Scale", 0x106, out.types.Vector2, getScale, setScale },
            { "Size", 0x206, out.types.Vector2, getSize }
          },
          methods = {
            { "PlayFlipbook", 0x106, PlayFlipbook, out.types.Hash },
            { "PlayFlipbook", 0x206, PlayFlipbook1, out.types.Hash, System.Delegate(class, out.types.Hash, out.types.ILuaTable, out.types.Url, System.Void) },
            { "PlayFlipbook", 0x306, PlayFlipbook2, out.types.Hash, System.Delegate(class, out.types.Hash, out.types.ILuaTable, out.types.Url, System.Void), out.types.ILuaTable }
          },
          class = { 0x6 }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- System API documentation
  -- 
  -- </summary>
  namespace.class("Sys", function (namespace)
    -- <summary>
    -- </summary>
    namespace.class("exit_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("exit")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        code = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "code", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("toggle_profile_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("toggle_profile")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("toggle_physics_debug_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("toggle_physics_debug")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("start_record_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("start_record")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        frame_period = 0,
        fps = 0,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "file_name", 0x6, System.String },
              { "fps", 0x6, System.Double },
              { "frame_period", 0x6, System.Double }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("stop_record_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("stop_record")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("reboot_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("reboot")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash },
              { "arg1", 0x6, System.String },
              { "arg2", 0x6, System.String },
              { "arg3", 0x6, System.String },
              { "arg4", 0x6, System.String },
              { "arg5", 0x6, System.String },
              { "arg6", 0x6, System.String }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("set_vsync_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("set_vsync")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    -- <summary>
    -- </summary>
    namespace.class("set_update_frequency_message", function (namespace)
      local FetchCode, class, static
      static = function (this)
        this.__CODE__ = hash("set_update_frequency")
      end
      FetchCode = function (this)
        return class.__CODE__
      end
      class = {
        base = function (out)
          return {
            out.MessageImplementation
          }
        end,
        FetchCode = FetchCode,
        static = static,
        __metadata__ = function (out)
          return {
            fields = {
              { "__CODE__", 0xE, out.types.Hash }
            },
            methods = {
              { "FetchCode", 0x86, FetchCode, out.types.Hash }
            },
            class = { 0x6 }
          }
        end
      }
      return class
    end)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
local types
System.import(function (out)
  support = out.support
  types = out.types
end)
System.namespace("", function (namespace)
  -- <summary>
  -- Tilemap API documentation
  -- 
  -- </summary>
  namespace.class("Tilemap", function (namespace)
    local getBounds, GetBounds, GetTile, GetTile1, SetTile, SetTile1, SetTile2, SetTile3, 
    SetLayerVisible, SetLayerVisible1
    getBounds = function (this)
      local default, y, w, h = tilemap.get_bounds(support.BuiltInComponentBase.op_Implicit(this))
      local x = default
      local returnVal = types.Rect(x, y, w, h)
      return returnVal
    end
    -- <summary>
    -- Fetches the bounds without allocating memory
    -- </summary>
    -- <param name="x"></param>
    -- <param name="y"></param>
    -- <param name="width"></param>
    -- <param name="height"></param>
    GetBounds = function (this, x, y, width, height)
      local default
      default, y, width, height = tilemap.get_bounds(support.BuiltInComponentBase.op_Implicit(this))
      x = default
      return x, y, width, height
    end
    GetTile = function (this, x, y, layer)
      return System.ToInt32(tilemap.get_tile(support.BuiltInComponentBase.op_Implicit(this), layer, x, y))
    end
    GetTile1 = function (this, x, y, layer)
      return System.ToInt32(tilemap.get_tile(support.BuiltInComponentBase.op_Implicit(this), layer, x, y))
    end
    SetTile = function (this, x, y, tile, layer)
      tilemap.set_tile(support.BuiltInComponentBase.op_Implicit(this), layer, x, y, tile)
    end
    SetTile1 = function (this, x, y, tile, layer, transformBitmask)
      tilemap.set_tile(support.BuiltInComponentBase.op_Implicit(this), layer, x, y, tile, transformBitmask)
    end
    SetTile2 = function (this, x, y, tile, layer)
      tilemap.set_tile(support.BuiltInComponentBase.op_Implicit(this), layer, x, y, tile)
    end
    SetTile3 = function (this, x, y, tile, layer, transformBitmask)
      tilemap.set_tile(support.BuiltInComponentBase.op_Implicit(this), layer, x, y, tile, transformBitmask)
    end
    SetLayerVisible = function (this, layer, visible)
      tilemap.set_visible(support.BuiltInComponentBase.op_Implicit(this), layer, visible)
    end
    SetLayerVisible1 = function (this, layer, visible)
      tilemap.set_visible(support.BuiltInComponentBase.op_Implicit(this), layer, visible)
    end
    return {
      base = function (out)
        return {
          out.support.BuiltInComponentBase
        }
      end,
      getBounds = getBounds,
      GetBounds = GetBounds,
      GetTile = GetTile,
      GetTile1 = GetTile1,
      SetTile = SetTile,
      SetTile1 = SetTile1,
      SetTile2 = SetTile2,
      SetTile3 = SetTile3,
      SetLayerVisible = SetLayerVisible,
      SetLayerVisible1 = SetLayerVisible1,
      __metadata__ = function (out)
        return {
          properties = {
            { "Bounds", 0x206, out.types.Rect, getBounds }
          },
          methods = {
            { "GetBounds", 0x406, GetBounds, System.Double, System.Double, System.Double, System.Double },
            { "GetTile", 0x386, GetTile, System.Int32, System.Int32, System.String, System.Int32 },
            { "GetTile", 0x386, GetTile1, System.Int32, System.Int32, out.types.Hash, System.Int32 },
            { "SetLayerVisible", 0x206, SetLayerVisible, System.String, System.Boolean },
            { "SetLayerVisible", 0x206, SetLayerVisible1, out.types.Hash, System.Boolean },
            { "SetTile", 0x406, SetTile, System.Int32, System.Int32, System.Int32, System.String },
            { "SetTile", 0x506, SetTile1, System.Int32, System.Int32, System.Int32, System.String, System.Int32 },
            { "SetTile", 0x406, SetTile2, System.Int32, System.Int32, System.Int32, out.types.Hash },
            { "SetTile", 0x506, SetTile3, System.Int32, System.Int32, System.Int32, out.types.Hash, System.Int32 }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Timer API documentation
  -- 
  -- </summary>
  namespace.class("Timer", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Vector math API documentation
  -- 
  -- </summary>
  namespace.class("Vmath", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Webview API documentation
  -- 
  -- </summary>
  namespace.class("Webview", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Window API documentation
  -- 
  -- </summary>
  namespace.class("Window", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  -- <summary>
  -- Zlib compression API documentation
  -- 
  -- </summary>
  namespace.class("Zlib", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
local types
local ArrayHash
System.import(function (out)
  types = out.types
  ArrayHash = System.Array(types.Hash)
end)
System.namespace("", function (namespace)
  namespace.class("Bunnymark", function (namespace)
    local BunnyImages, RandomImage, Reset, class, static
    static = function (this)
      BunnyImages = ArrayHash { "rabbitv3_batman", "rabbitv3_bb8", "rabbitv3", "rabbitv3_ash", "rabbitv3_frankenstein", "rabbitv3_neo", "rabbitv3_sonic", "rabbitv3_spidey", "rabbitv3_stormtrooper", "rabbitv3_superman", "rabbitv3_tron", "rabbitv3_wolverine" }
      this.BunnyImages = BunnyImages
    end
    RandomImage = function ()
      return BunnyImages:get(math.random(0, #BunnyImages - 1))
    end
    Reset = function ()
      class.BunnyCount = 0
      class.CurrentInstance = nil
    end
    class = {
      RandomImage = RandomImage,
      BunnyCount = 0,
      Reset = Reset,
      static = static,
      __metadata__ = function (out)
        return {
          fields = {
            { "BunnyImages", 0xE, System.Array(out.types.Hash) },
            { "CurrentInstance", 0xE, out.IBunnymark }
          },
          methods = {
            { "RandomImage", 0x8E, RandomImage, out.types.Hash },
            { "Reset", 0xE, Reset }
          },
          properties = {
            { "BunnyCount", 0xE, System.Int32 }
          },
          class = { 0xE }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
local CollectionProxy
local support
local types
local ArrayUrl
System.import(function (out)
  CollectionProxy = out.CollectionProxy
  support = out.support
  types = out.types
  ArrayUrl = System.Array(types.Url)
end)
System.namespace("Scenes", function (namespace)
  namespace.class("BunnymarkAnimateMultiple", function (namespace)
    local collections, init, final, LoadNextCollection, update, on_message, static
    static = function (this)
      collections = ArrayUrl(3, {
        msg.url("multiple:/go#proxy_one"),
        msg.url("multiple:/go#proxy_two"),
        msg.url("multiple:/go#proxy_three")
      })
    end
    init = function (this)
      this:RequestInput()
      LoadNextCollection(this)
    end
    final = function (this)
      Bunnymark.Reset()
    end
    LoadNextCollection = function (this)
      if this._currentCollection < #collections then
        this._currentCollection = this._currentCollection + 1

        --you could also trim the above urls to just component references
        --and use the GameObject.Component notation.  But this demonstrates how to use a custom locator
        local proxy = support.Component.At(support.Locator.AtUrl(collections:get(this._currentCollection)), CollectionProxy)
        proxy:LoadAsync()
      else
        pprint("No more collections to load")
      end
    end
    update = function (this, dt)
      label.set_text("#label", "Bunnies " .. Bunnymark.BunnyCount .. " FPS:" .. FPS.Fps)
    end
    on_message = function (this, message_id, message, sender)
      local default, impl = Message.IsMessage1(message_id, message, nil, false, CollectionProxy.proxy_loaded_message)
      if default then
        msg.post(sender,"enable")
      elseif message_id == hash("collection_full") then
        LoadNextCollection(this)
      end
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript
        }
      end,
      _currentCollection = - 1,
      init = init,
      final = final,
      update = update,
      on_message = on_message,
      static = static,
      __metadata__ = function (out)
        return {
          fields = {
            { "_currentCollection", 0x1, System.Int32 },
            { "collections", 0x9, System.Array(out.types.Url) }
          },
          methods = {
            { "LoadNextCollection", 0x1, LoadNextCollection },
            { "final", 0x3, final },
            { "init", 0x3, init },
            { "on_message", 0x303, on_message, out.types.Hash, System.Object, out.types.Hash },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("Scenes", function (namespace)
  namespace.class("AnimateMultipleCollectionProps", function (namespace)
    return {
      base = function (out)
        return {
          out.support.AnimatableProperties
        }
      end,
      min_x = 0,
      max_x = 640,
      __metadata__ = function (out)
        return {
          fields = {
            { "max_x", 0x6, System.Int32 },
            { "min_x", 0x6, System.Int32 }
          },
          class = { 0x6 }
        }
      end
    }
  end)

  namespace.class("BunnymarkAnimateMultipleCollection", function (namespace)
    local init, AnimateBunny, on_input, __ctor__
    __ctor__ = function (this)
      this.touchHash = hash("touch")
      System.base(this).__ctor__(this)
    end
    init = function (this)
      this:RequestInput()
      local factory = this:getGameobject():Component(hash("factory"), Factory)
      this._bunnymark = FactoryBasedBunnymark(factory, System.fn(this, AnimateBunny))
      this._bunnymark:Spawn(500)
    end
    AnimateBunny = function (this, newBunny)
      go.set_position(vmath.vector3(math.random(this.Properties.min_x, this.Properties.max_x),1024,0), newBunny.url)
      go.animate(newBunny.url, "position.y", 6 --[[GoPlaybackMode.PLAYBACK_LOOP_PINGPONG]], 80, 1 --[[Easing.EASING_INQUAD]], 2, math.random())
    end
    on_input = function (this, action_id, action)
      if action_id == this.touchHash and action.released and action.y < 1030 then
        if not this._bunnymark:Spawn(500) then
          pprint("Unable to create more bunnies")
          this:ReleaseInput()
          msg.post("multiple:/go", "collection_full")
        end
      end

      return false
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript_1(out.Scenes.AnimateMultipleCollectionProps)
        }
      end,
      init = init,
      on_input = on_input,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "_bunnymark", 0x1, out.FactoryBasedBunnymark },
            { "touchHash", 0x1, out.types.Hash }
          },
          methods = {
            { "AnimateBunny", 0x101, AnimateBunny, out.GoBunny },
            { "init", 0x3, init },
            { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("BunnymarkGoAnimate", function (namespace)
    local init, OnBunnyCreate, update, on_input, final, __ctor__
    __ctor__ = function (this)
      this.touchHash = hash("touch")
      System.base(this).__ctor__(this)
    end
    init = function (this)
      System.base(this).init(this)
      this:RequestInput()

      this._bunnymark = FactoryBasedBunnymark(this:getGameobject():Component(hash("factory"), Factory), System.fn(this, OnBunnyCreate))
      this._bunnymark:Spawn(500)
    end
    OnBunnyCreate = function (this, newBunny)
      go.set_position(vmath.vector3(math.random(640),1024,0), newBunny.url)
      go.animate(newBunny.url, "position.y", 6 --[[GoPlaybackMode.PLAYBACK_LOOP_PINGPONG]], 80, 1 --[[Easing.EASING_INQUAD]], 2, math.random())
    end
    update = function (this, dt)
      label.set_text("#label", "Bunnies " .. Bunnymark.BunnyCount .. " FPS:" .. FPS.Fps)
    end
    on_input = function (this, action_id, action)
      if action_id == this.touchHash and action.released and action.y < 1030 then
        this._bunnymark:Spawn(500)
      end

      return false
    end
    final = function (this)
      Bunnymark.Reset()
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript
        }
      end,
      init = init,
      OnBunnyCreate = OnBunnyCreate,
      update = update,
      on_input = on_input,
      final = final,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "_bunnymark", 0x1, out.FactoryBasedBunnymark },
            { "touchHash", 0x1, out.types.Hash }
          },
          methods = {
            { "OnBunnyCreate", 0x103, OnBunnyCreate, out.GoBunny },
            { "final", 0x3, final },
            { "init", 0x3, init },
            { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("BunnymarkGuiAnimate", function (namespace)
    local init, AnimateBunny, update, on_input, final, __ctor__
    __ctor__ = function (this)
      this.touchHash = hash("touch")
      System.base(this).__ctor__(this)
    end
    init = function (this)
      System.base(this).init(this)

      this._bunnymark = GuiBasedBunnymark(System.fn(this, AnimateBunny))
      this._factory = this:getGameobject():Component(hash("factory"), Factory)
      this:RequestInput()
    end
    AnimateBunny = function (this, bunny)
      gui.set_position(bunny.node, vmath.vector3(math.random(640),1030,0))
      gui.animate(bunny.node, "position.y", 80.0, 1 --[[Easing.EASING_INQUAD]], 2.0, math.random(), nil, 5 --[[GuiPlaybackMode.PLAYBACK_LOOP_PINGPONG]])
    end
    update = function (this, dt)
      -- inline GuiBasedBunnymark.BunnyCount.get
      local default
      do
        local this = this._bunnymark
        default = #this.Bunnies
      end
      label.set_text("#label", "Bunnies " .. default .. " FPS:" .. FPS.Fps)
    end
    on_input = function (this, action_id, action)
      if action_id == this.touchHash and action.released and action.y < 1030 then
        this._factory:Create()
      end

      return false
    end
    final = function (this)
      Bunnymark.Reset()
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript
        }
      end,
      init = init,
      update = update,
      on_input = on_input,
      final = final,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "_bunnymark", 0x1, out.GuiBasedBunnymark },
            { "_factory", 0x1, out.Factory },
            { "touchHash", 0x1, out.types.Hash }
          },
          methods = {
            { "AnimateBunny", 0x101, AnimateBunny, out.GuiBunny },
            { "final", 0x3, final },
            { "init", 0x3, init },
            { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("BunnymarkManyUpdates", function (namespace)
    local init, update, on_input, final, __ctor__
    __ctor__ = function (this)
      this.touchHash = hash("touch")
      this.toggledebugHash = hash("toggledebug")
      System.base(this).__ctor__(this)
    end
    init = function (this)
      System.base(this).init(this)

      this:RequestInput()

      this._bunnymark = FactoryBasedBunnymark(this:getGameobject():Component(hash("factory"), Factory))
      this._bunnymark:Spawn(500)
    end
    update = function (this, dt)
      System.base(this).update(this, dt)
      label.set_text("#label", "Bunnies " .. Bunnymark.BunnyCount .. " FPS:" .. FPS.Fps)
    end
    on_input = function (this, action_id, action)
      if action_id == this.touchHash and action.released and action.y < 1030 then
        this._bunnymark:Spawn(500)
      end

      if action_id == this.toggledebugHash and action.released then
        Debug.ToggleEditorDebug()
      end

      return false
    end
    final = function (this)
      Bunnymark.Reset()
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript
        }
      end,
      init = init,
      update = update,
      on_input = on_input,
      final = final,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "_bunnymark", 0x1, out.FactoryBasedBunnymark },
            { "toggledebugHash", 0x1, out.types.Hash },
            { "touchHash", 0x1, out.types.Hash }
          },
          methods = {
            { "final", 0x3, final },
            { "init", 0x3, init },
            { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("BunnymarkParticleFx", function (namespace)
    local init, update, final
    init = function (this)
      particlefx.play("#bunnies")
    end
    update = function (this, dt)
      label.set_text("#label", "Bunnies 15000 FPS:" .. FPS.Fps)
    end
    final = function (this)
      Bunnymark.Reset()
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript
        }
      end,
      init = init,
      update = update,
      final = final,
      __metadata__ = function (out)
        return {
          fields = {
            { "_bunnymark", 0x1, out.FactoryBasedBunnymark }
          },
          methods = {
            { "final", 0x3, final },
            { "init", 0x3, init },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.class("BunnymarkSingleUpdate", function (namespace)
    local init, OnBunnyCreate, update, on_input, final, __ctor__
    __ctor__ = function (this)
      this.touchHash = hash("touch")
      System.base(this).__ctor__(this)
    end
    init = function (this)
      System.base(this).init(this)
      this:RequestInput()

      this._bunnymark = FactoryBasedBunnymark(this:getGameobject():Component(hash("factory"), Factory), System.fn(this, OnBunnyCreate))
      this._bunnymark:Spawn(500)
    end
    OnBunnyCreate = function (this, newBunny)
      newBunny.Position = vmath.vector3(math.random(640),math.random(930, 1024),0)

      newBunny.Velocity = math.random(200)
    end
    update = function (this, dt)
      for _, bunny in System.each(this._bunnymark.Bunnies) do
        bunny.Velocity = bunny.Velocity - (1200 * dt)
        bunny.Position.y = bunny.Position.y + (bunny.Velocity * dt)

        if bunny.Position.y < 50 then
          bunny.Position.y = 50
          bunny.Velocity = - bunny.Velocity
        end

        go.set_position(bunny.Position, bunny.url)
      end

      label.set_text("#label", "Bunnies " .. Bunnymark.BunnyCount .. " FPS:" .. FPS.Fps)
    end
    on_input = function (this, action_id, action)
      if action_id == this.touchHash and action.released and action.y < 1030 then
        this._bunnymark:Spawn(500)
      end

      return false
    end
    final = function (this)
      Bunnymark.Reset()
    end
    return {
      base = function (out)
        return {
          out.support.GameObjectScript
        }
      end,
      init = init,
      OnBunnyCreate = OnBunnyCreate,
      update = update,
      on_input = on_input,
      final = final,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "_bunnymark", 0x1, out.FactoryBasedBunnymark },
            { "touchHash", 0x1, out.types.Hash }
          },
          methods = {
            { "OnBunnyCreate", 0x103, OnBunnyCreate, out.GoBunny },
            { "final", 0x3, final },
            { "init", 0x3, init },
            { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean },
            { "update", 0x103, update, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local ListGoBunny
System.import(function (out)
  ListGoBunny = System.List(GoBunny)
end)
System.namespace("", function (namespace)
  namespace.class("FactoryBasedBunnymark", function (namespace)
    local CreateBunny, InitializeBunny, Spawn, Dispose, __ctor__
    __ctor__ = function (this, sourceFactory, bunnyInitializer)
      this.Bunnies = ListGoBunny()
      this._bunnyFactory = sourceFactory
      this._bunnyInitializer = bunnyInitializer
      Bunnymark.CurrentInstance = this
    end
    CreateBunny = function (this)
      local id = this._bunnyFactory:Create()
      if id ~= nil then
        local urlP1 = msg.url(nil --[[Msg.DefaultSocket]], id, "sprite")


        local idP2 = Bunnymark.RandomImage()
        sprite.play_flipbook(urlP1, idP2)
        local url = msg.url(nil --[[Msg.DefaultSocket]],id,nil)
        local newBunny = GoBunny(url)
        this.Bunnies:Add(newBunny)
        InitializeBunny(this, newBunny)
        local default = Bunnymark
        default.BunnyCount = default.BunnyCount + 1
        return true
      else
        pprint("Unable to create more bunnies")
        return false
      end
    end
    InitializeBunny = function (this, newBunny)
      if this._bunnyInitializer ~= nil then
        this._bunnyInitializer(newBunny)
      end
    end
    Spawn = function (this, count)
      for i = 0, count - 1 do
        if not CreateBunny(this) then
          return false
        end
      end

      return true
    end
    Dispose = function (this)
      Bunnymark.CurrentInstance = nil
    end
    return {
      base = function (out)
        return {
          out.IBunnymark
        }
      end,
      CreateBunny = CreateBunny,
      InitializeBunny = InitializeBunny,
      Spawn = Spawn,
      Dispose = Dispose,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "Bunnies", 0x6, System.List(out.GoBunny) },
            { "_bunnyFactory", 0x1, out.Factory },
            { "_bunnyInitializer", 0x1, System.Delegate(out.GoBunny, System.Void) }
          },
          methods = {
            { ".ctor", 0x206, nil, out.Factory, System.Delegate(out.GoBunny, System.Void) },
            { "CreateBunny", 0x86, CreateBunny, System.Boolean },
            { "Dispose", 0x6, Dispose },
            { "InitializeBunny", 0x103, InitializeBunny, out.GoBunny },
            { "Spawn", 0x186, Spawn, System.Int32, System.Boolean }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local ListGuiBunny
System.import(function (out)
  ListGuiBunny = System.List(GuiBunny)
end)
System.namespace("", function (namespace)
  namespace.class("GuiBasedBunnymark", function (namespace)
    local getBunnyCount, CreateBunny, InitializeBunny, Spawn, Dispose, __ctor__
    __ctor__ = function (this, bunnyInitializer)
      this.Bunnies = ListGuiBunny()
      this._bunnyInitializer = bunnyInitializer
      Bunnymark.CurrentInstance = this
    end
    getBunnyCount = function (this)
      return #this.Bunnies
    end
    CreateBunny = function (this)
      local box = gui.new_box_node(vmath.vector3(), vmath.vector3())
      if box ~= nil then
        gui.set_size_mode(box, 1 --[[SizeMode.SIZE_MODE_AUTO]])
        gui.set_texture(box, "bunnymark")
        gui.play_flipbook(box, Bunnymark.RandomImage())
        local newBunny = GuiBunny(box)
        this.Bunnies:Add(newBunny)
        InitializeBunny(this, newBunny)
        local default = Bunnymark
        default.BunnyCount = default.BunnyCount + 1
        return true
      else
        pprint("Unable to create more bunnies")
        return false
      end
    end
    InitializeBunny = function (this, newBunny)
      if this._bunnyInitializer ~= nil then
        this._bunnyInitializer(newBunny)
      end
    end
    Spawn = function (this, count)
      for i = 0, count - 1 do
        if not CreateBunny(this) then
          return false
        end
      end

      return true
    end
    Dispose = function (this)
      Bunnymark.CurrentInstance = nil
    end
    return {
      base = function (out)
        return {
          out.IBunnymark,
          System.IDisposable
        }
      end,
      getBunnyCount = getBunnyCount,
      CreateBunny = CreateBunny,
      InitializeBunny = InitializeBunny,
      Spawn = Spawn,
      Dispose = Dispose,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "Bunnies", 0x6, System.List(out.GuiBunny) },
            { "_bunnyInitializer", 0x1, System.Delegate(out.GuiBunny, System.Void) }
          },
          properties = {
            { "BunnyCount", 0x206, System.Int32, getBunnyCount }
          },
          methods = {
            { ".ctor", 0x106, nil, System.Delegate(out.GuiBunny, System.Void) },
            { "CreateBunny", 0x86, CreateBunny, System.Boolean },
            { "Dispose", 0x6, Dispose },
            { "InitializeBunny", 0x103, InitializeBunny, out.GuiBunny },
            { "Spawn", 0x186, Spawn, System.Int32, System.Boolean }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("", function (namespace)
  namespace.interface("IBunnymark", function ()
    return {
      base = function (out)
        return {
          System.IDisposable
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("attributes", function (namespace)
  -- <summary>
  -- Flags a class as a property proxy, and that properties need to be generated on scripts
  -- that use this class as a proxy.
  -- </summary>
  namespace.class("DefoldPropertyProxyGenAttribute", function (namespace)
    return {
      base = function (out)
        return {
          System.Attribute
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("attributes", function (namespace)
  namespace.class("DoNotGenerateAttribute", function (namespace)
    return {
      base = function (out)
        return {
          System.Attribute
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("attributes", function (namespace)
end)

end
do
local System = System
System.namespace("attributes", function (namespace)
  namespace.class("PropertyProxyHandling", function (namespace)
    local __ctor__
    __ctor__ = function (this, style)
      System.base(this).__ctor__(this)
      this.Style = style
    end
    return {
      base = function (out)
        return {
          System.Attribute
        }
      end,
      Style = 0,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          methods = {
            { ".ctor", 0x106, nil, System.Int32 }
          },
          properties = {
            { "Style", 0x6, System.Int32 }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("DoNotGenerateAttribute", function (namespace)
    return {
      base = function (out)
        return {
          System.Attribute
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("support", function (namespace)
  namespace.class("GameObjectReference", function (namespace)
    local getPosition, setPosition, getRotation, setRotation, getScale, setScale, getUniformScale, getWorldPosition, 
    getWorldRotation, getWorldScale, getWorldScaleUniform, getWorldTransform, GetProperty, GetProperty1, GetProperty2, SetProperty, 
    SetProperty1, SetProperty2, Delete, Component, class, __ctor__
    __ctor__ = function (this, locatorUrl)
      this.LocatorUrl = locatorUrl
    end
    getPosition = function (this)
      if class.CurrentGameObject == this then
        return go.get_position()
      end
      return go.get_position(this.LocatorUrl)
    end
    setPosition = function (this, value)
      if class.CurrentGameObject == this then
        go.set_position(value)
      else
        go.set_position(value, this.LocatorUrl)
      end
    end
    getRotation = function (this)
      if class.CurrentGameObject == this then
        return go.get_rotation()
      end
      return go.get_rotation(this.LocatorUrl)
    end
    setRotation = function (this, value)
      if class.CurrentGameObject == this then
        go.set_rotation(value)
      else
        go.set_rotation(value, this.LocatorUrl)
      end
    end
    getScale = function (this)
      if class.CurrentGameObject == this then
        return go.get_scale()
      end
      return go.get_scale(this.LocatorUrl)
    end
    setScale = function (this, value)
      if class.CurrentGameObject == this then
        go.set_scale(value)
      else
        go.set_scale(value, this.LocatorUrl)
      end
    end
    getUniformScale = function (this)
      if class.CurrentGameObject == this then
        return go.get_scale_uniform()
      end
      return go.get_scale_uniform(this.LocatorUrl)
    end
    getWorldPosition = function (this)
      if class.CurrentGameObject == this then
        return go.get_world_position()
      end
      return go.get_world_position(this.LocatorUrl)
    end
    getWorldRotation = function (this)
      if class.CurrentGameObject == this then
        return go.get_world_rotation()
      end
      return go.get_world_rotation(this.LocatorUrl)
    end
    getWorldScale = function (this)
      if class.CurrentGameObject == this then
        return go.get_world_scale()
      end
      return go.get_world_scale(this.LocatorUrl)
    end
    getWorldScaleUniform = function (this)
      if class.CurrentGameObject == this then
        return go.get_world_scale_uniform()
      end
      return go.get_world_scale_uniform(this.LocatorUrl)
    end
    getWorldTransform = function (this)
      if class.CurrentGameObject == this then
        return go.get_world_transform()
      end
      return go.get_world_transform(this.LocatorUrl)
    end
    GetProperty = function (this, property, T)
      return go.get(this.LocatorUrl, property)
    end
    GetProperty1 = function (this, property, T)
      return go.get(this.LocatorUrl, property)
    end
    GetProperty2 = function (this, property, T)
      return go.get(this.LocatorUrl, property)
    end
    SetProperty = function (this, property, value, T)
      Go.set(this.LocatorUrl, property, value)
    end
    SetProperty1 = function (this, property, value, T)
      go.set(this.LocatorUrl, property, value)
    end
    SetProperty2 = function (this, property, value, T)
      Go.set(this.LocatorUrl, property, value)
    end
    Delete = function (this)
      this.isDestroyed = true
      go.delete(this.LocatorUrl)
    end
    -- <summary>
    -- A convenience shortcut for Component.At that handles fetching the Component relative
    -- to this gameobject.
    -- </summary>
    -- <param name="hash"></param>
    -- <typeparam name="T"></typeparam>
    -- <returns></returns>
    Component = function (this, hash, T)
      local targetUrl = msg.url()
      targetUrl.socket = this.LocatorUrl.socket
      targetUrl.path = this.LocatorUrl.path
      targetUrl.fragment = hash

      return support.Component.At(support.Locator.AtUrl(targetUrl), T)
    end
    class = {
      isDestroyed = false,
      getPosition = getPosition,
      setPosition = setPosition,
      getRotation = getRotation,
      setRotation = setRotation,
      getScale = getScale,
      setScale = setScale,
      getUniformScale = getUniformScale,
      getWorldPosition = getWorldPosition,
      getWorldRotation = getWorldRotation,
      getWorldScale = getWorldScale,
      getWorldScaleUniform = getWorldScaleUniform,
      getWorldTransform = getWorldTransform,
      GetProperty = GetProperty,
      GetProperty1 = GetProperty1,
      GetProperty2 = GetProperty2,
      SetProperty = SetProperty,
      SetProperty1 = SetProperty1,
      SetProperty2 = SetProperty2,
      Delete = Delete,
      Component = Component,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          properties = {
            { "CurrentGameObject", 0xE, class },
            { "LocatorUrl", 0x6, out.types.Url },
            { "Position", 0x106, out.types.Vector3, getPosition, setPosition },
            { "Rotation", 0x106, out.types.Quaternion, getRotation, setRotation },
            { "Scale", 0x106, out.types.Vector3, getScale, setScale },
            { "UniformScale", 0x206, System.Double, getUniformScale },
            { "WorldPosition", 0x206, out.types.Vector3, getWorldPosition },
            { "WorldRotation", 0x206, out.types.Quaternion, getWorldRotation },
            { "WorldScale", 0x206, out.types.Vector3, getWorldScale },
            { "WorldScaleUniform", 0x206, System.Double, getWorldScaleUniform },
            { "WorldTransform", 0x206, out.types.Matrix4, getWorldTransform }
          },
          fields = {
            { "isDestroyed", 0x6, System.Boolean }
          },
          methods = {
            { ".ctor", 0x106, nil, out.types.Url },
            { "Component", 0x10186, Component, function (T) return out.types.Hash, T end },
            { "Delete", 0x6, Delete },
            { "GetProperty", 0x10186, GetProperty, function (T) return out.types.__Hash2, T end },
            { "GetProperty", 0x10186, GetProperty1, function (T) return out.types.__Hash3, System.String end },
            { "GetProperty", 0x10186, GetProperty2, function (T) return out.types.Hash, T end },
            { "SetProperty", 0x10206, SetProperty, function (T) return out.types.__Hash2, T end },
            { "SetProperty", 0x10206, SetProperty1, function (T) return out.types.__Hash3, System.String end },
            { "SetProperty", 0x10206, SetProperty2, function (T) return out.types.Hash, T end }
          },
          class = { 0x6 }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
local support
System.import(function (out)
  support = out.support
end)
System.namespace("support", function (namespace)
  namespace.class("GameObjectScript", function (namespace)
    return {
      base = function (out)
        return {
          out.support.GameObjectScript_1(out.support.AnimatableProperties)
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)

  -- <summary>
  -- Base class for all game object scripts (.script).
  -- </summary>
  namespace.class("GameObjectScript_1", function (namespace)
    return function (TProps)
      local getLocatorUrl, getGameobject, init, final, update, fixed_update, on_message, on_input, 
      on_reload, __ctor__
      __ctor__ = function (this)
        this.LocatorUrl = msg.url()
      end
      getLocatorUrl = System.property("LocatorUrl", true)
      getGameobject = function (this)
        if this._gameObjectReference == nil then
          this._gameObjectReference = support.GameObjectReference(msg.url(this.LocatorUrl.socket, this.LocatorUrl.path, ""))
        end

        return this._gameObjectReference
      end
      -- <summary>
      -- Called when a script component is initialized.
      -- This is a callback-function, which is called by the engine when a script component is initialized. It can be used
      -- to set the initial state of the script.
      -- </summary>
      init = function (this)
      end
      -- <summary>
      -- Called when a script component is finalized.
      -- This is a callback-function, which is called by the engine when a script component is finalized (destroyed). It can
      -- be used to e.g. take some last action, report the finalization to other game object instances, delete spawned
      -- objects
      -- or release user input focus (see `release_input_focus`).
      -- </summary>
      final = function (this)
        support.Component.Unregister(this.LocatorUrl)
      end
      -- <summary>
      -- Called every frame to update the script component.
      -- This is a callback-function, which is called by the engine every frame to update the state of a script component.
      -- It can be used to perform any kind of game related tasks, e.g. moving the game object instance.
      -- </summary>
      -- <param name="dt">frame update timestep</param>
      update = function (this, dt)
      end
      -- <summary>
      -- Called every frame to update the script component.
      -- Frame-rate independent update. dt contains the delta time since the last update.
      -- Useful when you wish to manipulate physics objects at regular intervals to achieve a stable physics simulation.
      -- Requires that `physics.use_fixed_timestep` is enabled in game.project.
      -- </summary>
      -- <param name="dt">frame update timestep</param>
      fixed_update = function (this, dt)
      end
      -- <summary>
      -- Called when a message has been sent to the script component.
      -- This is a callback-function, which is called by the engine whenever a message has been sent to the script
      -- component.
      -- It can be used to take action on the message, e.g. send a response back to the sender of the message.
      -- The `message` parameter is a table containing the message data. If the message is sent from the engine, the
      -- documentation of the message specifies which data is supplied.
      -- </summary>
      -- <param name="message_id">id of the received message</param>
      -- <param name="message">a table containing the message data</param>
      -- <param name="sender">address of the sender</param>
      on_message = function (this, message_id, message, sender)
      end
      -- <summary>
      -- Called when user input is received.
      -- This is a callback-function, which is called by the engine when user input is sent to the game object instance of
      -- the script.
      -- It can be used to take action on the input, e.g. move the instance according to the input.
      -- For an instance to obtain user input, it must first acquire input focuse through the message `acquire_input_focus`.
      -- See the documentation of that message for more information.
      -- The `action` parameter is a table containing data about the input mapped to the `action_id`.
      -- For mapped actions it specifies the value of the input and if it was just pressed or released.
      -- Actions are mapped to input in an input_binding-file.
      -- Mouse movement is specifically handled and uses `nil` as its `action_id`.
      -- The `action` only contains positional parameters in this case, such as x and y of the pointer.
      -- </summary>
      -- <param name="action_id">id of the received input action, as mapped in the input_binding-file</param>
      -- <param name="action">a table containing the input data, see above for a description</param>
      -- <returns>boolean to signal if the input should be consumed (not passed on to others) or not, default is false</returns>
      on_input = function (this, action_id, action)
        return false
      end
      -- <summary>
      -- Called when the script component is reloaded.
      -- This is a callback-function, which is called by the engine when the script component is reloaded, e.g. from the
      -- editor.
      -- It can be used for live development, e.g. to tweak constants or set up the state properly for the instance.
      -- </summary>
      on_reload = function (this)
      end
      return {
        base = function (out)
          return {
            out.support.ScriptPropertyHost_1(TProps),
            out.support.IUserComponent
          }
        end,
        getLocatorUrl = getLocatorUrl,
        getGameobject = getGameobject,
        init = init,
        final = final,
        update = update,
        fixed_update = fixed_update,
        on_message = on_message,
        on_input = on_input,
        on_reload = on_reload,
        __ctor__ = __ctor__,
        __metadata__ = function (out)
          return {
            fields = {
              { "_gameObjectReference", 0x1, out.support.GameObjectReference },
              { "_gameObjectUrl", 0x1, out.types.Url }
            },
            properties = {
              { "Gameobject", 0x206, out.support.GameObjectReference, getGameobject },
              { "LocatorUrl", 0x206, out.types.Url, getLocatorUrl }
            },
            methods = {
              { ".ctor", 0x3, nil },
              { "final", 0x3, final },
              { "fixed_update", 0x103, fixed_update, System.Single },
              { "init", 0x3, init },
              { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean },
              { "on_message", 0x303, on_message, out.types.Hash, System.Object, out.types.Hash },
              { "on_reload", 0x3, on_reload },
              { "update", 0x103, update, System.Single }
            },
            class = { 0x106, TProps }
          }
        end
      }
    end
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("GeneratedScript", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("GUIScript", function (namespace)
    return {
      base = function (out)
        return {
          out.support.GUIScript_1(out.support.AnimatableProperties)
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)

  -- <summary>
  -- Base class for all game object scripts (.script).
  -- </summary>
  namespace.class("GUIScript_1", function (namespace)
    return function (TProps)
      local getLocatorUrl, init, final, update, fixed_update, on_message, on_input, on_reload, 
      GetNode1, __ctor__
      __ctor__ = function (this)
        this.LocatorUrl = msg.url()
      end
      getLocatorUrl = System.property("LocatorUrl", true)
      -- <summary>
      -- Called when a script component is initialized.
      -- This is a callback-function, which is called by the engine when a script component is initialized. It can be used
      -- to set the initial state of the script.
      -- </summary>
      init = function (this)
      end
      -- <summary>
      -- Called when a script component is finalized.
      -- This is a callback-function, which is called by the engine when a script component is finalized (destroyed). It can
      -- be used to e.g. take some last action, report the finalization to other game object instances, delete spawned
      -- objects
      -- or release user input focus (see `release_input_focus`).
      -- </summary>
      final = function (this)
      end
      -- <summary>
      -- Called every frame to update the script component.
      -- This is a callback-function, which is called by the engine every frame to update the state of a script component.
      -- It can be used to perform any kind of game related tasks, e.g. moving the game object instance.
      -- </summary>
      -- <param name="dt">frame update timestep</param>
      update = function (this, dt)
      end
      -- <summary>
      -- Called every frame to update the script component.
      -- Frame-rate independent update. dt contains the delta time since the last update.
      -- Useful when you wish to manipulate physics objects at regular intervals to achieve a stable physics simulation.
      -- Requires that `physics.use_fixed_timestep` is enabled in game.project.
      -- </summary>
      -- <param name="dt">frame update timestep</param>
      fixed_update = function (this, dt)
      end
      -- <summary>
      -- Called when a message has been sent to the script component.
      -- This is a callback-function, which is called by the engine whenever a message has been sent to the script
      -- component.
      -- It can be used to take action on the message, e.g. send a response back to the sender of the message.
      -- The `message` parameter is a table containing the message data. If the message is sent from the engine, the
      -- documentation of the message specifies which data is supplied.
      -- </summary>
      -- <param name="message_id">id of the received message</param>
      -- <param name="message">a table containing the message data</param>
      -- <param name="sender">address of the sender</param>
      on_message = function (this, message_id, message, sender)
      end
      -- <summary>
      -- Called when user input is received.
      -- This is a callback-function, which is called by the engine when user input is sent to the game object instance of
      -- the script.
      -- It can be used to take action on the input, e.g. move the instance according to the input.
      -- For an instance to obtain user input, it must first acquire input focuse through the message `acquire_input_focus`.
      -- See the documentation of that message for more information.
      -- The `action` parameter is a table containing data about the input mapped to the `action_id`.
      -- For mapped actions it specifies the value of the input and if it was just pressed or released.
      -- Actions are mapped to input in an input_binding-file.
      -- Mouse movement is specifically handled and uses `nil` as its `action_id`.
      -- The `action` only contains positional parameters in this case, such as x and y of the pointer.
      -- </summary>
      -- <param name="action_id">id of the received input action, as mapped in the input_binding-file</param>
      -- <param name="action">a table containing the input data, see above for a description</param>
      -- <returns>boolean to signal if the input should be consumed (not passed on to others) or not, default is false</returns>
      on_input = function (this, action_id, action)
        return false
      end
      -- <summary>
      -- Called when the script component is reloaded.
      -- This is a callback-function, which is called by the engine when the script component is reloaded, e.g. from the
      -- editor.
      -- It can be used for live development, e.g. to tweak constants or set up the state properly for the instance.
      -- </summary>
      on_reload = function (this)
      end
      GetNode1 = function (this, id, TNode)
        local node = TNode()
        node:__assignproxy__(gui.get_node(id))
        return node
      end
      return {
        base = function (out)
          return {
            out.support.ScriptPropertyHost_1(TProps),
            out.support.IUserComponent
          }
        end,
        getLocatorUrl = getLocatorUrl,
        init = init,
        final = final,
        update = update,
        fixed_update = fixed_update,
        on_message = on_message,
        on_input = on_input,
        on_reload = on_reload,
        GetNode1 = GetNode1,
        __ctor__ = __ctor__,
        __metadata__ = function (out)
          return {
            properties = {
              { "LocatorUrl", 0x206, out.types.Url, getLocatorUrl }
            },
            methods = {
              { ".ctor", 0x3, nil },
              { "GetNode", 0x10183, GetNode1, function (TNode) return out.types.Hash, TNode end },
              { "final", 0x3, final },
              { "fixed_update", 0x103, fixed_update, System.Single },
              { "init", 0x3, init },
              { "on_input", 0x283, on_input, out.types.Hash, System.Object, System.Boolean },
              { "on_message", 0x303, on_message, out.types.Hash, System.Object, out.types.Hash },
              { "on_reload", 0x3, on_reload },
              { "update", 0x103, update, System.Single }
            },
            class = { 0x106, TProps }
          }
        end
      }
    end
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  -- <summary>
  -- Because Defold will establish properties on the self userobject, we have to create a proxy to source the properties
  -- from.
  -- </summary>
  namespace.class("AnimatableProperties", function (namespace)
    local __ctor__
    __ctor__ = function (this)
      System.throw(System.InvalidOperationException("Defold handles property construction. Do not call the constructor yourself!"))
    end
    return {
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          methods = {
            { ".ctor", 0x6, nil }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("LuaTableSerializableExt", function (namespace)
    local DefaultTableSerialization, DefaultTableDeserialization
    DefaultTableSerialization = function (self)
      local table = {}
      local metadata = self.__metadata__
      if metadata.fields then
        for _, value in ipairs(metadata.fields) do
          table[ value[1] ] = self[ value[1] ];
        end
      end
      if metadata.properties then
        for _, value in ipairs(metadata.properties) do
          --We want to skip over non-auto properties. Only auto-properties have implicit backing
          --if we have getters and/or setters, then we assume that the property state can be recostructed
          --from fields and other properties. 
          if #value <= 3 then
            table[ value[1] ] = self[ value[1] ];
          end
        end
      end			

      return table
    end
    DefaultTableDeserialization = function (self, T)
      local table = T()
      local metadata = table.__metadata__
      if metadata.fields then
        for _, value in ipairs(metadata.fields) do
          table[ value[1] ] = self[ value[1] ];
        end
      end
      if metadata.properties then
        for _, value in ipairs(metadata.properties) do
        	--We want to skip over non-auto properties. Only auto-properties have implicit backing
          --if we have getters and/or setters, then we assume that the property state can be recostructed
          --from fields and other properties. 
          if #value <= 3 then
            table[ value[1] ] = self[ value[1] ];
          end
        end
      end			

      return table
    end
    return {
      DefaultTableSerialization = DefaultTableSerialization,
      DefaultTableDeserialization = DefaultTableDeserialization,
      __metadata__ = function (out)
        return {
          methods = {
            { "DefaultTableDeserialization", 0x1018E, DefaultTableDeserialization, function (T) return out.types.ILuaTable, T end },
            { "DefaultTableSerialization", 0x18E, DefaultTableSerialization, out.types.ILuaTableSerializable, out.types.ILuaTable }
          },
          class = { 0xE }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("ScriptPropertyHost_1", function (namespace)
    return function (TProps)
      local AssignProperties, RequestInput, ReleaseInput
      AssignProperties = function (this, prop)
        this.Properties = prop
      end
      RequestInput = function (this)
        msg.post('.', 'acquire_input_focus')
        this.IsInputFocusHeld = true
      end
      ReleaseInput = function (this)
        this.IsInputFocusHeld = false
        msg.post('.', 'release_input_focus')
      end
      return {
        base = function (out)
          return {
            out.support.GeneratedScript
          }
        end,
        IsInputFocusHeld = false,
        AssignProperties = AssignProperties,
        RequestInput = RequestInput,
        ReleaseInput = ReleaseInput,
        __metadata__ = function (out)
          return {
            properties = {
              { "IsInputFocusHeld", 0x3, System.Boolean },
              { "Properties", 0x3, TProps }
            },
            methods = {
              { "AssignProperties", 0x103, AssignProperties, TProps },
              { "ReleaseInput", 0x3, ReleaseInput },
              { "RequestInput", 0x3, RequestInput }
            },
            class = { 0x106, TProps }
          }
        end
      }
    end
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("BufferStream", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("DataBuffer", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("GuiTextureType", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Hash", function (namespace)
    local op_Implicit, op_Implicit1
    op_Implicit = function (v)
      --Doesn't actually get called.  Instead the template is injected.  But we can't extern operators.
      return hash(v)
    end
    op_Implicit1 = function (v)
      --Doesn't actually get called.  Instead the template is injected.  But we can't extern operators.
      return v
    end
    return {
      op_Implicit = op_Implicit,
      op_Implicit1 = op_Implicit1,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)



  -- <summary>
  -- //Used so we can fool the C# compiler into allowing us more overrides.  Hash is the actual implementation and should be
  -- used in methods where possible.
  -- </summary>
  namespace.class("__Hash2", function (namespace)
    local op_Implicit1, ToHash
    op_Implicit1 = function (v)
      --Doesn't actually get called.  Instead the template is injected.  But we can't extern operators.
      return op_Implicit(hash(v))
    end
    ToHash = function (this)
      return nil
      --Not actually called.  
    end
    return {
      op_Implicit1 = op_Implicit1,
      ToHash = ToHash,
      __metadata__ = function (out)
        return {
          methods = {
            { "ToHash", 0x86, ToHash, out.types.Hash }
          },
          class = { 0x6 }
        }
      end
    }
  end)


  -- <summary>
  -- //Used so we can fool the C# compiler into allowing us more overrides.  Hash is the actual implementation and should be
  -- used in methods where possible.
  -- </summary>
  namespace.class("__Hash3", function (namespace)
    local op_Implicit1, ToHash
    op_Implicit1 = function (v)
      --Doesn't actually get called.  Instead the template is injected.  But we can't extern operators.
      return op_Implicit(hash(v))
    end
    ToHash = function (this)
      return nil
      --Not actually called.  
    end
    return {
      op_Implicit1 = op_Implicit1,
      ToHash = ToHash,
      __metadata__ = function (out)
        return {
          methods = {
            { "ToHash", 0x86, ToHash, out.types.Hash }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.interface("ILuaTable", function ()
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.interface("ILuaTableSerializable", function ()
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.interface("ILuaType", function ()
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("LuaArray", function (namespace)
    return {
      base = function (out)
        return {
          out.types.LuaTableOf_2(System.Int32, out.types.LuaType)
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("LuaArray_1", function (namespace)
    return function (TValue)
      return {
        base = function (out)
          return {
            out.types.LuaTableOf_2(System.Int32, TValue)
          }
        end,
        __metadata__ = function (out)
          return {
            class = { 0x106, TValue }
          }
        end
      }
    end
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("LuaTable", function (namespace)
    return {
      base = function (out)
        return {
          out.types.LuaTableOf_2(out.types.LuaType, out.types.LuaType),
          out.types.ILuaType
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("LuaTableBase", function (namespace)
    return {
      base = function (out)
        return {
          out.types.ILuaTable
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("LuaTableOf_2", function (namespace)
    return function (TKey, TValue)
      return {
        base = function (out)
          return {
            out.types.LuaTableBase
          }
        end,
        __metadata__ = function (out)
          return {
            class = { 0x206, TKey, TValue }
          }
        end
      }
    end
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("LuaType", function (namespace)
    local op_Implicit, op_Implicit1, op_Implicit2, op_Implicit3, op_Implicit4, op_Implicit5, op_Implicit6, op_Implicit7, 
    op_Implicit8, op_Implicit9, op_Implicit10, op_Implicit11
    op_Implicit = function (v)
      return nil
    end
    op_Implicit1 = function (v)
      return nil
    end
    op_Implicit2 = function (v)
      return nil
    end
    op_Implicit3 = function (v)
      return nil
    end
    op_Implicit4 = function (v)
      return nil
    end
    op_Implicit5 = function (v)
      return nil
    end
    op_Implicit6 = function (v)
      return nil
    end
    op_Implicit7 = function (v)
      return nil
    end
    op_Implicit8 = function (v)
      return nil
    end
    op_Implicit9 = function (v)
      return nil
    end
    op_Implicit10 = function (v)
      return nil
    end
    op_Implicit11 = function (v)
      return nil
    end
    return {
      op_Implicit = op_Implicit,
      op_Implicit1 = op_Implicit1,
      op_Implicit2 = op_Implicit2,
      op_Implicit3 = op_Implicit3,
      op_Implicit4 = op_Implicit4,
      op_Implicit5 = op_Implicit5,
      op_Implicit6 = op_Implicit6,
      op_Implicit7 = op_Implicit7,
      op_Implicit8 = op_Implicit8,
      op_Implicit9 = op_Implicit9,
      op_Implicit10 = op_Implicit10,
      op_Implicit11 = op_Implicit11,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Matrix4", function (namespace)
    return {
      base = function (out)
        return {
          out.types.ILuaType
        }
      end,
      x = 0,
      y = 0,
      u = 0,
      v = 0,
      __metadata__ = function (out)
        return {
          fields = {
            { "u", 0x6, System.Single },
            { "v", 0x6, System.Single },
            { "x", 0x6, System.Single },
            { "y", 0x6, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local types
System.import(function (out)
  types = out.types
end)
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Node", function (namespace)
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)

  namespace.class("NodeProxy", function (namespace)
    local __assignproxy__, op_Implicit
    __assignproxy__ = function (this, proxy)
      this._proxy = proxy
    end
    op_Implicit = function (p)
      return p._proxy
    end
    return {
      __assignproxy__ = __assignproxy__,
      op_Implicit = op_Implicit,
      __metadata__ = function (out)
        return {
          fields = {
            { "_proxy", 0x1, out.types.Node }
          },
          methods = {
            { "__assignproxy__", 0x104, __assignproxy__, out.types.Node }
          },
          class = { 0x6 }
        }
      end
    }
  end)

  namespace.class("TextNode", function (namespace)
    local GetText, SetText
    GetText = function (this)
      return gui.get_text(types.NodeProxy.op_Implicit(this))
    end
    SetText = function (this, text)
      gui.set_text(types.NodeProxy.op_Implicit(this), text)
    end
    return {
      base = function (out)
        return {
          out.types.NodeProxy
        }
      end,
      GetText = GetText,
      SetText = SetText,
      __metadata__ = function (out)
        return {
          methods = {
            { "GetText", 0x86, GetText, System.String },
            { "SetText", 0x106, SetText, System.String }
          },
          class = { 0x6 }
        }
      end
    }
  end)

  namespace.class("ButtonNode", function (namespace)
    return {
      base = function (out)
        return {
          out.types.NodeProxy
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Quaternion", function (namespace)
    return {
      base = function (out)
        return {
          out.types.ILuaType
        }
      end,
      x = 0,
      y = 0,
      z = 0,
      w = 0,
      __metadata__ = function (out)
        return {
          fields = {
            { "w", 0x1, System.Single },
            { "x", 0x1, System.Single },
            { "y", 0x1, System.Single },
            { "z", 0x1, System.Single }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  namespace.class("Rect", function (namespace)
    local InRect, __ctor__
    __ctor__ = function (this, x, y, width, height)
      this.X = x
      this.Y = y
      this.Width = width
      this.Height = height
    end
    InRect = function (this, targetX, targetY)
      return this.X <= targetX and targetX <= (this.X + this.Width) and this.Y <= targetY and targetY <= (this.Y + this.Height)
    end
    return {
      X = 0,
      Y = 0,
      Width = 0,
      Height = 0,
      InRect = InRect,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "Height", 0x6, System.Double },
            { "Width", 0x6, System.Double },
            { "X", 0x6, System.Double },
            { "Y", 0x6, System.Double }
          },
          methods = {
            { ".ctor", 0x406, nil, System.Double, System.Double, System.Double, System.Double },
            { "InRect", 0x286, InRect, System.Int32, System.Int32, System.Boolean }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Url", function (namespace)
    local __ctor1__, __ctor2__, __ctor3__
    __ctor1__ = function (this)
    end
    __ctor2__ = function (this, url)
    end
    __ctor3__ = function (this, socket, path, fragment)
    end
    return {
      base = function (out)
        return {
          out.types.ILuaType
        }
      end,
      __ctor__ = {
        __ctor1__,
        __ctor2__,
        __ctor3__
      },
      __metadata__ = function (out)
        return {
          fields = {
            { "fragment", 0x6, out.types.Hash },
            { "path", 0x6, out.types.Hash },
            { "socket", 0x6, out.types.Hash }
          },
          methods = {
            { ".ctor", 0x6, __ctor1__ },
            { ".ctor", 0x106, __ctor2__, System.String },
            { ".ctor", 0x306, __ctor3__, System.String, System.String, System.String }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Vector2", function (namespace)
    local op_Implicit
    op_Implicit = function (v)
      return nil
    end
    return {
      base = function (out)
        return {
          out.types.ILuaType
        }
      end,
      x = 0,
      y = 0,
      op_Implicit = op_Implicit,
      __metadata__ = function (out)
        return {
          fields = {
            { "x", 0x6, System.Double },
            { "y", 0x6, System.Double }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Vector3", function (namespace)
    return {
      base = function (out)
        return {
          out.types.ILuaType
        }
      end,
      x = 0,
      y = 0,
      z = 0,
      __metadata__ = function (out)
        return {
          fields = {
            { "x", 0x6, System.Double },
            { "y", 0x6, System.Double },
            { "z", 0x6, System.Double }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("types", function (namespace)
  -- <summary>
  -- </summary>
  namespace.class("Vector4", function (namespace)
    return {
      base = function (out)
        return {
          out.types.ILuaType
        }
      end,
      x = 0,
      y = 0,
      u = 0,
      v = 0,
      __metadata__ = function (out)
        return {
          fields = {
            { "u", 0x6, System.Double },
            { "v", 0x6, System.Double },
            { "x", 0x6, System.Double },
            { "y", 0x6, System.Double }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("BuiltInComponentBase", function (namespace)
    local getLocatorUrl, setLocatorUrl, AssignLocator, op_Implicit
    getLocatorUrl, setLocatorUrl = System.property("LocatorUrl")
    AssignLocator = function (this, locator)
      this.LocatorUrl = locator:FetchUrl()
    end
    op_Implicit = function (self)
      return getLocatorUrl(self)
    end
    return {
      base = function (out)
        return {
          out.support.IBuiltInComponent
        }
      end,
      getLocatorUrl = getLocatorUrl,
      setLocatorUrl = setLocatorUrl,
      AssignLocator = AssignLocator,
      op_Implicit = op_Implicit,
      __metadata__ = function (out)
        return {
          properties = {
            { "LocatorUrl", 0x106, out.types.Url, getLocatorUrl, setLocatorUrl }
          },
          methods = {
            { "AssignLocator", 0x106, AssignLocator, out.support.Locator }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
local support
local supportComponent
local types
local DictUrlComponentRecord
System.import(function (out)
  support = out.support
  supportComponent = support.Component
  types = out.types
  DictUrlComponentRecord = System.Dictionary(types.Url, supportComponent.ComponentRecord)
end)
System.namespace("support", function (namespace)
  -- <summary>
  -- Generic access for both builtin components and user components.
  -- </summary>
  namespace.class("Component", function (namespace)
    local ComponentsByLocator, builtInType, userComponentType, Register, Unregister, At, AtUser, AtBuiltIn, 
    class, static
    namespace.class("ComponentRecord", function (namespace)
      local __ctor__
      __ctor__ = function (this, type, data)
        this.type = type
        this.data = data
      end
      return {
        __ctor__ = __ctor__,
        __metadata__ = function (out)
          return {
            fields = {
              { "data", 0x6, System.Object },
              { "type", 0x6, System.Type }
            },
            methods = {
              { ".ctor", 0x206, nil, System.Type, System.Object }
            },
            class = { 0x1 }
          }
        end
      }
    end)
    static = function (this)
      ComponentsByLocator = DictUrlComponentRecord()
      builtInType = System.typeof(support.IBuiltInComponent)
      userComponentType = System.typeof(support.IUserComponent)
    end
    Register = function (locator, data, TComponent)
      local newRecord = class.ComponentRecord(System.typeof(TComponent), data)
      ComponentsByLocator:AddKeyValue(locator, newRecord)
    end
    Unregister = function (locator)
      ComponentsByLocator:RemoveKey(locator)
    end
    At = function (locator, TComponent)
      if builtInType:IsAssignableFrom(System.typeof(TComponent)) then
        return AtBuiltIn(locator, TComponent)
      end

      if userComponentType:IsAssignableFrom(System.typeof(TComponent)) then
        return AtUser(locator, TComponent)
      end

      pprint("Unhandled component type!  " .. System.typeof(TComponent):getName())
      System.throw(System.NotImplementedException())
    end
    -- <summary>
    -- Specialized variant that will handle a USERCOMPONENT only.  But exists as an unsafe private that supposedly
    -- allows any component.  However, it really only supports IUserComponent.
    -- </summary>
    -- <param name="locator"></param>
    -- <typeparam name="TComponent"></typeparam>
    -- <returns></returns>
    -- <exception cref="InvalidCastException"></exception>
    -- <exception cref="KeyNotFoundException"></exception>
    AtUser = function (locator, TComponent)
      local url = locator:FetchUrl()

      local default, existingRecord = ComponentsByLocator:TryGetValue(url, nil)
      if default then
        if not existingRecord.type:IsAssignableTo(System.typeof(TComponent)) then
          System.throw(System.InvalidCastException("Requesting component of type " .. System.typeof(TComponent):getName() .. ", but record for component is " .. existingRecord.type:getName()))
        else
          return existingRecord.data
        end
      else
        pprint("Component of type (" .. System.typeof(TComponent):getName() .. ") at the specified address could not be found.")
        pprint(url)
        System.throw(System.KeyNotFoundException())
      end
    end
    -- <summary>
    -- Specialized variant that will handle a USERCOMPONENT only.  But exists as an unsafe private that supposedly
    -- allows any component.  However, it really only supports IBuiltInComponent.
    -- </summary>
    -- <param name="locator"></param>
    -- <typeparam name="TComponent"></typeparam>
    -- <returns></returns>
    -- <exception cref="InvalidCastException"></exception>
    -- <exception cref="KeyNotFoundException"></exception>
    AtBuiltIn = function (locator, TComponent)
      local url = locator:FetchUrl()


      --Built in components are not cached, because we cannot determine when they are cleared.

      local newComponent = TComponent()
      newComponent:AssignLocator(locator)
      Register(url, newComponent, TComponent)
      return newComponent
    end
    class = {
      DefaultToCaching = true,
      Register = Register,
      Unregister = Unregister,
      At = At,
      static = static,
      __metadata__ = function (out)
        return {
          fields = {
            { "ComponentsByLocator", 0x9, System.Dictionary(out.types.Url, out.support.Component.ComponentRecord) },
            { "DefaultToCaching", 0xE, System.Boolean },
            { "builtInType", 0x9, System.Type },
            { "userComponentType", 0x9, System.Type }
          },
          methods = {
            { "At", 0x1018E, At, function (TComponent) return out.support.Locator, TComponent end },
            { "AtBuiltIn", 0x10189, AtBuiltIn, function (TComponent) return out.support.Locator, TComponent end },
            { "AtUser", 0x10189, AtUser, function (TComponent) return out.support.Locator, TComponent end },
            { "Register", 0x1020E, Register, function (TComponent) return out.types.Url, TComponent end },
            { "Unregister", 0x10E, Unregister, out.types.Url }
          },
          class = { 0xE }
        }
      end
    }
    return class
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("ComponentLocator", function (namespace)
    local FetchUrl, __ctor1__, __ctor2__, __ctor3__
    __ctor1__ = function (this, url)
      this._url = url
    end
    -- <summary>
    -- Resolves the component relative to the current game object.
    -- </summary>
    -- <param name="componentName"></param>
    __ctor2__ = function (this, componentName)
      local url = msg.url()
      url.path = go.get_id()
      url.fragment = hash(componentName)
      this._url = url
    end
    -- <summary>
    -- Resolves the component relative to the specified game object
    -- </summary>
    -- <param name="gameobjectPath"></param>
    -- <param name="componentName"></param>
    __ctor3__ = function (this, gameobjectPath, componentName)
      local url = msg.url()
      url.path = go.get_id(gameobjectPath)
      url.fragment = hash(componentName)
      this._url = url
    end
    FetchUrl = function (this)
      return this._url
    end
    return {
      FetchUrl = FetchUrl,
      __ctor__ = {
        __ctor1__,
        __ctor2__,
        __ctor3__
      },
      __metadata__ = function (out)
        return {
          fields = {
            { "_url", 0x1, out.types.Url }
          },
          methods = {
            { ".ctor", 0x106, __ctor1__, out.types.Url },
            { ".ctor", 0x106, __ctor2__, System.String },
            { ".ctor", 0x206, __ctor3__, System.String, System.String },
            { "FetchUrl", 0x86, FetchUrl, out.types.Url }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("ComponentReference", function (namespace)
    local AssignLocatorInternal, op_Implicit
    AssignLocatorInternal = function (this, locator)
      this.Locator = this.Locator
    end
    op_Implicit = function (self)
      return self.Locator
    end
    return {
      AssignLocatorInternal = AssignLocatorInternal,
      op_Implicit = op_Implicit,
      __metadata__ = function (out)
        return {
          properties = {
            { "Locator", 0x6, out.types.Url }
          },
          methods = {
            { "AssignLocatorInternal", 0x103, AssignLocatorInternal, out.types.Url }
          },
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.interface("IBuiltInComponent", function ()
    return {
      base = function (out)
        return {
          out.support.IComponent
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.interface("ICachedData", function ()
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.interface("IComponent", function ()
    return {
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.interface("IUserComponent", function ()
    return {
      base = function (out)
        return {
          out.support.IComponent
        }
      end,
      __metadata__ = function (out)
        return {
          class = { 0x6 }
        }
      end
    }
  end)
end)

end
do
local System = System
System.namespace("support", function (namespace)
  namespace.class("Locator", function (namespace)
    local FetchUrl, AtUrl, AtComponent, AtComponent1, class, __ctor__
    __ctor__ = function (this, url)
      this._url = url
    end
    FetchUrl = function (this)
      return this._url
    end
    AtUrl = function (url)
      return class(url)
    end
    AtComponent = function (componentName)
      local url = msg.url()
      url.path = go.get_id()
      url.fragment = hash(componentName)
      return class(url)
    end
    AtComponent1 = function (gameobjectPath, componentName)
      local url = msg.url()
      url.path = go.get_id(gameobjectPath)
      url.fragment = hash(componentName)
      return class(url)
    end
    class = {
      FetchUrl = FetchUrl,
      AtUrl = AtUrl,
      AtComponent = AtComponent,
      AtComponent1 = AtComponent1,
      __ctor__ = __ctor__,
      __metadata__ = function (out)
        return {
          fields = {
            { "_url", 0x1, out.types.Url }
          },
          methods = {
            { ".ctor", 0x101, nil, out.types.Url },
            { "AtComponent", 0x18E, AtComponent, System.String, class },
            { "AtComponent", 0x28E, AtComponent1, System.String, System.String, class },
            { "AtUrl", 0x18E, AtUrl, out.types.Url, class },
            { "FetchUrl", 0x86, FetchUrl, out.types.Url }
          },
          class = { 0x6 }
        }
      end
    }
    return class
  end)
end)

end
System.init({
  types = {
    "support.GeneratedScript",
    "support.IComponent",
    "support.ScriptPropertyHost_1",
    "support.IUserComponent",
    "support.IBuiltInComponent",
    "support.AnimatableProperties",
    "types.ILuaTable",
    "support.GameObjectScript_1",
    "support.GUIScript_1",
    "types.ILuaTableSerializable",
    "support.BuiltInComponentBase",
    "FPSProperties",
    "types.LuaTableBase",
    "support.GameObjectScript",
    "support.GUIScript",
    "Camera",
    "MessageImplementation",
    "CollectionFactory",
    "CollectionProxy",
    "FPS",
    "IBunnymark",
    "Go",
    "Gui",
    "Model",
    "Physics",
    "Render",
    "Scenes.AnimateMultipleCollectionProps",
    "Sound",
    "Sprite",
    "Sys",
    "attributes.PropertyProxyHandling",
    "support.Component",
    "types.NodeProxy",
    "types.LuaTableOf_2",
    "types.LuaType",
    "types.ILuaType",
    "Buffer",
    "Builtins",
    "Bunny_Update",
    "Bunnymark",
    "BunnymarkGoAnimate",
    "BunnymarkGuiAnimate",
    "BunnymarkManyUpdates",
    "BunnymarkParticleFx",
    "BunnymarkSingleUpdate",
    "Bunnymark_GUI",
    "Camera.acquire_camera_focus_message",
    "Camera.release_camera_focus_message",
    "Camera.set_camera_message",
    "CollectionFactory.CollectionFactoryCreateResult",
    "CollectionProxy.async_load_message",
    "CollectionProxy.disable_message",
    "CollectionProxy.enable_message",
    "CollectionProxy.final_message",
    "CollectionProxy.init_message",
    "CollectionProxy.load_message",
    "CollectionProxy.proxy_loaded_message",
    "CollectionProxy.proxy_unloaded_message",
    "CollectionProxy.set_time_step_message",
    "CollectionProxy.unload_message",
    "Crash",
    "Debug",
    "FPS.SimpleMovingAverage",
    "Facebook",
    "Factory",
    "FactoryBasedBunnymark",
    "Go.acquire_input_focus_message",
    "Go.disable_message",
    "Go.enable_message",
    "Go.release_input_focus_message",
    "Go.set_parent_message",
    "GoBunny",
    "Gui.layout_changed_message",
    "GuiAnimateGui",
    "GuiBasedBunnymark",
    "GuiBunny",
    "Html5",
    "Http",
    "Iac",
    "Iap",
    "Image",
    "Json",
    "Label",
    "Math",
    "Message",
    "Model.model_animation_done_message",
    "Msg",
    "OS",
    "Particlefx",
    "Physics.apply_force_message",
    "Physics.collision_response_message",
    "Physics.contact_point_response_message",
    "Physics.ray_cast_missed_message",
    "Physics.ray_cast_response_message",
    "Physics.trigger_response_message",
    "Profiler",
    "Push",
    "Render.clear_color_message",
    "Render.draw_debug_text_message",
    "Render.draw_line_message",
    "Render.resize_message",
    "Render.window_resized_message",
    "Resource",
    "Scenes.BunnymarkAnimateMultiple",
    "Scenes.BunnymarkAnimateMultipleCollection",
    "Sound.play_sound_message",
    "Sound.set_gain_message",
    "Sound.sound_done_message",
    "Sound.stop_sound_message",
    "Sprite.animation_done_message",
    "Sprite.play_animation_message",
    "Sys.exit_message",
    "Sys.reboot_message",
    "Sys.set_update_frequency_message",
    "Sys.set_vsync_message",
    "Sys.start_record_message",
    "Sys.stop_record_message",
    "Sys.toggle_physics_debug_message",
    "Sys.toggle_profile_message",
    "Tilemap",
    "Timer",
    "Vmath",
    "Webview",
    "Window",
    "Zlib",
    "attributes.DefoldPropertyProxyGenAttribute",
    "attributes.DoNotGenerateAttribute",
    "support.Component.ComponentRecord",
    "support.ComponentLocator",
    "support.ComponentReference",
    "support.DoNotGenerateAttribute",
    "support.GameObjectReference",
    "support.ICachedData",
    "support.Locator",
    "support.LuaTableSerializableExt",
    "types.BufferStream",
    "types.ButtonNode",
    "types.DataBuffer",
    "types.GuiTextureType",
    "types.Hash",
    "types.LuaArray",
    "types.LuaArray_1",
    "types.LuaTable",
    "types.Matrix4",
    "types.Node",
    "types.Quaternion",
    "types.Rect",
    "types.TextNode",
    "types.Url",
    "types.Vector2",
    "types.Vector3",
    "types.Vector4",
    "types.__Hash2",
    "types.__Hash3"
  }
})

