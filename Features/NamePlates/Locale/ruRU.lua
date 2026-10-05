local ADDON, core = ...

-- Своё пространство имён этой части: внутри одного аддона все
-- файлы получают одну и ту же таблицу, и имена вроде Rules или
-- Window столкнулись бы молча.
local ns = core.Feature("nameplates")

-- Русский перевод движка неймплейтов.
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
ns.Strings.ruRU = {

    ["Game's Own Texture"] =
        "Родная текстура игры",

    ["Darken Nameplates"] =
        "Неймплейты Darken",

    ["Draws Darken's own nameplates instead of dressing the "
        .. "game's: health bar, name, level, a mark on your target and - "
        .. "each switched on separately below - a cast bar, aura icons, "
        .. "threat color and a quest mark. Off by default - a fresh "
        .. "install changes nothing. Switching it on takes nameplates "
        .. "over from Darken's own plate styling, which stands down "
        .. "while this is on and comes back when it is switched "
        .. "off."] =
        "Рисует собственные неймплейты Darken вместо оформления "
        .. "стандартных: полоска здоровья, имя, уровень, пометка цели и "
        .. "— каждое включается отдельно ниже — полоса применения, "
        .. "значки аур, цвет по угрозе и значок задания. Типово "
        .. "выключено: свежая установка не меняет ничего. Включение "
        .. "забирает неймплейты у собственного оформления Darken: оно "
        .. "отходит в сторону, пока это включено, и возвращается, когда "
        .. "выключено.",

    ["Draw Our Own Nameplates"] =
        "Рисовать свои неймплейты",

    ["Off leaves the game's nameplates exactly as they are, "
        .. "which is what a fresh install does."] =
        "Выключено оставляет неймплейты игры ровно такими, какие "
        .. "они есть, — так и ведёт себя свежая установка.",

    ["Health Bar Texture"] =
        "Текстура полоски здоровья",

    ["The first entry is the game's own bar texture. The addon's "
        .. "own textures are a gradient from white to a color, and the "
        .. "bar color multiplies them."] =
        "Первая запись — родная текстура игры. Авторские текстуры — "
        .. "градиент от белого к цвету, и цвет полоски их умножает.",

    ["Nameplate Width"] =
        "Ширина неймплейта",

    ["Health Bar Height"] =
        "Высота полоски здоровья",

    ["Nameplate Scale"] =
        "Масштаб неймплейта",

    ["Scales the whole nameplate, text included. Width and "
        .. "height above are measured before this."] =
        "Масштабирует неймплейт целиком, вместе с текстом. Ширина и "
        .. "высота выше измеряются до масштаба.",

    ["\"%s\" already draws nameplates, so Darken's nameplate "
        .. "engine stays out of the way: two engines on one frame give "
        .. "flicker and errors."] =
        "Неймплейты уже рисует «%s», поэтому движок неймплейтов "
        .. "Darken отходит в сторону: два движка на одном фрейме "
        .. "дают мигание и ошибки.",

    ["this client has no nameplate API, so the nameplate engine "
        .. "does nothing here"] =
        "в этом клиенте нет API неймплейтов, поэтому движок "
        .. "неймплейтов здесь ничего не делает",

    ["nameplate engine on"] =
        "движок неймплейтов включён",

    ["nameplate engine off"] =
        "движок неймплейтов выключен",

    ["Shorten Long Names"] =
        "Сокращать длинные имена",
    ["Cuts a name that does not fit the nameplate width and marks "
        .. "the cut with three dots. Off leaves long names running past "
        .. "the bar."] =
        "Обрезает имя, которое не помещается в ширину неймплейта, и "
        .. "помечает срез тремя точками. Выключено — длинные имена "
        .. "уезжают за полоску.",
    ["Color by Threat"] =
        "Цвет по угрозе",
    ["Colors the health bar of unfriendly creatures by how close "
        .. "they are to attacking you. Threat outranks class and "
        .. "reaction color, and only while it has something to say: a "
        .. "creature nobody is fighting keeps its own color."] =
        "Красит полоску недружелюбных существ по тому, насколько они "
        .. "близки к тому, чтобы напасть на вас. Угроза старше цвета по "
        .. "классу и по реакции, и только пока ей есть что сказать: "
        .. "существо, с которым никто не дерётся, остаётся своего цвета.",
    ["Mark Quest Targets"] =
        "Помечать цели заданий",
    ["Puts a small mark beside the nameplate of a creature one of "
        .. "your quests wants."] =
        "Ставит небольшую пометку рядом с неймплейтом существа, "
        .. "которое нужно одному из ваших заданий.",
    ["Cast Bar on the Nameplate"] =
        "Полоса применения на неймплейте",
    ["Shows what the creature is casting under its health bar. The "
        .. "bar is moved by the engine itself, so it costs nothing per "
        .. "frame. This is the nameplate's own cast bar - your own cast "
        .. "bar belongs to Darken and to the cast bars module."] =
        "Показывает под полоской здоровья то, что существо применяет. "
        .. "Полоску двигает сам движок, поэтому на кадр она не стоит "
        .. "ничего. Это полоса применения неймплейта — ваша собственная "
        .. "принадлежит Darken и модулю полос применения.",
    ["Cast Bar Height"] =
        "Высота полосы применения",
    ["Aura Icons"] =
        "Значки аур",
    ["Shows aura icons above the nameplate. Which auras pass is "
        .. "set below. Time left is drawn by the engine's own sweep, so "
        .. "the icons cost nothing per frame."] =
        "Показывает значки аур над неймплейтом. Какие ауры проходят, "
        .. "задаётся ниже. Остаток времени рисует затемнение самого "
        .. "движка, поэтому на кадр значки не стоят ничего.",
    ["Show Harmful Auras"] =
        "Показывать вредные ауры",
    ["Show Helpful Auras"] =
        "Показывать полезные ауры",
    ["Only Auras You Applied"] =
        "Только свои ауры",
    ["A creature in a raid carries everybody's auras. Off shows "
        .. "all of them, which in a busy fight is a wall of icons. On by "
        .. "default."] =
        "На существе в рейде висят ауры всех сразу. Выключено — "
        .. "показываются все, и в людном бою это стена значков. По "
        .. "умолчанию включено.",
    ["How Many Icons at Most"] =
        "Сколько значков самое большее",
    ["Aura Icon Size"] =
        "Размер значка ауры",
    ["What to Do with the List"] =
        "Что делать со списком",
    ["An empty list means the list is not used at all, whichever "
        .. "entry is picked here."] =
        "Пустой список означает, что список не используется вовсе, "
        .. "какой бы пункт здесь ни был выбран.",
    ["Spell List"] =
        "Список заклинаний",
    ["Spell names, separated by commas or written one per line. A "
        .. "name written in the list is shown even when \"only auras you "
        .. "applied\" is on - naming a spell is already an answer."] =
        "Имена заклинаний через запятую или по одному в строке. "
        .. "Названное в списке показывается даже при включённом «только "
        .. "свои ауры»: назвать заклинание — уже ответ.",
    ["Show Every Aura That Passes"] =
        "Показывать всё, что прошло",
    ["Show Only the Listed Spells"] =
        "Показывать только названные",
    ["Hide the Listed Spells"] =
        "Прятать названные",

    -- === Правила на отдельного юнита ===

    ["A rule gives named "
        .. "creatures a nameplate of their own. Its color outranks "
        .. "class and reaction color, because you named the creature "
        .. "by hand and those are guesses - but threat color still "
        .. "outranks the rule, so a creature turning on you is never "
        .. "hidden by it. With no rules nothing changes."] =
        "Правило даёт названным существам свой неймплейт. Его цвет "
        .. "старше цвета по классу и по реакции: существо назвали вы "
        .. "сами, а класс и реакция — догадки. Но цвет по угрозе "
        .. "старше правила, поэтому развернувшееся на вас существо "
        .. "правило не спрячет. Без правил ничего не меняется.",

    ["No rules yet, so every nameplate looks the same. "
        .. "A rule names creatures - by name, or by creature id for a "
        .. "name that is different in every language - and gives them "
        .. "their own color and their own size. Rules are tried from the "
        .. "top down, and the first one that names a creature wins it."] =
        "Правил пока нет, и все неймплейты выглядят одинаково. "
        .. "Правило называет существ — именем или номером существа, "
        .. "если имя на каждом языке своё, — и даёт им свой цвет и "
        .. "свой размер. Правила пробуются сверху вниз, и существо "
        .. "достаётся первому, кто его назвал.",

    ["%d. %s"] =
        "%d. %s",
    ["Rule to Edit"] =
        "Правило для правки",
    ["Pick a rule to change it, "
        .. "move it or forget it. Leave it unpicked, and the fields "
        .. "below describe a new rule instead."] =
        "Выберите правило, чтобы изменить его, передвинуть или "
        .. "забыть. Не выбрано — поля ниже описывают новое правило.",
    ["Start a New Rule"] =
        "Завести новое правило",
    ["Rule Name"] =
        "Имя правила",
    ["Yours, not the game's: it "
        .. "is how the rule is named in the list above."] =
        "Ваше, а не игровое: этим именем правило названо в перечне "
        .. "выше.",
    ["Creatures"] =
        "Существа",
    ["Creature names, separated "
        .. "by commas or written one per line, and capitals do not "
        .. "matter. An entry of digits only is read as a creature id "
        .. "instead: a name belongs to the language of your client "
        .. "and is not unique, an id is neither."] =
        "Имена существ через запятую или по одному в строке; регистр "
        .. "не важен. Запись из одних цифр читается как номер "
        .. "существа: имя принадлежит языку клиента и не уникально, а "
        .. "номер — ни то, ни другое.",
    ["Health Bar Color"] =
        "Цвет полоски здоровья",
    ["The color this rule paints "
        .. "the health bar and the name with. Threat color still "
        .. "outranks it."] =
        "Цвет, которым правило красит полоску здоровья и имя. Цвет по "
        .. "угрозе всё равно старше.",
    ["Use That Color"] =
        "Использовать этот цвет",
    ["Off leaves the color alone "
        .. "and the rule changes the size only."] =
        "Выключено — цвет не трогается, и правило меняет только "
        .. "размер.",
    ["Size of Those Nameplates"] =
        "Размер этих неймплейтов",
    ["Multiplies the nameplate "
        .. "scale set above, so one means no change at all."] =
        "Умножает общий масштаб неймплейта, заданный выше: единица "
        .. "означает «не менять».",
    ["Add This Rule"] =
        "Добавить это правило",
    ["Try This Rule Earlier"] =
        "Пробовать это правило раньше",
    ["Try This Rule Later"] =
        "Пробовать это правило позже",
    ["Forget This Rule"] =
        "Забыть это правило",
    ["forgot the rule %s"] =
        "правило %s забыто",

    ["a rule needs a name"] =
        "у правила должно быть имя",
    ["a rule needs at least one creature name or id"] =
        "правило должно назвать хотя бы одно существо — именем или номером",
    ["there is already a rule with that name"] =
        "правило с таким именем уже есть",
    ["that name is too long"] =
        "это имя слишком длинное",
    ["there is no room for another rule"] =
        "места ещё под одно правило нет",
    ["that rule is gone"] =
        "этого правила больше нет",
    -- === Расположение частей неймплейта ===
    ["Name"] =
        "Имя",
    ["Level"] =
        "Уровень",
    ["Cast Bar"] =
        "Полоса применения",
    ["Quest Mark"] =
        "Значок задания",
    ["The Whole Nameplate"] =
        "Весь неймплейт",

    ["Above"] =
        "Сверху",
    ["Below"] =
        "Снизу",
    ["Left"] =
        "Слева",
    ["Right"] =
        "Справа",
    ["On the Health Bar"] =
        "Поверх полоски здоровья",
    ["Where the Game Puts It"] =
        "Там, где его ставит игра",

    ["The engine has not taken a single "
        .. "nameplate over this session, so there is nothing "
        .. "here to arrange: a part cannot be placed on a "
        .. "nameplate that is not on screen. Switch the "
        .. "engine on above, go where there are creatures, "
        .. "and these controls are here the next time you "
        .. "open this window."] =
        "За этот сеанс движок не взял под себя ни одного неймплейта, "
        .. "поэтому расставлять тут нечего: часть нельзя поставить на "
        .. "неймплейт, которого нет на экране. Включите движок выше, "
        .. "выйдите туда, где есть существа, и в следующее открытие "
        .. "этого окна настройки будут здесь.",
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
        "Где стоит каждая часть неймплейта. Выберите часть, выберите "
        .. "сторону и поправьте двумя числами. Стороны считаются от "
        .. "полоски здоровья: своего места на экране у неймплейта нет — "
        .. "его двигает игра, и приходят и уходят они десятками. Поправка "
        .. "считается в собственных единицах неймплейта, поэтому "
        .. "увеличенный правилом неймплейт увеличен вместе с "
        .. "расположением, а не разъезжается. Свежая установка "
        .. "расставляет всё ровно так, как было всегда.",

    ["Part to Place"] =
        "Часть, которую ставим",
    ["Side It Sits On"] =
        "С какой стороны стоит",
    ["Nudge Sideways"] =
        "Поправка вбок",
    ["Nudge Up and Down"] =
        "Поправка вверх и вниз",
    ["Put This Part Back"] =
        "Вернуть эту часть на место",
    ["Put Every Part Back"] =
        "Вернуть на место все части",
    ["Arranges every part the "
        .. "way a fresh install does."] =
        "Расставляет все части так, как их расставляет свежая установка.",
    ["nameplate arrangement is back "
        .. "to what it was"] =
        "расположение частей неймплейта вернулось к прежнему",

    ["Health Bar"] = "Полоса здоровья",
    ["Name and Marks"] = "Имя и метки",
    ["Rules"] = "Правила",
    ["Where the Parts Sit"] = "Где стоят части",
    ["Nudge Up or Down"] = "Сдвиг вверх или вниз",
    ["Each part of the nameplate sits on one side of it and can be nudged two ways from there. A part left alone stays exactly where it was before this existed."] =
        "Каждая часть неймплейта стоит на одной из его сторон и может быть " ..
        "сдвинута оттуда в две стороны. Нетронутая часть остаётся ровно " ..
        "там, где стояла до появления этого.",
    ["Which side of the nameplate this part sits on. Not every side suits every part, and only the ones that do are listed."] =
        "На какой стороне неймплейта стоит эта часть. Не всякая сторона " ..
        "подходит всякой части, и перечислены только подходящие.",
    ["A correction measured from the side above, so zero means the part sits exactly where that side puts it."] =
        "Поправка, отсчитанная от стороны выше: ноль означает, что часть " ..
        "стоит ровно там, куда её ставит эта сторона.",
    ["Returns this one part to where it sat before you moved it. The others are left alone."] =
        "Возвращает одну эту часть туда, где она стояла до вашего сдвига. " ..
        "Остальные не трогаются.",
    ["Returns all six parts to where they sat before any of this was moved."] =
        "Возвращает все шесть частей туда, где они стояли до всякого " ..
        "сдвига.",
    ["Nameplates"] = "Неймплейты",
}
