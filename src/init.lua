local native = require('codemp.loader')() -- make sure we can load the native library correctly, otherwise no point going forward


-- TODO nvim docs say that we should stop all threads before exiting nvim
--  but we like to live dangerously (:
vim.loop.new_thread({}, function()
	vim.loop.sleep(500) -- sleep a bit leaving user config time to override logger opts
	local _codemp = require('codemp.loader')()
	local logger = _codemp.setup_tracing()
	while true do
		print(logger:recv())
	end
end)

local command = require('codemp.command')

return {
	native = native,
	client = require('codemp.client'),
	buffers = require('codemp.buffer'),
	workspace = require('codemp.workspace'),
	utils = require('codemp.utils'),
	async = require('codemp.async'),
}
