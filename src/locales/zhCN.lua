-- zhCN, the Simplified Chinese translation of enUS: it replaces the strings it
-- translates when the client is in Simplified Chinese, and any string it lacks
-- stays enUS. Same keys and format specifiers in the same order as enUS
-- (spec/locales_spec.lua checks both); Chinese writes no plural, so the enUS
-- |4singular:plural; forms are left out. '||' prints as one '|'.
local _, ns = ...

if GetLocale() ~= "zhCN" then
	return
end

local L = ns.L

L.REGISTERED = "此角色已登记为%s。"
L.UNREGISTERED = "此角色已不再登记。安装了Mnemosyne的玩家将遗忘它的昵称。"
L.NOT_REGISTERED = "此角色未登记。"
L.NICKNAME_EMPTY = "在命令后输入昵称：/mnemosyne register <昵称>"
L.NICKNAME_LONG = "昵称最多32个字符。"
L.NICKNAME_ESCAPE = "昵称不能包含||。"
L.NICKNAME_CONTROL = "昵称不能包含控制字符。"
L.NICKNAME_ENCODING = "此昵称包含Mnemosyne无法读取的字符。"
L.HELP = "命令："
L.HELP_REGISTER = "/mnemosyne register <昵称>：登记你正在使用的角色"
L.HELP_UNREGISTER = "/mnemosyne unregister：撤销它的登记；安装了Mnemosyne的玩家会遗忘它"
L.TOOLTIP_PLAYED_BY = "玩家：%s"
-- The sender's name in a chat line, then the nickname: "Hugh Jass (Tony)".
L.CHAT_NAME = "%s（%s）"
L.HEARD = "上次收到：%s" -- an AGO_ string: "Last heard 5 minutes ago"
-- |4singular:plural; picks the word for the number before it.
L.AGO_NOW = "刚刚"
L.AGO_MINUTES = "%d分钟前"
L.AGO_HOURS = "%d小时前"
L.AGO_DAYS = "%d天前"
-- The registration prompt.
L.PROMPT = "%s的玩家是谁？\n\n"
	.. "你的昵称将分享给所有安装了Mnemosyne的玩家，也会经由其他玩家传开。"
L.PROMPT_FROM_PEERS = "%s的玩家是谁？\n\n"
	.. "其他安装了Mnemosyne的玩家说它的玩家是%s。登记即可确认。\n\n"
	.. "你的昵称将分享给所有安装了Mnemosyne的玩家，也会经由其他玩家传开。"
L.PROMPT_NICKNAME = "你的昵称"
L.PROMPT_REGISTER = "登记"
L.PROMPT_ANONYMOUS = "保持匿名"
L.PROMPT_LATER = "稍后再问"
L.KEPT_ANONYMOUS = "此角色为匿名。安装了Mnemosyne的玩家不会把它与任何昵称关联。"
L.ASK_LATER = "你下次登录此角色时，Mnemosyne会再次询问。"
-- The other commands.
L.HELP_LOOKUP = "/mnemosyne lookup <文字>：按名字或昵称查找角色"
L.HELP_STATUS = "/mnemosyne status：你的记忆中有什么"
L.HELP_DEBUG = "/mnemosyne debug：在聊天框体中记录每条发送和收到的消息，或停止记录；"
	.. "/mnemosyne debug copy：在窗口中显示记录以便复制"
L.HELP_HELP = "/mnemosyne help：此列表"
L.LOOKUP_EMPTY = "在命令后输入名字或昵称：/mnemosyne lookup <文字>"
L.LOOKUP_NONE = "没有已知角色符合“%s”。"
L.LOOKUP_FOUND = "%s：玩家是%s"
L.LOOKUP_MORE = "……还有%d个。输入更多名字以缩小搜索范围。"
L.STATUS_IDENTITIES = "已知身份：%d"
L.STATUS_CHARACTERS = "你的角色：已登记%d个，匿名%d个"
L.STATUS_REGISTERED = "此角色：已登记为%s"
L.STATUS_ANONYMOUS = "此角色：匿名"
L.STATUS_NOT_ASKED = "此角色：尚未登记"
L.STATUS_UNREGISTERED = "此角色：已撤销登记"
L.STATUS_CANNOT_SEND = "此账号无法在这里发送插件消息（试玩账号）：Mnemosyne只接收。"
L.DEBUG_ON =
	"调试记录已开启：每条发送和收到的消息都会显示在这里。/mnemosyne debug可停止。"
