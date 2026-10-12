return {
  {
    "lewis6991/gitsigns.nvim",
    config = function()
      require("gitsigns").setup({
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns
          local map = function(mode, l, r, desc)
            vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
          end
          map("n", "]h", function()
            gs.nav_hunk("next")
          end, "Next hunk")
          map("n", "[h", function()
            gs.nav_hunk("prev")
          end, "Prev hunk")
          map("n", "<leader>hs", gs.stage_hunk, "Stage hunk")
          map("n", "<leader>hr", gs.reset_hunk, "Reset hunk")
          map("n", "<leader>hS", gs.stage_buffer, "Stage buffer")
          map("n", "<leader>hu", gs.stage_hunk, "Unstage hunk (toggle)")
          map("n", "<leader>hR", gs.reset_buffer, "Reset buffer")
          map("n", "<leader>hp", gs.preview_hunk, "Preview hunk")
          map("n", "<leader>hb", function()
            gs.blame_line({ full = true })
          end, "Blame line")
          map("n", "<leader>hd", gs.diffthis, "Diff this")
          map("v", "<leader>hs", function()
            gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
          end, "Stage hunk")
          map("v", "<leader>hr", function()
            gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
          end, "Reset hunk")
        end,
      })
    end,
  },
  {
    "esmuellert/codediff.nvim",
    cmd = "CodeDiff",
    keys = {
      { "<leader>gd", "<cmd>CodeDiff<CR>", desc = "Diff working tree" },
      { "<leader>gs", "<cmd>CodeDiff --staged<CR>", desc = "Diff staged" },
      { "<leader>gl", "<cmd>CodeDiff history<CR>", desc = "Commit history" },
      { "<leader>gf", "<cmd>CodeDiff history %<CR>", desc = "File history" },
    },
    opts = {},
  },
}
