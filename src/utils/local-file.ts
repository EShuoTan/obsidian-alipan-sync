import { normalizePath, TFile, TFolder, Vault } from 'obsidian'
import { dirname } from 'path-browserify'
import { StatModel } from '~/model/stat.model'
import { mkdirsVault } from './mkdirs-vault'

export async function statLocalPath(
	vault: Vault,
	path: string,
): Promise<StatModel | undefined> {
	path = normalizePath(path)
	const file = vault.getAbstractFileByPath(path)
	if (file instanceof TFolder) {
		return {
			path,
			basename: basenamePath(path),
			isDir: true,
			isDeleted: false,
		}
	}
	if (file instanceof TFile) {
		return {
			path,
			basename: basenamePath(path),
			isDir: false,
			isDeleted: false,
			mtime: file.stat.mtime,
			size: file.stat.size,
		}
	}

	const stat = await vault.adapter.stat(path)
	if (!stat) {
		return undefined
	}
	return stat.type === 'folder'
		? {
				path,
				basename: basenamePath(path),
				isDir: true,
				isDeleted: false,
			}
		: {
				path,
				basename: basenamePath(path),
				isDir: false,
				isDeleted: false,
				mtime: stat.mtime,
				size: stat.size,
			}
}

export async function readLocalBinary(
	vault: Vault,
	path: string,
): Promise<ArrayBuffer> {
	path = normalizePath(path)
	const file = vault.getFileByPath(path)
	if (file) {
		return vault.readBinary(file)
	}
	return vault.adapter.readBinary(path)
}

export async function writeLocalBinary(
	vault: Vault,
	path: string,
	data: ArrayBuffer,
) {
	path = normalizePath(path)
	const file = vault.getFileByPath(path)
	if (file) {
		await vault.modifyBinary(file, data)
		return
	}

	await mkdirsVault(vault, dirname(path))
	await vault.adapter.writeBinary(path, data)
}

export async function removeLocalPath(vault: Vault, path: string) {
	path = normalizePath(path)
	const file = vault.getAbstractFileByPath(path)
	if (file) {
		await vault.trash(file, false)
		return
	}

	const stat = await vault.adapter.stat(path)
	if (!stat) {
		return
	}
	if (stat.type === 'folder') {
		await vault.adapter.rmdir(path, true)
		return
	}
	await vault.adapter.remove(path)
}

function basenamePath(path: string) {
	const parts = normalizePath(path).split('/').filter(Boolean)
	return parts[parts.length - 1] ?? ''
}
