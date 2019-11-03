--local component = require('component') -- подгрузить обертку из OpenOS
--local computer = require('computer')
local chunks = 9 -- количество чанков для добычи
local min, max = 2.2, 40 -- минимальная и максимальная плотность
local port = 1 -- порт для взаимодействия с роботом
local X, Y, Z, D, border = 0, 0, 0, 0 -- переменные локальной системы координат
local steps, turns = 0, 0 -- debug
local WORLD = {x = {}, y = {}, z = {}} -- таблица меток
local E_C, W_R = 0, 0 -- энергозатраты на один шаг и скорость износа

local function arr2a_arr(tbl) -- преобразование списка в ассоциативный массив
  for i = #tbl, 1, -1 do
   tbl[tbl[i]], tbl[i] = true, nil
  end
end

local quads = {{-7, -7}, {-7, 1}, {1, -7}, {1, 1}}
local workbench = {1,2,3,5,6,7,9,10,11}
local wlist = {'enderstorage:ender_storage'}
local fragments = {'redstone','coal','dye','diamond','emerald'}
local tails = {'cobblestone','granite','diorite','andesite','marble','limestone','dirt','gravel','sand','stained_hardened_clay','sandstone','stone','grass','end_stone','hardened_clay','mossy_cobblestone','planks','fence','torch','nether_brick','nether_brick_fence','nether_brick_stairs','netherrack','soul_sand'}
arr2a_arr(wlist)
arr2a_arr(fragments)
arr2a_arr(tails)

local function add_component(name) -- получение прокси компонента
  name = component.list(name)() -- получить адрес по имени
  if name then -- если есть адрес
    return component.proxy(name) -- вернуть прокси
  end
end

-- загрузка компонентов --
local controller = add_component('inventory_controller')
local chunkloader = add_component('chunkloader')
local generator = add_component('generator')
local crafting = add_component('crafting')
local geolyzer = add_component('geolyzer')
local tunnel = add_component('tunnel')
local modem = add_component('modem')
local robot = add_component('robot')
local inventory = robot.inventorySize()
local energy_level, sleep, report, remove_point, check, step, turn, smart_turn, go, scan, calibration, sorter, home, main, solar, ignore_check, inv_check

energy_level = function()
  return computer.energy()/computer.maxEnergy()
end

sleep = function(timeout)
  local deadline = computer.uptime()+timeout
  repeat
    computer.pullSignal(deadline-computer.uptime())
  until computer.uptime() >= deadline
end

report = function(message, stop) -- рапорт о состоянии
  message = '|'..X..' '..Y..' '..Z..'|\n'..message..'\nenergy level: '..math.floor(energy_level()*100)..'%' -- добавить к сообщению координаты и уровень энергии
  if modem then -- если есть модем
    modem.broadcast(port, message) -- послать сообщение через модем
  elseif tunnel then -- если есть связанная карта
    tunnel.send(message) -- послать сообщение через нее
  end
  computer.beep() -- пикнуть
  if stop then -- если есть флаг завершения
    if chunkloader then
      chunkloader.setActive(false)
    end
    error(message,0) -- остановить работу программы
  end
end

remove_point = function(point) -- удаление меток
  table.remove(WORLD.x, point) -- удалить метку из таблицы
  table.remove(WORLD.y, point)
  table.remove(WORLD.z, point)
end

