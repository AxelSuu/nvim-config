return {
  {
    "olimorris/onedarkpro.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("onedarkpro").setup({ options = { transparency = true } })
      vim.o.background = "light"
      vim.cmd("colorscheme onelight")
      vim.api.nvim_set_hl(0, "NormalNC", { bg = "NONE" })
    end,
  },
}
