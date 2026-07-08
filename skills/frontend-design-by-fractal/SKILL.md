---
name: frontend-design-by-fractal
description: |
  Ben-specific frontend design discipline for polished app UI with restraint,
  hierarchy, product grammar, aesthetic budget, style reasoning, and tasteful
  delight. Use when Ben asks for a frontend prototype, UI rewrite, design iteration,
  app shell, dashboard, landing page, or critiques UI as gaudy, generic,
  derivative, fake, sloppy, or visually broken. Do NOT use as a generic
  frontend-design replacement unless explicitly requested.
metadata:
  author: Ben Rocat and Aria
  version: 0.3.0
---

# Frontend Design by Fractal

## Critical Principle

Frontend craft is not only screenshot taste. It is also reasoning about the CSS system before the browser embarrasses you.

Before claiming a UI is good, inspect the actual style mechanics: selector scope, class-name collisions, inherited fonts, box model, width, density, color semantics, token usage, and responsive behavior. Visual confirmation is valuable, but it is not a substitute for reading the styles. A screenshot catches symptoms. Style reasoning catches the cause.

Beautiful app UI is controlled attention.

Start restrained, competent, and credible. Then spend aesthetic budget deliberately. Every visual technique is a degree of freedom. If you spam it, it stops carrying information. If you exercise it without a clear reason, it adds noise without signal and makes the product feel amateur.

If everything is loud, nothing is loud. If everything is glassy, nothing is material. If everything is mono, nothing reads as telemetry. If everything is a card, nothing feels grouped. If every surface has a border, borders lose meaning. If every label is clever, the product sounds fake.

The goal is not minimalism for its own sake. The goal is a product interface that feels real, usable, ownable, and delightful because every choice has a job.

## Core Rule: Every Design Choice Has a Budget

Treat each design muscle as limited:

- Color
- Borders
- Containers
- Gradients
- Motion
- Icons
- Typography contrast
- Shadows
- Copy personality
- Data visualization
- Density

Use each one sparingly enough that it keeps informational value.

### High-budget elements

Only two or three things on a screen should get strong treatment:

- Brand mark
- Primary action
- Selected state
- Critical alert
- Active object
- Signature interaction
- Main metric or main content surface

### Medium-budget elements

These can receive moderate emphasis:

- Hover states
- Focus states
- Active tabs
- Metric changes
- Important attachments
- Secondary actions
- Status chips

### Low-budget elements

These should usually stay quiet:

- Navigation
- Labels
- Metadata
- Timestamps
- Secondary buttons
- Most rows
- Most charts
- Most containers
- Most supporting text

If the interface feels bland, do not immediately add effects everywhere. First decide where the budget should be spent.

## Style Mechanics Are Product Quality

Do not treat CSS as a dump of visual vibes. Every class and selector participates in a system. A small naming or inheritance mistake can make the whole product feel cheap.

Before shipping or showing UI, reason through these mechanics:

- Selector scope: does this selector hit only this component, or can it hit unrelated surfaces?
- Component contracts: before writing selectors for a shared component, inspect the rendered DOM or component source and target the class, element, slot, or attribute it actually emits. A shared icon component might render `.ms` instead of `.icon`; that mismatch creates dead CSS unless you pass an explicit scoped className.
- Class names: are generic names like `result`, `card`, `item`, `active`, `error`, `ms`, or `p` colliding with global styles?
- Font inheritance: is text accidentally using an icon font, mono utility, display font, or inherited button default? Is mono being used because alignment/telemetry requires it, or just because the UI wants to feel technical?
- Surface opacity: is translucency/glass communicating layering or focus, or is it making text harder to read for no product reason?
- Box model: what exact width, height, padding, radius, and display mode does the element resolve to? If Ben is asking about spacing, verify with actual rendered measurements or computed styles before answering — not visual vibes.
- Optical spacing: do left/right insets, row/action gaps, stacked-button gaps, scrollbar gutters, and fade bands resolve to the same perceived rhythm? Account for scrollbars explicitly; a raw scrollbar can make a mathematically equal layout look too tight on the right.
- Layout pressure: what happens when labels, counts, paths, durations, or translated text get longer?
- Color semantics: does each color mean brand, action, state, or hierarchy? If not, remove or quiet it. In tokenized or Material You-compatible apps, component CSS must use theme tokens and semantic token mixes; hardcoded colors and static accent tokens break the app's color contract unless that exact semantic accent is intentionally required.
- Contrast: can the text and state be read under dark mode, dim surfaces, hover, focus, disabled, and selected states?
- Density: are chips, pips, pills, buttons, rows, and cards sized according to their role, or are tiny things wearing big-card styles?
- Token fit: is the element using existing product tokens, or inventing one-off values that break the system?
- Scrollbars and overflow: if a panel scrolls, is the scrollbar styled to belong to the material system, or did a raw browser scrollbar break the illusion?
- Responsive width: does the component survive the real container width, not just the screenshot width?

