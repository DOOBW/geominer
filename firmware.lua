local internet = component.proxy(component.list('internet')())
if not internet then
  error('This program requires an internet card to run.',0)
end

local mirrors = {
  'https://raw.githubusercontent.com/DOOBW/geominer/master/miner.lua',
}

for i = 1, #mirrors do
  local _, request, reason = pcall(internet.request, mirrors[i])
  local result, code, message, headers = ''
  if request then
    while not request.finishConnect() do
      computer.pullSignal(1)
    end
    code, message, headers = request.response()
    while true do
      if not code then
        break
      end
      local data, reason = request.read()
      if not data then
        request.close()
        break
      elseif #data > 0 then
        result = result..data
      end
    end
    if tonumber(headers['Content-Length'][1]) == #result then
      pcall(load(result))
    end
  end
end
