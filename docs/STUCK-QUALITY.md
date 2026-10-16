# I’m stuck: real-model quality gate

Three development iterations on ten synthetic tasks. Each uses Apple’s installed system model, guided generation and greedy sampling. No screen content, network, or model download. These examples informed the prompt; they are not held-out evaluation.

**Result: usable with a documented quality gap, not a perfect pass.** The final run gives concrete actions for most tasks and fixes malformed calculus and invented surfaces. It still misdescribes Q/K in one chemistry alternative and leaks a recycling action into Spanish. The shipping filter rejects options with no subject overlap (including that Spanish option), caps and deduplicates suggestions; it cannot verify scientific correctness. Suggestions are optional and never change the goal without a click.

The requested best honest version ships with this limitation. Do not describe these results as proven coaching accuracy. Prompt is in `core/prompts/stuck_v1.txt`.


# Iteration 1 — raw output

Real Apple system model, synthetic task/context only. Prompt: `core/prompts/stuck_v1.txt`. Raw guided-generation strings below; no screen data. These ten examples are a development quality check, not an accuracy measurement.

## Essay on Hamlet

Context: Argue whether Hamlet delays through doubt; use the To be or not to be speech.

```json
[
  "Write one claim about Hamlet's doubt and delay.",
  "Choose two lines from the soliloquy supporting the claim.",
  "Draft a three-sentence paragraph explaining one chosen line."
]
```

## Study chemistry

Context: Equilibrium constants; distinguish Q from K and predict reaction shifts.

```json
[
  "Write how Q differs from K in one sentence.",
  "Predict the shift when Q is greater than K.",
  "Set up one equilibrium-constant expression without solving it."
]
```

## Fix duplicate rows

Context: SwiftUI list duplicates after refresh; requests may complete out of order.

```json
[
  "Reproduce duplicate rows with two quick refreshes.",
  "Trace where refreshed rows are appended to the list.",
  "Write a test completing two refresh requests in reverse order."
]
```

## Read biology chapter

Context: Photosynthesis: compare the light-dependent reactions and Calvin cycle.

```json
[
  "Read the first paragraph and note its main idea.",
  "Identify the key difference between the two cycles.",
  "Write one step common to both processes."
]
```

## Calc homework

Context: Use integration by parts to integrate x times e to the x.

```json
[
  "Write u times e to the u plus c.",
  "Choose u = u and dv = e to the u du.",
  "Write v = v and du = du."
]
```

## History essay

Context: Compare two primary-source accounts of the Boston Tea Party.

```json
[
  "Identify two primary-source accounts.",
  "List key differences between the sources.",
  "Select one source excerpt to analyze."
]
```

## Design settings

Context: A Mac focus app needs a clear grouped settings form for nudge intensity.

```json
[
  "Sketch a layout with intensity options.",
  "List required fields for intensity.",
  "Draft a sentence on intensity grouping."
]
```

## Practice Spanish

Context: Choose preterite versus imperfect when describing yesterday's trip.

```json
[
  "Write the imperfect form of 'viajar'.",
  "List verbs using 'viajar' in imperfect tense.",
  "Identify preterite verbs in a sample sentence."
]
```

## Recycling presentation

Context: Explain how contamination affects the school's paper recycling.

```json
[
  "List contamination types affecting paper.",
  "Identify school paper sources.",
  "Write one impact sentence on contamination."
]
```

## Friction lab report

Context: Compare measured friction for a wooden block on three synthetic surfaces.

```json
[
  "Record friction for the rubber surface.",
  "List surface order for the test.",
  "Note the block's weight before testing."
]
```


# Iteration 2 — raw output

Real Apple system model, synthetic task/context only. Prompt: `core/prompts/stuck_v1.txt`. Raw guided-generation strings below; no screen data. These ten examples are a development quality check, not an accuracy measurement.

## Essay on Hamlet

Context: Argue whether Hamlet delays through doubt; use the To be or not to be speech.

```json
[
  "Write one claim about Hamlet's doubt and delay.",
  "Choose two lines from the soliloquy supporting the claim.",
  "Draft a three-sentence paragraph explaining one chosen line."
]
```

## Study chemistry

Context: Equilibrium constants; distinguish Q from K and predict reaction shifts.

```json
[
  "Write how Q differs from K in one sentence.",
  "Predict the shift when Q is greater than K.",
  "Set up one equilibrium-constant expression without solving it."
]
```

## Fix duplicate rows

Context: SwiftUI list duplicates after refresh; requests may complete out of order.

```json
[
  "Refresh the list and note duplicate rows appear.",
  "Refresh the list and note duplicate rows persist.",
  "Refresh the list and note duplicate rows disappear."
]
```

