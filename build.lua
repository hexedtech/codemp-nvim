local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") -- got this from https://lazy.folke.io/developers#building

-- -- TODO not the best loader but a simple example? urls dont work
-- local host_os = vim.loop.os_uname().sysname
-- local ext = nil
-- if host_os == "Windows" then ext = ".dll"
-- elseif host_os == "Mac" then ext = ".dylib"
-- else ext = ".so"
-- end
-- 
-- local shasum = nil
-- 
-- if vim.fn.filereadable(path .. 'native' .. ext) == 1 then
-- 	shasum = vim.fn.system("sha256sum " .. path .. 'native' .. ext)
-- end
-- 
-- local last_sum = vim.fn.system("curl -s https://codemp.alemi.dev/lib/lua/latest/sum")
-- 
-- if last_sum ~= shasum then
-- 	vim.fn.system("curl -o " .. path .. 'native' .. ext .. "https://codemp.alemi.dev/lib/lua/latest")
-- end
local native_path = plugin_dir .. "/lua/codemp/native.so" -- TODO get extension based on platform
local download_url = "https://codemp.dev/releases/lua/codemp_native-linux.so" -- TODO get url based on platform

vim.system({"curl", "-s", "-o", native_path, download_url }):wait() -- TODO can we run this asynchronously?
