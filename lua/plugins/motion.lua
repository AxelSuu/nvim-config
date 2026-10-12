return {
  {
    "folke/flash.nvim",
    opts = { modes = { char = { enabled = false } } },
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash jump",
      },
      {
        "S",
        mode = { "n", "o" }, -- visual S stays nvim-surround
        function()
          require("flash").treesitter()
        end,
        desc = "Flash treesitter",
      },
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote flash",
      },
      {
        "R",
        mode = { "o", "x" },
        function()
          require("flash").treesitter_search()
        end,
        desc = "Treesitter search",
      },
      {
        "<C-s>",
        mode = "c",
        function()
          require("flash").toggle()
        end,
        desc = "Toggle flash search",
      },
    },
  },
  {
    "jake-stewart/multicursor.nvim",
    branch = "1.0",
    event = "VeryLazy",
    config = function()
      local mc = require("multicursor-nvim")
      mc.setup()
      local set = vim.keymap.set

      -- Helix C / Alt-C: add cursor on the line below/above (plain arrows stay normal movement)
      set({ "n", "x" }, "<C-down>", function()
        mc.lineAddCursor(1)
      end, { desc = "Add cursor below" })
      set({ "n", "x" }, "<C-up>", function()
        mc.lineAddCursor(-1)
      end, { desc = "Add cursor above" })
      set({ "n", "x" }, "<leader><down>", function()
        mc.lineSkipCursor(1)
      end, { desc = "Skip line below" })
      set({ "n", "x" }, "<leader><up>", function()
        mc.lineSkipCursor(-1)
      end, { desc = "Skip line above" })

      -- Add or skip the next/previous match of word or selection
      set({ "n", "x" }, "<leader>n", function()
        mc.matchAddCursor(1)
      end, { desc = "Add cursor at next match" })
      set({ "n", "x" }, "<leader>N", function()
        mc.matchAddCursor(-1)
      end, { desc = "Add cursor at prev match" })
      set({ "n", "x" }, "<leader>s", function()
        mc.matchSkipCursor(1)
      end, { desc = "Skip next match" })
      set({ "n", "x" }, "<leader>S", function()
        mc.matchSkipCursor(-1)
      end, { desc = "Skip prev match" })
      set({ "n", "x" }, "<leader>*", mc.matchAllAddCursors, { desc = "Cursors at all matches" })

      -- Helix s / S inside a selection: cursors on regex matches / split on regex
      set("x", "<leader>m", mc.matchCursors, { desc = "Cursors on regex matches" })
      set("x", "<leader>M", mc.splitCursors, { desc = "Split selection on regex" })

      set({ "n", "x" }, "<c-q>", mc.toggleCursor, { desc = "Toggle cursor" })
      set("n", "<c-leftmouse>", mc.handleMouse)
      set("n", "<c-leftdrag>", mc.handleMouseDrag)
      set("n", "<c-leftrelease>", mc.handleMouseRelease)

      -- Only active while there are multiple cursors
      mc.addKeymapLayer(function(layer)
        layer({ "n", "x" }, "<left>", mc.prevCursor)
        layer({ "n", "x" }, "<right>", mc.nextCursor)
        layer({ "n", "x" }, "<leader>X", mc.deleteCursor)
        layer("n", "<esc>", function()
          if not mc.cursorsEnabled() then
            mc.enableCursors()
          else
            mc.clearCursors()
          end
        end)
      end)

      local hl = vim.api.nvim_set_hl
      hl(0, "MultiCursorCursor", { reverse = true })
      hl(0, "MultiCursorVisual", { link = "Visual" })
      hl(0, "MultiCursorSign", { link = "SignColumn" })
      hl(0, "MultiCursorMatchPreview", { link = "Search" })
      hl(0, "MultiCursorDisabledCursor", { reverse = true })
      hl(0, "MultiCursorDisabledVisual", { link = "Visual" })
      hl(0, "MultiCursorDisabledSign", { link = "SignColumn" })
    end,
  },
}
