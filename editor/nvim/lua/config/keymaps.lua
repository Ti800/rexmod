-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Ctrl+h/j/k/l move between windows. At the edge of Neovim they move to the
-- next Rex pane, as vim-tmux-navigator does in tmux (see ~/.config/rex/init.lua).
local function navigate(key, direction)
  local window = vim.api.nvim_get_current_win()

  vim.cmd.wincmd(key)

  if vim.api.nvim_get_current_win() == window and vim.env.REX_SESSION then
    vim.system({ "rex", "focus", "-s", vim.env.REX_SESSION, direction })
  end
end

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  vim.keymap.set("n", "<C-" .. key .. ">", function()
    navigate(key, direction)
  end, { desc = "Go to " .. direction .. " window or Rex pane" })
end
