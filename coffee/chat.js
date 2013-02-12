// Generated by CoffeeScript 1.4.0
/*
Development-Info
The message stanza can contain a subject-tag. No idea, why a chat should have a subject... its more like a pm then
Thread-tags are for now not included, too. (http://tools.ietf.org/html/rfc6121#section-5.2.5)
*/

var Buddy, Roster, RosterBuddyView, RosterView, aChat,
  __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
  __hasProp = {}.hasOwnProperty,
  __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

aChat = (function(_super) {

  __extends(aChat, _super);

  function aChat() {
    this.unsubscribed = __bind(this.unsubscribed, this);

    this.unsubscribe = __bind(this.unsubscribe, this);

    this.subscribed = __bind(this.subscribed, this);

    this.subscribe = __bind(this.subscribe, this);

    this.sendResult = __bind(this.sendResult, this);

    this.initRoster = __bind(this.initRoster, this);

    this.requestRoster = __bind(this.requestRoster, this);

    this.initViews = __bind(this.initViews, this);

    this.onconnect = __bind(this.onconnect, this);

    this.connect = __bind(this.connect, this);
    return aChat.__super__.constructor.apply(this, arguments);
  }

  _.extend(aChat, Backbone.Events);

  aChat.prototype.initialize = function() {
    this.roster = new Roster(null, this);
    Strophe.addNamespace('CHATSTATES', 'http://jabber.org/protocol/chatstates');
    if (this.get('login')) {
      this.connect();
    }
    if (this.get('login')) {
      this.initDebug();
    }
    this.initViews();
    return this;
  };

  aChat.VERSION = '08.02.2013';

  aChat.prototype.defaults = {
    jid: null,
    sid: null,
    rid: null,
    pw: null,
    httpbind: 'http-bind/',
    login: false,
    debug: false,
    chatstates: true
  };

  aChat.prototype.afkTimer = null;

  aChat.prototype.status = 'active';

  aChat.prototype.con = null;

  aChat.prototype.roster = null;

  aChat.prototype.views = [];

  aChat.constants = {
    ACTIVE: 0,
    COMPOSING: 1,
    PAUSED: 2,
    INACTIVE: 3,
    GONE: 4
  };

  aChat.prototype.connect = function() {
    this.con = new Strophe.Connection(this.get('httpbind'));
    if (this.get('jid') && this.get('sid') && this.get('rid')) {
      this.con.attach(this.get('jid'), this.get('sid'), this.get('rid'), this.onconnect);
      return this.debug("Attach to session with jid: " + (this.get('jid')) + ", sid: " + (this.get('sid')) + ", rid: " + (this.get('rid')));
    } else if (this.get('jid') && this.get('pw')) {
      this.con.connect(this.get('jid'), this.get('pw'), this.onconnect);
      return this.debug("Connect to server with jid: " + (this.get('jid')) + ", pw: " + (this.get('pw')));
    }
  };

  aChat.prototype.onconnect = function(status, error) {
    var _this = this;
    switch (status) {
      case Strophe.Status.ERROR:
        this.debug(error);
        break;
      case Strophe.Status.AUTHENTICATING:
        this.debug('Authenticate');
        break;
      case Strophe.Status.AUTHFAIL:
        this.debug('Authentication failed');
        break;
      case Strophe.Status.CONNECTING:
        this.debug('Connect');
        break;
      case Strophe.Status.CONNFAIL:
        this.debug('Connection failed. Try again in 30s');
        setTimeout(function() {
          return _this.connect();
        }, 1000 * 30);
        break;
      case Strophe.Status.DISCONNECTING:
        this.debug('Abmelden');
        break;
      case Strophe.Status.DISCONNECTED:
        this.debug('Abgemeldet');
        break;
      case Strophe.Status.ATTACHED:
      case Strophe.Status.CONNECTED:
        this.debug('Verbunden');
        this.con.addHandler((function(msg) {
          _this.debug(msg);
          return true;
        }));
        this.con.addHandler(_.bind(this.handle.message.chat, this), null, 'message', 'chat');
        this.con.addHandler(_.bind(this.handle.message.chat, this), null, 'message', 'normal');
        this.con.addHandler(_.bind(this.handle.message.chatstates, this), Strophe.NS.CHATSTATES, 'message');
        this.con.addHandler(_.bind(this.handle.error, this), null, 'error');
        this.con.addHandler(_.bind(this.handle.iq.get, this), null, 'iq', 'get');
        this.con.addHandler(_.bind(this.handle.iq.set, this), null, 'iq', 'set');
        this.con.addHandler(_.bind(this.handle.presence.unavailable, this), null, 'presence', 'unavailable');
        this.con.addHandler(_.bind(this.handle.presence.subscribe, this), null, 'presence', 'subscribe');
        this.con.addHandler(_.bind(this.handle.presence.subscribed, this), null, 'presence', 'subscribed');
        this.con.addHandler(_.bind(this.handle.presence.unsubscribe, this), null, 'presence', 'unsubscribe');
        this.con.addHandler(_.bind(this.handle.presence.unsubscribed, this), null, 'presence', 'unsubscribed');
        this.con.addHandler(_.bind(this.handle.presence.unsubscribed, this), null, 'presence', 'probe');
        this.con.addHandler(_.bind(this.handle.presence.general, this), null, 'presence');
        this.debug('Request Roster');
        this.requestRoster();
    }
    return true;
  };

  aChat.prototype.initViews = function() {
    return this.views.push(new RosterView({
      collection: this.roster,
      id: this.get('id')
    }));
  };

  aChat.prototype.requestRoster = function() {
    var id, iq;
    this.con.addHandler(this.initRoster, null, 'iq', 'result', id = this.con.getUniqueId());
    iq = $iq({
      from: this.get('jid'),
      type: 'get',
      id: id
    }).c('query', {
      xmlns: Strophe.NS.ROSTER
    });
    this.con.send(iq);
    return true;
  };

  aChat.prototype.initRoster = function(msg) {
    var buddy, _i, _len, _ref;
    this.debug('Roster arrived');
    this.roster.reset();
    _ref = msg.getElementsByTagName('item');
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      buddy = _ref[_i];
      this.roster.add(new Buddy({
        jid: Strophe.getBareJidFromJid(buddy.getAttribute('jid')),
        name: buddy.getAttribute('name'),
        subscription: buddy.getAttribute('subscription'),
        ask: buddy.getAttribute('ask'),
        groups: buddy.getElementsByTagName('group')
      }));
    }
    this.debug('Sending initial Presence!');
    this.con.send($pres({
      from: this.get('jid')
    }));
    return false;
  };

  aChat.prototype.sendResult = function(msg) {
    this.con.send($iq({
      from: this.get('jid'),
      type: 'result',
      id: msg.getAttribute('id')
    }));
  };

  aChat.prototype.subscribe = function(buddy) {
    this.con.send($pres({
      to: Strophe.getBareJidFromJid(buddy.get('jid')),
      type: 'subscribe',
      id: this.con.getUniqueId()
    }));
  };

  aChat.prototype.subscribed = function(buddy) {
    this.con.send($pres({
      to: Strophe.getBareJidFromJid(buddy.get('jid')),
      type: 'subscribed',
      id: this.con.getUniqueId()
    }));
  };

  aChat.prototype.unsubscribe = function(buddy) {
    this.con.send($pres({
      to: Strophe.getBareJidFromJid(buddy.get('jid')),
      type: 'unsubscribe',
      id: this.con.getUniqueId()
    }));
  };

  aChat.prototype.unsubscribed = function(buddy) {
    this.con.send($pres({
      to: Strophe.getBareJidFromJid(buddy.get('jid')),
      type: 'unsubscribed',
      id: this.con.getUniqueId()
    }));
  };

  aChat.prototype.handle = {
    message: {
      chat: function(msg) {
        var body, buddy;
        buddy = this.roster.where({
          jid: Strophe.xmlescape(Strophe.getBareJidFromJid(msg.getAttribute('from')))
        })[0];
        if (!buddy) {
          return true;
        }
        body = msg.getElementsByTagName('body')[0];
        if (body) {
          buddy.trigger('message', Strophe.xmlescape(Strophe.getText(body)));
        }
        return true;
      },
      chatstates: function(msg) {
        var buddy, state;
        buddy = this.roster.where({
          jid: Strophe.xmlescape(Strophe.getBareJidFromJid(msg.getAttribute('from')))
        })[0];
        if (!buddy) {
          return true;
        }
        state = msg.lastElementChild || msg.children[msg.children.length - 1];
        buddy.trigger('chatstate', state.nodeName);
        return true;
      }
    },
    error: function(msg) {
      this.debug(Strophe.xmlescape(msg));
      return true;
    },
    iq: {
      get: function(msg) {
        if (Strophe.getBareJidFromJid(msg.getAttribute('jid' !== this.jid))) {
          return;
        }
        return true;
      },
      set: function(msg) {
        var buddy, temp, _i, _len, _ref;
        if (Strophe.getBareJidFromJid(msg.getAttribute('jid') !== this.jid)) {
          return true;
        }
        switch (msg.getElementsByTagName('query')[0].getAttribute('xmlns')) {
          case Strophe.NS.ROSTER:
            _ref = msg.getElementsByTagName('item');
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              buddy = _ref[_i];
              if ((temp = this.roster.where({
                jid: Strophe.getBareJidFromJid(buddy.getAttribute('jid'))
              })).length) {
                if (buddy.getAttribute('subscription' === 'remove')) {
                  this.roster.erase(temp[0]);
                  break;
                }
                temp[0].set({
                  jid: Strophe.getBareJidFromJid(buddy.getAttribute('jid')),
                  name: buddy.getAttribute('name'),
                  subscription: buddy.getAttribute('subscription'),
                  ask: buddy.getAttribute('ask'),
                  groups: buddy.getElementsByTagName('group')
                });
              } else {
                this.roster.add(new Buddy({
                  jid: Strophe.getBareJidFromJid(buddy.getAttribute('jid')),
                  name: buddy.getAttribute('name'),
                  subscription: buddy.getAttribute('subscription'),
                  ask: buddy.getAttribute('ask'),
                  groups: buddy.getElementsByTagName('group')
                }));
              }
            }
            this.sendResult(msg);
        }
        this.debug('roster push');
        this.debug(msg);
        return true;
      }
    },
    presence: {
      unavailable: function(msg) {
        var buddy;
        buddy = this.roster.where({
          jid: Strophe.getBareJidFromJid(msg.getAttribute('from'))
        })[0];
        if (!buddy) {
          return true;
        }
        buddy.set({
          'online': false,
          'status': Strophe.getText(msg.getElementsByTagName('status')[0]) || null
        });
        return true;
      },
      subscribe: function(msg) {
        return true;
      },
      subscribed: function(msg) {
        return true;
      },
      unsubscribe: function(msg) {
        return true;
      },
      unsubscribed: function(msg) {
        return true;
      },
      general: function(msg) {
        var buddy;
        if (msg.getAttribute('type')) {
          return true;
        }
        buddy = this.roster.where({
          jid: Strophe.getBareJidFromJid(msg.getAttribute('from'))
        })[0];
        if (!buddy) {
          return true;
        }
        buddy.set({
          'show': Strophe.getText(msg.getElementsByTagName('show')[0]) || null,
          'status': Strophe.getText(msg.getElementsByTagName('status')[0]) || null
        });
        return true;
      }
    }
  };

  aChat.prototype.initDebug = function() {};

  aChat.prototype.debug = function(msg) {
    return console.log(msg);
  };

  return aChat;

})(Backbone.Model);

