-- Measured word -> garbled word pairs. Stays empty until the word list of InterpretData.lua has been measured
-- with two clients (TEST REQUIRED). Entry format, one entry per language and client build:
--   { language = <language ID>, build = <client build number>, pairs = { word = 'garbledword', ... } }
-- Entries for another build than the running client are ignored by GarbleMap.
local _,Z=...
Z.GarbleData={}
