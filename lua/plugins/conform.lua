return {
  {
    "stevearc/conform.nvim",
    config = function()
      require("conform").setup({
        format_on_save = { timeout_ms = 500, lsp_fallback = true },
        formatters_by_ft = {
          python = { "black" },
          c = { "clang_format" },
          lua = { "stylua" },
        },
      })
    end,
  }
}
