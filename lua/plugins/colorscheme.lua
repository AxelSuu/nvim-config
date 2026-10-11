return {
  {
    "sonph/onehalf",
    lazy = false,
    priority = 1000,
    init = function(plugin)
      vim.opt.rtp:append(plugin.dir .. "/vim")
    end,
    config = function()
      vim.o.background = "light"
      vim.cmd("colorscheme onehalflight")
      vim.cmd("highlight Normal guibg=NONE ctermbg=NONE")
      vim.cmd("highlight NormalNC guibg=NONE ctermbg=NONE")
    end,
  },
}
