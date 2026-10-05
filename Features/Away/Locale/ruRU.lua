-- Русские подписи экрана отлучки.
--
-- Ключ — английская строка из места вызова: базовый язык аддона английский,
-- и английский клиент не читает этот файл вовсе. Таблица кладётся в
-- пространство имён части, а ядру её отдаёт Away.lua — одним вызовом
-- handle:RegisterStrings, чтобы своего ответа на вопрос «какой сейчас язык»
-- у части не завелось.

local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все файлы
-- получают одну и ту же таблицу, и имена вроде Rules или Screen
-- столкнулись бы молча.
local ns = core.Feature("away")

ns.Locales = ns.Locales or {}

ns.Locales.ruRU = {
    ["Away Screen"] = "Экран отлучки",
    ["Show the Away Screen"] = "Показывать экран отлучки",
    ["While the game marks you away, cover the screen with a dark card: "
        .. "your character, where you are and how long you have been gone. "
        .. "Off by default - a fresh install changes nothing."] =
        "Пока игра отмечает вас отошедшим, закрывать экран тёмной карточкой: "
        .. "персонаж, место и сколько вас нет. По умолчанию выключено — "
        .. "свежая установка ничего не меняет.",

    ["Show What I Missed"] = "Показывать пропущенное",
    ["Add a line with the whispers and letters that arrived while you were "
        .. "gone."] =
        "Добавить строку с шёпотами и письмами, пришедшими за время отлучки.",

    ["Level %d %s"] = "%d уровень, %s",
    ["Away %s"] = "Отошёл %s",

    ["%d whisper"] = "%d шёпот",
    ["%d whispers"] = "шёпотов: %d",
    ["%d letter"] = "%d письмо",
    ["%d letters"] = "писем: %d",

    ["the away screen is on now"] = "экран отлучки включён",

    ["Darkness"] = "Плотность",
    ["How solid the cover is. Below a hundred the world still shows through "
        .. "as a silhouette."] =
        "Насколько плотно укрыт экран. Ниже сотни мир ещё угадывается "
        .. "силуэтом.",

    ["Animation"] = "Движение",
    ["What your character does while you are gone."] =
        "Что делает персонаж, пока вас нет.",
    ["Standing"] = "Стоит",
    ["Talking"] = "Говорит",
    ["Dancing"] = "Танцует",
    ["While the game marks you away, the screen is covered with a dark card: your character, where you are and how long you have been gone. It draws over the interface rather than hiding it, and it goes away for good the moment something wants you - combat, a ready check, an invite."] =
        "Пока игра держит на вас отметку отлучки, экран закрыт тёмной " ..
        "карточкой: ваш персонаж, где вы и сколько вас нет. Она рисуется " ..
        "поверх интерфейса, а не прячет его, и уходит насовсем в тот миг, " ..
        "когда вы кому-то понадобились — бой, проверка готовности, " ..
        "приглашение.",
    ["Off by default - a screen-wide cover should not appear for someone who did not ask for one."] =
        "По умолчанию выключено: заслонка во весь экран не должна " ..
        "появляться у того, кто её не просил.",
}
