-- This file contains the built-in components. Each componment is a function
-- that takes the following arguments:
--      config: A table containing the configuration provided by the user
--              when declaring this component in their renderer config.
--      node:   A NuiNode object for the currently focused node.
--      state:  The current state of the source providing the items.
--
-- The function should return either a table, or a list of tables, each of which
-- contains the following keys:
--    text:      The text to display for this item.
--    highlight: The highlight group to apply to this text.

local highlights = require("neo-tree.ui.highlights")
local common = require("neo-tree.sources.common.components")
local codemp_utils = require("codemp.utils")
local codemp_buffers = require("codemp.buffers")

local M = {}

M.icon = function(config, node, state)
	local icon, highlight
	if node.type == "buffer" then
		icon = "- "
		highlight = highlights.FILE_ICON
	elseif node.type == "directory" then
		icon = "= "
		highlight = highlights.DIRECTORY_ICON
	elseif node.type == "root" then
		icon = "> "
		highlight = highlights.FILE_STATS_HEADER
	elseif node.type == "workspace" then
		if node:is_expanded() then
			icon = "| "
		else
			icon = "+ "
		end
		highlight = highlights.SYMBOLIC_LINK_TARGET
	elseif node.type == "user" then
		icon = ":"
		highlight = codemp_utils.color(node.name)
	end

	return {
		text = icon,
		highlight = highlight,
	}
end

M.name = function(config, node, state)
	local highlight = config.highlight or highlights.FILE_NAME
	if node.type == "root" then
		highlight = highlights.ROOT_NAME
	elseif node.type == "workspace" then
		highlight = highlights.SYMBOLIC_LINK_TARGET
	end
	return {
		text = node.name,
		highlight = highlight,
	}
end

M.spacer = function(config, node, state)
	return {
		text = "  ",
		highlight = highlights.NORMAL,
	}
end

M.users = function(config, node, state)
	local out = {}
	-- TODO this is rather inefficient, maybe store reverse map precalculated?
	for user, buf in pairs(codemp_buffers.users) do
		if buf == node.name then
			table.insert(out, {
				text = " ",
				highlight = codemp_utils.color(user),
				align = "right",
			})
		end
	end
	return out
end

return vim.tbl_deep_extend("force", common, M)
