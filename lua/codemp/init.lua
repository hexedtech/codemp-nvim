local rt = nil
local session = nil
local native = nil
local timer = nil

local function setup(opts)
	local path = vim.fn.stdpath('data') .. '/codemp/'
	if vim.fn.isdirectory(path) == 0 then
		vim.fn.mkdir(path, 'p')
	end
	
	if native == nil then
		native = require('codemp.loader').load() -- make sure we can load the native library correctly, otherwise no point going forward
		--native.logger(function (msg)
		--	vim.schedule(function () print(msg) end)
		--end, true)
	end

	if session == nil then
		session = require('codemp.session')
	end

	if rt == nil then
		rt = native.spawn_runtime_driver() -- spawn thread to drive tokio runtime
		vim.api.nvim_create_autocmd(
			{"ExitPre"},
			{
				callback = function (_ev)
					if session.client ~= nil then
						print(" xx disconnecting codemp client")
						session.client = nil
					end
					rt:stop()
				end
			}
		)
	end
	
	local timer_interval = vim.g.codemp_callback_interval or 100
	
	if timer == nil then
		timer = vim.loop.new_timer()
		timer:start(timer_interval, timer_interval, function()
			while true do
				local cb = native.poll_callback()
				if cb == nil then break end
				cb()
			end
		end)
	end

	require('codemp.command')

	return {
		native = native,
		session = session,
		buffers = require('codemp.buffers'),
		workspace = require('codemp.workspace'),
		window = require('codemp.window'),
		utils = require('codemp.utils'),
		logger = native.logger,
		rt = rt,
		callbacks_timer = timer,
	}
end

return {
	setup = setup
}