L.DEBUG_OFF = "调试记录已关闭。"
L.HELP_ECHO =
	"/mnemosyne echo：一个测试用的Mnemosyne玩家，会发回你发送的内容，供你独自测试，或停止"
L.ECHO_ON =
	"回声测试玩家已开启：Echo Mnemosyne会发回你对它说的悄悄话或广播的内容。/mnemosyne echo可停止。"
L.ECHO_OFF = "回声测试玩家已关闭：Echo Mnemosyne已被遗忘。"
L.DEBUG_LOG_TITLE = "Mnemosyne调试记录"
L.DEBUG_LOG_TEXT = "本次会话的记录，包含其他玩家的名字：复制（Ctrl+C）后即可分享。"
L.DEBUG_SENT = "已发送至%s：%s"
L.DEBUG_NOT_SENT = "未发送至%s（%s）：%s"
L.DEBUG_RECEIVED = "收到来自%s，经由%s：%s"
L.DEBUG_DROPPED = "丢弃来自%s（%s）：%s"
-- The debug report.
L.HELP_REPORT = "/mnemosyne report：生成调试报告，粘贴到错误报告中"
L.REPORT_TITLE = "Mnemosyne调试报告"
L.REPORT_LINK = "复制此链接（Ctrl+C）并在浏览器中打开：它会打开一份已填好的错误报告。"
L.REPORT_TEXT = "如果链接无法打开，请复制整份报告（Ctrl+C）并粘贴到错误报告中："
L.REPORT_OFFER = "Mnemosyne遇到了一个错误。要报告吗？报告会隐藏其他玩家的名字。"
L.REPORT_SHOW = "显示报告"
L.REPORT_NOT_NOW = "以后再说"
L.REPORT_NEVER = "不再询问"
-- Second-hand identities and syncs.
L.SECOND_HAND = "~%s" -- a nickname heard second-hand: "~Tony"
L.HEARD_FROM = "由%s转告"
L.LOOKUP_FOUND_SECOND_HAND = "%s：玩家是%s，由%s转告" -- the nickname marked as SECOND_HAND
L.HELP_SYNC = "/mnemosyne sync：与当前能联系到的Mnemosyne玩家同步，更新你的记忆"
L.SYNC_STARTED = "正在与%d名Mnemosyne玩家同步。"
L.SYNC_NONE =
	"当前没有可同步的Mnemosyne玩家：本次会话未收到任何Mnemosyne玩家的消息，或都已在过去6小时内同步过。"
-- Forgetting.
L.HELP_FORGET = "/mnemosyne forget <角色>：删除一个角色的昵称，并拒绝他人对它的转告"
L.HELP_UNFORGET = "/mnemosyne unforget <角色>：撤销forget"
L.FORGOTTEN = "%s已被遗忘。现在只有它自己的说法有效，直到/mnemosyne unforget %s。"
L.ALREADY_FORGOTTEN = "%s已被遗忘。"
L.UNFORGOTTEN = "%s不再被遗忘。"
L.NOT_FORGOTTEN = "%s未被遗忘。"
L.FORGOTTEN_LIST = "已遗忘：%s"
L.FORGET_FULL_NAME = "输入角色的完整名字，包括名和姓：/mnemosyne forget <角色>"
L.FORGOTTEN_NONE = "没有被遗忘的角色。输入角色的完整名字：/mnemosyne forget <角色>"
L.NEWER_VERSION = "Mnemosyne有新版本：请更新，否则其他玩家的部分消息将继续被忽略。"
-- The settings panel (Options, AddOns, Mnemosyne).
L.HELP_PANEL = "/mnemosyne：打开Mnemosyne窗口"
L.HELP_SETTINGS = "/mnemosyne settings：打开设置面板"
L.PANEL_CHARACTER = "此角色"
L.PANEL_NICKNAME = "昵称"
L.PANEL_REGISTER = "登记"
L.PANEL_CHANGE = "更换"
L.PANEL_UNREGISTER = "撤销登记"
L.PANEL_CANNOT_REGISTER =
	"此账号无法在这里发送插件消息（试玩账号），因此无法登记角色：Mnemosyne只接收。"
