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

extension Color {
    #if os(Android)
//    static let systemBackground = Color(colorImpl: {
//        MaterialTheme.colorScheme.surface
//    })
    static let systemBackground = SwiftUI.Color.brown
    #else
    static let systemBackground = Color(.systemBackground)
    #endif
}