check = function(forcibly) -- проверка инструмента, батареи, удаление меток
  if not ignore_check and (steps%32 == 0 or forcibly) then -- если пройдено 32 шага или включен принудительный режим
    inv_check()
    local delta = math.abs(X)+math.abs(Y)+math.abs(Z)+64 -- определить расстояние
    if robot.durability()/W_R < delta then -- если инструмент изношен
      report('tool is worn')
      ignore_check = true
      home(true) -- отправиться домой
    end
    if delta*E_C > computer.energy() then -- проверка уровня энергии
      report('battery is low')
      ignore_check = true
      home(true) -- отправиться домой
    end
    if energy_level() < 0.3 then -- если энергии меньше 30%
      local time = os.date('*t')
      if generator and generator.count() == 0 and not forcibly then -- если есть генератор
        report('refueling solid fuel generators')
        for slot = 1, inventory do -- обойти инвентарь
          robot.select(slot) -- выбрать слот
          for gen in component.list('generator') do -- перебрать все генераторы
            if component.proxy(gen).insert() then -- попробовать заправиться
              break
            end
          end
        end
      elseif solar and geolyzer.isSunVisible() and -- проверить видимость солнца
        (time.hour > 4 and time.hour < 17) then -- проверить время
        while not geolyzer.canSeeSky() do -- пока не видно неба
          step(1, true) -- сделать шаг вверх без проверки
        end
        report('recharging in the sun')
        sorter(true)
        while (energy_level() < 0.98) and geolyzer.isSunVisible() do
          time = os.date('*t') -- время работы солнечной панели 05:30 - 18:30
          if time.hour >= 5 and time.hour < 19 then
            sleep(60)
          else
            break
          end
        end
        report('return to work')
      end
    end
  end
  if #WORLD.x ~= 0 then -- если таблица меток не пуста
    for i = 1, #WORLD.x do -- пройти по всем позициям
      if WORLD.y[i] == Y and ((WORLD.x[i] == X and ((WORLD.z[i] == Z+1 and D == 0) or (WORLD.z[i] == Z-1 and D == 2))) or (WORLD.z[i] == Z and ((WORLD.x[i] == X+1 and D == 3) or (WORLD.x[i] == X-1 and D == 1)))) then
        robot.swing(3)
        remove_point(i)
      end
      if X == WORLD.x[i] and (Y-1 <= WORLD.y[i] and Y+1 >= WORLD.y[i]) and Z == WORLD.z[i] then
        if WORLD.y[i] == Y+1 then -- добыть блок сверху, если есть
          robot.swing(1)
        elseif WORLD.y[i] == Y-1 then -- добыть блок снизу
          robot.swing(0)
        end
        remove_point(i)
      end
    end
  end
end

step = function(side, ignore) -- функция движения на 1 блок
  local result, obstacle = robot.swing(side) 
  if not result and obstacle ~= 'air' and robot.detect(side) then -- если блок нельзя разрушить
    home(true) -- запустить завершающую функцию
    report('insurmountable obstacle', true) -- послать сообщение
  else
    while robot.swing(side) do end -- копать пока возможно
  end
  if robot.move(side) then -- если робот сдвинулся, обновить координаты
    steps = steps + 1 -- debug
    if side == 0 then
      Y = Y-1
    elseif side == 1 then
      Y = Y+1
    elseif side == 3 then
      if D == 0 then
        Z = Z+1
      elseif D == 1 then
        X = X-1
      elseif D == 2 then
        Z = Z-1
      else
        X = X+1
      end
    end
  end
  if not ignore then
    check()
  end
end

turn = function(side) -- поворот в сторону
  side = side or false
  if robot.turn(side) and D then -- если робот повернулся, обновить переменную  направления
    turns = turns+1 -- debug
    if side then
      D = (D+1)%4
    else
      D = (D-1)%4
    end
    check()
  end
end

smart_turn = function(side) -- поворот в определенную сторону света
  while D ~= side do
    turn((side-D)%4==1)
  end
end

go = function(x, y, z) -- переход по указанным координатам
  if border and y < border then
    y = border
  end
  while Y ~= y do
    if Y < y then
      step(1)
    elseif Y > y then
      step(0)
    end
  end
  if X < x then
    smart_turn(3)
  elseif X > x then
    smart_turn(1)
  end
  while X ~= x do
    step(3)
  end
  if Z < z then
    smart_turn(0)
  elseif Z > z then
    smart_turn(2)
  end
  while Z ~= z do
    step(3)
  end
end

