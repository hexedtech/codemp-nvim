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

		-- hook serverbound callbacks
		local group = vim.api.nvim_create_augroup("codemp-workspace", { clear = true })
		vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
			group = group,
			callback = function (_)
				local cur = cursor_position()
				controller:send("", cur[1][1], cur[1][2], cur[2][1], cur[2][2])
			end
		})

		-- hook clientbound callbacks
		local ns = vim.api.nvim_create_namespace("codemp-cursors")
		local buffer = vim.api.nvim_get_current_buf()
		register_async_waker(nil, function()
			while true do
				local event = controller:recv()
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
	"Attach",
	function (args)
		codemp.connect(#args.args > 0 and args.args or nil)
		print(" ++ connected")
	end,
	{ nargs = 1 }
)

return codemp