Buddy = (function(_super) {

  __extends(Buddy, _super);

  function Buddy() {
    this.send = __bind(this.send, this);
    return Buddy.__super__.constructor.apply(this, arguments);
  }

  _.extend(Buddy, Backbone.Events);

  Buddy.prototype.initialize = function() {
    var _this = this;
    this.on('message', function(e) {
      console.log(e);
      return _this.send(e);
    });
    this.on('chatstate', function(e) {
      _this.chatstates = true;
      return console.log(e);
    });
    return this;
  };

  Buddy.prototype.defaults = {
    jid: null,
    name: null,
    subscription: null,
    ask: null,
    groups: [],
    chatstates: false,
    status: null,
    show: null
  };

  Buddy.prototype.send = function(msg) {
    var XMLmsg;
    XMLmsg = $msg({
      from: this.collection.main.get('jid'),
      to: this.get('jid'),
      type: 'chat'
    }).c('body').t(msg).up();
    if (this.chatstates && this.collection.main.get('chatstates')) {
      XMLmsg.c('active', {
        xmlns: Strophe.NS.CHATSTATES
      });
    }
    this.collection.main.con.send(XMLmsg);
    return true;
  };

  return Buddy;

})(Backbone.Model);

Roster = (function(_super) {

  __extends(Roster, _super);

  function Roster() {
    this.erase = __bind(this.erase, this);

    this.create = __bind(this.create, this);
    return Roster.__super__.constructor.apply(this, arguments);
  }

  _.extend(Roster, Backbone.Events);

  Roster.prototype.model = Buddy;

  Roster.prototype.initialize = function(col, main) {
    this.main = main;
  };

  Roster.prototype.create = function(buddyData) {
    var buddy, group, id, iq, _i, _len, _ref;
    this.add(buddy = new Buddy({
      jid: buddyData.jid,
      name: buddyData.name || null,
      subscription: buddyData.subscription || 'none',
      ask: buddyData.ask || 'subscription',
      groups: buddyData.groups || []
    }));
    iq = $iq({
      from: this.main.get('jid'),
      type: 'set',
      id: id = this.main.con.getUniqueId()
    }).c('query', {
      xmlns: Strophe.NS.ROSTER
    }).c('item', {
      jid: buddy.get('jid'),
      name: buddy.get('name')
    });
    _ref = buddy.get('groups');
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      group = _ref[_i];
      iq.c('group').t(group).up();
    }
    this.main.debug('Add-Buddy - Request');
    this.collection.main.con.send(iq);
    return buddy;
  };

  Roster.prototype.erase = function(buddy) {
    var id, iq;
    this.remove(buddy);
    iq = $iq({
      from: this.main.get('jid'),
      type: 'set',
      id: id = this.main.con.getUniqueId()
    }).c('query', {
      xmlns: Strophe.NS.ROSTER
    }).c('item', {
      jid: buddy.get('jid'),
      subscription: 'remove'
    });
    this.main.debug('Remove-Buddy - Request');
    this.collection.main.con.send(iq);
    buddy = null;
    return true;
  };

  return Roster;

})(Backbone.Collection);

