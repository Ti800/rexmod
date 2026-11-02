-- rexmod.nvim: review comments for your coding agent, and the editor side of the Rex
-- Changes panel. Files clicked in the panel open here through `M.open`.
local M = {}

M.config = {
  bin = vim.fn.exepath("rexmod") ~= "" and vim.fn.exepath("rexmod") or (vim.env.HOME .. "/.local/bin/rexmod"),
  -- Open a file in any language and its parser and language server are
  -- installed (Mason) and started. false turns it off.
  auto_install = true,
  keys = {
    add = "<leader>r", -- comment on the line (normal) or the selection (visual)
    list = "<leader>R", -- all comments of the repo; <c-x> deletes, <c-s> sends to the agent
    next = "]r",
    prev = "[r",
  },
}

local ns = vim.api.nvim_create_namespace("rexmod_comments")
-- buf -> list of { id, s, e, text, pending } (0-based lines)
local marks = {}

local function run(args, cb)
  local cmd = { M.config.bin }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = true }, function(res)
    if cb then
      vim.schedule(function()
        cb(res)
      end)
    end
  end)
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Review" })
end

local function is_file_buf(buf)
  return vim.api.nvim_buf_is_valid(buf)
    and vim.bo[buf].buftype == ""
    and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function setup_highlights()
  local function link(name, target)
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
  vim.api.nvim_set_hl(0, "RexModPending", { fg = "#bb00ff", default = true })
  vim.api.nvim_set_hl(0, "RexModPendingText", { fg = "#d6a6ff", italic = true, default = true })
  link("RexModSent", "Comment")
  link("RexModSentText", "Comment")
  link("RexModBoxBorder", "FloatBorder")
  link("RexModBoxTitle", "FloatTitle")
  link("RexModBoxHint", "Comment")
end

-- buf -> comments of the file as rexmod returns them
local cache = {}
-- buf -> id of the note under the cursor (Hunk's "focused note")
local focused = {}

local function ago(stamp)
  if type(stamp) ~= "string" then
    return ""
  end
  local y, mo, d, h, mi, sec = stamp:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return ""
  end
  local t = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = sec })
  -- rexmod writes local time with an offset; os.time reads it as local time.
  local diff = math.max(0, os.time() - t)
  if diff < 60 then
    return "now"
  elseif diff < 3600 then
    return math.floor(diff / 60) .. "m"
  elseif diff < 86400 then
    return math.floor(diff / 3600) .. "h"
  end
  return math.floor(diff / 86400) .. "d"
end

local function where(c)
  local e = c.end_line or c.line
  return e > c.line and ("L" .. c.line .. "-" .. e) or ("L" .. c.line)
end