A style audit is not optional polish. It is correctness work. If you add a class, ask what else already uses that name. If you add color, ask what state it communicates. If you add width or padding, ask what happens at the smallest and largest real containers.

## Product Grammar Before Novelty

Before styling, classify the surface. A screen must obey the grammar of what it is.

Possible surfaces:

- App shell
- Feed
- Dashboard
- Editor
- Landing page
- Settings
- Admin console
- Data table
- Command center
- Prototype poster

Do not design an app shell like a landing page. Do not design a dashboard like a poster. Do not design a feed like a pile of decorative cards.

### Social feed grammar

A social feed usually needs:

- A clear feed rail
- Composer near the top
- Posts that behave like posts
- Familiar actions such as Post, Reply, Repost, Like, Share
- Secondary metadata
- Attachments that have a reason to exist
- Predictable scan rhythm

### Systems dashboard grammar

A systems dashboard usually needs:

- Health
- Latency
- Errors
- Incidents
- Throughput
- Regions
- Saturation
- Services
- Severity hierarchy
- Compact readouts
- Credible charts with units and state

### Hybrid product grammar

When combining two archetypes, one owns the center and the other supports it.

For a social plus operations product, a strong default is:

- Center: feed or primary work surface
- Left: quiet navigation
- Right: sticky telemetry or context rail
- Top: search, current scope, global status
- Alerts: rare, distinct, and semantically colored

Do not flatten multiple archetypes into equal decorative panels.

## Avoid Derivative Literalism

Respect product grammar without copying a famous product too literally.

Bad:

- Making an X-like feed that visually reads exactly like X
- Making a dashboard that looks like generic dark SaaS
- Copying Material You shapes without adopting the material logic
- Copying Linear restraint until the result has no ownable silhouette

Better:

- Keep familiar interaction models, but invent a shape, surface, and motion language
- Use literal controls, but let the product have a distinct material world
- Keep the primary workflow recognizable, but avoid copying another product's exact silhouette

A credible product can be familiar. A memorable product needs its own grammar.

## Tonal Segmentation Before Borders

Do not use borders as the default separator.

A border is a design muscle. If every element has a border, you lose the ability to use lines for precision, focus, or emphasis. In app and admin surfaces, start from a default border count of zero. Build hierarchy with tonal shifts, spacing, alignment, and shape first. Add a line only when it does a job those primitives cannot do.

Selection does not automatically justify a border. Prefer active background, tonal contrast, position, semantic icon, or compact state marker for selection. Use a border or ring for selection only when the selected object needs precision that tonal contrast cannot provide.

Prefer segmentation through:

- Tonal surface color
- Spatial grouping
- Shape contrast
- Size contrast
- Background planes
- Sticky regions
- Soft elevation
- Alignment
- Hairlines only when needed

Use borders and rings for:

- Focus states
- Text inputs
- High-precision data tables
- Critical separation
- Selected inspection states
- Accessibility needs

If a section can be separated by color, spacing, or shape, try that before adding a line.

## Container Discipline

A container is not decoration. A container claims meaning.

Use a card, panel, tinted block, or shadow only when it communicates:

- Ownership
- Grouping
- State
- Interaction
- Elevation
- Isolation
- A change in mode

