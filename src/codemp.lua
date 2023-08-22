local codemp = require("libcodemp_nvim")

local function register_async_waker(target, cb)
	local async = vim.loop.new_async(cb)
	vim.loop.new_thread(function(_async, _target)
		local _codemp = require("libcodemp_nvim")
		local _cntrl
		if _target ~= nil then
			_cntrl = _codemp.get_buffer(_target)
		else
			_cntrl = _codemp.get_cursor()
		end
		while true do
			_cntrl:poll()
			_async:send()
		end
	end, async, target)
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
	if mode == "v" or mode == "V" then
		local _, ls, cs = unpack(vim.fn.getpos('v'))
		local _, le, ce = unpack(vim.fn.getpos('.'))
		return order_tuples({ { ls-1, cs-1 }, { le-1, ce } })
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
	local lines = vim.fn.split(content, "\n")
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
		vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
			group = vim.api.nvim_create_augroup("codemp-workspace-" .. args.args, { clear = true }),
			callback = function (_)
				local cur = cursor_position()
				controller:send("", cur[1][1], cur[1][2], cur[2][1], cur[2][2])
			end
		})

		-- hook clientbound callbacks
		register_async_waker(nil, function()
			while true do
				local event = controller:try_recv()
				if event == nil then break end
				vim.schedule(function()
					vim.api.nvim_buf_clear_namespace(buffer, ns, 0, -1)
					multiline_highlight(buffer, ns, "ErrorMsg", event.start, event.finish)
				end)
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
		local buffer = vim.api.nvim_get_current_buf()

		buffer_set_content(buffer, controller.content)

		-- hook serverbound callbacks
		vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
			group = vim.api.nvim_create_augroup("codemp-buffer-" .. args.args, { clear = true }),
			buffer = buffer,
			callback = function (_)
				controller:replace(buffer_get_content(buffer))
			end
		})

		-- hook clientbound callbacks
		register_async_waker(args.args, function()
			vim.schedule(function()
				buffer_set_content(buffer, controller.content)
			end)
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
	}
}
