import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['tests/**/*.test.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.d.ts', 'src/**/index.ts', 'src/**/abis.ts', 'src/**/types.ts'],
      thresholds: {
        lines: 64,
        functions: 63,
        branches: 58,
        statements: 63,
      }
    }
  }
});
