var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __commonJS = (cb, mod) => function __require() {
  return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));

// node_modules/events/events.js
var require_events = __commonJS({
  "node_modules/events/events.js"(exports, module) {
    "use strict";
    var R = typeof Reflect === "object" ? Reflect : null;
    var ReflectApply = R && typeof R.apply === "function" ? R.apply : function ReflectApply2(target, receiver, args) {
      return Function.prototype.apply.call(target, receiver, args);
    };
    var ReflectOwnKeys;
    if (R && typeof R.ownKeys === "function") {
      ReflectOwnKeys = R.ownKeys;
    } else if (Object.getOwnPropertySymbols) {
      ReflectOwnKeys = function ReflectOwnKeys2(target) {
        return Object.getOwnPropertyNames(target).concat(Object.getOwnPropertySymbols(target));
      };
    } else {
      ReflectOwnKeys = function ReflectOwnKeys2(target) {
        return Object.getOwnPropertyNames(target);
      };
    }
    function ProcessEmitWarning(warning) {
      if (console && console.warn) console.warn(warning);
    }
    var NumberIsNaN = Number.isNaN || function NumberIsNaN2(value) {
      return value !== value;
    };
    function EventEmitter2() {
      EventEmitter2.init.call(this);
    }
    module.exports = EventEmitter2;
    module.exports.once = once;
    EventEmitter2.EventEmitter = EventEmitter2;
    EventEmitter2.prototype._events = void 0;
    EventEmitter2.prototype._eventsCount = 0;
    EventEmitter2.prototype._maxListeners = void 0;
    var defaultMaxListeners = 10;
    function checkListener(listener) {
      if (typeof listener !== "function") {
        throw new TypeError('The "listener" argument must be of type Function. Received type ' + typeof listener);
      }
    }
    Object.defineProperty(EventEmitter2, "defaultMaxListeners", {
      enumerable: true,
      get: function() {
        return defaultMaxListeners;
      },
      set: function(arg) {
        if (typeof arg !== "number" || arg < 0 || NumberIsNaN(arg)) {
          throw new RangeError('The value of "defaultMaxListeners" is out of range. It must be a non-negative number. Received ' + arg + ".");
        }
        defaultMaxListeners = arg;
      }
    });
    EventEmitter2.init = function() {
      if (this._events === void 0 || this._events === Object.getPrototypeOf(this)._events) {
        this._events = /* @__PURE__ */ Object.create(null);
        this._eventsCount = 0;
      }
      this._maxListeners = this._maxListeners || void 0;
    };
    EventEmitter2.prototype.setMaxListeners = function setMaxListeners(n) {
      if (typeof n !== "number" || n < 0 || NumberIsNaN(n)) {
        throw new RangeError('The value of "n" is out of range. It must be a non-negative number. Received ' + n + ".");
      }
      this._maxListeners = n;
      return this;
    };
    function _getMaxListeners(that) {
      if (that._maxListeners === void 0)
        return EventEmitter2.defaultMaxListeners;
      return that._maxListeners;
    }
    EventEmitter2.prototype.getMaxListeners = function getMaxListeners() {
      return _getMaxListeners(this);
    };
    EventEmitter2.prototype.emit = function emit(type) {
      var args = [];
      for (var i = 1; i < arguments.length; i++) args.push(arguments[i]);
      var doError = type === "error";
      var events = this._events;
      if (events !== void 0)
        doError = doError && events.error === void 0;
      else if (!doError)
        return false;
      if (doError) {
        var er;
        if (args.length > 0)
          er = args[0];
        if (er instanceof Error) {
          throw er;
        }
        var err = new Error("Unhandled error." + (er ? " (" + er.message + ")" : ""));
        err.context = er;
        throw err;
      }
      var handler = events[type];
      if (handler === void 0)
        return false;
      if (typeof handler === "function") {
        ReflectApply(handler, this, args);
      } else {
        var len = handler.length;
        var listeners = arrayClone(handler, len);
        for (var i = 0; i < len; ++i)
          ReflectApply(listeners[i], this, args);
      }
      return true;
    };
    function _addListener(target, type, listener, prepend) {
      var m;
      var events;
      var existing;
      checkListener(listener);
      events = target._events;
      if (events === void 0) {
        events = target._events = /* @__PURE__ */ Object.create(null);
        target._eventsCount = 0;
      } else {
        if (events.newListener !== void 0) {
          target.emit(
            "newListener",
            type,
            listener.listener ? listener.listener : listener
          );
          events = target._events;
        }
        existing = events[type];
      }
      if (existing === void 0) {
        existing = events[type] = listener;
        ++target._eventsCount;
      } else {
        if (typeof existing === "function") {
          existing = events[type] = prepend ? [listener, existing] : [existing, listener];
        } else if (prepend) {
          existing.unshift(listener);
        } else {
          existing.push(listener);
        }
        m = _getMaxListeners(target);
        if (m > 0 && existing.length > m && !existing.warned) {
          existing.warned = true;
          var w = new Error("Possible EventEmitter memory leak detected. " + existing.length + " " + String(type) + " listeners added. Use emitter.setMaxListeners() to increase limit");
          w.name = "MaxListenersExceededWarning";
          w.emitter = target;
          w.type = type;
          w.count = existing.length;
          ProcessEmitWarning(w);
        }
      }
      return target;
    }
    EventEmitter2.prototype.addListener = function addListener(type, listener) {
      return _addListener(this, type, listener, false);
    };
    EventEmitter2.prototype.on = EventEmitter2.prototype.addListener;
    EventEmitter2.prototype.prependListener = function prependListener(type, listener) {
      return _addListener(this, type, listener, true);
    };
    function onceWrapper() {
      if (!this.fired) {
        this.target.removeListener(this.type, this.wrapFn);
        this.fired = true;
        if (arguments.length === 0)
          return this.listener.call(this.target);
        return this.listener.apply(this.target, arguments);
      }
    }
    function _onceWrap(target, type, listener) {
      var state = { fired: false, wrapFn: void 0, target, type, listener };
      var wrapped = onceWrapper.bind(state);
      wrapped.listener = listener;
      state.wrapFn = wrapped;
      return wrapped;
    }
    EventEmitter2.prototype.once = function once2(type, listener) {
      checkListener(listener);
      this.on(type, _onceWrap(this, type, listener));
      return this;
    };
    EventEmitter2.prototype.prependOnceListener = function prependOnceListener(type, listener) {
      checkListener(listener);
      this.prependListener(type, _onceWrap(this, type, listener));
      return this;
    };
    EventEmitter2.prototype.removeListener = function removeListener(type, listener) {
      var list, events, position, i, originalListener;
      checkListener(listener);
      events = this._events;
      if (events === void 0)
        return this;
      list = events[type];
      if (list === void 0)
        return this;
      if (list === listener || list.listener === listener) {
        if (--this._eventsCount === 0)
          this._events = /* @__PURE__ */ Object.create(null);
        else {
          delete events[type];
          if (events.removeListener)
            this.emit("removeListener", type, list.listener || listener);
        }
      } else if (typeof list !== "function") {
        position = -1;
        for (i = list.length - 1; i >= 0; i--) {
          if (list[i] === listener || list[i].listener === listener) {
            originalListener = list[i].listener;
            position = i;
            break;
          }
        }
        if (position < 0)
          return this;
        if (position === 0)
          list.shift();
        else {
          spliceOne(list, position);
        }
        if (list.length === 1)
          events[type] = list[0];
        if (events.removeListener !== void 0)
          this.emit("removeListener", type, originalListener || listener);
      }
      return this;
    };
    EventEmitter2.prototype.off = EventEmitter2.prototype.removeListener;
    EventEmitter2.prototype.removeAllListeners = function removeAllListeners(type) {
      var listeners, events, i;
      events = this._events;
      if (events === void 0)
        return this;
      if (events.removeListener === void 0) {
        if (arguments.length === 0) {
          this._events = /* @__PURE__ */ Object.create(null);
          this._eventsCount = 0;
        } else if (events[type] !== void 0) {
          if (--this._eventsCount === 0)
            this._events = /* @__PURE__ */ Object.create(null);
          else
            delete events[type];
        }
        return this;
      }
      if (arguments.length === 0) {
        var keys = Object.keys(events);
        var key;
        for (i = 0; i < keys.length; ++i) {
          key = keys[i];
          if (key === "removeListener") continue;
          this.removeAllListeners(key);
        }
        this.removeAllListeners("removeListener");
        this._events = /* @__PURE__ */ Object.create(null);
        this._eventsCount = 0;
        return this;
      }
      listeners = events[type];
      if (typeof listeners === "function") {
        this.removeListener(type, listeners);
      } else if (listeners !== void 0) {
        for (i = listeners.length - 1; i >= 0; i--) {
          this.removeListener(type, listeners[i]);
        }
      }
      return this;
    };
    function _listeners(target, type, unwrap) {
      var events = target._events;
      if (events === void 0)
        return [];
      var evlistener = events[type];
      if (evlistener === void 0)
        return [];
      if (typeof evlistener === "function")
        return unwrap ? [evlistener.listener || evlistener] : [evlistener];
      return unwrap ? unwrapListeners(evlistener) : arrayClone(evlistener, evlistener.length);
    }
    EventEmitter2.prototype.listeners = function listeners(type) {
      return _listeners(this, type, true);
    };
    EventEmitter2.prototype.rawListeners = function rawListeners(type) {
      return _listeners(this, type, false);
    };
    EventEmitter2.listenerCount = function(emitter, type) {
      if (typeof emitter.listenerCount === "function") {
        return emitter.listenerCount(type);
      } else {
        return listenerCount.call(emitter, type);
      }
    };
    EventEmitter2.prototype.listenerCount = listenerCount;
    function listenerCount(type) {
      var events = this._events;
      if (events !== void 0) {
        var evlistener = events[type];
        if (typeof evlistener === "function") {
          return 1;
        } else if (evlistener !== void 0) {
          return evlistener.length;
        }
      }
      return 0;
    }
    EventEmitter2.prototype.eventNames = function eventNames() {
      return this._eventsCount > 0 ? ReflectOwnKeys(this._events) : [];
    };
    function arrayClone(arr, n) {
      var copy = new Array(n);
      for (var i = 0; i < n; ++i)
        copy[i] = arr[i];
      return copy;
    }
    function spliceOne(list, index) {
      for (; index + 1 < list.length; index++)
        list[index] = list[index + 1];
      list.pop();
    }
    function unwrapListeners(arr) {
      var ret = new Array(arr.length);
      for (var i = 0; i < ret.length; ++i) {
        ret[i] = arr[i].listener || arr[i];
      }
      return ret;
    }
    function once(emitter, name) {
      return new Promise(function(resolve, reject) {
        function errorListener(err) {
          emitter.removeListener(name, resolver);
          reject(err);
        }
        function resolver() {
          if (typeof emitter.removeListener === "function") {
            emitter.removeListener("error", errorListener);
          }
          resolve([].slice.call(arguments));
        }
        ;
        eventTargetAgnosticAddListener(emitter, name, resolver, { once: true });
        if (name !== "error") {
          addErrorHandlerIfEventEmitter(emitter, errorListener, { once: true });
        }
      });
    }
    function addErrorHandlerIfEventEmitter(emitter, handler, flags) {
      if (typeof emitter.on === "function") {
        eventTargetAgnosticAddListener(emitter, "error", handler, flags);
      }
    }
    function eventTargetAgnosticAddListener(emitter, name, listener, flags) {
      if (typeof emitter.on === "function") {
        if (flags.once) {
          emitter.once(name, listener);
        } else {
          emitter.on(name, listener);
        }
      } else if (typeof emitter.addEventListener === "function") {
        emitter.addEventListener(name, function wrapListener(arg) {
          if (flags.once) {
            emitter.removeEventListener(name, wrapListener);
          }
          listener(arg);
        });
      } else {
        throw new TypeError('The "emitter" argument must be of type EventEmitter. Received type ' + typeof emitter);
      }
    }
  }
});

// node_modules/@owlbear-rodeo/sdk/lib/api/PlayerApi.js
var __awaiter = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var PlayerApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  get id() {
    if (!this.messageBus.userId) {
      throw Error("Unable to get user ID: not ready");
    }
    return this.messageBus.userId;
  }
  getSelection() {
    return __awaiter(this, void 0, void 0, function* () {
      const { selection } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_SELECTION", {});
      return selection;
    });
  }
  select(items, replace) {
    return __awaiter(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_PLAYER_SELECT", { items, replace });
    });
  }
  deselect(items) {
    return __awaiter(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_PLAYER_DESELECT", { items });
    });
  }
  getName() {
    return __awaiter(this, void 0, void 0, function* () {
      const { name } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_NAME", {});
      return name;
    });
  }
  setName(name) {
    return __awaiter(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_PLAYER_SET_NAME", { name });
    });
  }
  getColor() {
    return __awaiter(this, void 0, void 0, function* () {
      const { color } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_COLOR", {});
      return color;
    });
  }
  setColor(color) {
    return __awaiter(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_PLAYER_SET_COLOR", { color });
    });
  }
  getSyncView() {
    return __awaiter(this, void 0, void 0, function* () {
      const { syncView } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_SYNC_VIEW", {});
      return syncView;
    });
  }
  setSyncView(syncView) {
    return __awaiter(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_PLAYER_SET_SYNC_VIEW", { syncView });
    });
  }
  getId() {
    return __awaiter(this, void 0, void 0, function* () {
      const { id } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_ID", {});
      return id;
    });
  }
  getRole() {
    return __awaiter(this, void 0, void 0, function* () {
      const { role } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_ROLE", {});
      return role;
    });
  }
  getMetadata() {
    return __awaiter(this, void 0, void 0, function* () {
      const { metadata } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_METADATA", {});
      return metadata;
    });
  }
  setMetadata(update) {
    return __awaiter(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_PLAYER_SET_METADATA", { update });
    });
  }
  hasPermission(permission) {
    return __awaiter(this, void 0, void 0, function* () {
      const role = yield this.getRole();
      if (role === "GM") {
        return true;
      }
      const { permissions } = yield this.messageBus.sendAsync("OBR_ROOM_GET_PERMISSIONS", {});
      return permissions.indexOf(permission) > -1;
    });
  }
  getConnectionId() {
    return __awaiter(this, void 0, void 0, function* () {
      const { connectionId } = yield this.messageBus.sendAsync("OBR_PLAYER_GET_CONNECTION_ID", {});
      return connectionId;
    });
  }
  onChange(callback) {
    const handleChange = (data) => {
      callback(data.player);
    };
    this.messageBus.send("OBR_PLAYER_SUBSCRIBE", {});
    this.messageBus.on("OBR_PLAYER_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_PLAYER_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_PLAYER_EVENT_CHANGE", handleChange);
    };
  }
};
var PlayerApi_default = PlayerApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/ViewportApi.js
var __awaiter2 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var ViewportApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  reset() {
    return __awaiter2(this, void 0, void 0, function* () {
      const { transform } = yield this.messageBus.sendAsync("OBR_VIEWPORT_RESET", {});
      return transform;
    });
  }
  animateTo(transform) {
    return __awaiter2(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_VIEWPORT_ANIMATE_TO", { transform });
    });
  }
  animateToBounds(bounds) {
    return __awaiter2(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_VIEWPORT_ANIMATE_TO_BOUNDS", {
        bounds
      });
    });
  }
  getPosition() {
    return __awaiter2(this, void 0, void 0, function* () {
      const { position } = yield this.messageBus.sendAsync("OBR_VIEWPORT_GET_POSITION", {});
      return position;
    });
  }
  setPosition(position) {
    return __awaiter2(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_VIEWPORT_SET_POSITION", { position });
    });
  }
  getScale() {
    return __awaiter2(this, void 0, void 0, function* () {
      const { scale } = yield this.messageBus.sendAsync("OBR_VIEWPORT_GET_SCALE", {});
      return scale;
    });
  }
  setScale(scale) {
    return __awaiter2(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_VIEWPORT_SET_SCALE", { scale });
    });
  }
  getWidth() {
    return __awaiter2(this, void 0, void 0, function* () {
      const { width } = yield this.messageBus.sendAsync("OBR_VIEWPORT_GET_WIDTH", {});
      return width;
    });
  }
  getHeight() {
    return __awaiter2(this, void 0, void 0, function* () {
      const { height } = yield this.messageBus.sendAsync("OBR_VIEWPORT_GET_HEIGHT", {});
      return height;
    });
  }
  transformPoint(point) {
    return __awaiter2(this, void 0, void 0, function* () {
      const { point: transformed } = yield this.messageBus.sendAsync("OBR_VIEWPORT_TRANSFORM_POINT", { point });
      return transformed;
    });
  }
  inverseTransformPoint(point) {
    return __awaiter2(this, void 0, void 0, function* () {
      const { point: transformed } = yield this.messageBus.sendAsync("OBR_VIEWPORT_INVERSE_TRANSFORM_POINT", { point });
      return transformed;
    });
  }
};
var ViewportApi_default = ViewportApi;

// node_modules/@owlbear-rodeo/sdk/lib/messages/Message.js
function isMessage(message) {
  return typeof message.id === "string";
}

// node_modules/@owlbear-rodeo/sdk/lib/messages/MessageBus.js
var import_events = __toESM(require_events());

// node_modules/uuid/dist/esm-browser/rng.js
var getRandomValues;
var rnds8 = new Uint8Array(16);
function rng() {
  if (!getRandomValues) {
    getRandomValues = typeof crypto !== "undefined" && crypto.getRandomValues && crypto.getRandomValues.bind(crypto);
    if (!getRandomValues) {
      throw new Error("crypto.getRandomValues() not supported. See https://github.com/uuidjs/uuid#getrandomvalues-not-supported");
    }
  }
  return getRandomValues(rnds8);
}

// node_modules/uuid/dist/esm-browser/stringify.js
var byteToHex = [];
for (let i = 0; i < 256; ++i) {
  byteToHex.push((i + 256).toString(16).slice(1));
}
function unsafeStringify(arr, offset = 0) {
  return byteToHex[arr[offset + 0]] + byteToHex[arr[offset + 1]] + byteToHex[arr[offset + 2]] + byteToHex[arr[offset + 3]] + "-" + byteToHex[arr[offset + 4]] + byteToHex[arr[offset + 5]] + "-" + byteToHex[arr[offset + 6]] + byteToHex[arr[offset + 7]] + "-" + byteToHex[arr[offset + 8]] + byteToHex[arr[offset + 9]] + "-" + byteToHex[arr[offset + 10]] + byteToHex[arr[offset + 11]] + byteToHex[arr[offset + 12]] + byteToHex[arr[offset + 13]] + byteToHex[arr[offset + 14]] + byteToHex[arr[offset + 15]];
}

// node_modules/uuid/dist/esm-browser/native.js
var randomUUID = typeof crypto !== "undefined" && crypto.randomUUID && crypto.randomUUID.bind(crypto);
var native_default = {
  randomUUID
};

// node_modules/uuid/dist/esm-browser/v4.js
function v4(options, buf, offset) {
  if (native_default.randomUUID && !buf && !options) {
    return native_default.randomUUID();
  }
  options = options || {};
  const rnds = options.random || (options.rng || rng)();
  rnds[6] = rnds[6] & 15 | 64;
  rnds[8] = rnds[8] & 63 | 128;
  if (buf) {
    offset = offset || 0;
    for (let i = 0; i < 16; ++i) {
      buf[offset + i] = rnds[i];
    }
    return buf;
  }
  return unsafeStringify(rnds);
}
var v4_default = v4;

// node_modules/@owlbear-rodeo/sdk/lib/messages/MessageBus.js
var MessageBus = class extends import_events.EventEmitter {
  constructor(origin, roomId) {
    super();
    this.ready = false;
    this.userId = null;
    this.ref = null;
    this.handleMessage = (event) => {
      const message = event.data;
      if (event.origin === this.targetOrigin && isMessage(message)) {
        if (message.id === "OBR_READY") {
          this.ready = true;
          const data = message.data;
          this.ref = data.ref;
          this.userId = data.userId;
        }
        this.emit(message.id, message.data);
      }
    };
    this.send = (id, data, nonce) => {
      var _a;
      if (!this.ref) {
        throw Error("Unable to send message: not ready");
      }
      (_a = window.parent) === null || _a === void 0 ? void 0 : _a.postMessage({
        id,
        data,
        ref: this.ref,
        nonce
      }, this.targetOrigin);
    };
    this.sendAsync = (id, data, timeout = 5e3) => {
      const nonce = `_${v4_default()}`;
      this.send(id, data, nonce);
      return Promise.race([
        new Promise((resolve, reject) => {
          const self = this;
          function onResponse(value) {
            self.off(`${id}_RESPONSE${nonce}`, onResponse);
            self.off(`${id}_ERROR${nonce}`, onError);
            resolve(value);
          }
          function onError(error) {
            self.off(`${id}_RESPONSE${nonce}`, onResponse);
            self.off(`${id}_ERROR${nonce}`, onError);
            reject(error);
          }
          this.on(`${id}_RESPONSE${nonce}`, onResponse);
          this.on(`${id}_ERROR${nonce}`, onError);
        }),
        ...timeout > 0 ? [
          new Promise((_, reject) => window.setTimeout(() => reject(new Error(`Message ${id} took longer than ${timeout}ms to get a result`)), timeout))
        ] : []
      ]);
    };
    this.roomId = roomId;
    this.targetOrigin = origin;
    window.addEventListener("message", this.handleMessage);
    this.setMaxListeners(100);
  }
  destroy() {
    window.removeEventListener("message", this.handleMessage);
  }
};
var MessageBus_default = MessageBus;

// node_modules/@owlbear-rodeo/sdk/lib/api/NotificationApi.js
var __awaiter3 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var NotificationApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  show(message, variant) {
    return __awaiter3(this, void 0, void 0, function* () {
      const { id } = yield this.messageBus.sendAsync("OBR_NOTIFICATION_SHOW", { message, variant });
      return id;
    });
  }
  close(id) {
    return __awaiter3(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_NOTIFICATION_CLOSE", { id });
    });
  }
};
var NotificationApi_default = NotificationApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/scene/SceneFogApi.js
var __awaiter4 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var SceneFogApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  getColor() {
    return __awaiter4(this, void 0, void 0, function* () {
      const { color } = yield this.messageBus.sendAsync("OBR_SCENE_FOG_GET_COLOR", {});
      return color;
    });
  }
  setColor(color) {
    return __awaiter4(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_FOG_SET_COLOR", { color });
    });
  }
  getStrokeWidth() {
    return __awaiter4(this, void 0, void 0, function* () {
      const { strokeWidth } = yield this.messageBus.sendAsync("OBR_SCENE_FOG_GET_STROKE_WIDTH", {});
      return strokeWidth;
    });
  }
  setStrokeWidth(strokeWidth) {
    return __awaiter4(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_FOG_SET_STROKE_WIDTH", {
        strokeWidth
      });
    });
  }
  getFilled() {
    return __awaiter4(this, void 0, void 0, function* () {
      const { filled } = yield this.messageBus.sendAsync("OBR_SCENE_FOG_GET_FILLED", {});
      return filled;
    });
  }
  setFilled(filled) {
    return __awaiter4(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_FOG_SET_FILLED", { filled });
    });
  }
  onChange(callback) {
    const handleChange = (data) => {
      callback(data.fog);
    };
    this.messageBus.send("OBR_SCENE_FOG_SUBSCRIBE", {});
    this.messageBus.on("OBR_SCENE_FOG_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_SCENE_FOG_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_SCENE_FOG_EVENT_CHANGE", handleChange);
    };
  }
};
var SceneFogApi_default = SceneFogApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/scene/SceneGridApi.js
var __awaiter5 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var SceneGridApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  getDpi() {
    return __awaiter5(this, void 0, void 0, function* () {
      const { dpi } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_DPI", {});
      return dpi;
    });
  }
  getScale() {
    return __awaiter5(this, void 0, void 0, function* () {
      const scale = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_SCALE", {});
      return scale;
    });
  }
  setScale(scale) {
    return __awaiter5(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_GRID_SET_SCALE", { scale });
    });
  }
  getColor() {
    return __awaiter5(this, void 0, void 0, function* () {
      const { color } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_COLOR", {});
      return color;
    });
  }
  setColor(color) {
    return __awaiter5(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_GRID_SET_COLOR", { color });
    });
  }
  getOpacity() {
    return __awaiter5(this, void 0, void 0, function* () {
      const { opacity } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_OPACITY", {});
      return opacity;
    });
  }
  setOpacity(opacity) {
    return __awaiter5(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_GRID_SET_OPACITY", { opacity });
    });
  }
  getType() {
    return __awaiter5(this, void 0, void 0, function* () {
      const { type } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_TYPE", {});
      return type;
    });
  }
  setType(type) {
    return __awaiter5(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_GRID_SET_TYPE", { type });
    });
  }
  getLineType() {
    return __awaiter5(this, void 0, void 0, function* () {
      const { lineType } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_LINE_TYPE", {});
      return lineType;
    });
  }
  setLineType(lineType) {
    return __awaiter5(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_GRID_SET_LINE_TYPE", {
        lineType
      });
    });
  }
  getMeasurement() {
    return __awaiter5(this, void 0, void 0, function* () {
      const { measurement } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_MEASUREMENT", {});
      return measurement;
    });
  }
  setMeasurement(measurement) {
    return __awaiter5(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_GRID_SET_MEASUREMENT", {
        measurement
      });
    });
  }
  getLineWidth() {
    return __awaiter5(this, void 0, void 0, function* () {
      const { lineWidth } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_LINE_WIDTH", {});
      return lineWidth;
    });
  }
  setLineWidth(lineWidth) {
    return __awaiter5(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_GRID_SET_LINE_WIDTH", {
        lineWidth
      });
    });
  }
  snapPosition(position, snappingSensitivity, useCorners, useCenter) {
    return __awaiter5(this, void 0, void 0, function* () {
      const { position: snapped } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_SNAP_POSITION", {
        position,
        snappingSensitivity,
        useCorners,
        useCenter
      });
      return snapped;
    });
  }
  getDistance(from, to) {
    return __awaiter5(this, void 0, void 0, function* () {
      const { distance } = yield this.messageBus.sendAsync("OBR_SCENE_GRID_GET_DISTANCE", { from, to });
      return distance;
    });
  }
  onChange(callback) {
    const handleChange = (data) => {
      callback(data.grid);
    };
    this.messageBus.send("OBR_SCENE_GRID_SUBSCRIBE", {});
    this.messageBus.on("OBR_SCENE_GRID_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_SCENE_GRID_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_SCENE_GRID_EVENT_CHANGE", handleChange);
    };
  }
};
var SceneGridApi_default = SceneGridApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/scene/SceneHistoryApi.js
var __awaiter6 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var SceneHistoryApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  undo() {
    return __awaiter6(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_HISTORY_UNDO", {});
    });
  }
  redo() {
    return __awaiter6(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_HISTORY_REDO", {});
    });
  }
  canUndo() {
    return __awaiter6(this, void 0, void 0, function* () {
      const { canUndo } = yield this.messageBus.sendAsync("OBR_SCENE_HISTORY_CAN_UNDO", {});
      return canUndo;
    });
  }
  canRedo() {
    return __awaiter6(this, void 0, void 0, function* () {
      const { canRedo } = yield this.messageBus.sendAsync("OBR_SCENE_HISTORY_CAN_REDO", {});
      return canRedo;
    });
  }
};
var SceneHistoryApi_default = SceneHistoryApi;

