---@class sidekick.cli.session.Opencode: sidekick.cli.Session
---@field port number
---@field pid number
---@field base_url string
local M = {}
M.__index = M
M.priority = 20
M.external = true

function M.sessions()
  local Procs = require("sidekick.cli.procs")
  local Util = require("sidekick.util")

  -- Get all listening ports with PIDs in one call
  local lines = Util.exec({ "lsof", "-w", "-iTCP", "-sTCP:LISTEN", "-P", "-n", "-Fn", "-Fp" }, { notify = false }) or {}

  -- Parse lsof output to build pid -> ports[] mapping
  local ports = {} ---@type table<number, number[]>
  local current_pid ---@type number?

  for _, line in ipairs(lines) do
    local pid = line:match("^p(%d+)$")
    if pid then
      current_pid = tonumber(pid)
    else
      local port = line:match("^n.*:(%d+)$")
      if port and current_pid then
        if not ports[current_pid] then
          ports[current_pid] = {}
        end
        local list = ports[current_pid]
        list[#list + 1] = tonumber(port)
      end
    end
  end

  -- Probe all ports for a PID to find the one serving the opencode API
  ---@param pid_ports number[]
  ---@return number?
  local function find_api_port(pid_ports)
    for _, port in ipairs(pid_ports) do
      local result = Util.exec(
        { "curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "http://localhost:" .. port .. "/app" },
        { notify = false }
      )
      if result and result[1] == "200" then
        return port
      end
    end
    return nil
  end

  -- Find opencode processes and match with the correct API port
  local ret = {} ---@type sidekick.cli.session.State[]

  for pid, pid_ports in pairs(ports) do
    local api_port = find_api_port(pid_ports)
    if api_port then
      local proc = vim.api.nvim_get_proc(pid)
      if proc and proc.name == "opencode" then
        ret[#ret + 1] = {
          id = "opencode-" .. pid,
          pid = pid,
          tool = "opencode",
          cwd = Procs.cwd(pid) or "",
          port = api_port,
          pids = Procs.pids(pid),
          mux_session = tostring(pid),
          base_url = ("http://localhost:%d"):format(api_port),
        }
      end
    end
  end
  return ret
end

function M:attach() end

function M:is_running()
  return self.pid and vim.api.nvim_get_proc(self.pid) ~= nil
end

function M:send(text)
  require("sidekick.util").curl(self.base_url .. "/tui/append-prompt", {
    method = "POST",
    data = { text = text },
  })
end

function M:submit()
  require("sidekick.util").curl(self.base_url .. "/tui/submit-prompt", {
    method = "POST",
    data = {},
  })
end

-- only register on Unix-like systems with lsof available
if vim.fn.has("win32") == 0 and vim.fn.executable("lsof") == 1 then
  require("sidekick.cli.session").register("opencode", M)
end

---@type sidekick.cli.Config
return {
  cmd = { "opencode" },
  env = {
    -- HACK: https://github.com/sst/opencode/issues/445
    OPENCODE_THEME = "system",
  },
  keys = {
    prompt = { "<a-p>", "prompt" },
  },
  is_proc = "\\<opencode\\>",
  url = "https://github.com/sst/opencode",
  continue = { "--continue" },
  native_scroll = true,
}
