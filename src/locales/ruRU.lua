-- ruRU, the Russian translation of enUS: it replaces the strings it translates
-- when the client is Russian, and any string it lacks stays enUS. Same keys,
-- same format specifiers in the same order as enUS, and |4one:few:many; plurals
-- with Russian's three forms (spec/locales_spec.lua checks both). '||' prints
-- as one '|'.
local _, ns = ...

if GetLocale() ~= "ruRU" then
	return
end

local L = ns.L

L.REGISTERED = "Этот персонаж теперь зарегистрирован под прозвищем %s."
L.UNREGISTERED =
	"Этот персонаж больше не зарегистрирован. Игроки, у которых есть Mnemosyne, забудут его прозвище."
L.NOT_REGISTERED = "Этот персонаж не зарегистрирован."
L.NICKNAME_EMPTY = "Введите прозвище после команды: /mnemosyne register <прозвище>"
L.NICKNAME_LONG = "Прозвище может содержать не более 32 символов."
L.NICKNAME_ESCAPE = "Прозвище не может содержать ||."
L.NICKNAME_CONTROL = "Прозвище не может содержать управляющие символы."
L.NICKNAME_ENCODING =
	"В этом прозвище есть символы, которые Mnemosyne не может прочитать."
L.HELP = "Команды:"
L.HELP_REGISTER =
	"/mnemosyne register <прозвище>: зарегистрировать персонажа, за которого вы играете"
L.HELP_UNREGISTER =
	"/mnemosyne unregister: отменить его регистрацию; игроки, у которых есть Mnemosyne, забудут его"
L.TOOLTIP_PLAYED_BY = "Игрок: %s"
-- The sender's name in a chat line, then the nickname: "Hugh Jass (Tony)".
L.CHAT_NAME = "%s (%s)"
L.HEARD = "Последняя связь: %s" -- an AGO_ string: "Последняя связь: 5 минут назад"
-- |4one:few:many; picks the word for the number before it.
L.AGO_NOW = "только что"
L.AGO_MINUTES = "%d |4минуту:минуты:минут; назад"
L.AGO_HOURS = "%d |4час:часа:часов; назад"
L.AGO_DAYS = "%d |4день:дня:дней; назад"
-- The registration prompt.
L.PROMPT = "Кто играет за персонажа %s?\n\n"
	.. "Ваше прозвище будет передано всем игрокам, у которых есть Mnemosyne, в том числе через других игроков."
L.PROMPT_FROM_PEERS = "Кто играет за персонажа %s?\n\n"
	.. "Другие игроки, у которых есть Mnemosyne, говорят, что за него играет %s. "
	.. "Зарегистрируйте его, чтобы подтвердить.\n\n"
	.. "Ваше прозвище будет передано всем игрокам, у которых есть Mnemosyne, в том числе через других игроков."
L.PROMPT_NICKNAME = "Ваше прозвище"
L.PROMPT_REGISTER = "Зарегистрировать"
L.PROMPT_ANONYMOUS = "Сохранить анонимность"
L.PROMPT_LATER = "Спросить позже"
L.KEPT_ANONYMOUS =
	"Этот персонаж анонимен. Игроки, у которых есть Mnemosyne, не свяжут его ни с каким прозвищем."
L.ASK_LATER =
	"Mnemosyne спросит снова при следующем входе в игру этим персонажем."
L.OPEN_PROFESSIONS =
	"Откройте один раз окно каждой профессии, чтобы Mnemosyne мог передавать ее рецепты: %s."
-- The other commands.
L.HELP_LOOKUP =
	"/mnemosyne lookup <текст>: найти персонажей по имени или прозвищу"
L.HELP_STATUS = "/mnemosyne status: что хранит ваша память"
L.HELP_DEBUG = "/mnemosyne debug: выводить в окно чата каждое отправленное и полученное сообщение или прекратить; "
	.. "/mnemosyne debug copy: журнал в окне для копирования"
