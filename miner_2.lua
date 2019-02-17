local component = require('component') -- подгрузить обертку из OpenOS
local computer = require('computer')
local X, Y, Z, D = 0, 0, 0, 0 -- переменные локальной системы координат
local WORLD = {x = {}, y = {}, z = {}}
local border = false -- указатель статуса обнаружения бедрока
local E_C, W_R = 0, 0 -- энергозатраты на один шаг и скорость износа

local function add_component(name) -- получение прокси компонента
  name = component.list(name)() -- получить адрес по имени
  if name then -- если есть адрес
    return component.proxy(name) -- вернуть прокси
  end
end

local robot = add_component('robot') -- загрузка компонента
local geolyzer = add_component('geolyzer')

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
        border = true -- сделать отметку
      end
      index = index + 1 -- переход к следующему индексу сырых даннх
    end
  end
end

local function compass() -- определение сторон света
  local sides = {2, 1, 3, 0} -- линки сторон света, для сырых данных
  D = nil -- обнуление направления
  while not D do -- пока не найдено направление
    if robot.detect(3) then -- проверить наличие блока перед носом
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

local function calibration() -- калибровка при запуске
  local energy = computer.energy() -- получить уровень энергии
  step(0) -- сделать шаг
  E_C = math.ceil(energy-computer.energy()) -- записать уровень потребления
  energy = robot.durability() -- получить уровень износа/разряда инструмента
  while energy == robot.durability() do -- пока не обнаружена разница
    robot.place(1) -- установить блок
    robot.swing(1) -- разрушить блок
  end
  W_R = energy-robot.durability() -- записать результат
  step(1) -- вернуться на место
end
