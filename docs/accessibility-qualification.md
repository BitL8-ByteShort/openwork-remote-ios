# Native accessibility qualification

October15 source checkpoint on the OpenCode migration branch. This is not a distributed native beta or physical-device acceptance.

The largest accessibility text size is exercised on iPhone17Pro/iOS27, iPhoneSE3/iOS26.5 and iPadPro11/iPadOS 27 Simulators. The SE and iPad final cohorts pass conversation controls, the software keyboard and retained draft after question-sheet dismissal, plus structural accessibility audits. Native startup/offline privacy/back navigation also passes on both device families, including SE. iPad landscape retains the768point reading width.

## Layout corrections

The initial largest-text capture exposed overlapping header/input cards. Accessibility sizes now omit the redundant model caption and static ready-state footer, use concise Approval/Question cards, and retain their full VoiceOver labels and details in the sheets. Icons stay within44point controls. Short available heights, including the SE software keyboard, use a compact header and Input row. The draft stays editable and required inputs stay reachable.

## Automated audit boundaries

The retained routine audit covers element detection, descriptions, hit regions and traits. The full contrast/predictive-clipping runs are recorded separately; this subset does not imply they all passed.

The full audit still reports the welcome heading as potentially clipped at larger text sizes, even during a largest-text run. Its captured heading and the actual scrolled welcome/legal journey were inspected; no words were missing. The Files from this chat label also receives a contrast failure. Its captured interior colors are RGB250/249/246 and32/36/43, measuring14.79:1; the complete label is visible. Removing heading tracking and replacing the file Label did not clear those reports. The heading tracking experiment was reverted. These conflicting automated findings remain documented, rather than described as an all-clear.

## Remaining acceptance

Physical VoiceOver navigation, all retained flows at narrow iPad multitasking widths, hardware-keyboard navigation, dark/reduce-motion cases, long/streaming/offline/file-load performance and final physical iPhone/iPad acceptance remain separate checks. Numeric form keyboard entry also emits an invalid-frame warning in a passing iOS27 case. A separate iOS26.5 toolbar warning occurred in an earlier passing SE cohort; the final SE and iPad cohorts did not report it. Neither is claimed fixed without a causal result.

## Narrow-window checkpoint

The native iPadOS 27 Simulator window was resized with the system corner control from 834 × 1210 to about 374 × 911 points. The captured whole-device image shows an actual app window on the iPad desktop. The composer, Add control measuring at least 44 points and Settings dismissal pass in that window.

Three maximum-text conversation/keyboard/structural-audit cases pass at that narrow width. The first attempt used application-wide swipes that did not move the chat list; explicitly targeting its CollectionView passes the same assertions. Window-aware gestures are used in the feature cohort: all 31 remaining native cases have passing results across the main run and a focused repair of its test-window restoration. The latter now reaches the screen edge and waits for the original width, without reducing the assertion. Together with the four accessibility cases, the 35-case iPad cohort is green across recorded batches. This is synthetic DEBUG UI evidence; physical VoiceOver, hardware-keyboard and complete device acceptance remain separate.

## iPad window controls

A normal Release inspection found that iPadOS window controls covered the custom history button in a floating window. A visible-center coordinate test reproduced the failure; semantic element taps had missed it. iPad now uses system toolbar placements to reserve that space. Narrow iPad windows use the compact model/settings icon with the full accessible project/model value; wider windows show a bounded title. The iPhone header is retained. [Apple's window guidance](https://developer.apple.com/videos/play/wwdc2025/208/) explains the automatic toolbar adjustment.

The repaired visible-center history touch, Settings dismissal, landscape, large-text keyboard and structural-audit checks are recorded separately from the earlier 35-case dispositions. Physical iPad acceptance remains open.
