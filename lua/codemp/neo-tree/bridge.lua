local renderer = require("neo-tree.ui.renderer")
local codemp = require("codemp.session")
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

local function new_root(name)
	return {
		id = "codemp-tree-" .. name,
		name = name,
		type = "root",
		extra = {},
		children = {}
	}
end

---@return Item
local function spacer()
	return {
		id = "codemp-ws-spacer-" .. vim.fn.rand() % 1024,
		name = "",
		type = "spacer",
	}
end

M.update_state = function(state)
	---@type Item[]
	local root = {
		{
			id = "codemp",
			name = "codemp",
			type = "title",
			extra = {},
		}
	}

	if codemp.workspace ~= nil then
		table.insert(root, spacer())
		local ws_section = new_root("session #" .. codemp.workspace.name)
		for i, path in ipairs(codemp.workspace:filetree()) do
			table.insert(ws_section.children, new_item(codemp.workspace.name, path))
		end

		local usr_section = new_root("users")
		for user, buffer in pairs(buf_manager.users) do
			table.insert(usr_section.children, new_user(codemp.workspace.name, user))
		end
		if #buf_manager.users > 0 then
			table.insert(ws_section.children, spacer())
			table.insert(ws_section.children, usr_section)
		end
		table.insert(root, ws_section)
	end

	if codemp.client ~= nil then
		table.insert(root, spacer())
		local ws_section = new_root("workspaces")
		for _, ws in ipairs(codemp.available) do
			table.insert(ws_section.children, new_workspace(ws.name, ws.owned))
		end
		table.insert(root, ws_section)
	else
		table.insert(root, spacer())
		table.insert(root, new_root("[connect]"))
	end

	renderer.show_nodes(root, state)

	if codemp.workspace ~= nil then
		for _, node in ipairs(state.tree:get_nodes()) do
			node:expand()
		end
	end
end

return M