scan = function(xx, zz) -- сканирование квадрата x8 относительно робота
  local raw, index = geolyzer.scan(xx, zz, -1, 8, 8, 1), 1 -- получить сырые данные, установить индекс в начало таблицы
  for z = zz, zz+7 do -- развертка данных по z
    for x = xx, xx+7 do -- развертка данных по х
      if raw[index] >= min and raw[index] <= max then -- если обнаружен блок с подходящей плотностью
        table.insert(WORLD.x, X+x) --| записать метку в список
        table.insert(WORLD.y, Y-1) --| с коррекцией локальных
        table.insert(WORLD.z, Z+z) --| координат геосканера
      elseif raw[index] < -0.31 then -- если обнаружен блок с отрицательной плотностью
        border = Y -- сделать отметку
      end
      index = index + 1 -- переход к следующему индексу сырых даннх
    end
  end
end

calibration = function() -- калибровка при запуске
  if not controller then -- проверить наличие контроллера инвентаря
    report('inventory controller not detected', true)
  elseif not geolyzer then -- проверить наличие геосканера
    report('geolyzer not detected', true)
  elseif not robot.detect(0) then
    report('bottom solid block is not detected', true)
  elseif not robot.durability() then
    report('there is no suitable tool in the manipulator', true)
  end
  local clist = computer.getDeviceInfo()
  for i, j in pairs(clist) do
    if j.description == 'Solar panel' then
      solar = true
      break
    end
  end
  if chunkloader then -- если есть чанклоадер
    chunkloader.setActive(true) -- включить
  end
  if modem then -- если есть модем
    --modem.open(port)
    modem.setWakeMessage('') -- установить сообщение пробуждения
    modem.setStrength(400) -- установить силу сигнала
  elseif tunnel then -- если есть туннель
    tunnel.setWakeMessage('') -- установить сообщение пробуждения
  end
  for slot = 1, inventory do -- пройти по слотам инвентаря
    if robot.count(slot) == 0 then -- если слот пуст
      robot.select(slot) -- выбрать слот
      break
    end
  end
  local energy = computer.energy() -- получить уровень энергии
  step(0) -- сделать шаг
  E_C = math.ceil(energy-computer.energy()) -- записать уровень потребления
  energy = robot.durability() -- получить уровень износа/разряда инструмента
  while energy == robot.durability() do -- пока не обнаружена разница
    robot.place(3) -- установить блок
    robot.swing(3) -- разрушить блок
  end
  W_R = energy-robot.durability() -- записать результат
  local sides = {2, 1, 3, 0} -- линки сторон света, для сырых данных
  D = nil -- обнуление направления
  for s = 1, #sides do -- проверка всех направлений
    if robot.detect(3) or robot.place(3) then -- проверить наличие блока перед носом
      local A = geolyzer.scan(-1, -1, 0, 3, 3, 1) -- сделать первый скан
      robot.swing(3) -- сломать блок
      local B = geolyzer.scan(-1, -1, 0, 3, 3, 1) -- сделать второй скан
      for n = 2, 8, 2 do -- обойти смежные блоки в таблице
        if math.ceil(B[n])-math.ceil(A[n])<0 then -- если блок исчез
          D = sides[n/2] -- установить новое направление
          break -- выйти из цикла
        end
      end
    else
      turn() -- задействовать простой поворот
    end
  end
  if not D then
    report('calibration error', true)
  end
end

inv_check = function() -- инвентаризация
  if ignore_check then
    return
  end
  local items = 0
  for slot = 1, inventory do
    if robot.count(slot) > 0 then
      items = items + 1
    end
  end
  if inventory-items < 10 or items/inventory > 0.9 then
    while robot.suck(1) do end
    home(true)
  end
end

