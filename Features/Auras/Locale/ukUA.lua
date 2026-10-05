local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("auras")

-- Украинский перевод компактных аур.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод перестанет
-- находиться, а игрок увидит английскую подпись. Правка английского всегда
-- идёт парой — в месте вызова и здесь.

-- Слова автора для этого модуля: «аура», «значок», «ряд», «стопка», «час»,
-- «напрямок». Синонимы не заводятся: два слова для одного и того же в одном
-- разделе настроек читаются как две разные вещи.

ns.Strings = ns.Strings or {}
ns.Strings.ukUA = {

    ["Darken Auras"] =
        "Аури Darken",

    ["Draws Darken's own grid of buffs and debuffs instead of the "
        .. "game's: your own icon size, icons per row, growth direction, "
        .. "time left and stack count. Off by default - a fresh install "
        .. "changes nothing. Switching it off puts the game's own grid back "
        .. "straight away, with no interface reload."] =
        "Малює власну сітку посилень і послаблень замість стандартної: "
        .. "власний розмір значка, кількість значків у ряду, напрямок "
        .. "росту, час, що лишився, і кількість стопок. Типово вимкнено — "
        .. "свіже встановлення не змінює нічого. Вимикання одразу повертає "
        .. "стандартну сітку, без перезавантаження інтерфейсу.",

    ["Draw Our Own Auras"] =
        "Малювати власні аури",

    ["Off leaves the game's own buff and debuff grid exactly as it is, "
        .. "which is what a fresh install does."] =
        "Вимкнено лишає стандартну сітку посилень і послаблень такою, якою "
        .. "вона є, — так само поводиться свіже встановлення.",

    ["Icon Size"] =
        "Розмір значка",

    ["Icons Per Row"] =
        "Значків у ряду",

    ["Growth Direction"] =
        "Напрямок росту",

    ["Where the grid grows from its first icon: rows go one way, each row "
        .. "fills the other."] =
        "Куди сітка росте від першого значка: ряди йдуть в один бік, сам ряд "
        .. "заповнюється в інший.",

    ["Show Time Left"] =
        "Показувати час, що лишився",

    ["Show Stack Count"] =
        "Показувати кількість стопок",

    ["A single stack is not written out: a \"1\" on every icon takes room "
        .. "and says nothing."] =
        "Одна стопка не пишеться: цифра «1» на кожному значку займає місце й "
        .. "нічого не повідомляє.",

    ["Separate Your Own Effects"] =
        "Відділяти власні ефекти",

    ["Effects you cast yourself come first and everyone else's start on a "
        .. "fresh row."] =
        "Накладене вами йде першим, а чуже починається з нового ряду.",

    ["Spacing Between Icons"] =
        "Проміжок між значками",


    ["The grid is placed with " ..
        "the Darken mover: type /darken move and drag the box " ..
        "labelled Compact Auras, the same way you place " ..
        "everything else on screen. \"Reset Every Element\" in " ..
        "the mover's own settings puts it back."] =
        "Сітку ставить мувер Darken: наберіть /darken move і пересуньте " ..
        "прямокутник із підписом «Компактні аури» — так само, як ви " ..
        "ставите все інше на екрані. «Скинути всі елементи» в " ..
        "налаштуваннях мувера повертає її на місце.",

    ["Down and to the left"] =
        "Униз і ліворуч",

    ["Down and to the right"] =
        "Униз і праворуч",

    ["Up and to the left"] =
        "Угору і ліворуч",

    ["Up and to the right"] =
        "Угору і праворуч",

    ["compact auras on"] =
        "компактні аури увімкнено",

    ["compact auras off"] =
        "компактні аури вимкнено",

    ["Hide All Buffs"] =
        "Приховувати всі посилення",

    ["The whole block of buffs stops being drawn - that is what this asks "
        .. "for, and an empty block takes no room on the screen. The spell "
        .. "list is senior to it: with the list set to \"Show Only the "
        .. "Listed Spells\", a listed buff still shows. Off by default."] =
        "Блок посилень перестає малюватися цілком — саме про це вимикач і "
        .. "просить, а порожній блок не займає на екрані місця. Перелік "
        .. "заклинань старший за нього: якщо перелік стоїть у режимі "
        .. "«показувати лише ці», вписане посилення показується, як і "
        .. "раніше. Типово вимкнено.",

    ["Hide All Debuffs"] =
        "Приховувати всі послаблення",

    ["The whole block of debuffs stops being drawn, the same way. Debuffs "
        .. "are what other things put on you, so this one has no \"only "
        .. "mine\" of its own: there would be nothing left to narrow. Off "
        .. "by default."] =
        "Блок послаблень перестає малюватися цілком, у той самий спосіб. "
        .. "Послаблення на гравця накладає хто завгодно, тільки не він сам, "
        .. "тому власного «тільки власні» в них немає: звужувати було б "
        .. "нічого. Типово вимкнено.",

    ["Both are on, so no aura is drawn at all - and the game's own grid is "
        .. "already gone. Only the spell list can bring anything back: set "
        .. "it to \"Show Only the Listed Spells\" and name what you want "
        .. "to keep."] =
        "Увімкнено обидва, і жодна аура не малюється взагалі — а стандартну "
        .. "сітку на цей час уже забрано. Повернути хоч щось уміє тільки "
        .. "перелік заклинань: поставте йому режим «показувати лише ці» й "
        .. "назвіть те, що хочете лишити.",

    ["Show Only Buffs You Cast"] =
        "Показувати тільки власні посилення",

    ["Buffs put on you by other players stop being drawn. Debuffs are "
        .. "never touched by this: what lands on you from outside is exactly "
        .. "what you need to see. With \"hide all buffs\" on there is "
        .. "nothing left for this to narrow, and it is greyed out."] =
        "Посилення, накладені на вас іншими гравцями, перестають малюватися. "
        .. "Послаблень це не торкається ніколи: те, що прилітає ззовні, — "
        .. "саме те, що треба бачити. За увімкненого «приховувати всі "
        .. "посилення» звужувати цьому вимикачеві вже нічого, і його "
        .. "погашено.",

    ["What the Spell List Does"] =
        "Що робить перелік заклинань",

    ["An empty list does nothing whichever of these is chosen."] =
        "Порожній перелік не робить нічого, хоч би що тут було обрано.",

    ["Spell List"] =
        "Перелік заклинань",

    ["One spell per line, or separated by commas. A spell id - a number - "
        .. "matches that one spell exactly and keeps working when you change "
        .. "the client's language; a name matches whatever this client calls "
        .. "the spell, and two different spells can share a name."] =
        "Одне заклинання на рядок або через кому. Номер заклинання — число — "
        .. "збігається рівно з одним заклинанням і працює далі, коли ви "
        .. "зміните мову клієнта; назва збігається з тим, як це заклинання "
        .. "зветься в цьому клієнті, а два різні заклинання можуть зватися "
        .. "однаково.",

    ["Nothing - keep the list, ignore it"] =
        "Нічого — перелік лишається, фільтр вимкнено",

    ["Hide the Listed Spells"] =
        "Приховувати перелічені заклинання",

    ["Show Only the Listed Spells"] =
        "Показувати лише перелічені заклинання",

    ["Tooltip and Right-Click to Cancel"] =
        "Підказка і скасування правою кнопкою",

    ["Pointing at an icon shows the game's own description of the aura, and "
        .. "right-clicking a buff cancels it - the two things the game's own "
        .. "grid does. Cancelling is an action the game forbids in combat, "
        .. "so in combat the right click does nothing at all: cancelling the "
        .. "wrong aura would be worse than cancelling none. The tooltip "
        .. "works in combat like everywhere else."] =
        "Наведення на значок показує підказку з описом аури, який дає сама "
        .. "гра, а права кнопка скасовує посилення — те саме, що вміє "
        .. "стандартна сітка. Скасування рушій у бою забороняє, тому в бою "
        .. "права кнопка не робить нічого: скасувати не ту ауру гірше, ніж "
        .. "не скасувати жодної. Підказка в бою працює як усюди.",
    -- === Правила на окрему ауру ===

    ["A rule gives named spells an icon of their own: its own size, its own "
        .. "border color and a sound when it runs out. A rule never shows an "
        .. "aura the spell list hides, and never hides one it shows - what "
        .. "to draw is the list's answer, and a rule only says how. With no "
        .. "rules nothing changes."] =
        "Правило дає названим заклинанням свій значок: свій розмір, свій "
        .. "колір рамки і звук на закінчення. Правило не показує ауру, яку "
        .. "сховав перелік заклинань, і не ховає ту, яку він показав: що "
        .. "малювати — відповідь переліку, а правило каже лише як. Без "
        .. "правил не змінюється нічого.",

    ["No rules yet, so every icon looks the same. A rule names spells - by "
        .. "name, or by spell id for a name that is different in every "
        .. "language - and gives them their own icon size, their own border "
        .. "color and a sound when they run out. Rules are tried from the "
        .. "top down, and the first one that names a spell wins it."] =
        "Правил поки немає, і всі значки виглядають однаково. Правило "
        .. "називає заклинання — назвою або номером, якщо назва в кожній "
        .. "мові своя, — і дає їм свій розмір значка, свій колір рамки і "
        .. "звук на закінчення. Правила пробуються згори вниз, і заклинання "
        .. "дістається першому, хто його назвав.",

    ["%d. %s"] = "%d. %s",

    ["Rule to Edit"] = "Правило для правки",

    ["Pick a rule to change it, move it or forget it. Leave it unpicked, and "
        .. "the fields below describe a new rule instead."] =
        "Виберіть правило, щоб змінити його, пересунути або забути. Нічого "
        .. "не вибрано — поля нижче описують нове правило.",

    ["Start a New Rule"] = "Завести нове правило",

    ["Rule Name"] = "Імʼя правила",

    ["Yours, not the game's: it is how the rule is named in the list above."] =
        "Ваше, а не ігрове: так правило зветься в переліку вище.",

    ["Spells"] = "Заклинання",

    ["Spell names, separated by commas or written one per line, and capitals "
        .. "do not matter. An entry of digits only is read as a spell id "
        .. "instead - the same door the spell list above uses."] =
        "Назви заклинань через кому або по одній у рядку; регістр не має "
        .. "значення. Запис із самих цифр читається як номер заклинання — "
        .. "тими самими дверима, що й перелік заклинань вище.",

    ["Size of Those Icons"] = "Розмір цих значків",

    ["Multiplies the icon size set above, so one means no change at all. The "
        .. "icon grows inside its own cell of the grid and the grid itself "
        .. "does not move: the set of auras changes constantly, and a grid "
        .. "that laid itself out again around one aura would never stand "
        .. "still."] =
        "Множник до розміру значка, заданого вище: одиниця не змінює нічого. "
        .. "Значок росте всередині своєї клітинки сітки, а сама сітка не "
        .. "рухається: набір аур змінюється постійно, і сітка, яка "
        .. "перекладалася б під одну ауру, не стояла б на місці ніколи.",

    ["Give It Its Own Border"] = "Своя рамка в цього правила",

    ["Off leaves the border the usual color and the rule changes the size "
        .. "only."] =
        "Вимкнено лишає рамку звичайного кольору, і правило змінює лише "
        .. "розмір.",

    ["Border Color"] = "Колір рамки",

    ["From the addon's own palette, so the icon stays part of the same "
        .. "interface when the palette changes."] =
        "З палітри самого аддона: значок лишається частиною того самого "
        .. "інтерфейсу й тоді, коли палітра зміниться.",

    ["Sound When It Runs Out"] = "Звук на закінчення",

    ["Plays the game's warning sound once when one of these auras is gone "
        .. "from you. Only that: an aura that stopped being drawn because "
        .. "you changed a setting, and auras missing because you have just "
        .. "zoned in, make no sound at all - a sound that lies is worse than "
        .. "no sound."] =
        "Один раз грає попереджувальний звук гри, коли одна з цих аур із вас "
        .. "зійшла. Тільки це: аура, що перестала малюватися через правку "
        .. "налаштування, і аури, яких немає після зміни зони, не звучать "
        .. "зовсім — звук, який бреше, гірший за жодний.",

    ["Add This Rule"] = "Завести це правило",

    ["Try This Rule Earlier"] = "Пробувати це правило раніше",

    ["Try This Rule Later"] = "Пробувати це правило пізніше",

    ["Forget This Rule"] = "Забути це правило",

    ["forgot the rule %s"] = "правило %s забуто",

    ["a rule needs a name"] = "правилу потрібне імʼя",

    ["a rule needs at least one spell name or id"] =
        "правилу потрібна хоча б одна назва або номер заклинання",

    ["there is already a rule with that name"] =
        "правило з таким імʼям уже є",

    ["that name is too long"] = "це імʼя завелике",

    ["there is no room for another rule"] = "більше правил не вміщається",

    ["that rule is gone"] = "такого правила більше немає",

    -- Імена кольорів палітри оформлення. Перекладені ті, що палітра оголошує
    -- сьогодні; те, що зʼявиться завтра, покажеться своїм іменем, і це краще,
    -- ніж не показатися зовсім.
    ["Ink"] = "Темний",
    ["Panel"] = "Панель",
    ["Panel, darker"] = "Панель, темніша",
    ["Line - the usual border"] = "Лінія — звичайна рамка",
    ["Lilac"] = "Бузковий",
    ["Lilac, deep"] = "Бузковий, глибокий",
    ["Text"] = "Текст",
    ["Text, dim"] = "Текст, приглушений",
    -- === Аури на юнітфреймах ===

    ["Also on Target, Focus and Party"] =
        "Також на цілі, фокусі й групі",

    ["Carries the filter and the rules onto the auras the game draws on unit "
        .. "frames: a spell you hid here stops showing up on your target "
        .. "too, and a rule's border color reaches it. The game keeps the "
        .. "layout - those icons belong to its own frames, and taking them "
        .. "over would mean re-laying them out in combat, on frames the game "
        .. "protects. Off by default."] =
        "Переносить відбір і правила на аури, які гра малює на юнітфреймах: "
        .. "заклинання, приховане тут, більше не показується й на цілі, а "
        .. "колір рамки правила сягає і туди. Розкладку гра лишає собі — ті "
        .. "значки належать її власним фреймам, і забрати їх означало б "
        .. "розкладати їх наново в бою, на фреймах, які гра захищає. Типово "
        .. "вимкнено.",
    ["What Gets Drawn"] = "Що малюється",
    ["Spacing and Place"] = "Відступ і місце",
    ["Rules"] = "Правила",
    ["Auras"] = "Аури",
}
