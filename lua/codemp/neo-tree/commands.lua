local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local manager = require("neo-tree.sources.manager")
local session = require("codemp.session")
local buf_manager = require("codemp.buffers")
local ws_manager = require("codemp.workspace")
local client_manager = require("codemp.client")

local M = {}

local function toggle(node)
	if node:is_expanded() then
		node:collapse()
	else
		node:expand()
	end
	manager.refresh("codemp")
end

M.refresh = require("neo-tree.utils").wrap(manager.refresh, "codemp")

M.open = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "spacer" then return end
	if selected.type == "title" then return end
	if selected.type == "entry" then return end
	if selected.type == "root" then return toggle(selected) end
	if selected.type == "button" then
		if selected.name == "[connect]" and session.client == nil then
			client_manager.connect()
		end
		return
	end
	if selected.type == "workspace" then
		if session.workspace ~= nil and session.workspace.name ~= selected.name then
			error("must leave current workspace first")
		end
		if session.workspace == nil then
			ws_manager.join(selected.name)
		end
		selected:expand()
		manager.refresh("codemp")
		return
	end
	if selected.type == "buffer" then
		local window = utils.get_appropriate_window(state)
		vim.api.nvim_set_current_win(window)
		if buf_manager.map_rev[selected.name] ~= nil then
			vim.api.nvim_win_set_buf(window, buf_manager.map_rev[selected.name])
			return
		end
		local buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_win_set_buf(window, buf)
		buf_manager.attach(selected.name, buf)
		return
	end
	if selected.type == "user" then
		print("another remote user")
		return
	end
	error("unrecognized node type")
end

M.move = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "buffer" then
		local window = utils.get_appropriate_window(state)
		local buf = vim.api.nvim_win_get_buf(window)
		buf_manager.attach(selected.name, buf)
		return
	end
	error("only buffers can be moved to current file")
end

M.delete = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "root" and vim.startswith(selected.name, "#") then
		vim.ui.input({ prompt = "disconnect from workspace?" }, function (input)
			if input == nil then return end
			if input ~= "y" then return end
			ws_manager.leave()
			manager.refresh("codemp")
		end)
	elseif selected.type == "buffer" then
		if session.workspace == nil then error("join a workspace first") end
		session.workspace:delete_buffer(selected.name):await()
		print("deleted buffer " .. selected.name)
		manager.refresh("codemp")
	elseif selected.type == "workspace" then
		if session.client == nil then error("connect to server first") end
		session.client:delete_workspace(selected.name):await()
		print("deleted workspace " .. selected.name)
		manager.refresh("codemp")
	else
		print("/!\\ can only delete buffers and workspaces")
	end
end

M.add = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "root" then
		if vim.startswith(selected.name, "#") then
			vim.ui.input({ prompt = "buffer path" }, function(input)
				if input == nil or input == "" then return end
				session.workspace:create_buffer(input):await()
				manager.refresh("codemp")
			end)
		elseif selected.name == "workspaces" then
			vim.ui.input({ prompt = "workspace name" }, function(input)
				if input == nil or input == "" then return end
				session.client:create_workspace(input):await()
				manager.refresh("codemp")
			end)
		end
	elseif selected.type == "workspace" then
		vim.ui.input({ prompt = "user name" }, function(input)
			if input == nil or input == "" then return end
			session.client:invite_to_workspace(selected.name, input):await()
			print("invited user " .. input .. " to workspace " .. selected.name)
		end)
	end
	manager.refresh("codemp")
end

cc._add_common_commands(M)
return M
