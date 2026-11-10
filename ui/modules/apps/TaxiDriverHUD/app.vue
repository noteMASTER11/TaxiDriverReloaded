<script>
import * as vue from 'vue'
import { useBridge } from '@/bridge'
import { createHudComponent } from './hud-component.js'

export default createHudComponent(vue, useBridge(), { externalPhoneMode: false })
</script>

<style>
@import url('/ui/modules/apps/TaxiDriverHUD/app.css?v=508');
@import url('/ui/modules/apps/TaxiDriverHUD/external/external-ui.css?v=508');
</style>
