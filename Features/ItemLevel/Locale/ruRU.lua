local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("itemlevel")

-- Русский перевод модуля уровня предметов.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод перестанет
-- находиться, а игрок увидит английскую подпись. Правка английского всегда
-- идёт парой — в месте вызова и здесь.

-- Таблица объявляется данными и ничем больше: складывает её в ядро
-- ItemLevel.lua, когда получит описатель модуля (handle:RegisterStrings).
-- Своего выбора языка у модуля нет — язык клиента определяет ядро, и второе
-- определение разошлось бы с ним молча.

ns.Strings = ns.Strings or {}
ns.Strings.ruRU = {

    ["Darken Item Level"] =
        "Уровень предметов Darken",

    ["Draws the item level over "
        .. "the icon of an item: on the character sheet, when "
        .. "inspecting another player and in your bags. Off by "
        .. "default - a fresh install changes nothing."] =
        "Показывает уровень предмета поверх значка вещи: в окне "
        .. "персонажа, в осмотре чужого персонажа и в сумках. По "
        .. "умолчанию выключено — свежая установка не меняет ничего.",

    ["Show Item Level"] =
        "Показывать уровень предмета",

    ["Off takes every number "
        .. "away at once, without reloading the interface."] =
        "Выключение убирает все числа разом, без перезагрузки "
        .. "интерфейса.",

    ["Number Position"] =
        "Положение числа",

    ["Which corner of the icon "
        .. "the number sits in. The bottom right corner is where the "
        .. "game puts the stack count."] =
        "В каком углу значка стоит число. В правом нижнем углу игра "
        .. "показывает количество в стопке.",

    ["Color by Item Quality"] =
        "Цвет по качеству предмета",

    ["Off draws every number in "
        .. "the addon's own text color."] =
        "Выключение красит все числа обычным цветом текста аддона.",

    ["Number Size"] =
        "Размер числа",

    ["Font"] =
        "Шрифт",

    ["Which of Darken's font "
        .. "categories the number follows. The font itself is chosen "
        .. "in the addon's Fonts section; only the size above "
        .. "belongs to this module."] =
        "Какой шрифтовой категории Darken следует число. Сам шрифт "
        .. "выбирается в разделе «Шрифты» аддона, модулю принадлежит "
        .. "только размер выше.",

    ["item level numbers on"] =
        "уровень предметов показывается",

    ["item level numbers off"] =
        "уровень предметов скрыт",

    -- Подписи углов значка. Ключи приходят из таблицы Level.POSITIONS, а не
    -- из литерала в месте вызова: угол — это данные, а не текст в коде.
    ["Top Left"]     = "Сверху слева",
    ["Top Right"]    = "Сверху справа",
    ["Bottom Left"]  = "Снизу слева",
    ["Bottom Right"] = "Снизу справа",
    ["Center"]       = "По центру",
    ["Corner"] = "Угол",
    ["Color by Quality"] = "Красить по качеству",
    ["Text Size"] = "Размер текста",
    ["Write the item level over the icon of an item: in the character sheet, in inspect and in the bags."] =
        "Писать уровень предмета поверх его значка: в окне персонажа, в " ..
        "осмотре и в сумках.",
    ["Which corner of the icon the number stands in."] =
        "В каком углу значка стоит число.",
    ["Colour the number by the item's quality instead of writing it in one colour."] =
        "Красить число по качеству предмета, а не писать одним цветом.",
    ["Which of Darken's font categories the number follows. The font itself is chosen in the addon's Fonts section; only the size below belongs to this module."] =
        "Какой шрифтовой категории Darken следует число. Сам шрифт " ..
        "выбирается в разделе шрифтов аддона; этому модулю принадлежит " ..
        "только размер ниже.",
    ["How big the number is drawn."] = "Насколько крупно нарисовано число.",
    ["Gear"] = "Снаряжение",
    ["Item Level"] = "Уровень предмета",
}
