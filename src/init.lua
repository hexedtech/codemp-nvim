local path = vim.fn.stdpath('data') .. '/codemp/'
if vim.fn.isdirectory(path) == 0 then
	vim.fn.mkdir(path, 'p')
end

-- -- TODO not the best loader but a simple example? urls dont work
-- local host_os = vim.loop.os_uname().sysname
-- local ext = nil
-- if host_os == "Windows" then ext = ".dll"
-- elseif host_os == "Mac" then ext = ".dylib"
-- else ext = ".so"
-- end
-- 
-- local shasum = nil
-- 
-- if vim.fn.filereadable(path .. 'native' .. ext) == 1 then
-- 	shasum = vim.fn.system("sha256sum " .. path .. 'native' .. ext)
-- end
-- 
-- local last_sum = vim.fn.system("curl -s https://codemp.alemi.dev/lib/lua/latest/sum")
-- 
-- if last_sum ~= shasum then
-- 	vim.fn.system("curl -o " .. path .. 'native' .. ext .. "https://codemp.alemi.dev/lib/lua/latest")
-- end

local native = require('codemp.loader').load() -- make sure we can load the native library correctly, otherwise no point going forward
local state = require('codemp.state')
native.runtime_drive_forever() -- spawn thread to drive tokio runtime

vim.api.nvim_create_autocmd(
	{"ExitPre"},
	{
		callback = function (ev)
			if state.client ~= nil then
				print(" xx disconnecting codemp client")
				native.close_client(state.client.id)
				state.client = nil
			end
		end
	}
)

-- TODO nvim docs say that we should stop all threads before exiting nvim
--  but we like to live dangerously (:
vim.loop.new_thread({}, function()
	vim.loop.sleep(1000) -- allow user to setup their own logger options
	local _codemp = require('codemp.loader').load()
	_codemp.setup_logger()
	local logger = _codemp.get_logger()
	while true do
		print(logger:recv())
	end
end)

require('codemp.command')

return {
	native = native,
	state = require('codemp.state'),
	buffers = require('codemp.buffers'),
	workspace = require('codemp.workspace'),
	window = require('codemp.window'),
	utils = require('codemp.utils'),
	async = require('codemp.async'),
}
