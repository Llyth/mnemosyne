-- koKR, the Korean translation of enUS: it replaces the strings it translates
-- when the client is Korean, and any string it lacks stays enUS. Same keys,
-- same format specifiers in the same order as enUS (spec/locales_spec.lua
-- checks both); Korean writes no plural, so the |4singular:plural; forms are
-- left out. '||' prints as one '|'.
local _, ns = ...

if GetLocale() ~= "koKR" then
	return
end

local L = ns.L

L.REGISTERED = "이 캐릭터가 등록되었습니다. 별명: %s"
L.UNREGISTERED =
	"이 캐릭터는 더 이상 등록되어 있지 않습니다. Mnemosyne를 사용하는 플레이어들은 이 캐릭터의 별명을 잊게 됩니다."
L.NOT_REGISTERED = "이 캐릭터는 등록되어 있지 않습니다."
L.NICKNAME_EMPTY = "명령어 뒤에 별명을 입력하십시오: /mnemosyne register <별명>"
L.NICKNAME_LONG = "별명은 최대 32자까지 가능합니다."
L.NICKNAME_ESCAPE = "별명에는 ||를 사용할 수 없습니다."
L.NICKNAME_CONTROL = "별명에는 제어 문자를 사용할 수 없습니다."
L.NICKNAME_ENCODING = "이 별명에는 Mnemosyne가 읽을 수 없는 문자가 있습니다."
L.HELP = "명령어:"
L.HELP_REGISTER = "/mnemosyne register <별명>: 플레이 중인 캐릭터 등록"
L.HELP_UNREGISTER =
	"/mnemosyne unregister: 등록 철회(Mnemosyne를 사용하는 플레이어들이 이 캐릭터를 잊습니다)"
L.TOOLTIP_PLAYED_BY = "플레이어: %s"
-- The sender's name in a chat line, then the nickname: "Hugh Jass (Tony)".
L.CHAT_NAME = "%s (%s)"
L.HEARD = "마지막 수신: %s" -- an AGO_ string: "마지막 수신: 5분 전"
-- |4singular:plural; picks the word for the number before it.
L.AGO_NOW = "방금"
L.AGO_MINUTES = "%d분 전"
L.AGO_HOURS = "%d시간 전"
L.AGO_DAYS = "%d일 전"
-- The registration prompt.
L.PROMPT = "%s 캐릭터의 플레이어는 누구입니까?\n\n"
	.. "별명은 Mnemosyne를 사용하는 모든 플레이어에게 다른 플레이어를 통해서도 공유됩니다."
L.PROMPT_FROM_PEERS = "%s 캐릭터의 플레이어는 누구입니까?\n\n"
	.. "Mnemosyne를 사용하는 다른 플레이어들은 이 캐릭터의 플레이어를 %s 님으로 알고 있습니다. "
	.. "확인하려면 등록하십시오.\n\n"
	.. "별명은 Mnemosyne를 사용하는 모든 플레이어에게 다른 플레이어를 통해서도 공유됩니다."
L.PROMPT_NICKNAME = "내 별명"
L.PROMPT_REGISTER = "등록"
L.PROMPT_ANONYMOUS = "익명 유지"
L.PROMPT_LATER = "나중에 묻기"
L.KEPT_ANONYMOUS =
	"이 캐릭터는 익명입니다. Mnemosyne를 사용하는 플레이어들은 이 캐릭터를 어떤 별명과도 연결하지 않습니다."
L.ASK_LATER = "이 캐릭터로 다음에 접속하면 Mnemosyne가 다시 묻습니다."
L.OPEN_PROFESSIONS =
	"Mnemosyne가 제조법을 공유할 수 있도록 각 전문 기술 창을 한 번씩 여십시오: %s."
-- The other commands.
L.HELP_LOOKUP = "/mnemosyne lookup <텍스트>: 이름이나 별명으로 캐릭터 검색"
L.HELP_STATUS = "/mnemosyne status: 기억에 담긴 내용"
L.HELP_DEBUG = "/mnemosyne debug: 주고받는 모든 메시지를 대화창에 기록하거나 중지; "
	.. "/mnemosyne debug copy: 복사할 수 있도록 기록을 창에 표시"