// node_modules/immer/dist/immer.mjs
var NOTHING = Symbol.for("immer-nothing");
var DRAFTABLE = Symbol.for("immer-draftable");
var DRAFT_STATE = Symbol.for("immer-state");
var errors = true ? [
  // All error codes, starting by 0:
  function(plugin) {
    return `The plugin for '${plugin}' has not been loaded into Immer. To enable the plugin, import and call \`enable${plugin}()\` when initializing your application.`;
  },
  function(thing) {
    return `produce can only be called on things that are draftable: plain objects, arrays, Map, Set or classes that are marked with '[immerable]: true'. Got '${thing}'`;
  },
  "This object has been frozen and should not be mutated",
  function(data) {
    return "Cannot use a proxy that has been revoked. Did you pass an object from inside an immer function to an async process? " + data;
  },
  "An immer producer returned a new value *and* modified its draft. Either return a new value *or* modify the draft.",
  "Immer forbids circular references",
  "The first or second argument to `produce` must be a function",
  "The third argument to `produce` must be a function or undefined",
  "First argument to `createDraft` must be a plain object, an array, or an immerable object",
  "First argument to `finishDraft` must be a draft returned by `createDraft`",
  function(thing) {
    return `'current' expects a draft, got: ${thing}`;
  },
  "Object.defineProperty() cannot be used on an Immer draft",
  "Object.setPrototypeOf() cannot be used on an Immer draft",
  "Immer only supports deleting array indices",
  "Immer only supports setting array indices and the 'length' property",
  function(thing) {
    return `'original' expects a draft, got: ${thing}`;
  }
  // Note: if more errors are added, the errorOffset in Patches.ts should be increased
  // See Patches.ts for additional errors
] : [];
function die(error, ...args) {
  if (true) {
    const e = errors[error];
    const msg = typeof e === "function" ? e.apply(null, args) : e;
    throw new Error(`[Immer] ${msg}`);
  }
  throw new Error(
    `[Immer] minified error nr: ${error}. Full error at: https://bit.ly/3cXEKWf`
  );
}
var getPrototypeOf = Object.getPrototypeOf;
function isDraft(value) {
  return !!value && !!value[DRAFT_STATE];
}
function isDraftable(value) {
  if (!value)
    return false;
  return isPlainObject(value) || Array.isArray(value) || !!value[DRAFTABLE] || !!value.constructor?.[DRAFTABLE] || isMap(value) || isSet(value);
}
var objectCtorString = Object.prototype.constructor.toString();
var cachedCtorStrings = /* @__PURE__ */ new WeakMap();
function isPlainObject(value) {
  if (!value || typeof value !== "object")
    return false;
  const proto = Object.getPrototypeOf(value);
  if (proto === null || proto === Object.prototype)
    return true;
  const Ctor = Object.hasOwnProperty.call(proto, "constructor") && proto.constructor;
  if (Ctor === Object)
    return true;
  if (typeof Ctor !== "function")
    return false;
  let ctorString = cachedCtorStrings.get(Ctor);
  if (ctorString === void 0) {
    ctorString = Function.toString.call(Ctor);
    cachedCtorStrings.set(Ctor, ctorString);
  }
  return ctorString === objectCtorString;
}
function each(obj, iter, strict = true) {
  if (getArchtype(obj) === 0) {
    const keys = strict ? Reflect.ownKeys(obj) : Object.keys(obj);
    keys.forEach((key) => {
      iter(key, obj[key], obj);
    });
  } else {
    obj.forEach((entry, index) => iter(index, entry, obj));
  }
}
function getArchtype(thing) {
  const state = thing[DRAFT_STATE];
  return state ? state.type_ : Array.isArray(thing) ? 1 : isMap(thing) ? 2 : isSet(thing) ? 3 : 0;
}
function has(thing, prop) {
  return getArchtype(thing) === 2 ? thing.has(prop) : Object.prototype.hasOwnProperty.call(thing, prop);
}
function get(thing, prop) {
  return getArchtype(thing) === 2 ? thing.get(prop) : thing[prop];
}
function set(thing, propOrOldValue, value) {
  const t = getArchtype(thing);
  if (t === 2)
    thing.set(propOrOldValue, value);
  else if (t === 3) {
    thing.add(value);
  } else
    thing[propOrOldValue] = value;
}
function is(x, y) {
  if (x === y) {
    return x !== 0 || 1 / x === 1 / y;
  } else {
    return x !== x && y !== y;
  }
}
function isMap(target) {
  return target instanceof Map;
}
function isSet(target) {
  return target instanceof Set;
}
function latest(state) {
  return state.copy_ || state.base_;
}
function shallowCopy(base, strict) {
  if (isMap(base)) {
    return new Map(base);
  }
  if (isSet(base)) {
    return new Set(base);
  }
  if (Array.isArray(base))
    return Array.prototype.slice.call(base);
  const isPlain = isPlainObject(base);
  if (strict === true || strict === "class_only" && !isPlain) {
    const descriptors = Object.getOwnPropertyDescriptors(base);
    delete descriptors[DRAFT_STATE];
    let keys = Reflect.ownKeys(descriptors);
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const desc = descriptors[key];
      if (desc.writable === false) {
        desc.writable = true;
        desc.configurable = true;
      }
      if (desc.get || desc.set)
        descriptors[key] = {
          configurable: true,
          writable: true,
          // could live with !!desc.set as well here...
          enumerable: desc.enumerable,
          value: base[key]
        };
    }
    return Object.create(getPrototypeOf(base), descriptors);
  } else {
    const proto = getPrototypeOf(base);
    if (proto !== null && isPlain) {
      return { ...base };
    }
    const obj = Object.create(proto);
    return Object.assign(obj, base);
  }
}
function freeze(obj, deep = false) {
  if (isFrozen(obj) || isDraft(obj) || !isDraftable(obj))
    return obj;
  if (getArchtype(obj) > 1) {
    Object.defineProperties(obj, {
      set: dontMutateMethodOverride,
      add: dontMutateMethodOverride,
      clear: dontMutateMethodOverride,
      delete: dontMutateMethodOverride
    });
  }
  Object.freeze(obj);
  if (deep)
    Object.values(obj).forEach((value) => freeze(value, true));
  return obj;
}
function dontMutateFrozenCollections() {
  die(2);
}
var dontMutateMethodOverride = {
  value: dontMutateFrozenCollections
};
function isFrozen(obj) {
  if (obj === null || typeof obj !== "object")
    return true;
  return Object.isFrozen(obj);
}
var plugins = {};
function getPlugin(pluginKey) {
  const plugin = plugins[pluginKey];
  if (!plugin) {
    die(0, pluginKey);
  }
  return plugin;
}
function loadPlugin(pluginKey, implementation) {
  if (!plugins[pluginKey])
    plugins[pluginKey] = implementation;
}
var currentScope;
function getCurrentScope() {
  return currentScope;
}
function createScope(parent_, immer_) {
  return {
    drafts_: [],
    parent_,
    immer_,
    // Whenever the modified draft contains a draft from another scope, we
    // need to prevent auto-freezing so the unowned draft can be finalized.
    canAutoFreeze_: true,
    unfinalizedDrafts_: 0
  };
}
function usePatchesInScope(scope, patchListener) {
  if (patchListener) {
    getPlugin("Patches");
    scope.patches_ = [];
    scope.inversePatches_ = [];
    scope.patchListener_ = patchListener;
  }
}
function revokeScope(scope) {
  leaveScope(scope);
  scope.drafts_.forEach(revokeDraft);
  scope.drafts_ = null;
}
function leaveScope(scope) {
  if (scope === currentScope) {
    currentScope = scope.parent_;
  }
}
function enterScope(immer2) {
  return currentScope = createScope(currentScope, immer2);
}
function revokeDraft(draft) {
  const state = draft[DRAFT_STATE];
  if (state.type_ === 0 || state.type_ === 1)
    state.revoke_();
  else
    state.revoked_ = true;
}
function processResult(result, scope) {
  scope.unfinalizedDrafts_ = scope.drafts_.length;
  const baseDraft = scope.drafts_[0];
  const isReplaced = result !== void 0 && result !== baseDraft;
  if (isReplaced) {
    if (baseDraft[DRAFT_STATE].modified_) {
      revokeScope(scope);
      die(4);
    }
    if (isDraftable(result)) {
      result = finalize(scope, result);
      if (!scope.parent_)
        maybeFreeze(scope, result);
    }
    if (scope.patches_) {
      getPlugin("Patches").generateReplacementPatches_(
        baseDraft[DRAFT_STATE].base_,
        result,
        scope.patches_,
        scope.inversePatches_
      );
    }
  } else {
    result = finalize(scope, baseDraft, []);
  }
  revokeScope(scope);
  if (scope.patches_) {
    scope.patchListener_(scope.patches_, scope.inversePatches_);
  }
  return result !== NOTHING ? result : void 0;
}
function finalize(rootScope, value, path) {
  if (isFrozen(value))
    return value;
  const useStrictIteration = rootScope.immer_.shouldUseStrictIteration();
  const state = value[DRAFT_STATE];
  if (!state) {
    each(
      value,
      (key, childValue) => finalizeProperty(rootScope, state, value, key, childValue, path),
      useStrictIteration
    );
    return value;
  }
  if (state.scope_ !== rootScope)
    return value;
  if (!state.modified_) {
    maybeFreeze(rootScope, state.base_, true);
    return state.base_;
  }
  if (!state.finalized_) {
    state.finalized_ = true;
    state.scope_.unfinalizedDrafts_--;
    const result = state.copy_;
    let resultEach = result;
    let isSet2 = false;
    if (state.type_ === 3) {
      resultEach = new Set(result);
      result.clear();
      isSet2 = true;
    }
    each(
      resultEach,
      (key, childValue) => finalizeProperty(
        rootScope,
        state,
        result,
        key,
        childValue,
        path,
        isSet2
      ),
      useStrictIteration
    );
    maybeFreeze(rootScope, result, false);
    if (path && rootScope.patches_) {
      getPlugin("Patches").generatePatches_(
        state,
        path,
        rootScope.patches_,
        rootScope.inversePatches_
      );
    }
  }
  return state.copy_;
}
function finalizeProperty(rootScope, parentState, targetObject, prop, childValue, rootPath, targetIsSet) {
  if (childValue == null) {
    return;
  }
  if (typeof childValue !== "object" && !targetIsSet) {
    return;
  }
  const childIsFrozen = isFrozen(childValue);
  if (childIsFrozen && !targetIsSet) {
    return;
  }
  if (childValue === targetObject)
    die(5);
  if (isDraft(childValue)) {
    const path = rootPath && parentState && parentState.type_ !== 3 && // Set objects are atomic since they have no keys.
    !has(parentState.assigned_, prop) ? rootPath.concat(prop) : void 0;
    const res = finalize(rootScope, childValue, path);
    set(targetObject, prop, res);
    if (isDraft(res)) {
      rootScope.canAutoFreeze_ = false;
    } else
      return;
  } else if (targetIsSet) {
    targetObject.add(childValue);
  }
  if (isDraftable(childValue) && !childIsFrozen) {
    if (!rootScope.immer_.autoFreeze_ && rootScope.unfinalizedDrafts_ < 1) {
      return;
    }
    if (parentState && parentState.base_ && parentState.base_[prop] === childValue && childIsFrozen) {
      return;
    }
    finalize(rootScope, childValue);
    if ((!parentState || !parentState.scope_.parent_) && typeof prop !== "symbol" && (isMap(targetObject) ? targetObject.has(prop) : Object.prototype.propertyIsEnumerable.call(targetObject, prop)))
      maybeFreeze(rootScope, childValue);
  }
}
function maybeFreeze(scope, value, deep = false) {
  if (!scope.parent_ && scope.immer_.autoFreeze_ && scope.canAutoFreeze_) {
    freeze(value, deep);
  }
}
function createProxyProxy(base, parent) {
  const isArray = Array.isArray(base);
  const state = {
    type_: isArray ? 1 : 0,
    // Track which produce call this is associated with.
    scope_: parent ? parent.scope_ : getCurrentScope(),
    // True for both shallow and deep changes.
    modified_: false,
    // Used during finalization.
    finalized_: false,
    // Track which properties have been assigned (true) or deleted (false).
    assigned_: {},
    // The parent draft state.
    parent_: parent,
    // The base state.
    base_: base,
    // The base proxy.
    draft_: null,
    // set below
    // The base copy with any updated values.
    copy_: null,
    // Called by the `produce` function.
    revoke_: null,
    isManual_: false
  };
  let target = state;
  let traps = objectTraps;
  if (isArray) {
    target = [state];
    traps = arrayTraps;
  }
  const { revoke, proxy } = Proxy.revocable(target, traps);
  state.draft_ = proxy;
  state.revoke_ = revoke;
  return proxy;
}
var objectTraps = {
  get(state, prop) {
    if (prop === DRAFT_STATE)
      return state;
    const source = latest(state);
    if (!has(source, prop)) {
      return readPropFromProto(state, source, prop);
    }
    const value = source[prop];
    if (state.finalized_ || !isDraftable(value)) {
      return value;
    }
    if (value === peek(state.base_, prop)) {
      prepareCopy(state);
      return state.copy_[prop] = createProxy(value, state);
    }
    return value;
  },
  has(state, prop) {
    return prop in latest(state);
  },
  ownKeys(state) {
    return Reflect.ownKeys(latest(state));
  },
  set(state, prop, value) {
    const desc = getDescriptorFromProto(latest(state), prop);
    if (desc?.set) {
      desc.set.call(state.draft_, value);
      return true;
    }
    if (!state.modified_) {
      const current2 = peek(latest(state), prop);
      const currentState = current2?.[DRAFT_STATE];
      if (currentState && currentState.base_ === value) {
        state.copy_[prop] = value;
        state.assigned_[prop] = false;
        return true;
      }
      if (is(value, current2) && (value !== void 0 || has(state.base_, prop)))
        return true;
      prepareCopy(state);
      markChanged(state);
    }
    if (state.copy_[prop] === value && // special case: handle new props with value 'undefined'
    (value !== void 0 || prop in state.copy_) || // special case: NaN
    Number.isNaN(value) && Number.isNaN(state.copy_[prop]))
      return true;
    state.copy_[prop] = value;
    state.assigned_[prop] = true;
    return true;
  },
  deleteProperty(state, prop) {
    if (peek(state.base_, prop) !== void 0 || prop in state.base_) {
      state.assigned_[prop] = false;
      prepareCopy(state);
      markChanged(state);
    } else {
      delete state.assigned_[prop];
    }
    if (state.copy_) {
      delete state.copy_[prop];
    }
    return true;
  },
  // Note: We never coerce `desc.value` into an Immer draft, because we can't make
  // the same guarantee in ES5 mode.
  getOwnPropertyDescriptor(state, prop) {
    const owner = latest(state);
    const desc = Reflect.getOwnPropertyDescriptor(owner, prop);
    if (!desc)
      return desc;
    return {
      writable: true,
      configurable: state.type_ !== 1 || prop !== "length",
      enumerable: desc.enumerable,
      value: owner[prop]
    };
  },
  defineProperty() {
    die(11);
  },
  getPrototypeOf(state) {
    return getPrototypeOf(state.base_);
  },
  setPrototypeOf() {
    die(12);
  }
};
var arrayTraps = {};
each(objectTraps, (key, fn) => {
  arrayTraps[key] = function() {
    arguments[0] = arguments[0][0];
    return fn.apply(this, arguments);
  };
});
arrayTraps.deleteProperty = function(state, prop) {
  if (isNaN(parseInt(prop)))
    die(13);
  return arrayTraps.set.call(this, state, prop, void 0);
};
arrayTraps.set = function(state, prop, value) {
  if (prop !== "length" && isNaN(parseInt(prop)))
    die(14);
  return objectTraps.set.call(this, state[0], prop, value, state[0]);
};
function peek(draft, prop) {
  const state = draft[DRAFT_STATE];
  const source = state ? latest(state) : draft;
  return source[prop];
}
function readPropFromProto(state, source, prop) {
  const desc = getDescriptorFromProto(source, prop);
  return desc ? `value` in desc ? desc.value : (
    // This is a very special case, if the prop is a getter defined by the
    // prototype, we should invoke it with the draft as context!
    desc.get?.call(state.draft_)
  ) : void 0;
}
function getDescriptorFromProto(source, prop) {
  if (!(prop in source))
    return void 0;
  let proto = getPrototypeOf(source);
  while (proto) {
    const desc = Object.getOwnPropertyDescriptor(proto, prop);
    if (desc)
      return desc;
    proto = getPrototypeOf(proto);
  }
  return void 0;
}
function markChanged(state) {
  if (!state.modified_) {
    state.modified_ = true;
    if (state.parent_) {
      markChanged(state.parent_);
    }
  }
}
function prepareCopy(state) {
  if (!state.copy_) {
    state.copy_ = shallowCopy(
      state.base_,
      state.scope_.immer_.useStrictShallowCopy_
    );
  }
}
var Immer2 = class {
  constructor(config) {
    this.autoFreeze_ = true;
    this.useStrictShallowCopy_ = false;
    this.useStrictIteration_ = true;
    this.produce = (base, recipe, patchListener) => {
      if (typeof base === "function" && typeof recipe !== "function") {
        const defaultBase = recipe;
        recipe = base;
        const self = this;
        return function curriedProduce(base2 = defaultBase, ...args) {
          return self.produce(base2, (draft) => recipe.call(this, draft, ...args));
        };
      }
      if (typeof recipe !== "function")
        die(6);
      if (patchListener !== void 0 && typeof patchListener !== "function")
        die(7);
      let result;
      if (isDraftable(base)) {
        const scope = enterScope(this);
        const proxy = createProxy(base, void 0);
        let hasError = true;
        try {
          result = recipe(proxy);
          hasError = false;
        } finally {
          if (hasError)
            revokeScope(scope);
          else
            leaveScope(scope);
        }
        usePatchesInScope(scope, patchListener);
        return processResult(result, scope);
      } else if (!base || typeof base !== "object") {
        result = recipe(base);
        if (result === void 0)
          result = base;
        if (result === NOTHING)
          result = void 0;
        if (this.autoFreeze_)
          freeze(result, true);
        if (patchListener) {
          const p = [];
          const ip = [];
          getPlugin("Patches").generateReplacementPatches_(base, result, p, ip);
          patchListener(p, ip);
        }
        return result;
      } else
        die(1, base);
    };
    this.produceWithPatches = (base, recipe) => {
      if (typeof base === "function") {
        return (state, ...args) => this.produceWithPatches(state, (draft) => base(draft, ...args));
      }
      let patches, inversePatches;
      const result = this.produce(base, recipe, (p, ip) => {
        patches = p;
        inversePatches = ip;
      });
      return [result, patches, inversePatches];
    };
    if (typeof config?.autoFreeze === "boolean")
      this.setAutoFreeze(config.autoFreeze);
    if (typeof config?.useStrictShallowCopy === "boolean")
      this.setUseStrictShallowCopy(config.useStrictShallowCopy);
    if (typeof config?.useStrictIteration === "boolean")
      this.setUseStrictIteration(config.useStrictIteration);
  }
  createDraft(base) {
    if (!isDraftable(base))
      die(8);
    if (isDraft(base))
      base = current(base);
    const scope = enterScope(this);
    const proxy = createProxy(base, void 0);
    proxy[DRAFT_STATE].isManual_ = true;
    leaveScope(scope);
    return proxy;
  }
  finishDraft(draft, patchListener) {
    const state = draft && draft[DRAFT_STATE];
    if (!state || !state.isManual_)
      die(9);
    const { scope_: scope } = state;
    usePatchesInScope(scope, patchListener);
    return processResult(void 0, scope);
  }
  /**
   * Pass true to automatically freeze all copies created by Immer.
   *
   * By default, auto-freezing is enabled.
   */
  setAutoFreeze(value) {
    this.autoFreeze_ = value;
  }
  /**
   * Pass true to enable strict shallow copy.
   *
   * By default, immer does not copy the object descriptors such as getter, setter and non-enumrable properties.
   */
  setUseStrictShallowCopy(value) {
    this.useStrictShallowCopy_ = value;
  }
  /**
   * Pass false to use faster iteration that skips non-enumerable properties
   * but still handles symbols for compatibility.
   *
   * By default, strict iteration is enabled (includes all own properties).
   */
  setUseStrictIteration(value) {
    this.useStrictIteration_ = value;
  }
  shouldUseStrictIteration() {
    return this.useStrictIteration_;
  }
  applyPatches(base, patches) {
    let i;
    for (i = patches.length - 1; i >= 0; i--) {
      const patch = patches[i];
      if (patch.path.length === 0 && patch.op === "replace") {
        base = patch.value;
        break;
      }
    }
    if (i > -1) {
      patches = patches.slice(i + 1);
    }
    const applyPatchesImpl = getPlugin("Patches").applyPatches_;
    if (isDraft(base)) {
      return applyPatchesImpl(base, patches);
    }
    return this.produce(
      base,
      (draft) => applyPatchesImpl(draft, patches)
    );
  }
};
function createProxy(value, parent) {
  const draft = isMap(value) ? getPlugin("MapSet").proxyMap_(value, parent) : isSet(value) ? getPlugin("MapSet").proxySet_(value, parent) : createProxyProxy(value, parent);
  const scope = parent ? parent.scope_ : getCurrentScope();
  scope.drafts_.push(draft);
  return draft;
}
function current(value) {
  if (!isDraft(value))
    die(10, value);
  return currentImpl(value);
}
function currentImpl(value) {
  if (!isDraftable(value) || isFrozen(value))
    return value;
  const state = value[DRAFT_STATE];
  let copy;
  let strict = true;
  if (state) {
    if (!state.modified_)
      return state.base_;
    state.finalized_ = true;
    copy = shallowCopy(value, state.scope_.immer_.useStrictShallowCopy_);
    strict = state.scope_.immer_.shouldUseStrictIteration();
  } else {
    copy = shallowCopy(value, true);
  }
  each(
    copy,
    (key, childValue) => {
      set(copy, key, currentImpl(childValue));
    },
    strict
  );
  if (state) {
    state.finalized_ = false;
  }
  return copy;
}
function enablePatches() {
  const errorOffset = 16;
  if (true) {
    errors.push(
      'Sets cannot have "replace" patches.',
      function(op) {
        return "Unsupported patch operation: " + op;
      },
      function(path) {
        return "Cannot apply patch, path doesn't resolve: " + path;
      },
      "Patching reserved attributes like __proto__, prototype and constructor is not allowed"
    );
  }
  const REPLACE = "replace";
  const ADD = "add";
  const REMOVE = "remove";
  function generatePatches_(state, basePath, patches, inversePatches) {
    switch (state.type_) {
      case 0:
      case 2:
        return generatePatchesFromAssigned(
          state,
          basePath,
          patches,
          inversePatches
        );
      case 1:
        return generateArrayPatches(state, basePath, patches, inversePatches);
      case 3:
        return generateSetPatches(
          state,
          basePath,
          patches,
          inversePatches
        );
    }
  }
  function generateArrayPatches(state, basePath, patches, inversePatches) {
    let { base_, assigned_ } = state;
    let copy_ = state.copy_;
    if (copy_.length < base_.length) {
      ;
      [base_, copy_] = [copy_, base_];
      [patches, inversePatches] = [inversePatches, patches];
    }
    for (let i = 0; i < base_.length; i++) {
      if (assigned_[i] && copy_[i] !== base_[i]) {
        const path = basePath.concat([i]);
        patches.push({
          op: REPLACE,
          path,
          // Need to maybe clone it, as it can in fact be the original value
          // due to the base/copy inversion at the start of this function
          value: clonePatchValueIfNeeded(copy_[i])
        });
        inversePatches.push({
          op: REPLACE,
          path,
          value: clonePatchValueIfNeeded(base_[i])
        });
      }
    }
    for (let i = base_.length; i < copy_.length; i++) {
      const path = basePath.concat([i]);
      patches.push({
        op: ADD,
        path,
        // Need to maybe clone it, as it can in fact be the original value
        // due to the base/copy inversion at the start of this function
        value: clonePatchValueIfNeeded(copy_[i])
      });
    }
    for (let i = copy_.length - 1; base_.length <= i; --i) {
      const path = basePath.concat([i]);
      inversePatches.push({
        op: REMOVE,
        path
      });
    }
  }
  function generatePatchesFromAssigned(state, basePath, patches, inversePatches) {
    const { base_, copy_ } = state;
    each(state.assigned_, (key, assignedValue) => {
      const origValue = get(base_, key);
      const value = get(copy_, key);
      const op = !assignedValue ? REMOVE : has(base_, key) ? REPLACE : ADD;
      if (origValue === value && op === REPLACE)
        return;
      const path = basePath.concat(key);
      patches.push(op === REMOVE ? { op, path } : { op, path, value });
      inversePatches.push(
        op === ADD ? { op: REMOVE, path } : op === REMOVE ? { op: ADD, path, value: clonePatchValueIfNeeded(origValue) } : { op: REPLACE, path, value: clonePatchValueIfNeeded(origValue) }
      );
    });
  }
  function generateSetPatches(state, basePath, patches, inversePatches) {
    let { base_, copy_ } = state;
    let i = 0;
    base_.forEach((value) => {
      if (!copy_.has(value)) {
        const path = basePath.concat([i]);
        patches.push({
          op: REMOVE,
          path,
          value
        });
        inversePatches.unshift({
          op: ADD,
          path,
          value
        });
      }
      i++;
    });
    i = 0;
    copy_.forEach((value) => {
      if (!base_.has(value)) {
        const path = basePath.concat([i]);
        patches.push({
          op: ADD,
          path,
          value
        });
        inversePatches.unshift({
          op: REMOVE,
          path,
          value
        });
      }
      i++;
    });
  }
  function generateReplacementPatches_(baseValue, replacement, patches, inversePatches) {
    patches.push({
      op: REPLACE,
      path: [],
      value: replacement === NOTHING ? void 0 : replacement
    });
    inversePatches.push({
      op: REPLACE,
      path: [],
      value: baseValue
    });
  }
  function applyPatches_(draft, patches) {
    patches.forEach((patch) => {
      const { path, op } = patch;
      let base = draft;
      for (let i = 0; i < path.length - 1; i++) {
        const parentType = getArchtype(base);
        let p = path[i];
        if (typeof p !== "string" && typeof p !== "number") {
          p = "" + p;
        }
        if ((parentType === 0 || parentType === 1) && (p === "__proto__" || p === "constructor"))
          die(errorOffset + 3);
        if (typeof base === "function" && p === "prototype")
          die(errorOffset + 3);
        base = get(base, p);
        if (typeof base !== "object")
          die(errorOffset + 2, path.join("/"));
      }
      const type = getArchtype(base);
      const value = deepClonePatchValue(patch.value);
      const key = path[path.length - 1];
      switch (op) {
        case REPLACE:
          switch (type) {
            case 2:
              return base.set(key, value);
            case 3:
              die(errorOffset);
            default:
              return base[key] = value;
          }
        case ADD:
          switch (type) {
            case 1:
              return key === "-" ? base.push(value) : base.splice(key, 0, value);
            case 2:
              return base.set(key, value);
            case 3:
              return base.add(value);
            default:
              return base[key] = value;
          }
        case REMOVE:
          switch (type) {
            case 1:
              return base.splice(key, 1);
            case 2:
              return base.delete(key);
            case 3:
              return base.delete(patch.value);
            default:
              return delete base[key];
          }
        default:
          die(errorOffset + 1, op);
      }
    });
    return draft;
  }
  function deepClonePatchValue(obj) {
    if (!isDraftable(obj))
      return obj;
    if (Array.isArray(obj))
      return obj.map(deepClonePatchValue);
    if (isMap(obj))
      return new Map(
        Array.from(obj.entries()).map(([k, v]) => [k, deepClonePatchValue(v)])
      );
    if (isSet(obj))
      return new Set(Array.from(obj).map(deepClonePatchValue));
    const cloned = Object.create(getPrototypeOf(obj));
    for (const key in obj)
      cloned[key] = deepClonePatchValue(obj[key]);
    if (has(obj, DRAFTABLE))
      cloned[DRAFTABLE] = obj[DRAFTABLE];
    return cloned;
  }
  function clonePatchValueIfNeeded(obj) {
    if (isDraft(obj)) {
      return deepClonePatchValue(obj);
    } else
      return obj;
  }
  loadPlugin("Patches", {
    applyPatches_,
    generatePatches_,
    generateReplacementPatches_
  });
}
var immer = new Immer2();
var produce = immer.produce;
var produceWithPatches = /* @__PURE__ */ immer.produceWithPatches.bind(
  immer
);