L.HELP_HELP = "/mnemosyne help: этот список"
L.LOOKUP_EMPTY =
	"Введите имя или прозвище после команды: /mnemosyne lookup <текст>"
L.LOOKUP_NONE = "Нет известных персонажей по запросу «%s»."
L.LOOKUP_FOUND = "%s: игрок %s"
L.LOOKUP_MORE = "...и еще %d. Введите больше букв имени, чтобы сузить поиск."
L.STATUS_IDENTITIES = "Известных личностей: %d"
L.STATUS_CHARACTERS =
	"Ваши персонажи: зарегистрированных – %d, анонимных – %d"
L.STATUS_REGISTERED = "Этот персонаж: зарегистрирован под прозвищем %s"
L.STATUS_ANONYMOUS = "Этот персонаж: анонимен"
L.STATUS_NOT_ASKED = "Этот персонаж: еще не зарегистрирован"
L.STATUS_UNREGISTERED = "Этот персонаж: регистрация отменена"
L.STATUS_CANNOT_SEND = "Эта учетная запись не может отправлять здесь сообщения модификаций (стартовая версия): "
	.. "Mnemosyne только слушает."
L.DEBUG_ON = "Журнал отладки включен: здесь отображается каждое отправленное и полученное сообщение. "
	.. "/mnemosyne debug выключает его."
L.DEBUG_OFF = "Журнал отладки выключен."
L.HELP_ECHO = "/mnemosyne echo: тестовый участник, который возвращает то, что вы отправляете, "
	.. "чтобы проверять в одиночку, или прекратить"
L.ECHO_ON = "Эхо-участник включен: Echo Mnemosyne возвращает то, что вы ему шепчете или рассылаете. "
	.. "/mnemosyne echo выключает его."
L.ECHO_OFF = "Эхо-участник выключен: Echo Mnemosyne забыт."
L.DEBUG_LOG_TITLE = "Журнал отладки Mnemosyne"
L.DEBUG_LOG_TEXT =
	"Журнал этого сеанса, включая имена других игроков: скопируйте его (Ctrl+C), чтобы поделиться."
L.DEBUG_SENT = "отправлено по каналу %s: %s"
L.DEBUG_NOT_SENT = "не отправлено по каналу %s (%s): %s"
L.DEBUG_RECEIVED = "получено от %s по каналу %s: %s"
L.DEBUG_DROPPED = "получено от %s и отклонено (%s): %s"
-- The debug report.
L.HELP_REPORT =
	"/mnemosyne report: отчет отладки, чтобы вставить его в отчет об ошибке"
L.REPORT_TITLE = "Отчет отладки Mnemosyne"
L.REPORT_LINK =
	"Скопируйте эту ссылку (Ctrl+C) и откройте ее в браузере: откроется уже заполненный отчет об ошибке."
L.REPORT_TEXT =
	"Если ссылка не открывается, скопируйте весь отчет (Ctrl+C) и вставьте его в отчет об ошибке:"
L.REPORT_OFFER =
	"В Mnemosyne произошла ошибка. Сообщить о ней? Отчет скрывает имена других игроков."
L.REPORT_SHOW = "Показать отчет"
L.REPORT_NOT_NOW = "Не сейчас"
L.REPORT_NEVER = "Больше не спрашивать"
-- Second-hand identities and syncs.
L.SECOND_HAND = "~%s" -- a nickname heard second-hand: "~Tony"
L.HEARD_FROM = "Источник: %s"
L.LOOKUP_FOUND_SECOND_HAND = "%s: игрок %s, источник: %s" -- the nickname marked as SECOND_HAND
L.HELP_SYNC =
	"/mnemosyne sync: сверить вашу память с участниками, доступными сейчас"
L.SYNC_STARTED =
	"Синхронизация с %d |4участником:участниками:участниками;."
