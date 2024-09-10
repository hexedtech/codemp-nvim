local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") -- got this from https://lazy.folke.io/developers#building

local os_uname = vim.loop.os_uname()

local arch = os_uname.machine

local platform = string.lower(os_uname.sysname)
if platform == "mac" then platform = "darwin" end

local ext = os_uname.sysname
if os_uname.sysname == "Windows" then ext = ".dll"
elseif os_uname.sysname == "Mac" then ext = ".dylib"
else ext = ".so"
end

-- -- TODO compare checksum before redownloading
-- if vim.fn.filereadable(path .. 'native' .. ext) == 1 then
-- 	shasum = vim.fn.system("sha256sum " .. path .. 'native' .. ext)
-- end

local native_path = plugin_dir .. "/lua/codemp/new-native." .. ext
local replace_native_path = plugin_dir .. "/lua/codemp/native." .. ext
local download_url_native = string.format("https://code.mp/releases/lua/codemp-lua-%s-%s.%s", arch, platform, ext)
print("downloading codemp native lua extension...")
vim.system({"curl", "-s", "-o", native_path, download_url_native }):wait() -- TODO can we run this asynchronously?
print("downloaded! exit nvim to reload library")

vim.api.nvim_create_autocmd(
	{"ExitPre"},
	{
		callback = function (_ev)
			vim.system({"sleep", "1", ";", "mv", native_path, replace_native_path}, { detach = true })
		end
	}
)
