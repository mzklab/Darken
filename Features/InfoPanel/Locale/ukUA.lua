local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("infopanel")

-- Украинский перевод информационной панели.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод перестанет
-- находиться, а игрок увидит английскую подпись. Правка английского всегда
-- идёт парой — в месте вызова и здесь.

-- Таблица объявляется данными и ничем больше: складывает её в ядро
-- InfoPanel.lua, когда получит описатель модуля (handle:RegisterStrings).
-- Своего выбора языка у модуля нет — язык клиента определяет ядро, и второе
-- определение разошлось бы с ним молча.

ns.Strings = ns.Strings or {}
ns.Strings.ukUA = {

    ["Gold"] =
        "Золото",

    ["Durability"] =
        "Міцність",

    ["Bags"] =
        "Сумки",

    ["Latency"] =
        "Затримка",

    ["Frames"] =
        "Кадри",

    ["Clock"] =
        "Годинник",

    ["Experience"] =
        "Досвід",

    ["Reputation"] =
        "Репутація",

    ["this client does not hold UIParent by its top or bottom edge, "
        .. "so the panel cannot take screen space here and draws over the "
        .. "interface instead"] =
        "у цьому клієнті UIParent тримається не за верхній і не за "
            .. "нижній край екрана, тому панель не може відібрати місце і "
            .. "малюється поверх інтерфейсу",

    ["Darken Information Panel"] =
        "Інформаційна панель Darken",

    ["A bar of metrics at the edge of the screen: gold, durability, "
        .. "bag space, latency, frames, the clock, experience and "
        .. "reputation. It shows everything published to the LibDataBroker "
        .. "standard, so metrics from other addons you have installed "
        .. "appear here on the same footing as ours. Off by default - a "
        .. "fresh install changes nothing."] =
        "Смуга показників скраю екрана: золото, міцність, місце в "
            .. "сумках, затримка, кадри, годинник, досвід і репутація. Показує "
            .. "все, що опубліковано за стандартом LibDataBroker, тому "
            .. "показники інших встановлених аддонів з'являються тут нарівні з "
            .. "нашими. Типово вимкнена — свіже встановлення нічого не змінює.",

    ["Show the Panel"] =
        "Показувати панель",

    ["The panel is two bars - one at the top of the screen, one at the "
        .. "bottom - and the two switches below say which of them are "
        .. "drawn. Off by default; with both bars off nothing is drawn "
        .. "either."] =
        "Панель — це дві смуги, одна вгорі екрана, друга внизу, і два "
        .. "перемикачі нижче кажуть, які з них малюються. Типово вимкнено; "
        .. "коли вимкнено обидві смуги, не малюється нічого.",

    ["Top Bar"] =
        "Верхня смуга",

    ["Bottom Bar"] =
        "Нижня смуга",

    ["Cells"] =
        "Комірки",

    ["Cell"] =
        "Комірка",

    ["Every metric in the list comes from the same place - ours and "
        .. "other addons' alike. The number is its place in the row."] =
        "Усі показники списку приходять з одного місця — і наші, і "
            .. "чужі. Число поряд з іменем — місце комірки в ряду.",

    ["Show This Cell"] =
        "Показувати цю комірку",

    ["Which Bar"] =
        "На якій смузі",

    ["Top"] =
        "Згори",

    ["Bottom"] =
        "Знизу",

    ["Move Earlier"] =
        "Пересунути лівіше",

    ["Move Later"] =
        "Пересунути правіше",

    ["Bar and Formats"] =
        "Смуга і вигляд значень",

    ["Bar Height"] =
        "Висота смуги",

    ["Move the Interface Out of the Way"] =
        "Посувати інтерфейс",

    ["On, the bar takes its height away from the rest of the "
        .. "interface, which moves in by that much and stays fully "
        .. "visible. Off, the bar draws over whatever is underneath it."] =
        "Увімкнено — смуга забирає свою висоту в решти інтерфейсу: він "
            .. "посувається і лишається видимим повністю. Вимкнено — смуга "
            .. "малюється поверх того, що під нею.",

    ["12-Hour Clock"] =
        "Дванадцятигодинний годинник",

    ["Show Seconds"] =
        "Показувати секунди",

    ["Experience Shown As"] =
        "Досвід показувати як",

    ["Current and Maximum"] =
        "Поточне і максимум",

    ["Percent"] =
        "Відсотки",

    ["Remaining"] =
        "Залишок",

    ["Reputation Shown As"] =
        "Репутацію показувати як",

    ["information panel on"] =
        "інформаційна панель увімкнена",

    ["information panel off"] =
        "інформаційна панель вимкнена",
    ["What This Metric Does Itself"] =
        "Що показник робить сам",

    ["Hide This Cell"] =
        "Сховати цю комірку",

    ["Move to the Top Bar"] =
        "Перевести на верхню панель",

    ["Move to the Bottom Bar"] =
        "Перевести на нижню панель",

    ["The same three things are on the bar itself: right-click a cell to hide it, move it or send it to the other bar. Left-click belongs to the metric - it does whatever the addon that published it does, and that is the same for ours and for other addons'."] =
        "Те саме є і на самій панелі: права кнопка по комірці ховає її, "
        .. "переставляє або переводить на іншу панель. Ліва кнопка належить "
        .. "показникові — вона робить те, що робить аддон, який його "
        .. "оприлюднив, і в наших показників та в чужих це однаково.",

    ["the game refused a protected action (%s) while the panel was holding screen space. If this keeps happening, turn off the setting that moves the interface out of the way, and the panel will draw over the interface instead."] =
        "гра відмовила захищеній дії (%s), поки панель тримала місце на "
        .. "екрані. Якщо це повторюється, вимкніть налаштування, що зсуває "
        .. "інтерфейс, — панель малюватиметься поверх нього.",

    ["the panel is on"] =
        "панель увімкнена",

    ["the panel is off"] =
        "панель вимкнена",

    ["moving the interface out of the way is on"] =
        "зсув інтерфейсу увімкнено",

    ["moving the interface out of the way is off"] =
        "зсув інтерфейсу вимкнено",

    ["asked for %d above and %d below"] =
        "попрошено: %d згори і %d знизу",

    ["applied %d above and %d below"] =
        "застосовано: %d згори і %d знизу",

    ["the change was refused: %s"] =
        "зміну відхилено: %s",

    ["the change is waiting for combat to end"] =
        "зміна чекає на кінець бою",

    ["this client does not hold UIParent by its top or bottom edge, so nothing was moved"] =
        "у цьому клієнті UIParent не тримається ні за верхній, ні за нижній "
        .. "край, тож нічого не зсунуто",

    ["UIParent is not where the panel left it: %s"] =
        "UIParent стоїть не там, де його лишила панель: %s",

    ["UIParent is exactly where the panel left it"] =
        "UIParent стоїть саме там, де його лишила панель",

    ["the last move did not take: %s"] =
        "останній зсув не застосувався: %s",

    ["the game refused a protected action %d times while the panel held screen space"] =
        "гра відмовила захищеній дії %d разів, поки панель тримала місце на "
        .. "екрані",

    ["cells shown: %d of %d in the registry"] =
        "показано комірок: %d з %d у реєстрі",

    ["the panel is drawing"] = "панель малює",
    ["the panel is not drawing"] = "панель не малює",
    ["cells on the bars: %d above, %d below"] = "комірок на смугах: %d згори, %d знизу",
    ["the %s bar was never built"] = "смуга «%s» не будувалася жодного разу",
    ["the %s bar could not be built"] = "смугу «%s» побудувати не вдалося",
    ["the %s bar: %s, %d by %d, opacity %.2f"] = "смуга «%s»: %s, %d на %d, прозорість %.2f",
    ["shown"] = "показана",
    ["hidden"] = "схована",
    ["the %s bar is anchored to nothing"] = "смуга «%s» ні до чого не прив'язана",
    ["the %s bar: %s at %d, %d"] = "смуга «%s»: %s у точці %d, %d",
    ["Cells Go To"] = "Комірки йдуть на",
    ["Opacity"] = "Непрозорість",
    ["A bar of metrics at the edge of the screen. It draws at the screen edge and takes the space it needs from the interface below it."] =
        "Смуга показників скраю екрана. Вона малюється біля самого краю і " ..
        "забирає потрібне їй місце в інтерфейсу під собою.",
    ["Use the bar along the top of the screen."] =
        "Користуватися смугою вздовж верхнього краю екрана.",
    ["Use the bar along the bottom of the screen. Switching it on is not enough by itself: a bar draws the cells that sit on it, and every cell starts on the bar chosen below. Send cells to it one at a time in the list further down, or change that choice to move them all at once."] =
        "Користуватися смугою вздовж нижнього краю екрана. Самого вмикання " ..
        "замало: смуга малює ті комірки, що на ній стоять, а кожна комірка " ..
        "починає на смузі, обраній нижче. Надсилайте комірки по одній у " ..
        "списку далі або змініть той вибір, щоб перевести їх усі разом.",
    ["Which bar a cell uses when you have not sent it to one yourself. Changing this moves every cell you have not placed by hand."] =
        "На якій смузі стоїть комірка, доки ви не надіслали її самі. Зміна " ..
        "цього рухає всі комірки, яких ви не ставили руками.",
    ["How solid the bar is. It never goes all the way to invisible: a bar you cannot see is a bar that is switched off, and that is the checkbox above."] =
        "Наскільки смуга щільна. До повної невидимості вона не доходить: " ..
        "смуга, якої не видно, — це вимкнена смуга, а вимикає її галочка " ..
        "вище.",
    ["Hiding, moving and sending a cell to the other bar can also be done on the bar itself, by right-clicking the cell. Left-click belongs to the metric - it does whatever the addon that published it does, and that is the same for ours and for other addons'. A hidden cell is the one thing the bar cannot undo: it is not on the bar to be clicked."] =
        "Сховати комірку, переставити її та надіслати на іншу смугу можна й " ..
        "на самій смузі — правим клацанням по комірці. Ліве клацання " ..
        "належить показникові: він робить те, що робить аддон, який його " ..
        "оприлюднив, і це однаково для наших і для чужих. Схована комірка — " ..
        "єдине, чого смуга скасувати не може: її на смузі немає, і клацати " ..
        "нема по чому.",
    ["A hidden cell cannot be brought back from the bar itself - it is not on it. This is the way back."] =
        "Сховану комірку не повернути з самої смуги — її там немає. Це і є " ..
        "шлях назад.",
    ["Which of the two bars this cell sits on. A cell sent to a bar that is switched off is not drawn at all."] =
        "На котрій із двох смуг стоїть ця комірка. Комірка, надіслана на " ..
        "вимкнену смугу, не малюється взагалі.",
    ["How tall the bar is."] = "Наскільки смуга висока.",
    ["Take the bar's height away from the screen so nothing hides under it. On a client that does not let the addon move the interface, the bar draws over it instead and says so."] =
        "Відняти висоту смуги в екрана, щоб під нею нічого не ховалося. На " ..
        "клієнті, який не дає аддону рухати інтерфейс, смуга малюється " ..
        "поверх нього і каже про це.",
    ["Write the time as twelve hours instead of twenty-four."] =
        "Писати час дванадцятьма годинами замість двадцяти чотирьох.",
    ["Write seconds in the clock cell."] =
        "Писати секунди в комірці годинника.",
    ["Information Panel"] = "Інформаційна панель",
}