L.SYNC_NONE = "Сейчас не с кем синхронизироваться: в этом сеансе не было слышно ни одного участника, "
	.. "или со всеми уже была недавняя синхронизация (с согильдийцами — за последний час, "
	.. "с остальными — за последние 6 часов)."
L.HELP_SYNC_RESET = "/mnemosyne sync reset: забыть, когда вы синхронизировались с каждым игроком, "
	.. "чтобы сразу синхронизироваться снова (другой игрок тоже должен это сделать)"
L.SYNC_RESET = "Ожидание между синхронизациями сброшено с вашей стороны. Другой игрок тоже должен ввести "
	.. "/mnemosyne sync reset, прежде чем вы сможете снова синхронизироваться."
-- Forgetting.
L.HELP_FORGET = "/mnemosyne forget <персонаж>: удалить прозвище персонажа "
	.. "и отвергать то, что о нем передают другие"
L.HELP_UNFORGET = "/mnemosyne unforget <персонаж>: отменить forget"
L.FORGOTTEN = "Персонаж %s забыт. Теперь учитывается только то, что он говорит о себе сам, "
	.. "до /mnemosyne unforget %s."
L.ALREADY_FORGOTTEN = "Персонаж %s уже забыт."
L.UNFORGOTTEN = "Персонаж %s больше не забыт."
L.NOT_FORGOTTEN = "Персонаж %s не забыт."
L.FORGOTTEN_LIST = "Забытые: %s"
L.FORGET_FULL_NAME =
	"Введите полное имя персонажа, имя и фамилию: /mnemosyne forget <персонаж>"
L.FORGOTTEN_NONE =
	"Забытых персонажей нет. Введите полное имя персонажа: /mnemosyne forget <персонаж>"
L.NEWER_VERSION = "Вышла новая версия Mnemosyne: обновите ее, "
	.. "иначе часть сообщений от других игроков будет игнорироваться."
-- The settings panel (Options, AddOns, Mnemosyne).
L.HELP_PANEL = "/mnemosyne: открыть окно Mnemosyne"
L.HELP_SETTINGS = "/mnemosyne settings: открыть панель параметров"
L.PANEL_CHARACTER = "Этот персонаж"
L.PANEL_NICKNAME = "Прозвище"
L.PANEL_REGISTER = "Зарегистрировать"
L.PANEL_CHANGE = "Изменить"
L.PANEL_UNREGISTER = "Отменить регистрацию"
L.PANEL_CANNOT_REGISTER = "Эта учетная запись не может отправлять здесь сообщения модификаций (стартовая версия), "
	.. "поэтому не может зарегистрировать персонажа: Mnemosyne только слушает."
L.PANEL_SWITCHES = "Параметры"
L.PANEL_TOOLTIP = "Показывать в подсказках"
L.PANEL_TOOLTIP_HELP =
	"Показывать в подсказке персонажа, кто за него играет."
L.PANEL_CHAT = "Показывать в чате"
L.PANEL_CHAT_HELP =
	"Показывать, кто играет за персонажа, после его имени в чате и в подсказке к его имени."
L.PANEL_SECOND_HAND = "Показывать из вторых рук"
L.PANEL_SECOND_HAND_HELP = "Показывать то, что передали другие игроки, серым цветом и с пометкой ~. "
	.. "Если выключено, вы видите только то, что персонажи сказали о себе сами."
L.PANEL_PASS_ON = "Передавать то, что я знаю"
L.PANEL_PASS_ON_HELP = "Передавать все известные вам прозвища при синхронизации с другим игроком "
	.. "и сообщать гильдии новые прозвища, полученные при синхронизации. "
	.. "Если выключено, вы передаете только свои регистрации."
L.PANEL_SHARE_PROFESSIONS = "Передавать мои профессии"
L.PANEL_SHARE_PROFESSIONS_HELP = "Передавать профессии ваших зарегистрированных персонажей (уровни навыка и "
	.. "изученные рецепты) игрокам с Mnemosyne в вашей гильдии и среди ваших друзей. Если выключено, они их забудут."