Avoid box addiction:

- Do not wrap every element in a bordered card
- Do not create card inside card inside card unless the hierarchy is necessary
- Keep nested surface depth to two levels by default: parent surface plus child row/card. A third tonal depth must prove it carries a real mode, ownership boundary, or interaction state.
- Do not use containers to compensate for weak layout
- Do not make every row feel equally elevated

A strong interface often uses fewer boxes and stronger planes.

## Shape as Personality

Personality does not require loud color or heavy gradients. Shape can carry identity.

Define shape roles:

- Brand mark
- Primary action
- Navigation item
- Feed unit
- Attachment
- Metric tile
- Alert
- Chip
- Input
- Floating panel

Do not make every shape the same radius. Do not make every radius random either. Build a shape system.

Useful shape moves:

- Large soft slabs for primary surfaces
- Pills for actions and status
- Squircles for app controls
- Compact rounded tiles for metrics
- Soft grouped surfaces for contextual panels
- Slight radius changes on hover when the object feels active

Shape should make the UI ownable without making it cartoonish.

## Material Fit: Edges Should Explain Relationships

Material You / M3 Expressive is not just large rounded blobs. Shape communicates how surfaces relate.

When controls sit beside a row, sheet, or list item, decide whether they are:

- **Inside the surface**: controls share the parent container and inherit its padding rhythm.
- **Beside the surface**: controls live in a separate column, visually apart from the row slab, with explicit air between row and action column.
- **Molded to the surface**: adjacent edges get smaller radii so pieces feel like they slot together while still remaining separate tappable targets.

If a row and its action stack are meant to slot together, encode the relationship in corners:

- Main row edge facing the actions: lesser radius.
- Top action: lesser radius on the side facing the row and on the edge facing the next action.
- Bottom action: lesser radius on the side facing the row and on the edge facing the previous action.
- Outer free corners keep the larger product radius.

Do not add a visible wrapper just to make stacked actions feel grouped. Prefer two tonal action slabs with a small consistent gap, especially when the reference image implies the buttons are beside the row rather than inside it.

## Spacing Must Be Verified, Not Eyeballed

Spacing bugs are product-quality bugs. If Ben challenges spacing, stop guessing and measure the boxes.

Before claiming spacing is fixed, capture or compute:

- Left container inset.
- Right visible inset after scrollbar gutter.
- Row-to-action-column gap.
- Gap between stacked action buttons.
- Vertical row rhythm.
- Action column width and button heights.
- Fade/overflow boundary relative to the first visible item.

Then make the numbers agree with the intended optical rhythm. Do not report "looks consistent" unless you have measured the relevant box model.

For scrollable tonal containers:

- The scroll content should pass under the header only when the material form implies it.
- Overflow should stop at the actual rounded/tone boundary, not an arbitrary inner clipping line.
- Use a container-colored fade when a hard cut would look amateurish.
- Keep the fade band out of the first row's readable content; add clearance above the first item if needed, then re-check that the header has not become loose.
- Reserve scrollbar gutter without over-padding the action side; perceived left/right balance matters more than raw CSS symmetry.

## Color Discipline

Color should usually mean state, action, or brand. It should not be decoration by default.

Use a small system:

- Base surfaces: quiet neutrals or tonal darks
- Text: high legibility with warm contrast
- Brand accent: one main accent
- Healthy: green or equivalent success color
- Warning: amber or equivalent caution color
- Critical: red or equivalent danger color

Rules:

