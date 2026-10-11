local mason_tools = { "clang-format", "stylua", "prettierd" }

return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    config = function()
      require("conform").setup({
        format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
        formatters_by_ft = {
          python = { "ruff_organize_imports", "ruff_format" },
          c = { "clang_format" },
          cpp = { "clang_format" },
          rust = { "rustfmt" },
          lua = { "stylua" },
          javascript = { "prettierd" },
          javascriptreact = { "prettierd" },
          typescript = { "prettierd" },
          typescriptreact = { "prettierd" },
          json = { "prettierd" },
          css = { "prettierd" },
        },
      })

      local registry = require("mason-registry")
      registry.refresh(function()
        for _, name in ipairs(mason_tools) do
          local pkg = registry.get_package(name)
          if not pkg:is_installed() then pkg:install() end
        end
      end)
    end,
  },
}