--- A saved note as Hunk draws it: a rounded box under the lines, with a dot
--- and "E edit  D delete" while the cursor is on it.
local function note_box(buf, c, pending, is_focused)
  local win = vim.fn.bufwinid(buf)
  local info = win ~= -1 and vim.fn.getwininfo(win)[1] or { width = 80, textoff = 0 }
  local inner = math.max(20, info.width - info.textoff - 4)
  local border = pending and "RexModBoxBorder" or "RexModSent"
  local text_hl = pending and "Normal" or "RexModSentText"
  local title = (is_focused and "● " or "") .. (pending and "Your note" or "Sent to the agent")
    .. " · " .. ago(c.created_at) .. " · " .. c.file .. " " .. where(c)
  local top_fill = math.max(0, inner - vim.fn.strdisplaywidth(title) - 1)
  local out = { { { "╭─ ", border }, { title, pending and "RexModBoxTitle" or border }, { " " .. string.rep("─", top_fill) .. "╮", border } } }
  out[#out + 1] = { { "│ " .. string.rep(" ", inner) .. " │", border } }
  for _, part in ipairs(vim.split(c.text, "\n", { plain = true })) do
    while vim.fn.strdisplaywidth(part) > inner do
      local cut = vim.fn.strcharpart(part, 0, inner)
      out[#out + 1] = { { "│ ", border }, { cut, text_hl }, { " │", border } }
      part = vim.fn.strcharpart(part, inner)
    end
    local pad = string.rep(" ", math.max(0, inner - vim.fn.strdisplaywidth(part)))
    out[#out + 1] = { { "│ ", border }, { part .. pad, text_hl }, { " │", border } }
  end
  if is_focused then
    local hint = " E edit  D delete "
    out[#out + 1] = { { "╰" .. string.rep("─", inner + 2 - vim.fn.strdisplaywidth(hint)), border }, { hint, "RexModBoxHint" }, { "╯", border } }
  else
    out[#out + 1] = { { "╰" .. string.rep("─", inner + 2) .. "╯", border } }
  end
  return out
end

local function is_pending(c)
  return c.sent_at == nil or c.sent_at == vim.NIL or c.sent_at == ""
end

--- Draw the cached comments of a buffer as signs and boxes.
local function render(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  marks[buf] = {}
  local count = vim.api.nvim_buf_line_count(buf)
  for _, c in ipairs(cache[buf] or {}) do
    local pending = is_pending(c)
    local s = math.max(0, math.min(c.line, count) - 1)
    local e = math.max(s, math.min(c.end_line or c.line, count) - 1)
    local sign_hl = pending and "RexModPending" or "RexModSent"
    for l = s, e do
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, l, 0, {
        sign_text = l == s and "󰆉" or "┃",
        sign_hl_group = sign_hl,
        priority = 30,
      })
    end
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, e, 0, { virt_lines = note_box(buf, c, pending, focused[buf] == c.id) })
    table.insert(marks[buf], { id = c.id, s = s, e = e, text = c.text, pending = pending, comment = c })
  end
end

local function comment_at_cursor(buf)
  local l = vim.fn.line(".") - 1
  for _, m in ipairs(marks[buf] or {}) do
    if l >= m.s and l <= m.e then
      return m
    end
  end
end

--- Hunk's focus: the note under the cursor shows its keys, and E / D act on
--- it. Elsewhere E and D keep their Vim meaning.
local function update_focus(buf)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local m = comment_at_cursor(buf)
  local id = m and m.id or nil
  if focused[buf] == id then
    return
  end
  focused[buf] = id
  if id then
    vim.keymap.set("n", "E", function() M.edit_at_cursor() end, { buffer = buf, nowait = true, desc = "Review: edit note" })
    vim.keymap.set("n", "D", function() M.delete_at_cursor() end, { buffer = buf, nowait = true, desc = "Review: delete note" })
  else
    pcall(vim.keymap.del, "n", "E", { buffer = buf })
    pcall(vim.keymap.del, "n", "D", { buffer = buf })
  end
  render(buf)
end

--- Watch a repo's comment store so notes changed outside Neovim (the agent
--- resolving one, the hook marking them sent) redraw right away.
local watchers, watched_dirs, refresh_timer = {}, {}, nil
local refresh_all
local function watch_store(file)
  local dir = vim.fs.dirname(file)
  if watched_dirs[dir] ~= nil then
    return
  end
  watched_dirs[dir] = false
  local out = vim.fn.systemlist({ "git", "-C", dir, "rev-parse", "--absolute-git-dir" })
  if vim.v.shell_error ~= 0 or not out[1] then
    return
  end
  local store = out[1] .. "/rexmod"
  vim.fn.mkdir(store, "p")
  if watchers[store] then
    return
  end
  local w = vim.uv.new_fs_event()
  if not w then
    return
  end
  watchers[store] = w
  w:start(store, {}, function(_, name)
    if name and not name:match("^comments") then
      return
    end
    if refresh_timer then
      refresh_timer:stop()
    end
    refresh_timer = vim.defer_fn(function()
      refresh_timer = nil
      refresh_all()
    end, 100)
  end)
end

--- Fetch the comments of a buffer and draw them.
function M.refresh(buf)
  buf = (buf and buf ~= 0) and buf or vim.api.nvim_get_current_buf()
  if not is_file_buf(buf) then
    return
  end
  local file = vim.api.nvim_buf_get_name(buf)
  watch_store(file)
  run({ "comments", "list", "--file", file, "--json" }, function(res)
    if not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local ok, data = pcall(vim.json.decode, res.stdout or "")
    cache[buf] = (res.code == 0 and ok and type(data) == "table" and data.comments) or {}
    focused[buf] = nil
    render(buf)
    if vim.api.nvim_get_current_buf() == buf then
      focused[buf] = false -- force update_focus to run
      update_focus(buf)
    end
  end)
end

local function current_range(visual)
  if visual then
    local s, e = vim.fn.line("v"), vim.fn.line(".")
    if s > e then
      s, e = e, s
    end
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
    return s, e
  end
  local l = vim.fn.line(".")
  return l, l
end

local function rel_name(file)
  local root = vim.fs.root(file, ".git")
  if root and file:sub(1, #root + 1) == root .. "/" then
    return file:sub(#root + 2)
  end
  return vim.fn.fnamemodify(file, ":t")
end

--- A draft box under the commented lines, like Hunk's: Ctrl+S saves, Esc
--- cancels, Enter adds a line.
local function draft_box(win, last_line, title, on_save, initial)
  local info = vim.fn.getwininfo(win)[1]
  local width = math.max(24, info.width - info.textoff - 2)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  -- A note is prose: no code completion popping up while you type it
  -- (blink.cmp honours vim.b.completion; nvim-cmp takes a buffer setup).
  vim.b[buf].completion = false
  vim.api.nvim_buf_call(buf, function()
    local ok, cmp = pcall(require, "cmp")
    if ok and cmp.setup and cmp.setup.buffer then
      pcall(cmp.setup.buffer, { enabled = false })
    end
  end)
  local float = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    win = win,
    bufpos = { last_line - 1, 0 },
    row = 1,
    col = 0,
    width = width,
    height = 2,
    style = "minimal",
    border = "rounded",
    title = { { " " .. title .. " ", "RexModBoxTitle" } },
    title_pos = "left",
    footer = { { " Ctrl+S save  Esc cancel ", "RexModBoxHint" } },
    footer_pos = "right",
    zindex = 60,
  })
  vim.wo[float].winhighlight = "NormalFloat:Normal,FloatBorder:RexModBoxBorder,FoldColumn:Normal"
  vim.wo[float].wrap = true
  vim.wo[float].linebreak = true
  vim.wo[float].foldcolumn = "1" -- one column of padding, like Hunk's box

  if initial and initial ~= "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(initial, "\n", { plain = true }))
  end
  local hint_ns = vim.api.nvim_create_namespace("rexmod_draft_hint")
  local function placeholder()
    vim.api.nvim_buf_clear_namespace(buf, hint_ns, 0, -1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    if #lines == 1 and lines[1] == "" then
      vim.api.nvim_buf_set_extmark(buf, hint_ns, 0, 0, { virt_text = { { "Write a note…", "RexModBoxHint" } }, virt_text_pos = "overlay" })
    end
    if vim.api.nvim_win_is_valid(float) then
      vim.api.nvim_win_set_height(float, math.min(math.max(#lines, 2), 12))
    end
  end

  local done = false
  local function close()
    if done then
      return
    end
    done = true
    vim.cmd.stopinsert()
    if vim.api.nvim_win_is_valid(float) then
      vim.api.nvim_win_close(float, true)
    end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_set_current_win(win)
    end
  end
  local function save()
    local text = vim.trim(table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"))
    close()
    if text ~= "" then
      on_save(text)
    end
  end

  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set({ "i", "n" }, "<C-s>", save, o)
  vim.keymap.set({ "i", "n" }, "<Esc>", close, o)
  vim.keymap.set("n", "q", close, o)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = buf, callback = placeholder })
  vim.api.nvim_create_autocmd("WinLeave", { buffer = buf, once = true, callback = close })
  placeholder()
  if initial and initial ~= "" then
    vim.api.nvim_win_set_cursor(float, { vim.api.nvim_buf_line_count(buf), #vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1] })
    vim.cmd("startinsert!")
  else
    vim.cmd.startinsert()
  end
end

--- Comment on the current line, or on the visual selection.
function M.add(opts)
  opts = opts or {}
  local buf = vim.api.nvim_get_current_buf()
  if not is_file_buf(buf) then
    return notify("Not a file buffer", vim.log.levels.WARN)
  end
  local file = vim.api.nvim_buf_get_name(buf)
  local s, e = current_range(opts.visual)
  local snippet = table.concat(vim.api.nvim_buf_get_lines(buf, s - 1, math.min(e, s + 60), false), "\n")
  local where = s == e and ("L" .. s) or ("L" .. s .. "-" .. e)
  draft_box(vim.api.nvim_get_current_win(), e, "Draft note - " .. rel_name(file) .. " " .. where, function(text)
    run({
      "comments", "add",
      "--file", file,
      "--line", tostring(s),
      "--end-line", tostring(e),
      "--snippet", snippet,
      "--text", text,
    }, function(res)
      if res.code ~= 0 then
        return notify("rexmod: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
      end
      M.refresh(buf)
    end)
  end)
end

--- Edit the note under the cursor in the same box (Hunk's E).
function M.edit_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local m = comment_at_cursor(buf)
  if not m then
    return notify("No note on this line", vim.log.levels.WARN)
  end
  local file = vim.api.nvim_buf_get_name(buf)
  draft_box(vim.api.nvim_get_current_win(), m.e + 1, "Edit note - " .. m.comment.file .. " " .. where(m.comment), function(text)
    run({ "comments", "edit", "--file", file, "--id", m.id, "--text", text }, function(res)
      if res.code ~= 0 then
        return notify("rexmod: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
      end
      M.refresh(buf)
    end)
  end, m.text)
end

--- Delete the note under the cursor (Hunk's D).
function M.delete_at_cursor()
  local buf = vim.api.nvim_get_current_buf()
  local m = comment_at_cursor(buf)
  if not m then
    return notify("No note on this line", vim.log.levels.WARN)
  end
  run({ "comments", "delete", "--file", vim.api.nvim_buf_get_name(buf), "--id", m.id }, function(res)
    if res.code ~= 0 then
      return notify("rexmod: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
    end
    M.refresh(buf)
  end)
end

function M.jump(dir)
  local buf = vim.api.nvim_get_current_buf()
  local l = vim.fn.line(".") - 1
  local best
  for _, m in ipairs(marks[buf] or {}) do
    if dir > 0 and m.s > l and (not best or m.s < best) then
      best = m.s
    elseif dir < 0 and m.s < l and (not best or m.s > best) then
      best = m.s
    end
  end
  if best then
    vim.api.nvim_win_set_cursor(0, { best + 1, 0 })
  end
end

local function repo_dir()
  local name = vim.api.nvim_buf_get_name(0)
  if name ~= "" and vim.bo.buftype == "" then
    return vim.fn.fnamemodify(name, ":p:h")
  end
  return vim.fn.getcwd()
end

local function target_args()
  local args = {}
  local session = vim.env.REXMOD_SESSION or vim.env.REX_SESSION
  if session and session ~= "" then
    vim.list_extend(args, { "--session", session })
  end
  if vim.env.REXMOD_WINDOW and vim.env.REXMOD_WINDOW ~= "" then
    vim.list_extend(args, { "--window", vim.env.REXMOD_WINDOW })
  end
  return args
end

--- Paste the pending comments into the agent pane and submit them.
function M.send()
  local args = { "comments", "send", "--repo", repo_dir() }
  vim.list_extend(args, target_args())
  run(args, function(res)
    if res.code ~= 0 then
      return notify("rexmod: " .. vim.trim(res.stderr or ""), vim.log.levels.WARN)
    end
    notify(vim.trim(res.stdout))
    for buf in pairs(marks) do
      M.refresh(buf)
    end
  end)
end

function refresh_all()
  for buf in pairs(marks) do
    if vim.api.nvim_buf_is_valid(buf) then
      M.refresh(buf)
    end
  end
end

--- List every comment of the repo.
function M.list()
  run({ "comments", "list", "--repo", repo_dir(), "--json" }, function(res)
    if res.code ~= 0 then
      return notify("rexmod: " .. vim.trim(res.stderr or ""), vim.log.levels.WARN)
    end
    local ok, data = pcall(vim.json.decode, res.stdout)
    if not ok then
      return
    end
    local items = {}
    for _, c in ipairs(data.comments or {}) do
      local pending = c.sent_at == nil or c.sent_at == vim.NIL or c.sent_at == ""
      local range = c.end_line and c.end_line > c.line and (c.line .. "-" .. c.end_line) or tostring(c.line)
      items[#items + 1] = {
        text = c.file .. ":" .. range .. " " .. c.text,
        file = data.repo .. "/" .. c.file,
        pos = { c.line, 0 },
        end_pos = { c.end_line or c.line, 0 },
        comment = c,
        pending = pending,
        range = range,
      }
    end
    if #items == 0 then
      return notify("No review comments in this repo")
    end
    local has_snacks, Snacks = pcall(require, "snacks")
    if not has_snacks or not Snacks.picker then
      vim.fn.setqflist({}, " ", {
        title = "Review comments",
        items = vim.tbl_map(function(it)
          return { filename = it.file, lnum = it.pos[1], text = it.comment.text }
        end, items),
      })
      return vim.cmd("copen")
    end
    Snacks.picker({
      title = "Review comments  ·  <c-s> send pending to the agent  ·  <c-x> delete",
      items = items,
      format = function(item)
        return {
          { item.pending and "󰆉 " or " ", item.pending and "RexModPending" or "RexModSent" },
          { item.comment.file, "SnacksPickerFile" },
          { ":" .. item.range .. "  ", "SnacksPickerDimmed" },
          { item.comment.text, item.pending and "Normal" or "Comment" },
        }
      end,
      preview = "file",
      actions = {
        rexmod_delete = function(picker, item)
          if not item then
            return
          end
          run({ "comments", "delete", "--repo", data.repo, "--id", item.comment.id }, function()
            picker:close()
            refresh_all()
            M.list()
          end)
        end,
        rexmod_send = function(picker)
          picker:close()
          M.send()
        end,
      },
      win = {
        input = {
          keys = {
            ["<c-x>"] = { "rexmod_delete", mode = { "n", "i" } },
            ["<c-s>"] = { "rexmod_send", mode = { "n", "i" } },
          },
        },
        list = { keys = { ["dd"] = "rexmod_delete" } },
      },
    })
  end)
end

--- Open a file at a line. Called by `rexmod open` through --remote-expr.
function M.open(path, line)
  vim.schedule(function()
    if vim.fn.mode():match("^[iR]") then
      vim.cmd.stopinsert()
    end
    -- Leave floating windows (pickers, inputs) before switching buffers.
    local cfg = vim.api.nvim_win_get_config(0)
    if cfg.relative and cfg.relative ~= "" then
      pcall(vim.api.nvim_win_close, 0, false)
    end
    local ok = pcall(vim.cmd, "drop " .. vim.fn.fnameescape(path))
    if not ok then
      vim.cmd("edit " .. vim.fn.fnameescape(path))
    end
    if line and line > 0 then
      pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
      vim.cmd("normal! zz")
    end
  end)
  return 1
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  setup_highlights()
  local k = M.config.keys
  vim.keymap.set("n", k.add, function()
    M.add()
  end, { desc = "Review: comment on line" })
  vim.keymap.set("x", k.add, function()
    M.add({ visual = true })
  end, { desc = "Review: comment on selection" })
  vim.keymap.set("n", k.list, M.list, { desc = "Review: list comments" })
  vim.keymap.set("n", k.next, function()
    M.jump(1)
  end, { desc = "Next review comment" })
  vim.keymap.set("n", k.prev, function()
    M.jump(-1)
  end, { desc = "Previous review comment" })

  vim.api.nvim_create_user_command("RexComment", function(a)
    M.add({ visual = a.range > 0 })
  end, { range = true, desc = "Comment on the line or range" })
  vim.api.nvim_create_user_command("RexComments", M.list, { desc = "List review comments" })
  vim.api.nvim_create_user_command("RexCommentDelete", M.delete_at_cursor, { desc = "Delete the comment on this line" })
  vim.api.nvim_create_user_command("RexCommentEdit", M.edit_at_cursor, { desc = "Edit the comment on this line" })
  vim.api.nvim_create_user_command("RexSend", M.send, { desc = "Send pending comments to the agent" })

  if M.config.auto_install then
    require("rexmod.autoinstall").setup()
  end

  local group = vim.api.nvim_create_augroup("rexmod", { clear = true })
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "BufEnter" }, {
    group = group,
    callback = function(ev)
      M.refresh(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = setup_highlights })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    callback = function(ev)
      update_focus(ev.buf)
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      for buf in pairs(cache) do
        render(buf)
      end
    end,
  })
  -- Comments sent by the agent hook change state outside Neovim.
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = refresh_all })

  -- The editor pane that `rexmod open` starts behaves like Zed: diagnostics
  -- update while typing.
  if vim.env.REXMOD_EDITOR == "1" then
    vim.diagnostic.config({ update_in_insert = true })
  end
end

return M
