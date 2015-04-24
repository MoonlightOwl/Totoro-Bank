-- Bank Supervisor (1.4)
-- computercraft.ru (c) Totoro

local term = require('term')
local event = require('event')
local fs = require('filesystem')
local serial = require('serialization')
local unicode = require('unicode')
local com = require('component')
local gpu = com.gpu
local modem = com.modem

-- константы
local PORT = 27
local comp = {}
local COMPLISTFILE = "supervisor.dat"
local WIDTH, HEIGHT = gpu.getResolution()
local old = {}
old.fore = gpu.getForeground()
old.back = gpu.getBackground()
local REQUEST = "root@admin:~$ "

-- функции
-- вывод в консоль
local function out(message, dark)
  if dark then gpu.setForeground( 0x008800) end
  term.write(message)
  if dark then gpu.setForeground( 0x00ff00) end
end
local function errout(message)
  out("[ERROR] ", true)
  out(message)
end
local function netout(message)
  out("[NET] ", true)
  out(message)
end

-- разбиваем строку по словам
local function split(line)
  local data = {}
  for word in line:gmatch("%S+") do table.insert(data, word) end
  return data
end

-- загружаем список
local function loadCompList(filename)
  if fs.exists(filename) then
    local file = io.open(filename, "r")
    local data = file:read("*a")
    file:close()
    comp = serial.unserialize(data)
    return true
  else
    print("Computers list file not found. New list will be created.")
    comp = {}
    return false
  end
end
-- сохраняем список
local function saveCompList(filename)
  local file = io.open(filename, "w")
  local data = serial.serialize(comp)
  file:write(data)
  file:close()
  return true
end

-- добавляем адрес в список
local function addTerminal(address, id)
  if comp[id] == nil then comp[id] = {} end
  if comp[id].terminal ~= address then
    comp[id].terminal = address
    saveCompList(COMPLISTFILE)
  end
end
local function addTeller(address, id)
  if comp[id] == nil then comp[id] = {} end
  if comp[id].teller ~= address then
    comp[id].teller = address
    saveCompList(COMPLISTFILE)
  end
end
local function addHard(address, id)
  if comp[id] == nil then comp[id] = {} end
  if comp[id].hard ~= address then
    comp[id].hard = address
    saveCompList(COMPLISTFILE)
  end
end

-- посылаем команду на один компьютер
local function send(id, message, toterminal, toteller)
  if comp[id] ~= nil then
    if toterminal and comp[id].terminal ~= nil then 
      modem.send(comp[id].terminal, PORT, message) 
    end
    if toteller and comp[id].teller ~= nil then 
      modem.send(comp[id].teller, PORT, message) 
    end
    return true
  else
    return false
  end
end
-- рассылаем команду всем компьютерам в списке
local function sendAll(message, toterminal, toteller)
  for a,b in pairs(comp) do
    send(a, message, toterminal, toteller)
  end
  return true
end

-- справка
local function help()
  out("[Totoro Bank] Supervisor (v1.3)\n")
  out("computercraft.ru (c) All right reserved\n")
  out("---\n", true)
  out("Available commands:\n")
  out(" clear                               -- clear screen\n")
  out(" exit                                -- leave the program\n")
  out(" shutdown  [PARAMETER] [IDs ...]     -- reboot computers\n")
  out("           -all    -- all computers\n")
  out("           -id     -- given id's\n")
  out(" block     [PARAMETER] [IDs ...]     -- block terminals\n")
  out("           -all    -- all terminals\n")
  out("           -id     -- given id's\n")
  out(" unblock   [PARAMETER] [IDs ...]     -- unblock terminals\n")
  out("           -all    -- all terminals\n")
  out("           -id     -- given id's\n")
  out(" pricesupd [PARAMETER] [IDs ...]     -- force update prices\n")
  out("           -all    -- all robots\n")
  out("           -id     -- given id's\n")
  out(" doors     [PARAMETER] [IDs ...]     -- manage cabin doors\n")
  out("           -open   -- \n")
  out("           -close  -- action\n")
  out("           -all    -- all doors\n")
  out("           -id     -- on given id's\n")
  out(" hardlist                            -- display all hard drive addresses\n")
  out(" drop database                       -- remove all addresses\n")
  out(" help                                -- this text\n")
  out("---\n", true)
  out("Created by Totoro, AlexCC\n")
end

local function hardlist()
  for a,b in pairs(comp) do
    out("#"..a.." Hard: ")
    if b.hard ~= nil then
      out(b.hard.."\n")
    else
      out(" ---- \n")
    end
  end
end

