# Az-5PD
A FivePD-style law enforcement resource for Azure Framework.

## What was preserved
- Existing callout system
- Existing MDT / records flow
- Existing F6 police actions
- Existing AI service hooks
- Existing cuff / arrest / citation / drag / seat gameplay

## What was added
- **Simulation / Scene Tools** submenu inside the existing **F6 Police Actions** menu
- Optional **F9** shortcut (`/az5pdsim`) for the same scene tools
- Shift / duty tracking with status changes
- Additive scene / traffic-stop logging that does **not** replace the old workflow
- Generated subject risk snapshots for traffic stops and contacts
- Evidence logging, backup requests, legal-basis notes, officer notes, and auto-built narrative summaries
- Training / review scoring for recently closed incidents
- New persistence tables for sim incidents and officer review totals

- Dispatch board with priority calls, BOLO / APB entries, caller updates, unit suggestions, and panic traffic
- Traffic stop workflow for stop reasons, ID checks, vehicle returns, DUI notes, search basis, plain-view observations, and tow / impound logging
- Scene control flags for safe / unsafe, perimeter, transport pending, and report pending
- Witness statements, officer observations, bag/tag style evidence entries, report preview generation, warrant requests, and case reopen flow
- Weekly scorecards, patrol goals, training scenarios, policy / IA actions, complaints, and commendations
- Overlay status strip with recommended next action and active incident card

## Dependencies
- Az-Framework
- ox_lib
- ox_target
- oxmysql

## New quick use
1. Keep using the resource the same way you already do.
2. Open **F6** and choose **Simulation / Scene Tools** when you want deeper logging / patrol sim.
3. Or target a ped / vehicle with `ox_target` and choose the sim option.
4. Start a shift, open a scene, add cues / probable cause / evidence / notes, and close the scene for a summary + score.

## Notes
- This patch is **additive**. It is meant to keep the current feel of Az-5PD while giving it better law-enforcement simulation depth.
- Fire / EMS gameplay was intentionally not expanded here, since those are handled by your other resources.


MDT bridge note:
- When an external Az-MDT resource from Config.MDT.externalResourceNames is started, the simulation tools now read and write BOLO / APB data from mdt_bolos and dispatch call data from mdt_calls, and mirror action log entries into mdt_action_log when enabled.
- When external Az-MDT is not started, the simulation tools fall back to Az-5PD local persistence tables such as az5pd_sim_bolos and az5pd_sim_dispatch_calls.
