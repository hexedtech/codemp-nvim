-- this is the codemp updater for nvim
--
-- it basically detects your operating system and architecture to
-- decide which native extension to download, then it downloads
-- from https://codemp.dev/release/lua/. If this doesn't work for
-- you or you don't trust periodic binary downloads, feel free to
-- remove this file (or its content). remember to place the
-- `native.(so|dll|dylib)` file in this plugin folder, next to
-- the `loader.lua` file.


local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") -- got this from https://lazy.folke.io/developers#building

local os_uname = vim.loop.os_uname()

local arch = os_uname.machine

if arch == "arm64" then arch = "aarch64" end

local platform = string.lower(os_uname.sysname)
if platform == "darwin" then
	platform = "darwin"
elseif platform == "windows_nt" then
	platform = "windows-msvc"
else
	platform = platform .. "-gnu"
end

local ext = os_uname.sysname
if os_uname.sysname == "Windows_NT" then ext = "dll"
elseif os_uname.sysname == "Darwin" then ext = "dylib"
else ext = "so"
end

-- -- TODO compare checksum before redownloading
-- if vim.fn.filereadable(path .. 'native' .. ext) == 1 then
-- 	shasum = vim.fn.system("sha256sum " .. path .. 'native' .. ext)
-- end

local sep = '/'
if os_uname.sysname == "Windows_NT" then sep = '\\' end

local version = "v0.7.3"

local native_path = plugin_dir..sep.."lua"..sep.."codemp"..sep.."new-native."..ext
local replace_native_path = plugin_dir..sep.."lua"..sep.."codemp"..sep.."native."..ext
local download_url_native = string.format("https://codemp.dev/releases/lua/codemp-lua-%s-%s-%s.%s", version, arch, platform, ext)

print("downloading codemp native lua extension from '" .. download_url_native .. "' ...")
if os_uname.sysname == "Windows_NT" then
	local handle, pid = vim.uv.spawn("powershell.exe", {
		args = { "-Command", "Invoke-WebRequest "..download_url_native.." -OutFile "..native_path }
	})

	print("downloading in background... library will be installed upon restart")

	vim.api.nvim_create_autocmd(
		{"ExitPre"},
		{
			callback = function (_ev)
				local handle, pid = vim.uv.spawn("cmd.exe", {
					args = { "/k", "move", "/Y", native_path, replace_native_path }
				})
			end
		}
	)
else
	local res = vim.system({"curl", "-o", native_path, download_url_native }):wait() -- TODO can we run this asynchronously?
	print(res.stdout)
	print(res.stderr)
	print(">> " .. res.code)
	if res.code == 0 then
		print("downloaded! exit nvim to reload library")
	else
		print("error downloading native library: " .. res.code)
		print(res.stdout)
		print(res.stderr)
	end
	vim.api.nvim_create_autocmd(
		{"ExitPre"},
		{
			callback = function (_ev)
				vim.system({"mv", native_path, replace_native_path}, { detach = true })
			end
		}
	)
end