sorter = function(pack) -- сортировка лута
  robot.swing(0) -- освободить место для мусора
  robot.swing(1) -- освободить место для буфера
  ------- сброс мусора -------
  local empty, available = 0, {} -- создать счетчик пустых слотов и доступных для упаковки
  for slot = 1, inventory do -- пройти по слотам инвентаря
    local item = controller.getStackInInternalSlot(slot) -- получить информацию о предмете
    if item then -- если есть предмет
      local name = item.name:gsub('%g+:', '')
      if tails[name] then -- проверить на совпадение в списке отходов
        robot.select(slot) -- выбрать слот
        robot.drop(0) -- выбросить к отходам
        empty = empty + 1 -- обновить счетчик
      elseif fragments[name] then -- если есть совпадение в списке фрагментов
        if available[name] then -- если уже создан счетчик
          available[name] = available[name] + item.size -- обновить количество
        else -- иначе
          available[name] = item.size -- задать счетчик для имени
        end
      end
    else -- обнаружен пустой слот
      empty = empty + 1 -- обновить счетчик
    end
  end
  -- упаковка предметов в блоки --
  if crafting and (empty < 12 or pack) then -- если есть верстак и меньше 12 свободных слотов или задана принудительная упаковка
    -- перенос лишних предметов в буфер --
    if empty < 10 then -- если пустых слотов меньше 10
      empty = 10-empty -- увеличить количество пустых слотов для обратного отсчета
      for slot = 1, inventory do -- просканировать инвентарь
        local item = controller.getStackInInternalSlot(slot)
        if item then -- если слот не пуст
          if not wlist[item.name] then -- проверка имени, чтобы не выкинуть важный предмет в лаву
            local name = item.name:gsub('%g+:', '') -- отформатировать имя
            if available[name] then -- если есть в счетчике
              available[name] = available[name] - item.size -- обновить счетчик
            end
            robot.select(slot) -- выбрать слот
            robot.drop(1) -- выбросить в буфер
            empty = empty - 1 -- обновить счетчик
          end
        end
        if empty == 0 then -- если место освободилось
          break -- прервать цикл
        end
      end
    end
    ------- основной цикл крафта -------
    for o, m in pairs(available) do
      if m > 8 then
        for l = 1, math.ceil(m/576) do
          inv_check()
          -- очистка рабочей зоны --
          for i = 1, 9 do -- пройти по слотам верстака
            if robot.count(workbench[i]) > 0 then -- если слот не пуст
              robot.select(workbench[i]) -- выбрать слот
              for slot = 4, inventory do -- перебор слотов инвентаря
                if slot == 4 or slot == 8 or slot > 11 then -- исключить слоты верстака
                  robot.transferTo(slot) -- попробовать переместить предметы
                  if robot.count(slot) == 0 then -- если слот освободился
                    break -- прервать цикл
                  end
                end
              end
              if robot.count() > 0 then -- если обнаружена перегрузка
                while robot.suck(1) do end -- забрать предметы из буфера
                return -- прекратить упаковку
              end
            end
          end
          for slot = 4, inventory do -- цикл поиска фрагментов
            local item = controller.getStackInInternalSlot(slot) -- получить информацию о предмете
            if item and (slot == 4 or slot == 8 or slot > 11) then -- если есть предмет вне рабочей зоны
              if o == item.name:gsub('%g+:', '') then -- если предмет совпадает
                robot.select(slot) -- при совпадении выбрать слот
                for n = 1, 10 do -- цикл заполнения рабочей зоны
                  robot.transferTo(workbench[n%9+1], item.size/9) -- разделить текущий стак на 9 частей и перенести в верстак
                end
                if robot.count(1) == 64 then -- сброс при заполнении верстака
                  break
                end
              end
            end
          end
          robot.select(inventory) -- выбор последнего слота
          crafting.craft() -- создание блока
          -- цикл сортировки остатков
          for A = 1, inventory do -- основной проход
            local size = robot.count(A) -- получить количество предметов
            if size > 0 and size < 64 then -- если слот не пуст и не полон
              for B = A+1, inventory do -- проход сравнения
                if robot.compareTo(B) then -- если предметы одинаковые
                  robot.select(A) -- выбрать слот
                  robot.transferTo(B, 64-robot.count(B)) -- перенести до заполнения
                end
                if robot.count() == 0 then -- если слот освободился
                  break -- прервать сравнение
                end
              end
            end
          end
        end
      end
    end
  end
  while robot.suck(1) do end --- забрать предметы из буфера
  inv_check()
end

