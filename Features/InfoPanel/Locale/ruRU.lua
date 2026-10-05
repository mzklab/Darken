local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("infopanel")

-- Русский перевод информационной панели.
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
ns.Strings.ruRU = {

    ["Gold"] =
        "Золото",

    ["Durability"] =
        "Прочность",

    ["Bags"] =
        "Сумки",

    ["Latency"] =
        "Задержка",

    ["Frames"] =
        "Кадры",

    ["Clock"] =
        "Часы",

    ["Experience"] =
        "Опыт",

    ["Reputation"] =
        "Репутация",

    ["this client does not hold UIParent by its top or bottom edge, "
        .. "so the panel cannot take screen space here and draws over the "
        .. "interface instead"] =
        "в этом клиенте UIParent держится не за верхний и не за нижний "
            .. "край экрана, поэтому панель не может отнять место и рисуется "
            .. "поверх интерфейса",

    ["Darken Information Panel"] =
        "Информационная панель Darken",

    ["A bar of metrics at the edge of the screen: gold, durability, "
        .. "bag space, latency, frames, the clock, experience and "
        .. "reputation. It shows everything published to the LibDataBroker "
        .. "standard, so metrics from other addons you have installed "
        .. "appear here on the same footing as ours. Off by default - a "
        .. "fresh install changes nothing."] =
        "Полоса показателей у края экрана: золото, прочность, место в "
            .. "сумках, задержка, кадры, часы, опыт и репутация. Показывает "
            .. "всё, что опубликовано по стандарту LibDataBroker, поэтому "
            .. "показатели других установленных аддонов появляются здесь "
            .. "наравне с нашими. По умолчанию выключена — свежая установка "
            .. "ничего не меняет.",

    ["Show the Panel"] =
        "Показывать панель",

    ["The panel is two bars - one at the top of the screen, one at the "
        .. "bottom - and the two switches below say which of them are "
        .. "drawn. Off by default; with both bars off nothing is drawn "
        .. "either."] =
        "Панель — это две полосы, одна вверху экрана, другая внизу, и два "
        .. "выключателя ниже говорят, какие из них рисуются. По умолчанию "
        .. "выключена; при обеих выключенных полосах не рисуется ничего.",

    ["Top Bar"] =
        "Верхняя полоса",

    ["Bottom Bar"] =
        "Нижняя полоса",

    ["Cells"] =
        "Ячейки",

    ["Cell"] =
        "Ячейка",

    ["Every metric in the list comes from the same place - ours and "
        .. "other addons' alike. The number is its place in the row."] =
        "Все показатели списка приходят из одного места — и наши, и "
            .. "чужие. Число рядом с именем — место ячейки в ряду.",

    ["Show This Cell"] =
        "Показывать эту ячейку",

    ["Which Bar"] =
        "На какой полосе",

    ["Top"] =
        "Сверху",

    ["Bottom"] =
        "Снизу",

    ["Move Earlier"] =
        "Переставить левее",

    ["Move Later"] =
        "Переставить правее",

    ["Bar and Formats"] =
        "Полоса и вид значений",

    ["Bar Height"] =
        "Высота полосы",

    ["Move the Interface Out of the Way"] =
        "Сдвигать интерфейс",

    ["On, the bar takes its height away from the rest of the "
        .. "interface, which moves in by that much and stays fully "
        .. "visible. Off, the bar draws over whatever is underneath it."] =
        "Включено — полоса отнимает свою высоту у остального "
            .. "интерфейса: он сдвигается и остаётся виден целиком. Выключено "
            .. "— полоса рисуется поверх того, что под ней.",

    ["12-Hour Clock"] =
        "Двенадцатичасовые часы",

    ["Show Seconds"] =
        "Показывать секунды",

    ["Experience Shown As"] =
        "Опыт показывать как",

    ["Current and Maximum"] =
        "Текущее и максимум",

    ["Percent"] =
        "Проценты",

    ["Remaining"] =
        "Остаток",

    ["Reputation Shown As"] =
        "Репутацию показывать как",

    ["information panel on"] =
        "информационная панель включена",

    ["information panel off"] =
        "информационная панель выключена",
    ["What This Metric Does Itself"] =
        "Что показатель делает сам",

    ["Hide This Cell"] =
        "Скрыть эту ячейку",

    ["Move to the Top Bar"] =
        "Перевести на верхнюю полосу",

    ["Move to the Bottom Bar"] =
        "Перевести на нижнюю полосу",

    ["The same three things are on the bar itself: right-click a cell to hide it, move it or send it to the other bar. Left-click belongs to the metric - it does whatever the addon that published it does, and that is the same for ours and for other addons'."] =
        "То же самое есть и на самой полосе: правая кнопка по ячейке прячет "
        .. "её, переставляет или переводит на другую полосу. Левая кнопка "
        .. "принадлежит показателю — она делает то, что делает опубликовавший "
        .. "его аддон, и у наших показателей и у чужих это одинаково.",

    ["the game refused a protected action (%s) while the panel was holding screen space. If this keeps happening, turn off the setting that moves the interface out of the way, and the panel will draw over the interface instead."] =
        "игра отказала защищённому действию (%s), пока панель держала место "
        .. "на экране. Если это повторяется, выключите настройку, сдвигающую "
        .. "интерфейс, — панель будет рисоваться поверх него.",

    ["the panel is on"] =
        "панель включена",

    ["the panel is off"] =
        "панель выключена",

    ["moving the interface out of the way is on"] =
        "сдвиг интерфейса включён",

    ["moving the interface out of the way is off"] =
        "сдвиг интерфейса выключен",

    ["asked for %d above and %d below"] =
        "попрошено: %d сверху и %d снизу",

    ["applied %d above and %d below"] =
        "применено: %d сверху и %d снизу",

    ["the change was refused: %s"] =
        "правка отвергнута: %s",

    ["the change is waiting for combat to end"] =
        "правка ждёт конца боя",

    ["this client does not hold UIParent by its top or bottom edge, so nothing was moved"] =
        "в этом клиенте UIParent не держится ни за верхний, ни за нижний край, "
        .. "поэтому ничего не сдвинуто",

    ["UIParent is not where the panel left it: %s"] =
        "UIParent стоит не там, где его оставила панель: %s",

    ["UIParent is exactly where the panel left it"] =
        "UIParent стоит ровно там, где его оставила панель",

    ["the last move did not take: %s"] =
        "последний сдвиг не применился: %s",

    ["the game refused a protected action %d times while the panel held screen space"] =
        "игра отказала защищённому действию %d раз, пока панель держала место "
        .. "на экране",

    ["cells shown: %d of %d in the registry"] =
        "показано ячеек: %d из %d в реестре",

    ["the panel is drawing"] = "панель рисует",
    ["the panel is not drawing"] = "панель не рисует",
    ["cells on the bars: %d above, %d below"] = "ячеек на полосах: %d сверху, %d снизу",
    ["the %s bar was never built"] = "полоса «%s» не строилась ни разу",
    ["the %s bar could not be built"] = "полосу «%s» построить не удалось",
    ["the %s bar: %s, %d by %d, opacity %.2f"] = "полоса «%s»: %s, %d на %d, прозрачность %.2f",
    ["shown"] = "показана",
    ["hidden"] = "спрятана",
    ["the %s bar is anchored to nothing"] = "полоса «%s» ни к чему не привязана",
    ["the %s bar: %s at %d, %d"] = "полоса «%s»: %s в точке %d, %d",
    ["Cells Go To"] = "Ячейки идут на",
    ["Opacity"] = "Непрозрачность",
    ["A bar of metrics at the edge of the screen. It draws at the screen edge and takes the space it needs from the interface below it."] =
        "Полоса показателей у края экрана. Она рисуется у самого края и " ..
        "забирает нужное ей место у интерфейса под собой.",
    ["Use the bar along the top of the screen."] =
        "Пользоваться полосой вдоль верхнего края экрана.",
    ["Use the bar along the bottom of the screen. Switching it on is not enough by itself: a bar draws the cells that sit on it, and every cell starts on the bar chosen below. Send cells to it one at a time in the list further down, or change that choice to move them all at once."] =
        "Пользоваться полосой вдоль нижнего края экрана. Одного включения " ..
        "мало: полоса рисует те ячейки, которые на ней стоят, а каждая " ..
        "ячейка начинает на полосе, выбранной ниже. Отправляйте ячейки по " ..
        "одной в списке дальше или смените тот выбор, чтобы перевести их " ..
        "все разом.",
    ["Which bar a cell uses when you have not sent it to one yourself. Changing this moves every cell you have not placed by hand."] =
        "На какой полосе стоит ячейка, пока вы не отправили её сами. Смена " ..
        "этого двигает все ячейки, которые вы не ставили руками.",
    ["How solid the bar is. It never goes all the way to invisible: a bar you cannot see is a bar that is switched off, and that is the checkbox above."] =
        "Насколько полоса плотная. До полной невидимости она не доходит: " ..
        "полоса, которую не видно, — это выключенная полоса, а выключает её " ..
        "галочка выше.",
    ["Hiding, moving and sending a cell to the other bar can also be done on the bar itself, by right-clicking the cell. Left-click belongs to the metric - it does whatever the addon that published it does, and that is the same for ours and for other addons'. A hidden cell is the one thing the bar cannot undo: it is not on the bar to be clicked."] =
        "Спрятать ячейку, переставить её и отправить на другую полосу можно " ..
        "и на самой полосе — правым щелчком по ячейке. Левый щелчок " ..
        "принадлежит показателю: он делает то, что делает опубликовавший " ..
        "его аддон, и это одинаково для наших и для чужих. Спрятанная " ..
        "ячейка — единственное, чего полоса отменить не может: её на полосе " ..
        "нет, и щёлкать не по чему.",
    ["A hidden cell cannot be brought back from the bar itself - it is not on it. This is the way back."] =
        "Спрятанную ячейку нельзя вернуть с самой полосы — её там нет. Это " ..
        "и есть путь назад.",
    ["Which of the two bars this cell sits on. A cell sent to a bar that is switched off is not drawn at all."] =
        "На которой из двух полос стоит эта ячейка. Ячейка, отправленная на " ..
        "выключенную полосу, не рисуется вовсе.",
    ["How tall the bar is."] = "Насколько полоса высока.",
    ["Take the bar's height away from the screen so nothing hides under it. On a client that does not let the addon move the interface, the bar draws over it instead and says so."] =
        "Отнять высоту полосы у экрана, чтобы под ней ничего не пряталось. " ..
        "На клиенте, который не даёт аддону двигать интерфейс, полоса " ..
        "рисуется поверх него и говорит об этом.",
    ["Write the time as twelve hours instead of twenty-four."] =
        "Писать время двенадцатью часами вместо двадцати четырёх.",
    ["Write seconds in the clock cell."] = "Писать секунды в ячейке часов.",
    ["Information Panel"] = "Информационная панель",
}
