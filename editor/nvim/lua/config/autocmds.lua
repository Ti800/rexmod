-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- A theme change in the Rex settings shows when focus comes back to nvim.
vim.api.nvim_create_autocmd("FocusGained", {
  group = vim.api.nvim_create_augroup("rex_theme", { clear = true }),
  callback = function()
    if vim.g.colors_name == "rex" and require("rex_theme").theme(vim.o.background).id ~= vim.g.rex_theme_id then
      vim.cmd.colorscheme("rex")
    end
  end,
})