// node_modules/@owlbear-rodeo/sdk/lib/api/scene/SceneItemsApi.js
var __awaiter7 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
enablePatches();
var SceneItemsApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  getItems(filter) {
    return __awaiter7(this, void 0, void 0, function* () {
      if (Array.isArray(filter)) {
        const { items } = yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_GET_ITEMS", { ids: filter });
        return items;
      } else if (filter) {
        const { items } = yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_GET_ALL_ITEMS", {});
        return items.filter(filter);
      } else {
        const { items } = yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_GET_ALL_ITEMS", {});
        return items;
      }
    });
  }
  isItemArray(value) {
    return Array.isArray(value) && value.every((item) => typeof item !== "string");
  }
  updateItems(filterOrItems, update) {
    return __awaiter7(this, void 0, void 0, function* () {
      let items;
      if (this.isItemArray(filterOrItems)) {
        items = filterOrItems;
      } else {
        items = yield this.getItems(filterOrItems);
      }
      const [nextState, patches] = produceWithPatches(items, update);
      const nextUpdates = nextState.map((item) => ({
        id: item.id,
        type: item.type
      }));
      for (const patch of patches) {
        const [index, key] = patch.path;
        if (typeof index === "number" && typeof key === "string") {
          nextUpdates[index][key] = nextState[index][key];
        }
      }
      const updates = nextUpdates.filter(
        // Ensure that there are updates besides the default ID and type
        (update2) => Object.keys(update2).length > 2
      );
      if (updates.length === 0) {
        return;
      }
      yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_UPDATE_ITEMS", {
        updates
      });
    });
  }
  addItems(items) {
    return __awaiter7(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_ADD_ITEMS", {
        items
      });
    });
  }
  deleteItems(ids) {
    return __awaiter7(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_DELETE_ITEMS", {
        ids
      });
    });
  }
  getItemAttachments(ids) {
    return __awaiter7(this, void 0, void 0, function* () {
      const { items } = yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_GET_ITEM_ATTACHMENTS", { ids });
      return items;
    });
  }
  getItemBounds(ids) {
    return __awaiter7(this, void 0, void 0, function* () {
      const { bounds } = yield this.messageBus.sendAsync("OBR_SCENE_ITEMS_GET_ITEM_BOUNDS", { ids });
      return bounds;
    });
  }
  onChange(callback) {
    const handleChange = (data) => {
      callback(data.items);
    };
    this.messageBus.send("OBR_SCENE_ITEMS_SUBSCRIBE", {});
    this.messageBus.on("OBR_SCENE_ITEMS_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_SCENE_ITEMS_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_SCENE_ITEMS_EVENT_CHANGE", handleChange);
    };
  }
};
var SceneItemsApi_default = SceneItemsApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/scene/SceneLocalApi.js
var __awaiter8 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
enablePatches();
var SceneLocalApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  getItems(filter) {
    return __awaiter8(this, void 0, void 0, function* () {
      if (Array.isArray(filter)) {
        const { items } = yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_GET_ITEMS", { ids: filter });
        return items;
      } else if (filter) {
        const { items } = yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_GET_ALL_ITEMS", {});
        return items.filter(filter);
      } else {
        const { items } = yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_GET_ALL_ITEMS", {});
        return items;
      }
    });
  }
  isItemArray(value) {
    return Array.isArray(value) && value.every((item) => typeof item !== "string");
  }
  updateItems(filterOrItems, update, fastUpdate) {
    return __awaiter8(this, void 0, void 0, function* () {
      let items;
      if (this.isItemArray(filterOrItems)) {
        items = filterOrItems;
      } else {
        items = yield this.getItems(filterOrItems);
      }
      const [nextState, patches] = produceWithPatches(items, update);
      const nextUpdates = nextState.map((item) => ({
        id: item.id,
        type: item.type
      }));
      for (const patch of patches) {
        const [index, key] = patch.path;
        if (typeof index === "number" && typeof key === "string") {
          nextUpdates[index][key] = nextState[index][key];
        }
      }
      const updates = nextUpdates.filter(
        // Ensure that there are updates besides the default ID and type
        (update2) => Object.keys(update2).length > 2
      );
      if (updates.length === 0) {
        return;
      }
      yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_UPDATE_ITEMS", {
        updates,
        fastUpdate
      });
    });
  }
  addItems(items) {
    return __awaiter8(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_ADD_ITEMS", {
        items
      });
    });
  }
  deleteItems(ids) {
    return __awaiter8(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_DELETE_ITEMS", {
        ids
      });
    });
  }
  getItemAttachments(ids) {
    return __awaiter8(this, void 0, void 0, function* () {
      const { items } = yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_GET_ITEM_ATTACHMENTS", { ids });
      return items;
    });
  }
  getItemBounds(ids) {
    return __awaiter8(this, void 0, void 0, function* () {
      const { bounds } = yield this.messageBus.sendAsync("OBR_SCENE_LOCAL_GET_ITEM_BOUNDS", { ids });
      return bounds;
    });
  }
  onChange(callback) {
    const handleChange = (data) => {
      callback(data.items);
    };
    this.messageBus.send("OBR_SCENE_LOCAL_SUBSCRIBE", {});
    this.messageBus.on("OBR_SCENE_LOCAL_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_SCENE_LOCAL_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_SCENE_LOCAL_EVENT_CHANGE", handleChange);
    };
  }
};
var SceneLocalApi_default = SceneLocalApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/scene/SceneApi.js
var __awaiter9 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var SceneApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
    this.grid = new SceneGridApi_default(messageBus2);
    this.fog = new SceneFogApi_default(messageBus2);
    this.history = new SceneHistoryApi_default(messageBus2);
    this.items = new SceneItemsApi_default(messageBus2);
    this.local = new SceneLocalApi_default(messageBus2);
  }
  isReady() {
    return __awaiter9(this, void 0, void 0, function* () {
      const { ready } = yield this.messageBus.sendAsync("OBR_SCENE_IS_READY", {});
      return ready;
    });
  }
  onReadyChange(callback) {
    const handleChange = (data) => {
      callback(data.ready);
    };
    this.messageBus.send("OBR_SCENE_READY_SUBSCRIBE", {});
    this.messageBus.on("OBR_SCENE_EVENT_READY_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_SCENE_READY_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_SCENE_EVENT_READY_CHANGE", handleChange);
    };
  }
  getMetadata() {
    return __awaiter9(this, void 0, void 0, function* () {
      const { metadata } = yield this.messageBus.sendAsync("OBR_SCENE_GET_METADATA", {});
      return metadata;
    });
  }
  setMetadata(update) {
    return __awaiter9(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_SCENE_SET_METADATA", { update });
    });
  }
  onMetadataChange(callback) {
    const handleChange = (data) => {
      callback(data.metadata);
    };
    this.messageBus.send("OBR_SCENE_METADATA_SUBSCRIBE", {});
    this.messageBus.on("OBR_SCENE_METADATA_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_SCENE_METADATA_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_SCENE_METADATA_EVENT_CHANGE", handleChange);
    };
  }
};
var SceneApi_default = SceneApi;

// node_modules/@owlbear-rodeo/sdk/lib/common/normalize.js
function normalizeUrl(url) {
  return url.startsWith("http") ? url : `${window.location.origin}${url}`;
}
function normalizeIconPaths(icons) {
  return icons.map((base) => Object.assign(Object.assign({}, base), { icon: normalizeUrl(base.icon) }));
}
function normalizeUrlObject(urlObject) {
  return Object.assign(Object.assign({}, urlObject), { url: normalizeUrl(urlObject.url) });
}

// node_modules/@owlbear-rodeo/sdk/lib/api/ContextMenuApi.js
var __awaiter10 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var ContextMenuApi = class {
  constructor(messageBus2) {
    this.contextMenus = {};
    this.handleClick = (event) => {
      var _a;
      const menu = this.contextMenus[event.id];
      if (menu) {
        (_a = menu.onClick) === null || _a === void 0 ? void 0 : _a.call(menu, event.context, event.elementId);
      }
    };
    this.messageBus = messageBus2;
    messageBus2.on("OBR_CONTEXT_MENU_EVENT_CLICK", this.handleClick);
  }
  create(contextMenu) {
    return __awaiter10(this, void 0, void 0, function* () {
      this.messageBus.sendAsync("OBR_CONTEXT_MENU_CREATE", {
        id: contextMenu.id,
        shortcut: contextMenu.shortcut,
        icons: normalizeIconPaths(contextMenu.icons),
        embed: contextMenu.embed && normalizeUrlObject(contextMenu.embed)
      });
      this.contextMenus[contextMenu.id] = contextMenu;
    });
  }
  remove(id) {
    return __awaiter10(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_CONTEXT_MENU_REMOVE", { id });
      delete this.contextMenus[id];
    });
  }
};
var ContextMenuApi_default = ContextMenuApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/ToolApi.js
var __awaiter11 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var ToolApi = class {
  constructor(messageBus2) {
    this.tools = {};
    this.toolActions = {};
    this.toolModes = {};
    this.handleToolClick = (event) => {
      const tool = this.tools[event.id];
      if (tool) {
        if (tool.onClick) {
          const result = tool.onClick(event.context, event.elementId);
          Promise.resolve(result).then((activate) => {
            if (activate) {
              this.messageBus.send("OBR_TOOL_ACTIVATE", {
                id: event.id
              });
            }
          });
        } else {
          this.messageBus.send("OBR_TOOL_ACTIVATE", {
            id: event.id
          });
        }
      }
    };
    this.handleToolActionClick = (event) => {
      var _a;
      const action = this.toolActions[event.id];
      if (action) {
        (_a = action.onClick) === null || _a === void 0 ? void 0 : _a.call(action, event.context, event.elementId);
      }
    };
    this.handleToolModeClick = (event) => {
      const mode = this.toolModes[event.id];
      if (mode) {
        if (mode.onClick) {
          const result = mode.onClick(event.context, event.elementId);
          Promise.resolve(result).then((activate) => {
            if (activate) {
              this.messageBus.send("OBR_TOOL_MODE_ACTIVATE", {
                toolId: event.context.activeTool,
                modeId: event.id
              });
            }
          });
        } else {
          this.messageBus.send("OBR_TOOL_MODE_ACTIVATE", {
            toolId: event.context.activeTool,
            modeId: event.id
          });
        }
      }
    };
    this.handleToolModeToolClick = (event) => {
      const mode = this.toolModes[event.id];
      if (mode) {
        if (mode.onToolClick) {
          const result = mode.onToolClick(event.context, event.event);
          Promise.resolve(result).then((select) => {
            if (select && event.event.target && !event.event.target.locked) {
              this.messageBus.sendAsync("OBR_PLAYER_SELECT", {
                items: [event.event.target.id]
              });
            }
          });
        } else {
          if (event.event.target && !event.event.target.locked) {
            this.messageBus.sendAsync("OBR_PLAYER_SELECT", {
              items: [event.event.target.id]
            });
          }
        }
      }
    };
    this.handleToolModeToolDoubleClick = (event) => {
      const mode = this.toolModes[event.id];
      if (mode) {
        if (mode.onToolDoubleClick) {
          const result = mode.onToolDoubleClick(event.context, event.event);
          Promise.resolve(result).then((select) => {
            if (select && event.event.target) {
              this.messageBus.sendAsync("OBR_PLAYER_SELECT", {
                items: [event.event.target.id]
              });
            }
          });
        } else {
          if (event.event.target) {
            this.messageBus.sendAsync("OBR_PLAYER_SELECT", {
              items: [event.event.target.id]
            });
          }
        }
      }
    };
    this.handleToolModeToolDown = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onToolDown) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeToolMove = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onToolMove) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeToolUp = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onToolUp) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeToolDragStart = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onToolDragStart) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeToolDragMove = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onToolDragMove) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeToolDragEnd = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onToolDragEnd) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeToolDragCancel = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onToolDragCancel) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeKeyDown = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onKeyDown) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeKeyUp = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onKeyUp) === null || _a === void 0 ? void 0 : _a.call(mode, event.context, event.event);
      }
    };
    this.handleToolModeActivate = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onActivate) === null || _a === void 0 ? void 0 : _a.call(mode, event.context);
      }
    };
    this.handleToolModeDeactivate = (event) => {
      var _a;
      const mode = this.toolModes[event.id];
      if (mode) {
        (_a = mode.onDeactivate) === null || _a === void 0 ? void 0 : _a.call(mode, event.context);
      }
    };
    this.messageBus = messageBus2;
    messageBus2.on("OBR_TOOL_EVENT_CLICK", this.handleToolClick);
    messageBus2.on("OBR_TOOL_ACTION_EVENT_CLICK", this.handleToolActionClick);
    messageBus2.on("OBR_TOOL_MODE_EVENT_CLICK", this.handleToolModeClick);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_CLICK", this.handleToolModeToolClick);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_DOUBLE_CLICK", this.handleToolModeToolDoubleClick);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_DOWN", this.handleToolModeToolDown);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_MOVE", this.handleToolModeToolMove);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_UP", this.handleToolModeToolUp);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_DRAG_START", this.handleToolModeToolDragStart);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_DRAG_MOVE", this.handleToolModeToolDragMove);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_DRAG_END", this.handleToolModeToolDragEnd);
    messageBus2.on("OBR_TOOL_MODE_EVENT_TOOL_DRAG_CANCEL", this.handleToolModeToolDragCancel);
    messageBus2.on("OBR_TOOL_MODE_EVENT_KEY_DOWN", this.handleToolModeKeyDown);
    messageBus2.on("OBR_TOOL_MODE_EVENT_KEY_UP", this.handleToolModeKeyUp);
    messageBus2.on("OBR_TOOL_MODE_EVENT_ACTIVATE", this.handleToolModeActivate);
    messageBus2.on("OBR_TOOL_MODE_EVENT_DEACTIVATE", this.handleToolModeDeactivate);
  }
  create(tool) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_CREATE", {
        id: tool.id,
        shortcut: tool.shortcut,
        defaultMode: tool.defaultMode,
        defaultMetadata: tool.defaultMetadata,
        icons: normalizeIconPaths(tool.icons),
        disabled: tool.disabled
      });
      this.tools[tool.id] = tool;
    });
  }
  remove(id) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_REMOVE", { id });
      delete this.tools[id];
    });
  }
  activateTool(id) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_ACTIVATE", { id });
    });
  }
  getActiveTool() {
    return __awaiter11(this, void 0, void 0, function* () {
      const { id } = yield this.messageBus.sendAsync("OBR_TOOL_GET_ACTIVE", {});
      return id;
    });
  }
  onToolChange(callback) {
    const handleChange = (data) => {
      callback(data.id);
    };
    this.messageBus.send("OBR_TOOL_ACTIVE_SUBSCRIBE", {});
    this.messageBus.on("OBR_TOOL_ACTIVE_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_TOOL_ACTIVE_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_TOOL_ACTIVE_EVENT_CHANGE", handleChange);
    };
  }
  getMetadata(id) {
    return __awaiter11(this, void 0, void 0, function* () {
      const { metadata } = yield this.messageBus.sendAsync("OBR_TOOL_GET_METADATA", { id });
      return metadata;
    });
  }
  setMetadata(toolId, update) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_SET_METADATA", {
        toolId,
        update
      });
    });
  }
  createAction(action) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_ACTION_CREATE", {
        id: action.id,
        shortcut: action.shortcut,
        icons: normalizeIconPaths(action.icons),
        disabled: action.disabled
      });
      this.toolActions[action.id] = action;
    });
  }
  removeAction(id) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_ACTION_REMOVE", { id });
      delete this.tools[id];
    });
  }
  createMode(mode) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_MODE_CREATE", {
        id: mode.id,
        shortcut: mode.shortcut,
        icons: normalizeIconPaths(mode.icons),
        preventDrag: mode.preventDrag,
        disabled: mode.disabled,
        cursors: mode.cursors
      });
      this.toolModes[mode.id] = mode;
    });
  }
  removeMode(id) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_MODE_REMOVE", { id });
      delete this.tools[id];
    });
  }
  activateMode(toolId, modeId) {
    return __awaiter11(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_TOOL_MODE_ACTIVATE", {
        toolId,
        modeId
      });
    });
  }
  getActiveToolMode() {
    return __awaiter11(this, void 0, void 0, function* () {
      const { id } = yield this.messageBus.sendAsync("OBR_TOOL_MODE_GET_ACTIVE", {});
      return id;
    });
  }
  onToolModeChange(callback) {
    const handleChange = (data) => {
      callback(data.id);
    };
    this.messageBus.send("OBR_TOOL_MODE_ACTIVE_SUBSCRIBE", {});
    this.messageBus.on("OBR_TOOL_MODE_ACTIVE_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_TOOL_MODE_ACTIVE_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_TOOL_MODE_ACTIVE_EVENT_CHANGE", handleChange);
    };
  }
};
var ToolApi_default = ToolApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/PopoverApi.js
var __awaiter12 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var PopoverApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  open(popover) {
    return __awaiter12(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_POPOVER_OPEN", Object.assign({}, normalizeUrlObject(popover)));
    });
  }
  close(id) {
    return __awaiter12(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_POPOVER_CLOSE", { id });
    });
  }
  getWidth(id) {
    return __awaiter12(this, void 0, void 0, function* () {
      const { width } = yield this.messageBus.sendAsync("OBR_POPOVER_GET_WIDTH", { id });
      return width;
    });
  }
  setWidth(id, width) {
    return __awaiter12(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_POPOVER_SET_WIDTH", { id, width });
    });
  }
  getHeight(id) {
    return __awaiter12(this, void 0, void 0, function* () {
      const { height } = yield this.messageBus.sendAsync("OBR_POPOVER_GET_HEIGHT", { id });
      return height;
    });
  }
  setHeight(id, height) {
    return __awaiter12(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_POPOVER_SET_HEIGHT", { id, height });
    });
  }
};
var PopoverApi_default = PopoverApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/ModalApi.js
var __awaiter13 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var ModalApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  open(modal) {
    return __awaiter13(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_MODAL_OPEN", Object.assign({}, normalizeUrlObject(modal)));
    });
  }
  close(id) {
    return __awaiter13(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_MODAL_CLOSE", { id });
    });
  }
};
var ModalApi_default = ModalApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/ActionApi.js
var __awaiter14 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var ActionApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  getWidth() {
    return __awaiter14(this, void 0, void 0, function* () {
      const { width } = yield this.messageBus.sendAsync("OBR_ACTION_GET_WIDTH", {});
      return width;
    });
  }
  setWidth(width) {
    return __awaiter14(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ACTION_SET_WIDTH", { width });
    });
  }
  getHeight() {
    return __awaiter14(this, void 0, void 0, function* () {
      const { height } = yield this.messageBus.sendAsync("OBR_ACTION_GET_HEIGHT", {});
      return height;
    });
  }
  setHeight(height) {
    return __awaiter14(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ACTION_SET_HEIGHT", { height });
    });
  }
  getBadgeText() {
    return __awaiter14(this, void 0, void 0, function* () {
      const { badgeText } = yield this.messageBus.sendAsync("OBR_ACTION_GET_BADGE_TEXT", {});
      return badgeText;
    });
  }
  setBadgeText(badgeText) {
    return __awaiter14(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ACTION_SET_BADGE_TEXT", { badgeText });
    });
  }
  getBadgeBackgroundColor() {
    return __awaiter14(this, void 0, void 0, function* () {
      const { badgeBackgroundColor } = yield this.messageBus.sendAsync("OBR_ACTION_GET_BADGE_BACKGROUND_COLOR", {});
      return badgeBackgroundColor;
    });
  }
  setBadgeBackgroundColor(badgeBackgroundColor) {
    return __awaiter14(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ACTION_SET_BADGE_BACKGROUND_COLOR", {
        badgeBackgroundColor
      });
    });
  }
  getIcon() {
    return __awaiter14(this, void 0, void 0, function* () {
      const { icon } = yield this.messageBus.sendAsync("OBR_ACTION_GET_ICON", {});
      return icon;
    });
  }
  setIcon(icon) {
    return __awaiter14(this, void 0, void 0, function* () {
      const data = normalizeIconPaths([{ icon }]);
      yield this.messageBus.sendAsync("OBR_ACTION_SET_ICON", {
        icon: data[0].icon
      });
    });
  }
  getTitle() {
    return __awaiter14(this, void 0, void 0, function* () {
      const { title } = yield this.messageBus.sendAsync("OBR_ACTION_GET_TITLE", {});
      return title;
    });
  }
  setTitle(title) {
    return __awaiter14(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ACTION_SET_TITLE", { title });
    });
  }
  isOpen() {
    return __awaiter14(this, void 0, void 0, function* () {
      const { isOpen } = yield this.messageBus.sendAsync("OBR_ACTION_GET_IS_OPEN", {});
      return isOpen;
    });
  }
  open() {
    return __awaiter14(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ACTION_OPEN", {});
    });
  }
  close() {
    return __awaiter14(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ACTION_CLOSE", {});
    });
  }
  onOpenChange(callback) {
    const handleChange = (data) => {
      callback(data.isOpen);
    };
    this.messageBus.send("OBR_ACTION_IS_OPEN_SUBSCRIBE", {});
    this.messageBus.on("OBR_ACTION_IS_OPEN_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_IS_OPEN_ACTION_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_ACTION_IS_OPEN_EVENT_CHANGE", handleChange);
    };
  }
};
var ActionApi_default = ActionApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/InteractionApi.js
var __awaiter15 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
enablePatches();
var InteractionApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  startItemInteraction(baseState) {
    return __awaiter15(this, void 0, void 0, function* () {
      const { id } = yield this.messageBus.sendAsync("OBR_INTERACTION_START_ITEM_INTERACTION", { baseState });
      let prev = baseState;
      const dispatcher = (update) => {
        const [next, patches] = produceWithPatches(prev, update);
        prev = next;
        this.messageBus.send("OBR_INTERACTION_UPDATE_ITEM_INTERACTION", {
          id,
          patches
        });
        return next;
      };
      const stop = () => {
        this.messageBus.send("OBR_INTERACTION_STOP_ITEM_INTERACTION", { id });
      };
      return [dispatcher, stop];
    });
  }
};
var InteractionApi_default = InteractionApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/PartyApi.js
var __awaiter16 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var PartyApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  getPlayers() {
    return __awaiter16(this, void 0, void 0, function* () {
      const { players } = yield this.messageBus.sendAsync("OBR_PARTY_GET_PLAYERS", {});
      return players;
    });
  }
  onChange(callback) {
    const handleChange = (data) => {
      callback(data.players);
    };
    this.messageBus.send("OBR_PARTY_SUBSCRIBE", {});
    this.messageBus.on("OBR_PARTY_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_PARTY_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_PARTY_EVENT_CHANGE", handleChange);
    };
  }
};
var PartyApi_default = PartyApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/RoomApi.js
var __awaiter17 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var RoomApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  get id() {
    return this.messageBus.roomId;
  }
  getPermissions() {
    return __awaiter17(this, void 0, void 0, function* () {
      const { permissions } = yield this.messageBus.sendAsync("OBR_ROOM_GET_PERMISSIONS", {});
      return permissions;
    });
  }
  getMetadata() {
    return __awaiter17(this, void 0, void 0, function* () {
      const { metadata } = yield this.messageBus.sendAsync("OBR_ROOM_GET_METADATA", {});
      return metadata;
    });
  }
  setMetadata(update) {
    return __awaiter17(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ROOM_SET_METADATA", { update });
    });
  }
  onMetadataChange(callback) {
    const handleChange = (data) => {
      callback(data.metadata);
    };
    this.messageBus.send("OBR_ROOM_METADATA_SUBSCRIBE", {});
    this.messageBus.on("OBR_ROOM_METADATA_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_METADATA_ROOM_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_ROOM_METADATA_EVENT_CHANGE", handleChange);
    };
  }
  onPermissionsChange(callback) {
    const handleChange = (data) => {
      callback(data.permissions);
    };
    this.messageBus.send("OBR_ROOM_PERMISSIONS_SUBSCRIBE", {});
    this.messageBus.on("OBR_ROOM_PERMISSIONS_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_PERMISSIONS_ROOM_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_ROOM_PERMISSIONS_EVENT_CHANGE", handleChange);
    };
  }
};
var RoomApi_default = RoomApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/ThemeApi.js
var __awaiter18 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var ThemeApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  getTheme() {
    return __awaiter18(this, void 0, void 0, function* () {
      const { theme } = yield this.messageBus.sendAsync("OBR_THEME_GET_THEME", {});
      return theme;
    });
  }
  onChange(callback) {
    const handleChange = (data) => {
      callback(data.theme);
    };
    this.messageBus.send("OBR_THEME_SUBSCRIBE", {});
    this.messageBus.on("OBR_THEME_EVENT_CHANGE", handleChange);
    return () => {
      this.messageBus.send("OBR_THEME_UNSUBSCRIBE", {});
      this.messageBus.off("OBR_THEME_EVENT_CHANGE", handleChange);
    };
  }
};
var ThemeApi_default = ThemeApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/AssetsApi.js
var __awaiter19 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var AssetsApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  uploadImages(images, typeHint) {
    return __awaiter19(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ASSETS_UPLOAD_IMAGES", {
        images,
        typeHint
      });
    });
  }
  uploadScenes(scenes, disableShowScenes) {
    return __awaiter19(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_ASSETS_UPLOAD_SCENES", {
        scenes,
        disableShowScenes
      });
    });
  }
  downloadImages(multiple, defaultSearch, typeHint) {
    return __awaiter19(this, void 0, void 0, function* () {
      const { images } = yield this.messageBus.sendAsync("OBR_ASSETS_DOWNLOAD_IMAGES", { multiple, defaultSearch, typeHint }, -1);
      return images;
    });
  }
  downloadScenes(multiple, defaultSearch) {
    return __awaiter19(this, void 0, void 0, function* () {
      const { scenes } = yield this.messageBus.sendAsync("OBR_ASSETS_DOWNLOAD_SCENES", { multiple, defaultSearch }, -1);
      return scenes;
    });
  }
};
var AssetsApi_default = AssetsApi;

// node_modules/@owlbear-rodeo/sdk/lib/api/BroadcastApi.js
var __awaiter20 = function(thisArg, _arguments, P, generator) {
  function adopt(value) {
    return value instanceof P ? value : new P(function(resolve) {
      resolve(value);
    });
  }
  return new (P || (P = Promise))(function(resolve, reject) {
    function fulfilled(value) {
      try {
        step(generator.next(value));
      } catch (e) {
        reject(e);
      }
    }
    function rejected(value) {
      try {
        step(generator["throw"](value));
      } catch (e) {
        reject(e);
      }
    }
    function step(result) {
      result.done ? resolve(result.value) : adopt(result.value).then(fulfilled, rejected);
    }
    step((generator = generator.apply(thisArg, _arguments || [])).next());
  });
};
var BroadcastApi = class {
  constructor(messageBus2) {
    this.messageBus = messageBus2;
  }
  sendMessage(channel, data, options) {
    return __awaiter20(this, void 0, void 0, function* () {
      yield this.messageBus.sendAsync("OBR_BROADCAST_SEND_MESSAGE", {
        channel,
        data,
        options
      });
    });
  }
  onMessage(channel, callback) {
    this.messageBus.send("OBR_BROADCAST_SUBSCRIBE", { channel });
    this.messageBus.on(`OBR_BROADCAST_MESSAGE_${channel}`, callback);
    return () => {
      this.messageBus.send("OBR_BROADCAST_UNSUBSCRIBE", { channel });
      this.messageBus.off(`OBR_BROADCAST_MESSAGE_${channel}`, callback);
    };
  }
};
var BroadcastApi_default = BroadcastApi;

