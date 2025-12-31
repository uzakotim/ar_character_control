//
//  MarkerAlignmentoverlay.swift
//  ar_character_control
//
//  Created by Timur Uzakov on 31/12/25.
//

import SwiftUI

struct MarkerAlignmentOverlay: View {
    @ObservedObject var state: MarkerAlignmentState

    var body: some View {
        ZStack {
            // Dark background
            Color.black.opacity(0.65)
                .ignoresSafeArea()

            // Alignment square
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    state.isAligned ? Color.green : Color.red,
                    lineWidth: 4
                )
                .frame(width: 180, height: 180)

            VStack {
                Spacer()
                Text(state.isAligned
                     ? "Hold still…"
                     : "Align marker in the square")
                    .foregroundColor(.white)
                    .padding(.bottom, 80)
            }
        }
        .opacity(state.alignmentComplete ? 0 : 1)
        .animation(.easeInOut(duration: 0.25), value: state.alignmentComplete)
    }
}
