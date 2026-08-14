#!/usr/bin/env lua
-- Every addon file must compile.
--
-- This exists because Lua caps a chunk at 200 local variables and Shinkili.lua
-- is one long chunk: crossing that limit produces a file that luacheck happily
-- reports as clean while the game refuses to load the addon at all. luacheck
-- does not catch it; loadfile does.

local root = arg[0]:match("(.*/)")

local files = {
    "ShinkiliLocale",
    "ShinkiliLogic",
    "ShinkiliSecret",
    "ShinkiliTrack",
    "ShinkiliEval",
    "ShinkiliVitals",
    "ShinkiliSimcData",
    "Shinkili",
}

local failures = 0

-- The TOC is the real load order; a file present here but missing there (or
-- vice versa) means the addon loads something different from what we tested.
local toc = io.open(root .. "../Shinkili/Shinkili.toc")
local tocOrder = {}
if toc then
    for line in toc:lines() do
        local name = line:match("^(%S+)%.lua%s*$")
        if name then
            tocOrder[#tocOrder + 1] = name
        end
    end
    toc:close()
end

for index, name in ipairs(files) do
    local path = root .. "../Shinkili/" .. name .. ".lua"
    local chunk, err = loadfile(path)
    if chunk then
        print("  OK  " .. name .. ".lua compiles")
    else
        failures = failures + 1
        print("  FAIL  " .. name .. ".lua — " .. tostring(err))
    end
    if tocOrder[index] ~= name then
        failures = failures + 1
        print(string.format("  FAIL  TOC order slot %d is %s, expected %s",
            index, tostring(tocOrder[index]), name))
    end
end

if #tocOrder ~= #files then
    failures = failures + 1
    print(string.format("  FAIL  TOC lists %d files, suite covers %d", #tocOrder, #files))
else
    print("  OK  TOC load order matches")
end

-- Headroom, not just "does it compile today". Shinkili.lua is one chunk and the
-- cap is 200 locals; landing exactly at the limit means the next top-level
-- `local` anyone adds makes the addon fail to load, with luacheck still green.
local MIN_FREE_LOCAL_SLOTS = 4
local handle = io.open(root .. "../Shinkili/Shinkili.lua")
local source = handle and handle:read("a") or nil
if handle then
    handle:close()
end
local compile = load or loadstring
local free = 0
if source and compile then
    for extra = 1, MIN_FREE_LOCAL_SLOTS do
        local padded = source
        for i = 1, extra do
            padded = padded .. "\nlocal __probe" .. i
        end
        if not compile(padded) then
            break
        end
        free = extra
    end
end
if free >= MIN_FREE_LOCAL_SLOTS then
    print(string.format("  OK  Shinkili.lua has at least %d free local slots", MIN_FREE_LOCAL_SLOTS))
else
    failures = failures + 1
    print(string.format("  FAIL  Shinkili.lua has only %d free local slots (want >= %d)",
        free, MIN_FREE_LOCAL_SLOTS))
end

if failures > 0 then
    print(string.format("%d failure(s)", failures))
    os.exit(1)
end
print("all passed")
