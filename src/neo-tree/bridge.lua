local renderer = require("neo-tree.ui.renderer")
local codemp = require("codemp.session")
local cc = require("neo-tree.sources.common.commands")
local buf_manager = require("codemp.buffers")

local M = {}

---@class Item
---@field id string
---@field name string
---@field type string
---@field loaded any
---@field filtered_by any
---@field extra table
---@field is_nested any
---@field skip_node any
---@field is_empty_with_hidden_root any
---@field stat any
---@field stat_provider any
---@field is_link any
---@field link_to any
---@field path any
---@field ext any
---@field search_pattern any

---@param workspace string workspace name
---@param path string buffer relative path
---@return Item
local function new_item(workspace, path)
	return {
		id = string.format("codemp://%s/%s", workspace, path),
		name = path,
		type = "buffer",
		extra = {},
		children = {},
	}
end

---@param workspace string workspace name
---@param username string user display name
---@return Item
local function new_user(workspace, username)
	return {
		id = string.format("codemp://%s@%s", username, workspace),
		name = username,
		type = "user",
		extra = {},
		children = {},
	}
end

---@param name string workspace name
---@param owned boolean true if this workspace is owned by us
---@param expanded? boolean if node should be pre-expanded
---@return Item
local function new_workspace(name, owned, expanded)
	return {
		id = "codemp://" .. name,
		name = name,
		type = "workspace",
		['_is_expanded'] = expanded, -- TODO this is nasty can we do better?
		extra = {
			owned = owned,
		},
		children = {},
	}
end

local function spacer()
	return {
		id = "codemp-ws-spacer-" .. vim.fn.rand() % 1024,
		name = "",
		type = "spacer",
	}
end

M.update_state = function(state)
	---@type Item
	local root

	if codemp.workspace ~= nil then
		root = {
			id = "codemp",
			name = codemp.client.username .. "@" .. codemp.workspace.name,
			type = "root",
			extra = {},
			children = {}
		}
		table.insert(root.children, spacer())
		for i, path in ipairs(codemp.workspace:filetree()) do
			table.insert(root.children, new_item(codemp.workspace.name, path))
		end
		table.insert(root.children, spacer())
		for user, buffer in pairs(buf_manager.users) do
			table.insert(root.children, new_user(codemp.workspace.name, user))
		end
	elseif codemp.client ~= nil then
		root = {
			id = "codemp",
			name = codemp.client.username .. "@codemp",
			type = "root",
			extra = {},
			children = {}
		}
		for _, ws in ipairs(codemp.available) do
			local workspace = new_workspace(ws.name, ws.owned)

			if codemp.workspace ~= nil and codemp.workspace.name == ws.name then
			end

			table.insert(root.children, workspace)
		end
	else
		root = {
			id = "codemp",
			name = "codemp",
			type = "root",
			extra = {},
			children = {}
		}
	end

	renderer.show_nodes({ root }, state)

	if codemp.workspace ~= nil then
		for _, node in ipairs(state.tree:get_nodes()) do
			node:expand()
		end
	end
end

return M
