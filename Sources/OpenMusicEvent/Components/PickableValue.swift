//
//  PickableValue
//  open-music-event
//
//  Created by Woodrow Melling on 9/17/25.
//



import SwiftUI

/**
 A protocol that defines an value that can be selected in a picker view. This should only be used with enum types

 Conforming types must provide a label property, which is `LocalizedStringKey`. The label property describes the title of the pickable value in the picker view. Values conforming to this type also comform to CaseIterable, which allows the declaration order of enum cases to drive the ordering of elements in the picker view.
 */
public protocol PickableValue: CaseIterable, LabeledValue { }

public protocol LabeledValue: Hashable {
    var label: LocalizedStringKey { get }
    var icon: Image? { get }
}

extension LabeledValue {
    public var icon: Image? { nil }
}

struct MenuPicker<Value: PickableValue>: View {
    @Binding var value: Value

    var body: some View {
        Menu {
            ForEach(Array(Value.allCases), id: \.self) { value in
                Button {
                    self.value = value
                } label: {
                    Label {
                        Text(value.label)
                    } icon: {
                        value.icon
                    }
                }
            }
        } label: {
            Label {
                Text(value.label)
            } icon: {
                value.icon
            }
        }
    }
}
