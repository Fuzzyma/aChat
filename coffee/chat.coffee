#coffee -cwb chat.coffee

###
Development-Info
The message stanza can contain a subject-tag. No idea, why a chat should have a subject... its more like a pm then
###

class aChat extends Backbone.Model

    _.extend(aChat, Backbone.Events);

    # Initialize the Chat
    initialize: ->
        Backbone.sync = ->
        @views = []
        @roster = new Roster null, @
        @initViews()
        
        Strophe.addNamespace 'CHATSTATES', 'http://jabber.org/protocol/chatstates'
        
        # If autologin: connect
        if @.get('login')
            @connect() 
        
        # Since the aChat model stores all main-views, we have events for this
        @on 'addView', @addView
        @on 'removeView', @removeView
        this

    # Public Properties
    @VERSION: '18.02.2013'
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
        id:'aChat'
    
    # Private Properties #TODO: rename to _variable
    con:null
    roster:null
    views:null #[] <-- scoping issues
    loginTimeout:null
    
    #Constants
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
    
    # Creates a new Connection-Object and create a new Session or attachs to it
    connect: =>
        # Don't connect if we already online
        return @ if @get 'online'
        
        @set 'online',true
        
        @con = new Strophe.Connection(@.get('httpbind'))

        if @.get('jid') and @.get('sid') and @.get('rid')
            @con.attach(@.get('jid'),@.get('sid'),@.get('rid'),@onConnect)
            @debug("Attach to session with jid: #{@.get('jid')}, sid: #{@.get('sid')}, rid: #{@.get('rid')}");
        else if @.get('jid') and @.get('pw')
            @con.connect(@.get('jid'),@.get('pw'),@onConnect)
            @debug("Connect to server with jid: #{@.get('jid')}, pw: #{@.get('pw')}");
        
        # The discoplugin needs a connection-object. Thats why we have no initialize it here
        @initDiscoPlugin()
        @
    

    disconnect: =>
        # Don't disconnect if we already offline
        return @ if not @get 'online'
        
        @set 'online',false
        
        # Clears the Timer and disconnect from the server
        clearTimeout @loginTimeout if @loginTimeout
        @con.disconnect('Offline')
        @
    
    onConnect: (status, error) =>
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
                    @connect() #TODO: Is this feature rly needed? I don't like it...
                ,1000*30
            when Strophe.Status.DISCONNECTING
                @debug('Abmelden');
            when Strophe.Status.DISCONNECTED
                @debug('Abgemeldet');
                @onDisconnected()
            when Strophe.Status.ATTACHED, Strophe.Status.CONNECTED
                @debug('Verbunden');
                
                # Debug handler - prints every stanza to the console
                @con.addHandler ((msg) => @debug(msg); true) if @get 'debug'
                
                # Handler for incoming messages includes chatstates and thread-handling
                @con.addHandler _.bind(@handle.message.chat,@), null, 'message', 'chat'
                @con.addHandler _.bind(@handle.message.chat,@), null, 'message', 'normal'
                @con.addHandler _.bind(@handle.message.chatstates,@), Strophe.NS.CHATSTATES, 'message'
                @con.addHandler _.bind(@handle.message.thread,@), null, 'thread'
                #@con.addHandler _.bind(@handle.message.groupchat, null, 'message', 'groupchat'# for now we will ignore groupchat
                
                # Error-handler
                @con.addHandler _.bind(@handle.error,@), null, 'error'
                
                # Iq-Handlers (one get and one set, errors ignored)
                @con.addHandler _.bind(@handle.iq.get,@), null, 'iq', 'get'
                @con.addHandler _.bind(@handle.iq.set,@), null, 'iq', 'set'
                #@con.addHandler _.bind(@handle.iq.error,@), null, 'iq', 'error'# for now we will ignore iq-errors
                
                # Handling the difference Presence-Types. General is general presence (status and show)
                @con.addHandler _.bind(@handle.presence.unavailable,@), null, 'presence', 'unavailable'
                @con.addHandler _.bind(@handle.presence.subscription,@), null, 'presence'
                @con.addHandler _.bind(@handle.presence.general,@), null, 'presence'
        
                # Calling the function to request the roster from the server
                @debug 'Request Roster'
                @requestRoster()
        true
    
    # Removes all views except the aChatView
    onDisconnected: =>
        for i in @views
            @trigger 'removeView', i
        true
    
    # Sets global settings for the templates and creates the main-view
    initViews: =>
        #Sets the lodash-templatevariable to a for easier template-writing
        _.templateSettings.variable = 'a'
        
        #Create the View for the Chat (this view includes the roster and other views)
        @trigger 'addView', new aChatView(model:@,id:@get('id'))
        @
    
    # Add our identity and the features to the discoPlugin
    initDiscoPlugin: =>
        @con.disco.addIdentity 'client', 'web', 'aChat '+aChat.VERSION, ''
        @con.disco.addFeature Strophe.NS.CHATSTATES
        @con.caps.node = 'https://github.com/Fuzzyma/aChat'
        @

    # Removes the given View
    removeView: (view) =>
        @debug 'view removed'
        @debug view
        i = _.indexOf(@views, view) 
        @views[i].remove()
        @views[i] = null
        @
    
    # Adds the given View
    addView: (view) =>
        @debug 'view added'
        @debug view
        @views.push view
        @
    
    # Requests the Roster from the server sending an iq-stanza of type 'get'
    requestRoster: =>
        
        # Adds a handler to handle this special id
        @con.addHandler @initRoster, null, 'iq', 'result', id = @con.getUniqueId()
        
        # Create the stanza
        iq = $iq
            from:@.get('jid'),
            type:'get',
            id:id
        .c('query',{xmlns:Strophe.NS.ROSTER})

        @con.send iq;
        true
        
    initRoster: (msg) =>
        #Reset the roster-collection
        @roster.reset() #TODO: Prove if models destroyed
        
        # Add a new Buddy to the roster for every item in the stanza
        for buddy in msg.getElementsByTagName 'item'
            @roster.create
                jid: Strophe.getBareJidFromJid buddy.getAttribute 'jid'
                name: buddy.getAttribute 'name'
                subscription: buddy.getAttribute 'subscription'
                ask: buddy.getAttribute 'ask'
                groups: buddy.getElementsByTagName 'group'

        # Send initial presence including the caps-attribute
        @debug 'Sending initial Presence!'
        @con.send $pres( from: @.get('jid') ).c('c',@con.caps.generateCapsAttrs())
        false
    
    # Creates and send an iq-result-stanza for a special id
    sendResult: (msg) =>
        @con.send $iq
            from: @.get 'jid'
            type: 'result'
            id: msg.getAttribute 'id'
        return
    
    # Send a subscription request to a contact
    subscribe: (jid, msg = '') =>
        @roster.createNew jid:jid
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'subscribe'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        @
        
    # Approve the subscription request of a contact
    subscribed: (jid, msg = '') =>
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'subscribed'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        @
        
    # Send a unsubscription request to a contact
    unsubscribe: (jid, msg = '') =>
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'unsubscribe'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        @
        
    # Denies the subscription request of a contact
    unsubscribed: (jid, msg = '') =>
        @con.send $pres(
            to: Strophe.getBareJidFromJid jid
            type: 'unsubscribed'
            id: @con.getUniqueId()
        ).c('status').t(msg).up().c('c',@con.caps.generateCapsAttrs())
        @
    
    # handler for the stanzas
    handle:
        message:
            chat: (msg) ->
                jid = msg.getAttribute('from')
                buddy = @roster.where(jid:Strophe.getBareJidFromJid(jid))[0]
                
                return true if not buddy #TODO: Not in List - open own window
                
                # Don't do anything if there is no body
                body = msg.getElementsByTagName('body')[0]
                #buddy.trigger 'message', Strophe.xmlescape(Strophe.getText(body)), Strophe.getResourceFromJid jid if body
                buddy.trigger 'message', Strophe.getText(body), Strophe.getResourceFromJid jid if body
                true
            
            chatstates: (msg) ->
                buddy = @roster.where(jid:Strophe.getBareJidFromJid(msg.getAttribute('from')))[0]
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
                true
        
        # Just debug the error
        error: (msg) ->
            @debug msg
            true

        iq:
            # I don't know any get-request - so...
            get: (msg) -> 
                return true if Strophe.getBareJidFromJid(msg.getAttribute('to')) isnt @get 'jid'
                true
                
            # do your action depending on the namespace
            set: (msg) ->
                #if this iq is not for us - ignore it (security issue)
                return true if Strophe.getBareJidFromJid(msg.getAttribute('to')) isnt @get 'jid'
                
                # For every namespace another action (till now only roster-set)
                switch msg.getElementsByTagName('query')[0].getAttribute 'xmlns'
                    when Strophe.NS.ROSTER
                        # Loop trough the items
                        for buddy in msg.getElementsByTagName('item')
                            
                            # If the buddy already exists in the roster
                            if (temp = @roster.where(jid:Strophe.getBareJidFromJid buddy.getAttribute 'jid')).length
                                
                                # delete it if it should be removed
                                if buddy.getAttribute('subscription') is 'remove'
                                    @roster.remove(temp[0]);
                                    temp[0] = null
                                    break
                                    
                                # otherwise udate it
                                temp[0].set
                                    jid: Strophe.getBareJidFromJid buddy.getAttribute 'jid'
                                    name: buddy.getAttribute 'name'
                                    subscription: buddy.getAttribute 'subscription'
                                    ask: buddy.getAttribute 'ask'
                                    groups: buddy.getElementsByTagName 'group'
                            
                            # if not, create it
                            else
                                @roster.create
                                    jid: Strophe.getBareJidFromJid buddy.getAttribute 'jid'
                                    name: buddy.getAttribute 'name'
                                    subscription: buddy.getAttribute 'subscription'
                                    ask: buddy.getAttribute 'ask'
                                    groups: buddy.getElementsByTagName 'group'
                        
                        # Answer in every case with a result
                        @sendResult msg

                @debug 'roster push'
                true

        presence:
            unavailable: (msg) ->
                jid = msg.getAttribute 'from'
                buddy = @roster.where(jid:Strophe.getBareJidFromJid jid)[0]
                
                # We don't care for unavailability of buddys who are not in our roster # TODO: maybe later
                return true if(!buddy) #if buddy == me or buddy not subscribed
                
                # Set the special resource to offline.
                resources = buddy.get 'resources'
                resources[Strophe.getResourceFromJid jid] = 
                    'show':null
                    'status':Strophe.getText(msg.getElementsByTagName('status')[0]) || null
                    'online':false
                buddy.set 'resources', resources
                
                # If this resource was the active one, make all other resources active
                if(buddy.get('activeRessource') is Strophe.getResourceFromJid jid)
                    buddy.set 'activeRessource', null

                buddy.trigger 'change:resources'
                true
 
            subscription: (msg) ->
                # return if message is not for this handler
                return true if not msg.getAttribute('type') or msg.getAttribute('type') is 'unavailable'
                
                # scrap all data we need
                jid = Strophe.getBareJidFromJid msg.getAttribute 'from'
                type = msg.getAttribute('type')
                status = msg.getElementsByTagName('status')

                info = @get 'info'
                info = {} if not info
                
                # Important thing. If the contact approved subscription AND request it, we need the request-info not the approve-info
                if(typeof info[jid] isnt 'undefined' and info[jid].type is 'subscribe' and type is 'subscribed')
                    return true
                
                # Add an info, that someone did some subscriptin-stuff on you
                info[jid] = type: type
                info[jid].status = Strophe.getText(status[0]) if status.length
                @set 'info', info
                @trigger 'change:info'
                true

            # Sets the presence for a special resource
            general: (msg) ->
                # return if message is not for this handler
                return true if msg.getAttribute('type')

                jid = msg.getAttribute 'from'
                buddy = @roster.where(jid:Strophe.getBareJidFromJid jid)[0]
                
                # We don't care for availability of buddys who are not in our roster # TODO: maybe later
                return true if(!buddy) #if buddy == me or buddy not subscribed

                # Set the resource to online
                resources = buddy.get 'resources'
                resources[Strophe.getResourceFromJid jid] = 
                    'show':Strophe.getText(msg.getElementsByTagName('show')[0]) || null  #can be away, chat, dnd or xa
                    'status':Strophe.getText(msg.getElementsByTagName('status')[0]) || null
                    'online':true

                buddy.set 'resources', resources
                buddy.trigger 'change:resources'
                true
    
    # Debug-function - routes all messages to the console if debug is active
    debug: (msg) -> console.log(msg) if @get 'debug'
    
    
    
    