// node_modules/js-base64/base64.mjs
var _hasBuffer = typeof Buffer === "function";
var _TD = typeof TextDecoder === "function" ? new TextDecoder() : void 0;
var _TE = typeof TextEncoder === "function" ? new TextEncoder() : void 0;
var b64ch = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
var b64chs = Array.prototype.slice.call(b64ch);
var b64tab = ((a) => {
  let tab = {};
  a.forEach((c, i) => tab[c] = i);
  return tab;
})(b64chs);
var b64re = /^(?:[A-Za-z\d+\/]{4})*?(?:[A-Za-z\d+\/]{2}(?:==)?|[A-Za-z\d+\/]{3}=?)?$/;
var _fromCC = String.fromCharCode.bind(String);
var _U8Afrom = typeof Uint8Array.from === "function" ? Uint8Array.from.bind(Uint8Array) : (it) => new Uint8Array(Array.prototype.slice.call(it, 0));
var _tidyB64 = (s) => s.replace(/[^A-Za-z0-9\+\/]/g, "");
var re_btou = /[\xC0-\xDF][\x80-\xBF]|[\xE0-\xEF][\x80-\xBF]{2}|[\xF0-\xF7][\x80-\xBF]{3}/g;
var cb_btou = (cccc) => {
  switch (cccc.length) {
    case 4:
      var cp = (7 & cccc.charCodeAt(0)) << 18 | (63 & cccc.charCodeAt(1)) << 12 | (63 & cccc.charCodeAt(2)) << 6 | 63 & cccc.charCodeAt(3), offset = cp - 65536;
      return _fromCC((offset >>> 10) + 55296) + _fromCC((offset & 1023) + 56320);
    case 3:
      return _fromCC((15 & cccc.charCodeAt(0)) << 12 | (63 & cccc.charCodeAt(1)) << 6 | 63 & cccc.charCodeAt(2));
    default:
      return _fromCC((31 & cccc.charCodeAt(0)) << 6 | 63 & cccc.charCodeAt(1));
  }
};
var btou = (b) => b.replace(re_btou, cb_btou);
var atobPolyfill = (asc) => {
  asc = asc.replace(/\s+/g, "");
  if (!b64re.test(asc))
    throw new TypeError("malformed base64.");
  asc += "==".slice(2 - (asc.length & 3));
  let u24, r1, r2;
  let binArray = [];
  for (let i = 0; i < asc.length; ) {
    u24 = b64tab[asc.charAt(i++)] << 18 | b64tab[asc.charAt(i++)] << 12 | (r1 = b64tab[asc.charAt(i++)]) << 6 | (r2 = b64tab[asc.charAt(i++)]);
    if (r1 === 64) {
      binArray.push(_fromCC(u24 >> 16 & 255));
    } else if (r2 === 64) {
      binArray.push(_fromCC(u24 >> 16 & 255, u24 >> 8 & 255));
    } else {
      binArray.push(_fromCC(u24 >> 16 & 255, u24 >> 8 & 255, u24 & 255));
    }
  }
  return binArray.join("");
};
var _atob = typeof atob === "function" ? (asc) => atob(_tidyB64(asc)) : _hasBuffer ? (asc) => Buffer.from(asc, "base64").toString("binary") : atobPolyfill;
var _toUint8Array = _hasBuffer ? (a) => _U8Afrom(Buffer.from(a, "base64")) : (a) => _U8Afrom(_atob(a).split("").map((c) => c.charCodeAt(0)));
var _decode = _hasBuffer ? (a) => Buffer.from(a, "base64").toString("utf8") : _TD ? (a) => _TD.decode(_toUint8Array(a)) : (a) => btou(_atob(a));
var _unURI = (a) => _tidyB64(a.replace(/[-_]/g, (m0) => m0 == "-" ? "+" : "/"));
var decode = (src) => _decode(_unURI(src));

// node_modules/@owlbear-rodeo/sdk/lib/common/getDetails.js
function getDetails() {
  const urlSearchParams = new URLSearchParams(window.location.search);
  const ref = urlSearchParams.get("obrref");
  let origin = "";
  let roomId = "";
  if (ref) {
    const decodedRef = decode(ref);
    const parts = decodedRef.split(" ");
    if (parts.length === 2) {
      origin = parts[0];
      roomId = parts[1];
    }
  }
  return { origin, roomId };
}

// node_modules/@owlbear-rodeo/sdk/lib/types/items/Path.js
var Command;
(function(Command2) {
  Command2[Command2["MOVE"] = 0] = "MOVE";
  Command2[Command2["LINE"] = 1] = "LINE";
  Command2[Command2["QUAD"] = 2] = "QUAD";
  Command2[Command2["CONIC"] = 3] = "CONIC";
  Command2[Command2["CUBIC"] = 4] = "CUBIC";
  Command2[Command2["CLOSE"] = 5] = "CLOSE";
})(Command || (Command = {}));

// node_modules/@owlbear-rodeo/sdk/lib/index.js
var details = getDetails();
var messageBus = new MessageBus_default(details.origin, details.roomId);
var viewportApi = new ViewportApi_default(messageBus);
var playerApi = new PlayerApi_default(messageBus);
var partyApi = new PartyApi_default(messageBus);
var notificationApi = new NotificationApi_default(messageBus);
var sceneApi = new SceneApi_default(messageBus);
var contextMenuApi = new ContextMenuApi_default(messageBus);
var toolApi = new ToolApi_default(messageBus);
var popoverApi = new PopoverApi_default(messageBus);
var modalApi = new ModalApi_default(messageBus);
var actionApi = new ActionApi_default(messageBus);
var interactionApi = new InteractionApi_default(messageBus);
var roomApi = new RoomApi_default(messageBus);
var themeApi = new ThemeApi_default(messageBus);
var assetsApi = new AssetsApi_default(messageBus);
var broadcastApi = new BroadcastApi_default(messageBus);
var OBR = {
  onReady: (callback) => {
    if (messageBus.ready) {
      callback();
    } else {
      messageBus.once("OBR_READY", () => callback());
    }
  },
  get isReady() {
    return messageBus.ready;
  },
  viewport: viewportApi,
  player: playerApi,
  party: partyApi,
  notification: notificationApi,
  scene: sceneApi,
  contextMenu: contextMenuApi,
  tool: toolApi,
  popover: popoverApi,
  modal: modalApi,
  action: actionApi,
  interaction: interactionApi,
  room: roomApi,
  theme: themeApi,
  assets: assetsApi,
  broadcast: broadcastApi,
  /** True if the current site is embedded in an instance of Owlbear Rodeo */
  isAvailable: Boolean(details.origin)
};
var lib_default = OBR;

// hud/styles/combatHudTokens.css
var combatHudTokens_default = "/*\n * Combat HUD \u2014 design tokens (Phase 0, palette refreshed for Phase 2).\n *\n * Semantic custom properties ONLY. No layout, no component rules \u2014 those live\n * in hud/components/combatHudLayout.css and hud/overlay/combatHudOverlay.css.\n * JavaScript must never hard-code colours; it stores semantic state names\n * (see hud/models/combatHudContracts.js) and the UI maps state \u2192 token here.\n *\n * Scope: variables are declared on a `.odyssey-hud` root class so the HUD's\n * theme cannot leak into the existing popup screens (Resolve Attack, etc.).\n *\n * The palette follows the approved Phase 2 references: a dark sci-fi MMORPG\n * panel \u2014 deep navy surfaces, thin blue-grey borders, bright colours reserved\n * for game-state accents only.\n */\n\n.odyssey-hud {\n  /* ---- Raw palette (approved Phase 2 reference) ---- */\n  --odyssey-bg-deep: #0e1320;\n  --odyssey-panel-base: #16203a;\n  --odyssey-panel-raised: #1a2236;\n  --odyssey-panel-hover: #232e47;\n  --odyssey-line: #3a4a66;\n  --odyssey-line-soft: #283448;\n\n  --odyssey-ink: #eaf0ff;\n  --odyssey-ink-muted: #9fb0d0;\n  --odyssey-ink-dim: #6b7a9c;\n\n  --odyssey-purple: #a78bfa;\n  --odyssey-purple-strong: #8b5cf6;\n  --odyssey-purple-panel: #26215c;\n  --odyssey-cyan: #34e1d6;\n  --odyssey-yellow: #ffc24b;\n  --odyssey-orange: #f59042;\n  --odyssey-red: #ff5c6c;\n  --odyssey-green: #4ade80;\n  --odyssey-steel: #aecbf0;     /* light cool blue \u2014 weapon / vehicle silhouettes */\n\n  /* ---- Semantic surfaces (names kept stable since Phase 0/1A) ---- */\n  --odyssey-hud-bg: rgba(14, 19, 32, 0.94);\n  --odyssey-hud-panel: rgba(22, 32, 58, 0.96);\n  --odyssey-hud-panel-raised: rgba(26, 34, 54, 0.98);\n  --odyssey-hud-panel-hover: #232e47;\n  --odyssey-hud-border: rgba(120, 142, 184, 0.30);\n  --odyssey-hud-border-strong: rgba(150, 172, 214, 0.55);\n\n  /* ---- Text ---- */\n  --odyssey-hud-text: var(--odyssey-ink);\n  --odyssey-hud-muted: var(--odyssey-ink-muted);\n  --odyssey-hud-dim: var(--odyssey-ink-dim);\n\n  /* ---- Generic valence ---- */\n  --odyssey-hud-positive: var(--odyssey-green);\n  --odyssey-hud-negative: var(--odyssey-red);\n  --odyssey-hud-warning: var(--odyssey-yellow);\n\n  /* ---- Action / ability semantics (spec colour language) ---- */\n  --odyssey-hud-attack: var(--odyssey-red);          /* red \u2014 attacking / hostile     */\n  --odyssey-hud-neutral: #8593b0;                    /* cool grey \u2014 defensive / util  */\n  --odyssey-hud-psionic: var(--odyssey-purple);      /* purple \u2014 psionics             */\n  --odyssey-hud-implant: var(--odyssey-cyan);        /* cyan \u2014 implants / tech        */\n  --odyssey-hud-intervention: var(--odyssey-yellow); /* gold \u2014 intervention           */\n\n  /* ---- State / availability ---- */\n  --odyssey-hud-state-active: var(--odyssey-green);\n  --odyssey-hud-state-unavailable: var(--odyssey-red);\n  --odyssey-hud-disabled: rgba(159, 176, 208, 0.22);\n\n  /* ---- Body zone condition scale (healthy \u2192 disabled) ---- */\n  /* healthy is a MUTED COOL tone (not green) per the spec. */\n  --odyssey-hud-zone-healthy: #6e7da0;\n  --odyssey-hud-zone-wounded: var(--odyssey-yellow);\n  --odyssey-hud-zone-serious: var(--odyssey-orange);\n  --odyssey-hud-zone-critical: var(--odyssey-red);\n  --odyssey-hud-zone-disabled: #39414f;\n\n  /* ---- Resources ---- */\n  --odyssey-hud-shield: #5b9be0;\n  --odyssey-hud-psi: var(--odyssey-purple);\n  --odyssey-hud-weapon: var(--odyssey-steel);\n\n  /* ---- Elevation & geometry ---- */\n  --odyssey-hud-shadow: 0 10px 30px rgba(0, 0, 0, 0.5);\n  --odyssey-hud-shadow-soft: 0 4px 14px rgba(0, 0, 0, 0.35);\n  --odyssey-hud-radius: 14px;       /* outer panels */\n  --odyssey-hud-radius-inner: 10px; /* nested cards / tiles */\n  --odyssey-hud-radius-chip: 9px;\n}\n";

// hud/overlay/combatHudOverlay.css
var combatHudOverlay_default = '/*\n * Combat HUD overlay \u2014 frame + collapsed pill (Phase 1A, trimmed for Phase 2).\n *\n * Only the overlay container and the collapsed reopen pill live here. All the\n * expanded module/layout styling is in hud/components/combatHudLayout.css.\n * Consumes the semantic tokens from hud/styles/combatHudTokens.css.\n */\n\n*,\n*::before,\n*::after { box-sizing: border-box; }\n\nhtml, body { height: 100%; }\nbody {\n  margin: 0;\n  background: transparent;\n  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;\n  color: var(--odyssey-hud-text, #eaf0ff);\n}\n\n#root { height: 100%; }\n\n/* The iframe rect IS the HUD footprint. The container bottom-aligns the HUD so\n   any spare height sits above it (transparent), and the map shows through. */\n.ohud-overlay {\n  height: 100%;\n  display: flex;\n  align-items: flex-end;\n  justify-content: center;\n  background: transparent;\n  padding: 0;\n}\n\n/* ===================== Collapsed pill ===================== */\n.ohud-overlay.is-collapsed { align-items: flex-end; }\n.ohud-pill {\n  display: inline-flex; align-items: center; gap: 8px;\n  margin-bottom: 6px;\n  padding: 9px 16px; cursor: pointer;\n  font: inherit; font-size: 12px; font-weight: 700; letter-spacing: 1px;\n  color: var(--odyssey-hud-text);\n  background: var(--odyssey-hud-bg); border: 1px solid var(--odyssey-hud-border-strong);\n  border-radius: 22px; box-shadow: var(--odyssey-hud-shadow);\n  backdrop-filter: blur(7px); -webkit-backdrop-filter: blur(7px);\n}\n.ohud-pill:hover { border-color: var(--odyssey-purple); }\n.ohud-pill .ohud-mark { color: var(--odyssey-purple); display: inline-flex; }\n.ohud-pill-label { line-height: 1; }\n';

