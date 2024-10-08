local utils = require('codemp.utils')

---@type table<integer, string>
local id_buffer_map = {}
---@type table<string, integer>
local buffer_id_map = {}
---@type table<string, string>
local user_buffer_name = {}
local ticks = {}

---@param name string
--TODO this should happen at the level above (Workspace) but accesses tables on this level, badly designed!
local function detach(name)
	local buffer = buffer_id_map[name]
	id_buffer_map[buffer] = nil
	buffer_id_map[name] = nil
	CODEMP.workspace:get_buffer(name):clear_callback()
	if not CODEMP.workspace:detach(name) then
		collectgarbage("collect") -- clear dangling references
	end

	print(" -- detached from buffer " .. name)

	require('codemp.window').update()
end

---@class AttachOptions
---@field content? string if provided, set this as content after attaching
---@field nowait? boolean skip waiting for initial content sync
---@field window? integer if given, open attached buffer in this window
---@field buffer? integer if given, use provided buffer instead of creating a new one
---@field skip_exists_check? boolean skip vim.fn.bufexists check, used for recursive call
---
---@param name string name of buffer to attach to
---@param opts AttachOptions options for attaching
local function attach(name, opts)
	if not opts.skip_exists_check and vim.fn.bufexists(name) == 1 then
		vim.ui.input(
			{ prompt = "buffer exists, overwrite?" },
			function (choice)
				if not vim.startswith(string.lower(choice), "y") then return end
				opts.buffer = vim.fn.bufnr(name)
				opts.skip_exists_check = true
				attach(name, opts)
			end
		)
		return
	end

	if buffer_id_map[name] ~= nil then
		return print(" !! already attached to buffer " .. name)
	end

	local buffer = opts.buffer
	if buffer == nil then
		buffer = vim.api.nvim_get_current_buf()
	end

	vim.api.nvim_buf_set_name(buffer, name)

	CODEMP.workspace:attach(name):and_then(function (controller)
		vim.schedule(function()
			-- TODO disgusting! but poll blocks forever on empty buffers...
			if not opts.nowait then
				local promise = controller:poll()
				for i=1, 20, 1 do
					if promise.ready then break end
					vim.uv.sleep(100)
				end
			end

			if opts.window ~= nil then
				vim.api.nvim_win_set_buf(opts.window, buffer)
				vim.api.nvim_set_current_win(opts.window)
			end

			-- TODO map name to uuid

			id_buffer_map[buffer] = name
			buffer_id_map[name] = buffer
			ticks[buffer] = 0

			-- hook serverbound callbacks
			-- TODO breaks when deleting whole lines at buffer end
			vim.api.nvim_buf_attach(buffer, false, {
				on_bytes = function(_, buf, tick, start_row, start_col, start_offset, old_end_row, old_end_col, old_end_byte_len, new_end_row, new_end_col, new_byte_len)
					if tick == ticks[buf] then return end
					if id_buffer_map[buf] == nil then return true end -- unregister callback handler
					if CODEMP.config.debug then print(string.format(
						"start(row:%s, col:%s) offset:%s end(row:%s, col:%s new(row:%s, col:%s)) len(old:%s, new:%s)",
						start_row, start_col, start_offset, old_end_row, old_end_col, new_end_row, new_end_col, old_end_byte_len, new_byte_len
					)) end
					local end_offset = start_offset + old_end_byte_len
					local change_content = ""
					local len = utils.buffer.len(buf)
					if start_offset + new_byte_len + 1 > len then
						-- i dont know why but we may go out of bounds when doing 'dd' at the end of buffer??
						local delta = (start_offset + new_byte_len + 1) - len
						if CODEMP.config.debug then print("/!\\ bytes out of bounds by " .. delta .. ", adjusting") end
						end_offset = end_offset - delta
						start_offset = start_offset - delta
					end
					if new_byte_len > 0 then
						local actual_end_col = new_end_col
						if new_end_row == 0 then actual_end_col = new_end_col + start_col end
						local actual_end_row = start_row + new_end_row
						-- -- when bulk inserting at the end we go out of bounds, so we probably need to clamp?
						-- --  issue: row=x+1 col=0 and row=x col=0 may be very far apart! we need to get last col of row x, ughh..
						-- -- also, this doesn't work so it will stay commented out for a while longer
						-- if new_end_row ~= old_end_row and new_end_col == 0 then
						-- 	-- we may be dealing with the last line of the buffer, get_text could error because out-of-bounds
						-- 	local row_count = vim.api.nvim_buf_line_count(buf)
						-- 	if actual_end_row + 1 > row_count then
						-- 		local delta = (actual_end_row + 1) - row_count
						-- 		if CODEMP.config.debug then print("/!\\ row out of bounds by " .. delta .. ", adjusting") end
						-- 		actual_end_row = actual_end_row - delta
						-- 		actual_end_col = len - vim.api.nvim_buf_get_offset(buf, row_count)
						-- 	end
						-- end
						local lines = vim.api.nvim_buf_get_text(buf, start_row, start_col, actual_end_row, actual_end_col, {})
						change_content = table.concat(lines, '\n')
					end
					if CODEMP.config.debug then
						print(string.format("sending: %s..%s '%s'", start_offset, start_offset + old_end_byte_len, change_content))
					end
					controller:send({
						start = start_offset, finish = end_offset, content = change_content
					}):await()
				end,
			})

			local lock = false
			local async = vim.loop.new_async(vim.schedule_wrap(function ()
				if lock then return end
				lock = true
				while true do
					local event = controller:try_recv():await()
					if event == nil then break end
					ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
					CODEMP.ignore_following_action = true
					if CODEMP.config.debug then
						print(" ~~ applying change ~~ " .. event.start .. ".." .. event.finish .. "::[" .. event.content .. "]")
					end
					utils.buffer.set_content(buffer, event.content, event.start, event.finish)
					if event.hash ~= nil then
						if CODEMP.native.hash(utils.buffer.get_content(buffer)) ~= event.hash then
							if CODEMP.config.auto_sync then
								print(" /!\\ out of sync, resynching...")
								utils.buffer.set_content(buffer, controller:content():await())
							else
								vim.ui.select(
									{ "sync", "detach" },
									{ prompt = "out of sync! force resync or detach?" },
									function (choice)
										if not choice then return end
										if choice == "sync" then
											utils.buffer.set_content(buffer, controller:content():await())
										end
										if choice == "detach" then
											detach(name)
										end
									end
								)
							end
							return
						end
					end
				end
				lock = false
			end))

			local remote_content = controller:content():await()
			if opts.content ~= nil then
				-- TODO this may happen too soon!!
				local _ = controller:send({
					start = 0, finish = #remote_content, content = opts.content
				}) -- no need to await
			else
				local current_content = utils.buffer.get_content(buffer)
				if current_content ~= remote_content then
					ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
					utils.buffer.set_content(buffer, remote_content)
				end
			end

			controller:callback(function (_) async:send() end)
			vim.defer_fn(function() async:send() end, 500) -- force a try_recv after 500ms

			local filetype = vim.filetype.match({ buf = buffer })
			vim.api.nvim_set_option_value("filetype", filetype, { buf = buffer })
			vim.api.nvim_set_option_value('fileformat', 'unix', { buf = buffer })
			print(" ++ attached to buffer " .. name)
			require('codemp.window').update()
		end)
	end)