RosterView = (function(_super) {

  __extends(RosterView, _super);

  function RosterView() {
    this.render = __bind(this.render, this);
    return RosterView.__super__.constructor.apply(this, arguments);
  }

  _.extend(Roster, Backbone.Events);

  RosterView.prototype.initialize = function() {
    this.listenTo(this.collection, 'add remove', this.render);
    if (this.collection) {
      this.render();
    }
    return this;
  };

  RosterView.prototype.render = function() {
    var buddy, template, _i, _len, _ref;
    this.collection.main.debug('render roster');
    template = $('<ul>');
    _ref = this.collection.models;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      buddy = _ref[_i];
      new RosterBuddyView({
        model: buddy,
        el: $('<li>').appendTo(template)
      });
    }
    this.$el.html(template).appendTo($('body'));
    return true;
  };

  return RosterView;

})(Backbone.View);

RosterBuddyView = (function(_super) {

  __extends(RosterBuddyView, _super);

  function RosterBuddyView() {
    this.render = __bind(this.render, this);
    return RosterBuddyView.__super__.constructor.apply(this, arguments);
  }

  _.extend(Roster, Backbone.Events);

  RosterBuddyView.prototype.initialize = function() {
    this.listenTo(this.model, 'change', this.render);
    if (this.model) {
      this.render();
    }
    return this;
  };

  RosterBuddyView.prototype.render = function() {
    var template;
    this.model.collection.main.debug('render BuddyView');
    _.templateSettings.variable = 'a';
    template = this.model.get('jid') + ' ( ' + this.model.get('name') + ') - ' + this.model.get('show') + '/' + this.model.get('status');
    this.$el.html(template);
    return true;
  };

  return RosterBuddyView;

})(Backbone.View);

$(function() {
  var a;
  return a = new aChat({
    jid: 'admin@localhost',
    pw: 'tree',
    login: true,
    debug: true,
    id: 'aChat'
  });
});