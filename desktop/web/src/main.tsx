/** Entry point: fonts, global styles and the app. */
import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/inter'
import './global.css'
import { api } from './api'
import { App } from './App'

createRoot(document.getElementById('root') as HTMLElement).render(
  <StrictMode>
    <App api={api} />
  </StrictMode>,
)