###
This Model represents one special Buddy.
It manages messages, chatsstates and threads of this buddy.
###
class Buddy extends Backbone.Model
    _.extend(Buddy, Backbone.Events)
    initialize: ->
        # Debug-View shows the resources of a buddy
        new ResourceView model:@ #debugging
        
        # Listen to message, chatstates and threads triggered in this instance
        @on 'message', @onMessage
        @on 'chatstate', @onChatstate
        @on 'thread', @onThread
        
        # Thats MOST important here. Every Instance needs his own object.
        # That means that we have to define it here and not in the defaults
        @set 'msg', {}
        @set 'groups', []
            
        # Debugging - prints the state of an instance
        @on 'change:state', => 
            text = ''
            for i,d of aChat.state
                text += i + ': ' + @checkstate(d) + '<br />'

            $('#flags').html text
            true
        #end
        
        @trigger 'change:state', @
        @
        
    # Public Properties
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
    
    # Private Properties
    chatStateTimer:null
    
    # Called if a message arrived
    onMessage: (msg, resource) =>
        @initView()

        # If a resource is given
        if resource
            @set 'activeResource', resource
            console.log 'Active Resource switched to '+resource
            
            # TODO: I have to take a look on this - a bit wired if there comes an offline message
            if(typeof @get('resources')[resource] isnt 'undefined' && @get('resources')[resource].online)
                @set 'activeResource', null
                console.log 'Active Resource switched to null'

        msgObj = @get 'msg'
        msgObj[+new Date] = msg
        @set 'msg', msgObj
        @trigger 'change:msg', @
        
        @set 'state', @get('state') | aChat.state.UPDATE
        true
    
    # Sets the Chatstate
    onChatstate: (state) =>
        @set 'state', @get('state') &~ (aChat.state.ACTIVE | aChat.state.COMPOSING | aChat.state.PAUSED | aChat.state.INACTIVE | aChat.state.GONE) | aChat.state[state.toUpperCase()]
        true
        
    # Changes the thread
    onThread: (thread) =>
        @set 'thread', thread
        @collection.main.debug 'Thread changed to '+thread;
        true
    
    # Initialize the view
    initView: =>
        if not @get 'view' 
            @set 'view', true
            @collection.main.trigger 'addView', new ChatWindowView model:@
            @set 'state', @get('state') | aChat.state.OPEN
        
    # Sends a message to the ative resource, if there is one. Otherwise to the contacts jid
    send: (msg = '', chatstate = aChat.state.ACTIVE) =>
    
        # Don't send everything if we aren't online
        return if not @collection.main.get 'online'
        
        # Sending a message means we are active. Without any timer. Clear it!
        clearTimeout(@chatStateTimer) if @chatStateTimer
        
        # If no thread is given we create a new
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
        
        # Get the keyword for the chatstate (active, composing...)
        for state,n of aChat.state
            if n is chatstate
                break
        
        XMLmsg.c(state.toLowerCase(), {xmlns: Strophe.NS.CHATSTATES})
        
        # If there is no message we just send only the chatstate
        @trigger 'message', msg if msg isnt ''
        
        @collection.main.con.send(XMLmsg.tree())
        @collection.main.debug(XMLmsg)
        true

    # Checks a special state (bit-check)
    checkstate: (state) => (@get('state') & state) is state
    
    # Changes the chatstate to the new one and may set a timer for special states like composing and inactive
    changeChatstate: (state = aChat.state.ACTIVE) =>
        
        # Chatstates are forbidden (from the user) - dont send them
        if not @collection.main.get('chatstates')
            return
        
        # Only send if state differs from the previous one
        if state isnt @currentChatState
            @send null, state
            @currentChatState = state
        
        # Since we have a new state, clear the timer 
        clearTimeout(@chatStateTimer) if @chatStateTimer
        
        # Do your action for the special state
        switch state
            when aChat.state.ACTIVE
                $(document).unbind 'mousemove.aChat_chatState'
                futureState = aChat.state.INACTIVE
                timeoutTime = 120000
            when aChat.state.INACTIVE
                # If the user moves the mouse he isnt longer inactive
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
        

