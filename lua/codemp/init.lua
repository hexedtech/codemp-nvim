if CODEMP == nil then
	---@class CodempGlobal
	CODEMP = {
		rt = nil,
		session = nil,
		native = nil,
		config = {
			neo_tree = false,
			timer_interval = 100,
		},
		setup = function (opts)
			CODEMP.config = vim.tbl_extend('force', CODEMP.config, opts)

			local path = vim.fn.stdpath('data') .. '/codemp/'
			if vim.fn.isdirectory(path) == 0 then
				vim.fn.mkdir(path, 'p')
			end

			if CODEMP.native == nil then
				CODEMP.native = require('codemp.loader').load() -- make sure we can load the native library correctly, otherwise no point going forward
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

			if timer == nil then
				timer = vim.loop.new_timer()
				timer:start(CODEMP.config.timer_interval, CODEMP.config.timer_interval, function()
					while true do
						local cb = CODEMP.native.poll_callback()
						if cb == nil then break end
						cb()
					end
				end)
			end

			require('codemp.command')

			return CODEMP
		end,
	}
end

return CODEMP
