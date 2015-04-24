-- Bank Teller (1.7.65)
-- computercraft.ru (c) Totoro
local robot = require('robot')
local internet = require("internet")
local serial = require('serialization')
local fs = require("filesystem")
local event = require('event')
local sides = require('sides')
local computer = require('computer')
local com = require('component')
local icontroller = com.inventory_controller
local magnet = com.tractor_beam
local modem = com.modem
local inet = com.internet
local red = com.redstone

-- константы
local PORT = 27                   -- порт, через который робот работает со своим терминалом
local DEFAULTMARKUP = 0.2         -- торговая наценка по дефолту
local MINTRANSFER = 10000         -- минимальный трансфер денег
local MAXTRANSFER = 10000000      -- максимальный трансфер
local TRANSFERCOMM = 0.005        -- комиссия на трансфер (от 0.0 до 1.0)
local MAXPURCHASE = 1000          -- максимальный объем закупок
local NETTIMEOUT = 30             -- таймаут ожидания сетевого сообщения
local PRICESPAGE = "PT9svXJz"     -- код странички Pastebin
local PRICESFILE = "prices.dat"   -- название файла с локальной копией прайсов
local PRICESUPDATE = 7200         -- время между обновлениями прайсов 2 часа (60*60*2)
local SESSIONTIME = 20000         -- время в игровых секундах, на "устаревание" сессии
local PASSWORDLEN = 4             -- длина пароля
local PASSWORDATT = 5             -- число попыток на ввод пароля
local CHARGERSIDE = sides.bottom  -- с какой стороны зарядник
local CHARGERPOWER = 1            -- c какой силой сигналить =)
local REALTIME = true             -- использовать ли в логах реальное время
local TIMEZONE = 1                -- часовой пояс по Гринвичу
local VIRTUALCB =  'virtual-CB-address'
local SUPERVISOR = 'supervisor-address'
local KEY  = 'secret-access-key-1'
local KEY2 = 'secret-access-key-2'

-- переменные (и программно-определяемые константы)
local ID = 1                            -- ID терминала
local POS = {X = 0, Y = 0, Z = 0}       -- позиция звука
local VOLUME = 1.0                      -- громкость звука
local TONALITY = 1.0                    -- тональность звука
local RADIUS = 5                        -- радиус слышимости звука
local MAXPACKET = modem.maxPacketSize() -- максимальный размер пакета для передачи по сети
local TERMINAL = ""                     -- адрес терминала
local INVSIZE = 0                       -- размер инвентаря
local time_offset = TIMEZONE * 60 * 60  -- для логов
local session = {}                      -- данные по текущей сессии


-- ================================= N E T ================================= --
-- функция для получения данных от сетевой платы address
-- данные должны быть помечены словом word
function from(address, word)
  while true do
    local name, a, sender, _, _, message, data = event.pull(NETTIMEOUT, "modem_message")
    if name ~= nil then
      if sender == address then
        if message == word then
          return true, data
        end
      end
    else
      return false
    end
  end
end

-- переопределение для использования "виртуального КБ"
function runCommand(command)
  modem.send(VIRTUALCB, PORT, 'netcb', command)
end
function becGive(nickname, id, metadata, size, maxSize)
  local codename = id
  -- TODO: избавиться от костыля
  -- отрезали лишнее (+костыль для досок)
  -- if codename == "minecraft:planks" then
  --   codename = "5"
  -- elseif codename:sub(1,10) == "minecraft:" then
  --   codename = codename:sub(11, -1)
  -- end
  -- -- выдаем стеками
  -- local max = maxSize
  -- if max == nil then max = 1 end
  -- local amount = size
  -- while true do
  --   -- если размер позволяет - выдаем все сразу
  --   if amount <= max then
  --     runCommand("bec give "..nickname.." "..codename.." "..amount.." "..metadata)
  --     break
  --   end
  --   -- иначе - выдаем один стак, и смотрим дальше
  --   runCommand("bec give "..nickname.." "..codename.." "..max.." "..metadata)
  --   amount = amount - max
  -- end

  -- чистый вывод без всяких костылей
  runCommand("bec give "..nickname.." "..codename.." "..size.." "..metadata)
end


