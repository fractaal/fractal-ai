---
name: fullstack-conventions
description: >-
  Ben's default stack and conventions for building a client<->server TypeScript
  application from scratch — frontend, backend, and the typed contract between
  them. Load this WHENEVER standing up a new web app, package, or service;
  scaffolding a monorepo; laying out frontend/backend/API structure; setting up
  tRPC, a Hono/Fastify backend, a Vite + React SPA, TanStack Router/Query,
  Zustand, or Tailwind/shadcn; defining the shapes/procedures that cross the
  client<->server boundary; deciding where shared types live; or weighing runtime
  validation (Zod), a data-fetching library, a state manager, or a metaframework.
  Especially load it on GREENFIELD work, where these defaults are cheap to set
  and expensive to change later. Portable principles plus a concrete, decided TS
  reference stack. Keywords: greenfield, new app, new service, scaffolding,
  monorepo, tRPC, Hono, Fastify, Vite, React, TanStack Router, TanStack Query,
  React Query, Zustand, Tailwind, shadcn, Zod, contract, DTO, data contract, API
  boundary, error handling, OpenAPI, oRPC, SPA, metaframework.
---

# Fullstack Conventions

Ben's default way to build a thing with a client, a server, and a typed contract
between them — starting fresh. Two layers: a small set of **portable principles**
(true in any language), and a **decided reference stack** (the concrete
TypeScript choices to reach for by default so this never gets re-litigated per
project). Read the principles for the *why*; use the stack as the default *how*.

