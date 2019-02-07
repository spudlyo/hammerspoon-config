-- Some globals
local tmux = "/usr/local/bin/tmux"
local hyper = {"cmd", "alt", "ctrl", "shift"}
local super = {"cmd", "alt", "ctrl"}
local hyperFuncs = {}
local alternates = {}
local superFuncs = {}

local function getAppMainWindow(app)
    local myapp = hs.appfinder.appFromName(app)
    if not myapp then
	return nil
    end
    local mainwin = myapp:mainWindow()
    if not mainwin then
	return nil
    end
    return mainwin
end

-- Plays an array of keystroke events.
local function playKb(kbd)
    for _,v in pairs(kbd) do
	if #v == 2 then
	    hs.eventtap.keyStroke(v[1], v[2], 10000)
	elseif #v == 1 then
	    hs.eventtap.keyStrokes(v[1])
	end
    end
end

-- Bring focus to the specified app, maybe launch it.
-- Maybe bring up an alternate and focus or launch it.
local function toggleApp(appinfo)
    local alternate = alternates[appinfo.name]
    local app = hs.appfinder.appFromName(appinfo.name)
    if not app then
	-- App isn't running.
	if appinfo.launch then
	    if (appinfo.name == "iTerm2") then
		-- naming is weird here.
		hs.application.launchOrFocus("/Applications/iTerm.app")
	    else
		hs.application.launchOrFocus(appinfo.name)
	    end
	    if appinfo.rect ~= nil or appinfo.kbd ~= nil then
		-- allow time app to start
		hs.timer.usleep(2000000)
	    end
	    if appinfo.rect ~= nil then
		local win = hs.window.focusedWindow()
		if win ~= nil then
		    win:setFrame(appinfo.rect)
		end
	    end
	    if appinfo.kbd ~= nil then
		playKb(appinfo.kbd)
	    end
	else
	    if alternate ~= nil then
		toggleApp(alternate)
	    end
	end
        return
    end
    -- App is running, let's focus it.
    local mainwin = app:mainWindow()
    if mainwin then
        if mainwin ~= hs.window.focusedWindow() then
            mainwin:application():activate(true)
            mainwin:application():unhide()
	    mainwin:frontmostWindow():unminimize()
            mainwin:focus()
        else
	    -- App already has the focus. Let's raise or launch the alternate.
	    if alternate ~= nil then
		toggleApp(alternate)
	    end
	end
    end
end

local function unhideApp(app)
    local myapp = hs.appfinder.appFromName(app)
    if not myapp then
	return nil
    end
    return myapp:unhide()
end

local function focusMainWindow(mainwin)
    mainwin:application():activate(true)
    mainwin:application():unhide()
    mainwin:focus()
end

local function runCommand(command)
    local handle = io.popen(command)
    if handle == nil then
	return nil, {false}
    end
    local out = handle:read("*a")
    local rc = {handle:close()}
    return out, rc
end

local function tmuxGetVariable(var)
    local cmd = tmux .. " display-message -p '#{" .. var .. "}'"
    local out, rc = runCommand(cmd)
    out = out:gsub("%s+$", "")
    return out, rc
end

local function gotoTmuxWindow(window)
    local cmd = tmux .. " select-window -t '" .. window .. "'"
    local out, rc =  runCommand(cmd)
    out = out:gsub("%s+$", "")
    return out, rc
end

local function newEmacsClient(title)
    local t = string.format("/usr/bin/printf '\\033]2;%s\\033\\\\'; ", title)
    local ec = "/usr/local/bin/emacsclient -c -a ''"
    local path = "PATH=/usr/local/bin "
    return (path .. tmux .. " %s " .. "\"" .. t .. ec .."\"")
end

local function newEmacsClientWindow()
    local tmux_arg = "new-window -n EmacsServer"
    local cmd = string.format(newEmacsClient("EmacsServer"), tmux_arg)
    return runCommand(cmd)
end

local function newEmacsClientPane()
    local tmux_arg = "splitw -p 30 -b"
    local cmd = string.format(newEmacsClient("EmacsServer"), tmux_arg)
    return runCommand(cmd)
end

local function tmuxGotoHost(hostname)
    local local_tmux = tmux .. " new-window -n " .. hostname
    local remote_tmux = "tmux new -A -D -s " .. hostname
    local ssh_cmd = "ssh -tt -q " .. hostname .. " " .. remote_tmux
    local cmd = local_tmux .. " " .. ssh_cmd
    return runCommand(cmd)
end

local function tmuxWindowExists(win)
    local out, rc = runCommand(tmux .. " list-windows")
    if not rc[1] then
	return false
    end
    for line in out:gmatch("[^\r\n]+") do
	if string.find(line, win) ~= nil then
	    return true
	end
    end
    return false
end

