local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("itemlevel")

-- Украинский перевод модуля уровня предметов.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод перестанет
-- находиться, а игрок увидит английскую подпись. Правка английского всегда
-- идёт парой — в месте вызова и здесь.

ns.Strings = ns.Strings or {}
ns.Strings.ukUA = {

    ["Darken Item Level"] =
        "Рівень предметів Darken",

    ["Draws the item level over "
        .. "the icon of an item: on the character sheet, when "
        .. "inspecting another player and in your bags. Off by "
        .. "default - a fresh install changes nothing."] =
        "Малює рівень предмета поверх значка речі: у вікні персонажа, "
        .. "в огляді чужого персонажа та в сумках. Типово вимкнено — "
        .. "свіже встановлення не змінює нічого.",

    ["Show Item Level"] =
        "Показувати рівень предмета",

    ["Off takes every number "
        .. "away at once, without reloading the interface."] =
        "Вимкнення прибирає всі числа разом, без перезавантаження "
        .. "інтерфейсу.",

    ["Number Position"] =
        "Розташування числа",

    ["Which corner of the icon "
        .. "the number sits in. The bottom right corner is where the "
        .. "game puts the stack count."] =
        "У якому куті значка стоїть число. У правому нижньому куті "
        .. "гра показує кількість у стосі.",

    ["Color by Item Quality"] =
        "Колір за якістю предмета",

    ["Off draws every number in "
        .. "the addon's own text color."] =
        "Вимкнення малює всі числа звичайним кольором тексту аддона.",

    ["Number Size"] =
        "Розмір числа",

    ["Font"] =
        "Шрифт",

    ["Which of Darken's font "
        .. "categories the number follows. The font itself is chosen "
        .. "in the addon's Fonts section; only the size above "
        .. "belongs to this module."] =
        "Якої шрифтової категорії Darken дотримується число. Сам "
        .. "шрифт обирається в розділі «Шрифти» аддона, модулю "
        .. "належить лише розмір вище.",

    ["item level numbers on"] =
        "рівень предметів показано",

    ["item level numbers off"] =
        "рівень предметів приховано",

    -- Підписи кутів значка. Ключі приходять із таблиці Level.POSITIONS, а не
    -- з літерала в місці виклику: кут — це дані, а не текст у коді.
    ["Top Left"]     = "Згори ліворуч",
    ["Top Right"]    = "Згори праворуч",
    ["Bottom Left"]  = "Знизу ліворуч",
    ["Bottom Right"] = "Знизу праворуч",
    ["Center"]       = "По центру",
    ["Corner"] = "Кут",
    ["Color by Quality"] = "Фарбувати за якістю",
    ["Text Size"] = "Розмір тексту",
    ["Write the item level over the icon of an item: in the character sheet, in inspect and in the bags."] =
        "Писати рівень предмета поверх його піктограми: у вікні персонажа, " ..
        "в огляді та в торбах.",
    ["Which corner of the icon the number stands in."] =
        "У якому куті піктограми стоїть число.",
    ["Colour the number by the item's quality instead of writing it in one colour."] =
        "Фарбувати число за якістю предмета, а не писати одним кольором.",
    ["Which of Darken's font categories the number follows. The font itself is chosen in the addon's Fonts section; only the size below belongs to this module."] =
        "Якій шрифтовій категорії Darken слідує число. Сам шрифт обирається " ..
        "в розділі шрифтів аддона; цьому модулю належить лише розмір нижче.",
    ["How big the number is drawn."] = "Наскільки великим намальоване число.",
    ["Gear"] = "Спорядження",
    ["Item Level"] = "Рівень предмета",
}
