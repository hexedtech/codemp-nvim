local codemp = require("libcodemp_nvim")
local active_workspace = nil

local codemp_changed_tick = {}

local function register_controller_handler(target, controller, handler, delay)
	local async = vim.loop.new_async(function()
		while true do
			local success, event = pcall(controller.try_recv, controller)
			if success then
				if event == nil then break end
				vim.schedule(function() handler(event) end)
			else
				print("error receiving: deadlocked?")
			end
		end
	end)
	-- TODO controller can't be passed to the uvloop new_thread: when sent to the new 
	--  Lua runtime it "loses" its methods defined with mlua, making the userdata object 
	--  completely useless. We can circumvent this by requiring codemp again in the new 
	--  thread and requesting a new reference to the same controller from che global instance
	-- NOTE variables prefixed with underscore live in another Lua runtime
	vim.loop.new_thread({}, function(_async, _workspace, _target, _delay)
		local _codemp = require("libcodemp_nvim")
		local _ws = _codemp.get_workspace(_workspace)
		local _controller = _target ~= nil and _ws:get_buffer(_target) or _ws.cursor
		while true do
			local success, _ = pcall(_controller.poll, _controller)
			if success then
				_async:send()
				if _delay ~= nil then vim.loop.sleep(_delay) end
			else
				local my_name = "cursor"
				if _target ~= nil then
					my_name = "buffer(" .. _target .. ")"
				end
				print(" -- stopping " .. my_name .. " controller poller")
				break
			end
		end
	end, async, active_workspace, target, delay)
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

local function buffer_set_content(buf, content)
	local lines = split_without_trim(content, "\n")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

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

-- vim.api.nvim_create_user_command(
-- 	"Connect",
-- 	function (args)
-- 		codemp.connect(#args.args > 0 and args.args or nil)
-- 		print(" ++ connected")
-- 	end,
-- 	{ nargs = "?" }
-- )

vim.api.nvim_create_user_command(
	"Login",
	function (args)
		codemp.login(args.fargs[1], args.fargs[2], args.fargs[3])
		print(" ++ logged in " .. args.args)
	end,
	{ nargs = "+" }
)

vim.api.nvim_create_user_command(
	"Join",
	function (args)
		local controller = codemp.join_workspace(args.args)
		active_workspace = args.args

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
		end, 20)

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
			-- TODO send content!
		end
		codemp.get_workspace(active_workspace):create_buffer(args.args, content)

		print(" ++ created buffer " .. args.args)
	end,
	{ nargs = 1, bang = true }
)

vim.api.nvim_create_user_command(
	"Attach",
	function (args)
		local buffer = nil
		if args.bang then
			buffer = vim.api.nvim_get_current_buf()
			buffer_set_content(buffer, "")
		else
			buffer = vim.api.nvim_create_buf(true, true)
			vim.api.nvim_buf_set_option(buffer, 'fileformat', 'unix')
			vim.api.nvim_buf_set_option(buffer, 'filetype', 'codemp')
			vim.api.nvim_buf_set_name(buffer, "codemp::" .. args.args)
			vim.api.nvim_set_current_buf(buffer)
		end
		local controller = codemp.get_workspace(active_workspace):attach_buffer(args.args)

		-- TODO map name to uuid

		buffer_mappings[buffer] = args.args
		buffer_mappings_reverse[args.args] = buffer
		codemp_changed_tick[buffer] = 0

		-- hook serverbound callbacks
		-- TODO breaks when deleting whole lines at buffer end
		vim.api.nvim_buf_attach(buffer, false, {
			on_bytes = function(_, buf, tick, start_row, start_col, start_offset, old_end_row, old_end_col, old_end_byte_len, new_end_row, new_end_col, new_byte_len)
				if tick <= codemp_changed_tick[buf] then return end
				if buffer_mappings[buf] == nil then return true end -- unregister callback handler
				local text = buffer_get_content(buf)
				print(string.format("CRDT content: %s", controller.content))
				controller:send(0, #controller.content, text)
				-- local content = ""
				-- if old_end_row < new_end_row and new_byte_len == 1 then
				-- 	content = "\n"
				-- else
				-- 	print(string.format("%s %s %s %s", start_row, start_col, start_row + new_end_row, start_col + new_end_col))
				-- 	content = table.concat(vim.api.nvim_buf_get_text(buf, start_row - 1, start_col, start_row + new_end_row - 1, start_col + new_end_col, {}), '\n')
				-- end
				-- if old_end_row < new_end_row then
				-- 	start_offset = start_offset - 1
				-- end
				-- controller:send(start_offset, start_offset + old_end_byte_len, content)
			end,
		})

		-- This is an ugly as hell fix: basically we receive all operations real fast at the start
		--  so the buffer changes rapidly and it messes up tracking our delta/diff state and we 
		--  get borked translated TextChanges (the underlying CRDT is fine)
		-- basically delay a bit so that it has time to sync and we can then get "normal slow" changes
		-- vim.loop.sleep(200) -- moved inside poller thread to at least not block ui

		-- hook clientbound callbacks
		register_controller_handler(args.args, controller, function(event)
			codemp_changed_tick[buffer] = vim.api.nvim_buf_get_changedtick(buffer) + 1
			local before = buffer_get_content(buffer)
			local after = event:apply(before)
			buffer_set_content(buffer, after)
			-- buffer_replace_content(buffer, event.first, event.last, event.content)
		end, 20) -- wait 20ms before polling again because it overwhelms libuv?

		print(" ++ attached to buffer " .. args.args)
	end,
	{ nargs = 1, bang = true }
)

vim.api.nvim_create_user_command(
	"Sync",
	function (_)
		local buffer = vim.api.nvim_get_current_buf()
		local name = buffer_mappings[buffer]
		if name ~= nil then
			local controller = codemp.get_workspace(active_workspace):get_buffer(name)
			codemp_changed_tick[buffer] = vim.api.nvim_buf_get_changedtick(buffer) + 1
			buffer_set_content(buffer, controller.content)
			print(" :: synched buffer " .. name)
		else
			print(" !! buffer not managed")
		end
	end,
	{ }
)

vim.api.nvim_create_user_command(
	"Detach",
	function (args)
		local buffer = buffer_mappings_reverse[args.args]
		if buffer == nil then buffer = vim.api.nvim_get_current_buf() end
		local name = buffer_mappings[buffer]
		buffer_mappings[buffer] = nil
		buffer_mappings_reverse[name] = nil
		codemp.get_workspace(active_workspace):disconnect_buffer(name)
		vim.api.nvim_buf_delete(buffer, {})
		print(" -- detached from buffer " .. name)
	end,
	{ nargs = '?' }
)

vim.api.nvim_create_user_command(
	"Leave",
	function (_)
		codemp.leave_workspace()
		print(" -- left workspace")
	end,
	{}
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
