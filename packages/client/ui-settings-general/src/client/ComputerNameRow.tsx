/** Desktop computer name shown by new mobile pairing links. */
import { useEffect, useState, type FormEvent } from 'react'
import type { InjectFace, PropsLocale, PropsRuntime } from '@deepseek-ai/dsh-client-ui-slots'
import type { DesktopComputerNameBridge } from '../types.ts'
import css from './ComputerNameRow.module.css'

interface ComputerNameRowInjected {
  computerName: DesktopComputerNameBridge
}

/** Edit the Desktop-owned pairing name in General Settings. */
export function ComputerNameRow({ computerName, t }:
  PropsRuntime<'settings.general.item'> & PropsLocale<'settings'> & InjectFace<ComputerNameRowInjected>) {
  const [name, setName] = useState('')
  const [saved, setSaved] = useState('')
  const [busy, setBusy] = useState(true)
  const [error, setError] = useState<'load' | 'invalid' | 'save' | null>(null)

  useEffect(() => {
    let active = true
    void computerName.get().then((value) => {
      if (!active) return
      setName(value)
      setSaved(value)
      setError(null)
    }).catch(() => {
      if (active) setError('load')
    }).finally(() => {
      if (active) setBusy(false)
    })
    return () => { active = false }
  }, [computerName])

  const save = (event: FormEvent<HTMLFormElement>): void => {
    event.preventDefault()
    const value = name.trim()
    if (value.length < 1 || value.length > 80 || /[\u0000-\u001f]/u.test(value)) {
      setError('invalid')
      return
    }
    setBusy(true)
    setError(null)
    void computerName.set(value).then((result) => {
      setName(result)
      setSaved(result)
    }).catch(() => { setError('save') }).finally(() => { setBusy(false) })
  }

  return <form className={css.row} onSubmit={save}>
    <div className={css.copy}>
      <label className={css.title} htmlFor="desktop-computer-name">{t('general.computerName')}</label>
      <div className={css.description}>{t('general.computerNameDescription')}</div>
      {error && <div className={css.error} role="alert">{t(error === 'invalid' ? 'general.computerNameInvalid' : 'general.computerNameError')}</div>}
    </div>
    <div className={css.controls}>
      <input id="desktop-computer-name" className={css.input} value={name} maxLength={80}
        disabled={busy} onChange={(event) => { setName(event.target.value); setError(null) }} />
      <button className={css.save} type="submit" disabled={busy || name.trim() === saved}>{t('general.computerNameSave')}</button>
    </div>
  </form>
}
