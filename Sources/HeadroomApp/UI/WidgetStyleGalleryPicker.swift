import SwiftUI
import HeadroomCore

/// R16/KTD13 (2026-10-02 widget-styles plan): which of the four widget styles the Widgets &
/// iPhone preview draws. Preview only: each widget's style is chosen on the widget itself, in
/// Edit Widget.
///
/// CA-S7 (revisits L9P's thumbnail gallery): a segmented control labelled "Preview", not a
/// row of swatches in `selectionChrome`. The gallery wore the same selection ring as settings
/// that persist while it set nothing, a control that looked like a preference and wasn't.
/// A segmented control is the native "views of the same thing" idiom, and its label says
/// what choosing does. It holds only a binding to view state on `SettingsView`; nothing here
/// reaches the store or `Preferences`.
struct WidgetStylePreviewPicker: View {
    @Binding var selection: WidgetLayoutStyle

    static let label = "Preview"

    var body: some View {
        ResponsiveControlRow(label: Self.label) {
            Picker(Self.label, selection: $selection) {
                ForEach(WidgetLayoutStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .accessibilityLabel("Widget style preview")
        }
    }
}
