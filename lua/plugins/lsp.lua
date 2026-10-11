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
          map("gr", vim.lsp.buf.references, "References")
          map("K", vim.lsp.buf.hover, "Hover")
          map("<leader>ca", vim.lsp.buf.code_action, "Code action")
          map("<leader>rn", vim.lsp.buf.rename, "Rename")
        end,
      })
    end,
  },
  {
    "hrsh7th/nvim-cmp",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "L3MON4D3/LuaSnip",
      "saadparwaiz1/cmp_luasnip",
      "rafamadriz/friendly-snippets",
    },
    config = function()
      local cmp = require("cmp")
      local luasnip = require("luasnip")
      require("luasnip.loaders.from_vscode").lazy_load()
      cmp.setup({
        snippet = {
          expand = function(args)
            luasnip.lsp_expand(args.body)
          end,
        },
        mapping = cmp.mapping.preset.insert({
          ["<C-Space>"] = cmp.mapping.complete(),
          ["<CR>"] = cmp.mapping.confirm({ select = true }),
          ["<Tab>"] = cmp.mapping(function(fallback)
            if cmp.visible() then
              cmp.select_next_item()
            elseif luasnip.expand_or_jumpable() then
              luasnip.expand_or_jump()
            else
              fallback()
            end
          end, { "i", "s" }),
        }),
        sources = cmp.config.sources({
          { name = "nvim_lsp" },
          { name = "luasnip" },
          { name = "buffer" },
          { name = "path" },
        }),
      })
    end,
  },
}