L.HELP_HELP = "/mnemosyne help: 이 목록"
L.LOOKUP_EMPTY = "명령어 뒤에 이름이나 별명을 입력하십시오: /mnemosyne lookup <텍스트>"
L.LOOKUP_NONE = '"%s"에 해당하는 캐릭터가 없습니다.'
L.LOOKUP_FOUND = "%s: 플레이어 %s"
L.LOOKUP_MORE = "...외 %d개. 검색 범위를 좁히려면 이름을 더 입력하십시오."
L.STATUS_IDENTITIES = "알고 있는 신원: %d"
L.STATUS_CHARACTERS = "내 캐릭터: 등록 %d, 익명 %d"
L.STATUS_REGISTERED = "이 캐릭터: 등록됨, 별명 %s"
L.STATUS_ANONYMOUS = "이 캐릭터: 익명"
L.STATUS_NOT_ASKED = "이 캐릭터: 아직 등록되지 않음"
L.STATUS_UNREGISTERED = "이 캐릭터: 등록 철회됨"
L.STATUS_CANNOT_SEND =
	"이 계정은 여기서 애드온 메시지를 보낼 수 없습니다(처음 사용자용 계정). Mnemosyne는 수신만 합니다."
L.DEBUG_ON =
	"디버그 기록 켜짐: 주고받는 모든 메시지가 여기에 표시됩니다. /mnemosyne debug로 중지합니다."
L.DEBUG_OFF = "디버그 기록 꺼짐."
L.HELP_ECHO =
	"/mnemosyne echo: 보낸 내용을 그대로 돌려보내는 테스트용 피어(혼자 테스트할 때), 또는 중지"
L.ECHO_ON = "에코 피어 켜짐: Echo Mnemosyne가 귓속말이나 전체 전송한 내용을 그대로 돌려보냅니다. "
	.. "/mnemosyne echo로 중지합니다."
L.ECHO_OFF = "에코 피어 꺼짐: Echo Mnemosyne를 잊었습니다."
L.DEBUG_LOG_TITLE = "Mnemosyne 디버그 기록"
L.DEBUG_LOG_TEXT =
	"이번 세션의 기록이며 다른 플레이어의 이름이 포함됩니다. 공유하려면 복사하십시오(Ctrl+C)."
L.DEBUG_SENT = "보냄(%s): %s"
L.DEBUG_NOT_SENT = "보내지 못함(%s, %s): %s"
L.DEBUG_RECEIVED = "%s에게서 받음(%s): %s"
L.DEBUG_DROPPED = "%s에게서 받아서 버림(%s): %s"
-- The debug report.
L.HELP_REPORT = "/mnemosyne report: 버그 신고에 붙여 넣을 디버그 보고서"
L.REPORT_TITLE = "Mnemosyne 디버그 보고서"
L.REPORT_LINK =
	"이 링크를 복사(Ctrl+C)하여 브라우저에서 여십시오. 내용이 미리 채워진 버그 신고가 열립니다."
L.REPORT_TEXT =
	"링크가 열리지 않으면 보고서 전체를 복사(Ctrl+C)하여 버그 신고에 붙여 넣으십시오:"
L.REPORT_OFFER =
	"Mnemosyne에 오류가 발생했습니다. 오류를 보고하시겠습니까? 보고서에서는 다른 플레이어의 이름이 가려집니다."
L.REPORT_SHOW = "보고서 보기"
L.REPORT_NOT_NOW = "나중에"
L.REPORT_NEVER = "다시 묻지 않기"
-- Second-hand identities and syncs.
L.SECOND_HAND = "~%s" -- a nickname heard second-hand: "~Tony"
L.HEARD_FROM = "출처: %s"
L.LOOKUP_FOUND_SECOND_HAND = "%s: 플레이어 %s, 출처 %s" -- the nickname marked as SECOND_HAND
L.HELP_SYNC = "/mnemosyne sync: 지금 연결할 수 있는 피어와 기억을 최신 상태로 맞춤"
L.SYNC_STARTED = "피어 %d명과 동기화합니다."
L.SYNC_NONE =
	"지금 동기화할 피어가 없습니다. 이번 세션에 수신된 피어가 없거나, 모두 최근 6시간 안에 동기화했습니다."