> These are **defaults for fresh/greenfield work.** In an *existing* repo, that
> repo's own `AGENTS.md` / `CLAUDE.md` is authoritative and wins — including
> third-party repos Ben works in but doesn't own, which will have different
> stacks and conventions. Don't impose this skill on them; read theirs first.
> See [Per-repo variation](#per-repo-variation).

---

## The default stack

Decided defaults. Each has an escape hatch for when a project genuinely needs it
— but the point of a default is you don't re-argue it every time.

| Layer | Default | Escape hatch |
|---|---|---|
| Language | TypeScript everywhere, one pnpm monorepo | — |
| Frontend | **Vite + React** (SPA) | **TanStack Start** *only if* SSR/SSG is a real need (public/SEO/first-paint). Never Next. |
| Routing | **TanStack Router** (type-safe) | React Router (library mode) |
| Server state | **TanStack Query**, driven by tRPC hooks | — |
| Client-only state | **Zustand** | — |
| Styling | **Tailwind + shadcn/ui** | — |
| Contract | **tRPC** (router type = the contract) | **oRPC** or OpenAPI *the day* a non-TS client is real. Not before. |
| Backend | **Hono** + tRPC server adapter | **Fastify** if you want more batteries; Node-only |
| Validation | **Zod** at the tRPC input boundary | — |
| Shared types | one pure-TS `packages/contracts` | — |

**Why these and not the obvious alternatives**, in one line each, because the
reasoning is the reusable part:

- **Vite + React, not Next** — the backend is deliberately *separate*; Next's
  "server and client are one" (RSC/server actions) fights that separation. React
  because it has the densest ecosystem support for everything else here (tRPC,
  Query, shadcn are all React-first). Vue/Quasar is genuinely nice to hand-write,
  but every other choice below is second-class in Vue.
- **TanStack Router gives metaframework-grade client DX** (type-safe routes,
  params, search-state, loaders, code-splitting) **without a server** — the sweet
  spot when you don't want a metaframework's server layer.
- **tRPC, not oRPC/OpenAPI, by default** — simpler, more battle-tested, and if
  every client is TS you never need the schema. Add oRPC/OpenAPI *when* a non-TS
  consumer actually appears (YAGNI).
- **Hono, not Fastify, by default** — tRPC already does validation + typing, so
  Fastify's headline batteries are redundant here; you want the thinnest,
  best-typed host. Hono also runs on Node/Bun/edge with no lock-in.

### Monorepo shape

```txt
apps/web         Vite + React SPA
apps/api         Hono + tRPC router (exports `type AppRouter`)
packages/contracts   pure TS: domain types, Zod schemas, shared unions, error-data shape
```

- `apps/web` gets full type safety by importing **`import type { AppRouter }`**
  from `apps/api`. It's a *type-only* import — erased at build, so there is **no
  runtime coupling** between web and api. Shared *runtime* values (Zod schemas,
  domain constants) live in `packages/contracts`, which both import.
- `packages/contracts` stays **pure**: no Hono, no DB driver, no React, no
  Node/browser APIs. The moment it imports one of those it stops being a contract.

---

## The one idea

**The typed contract at the boundary is the center of gravity.** With tRPC that
contract is the **router type** — the client infers every procedure's input and
output from it. Design from the user story *inward* to the procedure ("user opens
X → the client needs exactly this → the procedure returns exactly that"), and the
client and server fall out of it. Get the boundary right and both sides are easy;
get it wrong and no amount of clean code on either side saves you.

---

## Principles

Stack-agnostic; the reference sections show them instantiated.

### 1. Contract before consumer
The procedure/shape is the source of truth. Define or change it before wiring
either side against it; ideally change the router and both consumers in one move
so they can never disagree. A boundary is the one place a type error becomes an
invisible runtime error — making it a single declared thing both sides import is
how you turn "silent shape drift" back into "the build breaks."

### 2. Less code; earn every abstraction
Every line is a liability. Three similar lines beat a premature abstraction. Long
but readable beats terse and arcane (plain if/else over a nested ternary). Full
names, no cryptic abbreviations. Before adding a field, flag, procedure, wrapper,
or dependency, prove the simpler version is insufficient. See
`prove-why-this-needs-to-exist`.

### 3. Loud failures over silent fallbacks
When something can't be done, throw with a message saying what was expected and
how to fix it. Don't silently return a degraded/empty/placeholder result — a
"safety" fallback just converts a loud, fixable error into a quiet heisenbug that
ships. Go further and build *explicit* guards for the ways your system silently
degrades (e.g. reject a generated artifact that's suddenly a fraction of its
prior size, rather than serving the stub). Fix the root cause, not the symptom.

### 4. Validation lives at the trust boundary — and mostly only there
Untrusted input crossing into your system gets validated; trusted internal data
does not. With tRPC that boundary is `.input(zodSchema)` on each procedure — one
declaration gives you runtime validation *and* the inferred input type, so Zod
there is the norm, not ceremony. What's *not* the norm: Zod-wrapping internal
service functions that only ever receive already-validated data, or adding output
schemas reflexively. When you accept free-form JSON, **bound it** (max
depth/keys/array length/string length/bytes) before it reaches logic.

### 5. One home per concept; respect the boundary
Shared types live in one pure package. The client never imports server *runtime*
internals (type-only `AppRouter` import aside); integration is the tRPC contract,
nothing else. Business logic must not know about transport concerns (HTTP, the
Hono app, IPC).

### 6. Absence should mean something
Model "no state" as a missing record, not an empty placeholder kept to remember
absence. When it's a document-store / Firestore question, the deep version is in
the `firestore-design` skill — load it.

---

## Contract / types reference (tRPC)

The heart of the skill. In a tRPC world the router *is* the DTO layer, so the
REST habit of hand-writing `FooRequest`/`FooResponse` for every call **mostly
goes away** — tRPC infers those from the procedure. Here's what to do instead.

### What lives where
- **Procedure inputs/outputs** — defined on the procedure (`.input(...)`, return
  type). The client infers them from `AppRouter`. Don't duplicate them as
  hand-written interfaces.
- **`packages/contracts`** holds the *reused* pieces: domain/entity types
  (`Project`, `ConnectorDetail`), the **Zod schemas** for procedure inputs (so a
  form on the client and the procedure on the server validate against the same
  schema), cross-cutting unions/enums, and the app's **error-data shape**.
- **Request/Response naming** is only for the rare **non-tRPC REST endpoint**
  (webhook, OAuth callback, public API). There, name by role —
  `XRequest`/`XResponse`/`XEvent` — never `FooDTO`.

### Types, the house style
- `interface`/`type`, never `class`, for data shapes. Extend a base rather than
  repeat fields.
- Enums are **string-literal unions** (`type Status = 'active' | 'error'`), or a
  `const` array narrowed to a union when you need the runtime list too:
  ```ts
  export const ROLES = ['owner', 'editor', 'viewer'] as const;
  export type Role = (typeof ROLES)[number];
  ```
- **Optional vs nullable are different — spell them differently.** `?:` = the key
  may be absent. `| null` = present and explicitly null. Use a `Nullable<T>`
  helper when you mean null.

### Errors are part of the contract
- Throw **`TRPCError`** with one of its built-in codes (`BAD_REQUEST`,
  `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `CONFLICT`, `TOO_MANY_REQUESTS`,
  `INTERNAL_SERVER_ERROR`, …). That set *is* your fixed error-code union — you
  don't hand-roll an `ApiError` envelope; tRPC gives you one.
- For app-specific error data, attach a typed shape via the tRPC **error
  formatter** (define that shape once in `contracts`), so the client gets typed,
  actionable errors instead of a bare string.

### Change by migration, not versioning
Don't fork shapes (`FooV2`). When a shape must change under a live client, keep a
small `Legacy*`/`Compatible*` union to *read* the old form during a one-release
window, then delete it.

### Mechanics
ESM (`"type": "module"`, `.js` import specifiers in TS source). One barrel
`index.ts` per package. Zod v4.

---

## Frontend reference (Vite + React)

### Data: tRPC hooks, not hand-rolled fetch
- Server data comes through **tRPC's TanStack Query integration**
  (`@trpc/tanstack-react-query`) — typed hooks like `trpc.project.list.useQuery()`.
  No hand-written `fetch` provider modules; that's the REST idiom tRPC frees you
  from. Reach for raw `fetch` only for the odd non-tRPC endpoint.
- **Zustand is for client-only state** — UI toggles, local drafts, ephemeral
  selection. **Server data does not go in Zustand**; it lives in the Query cache.
  Mixing the two is the most common state-architecture mistake here.

### Structure
- **TanStack Router** for routing (type-safe params + search state). **Vite** for
  build/dev. **Tailwind + shadcn/ui** for UI.
- `src/` splits into `components/ routes/ hooks/ state/ lib/ utils/`.
- **Never hardcode the API URL.** Read it from env; in dev, proxy to the api
  process. Ports/hosts are transient transport, never baked into code.

### Visual craft
For hierarchy, aesthetic budget, product grammar, copy austerity, and animation
discipline, **load `frontend-design-by-fractal`** — that's where Ben's UI taste
lives; don't re-derive it here. One architectural note that isn't aesthetic:
**keep conditionally-shown elements mounted and toggle a class** rather than
unmounting — React unmounts skip the exit transition, so animated dismissals just
pop. And **get real visual feedback** (drive Chrome DevTools MCP); if it's
unavailable on a frontend task, say so rather than building blind.

---

## Backend reference (Hono + tRPC)

- **Hono app hosts the tRPC router** via the tRPC server adapter
  (`@hono/trpc-server`), typically mounted at `/trpc`. Plain Hono routes handle
  the non-tRPC surface: `/health`, webhooks, OAuth callbacks, static/file serving.
- **Organize tRPC routers by domain** — one sub-router per capability
  (`projectRouter`, `chatRouter`), merged into the root `AppRouter`. Don't pile
  every procedure into one file.
- **Context** (auth, db handles, request identity) is built once in
  `createContext` and flows to every procedure; auth/permission checks live in
  reusable middleware procedures, not copy-pasted per handler.
- **Errors** via `TRPCError` (see contract section).
- **Paths/secrets:** durable paths are namespace-scoped and never embed a port.
  Don't log secrets, tokens, or full prompt/PII payloads. Keep business logic out
  of transport concerns.

*Escape hatch:* swap Hono→**Fastify** if you want built-in schema/serialization,
Pino logging, and the larger plugin ecosystem, and you're staying on Node. tRPC
has a first-class Fastify adapter too.

---

## Greenfield checklist

When standing up a *new* app — the moment this skill is loudest, because these
choices are cheap now and expensive later:

1. **Scaffold the monorepo** with `apps/web`, `apps/api`, `packages/contracts`.
   Create `contracts` first — it sets the dependency direction.
2. **Stand up `AppRouter` with one real procedure** (input Zod schema, real
   return) and `createContext`, before building breadth.
3. **Wire the tRPC client + one `useQuery`** on the web side against that
   procedure. Prove the type flows end to end (change the procedure, watch the
   client type break).
4. **Set the API URL via env + dev proxy** so the client never learns the api's
   port.
5. **Ship one end-to-end vertical slice** — user action → tRPC hook → procedure →
   response → render — *before* going wide. A working spine proves the boundary;
   breadth on an unproven boundary is rework waiting to happen (Rule 5: verify the
   feature, not the proxy).
6. **Only then** decide if this project has earned any escape hatch — SSR
   (TanStack Start), a non-TS contract (oRPC/OpenAPI), Fastify. Default is no.

---

## Review checklist

Before approving frontend / backend / contract work:

- What user action drives this, and does the procedure return exactly the small
  shape the UI needs — no more?
- Is the contract one declared thing both sides derive from, or have they drifted?
- Did the router/schema change land before (or with) its consumers?
- Is validation at the input boundary (`.input`) and absent in the trusted middle?
  Is free-form JSON bounded?
- Do failures throw `TRPCError` loudly, or is something silently falling back?
- Is server data in the Query cache (not Zustand)? Is client-only state in Zustand
  (not refetched)?
- Does `packages/contracts` still import nothing framework/DB/React-specific? Is
  the web→api import type-only?
- Any port/host baked into code or a durable path?
- UI: loading/error/empty states, keyboard, responsive? Do exit animations play
  (element kept mounted)?
- Is any new field/flag/procedure/dependency provably necessary?

---

## Per-repo variation

This skill is the **starting default for fresh work.** It is **not** an override
for existing repos:

- **In a repo Ben owns**, its `AGENTS.md` / `CLAUDE.md` wins where it differs.
- **In a third-party repo** Ben works in but doesn't own, its stack and
  conventions are simply different (it may be Next + Express + REST, or C#, or
  anything). Read *its* guide and follow it; do not retrofit this skill's stack.
- Things that legitimately vary by repo and must not be flattened into universals:
  commit cadence, worktree usage, how heavy review should be, and whether Zod /
  runtime validation is used at all.

When in doubt, read the project's own guide first; apply these defaults only where
the project is silent — or when there's no project yet, which is exactly when this
skill matters most.
