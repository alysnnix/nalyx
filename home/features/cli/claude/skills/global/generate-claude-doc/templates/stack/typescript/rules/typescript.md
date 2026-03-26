---
paths:
  - "src/**/*.ts"
  - "src/**/*.tsx"
  - "**/*.ts"
  - "**/*.tsx"
---

# TypeScript Rules

## Typing

```tsx
// GOOD - explicit types
interface Props {
  id: string;
  onAction: (id: string) => void;
}

// BAD - avoid any
function fetch(id: any): any { ... }
```

## Path Aliases

```tsx
// GOOD
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';

// BAD
import { useAuth } from '../../../contexts/AuthContext';
```

## Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Components | PascalCase | `UserCard` |
| Hooks | camelCase + use | `useAuth`, `useIsMobile` |
| Functions | camelCase | `calculateTotal` |
| Constants | UPPER_SNAKE | `MAX_ITEMS` |
| Booleans | is/has/can | `isActive`, `hasPermission` |
| Types/Interfaces | PascalCase | `UserProfile` |

## Validation (Zod)

```tsx
import { z } from 'zod';

const schema = z.object({
  id: z.string().uuid(),
  email: z.string().email(),
});

const result = schema.safeParse(data);
if (!result.success) return;
```

## Component Structure

```tsx
// 1. Imports
// 2. Types/Interfaces
// 3. Component
// 4. Export

interface Props { ... }

const MyComponent = ({ prop }: Props) => {
  // hooks first
  const { user } = useAuth();
  const [state, setState] = useState();

  // handlers
  const handleAction = () => { ... };

  // render
  return <div>...</div>;
};

export default MyComponent;
```

## Null Handling

```tsx
// GOOD - optional chaining
const name = user?.profile?.name;

// GOOD - nullish coalescing
const value = data ?? defaultValue;

// BAD - loose equality
if (value == null) { ... }
```
