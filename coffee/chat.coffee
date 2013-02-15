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
        @roster = new Roster null, @
        Strophe.addNamespace 'CHATSTATES', 'http://jabber.org/protocol/chatstates'
        @connect() if @.get('login')
        @initDebug() if @.get('debug')
        @initViews()
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
        
    con:null
    roster:null
    views:[]
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
                #@onDisconnected()
            when Strophe.Status.ATTACHED, Strophe.Status.CONNECTED
                @debug('Verbunden');
                
                @set 'online', true
                @con.addHandler ((msg) => @debug(msg); true)
                
                @con.addHandler _.bind(@handle.message.chat,@), null, 'message', 'chat'
                @con.addHandler _.bind(@handle.message.chat,@), null, 'message', 'normal'
                @con.addHandler _.bind(@handle.message.chatstates,@), Strophe.NS.CHATSTATES, 'message'
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
        
    initViews: =>
        @views.push new aChatView
            model:@
            id: @get('id')
        

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
        @con.send $pres( from: @.get('jid') )
        false
    
    #Creates and send an iq-result-stanza for a special id
    sendResult: (msg) =>
        @con.send $iq
            from: @.get 'jid'
            type: 'result'
            id: msg.getAttribute 'id'
        return
    
    #Send a subscription request to a contact
    subscribe: (buddy) =>
        @con.send $pres
            to: Strophe.getBareJidFromJid buddy.get 'jid'
            type: 'subscribe'
            id: @con.getUniqueId()
        return
        
    #Approve the subscription request of a contact
    subscribed: (buddy) =>
        @con.send $pres
            to: Strophe.getBareJidFromJid buddy.get 'jid'
            type: 'subscribed'
            id: @con.getUniqueId()
        return
        
    #Send a unsubscription request to a contact
    unsubscribe: (buddy) =>
        @con.send $pres
            to: Strophe.getBareJidFromJid buddy.get 'jid'
            type: 'unsubscribe'
            id: @con.getUniqueId()
        return
        
    #Denies the subscription request of a contact
    unsubscribed: (buddy) =>
        @con.send $pres
            to: Strophe.getBareJidFromJid buddy.get 'jid'
            type: 'unsubscribed'
            id: @con.getUniqueId()
        return
    
    # handler for the stanzas
    handle:
        message:
            chat: (msg) ->
                buddy = @roster.where(jid:Strophe.xmlescape Strophe.getBareJidFromJid(msg.getAttribute('from')))[0]
                return true if not buddy
                body = msg.getElementsByTagName('body')[0]
                buddy.trigger 'message', Strophe.xmlescape Strophe.getText(body) if body
                true
            chatstates: (msg) ->
                buddy = @roster.where(jid:Strophe.xmlescape Strophe.getBareJidFromJid(msg.getAttribute('from')))[0]
                return true if not buddy
                state = msg.lastElementChild || msg.children[msg.children.length-1]
                buddy.trigger 'chatstate', state.nodeName
                true
        error: (msg) ->
            @debug msg
            true
        iq:
            get: (msg) -> 
                return if Strophe.getBareJidFromJid msg.getAttribute 'jid' isnt @jid
                true
            set: (msg) -> #This is kinda confusing - it just checks whether the contact exists. If not, it creates a new otherwise it updates the model (includes removing the contact)
                return true if Strophe.getBareJidFromJid msg.getAttribute('jid') isnt @jid
                switch msg.getElementsByTagName('query')[0].getAttribute 'xmlns'
                    when Strophe.NS.ROSTER
                        for buddy in msg.getElementsByTagName('item')
                            if (temp = @roster.where(jid:Strophe.getBareJidFromJid buddy.getAttribute 'jid')).length
                                if buddy.getAttribute 'subscription' is 'remove'
                                    @roster.erase temp[0]
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
                buddy = @roster.where(jid:Strophe.getBareJidFromJid msg.getAttribute 'from')[0]
                return true if(!buddy) #if buddy == me or buddy not subscribed
                buddy.set
                    'online':false
                    'status':Strophe.getText(msg.getElementsByTagName('status')[0]) || null
                    'show':null
                true
 
            subscription: (msg) ->
                return true if not msg.getAttribute 'type'
                jid = Strophe.getBareJidFromJid msg.getAttribute 'from'
                @trigger msg.getAttribute('type'), jid
                #subscribe    -> someone requests subscription
                #subscribed   -> somebody subscribed
                #unsubscribe  -> someone denies your subscription
                #unsubscribed -> somebody denyed to subscribe
                true

            general: (msg) ->
                return true if msg.getAttribute('type')
                buddy = @roster.where(jid:Strophe.getBareJidFromJid msg.getAttribute 'from')[0]
                return true if(!buddy) #if buddy == me or buddy not subscribed
                buddy.set
                    'show':Strophe.getText(msg.getElementsByTagName('show')[0]) || null  #can be away, chat, dnd or xa
                    'status':Strophe.getText(msg.getElementsByTagName('status')[0]) || null
                true

    #initialize the strophe-debug, setting the console as debug-output
    initDebug: ->
        #Strophe.log = console.log #too much spam of no interest for now
    
    #class-intern debug-function using the console
    debug: (msg) -> console.log(msg) if @get 'debug'
    
