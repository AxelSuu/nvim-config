return {
  {
    -- Fork with ESP-IDF / cross GCC support; ~/github/AssemblyForNeovim is used instead when present
    "AxelSuu/AssemblyForNeovim",
    branch = "esp-support",
    dev = true,
    cmd = "Asm",
    keys = {
      { "<leader>A", mode = "n", desc = "Assembly for function" },
      { "<leader>A", ":Asm<CR>", mode = "x", silent = true, desc = "Assembly for selection" },
    },
    config = function()
      require("asm").setup()
      -- setup() hardcodes <leader>a, which is the Claude prefix; move it to <leader>A
      local fn_map = vim.fn.maparg("<leader>a", "n", false, true)
      vim.keymap.del("n", "<leader>a")
      vim.keymap.del("x", "<leader>a")
      vim.keymap.set("n", "<leader>A", fn_map.callback, { desc = "Assembly for function" })
    end,
  },
}
