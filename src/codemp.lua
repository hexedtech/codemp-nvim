local codemp = require("libcodemp_nvim")

local codemp_changed_tick = 0 -- TODO this doesn't work when events are coalesced

local function register_controller_handler(target, controller, handler)
	local async = vim.loop.new_async(function()
		while true do
			local event = controller:try_recv()
			if event == nil then break end
			vim.schedule(function() handler(event) end)
		end
	end)
	-- TODO controller can't be passed to the uvloop new_thread: when sent to the new 
	--  Lua runtime it "loses" its methods defined with mlua, making the userdata object 
	--  completely useless. We can circumvent this by requiring codemp again in the new 
	--  thread and requesting a new reference to the same controller from che global instance
	-- NOTE variables prefixed with underscore live in another Lua runtime
	vim.loop.new_thread({}, function(_async, _target)
		local _codemp = require("libcodemp_nvim")
		local _controller = _target ~= nil and _codemp.get_buffer(_target) or _codemp.get_cursor()
		while true do
			_controller:poll()
			_async:send()
		end
	end, async, target)
end

local function split_without_trim(str, sep)
	local res = vim.fn.split(str, sep)
	if str:sub(1,1) == "\n" then
		table.insert(res, 1, '')
	end
	if str:sub(-1) == "\n" then
		table.insert(res, '')
	end
	return res
end

local function order_tuples(x) -- TODO send help...
	if x[1][1] < x[2][1] then
		return { { x[1][1], x[1][2] }, { x[2][1], x[2][2] } }
	elseif x[1][1] > x[2][1] then
		return { { x[2][1], x[2][2] }, { x[1][1], x[1][2] } }
	elseif x[1][2] < x[2][2] then
		return { { x[1][1], x[1][2] }, { x[2][1], x[2][2] } }
	else
		return { { x[2][1], x[2][2] }, { x[1][1], x[1][2] } }
	end
end

local function cursor_position()
	local mode = vim.api.nvim_get_mode().mode
	if mode == "v" then
		local _, ls, cs = unpack(vim.fn.getpos('v'))
		local _, le, ce = unpack(vim.fn.getpos('.'))
		return order_tuples({ { ls-1, cs-1 }, { le-1, ce } })
	elseif mode == "V" then
		local _, ls, _ = unpack(vim.fn.getpos('v'))
		local _, le, _ = unpack(vim.fn.getpos('.'))
		if le > ls then
			local ce = vim.fn.strlen(vim.fn.getline(le))
			return { { ls-1, 0 }, { le-1, ce } }
		else
			local ce = vim.fn.strlen(vim.fn.getline(ls))
			return { { le-1, 0 }, { ls-1, ce } }
		end
	else
		local win = vim.api.nvim_get_current_win()
		local cur = vim.api.nvim_win_get_cursor(win)
		return order_tuples({ { cur[1]-1, cur[2] }, { cur[1]-1, cur[2]+1 } })
	end
end

local function buffer_get_content(buf)
	if buf == nil then
		buf = vim.api.nvim_get_current_buf()
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, '\n')
end

-- local function buffer_set_content(buf, content)
-- 	local lines = split_without_trim(content, "\n")
-- 	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
-- end

local function buffer_replace_content(buffer, first, last, content)
	-- TODO send help it works but why is lost knowledge
	local start_row = vim.fn.byte2line(first + 1) - 1
	if start_row < 0 then start_row = 0 end
	local start_row_byte = vim.fn.line2byte(start_row + 1) - 1
	if start_row_byte < 0 then start_row_byte = 0 end
	local end_row = vim.fn.byte2line(last + 1) - 1
	if end_row < 0 then end_row = 0 end
	local end_row_byte = vim.fn.line2byte(end_row + 1) - 1
	if end_row_byte < 0 then end_row_byte = 0 end
	vim.api.nvim_buf_set_text(
		buffer,
		start_row,
		first - start_row_byte,
		end_row,
		last - end_row_byte,
		vim.fn.split(content, '\n', true)
	)
end

local function multiline_highlight(buf, ns, group, start, fini)
	for i=start.row,fini.row do
		if i == start.row and i == fini.row then
			local fini_col = fini.col
			if start.col == fini.col then fini_col = fini_col + 1 end
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, start.col, fini_col)
		elseif i == start.row then
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, start.col, -1)
		elseif i == fini.row then
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, 0, fini.col)
		else
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, 0, -1)
		end
	end
