-- Language support on demand: open a file and its tree-sitter parser and
-- language server are installed (Mason) and started, whatever the language.
-- Nothing happens for a filetype that already has both.
local M = {}

-- The server to install for common filetypes. Other filetypes take the first
-- language-specific server mason-lspconfig knows for them.
local preferred = {
  python = { "basedpyright", "ruff" },
  go = { "gopls" }, gomod = { "gopls" }, gowork = { "gopls" }, gotmpl = { "gopls" },
  rust = { "rust_analyzer" },
  lua = { "lua_ls" },
  c = { "clangd" }, cpp = { "clangd" }, objc = { "clangd" }, objcpp = { "clangd" }, cuda = { "clangd" },
  swift = { "sourcekit" },
  java = { "jdtls" },
  kotlin = { "kotlin_lsp", "kotlin_language_server" },
  ruby = { "ruby_lsp" },
  php = { "intelephense" },
  sh = { "bashls" }, bash = { "bashls" }, zsh = { "bashls" },
  yaml = { "yamlls" },
  toml = { "taplo" },
  json = { "jsonls" }, jsonc = { "jsonls" },
  html = { "html" },
  css = { "cssls" }, scss = { "cssls" }, less = { "cssls" },
  markdown = { "marksman" },
  dockerfile = { "dockerls" },
  terraform = { "terraformls" },
  elixir = { "elixirls" },
  zig = { "zls" },
  haskell = { "hls" },
  ocaml = { "ocamllsp" },
  svelte = { "svelte" }, vue = { "vue_ls" }, astro = { "astro" },
  javascript = { "vtsls" }, javascriptreact = { "vtsls" }, typescript = { "vtsls" }, typescriptreact = { "vtsls" },
  nix = { "nil_ls" },
  prisma = { "prismals" },
  graphql = { "graphql" },
  proto = { "buf_ls" },
  dart = { "dartls" },
  cs = { "roslyn", "omnisharp" },
  tex = { "texlab" }, plaintex = { "texlab" },
  typst = { "tinymist" },
  sql = { "sqls" },
  xml = { "lemminx" },
  vim = { "vimls" },
  clojure = { "clojure_lsp" },
  erlang = { "elp" },
  gleam = { "gleam" },
  scala = { "metals" },
}

-- Servers that cover many languages (spelling, linters, frameworks): never
-- the one picked for a filetype on their own.
local generic = {
  ast_grep = true, harper_ls = true, codebook = true, snyk_ls = true, ltex = true, ltex_plus = true,
  vale_ls = true, typos_lsp = true, htmx = true, tailwindcss = true, emmet_ls = true,
  emmet_language_server = true, unocss = true, stimulus_ls = true, biome = true, eslint = true,
  oxlint = true, stylelint_lsp = true, cspell_ls = true, copilot = true, sonarlint = true,
  efm = true, diagnosticls = true, rome = true, denols = true, shuck = true,
}

local tried = {} -- filetype or server -> true, once per session

local function notify(msg, level)
  vim.schedule(function()
    vim.notify(msg, level or vim.log.levels.INFO, { title = "rexmod" })
  end)
end

-- Tree-sitter -------------------------------------------------------------

local function ensure_parser(buf, ft)
  local lang = vim.treesitter.language.get_lang(ft) or ft
  if tried["ts:" .. lang] then
    return
  end
  tried["ts:" .. lang] = true
  -- language.add returns nil (it no longer throws) when the parser is missing.
  local ok, loaded = pcall(vim.treesitter.language.add, lang)
  if ok and loaded then
    return -- already there
  end
  local ok, ts = pcall(require, "nvim-treesitter")
  if not ok or not vim.tbl_contains(ts.get_available(), lang) then
    return
  end
  if vim.fn.executable("tree-sitter") == 0 then
    notify("rexmod: install the tree-sitter CLI (brew install tree-sitter-cli) for " .. lang .. " highlighting", vim.log.levels.WARN)
    return
  end
  notify("Installing the " .. lang .. " parser…")
  ts.install({ lang }):await(function(err)
    vim.schedule(function()
      if err then
        notify("rexmod: " .. lang .. " parser failed: " .. tostring(err), vim.log.levels.WARN)
        return
      end
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == ft then
          pcall(vim.treesitter.start, b, lang)
        end
      end
    end)
  end)
