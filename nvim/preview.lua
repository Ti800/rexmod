-- Renders a file as ANSI text with the same highlighting the editor uses:
-- Neovim's treesitter parsers and queries plus the "rex" colorscheme.
-- Usage: nvim --headless -u NONE -i NONE -l preview.lua FILE [FOCUS_LINE] [MAX_LINES]
local file, focus, max = arg[1], tonumber(arg[2] or "0") or 0, tonumber(arg[3] or "400") or 400
local config = vim.fn.stdpath("config")
local data = vim.fn.stdpath("data")

for _, dir in ipairs({
  config,
  data .. "/lazy/mini.base16",
  data .. "/site",
  data .. "/lazy/nvim-treesitter/runtime",
  data .. "/lazy/nvim-treesitter",
}) do
  if vim.uv.fs_stat(dir) then
    vim.opt.rtp:append(dir)
  end
end
vim.o.background = vim.env.REXMOD_BACKGROUND or "dark"
vim.o.termguicolors = true
pcall(vim.cmd.colorscheme, "rex")

local out = {}
local function emit(s)
  out[#out + 1] = s
end

local fd = io.open(file, "rb")
if not fd then
  io.stdout:write("(cannot read file)\n")
  return
end
local head = fd:read(8192) or ""
fd:close()
if head:find("\0", 1, true) then
  io.stdout:write("(binary file)\n")
  return
end

local lines = vim.fn.readfile(file, "", max)
local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

-- hl[row][col] = highlight group name for that byte (later captures win).
local hl = {}
local ft = vim.filetype.match({ filename = file, buf = buf })
local lang = ft and vim.treesitter.language.get_lang(ft) or nil
local ok, parser = pcall(vim.treesitter.get_parser, buf, lang)
if ok and parser then
  parser:parse(true)
  parser:for_each_tree(function(tree, ltree)
    local l = ltree:lang()
    local query = vim.treesitter.query.get(l, "highlights")
    if not query then
      return
    end
    for id, node in query:iter_captures(tree:root(), buf, 0, #lines) do
      local name = query.captures[id]
      if name and not name:find("^_") and name ~= "spell" and name ~= "nospell" then
        local sr, sc, er, ec = node:range()
        for r = sr, math.min(er, #lines - 1) do
          local line = lines[r + 1] or ""
          local from = (r == sr) and sc or 0
          local to = (r == er) and ec or #line
          hl[r] = hl[r] or {}
          for c = from, to - 1 do
            hl[r][c] = "@" .. name .. "." .. l
          end
        end
      end
    end
  end)
end

-- No treesitter parser for this language: fall back to Vim syntax, as the
-- editor does.
if next(hl) == nil and ft and ft ~= "" then
  vim.api.nvim_set_current_buf(buf)
  vim.cmd("syntax enable")
  vim.bo[buf].filetype = ft
  for r, line in ipairs(lines) do
    local row = {}
    local last_id, last_name = nil, nil
    for c = 1, math.min(#line, 400) do
      local id = vim.fn.synIDtrans(vim.fn.synID(r, c, 1))
      if id ~= last_id then
        last_id = id
        last_name = id ~= 0 and vim.fn.synIDattr(id, "name") or nil
      end
      row[c - 1] = last_name
    end
    hl[r - 1] = row
  end
end

local cache = {}
local function sgr(group)
  if not group then
    return ""
  end
  if cache[group] then
    return cache[group]
  end
  local name, attrs = group, {}
  while name do
    attrs = vim.api.nvim_get_hl(0, { name = name, link = false })
    if attrs.fg or attrs.bold or attrs.italic then
      break
    end
    name = name:match("^(.*)%.[^.]+$") -- @keyword.function.go -> @keyword.function -> @keyword
  end
  local s = ""
  if attrs.fg then
    s = s .. string.format("\27[38;2;%d;%d;%dm", bit.rshift(attrs.fg, 16), bit.band(bit.rshift(attrs.fg, 8), 255), bit.band(attrs.fg, 255))
  end
  if attrs.bold then
    s = s .. "\27[1m"
  end
  if attrs.italic then
    s = s .. "\27[3m"
  end
  cache[group] = s
  return s
end

local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
local reset = "\27[0m"
local gutter = vim.api.nvim_get_hl(0, { name = "LineNr", link = false })
local function rgb(c)
  return c and string.format("\27[38;2;%d;%d;%dm", bit.rshift(c, 16), bit.band(bit.rshift(c, 8), 255), bit.band(c, 255)) or ""
end
local base = rgb(normal.fg)

for r, line in ipairs(lines) do
  local row = r - 1
  local num = string.format("%5d  ", r)
  emit((r == focus and "\27[38;2;187;0;255m" or rgb(gutter.fg)) .. num .. reset)
  local cur, seg = nil, {}
  local rowhl = hl[row] or {}
  for c = 0, #line - 1 do
    local g = rowhl[c]
    if g ~= cur then
      seg[#seg + 1] = reset .. base .. sgr(g)
      cur = g
    end
    seg[#seg + 1] = line:sub(c + 1, c + 1)
  end
  emit(base .. table.concat(seg):gsub("\t", "    ") .. reset .. "\n")
end
io.stdout:write(table.concat(out))
