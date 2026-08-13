//
//  SkyScope_WidgetBundle.swift
//  SkyScope Widget
//
//  Created by Dennis Kiefer on 28.05.26.
//

import WidgetKit
import SwiftUI

@main
struct SkyScope_WidgetBundle: WidgetBundle {
    var body: some Widget {
        SkyScope_Widget()
        SkyScope_WidgetControl()
        SkyScope_WidgetLiveActivity()
    }
}