local function gotoHost(hostname)
    if not tmuxWindowExists(hostname) then
	tmuxGotoHost(hostname)
    end
    gotoTmuxWindow(hostname)
    local termMainWindow = getAppMainWindow("iTerm2")
    if termMainWindow == nil then
	return
    end
    focusMainWindow(termMainWindow)
end

local function applyLayout()
    local laptop = "Color LCD"
    local main = "FS-270D"
    local windowLayout = {
	{"Slack",         nil, main,   hs.layout.left50,    nil, nil},
	{"Google Chrome", nil, main,   hs.layout.left50,    nil, nil},
	{"Safari",        nil, main,   hs.layout.left50,    nil, nil},
	{"iTerm2",        nil, main,   hs.layout.right50,   nil, nil},
	{"zoom.us",       nil, laptop, hs.layout.maximized, nil, nil},
    }
    -- Let's unhide all the apps, in case they're hidden.
    for _,v in pairs(windowLayout) do
	unhideApp(v[1])
    end
    hs.layout.apply(windowLayout)
end

local function toggleVPN()
    local script = [[
    tell application "Viscosity"
      set connectionName to name of the first connection
      if the state of the first connection is "Connected" then
        tell application "Viscosity"
          disconnect connectionName
        end tell
      else
        tell application "Viscosity"
          connect connectionName
        end tell
      end if
    end tell
    ]]
    hs.applescript(script)
end

-- editWithEmacs helper for tmux emacs usage.
local function editWithEmacs()
    -- Get the application of the frontmost (focused) App.
    local frontapp = hs.application.frontmostApplication()
    local bundleid = hs.application.bundleID(frontapp)
    -- It's Chrome right?
    if bundleid ~= "com.google.Chrome" then
	-- Ok, it's iTerm2 then right?
	if bundleid ~= "com.googlecode.iterm2" then
	    hs.alert.show("Only works in Chrome and iTerm2.")
	    return
	end
	-- We're in the tmux editing pane right?
	local pane = tmuxGetVariable("pane_title")
	if pane == nil then
	    hs.alert.show("Could not get tmux pane title.")
	    return
	end
	if pane ~= "EmacsServer" then
	    hs.alert.show("Wrong tmux pane: " .. pane)
	    return
	end
	local chromeMainWindow = getAppMainWindow("Google Chrome")
	if chromeMainWindow == nil then
	    hs.alert.Show("Chrome has to be running.")
	    return
	end
	-- Send C-x C-s (save)
	hs.eventtap.keyStroke({"ctrl"}, "x", 10000)
	hs.eventtap.keyStroke({"ctrl"}, "s", 10000)
	-- Send C-c C-k (kill-this-buffer-volatile)
	hs.eventtap.keyStroke({"ctrl"}, "c", 10000)
	hs.eventtap.keyStroke({"ctrl"}, "k", 10000)
	-- Close the emacs frame
	hs.eventtap.keyStroke({"ctrl"}, "x", 10000)
	hs.eventtap.keyStroke({"ctrl"}, "c", 10000)
	-- Switch focus to Chrome.
	focusMainWindow(chromeMainWindow)
	return
    end
    -- Make sure iTerm2 is running.
    local termMainWindow = getAppMainWindow("iTerm2")
    if termMainWindow == nil then
	hs.alert.show("iTerm2 is not running, sorry.")
	return
    end
    local sleep_time = 10000
    -- See if we have an emacs daemon process running.
    local _, rc = runCommand("/usr/bin/pgrep -U spud -f emacs.*daemon")
    if not rc[1] then
	-- Allow for a longer emacs startup time.
	sleep_time = 2000000
    end
    newEmacsClientPane()
    hs.timer.usleep(sleep_time)
    -- Send the "Edit with Emacs" hot key to Chrome.
    hs.eventtap.keyStroke({"alt"}, "padenter")
    -- Switch focus to iTerm2
    focusMainWindow(termMainWindow)
    -- Tell tmux to switch to the window labeled EmacsServer
--    gotoTmuxWindow("EmacsServer")
    -- You are now free to edit things.
end

-- Reload config
local function reloadConfig(paths)
    local doReload = false
    for _,file in pairs(paths) do
        if file:sub(-4) == ".lua" then
            print("A lua file changed, doing reload")
            doReload = true
        end
    end
    if not doReload then
        print("No lua file changed, skipping reload")
        return
    end

    hs.reload()
end

local function toggleDarkMode()
    local script = [[
    tell application "System Events"
        tell appearance preferences
            set dark mode to not dark mode
        end tell
    end tell
    ]]
    hs.applescript(script)
end

local function iTerm2Shrink()
    local termMainWindow = getAppMainWindow("iTerm2")
    if termMainWindow == nil then
	return
    end
    focusMainWindow(termMainWindow)
    for _=1,3 do
	hs.eventtap.keyStroke({"cmd"}, "-", 10000)
    end
    local win = hs.window.focusedWindow()
    local f = win:frame()
    f.h = f.h - 700
    win:setFrame(f)
