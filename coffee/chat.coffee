#coffee -cwb chat.coffee

###
Development-Info
The message stanza can contain a subject-tag. No idea, why a chat should have a subject... its more like a pm then
Thread-tags are for now not included, too. (http://tools.ietf.org/html/rfc6121#section-5.2.5)
###

class aChat extends Backbone.Model

    _.extend(aChat, Backbone.Events);

    #Initialize the Chat and connects to the chat-server
    initialize: -> 
        # Create the roster and push the chat as object with it for backreferencing
        @views = []
        @roster = new Roster null, @
        Strophe.addNamespace 'CHATSTATES', 'http://jabber.org/protocol/chatstates'
        @connect() if @.get('login')
        @initDebug() if @.get('debug')
        @initViews()
        $('#'+@get('id') + ' select[name="presenceShow"] option[value="offline"]').removeAttr('selected') if @.get('login')
        @on 'removeView', @removeView
        this

    #Properties
    @VERSION: '15.02.2013'
    defaults:
        jid:null
        sid:null
        rid:null
        pw:null
        httpbind:'http-bind/'
        login:false
        debug:false
        chatstates:true
        online:false
        status:null
        show:null
        info:null
        
    con:null
    roster:null
    views:null #[] <-- scoping issues
    loginTimeout:null
    
    @state:
        OPEN:     1<<0
        MINIMIZED:1<<1
        CURRENT:  1<<2
        UPDATE:   1<<3
        ACTIVE:   1<<4
        COMPOSING:1<<5
        PAUSED:   1<<6
        INACTIVE: 1<<7
        GONE:     1<<8
    
    #connects or attachs to the server
    connect: =>
        return @ if @get 'online'
        @con = new Strophe.Connection(@.get('httpbind'))
        @initDiscoPlugin()
        if @.get('jid') and @.get('sid') and @.get('rid')
            @con.attach(@.get('jid'),@.get('sid'),@.get('rid'),@onconnect)
            @debug("Attach to session with jid: #{@.get('jid')}, sid: #{@.get('sid')}, rid: #{@.get('rid')}");
        else if @.get('jid') and @.get('pw')
            @con.connect(@.get('jid'),@.get('pw'),@onconnect)
            @debug("Connect to server with jid: #{@.get('jid')}, pw: #{@.get('pw')}");
        @
        
    disconnect: =>
        return @ if not @get 'online'
        @set 'online',false
        #@con.send $pres
        #    type:'unavailable'
        #    from:@get 'jid'    # Strophe doesnt send unavailable presence in tests. But doing it manually breaks the lib
        clearTimeout @loginTimeout if @loginTimeout
        @con.disconnect('offline')
        @
        
    onconnect: (status, error) =>
        switch status
            when Strophe.Status.ERROR
                @debug(error)
            when Strophe.Status.AUTHENTICATING
                @debug('Authenticate');
            when Strophe.Status.AUTHFAIL
                @debug('Authentication failed');
            when Strophe.Status.CONNECTING
                @debug('Connect');
            when Strophe.Status.CONNFAIL
                @debug('Connection failed. Try again in 30s');
                @loginTimeout = setTimeout =>
                    @connect()
                ,1000*30
            when Strophe.Status.DISCONNECTING
                @debug('Abmelden');
            when Strophe.Status.DISCONNECTED
                @debug('Abgemeldet');
                @onDisconnected()
            when Strophe.Status.ATTACHED, Strophe.Status.CONNECTED
                @debug('Verbunden');
                
                @set 'online', true
                @con.addHandler ((msg) => @debug(msg); true)
                
                @con.addHandler _.bind(@handle.message.chat,@), null, 'message', 'chat'
                @con.addHandler _.bind(@handle.message.chat,@), null, 'message', 'normal'
                @con.addHandler _.bind(@handle.message.chatstates,@), Strophe.NS.CHATSTATES, 'message'
                @con.addHandler _.bind(@handle.message.thread,@), null, 'thread'
                #@con.addHandler _.bind(@handle.message.groupchat, null, 'message', 'groupchat'# for now we will ignore groupchat
                
                @con.addHandler _.bind(@handle.error,@), null, 'error'
                
                @con.addHandler _.bind(@handle.iq.get,@), null, 'iq', 'get'
                @con.addHandler _.bind(@handle.iq.set,@), null, 'iq', 'set'
                #@con.addHandler _.bind(@handle.iq.error,@), null, 'iq', 'error'# for now we will ignore iq-errors
                
                @con.addHandler _.bind(@handle.presence.unavailable,@), null, 'presence', 'unavailable'
                #@con.addHandler _.bind(@handle.presence.subsciption,@), null, 'presence', 'subscribe'
                #@con.addHandler _.bind(@handle.presence.subsciption,@), null, 'presence', 'subscribed'
                #@con.addHandler _.bind(@handle.presence.subsciption,@), null, 'presence', 'unsubscribe'
                #@con.addHandler _.bind(@handle.presence.subsciption,@), null, 'presence', 'unsubscribed'
                
                @con.addHandler _.bind(@handle.presence.subscription,@), null, 'presence'
                @con.addHandler _.bind(@handle.presence.general,@), null, 'presence'
        
                @debug 'Request Roster'
                @requestRoster()
        true
    
    onDisconnected: =>
        # Trigger close on every view
    
    initViews: =>
        _.templateSettings.variable = 'a'
        @views.push new aChatView
            model:@
            id: @get('id')
    
    initDiscoPlugin: =>
        @con.disco.addIdentity 'client', 'web', 'aChat', ''
        @con.disco.addFeature Strophe.NS.CHATSTATES
        @con.caps.node = 'https://github.com/Fuzzyma/aChat'

    removeView: (view) =>
        i = _.indexOf(@views, view) 
        @views[i] = null
        
    requestRoster: =>

        @con.addHandler @initRoster, null, 'iq', 'result', id = @con.getUniqueId()
        
        iq = $iq
            from:@.get('jid'),
            type:'get',
            id:id
        .c('query',{xmlns:Strophe.NS.ROSTER})

        @con.send iq;
        true
        
    initRoster: (msg) =>
        @debug 'Roster arrived';
        
        @roster.reset()
        
        for buddy in msg.getElementsByTagName 'item'
            @roster.add new Buddy
                jid: Strophe.getBareJidFromJid buddy.getAttribute 'jid'
                name: buddy.getAttribute 'name'
                subscription: buddy.getAttribute 'subscription'
                ask: buddy.getAttribute 'ask'
                groups: buddy.getElementsByTagName 'group'

        @debug 'Sending initial Presence!'
        @debug $pres( from: @.get('jid') ).c('c',@con.caps.generateCapsAttrs()).tree()
        @con.send $pres( from: @.get('jid') ).c('c',@con.caps.generateCapsAttrs())
        false
    
    #Creates and send an iq-result-stanza for a special id
    sendResult: (msg) =>
        @con.send $iq
            from: @.get 'jid'
            type: 'result'
            id: msg.getAttribute 'id'
        return
    
    #Send a subscription request to a contact
    subscribe: (jid, msg = '') =>
        @roster.create jid:jid
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'subscribe'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        return
        
    #Approve the subscription request of a contact
    subscribed: (jid, msg = '') =>
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'subscribed'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        return
        
    #Send a unsubscription request to a contact
    unsubscribe: (jid, msg = '') =>
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'unsubscribe'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        return
        
    #Denies the subscription request of a contact
    unsubscribed: (jid, msg = '') =>
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'unsubscribed'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        return
    
    # handler for the stanzas
    handle:
        message:
            chat: (msg) ->
                jid = msg.getAttribute('from')
                buddy = @roster.where(jid:Strophe.xmlescape Strophe.getBareJidFromJid(jid))[0]
                return true if not buddy #Not in List - open own window
                body = msg.getElementsByTagName('body')[0]
                buddy.trigger 'message', Strophe.xmlescape(Strophe.getText(body)), Strophe.getResourceFromJid jid if body
                true
            chatstates: (msg) ->
                buddy = @roster.where(jid:Strophe.xmlescape Strophe.getBareJidFromJid(msg.getAttribute('from')))[0]
                return true if not buddy
                state = msg.lastElementChild || msg.children[msg.children.length-1]
                buddy.trigger 'chatstate', state.nodeName
                true
            thread: (msg) ->
                buddy = @roster.where(jid:Strophe.xmlescape Strophe.getBareJidFromJid(msg.getAttribute('from')))[0]
                return true if not buddy
                thread = msg.getElementsByTagName('thread')
                return true if not thread.length
                buddy.trigger 'thread', Strophe.getText(thread[0]) 
                @debug 'thread triggered'
                true
        error: (msg) ->
            @debug msg
            true
        iq:
            get: (msg) -> 
                return true if Strophe.getBareJidFromJid(msg.getAttribute('to')) isnt @get 'jid'
                true
            set: (msg) -> #This is kinda confusing - it just checks whether the contact exists. If not, it creates a new otherwise it updates the model (includes removing the contact)
                return true if Strophe.getBareJidFromJid(msg.getAttribute('to')) isnt @get 'jid'
                switch msg.getElementsByTagName('query')[0].getAttribute 'xmlns'
                    when Strophe.NS.ROSTER
                        for buddy in msg.getElementsByTagName('item')
                            if (temp = @roster.where(jid:Strophe.getBareJidFromJid buddy.getAttribute 'jid')).length
                                if buddy.getAttribute('subscription') is 'remove'
                                    @roster.remove(temp[0]);
                                    temp[0] = null
                                    break
                                temp[0].set
                                    jid: Strophe.getBareJidFromJid buddy.getAttribute 'jid'
                                    name: buddy.getAttribute 'name'
                                    subscription: buddy.getAttribute 'subscription'
                                    ask: buddy.getAttribute 'ask'
                                    groups: buddy.getElementsByTagName 'group'
                            else
                                @roster.add new Buddy
                                    jid: Strophe.getBareJidFromJid buddy.getAttribute 'jid'
                                    name: buddy.getAttribute 'name'
                                    subscription: buddy.getAttribute 'subscription'
                                    ask: buddy.getAttribute 'ask'
                                    groups: buddy.getElementsByTagName 'group'
                        @sendResult msg

                @debug 'roster push'
                true
        presence:
            unavailable: (msg) ->
                jid = msg.getAttribute 'from'
                buddy = @roster.where(jid:Strophe.getBareJidFromJid jid)[0]
                return true if(!buddy) #if buddy == me or buddy not subscribed
                resources = buddy.get 'resources'
                resources[Strophe.getResourceFromJid jid] = 
                    'show':null
                    'status':Strophe.getText(msg.getElementsByTagName('status')[0]) || null
                    'online':true
                buddy.set 'resources', resources
                if(buddy.get('activeRessource') is Strophe.getResourceFromJid jid)
                    buddy.set 'activeRessource', null
                buddy.trigger 'change:resources'
                true
 
            subscription: (msg) ->
                return true if not msg.getAttribute('type') or msg.getAttribute('type') is 'unavailable'
                jid = Strophe.getBareJidFromJid msg.getAttribute 'from'
                type = msg.getAttribute('type')
                status = msg.getElementsByTagName('status')

                info = @get 'info'
                info = {} if not info
                
                #Important thing. If the contact approved subscription AND request it, we need the request-info not the approve-info
                if(typeof info[jid] isnt 'undefined' and info[jid].type is 'subscribe' and type is 'subscribed')
                    return true
                
                info[jid] = type: type
                info[jid].status = Strophe.getText(status[0]) if status.length
                @set 'info', info
                #@trigger msg.getAttribute('type'), jid
                @trigger 'change:info'
                #subscribe    -> someone requests subscription
                #subscribed   -> somebody subscribed
                #unsubscribe  -> someone denies your subscription
                #unsubscribed -> somebody denyed to subscribe
                true

            #Sets the presence for a special resource
            general: (msg) ->

                return true if msg.getAttribute('type')

                jid = msg.getAttribute 'from'
                buddy = @roster.where(jid:Strophe.getBareJidFromJid jid)[0]
                return true if(!buddy) #if buddy == me or buddy not subscribed

                resources = buddy.get 'resources'
                resources[Strophe.getResourceFromJid jid] = 
                    'show':Strophe.getText(msg.getElementsByTagName('show')[0]) || null  #can be away, chat, dnd or xa
                    'status':Strophe.getText(msg.getElementsByTagName('status')[0]) || null
                    'online':true

                buddy.set 'resources', resources
                buddy.trigger 'change:resources'
                true

    #initialize the strophe-debug, setting the console as debug-output
    initDebug: ->
        #Strophe.log = console.log #too much spam of no interest for now
    
    #class-intern debug-function using the console
    debug: (msg) -> console.log(msg) if @get 'debug'
    
class Buddy extends Backbone.Model
    _.extend(Buddy, Backbone.Events)
    initialize: ->
        new ResourceView model:@ #debugging
        @on 'message', @onMessage
        @on 'chatstate', @onChatstate
        @on 'thread', @onThread
        
        #Thats MOST important here. Every Instance needs his own object.
        #That means that we have to define it here and not in the defaults
        @set 'msg', {}
        @set 'groups', []
            
        #Stuff for debugging
        @on 'change:state', => 
            text = ''
            for i,d of aChat.state
                text += i + ': ' + @checkstate(d) + '<br />'

            $('#flags').html text
            true
        #end
        
        @trigger 'change:state', @
        this
        
    
    defaults:
        jid:null
        name:null
        subscription:null
        ask:null
        groups:null #[] <-- scope Issues - see initializecomment
        resources:{
            ###
            ressource1:
                status:'At work'
                show:'dnd'
                online:true
            ###
        }
        activeResource:null
        msg:null #{} <-- scope Issues - see initializecomment
        state:0
        view:false
        currentChatState:aChat.state.ACTIVE
        thread:null
    
    chatStateTimer:null
    
    onMessage: (msg, resource) =>
        @initView()
        if resource
            @set 'activeResource', resource
            console.log 'Active Resource switched to '+resource
            if(!@get('resources')[resource].online)
                @set 'activeResource', null
                console.log 'Active Resource switched to null'

        msgObj = @get 'msg'
        msgObj[+new Date] = msg
        @set 'msg', msgObj
        @trigger 'change:msg', @
        @set 'state', @get('state') | aChat.state.UPDATE
        true
        
    onChatstate: (state) =>
        @set 'state', @get('state') &~ (aChat.state.ACTIVE | aChat.state.COMPOSING | aChat.state.PAUSED | aChat.state.INACTIVE | aChat.state.GONE) | aChat.state[state.toUpperCase()]
        true
        
    onThread: (thread) =>
        @set 'thread', thread
        @collection.main.debug 'Thread changed to '+thread;
        true
    
    initView: =>
        if not @get 'view' 
            @collection.main.views.push new ChatWindowView model:@
            @set 'state', @get('state') | aChat.state.OPEN
        
    send: (msg = '', chatstate = aChat.state.ACTIVE) =>
        return if not @collection.main.get 'online'
        
        clearTimeout(@chatStateTimer) if @chatStateTimer #we are active - if there is a timer, its the paused, timer. So clear it!
        
        if not @get 'thread'
            @set 'thread',@collection.main.con.getUniqueId()

        resource = ''
        resource = '/' + @get 'activeResource' if @get 'activeResource'
        XMLmsg = $msg
            from: @collection.main.get('jid')
            to: @get('jid')+resource
            type: 'chat'
        .c('body').t(msg).up()
        .c('thread').t(@get 'thread').up()
        
        for state,n of aChat.state
            if n is chatstate
                break
        
        XMLmsg.c(state.toLowerCase(), {xmlns: Strophe.NS.CHATSTATES})
        
        @trigger 'message', msg if msg isnt ''
        
        @collection.main.con.send(XMLmsg)
        @collection.main.debug(XMLmsg)
        true

    checkstate: (state) => (@get('state') & state) is state
        
    changeChatstate: (state = aChat.state.ACTIVE) =>
        
        if not @collection.main.get('chatstates')
            return
        
        if state isnt @currentChatState
            @send null, state
            @currentChatState = state
        
        clearTimeout(@chatStateTimer) if @chatStateTimer
        
        switch state
            when aChat.state.ACTIVE
                $(document).unbind 'mousemove.aChat_chatState'
                futureState = aChat.state.INACTIVE
                timeoutTime = 120000
            when aChat.state.INACTIVE
                $(document).bind 'mousemove.aChat_chatState', => @changeChatstate(aChat.state.ACTIVE)
                return
            when aChat.state.GONE
                return
            when aChat.state.COMPOSING
                futureState = aChat.state.PAUSED
                timeoutTime = 2000
            when aChat.state.PAUSED
                futureState = aChat.state.INACTIVE
                timeoutTime = 120000
                
        @chatStateTimer = setTimeout (=> @changeChatstate(futureState)),timeoutTime
        @
        

class Roster extends Backbone.Collection
    _.extend(Roster, Backbone.Events);
    model:Buddy
    initialize: (col, @main) ->
    
    create: (buddyData) =>
        return false if @where(jid:buddyData.jid).length
        @add buddy = new Buddy
            jid: buddyData.jid
            name: buddyData.name || null
            subscription: buddyData.subscription || 'none'
            ask: buddyData.ask || 'subscribe'
            groups: buddyData.groups || []

        iq = $iq
            from:@main.get('jid'),
            type:'set',
            id:id = @main.con.getUniqueId()
        .c('query', xmlns:Strophe.NS.ROSTER)
        .c 'item',
            jid: buddy.get('jid')
            name: buddy.get('name')
        
        for group in buddy.get('groups')
            iq.c('group').t(group).up()
            
        @main.debug 'Add-Buddy - Request'
        @main.con.send(iq);
        
        buddy
        
    erase: (jid) =>
        iq = $iq
            from:@main.get('jid'),
            type:'set',
            id:id = @main.con.getUniqueId()
        .c('query', xmlns:Strophe.NS.ROSTER)
        .c 'item',
            jid: jid
            subscription: 'remove'
            
        @remove(buddy = @where(jid:jid)[0])
        buddy = null
        @main.debug 'Remove-Buddy - Request'
        @main.con.send(iq);
        @
        

class RosterView extends Backbone.View
    _.extend(RosterView, Backbone.Events);
    initialize: ->
        @listenTo @collection,'add remove',@render
        @listenTo @collection.main, 'change:online',@toggleOnline
        @render() if @collection
        @
    
    render: =>
        @collection.main.debug 'render roster'
        @$el.html('')
        for buddy in @collection.models
            new RosterBuddyView
                model:buddy
                el:$('<li>').appendTo(@$el)
        true
        
    toggleOnline: (e) ->
        #disables/enables all buttons
        

class RosterBuddyView extends Backbone.View
    _.extend(RosterBuddyView, Backbone.Events)
    initialize: ->
        @listenTo @model,'change:status change:show change:msg',@render
        @render() if @model
        @
        
    events:
        'dblclick':'onDblClickBuddy'
        
    render: =>
        @model.collection.main.debug 'render RosterBuddyView'
        template = @model.get('name') || @model.get('jid').split('@')[0]
        this.$el.html( template )
        true
        
    onDblClickBuddy: ->
        @model.initView()
        false
        
        
class aChatView extends Backbone.View
    _.extend(aChatView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'change:info', @info
        @render()
        
    events:
        'change select[name="presenceShow"]':'onChangePresenceShow'
        'keydown input[name="presenceStatus"]':'onKeyDownPresenceStatus'
        'mousedown .aChatView':'onMouseDown'
        'click .aChatView_infoNotifications a':'onClickInfoNotification'
    
    dragdiff:null
    
    info: ->
        @model.debug 'Info arrived'
        ul = @$el.find('.aChatView_infoNotifications')
        if(!@model.get('info'))
            ul.hide()
            return true
            
        ul.html('')
            
        @model.debug @model.get 'info'
        for jid,buddy of @model.get 'info'
            continue if buddy.shown is true
            @model.debug 'not shown'
            html = '<a href="#">'+jid+'</a>'
            switch buddy.type
                when 'subscribe'
                    html += ' requested authorization'
                when 'subscribed'
                    html += ' approved your authorization'
                when 'unsubscribe'
                    html += ' removed your authorization'
                when 'unsubscribed' #If I myself sent unsubscribe i get these presence, too - but then I dont care about it
                    subscribe = @model.roster.where(jid:jid)
                    @model.debug subscribe
                    if(subscribe.length)# and subscribe[0].ask == 'subscribe' doesnt work for a reason :-/
                        html += ' declined your authorization'
                    else
                        continue
                # Todo: add here the handling for normal messages if the user is on dnd
            ul.append $('<li>').append(html)

        ul.show()
        true

    onClickInfoNotification: (e) ->
        e = $.event.fix e
        jid = $(e.target).html()
        info = @model.get 'info'
        info[jid].shown = true
        @model.set 'info', info
        @model.views.push new InfoView model:@model, jid:jid
        @model.trigger 'change:info'
        false
            
    render: ->
        @model.debug 'render aChatView'
        template = $($.trim($("#aChatView").html()))
        @model.views.push new RosterView
            collection:@model.roster
            el:template.find('.RosterView')
        @$el.html(template).appendTo('body') #happens only once
        @

    onChangePresenceShow: ->
        show = @$el.find('select[name="presenceShow"]').val()
        @model.set 'show', show
        switch show
            when 'online'
                if(@model.get 'online')
                    obj = {}
                    if(@model.get('status'))
                        obj.status = @model.get('status')
                    @model.con.send $pres(obj).c('c',@model.con.caps.generateCapsAttrs())
                else
                    @model.connect()
            when 'offline'
                @model.disconnect()
            else
                if(@model.get 'online')
                    obj = show:show
                    obj.show = @model.get 'status' if @model.get 'status'
                    @model.con.send $pres(obj).c('c',@model.con.caps.generateCapsAttrs())
        true
                
    onKeyDownPresenceStatus: (e) ->
        e = $.event.fix e
        if(e.keyCode == 13)
            status = @$el.find('input[name="presenceStatus"]').val()
            @model.set 'status', status
            obj = status:status
            obj.show = @model.get 'show' if @model.get 'show'
            @model.con.send $pres(obj).c('c',@model.con.caps.generateCapsAttrs())
        true
          
    onMouseDown: (e) =>
        e = $.event.fix e
        return true if e.target isnt @$el.find('.aChatView')[0]
        $(document).bind('mouseup.aChat',@onMouseUp)
        $(document).bind('mousemove.aChat',@onMouseMove)
        
        offset = @$el.find('.aChatView').offset()
        
        @dragdiff = 
            x:e.pageX-offset.left
            y:e.pageY-offset.top
        false
            
    onMouseUp: (e) =>
        e = $.event.fix e
        return true if e.target isnt @$el.find('.aChatView')[0]
        @dragdiff = null if @dragdiff
        $(document).unbind('.aChat');
        if @$el.find('.aChatView').offset().top < 0
            @$el.find('.aChatView').css top:0
        false
        
    onMouseMove: (e) =>
        return true if not @dragdiff
        e = $.event.fix e
        @$el.find('.aChatView').css
            left:e.pageX-@dragdiff.x
            top:e.pageY-@dragdiff.y
        false
        
class ChatWindowView extends Backbone.View
    _.extend(ChatWindowView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'change:state', @handleState
        @$el.addClass 'ChatWindowView'
        @render()
        
        
    events:
        'keydown .ChatWindowView_msg':'onKeyDownMsg'
        'click .ChatWindowView_close':'onClickClose'
        'mousedown .ChatWindowView_header':'onMouseDownHeader'
        'mousedown .ChatWindowView_state':'onMouseDownState'
        
    dragdiff:null
        
    handleState: =>
        state = @model.get 'state'
        if not @model.checkstate aChat.state.OPEN
            @close()
        if @model.checkstate aChat.state.CURRENT
            @$el.addClass('active')
        else
            @$el.removeClass('active')
        if @model.checkstate aChat.state.UPDATE
            @$el.addClass('update')
        else
            @$el.removeClass('update')
        if @model.checkstate aChat.state.OPEN && @model.checkstate aChat.state.MINIMIZED
            @minimize()
    
    render: =>
        @model.collection.main.debug 'render ChatWindowView'
        _.templateSettings.variable = "a"
        $template = $(_.template( $.trim($("#ChatWindowView").html()), jid:@model.get('jid') ))
        new MessageView el: $template.filter('.ChatWindowView_chat'), model:@model
        new StateView el: $template.filter('.ChatWindowView_state'), model:@model
        this.$el.html( $template )
        if not @model.get 'view'
            @$el.appendTo('#'+@model.collection.main.get 'id')
            @model.set 'view',true
        true

    close: =>
        @$el.remove()
        @model.set 'view',false
        @model.collection.main.trigger 'removeView', @
        false
        
    minimize: => true
        
    onClickMinimize: ->
        @model.set 'state', @get('state') | aChat.state.MINIMIZED &~ aChat.state.CURRENT
        
    onClickClose: ->
        @model.set 'state', 0
        @model.changeChatstate aChat.state.GONE
        
    onKeyDownMsg: (e) ->
        @model.changeChatstate(aChat.state.COMPOSING)
        if(e.keyCode == 13)
            if e.ctrlKey
                e.target.value = e.target.value + "\n"
                return false
            @model.send(e.target.value)
            e.target.value = ''
            false
            
    onMouseDownHeader: (e) =>
        e = $.event.fix e
        $(document).bind('mouseup.aChat',@onMouseUp)
        $(document).bind('mousemove.aChat',@onMouseMoveHeader)
        
        offset = @$el.offset()
        
        @dragdiff = 
            x:e.pageX-offset.left
            y:e.pageY-offset.top
        false
        
    onMouseDownState: (e) =>
        e = $.event.fix e
        $(document).bind('mouseup.aChat',@onMouseUp)
        $(document).bind('mousemove.aChat',@onMouseMoveState)
        
        offset = $(e.target).offset()

        @dragdiff = 
            x:e.pageX-offset.left
            y:e.pageY-offset.top
        false
            
    onMouseUp: (e) =>
        @dragdiff = null if @dragdiff
        $(document).unbind('.aChat');
        if @$el.offset().top < 0
            @$el.css top:0
        false
        
    onMouseMoveHeader: (e) =>
        return true if not @dragdiff
        e = $.event.fix e
        @$el.css
            left:e.pageX-@dragdiff.x
            top:e.pageY-@dragdiff.y
        false
        
    onMouseMoveState: (e) =>
        return true if not @dragdiff
        e = $.event.fix e
        offset = @$el.find('.ChatWindowView_chat').offset()

        @$el.find('.ChatWindowView_chat').css
            height:(e.pageY-offset.top)-@dragdiff.y-20
        false
        
class MessageView extends Backbone.View
    _.extend(MessageView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'change:msg', @render
        @render()
        @

    render: =>
        @model.collection.main.debug 'render MessageView'
        _.templateSettings.variable = "a"
        $template = _.template( $("#ChatWindowView_chat").html(), @model.get 'msg' )
        @$el.html($template)
        true
        
class StateView extends Backbone.View
    _.extend(StateView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'change:state', @render
        @render()
        @
        
    render: =>
        @model.collection.main.debug 'render StateView'
        text = ''
        if(@model.checkstate aChat.state.COMPOSING)
            text = 'composing'
        if(@model.checkstate aChat.state.PAUSED)
            text = 'paused'
        if(@model.checkstate aChat.state.INACTIVE)
            text = 'inactive'
        if(@model.checkstate aChat.state.GONE)
            text = 'has left the chat'
        @$el.html text
           

class InfoView extends Backbone.View
    _.extend(InfoView, Backbone.Events)
    initialize: (options)->
        @jid = options.jid
        @$el.addClass 'InfoView'
        @render()
    
    events:
        'click input[type="button"][name*="close"]':'onClickClose'
        'click input[type="button"][name*="subscribe"]':'onClickSubscribe'
        'click input[type="button"][name*="subscribed"]':'onClickSubscribed'
        'click input[type="button"][name*="unsubscribe"]':'onClickUnsubscribe'
        'click input[type="button"][name*="unsubscribed"]':'onClickUnsubscribed'
        'click .InfoView_close':'onClickClose'
        'mousedown .InfoView_header':'onMouseDownHeader'
    
    dragdiff:null
    
    render: ->
        info = @model.get('info')[@jid]
        @model.debug info
        templateObj = jid:@jid, buttons:[]
        switch info.type
            when 'subscribe'
                templateObj.infoMsg = @jid + ' requested subscription'
                templateObj.placeholder = 'Hey '+@jid+"!\nI got your request. Please add me, too."
                templateObj.buttons.push value: 'Approve', name: 'subscribed close'
                templateObj.buttons.push value: 'Approve & Subscribe', name: 'subscribed subscribe close'
                templateObj.buttons.push value: 'Decline', name: 'unsubscribed'
            when 'subscribed'
                templateObj.infoMsg = @jid + ' approved your authorization'
                templateObj.placeholder = false
                templateObj.buttons.push value: 'OK', name: 'close'
            #Does this ever happen???
            #when 'unsubscribe'
            #    templateObj.infoMsg = @jid + ' removed your authorization'
            #    templateObj.placeholder = false
            #    templateObj.buttons.push value: 'OK', name: 'unsubscribed close'
            #    templateObj.buttons.push value: 'Deny his authorization, too', name: 'unsubscribed unsubscribe close'
            when 'unsubscribed'
                buddy = @model.roster.where jid:@jid
                templateObj.infoMsg = @jid + ' declined your authorization'
                templateObj.placeholder = false
                templateObj.buttons.push value: 'OK', name: 'close'
                
        if info.show and info.show isnt ''
            templateObj.infoMsg += '<br />Message: '+info.show
        template = _.template($('#InfoView').html(),templateObj)
        @$el.html(template)
        @$el.appendTo('#'+@model.get 'id')
        @
    
    onClickClose: ->
        @$el.remove()
        info = @model.get 'info'
        delete info[@jid]
        @model.set 'info', info
        @model.trigger 'removeView', @
        false
        
    onClickSubscribe: ->
        @model.subscribe(@jid, @$el.find('.InfoView textarea').val())
        false
        
    onClickSubscribed: ->
        @model.subscribed(@jid)
        false
    
    onClickUnsubscribe: ->
        if(@model.roster.where(jid:@jid).length)
            @model.roster.erase(@jid)
        else
            @model.unsubscribe(@jid)
        false
        
    onClickUnsubscribed: ->
        @model.unsubscribed(@jid)
        
    onMouseDownHeader: (e) =>
        e = $.event.fix e
        $(document).bind('mouseup.aChat',@onMouseUp)
        $(document).bind('mousemove.aChat',@onMouseMoveHeader)
        
        offset = @$el.offset()
        
        @dragdiff = 
            x:e.pageX-offset.left
            y:e.pageY-offset.top
        false
            
    onMouseUp: (e) =>
        @dragdiff = null if @dragdiff
        $(document).unbind('.aChat');
        if @$el.offset().top < 0
            @$el.css top:0
        false
        
    onMouseMoveHeader: (e) =>
        return true if not @dragdiff
        e = $.event.fix e
        @$el.css
            left:e.pageX-@dragdiff.x
            top:e.pageY-@dragdiff.y
        false

class ResourceView extends Backbone.View
    _.extend(ResourceView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'change:resources', @render
        @listenTo @model, 'change:msg', @render
        @$el.appendTo('body')
        
    render: =>
        res = @model.get 'resources'
        html = 'active-resource: '+@model.get('jid')+'/'+@model.get('activeResource') + ' -> '
        for i,j of res
            html += i+': '+j.show+' / '+j.status+' / '+j.online + '<br />'
        @$el.html(html)
        
$ ->
    a = new aChat
        jid:'admin@localhost'
        pw:'tree'
        #login:true
        debug:true
        id:'aChat'
        #httpbind:'http://bosh.metajack.im:5280/xmpp-httpbind' #use this to connect to a server of yours