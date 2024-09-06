local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")
local session = require("codemp.session")
local buf_manager = require("codemp.buffers")
local ws_manager = require("codemp.workspace")
local client_manager = require("codemp.client")

local M = {}

M.refresh = require("neo-tree.utils").wrap(manager.refresh, "codemp")

M.open = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "spacer" then return end
	if selected.type == "root" then
		if session.client ~= nil then
			print(" +-+ connected to codemp as " .. session.client.username)
		else
			client_manager.connect()
		end
		return
	end
	if selected.type == "workspace" then
		if selected:is_expanded() then
			vim.ui.input({ prompt = "disconnect from workspace?" }, function (input)
				if input == nil then return end
				if input ~= "y" then return end
				ws_manager.leave()
				selected:collapse()
				manager.refresh("codemp")
			end)
		else
			if session.workspace ~= nil and session.workspace.name ~= selected.name then
				error("must leave current workspace first")
			end
			if session.workspace == nil then
				ws_manager.join(selected.name)
			end
			selected:expand()
			manager.refresh("codemp")
		end
		return
	end
	if selected.type == "buffer" then
		local window = utils.get_appropriate_window(state)
		local buf = vim.api.nvim_win_get_buf(window)
		vim.api.nvim_set_current_win(window)
		buf_manager.attach(selected.name, buf)
		return
	end
	if selected.type == "user" then
		print("another remote user")
		return
	end
	error("unrecognized node type")
end

M.add = function(_state)
	if session.client == nil then
		vim.ui.input({ prompt = "server address" }, function(input)
			if input == nil or input == "" then return end
			client_manager.connect(input)
		end)
	elseif session.workspace == nil then
		vim.ui.input({ prompt = "workspace name" }, function(input)
			if input == nil or input == "" then return end
			session.client:create_workspace(input):await()
			manager.refresh("codemp")
		end)
	else
		vim.ui.input({ prompt = "buffer path" }, function(input)
			if input == nil or input == "" then return end
			session.workspace:create_buffer(input):await()
			manager.refresh("codemp")
		end)
	end
end

cc._add_common_commands(M)
return M
