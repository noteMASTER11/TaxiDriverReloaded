import { createGameBridge } from './game-bridge.js';
import { createHudModel } from './hud-model.js';
import { render } from './hud-render.js';

export function createHudComponent(vue, nativeBridge, options = {}) {
  const { defineComponent, ref, shallowRef, h, onMounted, onBeforeUnmount } = vue;
  return defineComponent({
    name: 'TaxiDriverHUD',
    setup(_, { expose }) {
      const host = ref(null);
      const ready = shallowRef(false);
      const failure = shallowRef('');
      const renderCache = [];
      let model;
      onMounted(() => {
        try {
          model = createHudModel({host: host.value, bridge: createGameBridge(nativeBridge),
            vue, externalPhoneMode: options.externalPhoneMode});
          model.view.hud = model.hud;
          model.view.formatNumber = (value, digits = 0) => Number(value || 0).toLocaleString(
            model.view.settings.language || 'en', {minimumFractionDigits: digits, maximumFractionDigits: digits});
          ready.value = true;
        } catch (error) {
          failure.value = error?.message || 'TaxiDriver could not start.';
          console.error('TaxiDriverHUD:', error);
        }
      });
      onBeforeUnmount(() => { model?.destroy(); });
      // Component instance diagnostics are available through Vue's standard
      // expose mechanism. They do not add globals or another gameplay state.
      expose({ getModel: () => model });
      return () => h('taxi-driver-hud', {ref: host, class: 'taxi-driver-hud-host', 'data-runtime': 'vue3'},
        failure.value ? h('div', {class: 'taxi-runtime-error', role: 'alert'}, failure.value) :
          ready.value ? [render(model.view, renderCache)] : []);
    },
  });
}