## Read biology chapter

Context: Photosynthesis: compare the light-dependent reactions and Calvin cycle.

```json
[
  "List the inputs of the light-dependent reactions.",
  "List the outputs of the Calvin cycle.",
  "Draw an arrow linking the two stages with their shared molecules."
]
```

## Calc homework

Context: Use integration by parts to integrate x times e to the x.

```json
[
  "Choose u and dv for the integral of x times e to the x.",
  "Differentiate your chosen u and integrate your chosen dv.",
  "Substitute your choices into the integration by parts rule."
]
```

## History essay

Context: Compare two primary-source accounts of the Boston Tea Party.

```json
[
  "Write one claim from each primary-source account.",
  "List the authors of each primary-source account.",
  "Note the publication dates of each account."
]
```

## Design settings

Context: A Mac focus app needs a clear grouped settings form for nudge intensity.

```json
[
  "Sketch the nudge intensity slider layout.",
  "Draft a sentence for the intensity label.",
  "Outline the grouped settings section structure."
]
```

## Practice Spanish

Context: Choose preterite versus imperfect when describing yesterday's trip.

```json
[
  "Write one Spanish sentence about a completed event on yesterday's trip.",
  "Write one Spanish sentence describing the trip's background.",
  "Underline the verbs and note tense choices."
]
```

## Recycling presentation

Context: Explain how contamination affects the school's paper recycling.

```json
[
  "Identify the contaminated paper samples in the folder.",
  "List the contamination types observed in the samples.",
  "Write one effect of contamination on recycling efficiency."
]
```

## Friction lab report

Context: Compare measured friction for a wooden block on three synthetic surfaces.

```json
[
  "List the friction measurements for each surface.",
  "Label each measurement with its surface.",
  "Write which surface had the highest friction."
]
```


# Iteration 3 — raw output

Real Apple system model, synthetic task/context only. Prompt: `core/prompts/stuck_v1.txt`. Raw guided-generation strings below; no screen data. These ten examples are a development quality check, not an accuracy measurement.

## Essay on Hamlet

Context: Argue whether Hamlet delays through doubt; use the To be or not to be speech.

```json
[
  "Write one claim linking doubt to delay.",
  "Choose two lines from the soliloquy supporting your claim.",
  "Draft a three-sentence paragraph explaining one chosen line."
]
```

## Study chemistry

Context: Equilibrium constants; distinguish Q from K and predict reaction shifts.

```json
[
  "Write how Q differs from K in one sentence.",
  "List the two equilibrium constants to compare.",
  "Predict the shift when Q is greater than K."
]
```

## Fix duplicate rows

Context: SwiftUI list duplicates after refresh; requests may complete out of order.

```json
[
  "Trigger two rapid refreshes and write what duplicates.",
  "Find the code that appends refreshed rows.",
  "Sketch a test where the older request finishes last."
]
```

## Read biology chapter

Context: Photosynthesis: compare the light-dependent reactions and Calvin cycle.

```json
[
  "List the inputs of the light-dependent reactions.",
  "List the outputs of the Calvin cycle.",
  "Draw an arrow linking the two stages with their shared molecules."
]
```

## Calc homework

Context: Use integration by parts to integrate x times e to the x.

```json
[
  "Choose u and dv for the integral of x times e to the x.",
  "Differentiate your chosen u and integrate your chosen dv.",
  "Substitute your choices into the integration by parts rule."
]
```

## History essay

Context: Compare two primary-source accounts of the Boston Tea Party.

```json
[
  "Write one claim from each primary-source account.",
  "List the authors of each Boston Tea Party account.",
  "Note the publication dates of the two accounts."
]
```

## Design settings

Context: A Mac focus app needs a clear grouped settings form for nudge intensity.

```json
[
  "List intensity levels in the grouped settings form.",
  "Write one intensity description for each level.",
  "Sketch a layout showing grouped intensity sections."
]
```

## Practice Spanish

Context: Choose preterite versus imperfect when describing yesterday's trip.

```json
[
  "Write one Spanish sentence about a completed event on yesterday's trip.",
  "Write one Spanish sentence describing the trip's background.",
  "Write one question to ask the school about its recycling rules."
]
```

## Recycling presentation

Context: Explain how contamination affects the school's paper recycling.

```json
[
  "Write one example of contamination in school paper recycling.",
  "Draft a slide explaining why contaminated paper is harder to recycle.",
  "Write one question to ask the school about its recycling rules."
]
```

## Friction lab report

Context: Compare measured friction for a wooden block on three synthetic surfaces.

```json
[
  "List the three measured friction values.",
  "Label each value with its surface.",
  "Write which surface had the highest friction."
]
```
