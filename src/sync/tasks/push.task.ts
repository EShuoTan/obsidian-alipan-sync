import logger from '~/utils/logger'
import { readLocalBinary } from '~/utils/local-file'
import { BaseTask, toTaskError } from './task.interface'

export default class PushTask extends BaseTask {
	async exec() {
		try {
			if (!this.remoteStorage) {
				throw new Error('Remote storage not available')
			}

			const content = await readLocalBinary(this.vault, this.localPath)
			const res = await this.remoteStorage.putFileContents(
				this.remotePath,
				content,
				{ overwrite: true },
			)
			if (!res) {
				throw new Error('Upload failed')
			}
			return { success: res }
		} catch (e) {
			logger.error(this, e)
			return { success: false, error: toTaskError(e, this) }
		}
	}
}
