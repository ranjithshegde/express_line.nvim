local helper = require "el.helper"
local log = require "el.log"
local meta = require "el.meta"

-- TODO:
-- Should not error when the variable doesn't exist
-- Options to not get called for hidden files / etc.

local subscribe = {}

local _current_subscriptions = {}

local el_buf_au, el_user_au

subscribe._reload = function()
  if not el_buf_au then
    el_buf_au = vim.api.nvim_create_augroup("ElBufSubscriptions", { clear = true })
  end

  _ElBufSubscriptions = setmetatable({}, {
    __index = function(t, k)
      rawset(t, k, {})
      return rawget(t, k)
    end,
  })

  _ElUserSubscriptions = setmetatable({}, {
    __index = function(t, k)
      rawset(t, k, {})
      return rawget(t, k)
    end,
  })
end

if not _ElBufSubscriptions or not _ElUserSubscriptions then
  subscribe._reload()
end

local _current_callbacks = {}

--[[

table.insert(el_segment, subsribe.buf_autocmd(
  -- Sets b:el_git_status to the result
  "el_git_status",
  -- Events to fire on
  "BufWritePost",
  -- Function to run
  function(window, buffer)
    return extensions.git_changes(window, buffer)
  end
))


--]]

-- TODO: This doesn't work yet
subscribe.autocmd = function(identifier, name, pattern, callback)
  error()

  if _current_subscriptions[identifier] ~= nil then
    return
  end

  table.insert(_current_callbacks, callback)

  vim.api.nvim_create_autocmd(name, {
    -- group = au_id,
    pattern = pattern,
    callback = function()
      require("el.subscribe")._process_callback(#_current_callbacks)
    end,
  })
end

--- Subscribe to a buffer autocmd with a lua callback.
--
--@param identifier String: name of the variable we'll save to b:
--@param au_events String: The events to subscribe to
--@param callback Callable: A function that takes the (_, Buffer) style callback and returns a value
subscribe.buf_autocmd = function(identifier, au_events, callback)
  return function(_, buffer)
    if _ElBufSubscriptions[buffer.bufnr][identifier] == nil then
      log.debug("Generating callback for", identifier, buffer.bufnr)

      if not el_buf_au then
        el_buf_au = vim.api.nvim_create_augroup("ElBufSubscriptions", { clear = true })
      end

      vim.api.nvim_create_autocmd(au_events, {
        group = el_buf_au,
        buffer = buffer.bufnr,
        callback = function()
          require("el.subscribe")._process_buf_callback(buffer.bufnr, identifier)
        end,
      })

      _ElBufSubscriptions[buffer.bufnr][identifier] = callback

      vim.api.nvim_buf_set_var(buffer.bufnr, identifier, callback(nil, buffer) or "")
    end

    -- nvim_buf_get_var shouldn't return nil, because we set the buffer var to '' if callback returns nil
    -- we reset subscription here when nil is returned, see issue #40
    -- new subscription will be setup next time buf_autocmd is called
    local res = helper.nvim_buf_get_var(buffer.bufnr, identifier)
    if not res then
      _ElBufSubscriptions[buffer.bufnr][identifier] = nil
    end
    return res
  end
end

--- Subscribe to user autocmd.
---<pre>
--- subscribe.user_autocmd(
---     'el_git_hunks', 'GitGutter',
---     function(window, buffer)
---         return
---     end
--- )
---</pre>
subscribe.user_autocmd = function(identifier, au_events, callback)
  return function(_, buffer)
    if _ElUserSubscriptions[buffer.bufnr][identifier] == nil then
      log.debug("Generating user callback for", identifier, buffer.bufnr)

      if not el_user_au then
        el_user_au = vim.api.nvim_create_augroup("ElUserSubscriptions", { clear = true })
      end

      vim.api.nvim_create_autocmd("User " .. au_events, {
        group = el_user_au,
        callback = function()
          require("el.subscribe")._process_user_callback(buffer.bufnr, identifier)
        end,
      })

      _ElUserSubscriptions[buffer.bufnr][identifier] = callback

      vim.api.nvim_buf_set_var(buffer.bufnr, identifier, callback(nil, buffer) or "")
    end

    return helper.nvim_buf_get_var(buffer.bufnr, identifier)
  end
end

subscribe._process_callbacks = function(identifier) end

subscribe._process_buf_callback = function(bufnr, identifier)
  local cb = _ElBufSubscriptions[bufnr][identifier]
  if cb == nil then
    -- TODO: Figure out how this can happen.
    return
  end

  local res = cb(nil, meta.Buffer:new(bufnr))
  local ok, msg = pcall(vim.api.nvim_buf_set_var, bufnr, identifier, res or "")

  if not ok then
    log.debug(msg, res, bufnr, identifier)
  end
end

subscribe._process_user_callback = function(bufnr, identifier)
  local cb = _ElUserSubscriptions[bufnr][identifier]
  if cb == nil then
    -- TODO: Figure out how this can happen.
    return
  end

  local res = cb(nil, meta.Buffer:new(bufnr))
  local ok, msg = pcall(vim.api.nvim_buf_set_var, bufnr, identifier, res or "")

  if not ok then
    log.debug(msg, res, bufnr, identifier)
  end
end

subscribe.option_set = function() end

--[==[
local option_callbacks = setmetatable({}, {
  -- TODO: Could probably use v here.
  __mode = "v"
})

el.option_set_subscribe = function(group, option_pattern, callback)
  table.insert(option_callbacks, callback)
  local callback_number = #option_callbacks

  vim.cmd(string.format([[augroup %s]], group))
  vim.cmd(string.format([[  autocmd OptionSet %s lua el.option_process("<amatch>", %s)]], option_pattern, callback_number))
  vim.cmd               [[augroup END]]
end

el.option_process = function(name, callback_number)
  local option_type = vim.v.option_type
  local option_new = vim.v.option_new

  local opts = {
    option_type = option_type,
    option_new = option_new,
  }

  return option_callbacks[callback_number](name, opts)
end
--]==]

return subscribe
