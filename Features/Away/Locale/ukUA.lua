-- Українські підписи екрана відлучки.
--
-- Ключ — англійський рядок із місця виклику: базова мова аддона англійська,
-- і англійський клієнт цього файлу не читає зовсім. Таблиця кладеться в
-- простір імен частини, а ядру її віддає Away.lua — одним викликом
-- handle:RegisterStrings, щоб своєї відповіді на питання «яка зараз мова» у
-- частини не завелося.

local ADDON, core = ...

-- Свій простір імен цієї частини: всередині одного аддона всі файли
-- отримують одну й ту саму таблицю, і імена на кшталт Rules або Screen
-- зіткнулися б мовчки.
local ns = core.Feature("away")

ns.Locales = ns.Locales or {}

ns.Locales.ukUA = {
    ["Away Screen"] = "Екран відлучки",
    ["Show the Away Screen"] = "Показувати екран відлучки",
    ["While the game marks you away, cover the screen with a dark card: "
        .. "your character, where you are and how long you have been gone. "
        .. "Off by default - a fresh install changes nothing."] =
        "Поки гра позначає вас відсутнім, закривати екран темною карткою: "
        .. "персонаж, місце і скільки вас немає. Типово вимкнено — свіже "
        .. "встановлення нічого не змінює.",

    ["Show What I Missed"] = "Показувати пропущене",
    ["Add a line with the whispers and letters that arrived while you were "
        .. "gone."] =
        "Додати рядок із шепотами та листами, що надійшли за час відлучки.",

    ["Level %d %s"] = "%d рівень, %s",
    ["Away %s"] = "Відійшов %s",

    ["%d whisper"] = "%d шепіт",
    ["%d whispers"] = "шепотів: %d",
    ["%d letter"] = "%d лист",
    ["%d letters"] = "листів: %d",

    ["the away screen is on now"] = "екран відлучки увімкнено",

    ["Darkness"] = "Щільність",
    ["How solid the cover is. Below a hundred the world still shows through "
        .. "as a silhouette."] =
        "Наскільки щільно вкрито екран. Нижче сотні світ ще вгадується "
        .. "силуетом.",

    ["Animation"] = "Рух",
    ["What your character does while you are gone."] =
        "Що робить персонаж, поки вас немає.",
    ["Standing"] = "Стоїть",
    ["Talking"] = "Говорить",
    ["Dancing"] = "Танцює",
    ["While the game marks you away, the screen is covered with a dark card: your character, where you are and how long you have been gone. It draws over the interface rather than hiding it, and it goes away for good the moment something wants you - combat, a ready check, an invite."] =
        "Поки гра тримає на вас позначку відлучки, екран закритий темною " ..
        "карткою: ваш персонаж, де ви і скільки вас немає. Вона малюється " ..
        "поверх інтерфейсу, а не ховає його, і йде назавжди тієї миті, коли " ..
        "ви комусь знадобилися — бій, перевірка готовності, запрошення.",
    ["Off by default - a screen-wide cover should not appear for someone who did not ask for one."] =
        "За умовчанням вимкнено: заслінка на весь екран не повинна " ..
        "з'являтися в того, хто її не просив.",
}
