local ADDON, ns = ...

-- Український переклад інтерфейсу.
--
-- Ключ — английская строка из места вызова ns.Localize, один в один.
-- Английский текст менять здесь нельзя: изменится ключ, и перевод
-- перестанет находиться, а игрок увидит английскую подпись. Правка
-- английского всегда идёт парой — в месте вызова и здесь.
--
-- Порядок записей тот же, что в Locale/ruRU.lua: так две таблицы
-- сравниваются построчно и видно, что ни одна запись не потерялась.
--
-- Официальной украинской локали у клиента WoW нет, поэтому сверять
-- терминологию не с чем: слова выбраны так, как их читает украинский
-- игрок, а не переписаны с русского. Ключ, в переводе которого нет
-- уверенности, лучше не класть сюда вовсе: пропуск показывается
-- по-английски и заметен, а неверный перевод выглядит готовым.

ns.RegisterLocale("ukUA", {

    -- Общая оболочка окна.
    ["Close"] = "Закрити",

    -- Пошук по налаштуваннях (Config/Search.lua).
    -- Общий раздел настроек (Config/Options.lua).
    ["General"] = "Загальне",
    ["Darken repaints the game's "
        .. "own interface dark and hands you the parts "
        .. "Blizzard leaves alone. Nothing here is one "
        .. "way: the first entry in every list is the "
        .. "game's own look, and the one setting a fresh "
        .. "install changes by itself is the interface darkness, at "
        .. "sixty-four of a hundred. Type /darken in chat to "
        .. "open this window again."] =
        "Darken перефарбовує власний інтерфейс гри в темний і віддає вам "
        .. "ті його частини, які Blizzard не налаштовує. Дороги в один бік "
        .. "тут немає: першим рядком у кожному списку стоїть рідний вигляд "
        .. "гри, а єдине налаштування, яке свіже встановлення змінює саме, — "
        .. "затемнення, шістдесят чотири зі ста. Щоб відкрити це вікно знову, "
        .. "наберіть у чаті /darken.",
    ["This Copy"] = "Ця збірка",

    -- Страница аддона в настройках игры (Config/Options.lua).
    ["Darken has a settings window of its own. This page is narrow and "
        .. "shares the screen with the game's own panels, so the settings "
        .. "live in that window instead of here."] =
        "Darken має власне вікно налаштувань. Ця сторінка вузька й ділить "
        .. "екран з панелями самої гри, тому налаштування живуть у тому "
        .. "вікні, а не тут.",
    ["Open the Settings Window"] = "Відкрити вікно налаштувань",
    ["Typing /darken in chat opens the same window."] =
        "Набране в чаті /darken відкриває те саме вікно.",

    -- Узел-вместилище в колонке разделов (Config/Options.lua).
    -- Розділ на місці вимкненого модуля (Config/Options.lua).
    ["Skin Settings Windows"] = "Стилізувати вікна налаштувань",

    -- Пресети вигляду (Core/Presets.lua, кнопки в Config/Options.lua).
    ["Looks"] = "Вигляди",
    ["A look is a batch of this addon's own settings applied at once. It "
        .. "touches only the settings it names below: everything else stays "
        .. "as you left it. Nothing is locked in - each of these settings "
        .. "keeps its own list in its own section, and the game's own look "
        .. "is the first entry in every one of them."] =
        "Вигляд — це набір наших же налаштувань, застосований однією дією. "
        .. "Він чіпає лише ті налаштування, які названі нижче: решта "
        .. "лишається такою, якою ви її лишили. Дороги в один бік тут немає: "
        .. "кожне з цих налаштувань стоїть на своєму місці зі своїм списком, "
        .. "а рідний вигляд гри — перший рядок у кожному з них.",
    -- Питання перед застосуванням пресета (Core/Presets.lua). Три абзаци,
    -- і кожен відповідає на своє: що застосовуємо, що зміниться й що
    -- лишиться, як повернути попереднє.
    ["Apply \"%s\"?"] = "Застосувати «%s»?",
    ["It changes %s. Every other setting stays as it is."] =
        "Зміниться: %s. Усі інші налаштування лишаться як є.",
    ["To keep your current look, cancel and copy the profile first in the "
        .. "Profiles section."] =
        "Щоб нинішній вигляд можна було повернути, скасуйте це питання і "
        .. "скопіюйте профіль у розділі «Профілі».",
    ["Game's Own"] = "як у грі",

    ["Classic Look"] = "Класичний вигляд",
    ["Our settings arranged to read as the game did in 1.x: bars and "
        .. "fonts left to the game, and dimming off - the interface back to "
        .. "the game's own brightness. It is not a restoration of the old "
        .. "window art - that is a separate, much larger piece of work. Each "
        .. "of the three looks says what the dimming slider should be, this "
        .. "one included: a look you press is the whole look, not the "
        .. "difference from what you had."] =
        "Наші налаштування, розставлені так, щоб інтерфейс читався як у "
        .. "1.x: смужки та шрифти віддані грі, затемнення вимкнено — "
        .. "яскравість інтерфейсу повертається до ігрової. Це не "
        .. "відновлення старого оформлення вікон — воно робиться окремо й "
        .. "коштує незрівнянно більше. Кожен із трьох виглядів називає і "
        .. "положення повзунка затемнення, цей теж: натиснутий вигляд — це "
        .. "вигляд цілком, а не різниця з тим, що було.",
    ["Modern Look"] = "Сучасний вигляд",
    ["Our settings arranged to read as the game does today: bars colored "
        .. "by class and power type, thin outline on text, and the dimming a "
        .. "fresh install comes with."] =
        "Наші налаштування, розставлені так, щоб інтерфейс читався як "
        .. "сьогодні: смужки пофарбовані за класом і за видом ресурсу, у "
        .. "тексту тонкий контур, затемнення — те саме, що у свіжому "
        .. "встановленні.",
    ["The Author's Look"] = "Авторський вигляд",
    ["The addon's own unit frame look: the health bar tinted by class "
        .. "color, the power bar by power type, and the dimming a fresh "
        .. "install comes with. Fonts and name color stay yours."] =
        "Авторський вигляд юнітфреймів: смужка здоров'я тонується кольором "
        .. "класу, смужка ресурсу — кольором ресурсу, затемнення — те саме, "
        .. "що у свіжому встановленні. Шрифти та колір імені лишаються "
        .. "вашими.",

    -- Підсистема затемнення (Modules/Darkness.lua). Розділ і повзунок
    -- названі одним словом, і українською воно теж одне.
    ["Interface Darkness"] = "Темрява інтерфейсу",
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
        "Наскільки приглушити власну графіку інтерфейсу: фрейми, рамки, "
        .. "підкладки й обв'язку навколо них. Свіже встановлення "
        .. "починається з шістдесяти чотирьох, і це єдине, що встановлення "
        .. "аддона змінює саме: темний інтерфейс, невідрізний від "
        .. "незайманої гри, не робить того, заради чого його ставлять. "
        .. "Нуль — рідний вигляд гри, і до нього один рух; сто — найтемніше, "
        .. "до чого доходить аддон, і це навмисно не чорний: фрейм, якого не "
        .. "розгледіти, — не затемнений фрейм, а зниклий. Смужки здоров'я та "
        .. "ресурсу, значки заклять, портрети юнітів, модель персонажа й "
        .. "сама карта зберігають свій колір за будь-якого положення "
        .. "повзунка. Текст теж, окрім одного місця: сторінка завдання й "
        .. "розмова з істотою — єдине місце в грі, де текст надрукований "
        .. "темним по світлому, і там темний текст піднімається у світлий, "
        .. "щоб затемнена сторінка читалася. Зміна застосовується одразу, "
        .. "перезавантаження інтерфейсу не потрібне; повернення до нуля "
        .. "повертає попередній вигляд.",
    ["Tint"] = "Відтінок",
    ["The color the interface's artwork is " ..
        "tinted with. White changes nothing and is the default, " ..
        "so a fresh install is dimmed but not tinted. " ..
        "Tinting is the same multiply as dimming, only with the " ..
        "three color channels dimmed by different amounts, which " ..
        "is why it works on its own: a tint with the dimming at " ..
        "zero recolors the frames without darkening them. The " ..
        "same things dimming leaves alone are left alone here."] =
        "Колір, яким підфарбовується графіка інтерфейсу. Білий не змінює " ..
        "нічого й стоїть типово: свіже встановлення затемнене, але не " ..
        "підфарбоване. Відтінок — те саме " ..
        "множення, що й затемнення, тільки три кольорові канали гасяться " ..
        "по-різному; тому він працює й сам по собі: відтінок за нуля на " ..
        "слайдері перефарбовує фрейми, не затемнюючи їх. Того, чого не " ..
        "чіпає затемнення, не чіпає і він.",
    -- Режими областей (Modules/Darkness.lua).
    ["Areas"] = "Області",
    ["Dimmed"] = "Приглушено",
    ["Dark"] = "Темно",
    ["More Dark"] = "Ще темніше",
    ["Darker"] = "Темніше",
    ["Even Darker"] = "Ще темніше",
    ["Black"] = "Чорний",

    -- Винятки по одному вікну (Modules/Darkness.lua).
    ["Individual Windows"] = "Окремі вікна",
    ["Find a Window"] = "Пошук вікна",
    ["Narrows the list below to windows whose " ..
        "name contains what you type. The list is not written by " ..
        "hand: it is the windows dimming has actually reached, so " ..
        "it grows as you open the game's own windows and is " ..
        "remembered between sessions."] =
        "Лишає у списку нижче вікна, в імені яких є набране. Список не " ..
        "написаний руками: це ті вікна, до яких темрява справді сягнула, " ..
        "тому він поповнюється в міру того, як ви відкриваєте вікна гри, " ..
        "і запам'ятовується між сеансами.",
    ["Nothing here yet. This list fills itself " ..
        "as you open the game's windows - it is built from what " ..
        "dimming actually touched, and a fresh install starts " ..
        "empty rather than guessing at names. What appears here " ..
        "is remembered between sessions, so it is waiting for you " ..
        "the next time you log in."] =
        "Тут поки порожньо. Список наповнюється сам, у міру того як ви " ..
        "відкриваєте вікна гри: він зібраний з того, чого темрява справді " ..
        "торкнулася, а свіже встановлення починає з порожнього списку, а " ..
        "не з здогадок про імена. Те, що тут з'явиться, " ..
        "запам'ятовується між сеансами й чекатиме на вас наступного " ..
        "входу в гру.",
    ["Windows Seen So Far"] = "Побачені вікна",
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
        "Позначені вікна лишаються в рідному вигляді — і без затемнення, " ..
        "і без відтінку, — і змінюється це одразу, без перезавантаження " ..
        "інтерфейсу. Список зібраний з того, чого темрява справді " ..
        "сягнула, а не з наперед написаних імен: вікно потрапляє сюди при " ..
        "першому своєму відкритті й лишається між сеансами. Вікно, якого " ..
        "в грі більше немає, якийсь час тримає своє місце, а потім іде зі " ..
        "списку — але ваш вибір для нього зберігається: повернувшись, " ..
        "вікно повернеться саме таким, яким ви його лишили. Групи вище — " ..
        "той самий вимикач, тільки грубіший: доки позначені «Інші вікна», " ..
        "вони й так тримають усі ці вікна в рідному вигляді, і список " ..
        "тому згашено.",
    ["%d more windows are not " ..
        "shown. Type in the box above to narrow the list."] =
        "Ще %d вікон не показано. Наберіть щось у полі вище, щоб звузити " ..
        "список.",

    -- Группы затемнения (Modules/Darkness.lua: GROUPS).
    ["Action Bar Art"] = "Оздоблення панелей дій",
    ["Other Windows"] = "Інші вікна",
    ["Other Addons' Windows"] = "Вікна чужих аддонів",
    ["Minimap"] = "Мапа",
    ["Buffs and Debuffs"] = "Підсилення та послаблення",
    ["Bags and Micro Menu"] = "Сумки та меню",
    ["Chat"] = "Чат",
    ["Objective Tracker"] = "Список завдань",
    ["Tooltips"] = "Підказки",
    ["Character Sheet"] = "Вікно персонажа",
    ["Quest and Dialog Text"] = "Завдання й розмови",

    -- Подпись значения «как в игре» на ползунках, где ноль означает
    -- не число, а «не трогать» (Modules/Fonts.lua, Modules/CastBar.lua,
    -- Modules/ActionBars.lua).
    ["Game's Own"] = "Як у грі",

    -- Вкладки страницы шрифтов и строка «что действует сейчас» на каждой
    -- из них (Modules/Fonts.lua).
    ["Global"] = "Глобально",
    ["In effect now - font: %s, size: %s, outline: %s."] =
        "Зараз діє — шрифт: %s, розмір: %s, контур: %s.",
    ["game's own"] = "як у грі",
    ["set on this tab"] = "задано на цій вкладці",
    ["from the Global tab"] = "з вкладки «Глобально»",
    ["Movement of the Numbers"] = "Рух цифр",

    -- Подсистема шрифтов (Modules/Fonts.lua).
    ["Fonts"] = "Шрифти",
    ["Unit Names"] = "Імена юнітів",
    ["Bar Values"] = "Значення на смужках",
    ["Hotkeys and Counts"] = "Гарячі клавіші та лічильники",
    ["Floating Combat Text"] = "Бойовий текст, що спливає",
    ["Addon Window Text"] = "Текст вікон аддона",
    ["No Outline"] = "Без контуру",
    ["Thin Outline"] = "Тонкий контур",
    ["Thick Outline"] = "Товстий контур",
    ["Outline Without Antialiasing"] = "Контур без згладжування",
    ["Note: a font without glyphs for your client language shows text "
        .. "as empty boxes. LibSharedMedia cannot check glyphs, so such a "
        .. "font sits in the list next to the rest. If text disappears after "
        .. "you pick one, put the previous font back - no interface reload "
        .. "needed."] =
        "Увага: шрифт без гліфів для мови клієнта показує текст порожніми "
        .. "прямокутниками. Перевіряти гліфи LibSharedMedia не вміє, тож "
        .. "такий шрифт стоїть у списку нарівні з іншими. Якщо після вибору "
        .. "текст зник — поверніть попередній шрифт, перезавантаження "
        .. "інтерфейсу для цього не потрібне.",
    -- Про собственное окно аддона: оно вне области действия настроек
    -- шрифтов (Modules/Fonts.lua, OWN_WINDOW_KEY).
    ["Darken's own settings window stays out of all of this on "
        .. "purpose: it is the tool you are changing the font with, and a "
        .. "window that resizes under your hands while you drag the slider "
        .. "is hard to steer and hard to get back. Everything else follows "
        .. "what you set here - the game's interface, and the windows "
        .. "Darken puts in its place, the bags window and the nameplates "
        .. "among them."] =
        "Власне вікно налаштувань Darken з усього цього свідомо "
        .. "вилучено: це інструмент, яким ви зараз міняєте шрифт і розмір, "
        .. "а вікно, що перебудовується під руками, поки ви тягнете "
        .. "повзунок, некероване — і повернути його нічим. Усе інше "
        .. "підкоряється заданому тут: інтерфейс гри та вікна, які аддон "
        .. "ставить замість нього, зокрема вікно торб і неймплейти.",
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
        "Це про вікна, які Darken малює замість вікон гри: вікно торб, "
        .. "базу предметів і всі наступні. Вікно налаштувань, у якому ви це "
        .. "читаєте, сюди не належить: воно інструмент, а не предмет "
        .. "налаштування, і вікно, що перебудовується, поки його "
        .. "налаштовують, некероване. Вікно модуля бере звідси шрифт тоді, "
        .. "коли модуль питає його в ядра, тож давно не оновлюваний модуль "
        .. "може лишитися на шрифті гри.",
    ["Leave Global Fonts Alone"] = "Не чіпати глобальні шрифти",
    ["Replacing the standard font objects of the game changes text "
        .. "across the whole interface, the windows of other addons included. "
        .. "Checking this restores the game's own fonts at once, without an "
        .. "interface reload. Per-category overrides are not affected: they "
        .. "keep working."] =
        "Підміна стандартних шрифтових об’єктів гри змінює текст у всьому "
        .. "інтерфейсі, включно з вікнами інших аддонів. Позначка повертає "
        .. "рідні шрифти гри одразу, без перезавантаження інтерфейсу. "
        .. "Точкових налаштувань за категоріями позначка не стосується: вони "
        .. "й далі діють.",
    ["Interface Font"] = "Шрифт інтерфейсу",
    ["The font applied to the whole interface at once: windows, "
        .. "tooltips, the quest log, system messages. The list comes from "
        .. "LibSharedMedia, so it holds both the game's own fonts and "
        .. "everything other addons brought along."] =
        "Шрифт, застосований до всього інтерфейсу одразу: вікна, підказки, "
        .. "журнал завдань, системні повідомлення. Список береться з "
        .. "LibSharedMedia, тож у ньому і рідні шрифти гри, і все, що "
        .. "принесли інші аддони.",
    ["Game's Own Font"] = "Рідний шрифт гри",
    ["Outline"] = "Контур",
    ["The stroke around letters. \"Game's Own Outline\" leaves every "
        .. "element the outline it started with."] =
        "Обведення літер. «Рідний контур» лишає кожному елементу той "
        .. "контур, який був у нього спочатку.",
    ["Game's Own Outline"] = "Рідний контур",
    ["Back to the Game's Own Fonts"] = "Повернути шрифти як у грі",
    ["Puts every font setting back the way a fresh install has it: the "
        .. "font, size and outline here, every tab's own override, and the "
        .. "switch above. Nothing but the fonts is touched, and the game's "
        .. "own text comes back at once, without an interface reload."] =
        "Повертає всі налаштування шрифтів до того вигляду, який вони "
        .. "мають на свіжому встановленні: шрифт, розмір і контур тут, "
        .. "власні значення всіх вкладок і перемикач вище. Крім шрифтів не "
        .. "чіпається нічого, а рідний текст гри повертається одразу, без "
        .. "перезавантаження інтерфейсу.",
    ["Font"] = "Шрифт",
    ["\"Same as Global\" means the category takes its font from the "
        .. "setting above and follows its changes from then on."] =
        "«Як глобальний» — категорія бере шрифт із налаштування вище й "
        .. "далі стежить за його змінами.",
    ["Same as Global"] = "Як глобальний",
    ["Size"] = "Розмір",
    ["\"Same as Global\" means the outline is taken from the level "
        .. "above."] =
        "«Як глобальний» — контур береться з рівня вище.",
    ["Note: the numbers floating over units are drawn by the world text "
        .. "engine, which reads the font file once, at login. A new font "
        .. "therefore shows up only after a full logout to character "
        .. "select - an interface reload is not enough. Size, outline, "
        .. "gravity and duration apply at once."] =
        "Увага: цифри, що спливають над юнітами, малює движок тривимірного "
        .. "тексту, а він читає файл шрифта один раз — під час входу у "
        .. "світ. Тому новий шрифт видно лише після повного виходу до "
        .. "вибору персонажа: перезавантаження інтерфейсу для цього "
        .. "замало. Розмір, контур, гравітація і тривалість змінюються "
        .. "одразу.",
    ["Gravity"] = "Гравітація",
    ["How fast the numbers fall after they pop up. Zero leaves the game "
        .. "its own pull, and the game's own value is 0.5: bigger numbers "
        .. "drop faster, smaller ones let the numbers hang. Takes effect "
        .. "at once, without a reload."] =
        "Як швидко цифри падають після появи. Нуль — лишити грі її власне "
        .. "притягання; рідне значення гри — 0,5. Більше значення — швидше "
        .. "падіння, менше — цифри зависають. Змінюється одразу, без "
        .. "перезавантаження.",
    ["Duration"] = "Тривалість",
    ["How long the numbers stay on screen. Zero leaves the game its own "
        .. "timing, and the game's own value is 1.0. Takes effect at once, "
        .. "without a reload."] =
        "Скільки цифри тримаються на екрані. Нуль — лишити грі її власний "
        .. "час; рідне значення гри — 1,0. Змінюється одразу, без "
        .. "перезавантаження.",

    -- Юнитфреймы (Modules/UnitFrames.lua). Ключ «Unit Frames» общий с
    -- группой исключений подсистемы темноты: подпись там и там одна.
    ["Unit Frames"] = "Юнітфрейми",

    -- Вкладки страницы юнитфреймов. Делят её не по нашим заголовкам, а по
    -- тому, за чем игрок пришёл: как выглядит полоска, что написано на
    -- фрейме, какого он размера. Ключ «Size» общий с другими разделами.
    ["Health and Power"] = "Здоров’я та ресурс",
    ["Name and Bar Text"] = "Ім’я та написи",
    ["Game's Own Texture"] = "Рідна текстура гри",
    ["Game's Own Bar Color"] = "Рідний колір смужки",
    ["By Class"] = "За класом",
    ["By Reaction"] = "За ставленням до гравця",
    ["By Power Type"] = "За видом ресурсу",
    ["Custom Color"] = "Власний колір",

    ["Health Bar"] = "Смужка здоров’я",
    ["Health Bar Texture"] = "Текстура смужки здоров’я",
    ["Health Bar Color"] = "Колір смужки здоров’я",
    ["The color the texture is tinted by. \"By Class\" applies to "
        .. "players only: creatures have no class, so their bar is colored "
        .. "by reaction to you. The first entry leaves the color to the "
        .. "game, and switching back to it restores the native color at "
        .. "once."] =
        "Колір, яким тонується текстура. «За класом» діє лише на гравців: "
        .. "у створінь класу немає, тож їхня смужка фарбується за ставленням "
        .. "до вас. Перший рядок лишає колір грі, і повернення до нього "
        .. "повертає рідний колір одразу.",
    ["Custom Health Bar Color"] = "Власний колір смужки здоров’я",

    ["Power Bar"] = "Смужка ресурсу",
    ["Power Bar Texture"] = "Текстура смужки ресурсу",
    ["Mana, rage, energy. The texture is tinted by the bar color just "
        .. "as on the health bar. The first entry is the game's own texture, "
        .. "and going back to it restores the native look at once."] =
        "Мана, лють, енергія. Текстура тонується кольором смужки так само, "
        .. "як на смужці здоров’я. Перший рядок списку — рідна текстура гри, "
        .. "і повернення до неї повертає рідний вигляд одразу.",
    ["Power Bar Color"] = "Колір смужки ресурсу",
    ["\"By Power Type\" takes the color from the game itself: mana "
        .. "blue, rage red, energy yellow, and so on for whatever this "
        .. "client has. The first entry leaves the color to the game, and "
        .. "switching back to it restores the native color at once."] =
        "«За видом ресурсу» бере колір у самої гри: мана синя, лють "
        .. "червона, енергія жовта — і так для всього, що є в цьому клієнті. "
        .. "Перший рядок лишає колір грі, і повернення до нього повертає "
        .. "рідний колір одразу.",
    ["Custom Power Bar Color"] = "Власний колір смужки ресурсу",
    ["Used in \"Custom Color\" mode, and also when the game has no "
        .. "color for this kind of power."] =
        "Використовується в режимі «Власний колір», а також коли в гри немає "
        .. "кольору для цього виду ресурсу.",

    ["Unit Name"] = "Ім’я юніта",
    ["Name Color"] = "Колір імені",
    ["Game's Own Name Color"] = "Рідний колір імені",
    ["\"Game's Own Name Color\" leaves the name to the game; switching "
        .. "back to it restores the native color at once. \"By Class\" "
        .. "applies to players only: creatures have no class, so their name "
        .. "is colored by reaction to you. When that is unknown too, the "
        .. "color chosen below is used."] =
        "«Рідний колір імені» — ім’я фарбує сама гра, аддон його не чіпає; "
        .. "повернення до цього режиму повертає рідний колір одразу. «За "
        .. "класом» діє лише на гравців: у створінь класу немає, і для них "
        .. "колір береться за ставленням до вас. Якщо невідоме й воно — "
        .. "береться вибраний нижче колір.",
    ["Custom Name Color"] = "Власний колір імені",
    ["Used in \"Custom Color\" mode, and also when neither the class "
        .. "nor the reaction of a unit is known."] =
        "Використовується в режимі «Власний колір», а також коли ні клас, "
        .. "ні ставлення юніта невідомі.",

    ["Frame Scale"] = "Масштаб фреймів",
    ["One is the native size. Scale is a protected operation: a change "
        .. "made in combat is queued and applied as soon as combat ends. "
        .. "Textures and colors are not protected and apply immediately, "
        .. "in combat as well."] =
        "Одиниця — рідний розмір. Масштаб — захищена движком операція: "
        .. "зміна, зроблена в бою, відкладається й застосовується одразу "
        .. "після виходу з бою. Текстури й кольори захищеними не є та "
        .. "застосовуються негайно, зокрема в бою.",

    ["Scale multiplies everything at once: the bars, the portrait, the "
        .. "artwork and the text. There is no width or height here on "
        .. "purpose - the player, target and pet frames are drawn from "
        .. "artwork pinned to the frame at fixed offsets, so a width would "
        .. "change the click area and move nothing you can see. Group and "
        .. "raid frames are built from numbers instead, and there size is "
        .. "real: they have a tab of their own."] =
        "Масштаб множить усе разом: смужки, портрет, мальовану оправу й "
        .. "текст. Ширини та висоти тут немає навмисно: фрейми гравця, цілі "
        .. "й улюбленця складені з малюнків, прибитих до фрейма з "
        .. "піксельними відступами, і ширина змінила б лише область "
        .. "клацання, не зрушивши нічого видимого. Фрейми групи та рейду "
        .. "складені з чисел, і там розмір справжній: у них своя вкладка.",

    -- Фреймы группы и рейда (Modules/UnitFrames.lua).
    ["Group and Raid Frames"] = "Фрейми групи та рейду",
    ["Set the Group Frame Size Myself"] = "Задати розмір фреймів групи самому",
    ["Off leaves the size of a group member to the game, which is where a "
        .. "fresh install starts. On hands the two numbers below to the "
        .. "game's own layout, so they survive the group changing: a member "
        .. "joining or leaving re-lays the list out, and the game reads the "
        .. "size from the same place we wrote it. Size changes the box and "
        .. "leaves the text alone; scale multiplies both. They compose - a "
        .. "frame 120 wide at scale 1.5 takes 180 on screen."] =
        "Вимкнено — розмір учасника групи лишається за грою, і саме з цього "
        .. "починається свіже встановлення. Увімкнено — два числа нижче "
        .. "йдуть у власну розкладку гри й переживають зміну складу: прихід "
        .. "чи вихід учасника перекладає список наново, а розмір гра бере "
        .. "звідти ж, куди його поклали ми. Розмір змінює коробку й не "
        .. "чіпає текст, масштаб множить і те, і те. Складаються вони "
        .. "множенням: фрейм завширшки 120 при масштабі 1.5 займає на "
        .. "екрані 180.",
    ["Group Frame Width"] = "Ширина фрейма групи",
    ["How wide one group member is. Sizing a group frame is a protected "
        .. "operation: a change made in combat is queued and applied as soon "
        .. "as combat ends. Clients without compact group frames are left "
        .. "alone: the setting then quietly does nothing rather than "
        .. "erroring."] =
        "Якої ширини один учасник групи. Розмір фрейма групи — захищена "
        .. "движком операція: зміна, зроблена в бою, відкладається й "
        .. "застосовується одразу після виходу з бою. Клієнт без компактних "
        .. "фреймів групи лишається неторканим: налаштування тоді мовчки "
        .. "нічого не робить, а не падає з помилкою.",
    ["Group Frame Height"] = "Висота фрейма групи",
    ["How tall one group member is. Queued in combat just like the width, "
        .. "and applied as soon as combat ends."] =
        "Якої висоти один учасник групи. У бою відкладається так само, як "
        .. "ширина, і застосовується одразу після виходу з бою.",
    ["Group Frame Scale"] = "Масштаб фреймів групи",
    ["One is the native size. Scale multiplies the whole group frame, text "
        .. "and all, on top of the width and height above. It is a protected "
        .. "operation too, so a change made in combat applies as soon as "
        .. "combat ends."] =
        "Одиниця — рідний розмір. Масштаб множить увесь фрейм групи разом з "
        .. "текстом, поверх ширини та висоти вище. Операція теж захищена: "
        .. "зміна, зроблена в бою, застосовується одразу після виходу з бою.",

    -- Розвідка затемнення (/dark probe).
    ["\"%s\" is switched off right now, so /dark %s does nothing. Its "
        .. "section in the settings window says why and offers to try "
        .. "again."] =
        "«%s» зараз вимкнена, тому /dark %s нічого не робить. Її розділ у "
        .. "вікні налаштувань каже чому і пропонує повторити.",
    ["the dimming subsystem is not loaded"] =
        "підсистему затемнення не завантажено",
    ["the window opened last"] = "останнє відкрите вікно",
    ["open the window first, then type /dark probe - or name the frame: "
        .. "/dark probe <frame name>"] =
        "спершу відкрийте вікно, потім наберіть /dark probe - або назвіть "
        .. "фрейм: /dark probe <імʼя фрейма>",
    ["there is no frame named '%s'"] = "фрейма з імʼям «%s» немає",
    ["dimming probe of %s:"] = "розвідка затемнення, %s:",
    ["log out - the whole list will land in Darken.lua "
        .. "(SavedVariables), under DarkenDB.global.darkprobe"] =
        "вийдіть з гри - увесь список ляже в Darken.lua "
        .. "(SavedVariables), у DarkenDB.global.darkprobe",

    ["The color this area is painted with. It is a multiply, like dimming "
        .. "is: white changes nothing, a darker color darkens, and a "
        .. "colored one tints. The same things dimming leaves alone are "
        .. "left alone here."] =
        "Колір, яким фарбується ця область. Це множення, як і затемнення: "
        .. "білий не змінює нічого, темний затемнює, кольоровий фарбує. "
        .. "Усе, чого не чіпає затемнення, не чіпається й тут.",
    ["Custom Color"] = "Свій колір",
    ["Class Color"] = "Колір класу",

    -- Кнопка на мінікарті (Modules/Launcher.lua).
    ["Minimap Button"] = "Кнопка на мінікарті",
    ["Button on the Minimap"] = "Кнопка на мінікарті",
    ["A button at the edge of the minimap that opens this window. Drag it "
        .. "around the minimap to move it; its place is remembered for the "
        .. "whole account, not per profile. The other two doors stay where "
        .. "they were: the /dark command and the addon's page in the game's "
        .. "own interface options."] =
        "Кнопка скраю мінікарти, що відкриває це вікно. Її можна тягати по "
        .. "колу мінікарти; місце запам'ятовується на весь обліковий "
        .. "запис, а не на профіль. Дві інші двері лишилися де були: "
        .. "команда /dark і сторінка аддона в налаштуваннях самої гри.",
    ["Click to open the settings or close them, drag to move this button "
        .. "around the minimap."] =
        "Клац відкриває налаштування і закриває їх, перетягування рухає "
        .. "кнопку краєм мінікарти.",

    -- Рамки значків (Modules/Icons.lua).
    ["Icon Borders"] = "Рамки значків",
    ["Frame the Icons"] = "Обвести значки аур і кнопок",
    ["Draws a one pixel line around every action button and every buff and "
        .. "debuff icon, in the same color the addon draws all of its own "
        .. "lines. Dimming multiplies the color of what the game has "
        .. "already drawn; a line that is not there it cannot draw - and "
        .. "the game's own button edge is part of the button's picture, so "
        .. "it goes dark along with it and the row turns into dark patches "
        .. "with no borders. Off by default."] =
        "Малює лінію завтовшки в піксель навколо кожної кнопки панелі та "
        .. "кожного значка аури, тим самим кольором, яким аддон малює всі "
        .. "свої лінії. Затемнення "
        .. "множить колір того, що гра вже намалювала; лінію, якої немає, "
        .. "воно намалювати не може — а рідний кант кнопки намальовано "
        .. "всередині її ж картинки, він темніє разом із нею, і ряд кнопок "
        .. "перетворюється на темні плями без меж. Типово вимкнено.",
    ["Backing Behind the Bars"] = "Підкладка під панелями",
    ["Lays the addon's own panel color behind each action bar, a few pixels "
        .. "wider than the bar itself. It gives the row an edge where the "
        .. "game draws none, the same way the line above gives one to a "
        .. "button. Off by default."] =
        "Кладе під кожну панель команд наш власний колір підкладки, на "
        .. "кілька пікселів ширший за саму панель. Це дає ряду край там, де "
        .. "гра його не малює, — так само, як лінія вище дає край кнопці. "
        .. "Типово вимкнено.",
    ["Round the Minimap Buttons"] = "Заокруглити кнопки на мінікарті",
    ["Square Minimap"] = "Квадратна мінімапа",
    ["Dim the Icons Too"] = "Затемнювати й іконки",
    ["Darkens a spell's picture along with the interface around it, "
        .. "at the same strength. Off by default: the dimming spares "
        .. "icons on purpose, because an icon is how a spell is "
        .. "recognised. The game still colours an icon red out of range "
        .. "or grey when unusable - it is answering you, and it wins."] =
        "Затемнює зображення закляття разом з інтерфейсом навколо, тією "
            .. "ж силою. Типово вимкнено: затемнення щадить іконки "
            .. "навмисно, бо саме іконкою закляття й упізнають. Гра "
            .. "й далі фарбує іконку червоним поза радіусом і сірим, "
            .. "коли застосувати не можна, — це її відповідь вам, і вона головніша.",
    ["Cuts the minimap square instead of round. The ring around it "
        .. "is drawn as a circle and would lie across the corners, so it "
        .. "is taken away with the same tick. Off by default."] =
        "Обрізає мінімапу квадратом замість кола. Кільце навколо неї "
            .. "намальоване колом і лягло б упоперек кутів, тому "
            .. "знімається тією ж позначкою. Типово вимкнено.",
    ["Cuts the square buttons other addons put around the minimap into "
        .. "circles and gives each the same line the icons above get. Only "
        .. "other addons' buttons: the game's own are round already, and "
        .. "the few that are not are drawn that way on purpose. Off by "
        .. "default."] =
        "Обрізає в коло квадратні кнопки, які чужі аддони ставлять навколо "
        .. "мінікарти, і обводить кожну тією самою лінією, що й значки "
        .. "вище. Лише чужі кнопки: свої у гри й так круглі, а ті нечисленні, "
        .. "що не круглі, намальовані так навмисно. Типово вимкнено.",
    ["Trim the Icon Edges"] = "Обрізати кант значків",
    ["Cuts the game's own dark edge off each spell icon, the way a modern "
        .. "interface does. Nothing is removed: the picture is shown "
        .. "without its outermost border, and switching this off puts back "
        .. "exactly the coordinates the icon had. Best with the line above, "
        .. "which then becomes the button's edge."] =
        "Зрізає рідний темний кант з кожного значка закляття — так, як це "
        .. "робить сучасний інтерфейс. Нічого не видаляється: картинка "
        .. "показується без самого краю, а вимкнення повертає рівно ті "
        .. "координати, які у значка були. Найкраще разом із лінією вище: "
        .. "вона і стає краєм кнопки.",

    -- Знебарвлення та грифони (Modules/Darkness.lua).
    ["Grey Out the Artwork"] = "Знебарвити оформлення",
    ["Takes the color out of the interface's own artwork instead of only "
        .. "darkening it: the brown of the frames, the gold of the trim, "
        .. "the blue of the bag border all become grey. Dimming still "
        .. "applies on top, and everything dimming leaves alone is left "
        .. "alone here too - spell icons, portraits, the map and all text "
        .. "keep their own color. Off by default: how dark and what color "
        .. "are two questions, and a fresh install answers only the first."] =
        "Прибирає колір з оформлення інтерфейсу, а не лише затемнює його: "
        .. "бурий колір рамок, золото окантовки, синява обводки сумок "
        .. "стають сірими. Затемнення при цьому діє поверх, і все, чого "
        .. "воно не чіпає, не чіпається й тут: значки заклять, портрети, "
        .. "карта й будь-який текст лишаються свого кольору. Типово "
        .. "вимкнено: «наскільки темно» і «якого кольору» — два різні "
        .. "питання, і свіже встановлення відповідає лише на перше.",
    ["Level Out the Bright Artwork"] = "Вирівнювати яскраву графіку",
    ["On by default. Dimming multiplies, and multiplying keeps "
        .. "ratios: artwork the game drew nearly white - the gryphons, the "
        .. "main bar panel, the parchment of a dialog - stays twice as "
        .. "bright as the half-tones around it at every position of the "
        .. "slider, and those pieces glow while the rest of the interface "
        .. "is dark. With this on, anything brighter than a half-tone is "
        .. "brought down to one before the dimming is applied, so it lands "
        .. "where its neighbours land. Hue is kept: a colored texture gets "
        .. "darker, not different."] =
        "Типово увімкнено. Затемнення — це множення, а множення зберігає "
        .. "співвідношення: графіка, намальована грою майже білою — "
        .. "грифони, сама головна панель, пергамент вікна розмови, — за "
        .. "будь-якого положення повзунка лишається вдвічі світлішою за "
        .. "півтони навколо, і ці шматки світяться, доки решта інтерфейсу "
        .. "темна. З цією галочкою все, що світліше за півтон, зводиться "
        .. "до півтону перед затемненням і приходить туди ж, куди "
        .. "приходять сусіди. Відтінок зберігається: кольорова текстура "
        .. "стає темнішою, а не іншою.",
    ["what the cursor points at"] = "те, на що показує курсор",
    ["point the cursor at it first, then type /dark probe mouse"] =
        "наведи на це курсор і набери /dark probe mouse",
    ["Show the Gryphons"] = "Показувати грифонів",
    ["The two beasts at the ends of the main action bar. They are the "
        .. "loudest piece of artwork the game draws, and a dark interface "
        .. "with them still in place looks like two different interfaces at "
        .. "once. On by default - taking away part of the game is the "
        .. "player's call, not ours. On a client with Edit Mode the bar "
        .. "belongs to it in combat, so a change made mid-fight applies as "
        .. "soon as the fight ends."] =
        "Дві тварюки по краях головної панелі команд. Це найгучніша "
        .. "картинка з усього, що малює гра, і темний інтерфейс із ними на "
        .. "місці виглядає як два інтерфейси заразом. Типово показані: "
        .. "прибирати частину гри — рішення гравця, а не наше. На клієнті з "
        .. "Edit Mode панель у бою належить йому, тому зміна, зроблена в "
        .. "бою, застосовується одразу після виходу з бою.",

    -- Захищені вікна гри (Modules/Darkness.lua).
    ["Dim the Windows the Engine Protects"] =
        "Затемнювати вікна, які захищає рушій",
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
        "Типово увімкнено: частину вікон гри — вікно талантів серед них — "
        .. "рушій тримає під наглядом, і лишити їх осторонь означає одне "
        .. "світле вікно посеред темного інтерфейсу. Ціну знати варто. Усе, "
        .. "що аддон на такому вікні змінив, рушій відтоді вважає зміненим "
        .. "аддоном, і власний код вікна виконується поміченим; видно це не "
        .. "тоді, коли ви тягнете повзунок, а пізніше — рядком \"Interface "
        .. "action failed because of an AddOn\" тієї миті, коли ви "
        .. "натискаєте \"застосувати\" в талантах. Якщо так сталося — "
        .. "зніміть цю галочку і перезавантажте інтерфейс. Кнопки не "
        .. "чіпаються в будь-якому разі: клац по них і є захищена дія, і "
        .. "ціна там справжня.",

    -- Підписи вмістилищ і вкладок колонки (Config/Options.lua,
    -- ns.TAB_GROUPS). Їх ставить ядро: це рішення про МІСЦЕ розділу, а не
    -- про його вміст, і частина аддона, чий розділ ліг вкладкою, своєї
    -- підписи тут не дає.
    ["Gear"] = "Снаряження",
    ["Look"] = "Вигляд",
    ["Rules"] = "Правила",
    ["Item Level"] = "Рівень предметів",
    ["Durability"] = "Міцність",

    -- Неймплейты (Modules/NamePlates.lua). Подписи настроек общие с
    -- юнитфреймами: одно и то же на экране обязано называться одинаково.
    -- Ключ «Nameplates» общий со списком исключений темноты.
    ["Nameplates"] = "Неймплейти",
    ["The addon's look on the game's own nameplates: bar texture, bar "
        .. "color, name color, font and dimming. This is not a nameplate "
        .. "engine - placement, auras and threat thresholds stay with the "
        .. "game. If a real nameplate addon is loaded, this section "
        .. "disappears and Darken does not touch nameplates at all."] =
        "Авторський вигляд на стандартних неймплейтах гри: текстура смужки, "
        .. "її колір, колір імені, шрифт і затемнення. Це не движок "
        .. "неймплейтів — розстановка, аури та пороги загрози лишаються за "
        .. "грою. Якщо стоїть справжній аддон неймплейтів, цей розділ "
        .. "зникає, і Darken не чіпає неймплейти взагалі.",
    ["Font and dimming for nameplates are set elsewhere and on purpose: "
        .. "the name uses the \"Unit Names\" font category, and dimming "
        .. "follows the Interface Darkness slider, where \"Nameplates\" can be "
        .. "excluded like any other group."] =
        "Шрифт і затемнення неймплейтів налаштовуються не тут, і це зроблено "
        .. "свідомо: ім’я бере шрифт категорії «Імена юнітів», а затемнення "
        .. "йде за слайдером темряви, де «Неймплейти» виключаються так само, "
        .. "як будь-яка інша група.",
    ["Nameplates are handled by \"%s\", so Darken leaves them alone: two "
        .. "addons painting one bar give flicker and errors. The nameplate "
        .. "section is hidden."] =
        "Неймплейтами опікується «%s», тому Darken їх не чіпає: два аддони "
        .. "на одній смужці дають блимання та помилки. Розділ неймплейтів "
        .. "приховано.",

    -- Полоса применения (Modules/CastBar.lua). Три раздела — игрока, цели и
    -- фокуса — устроены одинаково, поэтому подписи настроек общие на все три.
    ["Player Cast Bar"] = "Смуга гравця",
    ["Target Cast Bar"] = "Смуга цілі",
    ["Focus Cast Bar"] = "Смуга фокуса",
    ["Game's Own Cast Text"] = "Рідний підпис гри",
    ["Spell Name"] = "Назва закляття",
    ["Time Left"] = "Час, що лишився",
    ["Spell Name and Time Left"] = "Назва та час, що лишився",
    ["Game's Own Cast Color"] = "Рідний колір гри",
    ["Custom Cast Colors"] = "Власні кольори",

    -- Тексты на полосках (Modules/Texts.lua).
    ["Bar Text"] = "Тексти на смужках",
    ["Health Bar Value"] = "Значення на смужці здоров’я",
    ["What the health bar says. The first entry leaves the text to the "
        .. "game, including the game's own setting for whether to show it "
        .. "at all. Any other choice shows the text even when the game "
        .. "would hide it - that is what choosing a format means."] =
        "Що написано на смужці здоров’я. Перший рядок лишає підпис грі — "
        .. "разом із її власним налаштуванням, чи показувати значення "
        .. "взагалі. Будь-який інший вибір показує напис навіть там, де гра "
        .. "сховала б його: вибір формату означає саме це.",
    ["Power Bar Value"] = "Значення на смужці ресурсу",
    ["Mana, rage, energy. The first entry leaves the text to the game."] =
        "Мана, лють, енергія. Перший рядок лишає підпис грі.",
    ["Shorten Large Numbers"] = "Скорочувати великі числа",
    ["Writes 12400 as 12.4k and 2500000 as 2.5m. Off by default, "
        .. "because the game writes numbers in full."] =
        "Пише 12400 як 12.4k, а 2500000 як 2.5m. Типово вимкнено: гра пише "
        .. "числа повністю.",
    ["Value Position"] = "Положення значення",
    ["Where the value sits on the bar. Moving text on a unit frame is a "
        .. "protected operation: a change made in combat is applied as soon "
        .. "as combat ends. The format itself is not protected and applies "
        .. "immediately, in combat as well."] =
        "Де стоїть значення на смужці. Переміщення напису на юнітфреймі — "
        .. "захищена движком операція: зміна, зроблена в бою, "
        .. "застосовується одразу після виходу з бою. Сам формат захищеним "
        .. "не є та застосовується негайно, зокрема в бою.",
    ["Game's Own Bar Text"] = "Рідне значення гри",
    ["Number"] = "Число",
    ["Percent"] = "Відсоток",
    ["Number and Percent"] = "Число та відсоток",
    ["Game's Own Position"] = "Рідне положення гри",
    ["Left Edge"] = "Біля лівого краю",
    ["Center"] = "По центру",
    ["Right Edge"] = "Біля правого краю",

    -- Показательный раздел (Config/Demo.lua). Уходит вместе с файлом при
    -- выпуске; переводы уходят той же правкой.
    ["This setting does nothing: the section exists to check appearance."] =
        "Налаштування нічого не робить: розділ існує для перевірки "
        .. "зовнішнього вигляду.",
    ["Disabled twin of the control above: this is what the disabled state "
        .. "looks like."] =
        "Вимкнений двійник елемента вище: так виглядає стан заборони.",
    -- Панели действий (Modules/ActionBars.lua).
    -- Заголовки внутри раздела панели действий.
    -- Написи на кнопці панелі (Modules/ActionBars.lua).
    -- Кнопка «посунути» в розділі модуля (Config/Options.lua).


    -- Подписи мувера, приходящие переменной: имена элементов, названия
    -- выключателей режима и слова их состояний.
    ["On"] = "Увімк.",
    ["Off"] = "Вимк.",

    -- Подписи панелей и видов кнопок, приходящие переменной.
    ["Main Action Bar"] = "Головна панель дій",
    ["Bottom Left Bar"] = "Нижня ліва панель",
    ["Bottom Right Bar"] = "Нижня права панель",
    ["Right Bar"] = "Права панель",
    ["Second Right Bar"] = "Друга права панель",
    ["Pet Bar"] = "Панель улюбленця",
    ["Stance Bar"] = "Панель стійок",
    ["Game's Own Button Look"] = "Рідний вигляд кнопок гри",
    ["Dark Buttons"] = "Темні кнопки",
    -- Сітка комірок стандартних сумок (Modules/Bags.lua). Підпис розділу
    -- лишився: він приїжджає блоком на сторінку затемнення.
    ["Game Bags"] = "Сумки гри",
    ["Bag Slot Borders"] = "Обвідка комірок сумки",
    ["Draws a one pixel border around every slot "
        .. "in the game's own bag windows, so that the grid reads "
        .. "as a grid. This is the one thing dimming cannot do for "
        .. "the bags by itself: dimming multiplies the artwork that "
        .. "is already there, and a line that is not there cannot "
        .. "be multiplied. Off to start with, and switching it off "
        .. "takes the line away at once, with no interface reload."] =
        "Малює рамку в один піксель навколо кожної комірки в рідних вікнах "
        .. "сумок гри, щоб сітка читалася сіткою. Це єдине, чого затемнення "
        .. "для сумок зробити не може: затемнення множить колір уже "
        .. "намальованої картинки, а лінію, якої немає, множити ні на що. "
        .. "Спочатку вимкнена; вимкнення прибирає лінію одразу, без "
        .. "перезавантаження інтерфейсу.",
    -- Публічний шар модулів (Core/Api.lua, Core/Registry.lua). Ці рядки
    -- бачить гравець, який поставив чужий модуль: вони мусять пояснити, що
    -- сталося і що робити, не називаючи ні файлів, ні функцій.
    ["Darken rejected a module: %s"] =
        "Darken відхилив модуль: %s",
    ["a module must be given as a table"] =
        "модуль має передаватися таблицею",
    ["a module needs a name made of Latin letters, "
        .. "digits and underscores and starting with a letter"] =
        "ім'я модуля має складатися з латинських літер, цифр і підкреслень "
        .. "та починатися з літери",
    ["the name \"%s\" belongs to Darken itself and cannot be a "
        .. "module name; names starting with \"core_\" are reserved for "
        .. "the core too, so name your module after your addon"] =
        "ім'я «%s» належить самому Darken і не може бути іменем модуля; "
        .. "імена, що починаються з «core_», теж закріплені за ядром — "
        .. "називайте модуль за своїм аддоном",
    ["the name \"%s\" is already registered"] =
        "ім'я «%s» вже зареєстроване",
    ["module \"%s\" declares \"%s\" of the wrong type"] =
        "модуль «%s» оголосив поле «%s» хибного типу",
    ["the options section of module \"%s\" is not a group "
        .. "AceConfig can show"] =
        "розділ налаштувань модуля «%s» не є групою, яку AceConfig вміє "
        .. "показати",
    ["the options section of module \"%s\" was refused by "
        .. "AceConfig: %s"] =
        "розділ налаштувань модуля «%s» відхилено AceConfig: %s",
    ["module \"%s\" does not say which Darken module API version "
        .. "it needs"] =
        "модуль «%s» не повідомив, яка версія API модулів Darken йому "
        .. "потрібна",
    ["module \"%s\" needs Darken module API version %s, and this "
        .. "core provides %s; update Darken"] =
        "модулю «%s» потрібна версія API модулів Darken %s, а це ядро дає "
        .. "%s; оновіть Darken",
    ["module \"%s\" was written for Darken module API version %s, "
        .. "which this core no longer supports (the oldest supported is "
        .. "%s); update the module"] =
        "модуль «%s» написаний під версію API модулів Darken %s, яку це "
        .. "ядро більше не підтримує (найстаріша прийнятна — %s); оновіть "
        .. "модуль",
    ["Module \"%s\" raised an error in %s and is switched off: the core "
        .. "will not call it again. The rest of Darken is unaffected. Its "
        .. "place in the settings window says so and offers to start it up "
        .. "again. Error: %s"] =
        "Модуль «%s» впав з помилкою у %s і вимкнений: ядро більше не "
        .. "викликатиме його. На решті аддона це не позначається. Його місце "
        .. "у вікні налаштувань каже про це й пропонує спробувати ще раз. "
        .. "Помилка: %s",
    ["Module \"%s\" started up again and is working. Its settings are "
        .. "back where they were."] =
        "Модуль «%s» запустився знову й працює. Його налаштування "
        .. "повернулися на попереднє місце.",
    ["Darken did not start on this client, so it cannot take modules"] =
        "Darken не запустився на цьому клієнті й не може приймати модулі",
    -- Відкладене на вихід із бою (Core/Combat.lua). Причину відмови модуль
    -- показує гравцеві своїм рядком у чат, тому вона перекладається так само,
    -- як решта рядків публічного шару.
    ["deferring work needs a non-empty key and a function"] =
        "щоб відкласти роботу, потрібні непорожній ключ і функція",
    ["a module that Darken switched off cannot defer work"] =
        "модуль, вимкнений Darken, не може відкладати роботу",
    ["the options section of module \"%s\" cannot be checked: "
        .. "AceConfigRegistry-3.0 is missing from this installation"] =
        "розділ налаштувань модуля «%s» немає чим перевірити: у встановленому "
        .. "аддоні немає AceConfigRegistry-3.0",
    ["the options section of module \"%s\" uses \"handler\" with "
        .. "string method names; Darken cannot guard that form, so put "
        .. "the function itself in the node instead"] =
        "розділ налаштувань модуля «%s» користується полем handler та "
        .. "іменами методів рядками; Darken не вміє захищати таку форму — "
        .. "покладіть у вузол саму функцію",
    ["the options section of module \"%s\" puts the method name "
        .. "\"%s\" in \"%s\"; Darken cannot guard that form, so put "
        .. "the function itself in the node instead"] =
        "розділ налаштувань модуля «%s» кладе ім'я методу «%s» у поле «%s»; "
        .. "Darken не вміє захищати таку форму — покладіть у вузол саму "
        .. "функцію",
    ["Darken has no settings scope named \"%s\""] =
        "в Darken немає розділу зберігання з іменем «%s»",
    -- Публічний шар: переведення збережених даних модуля (Core/Api.lua).
    ["the data to migrate must be a table"] =
        "дані, які переводять, мають бути таблицею",
    ["the migrations must be given as a table"] =
        "міграції задають таблицею",
    ["the target format version must be a number"] =
        "цільова версія форми даних має бути числом",
    ["the field \"%s\" on an Darken module handle belongs to "
        .. "the core and cannot be assigned"] =
        "поле «%s» описувача модуля Darken належить ядру, і записувати в "
        .. "нього не можна",
    -- Публічний шар: заміна підсистеми ядра модулем (Core/Api.lua).
    ["Darken has no subsystem named \"%s\" that a module may replace"] =
        "в Darken немає підсистеми «%s», яку модуль міг би замінити собою",
    ["Darken's own \"%s\" section is already switched off, so a "
        .. "module cannot stand it down"] =
        "власний розділ «%s» Darken уже вимкнено, і відвести його вбік "
        .. "модуль не може",
    ["One owner per frame: module \"%s\" draws this now, so Darken's own "
        .. "\"%s\" section stands down until that module gives it back."] =
        "В одного фрейма один господар: тепер це малює модуль «%s», тому "
        .. "власний розділ «%s» Darken відступає, доки цей модуль не "
        .. "поверне його назад.",

    -- Повернення відведеної підсистеми (Core/Api.lua).
    ["module \"%s\" is switched off and cannot stand a subsystem of "
        .. "Darken down"] =
        "модуль «%s» вимкнено, і він не може відвести підсистему Darken",
    ["module \"%s\" is switched off; Darken has already given back what "
        .. "it stood down"] =
        "модуль «%s» вимкнено; Darken уже повернув те, що було відведено",
    ["Darken's own \"%s\" section was not stood down by a module, so there "
        .. "is nothing to give back"] =
        "власний розділ «%s» Darken жоден модуль не відводив, і повертати "
        .. "нічого",
    ["Darken's own \"%s\" section was stood down by module \"%s\", and "
        .. "only that module can give it back"] =
        "власний розділ «%s» Darken відвів модуль «%s», і повернути його "
        .. "може лише він",
    ["Darken's own \"%s\" section did not start up again"] =
        "власний розділ «%s» Darken не зміг повернутися до ладу",
    ["Module \"%s\" does not draw this any more, so Darken's own \"%s\" "
        .. "section is back and has been applied."] =
        "Модуль «%s» це більше не малює, тому власний розділ «%s» Darken "
        .. "повернувся до ладу, і його оформлення застосовано.",

    -- Слеш-команди модулів (Core/Command.lua).
    ["a slash command needs a word made of Latin "
        .. "letters and digits and starting with a letter"] =
        "слово слеш-команди має складатися з латинських літер і цифр і "
        .. "починатися з літери",
    ["a slash command needs a function to call"] =
        "слеш-команді потрібна функція, яку вона покличе",
    ["the command \"/%s\" belongs to Darken itself"] =
        "команда «/%s» належить самому Darken",
    ["the command \"/%s\" is already taken by module \"%s\""] =
        "команду «/%s» уже зайняв модуль «%s»",
    ["the command \"/%s\" is already registered by another addon"] =
        "команду «/%s» уже зареєстрував інший аддон",

    -- Відповіді команд /darken в чат (Core/Init.lua).
    ["this client is not supported (flavor: %s, interface: %s). "
        .. "The addon did not start."] =
        "цей клієнт не підтримується (різновид: %s, інтерфейс: %s). Аддон не "
        .. "запущено.",
    ["could not add a page to the game's interface options (%s). "
        .. "The settings open with the /darken command."] =
        "не вдалося додати сторінку до ігрових налаштувань інтерфейсу (%s). "
        .. "Налаштування відкриваються командою /darken.",
    ["this build has no demo section"] =
        "показового розділу в цій збірці немає",
    ["the demo section is on"]  = "показовий розділ увімкнено",
    ["the demo section is off"] = "показовий розділ вимкнено",
    ["usage: /darken scan <part of a frame name>"] =
        "використання: /darken scan <частина імені фрейма>",
    ["or /darken scan all - collect everything into the saved "
        .. "variables file"] =
        "або /darken scan all — зібрати все у файл збережень",
    ["the settings database is not ready yet"] =
        "база налаштувань ще не готова",
    ["collected %d names over %d patterns"] =
        "зібрано %d імен за %d зразками",
    ["%d patterns hit the cap of %d names - their lists are "
        .. "the first %d by name, and scan.cut says how many "
        .. "there really were"] =
        "%d образців уперлося в стелю в %d імен: їхні списки - перші %d за "
            .. "абеткою, а скільки імен було насправді, каже scan.cut",
    ["log out - the result will land in Darken.lua (SavedVariables)"] =
        "вийдіть з гри — результат ляже в Darken.lua (SavedVariables)",
    ["found %d for the pattern '%s':"] = "знайдено %d за зразком «%s»:",
    ["... and %d more - narrow the pattern"] =
        "... і ще %d — уточніть зразок",

    -- Відмови, що йдуть у чат через реєстр (Core/Registry.lua,
    -- Core/Defaults.lua).
    ["this module was switched off"] = "модуль вимкнено",
    ["a module name must be a non-empty string"] =
        "ім'я модуля має бути непорожнім рядком",
    ["the name '%s' is reserved for a housekeeping field of the profile"] =
        "ім'я «%s» зарезервовано під службове поле профілю",
    ["the module name '%s' is taken by a core setting"] =
        "ім'я модуля «%s» зайняте налаштуванням ядра",
    -- Привітання на першому вході (Core/Init.lua).
    ["the interface is dimmed to %d of "
        .. "100 - that is the one thing a fresh install changes. Type "
        .. "/darken for the settings, where the Interface Darkness slider goes back "
        .. "to zero in one drag."] =
        "інтерфейс затемнено на %d зі 100 — це єдине, що змінює свіже "
        .. "встановлення. Налаштування відкриваються командою /darken, а "
        .. "повзунок затемнення повертається до нуля одним рухом.",
    ["type /darken for the settings. Everything the addon "
        .. "changes can be put back from the same place it was changed."] =
        "налаштування відкриваються командою /darken. Усе, що аддон змінює, "
        .. "повертається назад звідти ж, звідки було змінено.",

    -- Звіт про клієнт (Core/Report.lua, команда /darken report).
    ["answered by Darken %s, contract %s, settings %s, at %s by this "
        .. "computer's clock"] =
        "відповіла збірка Darken %s, версія контракту %s, версія "
        .. "налаштувань %s, о %s за годинником цього комп'ютера",
    ["the report stored here until now was made by Darken %s, not by "
        .. "this one - it was out of date. The game reads addon code "
        .. "at login and on /reload, and at no other time."] =
        "звіт, що лежав тут досі, зібрала збірка Darken %s, а не ця: він "
        .. "застарілий. Гра читає код аддона на вході та по /reload, і "
        .. "більше ніколи.",
    ["client %s, build %s, interface %s, UI scale %s, screen %s"] =
        "клієнт %s, збірка %s, інтерфейс %s, масштаб інтерфейсу %s, екран %s",
    ["frame groups: %d confirmed, %d partial, %d empty, %d unconfirmed, "
        .. "%d degraded, %d absent on this client by design"] =
        "груп фреймів: %d підтверджено, %d знайшли частину, %d порожні, "
        .. "%d не перевірити, %d без підписок, "
        .. "%d у цьому клієнті не буває зовсім",
    ["%s did nothing: group \"%s\" resolved to nothing (%d names tried)"] =
        "%s нічого не зробила: група «%s» не знайшла жодного імені "
        .. "(перевірено %d)",
    ["and %d more groups resolved to nothing"] =
        "і ще %d груп не знайшли нічого",
    ["every frame group declared for this client resolved to something"] =
        "кожна оголошена цьому клієнтові група знайшла бодай щось",
    ["%d groups found only part of what they name - see the saved "
        .. "variables"] =
        "%d груп знайшли лише частину названого — дивіться файл збережень",
    ["%d groups could not be judged: the game makes those frames only "
        .. "after you open the window or take a target. Open them and "
        .. "run the report again."] =
        "про %d груп судити немає з чого: ці фрейми гра заводить лише після "
        .. "того, як ви відкриєте вікно або візьмете ціль. Відкрийте їх "
        .. "і повторіть звіт.",
    ["%d hook groups are empty here: those subsystems fall back to a "
        .. "delayed pass, which is slower but not broken"] =
        "%d груп підписок тут порожні: ці підсистеми переходять на "
        .. "відкладений прохід — повільніше, але не зламано",
    ["guessed names needing live confirmation: %d of %d exist here"] =
        "здогадок, що потребують підтвердження живим клієнтом: "
        .. "%d із %d тут є",
    ["%d paths got part way: \"%s\" exists here and \"%s\" does not - "
        .. "the object is right, the last step is not"] =
        "%d шляхів дійшли до середини: «%s» тут є, а «%s» немає — об'єкт "
        .. "вгадано правильно, останній крок ні",
    ["log out and send Darken.lua (SavedVariables) - the full report "
        .. "is in DarkenDB.global.report"] =
        "вийдіть з гри і надішліть Darken.lua (SavedVariables) — повний "
        .. "звіт лежить у DarkenDB.global.report",

    -- Підписи підсистем у звіті про клієнт. Решту взято з уже перекладених
    -- підписів вікна налаштувань: те саме має називатися однаково.
    ["Auras on Unit Frames"]      = "Аури на юнітфреймах",
    ["Bag Windows"]               = "Вікна сумок",
    ["Player Aura Grid"]          = "Сітка аур гравця",
    ["Item Level on Equipment"]   = "Рівень предметів на спорядженні",
    ["Raid Frames"]               = "Рейдові фрейми",
    ["Action Bar Layout"]         = "Розкладка панелей дій",
    ["An Unnamed Group"]          = "Неназвана група",
    -- Лік зробленого (Core/Tally.lua, та сама команда /darken report).
    ["did nothing this session: %s"] =
        "за цей сеанс не зробили нічого: %s",
    ["the game quietly refused: %s"] =
        "гра мовчки відмовила: %s",
    ["the game refused to register these events: %s - whatever waits "
        .. "on them did nothing and could not say why"] =
        "рушій відмовився реєструвати події: %s - усе, що на них чекає, "
            .. "не зробило нічого й не змогло сказати чому",
    ["this session: %s"] =
        "за цей сеанс: %s",
    ["this session the addon did not do a single counted thing"] =
        "за цей сеанс аддон не зробив жодної врахованої речі",
    ["modules: %d in service, %d switched off"] =
        "модулів: %d у строю, %d вимкнено",

    -- Підписи лічильників. Приходять у ns.Localize полем таблиці, як і
    -- підписи підсистем вище.
    ["Objects Dimmed"]             = "Об'єктів затемнено",
    ["Objects Left As Content"]    = "Залишено як вміст",
    ["Repaints Heard"]             = "Перефарбувань почуто",
    ["Bars Retextured"]            = "Смужок перетекстуровано",
    ["Nameplates Attached"]        = "Неймплейтів узято",
    ["Nameplates Taken By The Engine"] = "Неймплейтів узято рушієм",
    ["Auras Ruled On"]             = "Аур відібрано списком",
    ["Positions Applied"]          = "Положень поставлено",
    ["Containers Recorded"]        = "Контейнерів записано",
    ["Game Functions Hooked"]      = "Функцій гри підписано",
    ["Hooks That Ran"]             = "Спрацювань підписок",
    ["Work Deferred In Combat"]    = "Відкладено через бій",
    ["Deferred Work Carried Out"]  = "Відкладеного виконано",
    ["Colours The Engine Refused"] = "Відмов рушія щодо кольору",
    ["Protected Actions Refused"]  = "Відмов захищеному коду",
    ["Font Size Adjustment"] = "Поправка до розміру шрифту",
    ["game's own %+d"] = "як у грі %+d",
    ["Bigger or smaller than the game draws it, by this many points. "
        .. "Zero is the game's own sizes. Every element keeps the size the "
        .. "game gave it and moves by the same step, so a heading stays "
        .. "bigger than a small label - which is exactly what one size for "
        .. "the whole interface used to destroy. A single element that "
        .. "needs an exact size gets it on its own tab, and that number "
        .. "wins over this one."] =
        "Більший або дрібніший, ніж малює гра, — на стільки пунктів. "
        .. "Нуль — рідні розміри гри. Кожен елемент зберігає розмір, який "
        .. "дала йому гра, і зсувається на той самий крок, тому заголовок "
        .. "лишається більшим за дрібний підпис — саме те, що колишній "
        .. "єдиний розмір на весь інтерфейс і нищив. Елементові, якому "
        .. "потрібен точний розмір, він задається на його власній вкладці, "
        .. "і те число сильніше за це.",
    ["Every other tab starts from what you choose here: a tab left "
        .. "on \"Same as Global\" follows this font and this outline, every "
        .. "element moves by the size adjustment below, and a tab that "
        .. "sets its own value wins over it. So one choice here is the "
        .. "short way to one font everywhere, and the tabs are for the "
        .. "elements that need something else."] =
        "Кожна інша вкладка відраховується від вибраного тут: вкладка, "
        .. "лишена на «Як глобально», слідує цьому шрифту й цьому контуру, "
        .. "кожен елемент зсувається на поправку розміру нижче, а вкладка "
        .. "зі своїм значенням сильніша. Тож один вибір тут — короткий "
        .. "шлях до одного шрифту всюди, а вкладки — для тих елементів, "
        .. "яким потрібне інше.",
    ["What you set here wins over the Global tab for this element "
        .. "alone. \"Same as Global\" means the field follows the Global tab "
        .. "instead and keeps following it as you change it there; a size "
        .. "of zero means this element keeps the size the game gave it, "
        .. "moved by the adjustment on the Global tab."] =
        "Задане тут сильніше за глобальну вкладку — але тільки для "
        .. "цього елемента. «Як глобально» означає, що поле слідує "
        .. "глобальній вкладці й далі за її правками; нульовий розмір "
        .. "означає, що елемент зберігає розмір, який дала йому гра, "
        .. "зсунутий на поправку з глобальної вкладки.",
    ["An exact size for this element alone, in points, and it wins "
        .. "over the adjustment on the Global tab. Zero means the element "
        .. "keeps the size the game gave it and follows that adjustment "
        .. "instead."] =
        "Точний розмір для одного цього елемента, у пунктах, і він "
        .. "сильніший за поправку з глобальної вкладки. Нуль означає, що "
        .. "елемент зберігає розмір, який дала йому гра, і слідує тій "
        .. "поправці.",
    ["Overall Strength"] = "Загальна сила",
    ["Game's Own Look"] = "Рідний вигляд гри",
    ["Leave every area on \"Overall Strength\" and the slider alone "
        .. "decides how dark the whole interface is. Give one area a "
        .. "strength of its own and it stops listening to the slider and "
        .. "keeps that strength wherever the slider goes."] =
        "Лишіть усі області на «Загальній силі» — і наскільки темно "
        .. "всьому інтерфейсу, вирішує один повзунок. Задайте області "
        .. "власну силу — і вона перестає слухати повзунок і тримає цю "
        .. "силу, хоч би куди той пішов.",
    ["\"Other Windows\" above means every window not named here, "
        .. "including ones later patches add and ones other addons build "
        .. "in the game's style: darkening finds them by walking the "
        .. "interface, not from a list of names. Single windows out of "
        .. "that sweep are handled one at a time below."] =
        "«Інші вікна» вище означає кожне вікно, не назване тут, — "
        .. "включно з тими, що додадуть майбутні патчі, і тими, що чужі "
        .. "аддони будують у стилі гри: затемнення знаходить їх обходом "
        .. "інтерфейсу, а не за списком імен. Окремі вікна з цього проходу "
        .. "розбираються поштучно нижче.",
    ["How dark this area is. \"Overall Strength\" means the strength "
        .. "slider on this page decides, and one drag of it moves this "
        .. "area along with everything else. Any named strength here wins "
        .. "over the slider and stays put. \"Game's Own Look\" leaves "
        .. "this area exactly as the game draws it - no darkening and no "
        .. "tint."] =
        "Наскільки темна ця область. «Загальна сила» означає, що вирішує "
        .. "повзунок сили на цій самій сторінці, і один його рух веде цю "
        .. "область разом з усім іншим. Будь-яка названа тут сила "
        .. "сильніша за повзунок і лишається на місці. «Рідний вигляд "
        .. "гри» лишає область рівно такою, якою її малює гра, — без "
        .. "затемнення й без відтінку.",
    ["These Settings Are For"] = "Ці налаштування — для",
    ["All Frames"] = "Усіх фреймів",
    ["Party"] = "Групи",
    ["Back to the Shared Settings"] = "Повернути до спільних налаштувань",
    ["\"All Frames\" is the choice every frame follows until you give "
        .. "that frame one of its own. What you set on a single frame wins "
        .. "over it and keeps winning; what you leave as \"Same as All "
        .. "Frames\" follows the shared choice and keeps following it as "
        .. "you change it. Your own frame and the target frame are looked "
        .. "at differently - one out of the corner of the eye, the other "
        .. "in a fight - and one setting for both means choosing what gets "
        .. "in the way least rather than what you want."] =
        "«Усі фрейми» — вибір, якому слідує кожен фрейм, доки ви не "
        .. "задали цьому фреймові власний. Задане на одному фреймі "
        .. "сильніше за спільне й лишається сильнішим; лишене як «Як в "
        .. "усіх фреймів» слідує спільному вибору й далі за його правками. "
        .. "На свій фрейм і на фрейм цілі дивляться по-різному — на один "
        .. "краєм ока, на інший у бою, — і одне налаштування на обидва "
        .. "означає вибір не того, що потрібно, а того, що менше заважає.",
    ["Drops everything set on this frame alone, so it follows the "
        .. "shared choice again - and goes on following it."] =
        "Знімає все, що задано на одному цьому фреймі, і він знову "
        .. "слідує спільному вибору — і слідує далі.",
    ["Individual Frames"] = "Окремі фрейми",
    ["There is no frame to choose on this tab, and that is the whole "
        .. "difference between it and the one beside it: the group grid "
        .. "has no unit of its own, and one size serves every member. "
        .. "Width and height here are real numbers, unlike the player and "
        .. "target frames, which are drawn from artwork and have scale "
        .. "only."] =
        "Обирати фрейм на цій вкладці нема з чого, і в цьому вся різниця "
        .. "між нею та сусідньою: у сітки групи свого юніта немає, і один "
        .. "розмір служить кожному в ній. Ширина з висотою тут — справжні "
        .. "числа, на відміну від фреймів гравця й цілі, які намальовані "
        .. "обв'язкою і мають лише масштаб.",
    ["Accent Color"] = "Колір акценту",
    ["The one color the dark theme uses to say look here: section headings, the tick in a checkbox, the filled part of a slider, the scrollbar, the chosen row and whatever the mouse is over. Everything else - the blacks, the lines, the text - stays as it is. Parts already drawn keep the old color until /reload."] = "Той єдиний колір, яким темна тема каже «поглянь сюди»: заголовки розділів, галочка прапорця, заповнена частина повзунка, смужка гортання, вибраний рядок і те, на що наведено мишу. Решта — чорнота, лінії, текст — лишається як була. Уже намальоване тримає попередній колір до /reload.",
    ["The first entry is the game's own texture: the addon leaves it "
        .. "alone until asked, and going back to it restores exactly the look "
        .. "you had before, at once and without an interface reload. The "
        .. "addon's own textures are a gradient from white to a color. The "
        .. "engine multiplies them by the bar color, so the white end gives "
        .. "the pure color and the pastel end its muted shade. Which color "
        .. "that is, is chosen right below."] =
        "Перший рядок списку — рідна текстура гри: аддон не підмінює її, "
        .. "доки не попросили, і повернення до неї повертає рівно той вигляд, "
        .. "що був до першої підміни, одразу й без перезавантаження "
        .. "інтерфейсу. Авторські текстури — градієнт від білого до кольору. "
        .. "Движок множить їх на колір смужки, тому білий кінець дає чистий "
        .. "колір, а пастельний — його приглушений відтінок. Який це колір, "
        .. "вибирається просто нижче.",

    ["letters %d"] = "літер %d",
    ["font"] = "шрифт",
    ["shown"] = "показана",
    ["color"] = "колір",
    ["layer"] = "шар",
    ["visible"] = "видно",
    ["owner"] = "хазяїн",
    ["room"] = "відведено",
    ["anchors"] = "прив язок",
    ["at"] = "у точці",
    ["opacity"] = "прозорість",
    ["size"] = "розмір",
    ["no explanatory paragraph found in the window"] =
        "у вікні не знайшлося жодного абзацу пояснення",
    ["open the settings window first, then type /dark probe text"] =
        "спершу відкрийте вікно налаштувань, потім наберіть /dark probe text",

    ["this build has no widget demo"] = "у цій збірці показу віджетів немає",
    ["this build has no new settings window"] = "у цій збірці нового вікна налаштувань немає",
    ["new settings window is open"] = "нове вікно налаштувань відкрито",
    ["new settings window is closed"] = "нове вікно налаштувань закрито",
    ["widget demo is open"] = "показ віджетів відкрито",
    ["widget demo is closed"] = "показ віджетів закрито",
    ["A button on the edge of the minimap that opens and closes this window. Drag it around the minimap to move it."] =
        "Кнопка скраю мінімапи, що відкриває й закриває це вікно. Її можна " ..
        "перетягнути вздовж краю мінімапи.",
    ["A correction, not a size: zero means every element keeps the size the game gives it, so a fresh profile changes not a single letter."] =
        "Поправка, а не розмір: нуль означає, що кожен елемент зберігає " ..
        "розмір, який дає йому гра, і свіжий профіль не змінює жодної " ..
        "літери.",
    ["A profile is every setting in this window at once. Which profile a character uses is that character's own choice; the profiles themselves are shared across the account."] =
        "Профіль — це всі налаштування цього вікна разом. Який профіль має " ..
        "персонаж, вирішує він сам; самі профілі спільні на весь обліковий " ..
        "запис.",
    ["A size of its own for this group. Zero follows the global tab and the size adjustment on it."] =
        "Власний розмір для цієї групи. Нуль означає «як на спільній " ..
        "вкладці», з її поправкою розміру.",
    ["A soft shadow behind every icon, so icons read apart from the darkened interface behind them."] =
        "М'яка тінь за кожною піктограмою, щоб піктограми читалися окремо " ..
        "від затемненого інтерфейсу позаду.",
    ["A thin line around every icon, in the addon's own colour."] =
        "Тонка лінія навколо кожної піктограми, кольором аддона.",
    ["Bag Reading"] = "Читання торб",
    ["Bag Sorting"] = "Сортування торб",
    ["Bags"] = "Торби",
    ["Bring the brightest pieces of artwork down to the same ceiling as the rest, so nothing stands out by being lighter than everything around it."] =
        "Опустити найсвітліші шматки оформлення до тієї ж стелі, що й " ..
        "решту, щоб ніщо не вирізнялося самою лише яскравістю.",
    ["Color Picker"] = "Вибір кольору",
    ["Copy Settings From"] = "Скопіювати налаштування з",
    ["Crop Icon Borders"] = "Обрізати окрайку піктограм",
    ["Current Profile"] = "Поточний профіль",
    ["Delete Profile"] = "Видалити профіль",
    ["Do not touch the game's own font objects at all. Everything the addon draws itself still follows the settings here."] =
        "Не чіпати шрифтові об'єкти самої гри взагалі. Усе, що аддон малює " ..
        "сам, і далі слідує цим налаштуванням.",
    ["Drain the colour out of the interface's own artwork as well as darkening it. Icons, bars, portraits and the map keep their colour either way."] =
        "Знебарвити оформлення інтерфейсу на додачу до затемнення. " ..
        "Піктограми, смуги, портрети й мапа зберігають колір у будь-якому " ..
        "разі.",
    ["Draw a thin line around every bag slot. The game draws the slots themselves; this only adds the outline."] =
        "Обвести тонкою лінією кожну комірку торби. Самі комірки малює гра; " ..
        "тут додається лише обведення.",
    ["Edit Mode"] = "Режим правки",
    ["Every other tab starts from what you choose here: a tab left on \"Same as Global\" follows this font and this outline, every element moves by the size adjustment below, and a tab that sets its own value wins over it."] =
        "Кожна інша вкладка відштовхується від обраного тут: вкладка, " ..
        "залишена на «Як спільний», бере цей шрифт і це обведення, кожен " ..
        "елемент зсувається на поправку розміру нижче, а вкладка з власним " ..
        "значенням перебиває спільне.",
    ["Extra Action Button"] = "Додаткова кнопка дії",
    ["Focus"] = "Фокус",
    ["Give the profile you are in that name. Its settings come with it."] =
        "Дати профілю, в якому ви перебуваєте, це ім'я. Його налаштування " ..
        "лишаються при ньому.",
    ["Health Bar Fixed Color"] = "Власний колір смуги здоров'я",
    ["Health Text"] = "Текст здоров'я",
    ["How big the portrait frames are drawn. One is the size the game gives them."] =
        "Наскільки великими малюються портретні фрейми. Одиниця — розмір, " ..
        "який дає їм гра.",
    ["How dark this area is. \"Overall Strength\" means the strength slider on this page decides. Any named strength here wins over the slider and stays put."] =
        "Наскільки темна ця ділянка. «Загальна сила» означає, що вирішує " ..
        "повзунок сили на цій сторінці. Будь-яка названа тут сила перебиває " ..
        "повзунок і лишається як є.",
    ["How much to dim the interface's own artwork: frames, borders, backgrounds and the trim around them. Zero is the game's own look and is one drag away; one hundred is as dark as the addon goes, and that is deliberately not black - a frame you cannot make out is not a dimmed frame, it is a missing one."] =
        "Наскільки затемнювати оформлення інтерфейсу: рамки, обведення, " ..
        "підкладки й окантовку навколо них. Нуль — рідний вигляд гри, і до " ..
        "нього один рух повзунка; сто — найтемніше, на що аддон іде, і це " ..
        "навмисно не чорний: фрейм, якого не розгледіти, — це не затемнений " ..
        "фрейм, а зниклий.",
    ["Icons"] = "Піктограми",
    ["Icons Dimmed"]               = "Іконок затемнено",
    ["Labels Raised"]              = "Написів піднято",
    ["Labels Left Light"]          = "Написів залишено світлими",
    ["Another Addon's, Left Alone"] = "Чужих адонів не зайнято",
    ["Chat Left To Its Owner"] = "Чат залишено його власнику",
    ["Painted By Name"] = "Пофарбовано за іменем",
    ["Given Up To The Game"] = "Віддано грі",
    ["Windows Listened For"] = "Вікон під спостереженням",
    ["point the cursor at it first, then type /dark harvest mouse"] =
        "наведіть курсор, потім введіть /dark harvest mouse",
    ["the window under the cursor is %s"] =
        "під курсором вікно %s",
    ["there is no frame named '%s' in this client"] =
        "у цьому клієнті немає фрейма '%s'",
    ["log out - the whole table will land in Darken.lua (SavedVariables), under DarkenDB.global.harvest"] =
        "вийдіть з гри - уся таблиця ляже в Darken.lua (SavedVariables), у DarkenDB.global.harvest",
    ["%d pictures examined, %d already covered, %d not"] =
        "розглянуто зображень: %d, вже охоплено: %d, ні: %d",
    ["%d more frames are not listed; the whole table is in the saved variables"] =
        "ще %d фреймів не показано; повна таблиця в SavedVariables",
    ["Supported Addons' Windows"] = "Вікна підтриманих адонів",
    ["Icon Edges Trimmed"]         = "Кромок в іконок зрізано",
    ["Minimap Buttons Rounded"]    = "Кнопок мінімапи заокруглено",
    ["Icons Framed"] = "Піктограм обведено",
    ["Leave Vehicle Button"] = "Кнопка виходу з транспорту",
    ["Name and Size"] = "Ім'я та розмір",
    ["Nameplates The Game Showed"] = "Неймплейтів показала гра",
    ["Names This Client Does Not Have"] = "Імен, яких немає в цього клієнта",
    ["New Profile"] = "Новий профіль",
    ["Objects The Game Keeps To Itself"] = "Об'єктів гра лишила собі",
    ["Only used while the switch above is on."] =
        "Береться до уваги лише при увімкненому перемикачі вище.",
    ["Other Profiles"] = "Інші профілі",
    ["Outline Bag Slots"] = "Обводити комірки торб",
    ["Outline Icons"] = "Обводити піктограми",
    ["Paint the settings windows of other addons that use the same library this one does. Needs /reload either way."] =
        "Фарбувати вікна налаштувань інших аддонів, що користуються тією ж " ..
        "бібліотекою. В обидва боки потребує /reload.",
    ["Panel Tabs"] = "Вкладки панелі",
    ["Party and Raid Frames"] = "Фрейми групи та рейду",
    ["Pet"] = "Улюбленець",
    ["Player"] = "Гравець",
    ["Power Bar Fixed Color"] = "Власний колір смуги ресурсу",
    ["Power Text"] = "Текст ресурсу",
    ["Profile Name"] = "Ім'я профілю",
    ["Profiles"] = "Профілі",
    ["Protected Frames The Sweep Left Alone"] =
        "Захищених фреймів обхід не торкнувся",
    ["Put every setting in the profile you are in back to the addon's defaults. Other profiles are left alone."] =
        "Повернути всі налаштування профілю, в якому ви перебуваєте, до " ..
        "умовчань аддона. Інші профілі не чіпаються.",
    ["Remove a profile you are not using. The one you are in cannot be deleted: deleting it would leave the addon with no settings at all."] =
        "Видалити профіль, яким ви не користуєтеся. Той, у якому ви " ..
        "перебуваєте, видалити не можна: аддон лишився б узагалі без " ..
        "налаштувань.",
    ["Rename"] = "Перейменувати",
    ["Reset This Profile"] = "Скинути цей профіль",
    ["Secret Values The Engine Refused"] = "Закритих значень рушій не віддав",
    ["Set the Size of Group Frames"] = "Задавати розмір фреймів групи",
    ["Shadow Under Icons"] = "Тінь під піктограмами",
    ["Some windows are protected by the engine, and touching them can make the game refuse an action later. Off leaves them exactly as the game draws them."] =
        "Частина вікон захищена рушієм, і дотик до них може змусити гру " ..
        "відмовити в дії пізніше. Вимкненим лишає їх саме такими, якими їх " ..
        "малює гра.",
    ["Spell and item icons across the whole interface. Each of these is off on a fresh install: an icon is how the player recognises a spell, and changing it is a choice, not a default."] =
        "Піктограми заклять і предметів по всьому інтерфейсу. Кожне з цих " ..
        "налаштувань вимкнене на свіжому встановленні: за піктограмою " ..
        "гравець упізнає закляття, і змінювати її — вибір, а не умовчання.",
    ["Start a profile with that name, at the addon's defaults, and switch this character to it."] =
        "Завести профіль із таким ім'ям, на умовчаннях аддона, і перевести " ..
        "в нього цього персонажа.",
    ["Switch this character to another profile. Everything in this window follows at once."] =
        "Перевести цього персонажа в інший профіль. Усе в цьому вікні " ..
        "змінюється слідом одразу.",
    ["Take every setting from another profile into the one you are in. The other profile is left alone."] =
        "Узяти всі налаштування іншого профілю в той, у якому ви " ..
        "перебуваєте. Інший профіль не чіпається.",
    ["Tapped Mobs Greyed"] = "Чужа здобич блякне",
    ["Target"] = "Ціль",
    ["Target of Target"] = "Ціль цілі",
    ["Text Position"] = "Місце тексту",
    ["The bars the game draws over heads. The first entry in every list is the game's own look."] =
        "Смуги, які гра малює над головами. Перший запис у кожному списку — " ..
        "рідний вигляд гри.",
    ["The font for this group of elements. The first entry follows the global tab."] =
        "Шрифт для цієї групи елементів. Перший запис означає «як на " ..
        "спільній вкладці».",
    ["The font the whole interface uses. The first entry leaves the game's own font in place."] =
        "Шрифт, яким набраний увесь інтерфейс. Перший запис лишає рідний " ..
        "шрифт гри.",
    ["The game's own portrait frames: you, your target, the party. The first entry in every list below is the game's own look, so nothing here is one way."] =
        "Рідні портретні фрейми гри: ви, ваша ціль, група. Перший запис у " ..
        "кожному списку нижче — рідний вигляд гри, тож ніщо тут не в один " ..
        "бік.",
    ["The numbers written across the health and power bars. The first entry in every list is the game's own."] =
        "Числа, написані поверх смуг здоров'я та ресурсу. Перший запис у " ..
        "кожному списку — рідний ігровий.",
    ["The one colour used when the health bar is set to a fixed colour above."] =
        "Той єдиний колір, яким фарбується смуга здоров'я, якщо вище обрано " ..
        "власний колір.",
    ["The one colour used when the name is set to a fixed colour above."] =
        "Той єдиний колір, яким фарбується ім'я, якщо вище обрано власний " ..
        "колір.",
    ["The one colour used when the power bar is set to a fixed colour above."] =
        "Той єдиний колір, яким фарбується смуга ресурсу, якщо вище обрано " ..
        "власний колір.",
    ["The outline around every letter. Thin reads better on a bright world, none reads better on a dark interface."] =
        "Обведення навколо кожної літери. Тонке краще читається на світлому " ..
        "світі, відсутність обведення — на темному інтерфейсі.",
    ["The outline for this group. The first entry follows the global tab."] =
        "Обведення для цієї групи. Перший запис означає «як на спільній " ..
        "вкладці».",
    ["The same choice for the power bar."] =
        "Той самий вибір для смуги ресурсу.",
    ["The texture the health bar is drawn with. The first entry leaves the game's own."] =
        "Текстура, якою намальована смуга здоров'я. Перший запис лишає " ..
        "рідну ігрову.",
    ["The texture the power bar is drawn with. The first entry leaves the game's own."] =
        "Текстура, якою намальована смуга ресурсу. Перший запис лишає рідну " ..
        "ігрову.",
    ["The two end caps of the main action bar. Hiding them is the one thing here that removes a piece of the game rather than darkening it."] =
        "Два навершя основної панелі вмінь. Їхнє приховування — єдине тут, " ..
        "що прибирає шматок гри, а не затемнює його.",
    ["Trim the dull edge the artist drew around each icon, so the picture itself fills the square."] =
        "Зрізати тьмяну окрайку, яку художник намалював навколо кожної " ..
        "піктограми, щоб сам малюнок заповнив квадрат.",
    ["Type a name here, then press one of the buttons below."] =
        "Наберіть тут ім'я і натисніть одну з кнопок нижче.",
    ["Unit Name Color"] = "Колір імені юніта",
    ["Unit Name Fixed Color"] = "Власний колір імені юніта",
    ["What the health bar says: nothing, the current value, the value and the maximum, or a percentage."] =
        "Що написано на смузі здоров'я: нічого, поточне значення, значення " ..
        "і межа або відсотки.",
    ["What the health bar's colour means: the game's own rule, the class of whoever it belongs to, or one colour you pick."] =
        "Що означає колір смуги здоров'я: рідне правило гри, клас того, " ..
        "кому вона належить, або один обраний вами колір.",
    ["What the power bar's colour means: the game's own rule by power type, or one colour you pick."] =
        "Що означає колір смуги ресурсу: рідне правило гри за видом ресурсу " ..
        "або один обраний вами колір.",
    ["What the unit's name is coloured by: the game's own rule, the unit's class, or one colour you pick."] =
        "Чим пофарбоване ім'я юніта: рідним правилом гри, класом юніта або " ..
        "одним обраним вами кольором.",
    ["Where on the bar the number stands."] = "Де на смузі стоїть число.",
    ["While this is off, not one number is forced on the game: a party member keeps the size the game gave it, and the real native numbers are read before the first change of ours and put back when this goes off again."] =
        "Поки це вимкнено, грі не нав'язується жодного числа: член групи " ..
        "зберігає розмір, який дала йому гра, а справжні рідні числа " ..
        "зчитуються до першої нашої правки й повертаються, коли це " ..
        "вимикають знову.",
    ["World Map"] = "Мапа світу",
    ["Write thousands as a short form instead of every digit."] =
        "Писати тисячі скорочено, а не кожною цифрою.",
    ["module \"%s\" brings an options section, and this version does not draw one: the settings window builds its pages from the schema instead. The module works; its settings are simply not shown."] =
        "модуль «%s» приніс розділ налаштувань, а ця версія дерева " ..
        "налаштувань не малює: вікно збирає свої сторінки зі схеми. Сам " ..
        "модуль працює; просто його налаштувань не видно.",
})
