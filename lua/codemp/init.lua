---@class WorkspaceReference
---@field name string
---@field owned boolean

if CODEMP == nil then
	---@class CodempGlobal
	---@field rt? RuntimeDriver background codemp runtime
	---@field client? Client currently connected client
	---@field workspace? Workspace current active workspace
	---@field available WorkspaceIdentifier[] available workspaces to connect to
	---@field timer? any libuv timer
	---@field config Config codemp configuration
	---@field following string | nil
	---@field auto_share boolean automatically share opened buffers
	---@field ignore_following_action boolean TODO a more elegant solution?
	---@field setup fun(opts: Config): nil update config and setup plugin
	CODEMP = {
		rt = nil,
		native = nil,
		timer = nil,
		available = {},
		following = nil,
		ignore_following_action = false,
		auto_share = false,
		config = {
			host = "codemp.moonlit.technology",
			tls = false,
			neo_tree = false,
			timer_interval = 20,
			debug = false,
			-- debug_file = "/home/alemi/.local/share/nvim/logs/codemp.log",
			username = "",
			password = "",
		},
		setup = function (opts)
			CODEMP.config = vim.tbl_extend('force', CODEMP.config, opts)
			if CODEMP.config.auto_share ~= nil then -- if given, set initial value
				CODEMP.auto_share = CODEMP.config.auto_share
			end
			-- register logger
			CODEMP.native.setup_tracing(CODEMP.config.debug_file or print, CODEMP.config.debug)
			-- start background runtime, with stop event
			CODEMP.rt = CODEMP.native.setup_driver() -- spawn thread to drive tokio runtime
			vim.api.nvim_create_autocmd(
				{"VimLeave"},
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
					if cb == false then
						error(arg)
					else
						vim.schedule(function() cb(arg) end)
					end
				end
			end)

			require('codemp.command') -- not really related but should only happen once
			require('codemp.utils').setup_colors() -- create highlight groups for users
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
