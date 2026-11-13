-- Bundled letter tables for the spelling codec (PhraseCodec). Ships empty on purpose: entries are added only
-- after an own measurement in the game client (two clients) or when computed tables are released.
-- Format: Z.PhraseTables[languageId] = {language=, build=, pool=1, letters={A=..., ..., Z=...}, separator=,
--         source='bundled'|'computed', at=}
-- languageId: 1 = Orcish, 7 = Common. letters: only keys A-Z, each one input character of that language.
local _,Z=...
Z.PhraseTables={}
