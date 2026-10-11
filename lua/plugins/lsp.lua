return {
  {
    "folke/lazydev.nvim",
    ft = "lua",
    opts = {
      library = {
        { path = "${3rd}/luv/library", words = { "vim%.uv" } },
      },
    },
  },
  {
    "mason-org/mason.nvim",
    cmd = { "Mason", "MasonInstall", "MasonUpdate", "MasonUninstall", "MasonLog" },
    opts = {},
  },
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = { "mason-org/mason.nvim", "mason-org/mason-lspconfig.nvim" },
    config = function()
      require("mason-lspconfig").setup({
        ensure_installed = { "lua_ls", "pyright", "clangd", "bashls", "vtsls" },
        automatic_enable = false,
      })

      -- ESP-IDF projects (sdkconfig in root) use Espressif's clangd, which knows Xtensa/RISC-V targets
      local esp_tools = vim.fn.expand("~/.espressif/tools")
      local function clangd_bin(root)
        if root and vim.uv.fs_stat(root .. "/sdkconfig") then
          local found = vim.fn.glob(esp_tools .. "/esp-clang/*/esp-clang/bin/clangd", false, true)
          if #found > 0 then
            return found[#found]
          end
        end
        return "clangd"
      end

      vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })
      vim.lsp.config("clangd", {
        cmd = function(dispatchers, config)
          return vim.lsp.rpc.start({
            clangd_bin(config.root_dir),
            "--background-index",
            "--clang-tidy",
            "--header-insertion=never",
            "--query-driver=" .. esp_tools .. "/**/bin/*-elf-g*,/usr/bin/*gcc*,/usr/bin/*g++*",
          }, dispatchers, { cwd = config.root_dir })
        end,
        filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
      })
      vim.lsp.config("rust_analyzer", {
        settings = { ["rust-analyzer"] = { check = { command = "clippy" } } },
      })

      -- rust-analyzer comes from rustup and ruff from uv, not mason
      vim.lsp.enable({ "lua_ls", "clangd", "pyright", "ruff", "rust_analyzer", "vtsls", "bashls" })

      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local client = vim.lsp.get_client_by_id(ev.data.client_id)
          if client and client.name == "ruff" then
            client.server_capabilities.hoverProvider = false
          end
          local map = function(lhs, rhs, desc)
            vim.keymap.set("n", lhs, rhs, { buffer = ev.buf, desc = desc })
          end
          map("gd", vim.lsp.buf.definition, "Goto definition")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
        end,
      })
    end,
  },
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = { "rafamadriz/friendly-snippets" },
    opts = {
      -- Same keys as the old nvim-cmp setup
      keymap = {
        preset = "none",
        ["<C-Space>"] = { "show", "show_documentation", "hide_documentation" },
        ["<CR>"] = { "accept", "fallback" },
        ["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
        ["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
        ["<C-n>"] = { "select_next", "fallback" },
        ["<C-p>"] = { "select_prev", "fallback" },
        ["<C-y>"] = { "select_and_accept" },
        ["<C-e>"] = { "hide", "fallback" },
        ["<C-b>"] = { "scroll_documentation_up", "fallback" },
        ["<C-f>"] = { "scroll_documentation_down", "fallback" },
      },
      completion = {
        list = { selection = { preselect = false } },
        documentation = { auto_show = true, auto_show_delay_ms = 300 },
      },
      signature = { enabled = true },
      sources = {
        default = { "lazydev", "lsp", "path", "snippets", "buffer" },
        providers = {
          lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
        },
      },
    },
  },
}
