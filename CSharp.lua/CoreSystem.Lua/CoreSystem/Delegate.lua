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

local System = System
local throw = System.throw
local ArgumentNullException = System.ArgumentNullException

local setmetatable = setmetatable
local getmetatable = getmetatable
local assert = assert
local select = select
local type = type
local unpack = table.unpack

local Delegate = {}
debug.setmetatable(System.emptyFn, Delegate)

local multicast = setmetatable({}, Delegate)
multicast.__index = multicast

function multicast.__call(t, ...)
  local result
  for i = 1, #t do
    result = t[i](...)
  end
  return result
end

local function appendFn(t, f)
  local count = #t + 1
  if getmetatable(f) == multicast then
    for i = 1, #f do
      t[count] = f[i]
      count = count + 1
    end
  else
    t[count] = f
  end
end

local function combineImpl(fn1, fn2)    
  local t = setmetatable({}, multicast)
  appendFn(t, fn1)
  appendFn(t, fn2)
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

Delegate.Combine = combine

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
  if getmetatable(fn2) ~= multicast then
    if getmetatable(fn1) ~= multicast then
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
  elseif getmetatable(fn1) == multicast then
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

Delegate.Remove = remove

function Delegate.RemoveAll(source, value)
  local newDelegate
  repeat
    newDelegate = source
    source = remove(source, value)
  until newDelegate == source
  return newDelegate
end

function Delegate.DynamicInvoke(this, ...)
  return this(...)
end

local function equals(fn1, fn2)
  if getmetatable(fn1) == multicast then
    if getmetatable(fn2) == multicast then
      local len1, len2 = #fn1, #fn2
      if len1 ~= len2 then
        return false         
      end
      for i = 1, len1 do
        if fn1[i] ~= fn2[2] then
          return false
        end
      end
      return true
    end
    return false
  end
  if getmetatable(fn2) == multicast then return false end
  return fn1 == fn2
end

Delegate.__add = combine
multicast.__add = combine

Delegate.__sub = remove
multicast.__sub = remove

multicast.__eq = equals
 
local metatableOfNil = debug.getmetatable(nil)
 metatableOfNil.__add = function (a, b)
  if a == nil then
    if b == nil or type(b) == "number" then
      return nil
    end
    return b
  end
  return nil
 end

function Delegate.EqualsObj(this, obj)
  local typename = type(obj)
  if typename == "function" then
    return equals(this, obj)
  end
  if typename == "table" then
    local metatable = getmetatable(obj)
    if metatable == multicast then
      return equals(this, obj)
    end
  end
  return false
end

function Delegate.GetType(this)
  return System.typeof(Delegate)
end

local multiKey = System.multiKey

local mt = {}
local function makeGenericTypes(...)
  local gt, gk = multiKey(mt, ...)
  local t = gt[gk]
  if t == nil then
    t = setmetatable({ ... }, Delegate)
    gt[gk] = t
  end
  return t
end

System.define("System.Delegate", Delegate)
setmetatable(Delegate, { __index = System.Object, __call = makeGenericTypes })

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
  local gt, gk = multiKey(binds, f, ...)
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
  local gt, gk = multiKey(binds, f, create)
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
    return f(x1, x2, T1, T2)
  end
end

function System.bind0_2(f)
  return bind(f, create0_2) 
end
