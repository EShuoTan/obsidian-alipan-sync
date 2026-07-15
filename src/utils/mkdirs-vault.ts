import { isNil } from 'lodash-es'
import { Vault } from 'obsidian'
import { dirname, normalize } from 'path-browserify'

export async function mkdirsVault(vault: Vault, path: string) {
	const stack: string[] = []
	let currentPath = normalize(path)
	if (currentPath === '/' || currentPath === '.') {
		return
	}
	if (vault.getAbstractFileByPath(currentPath)) {
		return
	}
	while (
		currentPath !== '' &&
		currentPath !== '/' &&
		currentPath !== '.' &&
		isNil(vault.getAbstractFileByPath(currentPath))
	) {
		stack.push(currentPath)
		currentPath = dirname(currentPath)
	}
	while (stack.length) {
		const pop = stack.pop()
		if (!pop) {
			continue
		}
		try {
			await vault.createFolder(pop)
		} catch {
			if (!(await vault.adapter.exists(pop))) {
				await vault.adapter.mkdir(pop)
			}
		}
	}
}