L.HELP_SYNC_RESET = "/mnemosyne sync reset: 각 플레이어와 마지막으로 동기화한 시간을 잊고 "
	.. "바로 다시 동기화함 (상대도 해야 함)"
L.SYNC_RESET = "내 쪽의 동기화 대기 시간을 초기화했습니다. 다시 동기화하려면 "
	.. "상대 플레이어도 /mnemosyne sync reset을 입력해야 합니다."
-- Forgetting.
L.HELP_FORGET =
	"/mnemosyne forget <캐릭터>: 캐릭터의 별명을 지우고 다른 플레이어가 전달하는 그 캐릭터 정보를 거부"
L.HELP_UNFORGET = "/mnemosyne unforget <캐릭터>: forget 되돌리기"
L.FORGOTTEN =
	"%s 캐릭터를 잊었습니다. 이제 /mnemosyne unforget %s 전까지 그 캐릭터가 직접 말한 내용만 반영됩니다."
L.ALREADY_FORGOTTEN = "%s 캐릭터는 이미 잊었습니다."
L.UNFORGOTTEN = "%s 캐릭터를 더 이상 잊지 않습니다."
L.NOT_FORGOTTEN = "%s 캐릭터는 잊은 상태가 아닙니다."
L.FORGOTTEN_LIST = "잊은 캐릭터: %s"
L.FORGET_FULL_NAME = "캐릭터의 전체 이름(이름과 성)을 입력하십시오: /mnemosyne forget <캐릭터>"
L.FORGOTTEN_NONE =
	"잊은 캐릭터가 없습니다. 캐릭터의 전체 이름을 입력하십시오: /mnemosyne forget <캐릭터>"
L.NEWER_VERSION =
	"Mnemosyne의 새 버전이 있습니다. 업데이트하지 않으면 다른 플레이어가 보낸 일부 메시지가 계속 무시됩니다."
-- The settings panel (Options, AddOns, Mnemosyne).
L.HELP_PANEL = "/mnemosyne: Mnemosyne 창 열기"
L.HELP_SETTINGS = "/mnemosyne settings: 설정 창 열기"
L.PANEL_CHARACTER = "이 캐릭터"
L.PANEL_NICKNAME = "별명"
L.PANEL_REGISTER = "등록"
L.PANEL_CHANGE = "변경"
L.PANEL_UNREGISTER = "등록 철회"
L.PANEL_CANNOT_REGISTER = "이 계정은 여기서 애드온 메시지를 보낼 수 없어(처음 사용자용 계정) 캐릭터를 등록할 수 "
	.. "없습니다. Mnemosyne는 수신만 합니다."
L.PANEL_SWITCHES = "설정"
L.PANEL_TOOLTIP = "툴팁에 표시"
L.PANEL_TOOLTIP_HELP = "캐릭터의 툴팁에 플레이어를 표시합니다."
L.PANEL_CHAT = "대화창에 표시"
L.PANEL_CHAT_HELP = "대화창에서 캐릭터 이름 뒤와 이름의 툴팁에 플레이어를 표시합니다."
L.PANEL_SECOND_HAND = "간접 정보 표시"
L.PANEL_SECOND_HAND_HELP = "다른 플레이어가 전달한 내용을 회색으로, ~ 표시와 함께 보여 줍니다. "
	.. "끄면 캐릭터가 직접 말한 내용만 보입니다."
L.PANEL_PASS_ON = "아는 정보 전달"
L.PANEL_PASS_ON_HELP = "다른 플레이어와 동기화할 때 알고 있는 모든 별명을 전달하고, "
	.. "동기화로 새로 알게 된 별명을 길드에 알립니다. "
	.. "끄면 내 등록 정보만 공유합니다."
