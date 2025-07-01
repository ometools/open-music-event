//
//  SkipUI+.swift
//  event-viewer
//
//  Created by Woodrow Melling on 2/21/25.
//

import  SwiftUI; import SkipFuse

#if SKIP
import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.material.ContentAlpha
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.surfaceColorAtElevation
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
#endif
//
//extension Color {
//#if SKIP
//    static let systemBackground = Color(colorImpl: {
//        MaterialTheme.colorScheme.surface
//    })
//#elseif canImport(UIKit)
//    static let systemBackground: Color = Color.systemBackground
//#else
//    #error("Unsupported platform")
//#endif
//}