// hud/components/combatHudLayout.css
var combatHudLayout_default = '/*\n * Combat HUD \u2014 Phase 2 layout & module styles.\n *\n * Scoped under the overlay (.odyssey-hud / .ohud-hud). Consumes semantic tokens\n * from hud/styles/combatHudTokens.css; no raw colours from JS. Composition uses\n * CSS grid + clamp() + grid-template-areas so proportions hold across widths.\n *\n * Breakpoints mirror hud/overlay/overlayConstants.js:\n *   wide \u22651280 \xB7 medium \u2265960 \xB7 compact \u2265620 \xB7 mini <620\n */\n\n/* ===================== Shell ===================== */\n.ohud-hud {\n  position: relative;\n  width: 100%;\n  height: 100%;\n  display: flex;\n  flex-direction: column;\n  justify-content: flex-end;\n  gap: 6px;\n  padding: 4px 4px 2px;\n  color: var(--odyssey-hud-text);\n  font-size: 12px;\n}\n\n/* ---- top control row (thin) ---- */\n.ohud-controls {\n  display: flex;\n  align-items: center;\n  gap: 10px;\n  min-height: 22px;\n  padding: 0 6px;\n}\n.ohud-brand { display: flex; align-items: center; gap: 7px; min-width: 0; }\n.ohud-brand-mark { color: var(--odyssey-purple); display: inline-flex; }\n.ohud-brand-text { font-weight: 800; letter-spacing: 2px; font-size: 11px; color: var(--odyssey-hud-text); }\n.ohud-brand-sub {\n  font-size: 10px; color: var(--odyssey-hud-dim);\n  white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 220px;\n}\n.ohud-fallback {\n  font-size: 10px; font-weight: 700; color: var(--odyssey-hud-warning);\n  border: 1px dashed var(--odyssey-hud-warning); border-radius: 6px; padding: 1px 7px;\n}\n.ohud-controls-right { margin-left: auto; display: flex; align-items: center; gap: 8px; }\n\n/* ---- dev controls (collapsed by default) ---- */\n.ohud-dev { display: flex; align-items: center; gap: 8px; }\n.ohud-dev-btn {\n  display: inline-flex; align-items: center; gap: 5px;\n  font: inherit; font-size: 10px; font-weight: 700; letter-spacing: 0.5px;\n  color: var(--odyssey-hud-muted); cursor: pointer;\n  background: var(--odyssey-hud-panel-raised);\n  border: 1px solid var(--odyssey-hud-border); border-radius: 7px; padding: 3px 8px;\n}\n.ohud-dev-btn:hover { color: var(--odyssey-hud-text); border-color: var(--odyssey-hud-border-strong); }\n.ohud-dev.is-open .ohud-dev-btn { color: var(--odyssey-purple); border-color: var(--odyssey-purple); }\n.ohud-dev-strip {\n  display: inline-flex; align-items: center; gap: 10px;\n  background: var(--odyssey-hud-panel-raised);\n  border: 1px solid var(--odyssey-hud-border); border-radius: 8px; padding: 3px 8px;\n}\n.ohud-dev-field { display: inline-flex; align-items: center; gap: 5px; font-size: 10px; color: var(--odyssey-hud-dim); }\n.ohud-dev-roles { display: inline-flex; gap: 4px; }\n.ohud-select {\n  font: inherit; font-size: 11px; color: var(--odyssey-hud-text);\n  background: var(--odyssey-panel-base); border: 1px solid var(--odyssey-hud-border);\n  border-radius: 6px; padding: 2px 6px; cursor: pointer;\n}\n.ohud-chip {\n  font: inherit; font-size: 11px; color: var(--odyssey-hud-muted);\n  background: var(--odyssey-panel-base); border: 1px solid var(--odyssey-hud-border);\n  border-radius: 12px; padding: 2px 10px; cursor: pointer;\n}\n.ohud-chip.is-on { background: var(--odyssey-purple-strong); border-color: var(--odyssey-purple-strong); color: #fff; }\n.ohud-collapse {\n  display: inline-flex; align-items: center; justify-content: center;\n  width: 26px; height: 26px; border-radius: 7px; cursor: pointer;\n  color: var(--odyssey-hud-muted); background: var(--odyssey-hud-panel-raised);\n  border: 1px solid var(--odyssey-hud-border);\n}\n.ohud-collapse:hover { color: var(--odyssey-hud-text); border-color: var(--odyssey-hud-border-strong); }\n\n/* ===================== Grid composition ===================== */\n.ohud-grid {\n  display: grid;\n  gap: 10px;\n  flex: 1 1 auto;\n  min-height: 0;\n}\n\n/* wide: one visual row; mod/action stack in their column; log own column */\n.ohud-grid--wide {\n  grid-template-columns:\n    minmax(150px, 168px)\n    minmax(206px, 240px)\n    minmax(320px, 1fr)\n    minmax(140px, 172px)\n    minmax(150px, 182px)\n    minmax(184px, 214px);\n  grid-template-rows: 1fr 1fr;\n  grid-template-areas:\n    "player gun skills target mod    log"\n    "player gun skills target action log";\n}\n\n/* medium: drop the log column (log floats as a button) */\n.ohud-grid--medium {\n  grid-template-columns:\n    minmax(138px, 158px)\n    minmax(186px, 224px)\n    minmax(250px, 1fr)\n    minmax(128px, 160px)\n    minmax(146px, 178px);\n  grid-template-rows: 1fr 1fr;\n  grid-template-areas:\n    "player gun skills target mod"\n    "player gun skills target action";\n}\n\n/* compact / mini: two module rows */\n.ohud-grid--compact,\n.ohud-grid--mini {\n  grid-template-columns: repeat(3, minmax(0, 1fr));\n  grid-template-rows: minmax(0, 1fr) minmax(0, 1fr);\n  grid-template-areas:\n    "player gun target"\n    "skills mod action";\n}\n\n.ohud-panel--player { grid-area: player; }\n.ohud-panel--gun { grid-area: gun; }\n.ohud-panel--skills { grid-area: skills; }\n.ohud-panel--target { grid-area: target; }\n.ohud-panel--mod { grid-area: mod; }\n.ohud-panel--action { grid-area: action; }\n.ohud-panel--log { grid-area: log; }\n\n/* ===================== Panel frame ===================== */\n.ohud-panel {\n  display: flex; flex-direction: column; gap: 6px; min-width: 0; min-height: 0;\n  background: var(--odyssey-hud-panel);\n  border: 1px solid var(--odyssey-hud-border);\n  border-radius: var(--odyssey-hud-radius);\n  box-shadow: var(--odyssey-hud-shadow-soft);\n  padding: 8px 10px;\n}\n.ohud-panel-head { display: flex; align-items: center; justify-content: space-between; gap: 6px; min-height: 12px; }\n.ohud-panel-label {\n  font-size: 9.5px; font-weight: 800; letter-spacing: 1.4px; text-transform: uppercase;\n  color: var(--odyssey-hud-dim);\n}\n.ohud-panel-body { flex: 1 1 auto; min-height: 0; display: flex; flex-direction: column; }\n.ohud-muted-fill { color: var(--odyssey-hud-dim); font-size: 11px; display: grid; place-items: center; flex: 1; }\n\n/* accent label colours */\n.ohud-accent--attack { color: var(--odyssey-hud-attack); }\n.ohud-accent--psionic { color: var(--odyssey-hud-psionic); }\n.ohud-accent--implant { color: var(--odyssey-hud-implant); }\n.ohud-accent--intervention { color: var(--odyssey-hud-intervention); }\n.ohud-accent--positive { color: var(--odyssey-hud-positive); }\n.ohud-accent--negative { color: var(--odyssey-hud-negative); }\n.ohud-accent--neutral { color: var(--odyssey-hud-neutral); }\n\n/* ===================== Body zones (silhouettes) ===================== */\n.ohud-silhouette { display: block; }\n.ohud-zone { transition: fill 120ms ease; }\n.ohud-zone--healthy { fill: var(--odyssey-hud-zone-healthy); }\n.ohud-zone--wounded { fill: var(--odyssey-hud-zone-wounded); }\n.ohud-zone--serious { fill: var(--odyssey-hud-zone-serious); }\n.ohud-zone--critical { fill: var(--odyssey-hud-zone-critical); }\n.ohud-zone--disabled { fill: var(--odyssey-hud-zone-disabled); }\n.ohud-zone.is-target { stroke: var(--odyssey-cyan); stroke-width: 2.5; }\n\n/* ===================== Player block ===================== */\n.ohud-turn {\n  font-size: 9px; font-weight: 800; letter-spacing: 0.6px; padding: 2px 7px; border-radius: 8px;\n  border: 1px solid transparent;\n}\n.ohud-turn--active { color: #06210f; background: var(--odyssey-hud-state-active); }\n.ohud-turn--waiting { color: #2a1c00; background: var(--odyssey-hud-warning); }\n.ohud-turn--gm { color: #fff; background: var(--odyssey-purple-strong); }\n.ohud-turn--idle { color: var(--odyssey-hud-muted); border-color: var(--odyssey-hud-border); }\n\n.ohud-player-grid { display: grid; grid-template-columns: auto 1fr; gap: 9px; align-items: center; flex: 1; min-height: 0; }\n.ohud-figure { position: relative; width: clamp(40px, 4vw, 54px); height: 100%; min-height: 56px; display: grid; place-items: center; }\n.ohud-figure-svg { width: 100%; height: 100%; }\n.ohud-figure-shield {\n  position: absolute; right: -4px; bottom: 0; width: 18px; height: 20px;\n  color: var(--odyssey-hud-shield); opacity: 0.85;\n}\n.ohud-figure--ghost { opacity: 0.4; }\n\n.ohud-player-stats { display: flex; flex-direction: column; gap: 5px; min-width: 0; }\n.ohud-player-name {\n  font-size: 13px; font-weight: 700; color: var(--odyssey-hud-text);\n  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;\n}\n\n.ohud-res { display: grid; grid-template-columns: 34px 1fr auto; align-items: center; gap: 6px; }\n.ohud-res-label { font-size: 8.5px; font-weight: 700; letter-spacing: 0.5px; color: var(--odyssey-hud-dim); }\n.ohud-res-track { height: 7px; border-radius: 4px; background: var(--odyssey-line-soft); overflow: hidden; }\n.ohud-res-fill { display: block; height: 100%; border-radius: 4px; }\n.ohud-res--shield .ohud-res-fill { background: var(--odyssey-hud-shield); }\n.ohud-res--psi .ohud-res-fill { background: var(--odyssey-hud-psi); }\n.ohud-res-num { font-size: 11px; font-weight: 700; color: var(--odyssey-hud-text); font-variant-numeric: tabular-nums; }\n.ohud-res-max { color: var(--odyssey-hud-dim); font-weight: 600; }\n\n.ohud-pips { display: flex; gap: 5px; }\n.ohud-pip {\n  font-size: 8.5px; font-weight: 800; letter-spacing: 0.5px; padding: 2px 7px; border-radius: 6px;\n  border: 1px solid var(--odyssey-hud-border);\n}\n.ohud-pip.is-on { color: #06210f; background: var(--odyssey-hud-state-active); border-color: transparent; }\n.ohud-pip.is-off { color: var(--odyssey-hud-dim); background: transparent; }\n\n.ohud-pilot {\n  display: flex; align-items: center; gap: 6px; padding: 3px 7px; border-radius: 8px;\n  background: var(--odyssey-purple-panel); border: 1px solid rgba(167, 139, 250, 0.4);\n}\n.ohud-pilot-tag { font-size: 8px; font-weight: 800; letter-spacing: 1px; color: var(--odyssey-purple); }\n.ohud-pilot-name { font-size: 11px; color: var(--odyssey-hud-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n.ohud-pilot-psi { margin-left: auto; font-size: 10px; color: var(--odyssey-purple); }\n\n.ohud-statuses { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; }\n.ohud-chip-status {\n  display: inline-flex; align-items: center; gap: 4px; max-width: 100%;\n  font-size: 9.5px; padding: 1px 6px 1px 2px; border-radius: 9px;\n  border: 1px solid var(--odyssey-hud-border); background: var(--odyssey-panel-base);\n  color: var(--odyssey-hud-muted);\n}\n.ohud-chip-dot {\n  width: 14px; height: 14px; border-radius: 50%; display: grid; place-items: center;\n  font-size: 8px; font-weight: 800; color: #0a0e18;\n}\n.ohud-chip-status--positive .ohud-chip-dot { background: var(--odyssey-hud-positive); }\n.ohud-chip-status--negative .ohud-chip-dot { background: var(--odyssey-hud-negative); }\n.ohud-chip-status--neutral .ohud-chip-dot { background: var(--odyssey-hud-neutral); }\n.ohud-chip-name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n.ohud-chip-status--more { color: var(--odyssey-hud-dim); padding: 1px 7px; font-weight: 700; }\n\n/* ===================== Gun block ===================== */\n.ohud-gun { display: grid; grid-template-columns: 1fr 84px; gap: 8px; flex: 1; min-height: 0; }\n.ohud-gun.is-disabled { opacity: 0.55; }\n.ohud-gun-main {\n  position: relative; border-radius: var(--odyssey-hud-radius-inner);\n  border: 1.5px solid var(--odyssey-hud-border-strong);\n  background: var(--odyssey-bg-deep); padding: 6px 8px; min-width: 0; overflow: hidden;\n}\n.ohud-gun-name { position: absolute; top: 5px; left: 9px; font-size: 9.5px; color: var(--odyssey-hud-muted); }\n.ohud-gun-caret { position: absolute; top: 4px; right: 6px; color: var(--odyssey-hud-muted); display: inline-flex; }\n.ohud-gun-silhouette { position: absolute; inset: 14px 10px 12px; color: var(--odyssey-hud-weapon); display: block; }\n.ohud-gun-silhouette svg { width: 100%; height: 100%; }\n.ohud-firemode {\n  position: absolute; right: 8px; bottom: 7px;\n  display: inline-flex; align-items: center; gap: 5px;\n  padding: 2px 8px 2px 4px; border-radius: 12px;\n  background: var(--odyssey-panel-base); border: 1px solid var(--odyssey-hud-border);\n}\n.ohud-firemode-knob { width: 12px; height: 12px; border-radius: 50%; background: var(--odyssey-hud-muted); }\n.ohud-firemode-letter { font-size: 10px; font-weight: 700; color: var(--odyssey-hud-text); }\n.ohud-gun-secondary {\n  position: absolute; left: 8px; bottom: 7px; font-size: 9px; font-weight: 700;\n  color: var(--odyssey-hud-muted); border: 1px solid var(--odyssey-hud-border);\n  border-radius: 8px; padding: 1px 6px;\n}\n\n.ohud-gun-side { display: grid; grid-template-rows: 1fr 1fr; gap: 8px; min-width: 0; }\n.ohud-mag-card {\n  position: relative; display: flex; align-items: center; gap: 4px;\n  border-radius: var(--odyssey-hud-radius-inner);\n  border: 1px solid var(--odyssey-hud-border); background: var(--odyssey-panel-base);\n  padding: 4px 6px;\n}\n.ohud-mag-icon { width: 16px; height: 26px; color: var(--odyssey-steel); display: inline-flex; }\n.ohud-mag-icon svg { width: 100%; height: 100%; }\n.ohud-mag-caret { position: absolute; top: 3px; right: 4px; color: var(--odyssey-hud-muted); }\n.ohud-mag-type { margin-left: auto; font-size: 10px; font-weight: 700; color: var(--odyssey-hud-text); }\n.ohud-ammo-card {\n  display: flex; flex-direction: column; justify-content: center;\n  border-radius: var(--odyssey-hud-radius-inner);\n  border: 1px solid var(--odyssey-hud-border); background: var(--odyssey-panel-base);\n  padding: 3px 7px;\n}\n.ohud-ammo-head { display: flex; align-items: center; justify-content: space-between; }\n.ohud-ammo-label { font-size: 8.5px; letter-spacing: 1px; color: var(--odyssey-hud-dim); text-transform: uppercase; }\n.ohud-ammo-reload { color: var(--odyssey-hud-muted); display: inline-flex; }\n.ohud-ammo-reload.is-off { opacity: 0.35; }\n.ohud-ammo-count { font-weight: 800; line-height: 1; color: var(--odyssey-hud-text); font-variant-numeric: tabular-nums; }\n.ohud-ammo-cur { font-size: clamp(20px, 2.4vw, 30px); }\n.ohud-ammo-max { font-size: 12px; color: var(--odyssey-hud-dim); }\n.ohud-ammo-count--empty .ohud-ammo-cur { color: var(--odyssey-hud-negative); }\n.ohud-ammo-count--empty { border-radius: 6px; }\n\n/* ===================== Skill block ===================== */\n.ohud-slots {\n  display: grid; gap: 8px; flex: 1; min-height: 0;\n  grid-template-columns: repeat(auto-fit, minmax(48px, 1fr));\n  grid-auto-rows: 1fr; align-content: center;\n}\n.ohud-slot {\n  position: relative; aspect-ratio: 1 / 1; min-height: 44px;\n  border-radius: var(--odyssey-hud-radius-inner);\n  border: 1.5px solid var(--odyssey-hud-border);\n  background: var(--odyssey-bg-deep);\n  display: grid; place-items: center; color: var(--odyssey-hud-neutral);\n}\n.ohud-slot--empty { border-style: dashed; opacity: 0.4; background: transparent; }\n.ohud-slot-icon { width: 56%; height: 56%; display: inline-flex; }\n.ohud-slot-icon svg { width: 100%; height: 100%; }\n.ohud-accent--attack.ohud-slot { border-color: var(--odyssey-hud-attack); color: var(--odyssey-hud-attack); }\n.ohud-accent--psionic.ohud-slot { border-color: var(--odyssey-purple); color: var(--odyssey-purple); }\n.ohud-accent--implant.ohud-slot { border-color: var(--odyssey-cyan); color: var(--odyssey-cyan); }\n.ohud-accent--positive.ohud-slot { border-color: var(--odyssey-green); color: var(--odyssey-green); }\n.ohud-accent--neutral.ohud-slot { border-color: var(--odyssey-hud-border-strong); color: var(--odyssey-hud-neutral); }\n.ohud-slot.is-disabled { opacity: 0.42; filter: grayscale(0.4); }\n.ohud-slot.is-selected { box-shadow: 0 0 0 2px var(--odyssey-cyan); }\n.ohud-slot.is-toggled { background: rgba(167, 139, 250, 0.16); }\n.ohud-slot-cost {\n  position: absolute; left: 4px; bottom: 3px; font-size: 8px; font-weight: 800;\n  color: var(--odyssey-hud-dim);\n}\n.ohud-slot-res {\n  position: absolute; right: 4px; bottom: 3px; font-size: 8px; font-weight: 800;\n  color: var(--odyssey-purple);\n}\n.ohud-slot-cd {\n  position: absolute; top: 3px; right: 4px; font-size: 9px; font-weight: 800;\n  color: var(--odyssey-hud-warning);\n}\n.ohud-slot-toggle { position: absolute; top: 4px; left: 4px; width: 6px; height: 6px; border-radius: 50%; background: var(--odyssey-purple); }\n\n/* ===================== Target block ===================== */\n.ohud-target { display: flex; flex-direction: column; align-items: center; gap: 4px; flex: 1; min-height: 0; justify-content: center; }\n.ohud-target .ohud-figure { width: clamp(40px, 4.5vw, 56px); }\n.ohud-target-meta { text-align: center; min-width: 0; width: 100%; }\n.ohud-target-name {\n  font-size: 11px; font-weight: 700; color: var(--odyssey-hud-text);\n  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;\n}\n.ohud-target-zone {\n  display: inline-block; margin-top: 2px; font-size: 9px; font-weight: 800; letter-spacing: 0.8px;\n  color: var(--odyssey-cyan); border: 1px solid rgba(52, 225, 214, 0.4); border-radius: 7px; padding: 1px 7px;\n}\n.ohud-target.is-empty .ohud-target-hint {\n  font-size: 9.5px; font-weight: 700; letter-spacing: 0.6px; text-align: center;\n  color: var(--odyssey-hud-dim); line-height: 1.3;\n}\n\n/* ===================== Modifier block ===================== */\n.ohud-mods { display: grid; grid-template-columns: 1fr 1fr; gap: 5px; align-content: start; flex: 1; min-height: 0; overflow: hidden; }\n.ohud-mod {\n  display: flex; align-items: center; justify-content: space-between; gap: 4px;\n  font-size: 9.5px; padding: 3px 8px; border-radius: var(--odyssey-hud-radius-chip);\n  border: 1px solid var(--odyssey-hud-border); background: var(--odyssey-panel-base);\n  color: var(--odyssey-hud-muted); min-width: 0;\n}\n.ohud-mod-name { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }\n.ohud-mod-val { font-weight: 800; flex: 0 0 auto; }\n.ohud-mod--positive { border-color: rgba(74, 222, 128, 0.55); color: var(--odyssey-green); }\n.ohud-mod--negative { border-color: rgba(255, 92, 108, 0.6); color: var(--odyssey-red); }\n.ohud-mod--intervention { border-color: rgba(255, 194, 75, 0.6); color: var(--odyssey-yellow); }\n.ohud-mod--narrative { border-color: rgba(167, 139, 250, 0.55); color: var(--odyssey-purple); }\n.ohud-mod--neutral { color: var(--odyssey-hud-muted); }\n.ohud-mod.is-selected { box-shadow: 0 0 0 1.5px var(--odyssey-cyan); }\n.ohud-mod.is-passive { opacity: 0.85; background: var(--odyssey-bg-deep); }\n.ohud-mod--empty { border-style: dashed; opacity: 0.3; background: transparent; }\n\n/* ===================== Action block ===================== */\n.ohud-panel--action { gap: 5px; justify-content: center; }\n.ohud-action-btn {\n  width: 100%; flex: 1 1 auto; min-height: 40px;\n  display: grid; place-items: center; cursor: pointer; font: inherit;\n  border-radius: var(--odyssey-hud-radius-inner);\n  border: 1.5px solid var(--odyssey-purple);\n  background: linear-gradient(180deg, rgba(139, 92, 246, 0.22), rgba(38, 33, 92, 0.4));\n  color: var(--odyssey-purple);\n}\n.ohud-action-btn .ohud-action-label { font-size: clamp(15px, 1.6vw, 20px); font-weight: 800; letter-spacing: 2px; }\n.ohud-action-btn.is-ready:hover { background: rgba(139, 92, 246, 0.32); color: #fff; }\n.ohud-action-btn.is-disabled {\n  cursor: not-allowed; border-color: var(--odyssey-hud-border);\n  background: var(--odyssey-panel-base); color: var(--odyssey-hud-dim);\n}\n.ohud-action-econ { display: flex; gap: 5px; justify-content: center; }\n.ohud-econ-pip {\n  font-size: 8px; font-weight: 800; letter-spacing: 0.5px; padding: 1px 6px; border-radius: 6px;\n  color: var(--odyssey-hud-dim); border: 1px solid var(--odyssey-hud-border);\n}\n.ohud-econ-pip.is-spend { color: var(--odyssey-cyan); border-color: var(--odyssey-cyan); }\n.ohud-action-reason { font-size: 9px; text-align: center; color: var(--odyssey-hud-negative); min-height: 11px; }\n.ohud-action-reason--ok { color: var(--odyssey-hud-dim); }\n\n/* ===================== Battle log ===================== */\n.ohud-panel--log { overflow: hidden; }\n.ohud-log-list { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 3px; overflow-y: auto; flex: 1; min-height: 0; }\n.ohud-log-list::-webkit-scrollbar { width: 5px; }\n.ohud-log-list::-webkit-scrollbar-thumb { background: var(--odyssey-line); border-radius: 3px; }\n.ohud-log-row {\n  font-size: 10px; line-height: 1.25; color: var(--odyssey-hud-muted);\n  display: flex; flex-wrap: wrap; gap: 4px; align-items: baseline;\n  padding: 2px 4px; border-radius: 5px; background: var(--odyssey-bg-deep);\n}\n.ohud-log-row--system { color: var(--odyssey-hud-dim); background: transparent; font-style: italic; }\n.ohud-log-row--narr { color: var(--odyssey-purple); background: transparent; font-style: italic; }\n.ohud-log-actor { font-weight: 700; color: var(--odyssey-hud-text); }\n.ohud-log-act { color: var(--odyssey-hud-muted); }\n.ohud-log-arrow { color: var(--odyssey-hud-dim); }\n.ohud-log-target { color: var(--odyssey-hud-text); }\n.ohud-log-delta { margin-left: auto; font-weight: 700; font-size: 9.5px; }\n.ohud-log-delta--hit { color: var(--odyssey-green); }\n.ohud-log-delta--miss { color: var(--odyssey-hud-dim); }\n.ohud-log-delta--neutral { color: var(--odyssey-hud-muted); }\n.ohud-log-empty { font-size: 10px; color: var(--odyssey-hud-dim); display: grid; place-items: center; flex: 1; }\n.ohud-log-collapse {\n  display: inline-flex; align-items: center; justify-content: center; cursor: pointer;\n  width: 20px; height: 20px; border-radius: 5px; color: var(--odyssey-hud-muted);\n  background: transparent; border: 1px solid var(--odyssey-hud-border);\n}\n.ohud-log-collapse:hover { color: var(--odyssey-hud-text); }\n\n/* log floating button / panel (medium / compact / mini) */\n.ohud-log-float { position: absolute; top: 0; right: 6px; z-index: 6; }\n.ohud-log--button { padding: 0; border: 0; background: transparent; box-shadow: none; }\n.ohud-log-toggle {\n  display: inline-flex; align-items: center; gap: 6px; cursor: pointer; font: inherit;\n  font-size: 10px; font-weight: 700; letter-spacing: 0.5px; color: var(--odyssey-hud-muted);\n  background: var(--odyssey-hud-panel-raised); border: 1px solid var(--odyssey-hud-border);\n  border-radius: 8px; padding: 3px 9px;\n}\n.ohud-log-toggle:hover { color: var(--odyssey-hud-text); border-color: var(--odyssey-hud-border-strong); }\n.ohud-log-toggle-icon { display: inline-flex; }\n.ohud-log-badge {\n  font-size: 9px; font-weight: 800; color: #0a0e18; background: var(--odyssey-cyan);\n  border-radius: 8px; padding: 0 5px;\n}\n.ohud-log-float .ohud-log--expanded {\n  position: absolute; top: 26px; right: 0; width: 248px; max-height: 168px;\n  box-shadow: var(--odyssey-hud-shadow);\n}\n\n/* ===================== Empty / error / loading ===================== */\n.ohud-state-wrap {\n  flex: 1 1 auto; display: grid; place-items: center;\n  background: var(--odyssey-hud-panel); border: 1px solid var(--odyssey-hud-border);\n  border-radius: var(--odyssey-hud-radius); box-shadow: var(--odyssey-hud-shadow-soft);\n}\n.ohud-empty { text-align: center; padding: 12px; display: flex; flex-direction: column; align-items: center; gap: 6px; }\n.ohud-empty-mark { color: var(--odyssey-purple); opacity: 0.8; }\n.ohud-empty-title { font-size: 14px; font-weight: 800; letter-spacing: 1.5px; color: var(--odyssey-hud-text); }\n.ohud-empty-hint { font-size: 11px; color: var(--odyssey-hud-muted); max-width: 420px; }\n.ohud-empty--error .ohud-empty-title { color: var(--odyssey-hud-negative); }\n\n/* ===================== Toast ===================== */\n.ohud-toast {\n  position: absolute; left: 50%; bottom: 8px; transform: translateX(-50%);\n  font-size: 11px; color: var(--odyssey-hud-text);\n  background: var(--odyssey-panel-base); border: 1px solid var(--odyssey-hud-border-strong);\n  border-radius: 8px; padding: 5px 12px; box-shadow: var(--odyssey-hud-shadow); z-index: 10;\n}\n.ohud-toast[hidden] { display: none; }\n\n/* ===================== Tooltip ===================== */\n.ohud-tooltip {\n  position: fixed; z-index: 50; pointer-events: none; max-width: 240px;\n  background: var(--odyssey-bg-deep); border: 1px solid var(--odyssey-hud-border-strong);\n  border-radius: 8px; padding: 6px 9px; box-shadow: var(--odyssey-hud-shadow);\n}\n.ohud-tooltip[hidden] { display: none; }\n.ohud-tooltip-title { font-size: 11px; font-weight: 700; color: var(--odyssey-hud-text); }\n.ohud-tooltip-line { font-size: 10px; color: var(--odyssey-hud-muted); margin-top: 2px; }\n\n/* ===================== Compact text trims ===================== */\n.ohud-controls { flex-wrap: wrap; row-gap: 4px; }\n.ohud-brand-text { white-space: nowrap; }\n.ohud-hud[data-mode="compact"] .ohud-brand-sub,\n.ohud-hud[data-mode="mini"] .ohud-brand-sub { display: none; }\n.ohud-hud[data-mode="mini"] .ohud-res-label,\n.ohud-hud[data-mode="mini"] .ohud-dev-btn-label,\n.ohud-hud[data-mode="mini"] .ohud-fallback,\n.ohud-hud[data-mode="compact"] .ohud-fallback { display: none; }\n.ohud-hud[data-mode="mini"] .ohud-player-name { font-size: 11px; }\n';

// hud/adapters/combatHudAdapter.js
var REQUIRED_METHODS = Object.freeze([
  "getViewer",
  "getSelectedTokenId",
  "getSceneTokens",
  "getCharacterForToken",
  "getCharacterRuntime",
  "getWeaponState",
  "getAvailableSkills",
  "getModifiers",
  "getCombatSession",
  "getBattleLog",
  "selectToken",
  "setViewerRole",
  "setMockScenario",
  "subscribe",
  "dispose"
]);
function createCombatHudAdapter(impl, source) {
  if (!impl || typeof impl !== "object") {
    throw new Error("createCombatHudAdapter: implementation object is required.");
  }
  if (source !== "mock" && source !== "supabase") {
    throw new Error(`createCombatHudAdapter: invalid source "${source}".`);
  }
  const missing = REQUIRED_METHODS.filter((name) => typeof impl[name] !== "function");
  if (missing.length > 0) {
    throw new Error(
      `createCombatHudAdapter: missing required method(s): ${missing.join(", ")}.`
    );
  }
  const adapter = { source };
  for (const name of REQUIRED_METHODS) {
    adapter[name] = impl[name].bind(impl);
  }
  return Object.freeze(adapter);
}

// hud/models/combatHudContracts.js
var HUD_STATUS = Object.freeze({
  idle: "idle",
  loading: "loading",
  ready: "ready",
  empty: "empty",
  error: "error"
});
var HUD_SOURCE = Object.freeze({
  mock: "mock",
  supabase: "supabase"
});
var VIEWER_ROLES = Object.freeze({
  player: "player",
  gm: "gm"
});
var TOKEN_KINDS = Object.freeze({
  player: "player",
  npc: "npc",
  turret: "turret",
  mech: "mech",
  other: "other"
});
var ZONE_STATES = Object.freeze({
  healthy: "healthy",
  wounded: "wounded",
  serious: "serious",
  critical: "critical",
  disabled: "disabled"
});
var ZONE_STATE_ORDER = Object.freeze([
  ZONE_STATES.healthy,
  ZONE_STATES.wounded,
  ZONE_STATES.serious,
  ZONE_STATES.critical,
  ZONE_STATES.disabled
]);
var COMBAT_STATUS = Object.freeze({
  inactive: "inactive",
  active: "active",
  ended: "ended"
});
var SKILL_TYPES = Object.freeze({
  attackTechnique: "attackTechnique",
  targetedAbility: "targetedAbility",
  instantAbility: "instantAbility",
  toggleAbility: "toggleAbility",
  itemAction: "itemAction"
});
var SKILL_SOURCES = Object.freeze({
  perk: "perk",
  psionic: "psionic",
  implant: "implant",
  item: "item"
});
var ACTION_COSTS = Object.freeze({
  free: "FREE",
  move: "MOVE",
  main: "MAIN",
  turn: "TURN"
});
var COLOR_SEMANTICS = Object.freeze({
  attack: "attack",
  neutral: "neutral",
  psionic: "psionic",
  implant: "implant",
  intervention: "intervention",
  positive: "positive",
  negative: "negative"
});
var TARGETING_MODES = Object.freeze({
  none: "none",
  token: "token",
  multipleTokens: "multipleTokens",
  point: "point"
});
var MODIFIER_KINDS = Object.freeze({
  passive: "passive",
  active: "active",
  narrative: "narrative"
});
var MODIFIER_POLARITY = Object.freeze({
  positive: "positive",
  negative: "negative",
  neutral: "neutral"
});
var LOG_ENTRY_KINDS = Object.freeze({
  action: "action",
  system: "system",
  narrative: "narrative"
});
var EMPTY_REASONS = Object.freeze({
  noToken: "NO_TOKEN_SELECTED",
  noCharacterLink: "TOKEN_HAS_NO_CHARACTER",
  notOwner: "CHARACTER_NOT_CONTROLLED_BY_VIEWER"
});
var EMPTY_REASON_TEXT = Object.freeze({
  [EMPTY_REASONS.noToken]: "No token selected.",
  [EMPTY_REASONS.noCharacterLink]: "Selected token is not linked to a character.",
  [EMPTY_REASONS.notOwner]: "You do not control this character."
});
var DEFAULT_BODY_PART_ID = "torso";
function cloneDeep(value) {
  if (value === null || typeof value !== "object") return value;
  if (typeof structuredClone === "function") {
    try {
      return structuredClone(value);
    } catch (_error) {
    }
  }
  try {
    return JSON.parse(JSON.stringify(value));
  } catch (_error) {
    return value;
  }
}
function createEmptySnapshot() {
  return {
    entity: null,
    weapon: { primary: null, secondary: null },
    skills: { library: [], quickSlots: [] },
    combatSession: createInactiveCombatSession(),
    modifiers: { passive: [], active: [], narrative: [] },
    battleLog: { entries: [] }
  };
}
function createInactiveCombatSession() {
  return {
    id: null,
    status: COMBAT_STATUS.inactive,
    round: 0,
    currentParticipantId: null,
    participants: [],
    isViewerTurn: false
  };
}
function createDefaultUiState() {
  return {
    isHudCollapsed: false,
    selectedTechniqueId: null,
    selectedAbilityId: null,
    selectedReloadMagazineId: null,
    selectedModifierIds: [],
    targeting: createDefaultTargeting(),
    isBattleLogExpanded: false
  };
}
function createDefaultTargeting() {
  return {
    mode: TARGETING_MODES.none,
    selectedTargetIds: [],
    selectedBodyPartId: DEFAULT_BODY_PART_ID,
    selectedPoint: null,
    radius: null
  };
}

