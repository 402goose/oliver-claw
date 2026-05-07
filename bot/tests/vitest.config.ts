import { defineConfig } from 'vitest/config'
export default defineConfig({
  test: {
    include: ['**/*.test.{js,mjs,ts}'],
    testTimeout: 30000,
    hookTimeout: 30000,
  },
})
