-- Украинские подписи модуля прочности.
--
-- Официальной украинской локали у клиента нет, сверять терминологию не с
-- чем, поэтому слова выбраны так, как их читает украинский игрок, а не
-- переписаны с русского. Набор ключей тот же, что в ruRU.lua: подпись,
-- переведённая на один язык и забытая на другом, — такая же потеря, как
-- непереведённая вовсе.

local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("durability")

ns.Locales = ns.Locales or {}

ns.Locales.ukUA = {
    ["Darken Durability"] = "Darken: міцність",

    ["Show the Durability Block"] = "Показувати показник міцності",
    ["A block on screen with the durability of the worst piece of equipment "
        .. "you are wearing. Off by default - a fresh install changes "
        .. "nothing."] =
        "Показник на екрані з міцністю найзношенішої вдягненої речі. Типово "
        .. "вимкнено — свіже встановлення не змінює нічого.",

    ["Always Show"] = "Показувати завжди",
    ["Keep the block on screen even when nothing is worn out."] =
        "Лишати показник на екрані навіть тоді, коли зношуватися немає чому.",

    ["Warn Below"] = "Попереджати нижче",
    ["Below this percent the block is drawn in the warning color."] =
        "Нижче цього відсотка показник малюється тривожним кольором.",

    ["Durability %d%%"] = "Міцність %d%%",
    ["Durability: nothing to wear out"] = "Міцність: немає чому зношуватися",
    ["%s at %d%%"] = "%s: %d%%",
    ["no equipped item has durability"] =
        "жодна вдягнена річ не має міцності",

    ["Head"] = "Голова",
    ["Shoulder"] = "Плечі",
    ["Chest"] = "Груди",
    ["Waist"] = "Пояс",
    ["Legs"] = "Ноги",
    ["Feet"] = "Стопи",
    ["Wrist"] = "Зап'ястя",
    ["Hands"] = "Кисті рук",
    ["Main Hand"] = "Права рука",
    ["Off Hand"] = "Ліва рука",
    ["Ranged"] = "Далекобійна зброя",
    ["A block on screen with the durability of the worst-worn piece of equipment you are wearing. Off by default - a fresh install changes nothing."] =
        "Блок на екрані з міцністю найзношенішої речі з одягнених на вас. " ..
        "За умовчанням вимкнений: свіже встановлення нічого не змінює.",
    ["Below this percent the block is drawn in the warning colour."] =
        "Нижче цього відсотка блок малюється тривожним кольором.",
    ["Gear"] = "Спорядження",
    ["Durability"] = "Міцність",
}
