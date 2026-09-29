# Mouselook launch plan

Date: 2026-09-29

Status: proposed plan; pricing and demand still need validation.

## Objective

Aim for a small paid launch in about four weeks, with free source code and a **$9.99 one-time App Store purchase**. Timing is a target; compatibility testing and App Review determine the actual release date.

The first milestone is **10 people independently completing a useful task on their own iPads**.

## 1. Define the launch promise — day 1

Agree on this scope:

- iPad, with a mouse or compatible trackpad and keyboard.
- Figma editing and GeForce NOW mouse control.
- One purchase includes both.
- Additional creative tools enter the launch only after testing.

Draft positioning:

> Use desktop mouse controls in web apps on your iPad.

Publish specific supported workflows underneath it. Avoid promising a complete laptop replacement.

## 2. Prove the workflows — days 2–5

Test the same tasks in Safari and Mouselook, recording the device, iPadOS version, peripherals, result, and limitations.

| Service | Task that must succeed |
| --- | --- |
| Figma | Sign in, open a representative file, edit text, scrub values, pan/zoom, undo, export, and reopen with changes saved. |
| GeForce NOW | Sign in, launch a game, aim continuously, use keyboard shortcuts, release/reacquire the mouse, and recover after an app switch. |
| Additional creative candidate | Complete a useful editing task and demonstrate a meaningful improvement over Safari. |

Test **Penpot, Spline, and Framer** first for additional creative coverage. Their documentation alone does not establish whether Mouselook improves their editors. Give each a short investigation; retain only promising candidates. Game previews in PlayCanvas can wait unless beta users request them.

A new service card is cheap. A reliable support promise is the expensive part.

## 3. Recruit a focused beta — week 2

Target **20 testers: roughly 12 creatives and 8 gamers**. Include former Figurative users, but also people unfamiliar with browser workarounds.

Recruit through relevant communities where permitted and personal contacts. Show a short real-device demonstration, disclose that you are the developer, and state the intended **$9.99 one-time price**.

Ask each person to use their own file or game, then answer:

- What did you finish?
- What prevented you from finishing?
- Did you use Mouselook again without a reminder?
- What would you use instead?

Offer free TestFlight access without requiring a review or testimonial.

## 4. Prepare distribution alongside the beta — weeks 2–3

Resolve the existing review questions around background audio, the native input bridge, and promoted third-party services. Explain the implementation honestly in review notes, with a demonstration and usable reviewer access.

Prepare the public repository:

- Choose a license.
- Confirm rights to included assets and dependencies.
- Check for credentials before publication.
- Update build instructions.
- Document limitations and support expectations.

Keep one codebase. For the initial paid-upfront release, there is no need to build subscriptions, accounts, or a Pro paywall.

## 5. Build the minimum sales package — week 3

Prepare:

- One landing page with price, requirements, compatibility, support, and source links.
- Two short videos: a useful Figma edit and mouse-controlled gameplay.
- App Store screenshots showing outcomes before settings.
- A clear statement that service subscriptions are separate.
- A concise comparison with Safari and CloudGear using verified differences.

Use separate creative and gaming messages that lead to the same app. Lead the main page with the strongest result from the beta.

## 6. Make the launch decision — week 4

Use these as **internal targets, not industry benchmarks**:

- At least **16 of 20** testers complete their main task without developer intervention.
- At least **8** return within a week without prompting.
- No unresolved failures involving lost work, stuck input, or a broken primary workflow.
- Several testers explicitly want to buy at the stated price.

If those signals are weak, fix the most common obstacle and repeat the test before expanding the service list.

Once approved, launch to the beta audience and relevant communities. Measure actual purchases, refunds, repeat use where observable, and support time. Consider paid promotion only after that provides evidence of demand.

## Immediate next actions

- [ ] Settle the launch promise.
- [ ] Create the compatibility checklist.
- [ ] Recruit the first five testers.

These results should guide the next product decisions before adding speculative features.