###
This collection contains all Buddy-Models.
It can create new Buddys or erase Buddys
from ther server roster
###
class Roster extends Backbone.Collection
    _.extend(Roster, Backbone.Events);
    model:Buddy
    
    # Set the aChat-Model as reference - we need it often
    initialize: (col, @main) ->
        @on 'reset', @destroyModels
    
    # Destroys all Models
    destroyModels: (a, oldModels) =>
        for model in oldModels
            model.destroy()
            model = null
    
    # Create a new Buddy in the server-roster
    createNew: (buddyData) =>
        # retun if user is in roster
        return false if @where(jid:buddyData.jid).length
        
        # Add the buddy to the collection
        buddy = @create
            jid: buddyData.jid
            name: buddyData.name || null
            subscription: buddyData.subscription || 'none'
            ask: buddyData.ask || 'subscribe'
            groups: buddyData.groups || []

        # Build the stanza to add the buddy to the server-roster
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
        
        # return the new buddy
        buddy
    
    # Erases a buddy from the server-roster and removes it from the collection
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
        @views = []
        @listenTo @collection,'add remove',@render
        @render() if @collection
        @
    
    views:null
    
    render: =>
        @collection.main.debug 'render roster'
        @$el.html('')
        for buddy in @collection.models
            @views.push new RosterBuddyView
                model:buddy
                el:$('<li>').appendTo(@$el)
        @
        
    remove: =>
        for i in @views
            i.remove()
            i = null
        @$el.html('')
        @stopListening()
        @
        

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
        @
        
    onDblClickBuddy: ->
        @model.initView()
        false
        
        
