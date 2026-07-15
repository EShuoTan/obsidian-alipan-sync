import { describe, expect, it, vi } from 'vitest'

vi.mock('obsidian', () => {
	class TFolder {
		children: unknown[] = []
		constructor(public path: string) {}
	}
	class TFile {
		constructor(
			public path: string,
			public stat: { mtime: number; size: number },
		) {}
	}
	return {
		TFolder,
		TFile,
		Vault: class {},
		normalizePath: (path: string) => path.replace(/\\/g, '/'),
	}
})

import { TFolder } from 'obsidian'
import { traverseLocalVault } from './traverse-local-vault'

describe('traverseLocalVault', () => {
	it('includes configDir when Vault children hide it but adapter can list it', async () => {
		const root = Object.assign(new (TFolder as any)(), {
			path: '',
			children: [],
		})
		const adapterStats = new Map([
			['.obsidian', { type: 'folder', mtime: 1000, size: 0 }],
			['.obsidian/app.json', { type: 'file', mtime: 2000, size: 12 }],
		])
		const vault = {
			configDir: '.obsidian',
			getRoot: () => root,
			getAbstractFileByPath: (path: string) => (path === '' ? root : null),
			adapter: {
				exists: vi.fn(async (path: string) => adapterStats.has(path)),
				stat: vi.fn(async (path: string) => adapterStats.get(path) ?? null),
				list: vi.fn(async (path: string) => {
					if (path === '.obsidian') {
						return {
							files: ['.obsidian/app.json'],
							folders: [],
						}
					}
					return { files: [], folders: [] }
				}),
			},
		} as any

		const stats = await traverseLocalVault(vault, '')

		expect(stats.map((stat) => stat.path)).toEqual([
			'.obsidian',
			'.obsidian/app.json',
		])
		expect(stats.find((stat) => stat.path === '.obsidian/app.json')).toMatchObject({
			isDir: false,
			mtime: 2000,
			size: 12,
		})
	})
})
