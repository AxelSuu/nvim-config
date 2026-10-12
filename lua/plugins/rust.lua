return {
  {
    -- Crate versions, features and docs in Cargo.toml (completion/hover/actions via an in-process LSP)
    "saecki/crates.nvim",
    tag = "stable",
    event = "BufRead Cargo.toml",
    opts = {
      lsp = { enabled = true, actions = true, completion = true, hover = true },
    },
  },
}
