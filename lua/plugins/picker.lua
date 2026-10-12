return {
  {
    "ibhagwan/fzf-lua",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    cmd = "FzfLua",
    keys = {
      { "<leader>ff", "<cmd>FzfLua files<CR>", desc = "Find files" },
      { "<leader>fg", "<cmd>FzfLua live_grep<CR>", desc = "Live grep" },
      { "<leader>fb", "<cmd>FzfLua buffers<CR>", desc = "Buffers" },
      { "<leader>fh", "<cmd>FzfLua helptags<CR>", desc = "Help tags" },
      { "<leader>fr", "<cmd>FzfLua oldfiles<CR>", desc = "Recent files" },
      { "<leader>fs", "<cmd>FzfLua lsp_document_symbols<CR>", desc = "Document symbols" },
      { "<leader>fS", "<cmd>FzfLua lsp_live_workspace_symbols<CR>", desc = "Workspace symbols" },
      { "<leader>fd", "<cmd>FzfLua diagnostics_document<CR>", desc = "Diagnostics" },
      { "<leader>f'", "<cmd>FzfLua resume<CR>", desc = "Resume last picker" },
    },
    init = function()
      -- Use fzf-lua for vim.ui.select (code actions etc.) without loading it at startup
      vim.ui.select = function(...)
        require("fzf-lua").register_ui_select()
        return vim.ui.select(...)
      end
    end,
    opts = {},
  },
  {
    -- Project-wide search and replace with ripgrep
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    keys = {
      { "<leader>fR", "<cmd>GrugFar<CR>", desc = "Search and replace" },
      {
        "<leader>fR",
        function()
          require("grug-far").with_visual_selection()
        end,
        mode = "x",
        desc = "Search and replace selection",
      },
    },
    opts = {},
  },
}
