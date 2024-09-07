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
		if codemp_buffers.map_rev[node.name] ~= nil then
			icon = "+ "
		else
			icon = "- "
		end
		highlight = highlights.FILE_ICON
	elseif node.type == "directory" then
		icon = "= "
		highlight = highlights.DIRECTORY_ICON
	elseif node.type == "root" then
		if node:is_expanded() then
			icon = "| "
		else
			icon = "> "
		end
		highlight = highlights.DIRECTORY_ICON
	elseif node.type == "workspace" then
		icon = "* "
		if node.extra.owned then
			highlight = highlights.GIT_STAGED
		else
			highlight = highlights.DIRECTORY_ICON
		end
	elseif node.type == "user" then
		icon = ":"
		highlight = codemp_utils.color(node.name)
	elseif node.type == "entry" then
		icon = "$"
		highlight = highlights.GIT_STAGED
	elseif node.type == "button" then
		icon = "  "
		highlight = highlights.NORMAL
	end

	return {
		text = icon,
		highlight = highlight,
	}
end

M.name = function(config, node, state)
	local highlight = config.highlight or highlights.FILE_NAME
	local text = node.name
	if node.type == "title" then
		text = " ::   " .. node.name .. "   :: "
		highlight = highlights.PREVIEW
	elseif node.type == "root" then
		highlight = highlights.FILTER_TERM
	elseif node.type == "button" then
		text = " " .. node.name .. " "
		highlight = highlights.FLOAT_TITLE
	end
	return {
		text = text,
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
				align = "end",
			})
		end
	end
	return out
end

return vim.tbl_deep_extend("force", common, M)
