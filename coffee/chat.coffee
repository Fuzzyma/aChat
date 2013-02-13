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
        @initDebug() if @.get('login')
        @initViews()
        this

    #Properties
    @VERSION: '08.02.2013'
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
        

    afkTimer:null
    status: 'active'
    con:null
    roster:null
    views:[]
    
    
    @constants:
        ACTIVE:0
        COMPOSING:1
        PAUSED:2
        INACTIVE:3
        GONE:4
    
    #connects or attachs to the server
    connect: =>
        @con = new Strophe.Connection(@.get('httpbind'))
        if @.get('jid') and @.get('sid') and @.get('rid')
            @con.attach(@.get('jid'),@.get('sid'),@.get('rid'),@onconnect)
            @debug("Attach to session with jid: #{@.get('jid')}, sid: #{@.get('sid')}, rid: #{@.get('rid')}");
        else if @.get('jid') and @.get('pw')
            @con.connect(@.get('jid'),@.get('pw'),@onconnect)
            @debug("Connect to server with jid: #{@.get('jid')}, pw: #{@.get('pw')}");
        
    disconnect: =>
        @set 'online',false
        @con.disconnect()
        
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
                @debug('Connection failed. Try again in 30s'); #Todo: Should be changed later
                setTimeout =>
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
                
                #@con.addHandler _.bind(@handle.presence.unavailable,@), null, 'presence', 'unavailable'
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
        @views.push new RosterView
            collection:@roster
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
    debug: (msg) -> console.log(msg)
    
class Buddy extends Backbone.Model
    _.extend(Buddy, Backbone.Events)
    initialize: ->
        @on 'message', (msg) =>
            console.log msg # only log the message for now and resend to the sender
                            # todo: ChatWindow-View
            if not @get 'view' 
                @collection.main.views.push new ChatWindowView model:@
                @set 'view',true
            msgObj = @get 'msg'
            msgObj[+new Date] = msg
            @set 'msg', msgObj
            @trigger 'change:msg', @
            @set 'state', @get('state') | Buddy.state.UPDATE | Buddy.state.OPEN
            
        @on 'chatstate', (e) =>
            @set('chatstates',e)
            console.log e # log the chatstate
        this
    
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
        
    @state:
        OPEN:     1<<0
        MINIMIZED:1<<1
        ACTIVE:   1<<2
        UPDATE:   1<<3
        ACTIVE:   1<<4
        COMPOSING:1<<5
        PAUSED:   1<<6
        INACTIVE: 1<<7
        GONE:     1<<8
        
        
    send: (msg) =>
        XMLmsg = $msg
            from: @collection.main.get('jid')
            to: @get('jid')
            type: 'chat'
        .c('body').t(msg).up()
        
        XMLmsg.c('active', {xmlns: Strophe.NS.CHATSTATES}) if @chatstates and @collection.main.get('chatstates')
        
        @collection.main.con.send(XMLmsg);
        true
        
        
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
        true
        

class RosterView extends Backbone.View
    _.extend(RosterView, Backbone.Events);
    initialize: ->
        @listenTo @collection,'add remove',@render
        @render() if @collection
        @
    
    events:
        'click .logout':'logout'
    
    render: =>
        @collection.main.debug 'render roster'
        template = $('<ul>');
        for buddy in @collection.models
            new RosterBuddyView
                model:buddy
                el:$('<li>').appendTo(template)
                
        button = ($('<input type="button" value="Log Out" class="logout" />'))
        template = template.add(button)
        this.$el.html( template ).appendTo($('body'))
        true
        
    logout: ->
        @collection.main.disconnect()
        

class RosterBuddyView extends Backbone.View
    _.extend(RosterBuddyView, Backbone.Events)
    initialize: ->
        @listenTo @model,'change',@render
        @render() if @model
        @
    
    render: =>
        @model.collection.main.debug 'render BuddyView'
        _.templateSettings.variable = 'a'
        #template = _.template( $("#rosterView").html(), @model )
        template = @model.get('jid') + ' ( ' + @model.get('name') + ') - ' + @model.get('show') + '/' + @model.get('status')

        this.$el.html( template )
        true
        
class aChatView extends Backbone.View
    _.extend(aChatView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'subscribe subscribed unsubscribe unsubscribed', @info
        @$el = $('body')
        @render()
        
    info: (jid) ->
        @model.views.push new aChatInfoView
        
    @render: ->
        this.$el.html($('<div id="aChat">'))
        
class ChatWindowView extends Backbone.View
    _.extend(aChatView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'change:state', @handleState
        @listenTo @model, 'change:msg', @handleMessage
        @class = '.ChatWindowView'
        #@render()
        
    handleState: =>
        state = @model.get 'state'
        if not @checkstate Buddy.state.OPEN
            @close()
        if @checkstate Buddy.state.ACTIVE
            @$el.addClass('active')
        else
            @$el.removeClass('active')
        if @checkstate Buddy.state.UPDATE
            @$el.addClass('update')
        else
            @$el.removeClass('update')
        if @checkstate Buddy.state.OPEN && @checkstate Buddy.state.MINIMIZED
            @minimize()
    
    render: =>
        $template = $('<span>').append(@model.get('jid')).add($('<ul>'))

        for date,msg of @model.get('msg')
            (time = new Date()).setTime(date)
            $template.filter('ul').append('<li>'+time.getMinutes()+':'+time.getSeconds()+' - '+msg+'</li>')
        this.$el.html( $template ).appendTo('#aChat')
        true
    
    checkstate: (state) =>
        return (@model.get('state') | Buddy.state.OPEN is Buddy.state.OPEN)

    close: =>
        @$el.remove()
        @model.collection.main.trigger 'removeView', @
        
    minimize: => true
    
    handleMessage: =>
        @render()
        true
        
$ ->
    a = new aChat jid:'admin@localhost', pw:'tree', login:true, debug:true, id:'aChat'
