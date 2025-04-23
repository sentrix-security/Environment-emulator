# Roblox Security Monitoring Module

Bypass Roblox userdata readonly restrictions – while tracking and monitoring all environment behavior in Lua.

![Lua](https://img.shields.io/badge/Lua-blue) ![Roblox](https://img.shields.io/badge/Roblox-red) ![Security](https://img.shields.io/badge/Security-green) ![License](https://img.shields.io/badge/License-MIT-yellow)

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [API Reference](#api-reference)
- [How It Works](#how-it-works)
- [Example Monitored Log Output](#example-monitored-log-output)
- [Performance Considerations](#performance-considerations)
- [Contributing](#contributing)
- [License](#license)

## Overview

This Lua module is designed for Roblox environments and allows developers to:
- Bypass readonly restrictions on Roblox userdata fields (e.g., `game.CreatorId`)
- Continuously monitor all access and modifications to Roblox objects, functions, and properties
- Detect, log, and analyze data exfiltration or unauthorized access behaviors
- Build a secure, observable execution environment for scripts

> **Note:** This module facilitates security research and development, not hacking or misuse!

## Features

- **Readonly Bypass:** Access and manipulate properties normally blocked by Roblox's metatable protections.
- **Full Access Monitoring:** Track every get, set, function call, and object creation in your scripts.
- **Detailed Exfiltration Logs:** Every monitored event is timestamped and contextualized for security audits.
- **Exportable Logs:** Output logs in JSON or pretty ASCII table for post-analysis.
- **Custom Env Emulation:** Create locked-down, monitored script environments with custom function replacements.

## Installation

1. Add this module as a ModuleScript in your Roblox game.
2. Require the module in your controlling scripts:
```lua
local SecurityMonitor = require(path.to.SecurityMonitorModule)
```

## Usage

### Basic Environment Setup
```lua
-- Initialize and wrap your script environment
local secureEnv = SecurityMonitor.Init({})

-- To monitor a specific script in isolation:
setfenv(targetScript, secureEnv)
```

### Bypassing Readonly Userdata Properties
```lua
-- Directly access or modify Roblox protected fields (e.g., CreatorId)
local creatorId = secureEnv.game.CreatorId -- Will be intercepted and accessible!
secureEnv.game.CreatorId = 133742
```

### Advanced Monitoring and Logging
```lua
-- Enable immediate log display for each monitored event:
SecurityMonitor.EnableAutoDisplay()

-- Print a formatted log at any time:
SecurityMonitor.PrintExfiltrationLog()

-- Export the entire log in JSON format:
local json = SecurityMonitor.ExportExfiltrationLog()
```

### Custom Library Emulation
```lua
local customHttpService = SecurityMonitor.Emulate_Libraries(game:GetService("HttpService"), {
    RequestAsync = function(params)
        -- your custom networking stub here
    end
})
```

## API Reference

| Function | Description |
|----------|-------------|
| `Init(customData)` | Initializes a monitored environment for your scripts. |
| `Emulate_Libraries(original, custom)` | Wraps Roblox libraries and overrides their methods for custom behavior and monitoring. |
| `Emulate_Lua_Functions(map)` | Spoofs/replaces global Lua functions (like print) within the monitored environment. |
| `Overwrite_Environment(newEnv)` | Swaps the current script environment for a new one. |
| `ClearCache()` | Clears all internal proxy caches, freeing memory. |
| `EnableAutoDisplay()` | Automatically displays log entries in real time. |
| `DisableAutoDisplay()` | Turns off real-time log display. |
| `PrintExfiltrationLog()` | Print a pretty-formatted ASCII log of all monitored actions. |
| `ExportExfiltrationLog()` | Get the entire event log as a JSON string. |
| `ClearExfiltrationLog()` | Remove all entries from the event/exfiltration log. |
| `GetExfiltrationCount()` | Returns the total number of tracked actions/events so far. |

## How It Works

1. **Bypassing Readonly Restrictions:** This module injects proxy objects and metatable overrides that allow property access and modification even on fields Roblox usually marks as readonly (e.g., `game.CreatorId`).

2. **Access Monitoring:** Every get, set, or method call on Roblox objects, instances, or libraries is tracked, logged, and made observable by the module.

3. **Proxy Creation:** When a Roblox Instance/function is accessed, a unique proxy object is created. This proxy intercepts all standard metamethods (`__index`, `__newindex`, `__call`, etc.), enabling both logging and readonly-bypass logic.

4. **Custom Environments:** Initialize execution environments that wrap globals, intercept libraries, and allow per-script tracking and function replacement.

5. **Data Exfiltration Logging:** Each access is timestamped, contextualized (path, action, value, etc.), and can be displayed in real-time (auto-display) or exported for post-mortem review.

## Example Monitored Log Output

```
  ┌─────┬───────────────────┬──────────────────────────┬──────────────────────────────────┬────────┬───────────────────────────────────────────────────────┐
  │INDEX│TIMESTAMP          │OBJECT PATH               │ACTION                            │TYPE    │VALUE                                                  │
  ├─────┼───────────────────┼──────────────────────────┼──────────────────────────────────┼────────┼───────────────────────────────────────────────────────┤
  │1    │2025-04-23 18:41:02│Environment               │EnvAccess                         │index   │game                                                   │ 
  ├─────┼───────────────────┼──────────────────────────┼──────────────────────────────────┼────────┼───────────────────────────────────────────────────────┤
  │2    │2025-04-23 18:41:02│Game.GetService           │LibAccess                         │function│function: 0x6e19b198bcd7ff1b                           │ 
  ├─────┼───────────────────┼──────────────────────────┼──────────────────────────────────┼────────┼───────────────────────────────────────────────────────┤
  │3    │2025-04-23 18:41:02│HttpService.GetAsync      │LibAccess                         │function│function: 0x07fb3122d000609b                           │ 
  ├─────┼───────────────────┼──────────────────────────┼──────────────────────────────────┼────────┼───────────────────────────────────────────────────────┤
  │4    │2025-04-23 18:41:02│HttpService.GetAsync      │LibFuncCall                       │function│args:{ https://example.com }                           │  ▶ {...} -- << args
  ├─────┼───────────────────┼──────────────────────────┼──────────────────────────────────┼────────┼───────────────────────────────────────────────────────┤
  │5    │2025-04-23 18:41:03│HttpService.GetAsync      │LibReturn                         │string  │<!doctype html>                                        │
  └─────┴───────────────────┴──────────────────────────┴──────────────────────────────────┴────────┴───────────────────────────────────────────────────────┘ 
```

## Performance Considerations

- There is some performance overhead due to proxy and metatable interception on every property and function access.
- Use `ClearCache()` and `ClearExfiltrationLog()` to manage memory during long sessions.
- To reduce impact, only wrap scripts or libraries that truly require monitoring/bypass.
- All content is laid out without scrollbars or extra breaks for PDF-friendly continuous export.

## Contributing

1. Fork this repository and create a new feature branch.
2. Make changes and add tests where appropriate.
3. Submit a pull request with a clear description of your changes.
