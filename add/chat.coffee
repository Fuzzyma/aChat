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
                @con.addHandler _.bind(@handle.presence.subscribe,@), null, 'presence', 'subscribe'
                @con.addHandler _.bind(@handle.presence.subscribed,@), null, 'presence', 'subscribed'
                @con.addHandler _.bind(@handle.presence.unsubscribe,@), null, 'presence', 'unsubscribe'
                @con.addHandler _.bind(@handle.presence.unsubscribed,@), null, 'presence', 'unsubscribed'
                @con.addHandler _.bind(@handle.presence.unsubscribed,@), null, 'presence', 'probe'
        
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
            @debug Strophe.xmlescape msg
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
                @debug msg
                true
        presence:
            unavailable: (msg) ->
                buddy = @roster.where(jid:Strophe.getBareJidFromJid msg.getAttribute 'from')[0]
                return true if(!buddy) #if buddy == me or buddy not subscribed
                buddy.set
                    'online':false
                    'status':Strophe.getText(msg.getElementsByTagName('status')[0]) || null
                true
 
            #Todo: !!If the contact isnt in the roster, show the presence in the chat window!!
            subscribe: (msg) ->
                #Todo: someone requests subscription. Ask the user to approve or denie!
                true
            subscribed: (msg) ->
                #Todo: somebody subscribed - maybe show an infading info
                true
            unsubscribe: (msg) -> true
                #Todo: someone denies your subscription. Ask the user what to do (remove, too or request again?)
            unsubscribed: (msg) -> true
                #Todo: somebody denyed to subscribe - again an info
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
        @on 'message', (e) =>
            console.log e # only log the message for now and resend to the sender
                          # todo: ChatWindow-View
            @send(e)
            
        @on 'chatstate', (e) =>
            @chatstates = true
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
    _.extend(Roster, Backbone.Events);
    initialize: ->
        #@$el = $('<div id="aChat">')
        @listenTo @collection,'add remove',@render
        @render() if @collection
        @
    
    
    render: =>
        @collection.main.debug 'render roster'
        template = $('<ul>');
        for buddy in @collection.models
            new RosterBuddyView
                model:buddy
                el:$('<li>').appendTo(template)
        this.$el.html( template ).appendTo($('body'))
        true

class RosterBuddyView extends Backbone.View
    _.extend(Roster, Backbone.Events);
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
$ ->
    a = new aChat jid:'admin@localhost', pw:'tree', login:true, debug:true, id:'aChat'
