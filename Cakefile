fs 		= require 'fs'
{exec} 	= require 'child_process'

config 	= require './src/config.json'

task "build:plugin", "build the plugin", ->
	invoke "config"
	exec "moonc plugin.moon", cwd: "./plugin", ->
		console.log "Plugin Compiled"
		fs.writeFileSync "./src/plugin.lua", fs.readFileSync("./plugin/plugin.lua", encoding: "utf8")

task "build:app", "build electron app", ->
	invoke "build:plugin"
	invoke "build:coffee"

	exec "electron-packager ./src RSync --platform=win32 --arch ia32 --asar --version 1.3.3", ->
		console.log "Build complete"

task "build:coffee", "build the coffee files into javascript", ->
	exec "coffee -c .", (err, stdio, stderr) ->
		console.log stderr
		console.log "CoffeeScript Compiled"

task "build:sass", "Compile scss into css", ->
	exec "sass ./src/app/style.scss ./src/app/style.css", ->
		console.log "Sass compiled"

task "b", "Build stuff needed before dev testing, run as cake b && electron src", ->
	console.log "Building..."

	invoke "build:coffee"
	invoke "build:sass"
	invoke "build:plugin"

	

task "config", "Update config in plugin.moon", ->
	code = fs.readFileSync "./plugin/plugin.moon", encoding: "utf8"
	code = code.replace /BUILD=[0-9]+/, "BUILD=#{config.BUILD}"
	code = code.replace /PORT=[0-9]+/, "PORT=#{config.PORT}"
	fs.writeFileSync "./plugin/plugin.moon", code