// hud/models/combatHudMockScenarios.js
var SELF_PLAYER = Object.freeze({ playerId: "obr-player-self", playerName: "Vega (You)" });
var OTHER_PLAYER = Object.freeze({ playerId: "obr-player-other", playerName: "Rook" });
function zone(id, label, state, canBeTargeted = true) {
  return { id, label, state, canBeTargeted };
}
function humanoidZones(states = {}) {
  return [
    zone("head", "Head", states.head ?? ZONE_STATES.healthy),
    zone("torso", "Torso", states.torso ?? ZONE_STATES.healthy),
    zone("l_arm", "Left Arm", states.l_arm ?? ZONE_STATES.healthy),
    zone("r_arm", "Right Arm", states.r_arm ?? ZONE_STATES.healthy),
    zone("l_leg", "Left Leg", states.l_leg ?? ZONE_STATES.healthy),
    zone("r_leg", "Right Leg", states.r_leg ?? ZONE_STATES.healthy)
  ];
}
function armor(zoneId, type, protection, durability, maxDurability) {
  return { zoneId, type, protection, durability, maxDurability };
}
function status(id, name, polarity, durationTurns, description) {
  return { id, name, polarity, durationTurns, description };
}
function magazine(id, ammoType, description, current2, max, caliber) {
  return { id, ammoType, description, current: current2, max, caliber };
}
function skill(overrides) {
  return {
    id: overrides.id,
    name: overrides.name ?? "Ability",
    type: overrides.type ?? SKILL_TYPES.instantAbility,
    source: overrides.source ?? SKILL_SOURCES.perk,
    icon: overrides.icon ?? "ability",
    color: overrides.color ?? COLOR_SEMANTICS.neutral,
    actionCost: overrides.actionCost ?? ACTION_COSTS.main,
    resourceCost: overrides.resourceCost ?? null,
    cooldownTurns: overrides.cooldownTurns ?? 0,
    weaponRequirements: overrides.weaponRequirements ?? [],
    targeting: overrides.targeting ?? TARGETING_MODES.none,
    allowsMultipleTargets: overrides.allowsMultipleTargets ?? false,
    usesPoint: overrides.usesPoint ?? false,
    radius: overrides.radius ?? null,
    isToggled: overrides.isToggled ?? false,
    disabledReason: overrides.disabledReason ?? null,
    tooltip: overrides.tooltip ?? ""
  };
}
function quickSlots(ids) {
  return ids.map((skillId, index) => ({ index, skillId: skillId ?? null }));
}
function modifier(overrides) {
  return {
    id: overrides.id,
    name: overrides.name ?? "Modifier",
    value: overrides.value ?? 0,
    source: overrides.source ?? "system",
    polarity: overrides.polarity ?? MODIFIER_POLARITY.neutral,
    selected: overrides.selected ?? false,
    alwaysActive: overrides.alwaysActive ?? false,
    requiresGMApproval: overrides.requiresGMApproval ?? false,
    consumesOnAction: overrides.consumesOnAction ?? false,
    kind: overrides.kind ?? MODIFIER_KINDS.active,
    description: overrides.description ?? ""
  };
}
function logEntry(sequence, kind, actor, action, target, delta, detail) {
  return {
    id: `log-${sequence}`,
    sequence,
    kind,
    actor,
    action,
    target,
    delta,
    summary: [actor, action, target, delta].filter(Boolean).join(" \xB7 "),
    detail: detail ?? ""
  };
}
function participant(overrides) {
  return {
    id: overrides.id,
    name: overrides.name ?? overrides.id,
    tokenId: overrides.tokenId ?? null,
    isPlayer: overrides.isPlayer ?? false,
    initiative: overrides.initiative ?? 0,
    initiativeRoll: overrides.initiativeRoll ?? 0,
    order: overrides.order ?? 0,
    isCurrent: overrides.isCurrent ?? false,
    canAct: overrides.canAct ?? true,
    condition: overrides.condition ?? "active"
  };
}
function makeVegaEntity() {
  return {
    summary: {
      id: "char-vega",
      name: "Vega",
      icon: "portrait-vega",
      characterType: TOKEN_KINDS.player,
      ownerPlayerId: SELF_PLAYER.playerId,
      svgRef: "humanoid"
    },
    zones: humanoidZones({
      l_arm: ZONE_STATES.wounded,
      r_leg: ZONE_STATES.serious
    }),
    shield: { current: 6, max: 15 },
    armorByZone: [
      armor("head", "Composite Helm", 3, 8, 10),
      armor("torso", "Ceramic Plate", 5, 14, 20),
      armor("l_arm", "Mesh", 2, 3, 6)
    ],
    psi: { current: 4, max: 10 },
    actions: { main: true, move: true },
    statuses: [
      status("st-focus", "Focused", MODIFIER_POLARITY.positive, 2, "+10 to next attack."),
      status("st-bleed", "Bleeding", MODIFIER_POLARITY.negative, 3, "Lose 1 minor wound per turn.")
    ],
    effects: [
      status("ef-adrenaline", "Adrenaline", MODIFIER_POLARITY.positive, 1, "MOVE actions are free this turn.")
    ],
    flags: { alive: true, conscious: true },
    mech: null,
    pilot: null
  };
}
function makeVegaWeapon() {
  return {
    id: "wpn-vega-rifle",
    name: "AR-7 Marksman Rifle",
    svgRef: "rifle",
    fireModes: ["Semi", "Burst"],
    currentFireMode: "Semi",
    usesMagazine: true,
    usesConsumable: false,
    requiresAmmo: true,
    loadedMagazine: magazine("mag-loaded", "AP", "Armor-piercing", 12, 30, "7.62"),
    reserveMagazines: [
      magazine("mag-full", "AP", "Armor-piercing", 30, 30, "7.62"),
      magazine("mag-partial", "HP", "Hollow-point", 8, 30, "7.62"),
      // The following two are intentionally invalid for the reserve list and
      // are filtered by selectVisibleReserveMagazines:
      magazine("mag-empty", "AP", "Armor-piercing", 0, 30, "7.62"),
      // empty
      magazine("mag-wrong", "SG", "Shotgun shells", 6, 6, "12ga")
      // wrong caliber
    ],
    ammo: { current: 12, max: 30 },
    reloadCandidateId: "mag-full",
    canReload: true,
    disabledReason: null
  };
}
function makeVegaSkills() {
  const library = [
    skill({
      id: "sk-precise",
      name: "Precision Shot",
      type: SKILL_TYPES.attackTechnique,
      source: SKILL_SOURCES.perk,
      icon: "scope",
      color: COLOR_SEMANTICS.attack,
      actionCost: ACTION_COSTS.main,
      weaponRequirements: ["rifle"],
      targeting: TARGETING_MODES.token,
      tooltip: "Aimed shot. +precision, zone penalty unchanged."
    }),
    skill({
      id: "sk-burst",
      name: "Suppressive Burst",
      type: SKILL_TYPES.attackTechnique,
      source: SKILL_SOURCES.perk,
      icon: "burst",
      color: COLOR_SEMANTICS.attack,
      actionCost: ACTION_COSTS.main,
      weaponRequirements: ["rifle"],
      targeting: TARGETING_MODES.multipleTokens,
      allowsMultipleTargets: true,
      tooltip: "Hit up to 3 targets in an arc."
    }),
    skill({
      id: "sk-mindspike",
      name: "Mind Spike",
      type: SKILL_TYPES.targetedAbility,
      source: SKILL_SOURCES.psionic,
      icon: "psi",
      color: COLOR_SEMANTICS.psionic,
      actionCost: ACTION_COSTS.main,
      resourceCost: { type: "psi", amount: 3 },
      cooldownTurns: 2,
      targeting: TARGETING_MODES.token,
      tooltip: "Psionic damage to one mind. Costs 3 Psi, 2-turn cooldown."
    }),
    skill({
      id: "sk-grenade",
      name: "Frag Grenade",
      type: SKILL_TYPES.itemAction,
      source: SKILL_SOURCES.item,
      icon: "grenade",
      color: COLOR_SEMANTICS.attack,
      actionCost: ACTION_COSTS.main,
      targeting: TARGETING_MODES.point,
      usesPoint: true,
      radius: 3,
      tooltip: "Throw to a point. 3m blast radius."
    }),
    skill({
      id: "sk-stim",
      name: "Combat Stim",
      type: SKILL_TYPES.instantAbility,
      source: SKILL_SOURCES.item,
      icon: "injector",
      color: COLOR_SEMANTICS.positive,
      actionCost: ACTION_COSTS.free,
      tooltip: "Instant self-heal. No confirmation."
    }),
    skill({
      id: "sk-cloak",
      name: "Optic Cloak",
      type: SKILL_TYPES.toggleAbility,
      source: SKILL_SOURCES.implant,
      icon: "cloak",
      color: COLOR_SEMANTICS.implant,
      actionCost: ACTION_COSTS.move,
      isToggled: false,
      tooltip: "Toggle camouflage. Active until disabled."
    }),
    skill({
      id: "sk-overload",
      name: "Implant Overload",
      type: SKILL_TYPES.instantAbility,
      source: SKILL_SOURCES.implant,
      icon: "bolt",
      color: COLOR_SEMANTICS.implant,
      actionCost: ACTION_COSTS.main,
      cooldownTurns: 4,
      disabledReason: "On cooldown (3 turns left).",
      tooltip: "Disabled: cooling down."
    })
  ];
  return { library, quickSlots: quickSlots([
    "sk-precise",
    "sk-burst",
    "sk-mindspike",
    "sk-grenade",
    "sk-stim",
    "sk-cloak",
    null,
    "sk-overload"
  ]) };
}
function makeVegaModifiers() {
  return [
    modifier({
      id: "mod-veteran",
      name: "Veteran Aim",
      value: 5,
      source: "perk",
      polarity: MODIFIER_POLARITY.positive,
      alwaysActive: true,
      kind: MODIFIER_KINDS.passive,
      description: "Passive +5 to ranged attacks."
    }),
    modifier({
      id: "mod-scope",
      name: "Scope",
      value: 10,
      source: "weapon",
      polarity: MODIFIER_POLARITY.positive,
      alwaysActive: true,
      kind: MODIFIER_KINDS.passive,
      description: "Passive +10 when aiming."
    }),
    modifier({
      id: "mod-cover",
      name: "Target in Cover",
      value: -10,
      source: "positioning",
      polarity: MODIFIER_POLARITY.negative,
      kind: MODIFIER_KINDS.active,
      description: "Apply when the target benefits from cover."
    }),
    modifier({
      id: "mod-prepared",
      name: "Prepared",
      value: 20,
      source: "positioning",
      polarity: MODIFIER_POLARITY.positive,
      kind: MODIFIER_KINDS.active,
      description: "Aim taken last turn."
    }),
    modifier({
      id: "mod-godbless",
      name: "God Bless",
      value: 0,
      source: "intervention",
      polarity: MODIFIER_POLARITY.positive,
      kind: MODIFIER_KINDS.active,
      consumesOnAction: true,
      description: "Intervention: re-roll. Resource consumed only on success."
    }),
    modifier({
      id: "mod-gm-highground",
      name: "High Ground (GM)",
      value: 15,
      source: "gm",
      polarity: MODIFIER_POLARITY.positive,
      kind: MODIFIER_KINDS.narrative,
      requiresGMApproval: true,
      description: "GM-granted narrative bonus."
    })
  ];
}
function makeRaiderEntity() {
  return {
    summary: {
      id: "char-raider",
      name: "Scrap Raider",
      icon: "portrait-raider",
      characterType: TOKEN_KINDS.npc,
      ownerPlayerId: null,
      svgRef: "humanoid"
    },
    zones: humanoidZones({ torso: ZONE_STATES.wounded, head: ZONE_STATES.healthy }),
    shield: { current: 0, max: 0 },
    armorByZone: [],
    // hidden from players; GM view still keeps it minimal in mocks
    psi: { current: 0, max: 0 },
    actions: { main: true, move: true },
    statuses: [status("st-enraged", "Enraged", MODIFIER_POLARITY.negative, null, "Attacks recklessly.")],
    effects: [],
    flags: { alive: true, conscious: true },
    mech: null,
    pilot: null
  };
}
function scenario(base) {
  return {
    id: base.id,
    label: base.label,
    description: base.description,
    defaultViewerRole: base.defaultViewerRole,
    viewer: base.viewer,
    selectedTokenId: base.selectedTokenId ?? null,
    tokens: base.tokens ?? [],
    links: base.links ?? {},
    characters: base.characters ?? {},
    weapons: base.weapons ?? {},
    skills: base.skills ?? {},
    modifiers: base.modifiers ?? {},
    combatSession: base.combatSession ?? null,
    battleLog: base.battleLog ?? { entries: [] }
  };
}
function scenarioA() {
  const tokens = [
    { tokenId: "tok-vega", name: "Vega", characterId: "char-vega", kind: TOKEN_KINDS.player, position: { x: 4, y: 2 } },
    { tokenId: "tok-raider", name: "Scrap Raider", characterId: "char-raider", kind: TOKEN_KINDS.npc, position: { x: 9, y: 3 } },
    // Unlinked scene prop — exists as a token but maps to no character.
    // Used to exercise the "token without character" empty state.
    { tokenId: "tok-crate", name: "Supply Crate", characterId: null, kind: TOKEN_KINDS.other, position: { x: 2, y: 8 } }
  ];
  return scenario({
    id: "A",
    label: "A \xB7 Player, own turn",
    description: "Owned player character, active combat, it is the viewer's turn.",
    defaultViewerRole: VIEWER_ROLES.player,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.player },
    selectedTokenId: "tok-vega",
    tokens,
    links: { "tok-vega": "char-vega", "tok-raider": "char-raider" },
    characters: { "char-vega": makeVegaEntity(), "char-raider": makeRaiderEntity() },
    weapons: { "char-vega": { primary: makeVegaWeapon(), secondary: null } },
    skills: { "char-vega": makeVegaSkills() },
    modifiers: { "char-vega": makeVegaModifiers() },
    combatSession: {
      id: "sess-1",
      status: COMBAT_STATUS.active,
      round: 2,
      currentParticipantId: "char-vega",
      participants: [
        participant({ id: "char-vega", name: "Vega", tokenId: "tok-vega", isPlayer: true, initiative: 22, initiativeRoll: 18, order: 0, isCurrent: true }),
        participant({ id: "char-raider", name: "Scrap Raider", tokenId: "tok-raider", initiative: 14, initiativeRoll: 11, order: 1 })
      ]
    },
    battleLog: { entries: [
      logEntry(1, LOG_ENTRY_KINDS.system, "", "Combat started", "", "", "Round 1 begins."),
      logEntry(2, LOG_ENTRY_KINDS.action, "Scrap Raider", "Attacks", "Vega", "Shield -4", "Rolled 65 vs torso."),
      logEntry(3, LOG_ENTRY_KINDS.action, "Vega", "Precision Shot", "Scrap Raider", "Wounds head", "Rolled 12, hit."),
      logEntry(4, LOG_ENTRY_KINDS.narrative, "GM", "Smoke drifts across the lane", "", "", "Light cover next round."),
      logEntry(5, LOG_ENTRY_KINDS.system, "", "Round 2 begins", "", "", "Actions restored.")
    ] }
  });
}
function scenarioB() {
  const a = scenarioA();
  const vega = a.characters["char-vega"];
  vega.actions = { main: false, move: false };
  return scenario({
    ...a,
    id: "B",
    label: "B \xB7 Player, waiting",
    description: "Owned player character, combat active, NOT the viewer's turn.",
    combatSession: {
      ...a.combatSession,
      currentParticipantId: "char-raider",
      participants: a.combatSession.participants.map((p) => ({
        ...p,
        isCurrent: p.id === "char-raider"
      }))
    }
  });
}
function scenarioC() {
  const tokens = [
    { tokenId: "tok-raider", name: "Scrap Raider", characterId: "char-raider", kind: TOKEN_KINDS.npc, position: { x: 9, y: 3 } }
  ];
  return scenario({
    id: "C",
    label: "C \xB7 NPC target (humanoid)",
    description: "Linked NPC humanoid. Player gets empty HUD; GM can inspect.",
    defaultViewerRole: VIEWER_ROLES.gm,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.gm },
    selectedTokenId: "tok-raider",
    tokens,
    links: { "tok-raider": "char-raider" },
    characters: { "char-raider": makeRaiderEntity() },
    weapons: {},
    skills: {},
    modifiers: {},
    combatSession: null,
    battleLog: { entries: [] }
  });
}
function scenarioD() {
  const turret = {
    summary: {
      id: "char-turret",
      name: "Sentry Turret MK-II",
      icon: "portrait-turret",
      characterType: TOKEN_KINDS.turret,
      ownerPlayerId: null,
      svgRef: "turret"
    },
    zones: [
      zone("barrel", "Barrel Assembly", ZONE_STATES.healthy),
      zone("housing", "Housing", ZONE_STATES.wounded),
      zone("sensor", "Sensor Array", ZONE_STATES.serious),
      zone("base", "Base Mount", ZONE_STATES.healthy, false)
    ],
    shield: { current: 10, max: 10 },
    armorByZone: [armor("housing", "Plated Steel", 6, 18, 25)],
    psi: { current: 0, max: 0 },
    actions: { main: true, move: false },
    statuses: [],
    effects: [status("ef-overheat", "Overheating", MODIFIER_POLARITY.negative, 1, "Skips next turn if not cooled.")],
    flags: { alive: true, conscious: true },
    mech: null,
    pilot: null
  };
  return scenario({
    id: "D",
    label: "D \xB7 Turret target (non-humanoid)",
    description: "Non-humanoid entity with a custom zone schema and its own SVG.",
    defaultViewerRole: VIEWER_ROLES.gm,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.gm },
    selectedTokenId: "tok-turret",
    tokens: [{ tokenId: "tok-turret", name: "Sentry Turret", characterId: "char-turret", kind: TOKEN_KINDS.turret, position: { x: 12, y: 7 } }],
    links: { "tok-turret": "char-turret" },
    characters: { "char-turret": turret }
  });
}
function scenarioE() {
  const pilotPsi = { current: 5, max: 8 };
  const mechEntity = {
    summary: {
      id: "char-vega",
      name: "Vega \u2014 'Ironclad' Mech",
      icon: "portrait-mech",
      characterType: TOKEN_KINDS.mech,
      ownerPlayerId: SELF_PLAYER.playerId,
      svgRef: "mech"
    },
    // Top-level zones mirror the mech while piloting.
    zones: [
      zone("m_head", "Cockpit", ZONE_STATES.healthy),
      zone("m_core", "Reactor Core", ZONE_STATES.wounded),
      zone("m_l_arm", "Left Manipulator", ZONE_STATES.healthy),
      zone("m_r_arm", "Right Weapon Mount", ZONE_STATES.serious),
      zone("m_legs", "Locomotion", ZONE_STATES.healthy)
    ],
    shield: { current: 25, max: 40 },
    armorByZone: [
      armor("m_core", "Reactor Shielding", 12, 30, 50),
      armor("m_r_arm", "Hardpoint Plating", 9, 12, 30)
    ],
    psi: pilotPsi,
    actions: { main: true, move: true },
    statuses: [status("st-locked", "Weapons Locked", MODIFIER_POLARITY.positive, null, "Targeting computer engaged.")],
    effects: [],
    flags: { alive: true, conscious: true },
    mech: {
      active: true,
      name: "'Ironclad' Assault Frame",
      zones: [
        zone("m_core", "Reactor Core", ZONE_STATES.wounded),
        zone("m_r_arm", "Right Weapon Mount", ZONE_STATES.serious)
      ],
      shield: { current: 25, max: 40 },
      armorByZone: [armor("m_core", "Reactor Shielding", 12, 30, 50)]
    },
    pilot: {
      characterId: "char-vega-pilot",
      name: "Vega",
      icon: "portrait-vega",
      psi: pilotPsi,
      statuses: [status("st-strain", "Neural Strain", MODIFIER_POLARITY.negative, 2, "Psi regen halved.")],
      flags: { alive: true, conscious: true }
    }
  };
  return scenario({
    id: "E",
    label: "E \xB7 Mech + pilot",
    description: "Mech is the primary displayed entity; pilot summary nested beneath.",
    defaultViewerRole: VIEWER_ROLES.player,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.player },
    selectedTokenId: "tok-mech",
    tokens: [{ tokenId: "tok-mech", name: "Ironclad", characterId: "char-vega", kind: TOKEN_KINDS.mech, position: { x: 5, y: 5 } }],
    links: { "tok-mech": "char-vega" },
    characters: { "char-vega": mechEntity },
    weapons: { "char-vega": { primary: makeVegaWeapon(), secondary: null } },
    skills: { "char-vega": makeVegaSkills() },
    modifiers: { "char-vega": makeVegaModifiers() },
    combatSession: {
      id: "sess-2",
      status: COMBAT_STATUS.active,
      round: 1,
      currentParticipantId: "char-vega",
      participants: [participant({ id: "char-vega", name: "Ironclad", tokenId: "tok-mech", isPlayer: true, initiative: 19, initiativeRoll: 15, order: 0, isCurrent: true })]
    },
    battleLog: { entries: [logEntry(1, LOG_ENTRY_KINDS.system, "", "Combat started", "", "", "Mech deployed.")] }
  });
}
function scenarioF() {
  return scenario({
    id: "F",
    label: "F \xB7 Unauthorised selection",
    description: "Player selects an NPC they do not control \u2192 empty HUD with reason.",
    defaultViewerRole: VIEWER_ROLES.player,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.player },
    selectedTokenId: "tok-raider",
    tokens: [{ tokenId: "tok-raider", name: "Scrap Raider", characterId: "char-raider", kind: TOKEN_KINDS.npc, position: { x: 9, y: 3 } }],
    links: { "tok-raider": "char-raider" },
    characters: { "char-raider": makeRaiderEntity() }
  });
}
function scenarioG() {
  const f = scenarioF();
  return scenario({
    ...f,
    id: "G",
    label: "G \xB7 GM inspection",
    description: "Same selection as F, but the viewer is GM \u2192 HUD becomes ready.",
    defaultViewerRole: VIEWER_ROLES.gm,
    viewer: { ...SELF_PLAYER, role: VIEWER_ROLES.gm }
  });
}
var MOCK_SCENARIOS = Object.freeze([
  { id: "A", label: "A \xB7 Player, own turn", create: scenarioA },
  { id: "B", label: "B \xB7 Player, waiting", create: scenarioB },
  { id: "C", label: "C \xB7 NPC target (humanoid)", create: scenarioC },
  { id: "D", label: "D \xB7 Turret target (non-humanoid)", create: scenarioD },
  { id: "E", label: "E \xB7 Mech + pilot", create: scenarioE },
  { id: "F", label: "F \xB7 Unauthorised selection", create: scenarioF },
  { id: "G", label: "G \xB7 GM inspection", create: scenarioG }
]);
var DEFAULT_SCENARIO_ID = "A";
function createScenario(scenarioId) {
  const entry = MOCK_SCENARIOS.find((s) => s.id === scenarioId);
  if (!entry) {
    throw new Error(`Unknown mock scenario: ${scenarioId}`);
  }
  return entry.create();
}
function listScenarios() {
  return MOCK_SCENARIOS.map(({ id, label }) => ({ id, label }));
}

