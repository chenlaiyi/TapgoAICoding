/** Verified worker archives admit only a single regular executable. */
import { mkdtemp, mkdir, writeFile, readFile, stat, rm, symlink } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { c as createTar } from 'tar'
import { expect, it } from 'vitest'
import { installCuaWorkerArchive } from '../scripts/prepare-cua-worker.ts'

it.each(['regular', 'missing', 'symlink', 'duplicate'] as const)('handles a %s worker archive without extracting unrelated files', async (kind) => {
  const root = await mkdtemp(join(tmpdir(), 'dsh-worker-archive-test-'))
  try {
    const input = join(root, 'input')
    await mkdir(input)
    await writeFile(join(input, 'other'), 'unrelated')
    if (kind === 'symlink') await symlink('other', join(input, 'cua-driver'))
    else await writeFile(join(input, 'cua-driver'), 'executable fixture')
    const archive = join(root, 'worker.tar.gz')
    await createTar({ file: archive, cwd: input, gzip: true }, kind === 'missing' ? ['other'] : kind === 'duplicate' ? ['cua-driver', 'cua-driver'] : ['cua-driver', 'other'])
    const output = join(root, 'output')
    if (kind === 'regular') {
      await installCuaWorkerArchive(archive, output)
      expect(await readFile(join(output, 'cua-driver'), 'utf8')).toBe('executable fixture')
      expect((await stat(join(output, 'cua-driver'))).mode & 0o777).toBe(0o755)
      await expect(stat(join(output, 'other'))).rejects.toMatchObject({ code: 'ENOENT' })
    } else {
      await expect(installCuaWorkerArchive(archive, output)).rejects.toThrow('desktop Cua worker:')
      await expect(stat(output)).rejects.toMatchObject({ code: 'ENOENT' })
    }
  } finally { await rm(root, { recursive: true, force: true }) }
})