home = function(forcibly, interrupt) -- переход к начальной точке и сброс лута
  local x, y, z, d
  report('ore unloading')
  ignore_check = true
  local enderchest -- обнулить слот с эндерсундуком
  for slot = 1, inventory do -- просканировать инвентарь
    local item = controller.getStackInInternalSlot(slot) -- получить информацию о слоте
    if item then -- если есть предмет
      if item.name == 'enderstorage:ender_storage' then -- если есть эндерсундук
        enderchest = slot -- задать слот
        break -- прервать поиск
      end
    end
  end
  if enderchest and not forcibly then -- если есть сундук и нет принудительного возвращения домой
    -- step(1) -- подняться на 1 блок
    robot.swing(3) -- освободить место для сундука
    robot.select(enderchest) -- выбрать сундук
    robot.place(3) -- поставить сундук
  else
    x, y, z, d = X, Y, Z, D
    go(0, -2, 0)
    go(0, 0, 0)
  end
  sorter() -- сортировка инвентаря
  local size = nil -- обнулить размер контейнера
  while true do -- войти в бесконечный цикл
    for side = 1, 4 do -- поиск контейнера
      size = controller.getInventorySize(3) -- получение размера инвентаря
      if size and size>26 then -- если контейнер найден
        break -- прервать поиск
      end
      turn() -- повернуться
    end
    if not size or size<26 then -- если контейнер не найден
      report('container not found') -- послать сообщение
      sleep(30)
    else
      break -- продолжить работу
    end
  end
  for slot = 1, inventory do -- обойти весь инвентарь
    local item = controller.getStackInInternalSlot(slot)
    if item then -- если слот не пуст
      if not wlist[item.name] then -- если предмет не в белом списке
        robot.select(slot) -- выбрать слот
        local a, b = robot.drop(3) -- сбросить в контейнер
        if not a and b == 'inventory full' then -- если контейнер заполнен
          while not robot.drop(3) do -- ждать, пока не освободится
            report(b) -- послать сообщение
            sleep(30) -- подождать
          end
        end
      end
    end
  end
  if crafting then -- если есть верстак, забрать предметы из сундука и упаковать
    for slot = 1, size do -- обход слотов контейнера
      local item = controller.getStackInSlot(3, slot) -- получить информацию о пердмете
      if item then -- если есть предмет
        if fragments[item.name:gsub('%g+:', '')] then -- если есть совпадение
          controller.suckFromSlot(3, slot) -- забрать предметы
        end
      end
    end
    sorter(true) -- упаковать
    for slot = 1, inventory do -- обойти весь инвентарь
      local item = controller.getStackInInternalSlot(slot)
      if item then -- если слот не пуст
        if not wlist[item.name] then -- если предмет не в белом списке
          robot.select(slot) -- выбрать слот
          robot.drop(3) -- сбрость в контейнер
        end
      end
    end
  end
  if generator and not forcibly then -- если есть генератор
    for slot = 1, size do -- просканировать контейнер
      local item = controller.getStackInSlot(3, slot) -- получить информацию о пердмете
      if item then -- если есть предмет
        if item.name:sub(11, 15) == 'coal' then -- если в слоте уголь
          controller.suckFromSlot(3, slot) -- взять
          break -- выйти из цикла
        end
      end
    end
  end
  if forcibly then
    report('tool search in container')
    if robot.durability() < 0.3 then -- если прочность инструмента меньше 30%
      robot.select(1) -- выбрать первый слот
      controller.equip() -- поместить инструмент в инвентарь
      local tool = controller.getStackInInternalSlot(1) -- получить данные инструмента
      for slot = 1, size do
        local item = controller.getStackInSlot(3, slot)
        if item then
          if item.name == tool.name and item.damage < tool.damage then
            robot.drop(3)
            controller.suckFromSlot(3, slot)
            break
          end
        end
      end
      controller.equip() -- экипировать
    end
    report('attempt to repair tool')
    if robot.durability() < 0.3 then -- если инструмент не заменился на лучший
      for side = 1, 3 do -- перебрать все стороны
        local name = controller.getInventoryName(3) -- получить имя инвенторя
        if name == 'opencomputers:charger' or name == 'tile.oc.charger' then -- сравнить имя
          robot.select(1) -- выбрать слот
          controller.equip() -- достать инструмент
          if robot.drop(3) then -- если получилось засунуть инструмент в зарядник
            local charge = controller.getStackInSlot(3, 1).charge
            local max_charge = controller.getStackInSlot(3, 1).maxCharge
            while true do
              sleep(30)
              local n_charge = controller.getStackInSlot(3, 1).charge -- получить заряд
              if charge then
                if n_charge == max_charge then
                  robot.suck(3) -- забрать предмет
                  controller.equip() -- экипировать
                  break -- остановить зарядку
                else
                  report('tool is '..math.floor((n_charge+1)/max_charge*100)..'% charged')
                end
              else -- если инструмент не чинится
                report('tool could not be charged', true) -- остановить работу
              end
            end
          else
            report('tool could not be repaired', true) -- остановить работу
          end
        else
          turn() -- повернуться
        end
      end
      while robot.durability() < 0.3 do
        report('need a new tool')
        sleep(30)
      end
    end
  end
  if enderchest and not forcibly then
    robot.swing(3) -- забрать сундук
  else
    while energy_level() < 0.98 do -- ждать полного заряда батареи
      report('charging')
      sleep(30)
    end
  end
  ignore_check = nil
  if not interrupt then
    report('return to work')
    go(0, -2, 0)
    go(x, y, z)
    smart_turn(d)
  end
