#!/usr/bin/env swift
//
//  generate-app-preview.swift
//  TalkType — Mac App Store Preview Video (1920x1080, 30fps, 18.0s, H.264 High@4.0 + 48kHz 256kbps AAC)
//

import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import SwiftUI

let W = 1920
let H = 1080
let FPS: Int32 = 30
let DURATION_SEC = 18.0
let TOTAL_FRAMES = Int(DURATION_SEC * Double(FPS)) // 540 frames

let cPaperTop  = Color(red: 1.000, green: 0.996, blue: 0.969)
let cPaperMid  = Color(red: 1.000, green: 0.965, blue: 0.902)
let cPaperBot  = Color(red: 0.992, green: 0.933, blue: 0.855)
let cPopoverBg = Color(red: 0.984, green: 0.945, blue: 0.894)
let cCardInner = Color(red: 0.992, green: 0.949, blue: 0.878)
let cInk       = Color(red: 0.118, green: 0.090, blue: 0.078)
let cInkSoft   = Color(red: 0.337, green: 0.290, blue: 0.259)
let cInkMute   = Color(red: 0.494, green: 0.439, blue: 0.400)
let cPink      = Color(red: 1.000, green: 0.510, blue: 0.792)
let cPinkDeep  = Color(red: 0.722, green: 0.267, blue: 0.533)
let cPeach     = Color(red: 1.000, green: 0.690, blue: 0.376)

let ghostNSImage: NSImage = {
    guard let img = NSImage(contentsOfFile: "Assets/ghost.png") else {
        fputs("Missing Assets/ghost.png\n", stderr)
        exit(1)
    }
    return img
}()

func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)
}

let fullWords = [
    "Morning", "team,", "ship", "the", "macOS", "release", "notes",
    "before", "noon,", "keep", "the", "onboarding", "calm,", "and",
    "bring", "the", "good", "espresso", "beans."
]

struct TalkTypePreviewFrame: View {
    let t: Double

    private var isHistoryTab: Bool { t >= 11.6 }
    private var isRecording: Bool { t >= 0.9 && t < 6.3 }
    private var isCopied: Bool { t >= 6.3 && t < 11.6 }

    private var streamedText: String {
        if t < 0.9 { return "" }
        if t >= 6.1 { return fullWords.joined(separator: " ") }
        let frac = (t - 0.9) / 5.2
        let count = max(1, min(fullWords.count, Int(Double(fullWords.count) * frac) + 1))
        return fullWords.prefix(count).joined(separator: " ")
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [cPaperTop, cPaperMid, cPaperBot], startPoint: .top, endPoint: .bottom)

            RadialGradient(
                colors: [cPink.opacity(0.22), cPeach.opacity(0.14), .clear],
                center: .init(x: 0.64, y: 0.48),
                startRadius: 20,
                endRadius: 560
            )