- No rainbow chart lines unless comparing multiple labeled series
- No gradient panels by default
- Gradients are rare and must have a job
- If WARNING gets a color, the whole design should not also be covered in unrelated warm gradients
- If a color appears, ask what state, action, or identity it communicates
- Keep repeated actions chromatically stable across row states. An `Open` action should not change color just because the row is running, warning, or errored; state belongs in the status text/dot/metric accent unless the action itself changes consequence.
- Do not tint an entire row/container by status unless the state is severe enough to own that much surface area. Prefer a small semantic marker, status subtitle, activity line, or metric accent. A full-row warning/error fill is high-budget and should be rare.
- Hover states should reinforce the existing light/dark material relationship. For icon-only action slabs, a good M3 move is inversion: light-on-dark becomes dark-on-light, dark-on-light becomes light-on-dark. Do not introduce a new hue on hover unless the action consequence changes.
- In Material You/token-driven products, never hardcode component-local colors (`oklch`, hex, raw rgba) or lean on a static accent like pink for generic UI; use `primary`, `tertiary`, surface, outline, and on-* tokens so the component follows the active theme
- The layout should still work in grayscale

## Gradients Are Expensive

Gradients are high-budget. Use them rarely.

Good uses:

- A brand mark
- One premium hero moment on a marketing surface
- A subtle chart area fill
- A selected state if it is the product signature
- A rare status surface where continuous scale matters

Bad uses:

- Every button
- Every card
- Background plus cards plus charts plus CTAs
- Warning treatment on entire posts without a clear state reason
- Gradient as a shortcut for visual interest

If a gradient is not adding information, remove it.

## Chart and Sparkline Discipline

Charts are instruments, not stickers.

Rules:

- Use fixed SVG geometry
- Use `vector-effect: non-scaling-stroke` for SVG chart strokes
- Keep stroke width stable
- Use one semantic color per series unless comparing labeled series
- Add a subtle area fill when it helps users read min, max, and direction
- Avoid glowing area fills unless volume or intensity is the point
- Do not stretch charts until the line feels distorted
- Put charts where measurement belongs, not as random decoration
- Label units and state when the chart is part of a dashboard

A credible sparkline should feel like a small measurement device.

## UI Copy Austerity

Functional UI should show, not explain. A product UI is not a brochure, and an admin tool is not a landing page. If the user already understands the object, stop announcing the object. Label only what changes comprehension, decision-making, or action.

Copy earns its pixels by doing one of four jobs:

- Orient: `Identity`
- Clarify state: `Your current access`
- Explain consequence: `Stale profiles may reflect old provider data`
- Enable action: `Search name, handle, or actor ID`

If a label only names obvious interface furniture, delete it. The page title owns the object. Do not keep re-naming the same object in section headers unless the section introduces a new state, risk, mode, or action. `Identity Register`, `Selected Identity`, `6 visible` as a heading, `List of identities`, `User details`, `Main dashboard`, and `Filter controls` usually describe the UI structure instead of helping the user. Let layout, proximity, and content make those relationships obvious.

Counts are metadata unless the count is the primary insight. `6 visible` should usually be a quiet toolbar note or filter result, not the hierarchy anchor of a list.

Use the calculator test: if the label feels like writing `press the equals sign to evaluate the expression` on a calculator, delete it.

Prefer literal terms:

- Post
- Reply
- Repost
- Like
- Share
- Trace
- Resolve
- Mute
- Settings
- Latency
- Errors
- Incidents
- Deploys
- CPU
- Memory
- Region
- Healthy
- Degraded
- Watch

Avoid performative labels in functional UI:

- Cute names for ordinary metrics
- Jokes in buttons
- Marketing claims inside dashboards
- Long explanatory labels for obvious controls
- Product narration where the interface should simply show state
- Object-restating section headers where the page title already establishes the object

Personality belongs in rare places:

- Empty states
- Onboarding
- Marketing surfaces
- Help panels
- Assistant responses
- Tiny product easter eggs

It does not belong in every button, metric, card heading, or table label.

### Do Not Build Hero Hierarchy Inside Tools

A tool page should not use landing-page hierarchy unless the user is being sold, onboarded, or taught a novel concept. Avoid the pattern of tiny category label, huge poetic headline, and small explainer paragraph on ordinary admin surfaces. It makes the page feel like marketing and pushes useful controls away from the user's hands.

Bad:

```text
IDENTITY OBSERVABILITY
Who Aria recognizes, and why
Inspect actor profiles, profile freshness, and tier facts.
```

Better:

```text
[identity icon] Identity
Inspect actor profiles, freshness, and tier facts.
```

