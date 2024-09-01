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
local session = require('codemp.session')
local rt = native.spawn_runtime_driver() -- spawn thread to drive tokio runtime
--native.logger(function (msg)
--	vim.schedule(function () print(msg) end)
--end, true)

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

require('codemp.command')

return {
	native = native,
	session = session,
	buffers = require('codemp.buffers'),
	workspace = require('codemp.workspace'),
	window = require('codemp.window'),
	utils = require('codemp.utils'),
	rt = rt,
}