-- ================================ L O G S ================================ --
-- логирование событий в файл на жестком, в реальном времени
-- по дефолту - в папку logs
function toLog(message, nickname)
  local nickname = nickname or session.name or 'system'
  -- записываем в файл
  local name = 'logs/total.log'
  local file = nil
  --if fs.exists(name) then
  --  file = io.open(name, 'a')
  --else
  -- пока жестко на запись, костыль
  file = io.open(name, 'w')
  --end
  local date
  if REALTIME then
    -- закрываем файл total.log
    file:close()
    -- получаем время
    local lm = string.sub(fs.lastModified(name), 1, -4)
    local nm = tonumber(lm) + time_offset
    local dt = os.date("*t", nm)
    date = dt.day..'.'..dt.month..'.'..dt.year..'/'..dt.hour..':'..dt.min
    -- проверка существования подходящей папки
    if not fs.exists("logs/"..nickname) then
      fs.makeDirectory("logs/"..nickname)
    end
    -- открываем новый файл
    name = 'logs/'..nickname..'/'..dt.day..'_'..dt.month..'_'..dt.year..'.txt'
    file = nil
    if fs.exists(name) then
      file = io.open(name, 'a')
    else
      file = io.open(name, 'w')
    end
  else
    date = os.date()
  end
  local logtext = date..' | '..message
  file:write(logtext..'\r\n')
  file:close()
  -- принтим сообщение в консоль
  print(logtext)
end


-- ============================= S H A - 2 5 6 ============================= --
--  
--  Adaptation of the Secure Hashing Algorithm (SHA-244/256)
--  Found Here: http://lua-users.org/wiki/SecureHashAlgorithm
--  
--  Using an adapted version of the bit library
--  Found Here: https://bitbucket.org/Boolsheet/bslf/src/1ee664885805/bit.lua
--  
local MOD = 2^32
local MODM = MOD-1
 
local function memoize(f)
  local mt = {}
  local t = setmetatable({}, mt)
  function mt:__index(k)
    local v = f(k)
    t[k] = v
    return v
  end
  return t
end
 
local function make_bitop_uncached(t, m)
  local function bitop(a, b)
    local res,p = 0,1
    while a ~= 0 and b ~= 0 do
      local am, bm = a % m, b % m
      res = res + t[am][bm] * p
      a = (a - am) / m
      b = (b - bm) / m
      p = p*m
    end
    res = res + (a + b) * p
    return res
  end
  return bitop
end
 
local function make_bitop(t)
  local op1 = make_bitop_uncached(t,2^1)
  local op2 = memoize(function(a) return memoize(function(b) return op1(a, b) end) end)
  return make_bitop_uncached(op2, 2 ^ (t.n or 1))
end
 
local bxor1 = make_bitop({[0] = {[0] = 0,[1] = 1}, [1] = {[0] = 1, [1] = 0}, n = 4})
 
local function bxor(a, b, c, ...)
  local z = nil
  if b then
    a = a % MOD
    b = b % MOD
    z = bxor1(a, b)
    if c then z = bxor(z, c, ...) end
    return z
  elseif a then return a % MOD
  else return 0 end
end
 
local function band(a, b, c, ...)
  local z
  if b then
    a = a % MOD
    b = b % MOD
    z = ((a + b) - bxor1(a,b)) / 2
    if c then z = bit32_band(z, c, ...) end
    return z
  elseif a then return a % MOD
  else return MODM end
end
 
local function bnot(x) return (-1 - x) % MOD end
 
local function rshift1(a, disp)
  if disp < 0 then return lshift(a,-disp) end
  return math.floor(a % 2 ^ 32 / 2 ^ disp)
end
 
local function rshift(x, disp)
  if disp > 31 or disp < -31 then return 0 end
  return rshift1(x % MOD, disp)
end
 
local function lshift(a, disp)
  if disp < 0 then return rshift(a,-disp) end
  return (a * 2 ^ disp) % 2 ^ 32
end
 
local function rrotate(x, disp)
  x = x % MOD
  disp = disp % 32
  local low = band(x, 2 ^ disp - 1)
  return rshift(x, disp) + lshift(low, 32 - disp)
end
 
local k = {
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
  0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
  0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
  0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
  0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
  0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
 
local function str2hexa(s)
  return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end))
end
 
local function num2s(l, n)
  local s = ""
  for i = 1, n do
    local rem = l % 256
    s = string.char(rem) .. s
    l = (l - rem) / 256
  end
  return s
end
 
local function s232num(s, i)
  local n = 0
  for i = i, i + 3 do n = n*256 + string.byte(s, i) end
  return n
end
 
