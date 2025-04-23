--[[
    Security Monitoring Module
    
    This module tracks and monitors access to Roblox objects, functions, and properties
    to help detect potential data exfiltration or unauthorized access.
]]

-- Store the initial environment
local Environment = getfenv()
local game = game
local HttpService = game:GetService("HttpService")

-- Type definitions
type EmulationProperties = { [string]: (...any) -> any }

-- Module state
local SpoofedFunctions = {}
local SpoofedLibraries = {}
local Cache = {}
local ProxyCache = setmetatable({}, { __mode = "v" }) -- Weak values to allow garbage collection

-- Data exfiltration tracking
local ExfiltrationLog = {}
local ExfiltrationCount = 0
local MAX_LOG_ENTRIES = 1000

------------------------------------------
-- Utility Functions
------------------------------------------

-- Safely converts value to string (removed for now, add it back if u need it)
local function SafeToString(value)
    return tostring(value)
end

-- Removes null characters and escape sequences from strings
local function sanitizeString(str)
    if type(str) ~= "string" then
        return str
    end
    str = str:gsub("%z", "")
    str = str:gsub("\\%d+", "")
    return str
end

-- Prevents duplicate warning messages
local Cached
local function repetitionSafeWarn(message)
    if Cached ~= message then
        warn(message)
        Cached = message
    end
end

-- Generates a unique identifier for objects, functions, or instances
local function getObjectId(value)
    if typeof(value) == "Instance" then
        local path, id = "", ""
        pcall(function()
            path = value:GetFullName()
        end)
        pcall(function()
            id = value.UniqueId or value:GetDebugId()
        end)
        return path .. ":" .. SafeToString(id)
    elseif type(value) == "function" then
        local name = debug.info(value, "n") or ""
        local addr = SafeToString(value):match("function: (.+)") or SafeToString(value)
        return "func:" .. name .. ":" .. addr
    end
    return "obj:" .. SafeToString(value)
end

-- Checks if an object is a proxy
local function isProxy(userdata)
    local original
    local ok = pcall(function()
        original = userdata.__originalObject
    end)
    return ok and original ~= nil
end

-- Forward declaration
local createObjectProxy

------------------------------------------
-- Logging Functions
------------------------------------------

