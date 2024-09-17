local cc = require("neo-tree.sources.common.commands")
local utils = require("neo-tree.utils")
local codemp_utils = require("codemp.utils")
local manager = require("neo-tree.sources.manager")
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
		if selected.name == "[connect]" and CODEMP.client == nil then
			client_manager.connect()
		end
		return
	end
	if selected.type == "workspace" then
		if CODEMP.workspace ~= nil and CODEMP.workspace.name ~= selected.name then
			error("must leave current workspace first")
		end
		if CODEMP.workspace == nil then
			ws_manager.join(selected.name)
		end
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
		local usr = ws_manager.map[selected.name]
		if usr ~= nil then
			local buf_name = buf_manager.users[selected.name]
			local buf_id = buf_manager.map_rev[buf_name]
			if buf_id ~= nil then
				local win = utils.get_appropriate_window(state)
				vim.api.nvim_set_current_win(win)
				vim.api.nvim_win_set_buf(win, buf_id)
				vim.api.nvim_win_set_cursor(win, { usr.pos[1] + 1, usr.pos[2] })
			else
				print(" /!\\ not attached to buffer '" .. buf_name .. "'")
			end
		end
		return
	end
	error("unrecognized node type")
end

M.move = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "buffer" then
		return vim.ui.input({ prompt = "move content into open buffer?" }, function (input)
			if input == nil then return end
			if not vim.startswith("y", string.lower(input)) then return end
			local window = utils.get_appropriate_window(state)
			local buf = vim.api.nvim_win_get_buf(window)
			buf_manager.attach(selected.name, buf)
		end)
	end
	error("only buffers can be moved to current file")
end

M.copy = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "buffer" then
		return vim.ui.input({ prompt = "copy content to remote buffer?" }, function (input)
			if input == nil then return end
			if not vim.startswith("y", string.lower(input)) then return end
			local window = utils.get_appropriate_window(state)
			local buf = vim.api.nvim_win_get_buf(window)
			local content = codemp_utils.buffer.get_content(buf)
			buf_manager.attach(selected.name, buf, content)
		end)
	end
	error("current file can only be copied into buffers")
end

M.delete = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "root" and vim.startswith(selected.name, "#") then
		vim.ui.input({ prompt = "disconnect from workspace?" }, function (input)
			if input == nil then return end
			if not vim.startswith("y", string.lower(input)) then return end
			ws_manager.leave()
		end)
	elseif selected.type == "buffer" then
		if CODEMP.workspace == nil then error("join a workspace first") end
		vim.ui.input({ prompt = "delete buffer '" .. selected.name .. "'?" }, function (input)
			if input == nil then return end
			if not vim.startswith("y", string.lower(input)) then return end
			CODEMP.workspace:delete(selected.name):and_then(function ()
				print("deleted buffer " .. selected.name)
				manager.refresh("codemp")
			end)
		end)
	elseif selected.type == "workspace" then
		if CODEMP.client == nil then error("connect to server first") end
		vim.ui.input({ prompt = "delete buffer '" .. selected.name .. "'?" }, function (input)
			if input == nil then return end
			if not vim.startswith("y", string.lower(input)) then return end
			CODEMP.client:delete_workspace(selected.name):and_then(function ()
				print("deleted workspace " .. selected.name)
				manager.refresh("codemp")
			end)
		end)
	end
end

M.add = function(state, path, extra)
	local selected = state.tree:get_node()
	if selected.type == "root" then
		if vim.startswith(selected.name, "#") then
			vim.ui.input({ prompt = "new buffer path" }, function(input)
				if input == nil or input == "" then return end
				CODEMP.workspace:create(input):and_then(function ()
					manager.refresh("codemp")
				end)
			end)
		elseif selected.name == "workspaces" then
			vim.ui.input({ prompt = "new workspace name" }, function(input)
				if input == nil or input == "" then return end
				CODEMP.client:create_workspace(input):and_then(function ()
					manager.refresh("codemp")
					require('codemp.workspace').list()
				end)
			end)
		end
	elseif selected.type == "workspace" then
		vim.ui.input({ prompt = "user name to invite" }, function(input)
			if input == nil or input == "" then return end
			CODEMP.client:invite_to_workspace(selected.name, input):and_then(function ()
				print("invited user " .. input .. " to workspace " .. selected.name)
			end)
		end)
	end
end

cc._add_common_commands(M)
return M
