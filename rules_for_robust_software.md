# Rules for Robust Software

> Choose `simple` over `easy`.

Writing simple code can be harder up front, but it's much easier to maintain, understand, and extend over time.

- `Simple` means every piece of code has a single, clear purpose and does one thing well.
- `Easy` only means something feels familiar or comfortable.

`Easy` depends on your skill level and experience. `Simple` is an attribute of your code.

Try to consider the next developer who will read or maintain your code. What will their first impression be? What are they likely trying to accomplish? What wrong assumptions might they make?

The rules below are my heuristics for writing code that is is `simple` but rarely is this the `easy` way.

---

### Rule 1: Data for State, Functions for Processes

In order to not leave consumers guessing, we should:

1. Use plain data structures for state.
2. Use functions to change that state.

It is `easy` to let an object's methods change its internal state, but this often causes confusion and makes it hard for others to know what properties are available at any given time.

**Bad. Class methods add properties, so you can't be sure what is set:**

```typescript
class Session {
  visitorId: string;

  // These may exist or not, depending on whether login() ran
  userId?: string;
  accessToken?: string;

  async login(credentials: Credentials) {
    const auth = await authenticate(credentials);
    this.userId = auth.userId;
    this.accessToken = auth.token;
  }

  logout() {
    this.userId = undefined;
    this.accessToken = undefined;
    // BUG: If someone later adds a new field (e.g., permissions, paymentMethods)
    // and forgets to clear it here, User B inherits User A's data
  }
}
```

**Good. Each type clearly shows its fields:**

```typescript
type AnonymousSession = {
  visitorId: string;
};

type AuthenticatedSession = {
  visitorId: string;
  userId: string;
  accessToken: string;
};

const login = async (
  session: AnonymousSession,
  credentials: Credentials
): Promise<AuthenticatedSession> => {
  const auth = await authenticate(credentials);
  return {
    visitorId: session.visitorId,
    userId: auth.userId,
    accessToken: auth.token,
  };
};

const logout = (session: AuthenticatedSession): AnonymousSession => {
  // Only visitorId carries over—impossible to accidentally leak fields
  return { visitorId: session.visitorId };
};
```

**Why?** In the bad example, `logout()` must remember to clear every authenticated field. When a developer adds a new field months later, they must also update `logout()`—and if they forget, one user's data leaks to another. In the good example, `logout()` explicitly constructs a new `AnonymousSession` with only the fields it should have. New fields added to `AuthenticatedSession` can't leak because they're never copied over.

### Rule 2: Group code by what it does instead of what it is.

Choosing the right boundaries between "services" is a constant battle. But, I have found that focusing on the `verbs` instead of the `nouns` is typically better in the long run.
Ideally, if a business rule changes, we should update only one file / module / microservice.

**Bad. Grouped by domain model:**

```typescript
class Order {
  private items: OrderItem[];
  private customer: Customer;

  calculateTax(): number {
    // Tax logic mixed with order logic
    const subtotal = this.calculateSubtotal();
    const taxRate = TaxRates[this.customer.state];
    return subtotal * taxRate;
  }

  validatePayment(payment: Payment): boolean {
    // Payment logic mixed with order logic
    return payment.amount >= this.calculateTotal();
  }

  generateInvoice(): Invoice {
    // Invoice logic mixed with order logic
    return new Invoice(this);
  }
}
```

**Good. Grouped by what they do:**

```typescript
// Each part handles one job
class TaxCalculator {
  calculate(items: OrderItem[], state: string): TaxBreakdown {
    const subtotal = items.reduce((sum, item) => sum + item.total, 0);
    const stateTax = this.getStateTax(state, subtotal);
    const federalTax = this.getFederalTax(subtotal);
    return { stateTax, federalTax, total: stateTax + federalTax };
  }
}

class PaymentValidator {
  validate(payment: Payment, requiredAmount: number): ValidationResult {
    if (payment.amount < requiredAmount) {
      return { valid: false, reason: 'Insufficient amount' };
    }
    if (!this.isCardValid(payment.card)) {
      return { valid: false, reason: 'Invalid card' };
    }
    return { valid: true };
  }
}
```

**Why?** When tax rules change, we can edit only TaxCalculator. When payment rules change, we can edit only PaymentValidator.

### Rule 3: Repetition is okay, but not encouraged