local function preproc(msg, len)
  local extra = 64 - ((len + 9) % 64)
  len = num2s(8 * len, 8)
  msg = msg .. "\128" .. string.rep("\0", extra) .. len
  assert(#msg % 64 == 0)
  return msg
end
 
local function initH256(H)
  H[1] = 0x6a09e667
  H[2] = 0xbb67ae85
  H[3] = 0x3c6ef372
  H[4] = 0xa54ff53a
  H[5] = 0x510e527f
  H[6] = 0x9b05688c
  H[7] = 0x1f83d9ab
  H[8] = 0x5be0cd19
  return H
end
 
local function digestblock(msg, i, H)
  local w = {}
  for j = 1, 16 do w[j] = s232num(msg, i + (j - 1)*4) end
  for j = 17, 64 do
    local v = w[j - 15]
    local s0 = bxor(rrotate(v, 7), rrotate(v, 18), rshift(v, 3))
    v = w[j - 2]
    w[j] = w[j - 16] + s0 + w[j - 7] + bxor(rrotate(v, 17), rrotate(v, 19), rshift(v, 10))
  end

  local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
  for i = 1, 64 do
    local s0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
    local maj = bxor(band(a, b), band(a, c), band(b, c))
    local t2 = s0 + maj
    local s1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
    local ch = bxor (band(e, f), band(bnot(e), g))
    local t1 = h + s1 + ch + k[i] + w[i]
    h, g, f, e, d, c, b, a = g, f, e, d + t1, c, b, a, t1 + t2
  end

  H[1] = band(H[1] + a)
  H[2] = band(H[2] + b)
  H[3] = band(H[3] + c)
  H[4] = band(H[4] + d)
  H[5] = band(H[5] + e)
  H[6] = band(H[6] + f)
  H[7] = band(H[7] + g)
  H[8] = band(H[8] + h)
end
function sha256(msg)
  msg = preproc(msg, #msg)
  local H = initH256({})
  for i = 1, #msg, 64 do digestblock(msg, i, H) end
  return str2hexa(num2s(H[1], 4) .. num2s(H[2], 4) .. num2s(H[3], 4) .. num2s(H[4], 4) ..
          num2s(H[5], 4) .. num2s(H[6], 4) .. num2s(H[7], 4) .. num2s(H[8], 4))
end
function shortsha(msg)
  return sha256(msg):sub(1,40)
end


-- ============================== P R I C E S ============================== --
-- функция получения прайсов с интернета
local prices = {}

function get(url)
  -- делаем запрос
  local request, reason = inet.request(url)
  -- если нет ответа - возвращаем nil
  if not request then return '' end

  -- если ответ есть - читаем данные
  local text = ''
  while true do
    local data, reason = request.read()
    if not data then 
      request.close()
      break
    elseif #data > 0 then
      text = text..data
    end
  end
  return text
end

function loadPrices(fromnet)
  local text = ''
  local fromnet = fromnet
  if fromnet == nil then fromnet = true end

  if fromnet then
    -- читаем таблицу с Pastebin
    text = get("http://pastebin.com/raw.php?i="..PRICESPAGE)
    if text ~= '' then
      -- сохраняем все на диск
      local file = io.open(PRICESFILE, 'w')
      file:write(text)
      file:close()
    else
      fromnet = false
    end
  end
  if not fromnet then
    if fs.exists(PRICESFILE) then
      local file = io.open(PRICESFILE, "r")
      text = file:read("*a")
      file:close()
    end
  end
  -- парсим данные
  parsePrices(text)
end

function parsePrices(text)
  prices = {}
  prices.enchants = {}
  prices.hash = ''
  prices.markup = DEFAULTMARKUP
  local part = 0  -- 0 = markup;  1 = items;  2 = enchantments;  3 = energy;  4 = killing
  -- поехали парсить строки
  for line in text:gmatch("[^\r\n]+") do
    -- если строка не пуста
    if string.len(line) > 0 and not line:match("^%s+$") then
      local first = line:sub(1,1)
      -- если строка - не комментарий
      if first ~= '#' then
        -- читаем таймштамп
        if first == '@' then
          prices.hash = line
        -- читаем заголовки
        elseif first == '[' then
          if line == '[MARKUP]' then
            part = 0
          elseif line == '[ITEMS]' then
            part = 1
          elseif line == '[ENCHANTMENTS]' then
            part = 2
          elseif line == '[ENERGY]' then
            part = 3
          else
            part = 4
          end
        -- читаем строки прайса
        else
          -- читаем наценку
          if part == 0 then
            -- экранируем пустые строки
            local markup = tonumber(line)
            if markup ~= nil then
              prices.markup = markup
            end
          -- читаем прайсы на предметы
          elseif part == 1 then
            local id, metadata, stack, sell, buy, UU, name = line:match("([%d%a:_.-]+)#?(%d*)%s+(%d+)%s+(-?%d+)%s+(-?%d*)%s*(%d*)%s*(.+)")
            local price = {}
            price.id = id
            price.metadata = tonumber(metadata)
            if price.metadata == nil then price.metadata = 0 end
            price.stackSize = tonumber(stack)
            price.sell = tonumber(sell)
            price.buy = tonumber(buy)
            if price.buy == nil or price.buy == 0 then
              -- если в продаже нет - значит нет
              if price.sell ~= -1 then
                price.buy = math.ceil(price.sell * (1-prices.markup))
              else
                price.buy = -1
              end
            end
            price.UU = tonumber(UU)
            if price.UU == nil then price.UU = 0 end
            price.name = name
            table.insert(prices, price)
          -- читаем прайсы на энчанты
          elseif part == 2 then
            if first == '?' then
              local last = #prices.enchants
              if last > 0 then
                if prices.enchants[last].description == nil then
                  prices.enchants[last].description = string.sub(line, 2, -1)
                else
                  prices.enchants[last].description = prices.enchants[last].description..'\n'..line
                end
              end
            elseif first == '!' then
              local last = #prices.enchants
              if last > 0 then
                if prices.enchants[last].comment == nil then
                  prices.enchants[last].comment = string.sub(line, 2, -1)
                else
                  prices.enchants[last].comment = prices.enchants[last].comment..'\n'..line
                end
              end
            else
              local enchant = {}
              local class, id, level, price, name = line:match("(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(.+)")
              enchant.class = tonumber(class)
              enchant.id = tonumber(id) 
              enchant.level = tonumber(level)
              enchant.price = tonumber(price)
              enchant.name = name

              table.insert(prices.enchants, enchant)
            end
          -- читаем цены на энергию
          elseif part == 3 then
            prices.energy = tonumber(line)
            if prices.energy == nil then prices.energy = 0 end
          end
        end
      end
    end
  end
end

-- функция получения одной записи из таблицы прайсов
function getPrice(id, metadata)
  for i=1, #prices do
    if prices[i].id == id and prices[i].metadata == metadata then
      return prices[i]
    end
  end
  return {id = id, metadata = metadata, sell = -1, buy = -1, name = id..":"..metadata, maxSize = 1}
end


local updateTime = computer.uptime()
function updatePricesTable()
  toLog("Price table updated!", "system")
  loadPrices(true)
end

-- посылаем таблицу прайсов терминалу фрагментами
function sendPrices()
  --for i=1, #prices do
  --  modem.send(TERMINAL, PORT, "prices", "items", serial.serialize(prices[i]))
  --end
  --for t=1, #prices.enchants do
  --  modem.send(TERMINAL, PORT, "prices", "enchants", serial.serialize(prices.enchants[i]))
  --end
  local data = serial.serialize(prices)
  local i = 0
  local size = MAXPACKET - 10
  while true do
    local packet = string.sub(data, (i*size)+1, (i+1)*size)
    if packet == '' then break end
    modem.send(TERMINAL, PORT, "prices", packet)
    i = i + 1
  end
  modem.send(TERMINAL, PORT, "prices", "end")
end


-- =============================== I T E M S =============================== --
local items = {}

-- инспектируем внутренний инвентарь и записываем содержимое в таблицу items
function getItemList()
  for i=1, INVSIZE do
    local stack = icontroller.getStackInInternalSlot(i)
    if stack == nil then break end
    -- заносим количество предметов в таблицу
    if items.raw[stack.name] == nil then
      -- заводим раздел под новый internal name
      items.raw[stack.name] = {}
    end
    if items.raw[stack.name][stack.damage] == nil then
      -- записываем для каждого нового предмета его название, и макс. размер стака,
      -- инициализируем счетчик количества и пишем его как "для продажи"
      -- общая стоимость пока будет равна 0
      items.raw[stack.name][stack.damage] = {size = 0, name = stack.label,
        id = stack.name, metadata = stack.damage,
        stackSize = stack.maxSize, enabled = true, total = 0, totalUU = 0}
    end
    items.raw[stack.name][stack.damage].size = items.raw[stack.name][stack.damage].size + stack.size
  end
end

-- едем к сундуку и все в него сбрасываем
function unload()
  -- переместились
  --robot.back()   -- это если сундук стоит подальше
  robot.up()
  robot.turnAround()
  -- выкинули
  for i=1, INVSIZE do
    if robot.count(i) > 0 then
      robot.select(i)
      robot.drop()
    end
  end
  -- вернулись к кассе
  robot.turnAround()
  robot.down()
  --robot.forward()
end

-- забираем все из лотка и заносим в items
function grabPurchases(add)
  -- огоньки (желтый - "выполнение операций")
  robot.setLightColor( 0xffdb00)
  -- обновление списка (если не было команды на добавление)
  if add ~= true then
    clearItems()
  end
  -- все засосали
  robot.select(1)
  if magnet.suck() then
    while magnet.suck() do 
      if robot.count(INVSIZE) > 0 then
        getItemList()
        unload()
      end
    end
    getItemList()
    unload()
  end
  -- огоньки (голубой - "готов к работе")
  robot.setLightColor( 0x0092ff)
  -- генерация "оглавления" к списку товаров
  -- обнуляем на "всякий пожарный"
  items.table = {}
  items.total = 0
  items.totalUU = 0
  local logtext = "List:"
  -- сканируем данные
  for a,b in pairs(items.raw) do
    local id = a
    for c, itemstack in pairs(b) do
      local metadata = c
      local price = getPrice(id, metadata)

      if price.buy ~= -1 then
        -- если товар продается, и он есть в прайсах,
        -- то заполним название предмета и тотальную стоимость
        itemstack.name = price.name
        itemstack.total = price.buy * itemstack.size
        itemstack.totalUU = price.UU * itemstack.size
        -- общая стоимость всех предметов тоже растет
        items.total = items.total + itemstack.total
        items.totalUU = items.totalUU + itemstack.totalUU
      else
        -- если же товар не продается, то помечаем его 
        -- как "не продаваемый" - enabled = false
        itemstack.enabled = false
      end
      -- заносим ссылку на стек в "оглавление"
      table.insert(items.table, itemstack)
      -- добавляем строчку в лог
      logtext = logtext.."\r\n - Item: "..itemstack.name..', Size='..itemstack.size.." ($"..itemstack.total.." / UU "..itemstack.totalUU..")"
    end
  end
  toLog(logtext)
  -- отдаем
  return items
end

-- возвращаем все предметы клиенту (отмена продажи)
function giveItems()
  -- перебираем все предметы
  for a,b in pairs(items.raw) do
    local id = a
    for c, itemstack in pairs(b) do
      local metadata = c
      local size = itemstack.size
      local maxSize = itemstack.stackSize
      -- выдаем предметы через команду консоли
      becGive(session.name, id, metadata, size, maxSize)
    end
  end
  -- очищаем таблицу
  clearItems()
end


-- возвращаем то, что продать не получится
function giveNonSellable(givelist)
  logtext = "List:"
  for i=1, #givelist.table do
    local itemstack = givelist.table[i]
    -- если предмет не продается
    if not itemstack.enabled then
      -- проверяем, есть ли такой предмет в списке
      if items.raw[itemstack.id][itemstack.metadata] ~= nil then
        -- выдаем предметы через команду консоли
        becGive(session.name, itemstack.id, itemstack.metadata, itemstack.size, itemstack.maxSize)
        -- вычитаем из общей стоимости
        items.total = items.total - itemstack.total
        items.totalUU = items.totalUU - itemstack.totalUU
        -- добавляем в лог
        logtext = logtext.."\r\n - Item: "..itemstack.name..', Size='..itemstack.size.." ($"..itemstack.total.." / UU "..itemstack.totalUU..")"
        -- стираем из "оглавления"
        for x, y in pairs(items.table) do
          if y == items.raw[itemstack.id][itemstack.metadata] then
            table.remove(items.table, x)
            break
          end
        end
        -- стираем из списка предметов
        items.raw[itemstack.id][itemstack.metadata] = nil
      end
    end
  end
  toLog(logtext)
end

-- чистим таблицу
function clearItems()
  items = {}
  items.raw = {}
  items.table = {}
  items.total = 0
  items.totalUU = 0
end

-- выдаем игроку покупки
function sellItems(id, metadata, amount, maxSize)
  becGive(session.name, id, metadata, amount, maxSize)
end


-- =============================== M O N E Y =============================== --
function getMoney(nickname)
  return tonumber(get('http://computercraft.ru/ccbalanceupd.php?type=balance&auth='..KEY..'&nick='..nickname..'&action=get'))
end
function addMoney(nickname, amount)
  return get('http://computercraft.ru/ccbalanceupd.php?type=balance&auth='..KEY..'&nick='..nickname..'&action=add&value='..amount)
end

function getUU(nickname)
  return tonumber(get('http://computercraft.ru/ccbalanceupd.php?type=voice&auth='..KEY..'&nick='..nickname..'&action=get'))
end
function addUU(nickname, amount)
  return get('http://computercraft.ru/ccbalanceupd.php?type=voice&auth='..KEY..'&nick='..nickname..'&action=add&value='..amount)
end

-- перечисляем деньги со счета на счет
function transferMoney(addressee, amount)
  local money_from = getMoney(session.name)
  local money_to   = getMoney(addressee)

  if amount == nil or amount < MINTRANSFER or amount > MAXTRANSFER then
    return "wrong amount"
  end
  if money_to == nil then
    return "wrong addressee"
  end
  if money_from < (amount + math.ceil(amount*TRANSFERCOMM)) then 
    return "no money"
  end

  -- если все проверки пройдены, значит подвоха нет
  -- адресату начисляем
  addMoney(addressee, amount)
  -- игроку уменьшаем
  addMoney(session.name, -(amount + math.ceil(amount*TRANSFERCOMM)))

  return "good deal"
end

-- зачарование предмета
function enchantItem(index, level)
  local enchantment = prices.enchants[index]
  local price = enchantment.price * level
  local UU = getUU(session.name)

  -- неудача
  if price > UU then return "no money" end

  -- запускаем команду на зачарование
  runCommand("enchant "..session.name..' '..enchantment.id..' '..level)
  -- снимаем тугрики со счета
  addUU(session.name, -price)

  -- успех
  return "good deal"
end


-- ============================ S E S S I O N S ============================ --
function getSessionStamp(nickname)
  return get('http://computercraft.ru/ccbalanceupd.php?action=get&nick='..nickname..'&type=banksession&auth='..KEY2)
end
function setSessionStamp(nickname, stamp)
  return get('http://computercraft.ru/ccbalanceupd.php?action=set&nick='..nickname..'&type=banksession&value='..stamp..'&auth='..KEY2)
end

function antiMultisessionCheck(sequence)
  if sequence == 'off' then return true end
  
  local timestamp = tonumber(sequence)
  if timestamp == nil then return true end

  local currenttime = os.time()
  if math.abs(currenttime - timestamp) > SESSIONTIME then return true end

  return false
end

-- геттим время последнего визита
function getLastVisitTime(nickname)
  return get('http://computercraft.ru/ccbalanceupd.php?action=get&nick='..nickname..'&type=paytime&auth='..KEY)
end


-- гетим/сетим хеши паролей в БД
function getPassHash(nickname)
  return get('http://computercraft.ru/ccbalanceupd.php?action=get&nick='..nickname..'&type=passhash&auth='..KEY2)
end
function setPassHash(nickname, hash)
  return get('http://computercraft.ru/ccbalanceupd.php?action=set&nick='..nickname..'&type=passhash&value='..hash..'&auth='..KEY2)
end

-- генерилка паролей
function genPass(len)
 local temp, cod = '',''
 local select 
  for i = 1, len do
   select = math.random(1, 3)
   if select == 1 then
    temp = string.char(math.random(48,57))
   elseif select == 2 then
    temp = string.char(math.random(65,90))
   elseif select == 3 then
    temp = string.char(math.random(97,122))  
   end
   cod = cod..temp 
  end
  return cod
end

function sendPassToUser(nickname, password)
  runCommand("tell "..nickname.." Вас приветствует [Totoro Bank]! Ваш личный пароль: "..password)
  runCommand("mail send "..nickname.." Вас приветствует [Totoro Bank]. Ваш личный пароль: "..password)
  runCommand("mail send "..nickname.." Внимание! Никогда и никому не передавайте свой пароль!")
end

function newPasswordForUser()
  local pass = genPass(PASSWORDLEN)
  local hash = shortsha(pass)
  session.hash = hash
  setPassHash(session.name, hash)
  sendPassToUser(session.name, pass)
end


-- ================================ I N I T ================================ --
function getPairID(filename)
  if fs.exists(filename) then
    local file = io.open(filename, 'r')
    local line = file:read("*l")
    local cb_mac = file:read("*l")
    file:close()
    if line ~= nil then
      ID = tonumber(line:match("ID%s*=%s*(%d+)"))
      -- если ID получен, то возвращаем успех
      if ID ~= nil then 
        VIRTUALCB = cb_mac:match("CB%s*=%s*(.+)")
        if VIRTUALCB ~= nil then
          return true 
        end
      end
    end
  end
  -- если попытка получить ID не увенчалась успехом, запишем ID=1
  local file = io.open(filename, 'w')
  file:write("ID = 1\nCB = 646d3443-cbb1-4bfd-87b7-51267d4203e3")
  file:close()
  ID = 1
  VIRTUALCB = '646d3443-cbb1-4bfd-87b7-51267d4203e3'
  return false
end


-- ================================ M A I N ================================ --
-- инициализация
-- огоньки (красный - "инициализация")
robot.setLightColor( 0xff0000)
-- создаем папку для логов
if not fs.exists("logs") then
  fs.makeDirectory("logs")
end
-- ищем и читаем ID
getPairID('bank.ini')
-- определяем объем инвентаря
INVSIZE = robot.inventorySize()
-- готовим таблицу для продажи
clearItems()
-- грузим прайсы c Pastebin
print("Загрузка прайсов...")
loadPrices(true)
-- пингуем супервайзера, чтобы не спал
modem.send(SUPERVISOR, PORT, "teller", ID, fs.proxy("OpenOS").address)
-- открываем порт
modem.open(PORT)
-- посылаем сигнал на зарядник
red.setOutput(CHARGERSIDE, CHARGERPOWER)
-- огоньки (голубой - "готов к работе")
robot.setLightColor( 0x0092ff)
-- статус
print("Ожидаю команд...")
print("Робот не привязан к кабинке. Первое сетевое сообщение привяжет его.")

-- обработка событий
while true do
  local name, add, sender, _, _, message, data, data2, data3 = event.pull(10)
  if name == 'modem_message' then
    -- неавторизованные сообщения
    if message == 'robot-ping' then
      if data == ID then
        modem.send(sender, PORT, "robot-gotit")
        -- если робот был свободен - привязываем его к терминалу
        if TERMINAL == "" then 
          toLog("Linked to: "..sender:sub(1,8), "system")
          TERMINAL = sender 
        end
      end
    end

    -- авторизованные: никаких посторонних адресов, только терминал или супервайзер
    if sender == SUPERVISOR then
      -- супервайзер дает команду на перезагрузку
      if message == "shutdown" then
        toLog("Superviser: shutdown!")
        break
      -- супервайзер требует обновить цены
      elseif message == "pricesupd" then
        toLog("Superviser: get new prices, now!")
        updatePricesTable()
        updateTime = computer.uptime()
      end
    elseif sender == TERMINAL then
      -- захват предметов и подсчет
      if message == "signin" then
        toLog("SignIn: "..data, data)
        -- если пришел сигнал на логин, значит незакрытых сессий нет
        -- создаем новую
        -- пока кроме имени и счета тут хранить нечего =)
        session = {}
        session.logged = false
        session.fails = 0

        -- проверяем на мульти-сессии
        local oldsession = getSessionStamp(data)
        
        -- TODO - разобраться с глюками проверки на мультисессии
        --if antiMultisessionCheck(oldsession) then
        if true then
          session.name = data
          session.money = getMoney(session.name)
          session.UU = getUU(session.name)
          session.lastvisit = getLastVisitTime(session.name)
          -- если получение счета прошло неудачно, значит логин не пройдет тоже
          if session.money == nil or session.UU == nil then
            toLog("[ERROR] Cannot get balance!")
            modem.send(TERMINAL, PORT, "signin", nil)
          else
            -- проверяем хеш пароля
            session.hash = getPassHash(session.name)
            -- если хеш слишком короткий
            if string.len(session.hash) < 10 then 
              newPasswordForUser()
            elseif string.len(session.hash) ~= 40 then
              -- если вместо нормального хеша в 40 символов
              -- мы получаем какую-то муру, значит с логином проблемы
              toLog("[ERROR] Hash problems!")
              modem.send(TERMINAL, PORT, "signin", nil)
            end
            -- если с паролем все нормально, то разрешаем логин
            if string.len(session.hash) == 40 then
              -- подтверждаем логин терминалу
              modem.send(TERMINAL, PORT, "signin", true)
              -- очищаем список предметов со старой сессии (на всякий пожарный)
              clearItems()
            end
          end
        else
          modem.send(TERMINAL, PORT, "signin", false)
        end
      elseif message == "password" then
        local hash = shortsha(data)
        if hash == session.hash then
          -- отсылаем таблицу сессии терминалу
          modem.send(TERMINAL, PORT, "password", serial.serialize(session))
          -- посылаем время открытия сессии в БД сервера
          --session.time = tostring(os.time()):sub(-6, -1)
          --setSessionStamp(session.name, session.time)
          -- логин подтвержден
          session.logged = true
        else
          if session.fails < PASSWORDATT then
            modem.send(TERMINAL, PORT, "password", false)
            session.fails = session.fails + 1
          else
            modem.send(TERMINAL, PORT, "password", nil)
            session.fails = 0
          end
        end
      elseif message == "forgot" then
        -- юзер забыл пароль, ай-яй-яй
        newPasswordForUser()
      end

      -- следующие пакеты обрабатываются ТОЛЬКО после подтверждения пароля
      if session.logged then
        if message == "signout" then
          -- если не произошло ошибки (мало ли)
          if session.name ~= nil then
            toLog("SignOut: "..session.name..'\r\n')
            -- посылаем знак, что сессия закрыта в БД сервера
            setSessionStamp(session.name, "off")
            -- чистим таблицу
            session = {}
          end

        elseif message == "prices" then
          -- отправляем терминалу табличку с ценами
          sendPrices()

        elseif message == "new-prices" then
          -- получили новые прайсы от сервера
          prices = serial.unserialize(data)

        elseif message == "grab" then
          toLog("Grab request (add="..tostring(data).."). ("..session.name..")")
          -- захват и подсчет
          grabPurchases(data)
          -- отдаем данные
          modem.send(TERMINAL, PORT, "items", serial.serialize(items))

        elseif message == "grab-cancel" then
          toLog("Return all items. ("..session.name..")")
          -- выдаем предметы игроку на руки
          giveItems()

        elseif message == "grab-surplus" then
          toLog("Return selected items. ("..session.name..")")
          -- возвращаем игроку то, что не продается
          local givelist = serial.unserialize(data)
          giveNonSellable(givelist)

        elseif message == "grab-sell" then
          toLog("Sell request. ("..session.name..")")
          -- отсылаем терминалу результат "сделки"
          modem.send(TERMINAL, PORT, "sell", items.total, items.totalUU)
          -- сохраняем изменения счета
          addMoney(session.name, items.total)
          addUU(session.name, items.totalUU)
          -- очищаем таблицу
          clearItems()

        elseif message == "buy" then
          -- сколько и чего
          local price = getPrice(data, data2)
          local size = data3
          local maxSize = price.stackSize
          -- если предмет продается
          if price.sell ~= -1 then
            local total = price.sell * size
            local totalUU = price.UU * size
            --
            toLog("Buy request. ("..session.name..")\r\n - Item: ID="..data..', Meta='..data2..', Size='..data3.." ($"..total.." / UU "..totalUU..")")
            --
            local money = getMoney(session.name)
            local UU = getUU(session.name)
            if money == nil or UU == nil then
              -- неведомый глюк
              modem.send(TERMINAL, PORT, "deal", "wtf")
              toLog("[ERROR] Unknown error!")
            elseif total > money or totalUU > UU then
              -- слишком мало денег
              modem.send(TERMINAL, PORT, "deal", "hands off")
              toLog("[FALSE] Not enough money! ($"..session.money.." / UU "..session.UU..")")
            else
              -- высылаем товар
              sellItems(data, data2, size, maxSize)
              -- успешная продажа
              modem.send(TERMINAL, PORT, "deal", money-total, UU-totalUU)
              -- снимаем деньги со счета
              addMoney(session.name, -total)
              -- снимаем тугрики со счета
              addUU(session.name, -totalUU)
            end
          else
            -- предмет не продается
            modem.send(TERMINAL, PORT, "deal", "no way")
            toLog("[FALSE] Item is not for sale!")
          end

        elseif message == "transfer" then
          toLog("Transfer request. ("..session.name.."->"..data..", $"..data2..")")
          -- перевод денег со счета на счет
          local addressee = data
          local amount = tonumber(data2)
          local result = transferMoney(addressee, amount)
          modem.send(TERMINAL, PORT, "transfer", result)

        elseif message == 'enchant' then
          toLog("Enchant request. ("..session.name..")\n - Enchant: ID="..data..", Level="..data2)
          -- зачарование предметов
          local index = tonumber(data)
          local level = tonumber(data2)
          local result = enchantItem(index, level)
          modem.send(TERMINAL, PORT, "enchant", result)

        elseif message == 'energy' then
          -- накачка энергии
          local level = tonumber(data)
          local price = math.ceil(prices.energy * level)
          -- логируем
          toLog("Energy request. ("..session.name..", "..level.." EU / $"..price..")")
          --
          session.money = getMoney(session.name)
          if session.money >= price then
            session.money = session.money - price
            modem.send(TERMINAL, PORT, "energy", "good deal", session.money)
            addMoney(session.name, -price)
          else
            modem.send(TERMINAL, PORT, "energy", "no money", session.money)
            toLog("[FALSE] Not enough money! ($"..session.money.." / UU "..session.UU..")")
          end
        end
      end
    end

  -- по нажатию любой кнопки, программа "кассира" останавливается
  elseif name == 'key_down' then break end

  -- проверяем цены на Pastebin если надо
  if (computer.uptime() - updateTime) > PRICESUPDATE then
    updatePricesTable()
    updateTime = computer.uptime()
  end
end

-- выключаем сигнал на зарядник
red.setOutput(CHARGERSIDE, 0)
-- закрываем порты
modem.close(PORT)
-- огоньки (красный - "завершение")
robot.setLightColor( 0xff00a0)
-- все