Rule: the title names the thing. The hint explains what is not obvious. Do not add a second headline just because the layout feels empty. For normal app tools, the default header pattern is semantic icon plus noun plus one compact hint. If the proposed title sounds like a thesis statement, it is probably marketing hierarchy leaking into a tool.

Do not default to `eyebrow → newline → bigger headline` for ordinary app controls. That pattern is expensive hierarchy. Use it only when the eyebrow and headline carry different necessary information. In small control panels, one literal noun often beats two stacked labels: `Local sessions`, not `LOCAL ARIA` plus `Runs on this machine`.

### Avoid Duplicate Status Claims

If the same fact appears twice, the UI tells the user it matters twice. That creates false hierarchy. Do not show `Viewer access: T4 Platform` in one badge and `Your current access: T4 Platform` in a nearby card. Do not show `4 pending` in a summary chip and then `Pending — 4` immediately below unless the two counts mean different things. Pick one owner.

If the fact gates the page, place it near the title as compact context. If the fact organizes a list, put it in that section header. If the fact needs explanation, give it one dedicated panel. Do not repeat it as both decoration and content.

### Do Not Expose Implementation Plumbing

User-facing copy should describe the concrete user outcome, not the internal system route that produces it.

If the copy mentions gateways, side effects, worker ownership, tracked records, internal service names, orchestration, queues, IDs, schemas, or other builder-only mechanics, stop and rewrite it from the user's point of view.

Ask:

- What does the user get?
- What can the user do next?
- What input is required?
- What state changed in the product?

Bad:

- “1 startable workflow”
- “Side effects stay gateway-owned”
- “Operational workflow”
- “Gateway action”
- “Aria Chat sends it to the gateway, which creates the tracked invite and onboarding thread.”
- “This moves the request through the workflow service.”

Why bad:

- The count is obvious.
- The implementation boundary is not the user’s concern.
- The copy reassures builders instead of helping users.
- It explains plumbing when the UI should show the outcome.

Good:

- “Invite Interns”
- “Team setup”
- “Emails, products, supervisor”
- “Create invite”
- “Enter the cohort details. You get an invite link and an onboarding thread for next steps.”
- “Create cohort invites and onboarding threads.”

Rule of thumb: if the phrase is useful mainly to someone reviewing the architecture, it does not belong in the product UI. Move that reassurance to code review notes, PR descriptions, or developer docs.

## Icons and Controls

Small controls should often use icons, or icon plus word, not text-only labels. Icons are a semantic channel, not decoration. Underusing them can flatten the interface into text-only parsing just as badly as overusing them can turn icons into wallpaper.

Use icons where they reduce parsing cost:

- Page object: identity, settings, meetings, workflows
- Entity kind: person, group, bot, service
- State: fresh, stale, unresolved, healthy, degraded
- Tier or severity: T1 through T4, low through critical
- Inspector facts: actor ID, kind, observed, resolved
- Metrics: CPU, memory, process count, total count, platform access, needs review

Before styling an inspection-heavy page, define the icon vocabulary for repeated categories. Icons should be quiet, consistent scan anchors, not one-off decoration sprinkled onto headings after the fact.

The symmetry matters: overusing icons wastes the channel, but refusing to use icons wastes a degree of freedom.

Good:

- Composer tools: icon plus label, or icon-only with accessible label
- Navigation: icon plus label
- Compact row actions: icon-only with visible affordance and accessible label
- Status chips: short word plus color, dot, or quiet icon
- Detail panels: small semantic icons beside repeated facts, especially IDs, timestamps, kinds, and status

Bad:

- Text-only utility buttons when the control is spatial and repeated
- Long action phrases inside compact UI
- All-primary buttons
- Buttons that promise huge magic actions when the product cannot support them
- Text-only filters for semantic categories that already have strong icon vocabulary
- Decorative one-off icons that do not repeat consistently for the same meaning
- Icons added to one-off row actions just to make the row feel designed

