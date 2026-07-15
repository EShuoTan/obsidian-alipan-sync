import { isNil, partial } from 'lodash-es'
import { normalizePath, TFolder, Vault } from 'obsidian'
import { isNotNil } from 'ramda'
import { StatModel } from '~/model/stat.model'
import GlobMatch from './glob-match'
import { statVaultItem } from './stat-vault-item'

export async function traverseLocalVault(vault: Vault, from: string) {
	const res: StatModel[] = []
	const q = [from]
	const ignores = [
		new GlobMatch(`${vault.configDir}/plugins/*/node_modules`, {
			caseSensitive: true,
		}),
	]
	function folderFilter(path: string) {
		path = normalizePath(path)
		if (ignores.some((rule) => rule.test(path))) {
			return false
		}
		return true
	}

	while (q.length > 0) {
		const current = q.shift()
		if (isNil(current)) {
			continue
		}

		const normalizedCurrent = normalizePath(current)
		const { files, folders } = await listLocalFolder(vault, normalizedCurrent)
		let nextFolders = folders

		if (normalizedCurrent === vault.getRoot().path) {
			const configDir = normalizePath(vault.configDir)
			if (
				!nextFolders.includes(configDir) &&
				await vault.adapter.exists(configDir)
			) {
				nextFolders = [...nextFolders, configDir]
			}
		}

		nextFolders = nextFolders.filter(folderFilter)
		q.push(...nextFolders)

		const contents = await Promise.all(
			[...files, ...nextFolders].map(partial(statVaultItem, vault)),
		).then((arr) => arr.filter(isNotNil))
		res.push(...contents)
	}
	return res
}

async function listLocalFolder(vault: Vault, folderPath: string) {
	const folder = vault.getAbstractFileByPath(folderPath)
	if (folder instanceof TFolder) {
		return {
			files: folder.children
				.filter((f) => !(f instanceof TFolder))
				.map((f) => f.path),
			folders: folder.children
				.filter((f) => f instanceof TFolder)
				.map((f) => f.path),
		}
	}

	const stat = await vault.adapter.stat(folderPath)
	if (stat?.type !== 'folder') {
		return { files: [], folders: [] }
	}

	const listed = await vault.adapter.list(folderPath)
	return {
		files: listed.files,
		folders: listed.folders,
	}
}