-- Displays exfiltration data in formatted ASCII columns
local function printExfiltrationLog()
    -- Define column widths
    local colWidths = {
        index = 5,     -- INDEX
        timestamp = 19, -- TIMESTAMP
        path = 26,     -- OBJECT PATH
        action = 34,   -- ACTION
        type = 8,      -- TYPE
        value = 55     -- VALUE
    }

    -- Create borders and dividers with appropriate widths
    local header = "┌" .. string.rep("─", colWidths.index) .. "┬" .. 
        string.rep("─", colWidths.timestamp) .. "┬" .. 
        string.rep("─", colWidths.path) .. "┬" .. 
        string.rep("─", colWidths.action) .. "┬" .. 
        string.rep("─", colWidths.type) .. "┬" .. 
        string.rep("─", colWidths.value) .. "┐"

    local divider = "├" .. string.rep("─", colWidths.index) .. "┼" .. 
        string.rep("─", colWidths.timestamp) .. "┼" .. 
        string.rep("─", colWidths.path) .. "┼" .. 
        string.rep("─", colWidths.action) .. "┼" .. 
        string.rep("─", colWidths.type) .. "┼" .. 
        string.rep("─", colWidths.value) .. "┤"

    local footer = "└" .. string.rep("─", colWidths.index) .. "┴" .. 
        string.rep("─", colWidths.timestamp) .. "┴" .. 
        string.rep("─", colWidths.path) .. "┴" .. 
        string.rep("─", colWidths.action) .. "┴" .. 
        string.rep("─", colWidths.type) .. "┴" .. 
        string.rep("─", colWidths.value) .. "┘"

    -- Helper function to format a column with proper padding
    local function formatColumn(text, width)
        text = SafeToString(text or "")
        if #text > width then
            text = text:sub(1, width - 3) .. "..."
        end
        return text .. string.rep(" ", width - #text)
    end

    -- Print the header
    print(header)

    -- Print column titles with proper spacing
    local titles = "│" .. formatColumn("INDEX", colWidths.index) .. 
        "│" .. formatColumn("TIMESTAMP", colWidths.timestamp) .. 
        "│" .. formatColumn("OBJECT PATH", colWidths.path) .. 
        "│" .. formatColumn("ACTION", colWidths.action) .. 
        "│" .. formatColumn("TYPE", colWidths.type) .. 
        "│" .. formatColumn("VALUE", colWidths.value) .. "│"
    print(titles)

    print(divider)

    -- Print each log entry with proper formatting
    for i, entry in ipairs(ExfiltrationLog) do
        local row = "│" .. formatColumn(i, colWidths.index) .. 
            "│" .. formatColumn(entry.timestamp, colWidths.timestamp) .. 
            "│" .. formatColumn(entry.path, colWidths.path) .. 
            "│" .. formatColumn(entry.action, colWidths.action) .. 
            "│" .. formatColumn(entry.type or "", colWidths.type) .. 
            "│" .. formatColumn(type(entry.value) == 'table' and `args:\{\ {unpack(entry.value)} \}\ ` or entry.value, colWidths.value) .. "│"
        print(row, type(entry.value) == 'table' and entry.value or '')

        -- Add a divider every 5 entries for readability
        if i % 1 == 0 and i < #ExfiltrationLog then
            print(divider)
        end
    end

    print(footer, '\n\n\n\n\n')
end

-- Records data access, function calls, and property changes for tracking
local function logExfiltration(path, value, action, typeInfo, args)
    ExfiltrationCount = ExfiltrationCount + 1

    -- Format timestamp as YYYY-MM-DD HH:MM:SS
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")

    -- Convert value to string safely, truncate if needed
    local valueStr = type(value) == "string" and value or SafeToString(value)
    if #valueStr > 100 then
        valueStr = valueStr:sub(1, 97) .. "..."
    end

    -- Record the exfiltration with new fields
    table.insert(ExfiltrationLog, {
        index = ExfiltrationCount,
        timestamp = timestamp,
        path = path,
        action = action,
        value = (type(value) == 'table' and value) or valueStr,
        type = typeInfo or type(value),
        args = args or ""
    })

    -- Keep log size reasonable
    if #ExfiltrationLog > MAX_LOG_ENTRIES then
        table.remove(ExfiltrationLog, 1)
    end

    -- Print updated log if configured to do so
    if ExfiltrationLog.autoDisplay then
        printExfiltrationLog()
    end
end

------------------------------------------
-- Proxy Creation
------------------------------------------

-- Creates a proxy wrapper around any Roblox object to track access and operations
createObjectProxy = function(value)
    local id = getObjectId(value)
    if ProxyCache[id] then
        return ProxyCache[id]
    end

    if value == game then
        return SpoofedLibraries['game']
    end

    local proxy = newproxy(true)
    local metatable = getmetatable(proxy)

    metatable.__originalObject = value

    -- Track object creation
    local objectPath = ""
    local typeInfo = typeof(value)

    pcall(function()
        if typeof(value) == "Instance" then
            objectPath = value:GetFullName()
            logExfiltration(objectPath, value, "Create proxy", typeInfo, "")
        else
            logExfiltration("unknown", value, "Create proxy", typeInfo, "")
        end
    end)

    pcall(function()
        if typeof(value) == "Instance" then
            metatable.__proxyName = value.Name
            metatable.__proxyId = value.UniqueId or value:GetDebugId()
        end
    end)

    metatable.__index = function(_, index)
        index = sanitizeString(index)

        -- Check if trying to access the original object
        if index == "__originalObject" then
            return value
        end

        -- Track property access
        local accessPath = ""
        pcall(function()
            if typeof(value) == "Instance" then
                accessPath = value:GetFullName() .. "." .. tostring(index)
            else
                accessPath = tostring(value) .. "." .. tostring(index)
            end

            logExfiltration(accessPath, value[index], "Get", typeof(value[index]), "")
        end)

        -- Handle function access
        if type(value[index]) == 'function' then
            return function(self, ...)
                local Arguments = {...}

                for i,v in next, Arguments do
                    Arguments[i] = (type(v) == 'userdata' and isProxy(v) and v.__originalObject) or v
                end

                if self == proxy then
                    return value[index](value, unpack(Arguments))
                else
                    return value[index](unpack(Arguments))
                end
            end
        end

        -- Return the actual property value or proxy for objects
        local propValue = value[index]
        if type(propValue) == "table" or typeof(propValue) == "Instance" or type(propValue) == "userdata" then
            return createObjectProxy(propValue)
        else
            return propValue
        end
    end

    metatable.__newindex = function(_, i, v)
        -- Track property setting
        local setPath = ""
        local valueType = type(v)

        pcall(function()
            if typeof(value) == "Instance" then
                setPath = value:GetFullName() .. "." .. tostring(i)
            else
                setPath = tostring(value) .. "." .. tostring(i)
            end

            local valueStr = SafeToString(v)
            logExfiltration(setPath, v, "Set", valueType, "")
        end)

        value[i] = (isProxy(v) and v.__originalObject) or v
    end

    metatable.__call = function(_, ...)
        local args = {...}
        local argStr = ""
        for i, arg in ipairs(args) do
            if i > 1 then argStr = argStr .. ", " end
            argStr = argStr .. SafeToString(arg)
            if #argStr > 50 then
                argStr = argStr:sub(1, 47) .. "..."
                break
            end
        end

        logExfiltration(id, argStr, "Call", type(value), argStr)

        local result = value(...)
        local resultType = type(result)

        -- Log the result
        pcall(function()
            local resultStr = SafeToString(result)
            logExfiltration(id, result, "CallResult", resultType, argStr)
        end)

        return result
    end

    metatable.__tostring = function()
        logExfiltration(id, value, "ToString", type(value), "")
        return tostring(value)
    end

    metatable.__metatable = "The metatable is locked"

    ProxyCache[id] = proxy
    return proxy
end

------------------------------------------
-- Core Module Functions
------------------------------------------

-- Registers custom implementations for spoofed functions
local function setSpoofedFunctions(map)
    for name, implementation in pairs(map) do
        SpoofedFunctions[name] = implementation
    end
end

-- Creates a proxy wrapper for Roblox libraries with custom method implementations
local function createEmulatedLibrary(original, custom)
    local objectId = getObjectId(original)
    if ProxyCache[objectId] then
        return ProxyCache[objectId]
    end

    local wrapper = setmetatable({}, {
        __index = function(_, idx)
            return _
        end,
        __call = function(_, target)
            local targetId = getObjectId(target)
            if ProxyCache[targetId] then
                return ProxyCache[targetId]
            end

            local p = newproxy(true)
            local proxyMetatable = getmetatable(p)

            proxyMetatable.__originalObject = target

            proxyMetatable.__index = function(_, i)                
                -- Track access to library methods
                local accessPath = target.Name .. "." .. tostring(i)
                logExfiltration(accessPath, target[i], "LibAccess", typeof(target[i]), "")

                for propertyName, fn in pairs(custom) do
                    if rawequal(i, propertyName) then
                        return fn
                    end
                end

                if rawequal(i, '__originalObject') then
                    return target
                end

                local value = target[i]
                local valueType = type(value)

                if type(value) == "function" then
                    return function(_, ...)
                        local args = {...}
                        local argStr = ""
                        for i, arg in ipairs(args) do
                            if i > 1 then argStr = argStr .. ", " end
                            argStr = argStr .. SafeToString(arg)
                            if #argStr > 50 then
                                argStr = argStr:sub(1, 47) .. "..."
                                break
                            end
                        end

                        logExfiltration(accessPath, args, "LibFuncCall", valueType, args)

                        local result = value(target, ...)
                        local resultType = type(result)

                        if typeof(result) == 'Instance' then
                            pcall(function()
                                result = createObjectProxy(result)
                            end)
                        end

                        -- Log the result
                        pcall(function()
                            local resultStr = SafeToString(result)
                            logExfiltration(accessPath, resultStr, "LibReturn", resultType, args)
                        end)

                        return result
                    end
                end

                return typeof(value) == "Instance" and createObjectProxy(value) or value
            end

            proxyMetatable.__newindex = function(_, i, v)
                -- Track library property setting
                local setPath = target.Name .. "." .. tostring(i)
                local valueStr = SafeToString(v)
                local valueType = type(v)

                logExfiltration(setPath, valueStr, "LibSet", valueType, "")

                target[i] = isProxy(v) and v.__originalObject or v
            end

            proxyMetatable.__tostring = function()
                logExfiltration(targetId, tostring(target), "LibToString", type(target), "")
                return tostring(target)
            end

            proxyMetatable.__metatable = "The metatable is locked"

            ProxyCache[targetId] = p
            return p
        end
    })

    local emulatedLibrary = wrapper(original)
    ProxyCache[objectId] = emulatedLibrary

    SpoofedLibraries[original.Name or ""] = emulatedLibrary
    if original == game then
        SpoofedLibraries['game'] = emulatedLibrary
    end

    return emulatedLibrary
end

-- Setup the Instance.new proxy
local originalInstanceNew = Instance.new
SpoofedFunctions["Instance"] = {
    new = function(className, parent)
        local argStr = className .. (parent and (", " .. SafeToString(parent)) or "")
        logExfiltration("Instance.new", argStr, "Create", "function", argStr)
        local newInstance = originalInstanceNew(className, parent)
        return createObjectProxy(newInstance)
    end
}

-- Initializes a protected environment with tracking for all accessed values
local function initEnvironment(customData)
    logExfiltration("Environment", "Initializing", "Init", "environment", "")

    local env = setmetatable({ script = Environment.script }, {
        __index = function(_, idx)
            logExfiltration("Environment", tostring(idx), "EnvAccess", "index", "")

            if not Cache[idx] then
                Cache[idx] = customData[idx] or SpoofedFunctions[idx] or Environment[idx]
            end

            local value = Cache[idx]
            return value
        end,

        __newindex = function(_, idx, newValue)
            local valueType = type(newValue)
            logExfiltration("Environment", tostring(idx) .. " = " .. SafeToString(newValue), "EnvSet", valueType, "")
            Environment[idx] = newValue
            return Environment[idx]
        end,

        __metatable = "The metatable is locked",
        __tostring = function()
            logExfiltration("Environment", "toString", "EnvToString", "environment", "")
            return tostring(Environment)
        end,
        __type = "userdata",
        __len = function()
            logExfiltration("Environment", "length", "EnvLen", "length", "")
            return 0
        end,
    })

    return env
end

-- Replaces the current environment with a new one
local function overwriteEnvironment(newEnv)
    logExfiltration("Environment", "Overwriting", "Overwrite", "environment", "")
    Environment = newEnv
    return Environment
end

-- Clears all cached proxies to free memory
local function clearProxyCache()
    logExfiltration("ProxyCache", "Clearing", "Clear", "cache", "")
    for k in pairs(ProxyCache) do
        ProxyCache[k] = nil
    end
end

-- Create Instance library proxy
local instanceLib = createEmulatedLibrary(Instance, {
    new = function(className, parent)
        local argStr = className .. (parent and (", " .. SafeToString(parent)) or "")
        logExfiltration("Instance.new", argStr, "LibCreate", "function", argStr)
        local newInstance = Instance.new(className, parent)
        return createObjectProxy(newInstance)
    end
})
SpoofedLibraries["Instance"] = instanceLib

------------------------------------------
-- Public API Functions
------------------------------------------

-- Enables automatic display of exfiltration data for real-time monitoring
local function enableAutoDisplay()
    ExfiltrationLog.autoDisplay = true
    print("Auto display of exfiltration data enabled")
end

-- Disables automatic display of exfiltration data
local function disableAutoDisplay()
    ExfiltrationLog.autoDisplay = false
    print("Auto display of exfiltration data disabled")
end

-- Clears all recorded exfiltration entries
local function clearExfiltrationLog()
    ExfiltrationLog = {}
    ExfiltrationCount = 0
    print("Exfiltration log cleared")
end

-- Exports the exfiltration log in JSON format for external processing
local function exportExfiltrationLog()
    return HttpService:JSONEncode(ExfiltrationLog)
end

-- Public API
return {
    -- Core functions
    Init = initEnvironment,
    Emulate_Libraries = createEmulatedLibrary,
    Emulate_Lua_Functions = setSpoofedFunctions,
    Overwrite_Environment = overwriteEnvironment,
    ClearCache = clearProxyCache,

    -- Data exfiltration functions
    PrintExfiltrationLog = printExfiltrationLog,
    EnableAutoDisplay = enableAutoDisplay,
    DisableAutoDisplay = disableAutoDisplay,
    ClearExfiltrationLog = clearExfiltrationLog,
    ExportExfiltrationLog = exportExfiltrationLog,
    GetExfiltrationCount = function() return ExfiltrationCount end,
}
