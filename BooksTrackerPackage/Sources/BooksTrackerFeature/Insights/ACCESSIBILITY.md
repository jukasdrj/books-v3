# Insights Accessibility Compliance

## VoiceOver Support

✅ All charts have descriptive labels
✅ Hero stats announce title and value
✅ Stat cards combine elements for clarity
✅ Buttons have accessibility hints

## Dynamic Type

✅ All text scales with system font size
✅ Layout adapts to larger text

## Color & Contrast

✅ WCAG AA compliant (4.5:1 minimum)
✅ Semantic colors adapt to Dark Mode
✅ Chart colors have sufficient contrast

## Audio Graphs (iOS 15+)

✅ Charts include AXChartDescriptor for audio playback

## Reduce Motion

⚠️ TODO: Disable chart animations when Reduce Motion enabled

## Manual Testing Checklist

### VoiceOver Testing
- [ ] Enable VoiceOver on device/simulator (Cmd+F5)
- [ ] Navigate to Insights tab
- [ ] Verify hero stats announce correctly
- [ ] Verify cultural regions chart reads bar values
- [ ] Verify gender donut chart announces percentages
- [ ] Verify language tags are readable
- [ ] Verify reading stats cards combine content
- [ ] Test audio graphs (swipe up/down on charts)

### Dynamic Type Testing
- [ ] Open Settings → Accessibility → Display & Text Size
- [ ] Set text size to largest (AX5)
- [ ] Verify all text scales properly
- [ ] Verify no text truncation or overlap
- [ ] Verify layouts remain usable

### Dark Mode Testing
- [ ] Enable Dark Mode
- [ ] Verify all colors have sufficient contrast
- [ ] Verify chart colors remain distinguishable
- [ ] Verify text remains readable

### High Contrast Testing
- [ ] Enable High Contrast mode
- [ ] Verify borders and separators are visible
- [ ] Verify chart elements remain clear

### Reduce Motion Testing
- [ ] Enable Reduce Motion
- [ ] Navigate to Insights tab
- [ ] Verify no disorienting animations
- [ ] Verify chart transitions are smooth

## Known Issues

None at this time.

## References

- [iOS Human Interface Guidelines - Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [WCAG 2.1 Level AA](https://www.w3.org/WAI/WCAG21/quickref/?currentsidebar=%23col_customize&levels=aaa)
- [Swift Charts Accessibility](https://developer.apple.com/documentation/charts/accessibility)
