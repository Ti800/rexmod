-- Language servers set up up front. Any other language gets its server and
-- tree-sitter parser on demand: rexmod installs them when you open a file.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        tailwindcss = {
          settings = {
            tailwindCSS = {
              classFunctions = { "cn", "clsx", "cva", "tv", "twMerge" },
            },
          },
        },
      },
    },
  },
}