// hud/adapters/mockCombatHudAdapter.js
function createMockCombatHudAdapter(options = {}) {
  const listeners = /* @__PURE__ */ new Set();
  let scenario2 = createScenario(options.scenarioId ?? DEFAULT_SCENARIO_ID);
  let selectedTokenOverride = void 0;
  let roleOverride = void 0;
  let disposed = false;
  function notify() {
    if (disposed) return;
    for (const listener of Array.from(listeners)) {
      try {
        listener();
      } catch (error) {
        console.error("[combatHud/mock] listener threw", error);
      }
    }
  }
  function currentSelectedTokenId() {
    return selectedTokenOverride !== void 0 ? selectedTokenOverride : scenario2.selectedTokenId;
  }
  function currentRole() {
    return roleOverride !== void 0 ? roleOverride : scenario2.viewer.role;
  }
  const impl = {
    /* ----------------- data getters ----------------- */
    getViewer() {
      return { ...scenario2.viewer, role: currentRole() };
    },
    getSelectedTokenId() {
      return currentSelectedTokenId() ?? null;
    },
    getSceneTokens() {
      return scenario2.tokens;
    },
    getCharacterForToken(tokenId) {
      if (!tokenId) return null;
      const characterId = scenario2.links[tokenId] ?? null;
      const token = scenario2.tokens.find((t) => t.tokenId === tokenId) ?? null;
      if (!characterId || !token) return null;
      return { characterId, token };
    },
    getCharacterRuntime(characterId) {
      if (!characterId) return null;
      return scenario2.characters[characterId] ?? null;
    },
    getWeaponState(characterId) {
      if (!characterId) return null;
      return scenario2.weapons[characterId] ?? null;
    },
    getAvailableSkills(characterId) {
      if (!characterId) return { library: [], quickSlots: [] };
      return scenario2.skills[characterId] ?? { library: [], quickSlots: [] };
    },
    getModifiers(characterId) {
      if (!characterId) return [];
      return scenario2.modifiers[characterId] ?? [];
    },
    getCombatSession() {
      return scenario2.combatSession ?? null;
    },
    getBattleLog(_sessionId) {
      return scenario2.battleLog ?? { entries: [] };
    },
    /* ----------------- mutators ----------------- */
    selectToken(tokenId) {
      selectedTokenOverride = tokenId ?? null;
      notify();
    },
    setViewerRole(role) {
      roleOverride = role;
      notify();
    },
    setMockScenario(scenarioId) {
      scenario2 = createScenario(scenarioId);
      selectedTokenOverride = void 0;
      roleOverride = void 0;
      notify();
    },
    /* ----------------- lifecycle ----------------- */
    subscribe(listener) {
      if (typeof listener !== "function") return () => {
      };
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    dispose() {
      disposed = true;
      listeners.clear();
    }
  };
  return createCombatHudAdapter(impl, "mock");
}

// hud/core/combatHudActions.js
function createInitialState(source = HUD_SOURCE.mock) {
  return {
    status: HUD_STATUS.idle,
    source,
    viewer: { playerId: "", playerName: "", role: VIEWER_ROLES.player },
    selectedTokenId: null,
    selectedCharacterId: null,
    access: { canViewSelectedCharacter: false, reason: null },
    snapshot: createEmptySnapshot(),
    ui: createDefaultUiState(),
    error: null
  };
}
function computeAccess(viewer, entity) {
  if (!entity) {
    return { canView: false, reason: EMPTY_REASONS.noCharacterLink };
  }
  if (viewer?.role === VIEWER_ROLES.gm) {
    return { canView: true, reason: null };
  }
  const ownerId = entity.summary?.ownerPlayerId ?? null;
  if (ownerId && viewer?.playerId && ownerId === viewer.playerId) {
    return { canView: true, reason: null };
  }
  return { canView: false, reason: EMPTY_REASONS.notOwner };
}
function applyViewer(state, viewer) {
  return {
    ...state,
    viewer: {
      playerId: String(viewer?.playerId ?? ""),
      playerName: String(viewer?.playerName ?? ""),
      role: viewer?.role === VIEWER_ROLES.gm ? VIEWER_ROLES.gm : VIEWER_ROLES.player
    }
  };
}
function applyLoading(state) {
  return { ...state, status: HUD_STATUS.loading, error: null };
}
function applySelectionResult(state, resolved) {
  const base = applyViewer(state, resolved.viewer);
  if (!resolved.selectedTokenId) {
    return {
      ...base,
      status: HUD_STATUS.empty,
      selectedTokenId: null,
      selectedCharacterId: null,
      access: { canViewSelectedCharacter: false, reason: EMPTY_REASONS.noToken },
      snapshot: createEmptySnapshot(),
      error: null
    };
  }
  if (!resolved.characterId || !resolved.entity) {
    return {
      ...base,
      status: HUD_STATUS.empty,
      selectedTokenId: resolved.selectedTokenId,
      selectedCharacterId: null,
      access: { canViewSelectedCharacter: false, reason: EMPTY_REASONS.noCharacterLink },
      snapshot: createEmptySnapshot(),
      error: null
    };
  }
  const access = computeAccess(resolved.viewer, resolved.entity);
  if (!access.canView) {
    return {
      ...base,
      status: HUD_STATUS.empty,
      selectedTokenId: resolved.selectedTokenId,
      selectedCharacterId: resolved.characterId,
      access: { canViewSelectedCharacter: false, reason: access.reason },
      snapshot: createEmptySnapshot(),
      error: null
    };
  }
  return {
    ...base,
    status: HUD_STATUS.ready,
    selectedTokenId: resolved.selectedTokenId,
    selectedCharacterId: resolved.characterId,
    access: { canViewSelectedCharacter: true, reason: null },
    snapshot: resolved.snapshot,
    error: null
  };
}
function applyError(state, message, cause = null) {
  return {
    ...state,
    status: HUD_STATUS.error,
    error: { message: String(message ?? "Unknown error"), cause: cause ? String(cause) : null }
  };
}
function setCollapsed(state, isCollapsed) {
  return { ...state, ui: { ...state.ui, isHudCollapsed: Boolean(isCollapsed) } };
}
function resetActionDraft(state) {
  return {
    ...state,
    ui: {
      ...state.ui,
      selectedTechniqueId: null,
      selectedAbilityId: null,
      selectedReloadMagazineId: null,
      selectedModifierIds: [],
      targeting: createDefaultTargeting()
      // isHudCollapsed and isBattleLogExpanded are view prefs, intentionally kept.
    }
  };
}
function assembleSnapshot(pieces) {
  const snapshot = createEmptySnapshot();
  snapshot.entity = cloneDeep(pieces.entity) ?? null;
  if (pieces.weapon) {
    snapshot.weapon = {
      primary: cloneDeep(pieces.weapon.primary) ?? null,
      secondary: cloneDeep(pieces.weapon.secondary) ?? null
    };
  }
  snapshot.skills = {
    library: cloneDeep(pieces.skills?.library ?? []),
    quickSlots: cloneDeep(pieces.skills?.quickSlots ?? [])
  };
  const session = pieces.combatSession ? cloneDeep(pieces.combatSession) : null;
  if (session) {
    session.isViewerTurn = computeIsViewerTurn(session, pieces.selectedCharacterId);
    snapshot.combatSession = normalizeCombatSession(session);
  }
  const groups = { passive: [], active: [], narrative: [] };
  for (const mod of cloneDeep(pieces.modifiers ?? [])) {
    const bucket = groups[mod.kind] ? mod.kind : "active";
    groups[bucket].push(mod);
  }
  snapshot.modifiers = groups;
  snapshot.battleLog = { entries: cloneDeep(pieces.battleLog?.entries ?? []) };
  return snapshot;
}
function computeIsViewerTurn(session, selectedCharacterId) {
  if (!session || session.status !== "active") return false;
  if (!selectedCharacterId) return false;
  return session.currentParticipantId === selectedCharacterId;
}
function normalizeCombatSession(session) {
  return {
    id: session.id ?? null,
    status: session.status ?? "inactive",
    round: Number(session.round ?? 0) || 0,
    currentParticipantId: session.currentParticipantId ?? null,
    participants: Array.isArray(session.participants) ? session.participants : [],
    isViewerTurn: Boolean(session.isViewerTurn)
  };
}

// hud/core/combatHudStore.js
function createCombatHudStore({ adapter }) {
  if (!adapter || typeof adapter.subscribe !== "function") {
    throw new Error("createCombatHudStore: a valid adapter is required.");
  }
  let state = createInitialState(adapter.source);
  const listeners = /* @__PURE__ */ new Set();
  let disposed = false;
  let unsubscribeAdapter = null;
  function setState(next) {
    state = next;
    emit();
  }
  function emit() {
    if (disposed) return;
    for (const listener of Array.from(listeners)) {
      try {
        listener(state);
      } catch (error) {
        console.error("[combatHud/store] listener threw", error);
      }
    }
  }
  function refreshRuntime() {
    if (disposed) return;
    try {
      const viewer = adapter.getViewer();
      const selectedTokenId = adapter.getSelectedTokenId();
      if (!selectedTokenId) {
        setState(applySelectionResult(state, {
          viewer,
          selectedTokenId: null,
          characterId: null,
          entity: null,
          snapshot: state.snapshot
        }));
        return;
      }
      const link = adapter.getCharacterForToken(selectedTokenId);
      const characterId = link?.characterId ?? null;
      const entity = characterId ? adapter.getCharacterRuntime(characterId) : null;
      if (!characterId || !entity) {
        setState(applySelectionResult(state, {
          viewer,
          selectedTokenId,
          characterId,
          entity: null,
          snapshot: state.snapshot
        }));
        return;
      }
      const weapon = adapter.getWeaponState(characterId);
      const skills = adapter.getAvailableSkills(characterId);
      const modifiers = adapter.getModifiers(characterId);
      const combatSession = adapter.getCombatSession();
      const battleLog = adapter.getBattleLog(combatSession?.id ?? null);
      const snapshot = assembleSnapshot({
        entity,
        weapon,
        skills,
        combatSession,
        modifiers,
        battleLog,
        selectedCharacterId: characterId
      });
      setState(applySelectionResult(state, {
        viewer,
        selectedTokenId,
        characterId,
        entity,
        snapshot
      }));
    } catch (error) {
      setState(applyError(state, "Failed to refresh Combat HUD state.", error?.message ?? error));
    }
  }
  function initialize() {
    if (disposed) return;
    setState(applyLoading(state));
    if (!unsubscribeAdapter) {
      unsubscribeAdapter = adapter.subscribe(() => refreshRuntime());
    }
    refreshRuntime();
  }
  function selectToken(tokenId) {
    if (disposed) return;
    adapter.selectToken(tokenId ?? null);
  }
  function setViewerRole(role) {
    if (disposed) return;
    adapter.setViewerRole(role);
  }
  function setViewer(viewer) {
    if (disposed) return;
    setState(applyViewer(state, viewer));
    refreshRuntime();
  }
  function setHudCollapsed(isCollapsed) {
    if (disposed) return;
    setState(setCollapsed(state, isCollapsed));
  }
  function setMockScenario(scenarioId) {
    if (disposed) return;
    try {
      adapter.setMockScenario(scenarioId);
    } catch (error) {
      setState(applyError(state, "setMockScenario is not supported by this adapter.", error?.message ?? error));
    }
  }
  function resetActionDraft2() {
    if (disposed) return;
    setState(resetActionDraft(state));
  }
  function getState() {
    return state;
  }
  function subscribe(listener) {
    if (typeof listener !== "function") return () => {
    };
    listeners.add(listener);
    return () => {
      listeners.delete(listener);
    };
  }
  function dispose() {
    if (disposed) return;
    disposed = true;
    if (typeof unsubscribeAdapter === "function") {
      try {
        unsubscribeAdapter();
      } catch (_e) {
      }
      unsubscribeAdapter = null;
    }
    listeners.clear();
  }
  return {
    // lifecycle
    initialize,
    dispose,
    // reads
    getState,
    subscribe,
    // actions
    selectToken,
    setViewer,
    setViewerRole,
    setHudCollapsed,
    setMockScenario,
    resetActionDraft: resetActionDraft2,
    // exposed for diagnostics/tests
    get status() {
      return state.status;
    },
    isReady() {
      return state.status === HUD_STATUS.ready;
    }
  };
}

// hud/overlay/overlayConstants.js
var BC_HUD_UI_STATE = "com.odyssey.combat-hud/ui-state";
var WIDE_BREAKPOINT = 1280;
var MEDIUM_BREAKPOINT = 960;
var MINI_BREAKPOINT = 620;
function resolveLayoutMode(width) {
  const w = Math.max(0, Number(width) || 0);
  if (w >= WIDE_BREAKPOINT) return "wide";
  if (w >= MEDIUM_BREAKPOINT) return "medium";
  if (w >= MINI_BREAKPOINT) return "compact";
  return "mini";
}
var ANCHOR_ORIGIN = Object.freeze({ horizontal: "CENTER", vertical: "BOTTOM" });
var TRANSFORM_ORIGIN = Object.freeze({ horizontal: "CENTER", vertical: "BOTTOM" });
var DEFAULT_HUD_UI_STATE = Object.freeze({
  isHudCollapsed: false,
  mockScenarioId: "A",
  viewerRole: "player",
  selectedTokenId: null
});
var HUD_UI_PARAM_KEYS = Object.freeze({
  collapsed: "collapsed",
  scenario: "scenario",
  role: "role",
  token: "token"
});
function parseHudUiState(search) {
  const out = {};
  let params;
  try {
    params = new URLSearchParams(search || "");
  } catch {
    return out;
  }
  if (params.has(HUD_UI_PARAM_KEYS.collapsed)) {
    out.isHudCollapsed = params.get(HUD_UI_PARAM_KEYS.collapsed) === "1";
  }
  const scenario2 = params.get(HUD_UI_PARAM_KEYS.scenario);
  if (scenario2) out.mockScenarioId = scenario2;
  const role = params.get(HUD_UI_PARAM_KEYS.role);
  if (role === "player" || role === "gm") out.viewerRole = role;
  if (params.has(HUD_UI_PARAM_KEYS.token)) {
    const token = params.get(HUD_UI_PARAM_KEYS.token);
    out.selectedTokenId = token ? token : null;
  }
  return out;
}
function normalizeHudUiState(partial) {
  const p = partial && typeof partial === "object" ? partial : {};
  return {
    isHudCollapsed: typeof p.isHudCollapsed === "boolean" ? p.isHudCollapsed : DEFAULT_HUD_UI_STATE.isHudCollapsed,
    mockScenarioId: p.mockScenarioId != null && p.mockScenarioId !== "" ? String(p.mockScenarioId) : DEFAULT_HUD_UI_STATE.mockScenarioId,
    viewerRole: p.viewerRole === "gm" ? "gm" : "player",
    selectedTokenId: Object.prototype.hasOwnProperty.call(p, "selectedTokenId") ? p.selectedTokenId : DEFAULT_HUD_UI_STATE.selectedTokenId
  };
}

// hud/components/hudLayoutModel.js
function resolveBattleLogMode(mode, expanded) {
  if (mode === "wide") return expanded ? "expanded" : "card";
  if (mode === "medium") return expanded ? "expanded" : "button";
  return expanded ? "expanded" : "button";
}
function battleLogIsColumn(mode) {
  return mode === "wide";
}
function buildEmptyStateModel(state) {
  const reason = state?.access?.reason ?? null;
  switch (reason) {
    case EMPTY_REASONS.notOwner:
      return {
        title: "SELECT YOUR CHARACTER",
        hint: "You do not control this token. Choose a controlled token on the map."
      };
    case EMPTY_REASONS.noCharacterLink:
      return {
        title: "NO CHARACTER LINKED",
        hint: "This token is not linked to a character sheet."
      };
    case EMPTY_REASONS.noToken:
    default:
      return {
        title: "SELECT YOUR CHARACTER",
        hint: "Choose a controlled token on the map."
      };
  }
}
function resolveBodyMode(state) {
  switch (state?.status) {
    case HUD_STATUS.ready:
      return "ready";
    case HUD_STATUS.empty:
      return "empty";
    case HUD_STATUS.error:
      return "error";
    default:
      return "loading";
  }
}
function zoneStateClass(stateName) {
  switch (stateName) {
    case ZONE_STATES.wounded:
      return "wounded";
    case ZONE_STATES.serious:
      return "serious";
    case ZONE_STATES.critical:
      return "critical";
    case ZONE_STATES.disabled:
      return "disabled";
    case ZONE_STATES.healthy:
    default:
      return "healthy";
  }
}
function accentClass(colorSemantic) {
  switch (colorSemantic) {
    case "attack":
      return "attack";
    case "psionic":
      return "psionic";
    case "implant":
      return "implant";
    case "intervention":
      return "intervention";
    case "positive":
      return "positive";
    case "negative":
      return "negative";
    case "neutral":
    default:
      return "neutral";
  }
}

// hud/core/combatHudSelectors.js
var COMPACT_LOG_LIMIT = 5;
function selectCurrentEntity(state) {
  return state?.snapshot?.entity ?? null;
}
function selectControlledCharacter(state) {
  if (state?.status !== HUD_STATUS.ready) return null;
  if (!state?.access?.canViewSelectedCharacter) return null;
  const entity = state?.snapshot?.entity ?? null;
  if (!entity) return null;
  const type = entity.summary?.characterType;
  if (state.viewer?.role === "player") return entity;
  if (type === TOKEN_KINDS.player || type === TOKEN_KINDS.mech) return entity;
  return null;
}
function selectCombatSession(state) {
  return state?.snapshot?.combatSession ?? null;
}
function selectIsViewerTurn(state) {
  return Boolean(state?.snapshot?.combatSession?.isViewerTurn);
}
function selectCanAct(state) {
  const entity = selectCurrentEntity(state);
  if (!entity) return false;
  if (!entity.flags?.conscious || !entity.flags?.alive) return false;
  const session = selectCombatSession(state);
  if (session && session.status === "active" && !session.isViewerTurn) return false;
  return Boolean(entity.actions?.main || entity.actions?.move);
}
function selectSelectedSkill(state) {
  const id = state?.ui?.selectedTechniqueId ?? state?.ui?.selectedAbilityId ?? null;
  if (!id) return null;
  const library = state?.snapshot?.skills?.library ?? [];
  return library.find((s) => s.id === id) ?? null;
}
function selectCurrentActionCost(state) {
  const skill2 = selectSelectedSkill(state);
  if (skill2) return skill2.actionCost;
  return "MAIN";
}
function selectDisabledReason(state) {
  if (state?.status !== HUD_STATUS.ready) return "No character loaded.";
  const entity = selectCurrentEntity(state);
  if (!entity) return "No character loaded.";
  if (!entity.flags?.alive) return "Character is dead.";
  if (!entity.flags?.conscious) return "Character is unconscious.";
  const session = selectCombatSession(state);
  if (session && session.status === "active" && !session.isViewerTurn) {
    return "Not your turn.";
  }
  const skill2 = selectSelectedSkill(state);
  if (skill2?.disabledReason) return skill2.disabledReason;
  const cost = selectCurrentActionCost(state);
  if (cost === "MAIN" && !entity.actions?.main) return "MAIN action already spent.";
  if (cost === "MOVE" && !entity.actions?.move) return "MOVE action already spent.";
  if (skill2 && skill2.targeting !== "none") {
    const targeting = state?.ui?.targeting ?? {};
    if (skill2.usesPoint && !targeting.selectedPoint) return "Pick a target point.";
    if (!skill2.usesPoint && (targeting.selectedTargetIds?.length ?? 0) === 0) {
      return "Pick a target on the map.";
    }
  }
  return null;
}
function selectVisibleReserveMagazines(state) {
  const weapon = state?.snapshot?.weapon?.primary ?? null;
  if (!weapon || !weapon.usesMagazine) return [];
  const loaded = weapon.loadedMagazine ?? null;
  const loadedId = loaded?.id ?? null;
  const loadedCaliber = loaded?.caliber ?? null;
  const reserve = Array.isArray(weapon.reserveMagazines) ? weapon.reserveMagazines : [];
  return reserve.filter((mag) => {
    if (!mag) return false;
    if (mag.id === loadedId) return false;
    if ((mag.current ?? 0) <= 0) return false;
    if (loadedCaliber && mag.caliber !== loadedCaliber) return false;
    return true;
  });
}
function selectCompactBattleLog(state) {
  const entries = state?.snapshot?.battleLog?.entries ?? [];
  if (entries.length <= COMPACT_LOG_LIMIT) return entries.slice();
  return entries.slice(entries.length - COMPACT_LOG_LIMIT);
}
function selectQuickSlots(state) {
  return state?.snapshot?.skills?.quickSlots ?? [];
}
function selectSkillById(state, skillId) {
  if (!skillId) return null;
  const library = state?.snapshot?.skills?.library ?? [];
  return library.find((s) => s.id === skillId) ?? null;
}
function selectModifierGroups(state) {
  return state?.snapshot?.modifiers ?? { passive: [], active: [], narrative: [] };
}
function selectSelectedBodyPart(state) {
  return state?.ui?.targeting?.selectedBodyPartId ?? DEFAULT_BODY_PART_ID;
}
var BODY_PART_LABELS = Object.freeze({
  head: "HEAD",
  torso: "TORSO",
  l_arm: "L.ARM",
  r_arm: "R.ARM",
  l_leg: "L.LEG",
  r_leg: "R.LEG"
});
function selectBodyPartLabel(bodyPartId) {
  if (!bodyPartId) return "";
  return BODY_PART_LABELS[bodyPartId] ?? String(bodyPartId).toUpperCase();
}
function selectActionLabel(state) {
  const skill2 = selectSelectedSkill(state);
  if (!skill2) return "ATTACK";
  switch (skill2.type) {
    case "attackTechnique":
      return "ATTACK";
    case "itemAction":
      return skill2.usesPoint ? "THROW" : "USE";
    case "targetedAbility":
      return skill2.source === "psionic" ? "CAST" : "ACTIVATE";
    case "instantAbility":
      return skill2.source === "item" ? "USE" : "ACTIVATE";
    case "toggleAbility":
      return "ACTIVATE";
    default:
      return "ATTACK";
  }
}
function selectPlayerStatusLabel(state) {
  const controlled = selectControlledCharacter(state);
  if (state?.viewer?.role === "gm" && !controlled) return "GM VIEW";
  const session = selectCombatSession(state);
  if (session && session.status === "active") {
    return selectIsViewerTurn(state) ? "YOUR TURN" : "WAITING";
  }
  return "READY";
}
function selectVisibleStatuses(state, limit = 5) {
  const entity = selectCurrentEntity(state);
  if (!entity) return { shown: [], overflow: 0 };
  const all = [
    ...Array.isArray(entity.statuses) ? entity.statuses : [],
    ...Array.isArray(entity.effects) ? entity.effects : []
  ];
  if (all.length <= limit) return { shown: all, overflow: 0 };
  return { shown: all.slice(0, limit), overflow: all.length - limit };
}
function selectTargetView(state) {
  const bodyPartId = selectSelectedBodyPart(state);
  const empty = {
    hasTarget: false,
    name: null,
    kind: "humanoid",
    bodyPartId,
    bodyPartLabel: selectBodyPartLabel(bodyPartId)
  };
  const session = selectCombatSession(state);
  if (!session || session.status !== "active") return empty;
  const selfId = state?.selectedCharacterId ?? null;
  const participants = Array.isArray(session.participants) ? session.participants : [];
  const enemy = participants.find((p) => p.id !== selfId && !p.isPlayer && p.condition === "active") ?? participants.find((p) => p.id !== selfId && p.condition === "active") ?? null;
  if (!enemy) return empty;
  return {
    hasTarget: true,
    name: enemy.name,
    kind: "humanoid",
    bodyPartId,
    bodyPartLabel: selectBodyPartLabel(bodyPartId)
  };
}
function selectModifierChips(state) {
  const groups = selectModifierGroups(state);
  return [
    ...groups.passive ?? [],
    ...groups.active ?? [],
    ...groups.narrative ?? []
  ];
}

// hud/components/hudIcons.js
var ICON_MARK = `<svg viewBox="0 0 24 24" width="16" height="16" aria-hidden="true"><path d="M12 2l8 10-8 10-8-10z" fill="currentColor"/></svg>`;
var ICON_CARET_DOWN = `<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M6 9l6 7 6-7z" fill="currentColor"/></svg>`;
var ICON_CARET_UP = `<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M6 15l6-7 6 7z" fill="currentColor"/></svg>`;
var ICON_PENCIL = `<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M4 16.5L15 5.5l3.5 3.5L7.5 20H4z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M13.5 7l3.5 3.5" stroke="currentColor" stroke-width="1.6"/></svg>`;
var ICON_RELOAD = `<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M20 12a8 8 0 1 1-2.3-5.6" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/><path d="M20 4v4h-4" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
var ICON_LOG = `<svg viewBox="0 0 24 24" width="14" height="14" aria-hidden="true"><path d="M5 4h14v16H5z" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 9h8M8 12h8M8 15h5" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>`;
var ICON_SHIELD = `<svg viewBox="0 0 24 28" width="100%" height="100%" aria-hidden="true"><path d="M12 2l9 3v8c0 6-4 9-9 11-5-2-9-5-9-11V5z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
var ICON_MAGAZINE = `<svg viewBox="0 0 40 64" width="100%" height="100%" aria-hidden="true"><rect x="9" y="6" width="22" height="50" rx="5" fill="currentColor"/><rect x="13" y="2" width="14" height="7" rx="2.5" fill="currentColor"/></svg>`;
function weaponSvg(svgRef) {
  if (svgRef === "pistol") {
    return `<svg viewBox="0 0 200 120" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" aria-hidden="true">
      <path d="M18 40h140l12 6v16h-58l-6 10-18 0-4-10H40l-6 22H18l4-30-4-2z" fill="currentColor"/>
    </svg>`;
  }
  return `<svg viewBox="0 0 360 150" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" aria-hidden="true">
    <!-- receiver + barrel -->
    <rect x="40" y="58" width="250" height="20" rx="5" fill="currentColor"/>
    <rect x="280" y="62" width="70" height="9" rx="4" fill="currentColor"/>
    <!-- stock -->
    <path d="M10 56h40v26H22l-12-8z" fill="currentColor"/>
    <!-- optic -->
    <rect x="150" y="40" width="60" height="14" rx="4" fill="currentColor"/>
    <rect x="170" y="30" width="22" height="12" rx="3" fill="currentColor"/>
    <!-- magazine -->
    <path d="M150 78l8 34h26l4-34z" fill="currentColor"/>
    <!-- grip -->
    <path d="M96 78l-10 34h22l6-34z" fill="currentColor"/>
    <!-- handguard underline -->
    <rect x="210" y="78" width="70" height="8" rx="4" fill="currentColor"/>
  </svg>`;
}
var SKILL_ICONS = {
  star: `<path d="M12 3l2.6 5.6 6.1.7-4.5 4.1 1.2 6L12 16.9 6.6 19.5l1.2-6L3.3 9.3l6.1-.7z" fill="currentColor"/>`,
  burst: `<path d="M12 2l1.8 4.4L18 4.5l-1.5 4.2 4.5 1L17 12l4 2.3-4.5 1L18 19.5l-4.2-1.9L12 22l-1.8-4.4L6 19.5l1.5-4.2-4.5-1L7 12 3 9.7l4.5-1L6 4.5l4.2 1.9z" fill="currentColor"/><circle cx="12" cy="12" r="3" fill="var(--odyssey-bg-deep)"/>`,
  scope: `<circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M12 2v5M12 17v5M2 12h5M17 12h5" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>`,
  psi: `<path d="M7 4h2v6a3 3 0 1 0 6 0V4h2v6a5 5 0 0 1-4 4.9V20h-2v-5.1A5 5 0 0 1 7 10z" fill="currentColor"/>`,
  cube: `<path d="M12 3l8 4.5v9L12 21l-8-4.5v-9z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path d="M12 3v18M4 7.5l8 4.5 8-4.5" fill="none" stroke="currentColor" stroke-width="1.6"/>`,
  arrowup: `<path d="M12 4v13" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><path d="M7 9l5-5 5 5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/><circle cx="12" cy="19" r="2.4" fill="currentColor"/>`,
  grenade: `<circle cx="12" cy="14" r="6.5" fill="currentColor"/><rect x="10" y="3" width="4" height="4" rx="1" fill="currentColor"/><path d="M14 4h4v3" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/>`,
  injector: `<path d="M5 19l8-8 3 3-8 8H5z" fill="currentColor"/><path d="M14 8l4-4 2 2-4 4z" fill="currentColor"/>`,
  cloak: `<path d="M12 3c4 2 6 5 6 9 0 5-3 8-6 9-3-1-6-4-6-9 0-4 2-7 6-9z" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M9 11c1.5 1.5 4.5 1.5 6 0" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/>`,
  bolt: `<path d="M13 2L4 14h6l-1 8 9-12h-6z" fill="currentColor"/>`,
  shieldtri: `<path d="M12 4l7 3v6c0 4-3 6-7 7-4-1-7-3-7-7V7z" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/>`,
  arc: `<path d="M12 5a7 7 0 1 1-5 2" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="12" r="2.4" fill="currentColor"/>`
};
function skillIconSvg(name) {
  const key = String(name || "").toLowerCase();
  const alias = {
    "arrow-up": "arrowup",
    "mind": "psi",
    "psionic": "psi",
    "explosion": "burst",
    "sunburst": "burst",
    "shield": "shieldtri",
    "cooldown": "arc",
    "reload": "arc"
  };
  const inner = SKILL_ICONS[key] ?? SKILL_ICONS[alias[key]] ?? `<circle cx="12" cy="12" r="6" fill="currentColor"/>`;
  return `<svg viewBox="0 0 24 24" width="100%" height="100%" aria-hidden="true">${inner}</svg>`;
}
function zoneAttr(zoneId, zonesMap2, neutral) {
  const stateName = neutral ? "healthy" : zonesMap2?.[zoneId] ?? "healthy";
  return zoneStateClass(stateName);
}
function humanoidSvg(opts = {}) {
  const { zones = {}, highlight = null, neutral = false } = opts;
  const z = (id) => `ohud-zone ohud-zone--${zoneAttr(id, zones, neutral)}${highlight === id ? " is-target" : ""}`;
  return `<svg viewBox="0 0 120 150" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" aria-hidden="true" class="ohud-silhouette">
    <circle cx="60" cy="24" r="16" class="${z("head")}" data-zone="head"/>
    <rect x="42" y="44" width="36" height="46" rx="11" class="${z("torso")}" data-zone="torso"/>
    <rect x="24" y="48" width="14" height="40" rx="7" class="${z("l_arm")}" data-zone="l_arm"/>
    <rect x="82" y="48" width="14" height="40" rx="7" class="${z("r_arm")}" data-zone="r_arm"/>
    <rect x="45" y="94" width="14" height="44" rx="7" class="${z("l_leg")}" data-zone="l_leg"/>
    <rect x="61" y="94" width="14" height="44" rx="7" class="${z("r_leg")}" data-zone="r_leg"/>
  </svg>`;
}
function mechSvg(opts = {}) {
  const { zones = {} } = opts;
  const z = (id) => `ohud-zone ohud-zone--${zoneAttr(id, zones, false)}`;
  return `<svg viewBox="0 0 120 150" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" aria-hidden="true" class="ohud-silhouette">
    <rect x="46" y="10" width="28" height="20" rx="5" class="${z("m_head")}" data-zone="m_head"/>
    <path d="M36 34h48l6 40H30z" class="${z("m_core")}" data-zone="m_core"/>
    <rect x="14" y="38" width="18" height="46" rx="6" class="${z("m_l_arm")}" data-zone="m_l_arm"/>
    <rect x="88" y="38" width="18" height="46" rx="6" class="${z("m_r_arm")}" data-zone="m_r_arm"/>
    <path d="M40 78h16v60H38z" class="${z("m_legs")}" data-zone="m_legs"/>
    <path d="M64 78h16l-2 60H64z" class="${z("m_legs")}"/>
  </svg>`;
}
function turretSvg(opts = {}) {
  const { zones = {} } = opts;
  const z = (id) => `ohud-zone ohud-zone--${zoneAttr(id, zones, false)}`;
  return `<svg viewBox="0 0 120 150" width="100%" height="100%" preserveAspectRatio="xMidYMid meet" aria-hidden="true" class="ohud-silhouette">
    <ellipse cx="60" cy="132" rx="38" ry="10" class="${z("base")}" data-zone="base"/>
    <rect x="50" y="78" width="20" height="50" rx="6" class="${z("base")}"/>
    <rect x="34" y="50" width="52" height="34" rx="10" class="${z("housing")}" data-zone="housing"/>
    <rect x="80" y="58" width="34" height="10" rx="5" class="${z("barrel")}" data-zone="barrel"/>
    <circle cx="48" cy="44" r="8" class="${z("sensor")}" data-zone="sensor"/>
  </svg>`;
}
function entitySilhouetteSvg(summary, opts = {}) {
  const ref = summary?.svgRef ?? "humanoid";
  if (ref === "mech") return mechSvg(opts);
  if (ref === "turret") return turretSvg(opts);
  return humanoidSvg(opts);
}

// utils/json.js
function escapeHtml(value) {
  return String(value ?? "").replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll('"', "&quot;").replaceAll("'", "&#39;");
}

// hud/components/hudDom.js
var esc = escapeHtml;
function cls(...names) {
  return names.filter(Boolean).join(" ");
}
var TIP_SEP = "\u2016";
function tipAttr(title, lines = []) {
  if (!title) return "";
  const body = lines.filter(Boolean).join(TIP_SEP);
  const t = esc(String(title));
  const l = esc(body);
  return ` data-tip-title="${t}"${body ? ` data-tip-lines="${l}"` : ""}`;
}

// hud/components/StatusChip.js
function polarityClass(polarity) {
  if (polarity === "positive") return "positive";
  if (polarity === "negative") return "negative";
  return "neutral";
}
function statusChip(status2) {
  if (!status2) return "";
  const dur = status2.durationTurns == null ? "Ongoing" : `${status2.durationTurns}t`;
  const tip = tipAttr(status2.name, [
    status2.description || "",
    `Duration: ${dur}`
  ]);
  const initial = esc((status2.name || "?").trim().charAt(0).toUpperCase());
  return `<span class="ohud-chip-status ohud-chip-status--${polarityClass(status2.polarity)}"${tip}>
    <span class="ohud-chip-dot" aria-hidden="true">${initial}</span>
    <span class="ohud-chip-name">${esc(status2.name)}</span>
  </span>`;
}
function overflowChip(n) {
  if (!n || n <= 0) return "";
  return `<span class="ohud-chip-status ohud-chip-status--more" data-tip-title="More statuses" data-tip-lines="${n} more active">+${n}</span>`;
}

// hud/components/HudPanel.js
function panel(cfg) {
  const { key, label, accent, bodyHtml, className, headerRightHtml } = cfg;
  const header = label || headerRightHtml ? `<div class="ohud-panel-head">
         ${label ? `<span class="ohud-panel-label ${accent ? `ohud-accent--${accent}` : ""}">${esc(label)}</span>` : "<span></span>"}
         ${headerRightHtml ?? ""}
       </div>` : "";
  return `<section class="${cls("ohud-panel", `ohud-panel--${key}`, className)}" data-block="${esc(key)}">
    ${header}
    <div class="ohud-panel-body">${bodyHtml}</div>
  </section>`;
}

// hud/components/PlayerBlock.js
function zonesMap(entity) {
  const map = {};
  for (const z of entity.zones ?? []) map[z.id] = z.state;
  return map;
}
function resourceBar(kind, label, res) {
  const max = Math.max(0, Number(res?.max) || 0);
  const cur = Math.max(0, Number(res?.current) || 0);
  const pct = max > 0 ? Math.round(cur / max * 100) : 0;
  return `<div class="ohud-res ohud-res--${kind}"${tipAttr(label, [`${cur} / ${max}`])}>
    <span class="ohud-res-label">${esc(label)}</span>
    <span class="ohud-res-track"><span class="ohud-res-fill" style="width:${pct}%"></span></span>
    <span class="ohud-res-num">${cur}<span class="ohud-res-max">/${max}</span></span>
  </div>`;
}
function actionPips(actions) {
  const pip = (on, name) => `<span class="${cls("ohud-pip", on ? "is-on" : "is-off")}"${tipAttr(`${name} action`, [on ? "Available" : "Spent"])}>${name}</span>`;
  return `<div class="ohud-pips">${pip(Boolean(actions?.main), "MAIN")}${pip(Boolean(actions?.move), "MOVE")}</div>`;
}
function pilotStrip(pilot) {
  if (!pilot) return "";
  const psi = pilot.psi ? `${pilot.psi.current}/${pilot.psi.max}` : "";
  return `<div class="ohud-pilot"${tipAttr(`Pilot: ${pilot.name}`, [psi ? `Psi ${psi}` : ""])}>
    <span class="ohud-pilot-tag">PILOT</span>
    <span class="ohud-pilot-name">${esc(pilot.name)}</span>
    ${psi ? `<span class="ohud-pilot-psi">\u03A8 ${esc(psi)}</span>` : ""}
  </div>`;
}
function renderPlayerBlock(state) {
  const entity = selectCurrentEntity(state);
  if (!entity) {
    return panel({ key: "player", label: "PLAYER", bodyHtml: `<div class="ohud-muted-fill">\u2014</div>` });
  }
  const turn = selectPlayerStatusLabel(state);
  const turnClass = turn === "YOUR TURN" ? "active" : turn === "WAITING" ? "waiting" : turn === "GM VIEW" ? "gm" : "idle";
  const { shown, overflow } = selectVisibleStatuses(state, 5);
  const isMech = entity.summary?.svgRef === "mech";
  const headerRight = `<span class="ohud-turn ohud-turn--${turnClass}">${esc(turn)}</span>`;
  const body = `
    <div class="ohud-player-grid">
      <div class="ohud-figure">
        <div class="ohud-figure-svg">${entitySilhouetteSvg(entity.summary, { zones: zonesMap(entity) })}</div>
        <div class="ohud-figure-shield" aria-hidden="true">${ICON_SHIELD}</div>
      </div>
      <div class="ohud-player-stats">
        <div class="ohud-player-name" title="${esc(entity.summary.name)}">${esc(entity.summary.name)}</div>
        ${resourceBar("shield", "SHIELD", entity.shield)}
        ${entity.psi && entity.psi.max > 0 ? resourceBar("psi", "PSI", entity.psi) : ""}
        ${actionPips(entity.actions)}
      </div>
    </div>
    ${isMech ? pilotStrip(entity.pilot) : ""}
    <div class="ohud-statuses">
      ${shown.map(statusChip).join("")}
      ${overflowChip(overflow)}
    </div>
  `;
  return panel({
    key: "player",
    label: isMech ? "MECH" : "YOU",
    bodyHtml: body,
    headerRightHtml: headerRight
  });
}