Do not create abstractions, extra layers, or move code out until you are certain they are needed.
Premature abstractions tend to stay bad and get worse over time.
Coupling transformations / functions too early makes it harder to find the correct boundaries between systems.

> Write things inline until you run into 3+ instances of the same pattern.

**Bad. Abstracted too early, became a junk drawer:**

```typescript
// Started simple: format a user's name
const formatUserName = (user: User) => `${user.firstName} ${user.lastName}`;

// Then someone needed "Last, First" for a table...
// Then someone needed a fallback for missing names...
// Then someone needed a title prefix for formal contexts...
// Now you have this:
const formatUserName = (
  user: User,
  options: {
    lastFirst?: boolean;
    fallback?: string;
    includeTitle?: boolean;
    maxLength?: number;
  } = {}
) => {
  if (!user.firstName) return options.fallback ?? 'Anonymous';
  const title = options.includeTitle ? `${user.title} ` : '';
  const name = options.lastFirst
    ? `${user.lastName}, ${user.firstName}`
    : `${user.firstName} ${user.lastName}`;
  const full = `${title}${name}`;
  return options.maxLength ? full.slice(0, options.maxLength) : full;
};
```

Every new case added a flag instead of questioning whether this should be one function at all. Now it's a branching mess that no one wants to touch.

**Good. Inline until the real pattern emerges:**

```typescript
// Table component - needs "Last, First"
<td>{`${user.lastName}, ${user.firstName}`}</td>

// Avatar component - needs fallback
<span>{user.firstName ?? 'Anonymous'}</span>

// Formal letter - needs title
<p>{`${user.title} ${user.firstName} ${user.lastName}`}</p>

// After seeing the REAL patterns, you might extract:
const formatNameForTable = (user: User) =>
  `${user.lastName}, ${user.firstName}`;

// Or you might realize: these share almost nothing.
// No abstraction needed.
```

**Why?** Waiting reveals whether the cases are truly similar or just superficially alike.

### Rule 4: Use Type-Safe Structures

Let your language's type system handle branching. The compiler should stop errors before your code runs.

**Bad. Optional fields force runtime guessing:**

```typescript
type ApiResponse = {
  success: boolean;
  data?: User;
  error?: string;
};

function handleResponse(res: ApiResponse) {
  if (res.success) {
    console.log(res.data.name); // BUG: data might be undefined
  } else {
    console.log(res.error); // BUG: error might be undefined
  }
}

// Nothing stops you from creating invalid states:
const broken: ApiResponse = { success: true, error: 'wat' };
const alsoBroken: ApiResponse = { success: false }; // no error message
```

**Good. Discriminated union makes invalid states unrepresentable:**

```typescript
type ApiResponse = { success: true; data: User } | { success: false; error: string };

function handleResponse(res: ApiResponse) {
  if (res.success) {
    console.log(res.data.name); // Guaranteed to exist
  } else {
    console.log(res.error); // Guaranteed to exist
  }
}

// Invalid states are now compile errors:
const broken: ApiResponse = { success: true, error: 'wat' }; // ✗ Error
const alsoBroken: ApiResponse = { success: false }; // ✗ Error
```

**Why?** In the bad example, `success: true` doesn't guarantee `data` exists—you're trusting convention, not the compiler. In the good example, TypeScript knows that when `success` is `true`, `data` must exist. The type system enforces correctness, so bugs are caught at compile time instead of production.

### Rule 5: Validate at Boundaries, Trust Internally

Validate incoming data right away. Inside of functions / modules / services, trust your types.

**Bad. Defensive programming everywhere:**

```typescript
function calculateTotal(items: CartItem[] | null | undefined) {
  if (!items || !Array.isArray(items)) return 0;

  return items.reduce((sum, item) => {
    if (!item || typeof item.price !== 'number') return sum;
    if (!item.quantity || typeof item.quantity !== 'number') return sum;
    return sum + item.price * item.quantity;
  }, 0);
}
```

**Good. Validate once at the edge:**

```typescript
// Validate data coming in
import { z } from 'zod';

const CartItemSchema = z.object({
  price: z.number().positive(),
  quantity: z.number().int().positive(),
});

async function fetchCart(): Promise<CartItem[]> {
  const response = await fetch('/api/cart');
  const data = await response.json();
  return z.array(CartItemSchema).parse(data); // Runtime validation
}

// Trust the types inside your app
function calculateTotal(items: CartItem[]) {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}
```
Ï
