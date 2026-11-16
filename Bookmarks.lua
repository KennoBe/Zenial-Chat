-- Message bookmarks: own copies of marked messages in ZenialChatDB.bookmarks. Pure data, no UI.
-- A bookmark outlives its message: pruning, clearing and deleting never touch this list.
local _,Z=...
local B={};Z.Bookmarks=B
B.MAX=500
-- Lookup by conversation and message id. Lives in memory only and is rebuilt when the saved list is
-- another table or has another length, so a lookup never walks the list.
local lookup,lookupFor,lookupCount={}
local function entries()
    local db=Z.store and Z.store.db;if not db then return nil end
    if type(db.bookmarks)~='table'then db.bookmarks={}end
    return db.bookmarks
end
local function index()
    local list=entries();if not list then return lookup end
    if list~=lookupFor or#list~=lookupCount then
        lookup={}
        for _,e in ipairs(list)do local k=lookup[e.key];if not k then k={};lookup[e.key]=k end;k[e.id]=e end
        lookupFor,lookupCount=list,#list
    end
    return lookup
end
function B.Has(key,id)
    local k=index()[tostring(key)]
    return k~=nil and k[tostring(id)]~=nil
end
function B.Count()local list=entries();return list and#list or 0 end
-- Returns true (also when it exists already) or nil and 'limit' / 'invalid'.
function B.Add(conv,msg)
    local list=entries()
    if not list or type(conv)~='table'or type(msg)~='table'or msg.context or msg.deleted or msg.id==nil then return nil,'invalid'end
    local text=msg.text
    if type(text)~='string'or text==''then text=msg.meaning end
    if type(text)~='string'or text==''or type(conv.key)~='string'or not Z.Safe(text,msg.id,msg.sender)then return nil,'invalid'end
    local key,id=conv.key,tostring(msg.id)
    if B.Has(key,id)then return true end
    if#list>=B.MAX then return nil,'limit'end
    local sender=msg.outgoing and msg.ownCharacter or msg.sender
    local entry={key=key,id=id,at=tonumber(msg.at)or 0,sender=type(sender)=='string'and sender or nil,
        outgoing=msg.outgoing==true or nil,text=text,conv=Z.Format and Z.Format.ConversationLabel(conv)or conv.name,
        kind=conv.kind,added=Z.Now()}
    local known=index()
    list[#list+1]=entry
    -- Keep the lookup current without a rebuild.
    local k=known[key];if not k then k={};known[key]=k end
    k[id]=entry;lookupCount=#list
    return true
end
function B.Remove(key,id)
    key,id=tostring(key),tostring(id)
    local k=index()[key];local entry=k and k[id];if not entry then return false end
    local list=entries()
    for i=#list,1,-1 do if list[i]==entry then table.remove(list,i);break end end
    k[id]=nil;lookupCount=#list
    return true
end
-- True while the conversation and the message are still in the archive.
function B.Exists(entry)
    if type(entry)~='table'or not Z.store or type(entry.key)~='string'then return false end
    local conv=Z.store:Get(entry.key);if not conv then return false end
    local at=Z.store:IndexOf(entry.key,entry.id)
    local msg=at and conv.messages[at]
    return msg~=nil and not msg.deleted
end
-- opts.key limits to one conversation, opts.since to messages from that time on. Every term of the
-- query must occur in the text, the sender or the conversation label. Newest message first.
function B.List(query,opts)
    local list=entries()or{};opts=opts or{}
    local fold=Z.Store.Fold;local terms={}
    if type(query)=='string'then for term in fold(Z.Plain(query)):gmatch('%S+')do terms[#terms+1]=term end end
    local result={}
    for _,e in ipairs(list)do
        if(not opts.key or e.key==opts.key)and(not opts.since or e.at>=opts.since)then
            local ok=true
            if#terms>0 then
                local hay=fold(Z.Plain(e.text))..'\n'..fold(Z.Plain(e.sender))..'\n'..fold(Z.Plain(e.conv))
                for _,term in ipairs(terms)do if not hay:find(term,1,true)then ok=false;break end end
            end
            if ok then result[#result+1]=e end
        end
    end
    table.sort(result,function(a,b)
        if a.at~=b.at then return a.at>b.at end
        if a.added~=b.added then return a.added>b.added end
        return a.id>b.id
    end)
    return result
end