            VStack(spacing: 0) {
                // macOS Menu Bar
                HStack(spacing: 20) {
                    Image(systemName: "apple.logo").font(.system(size: 15, weight: .semibold))
                    Text("Notes").font(.system(size: 14.5, weight: .bold))
                    Text("File").font(.system(size: 14.5)).foregroundStyle(cInkSoft)
                    Text("Edit").font(.system(size: 14.5)).foregroundStyle(cInkSoft)
                    Text("Format").font(.system(size: 14.5)).foregroundStyle(cInkSoft)
                    Text("View").font(.system(size: 14.5)).foregroundStyle(cInkSoft)
                    Spacer()
                    HStack(spacing: 16) {
                        HStack(spacing: 6) {
                            Image(nsImage: ghostNSImage)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 20, height: 20)
                            if isRecording {
                                Circle().fill(cPinkDeep).frame(width: 7, height: 7)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(cPink.opacity(isRecording ? 0.28 : 0.16)))

                        Image(systemName: "wifi").font(.system(size: 14))
                        Text("Tue 9:41 AM").font(.system(size: 14, weight: .medium))
                    }
                }
                .foregroundStyle(cInk)
                .padding(.horizontal, 28)
                .frame(height: 38)
                .background(cPaperTop.opacity(0.92))
                .overlay(alignment: .bottom) { Rectangle().fill(cInk.opacity(0.10)).frame(height: 1) }

                // Split Desktop Stage: Left Notes Editor + Right Open TalkType Popover
                HStack(alignment: .top, spacing: 56) {
                    // Left: Clean macOS Notes window receiving the dictated take
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 8) {
                            Circle().fill(cInk.opacity(0.22)).frame(width: 11, height: 11)
                            Circle().fill(cInk.opacity(0.12)).frame(width: 11, height: 11)
                            Circle().fill(cInk.opacity(0.12)).frame(width: 11, height: 11)
                            Spacer()
                            Text("Release Checklist — Notes")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(cInkMute)
                            Spacer()
                        }

                        Rectangle().fill(cInk.opacity(0.08)).frame(height: 1)

                        Text("Studio Standup")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                            .foregroundStyle(cInk)

                        if t >= 8.2 {
                            let pasteAlpha = smoothstep(8.2, 8.7, t)
                            Text(fullWords.joined(separator: " "))
                                .font(.system(size: 21, weight: .medium))
                                .lineSpacing(6)
                                .foregroundStyle(cInk)
                                .opacity(pasteAlpha)
                        } else {
                            HStack(spacing: 2) {
                                Rectangle()
                                    .fill(cPinkDeep)
                                    .frame(width: 2.5, height: 24)
                                    .opacity(0.45 + 0.55 * abs(sin(t * .pi * 2)))
                                Text("Hold ⌃⌥ Space anywhere to dictate…")
                                    .font(.system(size: 19, weight: .regular))
                                    .foregroundStyle(cInkMute.opacity(0.75))
                            }
                        }

                        Spacer()

                        // Bottom tactile shortcut indicator
                        HStack(spacing: 10) {
                            keyCap("⌃ Control", active: isRecording)
                            keyCap("⌥ Option", active: isRecording)
                            keyCap("Space", active: isRecording)
                            Text(isRecording ? "Listening on-device…" : (t >= 8.2 ? "⌘V pasted cleanly" : "Ready in every Mac app"))
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(isRecording ? cPinkDeep : cInkSoft)
                                .padding(.leading, 6)
                        }
                    }
                    .padding(28)
                    .frame(width: 820, height: 620)
                    .background(cPaperTop)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(cInk.opacity(0.14), lineWidth: 1.5))
                    .shadow(color: cInk.opacity(0.10), radius: 28, x: 0, y: 14)
                    .padding(.top, 96)

                    // Right: Real TalkType Menu Bar Popover + Floating Copied HUD
                    VStack(spacing: 22) {
                        popoverCard
                        if t >= 6.4 && t < 11.4 {
                            let hudIn = smoothstep(6.4, 6.85, t)
                            let hudOut = 1.0 - smoothstep(10.9, 11.35, t)
                            copiedHUD
                                .opacity(hudIn * hudOut)
                                .offset(y: CGFloat((1.0 - hudIn) * 12.0))
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 84)

                Spacer()
            }
        }
        .frame(width: CGFloat(W), height: CGFloat(H))
    }

    private func keyCap(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 14, weight: .bold, design: .monospaced))
            .foregroundStyle(active ? cPaperTop : cInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(active ? cPinkDeep : cPopoverBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(cInk.opacity(0.18), lineWidth: 1.5)
            )
    }

    private var popoverCard: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 0) {
                    Text("Talk").foregroundStyle(cInk)
                    Text("Type").foregroundStyle(LinearGradient(colors: [cPinkDeep, cPeach], startPoint: .leading, endPoint: .trailing))
                }
                .font(.system(size: 26, weight: .black, design: .rounded))

                Spacer()

                HStack(spacing: 4) {
                    tabChip("Live", selected: !isHistoryTab)
                    tabChip("History", selected: isHistoryTab)
                    tabChip("About", selected: false)
                }
                .padding(4)
                .background(Capsule().fill(cInk.opacity(0.06)))
            }

            if !isHistoryTab {
                // Transcript paper box
                VStack(alignment: .leading, spacing: 12) {
                    Text(streamedText.isEmpty ? "Speak naturally — words appear here…" : streamedText)
                        .font(.system(size: 16.5, weight: .medium, design: .monospaced))
                        .lineSpacing(5)
                        .foregroundStyle(streamedText.isEmpty ? cInkMute : cInk)
                        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)

                    HStack {
                        Text(streamedText.isEmpty ? "0 words" : "\(streamedText.split(separator: " ").count) words")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(cInkMute)
                        Spacer()
                        if isCopied {
                            Text("Copied!")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(cPinkDeep)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(cPink.opacity(0.24)))
                        }
                    }
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(cCardInner))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(cInk.opacity(0.14), lineWidth: 1.2))

                // Ghost + Waveform stage
                VStack(spacing: 14) {
                    ZStack {
                        if isRecording {
                            Circle()
                                .fill(RadialGradient(colors: [cPink.opacity(0.38), cPeach.opacity(0.14), .clear], center: .center, startRadius: 10, endRadius: 96))
                                .frame(width: 190, height: 190)
                                .scaleEffect(1.0 + 0.08 * CGFloat(sin(t * .pi * 4)))
                        }

                        HStack(spacing: 22) {
                            if isRecording {
                                waveformStack(seedOffset: 0)
                            }
                            Image(nsImage: ghostNSImage)
                                .resizable()
                                .interpolation(.high)
                                .frame(width: 138, height: 138)
                                .offset(y: CGFloat(sin(t * .pi * (isRecording ? 3.2 : 1.2)) * (isRecording ? 5.0 : 2.5)))
                            if isRecording {
                                waveformStack(seedOffset: 4)
                            }
                        }
                    }
                    .frame(height: 168)

                    Text(isRecording ? "Listening… release to copy" : "Click ghost or hold ⌃⌥ Space")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(isRecording ? cPinkDeep : cInkSoft)
                }

                // Footer pills
                HStack {
                    HStack(spacing: 8) {
                        Text("EN").font(.system(size: 12.5, weight: .bold, design: .rounded)).padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(cPaperTop))
                        Text("ES").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(cInkMute).padding(.trailing, 8)
                    }
                    .padding(3)
                    .background(Capsule().fill(cInk.opacity(0.07)))

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(cPinkDeep)
                        Text("Mac Offline · EN").font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(cInk)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(cPaperTop).overlay(Capsule().stroke(cInk.opacity(0.14), lineWidth: 1)))
                }
            } else {
                // History & Vocabulary View (11.6s - 18.0s)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("14 takes")
                            .font(.system(size: 13.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(cInkSoft)
                        Spacer()
                        Text("↓ Newest")
                            .font(.system(size: 12.5, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(cPaperTop).overlay(Capsule().stroke(cInk.opacity(0.14), lineWidth: 1)))
                    }

                    historyRow(time: "Today, 9:41 AM", badge: "Copied!", text: "Morning team, ship the macOS release notes before noon, keep the onboarding calm.")
                    historyRow(time: "Today, 9:18 AM", badge: "Copy", text: "El resumen del taller ya está listo para enviar al equipo de diseño.")
                    historyRow(time: "Custom Vocabulary", badge: "Active", text: "doctype → TalkType  ·  pibulus, Melbourne, SwiftUI")

                    HStack {
                        Text("Clear History").font(.system(size: 13, weight: .semibold)).foregroundStyle(cInkMute)
                        Spacer()
                        Text("Export .txt").font(.system(size: 13, weight: .bold)).foregroundStyle(cPinkDeep)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(24)
        .frame(width: 470)
        .background(cPopoverBg)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(cInk.opacity(0.18), lineWidth: 1.5))
        .shadow(color: cInk.opacity(0.14), radius: 32, x: 0, y: 16)
    }

    private func waveformStack(seedOffset: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { idx in
                let phase = t * 8.5 + Double(idx + seedOffset) * 1.15
                let h = 16.0 + 34.0 * abs(sin(phase))
                Capsule()
                    .fill(LinearGradient(colors: [cPinkDeep, cPeach], startPoint: .bottom, endPoint: .top))
                    .frame(width: 6, height: CGFloat(h))
            }
        }
    }

    private func tabChip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .foregroundStyle(selected ? cInk : cInkSoft)
            .padding(.horizontal, 13)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? cPaperTop : .clear))
    }

    private func historyRow(time: String, badge: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(time).font(.system(size: 12.5, weight: .medium)).monospacedDigit().foregroundStyle(cInkMute)
                Spacer()
                Text(badge)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(cPinkDeep)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(cPink.opacity(0.22)))
            }
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .lineSpacing(3)
                .foregroundStyle(cInk)
                .lineLimit(2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(cCardInner))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(cInk.opacity(0.12), lineWidth: 1))
    }

    private var copiedHUD: some View {
        HStack(spacing: 14) {
            Image(nsImage: ghostNSImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
            Text("Copied to clipboard — Press ⌘V to paste!")
                .font(.system(size: 17.5, weight: .heavy, design: .rounded))
                .foregroundStyle(cInk)
            Spacer()
            ZStack {
                Circle().fill(cPinkDeep).frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(cPaperTop)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(width: 470)
        .background(Capsule().fill(cPaperTop))
        .overlay(Capsule().stroke(cPink, lineWidth: 3))
        .shadow(color: cPinkDeep.opacity(0.22), radius: 18, x: 0, y: 8)
    }
}

@MainActor
func renderVideo() throws {
    let outDir = URL(fileURLWithPath: "screenshots/app-preview")
    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    let silentMov = outDir.appendingPathComponent("raw-silent.mov")
    let finalMov  = outDir.appendingPathComponent("TalkType-AppPreview-1920x1080.mov")
    try? FileManager.default.removeItem(at: silentMov)
    try? FileManager.default.removeItem(at: finalMov)

    let writer = try AVAssetWriter(outputURL: silentMov, fileType: .mov)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: W,
        AVVideoHeightKey: H,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 10_500_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 30
        ]
    ]
    let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    writerInput.expectsMediaDataInRealTime = false

    let attrs: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
        kCVPixelBufferWidthKey as String: W,
        kCVPixelBufferHeightKey as String: H
    ]
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: writerInput, sourcePixelBufferAttributes: attrs)
    writer.add(writerInput)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    for frame in 0..<TOTAL_FRAMES {
        autoreleasepool {
            while !writerInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.002)
            }
            let t = Double(frame) / Double(FPS)
            let renderer = ImageRenderer(content: TalkTypePreviewFrame(t: t))
            renderer.scale = 1.0
            renderer.isOpaque = true

            guard let cgImg = renderer.cgImage,
                  let pool = adaptor.pixelBufferPool else {
                fputs("Failed frame \(frame)\n", stderr)
                exit(1)
            }

            var pbOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pbOut)
            guard let pb = pbOut else { exit(1) }

            CVPixelBufferLockBaseAddress(pb, [])
            if let ctx = CGContext(
                data: CVPixelBufferGetBaseAddress(pb),
                width: W,
                height: H,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) {
                ctx.draw(cgImg, in: CGRect(x: 0, y: 0, width: W, height: H))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])

            let pts = CMTime(value: CMTimeValue(frame), timescale: FPS)
            adaptor.append(pb, withPresentationTime: pts)
        }
    }

    writerInput.markAsFinished()
    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting { sem.signal() }
    sem.wait()

    // Synthesize a warm, subtle stereo Rhodes-pad + soft chime cue at 0.9s (start) & 6.3s (copied!) via ffmpeg aevalsrc
    let exprL = "0.055*sin(2*PI*261.63*t)*exp(-0.04*t)+0.045*sin(2*PI*329.63*t)+0.035*sin(2*PI*392.00*t)+0.025*sin(2*PI*493.88*t)+if(gte(t,0.9),0.14*sin(2*PI*523.25*(t-0.9))*exp(-7*(t-0.9)),0)+if(gte(t,6.3),0.16*sin(2*PI*659.25*(t-6.3))*exp(-6*(t-6.3)),0)+if(gte(t,6.42),0.16*sin(2*PI*783.99*(t-6.42))*exp(-5*(t-6.42)),0)"
    let exprR = "0.055*sin(2*PI*262.0*t)*exp(-0.04*t)+0.045*sin(2*PI*330.0*t)+0.035*sin(2*PI*392.4*t)+0.025*sin(2*PI*494.2*t)+if(gte(t,0.9),0.14*sin(2*PI*523.25*(t-0.9))*exp(-7*(t-0.9)),0)+if(gte(t,6.3),0.16*sin(2*PI*659.25*(t-6.3))*exp(-6*(t-6.3)),0)+if(gte(t,6.42),0.16*sin(2*PI*783.99*(t-6.42))*exp(-5*(t-6.42)),0)"

    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    proc.arguments = [
        "-nostdin",
        "-loglevel", "error",
        "-y",
        "-i", silentMov.path,
        "-f", "lavfi",
        "-i", "aevalsrc=exprs='\(exprL)|\(exprR)':s=48000:d=18",
        "-filter_complex",
        "[1:a]afade=t=in:st=0:d=1.0,afade=t=out:st=16.2:d=1.8,aformat=sample_fmts=fltp:channel_layouts=stereo[aout]",
        "-map", "0:v:0",
        "-map", "[aout]",
        "-c:v", "libx264",
        "-profile:v", "high",
        "-level:v", "4.0",
        "-pix_fmt", "yuv420p",
        "-r", "30",
        "-b:v", "10M",
        "-maxrate", "12M",
        "-bufsize", "20M",
        "-c:a", "aac",
        "-b:a", "256k",
        "-ar", "48000",
        "-ac", "2",
        "-t", "18",
        "-movflags", "+faststart",
        finalMov.path
    ]
    try proc.run()
    proc.waitUntilExit()
    try? FileManager.default.removeItem(at: silentMov)
    guard proc.terminationStatus == 0 else {
        fputs("ffmpeg failed with code \(proc.terminationStatus)\n", stderr)
        exit(1)
    }
    print("✅ Wrote \(finalMov.path)")
}

MainActor.assumeIsolated {
    try! renderVideo()
}
