local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("auras")

-- Русский перевод компактных аур.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод перестанет
-- находиться, а игрок увидит английскую подпись. Правка английского всегда
-- идёт парой — в месте вызова и здесь.

-- Таблица объявляется данными и ничем больше: складывает её в ядро Auras.lua,
-- когда получит описатель модуля (handle:RegisterStrings). Своего выбора
-- языка у модуля нет — язык клиента определяет ядро, и второе определение
-- разошлось бы с ним молча.

ns.Strings = ns.Strings or {}
ns.Strings.ruRU = {

    ["Darken Auras"] =
        "Ауры Darken",

    ["Draws Darken's own grid of buffs and debuffs instead of the "
        .. "game's: your own icon size, icons per row, growth direction, "
        .. "time left and stack count. Off by default - a fresh install "
        .. "changes nothing. Switching it off puts the game's own grid back "
        .. "straight away, with no interface reload."] =
        "Рисует свою сетку усилений и ослаблений вместо стандартной: свой "
        .. "размер значка, число значков в ряду, направление роста, "
        .. "оставшееся время и число стопок. По умолчанию выключено — свежая "
        .. "установка не меняет ничего. Выключение сразу возвращает "
        .. "стандартную сетку, без перезагрузки интерфейса.",

    ["Draw Our Own Auras"] =
        "Рисовать свои ауры",

    ["Off leaves the game's own buff and debuff grid exactly as it is, "
        .. "which is what a fresh install does."] =
        "Выключено оставляет стандартную сетку усилений и ослаблений ровно "
        .. "такой, какая она есть, — так же ведёт себя свежая установка.",

    ["Icon Size"] =
        "Размер значка",

    ["Icons Per Row"] =
        "Значков в ряду",

    ["Growth Direction"] =
        "Направление роста",

    ["Where the grid grows from its first icon: rows go one way, each row "
        .. "fills the other."] =
        "Куда сетка растёт от первого значка: ряды уходят в одну сторону, "
        .. "сам ряд заполняется в другую.",

    ["Show Time Left"] =
        "Показывать оставшееся время",

    ["Show Stack Count"] =
        "Показывать число стопок",

    ["A single stack is not written out: a \"1\" on every icon takes room "
        .. "and says nothing."] =
        "Одна стопка не пишется: цифра «1» на каждом значке занимает место и "
        .. "ничего не сообщает.",

    ["Separate Your Own Effects"] =
        "Отделять свои эффекты",

    ["Effects you cast yourself come first and everyone else's start on a "
        .. "fresh row."] =
        "Наложенное вами идёт первым, а чужое начинается с нового ряда.",

    ["Spacing Between Icons"] =
        "Зазор между значками",


    ["The grid is placed with " ..
        "the Darken mover: type /darken move and drag the box " ..
        "labelled Compact Auras, the same way you place " ..
        "everything else on screen. \"Reset Every Element\" in " ..
        "the mover's own settings puts it back."] =
        "Сетку ставит мувер Darken: наберите /darken move и перетащите " ..
        "прямоугольник с подписью «Компактные ауры» — так же, как вы " ..
        "ставите всё остальное на экране. «Сбросить все элементы» в " ..
        "настройках мувера возвращает её на место.",

    ["Down and to the left"] =
        "Вниз и влево",

    ["Down and to the right"] =
        "Вниз и вправо",

    ["Up and to the left"] =
        "Вверх и влево",

    ["Up and to the right"] =
        "Вверх и вправо",

    ["compact auras on"] =
        "компактные ауры включены",

    ["compact auras off"] =
        "компактные ауры выключены",

    ["Hide All Buffs"] =
        "Прятать все усиления",

    ["The whole block of buffs stops being drawn - that is what this asks "
        .. "for, and an empty block takes no room on the screen. The spell "
        .. "list is senior to it: with the list set to \"Show Only the "
        .. "Listed Spells\", a listed buff still shows. Off by default."] =
        "Блок усилений перестаёт рисоваться целиком — об этом настройка и "
        .. "просит, а пустой блок не занимает на экране места. Перечень "
        .. "заклинаний старше неё: если перечень стоит в режиме «показывать "
        .. "только эти», вписанное усиление показывается по-прежнему. Типово "
        .. "выключено.",

    ["Hide All Debuffs"] =
        "Прятать все ослабления",

    ["The whole block of debuffs stops being drawn, the same way. Debuffs "
        .. "are what other things put on you, so this one has no \"only "
        .. "mine\" of its own: there would be nothing left to narrow. Off "
        .. "by default."] =
        "Блок ослаблений перестаёт рисоваться целиком, тем же способом. "
        .. "Ослабления на игрока накладывает кто угодно, только не он сам, "
        .. "поэтому своего «только свои» у них нет: сужать было бы нечего. "
        .. "Типово выключено.",

    ["Both are on, so no aura is drawn at all - and the game's own grid is "
        .. "already gone. Only the spell list can bring anything back: set "
        .. "it to \"Show Only the Listed Spells\" and name what you want "
        .. "to keep."] =
        "Включены оба, и ни одна аура не рисуется вовсе — а стандартная сетка "
        .. "к этому моменту уже уведена. Вернуть хоть что-то умеет только "
        .. "перечень заклинаний: поставьте ему режим «показывать только "
        .. "эти» и назовите то, что хотите оставить.",

    ["Show Only Buffs You Cast"] =
        "Показывать только свои усиления",

    ["Buffs put on you by other players stop being drawn. Debuffs are "
        .. "never touched by this: what lands on you from outside is exactly "
        .. "what you need to see. With \"hide all buffs\" on there is "
        .. "nothing left for this to narrow, and it is greyed out."] =
        "Усиления, наложенные на вас другими игроками, перестают рисоваться. "
        .. "Ослаблений это не касается никогда: то, что прилетает извне, — "
        .. "ровно то, что нужно видеть. При включённом «прятать все "
        .. "усиления» сужать этой настройке уже нечего, и она погашена.",

    ["What the Spell List Does"] =
        "Что делает список заклинаний",

    ["An empty list does nothing whichever of these is chosen."] =
        "Пустой список не делает ничего, что бы здесь ни было выбрано.",

    ["Spell List"] =
        "Список заклинаний",

    ["One spell per line, or separated by commas. A spell id - a number - "
        .. "matches that one spell exactly and keeps working when you change "
        .. "the client's language; a name matches whatever this client calls "
        .. "the spell, and two different spells can share a name."] =
        "Одно заклинание в строке или через запятую. Номер заклинания — "
        .. "число — совпадает ровно с одним заклинанием и продолжает "
        .. "работать после смены языка клиента; название совпадает с тем, "
        .. "как это заклинание зовётся в этом клиенте, а два разных "
        .. "заклинания могут зваться одинаково.",

    ["Nothing - keep the list, ignore it"] =
        "Ничего — список остаётся, отбор выключен",

    ["Hide the Listed Spells"] =
        "Прятать перечисленные заклинания",

    ["Show Only the Listed Spells"] =
        "Показывать только перечисленные заклинания",

    ["Tooltip and Right-Click to Cancel"] =
        "Подсказка и снятие правой кнопкой",

    ["Pointing at an icon shows the game's own description of the aura, and "
        .. "right-clicking a buff cancels it - the two things the game's own "
        .. "grid does. Cancelling is an action the game forbids in combat, "
        .. "so in combat the right click does nothing at all: cancelling the "
        .. "wrong aura would be worse than cancelling none. The tooltip "
        .. "works in combat like everywhere else."] =
        "Наведение на значок показывает описание ауры, которое даёт сама "
        .. "игра, а правая кнопка снимает усиление — то же самое, что умеет "
        .. "стандартная сетка. Снятие движок в бою запрещает, поэтому в бою "
        .. "правая кнопка не делает ничего: снять не ту ауру хуже, чем не "
        .. "снять никакую. Подсказка в бою работает как всюду.",
    -- === Правила на отдельную ауру ===

    ["A rule gives named spells an icon of their own: its own size, its own "
        .. "border color and a sound when it runs out. A rule never shows an "
        .. "aura the spell list hides, and never hides one it shows - what "
        .. "to draw is the list's answer, and a rule only says how. With no "
        .. "rules nothing changes."] =
        "Правило даёт названным заклинаниям свой значок: свой размер, свой "
        .. "цвет рамки и звук на окончание. Правило не показывает ауру, "
        .. "которую спрятал список заклинаний, и не прячет ту, которую он "
        .. "показал: что рисовать — ответ списка, а правило говорит только "
        .. "как. Без правил не меняется ничего.",

    ["No rules yet, so every icon looks the same. A rule names spells - by "
        .. "name, or by spell id for a name that is different in every "
        .. "language - and gives them their own icon size, their own border "
        .. "color and a sound when they run out. Rules are tried from the "
        .. "top down, and the first one that names a spell wins it."] =
        "Правил пока нет, и все значки выглядят одинаково. Правило называет "
        .. "заклинания — по названию или по номеру, если название в каждом "
        .. "языке своё, — и даёт им свой размер значка, свой цвет рамки и "
        .. "звук на окончание. Правила пробуются сверху вниз, и заклинание "
        .. "достаётся первому, кто его назвал.",

    ["%d. %s"] = "%d. %s",

    ["Rule to Edit"] = "Правило для правки",

    ["Pick a rule to change it, move it or forget it. Leave it unpicked, and "
        .. "the fields below describe a new rule instead."] =
        "Выберите правило, чтобы изменить его, передвинуть или забыть. Ничего "
        .. "не выбрано — поля ниже описывают новое правило.",

    ["Start a New Rule"] = "Завести новое правило",

    ["Rule Name"] = "Имя правила",

    ["Yours, not the game's: it is how the rule is named in the list above."] =
        "Ваше, а не игровое: так правило зовётся в перечне выше.",

    ["Spells"] = "Заклинания",

    ["Spell names, separated by commas or written one per line, and capitals "
        .. "do not matter. An entry of digits only is read as a spell id "
        .. "instead - the same door the spell list above uses."] =
        "Названия заклинаний через запятую или по одному в строке; регистр "
        .. "не важен. Запись из одних цифр читается как номер заклинания — "
        .. "той же дверью, что и список заклинаний выше.",

    ["Size of Those Icons"] = "Размер этих значков",

    ["Multiplies the icon size set above, so one means no change at all. The "
        .. "icon grows inside its own cell of the grid and the grid itself "
        .. "does not move: the set of auras changes constantly, and a grid "
        .. "that laid itself out again around one aura would never stand "
        .. "still."] =
        "Множитель к размеру значка, заданному выше: единица не меняет "
        .. "ничего. Значок растёт внутри своей клетки сетки, а сама сетка не "
        .. "двигается: набор аур меняется постоянно, и сетка, которая "
        .. "перекладывалась бы под одну ауру, не стояла бы на месте никогда.",

    ["Give It Its Own Border"] = "Своя рамка у этого правила",

    ["Off leaves the border the usual color and the rule changes the size "
        .. "only."] =
        "Выключено оставляет рамку обычного цвета, и правило меняет один "
        .. "размер.",

    ["Border Color"] = "Цвет рамки",

    ["From the addon's own palette, so the icon stays part of the same "
        .. "interface when the palette changes."] =
        "Из палитры самого аддона: значок остаётся частью того же интерфейса "
        .. "и тогда, когда палитра поменяется.",

    ["Sound When It Runs Out"] = "Звук на окончание",

    ["Plays the game's warning sound once when one of these auras is gone "
        .. "from you. Only that: an aura that stopped being drawn because "
        .. "you changed a setting, and auras missing because you have just "
        .. "zoned in, make no sound at all - a sound that lies is worse than "
        .. "no sound."] =
        "Один раз играет предупреждающий звук игры, когда одна из этих аур с "
        .. "вас ушла. Только это: аура, переставшая рисоваться из-за правки "
        .. "настройки, и ауры, которых нет после смены зоны, не звучат вовсе "
        .. "— звук, который врёт, хуже, чем никакого.",

    ["Add This Rule"] = "Завести это правило",

    ["Try This Rule Earlier"] = "Пробовать это правило раньше",

    ["Try This Rule Later"] = "Пробовать это правило позже",

    ["Forget This Rule"] = "Забыть это правило",

    ["forgot the rule %s"] = "правило %s забыто",

    ["a rule needs a name"] = "правилу нужно имя",

    ["a rule needs at least one spell name or id"] =
        "правилу нужно хотя бы одно название или номер заклинания",

    ["there is already a rule with that name"] =
        "правило с таким именем уже есть",

    ["that name is too long"] = "это имя слишком длинное",

    ["there is no room for another rule"] = "больше правил не помещается",

    ["that rule is gone"] = "такого правила больше нет",

    -- Имена цветов палитры оформления. Переведены те, что палитра объявляет
    -- сегодня; появившееся завтра покажется своим именем, и это лучше, чем
    -- не показаться вовсе.
    ["Ink"] = "Тёмный",
    ["Panel"] = "Панель",
    ["Panel, darker"] = "Панель, темнее",
    ["Line - the usual border"] = "Линия — обычная рамка",
    ["Lilac"] = "Сиреневый",
    ["Lilac, deep"] = "Сиреневый, глубокий",
    ["Text"] = "Текст",
    ["Text, dim"] = "Текст, приглушённый",
    -- === Ауры на юнитфреймах ===

    ["Also on Target, Focus and Party"] =
        "Ещё на цели, фокусе и группе",

    ["Carries the filter and the rules onto the auras the game draws on unit "
        .. "frames: a spell you hid here stops showing up on your target "
        .. "too, and a rule's border color reaches it. The game keeps the "
        .. "layout - those icons belong to its own frames, and taking them "
        .. "over would mean re-laying them out in combat, on frames the game "
        .. "protects. Off by default."] =
        "Переносит отбор и правила на ауры, которые игра рисует на "
        .. "юнитфреймах: заклинание, спрятанное здесь, перестаёт "
        .. "показываться и на цели, а цвет рамки правила достаёт и туда. "
        .. "Раскладку игра оставляет себе — эти значки принадлежат её "
        .. "собственным фреймам, и забрать их значило бы раскладывать их "
        .. "заново в бою, на фреймах, которые игра защищает. По умолчанию "
        .. "выключено.",
    ["What Gets Drawn"] = "Что рисуется",
    ["Spacing and Place"] = "Зазор и место",
    ["Rules"] = "Правила",
    ["Auras"] = "Ауры",
}