// hud/components/GunBlock.js
function fireModeLetter(mode) {
  if (!mode) return "\u2014";
  const m = String(mode).toLowerCase();
  if (m.startsWith("semi")) return "S";
  if (m.startsWith("burst")) return "B";
  if (m.startsWith("auto")) return "A";
  if (m.startsWith("full")) return "F";
  return String(mode).charAt(0).toUpperCase();
}
function emptyGun() {
  return panel({
    key: "gun",
    label: "WEAPON",
    bodyHtml: `<div class="ohud-gun is-disabled"><div class="ohud-gun-main"><div class="ohud-muted-fill">NO WEAPON</div></div></div>`
  });
}
function renderGunBlock(state) {
  const weapon = state?.snapshot?.weapon?.primary ?? null;
  const secondary = state?.snapshot?.weapon?.secondary ?? null;
  if (!weapon) return emptyGun();
  const mag = weapon.loadedMagazine ?? null;
  const usesMag = Boolean(weapon.usesMagazine);
  const ammoCur = mag ? Number(mag.current ?? 0) : Number(weapon.ammo?.current ?? 0);
  const ammoMax = mag ? Number(mag.max ?? 0) : Number(weapon.ammo?.max ?? 0);
  const ammoType = mag?.ammoType ?? (weapon.usesConsumable ? "item" : "\u2014");
  const isEmpty = weapon.requiresAmmo && ammoCur <= 0;
  const reserve = selectVisibleReserveMagazines(state);
  const canReload = Boolean(weapon.canReload) && reserve.length > 0;
  const disabled = Boolean(weapon.disabledReason) || isEmpty && !canReload;
  const fm = fireModeLetter(weapon.currentFireMode);
  const fireModeTip = tipAttr("Fire mode", [
    `Current: ${weapon.currentFireMode ?? "\u2014"}`,
    weapon.fireModes?.length ? `Available: ${weapon.fireModes.join(", ")}` : ""
  ]);
  const swapTip = tipAttr("Magazine / ammo", [
    "Swap available in a later phase",
    reserve.length ? `${reserve.length} compatible magazine(s) in reserve` : "No spare magazines"
  ]);
  const mainCard = `
    <div class="ohud-gun-main"${tipAttr(weapon.name, [weapon.currentFireMode ? `Mode: ${weapon.currentFireMode}` : ""])}>
      <span class="ohud-gun-name">${esc(weapon.name)}</span>
      <span class="ohud-gun-caret is-readonly" aria-hidden="true"${swapTip}>${ICON_CARET_DOWN}</span>
      <span class="ohud-gun-silhouette">${weaponSvg(weapon.svgRef)}</span>
      <span class="ohud-firemode is-readonly"${fireModeTip}><span class="ohud-firemode-knob"></span><span class="ohud-firemode-letter">${esc(fm)}</span></span>
      ${secondary ? `<span class="ohud-gun-secondary"${tipAttr("Secondary weapon", [esc(secondary.name || "")])}>2nd</span>` : ""}
    </div>`;
  const magCard = `
    <div class="ohud-mag-card${usesMag ? "" : " is-consumable"}"${swapTip}>
      <span class="ohud-mag-icon" aria-hidden="true">${usesMag ? ICON_MAGAZINE : ""}</span>
      ${usesMag ? `<span class="ohud-mag-caret is-readonly" aria-hidden="true">${ICON_CARET_DOWN}</span>` : ""}
      <span class="ohud-mag-type">${esc(ammoType)}</span>
    </div>`;
  const ammoCard = `
    <div class="ohud-ammo-card">
      <span class="ohud-ammo-head">
        <span class="ohud-ammo-label">ammo</span>
        <span class="${cls("ohud-ammo-reload", "is-readonly", canReload ? "" : "is-off")}" aria-hidden="true"${tipAttr("Reload", [canReload ? "Reserve magazine available" : "No reload available", "Reload arrives in a later phase"])}>${ICON_RELOAD}</span>
      </span>
      <span class="${cls("ohud-ammo-count", isEmpty ? "ohud-ammo-count--empty" : "")}">
        <span class="ohud-ammo-cur">${ammoCur}</span><span class="ohud-ammo-max">/${ammoMax}</span>
      </span>
    </div>`;
  const body = `<div class="${cls("ohud-gun", disabled ? "is-disabled" : "")}"${disabled ? tipAttr("Weapon unavailable", [esc(weapon.disabledReason || "Out of ammo")]) : ""}>
    ${mainCard}
    <div class="ohud-gun-side">${magCard}${ammoCard}</div>
  </div>`;
  return panel({ key: "gun", label: "WEAPON", bodyHtml: body });
}

// hud/components/SkillBlock.js
var COST_ABBR = { FREE: "F", MOVE: "Mv", MAIN: "M", TURN: "T" };
function emptyTile(index) {
  return `<div class="ohud-slot ohud-slot--empty" data-slot="${index}" aria-hidden="true"></div>`;
}
function skillTile(skill2, index, selectedId) {
  const accent = accentClass(skill2.color);
  const disabled = Boolean(skill2.disabledReason);
  const selected = skill2.id === selectedId;
  const cost = COST_ABBR[skill2.actionCost] ?? "";
  const cd = Number(skill2.cooldownTurns) || 0;
  const res = skill2.resourceCost ? `${skill2.resourceCost.amount}${String(skill2.resourceCost.type).charAt(0).toUpperCase()}` : "";
  const tip = tipAttr(skill2.name, [
    `Source: ${skill2.source}`,
    `Cost: ${skill2.actionCost}${res ? ` \xB7 ${res}` : ""}`,
    cd > 0 ? `Cooldown: ${cd} turn(s)` : "",
    skill2.isToggled ? "Active (toggled on)" : "",
    skill2.disabledReason ? `Disabled: ${skill2.disabledReason}` : skill2.tooltip || ""
  ]);
  return `<div class="${cls(
    "ohud-slot",
    `ohud-accent--${accent}`,
    disabled ? "is-disabled" : "",
    selected ? "is-selected" : "",
    skill2.isToggled ? "is-toggled" : ""
  )}" data-slot="${index}" data-skill="${esc(skill2.id)}"${tip}>
    <span class="ohud-slot-icon">${skillIconSvg(skill2.icon)}</span>
    ${cost ? `<span class="ohud-slot-cost">${esc(cost)}</span>` : ""}
    ${res ? `<span class="ohud-slot-res">${esc(res)}</span>` : ""}
    ${cd > 0 ? `<span class="ohud-slot-cd">${cd}</span>` : ""}
    ${skill2.isToggled ? `<span class="ohud-slot-toggle" aria-hidden="true"></span>` : ""}
  </div>`;
}
function renderSkillBlock(state) {
  const slots = selectQuickSlots(state);
  const selected = selectSelectedSkill(state);
  const selectedId = selected?.id ?? null;
  const tiles = (slots.length ? slots : Array.from({ length: 6 }, (_, i) => ({ index: i, skillId: null }))).map((slot) => {
    const skill2 = selectSkillById(state, slot.skillId);
    return skill2 ? skillTile(skill2, slot.index, selectedId) : emptyTile(slot.index);
  }).join("");
  return panel({
    key: "skills",
    label: "SKILLS",
    bodyHtml: `<div class="ohud-slots">${tiles}</div>`
  });
}

// hud/components/TargetBlock.js
function renderTargetBlock(state) {
  const tv = selectTargetView(state);
  if (!tv.hasTarget) {
    const body2 = `<div class="ohud-target is-empty">
      <div class="ohud-figure ohud-figure--ghost">
        <div class="ohud-figure-svg">${humanoidSvg({ neutral: true })}</div>
      </div>
      <div class="ohud-target-hint">PICK TARGET<br>ON MAP</div>
    </div>`;
    return panel({ key: "target", label: "TARGET", bodyHtml: body2 });
  }
  const body = `<div class="ohud-target">
    <div class="ohud-figure">
      <div class="ohud-figure-svg">${humanoidSvg({ neutral: true, highlight: tv.bodyPartId })}</div>
      <div class="ohud-figure-shield" aria-hidden="true"${tipAttr("Target shield", ["Detail hidden for non-owned entity"])}>${ICON_SHIELD}</div>
    </div>
    <div class="ohud-target-meta">
      <div class="ohud-target-name" title="${esc(tv.name)}">${esc(tv.name)}</div>
      <div class="ohud-target-zone"${tipAttr("Aimed zone", ["Body-part targeting arrives in a later phase"])}>${esc(tv.bodyPartLabel)}</div>
    </div>
  </div>`;
  return panel({ key: "target", label: "TARGET", bodyHtml: body });
}

// hud/components/ModifierBlock.js
var MAX_CHIPS = 6;
function chipAccent(mod) {
  if (mod.source === "intervention") return "intervention";
  if (mod.kind === "narrative" || mod.requiresGMApproval) return "narrative";
  if (mod.polarity === "negative") return "negative";
  if (mod.polarity === "positive") return "positive";
  return "neutral";
}
function modChip(mod) {
  const accent = chipAccent(mod);
  const sign = mod.value > 0 ? `+${mod.value}` : mod.value < 0 ? `${mod.value}` : "";
  const tip = tipAttr(mod.name, [
    mod.description || "",
    sign ? `Value: ${sign}` : "",
    `Source: ${mod.source}`,
    mod.alwaysActive ? "Always active (passive)" : "",
    mod.requiresGMApproval ? "Requires GM approval" : ""
  ]);
  return `<span class="${cls(
    "ohud-mod",
    `ohud-mod--${accent}`,
    mod.selected ? "is-selected" : "",
    mod.alwaysActive ? "is-passive" : ""
  )}"${tip}>
    <span class="ohud-mod-name">${esc(mod.name)}</span>
    ${sign ? `<span class="ohud-mod-val">${esc(sign)}</span>` : ""}
  </span>`;
}
function renderModifierBlock(state) {
  const chips = selectModifierChips(state).slice(0, MAX_CHIPS);
  const filled = chips.map(modChip).join("");
  const padCount = Math.max(0, Math.min(2, MAX_CHIPS - chips.length));
  const pads = Array.from({ length: padCount }, () => `<span class="ohud-mod ohud-mod--empty" aria-hidden="true"></span>`).join("");
  return panel({
    key: "mod",
    label: "MOD",
    bodyHtml: `<div class="ohud-mods">${filled}${pads}</div>`
  });
}

// hud/components/ActionBlock.js
function renderActionBlock(state) {
  const label = selectActionLabel(state);
  const can = selectCanAct(state);
  const reason = selectDisabledReason(state);
  const disabled = !can || Boolean(reason);
  const cost = selectCurrentActionCost(state);
  const costHint = `<span class="ohud-action-econ">
    <span class="${cls("ohud-econ-pip", cost === "MAIN" ? "is-spend" : "")}">MAIN</span>
    <span class="${cls("ohud-econ-pip", cost === "MOVE" ? "is-spend" : "")}">MOVE</span>
  </span>`;
  const tip = disabled ? tipAttr("Action unavailable", [esc(reason || "Not available")]) : tipAttr(`${label}`, [`Costs: ${cost}`, "Resolution arrives in a later phase"]);
  const reasonLine = disabled && reason ? `<div class="ohud-action-reason">${esc(reason)}</div>` : `<div class="ohud-action-reason ohud-action-reason--ok">Preview only</div>`;
  return `<section class="ohud-panel ohud-panel--action" data-block="action">
    <button type="button" class="${cls("ohud-action-btn", disabled ? "is-disabled" : "is-ready")}"
      data-action="primary" ${disabled ? 'aria-disabled="true"' : ""}${tip}>
      <span class="ohud-action-label">${esc(label)}</span>
    </button>
    ${costHint}
    ${reasonLine}
  </section>`;
}

// hud/components/BattleLogBlock.js
function deltaClass(delta) {
  const d = String(delta || "").toLowerCase();
  if (!d) return "neutral";
  if (d.includes("miss")) return "miss";
  return "hit";
}
function entryRow(e) {
  if (e.kind === "system") {
    return `<li class="ohud-log-row ohud-log-row--system">\u25B8 ${esc(e.action || e.summary)}</li>`;
  }
  if (e.kind === "narrative") {
    return `<li class="ohud-log-row ohud-log-row--narr">${esc(e.actor ? `${e.actor}: ` : "")}${esc(e.action || e.summary)}</li>`;
  }
  return `<li class="ohud-log-row">
    <span class="ohud-log-actor">${esc(e.actor)}</span>
    <span class="ohud-log-act">${esc(e.action)}</span>
    ${e.target ? `<span class="ohud-log-arrow">\u203A</span><span class="ohud-log-target">${esc(e.target)}</span>` : ""}
    ${e.delta ? `<span class="ohud-log-delta ohud-log-delta--${deltaClass(e.delta)}">${esc(e.delta)}</span>` : ""}
  </li>`;
}
function renderBattleLogBlock(state, logMode) {
  const entries = selectCompactBattleLog(state);
  const count = entries.length;
  if (logMode === "button") {
    return `<section class="ohud-panel ohud-panel--log ohud-log--button" data-block="log">
      <button type="button" class="ohud-log-toggle" data-action="toggle-log" data-tip-title="Battle log" data-tip-lines="${count} recent entr${count === 1 ? "y" : "ies"}">
        <span class="ohud-log-toggle-icon">${ICON_LOG}</span><span>LOG</span>
        ${count ? `<span class="ohud-log-badge">${count}</span>` : ""}
      </button>
    </section>`;
  }
  const expanded = logMode === "expanded";
  const list = entries.length ? `<ul class="ohud-log-list">${entries.map(entryRow).join("")}</ul>` : `<div class="ohud-log-empty">No combat log yet.</div>`;
  return `<section class="${cls("ohud-panel", "ohud-panel--log", expanded ? "ohud-log--expanded" : "ohud-log--card")}" data-block="log">
    <div class="ohud-panel-head">
      <span class="ohud-panel-label">BATTLE LOG</span>
      <button type="button" class="ohud-log-collapse" data-action="toggle-log" aria-label="${expanded ? "Collapse log" : "Expand log"}">
        ${expanded ? ICON_CARET_DOWN : ICON_CARET_UP}
      </button>
    </div>
    ${list}
  </section>`;
}

// hud/components/EmptyHudState.js
function renderEmptyState(state) {
  const { title, hint } = buildEmptyStateModel(state);
  return `<div class="ohud-empty">
    <span class="ohud-empty-mark" aria-hidden="true">${ICON_MARK}</span>
    <div class="ohud-empty-title">${esc(title)}</div>
    <div class="ohud-empty-hint">${esc(hint)}</div>
  </div>`;
}
function renderErrorState(state) {
  const msg = state?.error?.message || "Something went wrong.";
  return `<div class="ohud-empty ohud-empty--error">
    <div class="ohud-empty-title">HUD ERROR</div>
    <div class="ohud-empty-hint">${esc(msg)}</div>
  </div>`;
}
function renderLoadingState() {
  return `<div class="ohud-empty ohud-empty--loading">
    <div class="ohud-empty-title">LOADING\u2026</div>
  </div>`;
}

// hud/components/Tooltip.js
var MARGIN = 8;
function createTooltip(host) {
  const el = document.createElement("div");
  el.className = "ohud-tooltip";
  el.setAttribute("role", "tooltip");
  el.hidden = true;
  host.appendChild(el);
  let visible = false;
  function show(target) {
    const title = target.getAttribute("data-tip-title");
    if (!title) return;
    const lines = (target.getAttribute("data-tip-lines") || "").split(TIP_SEP).filter(Boolean);
    el.innerHTML = `<div class="ohud-tooltip-title">${title}</div>` + lines.map((l) => `<div class="ohud-tooltip-line">${l}</div>`).join("");
    el.hidden = false;
    visible = true;
  }
  function hide() {
    if (!visible) return;
    el.hidden = true;
    visible = false;
  }
  function place(x, y) {
    if (!visible) return;
    const vw = window.innerWidth;
    const vh = window.innerHeight;
    const rect = el.getBoundingClientRect();
    let left = x + 14;
    let top = y - rect.height - 12;
    if (top < MARGIN) top = y + 18;
    left = Math.max(MARGIN, Math.min(left, vw - rect.width - MARGIN));
    top = Math.max(MARGIN, Math.min(top, vh - rect.height - MARGIN));
    el.style.left = `${Math.round(left)}px`;
    el.style.top = `${Math.round(top)}px`;
  }
  function onOver(e) {
    const target = e.target.closest("[data-tip-title]");
    if (!target || !host.contains(target)) return;
    show(target);
    place(e.clientX, e.clientY);
  }
  function onMove(e) {
    if (!visible) return;
    if (!e.target.closest("[data-tip-title]")) {
      hide();
      return;
    }
    place(e.clientX, e.clientY);
  }
  function onOut(e) {
    const to = e.relatedTarget;
    if (to && to.closest && to.closest("[data-tip-title]")) return;
    hide();
  }
  host.addEventListener("mouseover", onOver);
  host.addEventListener("mousemove", onMove);
  host.addEventListener("mouseout", onOut);
  return {
    hide,
    destroy() {
      host.removeEventListener("mouseover", onOver);
      host.removeEventListener("mousemove", onMove);
      host.removeEventListener("mouseout", onOut);
      el.remove();
    }
  };
}

// hud/components/CombatHudLayout.js
function createCombatHudLayout(cfg) {
  const {
    store,
    obrAvailable = true,
    devControls = true,
    onScenario,
    onRole,
    onCollapse
  } = cfg;
  const el = document.createElement("div");
  el.className = "ohud-hud";
  let currentScenarioId = cfg.scenarioId ?? "A";
  let devOpen = false;
  let battleLogExpanded = false;
  let toastTimer = null;
  const tooltip = createTooltip(el);
  function currentWidth() {
    return typeof window !== "undefined" && window.innerWidth || el.clientWidth || 1280;
  }
  function devStrip(state) {
    if (!devControls) return "";
    const role = state?.viewer?.role === "gm" ? "gm" : "player";
    const options = listScenarios().map((s) => `<option value="${esc(s.id)}" ${s.id === currentScenarioId ? "selected" : ""}>${esc(s.label)}</option>`).join("");
    return `<div class="${cls("ohud-dev", devOpen ? "is-open" : "")}">
      <button type="button" class="ohud-dev-btn" data-action="dev-toggle" aria-expanded="${devOpen}" data-tip-title="Developer tools" data-tip-lines="Scenario + role (dev only)">
        ${ICON_PENCIL}<span class="ohud-dev-btn-label">DEV</span>
      </button>
      ${devOpen ? `<div class="ohud-dev-strip">
        <label class="ohud-dev-field"><span>Scenario</span>
          <select class="ohud-select" data-action="scenario">${options}</select>
        </label>
        <span class="ohud-dev-roles">
          <button type="button" class="${cls("ohud-chip", role === "player" ? "is-on" : "")}" data-action="role" data-value="player">Player</button>
          <button type="button" class="${cls("ohud-chip", role === "gm" ? "is-on" : "")}" data-action="role" data-value="gm">GM</button>
        </span>
      </div>` : ""}
    </div>`;
  }
  function controls(state) {
    const fallback = obrAvailable ? "" : `<span class="ohud-fallback">OBR unavailable \u2014 local HUD preview</span>`;
    const scenarioLabel = (listScenarios().find((s) => s.id === currentScenarioId) || {}).label || "";
    return `<div class="ohud-controls">
      <span class="ohud-brand">
        <span class="ohud-brand-mark" aria-hidden="true">${ICON_MARK}</span>
        <span class="ohud-brand-text">ODYSSEY</span>
        <span class="ohud-brand-sub">${esc(scenarioLabel)}</span>
      </span>
      ${fallback}
      <span class="ohud-controls-right">
        ${devStrip(state)}
        <button type="button" class="ohud-collapse" data-action="collapse" aria-label="Collapse HUD" data-tip-title="Collapse HUD">${ICON_CARET_DOWN}</button>
      </span>
    </div>`;
  }
  function readyGrid(state, mode) {
    const logMode = resolveBattleLogMode(mode, battleLogExpanded);
    const logInColumn = battleLogIsColumn(mode);
    const logHtml = renderBattleLogBlock(state, logMode);
    return `<div class="${cls("ohud-grid", `ohud-grid--${mode}`)}">
      ${renderPlayerBlock(state)}
      ${renderGunBlock(state)}
      ${renderSkillBlock(state)}
      ${renderTargetBlock(state)}
      ${renderModifierBlock(state)}
      ${renderActionBlock(state)}
      ${logInColumn ? logHtml : ""}
    </div>
    ${logInColumn ? "" : `<div class="ohud-log-float">${logHtml}</div>`}`;
  }
  function bodyHtml(state, mode) {
    const bodyMode = resolveBodyMode(state);
    if (bodyMode === "ready") return readyGrid(state, mode);
    if (bodyMode === "empty") return `<div class="ohud-state-wrap">${renderEmptyState(state)}</div>`;
    if (bodyMode === "error") return `<div class="ohud-state-wrap">${renderErrorState(state)}</div>`;
    return `<div class="ohud-state-wrap">${renderLoadingState()}</div>`;
  }
  function render() {
    const state = store.getState();
    const mode = resolveLayoutMode(currentWidth());
    el.setAttribute("data-mode", mode);
    el.setAttribute("data-body", resolveBodyMode(state));
    el.innerHTML = `${controls(state)}${bodyHtml(state, mode)}<div class="ohud-toast" hidden></div>`;
  }
  function showToast(text) {
    const toast = el.querySelector(".ohud-toast");
    if (!toast) return;
    toast.textContent = text;
    toast.hidden = false;
    if (toastTimer) clearTimeout(toastTimer);
    toastTimer = setTimeout(() => {
      if (toast) toast.hidden = true;
    }, 1800);
  }
  function onClick(e) {
    const t = e.target.closest("[data-action]");
    if (!t) return;
    const action = t.getAttribute("data-action");
    switch (action) {
      case "collapse":
        onCollapse && onCollapse(true);
        break;
      case "dev-toggle":
        devOpen = !devOpen;
        render();
        break;
      case "role":
        onRole && onRole(t.getAttribute("data-value"));
        break;
      case "toggle-log":
        battleLogExpanded = !battleLogExpanded;
        render();
        break;
      case "primary":
        if (t.classList.contains("is-disabled")) return;
        showToast("Action resolution arrives in a later phase");
        break;
      default:
        break;
    }
  }
  function onChange(e) {
    const t = e.target.closest("[data-action='scenario']");
    if (!t) return;
    currentScenarioId = t.value;
    battleLogExpanded = false;
    onScenario && onScenario(currentScenarioId);
  }
  let resizeRaf = null;
  function onResize() {
    if (resizeRaf) return;
    resizeRaf = requestAnimationFrame(() => {
      resizeRaf = null;
      render();
    });
  }
  el.addEventListener("click", onClick);
  el.addEventListener("change", onChange);
  if (typeof window !== "undefined") window.addEventListener("resize", onResize);
  const unsubscribe = store.subscribe(render);
  render();
  return {
    el,
    setScenarioId(id) {
      currentScenarioId = id;
      render();
    },
    destroy() {
      unsubscribe();
      tooltip.destroy();
      el.removeEventListener("click", onClick);
      el.removeEventListener("change", onChange);
      if (typeof window !== "undefined") window.removeEventListener("resize", onResize);
      if (toastTimer) clearTimeout(toastTimer);
      el.remove();
    }
  };
}

// hud/overlay/combatHudOverlayView.js
function createCombatHudOverlayView(cfg) {
  const {
    root,
    store,
    obrAvailable = true,
    devControls = true,
    onCollapse,
    onScenario,
    onRole
  } = cfg;
  const host = document.createElement("div");
  host.className = "odyssey-hud ohud-overlay";
  root.appendChild(host);
  let scenarioId = cfg.scenarioId ?? "A";
  let layout = null;
  let mode = null;
  function mountLayout() {
    if (layout) return;
    layout = createCombatHudLayout({
      store,
      obrAvailable,
      devControls,
      scenarioId,
      onScenario(id) {
        scenarioId = id;
        onScenario(id);
      },
      onRole,
      onCollapse
    });
    host.appendChild(layout.el);
  }
  function unmountLayout() {
    if (!layout) return;
    layout.destroy();
    layout = null;
  }
  function showPill() {
    host.innerHTML = `
      <button class="ohud-pill" data-ohud="reopen" title="Open Odyssey Combat HUD" aria-label="Open Odyssey Combat HUD">
        <span class="ohud-mark" aria-hidden="true">${ICON_MARK}</span>
        <span class="ohud-pill-label">ODYSSEY</span>
      </button>`;
  }
  function render(state) {
    const collapsed = Boolean(state?.ui?.isHudCollapsed);
    host.classList.toggle("is-collapsed", collapsed);
    if (collapsed) {
      if (mode !== "collapsed") {
        unmountLayout();
        showPill();
        mode = "collapsed";
      }
    } else if (mode !== "expanded") {
      host.innerHTML = "";
      mountLayout();
      mode = "expanded";
    }
  }
  function onClick(e) {
    const el = e.target.closest("[data-ohud='reopen']");
    if (el) onCollapse(false);
  }
  host.addEventListener("click", onClick);
  const unsubscribe = store.subscribe(render);
  render(store.getState());
  return {
    render,
    setScenarioId(id) {
      scenarioId = id;
      if (layout) layout.setScenarioId(id);
    },
    destroy() {
      unsubscribe();
      host.removeEventListener("click", onClick);
      unmountLayout();
      host.remove();
    }
  };
}

// hud/overlay/mountCombatHudOverlay.js
function mountCombatHudOverlay(options = {}) {
  if (typeof document === "undefined") {
    throw new Error("mountCombatHudOverlay requires a DOM environment.");
  }
  const root = options.root ?? document.body;
  const integration = options.integration ?? {};
  const obrAvailable = integration.available !== false;
  const restored = normalizeHudUiState(options.uiState);
  let scenarioId = restored.mockScenarioId;
  const adapter = createMockCombatHudAdapter({ scenarioId });
  adapter.setViewerRole(restored.viewerRole);
  if (restored.selectedTokenId) {
    adapter.selectToken(restored.selectedTokenId);
  }
  const store = createCombatHudStore({ adapter });
  store.initialize();
  store.setHudCollapsed(restored.isHudCollapsed);
  function currentUiState() {
    const s = store.getState();
    return {
      isHudCollapsed: s.ui.isHudCollapsed,
      mockScenarioId: scenarioId,
      viewerRole: s.viewer.role,
      selectedTokenId: s.selectedTokenId
    };
  }
  function emitUiState() {
    if (typeof integration.onUiStateChange === "function") {
      try {
        integration.onUiStateChange(currentUiState());
      } catch (_e) {
      }
    }
  }
  const view = createCombatHudOverlayView({
    root,
    store,
    scenarioId,
    role: restored.viewerRole,
    obrAvailable,
    devControls: options.devControls !== false,
    onCollapse(collapsed) {
      store.setHudCollapsed(collapsed);
      emitUiState();
    },
    onScenario(id) {
      scenarioId = id;
      store.setMockScenario(id);
      emitUiState();
    },
    onRole(role) {
      store.setViewerRole(role);
      emitUiState();
    }
  });
  emitUiState();
  return {
    store,
    unmount() {
      view.destroy();
      store.dispose();
    }
  };
}

// hud/overlay/combatHudOverlayPage.js
function injectStyles() {
  for (const [id, css] of [
    ["ohud-tokens", combatHudTokens_default],
    ["ohud-overlay-styles", combatHudOverlay_default],
    ["ohud-layout-styles", combatHudLayout_default]
  ]) {
    if (document.getElementById(id)) continue;
    const el = document.createElement("style");
    el.id = id;
    el.textContent = css;
    document.head.appendChild(el);
  }
}
function start() {
  injectStyles();
  document.documentElement.style.background = "transparent";
  document.body.style.background = "transparent";
  document.body.style.margin = "0";
  const root = document.getElementById("root") || document.body;
  const available = !!(lib_default && lib_default.isAvailable);
  let restored = {};
  try {
    restored = parseHudUiState(window.location.search);
  } catch {
    restored = {};
  }
  mountCombatHudOverlay({
    root,
    uiState: restored,
    devControls: true,
    integration: {
      available,
      onUiStateChange(uiState) {
        if (!available) return;
        try {
          lib_default.broadcast.sendMessage(BC_HUD_UI_STATE, uiState, { destination: "LOCAL" });
        } catch (_e) {
        }
      }
    }
  });
}
if (lib_default && lib_default.isAvailable) {
  lib_default.onReady(start);
} else {
  start();
}
