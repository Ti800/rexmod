-- The active Rex theme for the current 'background', as a base16 palette.
local theme = require("rex_theme").theme(vim.o.background)
local colors = theme.source
local ansi = colors.ansi

local function blend(from, to, amount)
  local channels = {}

  for i = 2, 6, 2 do
    local a = tonumber(from:sub(i, i + 1), 16)
    local b = tonumber(to:sub(i, i + 1), 16)

    channels[#channels + 1] = string.format("%02x", math.floor(a + (b - a) * amount + 0.5))
  end

  return "#" .. table.concat(channels)
end

local bg, fg = colors.background, colors.foreground
local ink = vim.o.background == "dark" and "#ffffff" or "#000000"

-- ansi[1] is terminal color 0. Base16 has an orange that ANSI lacks: mix red and yellow.
require("mini.base16").setup({
  palette = {
    base00 = bg,
    base01 = blend(bg, fg, 0.06),
    base02 = blend(bg, fg, 0.14),
    base03 = ansi[9],
    base04 = blend(bg, fg, 0.65),
    base05 = fg,
    base06 = blend(fg, ink, 0.5),
    base07 = ink,
    base08 = ansi[2],
    base09 = blend(ansi[2], ansi[4], 0.5),
    base0A = ansi[4],
    base0B = ansi[3],
    base0C = ansi[7],
    base0D = ansi[5],
    base0E = ansi[6],
    base0F = ansi[10],
  },
})

vim.api.nvim_set_hl(0, "Visual", { fg = colors.selectionForeground, bg = colors.selectionBackground })

for i, color in ipairs(ansi) do
  vim.g["terminal_color_" .. (i - 1)] = color
end

vim.g.rex_theme_id = theme.id
vim.g.colors_name = "rex"
