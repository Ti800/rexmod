-- Review comments for your coding agent and the editor side of the Rex Changes panel.
-- Installed by rexmod into ~/Library/Application Support/rexmod/nvim.
return {
  {
    dir = vim.fn.expand("~/Library/Application Support/rexmod/nvim"),
    name = "rexmod.nvim",
    lazy = false,
    config = function()
      require("rexmod").setup()
    end,
  },
}
