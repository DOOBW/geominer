local component = require('component') -- подгрузить обертку из OpenOS
local computer = require('computer')
local X, Y, Z, D, border = 0, 0, 0, 0 -- переменные локальной системы координат
local WORLD = {x = {}, y = {}, z = {}}
local E_C, W_R = 0, 0 -- энергозатраты на один шаг и скорость износа

local tails = {'cobblestone','dirt','gravel','sand','stained_hardened_clay','sandstone','stone','grass','end_stone','hardened_clay','mossy_cobblestone','planks','fence','torch','nether_brick','nether_brick_fence','nether_brick_stairs','netherrack','soul_sand'}
local workbench = {1,2,3,5,6,7,9,10,11}
local fragments = {'redstone','coal','dye','diamond','emerald'}

local function add_component(name) -- получение прокси компонента
  name = component.list(name)() -- получить адрес по имени
  if name then -- если есть адрес
    return component.proxy(name) -- вернуть прокси
  end
end

-- загрузка компонентов --
local controller = add_component('inventory_controller')
local crafting = add_component('crafting')
local geolyzer = add_component('geolyzer')
local robot = add_component('robot')
local inventory = robot.inventorySize()

local function step(side) -- функция движения на 1 блок
  if not robot.swing(side) and robot.detect(side) then -- если блок нельзя разрушить
    print('bedrock')
    os.exit() -- временная заглушка
  else
    while robot.swing(side) do end -- копать пока возможно
  end
  if robot.move(side) then -- если робот сдвинулся, обновить координаты
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
  if #WORLD.x ~= 0 then -- если таблица меток не пуста
    for i = 1, #WORLD.x do -- пройти по всем позициям
      if X == WORLD.x[i] and (Y-1 <= WORLD.y[i] and Y+1 >= WORLD.y[i]) and Z == WORLD.z[i] then
        if WORLD.y[i] == Y+1 then -- добыть блок сверху, если есть
          robot.swing(1)
        elseif WORLD.y[i] == Y-1 then -- добыть блок снизу
          robot.swing(0)
        end
        table.remove(WORLD.x, i) -- удалить метку из таблицы
        table.remove(WORLD.y, i)
        table.remove(WORLD.z, i)
      end
    end
  end
end

local function turn(side) -- поворот в сторону
  side = side or false
  if robot.turn(side) and D then -- если робот повернулся, обновить переменную направления
    if side then
      D = (D+1)%4
    else
      D = (D-1)%4
    end
  end
end

local function smart_turn(side) -- поворот в определенную сторону света
  while D ~= side do
    turn((side-D)%4==1)
  end
end

local function go(x, y, z) -- переход по указанным координатам
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

local function scan(xx, zz) -- сканирование квадрата x8 относительно робота
  local raw, index = geolyzer.scan(xx, zz, -1, 8, 8, 1), 1 -- получить сырые данные, установить индекс в начало таблицы
  for z = zz, zz+7 do -- развертка данных по z
    for x = xx, xx+7 do -- развертка данных по х
      if raw[index] >= 2.3 and raw[index] <= 40 then -- если обнаружен блок с плотностью от 2.3 до 40
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

local function calibration() -- калибровка при запуске
  robot.select(1)
  local energy = computer.energy() -- получить уровень энергии
  step(0) -- сделать шаг
  E_C = math.ceil(energy-computer.energy()) -- записать уровень потребления
  energy = robot.durability() -- получить уровень износа/разряда инструмента
  while energy == robot.durability() do -- пока не обнаружена разница
    robot.place(1) -- установить блок
    robot.swing(1) -- разрушить блок
  end
  W_R = energy-robot.durability() -- записать результат
  local sides = {2, 1, 3, 0} -- линки сторон света, для сырых данных
  D = nil -- обнуление направления
  while not D do -- пока не найдено направление
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
end

local function sorter() -- сортировка лута
  robot.swing(0) -- освободить место для мусора
  robot.swing(1) -- освободить место для буфера
  ------- сброс мусора -------
  local empty = 0 -- создать счетчик пустых слотов
  for slot = 1, inventory do -- пройти по слотам инвентаря
    local item = controller.getStackInInternalSlot(slot) -- получить информацию о предмете
    if item then -- если есть предмет
      for name = 1, #tails do -- пройти по таблице хвостов
        if item.name:gsub('%g+:', '') == tails[name] then -- проверить на совпадение
          robot.select(slot) -- выбрать слот
          robot.drop(0) -- выбросить к отходам
          empty = empty + 1 -- обновить счетчик
          break -- прервать цикл сравнения
        end
      end
    else
      empty = empty + 1 -- обновить счетчик
    end
  end
  -- упаковка предметов в блоки --
  if crafting and empty < 12 then -- если есть верстак и переполнение
    -- перенос лишних предметов в буфер --
    if empty < 10 then -- если пустых слотов меньше 10
      empty = 10-empty -- увеличить количество пустых слотов для обратного отсчета
      for slot = 1, inventory do -- просканировать инвентарь
        if robot.count(slot) > 0 then -- если слот не пуст
          robot.select(slot) -- выбрать слот
          robot.drop(1) -- выбросить в буфер
          empty = empty - 1 -- обновить счетчик
        end
        if empty == 0 then -- если место освободилось
          break -- прервать цикл
        end
      end
    end
    -- подсчет предметов доступных для упаковки --
    local available = {} -- создать таблицу счетчиков
    for slot = 1, inventory do -- пройти по слотам инвентаря
      local item = controller.getStackInInternalSlot(slot) -- получить информацию о предмете
      if item then -- если есть предмет
        for n = 1, #fragments do -- пройти по списку названий фрагментов
          if item.name:gsub('%g+:', '') == fragments[n] then -- сравнить по имени
            if available[n] then -- если есть подобные фрагменты
              available[n] = available[n] + item.size -- обновить
            else -- иначе
              available[n] = item.size -- создать
            end
            break
          end
        end
      end
    end
    ------- основной цикл крафта -------
    for i = 1, #fragments do -- перебор всех названий
      if available[i] then -- если в инвентаре такой есть
        for j = 1, math.ceil(available[i]/576) do -- разделить результат на стаки
          for c_slot = 1, 9 do -- цикл чистки зоны верстака
            if robot.count(workbench[c_slot]) > 0 then -- если слот не пуст
              for slot = 4, inventory do -- обойти весь инвентарь, кроме рабочей зоны
                if robot.count(slot) == 0 and (slot == 4 or slot == 8 or slot > 11) then -- если есть свободный
                  robot.select(workbench[c_slot]) -- выбрать слот верстака
                  robot.transferTo(slot) -- освободить слот
                  break -- выйти из цикла
                end
              end
              if robot.count() > 0 then -- проверить на перегрузку
                robot.suck(1) -- забрать из буфера
                return true -- остановить упаковку
              end
            end
          end
          ------- основной цикл крафта -------
          for slot = 4, inventory do -- цикл поиска фрагментов
            local item = controller.getStackInInternalSlot(slot) -- получить информацию о предмете
            if item and (slot == 4 or slot == 8 or slot > 11) then -- если есть предмет вне рабочей зоны
              if item.name:gsub('%g+:', '') == fragments[i] then -- сравнить по названию фрагмента
                robot.select(slot) -- при совпадении выбрать слот
                for n = 1, 9 do -- цикл заполнения рабочей зоны
                  robot.transferTo(workbench[n], item.size/9) -- разделить текущий стак на 9 частей и перенести в верстак
                end
                if robot.count(1) == 64 then -- сброс при заполнении верстака
                  break
                end
              end
            end
          end
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
  robot.suck(1) --- забрать предметы из буфера
end