end

-- Language servers ----------------------------------------------------------

local function mason()
  local ok1, registry = pcall(require, "mason-registry")
  local ok2, mlsp = pcall(require, "mason-lspconfig")
  if ok1 and ok2 then
    return registry, mlsp
  end
end

-- Servers to run for ft: the preferred ones Mason or the system has, else the
-- first language-specific one Mason knows.
local function servers_for(ft, mlsp)
  local known = {}
  local map = {}
  if mlsp then
    for _, s in ipairs(mlsp.get_available_servers({ filetype = ft })) do
      known[s] = true
    end
    map = mlsp.get_mappings().lspconfig_to_package or {}
  end
  local out = {}
  for _, s in ipairs(preferred[ft] or {}) do
    local cfg = vim.lsp.config[s]
    local cmd = cfg and type(cfg.cmd) == "table" and cfg.cmd[1]
    if map[s] or (cmd and vim.fn.executable(cmd) == 1) then
      table.insert(out, s)
      if s ~= "basedpyright" then
        break -- one server, except Python's type checker + ruff
      end
    end
  end
  if #out == 0 then
    local candidates = vim.tbl_keys(known)
    table.sort(candidates)
    for _, s in ipairs(candidates) do
      if not generic[s] then
        table.insert(out, s)
        break
      end
    end
  end
  -- A preferred server Mason can't install (it ships with the language).
  local missing
  if #out == 0 and preferred[ft] then
    local cfg = vim.lsp.config[preferred[ft][1]]
    missing = cfg and type(cfg.cmd) == "table" and cfg.cmd[1] or nil
  end
  return out, map, missing
end

local function enable(server)
  vim.schedule(function()
    pcall(vim.lsp.enable, server)
  end)
end

local function ensure_server(buf, ft)
  if tried["lsp:" .. ft] then
    return
  end
  -- Give configured servers (LazyVim extras, your own) a moment to attach.
  vim.defer_fn(function()
    if tried["lsp:" .. ft] or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    tried["lsp:" .. ft] = true
    for _, c in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
      if not generic[c.name] then
        return -- a language server already works on it
      end
    end
    local registry, mlsp = mason()
    local servers, map, missing = servers_for(ft, mlsp)
    if missing then
      notify("No language server for " .. ft .. " yet: it comes with `" .. missing .. "`; install that and reopen the file.")
    end
    for _, server in ipairs(servers) do
      if not tried[server] then
        tried[server] = true
        local pkg_name = map[server]
        if not pkg_name or not registry then
          enable(server) -- a system binary (sourcekit, dartls, …)
        else
          local ok, pkg = pcall(registry.get_package, pkg_name)
          if ok and pkg:is_installed() then
            enable(server)
          elseif ok then
            notify("Installing " .. pkg_name .. " for " .. ft .. "…")
            pkg:install({}, function(success, err)
              if success then
                notify(pkg_name .. " is ready")
                enable(server)
              else
                notify("rexmod: " .. pkg_name .. " failed: " .. tostring(err), vim.log.levels.WARN)
              end
            end)
          end
        end
      end
    end
  end, 1500)
end

function M.setup()
  local group = vim.api.nvim_create_augroup("rexmod_autoinstall", { clear = true })
  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    callback = function(ev)
      local buf, ft = ev.buf, ev.match
      if ft == "" or vim.bo[buf].buftype ~= "" or vim.api.nvim_buf_get_name(buf) == "" then
        return
      end
      ensure_parser(buf, ft)
      ensure_server(buf, ft)
    end,
  })
end

return M
