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
local utils = require("neo-tree.utils")
local file_nesting = require("neo-tree.sources.common.file-nesting")

local M = {}

M.icon = function(config, node, state)
	local icon, highlight
	if node.type == "buffer" then
		if codemp_buffers.map_rev[node.name] ~= nil then
			icon = ">"
		else
			icon = "+"
		end
		highlight = highlights.FILE_ICON
	elseif node.type == "directory" then
		icon = "= "
		highlight = highlights.DIRECTORY_ICON
	elseif node.type == "root" then
		if node:is_expanded() then
			icon = "┬"
		else
			icon = "─"
		end
		highlight = highlights.DIRECTORY_ICON
	elseif node.type == "workspace" then
		icon = "*"
		if node.extra.owned then
			highlight = highlights.GIT_STAGED
		else
			highlight = highlights.DIRECTORY_ICON
		end
	elseif node.type == "user" then
		if node.name == CODEMP.following then
			icon = "="
		else
			icon = ":"
		end
		highlight = codemp_utils.color(node.name).bg
	elseif node.type == "entry" then
		icon = "$"
		highlight = highlights.GIT_STAGED
	elseif node.type == "button" then
		icon = " "
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

M.buffer = function(config, node, state)
	return {
		text = codemp_buffers.users[node.name],
		highlight = highlights.FILE_ICON,
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
				text = string.sub(user, 0, 1).." ",
				highlight = codemp_utils.color(user).bg,
			})
		end
	end
	return out
end


-- this is basically copy-pasted from neo-tree source to remove the 0-depth case
-- https://github.com/nvim-neo-tree/neo-tree.nvim/blob/0774fa2085c62a147fcc7b56f0ac37053cc80217/lua/neo-tree/sources/common/components.lua#L383
M.indent = function(config, node, state)
	if not state.skip_marker_at_level then
		state.skip_marker_at_level = {}
	end

	local skip_marker = state.skip_marker_at_level
	local indent_size = config.indent_size or 2
	local padding = config.padding or 0
	local level = node.level
	local with_expanders = config.with_expanders == nil and file_nesting.is_enabled()
		or config.with_expanders
	local marker_highlight = config.highlight or highlights.INDENT_MARKER
	local expander_highlight = config.expander_highlight or config.highlight or highlights.EXPANDER

	local function get_expander()
		if with_expanders and utils.is_expandable(node) then
			return node:is_expanded() and (config.expander_expanded or "")
				or (config.expander_collapsed or "")
		end
	end

	local indent_marker = config.indent_marker or "│"
	local last_indent_marker = config.last_indent_marker or "└"

	skip_marker[level] = node.is_last_child
	local indent = {}
	if padding > 0 then
		table.insert(indent, { text = string.rep(" ", padding) })
	end

	for i = 1, level do
		local char = ""
		local spaces_count = indent_size
		local highlight = nil

		if i > 1 and not skip_marker[i] or i == level then
			spaces_count = spaces_count - 1
			char = indent_marker
			highlight = marker_highlight
			if i == level then
				local expander = get_expander()
				if expander then
					char = expander
					highlight = expander_highlight
				elseif node.is_last_child then
					char = last_indent_marker
					spaces_count = spaces_count - (vim.api.nvim_strwidth(last_indent_marker) - 1)
				end
			end
		end

		table.insert(indent, {
			text = char .. string.rep(" ", spaces_count),
			highlight = highlight,
			no_next_padding = true,
		})
	end

	return indent
end

return vim.tbl_deep_extend("force", common, M)
