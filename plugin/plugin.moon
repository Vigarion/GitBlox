-- BEGIN AUTO CONFIG --
BUILD=10
PORT=21496
-- END AUTO CONFIG --

-- Variable declarations --
UserInputService 	= game\GetService "UserInputService"
HttpService 		= game\GetService "HttpService"
CoreGui 			= game\GetService "CoreGui"

local hookChanges, sendScript, doSelection, alertBox, alertActive, resetCache, checkMoonHelper
local justAdded, parseMixinsOut, parseMixinsIn, deleteScript, checkForPlaceName

pmPath 		= "Documents\\ROBLOX\\GitBlox"
scriptCache = {}
sourceCache = {}
gameGUID 	= HttpService\GenerateGUID!
temp 		= true
polling		= false
failed		= 0

mixinRequire = "local __RSMIXINS=require(game.ReplicatedStorage.Mixins);__RSMIXIN=function(a,b,c)if type(__RSMIXINS[a])=='function'then return __RSMIXINS[a](a,b,c)else return __RSMIXINS[a]end end\n"
mixinString = "__RSMIXIN('%1', script, getfenv())"
mixinStringPattern = "__RSMIXIN%('([%w_]+)', script, getfenv%(%)%)"
moonBoilerplate = [=[
-- GitBlox Boilerplate --
local function mixin(name, automatic)
	if (not automatic) and (name == "autoload" or name == "client" or name == "server") then
		error("GitBlox: Name \"" .. name .. "\" is a reserved name, and is automatically included in every applicable script.")
	end
	
	if not game.ReplicatedStorage:FindFirstChild("Mixins") then
		return
	end

	if script.Name == "Mixins" and script.Parent == game.ReplicatedStorage then
		return
	end

	local mixins = require(game.ReplicatedStorage.Mixins)

	if type(mixins[name]) == "function" then
		return mixins[name](name, script, getfenv(2))
	else
		return mixins[name]
	end
end

mixin("autoload", true)
mixin(game.Players.LocalPlayer and "client" or "server", true)
-- End Boilerplate --
]=]
-- A wrapper for `print` that prefixes plugin version information.--
debug = (...) ->
	print "[GitBlox build #{BUILD}] ", ...

-- Creates a GUI alert to tell the user something, 
-- also calls `debug` on the arguments. --
alert = (...) ->
	debug ...

	-- Use tick to save the time of the most recent alert. --
	alertActive = tick!

	text = ""
	for segment in *{...}
		text ..= segment .. " "
	text = text\sub 1, #text-1

	alertBox.Text = text
	alertBox.Visible = true

	-- Store the current alert's time. --
	snapshot = alertActive

	Spawn ->
		wait 5
		-- If the alert is still the most recentl, hide it. 
		-- Otherwise, keep it open since another alert has been issued. --
		if snapshot == alertActive
			alertBox.Visible = false

