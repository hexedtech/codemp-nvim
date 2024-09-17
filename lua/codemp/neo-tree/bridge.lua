local renderer = require("neo-tree.ui.renderer")
local buf_manager = require("codemp.buffers")
---@module 'nui.tree'

local M = {}

---@param workspace string workspace name
---@param path string buffer relative path
---@return NuiTree.Node
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
---@return NuiTree.Node
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
---@return NuiTree.Node
local function new_workspace(name, owned, expanded)
	return {
		id = "codemp://" .. name,
		name = name,
		type = "workspace",
		extra = {
			owned = owned,
		},
		children = {},
	}
end


---@param key string
---@param value string
---@return NuiTree.Node
local function new_entry(key, value)
	return {
		id = "codemp-entry-" .. key .. "-" .. value,
		name = key .. ": " .. value,
		type = "entry",
		extra = {},
	}
end

local function new_root(name)
	return {
		id = "codemp-tree-" .. name,
		name = name,
		type = "root",
		expanded = true,
		expand = true,
		extra = {},
		children = {}
	}
end

local function new_button(name)
	return {
		id = "codemp-button-" .. name,
		name = name,
		type = "button",
		extra = {},
		children = {}
	}
end

local counter = 0;

---@return NuiTree.Node
local function spacer()
	counter = counter + 1
	return {
		id = "codemp-ws-spacer-" .. counter,
		name = "",
		type = "spacer",
	}
end

local last_state = "N/A"

---@param tree NuiTree
local function expand(tree)
	---@param node? NuiTree.Node
	local function process(node)
		local id = nil
		if node ~= nil then id = node:get_id() end
		for _, node in ipairs(tree:get_nodes(id)) do
			node:expand()
			if node:has_children() then
				process(node)
			end
		end
	end

	process()
end


M.update_state = function(state)
	---@type NuiTree.Node[]
	local root = {
		{
			id = "codemp",
			name = "codemp",
			type = "title",
			extra = {},
		}
	}

	if CODEMP.workspace ~= nil then
		local ws_section = new_root("#" .. CODEMP.workspace.name)
		for i, path in ipairs(CODEMP.workspace:filetree()) do
			table.insert(ws_section.children, new_item(CODEMP.workspace.name, path))
		end

		local usr_section = new_root("users")
		for user, buffer in pairs(buf_manager.users) do
			table.insert(usr_section.children, new_user(CODEMP.workspace.name, user))
		end
		table.insert(ws_section.children, spacer())
		table.insert(ws_section.children, usr_section)

		table.insert(root, spacer())
		table.insert(root, ws_section)
	end

	if CODEMP.client ~= nil then
		local ws_section = new_root("workspaces")
		for _, ws in ipairs(CODEMP.available) do
			table.insert(ws_section.children, new_workspace(ws.name, ws.owned))
		end
		table.insert(root, spacer())
		table.insert(root, ws_section)

		local status_section = new_root("client")
		table.insert(status_section.children, new_entry("id", CODEMP.client.id))
		table.insert(status_section.children, new_entry("name", CODEMP.client.username))

		table.insert(root, spacer())
		table.insert(root, status_section)
	end

	if CODEMP.client == nil then
		table.insert(root, spacer())
		table.insert(root, new_button("[connect]"))
	end

	renderer.show_nodes(root, state)

	local new_state = "disconnected"
	if CODEMP.client ~= nil then new_state = "connected" end
	if CODEMP.workspace ~= nil then new_state = "joined" end

	if last_state ~= new_state then expand(state.tree) end
	last_state = new_state
end

return M
