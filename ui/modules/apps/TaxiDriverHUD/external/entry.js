import * as vue from 'vue';
import { createHudComponent } from '../hud-component.js';

export function mountTaxiDriver(host, bridge, options = {externalPhoneMode: true}) {
  const app = vue.createApp(createHudComponent(vue, bridge, options));
  const instance = app.mount(host);
  const page = host.ownerDocument.defaultView;
  let unmounted = false;
  const unmount = () => {
    if (unmounted) return;
    unmounted = true;
    page.removeEventListener('pagehide', handlePageHide);
    app.unmount();
  };
  const handlePageHide = event => {
    if (!event.persisted) unmount();
  };
  page.addEventListener('pagehide', handlePageHide);
  return {unmount, version: vue.version, getModel: instance.getModel};
}
