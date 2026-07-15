import { describe, expect, it } from 'vitest'
import { getInvalidChars, hasInvalidChar } from './has-invalid-char'

describe('hasInvalidChar', () => {
	it('allows nested relative paths when each basename is valid', () => {
		expect(hasInvalidChar('folder/subfolder/note.md')).toBe(false)
		expect(getInvalidChars('folder\\subfolder\\note.md')).toEqual([])
	})

	it('checks only the final path segment for invalid characters', () => {
		expect(hasInvalidChar('folder/subfolder/bad\tname.md')).toBe(true)
		expect(getInvalidChars('folder/subfolder/bad\r\nname.md')).toEqual([
			'\r',
			'\n',
		])
	})
})
