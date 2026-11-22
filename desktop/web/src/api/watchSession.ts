/**
 * Notices when the server says the session has ended (401 "signed_out":
 * signed out elsewhere, idle too long, or the server restarted), so the
 * desktop can return to the sign-in page instead of every app showing its
 * own error. Every request is watched, whichever app makes it, and the
 * refusal still reaches the caller.
 */
import { ApiError, type Api } from './types'

export function watchSession(api: Api, onSignedOut: () => void): Api {
  const report = (e: unknown) => {
    if (e instanceof ApiError && e.code === 'signed_out') onSignedOut()
    throw e
  }
  const watched = Object.fromEntries(
    Object.entries(api).map(([name, ask]) => [
      name,
      (...args: unknown[]) => {
        const answer = (ask as (...a: unknown[]) => unknown)(...args)
        return answer instanceof Promise ? answer.catch(report) : answer
      },
    ]),
  ) as unknown as Api
  return {
    ...watched,
    // A refused WebSocket carries no reason; ask whether the session is the cause.
    terminal: (size, handlers) =>
      api.terminal(size, {
        ...handlers,
        onEnd(reason) {
          if (reason === 'refused') void api.session().then((user) => user ?? onSignedOut(), () => {})
          handlers.onEnd(reason)
        },
      }),
  }
}
