---@class WorkspaceReference
---@field name string
---@field owned boolean

if CODEMP == nil then
	---@class CodempGlobal
	---@field rt? RuntimeDriver background codemp runtime
	---@field client? Client currently connected client
	---@field workspace? Workspace current active workspace
	---@field available WorkspaceReference[] available workspaces to connect to
	---@field timer? any libuv timer
	---@field config Config codemp configuration
	---@field setup fun(opts: Config): nil update config and setup plugin
	CODEMP = {
		rt = nil,
		native = nil,
		timer = nil,
		available = {},
		config = {
			neo_tree = false,
			timer_interval = 20,
			debug = false,
			username = "",
			password = "",
		},
		setup = function (opts)
			CODEMP.config = vim.tbl_extend('force', CODEMP.config, opts)
			-- register logger
			CODEMP.native.logger(print, CODEMP.config.debug)
			-- start background runtime, with stop event
			CODEMP.rt = CODEMP.native.spawn_runtime_driver() -- spawn thread to drive tokio runtime
			vim.api.nvim_create_autocmd(
				{"ExitPre"},
				{
					callback = function (_ev)
						if CODEMP.client ~= nil then
							print(" xx disconnecting codemp client")
							CODEMP.client = nil -- drop reference so it gets garbage collected
						end
						CODEMP.rt:stop()
					end
				}
			)

			CODEMP.timer = vim.loop.new_timer()
			CODEMP.timer:start(CODEMP.config.timer_interval, CODEMP.config.timer_interval, function()
				while true do
					local cb, arg = CODEMP.native.poll_callback()
					if cb == nil then break end
					vim.schedule(function() cb(arg) end)
				end
			end)

			require('codemp.command') -- not really related but should only happen once
		end
	}
end

if CODEMP.native == nil then
	CODEMP.native = require('codemp.loader').load() -- make sure we can load the native library correctly, otherwise no point going forward
	if CODEMP.native == nil then
		print(" !! could not load native bindings, try reloading")
		return CODEMP
	end
end

return CODEMP
