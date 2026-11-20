// Vitest setup: jest-dom matchers and a matchMedia stub for MUI's useMediaQuery.
import '@testing-library/jest-dom/vitest'

if (!window.matchMedia) {
  window.matchMedia = (query: string) =>
    ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }) as MediaQueryList
}

// jsdom has no pointer capture; windows call it when a drag starts.
Element.prototype.setPointerCapture = () => {}
