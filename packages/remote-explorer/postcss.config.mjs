import UnoCSS from '@unocss/postcss'
import unoConfig from './unocss.config.mjs'

export default {
	plugins: [UnoCSS({ configOrPath: unoConfig })],
}
