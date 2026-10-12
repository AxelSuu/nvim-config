return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    lazy = false,
    config = function()
      require("nvim-treesitter").install({
        "c",
        "cpp",
        "rust",
        "python",
        "typescript",
        "tsx",
        "javascript",
        "lua",
        "luadoc",
        "bash",
        "json",
        "yaml",
        "toml",
        "markdown",
        "markdown_inline",
        "cmake",
        "make",
        "kconfig",
        "linkerscript",
        "devicetree",
        "asm",
        "diff",
        "gitcommit",
        "git_rebase",
        "html",
        "css",
        "regex",
        "vim",
        "vimdoc",
        "query",
      })

      -- Start highlighting for any filetype that has a parser
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)
        end,
      })
    end,
  },
  {
    "nvim-treesitter/nvim-treesitter-textobjects",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    event = "VeryLazy",
    config = function()
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
        move = { set_jumps = true },
      })

      local select = require("nvim-treesitter-textobjects.select")
      local move = require("nvim-treesitter-textobjects.move")

      -- select (Helix mi/ma): f function, c class, a argument
      for key, obj in pairs({ f = "function", c = "class", a = "parameter" }) do
        vim.keymap.set({ "x", "o" }, "a" .. key, function()
          select.select_textobject("@" .. obj .. ".outer", "textobjects")
        end)
        vim.keymap.set({ "x", "o" }, "i" .. key, function()
          select.select_textobject("@" .. obj .. ".inner", "textobjects")
        end)
      end

      -- move (Helix ]f ]t); ]c [c stay free for diff hunks
      for key, obj in pairs({ f = "@function.outer", t = "@class.outer" }) do
        vim.keymap.set({ "n", "x", "o" }, "]" .. key, function()
          move.goto_next_start(obj, "textobjects")
        end)
        vim.keymap.set({ "n", "x", "o" }, "[" .. key, function()
          move.goto_prev_start(obj, "textobjects")
        end)
      end
    end,
  },
  {
    -- Sticky function/struct header when scrolled inside long blocks
    "nvim-treesitter/nvim-treesitter-context",
    event = { "BufReadPost", "BufNewFile" },
    opts = { max_lines = 3 },
  },
}
