# Accessibility guidelines

Target: **WCAG 2.1 AA** and Apple's Human Interface Guidelines. Every new screen must meet the
checklist below before it is merged.

## Built into the project

| Area | How it is handled |
| --- | --- |
| Text size | All fonts come from `AppFont`, which uses Dynamic Type text styles. Screens scroll, so large text never gets cut off. |
| Colour contrast | Brand, status and secondary-text colours have light, dark and Increase Contrast variants. `ColorContrastTests` fails if any pairing drops below 4.5:1. |
| Colour alone | `StatusBadge` always pairs colour with an icon and text. |
| Touch targets | Buttons are at least 44 × 44 pt (`Layout.minimumTapTarget`). |
| Motion | Animations go through `motionSafeAnimation`, which turns them off when Reduce Motion is on. |
| Orientation | Portrait and landscape are both supported, and content width is capped for readability. |
| Automated checks | UI tests run `performAccessibilityAudit()` at the default and the largest text size. |

## Checklist for every screen

- [ ] Uses `AppFont`/`AppColor` tokens only. No fixed font sizes, no hard-coded colours.
- [ ] Works at the **AX5** text size (check with the "largest text" preview). Nothing is clipped or overlaps, and the screen scrolls.
- [ ] Works in dark mode and with **Increase Contrast** turned on.
- [ ] Every interactive element has a clear VoiceOver label. Add a hint when the result of the action isn't obvious.
- [ ] Decorative images use `.accessibilityHidden(true)`. Related content is combined with `.accessibilityElement(children: .combine)`.
- [ ] Screen titles and section titles have the `.isHeader` trait.
- [ ] Custom controls such as the intensity slider or mode picker expose `accessibilityValue` and support `accessibilityAdjustableAction`.
- [ ] State changes like "Connected" or "Fragrance low" are announced with `AccessibilityNotification.Announcement`.
- [ ] Status is never shown by colour alone.
- [ ] Tested with VoiceOver, Voice Control and Switch Control on a real device.
- [ ] A UI test with `performAccessibilityAudit()` covers the screen.
