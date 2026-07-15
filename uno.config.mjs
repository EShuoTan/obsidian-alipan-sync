import { defineConfig, presetUno } from 'unocss'

export default defineConfig({
	configFile: false,
	content: {
		filesystem: ['src/**/*.{html,js,ts,jsx,tsx,vue,svelte,astro}'],
	},
	rules: [[/^background-none$/, () => ({ background: 'none' })]],
	presets: [presetUno()],
})
