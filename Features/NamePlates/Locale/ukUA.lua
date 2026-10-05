local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("nameplates")

-- Украинский перевод движка неймплейтов.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод перестанет
-- находиться, а игрок увидит английскую подпись. Правка английского всегда
-- идёт парой — в месте вызова и здесь.

-- Таблица объявляется данными и ничем больше: складывает её в ядро
-- NamePlates.lua, когда получит описатель модуля (handle:RegisterStrings).
-- Своего выбора языка у модуля нет — язык клиента определяет ядро, и второе
-- определение разошлось бы с ним молча.

ns.Strings = ns.Strings or {}
ns.Strings.ukUA = {

    ["Game's Own Texture"] =
        "Рідна текстура гри",

    ["Darken Nameplates"] =
        "Неймплейти Darken",

    ["Draws Darken's own nameplates instead of dressing the "
        .. "game's: health bar, name, level, a mark on your target and - "
        .. "each switched on separately below - a cast bar, aura icons, "
        .. "threat color and a quest mark. Off by default - a fresh "
        .. "install changes nothing. Switching it on takes nameplates "
        .. "over from Darken's own plate styling, which stands down "
        .. "while this is on and comes back when it is switched "
        .. "off."] =
        "Малює власні неймплейти Darken замість оформлення "
        .. "стандартних: смужка здоров'я, ім'я, рівень, позначка цілі та "
        .. "— кожне вмикається окремо нижче — смужка застосування, "
        .. "значки аур, колір за загрозою і значок квеста. Типово "
        .. "вимкнено: свіже встановлення не змінює нічого. Увімкнення "
        .. "забирає неймплейти у власного оформлення Darken: воно "
        .. "відходить убік, доки це ввімкнено, і повертається, коли "
        .. "вимкнено.",

    ["Draw Our Own Nameplates"] =
        "Малювати свої неймплейти",

    ["Off leaves the game's nameplates exactly as they are, "
        .. "which is what a fresh install does."] =
        "Вимкнено лишає неймплейти гри рівно такими, якими вони є, "
        .. "— так і поводиться свіже встановлення.",

    ["Health Bar Texture"] =
        "Текстура смужки здоров'я",

    ["The first entry is the game's own bar texture. The addon's "
        .. "own textures are a gradient from white to a color, and the "
        .. "bar color multiplies them."] =
        "Перший запис — рідна текстура гри. Авторські текстури — "
        .. "градієнт від білого до кольору, і колір смужки їх множить.",

    ["Nameplate Width"] =
        "Ширина неймплейта",

    ["Health Bar Height"] =
        "Висота смужки здоров'я",

    ["Nameplate Scale"] =
        "Масштаб неймплейта",

    ["Scales the whole nameplate, text included. Width and "
        .. "height above are measured before this."] =
        "Масштабує неймплейт цілком, разом із текстом. Ширина й "
        .. "висота вище вимірюються до масштабу.",

    ["\"%s\" already draws nameplates, so Darken's nameplate "
        .. "engine stays out of the way: two engines on one frame give "
        .. "flicker and errors."] =
        "Неймплейти вже малює «%s», тому рушій неймплейтів Darken "
        .. "відступає: два рушії на одному фреймі дають миготіння й "
        .. "помилки.",

    ["this client has no nameplate API, so the nameplate engine "
        .. "does nothing here"] =
        "у цьому клієнті немає API неймплейтів, тому рушій "
        .. "неймплейтів тут нічого не робить",

    ["nameplate engine on"] =
        "рушій неймплейтів увімкнено",

    ["nameplate engine off"] =
        "рушій неймплейтів вимкнено",

    ["Shorten Long Names"] =
        "Скорочувати довгі імена",
    ["Cuts a name that does not fit the nameplate width and marks "
        .. "the cut with three dots. Off leaves long names running past "
        .. "the bar."] =
        "Обрізає ім'я, яке не вміщується в ширину неймплейта, і "
        .. "позначає зріз трьома крапками. Вимкнено — довгі імена "
        .. "виїжджають за смужку.",
    ["Color by Threat"] =
        "Колір за загрозою",
    ["Colors the health bar of unfriendly creatures by how close "
        .. "they are to attacking you. Threat outranks class and "
        .. "reaction color, and only while it has something to say: a "
        .. "creature nobody is fighting keeps its own color."] =
        "Фарбує смужку недружніх істот за тим, наскільки вони близькі "
        .. "до того, щоб напасти на вас. Загроза старша за колір класу й "
        .. "реакції, і лише доки їй є що сказати: істота, з якою ніхто "
        .. "не б'ється, лишається свого кольору.",
    ["Mark Quest Targets"] =
        "Позначати цілі квестів",
    ["Puts a small mark beside the nameplate of a creature one of "
        .. "your quests wants."] =
        "Ставить невелику позначку поряд з неймплейтом істоти, яка "
        .. "потрібна одному з ваших квестів.",
    ["Cast Bar on the Nameplate"] =
        "Смужка застосування на неймплейті",
    ["Shows what the creature is casting under its health bar. The "
        .. "bar is moved by the engine itself, so it costs nothing per "
        .. "frame. This is the nameplate's own cast bar - your own cast "
        .. "bar belongs to Darken and to the cast bars module."] =
        "Показує під смужкою здоров'я те, що істота застосовує. "
        .. "Смужку рухає сам рушій, тому на кадр вона не коштує нічого. "
        .. "Це смужка застосування неймплейта — ваша власна належить "
        .. "Darken та модулю смужок застосування.",
    ["Cast Bar Height"] =
        "Висота смужки застосування",
    ["Aura Icons"] =
        "Значки аур",
    ["Shows aura icons above the nameplate. Which auras pass is "
        .. "set below. Time left is drawn by the engine's own sweep, so "
        .. "the icons cost nothing per frame."] =
        "Показує значки аур над неймплейтом. Які аури проходять, "
        .. "задається нижче. Залишок часу малює затемнення самого рушія, "
        .. "тому на кадр значки не коштують нічого.",
    ["Show Harmful Auras"] =
        "Показувати шкідливі аури",
    ["Show Helpful Auras"] =
        "Показувати корисні аури",
    ["Only Auras You Applied"] =
        "Лише власні аури",
    ["A creature in a raid carries everybody's auras. Off shows "
        .. "all of them, which in a busy fight is a wall of icons. On by "
        .. "default."] =
        "На істоті в рейді висять аури всіх одразу. Вимкнено — "
        .. "показуються всі, і в людному бою це стіна значків. Типово "
        .. "увімкнено.",
    ["How Many Icons at Most"] =
        "Скільки значків щонайбільше",
    ["Aura Icon Size"] =
        "Розмір значка аури",
    ["What to Do with the List"] =
        "Що робити зі списком",
    ["An empty list means the list is not used at all, whichever "
        .. "entry is picked here."] =
        "Порожній список означає, що список не використовується "
        .. "взагалі, хоч би який пункт тут було обрано.",
    ["Spell List"] =
        "Список заклинань",
    ["Spell names, separated by commas or written one per line. A "
        .. "name written in the list is shown even when \"only auras you "
        .. "applied\" is on - naming a spell is already an answer."] =
        "Імена заклинань через кому або по одному в рядку. Назване в "
        .. "списку показується навіть за увімкненого «лише власні аури»: "
        .. "назвати заклинання — це вже відповідь.",
    ["Show Every Aura That Passes"] =
        "Показувати все, що пройшло",
    ["Show Only the Listed Spells"] =
        "Показувати лише названі",
    ["Hide the Listed Spells"] =
        "Ховати названі",

    -- === Правила на окремого юніта ===

    ["A rule gives named "
        .. "creatures a nameplate of their own. Its color outranks "
        .. "class and reaction color, because you named the creature "
        .. "by hand and those are guesses - but threat color still "
        .. "outranks the rule, so a creature turning on you is never "
        .. "hidden by it. With no rules nothing changes."] =
        "Правило дає названим істотам власний неймплейт. Його колір "
        .. "старший за колір за класом і за реакцією: істоту назвали "
        .. "ви самі, а клас і реакція — здогадки. Але колір за "
        .. "загрозою старший за правило, тож істоту, яка розвернулася "
        .. "на вас, правило не сховає. Без правил не змінюється "
        .. "нічого.",

    ["No rules yet, so every nameplate looks the same. "
        .. "A rule names creatures - by name, or by creature id for a "
        .. "name that is different in every language - and gives them "
        .. "their own color and their own size. Rules are tried from the "
        .. "top down, and the first one that names a creature wins it."] =
        "Правил поки немає, і всі неймплейти виглядають однаково. "
        .. "Правило називає істот — іменем або номером істоти, якщо "
        .. "ім'я кожною мовою своє, — і дає їм власний колір і "
        .. "власний розмір. Правила пробуються згори вниз, і істота "
        .. "дістається першому, хто її назвав.",

    ["%d. %s"] =
        "%d. %s",
    ["Rule to Edit"] =
        "Правило для правки",
    ["Pick a rule to change it, "
        .. "move it or forget it. Leave it unpicked, and the fields "
        .. "below describe a new rule instead."] =
        "Оберіть правило, щоб змінити його, пересунути або забути. Не "
        .. "обрано — поля нижче описують нове правило.",
    ["Start a New Rule"] =
        "Завести нове правило",
    ["Rule Name"] =
        "Ім'я правила",
    ["Yours, not the game's: it "
        .. "is how the rule is named in the list above."] =
        "Ваше, а не ігрове: цим іменем правило названо в переліку "
        .. "вище.",
    ["Creatures"] =
        "Істоти",
    ["Creature names, separated "
        .. "by commas or written one per line, and capitals do not "
        .. "matter. An entry of digits only is read as a creature id "
        .. "instead: a name belongs to the language of your client "
        .. "and is not unique, an id is neither."] =
        "Імена істот через кому або по одному в рядку; регістр не "
        .. "важить. Запис із самих цифр читається як номер істоти: "
        .. "ім'я належить мові клієнта і не унікальне, а номер — ні "
        .. "те, ні інше.",
    ["Health Bar Color"] =
        "Колір смужки здоров'я",
    ["The color this rule paints "
        .. "the health bar and the name with. Threat color still "
        .. "outranks it."] =
        "Колір, яким правило фарбує смужку здоров'я та ім'я. Колір за "
        .. "загрозою однаково старший.",
    ["Use That Color"] =
        "Використовувати цей колір",
    ["Off leaves the color alone "
        .. "and the rule changes the size only."] =
        "Вимкнено — колір не чіпається, і правило змінює лише "
        .. "розмір.",
    ["Size of Those Nameplates"] =
        "Розмір цих неймплейтів",
    ["Multiplies the nameplate "
        .. "scale set above, so one means no change at all."] =
        "Множить загальний масштаб неймплейта, заданий вище: одиниця "
        .. "означає «не змінювати».",
    ["Add This Rule"] =
        "Додати це правило",
    ["Try This Rule Earlier"] =
        "Пробувати це правило раніше",
    ["Try This Rule Later"] =
        "Пробувати це правило пізніше",
    ["Forget This Rule"] =
        "Забути це правило",
    ["forgot the rule %s"] =
        "правило %s забуто",

    ["a rule needs a name"] =
        "у правила має бути ім'я",
    ["a rule needs at least one creature name or id"] =
        "правило має назвати хоча б одну істоту — іменем або номером",
    ["there is already a rule with that name"] =
        "правило з таким іменем уже є",
    ["that name is too long"] =
        "це ім'я задовге",
    ["there is no room for another rule"] =
        "місця ще на одне правило немає",
    ["that rule is gone"] =
        "цього правила більше немає",
    -- === Розташування частин неймплейта ===
    ["Name"] =
        "Ім'я",
    ["Level"] =
        "Рівень",
    ["Cast Bar"] =
        "Смужка застосування",
    ["Quest Mark"] =
        "Значок квеста",
    ["The Whole Nameplate"] =
        "Увесь неймплейт",

    ["Above"] =
        "Згори",
    ["Below"] =
        "Знизу",
    ["Left"] =
        "Ліворуч",
    ["Right"] =
        "Праворуч",
    ["On the Health Bar"] =
        "Поверх смужки здоров'я",
    ["Where the Game Puts It"] =
        "Там, де його ставить гра",

    ["The engine has not taken a single "
        .. "nameplate over this session, so there is nothing "
        .. "here to arrange: a part cannot be placed on a "
        .. "nameplate that is not on screen. Switch the "
        .. "engine on above, go where there are creatures, "
        .. "and these controls are here the next time you "
        .. "open this window."] =
        "За цей сеанс рушій не взяв під себе жодного неймплейта, тож "
        .. "розташовувати тут нічого: частину не поставити на неймплейт, "
        .. "якого немає на екрані. Увімкніть рушій вище, вийдіть туди, де "
        .. "є істоти, і наступного разу, коли відкриєте це вікно, "
        .. "налаштування будуть тут.",
    ["Where each part of the nameplate sits. "
        .. "Pick a part, pick the side it sits on, and nudge it "
        .. "with the two offsets. Sides are counted from the "
        .. "health bar, because a nameplate has no place on "
        .. "screen of its own - the game moves it, and dozens of "
        .. "them come and go. An offset is measured in the "
        .. "nameplate's own units, so a rule that makes a "
        .. "nameplate bigger makes its arrangement bigger with "
        .. "it instead of pulling it apart. A fresh install "
        .. "arranges everything exactly as it always was."] =
        "Де стоїть кожна частина неймплейта. Оберіть частину, оберіть "
        .. "сторону і поправте двома числами. Сторони рахуються від смужки "
        .. "здоров'я: власного місця на екрані неймплейт не має — його "
        .. "рухає гра, а приходять і йдуть вони десятками. Поправка "
        .. "рахується у власних одиницях неймплейта, тож збільшений "
        .. "правилом неймплейт збільшено разом із розташуванням, а не "
        .. "розсунуто. Свіже встановлення розташовує все рівно так, як "
        .. "було завжди.",

    ["Part to Place"] =
        "Частина, яку ставимо",
    ["Side It Sits On"] =
        "З якого боку стоїть",
    ["Nudge Sideways"] =
        "Поправка вбік",
    ["Nudge Up and Down"] =
        "Поправка вгору і вниз",
    ["Put This Part Back"] =
        "Скинути цю частину",
    ["Put Every Part Back"] =
        "Скинути всі частини",
    ["Arranges every part the "
        .. "way a fresh install does."] =
        "Розташовує всі частини так, як їх розташовує свіже встановлення.",
    ["nameplate arrangement is back "
        .. "to what it was"] =
        "розташування частин неймплейта повернулося до колишнього",

    ["Health Bar"] = "Смуга здоров'я",
    ["Name and Marks"] = "Ім'я та позначки",
    ["Rules"] = "Правила",
    ["Where the Parts Sit"] = "Де стоять частини",
    ["Nudge Up or Down"] = "Зсув угору чи вниз",
    ["Each part of the nameplate sits on one side of it and can be nudged two ways from there. A part left alone stays exactly where it was before this existed."] =
        "Кожна частина неймплейта стоїть на одному з його боків і може бути " ..
        "зсунута звідти у два напрямки. Незаймана частина лишається саме " ..
        "там, де стояла до появи цього.",
    ["Which side of the nameplate this part sits on. Not every side suits every part, and only the ones that do are listed."] =
        "На якому боці неймплейта стоїть ця частина. Не кожен бік пасує " ..
        "кожній частині, і перелічені лише придатні.",
    ["A correction measured from the side above, so zero means the part sits exactly where that side puts it."] =
        "Поправка, відлічена від боку вище: нуль означає, що частина стоїть " ..
        "саме там, куди її ставить цей бік.",
    ["Returns this one part to where it sat before you moved it. The others are left alone."] =
        "Повертає одну цю частину туди, де вона стояла до вашого зсуву. " ..
        "Решта не чіпається.",
    ["Returns all six parts to where they sat before any of this was moved."] =
        "Повертає всі шість частин туди, де вони стояли до будь-якого " ..
        "зсуву.",
    ["Nameplates"] = "Неймплейти",
}
