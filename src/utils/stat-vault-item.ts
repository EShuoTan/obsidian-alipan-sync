import { Vault } from 'obsidian'
import { StatModel } from '~/model/stat.model'
import { statLocalPath } from './local-file'

export async function statVaultItem(
	vault: Vault,
	path: string,
): Promise<StatModel | undefined> {
	return statLocalPath(vault, path)
}
