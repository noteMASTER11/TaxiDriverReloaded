// All browser-to-game dependencies live here. UI behavior does not depend on
// Angular globals or the implementation of BeamNG's UI application host.
export function createGameBridge(native) {
  if (!native?.api || typeof native.api.engineLua !== 'function' ||
      typeof native.api.serializeToLua !== 'function' ||
      typeof native.events?.on !== 'function' || typeof native.events?.off !== 'function') {
    throw new Error('TaxiDriver: game bridge is unavailable or incompatible.');
  }
  return {
    api: {
      engineLua: native.api.engineLua.bind(native.api),
      serializeToLua: native.api.serializeToLua.bind(native.api),
    },
    events: {
      on: native.events.on.bind(native.events),
      off: native.events.off.bind(native.events),
    },
    streams: native.streams,
  };
}
