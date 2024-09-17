[![codemp](https://code.mp/static/banner.png)](https://code.mp)
[![GitHub last commit](https://img.shields.io/github/last-commit/hexedtech/codemp-nvim)](https://github.com/hexedtech/codemp-nvim)
[![LuaRocks](https://img.shields.io/luarocks/v/alemi/codemp)](https://luarocks.org/modules/alemi/codemp)
[![Gitter](https://img.shields.io/gitter/room/hexedtech/codemp)](https://gitter.im/hexedtech/codemp)

> `codemp` is a **collaborative** text editing solution to work remotely.

It seamlessly integrates in your editor providing remote cursors and instant text synchronization,
as well as a remote virtual workspace for you and your team.

# codemp-nvim

This is the reference codemp [neovim](https://neovim.io) plugin maintained by [hexedtech](https://hexed.technology)

# installation
Just add `hexedtech/codemp-nvim` to your plugin spec.

If you're using [`lazy.nvim`](https://github.com/folke/lazy.nvim), everything will be configured automatically!

If you're using something else to load `codemp-nvim`, you need to also do the following:
 * run `build.lua` during installation and every update
 * invoke `require('codemp-nvim').setup({ ... })` after loading, pass your config

Note that the native codemp lua library will be downloaded automatically on each update.

## neo-tree integration
`codemp-nvim` integrates with [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim) to provide a rich and intuitive file tree.

To enable this integration, add `neo_tree = true` in plugin `opts` and add `codemp` as a neo-tree source:

```lua
{
	"hexedtech/codemp-nvim",
	opts = { neo_tree = true },
},
{
	"nvim-neo-tree/neo-tree.nvim",
	dependencies = { "hexedtech/codemp-nvim" },
	config = function ()
		require('neo-tree').setup({
			sources = {
				-- your other sources
				"codemp.neo-tree",
			},
		})
	end,
}
```

# usage
Interact with this plugin using the `:MP` command.

Most actions can be performed from the side tree: toggle it with `:MP toggle`.

| command | description |
| --- | --- |
| `:MP toggle` |  toggles the codemp sidebar |
| `:MP connect [host] [username] [password]` |  to connect to server, user and pwd will be prompted if not given |

once connected, more commands become available:

| command | description |
| --- | --- |
| `:MP disconnect` |  disconnects from server |
| `:MP id` |  shows current client id |
| `:MP start <workspace>` |  will create a new workspace with given name |
| `:MP invite <user> [workspace]` |  invite given user to workspace  |
| `:MP available` |  list all workspaces available to join  |
| `:MP join <workspace>` |  will join requested workspace; starts processing cursors, users and filetree |

after a workspace is joined, more commands become available:

| command | description |
| --- | --- |
| `:MP leave <workspace>` |  disconnect from a joined workspace |
| `:MP attach <buffer>` |  will attach to requested buffer if it exists (opens a new local buffer and uses current window) |
| `:MP detach <buffer>` |  detach from a buffer and stop receiving changes |
| `:MP share` |  shares current file: creates a new buffer with local file's content, and attach to it |
| `:MP sync` |  forces resynchronization of current buffer |
| `:MP create <bufname>` |  will create a new empty buffer in workspace |
| `:MP delete <bufname>` |  will delete a buffer from workspace |

### quick start
 * first connect to server with `:MP connect`
 * then join a workspace with `:MP join <workspace>`
 * either attach directly to a buffer with `:MP attach <buffer>` or browse available buffers with `:MP toggle`

MP command autocompletes available options for current state, so cycle <Tab> if you forget any name

## configuration
`codemp-nvim` gets most of its configuration from `setup()` options. If you're using `lazy.nvim`, just place these in the `opts` table in your spec, otherwise be sure to `require('codemp').setup({...})`.

```lua
opts = {
	neo_tree = false, -- enable neo-tree integration
	timer_interval = 100, -- poll for codemp callbacks every __ ms
	debug = false, -- print text operations as they happen
}
```

`codemp-nvim` reads some global vim variables for configuration:
 * `vim.g.codemp_username` will be used when connecting instead of prompting for username
 * `vim.g.codemp_password` will be used when connecting instead of prompting for password

## building
this plugin relies on the native codemp lua bindings: just compile the main `codemp` project with `lua` feature enabled, rename the
output library into `native.so` (or `.dll` or `.dylib`) and place it together with the plugin lua files while bundling

```
.config/
  |-nvim/
  :  |-lua/
  :  :  |-codemp/
  :  :  :  |- native.(so|dll|dylib)
  :  :  :  |- init.lua
  :  :  :  :   ...
```
