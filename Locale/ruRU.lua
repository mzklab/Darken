local ADDON, ns = ...

-- Русский перевод интерфейса.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод
-- перестанет находиться, а игрок увидит английскую подпись. Правка
-- английского всегда идёт парой — в месте вызова и здесь.
--
-- Порядок записей повторяет порядок разделов в окне настроек, а не
-- алфавит: так видно, что перевод раздела полон.

ns.RegisterLocale("ruRU", {

    -- Общая оболочка окна.
    ["Close"] = "Закрыть",

    -- Поиск по настройкам (Config/Search.lua).
    -- Общий раздел настроек (Config/Options.lua).
    ["General"] = "Общее",
    ["Darken repaints the game's "
        .. "own interface dark and hands you the parts "
        .. "Blizzard leaves alone. Nothing here is one "
        .. "way: the first entry in every list is the "
        .. "game's own look, and the one setting a fresh "
        .. "install changes by itself is the interface darkness, at "
        .. "sixty-four of a hundred. Type /darken in chat to "
        .. "open this window again."] =
        "Darken перекрашивает собственный интерфейс игры в тёмный и отдаёт "
        .. "вам те его части, которые Blizzard не настраивает. Дороги в один "
        .. "конец здесь нет: первой строкой в каждом списке стоит родной вид "
        .. "игры, а единственная настройка, которую свежая установка меняет "
        .. "сама, — затемнение, шестьдесят четыре из ста. Чтобы открыть это окно "
        .. "снова, наберите в чате /darken.",
    ["This Copy"] = "Эта сборка",

    -- Страница аддона в настройках игры (Config/Options.lua).
    ["Darken has a settings window of its own. This page is narrow and "
        .. "shares the screen with the game's own panels, so the settings "
        .. "live in that window instead of here."] =
        "У Darken есть собственное окно настроек. Эта страница узкая и "
        .. "делит экран с панелями самой игры, поэтому настройки живут в том "
        .. "окне, а не здесь.",
    ["Open the Settings Window"] = "Открыть окно настроек",
    ["Typing /darken in chat opens the same window."] =
        "Набранное в чате /darken открывает то же окно.",

    -- Узел-вместилище в колонке разделов (Config/Options.lua).
    -- Раздел на месте отключённого модуля (Config/Options.lua).
    ["Skin Settings Windows"] = "Оформлять окна настроек",

    -- Пресеты вида (Core/Presets.lua, кнопки в Config/Options.lua).
    ["Looks"] = "Виды",
    ["A look is a batch of this addon's own settings applied at once. It "
        .. "touches only the settings it names below: everything else stays "
        .. "as you left it. Nothing is locked in - each of these settings "
        .. "keeps its own list in its own section, and the game's own look "
        .. "is the first entry in every one of them."] =
        "Вид — это набор наших же настроек, применяемый одним действием. Он "
        .. "трогает только те настройки, которые названы ниже: всё остальное "
        .. "остаётся таким, каким вы его оставили. Дороги в один конец тут "
        .. "нет: каждая из этих настроек стоит на своём месте со своим "
        .. "списком, и родной вид игры — первая строка в каждом из них.",
    -- Вопрос перед применением пресета (Core/Presets.lua). Три абзаца, и
    -- каждый отвечает на свой вопрос: что применяем, что изменится и что
    -- останется, как вернуть прежнее.
    ["Apply \"%s\"?"] = "Применить «%s»?",
    ["It changes %s. Every other setting stays as it is."] =
        "Изменится: %s. Все остальные настройки останутся как есть.",
    ["To keep your current look, cancel and copy the profile first in the "
        .. "Profiles section."] =
        "Чтобы нынешний вид можно было вернуть, отмените этот вопрос и "
        .. "скопируйте профиль в разделе «Профили».",
    ["Game's Own"] = "как в игре",

    ["On"] = "вкл",
    ["Off"] = "выкл",
    ["Classic Look"] = "Классический вид",
    ["Our settings arranged to read as the game did in 1.x: bars and "
        .. "fonts left to the game, and dimming off - the interface back to "
        .. "the game's own brightness. It is not a restoration of the old "
        .. "window art - that is a separate, much larger piece of work. Each "
        .. "of the three looks says what the dimming slider should be, this "
        .. "one included: a look you press is the whole look, not the "
        .. "difference from what you had."] =
        "Наши настройки, расставленные так, чтобы интерфейс читался как в "
        .. "1.x: полоски и шрифты отданы игре, затемнение выключено — "
        .. "яркость интерфейса возвращается к игровой. Это не восстановление "
        .. "старого оформления окон — оно делается отдельно и стоит "
        .. "несравнимо больше. Каждый из трёх видов называет и положение "
        .. "ползунка затемнения, этот в том числе: нажатый вид — это вид "
        .. "целиком, а не разница с тем, что было.",
    ["Modern Look"] = "Современный вид",
    ["Our settings arranged to read as the game does today: bars colored "
        .. "by class and power type, thin outline on text, and the dimming a "
        .. "fresh install comes with."] =
        "Наши настройки, расставленные так, чтобы интерфейс читался как "
        .. "сегодня: полоски крашены по классу и по виду ресурса, у текста "
        .. "тонкий контур, затемнение — то же, что у свежей установки.",
    ["The Author's Look"] = "Авторский вид",
    ["The addon's own unit frame look: the health bar tinted by class "
        .. "color, the power bar by power type, and the dimming a fresh "
        .. "install comes with. Fonts and name color stay yours."] =
        "Авторский вид юнитфреймов: полоска здоровья тонируется цветом "
        .. "класса, полоска ресурса — цветом ресурса, затемнение — то же, "
        .. "что у свежей установки. Шрифты и цвет имени остаются вашими.",

    -- Подсистема затемнения (Modules/Darkness.lua). Раздел и ползунок
    -- названы одним словом, и по-русски оно тоже одно.
    ["Interface Darkness"] = "Затемнение интерфейса",
    ["Strength"] = "Сила",
    ["How much to dim the interface's own " ..
        "artwork: frames, borders, backgrounds and the trim " ..
        "around them. A fresh install starts at sixty-four, and that " ..
        "is the one thing installing this addon changes on its own: " ..
        "a dark interface addon that looks like the untouched game " ..
        "is not doing what it exists for. Zero is the game's own " ..
        "look and is one drag away; one hundred " ..
        "is as dark as the addon goes, and that is deliberately " ..
        "not black - a frame you cannot make out is not a dimmed " ..
        "frame, it is a missing one. Health and power bars, " ..
        "spell icons, unit portraits, the character model, the " ..
        "map itself keep their own color at every setting. Text " ..
        "keeps its own too, with one exception: the quest and " ..
        "gossip pages are the only place in the game where text is " ..
        "printed dark on light, and there the dark text is lifted " ..
        "to a light tone so the darkened page stays readable. " ..
        "The change applies at once, no interface " ..
        "reload needed; back to zero restores the previous look."] =
        "Насколько приглушить собственную графику интерфейса: фреймы, " ..
        "рамки, подложки и обвязку вокруг них. Свежая установка " ..
        "начинается с шестидесяти четырёх, и это единственное, что установка " ..
        "аддона меняет сама: тёмный интерфейс, неотличимый от " ..
        "нетронутой игры, не делает того, ради чего его ставят. " ..
        "Ноль — родной вид игры, и до него одно движение; " ..
        "сто — самое тёмное, до чего доходит аддон, и это намеренно не " ..
        "чёрный: фрейм, который не разглядеть, — не затемнённый фрейм, а " ..
        "пропавший. Полоски здоровья и ресурса, значки заклинаний, " ..
        "портреты юнитов, модель персонажа и сама карта сохраняют свой " ..
        "цвет при любом положении ползунка. Текст тоже, кроме одного " ..
        "места: страница задания и разговор с существом — единственное " ..
        "место в игре, где текст напечатан тёмным по светлому, и там " ..
        "тёмный текст поднимается в светлый, чтобы затемнённая страница " ..
        "читалась. Изменение " ..
        "применяется сразу, перезагрузка интерфейса не нужна; возврат к " ..
        "нулю возвращает прежний вид.",
    ["Tint"] = "Оттенок",
    ["The color the interface's artwork is " ..
        "tinted with. White changes nothing and is the default, " ..
        "so a fresh install is dimmed but not tinted. " ..
        "Tinting is the same multiply as dimming, only with the " ..
        "three color channels dimmed by different amounts, which " ..
        "is why it works on its own: a tint with the dimming at " ..
        "zero recolors the frames without darkening them. The " ..
        "same things dimming leaves alone are left alone here."] =
        "Цвет, которым подкрашивается графика интерфейса. Белый не меняет " ..
        "ничего и стоит умолчанием: свежая установка затемнена, но не " ..
        "подкрашена. Оттенок — то же самое умножение, " ..
        "что и затемнение, только три цветовых канала гасятся по-разному; " ..
        "поэтому он работает и сам по себе: оттенок при нуле на ползунке " ..
        "перекрашивает фреймы, не затемняя их. Того, что не трогает " ..
        "затемнение, не трогает и он.",
    -- Режимы областей (Modules/Darkness.lua).
    ["Areas"] = "Области",
    ["Dimmed"] = "Приглушено",
    ["Dark"] = "Темно",
    ["More Dark"] = "Ещё темнее",
    ["Darker"] = "Темнее",
    ["Even Darker"] = "Ещё темнее",
    ["Black"] = "Чёрный",

    -- Исключения по одному окну (Modules/Darkness.lua).
    ["Individual Windows"] = "Отдельные окна",
    ["Find a Window"] = "Поиск окна",
    ["Narrows the list below to windows whose " ..
        "name contains what you type. The list is not written by " ..
        "hand: it is the windows dimming has actually reached, so " ..
        "it grows as you open the game's own windows and is " ..
        "remembered between sessions."] =
        "Оставляет в списке ниже окна, в имени которых есть набранное. " ..
        "Список не написан руками: это те окна, до которых затемнение " ..
        "действительно дотянулось, поэтому он пополняется по мере того, " ..
        "как вы открываете окна игры, и запоминается между сеансами.",
    ["Nothing here yet. This list fills itself " ..
        "as you open the game's windows - it is built from what " ..
        "dimming actually touched, and a fresh install starts " ..
        "empty rather than guessing at names. What appears here " ..
        "is remembered between sessions, so it is waiting for you " ..
        "the next time you log in."] =
        "Здесь пока пусто. Список наполняется сам, по мере того как вы " ..
        "открываете окна игры: он собран из того, что затемнение " ..
        "действительно тронуло, а свежая установка начинает с пустого " ..
        "списка, а не с догадок об именах. Появившееся здесь запоминается " ..
        "между сеансами и будет ждать вас при следующем входе в игру.",
    ["Windows Seen So Far"] = "Увиденные окна",
    ["Checked windows keep the game's own look, " ..
        "dimming and tint both, and the change happens at once, " ..
        "no interface reload needed. The list is built from what " ..
        "dimming actually reached rather than from names written " ..
        "in advance, so a window joins it the first time you open " ..
        "it and stays there between sessions. A window this game " ..
        "no longer has keeps its place for a while and is then " ..
        "dropped from the list, but your choice for it is kept: " ..
        "should the window ever come back, it comes back the way " ..
        "you left it. The groups above are the same switch, only " ..
        "coarser - while \"Other Windows\" is checked it already " ..
        "keeps every one of these native, and this list is greyed " ..
        "out to say so."] =
        "Отмеченные окна остаются в родном виде — и без затемнения, и без " ..
        "оттенка, — и меняется это сразу, без перезагрузки интерфейса. " ..
        "Список собран из того, до чего затемнение действительно " ..
        "дотянулось, а не из заранее написанных имён: окно попадает сюда " ..
        "при первом своём открытии и остаётся между сеансами. Окно, " ..
        "которого в игре больше нет, какое-то время держит своё место, а " ..
        "потом уходит из списка — но ваш выбор для него сохраняется: " ..
        "вернувшись, окно вернётся ровно таким, каким вы его оставили. " ..
        "Группы выше — тот же выключатель, только грубее: пока отмечены " ..
        "«Прочие окна», они и так держат все эти окна в родном виде, и " ..
        "список поэтому погашен.",
    ["%d more windows are not " ..
        "shown. Type in the box above to narrow the list."] =
        "Ещё %d окон не показано. Наберите что-нибудь в поле выше, чтобы " ..
        "сузить список.",

    -- Группы затемнения (Modules/Darkness.lua: GROUPS).
    ["Action Bar Art"] = "Обвязка панелей действий",
    ["Other Windows"] = "Прочие окна",
    ["Other Addons' Windows"] = "Окна чужих аддонов",
    ["Minimap"] = "Карта",
    ["Buffs and Debuffs"] = "Усиления и ослабления",
    ["Bags and Micro Menu"] = "Сумки и меню",
    ["Chat"] = "Чат",
    ["Objective Tracker"] = "Список заданий",
    ["Tooltips"] = "Подсказки",
    ["Character Sheet"] = "Окно персонажа",
    ["Quest and Dialog Text"] = "Задания и разговоры",

    -- Подпись значения «как в игре» на ползунках, где ноль означает
    -- не число, а «не трогать» (Modules/Fonts.lua, Modules/CastBar.lua,
    -- Modules/ActionBars.lua).
    ["Game's Own"] = "Как в игре",

    -- Вкладки страницы шрифтов и строка «что действует сейчас» на каждой
    -- из них (Modules/Fonts.lua).
    ["Global"] = "Глобально",
    ["In effect now - font: %s, size: %s, outline: %s."] =
        "Сейчас действует — шрифт: %s, размер: %s, контур: %s.",
    ["game's own"] = "как в игре",
    ["set on this tab"] = "задано на этой вкладке",
    ["from the Global tab"] = "с вкладки «Глобально»",
    ["Movement of the Numbers"] = "Движение цифр",

    -- Подсистема шрифтов (Modules/Fonts.lua).
    ["Fonts"] = "Шрифты",
    ["Unit Names"] = "Имена юнитов",
    ["Bar Values"] = "Значения на полосках",
    ["Hotkeys and Counts"] = "Горячие клавиши и счётчики",
    ["Floating Combat Text"] = "Всплывающий боевой текст",
    ["Addon Window Text"] = "Текст окон аддона",
    ["No Outline"] = "Без контура",
    ["Thin Outline"] = "Тонкий контур",
    ["Thick Outline"] = "Толстый контур",
    ["Outline Without Antialiasing"] = "Контур без сглаживания",
    ["Note: a font without glyphs for your client language shows text "
        .. "as empty boxes. LibSharedMedia cannot check glyphs, so such a "
        .. "font sits in the list next to the rest. If text disappears after "
        .. "you pick one, put the previous font back - no interface reload "
        .. "needed."] =
        "Внимание: шрифт без кириллических глифов на русском клиенте "
        .. "показывает текст пустыми прямоугольниками. Проверять глифы "
        .. "LibSharedMedia не умеет, поэтому такой шрифт стоит в списке "
        .. "наравне с остальными. Если после выбора текст пропал — верните "
        .. "прежний шрифт, перезагрузка интерфейса для этого не нужна.",
    -- Про собственное окно аддона: оно вне области действия настроек
    -- шрифтов (Modules/Fonts.lua, OWN_WINDOW_KEY).
    ["Darken's own settings window stays out of all of this on "
        .. "purpose: it is the tool you are changing the font with, and a "
        .. "window that resizes under your hands while you drag the slider "
        .. "is hard to steer and hard to get back. Everything else follows "
        .. "what you set here - the game's interface, and the windows "
        .. "Darken puts in its place, the bags window and the nameplates "
        .. "among them."] =
        "Собственное окно настроек Darken из всего этого исключено "
        .. "намеренно: это инструмент, которым вы сейчас меняете шрифт, а "
        .. "окно, которое перестраивается под руками, пока вы двигаете "
        .. "ползунок, неуправляемо — и вернуть его нечем. Всё остальное "
        .. "подчиняется заданному здесь: интерфейс игры и окна, которые "
        .. "Darken ставит вместо него, включая окно сумок и неймплейты.",
    -- Про границу вкладки собственного текста: наши окна — предмет
    -- настройки, окно настроек — инструмент (Modules/Fonts.lua,
    -- WINDOW_TEXT_KEY).
    ["This covers the windows Darken draws in place of the game's own - "
        .. "the bags window and the item database among them. The settings "
        .. "window you are reading this in is not one of them: it is the "
        .. "tool, not the thing being set, and a window that reshapes itself "
        .. "while you adjust it is hard to steer. A window of a module picks "
        .. "this up when the module asks the core for it, so an older module "
        .. "may still be on the game's own font."] =
        "Это про окна, которые Darken рисует вместо окон игры: окно сумок, "
        .. "базу предметов и все следующие. Окно настроек, в котором вы это "
        .. "читаете, сюда не входит: оно инструмент, а не предмет настройки, "
        .. "и окно, перестраивающееся, пока его настраивают, неуправляемо. "
        .. "Окно модуля берёт отсюда шрифт тогда, когда модуль спрашивает "
        .. "его у ядра, поэтому давно не обновлявшийся модуль может "
        .. "остаться на шрифте игры.",
    ["Leave Global Fonts Alone"] = "Не трогать глобальные шрифты",
    ["Replacing the standard font objects of the game changes text "
        .. "across the whole interface, the windows of other addons included. "
        .. "Checking this restores the game's own fonts at once, without an "
        .. "interface reload. Per-category overrides are not affected: they "
        .. "keep working."] =
        "Подмена стандартных шрифтовых объектов игры меняет текст во всём "
        .. "интерфейсе, включая окна других аддонов. Отметка возвращает "
        .. "родные шрифты игры сразу, без перезагрузки интерфейса. Точечных "
        .. "настроек по категориям отметка не касается: они продолжают "
        .. "действовать.",
    ["Interface Font"] = "Шрифт интерфейса",
    ["The font applied to the whole interface at once: windows, "
        .. "tooltips, the quest log, system messages. The list comes from "
        .. "LibSharedMedia, so it holds both the game's own fonts and "
        .. "everything other addons brought along."] =
        "Шрифт, применяемый ко всему интерфейсу сразу: окна, подсказки, "
        .. "журнал заданий, системные сообщения. Список берётся из "
        .. "LibSharedMedia, поэтому в нём и родные шрифты игры, и всё, что "
        .. "принесли другие аддоны.",
    ["Game's Own Font"] = "Родной шрифт игры",
    ["Outline"] = "Контур",
    ["The stroke around letters. \"Game's Own Outline\" leaves every "
        .. "element the outline it started with."] =
        "Обводка букв. «Родной контур» оставляет каждому элементу тот "
        .. "контур, который был у него изначально.",
    ["Game's Own Outline"] = "Родной контур",
    ["Back to the Game's Own Fonts"] = "Вернуть шрифты как в игре",
    ["Puts every font setting back the way a fresh install has it: the "
        .. "font, size and outline here, every tab's own override, and the "
        .. "switch above. Nothing but the fonts is touched, and the game's "
        .. "own text comes back at once, without an interface reload."] =
        "Возвращает все настройки шрифтов к тому виду, какой у них на "
        .. "свежей установке: шрифт, размер и контур здесь, собственные "
        .. "значения всех вкладок и выключатель выше. Кроме шрифтов не "
        .. "трогается ничего, а родной текст игры возвращается сразу, без "
        .. "перезагрузки интерфейса.",
    ["Font"] = "Шрифт",
    ["\"Same as Global\" means the category takes its font from the "
        .. "setting above and follows its changes from then on."] =
        "«Как глобальный» — категория берёт шрифт из настройки выше и "
        .. "дальше следует за её изменениями.",
    ["Same as Global"] = "Как глобальный",
    ["Size"] = "Размер",
    ["\"Same as Global\" means the outline is taken from the level "
        .. "above."] =
        "«Как глобальный» — контур берётся с уровня выше.",
    ["Note: the numbers floating over units are drawn by the world text "
        .. "engine, which reads the font file once, at login. A new font "
        .. "therefore shows up only after a full logout to character "
        .. "select - an interface reload is not enough. Size, outline, "
        .. "gravity and duration apply at once."] =
        "Внимание: цифры, всплывающие над юнитами, рисует движок "
        .. "трёхмерного текста, а он читает файл шрифта один раз — при "
        .. "входе в мир. Поэтому новый шрифт виден только после полного "
        .. "выхода к выбору персонажа: перезагрузки интерфейса для этого "
        .. "не хватает. Размер, контур, гравитация и длительность "
        .. "меняются сразу.",
    ["Gravity"] = "Гравитация",
    ["How fast the numbers fall after they pop up. Zero leaves the game "
        .. "its own pull, and the game's own value is 0.5: bigger numbers "
        .. "drop faster, smaller ones let the numbers hang. Takes effect "
        .. "at once, without a reload."] =
        "Как быстро цифры падают после появления. Ноль — оставить игре её "
        .. "собственное притяжение; родное значение игры — 0,5. Больше "
        .. "значение — быстрее падение, меньше — цифры зависают. Меняется "
        .. "сразу, без перезагрузки.",
    ["Duration"] = "Длительность",
    ["How long the numbers stay on screen. Zero leaves the game its own "
        .. "timing, and the game's own value is 1.0. Takes effect at once, "
        .. "without a reload."] =
        "Сколько цифры держатся на экране. Ноль — оставить игре её "
        .. "собственное время; родное значение игры — 1,0. Меняется сразу, "
        .. "без перезагрузки.",

    -- Юнитфреймы (Modules/UnitFrames.lua). Ключ «Unit Frames» общий с
    -- группой исключений подсистемы темноты: подпись там и там одна.
    ["Unit Frames"] = "Юнитфреймы",

    -- Вкладки страницы юнитфреймов. Делят её не по нашим заголовкам, а по
    -- тому, за чем игрок пришёл: как выглядит полоска, что написано на
    -- фрейме, какого он размера. Ключ «Size» общий с другими разделами.
    ["Health and Power"] = "Здоровье и ресурс",
    ["Name and Bar Text"] = "Имя и надписи",
    ["Game's Own Texture"] = "Родная текстура игры",
    ["Game's Own Bar Color"] = "Родной цвет полоски",
    ["By Class"] = "По классу",
    ["By Reaction"] = "По отношению к игроку",
    ["By Power Type"] = "По виду ресурса",
    ["Custom Color"] = "Свой цвет",

    ["Health Bar"] = "Полоска здоровья",
    ["Health Bar Texture"] = "Текстура полоски здоровья",
    ["Health Bar Color"] = "Цвет полоски здоровья",
    ["The color the texture is tinted by. \"By Class\" applies to "
        .. "players only: creatures have no class, so their bar is colored "
        .. "by reaction to you. The first entry leaves the color to the "
        .. "game, and switching back to it restores the native color at "
        .. "once."] =
        "Цвет, которым тонируется текстура. «По классу» действует только на "
        .. "игроков: у существ класса нет, и их полоска красится по "
        .. "отношению к вам. Первая строка оставляет цвет игре, и возврат к "
        .. "ней возвращает родной цвет сразу.",
    ["Custom Health Bar Color"] = "Свой цвет полоски здоровья",

    ["Power Bar"] = "Полоска ресурса",
    ["Power Bar Texture"] = "Текстура полоски ресурса",
    ["Mana, rage, energy. The texture is tinted by the bar color just "
        .. "as on the health bar. The first entry is the game's own texture, "
        .. "and going back to it restores the native look at once."] =
        "Мана, ярость, энергия. Текстура тонируется цветом полоски так же, "
        .. "как на полоске здоровья. Первая строка списка — родная текстура "
        .. "игры, и возврат к ней возвращает родной вид сразу.",
    ["Power Bar Color"] = "Цвет полоски ресурса",
    ["\"By Power Type\" takes the color from the game itself: mana "
        .. "blue, rage red, energy yellow, and so on for whatever this "
        .. "client has. The first entry leaves the color to the game, and "
        .. "switching back to it restores the native color at once."] =
        "«По виду ресурса» берёт цвет у самой игры: мана синяя, ярость "
        .. "красная, энергия жёлтая — и так для всего, что есть в этом "
        .. "клиенте. Первая строка оставляет цвет игре, и возврат к ней "
        .. "возвращает родной цвет сразу.",
    ["Custom Power Bar Color"] = "Свой цвет полоски ресурса",
    ["Used in \"Custom Color\" mode, and also when the game has no "
        .. "color for this kind of power."] =
        "Используется в режиме «Свой цвет», а также когда у игры нет цвета "
        .. "для этого вида ресурса.",

    ["Unit Name"] = "Имя юнита",
    ["Name Color"] = "Цвет имени",
    ["Game's Own Name Color"] = "Родной цвет имени",
    ["\"Game's Own Name Color\" leaves the name to the game; switching "
        .. "back to it restores the native color at once. \"By Class\" "
        .. "applies to players only: creatures have no class, so their name "
        .. "is colored by reaction to you. When that is unknown too, the "
        .. "color chosen below is used."] =
        "«Родной цвет имени» — имя красит сама игра, аддон его не трогает; "
        .. "возврат к этому режиму возвращает родной цвет сразу. «По классу» "
        .. "действует только на игроков: у существ класса нет, и для них цвет "
        .. "берётся по отношению к вам. Если неизвестно и оно — берётся "
        .. "выбранный ниже цвет.",
    ["Custom Name Color"] = "Свой цвет имени",
    ["Used in \"Custom Color\" mode, and also when neither the class "
        .. "nor the reaction of a unit is known."] =
        "Используется в режиме «Свой цвет», а также когда ни класс, ни "
        .. "отношение юнита неизвестны.",

    ["Frame Scale"] = "Масштаб фреймов",
    ["One is the native size. Scale is a protected operation: a change "
        .. "made in combat is queued and applied as soon as combat ends. "
        .. "Textures and colors are not protected and apply immediately, "
        .. "in combat as well."] =
        "Единица — родной размер. Масштаб — защищённая движком операция: "
        .. "изменение, сделанное в бою, откладывается и применяется сразу "
        .. "после выхода из боя. Текстуры и цвета защищёнными не являются и "
        .. "применяются немедленно, в том числе в бою.",

    ["Scale multiplies everything at once: the bars, the portrait, the "
        .. "artwork and the text. There is no width or height here on "
        .. "purpose - the player, target and pet frames are drawn from "
        .. "artwork pinned to the frame at fixed offsets, so a width would "
        .. "change the click area and move nothing you can see. Group and "
        .. "raid frames are built from numbers instead, and there size is "
        .. "real: they have a tab of their own."] =
        "Масштаб умножает всё разом: полоски, портрет, рисованную обвязку и "
        .. "текст. Ширины и высоты здесь нет нарочно: фреймы игрока, цели и "
        .. "питомца собраны из рисунков, прибитых к фрейму с пиксельными "
        .. "отступами, и ширина поменяла бы только область щелчка, не сдвинув "
        .. "ничего видимого. Фреймы группы и рейда сложены из чисел, и там "
        .. "размер настоящий: у них своя вкладка.",

    -- Фреймы группы и рейда (Modules/UnitFrames.lua).
    ["Group and Raid Frames"] = "Фреймы группы и рейда",
    ["Set the Group Frame Size Myself"] = "Задать размер фреймов группы самому",
    ["Off leaves the size of a group member to the game, which is where a "
        .. "fresh install starts. On hands the two numbers below to the "
        .. "game's own layout, so they survive the group changing: a member "
        .. "joining or leaving re-lays the list out, and the game reads the "
        .. "size from the same place we wrote it. Size changes the box and "
        .. "leaves the text alone; scale multiplies both. They compose - a "
        .. "frame 120 wide at scale 1.5 takes 180 on screen."] =
        "Выключено — размер члена группы остаётся за игрой, и с этого "
        .. "начинается свежая установка. Включено — два числа ниже уходят в "
        .. "собственную раскладку игры и переживают смену состава: приход и "
        .. "уход участника перекладывают список заново, а размер игра берёт "
        .. "оттуда же, куда его положили мы. Размер меняет коробку и не "
        .. "трогает текст, масштаб умножает и то и другое. Складываются они "
        .. "умножением: фрейм шириной 120 при масштабе 1.5 занимает на "
        .. "экране 180.",
    ["Group Frame Width"] = "Ширина фрейма группы",
    ["How wide one group member is. Sizing a group frame is a protected "
        .. "operation: a change made in combat is queued and applied as soon "
        .. "as combat ends. Clients without compact group frames are left "
        .. "alone: the setting then quietly does nothing rather than "
        .. "erroring."] =
        "Какой ширины один член группы. Размер фрейма группы — защищённая "
        .. "движком операция: изменение, сделанное в бою, откладывается и "
        .. "применяется сразу после выхода из боя. Клиент без компактных "
        .. "фреймов группы остаётся нетронутым: настройка тогда молча ничего "
        .. "не делает, а не падает с ошибкой.",
    ["Group Frame Height"] = "Высота фрейма группы",
    ["How tall one group member is. Queued in combat just like the width, "
        .. "and applied as soon as combat ends."] =
        "Какой высоты один член группы. В бою откладывается так же, как "
        .. "ширина, и применяется сразу после выхода из боя.",
    ["Group Frame Scale"] = "Масштаб фреймов группы",
    ["One is the native size. Scale multiplies the whole group frame, text "
        .. "and all, on top of the width and height above. It is a protected "
        .. "operation too, so a change made in combat applies as soon as "
        .. "combat ends."] =
        "Единица — родной размер. Масштаб умножает весь фрейм группы вместе "
        .. "с текстом, поверх ширины и высоты выше. Операция тоже защищённая: "
        .. "изменение, сделанное в бою, применяется сразу после выхода из боя.",

    -- Разведка затемнения (/dark probe).
    ["\"%s\" is switched off right now, so /dark %s does nothing. Its "
        .. "section in the settings window says why and offers to try "
        .. "again."] =
        "«%s» сейчас отключена, поэтому /dark %s ничего не делает. Её "
        .. "раздел в окне настроек говорит почему и предлагает повторить.",
    ["the dimming subsystem is not loaded"] =
        "подсистема затемнения не загружена",
    ["the window opened last"] = "последнее открытое окно",
    ["open the window first, then type /dark probe - or name the frame: "
        .. "/dark probe <frame name>"] =
        "сначала откройте окно, потом наберите /dark probe - или назовите "
        .. "фрейм: /dark probe <имя фрейма>",
    ["there is no frame named '%s'"] = "фрейма с именем «%s» нет",
    ["dimming probe of %s:"] = "разведка затемнения, %s:",
    ["log out - the whole list will land in Darken.lua "
        .. "(SavedVariables), under DarkenDB.global.darkprobe"] =
        "выйдите из игры - весь список ляжет в Darken.lua "
        .. "(SavedVariables), в DarkenDB.global.darkprobe",

    ["The color this area is painted with. It is a multiply, like dimming "
        .. "is: white changes nothing, a darker color darkens, and a "
        .. "colored one tints. The same things dimming leaves alone are "
        .. "left alone here."] =
        "Цвет, которым красится эта область. Это умножение, как и "
        .. "затемнение: белый не меняет ничего, тёмный затемняет, цветной "
        .. "окрашивает. Всё, чего не трогает затемнение, не трогается и "
        .. "здесь.",
    ["Custom Color"] = "Свой цвет",
    ["Class Color"] = "Цвет класса",

    -- Кнопка на миникарте (Modules/Launcher.lua).
    ["Minimap Button"] = "Кнопка на миникарте",
    ["Button on the Minimap"] = "Кнопка на миникарте",
    ["A button at the edge of the minimap that opens this window. Drag it "
        .. "around the minimap to move it; its place is remembered for the "
        .. "whole account, not per profile. The other two doors stay where "
        .. "they were: the /dark command and the addon's page in the game's "
        .. "own interface options."] =
        "Кнопка у края миникарты, открывающая это окно. Её можно таскать "
        .. "по кругу миникарты; место запоминается на всю учётную запись, а "
        .. "не на профиль. Две другие двери остались где были: команда "
        .. "/dark и страница аддона в настройках самой игры.",
    ["Click to open the settings or close them, drag to move this button "
        .. "around the minimap."] =
        "Щелчок открывает настройки и закрывает их, перетаскивание двигает "
        .. "кнопку по краю миникарты.",

    -- Рамки значков (Modules/Icons.lua).
    ["Icon Borders"] = "Рамки значков",
    ["Frame the Icons"] = "Обвести значки",
    ["Draws a one pixel line around every action button and every buff and "
        .. "debuff icon, in the same color the addon draws all of its own "
        .. "lines. Dimming multiplies the color of what the game has "
        .. "already drawn; a line that is not there it cannot draw - and "
        .. "the game's own button edge is part of the button's picture, so "
        .. "it goes dark along with it and the row turns into dark patches "
        .. "with no borders. Off by default."] =
        "Рисует линию толщиной в пиксель вокруг каждой кнопки панели и "
        .. "каждого значка ауры, тем же цветом, которым аддон рисует все "
        .. "свои линии. Затемнение "
        .. "умножает цвет того, что игра уже нарисовала; линию, которой "
        .. "нет, оно нарисовать не может — а родной кант кнопки нарисован "
        .. "внутри её же картинки, темнеет вместе с ней, и ряд кнопок "
        .. "превращается в тёмные пятна без границ. По умолчанию выключено.",
    ["Backing Behind the Bars"] = "Подложка под панелями",
    ["Lays the addon's own panel color behind each action bar, a few pixels "
        .. "wider than the bar itself. It gives the row an edge where the "
        .. "game draws none, the same way the line above gives one to a "
        .. "button. Off by default."] =
        "Кладёт под каждую панель команд наш собственный цвет подложки, на "
        .. "несколько пикселей шире самой панели. Это даёт ряду край там, "
        .. "где игра его не рисует, — так же, как линия выше даёт край "
        .. "кнопке. По умолчанию выключено.",
    ["Round the Minimap Buttons"] = "Скруглить кнопки на миникарте",
    ["Square Minimap"] = "Квадратная миникарта",
    ["Dim the Icons Too"] = "Затемнять и иконки",
    ["Darkens a spell's picture along with the interface around it, "
        .. "at the same strength. Off by default: the dimming spares "
        .. "icons on purpose, because an icon is how a spell is "
        .. "recognised. The game still colours an icon red out of range "
        .. "or grey when unusable - it is answering you, and it wins."] =
        "Затемняет картинку заклинания вместе с интерфейсом вокруг, той "
            .. "же силой. По умолчанию выключено: затемнение щадит иконки "
            .. "нарочно, потому что иконкой заклинание и узнают. Игра "
            .. "по-прежнему красит иконку красным вне радиуса и серым, "
            .. "когда применить нельзя, — это её ответ вам, и он главнее.",
    ["Cuts the minimap square instead of round. The ring around it "
        .. "is drawn as a circle and would lie across the corners, so it "
        .. "is taken away with the same tick. Off by default."] =
        "Обрезает миникарту квадратом вместо круга. Кольцо вокруг неё "
            .. "нарисовано кругом и легло бы поперёк углов, поэтому "
            .. "снимается той же галочкой. По умолчанию выключено.",
    ["Cuts the square buttons other addons put around the minimap into "
        .. "circles and gives each the same line the icons above get. Only "
        .. "other addons' buttons: the game's own are round already, and "
        .. "the few that are not are drawn that way on purpose. Off by "
        .. "default."] =
        "Обрезает в круг квадратные кнопки, которые чужие аддоны ставят "
        .. "вокруг миникарты, и обводит каждую той же линией, что и значки "
        .. "выше. Только чужие кнопки: свои у игры и так круглые, а те "
        .. "немногие, что не круглые, нарисованы так намеренно. По "
        .. "умолчанию выключено.",
    ["Trim the Icon Edges"] = "Обрезать кант значков",
    ["Cuts the game's own dark edge off each spell icon, the way a modern "
        .. "interface does. Nothing is removed: the picture is shown "
        .. "without its outermost border, and switching this off puts back "
        .. "exactly the coordinates the icon had. Best with the line above, "
        .. "which then becomes the button's edge."] =
        "Срезает родной тёмный кант с каждого значка заклинания — так, как "
        .. "это делает современный интерфейс. Ничего не удаляется: "
        .. "картинка показывается без самого края, а выключение "
        .. "возвращает ровно те координаты, которые у значка были. Лучше "
        .. "всего вместе с линией выше: она и становится краем кнопки.",

    -- Обесцвечивание и грифоны (Modules/Darkness.lua).
    ["Grey Out the Artwork"] = "Обесцветить оформление",
    ["Takes the color out of the interface's own artwork instead of only "
        .. "darkening it: the brown of the frames, the gold of the trim, "
        .. "the blue of the bag border all become grey. Dimming still "
        .. "applies on top, and everything dimming leaves alone is left "
        .. "alone here too - spell icons, portraits, the map and all text "
        .. "keep their own color. Off by default: how dark and what color "
        .. "are two questions, and a fresh install answers only the first."] =
        "Убирает цвет из оформления интерфейса, а не только затемняет его: "
        .. "бурый цвет рамок, золото окантовки, синева обводки сумок "
        .. "становятся серыми. Затемнение при этом действует поверх, и всё, "
        .. "чего оно не трогает, не трогается и здесь: значки заклинаний, "
        .. "портреты, карта и любой текст остаются своего цвета. По "
        .. "умолчанию выключено: «насколько темно» и «какого цвета» — два "
        .. "разных вопроса, и свежая установка отвечает только на первый.",
    ["Level Out the Bright Artwork"] = "Выравнивать яркую графику",
    ["On by default. Dimming multiplies, and multiplying keeps "
        .. "ratios: artwork the game drew nearly white - the gryphons, the "
        .. "main bar panel, the parchment of a dialog - stays twice as "
        .. "bright as the half-tones around it at every position of the "
        .. "slider, and those pieces glow while the rest of the interface "
        .. "is dark. With this on, anything brighter than a half-tone is "
        .. "brought down to one before the dimming is applied, so it lands "
        .. "where its neighbours land. Hue is kept: a colored texture gets "
        .. "darker, not different."] =
        "По умолчанию включено. Затемнение — это умножение, а умножение "
        .. "сохраняет отношения: графика, нарисованная игрой почти белой — "
        .. "грифоны, сама главная панель, пергамент окна разговора, — при "
        .. "любом положении ползунка остаётся вдвое светлее полутонов "
        .. "вокруг, и эти куски светятся, пока весь остальной интерфейс "
        .. "тёмный. С этой галочкой всё, что светлее полутона, приводится "
        .. "к полутону до затемнения и приходит туда же, куда приходят "
        .. "соседи. Оттенок сохраняется: цветная текстура становится "
        .. "темнее, а не другой.",
    ["what the cursor points at"] = "то, на что показывает курсор",
    ["point the cursor at it first, then type /dark probe mouse"] =
        "наведи на это курсор и набери /dark probe mouse",
    ["Show the Gryphons"] = "Показывать грифонов",
    ["The two beasts at the ends of the main action bar. They are the "
        .. "loudest piece of artwork the game draws, and a dark interface "
        .. "with them still in place looks like two different interfaces at "
        .. "once. On by default - taking away part of the game is the "
        .. "player's call, not ours. On a client with Edit Mode the bar "
        .. "belongs to it in combat, so a change made mid-fight applies as "
        .. "soon as the fight ends."] =
        "Две твари по краям главной панели команд. Это самая громкая "
        .. "картинка из всего, что рисует игра, и тёмный интерфейс с ними "
        .. "на месте выглядит как два интерфейса сразу. По умолчанию "
        .. "показаны: убирать часть игры — решение игрока, а не наше. На "
        .. "клиенте с Edit Mode панель в бою принадлежит ему, поэтому "
        .. "изменение, сделанное в бою, применяется сразу после выхода из "
        .. "боя.",

    -- Защищённые окна игры (Modules/Darkness.lua).
    ["Dim the Windows the Engine Protects"] =
        "Затемнять окна, которые защищает движок",
    ["On by default: a few of the game's windows - the talent frame among "
        .. "them - are watched by the engine, and leaving them out means one "
        .. "bright window in a dark interface. The cost is worth knowing. "
        .. "Everything an addon changes on such a window, the engine counts "
        .. "as changed by an addon from then on, and the window's own code "
        .. "runs marked; you do not see that when you drag the slider, you "
        .. "see it later, as \"Interface action failed because of an "
        .. "AddOn\" at the moment you press Apply on your talents. If that "
        .. "happens, switch this off and reload. Buttons stay untouched "
        .. "either way - their click is the protected action itself, and "
        .. "that is where the cost is real."] =
        "По умолчанию включено: часть окон игры — окно талантов среди них — "
        .. "движок держит под присмотром, и оставить их в стороне значит "
        .. "получить одно светлое окно посреди тёмного интерфейса. Цену "
        .. "знать стоит. Всё, что аддон на таком окне поменял, движок с "
        .. "этой минуты считает изменённым аддоном, и собственный код окна "
        .. "исполняется помеченным; видно это не тогда, когда вы двигаете "
        .. "ползунок, а позже — строкой \"Interface action failed because "
        .. "of an AddOn\" в тот момент, когда вы нажимаете \"применить\" в "
        .. "талантах. Если так случилось — снимите эту галочку и "
        .. "перезагрузите интерфейс. Кнопки не трогаются в любом случае: "
        .. "щелчок по ним и есть защищённое действие, и цена там "
        .. "настоящая.",

    -- Подписи вместилищ и вкладок колонки (Config/Options.lua,
    -- ns.TAB_GROUPS). Их ставит ядро: это решение о МЕСТЕ раздела, а не о
    -- его содержимом, и часть аддона, чей раздел легло вкладкой, своей
    -- подписи здесь не даёт.
    ["Gear"] = "Снаряжение",
    ["Look"] = "Вид",
    ["Rules"] = "Правила",
    ["Item Level"] = "Уровень предметов",
    ["Durability"] = "Прочность",

    -- Неймплейты (Modules/NamePlates.lua). Подписи настроек общие с
    -- юнитфреймами: одно и то же на экране обязано называться одинаково.
    -- Ключ «Nameplates» общий со списком исключений темноты.
    ["Nameplates"] = "Неймплейты",
    ["The addon's look on the game's own nameplates: bar texture, bar "
        .. "color, name color, font and dimming. This is not a nameplate "
        .. "engine - placement, auras and threat thresholds stay with the "
        .. "game. If a real nameplate addon is loaded, this section "
        .. "disappears and Darken does not touch nameplates at all."] =
        "Авторский вид на стандартных неймплейтах игры: текстура полоски, "
        .. "её цвет, цвет имени, шрифт и затемнение. Это не движок "
        .. "неймплейтов — расстановка, ауры и пороги угрозы остаются за "
        .. "игрой. Если стоит настоящий аддон неймплейтов, этот раздел "
        .. "пропадает, и Darken не трогает неймплейты вовсе.",
    ["Font and dimming for nameplates are set elsewhere and on purpose: "
        .. "the name uses the \"Unit Names\" font category, and dimming "
        .. "follows the Interface Darkness slider, where \"Nameplates\" can be "
        .. "excluded like any other group."] =
        "Шрифт и затемнение неймплейтов настраиваются не здесь, и это "
        .. "сделано намеренно: имя берёт шрифт категории «Имена юнитов», а "
        .. "затемнение идёт за ползунком темноты, где «Неймплейты» "
        .. "исключаются так же, как любая другая группа.",
    ["Nameplates are handled by \"%s\", so Darken leaves them alone: two "
        .. "addons painting one bar give flicker and errors. The nameplate "
        .. "section is hidden."] =
        "Неймплейтами занимается «%s», поэтому Darken их не трогает: два "
        .. "аддона на одной полоске дают мигание и ошибки. Раздел "
        .. "неймплейтов скрыт.",

    -- Полоса применения (Modules/CastBar.lua). Три раздела — игрока, цели и
    -- фокуса — устроены одинаково, поэтому подписи настроек общие на все три.
    ["Player Cast Bar"] = "Полоса игрока",
    ["Target Cast Bar"] = "Полоса цели",
    ["Focus Cast Bar"] = "Полоса фокуса",
    ["Game's Own Cast Text"] = "Родная подпись игры",
    ["Spell Name"] = "Название заклинания",
    ["Time Left"] = "Оставшееся время",
    ["Spell Name and Time Left"] = "Название и оставшееся время",
    ["Game's Own Cast Color"] = "Родной цвет игры",
    ["Custom Cast Colors"] = "Свои цвета",

    -- Тексты на полосках (Modules/Texts.lua).
    ["Bar Text"] = "Тексты на полосках",
    ["Health Bar Value"] = "Значение на полоске здоровья",
    ["What the health bar says. The first entry leaves the text to the "
        .. "game, including the game's own setting for whether to show it "
        .. "at all. Any other choice shows the text even when the game "
        .. "would hide it - that is what choosing a format means."] =
        "Что написано на полоске здоровья. Первая строка оставляет подпись "
        .. "игре — вместе с её собственной настройкой, показывать ли "
        .. "значения вообще. Любой другой выбор показывает надпись даже там, "
        .. "где игра её спрятала бы: выбор формата означает именно это.",
    ["Power Bar Value"] = "Значение на полоске ресурса",
    ["Mana, rage, energy. The first entry leaves the text to the game."] =
        "Мана, ярость, энергия. Первая строка оставляет подпись игре.",
    ["Shorten Large Numbers"] = "Сокращать крупные числа",
    ["Writes 12400 as 12.4k and 2500000 as 2.5m. Off by default, "
        .. "because the game writes numbers in full."] =
        "Пишет 12400 как 12.4k, а 2500000 как 2.5m. По умолчанию выключено: "
        .. "игра пишет числа целиком.",
    ["Value Position"] = "Положение значения",
    ["Where the value sits on the bar. Moving text on a unit frame is a "
        .. "protected operation: a change made in combat is applied as soon "
        .. "as combat ends. The format itself is not protected and applies "
        .. "immediately, in combat as well."] =
        "Где стоит значение на полоске. Перемещение надписи на юнитфрейме — "
        .. "защищённая движком операция: изменение, сделанное в бою, "
        .. "применяется сразу после выхода из боя. Сам формат защищённым не "
        .. "является и применяется немедленно, в том числе в бою.",
    ["Game's Own Bar Text"] = "Родное значение игры",
    ["Number"] = "Число",
    ["Percent"] = "Процент",
    ["Number and Percent"] = "Число и процент",
    ["Game's Own Position"] = "Родное положение игры",
    ["Left Edge"] = "У левого края",
    ["Center"] = "По центру",
    ["Right Edge"] = "У правого края",

    -- Показательный раздел (Config/Demo.lua). Уходит вместе с файлом при
    -- выпуске; переводы уходят той же правкой.
    ["This setting does nothing: the section exists to check appearance."] =
        "Настройка ничего не делает: раздел существует для проверки "
        .. "внешнего вида.",
    ["Disabled twin of the control above: this is what the disabled state "
        .. "looks like."] =
        "Запрещённый двойник элемента выше: так выглядит состояние запрета.",
    -- Панели действий (Modules/ActionBars.lua).
    -- Заголовки внутри раздела панели действий.
    -- Надписи на кнопке панели (Modules/ActionBars.lua).
    -- Подписи панелей и видов кнопок, приходящие переменной.
    ["Main Action Bar"] = "Главная панель действий",
    ["Bottom Left Bar"] = "Нижняя левая панель",
    ["Bottom Right Bar"] = "Нижняя правая панель",
    ["Right Bar"] = "Правая панель",
    ["Second Right Bar"] = "Вторая правая панель",
    ["Pet Bar"] = "Панель питомца",
    ["Stance Bar"] = "Панель стоек",
    ["Game's Own Button Look"] = "Родной вид кнопок игры",
    ["Dark Buttons"] = "Тёмные кнопки",
    -- Сетка ячеек стандартных сумок (Modules/Bags.lua). Подпись раздела
    -- осталась: он приезжает блоком на страницу затемнения.
    ["Game Bags"] = "Сумки игры",
    ["Bag Slot Borders"] = "Обводка ячеек сумки",
    ["Draws a one pixel border around every slot "
        .. "in the game's own bag windows, so that the grid reads "
        .. "as a grid. This is the one thing dimming cannot do for "
        .. "the bags by itself: dimming multiplies the artwork that "
        .. "is already there, and a line that is not there cannot "
        .. "be multiplied. Off to start with, and switching it off "
        .. "takes the line away at once, with no interface reload."] =
        "Рисует рамку в один пиксель вокруг каждой ячейки в родных окнах "
        .. "сумок игры, чтобы сетка читалась сеткой. Это единственное, чего "
        .. "затемнение для сумок сделать не может: затемнение множит цвет "
        .. "уже нарисованной картинки, а линию, которой нет, умножать не на "
        .. "что. Изначально выключена; выключение убирает линию сразу, без "
        .. "перезагрузки интерфейса.",
    -- Публичный слой модулей (Core/Api.lua, Core/Registry.lua). Эти строки
    -- видит игрок, поставивший чужой модуль: они обязаны объяснять, что
    -- случилось и что делать, не называя ни файлов, ни функций.
    ["Darken rejected a module: %s"] =
        "Darken отклонил модуль: %s",
    ["a module must be given as a table"] =
        "модуль должен передаваться таблицей",
    ["a module needs a name made of Latin letters, "
        .. "digits and underscores and starting with a letter"] =
        "имя модуля должно состоять из латинских букв, цифр и подчёркиваний "
        .. "и начинаться с буквы",
    ["the name \"%s\" belongs to Darken itself and cannot be a "
        .. "module name; names starting with \"core_\" are reserved for "
        .. "the core too, so name your module after your addon"] =
        "имя «%s» принадлежит самому Darken и не может быть именем модуля; "
        .. "имена, начинающиеся с «core_», тоже закреплены за ядром — "
        .. "называйте модуль по своему аддону",
    ["the name \"%s\" is already registered"] =
        "имя «%s» уже зарегистрировано",
    ["module \"%s\" declares \"%s\" of the wrong type"] =
        "модуль «%s» объявил поле «%s» неверного типа",
    ["the options section of module \"%s\" is not a group "
        .. "AceConfig can show"] =
        "раздел настроек модуля «%s» не является группой, которую AceConfig "
        .. "умеет показать",
    ["the options section of module \"%s\" was refused by "
        .. "AceConfig: %s"] =
        "раздел настроек модуля «%s» отвергнут AceConfig: %s",
    ["module \"%s\" does not say which Darken module API version "
        .. "it needs"] =
        "модуль «%s» не сообщил, какая версия API модулей Darken ему нужна",
    ["module \"%s\" needs Darken module API version %s, and this "
        .. "core provides %s; update Darken"] =
        "модулю «%s» нужна версия API модулей Darken %s, а это ядро даёт "
        .. "%s; обновите Darken",
    ["module \"%s\" was written for Darken module API version %s, "
        .. "which this core no longer supports (the oldest supported is "
        .. "%s); update the module"] =
        "модуль «%s» написан под версию API модулей Darken %s, которую это "
        .. "ядро больше не поддерживает (самая старая принимаемая — %s); "
        .. "обновите модуль",
    ["Module \"%s\" raised an error in %s and is switched off: the core "
        .. "will not call it again. The rest of Darken is unaffected. Its "
        .. "place in the settings window says so and offers to start it up "
        .. "again. Error: %s"] =
        "Модуль «%s» уронил ошибку в %s и отключён: ядро больше не будет его "
        .. "вызывать. На остальном аддоне это не сказывается. Его место в "
        .. "окне настроек говорит об этом и предлагает запустить его заново. "
        .. "Ошибка: %s",
    ["Module \"%s\" started up again and is working. Its settings are "
        .. "back where they were."] =
        "Модуль «%s» запустился заново и работает. Его настройки вернулись "
        .. "на прежнее место.",
    ["Darken did not start on this client, so it cannot take modules"] =
        "Darken не запустился на этом клиенте и не может принимать модули",
    -- Отложенное на выход из боя (Core/Combat.lua). Причину отказа модуль
    -- показывает игроку своей строкой в чат, поэтому она переводится так же,
    -- как остальные строки публичного слоя.
    ["deferring work needs a non-empty key and a function"] =
        "чтобы отложить работу, нужны непустой ключ и функция",
    ["a module that Darken switched off cannot defer work"] =
        "модуль, выключенный Darken, не может откладывать работу",
    ["the options section of module \"%s\" cannot be checked: "
        .. "AceConfigRegistry-3.0 is missing from this installation"] =
        "раздел настроек модуля «%s» нечем проверить: в установленном аддоне "
        .. "нет AceConfigRegistry-3.0",
    ["the options section of module \"%s\" uses \"handler\" with "
        .. "string method names; Darken cannot guard that form, so put "
        .. "the function itself in the node instead"] =
        "раздел настроек модуля «%s» пользуется полем handler и именами "
        .. "методов строками; Darken не умеет защищать такую форму — "
        .. "положите в узел саму функцию",
    ["the options section of module \"%s\" puts the method name "
        .. "\"%s\" in \"%s\"; Darken cannot guard that form, so put "
        .. "the function itself in the node instead"] =
        "раздел настроек модуля «%s» кладёт имя метода «%s» в поле «%s»; "
        .. "Darken не умеет защищать такую форму — положите в узел саму "
        .. "функцию",
    ["Darken has no settings scope named \"%s\""] =
        "у Darken нет раздела хранения с именем «%s»",
    -- Публичный слой: перевод сохранённых данных модуля (Core/Api.lua).
    ["the data to migrate must be a table"] =
        "переводимые данные должны быть таблицей",
    ["the migrations must be given as a table"] =
        "миграции задаются таблицей",
    ["the target format version must be a number"] =
        "целевая версия формы данных должна быть числом",
    ["the field \"%s\" on an Darken module handle belongs to "
        .. "the core and cannot be assigned"] =
        "поле «%s» описателя модуля Darken принадлежит ядру, и записывать "
        .. "в него нельзя",
    -- Публичный слой: замена подсистемы ядра модулем (Core/Api.lua).
    ["Darken has no subsystem named \"%s\" that a module may replace"] =
        "у Darken нет подсистемы «%s», которую модуль мог бы заменить собой",
    ["Darken's own \"%s\" section is already switched off, so a "
        .. "module cannot stand it down"] =
        "собственный раздел «%s» Darken уже выключен, и отвести его в "
        .. "сторону модуль не может",
    ["One owner per frame: module \"%s\" draws this now, so Darken's own "
        .. "\"%s\" section stands down until that module gives it back."] =
        "У одного фрейма один хозяин: теперь это рисует модуль «%s», поэтому "
        .. "собственный раздел «%s» Darken отходит в сторону, пока этот "
        .. "модуль не вернёт его обратно.",

    -- Возврат отведённой подсистемы (Core/Api.lua).
    ["module \"%s\" is switched off and cannot stand a subsystem of "
        .. "Darken down"] =
        "модуль «%s» выключен и не может отвести подсистему Darken в сторону",
    ["module \"%s\" is switched off; Darken has already given back what "
        .. "it stood down"] =
        "модуль «%s» выключен; Darken уже вернул то, что было отведено",
    ["Darken's own \"%s\" section was not stood down by a module, so there "
        .. "is nothing to give back"] =
        "собственный раздел «%s» Darken никакой модуль не отводил, и "
        .. "возвращать нечего",
    ["Darken's own \"%s\" section was stood down by module \"%s\", and "
        .. "only that module can give it back"] =
        "собственный раздел «%s» Darken отвёл модуль «%s», и вернуть его "
        .. "может только он",
    ["Darken's own \"%s\" section did not start up again"] =
        "собственный раздел «%s» Darken не смог вернуться в строй",
    ["Module \"%s\" does not draw this any more, so Darken's own \"%s\" "
        .. "section is back and has been applied."] =
        "Модуль «%s» это больше не рисует, поэтому собственный раздел «%s» "
        .. "Darken вернулся в строй, и его оформление применено.",

    -- Слэш-команды модулей (Core/Command.lua).
    ["a slash command needs a word made of Latin "
        .. "letters and digits and starting with a letter"] =
        "слову слэш-команды полагается состоять из латинских букв и цифр и "
        .. "начинаться с буквы",
    ["a slash command needs a function to call"] =
        "слэш-команде нужна функция, которую она позовёт",
    ["the command \"/%s\" belongs to Darken itself"] =
        "команда «/%s» принадлежит самому Darken",
    ["the command \"/%s\" is already taken by module \"%s\""] =
        "команда «/%s» уже занята модулем «%s»",
    ["the command \"/%s\" is already registered by another addon"] =
        "команду «/%s» уже зарегистрировал другой аддон",

    -- Ответы команд /darken в чат (Core/Init.lua).
    ["this client is not supported (flavor: %s, interface: %s). "
        .. "The addon did not start."] =
        "клиент не поддерживается (флейвор: %s, интерфейс: %s). Аддон не "
        .. "запущен.",
    ["could not add a page to the game's interface options (%s). "
        .. "The settings open with the /darken command."] =
        "не удалось добавить страницу в игровые настройки интерфейса (%s). "
        .. "Настройки открываются командой /darken.",
    ["this build has no demo section"] =
        "показательного раздела в этой сборке нет",
    ["the demo section is on"]  = "показательный раздел включён",
    ["the demo section is off"] = "показательный раздел выключен",
    ["usage: /darken scan <part of a frame name>"] =
        "использование: /darken scan <часть имени фрейма>",
    ["or /darken scan all - collect everything into the saved "
        .. "variables file"] =
        "или /darken scan all — собрать всё в файл сохранений",
    ["the settings database is not ready yet"] =
        "база настроек ещё не готова",
    ["collected %d names over %d patterns"] =
        "собрано %d имён по %d образцам",
    ["%d patterns hit the cap of %d names - their lists are "
        .. "the first %d by name, and scan.cut says how many "
        .. "there really were"] =
        "%d образцов упёрлось в потолок в %d имён: их списки - первые %d по "
            .. "алфавиту, а сколько имён было на самом деле, говорит scan.cut",
    ["log out - the result will land in Darken.lua (SavedVariables)"] =
        "выйдите из игры — результат ляжет в Darken.lua (SavedVariables)",
    ["found %d for the pattern '%s':"] = "найдено %d по образцу «%s»:",
    ["... and %d more - narrow the pattern"] =
        "... и ещё %d — уточните образец",

    -- Отказы, уходящие в чат через реестр (Core/Registry.lua,
    -- Core/Defaults.lua).
    ["this module was switched off"] = "модуль отключён",
    ["a module name must be a non-empty string"] =
        "имя модуля должно быть непустой строкой",
    ["the name '%s' is reserved for a housekeeping field of the profile"] =
        "имя «%s» зарезервировано под служебное поле профиля",
    ["the module name '%s' is taken by a core setting"] =
        "имя модуля «%s» занято настройкой ядра",
    -- Приветствие на первом входе (Core/Init.lua).
    ["the interface is dimmed to %d of "
        .. "100 - that is the one thing a fresh install changes. Type "
        .. "/darken for the settings, where the Interface Darkness slider goes back "
        .. "to zero in one drag."] =
        "интерфейс затемнён на %d из 100 — это единственное, что меняет "
        .. "свежая установка. Настройки открываются командой /darken, и "
        .. "ползунок затемнения возвращается к нулю одним движением.",
    ["type /darken for the settings. Everything the addon "
        .. "changes can be put back from the same place it was changed."] =
        "настройки открываются командой /darken. Всё, что аддон меняет, "
        .. "возвращается обратно оттуда же, откуда было изменено.",

    -- Отчёт о клиенте (Core/Report.lua, команда /darken report).
    ["answered by Darken %s, contract %s, settings %s, at %s by this "
        .. "computer's clock"] =
        "отвечала сборка Darken %s, версия контракта %s, версия настроек "
        .. "%s, в %s по часам этого компьютера",
    ["the report stored here until now was made by Darken %s, not by "
        .. "this one - it was out of date. The game reads addon code "
        .. "at login and on /reload, and at no other time."] =
        "лежавший здесь до сих пор отчёт собрала сборка Darken %s, а не "
        .. "эта: он устарел. Игра читает код аддона при входе и по /reload, "
        .. "и больше никогда.",
    ["client %s, build %s, interface %s, UI scale %s, screen %s"] =
        "клиент %s, сборка %s, интерфейс %s, масштаб интерфейса %s, экран %s",
    ["frame groups: %d confirmed, %d partial, %d empty, %d unconfirmed, "
        .. "%d degraded, %d absent on this client by design"] =
        "групп фреймов: %d подтверждено, %d нашли часть, %d пусты, "
        .. "%d не проверить, %d без подписок, "
        .. "%d в этом клиенте не бывает вовсе",
    ["%s did nothing: group \"%s\" resolved to nothing (%d names tried)"] =
        "%s ничего не сделала: группа «%s» не нашла ни одного имени "
        .. "(проверено %d)",
    ["and %d more groups resolved to nothing"] =
        "и ещё %d групп не нашли ничего",
    ["every frame group declared for this client resolved to something"] =
        "каждая объявленная этому клиенту группа нашла хоть что-то",
    ["%d groups found only part of what they name - see the saved "
        .. "variables"] =
        "%d групп нашли лишь часть названного — смотрите файл сохранений",
    ["%d groups could not be judged: the game makes those frames only "
        .. "after you open the window or take a target. Open them and "
        .. "run the report again."] =
        "о %d группах судить не по чему: эти фреймы игра заводит только "
        .. "после того, как вы откроете окно или возьмёте цель. Откройте их "
        .. "и повторите отчёт.",
    ["%d hook groups are empty here: those subsystems fall back to a "
        .. "delayed pass, which is slower but not broken"] =
        "%d групп подписок здесь пусты: эти подсистемы переходят на "
        .. "отложенный проход — медленнее, но не сломано",
    ["guessed names needing live confirmation: %d of %d exist here"] =
        "догадок, требующих подтверждения живым клиентом: %d из %d здесь есть",
    ["%d paths got part way: \"%s\" exists here and \"%s\" does not - "
        .. "the object is right, the last step is not"] =
        "%d путей дошли до середины: «%s» здесь есть, а «%s» нет — объект "
        .. "угадан верно, последний шаг нет",
    ["log out and send Darken.lua (SavedVariables) - the full report "
        .. "is in DarkenDB.global.report"] =
        "выйдите из игры и пришлите Darken.lua (SavedVariables) — полный "
        .. "отчёт лежит в DarkenDB.global.report",

    -- Подписи подсистем в отчёте о клиенте. Остальные взяты из уже
    -- переведённых подписей окна настроек: одно и то же обязано называться
    -- одинаково.
    ["Auras on Unit Frames"]      = "Ауры на юнитфреймах",
    ["Bag Windows"]               = "Окна сумок",
    ["Player Aura Grid"]          = "Сетка аур игрока",
    ["Item Level on Equipment"]   = "Уровень предметов на экипировке",
    ["Raid Frames"]               = "Рейдовые фреймы",
    ["Action Bar Layout"]         = "Раскладка панелей действий",
    ["An Unnamed Group"]          = "Неназванная группа",
    -- Счёт сделанного (Core/Tally.lua, та же команда /darken report).
    ["did nothing this session: %s"] =
        "за этот сеанс не сделали ничего: %s",
    ["the game quietly refused: %s"] =
        "игра молча отказала: %s",
    ["the game refused to register these events: %s - whatever waits "
        .. "on them did nothing and could not say why"] =
        "движок отказался регистрировать события: %s - всё, что их ждёт, "
            .. "не сделало ничего и не смогло сказать почему",
    ["this session: %s"] =
        "за этот сеанс: %s",
    ["this session the addon did not do a single counted thing"] =
        "за этот сеанс аддон не сделал ни одной считаемой вещи",
    ["modules: %d in service, %d switched off"] =
        "модулей: %d в строю, %d отключено",

    -- Подписи счётчиков. Приходят в ns.Localize полем таблицы, как и подписи
    -- подсистем выше.
    ["Objects Dimmed"]             = "Объектов затемнено",
    ["Objects Left As Content"]    = "Оставлено как содержимое",
    ["Repaints Heard"]             = "Перекрасок услышано",
    ["Bars Retextured"]            = "Полосок перетекстурено",
    ["Nameplates Attached"]        = "Неймплейтов взято",
    ["Nameplates Taken By The Engine"] = "Неймплейтов взято движком",
    ["Auras Ruled On"]             = "Аур отобрано списком",
    ["Positions Applied"]          = "Положений поставлено",
    ["Containers Recorded"]        = "Контейнеров записано",
    ["Game Functions Hooked"]      = "Функций игры подписано",
    ["Hooks That Ran"]             = "Срабатываний подписок",
    ["Work Deferred In Combat"]    = "Отложено из-за боя",
    ["Deferred Work Carried Out"]  = "Отложенного выполнено",
    ["Colours The Engine Refused"] = "Отказов движка по цвету",
    ["Protected Actions Refused"]  = "Отказов защищённому коду",
    ["Font Size Adjustment"] = "Поправка к размеру шрифта",
    ["game's own %+d"] = "как в игре %+d",
    ["Bigger or smaller than the game draws it, by this many points. "
        .. "Zero is the game's own sizes. Every element keeps the size the "
        .. "game gave it and moves by the same step, so a heading stays "
        .. "bigger than a small label - which is exactly what one size for "
        .. "the whole interface used to destroy. A single element that "
        .. "needs an exact size gets it on its own tab, and that number "
        .. "wins over this one."] =
        "Крупнее или мельче, чем рисует игра, — на столько пунктов. "
        .. "Ноль — родные размеры игры. Каждый элемент сохраняет размер, "
        .. "который ему дала игра, и сдвигается на один и тот же шаг, "
        .. "поэтому заголовок остаётся крупнее мелкой подписи — ровно то, "
        .. "что прежний единый размер на весь интерфейс и уничтожал. "
        .. "Элементу, которому нужен точный размер, он задаётся на его "
        .. "собственной вкладке, и то число сильнее этого.",
    ["Every other tab starts from what you choose here: a tab left "
        .. "on \"Same as Global\" follows this font and this outline, every "
        .. "element moves by the size adjustment below, and a tab that "
        .. "sets its own value wins over it. So one choice here is the "
        .. "short way to one font everywhere, and the tabs are for the "
        .. "elements that need something else."] =
        "Каждая другая вкладка отсчитывается от выбранного здесь: "
        .. "вкладка, оставленная на «Как глобально», следует этому шрифту "
        .. "и этому контуру, каждый элемент сдвигается на поправку размера "
        .. "ниже, а вкладка со своим значением сильнее. Так один выбор "
        .. "здесь — короткий путь к одному шрифту везде, а вкладки — для "
        .. "тех элементов, которым нужно другое.",
    ["What you set here wins over the Global tab for this element "
        .. "alone. \"Same as Global\" means the field follows the Global tab "
        .. "instead and keeps following it as you change it there; a size "
        .. "of zero means this element keeps the size the game gave it, "
        .. "moved by the adjustment on the Global tab."] =
        "Заданное здесь сильнее глобальной вкладки — но только для "
        .. "этого элемента. «Как глобально» означает, что поле следует "
        .. "глобальной вкладке и продолжает следовать за её правками; "
        .. "нулевой размер означает, что элемент сохраняет размер, который "
        .. "ему дала игра, сдвинутый на поправку с глобальной вкладки.",
    ["An exact size for this element alone, in points, and it wins "
        .. "over the adjustment on the Global tab. Zero means the element "
        .. "keeps the size the game gave it and follows that adjustment "
        .. "instead."] =
        "Точный размер для одного этого элемента, в пунктах, и он "
        .. "сильнее поправки с глобальной вкладки. Ноль означает, что "
        .. "элемент сохраняет размер, который ему дала игра, и следует той "
        .. "поправке.",
    ["Overall Strength"] = "Общая сила",
    ["Game's Own Look"] = "Родной вид игры",
    ["Leave every area on \"Overall Strength\" and the slider alone "
        .. "decides how dark the whole interface is. Give one area a "
        .. "strength of its own and it stops listening to the slider and "
        .. "keeps that strength wherever the slider goes."] =
        "Оставьте все области на «Общей силе» — и насколько темно всему "
        .. "интерфейсу, решает один ползунок. Задайте области свою силу — "
        .. "и она перестаёт слушать ползунок и держит эту силу, куда бы "
        .. "он ни ушёл.",
    ["\"Other Windows\" above means every window not named here, "
        .. "including ones later patches add and ones other addons build "
        .. "in the game's style: darkening finds them by walking the "
        .. "interface, not from a list of names. Single windows out of "
        .. "that sweep are handled one at a time below."] =
        "«Прочие окна» выше означает каждое окно, не названное здесь, — "
        .. "включая те, что добавят будущие патчи, и те, что чужие аддоны "
        .. "строят в стиле игры: затемнение находит их обходом интерфейса, "
        .. "а не по списку имён. Отдельные окна из этого прохода "
        .. "разбираются поштучно ниже.",
    ["How dark this area is. \"Overall Strength\" means the strength "
        .. "slider on this page decides, and one drag of it moves this "
        .. "area along with everything else. Any named strength here wins "
        .. "over the slider and stays put. \"Game's Own Look\" leaves "
        .. "this area exactly as the game draws it - no darkening and no "
        .. "tint."] =
        "Насколько темна эта область. «Общая сила» означает, что решает "
        .. "ползунок силы на этой же странице, и одно его движение ведёт "
        .. "эту область вместе со всем остальным. Любая названная здесь "
        .. "сила сильнее ползунка и остаётся на месте. «Родной вид игры» "
        .. "оставляет область ровно такой, какой её рисует игра, — без "
        .. "затемнения и без оттенка.",
    ["These Settings Are For"] = "Эти настройки — для",
    ["All Frames"] = "Всех фреймов",
    ["Party"] = "Группы",
    ["Back to the Shared Settings"] = "Вернуть к общим настройкам",
    ["\"All Frames\" is the choice every frame follows until you give "
        .. "that frame one of its own. What you set on a single frame wins "
        .. "over it and keeps winning; what you leave as \"Same as All "
        .. "Frames\" follows the shared choice and keeps following it as "
        .. "you change it. Your own frame and the target frame are looked "
        .. "at differently - one out of the corner of the eye, the other "
        .. "in a fight - and one setting for both means choosing what gets "
        .. "in the way least rather than what you want."] =
        "«Все фреймы» — выбор, которому следует каждый фрейм, пока вы "
        .. "не задали этому фрейму свой. Заданное на одном фрейме сильнее "
        .. "общего и остаётся сильнее; оставленное как «Как у всех "
        .. "фреймов» следует общему выбору и продолжает следовать за его "
        .. "правками. На свой фрейм и на фрейм цели смотрят по-разному — "
        .. "на один краем глаза, на другой в бою, — и одна настройка на "
        .. "оба означает выбор не того, что нужно, а того, что меньше "
        .. "мешает.",
    ["Drops everything set on this frame alone, so it follows the "
        .. "shared choice again - and goes on following it."] =
        "Снимает всё, что задано на одном этом фрейме, и он снова "
        .. "следует общему выбору — и продолжает следовать.",
    ["Individual Frames"] = "Отдельные фреймы",
    ["There is no frame to choose on this tab, and that is the whole "
        .. "difference between it and the one beside it: the group grid "
        .. "has no unit of its own, and one size serves every member. "
        .. "Width and height here are real numbers, unlike the player and "
        .. "target frames, which are drawn from artwork and have scale "
        .. "only."] =
        "Выбирать фрейм на этой вкладке не из чего, и в этом вся разница "
        .. "между ней и соседней: у сетки группы своего юнита нет, и один "
        .. "размер служит каждому в ней. Ширина с высотой здесь — "
        .. "настоящие числа, в отличие от фреймов игрока и цели, которые "
        .. "нарисованы обвязкой и имеют только масштаб.",
    ["Accent Color"] = "Цвет акцента",
    ["The one color the dark theme uses to say look here: section headings, the tick in a checkbox, the filled part of a slider, the scrollbar, the chosen row and whatever the mouse is over. Everything else - the blacks, the lines, the text - stays as it is. Parts already drawn keep the old color until /reload."] = "Тот единственный цвет, которым тёмная тема говорит «посмотри сюда»: заголовки разделов, галочка флажка, заполненная часть ползунка, полоска прокрутки, выбранная строка и то, на что наведена мышь. Остальное — чернота, линии, текст — остаётся как было. Уже нарисованное держит прежний цвет до /reload.",
    ["The first entry is the game's own texture: the addon leaves it "
        .. "alone until asked, and going back to it restores exactly the look "
        .. "you had before, at once and without an interface reload. The "
        .. "addon's own textures are a gradient from white to a color. The "
        .. "engine multiplies them by the bar color, so the white end gives "
        .. "the pure color and the pastel end its muted shade. Which color "
        .. "that is, is chosen right below."] =
        "Первая строка списка — родная текстура игры: аддон не подменяет "
        .. "её, пока не попросили, и возврат к ней возвращает ровно тот вид, "
        .. "что был до первой подмены, сразу и без перезагрузки интерфейса. "
        .. "Авторские текстуры — градиент от белого к цвету. Движок умножает "
        .. "их на цвет полоски, поэтому белый конец даёт чистый цвет, а "
        .. "пастельный — его приглушённый оттенок. Какой это цвет, выбирается "
        .. "прямо ниже.",

    ["letters %d"] = "букв %d",
    ["font"] = "шрифт",
    ["shown"] = "показана",
    ["color"] = "цвет",
    ["layer"] = "слой",
    ["visible"] = "видна",
    ["owner"] = "хозяин",
    ["room"] = "отведено",
    ["anchors"] = "привязок",
    ["at"] = "в точке",
    ["opacity"] = "прозрачность",
    ["size"] = "размер",
    ["no explanatory paragraph found in the window"] =
        "в окне не нашлось ни одного абзаца пояснения",
    ["open the settings window first, then type /dark probe text"] =
        "сперва откройте окно настроек, потом наберите /dark probe text",

    ["this build has no widget demo"] = "в этой сборке показа виджетов нет",
    ["this build has no new settings window"] = "в этой сборке нового окна настроек нет",
    ["new settings window is open"] = "новое окно настроек открыто",
    ["new settings window is closed"] = "новое окно настроек закрыто",
    ["widget demo is open"] = "показ виджетов открыт",
    ["widget demo is closed"] = "показ виджетов закрыт",
    ["A button on the edge of the minimap that opens and closes this window. Drag it around the minimap to move it."] =
        "Кнопка у края миникарты, открывающая и закрывающая это окно. Её " ..
        "можно перетащить по краю миникарты.",
    ["A correction, not a size: zero means every element keeps the size the game gives it, so a fresh profile changes not a single letter."] =
        "Поправка, а не размер: ноль означает, что каждый элемент сохраняет " ..
        "размер, который даёт ему игра, и свежий профиль не меняет ни одной " ..
        "буквы.",
    ["A profile is every setting in this window at once. Which profile a character uses is that character's own choice; the profiles themselves are shared across the account."] =
        "Профиль — это все настройки этого окна разом. Какой профиль у " ..
        "персонажа, решает он сам; сами профили общие на весь аккаунт.",
    ["A size of its own for this group. Zero follows the global tab and the size adjustment on it."] =
        "Свой размер для этой группы. Ноль означает «как на общей вкладке», " ..
        "с её поправкой размера.",
    ["A soft shadow behind every icon, so icons read apart from the darkened interface behind them."] =
        "Мягкая тень за каждым значком, чтобы значки читались отдельно от " ..
        "затемнённого интерфейса за ними.",
    ["A thin line around every icon, in the addon's own colour."] =
        "Тонкая линия вокруг каждого значка, цветом аддона.",
    ["Bag Reading"] = "Чтение сумок",
    ["Bag Sorting"] = "Сортировка сумок",
    ["Bags"] = "Сумки",
    ["Bring the brightest pieces of artwork down to the same ceiling as the rest, so nothing stands out by being lighter than everything around it."] =
        "Опустить самые светлые куски оформления до того же потолка, что и " ..
        "остальные, чтобы ничто не выделялось одной лишь яркостью.",
    ["Color Picker"] = "Выбор цвета",
    ["Copy Settings From"] = "Скопировать настройки из",
    ["Crop Icon Borders"] = "Обрезать кромку значков",
    ["Current Profile"] = "Текущий профиль",
    ["Delete Profile"] = "Удалить профиль",
    ["Do not touch the game's own font objects at all. Everything the addon draws itself still follows the settings here."] =
        "Не трогать шрифтовые объекты самой игры вовсе. Всё, что аддон " ..
        "рисует сам, по-прежнему следует этим настройкам.",
    ["Drain the colour out of the interface's own artwork as well as darkening it. Icons, bars, portraits and the map keep their colour either way."] =
        "Обесцветить оформление интерфейса вдобавок к затемнению. Значки, " ..
        "полосы, портреты и карта сохраняют цвет в любом случае.",
    ["Draw a thin line around every bag slot. The game draws the slots themselves; this only adds the outline."] =
        "Обвести тонкой линией каждую ячейку сумки. Сами ячейки рисует " ..
        "игра; здесь добавляется только обводка.",
    ["Edit Mode"] = "Режим правки",
    ["Every other tab starts from what you choose here: a tab left on \"Same as Global\" follows this font and this outline, every element moves by the size adjustment below, and a tab that sets its own value wins over it."] =
        "Каждая другая вкладка отталкивается от выбранного здесь: вкладка, " ..
        "оставленная на «Как общий», берёт этот шрифт и эту обводку, каждый " ..
        "элемент сдвигается на поправку размера ниже, а вкладка со своим " ..
        "значением перебивает общее.",
    ["Extra Action Button"] = "Дополнительная кнопка действия",
    ["Focus"] = "Фокус",
    ["Give the profile you are in that name. Its settings come with it."] =
        "Дать профилю, в котором вы находитесь, это имя. Его настройки " ..
        "остаются при нём.",
    ["Health Bar Fixed Color"] = "Свой цвет полосы здоровья",
    ["Health Text"] = "Текст здоровья",
    ["How big the portrait frames are drawn. One is the size the game gives them."] =
        "Насколько крупно рисуются портретные фреймы. Единица — размер, " ..
        "который даёт им игра.",
    ["How dark this area is. \"Overall Strength\" means the strength slider on this page decides. Any named strength here wins over the slider and stays put."] =
        "Насколько темна эта область. «Общая сила» означает, что решает " ..
        "ползунок силы на этой странице. Любая названная здесь сила " ..
        "перебивает ползунок и остаётся как есть.",
    ["How much to dim the interface's own artwork: frames, borders, backgrounds and the trim around them. Zero is the game's own look and is one drag away; one hundred is as dark as the addon goes, and that is deliberately not black - a frame you cannot make out is not a dimmed frame, it is a missing one."] =
        "Насколько затемнять оформление интерфейса: рамки, обводки, " ..
        "подложки и окантовку вокруг них. Ноль — родной вид игры, и до него " ..
        "одно движение ползунка; сто — самое тёмное, на что аддон идёт, и " ..
        "это нарочно не чёрный: фрейм, который не разглядеть, — это не " ..
        "затемнённый фрейм, а пропавший.",
    ["Icons"] = "Значки",
    ["Icons Dimmed"]               = "Иконок затемнено",
    ["Labels Raised"]              = "Надписей поднято",
    ["Labels Left Light"]          = "Надписей оставлено светлыми",
    ["Another Addon's, Left Alone"] = "Чужих аддонов не тронуто",
    ["Chat Left To Its Owner"] = "Чат оставлен его хозяину",
    ["Icon Edges Trimmed"]         = "Кромок у иконок срезано",
    ["Minimap Buttons Rounded"]    = "Кнопок миникарты скруглено",
    ["Icons Framed"] = "Значков обведено",
    ["Leave Vehicle Button"] = "Кнопка выхода из транспорта",
    ["Name and Size"] = "Имя и размер",
    ["Nameplates The Game Showed"] = "Неймплейтов показала игра",
    ["Names This Client Does Not Have"] = "Имён, которых нет у этого клиента",
    ["New Profile"] = "Новый профиль",
    ["Objects The Game Keeps To Itself"] = "Объектов игра оставила себе",
    ["Only used while the switch above is on."] =
        "Берётся в расчёт только при включённом выключателе выше.",
    ["Other Profiles"] = "Другие профили",
    ["Outline Bag Slots"] = "Обводить ячейки сумок",
    ["Outline Icons"] = "Обводить значки",
    ["Paint the settings windows of other addons that use the same library this one does. Needs /reload either way."] =
        "Красить окна настроек других аддонов, пользующихся той же " ..
        "библиотекой. В обе стороны требует /reload.",
    ["Panel Tabs"] = "Вкладки панели",
    ["Party and Raid Frames"] = "Фреймы группы и рейда",
    ["Pet"] = "Питомец",
    ["Player"] = "Игрок",
    ["Power Bar Fixed Color"] = "Свой цвет полосы ресурса",
    ["Power Text"] = "Текст ресурса",
    ["Profile Name"] = "Имя профиля",
    ["Profiles"] = "Профили",
    ["Protected Frames The Sweep Left Alone"] =
        "Защищённых фреймов обход не тронул",
    ["Put every setting in the profile you are in back to the addon's defaults. Other profiles are left alone."] =
        "Вернуть все настройки профиля, в котором вы находитесь, к " ..
        "умолчаниям аддона. Другие профили не трогаются.",
    ["Remove a profile you are not using. The one you are in cannot be deleted: deleting it would leave the addon with no settings at all."] =
        "Удалить профиль, которым вы не пользуетесь. Тот, в котором вы " ..
        "находитесь, удалить нельзя: аддон остался бы вовсе без настроек.",
    ["Rename"] = "Переименовать",
    ["Reset This Profile"] = "Сбросить этот профиль",
    ["Secret Values The Engine Refused"] =
        "Закрытых значений движок не отдал",
    ["Set the Size of Group Frames"] = "Задавать размер фреймов группы",
    ["Shadow Under Icons"] = "Тень под значками",
    ["Some windows are protected by the engine, and touching them can make the game refuse an action later. Off leaves them exactly as the game draws them."] =
        "Часть окон защищена движком, и прикосновение к ним может заставить " ..
        "игру отказать в действии позже. Выключенным оставляет их ровно " ..
        "такими, какими их рисует игра.",
    ["Spell and item icons across the whole interface. Each of these is off on a fresh install: an icon is how the player recognises a spell, and changing it is a choice, not a default."] =
        "Значки заклинаний и предметов по всему интерфейсу. Каждая из этих " ..
        "настроек выключена на свежей установке: по значку игрок узнаёт " ..
        "заклинание, и менять его — выбор, а не умолчание.",
    ["Start a profile with that name, at the addon's defaults, and switch this character to it."] =
        "Завести профиль с таким именем, на умолчаниях аддона, и перевести " ..
        "в него этого персонажа.",
    ["Switch this character to another profile. Everything in this window follows at once."] =
        "Перевести этого персонажа в другой профиль. Всё в этом окне " ..
        "меняется следом сразу.",
    ["Take every setting from another profile into the one you are in. The other profile is left alone."] =
        "Взять все настройки другого профиля в тот, в котором вы " ..
        "находитесь. Другой профиль не трогается.",
    ["Tapped Mobs Greyed"] = "Чужая добыча блёкнет",
    ["Target"] = "Цель",
    ["Target of Target"] = "Цель цели",
    ["Text Position"] = "Место текста",
    ["The bars the game draws over heads. The first entry in every list is the game's own look."] =
        "Полосы, которые игра рисует над головами. Первая запись в каждом " ..
        "списке — родной вид игры.",
    ["The font for this group of elements. The first entry follows the global tab."] =
        "Шрифт для этой группы элементов. Первая запись означает «как на " ..
        "общей вкладке».",
    ["The font the whole interface uses. The first entry leaves the game's own font in place."] =
        "Шрифт, которым набран весь интерфейс. Первая запись оставляет " ..
        "родной шрифт игры.",
    ["The game's own portrait frames: you, your target, the party. The first entry in every list below is the game's own look, so nothing here is one way."] =
        "Родные портретные фреймы игры: вы, ваша цель, группа. Первая " ..
        "запись в каждом списке ниже — родной вид игры, так что ничто здесь " ..
        "не в одну сторону.",
    ["The numbers written across the health and power bars. The first entry in every list is the game's own."] =
        "Числа, написанные поверх полос здоровья и ресурса. Первая запись в " ..
        "каждом списке — родная игровая.",
    ["The one colour used when the health bar is set to a fixed colour above."] =
        "Тот единственный цвет, которым красится полоса здоровья, если выше " ..
        "выбран свой цвет.",
    ["The one colour used when the name is set to a fixed colour above."] =
        "Тот единственный цвет, которым красится имя, если выше выбран свой " ..
        "цвет.",
    ["The one colour used when the power bar is set to a fixed colour above."] =
        "Тот единственный цвет, которым красится полоса ресурса, если выше " ..
        "выбран свой цвет.",
    ["The outline around every letter. Thin reads better on a bright world, none reads better on a dark interface."] =
        "Обводка вокруг каждой буквы. Тонкая лучше читается на светлом " ..
        "мире, отсутствие обводки — на тёмном интерфейсе.",
    ["The outline for this group. The first entry follows the global tab."] =
        "Обводка для этой группы. Первая запись означает «как на общей " ..
        "вкладке».",
    ["The same choice for the power bar."] =
        "Тот же выбор для полосы ресурса.",
    ["The texture the health bar is drawn with. The first entry leaves the game's own."] =
        "Текстура, которой нарисована полоса здоровья. Первая запись " ..
        "оставляет родную игровую.",
    ["The texture the power bar is drawn with. The first entry leaves the game's own."] =
        "Текстура, которой нарисована полоса ресурса. Первая запись " ..
        "оставляет родную игровую.",
    ["The two end caps of the main action bar. Hiding them is the one thing here that removes a piece of the game rather than darkening it."] =
        "Два навершия основной панели умений. Их скрытие — единственное " ..
        "здесь, что убирает кусок игры, а не затемняет его.",
    ["Trim the dull edge the artist drew around each icon, so the picture itself fills the square."] =
        "Срезать тусклую кромку, которую художник нарисовал вокруг каждого " ..
        "значка, чтобы сама картинка заполнила квадрат.",
    ["Type a name here, then press one of the buttons below."] =
        "Наберите здесь имя и нажмите одну из кнопок ниже.",
    ["Unit Name Color"] = "Цвет имени юнита",
    ["Unit Name Fixed Color"] = "Свой цвет имени юнита",
    ["What the health bar says: nothing, the current value, the value and the maximum, or a percentage."] =
        "Что написано на полосе здоровья: ничего, текущее значение, " ..
        "значение и предел или проценты.",
    ["What the health bar's colour means: the game's own rule, the class of whoever it belongs to, or one colour you pick."] =
        "Что означает цвет полосы здоровья: родное правило игры, класс " ..
        "того, кому она принадлежит, или один выбранный вами цвет.",
    ["What the power bar's colour means: the game's own rule by power type, or one colour you pick."] =
        "Что означает цвет полосы ресурса: родное правило игры по виду " ..
        "ресурса или один выбранный вами цвет.",
    ["What the unit's name is coloured by: the game's own rule, the unit's class, or one colour you pick."] =
        "Чем покрашено имя юнита: родным правилом игры, классом юнита или " ..
        "одним выбранным вами цветом.",
    ["Where on the bar the number stands."] = "Где на полосе стоит число.",
    ["While this is off, not one number is forced on the game: a party member keeps the size the game gave it, and the real native numbers are read before the first change of ours and put back when this goes off again."] =
        "Пока это выключено, игре не навязывается ни одного числа: член " ..
        "группы сохраняет размер, который дала ему игра, а настоящие родные " ..
        "числа считываются до первой нашей правки и возвращаются, когда это " ..
        "выключают снова.",
    ["World Map"] = "Карта мира",
    ["Write thousands as a short form instead of every digit."] =
        "Писать тысячи сокращённо, а не каждой цифрой.",
    ["module \"%s\" brings an options section, and this version does not draw one: the settings window builds its pages from the schema instead. The module works; its settings are simply not shown."] =
        "модуль «%s» принёс раздел настроек, а эта версия дерева настроек " ..
        "не рисует: окно собирает свои страницы из схемы. Сам модуль " ..
        "работает; просто его настроек не видно.",
})