L.PANEL_SWITCHES = "设置选项"
L.PANEL_TOOLTIP = "在鼠标提示中显示"
L.PANEL_TOOLTIP_HELP = "在角色的鼠标提示中显示它的玩家是谁。"
L.PANEL_CHAT = "在聊天中显示"
L.PANEL_CHAT_HELP = "在聊天中角色名字的后面，以及名字的鼠标提示中，显示它的玩家是谁。"
L.PANEL_SECOND_HAND = "显示二手信息"
L.PANEL_SECOND_HAND_HELP = "以灰色显示其他玩家转告的内容，并标上~。"
	.. "关闭时，你只会看到角色关于自己的说法。"
L.PANEL_PASS_ON = "转告我知道的"
L.PANEL_PASS_ON_HELP = "与其他玩家同步时，转告你知道的所有昵称，并把同步带来的新昵称发布到你的公会。"
	.. "关闭时，你只分享自己的登记。"
L.PANEL_EVERYONE = "与所有人通信"
L.PANEL_EVERYONE_HELP = "关闭时，Mnemosyne只与你的好友（你的好友名单和战网好友）以及你的公会通信。"
	.. "开启时，还会与你的队伍以及你鼠标指向或选为目标的任何人通信。"
L.PANEL_ASK_STRANGERS = "询问陌生人"
L.PANEL_ASK_STRANGERS_HELP = "向你鼠标指向或选为目标、但不认识的角色发送一条询问悄悄话，不会显示在聊天中，"
	.. "每个角色每天最多一次。"
L.PANEL_OFFER_REPORT = "出错后提议报告"
L.PANEL_OFFER_REPORT_HELP = "Mnemosyne自身出错时，每次会话提议一次调试报告。"
L.PANEL_STATUS = "状态"
L.PANEL_REPORT = "报告错误"
L.PANEL_IDENTITIES = "身份"
L.PANEL_SEARCH = "搜索名字和昵称"
L.PANEL_COLUMN_CHARACTER = "角色"
L.PANEL_COLUMN_NICKNAME = "昵称"
L.PANEL_COLUMN_HEARD = "来源"
L.PANEL_COLUMN_AGO = "上次收到"
L.PANEL_FORGET = "遗忘"
L.PANEL_UNDO = "撤销"
L.PANEL_NONE = "没有找到身份。"
L.PANEL_FIRST_HAND = "第一手"
L.PANEL_FIRST_HAND_FORGOTTEN = "第一手，已遗忘" -- heard from the character after you forgot it
L.PANEL_FROM = "来自%s" -- a second-hand identity's source
L.PANEL_DISPUTED = "有争议"
L.PANEL_FORGOTTEN = "已遗忘"
L.PANEL_YOURS = "你的" -- one of your own characters
L.PANEL_ANONYMOUS = "匿名" -- one of your own characters, kept anonymous
L.STATUS_PEERS = "本次会话收到的Mnemosyne玩家：%d"
L.STATUS_SYNCS = "过去6小时内已同步：%s"
L.STATUS_SYNC = "%s（%s）" -- a peer and how long ago: "Anna Conda (5 minutes ago)"
L.STATUS_NO_SYNC = "过去6小时内没有同步。"
-- Mnemosyne's window.
L.WINDOW_WHISPER = "密语"
L.WINDOW_LAST_SYNC = "上次同步：%s，%s。" -- a peer and how long ago
L.WINDOW_WAITING = "等待中：%d"