end

---@param buffer? integer if provided, sync given buffer id, otherwise sync current buf
local function sync(buffer)
	if buffer == nil then
		buffer = vim.api.nvim_get_current_buf()
	end
	local name = id_buffer_map[buffer]
	if name ~= nil then
		local controller = CODEMP.workspace:get_buffer(name)
		if controller ~= nil then
			local real_content = controller:content():await()
			local my_content = utils.buffer.get_content(buffer)
			if real_content ~= my_content then
				ticks[buffer] = vim.api.nvim_buf_get_changedtick(buffer)
				utils.buffer.set_content(buffer, real_content)
				print(" !! re-synched buffer " .. name)
			else
				print(" :: buffer " .. name .. " is in sync")
			end
			return
		end
	end

	print(" !! buffer not managed")
end

local function create(buffer)
	if buffer == nil then
		buffer = vim.fn.expand("%p")
	end
	if CODEMP.workspace == nil then
		error("join a workspace first")
	end
	CODEMP.workspace:create(buffer):and_then(function ()
		print(" ++  created buffer " .. buffer)
		require('codemp.window').update()
	end)
end

return {
	sync = sync,
	attach = attach,
	detach = detach,
	create = create,
	map = id_buffer_map,
	map_rev = buffer_id_map,
	ticks = ticks,
	users = user_buffer_name,
}
