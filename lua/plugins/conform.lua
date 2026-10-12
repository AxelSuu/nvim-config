local mason_tools = { "clang-format", "stylua", "prettierd" }

local autoformat = require("autoformat")

return {
  {
    "stevearc/conform.nvim",
    event = "BufWritePre",
    cmd = "ConformInfo",
    keys = {
      { "<leader>cf", autoformat.toggle("global"), desc = "Toggle format on save" },
      { "<leader>cF", autoformat.toggle("buffer"), desc = "Toggle format on save (buffer)" },
    },
    config = function()
      require("conform").setup({
        format_on_save = function(bufnr)
          if autoformat.enabled(bufnr) then
            return { timeout_ms = 500, lsp_format = "fallback" }
          end
        end,
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
          if not pkg:is_installed() then
            pkg:install()
          end
        end
      end)
    end,
  },
}