class aChatView extends Backbone.View
    _.extend(aChatView, Backbone.Events)
    initialize: ->
        @listenTo @model, 'change:info', @info
        @listenTo @model, 'change:online', @changeOnline
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
        @

    changeOnline: =>
        status = 'offline'
        status = 'online' if @model.get('online')
        @$el.find('select[name="presenceShow"]').val(status)
        @
        
    remove: (confirm = false) =>
        return @ if !confirm
        @$el.remove()
        @stopListening()
        @
        
    onClickInfoNotification: (e) ->
        e = $.event.fix e
        jid = $(e.target).html()
        info = @model.get 'info'
        info[jid].shown = true
        @model.set 'info', info
        @model.trigger 'addView', new InfoView(model:@model, jid:jid)
        @model.trigger 'change:info'
        false
            
    render: ->
        @model.debug 'render aChatView'
        template = $($.trim($("#aChatView").html()))
        @model.trigger 'addView', new RosterView(
        #@model.views.push new RosterView(
            collection:@model.roster
            el:template.find('.RosterView')
        )
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
                    obj.status = @model.get 'status' if @model.get 'status'
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
        @views = []
        @listenTo @model, 'change:state', @handleState
        @$el.addClass 'ChatWindowView'
        @render()
        @
        
        
    events:
        'keydown .ChatWindowView_msg':'onKeyDownMsg'
        'click .ChatWindowView_close':'onClickClose'
        'mousedown .ChatWindowView_header':'onMouseDownHeader'
        'mousedown .ChatWindowView_state':'onMouseDownState'
        
    dragdiff:null
    views:null
        
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
        @views.push = new MessageView el: $template.filter('.ChatWindowView_chat'), model:@model
        @views.push = new StateView el: $template.filter('.ChatWindowView_state'), model:@model
        this.$el.html( $template )
        @$el.appendTo('#'+@model.collection.main.get 'id')
        @
        
    remove: =>
        for i in @views
            i.remove()
        @$el.remove()
        @stopListening()
        @

    close: =>
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
        true
            
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
        @
    
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
        
    remove: ->
        @$el.html('')
        @stopListening()
        @
    
    onClickClose: ->
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
        @
        
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
        login:true
        debug:true
        id:'aChat'
        #httpbind:'http://bosh.metajack.im:5280/xmpp-httpbind' #use this to connect to a server of yours