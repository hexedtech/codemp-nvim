local workspace = require("codemp.workspace")
local buffers = require("codemp.buffers")
local utils = require("codemp.utils")
local enums = require("codemp.enums")

local events_poller = nil

local function connect()
	---@type Config
	local tmp_cfg = vim.tbl_extend('force', {}, CODEMP.config)
	if tmp_cfg.username == nil or #tmp_cfg.username == 0 then
		tmp_cfg.username = vim.g.codemp_username or vim.fn.input("username > ", "")
	end
	if tmp_cfg.password == nil or #tmp_cfg.password == 0 then
		tmp_cfg.password = vim.g.codemp_password or vim.fn.input("password > ", "")
	end
	print(" -- connecting ...")
	CODEMP.native.connect(tmp_cfg):and_then(function (client)
		print(" ++ connected")
		CODEMP.client = client
		require('codemp.window').update()
		workspace.list()

		events_poller = utils.poller(
			function()
				if CODEMP.client == nil then return nil end
				return CODEMP.client:recv()
			end,
			---@param event SessionEvent
			function(event)
				if event.kind == enums.SessionEventKind.InvitationEvent then
					require('codemp.window').update()
				end
			end
		)

		local client_buffer_callback_group = vim.api.nvim_create_augroup("codemp-client-" .. client:current_user().name, {})

		vim.api.nvim_create_autocmd({"BufReadPost"}, {
			group = client_buffer_callback_group,
			callback = function (ev)
				if CODEMP.workspace ~= nil and CODEMP.auto_share then
					local bufname = string.gsub(
						vim.api.nvim_buf_get_name(ev.buf),
						vim.fn.getcwd() .. '/',
						""
					)
					if buffers.map_rev[bufname] == nil then
						CODEMP.workspace:create_buffer(bufname, { ephemeral = true }):and_then(function ()
							buffers.attach(bufname, {
								buffer = ev.buf,
								content = utils.buffer.get_content(ev.buf),
								skip_exists_check = true,
							})
						end)
					end
				end
			end
		})
	end)


end

return {
	connect = connect
}
