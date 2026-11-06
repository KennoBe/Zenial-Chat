-- Message search that runs in slices. A run walks the archive from the newest message backwards and
-- does a bounded amount of work per Step, so even a large archive never blocks a frame.
local _,Z=...
local S={};S.__index=S;Z.Search=S
S.MIN_LENGTH=2
S.BUDGET=800 -- messages per slice
S.MAX_RESULTS=500
S.SLICE_MS=4 -- where the client has a precise clock, a slice also ends after this time
-- Terms must all occur. von:Name / from:Name limits the sender; quotes keep a full name together.
function S.Parse(raw)
    raw=type(raw)=='string'and raw or''
    local fold=Z.Store.Fold;local from
    local function take(prefix)
        raw=raw:gsub('%f[%w]'..prefix..':"([^"]*)"',function(value)from=fold(value);return''end)
        raw=raw:gsub('%f[%w]'..prefix..':(%S+)',function(value)from=fold(value);return''end)
    end
    take('von');take('from')
    local terms={}
    for term in raw:gmatch('%S+')do terms[#terms+1]=fold(term)end
    return terms,from
end
-- options: key (one conversation), since (epoch)
function S.New(store,raw,options)
    options=options or{}
    local terms,from=S.Parse(raw)
    local self=setmetatable({store=store,raw=raw,terms=terms,from=from,since=options.since,results={},hits={},count=0,queue={},done=false},S)
    local length=0;for _,term in ipairs(terms)do length=length+#term end
    if length<S.MIN_LENGTH and not from then self.done=true;self.empty=true;return self end
    if options.key then
        local c=store:Get(options.key);if c then self.queue[1]=c end
    else
        for _,c in pairs(store.conversations)do self.queue[#self.queue+1]=c end
        table.sort(self.queue,function(a,b)
            if(a.last or 0)~=(b.last or 0)then return(a.last or 0)>(b.last or 0)end
            return tostring(a.key)<tostring(b.key)
        end)
    end
    self.position=1
    self.cursor=self.queue[1]and #self.queue[1].messages or 0
    if not self.queue[1]then self.done=true end
    return self
end
local function matches(self,msg)
    if msg.context or msg.deleted then return false end
    if self.from then
        local name=Z.Store.Fold(Z.Plain(msg.outgoing and msg.ownCharacter or msg.sender))
        if not name:find(self.from,1,true)then return false end
    end
    if #self.terms>0 then
        local text=Z.Store.Fold(Z.Plain(msg.text))
        for _,term in ipairs(self.terms)do if not text:find(term,1,true)then return false end end
    end
    return true
end
function S:Step(budget)
    if self.done then return false end
    budget=budget or S.BUDGET;local found=false
    local clock=type(debugprofilestop)=='function'and debugprofilestop or nil
    local deadline=clock and clock()+S.SLICE_MS
    while budget>0 do
        if deadline and budget%32==0 and clock()>deadline then break end
        local conv=self.queue[self.position]
        if not conv then self.done=true;break end
        local msg=self.cursor>=1 and conv.messages[self.cursor]
        if not msg then
            self.position=self.position+1
            local following=self.queue[self.position]
            self.cursor=following and #following.messages or 0
        elseif self.since and(tonumber(msg.at)or 0)<self.since then
            self.cursor=0 -- messages are sorted by time: everything further back is older
        else
            if matches(self,msg)then
                self.count=self.count+1;found=true
                local hit=self.hits[conv.key]
                if hit then hit.count=hit.count+1
                else self.hits[conv.key]={count=1,newest=msg.id}end
                if #self.results<S.MAX_RESULTS then self.results[#self.results+1]={key=conv.key,msg=msg}end
            end
            self.cursor=self.cursor-1
        end
        budget=budget-1
    end
    return found
end
-- The messages around a hit, for its tooltip.
function S.Context(store,hit,around)
    local conv=store:Get(hit.key);if not conv then return{}end
    local index=store:IndexOf(hit.key,hit.msg.id);if not index then return{}end
    local lines={}
    for i=math.max(1,index-around),math.min(#conv.messages,index+around)do
        local msg=conv.messages[i]
        if msg and not msg.context and not msg.deleted then
            lines[#lines+1]={text=Z.Format.MessageLine(conv,msg,'sender'),current=i==index}
        end
    end
    return lines
end
-- A plain extract around the first term that fits one row.
function S.Snippet(msg,terms,limit)
    limit=limit or 110
    local plain=(Z.Plain(msg.text):gsub('[\r\n]+',' '))
    if #plain<=limit then return plain end
    local folded=Z.Store.Fold(plain);local at
    for _,term in ipairs(terms or{})do local a=folded:find(term,1,true);if a and(not at or a<at)then at=a end end
    local start=math.max(1,(at or 1)-30)
    -- Do not begin or end inside a multi-byte character.
    while start>1 and(plain:byte(start)or 0)>=128 and(plain:byte(start)or 0)<192 do start=start-1 end
    local stop=math.min(#plain,start+limit)
    while stop<#plain and(plain:byte(stop+1)or 0)>=128 and(plain:byte(stop+1)or 0)<192 do stop=stop-1 end
    return(start>1 and'…'or'')..plain:sub(start,stop)..(stop<#plain and'…'or'')
end
