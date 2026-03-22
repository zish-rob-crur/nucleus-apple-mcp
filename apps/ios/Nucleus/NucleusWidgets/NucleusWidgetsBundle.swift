import SwiftUI
import WidgetKit

@main
struct NucleusWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NucleusSyncStatusWidget()
        NucleusSyncLiveActivityWidget()
    }
}