Buttons should be small composable units of action. Match the product's existing button grammar before inventing a new silhouette. This is especially true in app-shell rails and nav clusters: a new rail control should look like it belongs to the existing rail button family before it advertises its special state. A row action like `Spin up` is usually a compact secondary pill, not a fat blob, unless it is the primary action of the entire surface. Icons should repeat consistently enough that the user learns the grammar.

## Event Feedback Causality

Events should be colocated with the thing that caused them. If a row, message,
tool call, field, button, or panel triggers feedback, put the feedback on that
object or in its immediate region. This matters most for transient feedback:
short-lived state shown far away forces the user to mentally connect cause and
effect across the screen.

Use global strips, rails, banners, or footers only for genuinely global or
ambient state: connectivity, active mode, account/session health, sync state,
quota, or app-wide outages. Do not put a one-off consequence from a specific
object in an ambient status surface just because that surface already exists.

Bad:

- A tool call is blocked in the transcript, but the notice appears under the
  composer.
- A row action fails, but the error appears in a distant sidebar.
- A field validation error appears as a global toast while the field stays
  visually unchanged.

Better:

- Blocked tool feedback appears in the turn/trace where the tool was attempted.
- Row-action errors attach to that row or action cluster.
- Field errors sit under or beside the field that needs correction.

Rule: transient feedback answers "what just happened here?" The answer belongs
where "here" is.

## Motion Causality

Delight should come from material behavior, not random animation.

Objects should come from somewhere and return somewhere. Nothing should appear or disappear in a way that feels physically unrelated to the interface.

Good motion:

- Panels unfurl from their trigger or region
- Tabs slide or reshape from the selected control
- Metric changes pulse from the number itself
- Menu surfaces expand from the clicked object
- Cards collapse back into their source
- Hover states softly reshape, lift, or tonal-shift only when the object is semantically interactive/elevated
- Charts update smoothly without screaming for attention

Bad motion:

- Decorative spinning objects
- Ambient blobs with no meaning
- Constant glow movement
- Things popping in from nowhere
- Animation that competes with reading
- Row hover lift when the row is not a button/card. A selectable row may get cursor + tonal change; translateY/elevation is a separate degree of freedom and must earn its semantics.

If motion does not communicate state, origin, continuity, or action, remove it.

## Live Mock Rule

Frontend prototypes should feel alive when the concept implies live data or interaction.

Add lightweight interactivity when useful:

- Tabs filter content
- Navigation selected state changes
- Buttons toggle local state
- Counts update visibly
- Metrics evolve subtly
- Charts update over time
- Panels open, close, or unfurl
- Rows and tiles have meaningful hover states

Do not fake a backend when a local state demo is enough. But avoid static screenshots when the product is supposed to be interactive.

## Typography Discipline

Typography should create hierarchy before color does.

Rules:

- App UI usually needs one serious sans and one mono for telemetry
- Use mono for code, IDs, fixed-width numeric readouts, and telemetry; do not use it for ordinary labels, section headers, row metadata, or action copy unless alignment/measurement is the actual reason
- Use tabular numerals for metrics
- Keep headings proportional to the surface
- Avoid giant marketing headlines inside app shells
- Use weight, spacing, and alignment before decorative type
- Use ornate display type only when the product surface justifies it

Row typography must follow decision hierarchy. The object identity usually comes first and should read strongest: thread title, service name, actor, file, incident. The changing content comes second: message preview, latest activity, status detail. Metadata comes third: counts, timestamps, IDs, telemetry. Do not let previews, badges, or metadata visually outrank the row's title unless the user's decision genuinely starts with that field. Normalize machine/event labels into user-facing state language before rendering: `Idle`, `Running command`, or `Last ran: bash` beats raw lowercase fragments like `idle` or `completed: bash` when the UI is a control panel rather than a log stream.

## Density Discipline

Dense does not mean loud.

Good density:

- Compact rows
- Aligned numbers
- Consistent units
- Grouped metrics
- Clear labels
- Small multiples with shared rules
- A two-second scan path

Bad density:

- Every panel has a big heading
- Every metric has an icon
- Every card has a chart
- Every section gets its own visual universe
- Every number has a sentence explaining it