L.PANEL_SHARE_PROFESSIONS = "내 전문 기술 공유"
L.PANEL_SHARE_PROFESSIONS_HELP = "등록된 내 캐릭터의 전문 기술(숙련도와 배운 제조법)을 길드와 친구 중 Mnemosyne를 사용하는 플레이어에게 공유합니다. 끄면 그 "
	.. "플레이어들이 잊습니다."
L.PANEL_EVERYONE = "모두와 대화"
L.PANEL_EVERYONE_HELP = "끄면 Mnemosyne는 친구(친구 목록과 Battle.net 친구)와 길드와만 대화합니다. "
	.. "켜면 파티, 그리고 마우스를 올리거나 대상으로 지정한 모든 플레이어와도 대화합니다."
L.PANEL_ASK_STRANGERS = "모르는 캐릭터에게 묻기"
L.PANEL_ASK_STRANGERS_HELP = "마우스를 올리거나 대상으로 지정한 모르는 캐릭터에게 대화창에 보이지 않는 질문을 "
	.. "귓속말로 보냅니다. 캐릭터마다 하루 최대 한 번입니다."
L.PANEL_OFFER_REPORT = "오류 발생 시 보고서 제안"
L.PANEL_OFFER_REPORT_HELP =
	"Mnemosyne 자체 오류가 발생하면 세션마다 한 번 디버그 보고서를 제안합니다."
L.PANEL_STATUS = "상태"
L.PANEL_REPORT = "버그 신고"
L.PANEL_IDENTITIES = "신원"
L.PANEL_SEARCH = "이름 및 별명 검색"
L.PANEL_COLUMN_CHARACTER = "캐릭터"
L.PANEL_COLUMN_NICKNAME = "별명"
L.PANEL_COLUMN_HEARD = "출처"
L.PANEL_COLUMN_AGO = "마지막 수신"
L.PANEL_FORGET = "잊기"
L.PANEL_UNDO = "되돌리기"
L.PANEL_NONE = "찾은 신원이 없습니다."
L.PANEL_FIRST_HAND = "직접"
L.PANEL_FIRST_HAND_FORGOTTEN = "직접, 잊음" -- heard from the character after you forgot it
L.PANEL_FROM = "%s 경유" -- a second-hand identity's source
L.PANEL_DISPUTED = "불일치"
L.PANEL_FORGOTTEN = "잊음"
L.PANEL_YOURS = "내 캐릭터" -- one of your own characters
L.PANEL_ANONYMOUS = "익명" -- one of your own characters, kept anonymous
L.STATUS_PEERS = "이번 세션에 수신된 피어: %d"
L.STATUS_SYNCS = "최근 6시간 내 동기화: %s"
L.STATUS_SYNC = "%s (%s)" -- a peer and how long ago: "Anna Conda (5분 전)"
L.STATUS_NO_SYNC = "최근 6시간 내 동기화 없음."
-- Mnemosyne's window.
L.WINDOW_WHISPER = "귓속말"
L.WINDOW_LAST_SYNC = "마지막 동기화: %s, %s." -- a peer and how long ago
L.WINDOW_WAITING = "대기 중: %d"

-- The window's Professions tab.
L.PROFESSIONS = "전문 기술"
L.PROFESSIONS_PRIMARY = "주 전문 기술"
L.PROFESSIONS_SECONDARY = "보조 전문 기술"
L.PROFESSIONS_RECIPES = "제조법"
L.PROFESSIONS_CHARACTERS = "캐릭터"
L.PROFESSIONS_KNOWN_BY = "%s을(를) 아는 캐릭터"
L.PROFESSIONS_RECIPE_COUNT = "제조법 %d개"
L.PROFESSIONS_CHARACTER_COUNT = "캐릭터 %d명"
L.PROFESSIONS_SEARCH = "제조법, 이름 및 별명 검색"
L.PROFESSIONS_NO_RECIPE = "찾은 제조법이 없습니다."
L.PROFESSIONS_BACK = "뒤로"
L.HELP_PROFESSIONS = "/mnemosyne professions: 전문 기술 탭 열기"
