// OpenCode adapter for kungfu — registers the shared skills/ dir and injects the
// using-kungfu bootstrap into the first user message. Mirrors superpowers'
// .opencode/plugins/superpowers.js pattern.
import path from 'path'
import fs from 'fs'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const skillsDir = path.resolve(__dirname, '../../skills')

let _bootstrap = null
function getBootstrap() {
  if (_bootstrap !== null) return _bootstrap
  try {
    const md = fs.readFileSync(path.join(skillsDir, 'using-kungfu', 'SKILL.md'), 'utf8')
    const m = md.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/)
    const content = m ? m[2] : md
    _bootstrap = `<EXTREMELY_IMPORTANT>\nYou have kungfu skills. The using-kungfu skill is included below and is ALREADY LOADED — do not re-load it with the skill tool.\n\n${content}\n</EXTREMELY_IMPORTANT>`
  } catch {
    _bootstrap = ''
  }
  return _bootstrap
}

export const KungfuPlugin = async () => ({
  // register the shared skills dir on the live config
  config: async (config) => {
    config.skills = config.skills || {}
    config.skills.paths = config.skills.paths || []
    if (!config.skills.paths.includes(skillsDir)) config.skills.paths.push(skillsDir)
  },
  // inject the bootstrap once, into the first user message
  'experimental.chat.messages.transform': async (_input, output) => {
    const bootstrap = getBootstrap()
    if (!bootstrap || !output.messages || !output.messages.length) return
    const firstUser = output.messages.find((m) => m.info && m.info.role === 'user')
    if (!firstUser || !firstUser.parts || !firstUser.parts.length) return
    if (firstUser.parts.some((p) => p.type === 'text' && p.text.includes('EXTREMELY_IMPORTANT'))) return
    const ref = firstUser.parts[0]
    firstUser.parts.unshift({ ...ref, type: 'text', text: bootstrap })
  },
})
