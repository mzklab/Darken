-- Русские подписи модуля прочности.
--
-- Ключ — английская строка из места вызова: базовый язык аддона английский,
-- и английский клиент не читает этот файл вовсе. Таблица кладётся в
-- пространство имён модуля, а ядру её отдаёт Durability.lua — одним вызовом
-- handle:RegisterStrings, чтобы своего ответа на вопрос «какой сейчас язык»
-- у модуля не завелось.

local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("durability")

ns.Locales = ns.Locales or {}

ns.Locales.ruRU = {
    ["Darken Durability"] = "Darken: прочность",

    ["Show the Durability Block"] = "Показывать показатель прочности",
    ["A block on screen with the durability of the worst piece of equipment "
        .. "you are wearing. Off by default - a fresh install changes "
        .. "nothing."] =
        "Блок на экране с прочностью самой изношенной надетой вещи. По "
        .. "умолчанию выключен — свежая установка ничего не меняет.",

    ["Always Show"] = "Показывать всегда",
    ["Keep the block on screen even when nothing is worn out."] =
        "Оставлять блок на экране даже тогда, когда изнашиваться нечему.",

    ["Warn Below"] = "Предупреждать ниже",
    ["Below this percent the block is drawn in the warning color."] =
        "Ниже этого процента блок рисуется тревожным цветом.",

    ["Durability %d%%"] = "Прочность %d%%",
    ["Durability: nothing to wear out"] = "Прочность: нечему изнашиваться",
    ["%s at %d%%"] = "%s: %d%%",
    ["no equipped item has durability"] =
        "ни одна надетая вещь не имеет прочности",

    ["Head"] = "Голова",
    ["Shoulder"] = "Плечи",
    ["Chest"] = "Грудь",
    ["Waist"] = "Пояс",
    ["Legs"] = "Ноги",
    ["Feet"] = "Ступни",
    ["Wrist"] = "Запястья",
    ["Hands"] = "Кисти рук",
    ["Main Hand"] = "Правая рука",
    ["Off Hand"] = "Левая рука",
    ["Ranged"] = "Дальний бой",
    ["A block on screen with the durability of the worst-worn piece of equipment you are wearing. Off by default - a fresh install changes nothing."] =
        "Блок на экране с прочностью самой изношенной вещи из надетых на " ..
        "вас. По умолчанию выключен: свежая установка ничего не меняет.",
    ["Below this percent the block is drawn in the warning colour."] =
        "Ниже этого процента блок рисуется тревожным цветом.",
    ["Gear"] = "Снаряжение",
    ["Durability"] = "Прочность",
}