Users should know what changed without reading the entire screen. Dense rows still need internal hierarchy: title strongest, preview/activity secondary, metadata quietest. If two adjacent text lines have nearly identical size, weight, and contrast but different jobs, the hierarchy is not designed yet. Telemetry is the exception where compact mono values and small repeated metric icons can help scan; ordinary labels and action rows should not inherit that treatment.

## The Frontend by Fractal Process

### Step 1: Classify the surface

State the surface type before designing:

- App shell
- Feed
- Dashboard
- Editor
- Landing page
- Settings
- Admin console
- Data table
- Command center
- Prototype poster

### Step 2: Name the primary interaction

Examples:

- Read and post
- Triage incidents
- Compare metrics
- Edit a record
- Configure settings
- Search and filter

The primary interaction owns the center.

### Step 3: Assign layout hierarchy

Define:

- Primary region
- Secondary support region
- Navigation region
- Context region
- Rare alert region

If two regions compete for primary attention, redesign.

### Step 4: Write the budget ledger

Before building, state:

- High-budget elements
- Medium-budget elements
- Low-budget elements
- One visual flourish, if any
- What must stay quiet
- Which design muscles are intentionally not being used

### Step 5: Write the style mechanics ledger

Before building or modifying CSS, state:

- Component scope: which component owns these classes
- Existing selectors checked: grep for every new class and generic selector
- Class names rejected: names avoided because they collide or are too broad
- Font plan: body font, mono use, icon font use, and where each is forbidden
- Width and density plan: expected min, max, padding, radius, row rhythm, action gaps, scrollbar gutter, and overflow behavior
- Edge relationship plan: whether actions live inside, beside, or molded to the row/surface, and which corners intentionally use lesser radii
- Measurement plan: which box-model values must be checked before telling Ben a spacing/radius issue is fixed
- Color plan: exact semantic role of every accent, state, and muted color
- Interaction states: hover, focus, selected, disabled, loading, and error
- Responsive breakpoints or container widths that must be checked

If you cannot write this ledger, you do not understand the UI well enough to touch it.

### Step 6: Build grayscale hierarchy

Before relying on color, the layout must show:

- Where to look first
- What is interactive
- What is feed, nav, telemetry, or alert
- What is important and what is passive context

If color is required to understand the layout, the layout is weak.

### Step 7: Add semantic color and tonal surfaces

Add color after hierarchy works. Prefer tonal segmentation before borders.

Ask for each color:

- Is this state?
- Is this brand?
- Is this action?
- Is this decoration?

Decoration needs a strong reason.

### Step 8: Strip UI copy

Replace performative UI copy with literal terms.

Ask:

- Would a real user understand this instantly?
- Is this a control label or marketing copy?
- Does this explain something the UI should already show?
- Is the joke making the product feel fake?

### Step 9: Add live behavior

When the concept implies interactivity, add local prototype behavior:

- Tabs
- Toggles
- Hover states
- Live metric drift
- Animated chart updates
- Small state transitions

### Step 10: Verify at real widths

Check at least:

- 1440px
- 1728px or wider
- A narrow mobile width if responsive behavior is in scope

Do not design only for the screenshot viewport.

## Review Checklist

Before showing Ben a frontend, answer these:

- Does the screen have one obvious primary region?
- Does it respect the product archetype?
- Is it familiar without being derivative?
- Are secondary regions quieter than the center?
- Did every container earn its surface treatment?
- Are colors semantic, or are they just vibes?
- Are borders rare enough to still mean something?
- Are gradients rare enough to still feel special?
- Are charts credible instruments?
- Is UI copy literal and useful?
- Does shape carry personality without making the UI childish?
- Does motion have origin and destination?
- Does the prototype respond to clicks when the product concept implies it should?
- Does it look intentional at widescreen?
- Did you grep for every new class name and selector that could collide globally?
- Did you inspect computed or source styles for color, width, font, padding, radius, overflow, and display?
- If Ben asked about spacing, did you measure the actual row/action/scrollbar/fade boxes before replying?
- Do adjacent controls live in the right place — inside the row, beside it, or molded to it — instead of accidentally looking embedded?
- Are scrollbar gutters and fade bands accounted for in perceived spacing?
- Are tiny elements protected from broad card, result, pill, button, or utility classes?
- Are text spans protected from icon-font utility classes such as `.ms`?
- Does each accent color have a semantic job?
- Does the component still work when labels, paths, counts, and durations get longer?
- Did visual confirmation verify the actual state you changed, not a nearby happy-path screen?
- Does it feel expensive because it is controlled, not because it is loud?

