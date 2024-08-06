local native = require('codemp.loader').load()

local utils = require('codemp.utils')
local buffers = require('codemp.buffers')
local async = require('codemp.async')

local user_hl = {}
local user_buffer = {}
local tree_buf = nil
local available_colors = { -- TODO these are definitely not portable!
	"ErrorMsg",
	"WarningMsg",
	"MatchParen",
	"SpecialMode",
	"CmpItemKindFunction",
	"CmpItemKindValue",
	"CmpItemKindInterface",
}

local function register_cursor_callback(controller, workspace, buffer)
	vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "ModeChanged"}, {
		group = vim.api.nvim_create_augroup("codemp-workspace-" .. workspace, { clear = true }),
		callback = function (_)
			local cur = utils.cursor.position()
			local buf = buffer or vim.api.nvim_get_current_buf()
			if buffers.map[buf] ~= nil then
				controller:send(buffers.map[buf], cur[1][1], cur[1][2], cur[2][1], cur[2][2])
			end
		end
	})
end

local function register_cursor_handler(controller, workspace)
	async.handler(workspace, nil, controller, function(event)
		if user_hl[event.user] == nil then
			user_hl[event.user] = {
				ns = vim.api.nvim_create_namespace("codemp-cursor-" .. event.user),
				hi = available_colors[ math.random( #available_colors ) ],
			}
		end
		user_buffer[event.user] = event.buffer
		local buffer = buffers.map_rev[event.position.buffer]
		if buffer ~= nil then
			vim.api.nvim_buf_clear_namespace(buffer, user_hl[event.user].ns, 0, -1)
			utils.multiline_highlight(
				buffer,
				user_hl[event.user].ns,
				user_hl[event.user].hi,
				event.position.start,
				event.position.finish
			)
		end
	end, 20)
end

local function join(workspace)
	local controller = native.join_workspace(workspace)
	register_cursor_callback(controller, workspace)
	register_cursor_handler(controller, workspace)
	print(" ++ joined workspace " .. workspace)
end

local function leave()
	native.leave_workspace()
	print(" -- left workspace")
end

local function open_buffer_tree(workspace)
	local tree = native.get_workspace(workspace).filetree
	if tree_buf == nil then
		tree_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(tree_buf, "codemp::" .. workspace)
		vim.api.nvim_set_option_value('buftype', 'nofile', { buf = tree_buf })
	end
	vim.api.nvim_set_option_value('modifiable', true, { buf = tree_buf })
	utils.buffer.set_content(tree_buf, "codemp::" .. workspace .. "\n\n- " .. vim.fn.join(tree, "\n- "))
	vim.api.nvim_set_option_value('modifiable', false, { buf = tree_buf })
	vim.api.nvim_open_win(tree_buf, true, {
		win = 0,
		split = 'left',
		width = 20,
	})
	vim.api.nvim_set_option_value('relativenumber', false, {})
	vim.api.nvim_set_option_value('number', false, {})
	vim.api.nvim_set_option_value('cursorlineopt', 'line', {})
end

return {
	join = join,
	leave = leave,
	map = user_hl,
	colors = available_colors,
	positions = user_buffer,
	open_buffer_tree = open_buffer_tree,
	buffer_tree = tree_buf,
}
