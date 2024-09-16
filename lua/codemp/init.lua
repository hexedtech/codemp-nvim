if CODEMP == nil then
	---@class CodempGlobal
	CODEMP = {
		rt = nil,
		session = nil,
		native = nil,
		timer = nil,
		config = {
			neo_tree = false,
			timer_interval = 20,
			debug = false,
		},
		setup = function (opts)
			CODEMP.config = vim.tbl_extend('force', CODEMP.config, opts)
		end
	}
end

if CODEMP.native == nil then
	CODEMP.native = require('codemp.loader').load() -- make sure we can load the native library correctly, otherwise no point going forward
	if CODEMP.native == nil then
		print(" !! could not load native bindings, try reloading")
	end
	--CODEMP.native.logger(function (msg)
	--	vim.schedule(function () print(msg) end)
	--end, true)
end

if CODEMP.session == nil then
	CODEMP.session = require('codemp.session')
end

if CODEMP.rt == nil then
	CODEMP.rt = CODEMP.native.spawn_runtime_driver() -- spawn thread to drive tokio runtime
	vim.api.nvim_create_autocmd(
		{"ExitPre"},
		{
			callback = function (_ev)
				if CODEMP.session.client ~= nil then
					print(" xx disconnecting codemp client")
					CODEMP.session.client = nil
				end
				CODEMP.rt:stop()
			end
		}
	)
end

if CODEMP.timer == nil then
	CODEMP.timer = vim.loop.new_timer()
	CODEMP.timer:start(CODEMP.config.timer_interval, CODEMP.config.timer_interval, function()
		while true do
			local cb = CODEMP.native.poll_callback()
			if cb == nil then break end
			cb()
		end
	end)

	require('codemp.command') -- not really related but should only happen once
end


return CODEMP
