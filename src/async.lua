local state = require('codemp.state')

local function register_controller_handler(target, controller, handler, delay)
	local async = vim.loop.new_async(function()
		while true do
			local success, event = pcall(controller.try_recv, controller)
			if success then
				if event == nil then break end
				vim.schedule(function()
					local ok, res = pcall(handler, event)
					if not ok then
						print(" !! error running callback handler: " .. res)
					end
				end)
			else
				print("error receiving: " .. tostring(event))
				break
			end
		end
	end)
	-- TODO controller can't be passed to the uvloop new_thread: when sent to the new 
	--  Lua runtime it "loses" its methods defined with mlua, making the userdata object 
	--  completely useless. We can circumvent this by requiring codemp again in the new 
	--  thread and requesting a new reference to the same controller from che global instance
	-- NOTE variables prefixed with underscore live in another Lua runtime
	vim.loop.new_thread({}, function(_async, _target, _delay, _ws, _id)
		local _codemp = require("codemp.loader").load() -- TODO maybe make a native.load() idk
		local _client = _codemp.get_client(_id)
		if _client == nil then error("cant find client " .. _id .. " from thread") end
		local _workspace = _client:get_workspace(_ws)
		if _workspace == nil then error("cant find workspace " .. _ws .. " from thread") end
		local _controller = _target ~= nil and _workspace:get_buffer(_target) or _workspace.cursor
		if _controller == nil then error("cant find controller " .. _target .. " from thread") end
		if _controller.poll == nil then error("controller has nil poll field???") end
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
	end, async, target, delay, state.workspace, state.client.id)
end

return {
	handler = register_controller_handler,
}