end

main = function()
  border = nil
  while not border do
    step(0)
    for q = 1, 4 do
      scan(table.unpack(quads[q]))
    end
    check(true)
  end
  while #WORLD.x ~= 0 do
    local n_delta, c_delta, current = math.huge, math.huge
    for index = 1, #WORLD.x do
      n_delta = math.abs(X-WORLD.x[index])+math.abs(Y-WORLD.y[index])+math.abs(Z-WORLD.z[index])-border+WORLD.y[index]
      if (WORLD.x[index] > X and D ~= 3) or
      (WORLD.x[index] < X and D ~= 1) or
      (WORLD.z[index] > Z and D ~= 0) or
      (WORLD.z[index] < Z and D ~= 2) then
        n_delta = n_delta + 1
      end
      if n_delta < c_delta then
        c_delta, current = n_delta, index
      end
    end
    if WORLD.x[current] == X and WORLD.y[current] == Y and WORLD.z[current] == Z then
      remove_point(current)
    else
      local yc = WORLD.y[current]
      if yc-1 > Y then
        yc = yc-1
      elseif yc+1 < Y then
        yc = yc+1
      end
      go(WORLD.x[current], yc, WORLD.z[current])
    end
  end
  sorter()
end

calibration() -- запустить калибровку
calibration = nil -- освободить память от функции калибровки
local Tau = computer.uptime() -- записать текущее время
local pos = {0, 0, 0, [0] = 1} -- таблица для хранения координат чанков
for o = 1, 10 do -- цикл ограничения спирали
  for i = 1, 2 do -- цикл обновления координат
    for a = 1, o do -- цикл перехода по линии спирали
      main() -- запуск функции сканирования и добычи
      report('chunk #'..pos[3]+1 ..' processed') -- сообщить о завершении работы в чанке
      pos[i], pos[3] = pos[i] + pos[0], pos[3] + 1 -- обновить координаты
      if pos[3] == chunks then -- если достигнут последний чанк
        home(true, true) -- возврат домой
        report(computer.uptime()-Tau..' seconds\npath length: '..steps..'\nmade turns: '..turns, true) -- сообщить о завершении работы
      else -- иначе
        WORLD = {x = {}, y = {}, z = {}} 
        go(pos[1]*16, -2, pos[2]*16) -- перейти к следующему чанку
        go(X, 0, Z) -- перейти в стартовую точку сканирования
      end
    end
  end
  pos[0] = 0-pos[0] -- обновить направление спирали
end