-- стандартная команда
local function standart(command, data, message, toterminal, toteller)
  if data[1] == command then
    -- все компьютеры
    if data[2] == nil or data[2] == '-all' then
      out("Processing...\n")
      sendAll(command, toterminal, toteller)
      out("All computers have been "..message.."\n")
    -- перечисленные компьютеры
    elseif data[2] == '-id' then
      local n = 3
      while true do
        local id = tonumber(data[n])
        if id ~= nil then
          if send(id, command, toterminal, toteller) then
            out("#"..data[n].." "..message.."\n")
          else
            errout("Not found, ID: "..data[n].."\n")
          end
          n = n + 1
        else 
          if data[n] ~= nil then
            errout("Wrong ID: "..data[n].."\n")
          end
          break 
        end
      end
      out("Done\n")
    else
      errout("Wrong parameter\n")
    end  
    return true
  end
  return false
end

-- выполнение команд админа
local function execute(command)
  local data = split(command)
  if data[1] == 'help' then
    help()
  elseif data[1] == 'clear' then
    term.clear()
  elseif data[1] == 'exit' then
    return false
  elseif data[1] == 'hardlist' then
    hardlist()
  elseif data[1] == 'drop' and data[2] == 'database' then
    comp = {}
    saveCompList(COMPLISTFILE)
  elseif data[1] == 'doors' then
    if data[2] == '-open' then
      data[2] = "opendoor"
      table.remove(data, 1)
      standart("opendoor", data, "opened", true, false)
    elseif data[2] == '-close' then
      data[2] = "closedoor"
      table.remove(data, 1)
      standart("closedoor", data, "closed", true, false)
    end
  elseif data[1] == 'alexcc' then
    out("Hi, AlexCC!\n")
  elseif data[1] == 'totoro' then
    out("Hi, Totoro!\n")
  else
    local ok = false
    ok = ok or standart("shutdown", data, "restarted", true, true)
    ok = ok or standart("block", data, "blocked", true, false)
    ok = ok or standart("unblock", data, "unblocked", true, false)
    ok = ok or standart("pricesupd", data, "updated", false, true)
    if not ok then errout("Unknown command") end
  end
  return true
end

-- инициализация
-- чистим экран
gpu.setForeground( 0x00FF00)
gpu.setBackground( 0x000000)
term.clear()
-- шапка
--out("[Bank Admin Tool] Supervisor v1.2\n")
--out(string.rep("-", WIDTH).."\n", true)
-- загружаем список адресов
loadCompList(COMPLISTFILE)
-- включаем мигание курсора
term.setCursorBlink(true)
-- открываем порт
modem.open(PORT)

-- приглашение
out("\n"..REQUEST, true)
local command = ""
local history = {pos = 1}

-- главный цикл - ловим эвенты, слушаем эфир
while true do
  local name, add, sender, code, _, message, data, data2 = event.pull()
  
  if name == 'modem_message' then
    -- если получено оповещение от компьютера
    -- заносим его адрес в список
    local id = tonumber(data)
    if id ~= nil then
      if message == 'terminal' then
        addTerminal(sender, id)
        term.clearLine()
        netout("New terminal: #"..id.." : "..sender.."\n")
        out(REQUEST, true)
        term.write(command)
      elseif message == 'teller' then
        addTeller(sender, id)
        addHard(data2, id)
        term.clearLine()
        netout("New teller: #"..id.." : "..sender.."\n")
        out(REQUEST, true)
        term.write(command)
      end
    end    
  elseif name == 'key_down' then
    -- проверка на спецсимволы
    if sender > 30 then
      local letter = unicode.char(sender)
      command = command..letter
      term.write(letter)
    else
      -- enter
      if code == 28 then
        -- исполняем
        print()
        if not execute(command) then break end
        out("\n"..REQUEST, true)
        -- записываем для истории
        table.insert(history, command)
        if #history > 40 then table.remove(history, 1) end
        history.pos = #history+1
        -- новая
        command = ""
      -- backspace
      elseif code == 14 then
        if unicode.len(command) > 0 then
          local x, y = term.getCursor()
          gpu.set(x-1, y, ' ')
          term.setCursor(x-1, y)
          command = unicode.sub(command, 1, -2)
        end
      -- up
      elseif code == 200 or code == 208 then
        if #history > 0 then
          if code == 200 then
            if history.pos > 1 then history.pos = history.pos - 1 end
          else
            if history.pos < #history+1 then history.pos = history.pos + 1 end
          end
          local x, y = term.getCursor()
          gpu.set(#REQUEST+1, y, string.rep(' ', unicode.len(command)))
          term.setCursor(#REQUEST+1, y)
          if history[history.pos] ~= nil then
            command = history[history.pos]
          else
            command = ""
          end
          term.write(command)
        end
      end
    end
  end
end

-- сохраняем список адресов
saveCompList(COMPLISTFILE)
-- выключаем мигание курсора
term.setCursorBlink(false)
-- закрываем порт
modem.close(PORT)
-- чистим экран
gpu.setForeground(old.fore)
gpu.setBackground(old.back)
term.clear()