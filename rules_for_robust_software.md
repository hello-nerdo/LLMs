# Rules for Robust Software

_Principles for building maintainable applications across languages_

**Simplicity Over Cleverness**. **Simple** means one responsibility, one concept, one clear purpose. **Easy** means familiar, convenient or comfortable. These are completely different concepts. Always choose simple over easy when building systems you'll maintain long-term.

---

### Rule 1: One Decision, One Place

Don't create abstractions, indirections, or extractions until you have clear evidence they're needed.

#### Direct is Better Than Clever

**Keep it inline until you see real duplication:**

```typescript
// ✅ Good - One-off logic stays simple
if (user?.plan === 'premium') {
  return <PremiumFeature />;
}

// ✅ Good - Extract only when pattern emerges (3+ instances)
// After seeing this condition in multiple places:
const canAccessPremiumFeatures = (user: User | null) =>
  user?.plan === 'premium' || (user?.credits ?? 0) > 5;
```

**❌ Bad - Premature event bus:**

```typescript
interface EventBus {
  emit(event: string, data: any): void;
  on(event: string, handler: Function): void;
}

class OrderService {
  constructor(private eventBus: EventBus) {}

  async createOrder(data: OrderData) {
    const order = await this.saveOrder(data);
    this.eventBus.emit('order.created', order);
  }
}

class EmailService {
  constructor(private eventBus: EventBus) {
    eventBus.on('order.created', (order) => this.sendConfirmation(order));
  }
}
```

**✅ Good - Direct connection:**

```typescript
class OrderService {
  constructor(private emailService: EmailService) {}

  async createOrder(data: OrderData) {
    const order = await this.saveOrder(data);
    await this.emailService.sendOrderConfirmation(order);
    return order;
  }
}
```

### Rule 2: Use Type-Safe Structures

Replace branching logic with your language's type system. Let the compiler catch errors instead of runtime.

**❌ Bad - Error-prone conditionals:**

```typescript
function processWebhook(payload: any) {
  if (payload.type === 'user.created') {
    sendWelcomeEmail(payload.data.email);
  } else if (payload.type === 'payment.succeeded') {
    updateUserCredits(payload.data.user_id, payload.data.amount);
  } else if (payload.type === 'subscription.cancelled') {
    downgradeUser(payload.data.user_id);
  }
  // What happens when new webhook types are added?
}
```

**✅ Good - Type-safe exhaustive handling:**

```typescript
// Exhaustive discriminated union - compile-time safety
type WebhookEvent =
  | { type: 'user.created'; data: { email: string } }
  | { type: 'payment.succeeded'; data: { user_id: string; amount: number } }
  | { type: 'subscription.cancelled'; data: { user_id: string } };

const webhookHandlers = {
  'user.created': async (data: { email: string }) => {
    await sendWelcomeEmail(data.email);
  },
  'payment.succeeded': async (data: { user_id: string; amount: number }) => {
    await updateUserCredits(data.user_id, data.amount);
  },
  'subscription.cancelled': async (data: { user_id: string }) => {
    await downgradeUser(data.user_id);
  },
} as const;

async function processWebhook(payload: WebhookEvent) {
  const handler = webhookHandlers[payload.type];
  await handler(payload.data); // TypeScript ensures all cases handled
}
```

### Rule 3: Validate at Boundaries, Trust Internally

Check external data rigorously. Trust internal types completely. Never mix the two approaches.

**❌ Bad - Defensive programming everywhere:**

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

**✅ Good - Validate once at the boundary:**

```typescript
// Validate external data
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

// Trust internal types
function calculateTotal(items: CartItem[]) {
  return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}
```

### Rule 4: Build for Change

Group code by what it does, not what it is. Changes to business logic should affect one module, not many.

**❌ Bad - Organized by domain model:**

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

**✅ Good - Organized by feature:**

```typescript
// Each system handles its own concern
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

**Why?** When tax laws change, you modify the TaxCalculator. When payment rules change, you modify the PaymentValidator. A single business rule change affects one module, not many scattered classes.

### Rule 5: Data for State, Classes for Processes

Use plain data structures for information that moves through your system. Reserve classes for multi-step operations that orchestrate that data.

**❌ Bad - Mixing data and behavior:**

```typescript
class BlogPost {
  private id: string;
  private title: string;
  private content: string;
  private publishedAt: Date | null;

  publish() {
    this.publishedAt = new Date();
    Database.save(this);
    EmailService.notifySubscribers(this);
  }

  getWordCount() {
    return this.content.split(' ').length;
  }
}
```

**✅ Good - Separate data from processes:**

```typescript
// Plain data
type BlogPost = {
  id: string;
  title: string;
  content: string;
  publishedAt: Date | null;
};

// Pure functions for calculations
const getPostMetrics = (post: BlogPost) => ({
  wordCount: post.content.split(' ').length,
  readingTime: Math.ceil(post.content.split(' ').length / 200),
});

// Class for complex process
class PublishingPipeline {
  constructor(
    private validator: ContentValidator,
    private storage: Storage,
    private notifier: Notifier
  ) {}

  async publish(post: BlogPost): Promise<BlogPost> {
    await this.validator.validate(post);
    const published = { ...post, publishedAt: new Date() };
    await this.storage.save(published);
    await this.notifier.notifySubscribers(post.authorId);
    return published;
  }
}
```

---

## Quick Reference

1. **One Decision, One Place** - Wait for patterns, avoid premature abstraction
2. **Use Type-Safe Structures** - Let the compiler catch errors at compile time
3. **Validate at Boundaries** - Check external input once, trust internal data
4. **Build for Change** - Code that changes together lives together
5. **Data for State, Classes for Processes** - Separate data from behavior

Remember: **Profile before optimizing**. These patterns prevent common problems, but always measure your specific use case.
