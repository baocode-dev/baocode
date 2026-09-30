---
mode: agent
description: 'Review the current file'
tools: ['codebase', 'search']
---
# Review

Review ${file} for **bugs** and _style_ issues; see [the guide](../guide.md).

- Check `null` handling
- Use #file:src/main.ts as the reference

```ts
const answer: number = 42;
```