end

local function iTerm2Grow()
    local termMainWindow = getAppMainWindow("iTerm2")
    if termMainWindow == nil then
	return
    end
    focusMainWindow(termMainWindow)
    hs.eventtap.keyStroke({"cmd"}, "0", 10000)
    applyLayout()
end

local function applicationWatcher(appName, eventType, _)
    if appName == "Mail" then
	if eventType == hs.application.watcher.launched then
	    iTerm2Shrink()
	    focusMainWindow(getAppMainWindow("Mail"))
	end
	if eventType == hs.application.watcher.terminated then
	    iTerm2Grow()
	end
    end
end

local function printWindowID()
    local window = hs.window.focusedWindow()
    print (window:id())
end

local function printWindowLayout()
    local window = hs.window.focusedWindow()
    local f = window:frame()
    print(string.format("{x=%d,y=%d,h=%d,w=%d}", f.x, f.y, f.h, f.w))
end

local function toggleInputDevice()
    local builtInMic = "MacBook Pro Microphone"
    local fancyMic = "Universal Audio Thunderbolt"
    local curInput = hs.audiodevice.defaultInputDevice()

    if curInput:name() == builtInMic then
	local fancy = hs.audiodevice.findDeviceByName(fancyMic)
	if fancy ~= nil then
	    hs.alert.show("Current mic: " .. fancyMic)
	    fancy:setDefaultInputDevice()
	end
    elseif curInput:name() == fancyMic then
	local builtIn = hs.audiodevice.findDeviceByName(builtInMic)
	if builtIn ~= nil then
	    hs.alert.show("Current mic: " .. builtInMic)
	    builtIn:setDefaultInputDevice()
	end
    end
end

local skb = {
    {{"cmd"}, "t"},
    {{}, "padenter"},
}

local tkb = {
    {"tmux new -A -D -s darkstar"},
    {{}, "padenter"}
}

local mrt = {x=-1278,y=701,w=1278,h=704} -- Mail.app Rect
local zrt = {x=415,y=201,h=660,w=880}    -- Zoom Rect

-- Application switch & launch hotkeys.
hyperFuncs['t'] = function() toggleApp({name="iTerm2",        launch=true,  kbd=tkb, rect=nil}) end
hyperFuncs['w'] = function() toggleApp({name="Google Chrome", launch=true,  kbd=nil, rect=nil}) end
hyperFuncs['c'] = function() toggleApp({name="Calendar",      launch=true,  kbd=nil, rect=nil}) end
hyperFuncs['m'] = function() toggleApp({name="Mail",          launch=true,  kbd=nil, rect=mrt}) end
hyperFuncs['s'] = function() toggleApp({name="Slack",         launch=true,  kbd=nil, rect=nil}) end
hyperFuncs['i'] = function() toggleApp({name="iTunes",        launch=true,  kbd=nil, rect=nil}) end
hyperFuncs['z'] = function() toggleApp({name="zoom.us",       launch=true,  kbd=nil, rect=zrt}) end
hyperFuncs['h'] = function() toggleApp({name="Hammerspoon",   launch=true,  kbd=nil, rect=nil}) end
-- App alternates
alternates["Mail"] = {name="Microsoft Outlook", launch=false}
alternates["Google Chrome"] = {name="Safari", launch=false}
-- Misc Hyper
hyperFuncs['d'] = function() toggleDarkMode() end
hyperFuncs['v'] = function() toggleVPN() end
hyperFuncs['l'] = function() applyLayout() end
-- SSH launchers
superFuncs['e'] = function() gotoHost("eidolon") end
superFuncs['s'] = function() gotoHost("st2") end
superFuncs['r'] = function() gotoHost("cbrs") end
superFuncs['b'] = function() gotoHost("cbbb") end
superFuncs['f'] = function() gotoHost("cbfr") end
superFuncs['d'] = function() gotoHost("cbdev") end
-- Misc Super
superFuncs['k'] = function() runCommand("/Users/spud/bin/ck.sh") end
superFuncs['i'] = function() printWindowID() end
superFuncs['l'] = function() printWindowLayout() end
superFuncs['m'] = function() toggleInputDevice() end

for _hotkey, _fn in pairs(hyperFuncs) do
    hs.hotkey.bind(hyper, _hotkey, _fn)
end

for _hotkey, _fn in pairs(superFuncs) do
    hs.hotkey.bind(super, _hotkey, _fn)
end

hs.hotkey.bind({"alt"}, "return", function() editWithEmacs() end)

local configFileWatcher = hs.pathwatcher.new(os.getenv("HOME") .. "/.hammerspoon/", reloadConfig)
configFileWatcher:start()

local appWatcher = hs.application.watcher.new(applicationWatcher)
appWatcher:start()