L.PANEL_EVERYONE = "Общаться со всеми"
L.PANEL_EVERYONE_HELP = "Если выключено, Mnemosyne общается только с вашими друзьями (из списка друзей "
	.. "и друзьями Battle.net) и гильдией. Если включено, то еще и с вашими группами и со всеми, "
	.. "на кого вы наводите указатель мыши или кого берете в цель."
L.PANEL_ASK_STRANGERS = "Спрашивать незнакомцев"
L.PANEL_ASK_STRANGERS_HELP = "Шепотом отправлять невидимый в чате запрос незнакомому персонажу, на которого вы "
	.. "наводите указатель мыши или которого берете в цель, не чаще раза в день для каждого персонажа."
L.PANEL_OFFER_REPORT = "Предлагать отчет после ошибки"
L.PANEL_OFFER_REPORT_HELP = "Когда в Mnemosyne происходит собственная ошибка, предлагать отчет отладки "
	.. "один раз за сеанс."
L.PANEL_STATUS = "Статус"
L.PANEL_REPORT = "Сообщить об ошибке"
L.PANEL_IDENTITIES = "Личности"
L.PANEL_SEARCH = "Поиск по именам и прозвищам"
L.PANEL_COLUMN_CHARACTER = "Персонаж"
L.PANEL_COLUMN_NICKNAME = "Прозвище"
L.PANEL_COLUMN_HEARD = "Источник"
L.PANEL_COLUMN_AGO = "Последняя связь"
L.PANEL_COLUMN_VERSION = "Версия"
L.PANEL_FORGET = "Забыть"
L.PANEL_UNDO = "Отменить"
L.PANEL_NONE = "Личности не найдены."
L.PANEL_FIRST_HAND = "из первых рук"
L.PANEL_FIRST_HAND_FORGOTTEN = "из первых рук, забыт" -- heard from the character after you forgot it
L.PANEL_FROM = "от %s" -- a second-hand identity's source
L.PANEL_DISPUTED = "спорный"
L.PANEL_FORGOTTEN = "забыт"
L.PANEL_YOURS = "ваш" -- one of your own characters
L.PANEL_ANONYMOUS = "анонимен" -- one of your own characters, kept anonymous
L.STATUS_PEERS = "Участников услышано за сеанс: %d"
L.STATUS_SYNCS =
	"Этот персонаж синхронизировался за последние 6 часов с: %s"
L.STATUS_SYNC = "%s (%s)" -- a peer and how long ago: "Anna Conda (5 минут назад)"
L.STATUS_NO_SYNC =
	"Этот персонаж не синхронизировался за последние 6 часов."
-- Mnemosyne's window.
L.WINDOW_WHISPER = "Шепот"
L.WINDOW_LAST_SYNC = "Последняя синхронизация этого персонажа: %s, %s." -- a peer and how long ago
L.WINDOW_WAITING = "В очереди: %d"

-- The window's Professions tab.
L.PROFESSIONS = "Профессии"
L.PROFESSIONS_PRIMARY = "Основные профессии"
L.PROFESSIONS_SECONDARY = "Вспомогательные профессии"
L.PROFESSIONS_RECIPES = "Рецепты"
L.PROFESSIONS_CHARACTERS = "Персонажи"
L.PROFESSIONS_KNOWN_BY = "Кто знает рецепт «%s»"
L.PROFESSIONS_RECIPE_COUNT = "%d |4рецепт:рецепта:рецептов;"
L.PROFESSIONS_CHARACTER_COUNT = "%d |4персонаж:персонажа:персонажей;"
L.PROFESSIONS_SEARCH = "Поиск по рецептам, именам и прозвищам"
L.PROFESSIONS_NO_RECIPE = "Рецепты не найдены."
L.PROFESSIONS_BACK = "Назад"
L.HELP_PROFESSIONS = "/mnemosyne professions: открыть вкладку «Профессии»"
