local map = vim.keymap.set

-- Move between windows
map("n", "<C-h>", "<C-w>h")
map("n", "<C-l>", "<C-w>l")
map("n", "<C-j>", "<C-w>j")
map("n", "<C-k>", "<C-w>k")

-- Better indenting (stay in visual mode)
map("v", "<", "<gv")
map("v", ">", ">gv")

-- Move lines up/down in visual mode
map("v", "J", ":m '>+1<CR>gv=gv")
map("v", "K", ":m '<-2<CR>gv=gv")

-- Diagnostics ([d ]d are built in; LSP maps are set on LspAttach, see plugins/lsp.lua)
map("n", "<leader>d", vim.diagnostic.open_float)
vim.diagnostic.config({ virtual_text = { current_line = true }, severity_sort = true })

-- Inlay hints (types, parameter names)
map("n", "<leader>ih", function()
  vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled())
end, { desc = "Toggle inlay hints" })

-- Undo tree (built in)
map("n", "<leader>u", "<cmd>Undotree<CR>")

-- Quick save / quit
map("n", "<leader>w", "<cmd>w<CR>")
map("n", "<leader>q", "<cmd>q<CR>")

-- Clear search highlight
map("n", "<Esc>", "<cmd>nohlsearch<CR>")