end

local buffer_mappings = {}
local buffer_mappings_reverse = {} -- TODO maybe not???
local user_mappings = {}
local available_colors = { -- TODO these are definitely not portable!
	"ErrorMsg",
	"WarningMsg",
	"MatchParen",
	"SpecialMode",
	"CmpItemKindFunction",
	"CmpItemKindValue",
	"CmpItemKindInterface",
}

vim.api.nvim_create_user_command(
	"Connect",
	function (args)
		codemp.connect(#args.args > 0 and args.args or nil)
		print(" ++ connected")
	end,
	{ nargs = "?" }
)

vim.api.nvim_create_user_command(
	"Join",
	function (args)
		local controller = codemp.join(args.args)

		-- hook serverbound callbacks
		vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "ModeChanged"}, {
			group = vim.api.nvim_create_augroup("codemp-workspace-" .. args.args, { clear = true }),
			callback = function (_)
				local cur = cursor_position()
				local buf = vim.api.nvim_get_current_buf()
				if buffer_mappings[buf] ~= nil then
					controller:send(buffer_mappings[buf], cur[1][1], cur[1][2], cur[2][1], cur[2][2])
				end
			end
		})

		-- hook clientbound callbacks
		register_controller_handler(nil, controller, function(event)
			if user_mappings[event.user] == nil then
				user_mappings[event.user] = {
					ns = vim.api.nvim_create_namespace("codemp-cursor-" .. event.user),
					hi = available_colors[ math.random( #available_colors ) ],
				}
			end
			local buffer = buffer_mappings_reverse[event.position.buffer]
			if buffer ~= nil then
				vim.api.nvim_buf_clear_namespace(buffer, user_mappings[event.user].ns, 0, -1)
				multiline_highlight(
					buffer,
					user_mappings[event.user].ns,
					user_mappings[event.user].hi,
					event.position.start,
					event.position.finish
				)
			end
		end)

		print(" ++ joined workspace " .. args.args)
	end,
	{ nargs = 1 }
)

vim.api.nvim_create_user_command(
	"Create",
	function (args)
		local content = nil
		if args.bang then
			local buf = vim.api.nvim_get_current_buf()
			content = buffer_get_content(buf)
		end
		codemp.create(args.args, content)

		print(" ++ created buffer " .. args.args)
	end,
	{ nargs = 1, bang = true }
)

vim.api.nvim_create_user_command(
	"Attach",
	function (args)
		local controller = codemp.attach(args.args)

		-- TODO map name to uuid

		local buffer = vim.api.nvim_get_current_buf()
		buffer_mappings[buffer] = args.args
		buffer_mappings_reverse[args.args] = buffer

		-- hook serverbound callbacks
		vim.api.nvim_buf_attach(buffer, false, {
			on_lines = function (_, buf, tick, firstline, lastline, new_lastline, old_byte_size)
				if tick <= codemp_changed_tick then return end
				local start = vim.api.nvim_buf_get_offset(buf, firstline)
				local content = table.concat(vim.api.nvim_buf_get_lines(buf, firstline, new_lastline, false), '\n')
				if start == -1 then start = 0 end
				if new_lastline < lastline then old_byte_size = old_byte_size + 1 end
				controller:send(start, start + old_byte_size - 1, content)
			end
		})

		-- hook clientbound callbacks
		register_controller_handler(args.args, controller, function(event)
			codemp_changed_tick = vim.api.nvim_buf_get_changedtick(buffer) + 1
			buffer_replace_content(buffer, event.first, event.last, event.content)
		end)

		print(" ++ joined workspace " .. args.args)
	end,
	{ nargs = 1 }
)

-- TODO nvim docs say that we should stop all threads before exiting nvim
--  but we like to live dangerously (:
vim.loop.new_thread({}, function()
	local _codemp = require("libcodemp_nvim")
	local logger = _codemp.setup_tracing()
	while true do
		print(logger:recv())
	end
end)

return {
	lib = codemp,
	utils = {
		buffer = buffer_get_content,
		cursor  = cursor_position,
		split = split_without_trim,
	}
}