## Examples

### Example 1: Overdesigned social dashboard

Bad:

- Large marketing hero inside an app shell
- Neon command center theme
- Every module in a glowing card
- Clever labels everywhere
- Decorative sparklines inside posts
- Gradients on buttons, background, charts, and panels

Better:

- Central feed rail owns the screen
- Quiet left nav
- Sticky telemetry rail
- Literal labels
- Tonal surfaces instead of border-heavy cards
- One accent color plus semantic status colors
- Telemetry attachments only where relevant

### Example 2: Too derivative feed

Bad:

- Exact X-like visual structure
- Standard dark SaaS right rail
- Generic bordered cards
- Familiar but not ownable

Better:

- Keep feed grammar, but change the material language
- Use soft slabs, pills, and tonal fields
- Make telemetry attachments feel native to this product
- Add local state and live metrics
- Avoid copying another product's exact silhouette

### Example 3: Border overuse

Bad:

- Every tile has a one-pixel border
- Every panel has a ring
- Every row is boxed
- The whole screen becomes a wireframe with colors

Better:

- Use background tone to segment groups
- Use spacing and shape for grouping
- Reserve borders for focus, inputs, and precision states
- Let color fields carry hierarchy

### Example 4: Static prototype for live product

Bad:

- Metrics never change
- Tabs do nothing
- Buttons do nothing
- Charts are decorative

Better:

- Metrics drift subtly
- Tabs filter content
- Reactions toggle
- Composer tools select
- Charts update while keeping stable scale
- Motion is subtle and tied to state

## Troubleshooting

### A tiny element suddenly looks like a giant blob

Cause: a generic class name is being hit by unrelated global CSS.

Fix:

1. Inspect the element class list.
2. Grep every class selector that could match it.
3. Rename component-local classes to honest scoped names.
4. Avoid generic names like `result`, `card`, `item`, `active`, `error`, `p`, and `ms` unless they are intentionally global.
5. Add a mock or fixture that exercises the tiny element in the real component.

### Text renders in a bizarre font

Cause: the text is inheriting an icon font, mono utility, display font, or button default.

Fix:

1. Check the class name against global font utilities.
2. Rename misleading classes such as `.ms` when the element is not a Material Symbol.
3. Set an explicit font family only where the component owns the typography.
4. Verify numeric text uses tabular numerals without invoking an icon font.

### It looks gaudy

Remove in this order:

1. Gradients
2. Glow
3. Oversized headings
4. Extra containers
5. Decorative icons
6. Clever labels
7. Unnecessary charts
8. Repeated borders

Then rebuild hierarchy in grayscale.

### It looks bland

Do not add effects everywhere. Improve:

- Shape system
- Tonal segmentation
- Spacing rhythm
- Type scale
- One focal action
- One signature interaction
- Product-specific data shapes

### It looks too derivative

Keep the product grammar, change the material language.

Adjust:

- Shape roles
- Surface tones
- Attachment patterns
- Motion behavior
- Information grouping
- Component silhouettes

Do not solve derivativeness by adding random decoration.

### It looks like a landing page, but it should be an app

Delete the hero. Restore product grammar. Put the primary interaction in the center.

### The UI copy sounds fake

Replace voice with function. Use literal product terms. Save personality for empty states, onboarding, help, and marketing surfaces.

### The interface lacks delight

Do not add noise. Add one or two of:

- Smooth selected state movement
- Soft hover reshaping
- Local state changes
- Live metric updates
- A thoughtful empty state
- A signature control shape
- A subtle unfurl transition from the triggering element