class Buddy extends Backbone.Model
    _.extend(Buddy, Backbone.Events)
    initialize: ->
        @on 'message', (msg) =>
            @initView()
            console.log msg
            msgObj = @get 'msg'
            msgObj[+new Date] = msg
            @set 'msg', msgObj
            @trigger 'change:msg', @
            @set 'state', @get('state') | aChat.state.UPDATE
                        
            
        @on 'chatstate', (state) =>
            @set 'state', @get('state') &~ (aChat.state.ACTIVE | aChat.state.COMPOSING | aChat.state.PAUSED | aChat.state.INACTIVE | aChat.state.GONE) | aChat.state[state.toUpperCase()]
            console.log state # log the chatstate
        
        #Stuff for debugging
        @on 'change:state', => 
            text = ''
            for i,d of aChat.state
                text += i + ': ' + @checkstate(d) + '<br />'

            $('#flags').html text
            
        @trigger 'change:state', @
        this
        #end
    
    initView: =>
        if not @get 'view' 
            @collection.main.views.push new ChatWindowView model:@
            @set 'state', @get('state') | aChat.state.OPEN
    
    defaults:
        jid:null
        name:null
        subscription:null
        ask:null
        groups:[]
        chatstates:false
        status:null
        show:null
        msg:{}
        state:0
        view:false
        currentChatState:aChat.state.ACTIVE
        
    chatStateTimer:null
        
    send: (msg = '', chatstate = aChat.state.ACTIVE) =>
        return if not @collection.main.get 'online'
        XMLmsg = $msg
            from: @collection.main.get('jid')
            to: @get('jid')
            type: 'chat'
        .c('body').t(msg).up()
        
        for state,n of aChat.state
            if n is chatstate
                break
        
        XMLmsg.c(state.toLowerCase(), {xmlns: Strophe.NS.CHATSTATES})# if @chatstates and @collection.main.get('chatstates')
        
        @trigger 'message', msg if msg isnt ''
        
        @collection.main.con.send(XMLmsg);
        true

    checkstate: (state) =>
        #alert(@get('state').toString(2) + ' & ' + state.toString(2) + ' == ' + (@get('state') & state).toString(2) + ' (' + ((@get('state') & state) == state) + ')')
        (@get('state') & state) is state
        
    changeChatstate: (state = aChat.state.ACTIVE) =>
        
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
                timeoutTime = 1000
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
        @add buddy = new Buddy
            jid: buddyData.jid
            name: buddyData.name || null
            subscription: buddyData.subscription || 'none'
            ask: buddyData.ask || 'subscription'
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
        @collection.main.con.send(iq);
        
        buddy
        
    erase: (buddy) =>
        @remove buddy
        iq = $iq
            from:@main.get('jid'),
            type:'set',
            id:id = @main.con.getUniqueId()
        .c('query', xmlns:Strophe.NS.ROSTER)
        .c 'item',
            jid: buddy.get('jid')
            subscription: 'remove'
            
        @main.debug 'Remove-Buddy - Request'
        @collection.main.con.send(iq);
        buddy = null
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
        
    logout: ->
        @collection.main.disconnect()
        
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
        _.templateSettings.variable = 'a'
        #template = _.template( $("#rosterView").html(), @model )
        template = @model.get('name') || @model.get('jid').split('@')[0]
        this.$el.html( template )
        true
        
    onDblClickBuddy: ->
        @model.initView()
        false
        
        
class aChatView extends Backbone.View
    _.extend(aChatView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'subscribe subscribed unsubscribe unsubscribed', @info
        @render()
        
    events:
        'change select[name="presenceStatus"]':'onChangePresenceStatus'
        'keydown input[name="presenceShow"]':'onKeyDownPresenceShow'
        'mousedown .aChatView':'onMouseDown'
    
    dragdiff:null
    
    info: (jid) ->
        #@model.views.push new aChatInfoView #not implemented

    render: ->
        @model.debug 'render aChatView'
        template = $($.trim($("#aChatView").html()))
        @model.views.push new RosterView
            collection:@model.roster
            el:template.find('.RosterView')
        @$el.html(template).appendTo('body') #happens only once

    onChangePresenceStatus: ->
        status = @$el.find('select[name="presenceStatus"]').val()
        @model.set 'status', status
        switch status
            when 'online'
                @model.connect()
            when 'offline'
                @model.disconnect()
            else
                obj = status:status
                obj.show = @model.get 'show' if @model.get 'show'
                @model.con.send $pres obj
                
    onKeyDownPresenceShow: (e) ->
        e = $.event.fix e
        if(e.keyCode == 13)
            show = @$el.find('input[name="presenceShow"]').val()
            @model.set 'show', show
            obj = show:show
            obj.status = @model.get 'status' if @model.get 'status'
            @model.con.send $pres obj
            
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
            this.$el.appendTo('#aChat')
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
            
        
        
$ ->
    a = new aChat
        jid:'admin@localhost'
        pw:'tree'
        #login:true
        debug:true
        id:'aChat'
        #httpbind:'http://bosh.metajack.im:5280/xmpp-httpbind' #use this to connect to a server of yours