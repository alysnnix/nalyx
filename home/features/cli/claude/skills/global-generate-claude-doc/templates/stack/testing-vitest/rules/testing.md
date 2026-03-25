---
paths:
  - "src/**/*.test.ts"
  - "src/**/*.test.tsx"
  - "src/**/*.spec.ts"
  - "src/**/*.spec.tsx"
  - "tests/**/*"
  - "__tests__/**/*"
---

# Testing Rules

## Stack

- **Vitest** - test runner
- **@testing-library/react** - component testing
- **jsdom** - DOM environment

## Commands

```bash
npm run test        # Run once
npm run test:watch  # Watch mode
npm run test:coverage # With coverage
```

## Structure

```tsx
import { describe, test, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';

vi.mock('@/contexts/AuthContext');

describe('Component', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test('should render correctly', () => {
    render(<Component />);
    expect(screen.getByText('text')).toBeInTheDocument();
  });

  test('should handle async operations', async () => {
    render(<Component />);

    fireEvent.click(screen.getByRole('button'));

    await waitFor(() => {
      expect(screen.getByText('loaded')).toBeInTheDocument();
    });
  });
});
```

## Common Mocks

### Context

```tsx
vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({
    user: { id: 'user-1' },
    isAuthenticated: true,
  }),
}));
```

### API Client

```tsx
vi.mock('@/lib/api', () => ({
  api: {
    get: vi.fn(() => Promise.resolve({ data: [] })),
    post: vi.fn(() => Promise.resolve({ data: {} })),
  },
}));
```

### Router

```tsx
vi.mock('react-router-dom', async () => {
  const actual = await vi.importActual('react-router-dom');
  return {
    ...actual,
    useNavigate: () => vi.fn(),
    useParams: () => ({ id: 'test-id' }),
  };
});
```

## Rules

1. Always `vi.clearAllMocks()` in `beforeEach`
2. Use `waitFor` for async operations
3. Test behavior, not implementation
4. Test file names in kebab-case
5. One assertion focus per test