-- Takes the injected mixin code and reverts it back to special GitBlox syntax. --
parseMixinsOut = (source) ->
	return source unless game.ReplicatedStorage\FindFirstChild("Mixins") and 
		game.ReplicatedStorage.Mixins\IsA("ModuleScript")

	if source\sub(1, #mixinRequire) == mixinRequire
		source = source\sub(#mixinRequire + 1)

	source = source\gsub mixinStringPattern, "@(%1)"

	return source

-- Parses the special Mixin syntax and replaces it with the injected code. --
parseMixinsIn = (source) ->
	return source unless game.ReplicatedStorage\FindFirstChild("Mixins") and 
		game.ReplicatedStorage.Mixins\IsA("ModuleScript")

	if source\find "@%(([%w_]+)%)"
		source = mixinRequire .. source

		source = source\gsub "@%(([%w_]+)%)", mixinString

	return source

-- Called with a LuaSourceContainer object to begin tracking script changes. --
hookChanges = (obj) ->
	obj.Changed\connect (prop) ->

		-- Ignore the change if the script was just added, since the Change event gets called immediately. --
		if obj == justAdded
			justAdded = nil
			return

		switch prop
			when "Source"
				-- Ignore MoonScript mode scripts --
				if obj\FindFirstChild "MoonScript"
					return
				-- Ignore the change if we are the ones who changed the script. --
				if sourceCache[obj] == obj.Source
					sourceCache[obj] = nil
				else
					sendScript obj, false
			when "Parent", "Name"
				-- If the Parent or Name properties change, delete the script. 
				-- deleteScript will handle sending the script again after the request completes if Parent is not nil. --
				deleteScript obj

-- Deletes a script from the user's filesystem. 
-- Called when a script's `Name` or `Parent` properties are changed. --
deleteScript = (obj) ->
	return unless scriptCache[obj]

	data =
		guid: scriptCache[obj]

	scriptCache[scriptCache[obj]] = nil
	scriptCache[obj] = nil

	pcall ->
		HttpService\PostAsync "http://localhost:#{PORT}/delete", HttpService\JSONEncode(data), "ApplicationJson", false
		-- Immediately send the script again. If the parent is still nil in the game, it will be ignored. 
		-- In cases of name change, this is done so we can wait for the delete request to finish before sending the newly-named script. --
		sendScript obj, false

-- Sends a script to the filesystem. 
-- Optional second parameter, which will open the file automatically in a code editor if true. --
sendScript = (obj, open=true) ->
	-- If the script doesn't have a Parent, ignore it. --
	return unless obj.Parent

	-- Generate the script ancestry path to map to the filesystem. --
	stack = {}
	parent = obj.Parent
	while parent != game
		table.insert stack, 1, parent
		parent = parent.Parent

	path = ""
	for ancestor in *stack
		path ..= ancestor.Name .. "/"

	-- Check if this is the first time we've seen this script. --
	if not scriptCache[obj]
		-- Assign the script a GUID, which is used for internally tracking the script changes. --
		scriptCache[obj] = HttpService\GenerateGUID false
		-- Also map the GUID to the object for easy referencing. --
		scriptCache[scriptCache[obj]] = obj
		-- Hook up the Change event on the script. --
		hookChanges obj

	-- Determine what syntax the script is using. --
	local syntax, source
	if obj\FindFirstChild("MoonScript") and obj.MoonScript\IsA("StringValue")
		syntax = "moon"
		source = obj.MoonScript.Value
	else
		syntax = "lua"
		source = parseMixinsOut obj.Source

	-- Send the data to the endpoint. --
	data = 
		:path
		:syntax
		:source
		:temp
		name: obj.Name
		class: obj.ClassName
		place_name: gameGUID
		guid: scriptCache[obj]

	pcall ->
		HttpService\PostAsync "http://localhost:#{PORT}/write/#{open and 'open' or 'update'}", HttpService\JSONEncode(data), "ApplicationJson", false

-- Resets the session, so it can be reinitialized.
-- Also called when there is a conneciton loss. --
resetCache = ->
	polling = false
	scriptCache = {}
	sourceCache = {}
	gameGUID 	= HttpService\GenerateGUID! if temp
	debug "Resetting, if you restart the client you will need to reopen your scripts again, the files on disk will no longer be sent to this game instance as a result of the connection loss."

-- Begins the long-polling to the local server. --
startPoll = ->
	return if polling
	polling = true

	Spawn ->
		while true
			success = pcall ->
				body = HttpService\GetAsync "http://localhost:#{PORT}/poll", true
				command = HttpService\JSONDecode body

				-- Determine what kind of command the server has sent us. --
				switch command.type
					when "update"
						-- If we don't know about the script, then ignore it. --
						if scriptCache[command.data.guid]
							obj = scriptCache[command.data.guid]

							-- Only parse mixins if Lua. --
							local source
							if command.data.moon
								source = moonBoilerplate .. command.data.source
							else
								source = parseMixinsIn command.data.source

							-- Save the script source in sourceCache so we can ignore this change when the script changes from us setting the Source. --
							sourceCache[scriptCache[command.data.guid]] = source

							-- Update the script. --
							obj.Source = source

							if command.data.moon and obj\FindFirstChild("MoonScript") and obj.MoonScript\IsA("StringValue")
								obj.MoonScript.Value = command.data.moon
					when "output"
						-- An output command from the server, useful for showing information such as Moonscript compile errors. --
						return if #command.data.text == 0
						debug command.data.text

			-- Increment the failed counter if the request failed, or reset it upon success. --
			failed += 1 unless success
			failed = 0 if success

			-- If the previous three requests have failed, determine there is a connection issue and stop long-polling. --
			if failed > 3
				resetCache!
				alert "Lost connection to the helper client, stopping."
				break

-- Performs the initial handshake and version check with the server. --
init = (cb) ->
	success, err = pcall ->
		data = HttpService\JSONDecode HttpService\PostAsync("http://localhost:#{PORT}/new", HttpService\JSONEncode(place_name: gameGUID), "ApplicationJson", false)
		if data.status == "OK"
			-- Check that the version of the plugin matches the version of the helper client. --
			if data.build == BUILD
				pmPath = data.pm
				startPoll!
				cb!
			else
				alert "Plugin version does not match helper version, restart studio."
		else
			-- An unknown error has occurred. --
			alert "Unhandled error, please check output."
			debug data.error

	-- Show special alerts for certain common errors. --
	unless success
		if err\find "Http requests are not enabled"
			alert "Set HttpService.HttpEnabled to true to use this feature."
		elseif err\find "Couldn't connect to server"
			alert "Couldn't connect to helper client, did you start the executable?"
		else
			alert "Unhandled error, please check output."
			debug "An error occurred: #{err}"

-- Scans the game for scripts, used with persistent mode. --
scan = ->
	-- If the initial handshake hasn't been performed, do it first. --
	return init scan unless polling

	-- A recursive function used to check the game for scripts. --
	lookIn = (obj) ->
		for child in *obj\GetChildren!
			if child\IsA "LuaSourceContainer"
				sendScript child, false
			lookIn child

	lookIn game.Workspace
	lookIn game.Lighting
	lookIn game.ReplicatedFirst
	lookIn game.ReplicatedStorage
	lookIn game.ServerScriptService
	lookIn game.ServerStorage
	lookIn game.StarterGui
	lookIn game.StarterPack
	lookIn game.StarterPlayer

	-- When a new script is added to the game, handle it correctly. --
	game.DescendantAdded\connect (obj) ->
		pcall ->
			if obj\IsA "LuaSourceContainer"
				justAdded = obj
				sendScript obj, false

	alert "All game scripts updated on filesystem, path in output"
	debug "\\#{pmPath}\\#{gameGUID}\\"

-- Handles checking the user selection for scripts, called when the Open in Editor button is pressed. --
doSelection = ->
	-- If the initial handshake hasn't been performed, do it first. --
	return init doSelection unless polling

	selection = game.Selection\Get!

	-- Check if selection is empty. --
	if #selection == 0
		return alert "Select one or more scripts in the Explorer."

	-- Search the selection for scripts, and send them. --
	one = false
	for obj in *selection
		if obj\IsA "LuaSourceContainer"
			one = true
			checkMoonHelper obj
			sendScript obj

	-- If at least one script wasn't found, show the user a help message. --
	unless one
		alert "Select one or more scripts in the Explorer."

-- Checks if a script should be automatically set to MoonScript mode when a user presses the plugin button.
-- Optional parameter `force`, which will bypass the check and forcibly convert to MoonScript mode. --
checkMoonHelper = (obj, force) ->
	return unless obj\IsA "LuaSourceContainer"
	return if obj\FindFirstChild "MoonScript"
	return if #obj.Source > 100

	hasExt = obj.Name\sub(#obj.Name-4, #obj.Name) == ".moon"

	if force or hasExt or
		obj.Source\lower! == "m" or 
		obj.Source\lower! == "moon" or 
		obj.Source\lower! == "moonscript"
			with Instance.new "StringValue", obj
				.Name 	= "MoonScript"
				.Value 	= 'print "Hello", "from MoonScript", "Lua version: #{_VERSION}"'
			obj.Name = obj.Name\sub 1, #obj.Name-5 if hasExt

-- Check HttpService for StringValue "PlaceName" to see if we should enable persistent mode. --
checkForPlaceName = (obj) ->
	-- If obj is nil, try to find it. If it is nil, return. --
	unless obj
		if HttpService\FindFirstChild "PlaceName"
			obj = HttpService.PlaceName

	return unless obj

	-- Wait for any changes to objects in HttpService.
	obj.Changed\connect ->
		checkForPlaceName obj

	-- If the object meets the requirements, enable persistent mode. -- 
	if obj\IsA("StringValue") and #obj.Value > 0
		resetCache!
		gameGUID = obj.Value
		temp = false
		scan!

-- Create the alert box and place it in CoreGui. --
with alertBox = Instance.new "TextLabel"
	.Parent 				= Instance.new "ScreenGui", CoreGui
	.Name 					= "GitBlox Alert"
	.BackgroundColor3 		= Color3.new 231/255, 76/255, 60/255
	.TextColor3				= Color3.new 1, 1, 1
	.BackgroundTransparency	= 0
	.BorderColor3 			= Color3.new 231/255, 76/255, 60/255
	.BorderSizePixel 		= 30
	.Position 				= UDim2.new 0.5, -150, 0.5, -25
	.Size 					= UDim2.new 0, 300, 0, 50
	.ZIndex 				= 10
	.Font 					= "SourceSansLight"
	.FontSize				= "Size24"
	.Visible 				= false
	.TextWrapped			= true

-- Check that the game is not in test mode before enabling the plugin. 
-- This works because Studio names all edit-mode places in the format PlaceN, where N is a number.
-- All places in test mode either take the name of the file or the name of the place online.
-- This obviously won't work in all cases, but it should work with the majority of cases. --
if game.Name\match("Place[%d+]") and
	-- Studio mode is both server and client. If not both, then user is testing in server/client mode. --
	(game\GetService("RunService")\IsClient! and game\GetService("RunService")\IsServer!)
		-- Create the plugin toolbar and button. --
		toolbar = plugin\CreateToolbar "GitBlox"
		button = toolbar\CreateButton "Open with Editor", "Open with system .lua editor (Ctrl+B)", "rbxassetid://478150446"

		button.Click\connect doSelection

		-- Hook up the keybinds Ctrl+B and Ctrl+Alt+B --
		UserInputService.InputBegan\connect (input, gpe) ->
			return if gpe

			if input.KeyCode == Enum.KeyCode.B and UserInputService\IsKeyDown(Enum.KeyCode.LeftControl)
				if UserInputService\IsKeyDown Enum.KeyCode.LeftAlt
					for obj in *game.Selection\Get!
						checkMoonHelper obj, true
				
				doSelection!

		-- Check if we should turn persistent mode on. --
		checkForPlaceName!
		HttpService.ChildAdded\connect checkForPlaceName