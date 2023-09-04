local codemp = require("libcodemp_nvim")

local codemp_changed_tick = nil -- TODO this doesn't work when events are coalesced

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

-- local function byte2rowcol(buf, x)
-- 	local row
-- 	local row_start
-- 	vim.api.nvim_buf_call(buf, function ()
-- 		row = vim.fn.byte2line(x)
-- 		row_start = vim.fn.line2byte(row)
-- 	end)
-- 	local col = x - row_start
-- 	return { row, col }
-- end

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

local function buffer_set_content(buf, content)
	local lines = split_without_trim(content, "\n")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

local function multiline_highlight(buf, ns, group, start, fini)
	for i=start[1],fini[1] do
		if i == start[1] and i == fini[1] then
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, start[2], fini[2])
		elseif i == start[1] then
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, start[2], -1)
		elseif i == fini[1] then
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, 0, fini[2])
		else
			vim.api.nvim_buf_add_highlight(buf, ns, group, i, 0, -1)
		end
	end
end

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
		local buffer = vim.api.nvim_get_current_buf()
		local ns = vim.api.nvim_create_namespace("codemp-cursors")

		-- hook serverbound callbacks
		vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI", "ModeChanged"}, {
			group = vim.api.nvim_create_augroup("codemp-workspace-" .. args.args, { clear = true }),
			callback = function (_)
				local cur = cursor_position()
				controller:send("", cur[1][1], cur[1][2], cur[2][1], cur[2][2])
			end
		})

		-- hook clientbound callbacks
		register_controller_handler(nil, controller, function(event)
			vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1)
			multiline_highlight(buffer, ns, "ErrorMsg", event.start, event.finish)
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

		local buffer = vim.api.nvim_get_current_buf()

		buffer_set_content(buffer, controller.content)

		-- hook serverbound callbacks
		vim.api.nvim_buf_attach(buffer, false, {
			on_lines = function (_, buf, tick, firstline, lastline, new_lastline, old_byte_size)
				if tick == codemp_changed_tick then return end
				print(string.format(">[%s] %s:%s|%s (%s)", tick, firstline, lastline, new_lastline, old_byte_size))
				local start_index = firstline == 0 and 0 or vim.fn.line2byte(firstline + 1) - 1
				local text = table.concat(
					vim.api.nvim_buf_get_lines(buf, firstline, new_lastline, true),
					"\n"
				)
				if lastline ~= new_lastline then
					text = text .. "\n"
				end
				print(string.format(">delta [%d,%s,%d]", start_index, text, start_index + old_byte_size - 1))
				controller:delta(start_index, text, start_index + old_byte_size - 1)
			end
		})

		-- hook clientbound callbacks
		register_controller_handler(args.args, controller, function(event)
			codemp_changed_tick = vim.api.nvim_buf_get_changedtick(buffer) + 1
			local start = controller:byte2rowcol(event.start)
			local finish = controller:byte2rowcol(event.finish)
			print(string.format(
				"buf_set_text(%s,%s, %s,%s, '%s')",
				start.row, start.col, finish.row, finish.col, vim.inspect(split_without_trim(event.content, "\n"))
			))
			vim.api.nvim_buf_set_text(
				buffer, start.row, start.col, finish.row, finish.col,
				split_without_trim(event.content, "\n")
			)
		end)

		print(" ++ joined workspace " .. args.args)
	end,
	{ nargs = 1 }
)

return {
	lib = codemp,
	utils = {
		buffer = buffer_get_content,
		cursor  = cursor_position,
		split = split_without_trim,
	}
}
