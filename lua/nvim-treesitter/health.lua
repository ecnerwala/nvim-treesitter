local api = vim.api
local fn = vim.fn

local queries = require "nvim-treesitter.query"
local info = require "nvim-treesitter.info"
local shell = require "nvim-treesitter.shell_command_selectors"
local install = require "nvim-treesitter.install"

local health_start = vim.fn["health#report_start"]
local health_ok = vim.fn["health#report_ok"]
local health_error = vim.fn["health#report_error"]
local health_warn = vim.fn["health#report_warn"]

local M = {}

local NVIM_TREESITTER_MINIMUM_ABI = 13

local function install_health()
  health_start "Installation"

  if fn.executable "tree-sitter" == 0 then
    health_warn(
      "`tree-sitter` executable not found (parser generator, only needed for :TSInstallFromGrammar,"
        .. " not required for :TSInstall)"
    )
  else
    local handle = io.popen "tree-sitter  -V"
    local result = handle:read "*a"
    handle:close()
    local version = vim.split(result, "\n")[1]:match "[^tree%psitter].*"
    health_ok(
      "`tree-sitter` found "
        .. (version or "(unknown version)")
        .. " (parser generator, only needed for :TSInstallFromGrammar)"
    )
  end

  if fn.executable "node" == 0 then
    health_warn(
      "`node` executable not found (only needed for :TSInstallFromGrammar," .. " not required for :TSInstall)"
    )
  else
    local handle = io.popen "node --version"
    local result = handle:read "*a"
    handle:close()
    local version = vim.split(result, "\n")[1]
    health_ok("`node` found " .. version .. " (only needed for :TSInstallFromGrammar)")
  end

  if fn.executable "git" == 0 then
    health_error("`git` executable not found.", {
      "Install it with your package manager.",
      "Check that your `$PATH` is set correctly.",
    })
  else
    health_ok "`git` executable found."
  end

  local cc = shell.select_executable(install.compilers)
  if not cc then
    health_error("`cc` executable not found.", {
      "Check that any of "
        .. vim.inspect(install.compilers)
        .. " is in your $PATH"
        .. ' or set the environment variable CC or `require"nvim-treesitter.install".compilers` explicitly!',
    })
  else
    health_ok("`" .. cc .. "` executable found. Selected from " .. vim.inspect(install.compilers))
  end
  if vim.treesitter.language_version then
    if vim.treesitter.language_version >= NVIM_TREESITTER_MINIMUM_ABI then
      health_ok(
        "Neovim was compiled with tree-sitter runtime ABI version "
          .. vim.treesitter.language_version
          .. " (required >="
          .. NVIM_TREESITTER_MINIMUM_ABI
          .. "). Parsers must be compatible with runtime ABI."
      )
    else
      health_error(
        "Neovim was compiled with tree-sitter runtime ABI version "
          .. vim.treesitter.language_version
          .. ".\n"
          .. "nvim-treesitter expects at least ABI version "
          .. NVIM_TREESITTER_MINIMUM_ABI
          .. "\n"
          .. "Please make sure that Neovim is linked against are recent tree-sitter runtime when building"
          .. " or raise an issue at your Neovim packager. Parsers must be compatible with runtime ABI."
      )
    end
  end
end

local function query_status(lang, query_group)
  local ok, err = pcall(queries.get_query, lang, query_group)
  if not ok then
    return "x", err
  elseif not err then
    return "."
  else
    return "✓"
  end
end

function M.checkhealth()
  local error_collection = {}
  -- Installation dependency checks
  install_health()
  queries.invalidate_query_cache()
  health_start "Parser/Features H L F I"
  -- Parser installation checks
  for _, parser_name in pairs(info.installed_parsers()) do
    local installed = #api.nvim_get_runtime_file("parser/" .. parser_name .. ".so", false)

    -- Only print informations about installed parsers
    if installed >= 1 then
      local multiple_parsers = installed > 1 and "+" or ""
      local out = "  - " .. parser_name .. multiple_parsers .. string.rep(" ", 15 - (#parser_name + #multiple_parsers))
      for _, query_group in pairs(queries.built_in_query_groups) do
        local status, err = query_status(parser_name, query_group)
        out = out .. status .. " "
        if err then
          table.insert(error_collection, { parser_name, query_group, err })
        end
      end
      print(out)
    end
  end
  print [[

 Legend: H[ighlight], L[ocals], F[olds], I[ndents]
         +) multiple parsers found, only one will be used
         x) errors found in the query, try to run :TSUpdate {lang}]]
  if #error_collection > 0 then
    print "\nThe following errors have been detected:"
    for _, p in ipairs(error_collection) do
      local lang, type, err = unpack(p)
      health_error(lang .. "(" .. type .. "): " .. err)
    end
  end
end

return M
