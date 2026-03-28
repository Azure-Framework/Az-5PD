# Az-5PD — Expanded Weekly Change Log

_Date range covered: recent week of chat work (conversation-based recap)._

## Main themes this week
- Traffic stop reliability
- Better suspect behavior and release behavior
- Better callout realism
- Better spawn placement
- Tighter integration with Az-MDT
- Cleaner config expectations

## Traffic stop workflow changes
The traffic stop flow was iterated on multiple times.

### Stop activation / interaction flow
- Added or refined:
  - `SHIFT + E` to mark a vehicle
  - activate police lights as part of the stop workflow
  - `G` cancels the stop

### Pullover driving behavior
The user wanted stopped vehicles to:
- move **farther to the right**
- slow down more naturally
- **not slam on brakes**
- choose better roadside stopping behavior

This was an explicit quality issue for making traffic stops feel believable.

## Stop-state bugs reported and worked on
A big part of the week was repeated iteration on these exact problems:

- On **finish pull over**, when the officer got back in their own vehicle, the AI ped was being **forced out** of their car instead of simply driving away.
- Suspects were still getting out of the car during **question / interaction** flow when they should stay put.
- In some cases the suspect fled before the officer had finished checking ID or documents.
- Vehicle release behavior was inconsistent; the stop sometimes did not end cleanly.
- Sometimes the stopped vehicle kept rolling or the scene felt physically unstable.
- When returning to the patrol car, the suspect sometimes did not leave correctly at all.

The recurring goal was:
- keep suspect in vehicle during questions
- do not let flee logic fire early
- when the stop is properly ended, let the suspect drive off naturally

## Stop UI / prompt changes
- User asked to add back **Draw3DText** above the ped’s head.
- User did **not** want AlertDialog used for that interaction.
- Registration / insurance display in the MDT was expected to remain visible during stop workflows.

## Arrest / suspect state fixes
- Fixed cuff / uncuff toggle issues.
- Cleared arrest animation and duplicate state keys.
- Added a short uncuff cooldown.
- Fleeing suspects were adjusted so they properly stop, exit, and then run when the logic actually intends a flee event.

## Code 5 / felony stop expectations
The broader Az-5PD work also included requested felony stop improvements:
- With gun drawn + holding left shift, driver should exit with hands up
- Same behavior for passenger
- For foot chase, holding left shift for a few seconds should force surrender
- Surrender behavior should include hands up / kneeling style compliance

## Ped handling / custody workflow
The user also wanted stronger prisoner / subject handling:
- improved ped drag
- left/right seat placement via ox_target
- avoid bad cuff state after ejection from a vehicle
- fix drag orientation because dragged peds were sometimes sideways

## Az-MDT integration work
Az-5PD was not being treated as isolated from MDT.

### Data expected to appear in MDT from 5PD encounters
- vehicle registration
- DOB
- insurance
- sometimes prior tickets or behavior history

### Sim / Scene Tools
- Sim / Scene Tools logic was surfaced inside Az-MDT while 5PD continued to own gameplay state.

### Sync expectations
The larger integration requirement was that 5PD call state should propagate correctly to MDT:
- accepted
- denied
- en route
- on scene

User specifically called out that acceptance / deny / scene state had problems.

## Callout quality and realism
This was another major area.

### Spawn / placement problems reported
The user explicitly reported that callout actors or support units sometimes:
- spawned in the ground
- spawned in weird or bad spots
- stood around doing nothing
- felt like static NPCs instead of active scenes

### Requested direction
The user wanted:
- a lot more callouts
- more varied crimes
- more active RP behavior
- scenes where NPCs are actually doing something wrong, not just standing there

## EMS / Tow / Coroner related improvements
The broader 5PD work also included scene support logic:
- EMS / Tow / Coroner spawn placement improved to align with lanes and headings
- hospital transport logic hardened so patients are not left behind
- EMS final report behavior improved / added
- AI medic / tow were expected to park smarter near peds / vehicles / callers

## EMS workflow concerns
User had also flagged problems such as:
- EMS workflows feeling awkward
- units exiting vehicles too early
- vehicles rolling away
- EMS lingering after revive / death resolution

## Config simplification direction
The user repeatedly complained that config was too overwhelming.

A specific preference example was:
- user wanted simple config values like:
  - `suspicion.baseChance = 0.02`
instead of nested fallback-heavy initialization patterns.

The general direction was:
- easier config
- cleaner defaults
- less intimidating setup

## Broader stop realism goals
By the end of the week, the desired traffic-stop experience looked like this:
- suspect yields smoothly
- pulls farther right
- stays in the car while being questioned
- does not flee before checks are done
- officer can see realistic record data in MDT
- when finished, suspect drives off without being force-extracted
- if the suspect really does flee or escalate, it happens through an intentional believable branch

## Summary of actual 5PD direction
Az-5PD was being pushed toward a more complete patrol / stop / scene simulation layer, with:
- better roadside vehicle behavior
- better suspect state handling
- more believable callouts
- stronger MDT integration
- simpler config structure
